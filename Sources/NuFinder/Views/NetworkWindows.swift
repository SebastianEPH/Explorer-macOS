import AppKit
import NetFS
import SwiftUI

/// Fork: «Red». Una página por protocolo (FTP, SMB…) en Ajustes → Red, cada una con
///  · Mis conexiones: los equipos a los que entras (lista + ficha con todos sus datos, Conectar).
///  · Mi servidor: este Mac compartiendo por ese protocolo (misma lista + ficha).
/// Protocolo nuevo → su página aquí con esas dos partes. Todo en `~/.explorer/red.json`
/// (`NetworkStore`); las contraseñas, en el Llavero.
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
        let saved = store.config.servers.first ?? server // con la clave definitiva (si ya existía, la suya)
        FTPSecrets.setPassword(remember && !server.anonymous ? password : nil, for: saved.id)
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


// MARK: Ajustes → Red

enum NetworkSettingsPages {
    @MainActor static var pages: [SettingsPage] {
        [
            SettingsPage("ftp", "FTP", "network") { ProtocolPage(kind: .ftp) },
            SettingsPage("smb", "SMB (Windows, NAS, Mac)", "externaldrive.connected.to.line.below") { ProtocolPage(kind: .smb) },
            SettingsPage("general", "General", "gearshape") { NetworkSettingsSection() },
        ]
    }

    @MainActor static func open(_ kind: SavedServer.Kind, add: Bool = false) {
        if add { UserDefaults.standard.set(kind.rawValue, forKey: ProtocolPage.addKey) }
        SettingsOpener.open(tab: "network", page: kind.rawValue)
    }
}

