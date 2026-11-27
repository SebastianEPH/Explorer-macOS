import AppKit
import SwiftUI

/// Fork: Ajustes → Servidores → Cliente FTP / Servidor FTP (apartados separados, `part`).
struct FTPSettingsSection: View {
    var part = "client"
    @AppStorage(FTPSettings.clientEnabledKey) private var clientEnabled = false
    @AppStorage(FTPSettings.serverEnabledKey) private var serverEnabled = false
    @AppStorage(FTPSettings.serverPortKey) private var port = FTPSettings.defaultPort
    @AppStorage(FTPSettings.serverRootKey) private var root = ""
    @AppStorage(FTPSettings.serverUserKey) private var user = NSUserName()
    @AppStorage(FTPSettings.serverAnonymousKey) private var anonymous = false
    @AppStorage(FTPSettings.serverReadOnlyKey) private var readOnly = true
    @AppStorage(FTPSettings.serverLocalOnlyKey) private var localOnly = false
    @AppStorage(FTPSettings.showsMenuKey) private var showsMenu = true
    @State private var password = FTPSecrets.password(for: FTPSettings.serverPasswordAccount) ?? ""
    @ObservedObject private var server = FTPServerController.shared

    private var rootPath: String { root.isEmpty ? NSHomeDirectory() : root }

    var body: some View {
        if part == "client" { clientSection } else { serverSection }
    }

    @ObservedObject private var client = FTPClientModel.shared

    // MARK: Cliente FTP: Estado · Servidores guardados · Opciones

    @ViewBuilder private var clientSection: some View {
        Section("Status") {
            SettingsPreviewBox(title: "Preview: the FTP client window") { FTPClientPreview(enabled: clientEnabled) }
            StatusRow(on: client.connectedHost != nil,
                      title: client.connectedHost != nil ? "Connected to \(client.connectedHost ?? "")" : "Not connected",
                      detail: client.connectedHost != nil ? "\(client.path)" : String(localized: "Connect to browse a server's files.")) {
                if client.connectedHost != nil {
                    Button("Show FTP Client") { FTPClientWindow.open() }
                    Button("Disconnect") { client.disconnect() }
                } else {
                    Button("Connect to FTP Server…") { clientEnabled = true; FTPClientWindow.open() }.buttonStyle(.borderedProminent)
                }
            }
        }
        Section("Saved Servers") {
            if client.saved.isEmpty { Text("No saved servers").foregroundStyle(.secondary) }
            ForEach(client.saved) { saved in
                LabeledContent {
                    HStack {
                        Button("Connect") { clientEnabled = true; client.pick(saved); FTPClientWindow.open(); Task { await client.connect() } }
                        Button("Forget") { FTPSettings.forget(saved); client.saved = FTPSettings.savedServers() }
                    }
                } label: {
                    Label(saved.anonymous ? saved.host : "\(saved.user)@\(saved.host)", systemImage: "server.rack")
                    Text(verbatim: "ftp://\(saved.host):\(saved.port)")
                }
            }
        }
        Section("Options") {
            Toggle(isOn: $clientEnabled) {
                Label("FTP Client", systemImage: "network")
                Text("Browse a server, download to the current folder, upload by dragging files. Passwords are kept in the Keychain.")
            }
            Toggle(isOn: $showsMenu) {
                Label("FTP in the “Servers” menu", systemImage: "menubar.rectangle")
                Text("Shows the FTP submenu (client and server) in the menu bar.")
            }
        }
    }

    // MARK: Servidor FTP: Estado · Carpeta compartida · Acceso · Red

