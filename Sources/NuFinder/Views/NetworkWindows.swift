import AppKit
import NetFS
import SwiftUI

/// Fork: «Red», pensado por lo que quiere hacer la persona, no por protocolo:
///  · Conectarse a un servidor… → ventana con «Configuración rápida» (dirección, usuario, contraseña)
///    y «Configuración avanzada» (tipo, puerto, anónimo, carpeta, nombre).
///  · Compartir una carpeta… → ventana con la carpeta, un interruptor y lo que hay que escribir
///    en el otro equipo; en avanzada, permisos, puerto, usuario y SMB de macOS.
/// Todo se guarda en `~/.explorer/red.json` (`NetworkStore`); las contraseñas, en el Llavero.
enum NetworkSettings {
    static let showsMenuKey = "menu.showsNetwork"
}

// MARK: Conectar

enum NetworkConnector {
    /// SMB: monta la carpeta compartida (macOS pide lo que falte) y la abre en una pestaña.
    /// FTP: abre el explorador FTP de Explorer ya conectado.
    @MainActor
    static func connect(_ server: SavedServer, password: String, remember: Bool,
                        store: NetworkStore = .shared) async -> String? {
        switch server.kind {
        case .ftp:
            let model = FTPClientModel.shared
            model.address = server.ftpAddress
            model.password = password
            if let error = await model.connect(startPath: server.path.isEmpty ? "/" : "/" + server.path) { return error }
            FTPClientWindow.open()
        case .smb:
            do {
                let mounts = try await SMBMount.mount(server, password: password)
                if let folder = mounts.first {
                    if let browser = KeyWindowFocus.shared.windowBrowser { browser.newTab(at: folder) } else { WindowService.open(at: folder) }
                }
            } catch is CancellationError {
                return nil
            } catch { return error.localizedDescription }
        }
        store.remember(server)
        FTPSecrets.setPassword(remember && !server.anonymous ? password : nil, for: server.id)
        return nil
    }
}

enum SMBMount {
    struct Failure: LocalizedError {
        let status: Int32
        var errorDescription: String? {
            status > 0 ? String(cString: strerror(status))
                : (SecCopyErrorMessageString(OSStatus(status), nil) as String?) ?? String(localized: "The server returned error \(status).")
        }
    }

    static func url(for server: SavedServer) -> URL? {
        var components = URLComponents()
        components.scheme = "smb"
        components.host = server.host
        if server.port != 445 { components.port = server.port }
        components.path = server.path.isEmpty ? "" : "/" + server.path
        return components.url
    }

    static func mount(_ server: SavedServer, password: String) async throws -> [URL] {
        guard let url = url(for: server) else { throw Failure(status: EINVAL) }
        let user = server.anonymous || server.user.isEmpty ? nil : server.user
        let pass = server.anonymous || password.isEmpty ? nil : password
        let guest = server.anonymous
        return try await Task.detached(priority: .userInitiated) {
            var mounts: Unmanaged<CFArray>?
            let open = NSMutableDictionary(object: "AllowUI", forKey: "UIOption" as NSString) // macOS pide lo que falte
            if guest { open["Guest"] = true }
            let status = NetFSMountURLSync(url as CFURL, nil, user as CFString?, pass as CFString?, open, nil, &mounts)
            if status == userCanceledErr { throw CancellationError() }
            guard status == 0 else { throw Failure(status: status) }
            return (mounts?.takeRetainedValue() as? [String] ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        }.value
    }
}

/// Ventana «Conectarse a un servidor».
struct ConnectView: View {
    @ObservedObject private var store = NetworkStore.shared
    @AppStorage("network.connect.advanced") private var advanced = false
    @State private var address = ""
    @State private var user = ""
    @State private var password = ""
    @State private var kind: SavedServer.Kind? = nil // nil = automático
    @State private var port = ""
    @State private var anonymous = false
    @State private var remember = true
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    /// Servidor que resulta de lo escrito (lo que se va a usar al pulsar Conectar).
    var server: SavedServer? {
        guard var server = SavedServer.parse(address, kind: kind) else { return nil }
        if !user.isEmpty { server.user = user }
        if let custom = Int(port), custom > 0 { server.port = custom }
        server.anonymous = anonymous
        server.name = name
        return server
    }