/// Fila de lista: icono, título, detalle y lápiz si está elegida (igual para conexiones y mi servidor).
private struct ItemRow: View {
    let symbol: String
    let title: String
    let detail: String
    let selected: Bool
    var dot: Bool? = nil
    let tap: () -> Void
    var body: some View {
        HStack {
            Image(systemName: symbol).frame(width: 20)
            VStack(alignment: .leading) {
                Text(title).fontWeight(selected ? .semibold : .regular)
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let dot { Circle().fill(dot ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8) }
            if selected { Image(systemName: "pencil").foregroundStyle(.tint) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
    }
}

/// Página de un protocolo: «Mis conexiones» y «Mi servidor», cada una con lista y ficha.
struct ProtocolPage: View {
    static let addKey = "network.addServer"
    let kind: SavedServer.Kind
    @ObservedObject private var store = NetworkStore.shared
    @ObservedObject private var ftp = FTPServerController.shared
    @ObservedObject private var smb = SMBServerController.shared
    /// Clave de la conexión elegida, o «mine» = mi servidor.
    @State private var selected: String?
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var pickerDone: ((String) -> Void)?

    private var name: String { kind == .ftp ? "FTP" : "SMB" }
    private var connections: [SavedServer] { store.config.servers.filter { $0.kind == kind } }
    private var index: Int? { store.config.servers.firstIndex { $0.key == selected } }

    /// Pestaña: conexiones (cliente) o mi servidor; se recuerda por protocolo.
    @AppStorage private var tab: String
    init(kind: SavedServer.Kind) {
        self.kind = kind
        _tab = AppStorage(wrappedValue: "connections", "network.tab.\(kind.rawValue)")
    }

    var body: some View {
        Section {
            Picker("", selection: $tab) {
                Label(kind == .ftp ? "My FTP Connections" : "My SMB Connections", systemImage: "arrow.down.circle").tag("connections")
                Label(kind == .ftp ? "My FTP Server" : "My SMB Server", systemImage: "desktopcomputer").tag("server")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } footer: {
            Text(tab == "connections" ? "Computers you connect to (client)." : "This Mac sharing with others (server).")
        }
        .sheet(isPresented: Binding(get: { pickerDone != nil }, set: { if !$0 { pickerDone = nil } })) {
            FolderPicker(title: "Choose the folder to share", confirm: "Share This Folder") { url in
                if let url { pickerDone?(url.path) }
                pickerDone = nil
            }
        }
        .onAppear(perform: addRequested)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in addRequested() }
        .onChange(of: tab) { _, new in
            // La contraseña de la ficha visible (conexión elegida o mi servidor), nunca la de la otra pestaña.
            password = FTPSecrets.password(for: new == "server" ? FTPSettings.serverPasswordAccount : selected ?? "") ?? ""
        }

        if tab == "connections" { connectionsTab } else { serverTab }
    }

    // MARK: Pestaña «Mis conexiones» (cliente)

    @ViewBuilder private var connectionsTab: some View {
        Section {
            if connections.isEmpty {
                Text(kind == .ftp ? "No FTP connections yet. Add one with its address, user and password."
                                  : "No SMB connections yet. Add a Windows PC, NAS or Mac with its address, user and password.")
                    .foregroundStyle(.secondary)
            }
            ForEach(connections) { server in
                ItemRow(symbol: kind == .ftp ? "network" : "externaldrive.connected.to.line.below",
                        title: server.title,
                        detail: "\(server.anonymous ? "" : server.user.isEmpty ? "" : server.user + "@")\(server.host):\(server.port)\(server.path.isEmpty ? "" : "/" + server.path)",
                        selected: server.key == selected) { select(server.key) }
            }
            Button { add() } label: { Label(kind == .ftp ? "Add FTP Connection" : "Add SMB Connection", systemImage: "plus") }
        } header: { Text(kind == .ftp ? "My FTP Connections" : "My SMB Connections") } footer: {
            Text("Saved in ~/.explorer/red.json; passwords go to the macOS Keychain.")
        }
        if let index { connectionForm($store.config.servers[index]) }
    }

    // MARK: Pestaña «Mi servidor»

    @ViewBuilder private var serverTab: some View {
        Section {
            if kind == .ftp {
                ItemRow(symbol: "desktopcomputer", title: String(localized: "This Mac"),
                        detail: ftp.isRunning ? (ftp.addresses.first ?? "") + " · " + (store.config.share.folderPath as NSString).lastPathComponent
                                              : String(localized: "Stopped"),
                        selected: false, dot: ftp.isRunning) {}
            } else {
                ItemRow(symbol: "desktopcomputer", title: String(localized: "This Mac"),
                        detail: smb.running ? String(localized: "On · \(smb.shares.count) shared folders") : String(localized: "Stopped"),
                        selected: false, dot: smb.running) {}
            }
        } header: { Text(kind == .ftp ? "My FTP Server" : "My SMB Server") } footer: {
            Text(kind == .ftp ? "This Mac shares a folder by FTP (built into Explorer)." : "This Mac shares folders by SMB (macOS File Sharing).")
        }
        .task {
            await smb.refresh()
            password = FTPSecrets.password(for: FTPSettings.serverPasswordAccount) ?? ""
        }
        if kind == .ftp { ftpServerForm } else { smbServerForm }
    }

    // MARK: Ficha de una conexión

    @ViewBuilder private func connectionForm(_ server: Binding<SavedServer>) -> some View {
        Section("Connection details") {
            TextField("Name", text: server.name, prompt: Text("e.g. “NAS at home”"))
            TextField("Address", text: server.host, prompt: Text(verbatim: kind == .ftp ? "ftp.mi-web.com" : "192.168.1.20"))
            TextField("Port", value: server.port, format: .number.grouping(.never))
            TextField(kind == .ftp ? "Start folder" : "Shared folder on that computer", text: server.path,
                      prompt: Text(verbatim: kind == .ftp ? "/" : "Fotos"))
            Toggle(kind == .ftp ? "Anonymous (no user)" : "Guest (no user)", isOn: server.anonymous)
            if !server.wrappedValue.anonymous {
                TextField("User", text: server.user)
                // Se guarda solo cuando la persona escribe (no al abrir la ficha: eso tocaba el Llavero).
                SecureField("Password", text: Binding(get: { password }, set: { value in
                    password = value
                    FTPSecrets.setPassword(value.isEmpty ? nil : value, for: server.wrappedValue.key)
                }))
            }
            HStack {
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Delete", role: .destructive) { store.forget(server.wrappedValue); selected = nil }
                Button("Connect") { connect(server.wrappedValue) }
                    .buttonStyle(.borderedProminent)
                    .disabled(server.wrappedValue.host.isEmpty || busy)
            }
        }
    }

    // MARK: Ficha de mi servidor FTP

    @ViewBuilder private var ftpServerForm: some View {
        let share = $store.config.share
        Section("My FTP server details") {
            Toggle(isOn: share.enabled) { Text("On") }
            if case .failed(let message) = ftp.state, store.config.share.enabled {
                DisabledReason("Couldn’t start: \(message). Try another port.")
            }
            LabeledContent("Shared folder") {
                HStack {
                    Text(store.config.share.folderPath).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Change…") { chooseFolder { store.config.share.folder = $0 } }
                }
            }
            TextField("Port", value: share.port, format: .number.grouping(.never))
            Toggle("Only this Mac (127.0.0.1)", isOn: share.localOnly)
            if let address = ftp.addresses.first { AccessLine(label: "Address to connect", value: address) }
            if ftp.isRunning && !store.config.share.localOnly { NetworkExposureNote(port: UInt16(store.config.share.port)) }
            Text("FTP doesn’t encrypt: use it only on networks you trust.").font(.caption).foregroundStyle(.secondary)
        }
        usersSection
    }

    // MARK: Usuarios de mi servidor FTP

    @State private var selectedUser: String?
    @State private var userPassword = ""

    @ViewBuilder private var usersSection: some View {
        let share = $store.config.share
        Section {
            ForEach(store.config.share.users) { user in
                ItemRow(symbol: "person.fill", title: user.name.isEmpty ? String(localized: "New user") : user.name,
                        detail: userDetail(user), selected: user.key == selectedUser) { selectUser(user.key) }
            }
            Toggle(isOn: share.anonymous) {
                Text("Anonymous access")
                Text("Anyone can enter with the user “anonymous” and no password.")
            }
            if store.config.share.anonymous { Toggle("Anonymous: read only", isOn: share.readOnly) }
            Button { addUser() } label: { Label("Add User", systemImage: "person.badge.plus") }
            if store.config.share.users.isEmpty && !store.config.share.anonymous {
                DisabledReason("Add a user or turn on anonymous access, otherwise nobody can enter.")
            }
        } header: { Text("Users") } footer: {
            Text("Each user can have their own password (optional), permissions and folder. Passwords go to the macOS Keychain.")
        }

        if let index = store.config.share.users.firstIndex(where: { $0.key == selectedUser }) {
            let user = share.users[index]
            Section("User details") {
                TextField("User", text: user.name, prompt: Text("e.g. “ana”"))
                SecureField("Password (optional)", text: Binding(get: { userPassword }, set: { value in
                    userPassword = value // solo al escribir: al abrir la ficha no se toca el Llavero
                    FTPSecrets.setPassword(value.isEmpty ? nil : value, for: user.wrappedValue.key)
                    FTPServerController.shared.passwordChanged()
                }))
                if userPassword.isEmpty {
                    Text("No password: anyone who knows this user name can enter.").font(.caption).foregroundStyle(.orange)
                }
                Toggle("Read only", isOn: user.readOnly)
                LabeledContent("Folder") {
                    HStack {
                        Text(user.wrappedValue.folder.isEmpty ? String(localized: "Same as the server") : user.wrappedValue.folder)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        if !user.wrappedValue.folder.isEmpty { Button("Use the server’s") { user.wrappedValue.folder = "" } }
                        Button("Change…") { chooseFolder { user.wrappedValue.folder = $0 } }
                    }
                }
                HStack {
                    Spacer()
                    Button("Delete User", role: .destructive) {
                        FTPSecrets.setPassword(nil, for: user.wrappedValue.key)
                        store.config.share.users.remove(at: index)
                        selectedUser = nil
                    }
                }
            }
        }
    }

    private func userDetail(_ user: FTPUser) -> String {
        var parts = [user.readOnly ? String(localized: "Read only") : String(localized: "Read and write")]
        parts.append(FTPSecrets.password(for: user.key)?.isEmpty == false ? String(localized: "With password") : String(localized: "No password"))
        if !user.folder.isEmpty { parts.append((user.folder as NSString).lastPathComponent) }
        return parts.joined(separator: " · ")
    }

    private func selectUser(_ key: String) {
        selectedUser = key
        userPassword = FTPSecrets.password(for: key) ?? ""
    }

    private func addUser() {
        let user = FTPUser(name: "")
        store.config.share.users.append(user)
        selectUser(user.key)
    }

    // MARK: Ficha de mi servidor SMB

    @State private var smbReadOnly = false
    @State private var smbGuest = false
    @AppStorage(AdminAuthorization.rememberKey) private var rememberAdmin = true
    @State private var adminRemembered = AdminAuthorization.isRemembered
    @State private var adminMessage: String?

    /// El permiso de administrador se gestiona en Ajustes → Sistema → Permisos; aquí solo se ve y se enlaza.
    @ViewBuilder private var adminSection: some View {
        // Solo si falta el permiso: si ya está recordado no hay nada que decir.
        if !AdminAuthorization.isRemembered {
        Section {
            HStack {
                Image(systemName: AdminAuthorization.isRemembered ? "checkmark.circle.fill" : "lock.fill")
                    .foregroundStyle(AdminAuthorization.isRemembered ? Color.green : Color.orange)
                Text(AdminAuthorization.isRemembered ? "Administrator permission remembered" : "Needs the administrator permission (once)")
                Spacer()
                Button("Permissions…") { SettingsOpener.open(tab: "system", page: "permissions") }
            }
        }
        }
    }

    @ViewBuilder private var smbServerForm: some View {
        adminSection
        smbUsersSection
        Section("My SMB server details") {
            HStack {
                Text(smb.running ? "macOS File Sharing is on" : "macOS File Sharing is off")
                Spacer()
                if smb.busy { ProgressView().controlSize(.small) }
                Button(smb.running ? "Stop" : "Start") { let on = !smb.running; Task { await smb.setRunning(on) } }.disabled(smb.busy)
            }
            if let message = smb.message { DisabledReason("\(message)") }
            ForEach(smb.shares) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(item.name, systemImage: "folder.fill")
                        Spacer()
                        Button("Stop Sharing") { Task { await smb.unshare(item) } }.disabled(smb.busy)
                    }
                    Text(verbatim: item.path).font(.caption).foregroundStyle(.secondary)
                    // Permisos de la carpeta ya compartida, cambiables en cualquier momento.
                    HStack(spacing: 20) {
                        Toggle("Read only", isOn: Binding(get: { item.readOnly }, set: { value in
                            Task { await smb.update(item, readOnly: value, guest: item.guest) }
                        }))
                        Toggle("Guests", isOn: Binding(get: { item.guest }, set: { value in
                            Task { await smb.update(item, readOnly: item.readOnly, guest: value) }
                        }))
                    }
                    .toggleStyle(.checkbox)
                    .disabled(smb.busy)
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text("To log in from Windows, turn on “Windows File Sharing” for your user in System Settings → Sharing → File Sharing → Options.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open…") { SMBServer.openSystemSharing() }
            }
        }
        smbNewShareSection
        if smb.running { smbHowToConnect }
    }

    /// «Cómo conectarse»: IP, dirección de cada carpeta, usuario y quién puede entrar.
    @ViewBuilder private var smbHowToConnect: some View {
        let ip = FTPSettings.localAddresses().first ?? "127.0.0.1"
        Section {
            AccessLine(label: "Your IP on the network", value: ip)
            ForEach(smb.shares) { item in
                let encoded = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.name
                VStack(alignment: .leading, spacing: 4) {
                    Label(item.name, systemImage: "folder.fill").font(.callout.weight(.medium))
                    AccessLine(label: "Windows (File Explorer)", value: "\\\\\(ip)\\\(item.name)")
                    AccessLine(label: "Mac, iPhone, Android (smb://)", value: "smb://\(ip)/\(encoded)")
                    Text(item.guest ? "Anyone on your network can enter without a password (guests on)."
                                    : "Log in with your Mac user “\(NSUserName())” and its password.")
                        .font(.caption).foregroundStyle(item.guest ? Color.orange : Color.secondary)
                    if item.guest && !item.guestsCanRead {
                        Text("Guests will see “content unavailable”: on the disk only your user can open this folder. Log in with your user instead.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            NetworkExposureNote(port: 445)
        } header: { Text("How to connect") }
    }

    /// «Compartir otra carpeta»: opciones en filas propias y el botón al final.
    @ViewBuilder private var smbNewShareSection: some View {
        Section {
            Toggle(isOn: $smbReadOnly) {
                Text("Read only")
                Text("Others can open and copy, but not change or delete.")
            }
            Toggle(isOn: $smbGuest) {
                Text("Allow guests")
                Text("Anyone on the network can enter without a user or password.")
            }
            HStack {
                Spacer()
                Button("Choose Folder and Share…") {
                    chooseFolder { path in
                        let ro = smbReadOnly, guest = smbGuest
                        Task { await smb.share(URL(fileURLWithPath: path), readOnly: ro, guest: guest) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(smb.busy)
            }
        } header: { Text("Share another folder") }
    }

    /// Usuarios que pueden entrar por SMB: las cuentas de este Mac (SMB no tiene usuarios propios).
    @ViewBuilder private var smbUsersSection: some View {
        Section {
            ForEach(SMBUsers.list(), id: \.name) { user in
                VStack(alignment: .leading, spacing: 4) {
                    ItemRow(symbol: user.isAdmin ? "person.badge.key.fill" : "person.fill", title: user.fullName,
                            detail: user.name + (user.isAdmin ? " · " + String(localized: "Administrator") : ""),
                            selected: false, dot: user.canUseSMB) {}
                    if user.canUseSMB {
                        Text("Can log in from iPhone, Android and Windows.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Can’t log in from iPhone, Android or Windows yet: turn on “Windows File Sharing” for this user (System Settings → General → Sharing → File Sharing ⓘ → Options). macOS asks for its password.")
                                .font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button("Open…") { SMBServer.openSystemSharing() }.controlSize(.small)
                        }
                    }
                }
            }
            HStack {
                Text("To add someone, create a user in System Settings → Users & Groups; they log in with that user and password.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Users & Groups…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")!)
                }
            }
        } header: { Text("Users") } footer: {
            Text("SMB uses the user accounts of this Mac. Guests (if allowed on a folder) enter without a user.")
        }
    }

    // MARK: Acciones

    private func addRequested() {
        guard UserDefaults.standard.string(forKey: ProtocolPage.addKey) == kind.rawValue else { return }
        UserDefaults.standard.removeObject(forKey: ProtocolPage.addKey)
        tab = "connections"
        add()
    }

    private func select(_ key: String) {
        selected = key
        password = FTPSecrets.password(for: key == "mine" ? FTPSettings.serverPasswordAccount : key) ?? ""
        error = nil
    }

    private func add() {
        let new = SavedServer(kind: kind, host: "")
        store.config.servers.insert(new, at: 0)
        select(new.key)
    }

    private func connect(_ server: SavedServer) {
        busy = true; error = nil
        Task {
            error = await NetworkConnector.connect(server, password: password, remember: true)
            busy = false
        }
    }

    /// Abre el selector de carpetas de Explorer (no el panel de macOS/Finder).
    private func chooseFolder(_ done: @escaping (String) -> Void) { pickerDone = done }
}

// MARK: Menú

/// Menú «Red»: un submenú por protocolo con tus conexiones (clic = conectar), añadir una,
/// el estado de tu servidor y el acceso a su página de Ajustes.
struct NetworkMenu: Commands {
    static let title = "Network"
    @AppStorage(NetworkSettings.showsMenuKey) private var shows = true
    @ObservedObject private var store = NetworkStore.shared
    @ObservedObject private var ftp = FTPServerController.shared
    @ObservedObject private var smb = SMBServerController.shared
    let currentFolder: () -> URL?

    @ViewBuilder private func section(_ kind: SavedServer.Kind) -> some View {
        let mine = store.config.servers.filter { $0.kind == kind && !$0.host.isEmpty }
        Section(kind == .ftp ? "My FTP Connections" : "My SMB Connections") {
            ForEach(mine) { saved in
                Button(saved.title) {
                    Task {
                        if let error = await NetworkConnector.connect(saved, password: FTPSecrets.password(for: saved.id) ?? "", remember: true) {
                            KeyWindowFocus.shared.windowBrowser?.errorMessage = error
                        }
                    }
                }
            }
            if mine.isEmpty { Text("None yet") }
            Button(kind == .ftp ? "Add FTP Connection…" : "Add SMB Connection…") { NetworkSettingsPages.open(kind, add: true) }
        }
        Section(kind == .ftp ? "My FTP Server" : "My SMB Server") {
            if kind == .ftp {
                Text(ftp.isRunning ? "On: \(ftp.addresses.first ?? "")" : "Stopped")
                Button(ftp.isRunning ? "Stop" : "Start") { store.config.share.enabled.toggle() }
            } else {
                Text(smb.running ? "On: \(smb.shares.count) shared folders" : "Stopped")
            }
        }
        Divider()
        Button(kind == .ftp ? "FTP Settings…" : "SMB Settings…") { NetworkSettingsPages.open(kind) }
    }

    var body: some Commands {
        if shows {
            CommandMenu(LocalizedStringKey(NetworkMenu.title)) {
                Menu("FTP") { section(.ftp) }
                Menu("SMB (Windows, NAS, Mac)") { section(.smb) }
            }
        }
    }
}

/// Ajustes → Red → General: el menú y dónde se guarda.
struct NetworkSettingsSection: View {
    @AppStorage(NetworkSettings.showsMenuKey) private var shows = true
    @ObservedObject private var store = NetworkStore.shared

    var body: some View {
        Section {
            SettingsPreviewBox(title: "Preview: the “Network” menu") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("FTP  ›  My FTP Connections · My FTP Server")
                    Text("SMB (Windows, NAS, Mac)  ›  My SMB Connections · My SMB Server")
                }
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                .opacity(shows ? 1 : 0.3)
            }
            Toggle(isOn: $shows) {
                Label("“Network” menu in the menu bar", systemImage: "menubar.rectangle")
                Text("Your connections and your server for each protocol, one click away.")
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

/// Quién puede llegar a mi servidor: solo mi red (IP privada), no internet salvo que se abra el
/// puerto en el router; y si el cortafuegos de macOS está activo.
struct NetworkExposureNote: View {
    let port: UInt16
    @State private var firewallOn: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Only devices on your same network (Wi‑Fi or cable) can reach it. From the internet it’s not reachable unless you open port \(Int(port)) on your router — don’t.",
                  systemImage: "wifi")
                .font(.caption).foregroundStyle(.secondary)
            if let firewallOn {
                HStack {
                    Label(firewallOn ? "macOS firewall is on." : "macOS firewall is off: any device on your network can try to connect.",
                          systemImage: firewallOn ? "checkmark.shield" : "exclamationmark.shield")
                        .font(.caption).foregroundStyle(firewallOn ? Color.secondary : Color.orange)
                    Spacer()
                    Button("Firewall…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")!)
                    }
                    .controlSize(.small)
                }
            }
        }
        .task {
            let on = await Task.detached { () -> Bool in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
                process.arguments = ["--getglobalstate"]
                let pipe = Pipe(); process.standardOutput = pipe; process.standardInput = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return false }
                let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                return text.contains("enabled") || text.contains("State = 1") || text.contains("State = 2")
            }.value
            firewallOn = on
        }
    }
}
