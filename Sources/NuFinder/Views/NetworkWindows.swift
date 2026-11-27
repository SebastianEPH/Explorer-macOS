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

/// Ventana «Conectarse a un servidor FTP / SMB».
struct ConnectView: View {
    /// FTP o SMB: lo elige el menú («Conectarse a un servidor FTP…» / «…SMB…»).
    let kind: SavedServer.Kind
    @ObservedObject private var store = NetworkStore.shared
    @AppStorage("network.connect.advanced") private var advanced = false
    @State private var address = ""
    @State private var user = ""
    @State private var password = ""
    @State private var port = ""
    @State private var anonymous = false
    @State private var remember = true
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    /// Servidor que resulta de lo escrito (lo que se usa al pulsar Conectar).
    var server: SavedServer? {
        guard var server = SavedServer.parse(address, kind: kind) else { return nil }
        if !user.isEmpty { server.user = user }
        if let custom = Int(port), custom > 0 { server.port = custom }
        server.anonymous = anonymous
        server.name = name
        return server
    }

    private var examples: String {
        kind == .ftp ? String(localized: "Examples: ftp.mi-web.com · 192.168.1.30 · ftp://192.168.1.30:2121")
                     : String(localized: "Examples: 192.168.1.20 · nas.local/Fotos · \\\\PC\\Documentos")
    }