    @ViewBuilder private var serverSection: some View {
        Section("Status") {
            SettingsPreviewBox(title: "Preview: what other computers connect to") {
                FTPServerPreview(running: server.isRunning, address: server.addresses.first
                                 ?? "ftp://\(FTPSettings.localAddresses().first ?? "127.0.0.1"):\(port)",
                                 folder: (rootPath as NSString).lastPathComponent, readOnly: readOnly, anonymous: anonymous)
            }
            StatusRow(on: server.isRunning,
                      title: server.isRunning ? "Running at \(server.addresses.first ?? "")" : "Stopped",
                      detail: server.isRunning ? String(localized: "Other devices can connect now.") : String(localized: "Nothing is listening. Start it to share the folder below.")) {
                if server.isRunning {
                    Button("Copy Server Address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(server.addresses.first ?? "", forType: .string)
                    }
                    Button("Stop Server") { serverEnabled = false }
                } else {
                    Button("Start Server") { serverEnabled = true }.buttonStyle(.borderedProminent)
                }
            }
            if case .failed(let message) = server.state, serverEnabled {
                DisabledReason("Couldn’t start: \(message). Try another port.")
            }
        }
        Section("Shared Folder") {
            LabeledContent {
                HStack {
                    Button("Change…") { FTPSettings.chooseRoot() }
                    Button("Show in Explorer") { WindowService.open(at: URL(fileURLWithPath: rootPath)) }
                }
            } label: {
                Label((rootPath as NSString).lastPathComponent, systemImage: "folder.fill")
                Text(rootPath)
            }
            Text("Clients see this folder as “/” and can’t leave it.").font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: $readOnly) {
                Label("Read only", systemImage: "lock")
                Text("Clients can download but not upload, rename or delete.")
            }
        }
        Section("Access") {
            TextField(text: $user) { Label("User", systemImage: "person") }
            SecureField(text: $password) { Label("Password", systemImage: "key") }
                .onChange(of: password) { _, value in
                    FTPSecrets.setPassword(value, for: FTPSettings.serverPasswordAccount)
                    Task { await FTPServerController.shared.apply() }
                }
            if password.isEmpty && !anonymous {
                DisabledReason("Set a password or allow anonymous access, otherwise nobody can log in.")
            }
            Toggle(isOn: $anonymous) {
                Label("Allow anonymous access", systemImage: "person.fill.questionmark")
                Text("Anyone on the network can connect without a password.")
            }
        }
        Section("Network") {
            LabeledContent {
                TextField("", value: $port, format: .number.grouping(.never)).frame(width: 80)
            } label: { Label("Port", systemImage: "number"); Text("2121 by default (ports below 1024 need administrator rights).") }
            Toggle(isOn: $localOnly) {
                Label("Only this Mac", systemImage: "desktopcomputer")
                Text("Listens on 127.0.0.1 only, invisible to the network.")
            }
            Text("FTP sends passwords and files unencrypted: use it only on networks you trust.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Fila de estado: punto verde/gris, qué pasa ahora y los botones para cambiarlo.
struct StatusRow<Actions: View>: View {
    let on: Bool
    let title: LocalizedStringKey
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(on ? Color.green : Color.secondary.opacity(0.5)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            actions
        }
        .padding(.vertical, 4)
    }
}

/// Dibujo de la ventana del cliente: servidor, ruta y unos archivos.
struct FTPClientPreview: View {
    let enabled: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up"); Image(systemName: "arrow.clockwise")
                Text(verbatim: "192.168.1.10/Fotos").font(.caption.monospaced())
                Spacer()
                Image(systemName: "arrow.up.doc"); Image(systemName: "arrow.down.doc")
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach([("folder.fill", "Vacaciones", "—"), ("doc", "playa.jpg", "2,4 MB"), ("doc", "notas.txt", "3 KB")], id: \.1) { row in
                HStack {
                    Label(row.1, systemImage: row.0).font(.caption)
                    Spacer()
                    Text(row.2).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(enabled ? 1 : 0.3)
        .overlay { if !enabled { Text("Off").font(.headline).foregroundStyle(.secondary) } }
        .animation(.default, value: enabled)
    }
}

/// Dibujo del servidor: estado, dirección para conectarse y permisos.
struct FTPServerPreview: View {
    let running: Bool
    let address: String
    let folder: String
    let readOnly: Bool
    let anonymous: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack").font(.title).foregroundStyle(running ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(running ? "Running" : "Stopped").font(.headline)
                Text(verbatim: address).font(.callout.monospaced()).textSelection(.enabled)
                HStack(spacing: 8) {
                    Label(folder, systemImage: "folder")
                    Label(readOnly ? "Read only" : "Read and write", systemImage: readOnly ? "lock" : "pencil")
                    if anonymous { Label("Anonymous", systemImage: "person.fill.questionmark") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .animation(.default, value: running)
    }
}

/// Pestaña «Servidores» de Ajustes (mismo nombre que el menú): un apartado por protocolo y papel.
/// Protocolo nuevo → «Cliente X» y «Servidor X» aquí.
enum ServersSettings {
    static var pages: [SettingsPage] {
        [
            SettingsPage("ftpClient", "FTP Client", "arrow.down.circle") { FTPSettingsSection(part: "client") },
            SettingsPage("ftpServer", "FTP Server", "server.rack") { FTPSettingsSection(part: "server") },
            SettingsPage("smbClient", "SMB Client", "link") { SMBClientSettingsSection() },
            SettingsPage("smbServer", "SMB Server", "externaldrive.connected.to.line.below") { SMBSettingsSection() },
        ]
    }
}