    var body: some View {
        VStack(spacing: 0) {
            ModePicker(advanced: $advanced)
            Form {
                Section {
                    TextField(text: $address, prompt: Text(verbatim: "192.168.1.20/Fotos")) { Text("Server address") }
                        .onSubmit { connect() }
                    if let server {
                        Label(server.kind == .ftp ? "Will connect with FTP to \(server.host)" : "Will connect to the shared folder of \(server.host) (Windows, NAS, Mac)",
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: String(localized: "Examples: 192.168.1.20 · nas.local/Fotos · \\\\PC\\Documentos · ftp://mi-web.com")) // verbatim: sin Markdown, que se comía una «\\»
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !anonymous {
                        TextField("User", text: $user)
                        SecureField("Password", text: $password)
                    }
                } header: { Text("Which computer do you want to open?") }
                if advanced {
                    Section("Advanced") {
                        Picker("Type", selection: $kind) {
                            Text("Automatic").tag(SavedServer.Kind?.none)
                            Text("Windows, NAS or Mac (SMB)").tag(SavedServer.Kind?.some(.smb))
                            Text("FTP").tag(SavedServer.Kind?.some(.ftp))
                        }
                        TextField("Port", text: $port, prompt: Text(verbatim: String(server.map { $0.port } ?? 445)))
                        Toggle("Connect without user (anonymous / guest)", isOn: $anonymous)
                        Toggle("Remember password in the Keychain", isOn: $remember)
                        TextField("Name in the list", text: $name, prompt: Text("Optional, e.g. “NAS at home”"))
                    }
                }
                if !store.config.servers.isEmpty {
                    Section("Recent") {
                        ForEach(store.config.servers) { saved in
                            HStack {
                                Image(systemName: saved.kind == .ftp ? "network" : "externaldrive.connected.to.line.below")
                                VStack(alignment: .leading) {
                                    Text(saved.title)
                                    Text(verbatim: "\(saved.kind.rawValue)://\(saved.host)\(saved.path.isEmpty ? "" : "/" + saved.path)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Connect") { fill(saved); connect() }
                                Button { store.forget(saved) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).help(Text("Forget"))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { fill(saved) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(server == nil || busy)
            }
            .padding(14)
        }
        .frame(width: 520, height: advanced ? 600 : 470)
    }

    private func fill(_ saved: SavedServer) {
        address = saved.host + (saved.path.isEmpty ? "" : "/" + saved.path)
        kind = saved.kind
        user = saved.user
        anonymous = saved.anonymous
        name = saved.name
        port = saved.port == SavedServer.defaultPort(saved.kind) ? "" : String(saved.port)
        password = FTPSecrets.password(for: saved.id) ?? ""
    }

    private func connect() {
        guard let server, !busy else { return }
        busy = true; error = nil
        Task {
            error = await NetworkConnector.connect(server, password: password, remember: remember)
            busy = false
            if error == nil { NetworkWindow.close(.connect) }
        }
    }
}

// MARK: Compartir

/// Ventana «Compartir una carpeta».
struct ShareView: View {
    @ObservedObject private var store = NetworkStore.shared
    @ObservedObject private var ftp = FTPServerController.shared
    @ObservedObject private var smb = SMBServerController.shared
    @AppStorage("network.share.advanced") private var advanced = false
    @State private var password = FTPSecrets.password(for: FTPSettings.serverPasswordAccount) ?? ""
    @State private var copied = false

    private var share: Binding<NetworkConfig.Share> { $store.config.share }
    private var folder: String { store.config.share.folderPath }

    var body: some View {
        VStack(spacing: 0) {
            ModePicker(advanced: $advanced)
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").font(.largeTitle).foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text((folder as NSString).lastPathComponent).font(.headline)
                            Text(folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Change…") { chooseFolder() }
                    }
                    Toggle(isOn: share.enabled) {
                        Text(store.config.share.enabled ? "Shared" : "Not shared").font(.headline)
                        Text(store.config.share.enabled ? "Other devices on your network can open this folder." : "Turn on to let other devices open this folder.")
                    }
                    .toggleStyle(.switch)
                    if case .failed(let message) = ftp.state, store.config.share.enabled {
                        DisabledReason("Couldn’t share: \(message). Change the port in Advanced.")
                    }
                } header: { Text("Which folder do you want to share?") }

                if ftp.isRunning, let address = ftp.addresses.first {
                    Section("How to open it from another device") {
                        AccessLine(label: "Address", value: address)
                        if store.config.share.anonymous {
                            Text("No user or password needed.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            AccessLine(label: "User", value: store.config.share.user)
                            AccessLine(label: "Password", value: password.isEmpty ? String(localized: "(set one below)") : String(repeating: "•", count: password.count))
                        }
                        Text("Windows: paste the address in File Explorer. Phone: any “FTP” file app. Mac: Finder → Go → Connect to Server.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(copied ? "Copied" : "Copy Instructions") { copyInstructions(address) }
                    }
                }

                Section("Who can enter") {
                    Toggle("Anyone, without password", isOn: share.anonymous)
                    if !store.config.share.anonymous {
                        TextField("User", text: share.user)
                        SecureField("Password", text: $password)
                            .onChange(of: password) { _, value in
                                FTPSecrets.setPassword(value, for: FTPSettings.serverPasswordAccount)
                                FTPServerController.shared.passwordChanged()
                            }
                        if password.isEmpty { DisabledReason("Set a password, otherwise nobody can enter.") }
                    }
                    Toggle("Others can only view and download (not change or delete)", isOn: share.readOnly)
                }

                if advanced {
                    Section("Advanced") {
                        TextField("Port", value: share.port, format: .number.grouping(.never))
                        Toggle("Only this Mac (invisible to the network)", isOn: share.localOnly)
                        Text("Shared with FTP, built into Explorer. FTP doesn’t encrypt: use it only on networks you trust.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Also share with Windows (SMB, macOS File Sharing)") {
                        HStack {
                            Text(smb.running ? "macOS File Sharing is on" : "macOS File Sharing is off")
                            Spacer()
                            if smb.busy { ProgressView().controlSize(.small) }
                            if smb.shares.contains(where: { $0.path == folder }) {
                                Button("Stop sharing with SMB") {
                                    if let item = smb.shares.first(where: { $0.path == folder }) { Task { await smb.unshare(item) } }
                                }
                            } else {
                                Button("Share this folder with SMB") {
                                    let readOnly = store.config.share.readOnly, guest = store.config.share.anonymous
                                    Task { await smb.share(URL(fileURLWithPath: folder), readOnly: readOnly, guest: guest) }
                                }
                            }
                        }
                        if smb.shares.contains(where: { $0.path == folder }), let address = SMBServer.addresses().first {
                            AccessLine(label: "Windows", value: "\\\\" + address.replacingOccurrences(of: "smb://", with: "") + "\\" + (folder as NSString).lastPathComponent)
                        }
                        ForEach(smb.shares.filter { $0.path != folder }) { item in
                            HStack {
                                Label(item.name, systemImage: "folder")
                                Spacer()
                                Button("Stop Sharing") { Task { await smb.unshare(item) } }
                            }
                        }
                        Text("Asks for your administrator password. To log in from Windows, turn on “Windows File Sharing” for your user in System Settings → Sharing.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let message = smb.message { DisabledReason("\(message)") }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: advanced ? 720 : 560)
        .task { await smb.refresh() }
        .onAppear {
            // Sin carpeta elegida: se propone la que está abierta en Explorer (no toda la carpeta de usuario).
            if !store.config.share.enabled, store.config.share.folder.isEmpty,
               let current = KeyWindowFocus.shared.windowBrowser?.currentURL {
                store.config.share.folder = current.path
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Share")
        panel.directoryURL = URL(fileURLWithPath: folder)
        if panel.runModal() == .OK, let url = panel.url { store.config.share.folder = url.path }
    }

    private func copyInstructions(_ address: String) {
        var text = String(localized: "Address") + ": " + address
        if !store.config.share.anonymous {
            text += "\n" + String(localized: "User") + ": " + store.config.share.user
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}

private struct AccessLine: View {
    let label: LocalizedStringKey
    let value: String
    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(verbatim: value).font(.body.monospaced()).textSelection(.enabled)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless).help(Text("Copy"))
            }
        }
    }
}

/// Los dos botones de arriba: «Configuración rápida» / «Configuración avanzada».
private struct ModePicker: View {
    @Binding var advanced: Bool
    var body: some View {
        Picker("", selection: $advanced) {
            Text("Quick Setup").tag(false)
            Text("Advanced Setup").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding([.horizontal, .top], 14)
        .accessibilityIdentifier("network.mode")
    }
}

// MARK: Ventanas y menú

enum NetworkWindow: String {
    case connect, share
    @MainActor private static var windows: [NetworkWindow: NSWindow] = [:]

    @MainActor
    static func open(_ kind: NetworkWindow) {
        if let window = windows[kind], window.isVisible { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("explorer.network.\(kind.rawValue)")
        switch kind {
        case .connect:
            window.title = String(localized: "Connect to a Server")
            window.contentViewController = NSHostingController(rootView: ConnectView())
        case .share:
            window.title = String(localized: "Share a Folder")
            window.contentViewController = NSHostingController(rootView: ShareView())
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[kind] = window
    }

    @MainActor static func close(_ kind: NetworkWindow) { windows[kind]?.close() }
    @MainActor static func current(_ kind: NetworkWindow) -> NSWindow? { windows[kind].flatMap { $0.isVisible ? $0 : nil } }
}

/// Menú «Red» de la barra de menús: dos acciones y, si compartes algo, qué y cómo pararlo.
struct NetworkMenu: Commands {
    static let title = "Network"
    @AppStorage(NetworkSettings.showsMenuKey) private var shows = true
    @ObservedObject private var store = NetworkStore.shared
    @ObservedObject private var ftp = FTPServerController.shared
    let currentFolder: () -> URL?

    var body: some Commands {
        if shows {
            CommandMenu(LocalizedStringKey(NetworkMenu.title)) {
                Button("Connect to a Server…") { NetworkWindow.open(.connect) }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                if !store.config.servers.isEmpty {
                    Menu("Recent") {
                        ForEach(store.config.servers.prefix(10)) { saved in
                            Button(saved.title) {
                                Task {
                                    if let error = await NetworkConnector.connect(saved, password: FTPSecrets.password(for: saved.id) ?? "", remember: true) {
                                        KeyWindowFocus.shared.windowBrowser?.errorMessage = error
                                    }
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Share a Folder…") { NetworkWindow.open(.share) }
                if let url = currentFolder(), !(store.config.share.enabled && store.config.share.folderPath == url.path) {
                    Button("Share “\(url.lastPathComponent)”") {
                        store.config.share.folder = url.path
                        store.config.share.enabled = true
                        NetworkWindow.open(.share)
                    }
                }
                if store.config.share.enabled {
                    Divider()
                    Text("Sharing “\((store.config.share.folderPath as NSString).lastPathComponent)”")
                    Button("Stop Sharing") { store.config.share.enabled = false }
                }
            }
        }
    }
}

/// Ajustes → Red: dónde se guarda, el menú y accesos a las dos ventanas.
struct NetworkSettingsSection: View {
    @AppStorage(NetworkSettings.showsMenuKey) private var shows = true
    @ObservedObject private var store = NetworkStore.shared

    var body: some View {
        Section {
            SettingsPreviewBox(title: "Preview: the “Network” menu") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connect to a Server…")
                    Text("Share a Folder…")
                    if store.config.share.enabled {
                        Divider()
                        Text("Sharing “\((store.config.share.folderPath as NSString).lastPathComponent)”").foregroundStyle(.secondary)
                    }
                }
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                .opacity(shows ? 1 : 0.3)
            }
            Toggle(isOn: $shows) {
                Label("“Network” menu in the menu bar", systemImage: "menubar.rectangle")
                Text("Connect to other computers (Windows, NAS, Mac, FTP) and share a folder of this Mac.")
            }
            HStack {
                Button("Connect to a Server…") { NetworkWindow.open(.connect) }
                Button("Share a Folder…") { NetworkWindow.open(.share) }
            }
        }
        Section("Where it’s saved") {
            LabeledContent {
                Button("Show in Explorer") { WindowService.open(at: store.file.deletingLastPathComponent()) }
            } label: {
                Label(store.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "doc.text")
                Text("Saved servers and the shared folder, as readable text you can copy or back up. Passwords are kept in the macOS Keychain, never in this file.")
            }
        }
    }
}