    var body: some View {
        VStack(spacing: 0) {
            ModePicker(advanced: $advanced)
            Form {
                Section {
                    TextField(text: $address, prompt: Text(verbatim: kind == .ftp ? "ftp.mi-web.com" : "192.168.1.20/Fotos")) { Text("Server address") }
                        .onSubmit { connect() }
                    Text(verbatim: examples).font(.caption).foregroundStyle(.secondary) // verbatim: sin Markdown (se comía «\»)
                    if !anonymous {
                        TextField("User", text: $user)
                        SecureField("Password", text: $password)
                    }
                } header: {
                    Text(kind == .ftp ? "Which FTP server do you want to open?" : "Which Windows, NAS or Mac do you want to open?")
                }
                if advanced {
                    Section("Advanced") {
                        TextField("Port", text: $port, prompt: Text(verbatim: String(SavedServer.defaultPort(kind))))
                        Toggle(kind == .ftp ? "Connect without user (anonymous)" : "Connect as guest", isOn: $anonymous)
                        Toggle("Remember password in the Keychain", isOn: $remember)
                        TextField("Name in the list", text: $name, prompt: Text("Optional, e.g. “NAS at home”"))
                    }
                }
                let recent = store.config.servers.filter { $0.kind == kind }
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent) { saved in
                            HStack {
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
            if error == nil { NetworkWindow.close(.connect, kind) }
        }
    }
}

// MARK: Compartir

/// Ventana «Compartir una carpeta por FTP / SMB».
struct ShareView: View {
    let kind: SavedServer.Kind
    @ObservedObject private var store = NetworkStore.shared
    @ObservedObject private var ftp = FTPServerController.shared
    @ObservedObject private var smb = SMBServerController.shared
    @AppStorage("network.share.advanced") private var advanced = false
    @State private var password = FTPSecrets.password(for: FTPSettings.serverPasswordAccount) ?? ""
    @State private var smbFolder = KeyWindowFocus.shared.windowBrowser?.currentURL.path ?? NSHomeDirectory()
    @State private var smbReadOnly = false
    @State private var smbGuest = false

    private var share: Binding<NetworkConfig.Share> { $store.config.share }
    private var folder: String { kind == .ftp ? store.config.share.folderPath : smbFolder }

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
                } header: {
                    Text(kind == .ftp ? "Which folder do you want to share by FTP?" : "Which folder do you want to share with Windows, NAS or Mac (SMB)?")
                }
                if kind == .ftp { ftpSections } else { smbSections }
            }
            .formStyle(.grouped)
        }
        .frame(width: 540, height: advanced ? 680 : 580)
        .task { await smb.refresh() }
        .onAppear {
            // Sin carpeta elegida: se propone la abierta en Explorer (no toda la carpeta de usuario).
            if kind == .ftp, !store.config.share.enabled, store.config.share.folder.isEmpty,
               let current = KeyWindowFocus.shared.windowBrowser?.currentURL {
                store.config.share.folder = current.path
            }
        }
    }

    // FTP: servidor propio de Explorer (sin contraseña de administrador).
    @ViewBuilder private var ftpSections: some View {
        Section {
            Toggle(isOn: share.enabled) {
                Text(store.config.share.enabled ? "Shared by FTP" : "Not shared").font(.headline)
                Text(store.config.share.enabled ? "Other devices on your network can open this folder." : "Turn on to let other devices open this folder.")
            }
            .toggleStyle(.switch)
            if case .failed(let message) = ftp.state, store.config.share.enabled {
                DisabledReason("Couldn’t share: \(message). Change the port in Advanced.")
            }
        }
        if ftp.isRunning, let address = ftp.addresses.first {
            Section("How to open it from another device") {
                AccessLine(label: "Address", value: address)
                if store.config.share.anonymous {
                    Text("No user or password needed.").font(.caption).foregroundStyle(.secondary)
                } else {
                    AccessLine(label: "User", value: store.config.share.user)
                }
                Text("Windows: paste the address in File Explorer. Phone: any “FTP” file app. Mac: Finder → Go → Connect to Server.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Text("FTP doesn’t encrypt: use it only on networks you trust.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // SMB: el «Compartir archivos» de macOS (pide contraseña de administrador).
    @ViewBuilder private var smbSections: some View {
        let current = smb.shares.first { $0.path == folder }
        Section {
            HStack {
                VStack(alignment: .leading) {
                    Text(current != nil ? "Shared with SMB" : "Not shared").font(.headline)
                    Text("Uses macOS File Sharing. It asks for your administrator password.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if smb.busy { ProgressView().controlSize(.small) }
                if let current {
                    Button("Stop Sharing") { Task { await smb.unshare(current) } }.disabled(smb.busy)
                } else {
                    Button("Share") {
                        let url = URL(fileURLWithPath: folder), ro = smbReadOnly, guest = smbGuest
                        Task { await smb.share(url, readOnly: ro, guest: guest) }
                    }
                    .buttonStyle(.borderedProminent).disabled(smb.busy)
                }
            }
            if let message = smb.message { DisabledReason("\(message)") }
        }
        if let current, let host = SMBServer.addresses().first?.replacingOccurrences(of: "smb://", with: "") {
            Section("How to open it from another device") {
                AccessLine(label: "Windows", value: "\\\\" + host + "\\" + current.name)
                AccessLine(label: "Mac", value: "smb://\(host)/\(current.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? current.name)")
                Text("Log in with your Mac user and password. On Windows, your user needs “Windows File Sharing” turned on in System Settings → Sharing → File Sharing → Options.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open System Settings → Sharing") { SMBServer.openSystemSharing() }
            }
        }
        if advanced {
            Section("Advanced") {
                Toggle("Others can only view and download (not change or delete)", isOn: $smbReadOnly)
                Toggle("Allow guests (no password)", isOn: $smbGuest)
                Text("Applies when you press Share.").font(.caption).foregroundStyle(.secondary)
            }
        }
        let others = smb.shares.filter { $0.path != folder }
        if !others.isEmpty {
            Section("Other folders shared with SMB") {
                ForEach(others) { item in
                    HStack {
                        Label(item.name, systemImage: "folder")
                        Spacer()
                        Button("Stop Sharing") { Task { await smb.unshare(item) } }.disabled(smb.busy)
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Share")
        panel.directoryURL = URL(fileURLWithPath: folder)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if kind == .ftp { store.config.share.folder = url.path } else { smbFolder = url.path }
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
    @MainActor private static var windows: [String: NSWindow] = [:]

    @MainActor
    static func open(_ kind: NetworkWindow, _ proto: SavedServer.Kind) {
        let key = "\(kind.rawValue).\(proto.rawValue)"
        if let window = windows[key], window.isVisible { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("explorer.network.\(key)")
        switch (kind, proto) {
        case (.connect, .ftp): window.title = String(localized: "Connect to an FTP Server")
        case (.connect, .smb): window.title = String(localized: "Connect to an SMB Server (Windows, NAS, Mac)")
        case (.share, .ftp): window.title = String(localized: "Share a Folder by FTP")
        case (.share, .smb): window.title = String(localized: "Share a Folder by SMB")
        }
        window.contentViewController = kind == .connect
            ? NSHostingController(rootView: ConnectView(kind: proto))
            : NSHostingController(rootView: AnyView(ShareView(kind: proto)))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[key] = window
    }

    @MainActor static func close(_ kind: NetworkWindow, _ proto: SavedServer.Kind) { windows["\(kind.rawValue).\(proto.rawValue)"]?.close() }
    @MainActor static func current(_ kind: NetworkWindow, _ proto: SavedServer.Kind) -> NSWindow? {
        windows["\(kind.rawValue).\(proto.rawValue)"].flatMap { $0.isVisible ? $0 : nil }
    }
}

/// Menú «Red»: FTP y SMB a la vista, cada uno con «Conectarse a un servidor …» y «Compartir una
/// carpeta por …» (y lo que se está compartiendo), recientes y «Configuración de Red…».
struct NetworkMenu: Commands {
    static let title = "Network"
    @AppStorage(NetworkSettings.showsMenuKey) private var shows = true
    @ObservedObject private var store = NetworkStore.shared
    @ObservedObject private var smb = SMBServerController.shared
    let currentFolder: () -> URL?

    var body: some Commands {
        if shows {
            CommandMenu(LocalizedStringKey(NetworkMenu.title)) {
                Menu("FTP") {
                    Button("Connect to an FTP Server…") { NetworkWindow.open(.connect, .ftp) }
                        .keyboardShortcut("k", modifiers: [.command, .option])
                    Button("Share a Folder by FTP…") { NetworkWindow.open(.share, .ftp) }
                    if store.config.share.enabled {
                        Divider()
                        Text("Sharing “\((store.config.share.folderPath as NSString).lastPathComponent)” by FTP")
                        Button("Stop Sharing by FTP") { store.config.share.enabled = false }
                    }
                }
                Menu("SMB (Windows, NAS, Mac)") {
                    Button("Connect to an SMB Server…") { NetworkWindow.open(.connect, .smb) }
                    Button("Share a Folder by SMB…") { NetworkWindow.open(.share, .smb) }
                    if !smb.shares.isEmpty {
                        Divider()
                        ForEach(smb.shares) { item in
                            Button("Stop Sharing “\(item.name)” by SMB") { Task { await smb.unshare(item) } }
                        }
                    }
                }
                if !store.config.servers.isEmpty {
                    Menu("Recent Servers") {
                        ForEach(store.config.servers.prefix(10)) { saved in
                            Button("\(saved.title) (\(saved.kind.rawValue.uppercased()))") {
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
                Button("Network Settings…") { SettingsOpener.open(tab: "network", page: "") }
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
                    Text("FTP  ›  Connect to an FTP Server… · Share a Folder by FTP…")
                    Text("SMB (Windows, NAS, Mac)  ›  Connect to an SMB Server… · Share a Folder by SMB…")
                    Text("Network Settings…")
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
                Button("Connect to an FTP Server…") { NetworkWindow.open(.connect, .ftp) }
                Button("Connect to an SMB Server…") { NetworkWindow.open(.connect, .smb) }
            }
            HStack {
                Button("Share a Folder by FTP…") { NetworkWindow.open(.share, .ftp) }
                Button("Share a Folder by SMB…") { NetworkWindow.open(.share, .smb) }
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
