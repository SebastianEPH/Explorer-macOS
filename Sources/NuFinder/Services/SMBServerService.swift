import AppKit
import SystemConfiguration
import SwiftUI

/// Fork: servidor SMB. No se reimplementa SMB: se usa el de macOS («Compartir archivos», `smbd`),
/// que es el que entienden Windows, Linux, móviles y otros Mac. Explorer lo enciende/apaga y
/// crea o quita carpetas compartidas con `/usr/sbin/sharing`; macOS pide la contraseña de
/// administrador para cada cambio (no se guarda en ningún sitio).
struct SMBShare: Identifiable, Equatable, Sendable {
    var name: String
    var path: String
    var readOnly: Bool
    var guest: Bool
    var id: String { name }
}

enum SMBServer {
    static let showsMenuKey = "menu.showsSMB"

    /// Ejecuta órdenes; en pruebas se sustituye para no tocar el sistema.
    struct Runner: Sendable {
        /// Orden normal → (código de salida, salida).
        var run: @Sendable (_ executable: String, _ arguments: [String]) -> (Int32, String)
        /// Guion de shell con permisos de administrador → nil si fue bien, si no el error.
        var runAsAdmin: @Sendable (_ script: String) -> String?
    }

    nonisolated(unsafe) static var runner = Runner(
        run: { executable, arguments in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return (-1, "") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        },
        runAsAdmin: { script in
            let source = "do shell script \"\(SMBServer.appleScriptEscaped(script))\" with administrator privileges"
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            guard let error else { return nil }
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { return String(localized: "Cancelled") }
            return error[NSAppleScript.errorMessage] as? String ?? String(localized: "Unknown error")
        })

    static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Comillas simples de shell.
    static func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    // MARK: Estado (sin permisos)

    /// ¿Hay algo escuchando en el puerto 445? (lo abre launchd cuando Compartir archivos está activo).
    static func isRunning() -> Bool {
        let (_, output) = runner.run("/usr/sbin/netstat", ["-an", "-p", "tcp"])
        return parseListening(output)
    }

    static func parseListening(_ netstat: String) -> Bool {
        netstat.split(whereSeparator: \.isNewline).contains { line in
            line.contains("LISTEN") && line.split(separator: " ").contains { $0.hasSuffix(".445") }
        }
    }

    static func shares() -> [SMBShare] {
        let (status, output) = runner.run("/usr/sbin/sharing", ["-l", "-f", "json"])
        return status == 0 ? parseShares(output) : []
    }

    static func parseShares(_ json: String) -> [SMBShare] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return object.compactMap { key, value in
            guard (value["smb_shared"] as? Int ?? 0) == 1, let path = value["path"] as? String else { return nil }
            return SMBShare(name: value["smb_name"] as? String ?? key, path: path,
                            readOnly: (value["smb_read_only"] as? Int ?? 0) == 1, guest: (value["smb_guest_access"] as? Int ?? 0) == 1)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Cambios (piden contraseña de administrador)

    private static let smbPlist = "/System/Library/LaunchDaemons/com.apple.smbd.plist"
    private static let serverPrefs = "/Library/Preferences/SystemConfiguration/com.apple.smb.server"

    /// Lo mismo que el interruptor «Compartir archivos» de Ajustes del Sistema.
    static func enableScript() -> String {
        "/bin/launchctl enable system/com.apple.smbd; /bin/launchctl bootstrap system \(smbPlist) 2>/dev/null; "
            + "/usr/bin/defaults write \(serverPrefs) EnabledServices -array disk; true"
    }

    static func disableScript() -> String {
        "/usr/bin/defaults delete \(serverPrefs) EnabledServices 2>/dev/null; "
            + "/bin/launchctl bootout system/com.apple.smbd 2>/dev/null; /bin/launchctl disable system/com.apple.smbd; true"
    }

    static func addScript(path: String, name: String, readOnly: Bool, guest: Bool) -> String {
        "/usr/sbin/sharing -a \(quoted(path)) -n \(quoted(name)) -S \(quoted(name)) -s 001 -g \(guest ? "001" : "000") -R \(readOnly ? 1 : 0)"
    }

    static func removeScript(name: String) -> String { "/usr/sbin/sharing -r \(quoted(name))" }

    static func setEnabled(_ on: Bool) -> String? { runner.runAsAdmin(on ? enableScript() : disableScript()) }

    /// Comparte una carpeta (y enciende el servidor si estaba apagado) con una sola contraseña.
    static func share(path: String, name: String, readOnly: Bool, guest: Bool, startServer: Bool) -> String? {
        var script = addScript(path: path, name: name, readOnly: readOnly, guest: guest)
        if startServer { script = enableScript() + "; " + script }
        return runner.runAsAdmin(script)
    }

    static func unshare(_ share: SMBShare) -> String? { runner.runAsAdmin(removeScript(name: share.name)) }

    /// Direcciones para conectarse desde otro equipo (smb://nombre.local y smb://IP).
    static func addresses() -> [String] {
        let bonjour = (SCDynamicStoreCopyLocalHostName(nil) as String?).map { ["smb://\($0).local"] } ?? []
        return bonjour + FTPSettings.localAddresses().map { "smb://\($0)" }
    }

    static func openSystemSharing() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")!)
    }
}

/// Estado del servidor SMB para menús y Ajustes.
@MainActor
final class SMBServerController: ObservableObject {
    static let shared = SMBServerController()
    @Published private(set) var running = false
    @Published private(set) var shares: [SMBShare] = []
    @Published var message: String?
    @Published private(set) var busy = false
    private var observer: NSObjectProtocol?

    /// Al arrancar y cada vez que se vuelve a Explorer (puede haberse cambiado en Ajustes del Sistema).
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Task { await SMBServerController.shared.refresh() } }
        }
        Task { await refresh() }
    }

    func refresh() async {
        let (isRunning, list) = await Task.detached { (SMBServer.isRunning(), SMBServer.shares()) }.value
        running = isRunning; shares = list
    }

    private func change(_ work: @escaping @Sendable () -> String?) async {
        busy = true
        let error = await Task.detached { work() }.value
        if let error { message = error } else { message = nil }
        busy = false
        await refresh()
    }

    func setRunning(_ on: Bool) async { await change { SMBServer.setEnabled(on) } }

    func share(_ url: URL, readOnly: Bool = false, guest: Bool = false) async {
        let name = url.lastPathComponent, start = !running
        await change { SMBServer.share(path: url.path, name: name, readOnly: readOnly, guest: guest, startServer: start) }
    }

    func unshare(_ share: SMBShare) async { await change { SMBServer.unshare(share) } }
}

/// Menú «SMB»: encender/apagar el servidor de macOS, compartir la carpeta actual, conectarse.
struct SMBMenuItems: View {
    @AppStorage(SMBServer.showsMenuKey) private var showsMenu = true
    @ObservedObject private var server = SMBServerController.shared
    let currentFolder: () -> URL?
    let connect: () -> Void

    var body: some View {
        if showsMenu {
            Menu("SMB") {
                Section("Client") {
                Button("Connect to SMB Server…") { connect() }
                Button("SMB Client Settings…") { SettingsOpener.open(tab: "servers", page: "smbClient") }
                }
                Section("Server") {
                Toggle("SMB Server (macOS File Sharing)", isOn: Binding(
                    get: { server.running }, set: { on in Task { await server.setRunning(on) } }))
                Button("Share Current Folder via SMB") {
                    if let url = currentFolder() { Task { await server.share(url) } }
                }
                .disabled(currentFolder() == nil)
                if !server.shares.isEmpty {
                    Menu("Stop Sharing") {
                        ForEach(server.shares) { share in
                            Button(share.name) { Task { await server.unshare(share) } }
                        }
                    }
                }
                if server.running, let address = SMBServer.addresses().first {
                    Button("Copy Server Address (\(address))") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(address, forType: .string)
                    }
                }
                Button("Refresh Status") { Task { await server.refresh() } }
                Button("SMB Server Settings…") { SettingsOpener.open(tab: "servers", page: "smbServer") }
                }
            }
        }
    }
}

/// Ajustes → Servidores → Servidor SMB.
struct SMBSettingsSection: View {
    @AppStorage(SMBServer.showsMenuKey) private var showsMenu = true
    @ObservedObject private var server = SMBServerController.shared
    @State private var readOnly = false
    @State private var guest = false

    var body: some View {
        Section {
            SettingsPreviewBox(title: "Preview: what other computers connect to") {
                SMBServerPreview(running: server.running, address: SMBServer.addresses().first ?? "smb://", shares: server.shares)
            }
            Toggle(isOn: Binding(get: { server.running }, set: { on in Task { await server.setRunning(on) } })) {
                Label("SMB Server (macOS File Sharing)", systemImage: "externaldrive.connected.to.line.below")
                Text("Windows, Linux, phones and other Macs see your shared folders. Uses the server built into macOS; it asks for your administrator password for each change.")
            }
            .disabled(server.busy)
            if let message = server.message { DisabledReason("\(message)") }
            ForEach(server.shares) { share in
                LabeledContent {
                    Button("Stop Sharing") { Task { await server.unshare(share) } }.disabled(server.busy)
                } label: {
                    Label(share.name, systemImage: "folder.fill.badge.person.crop")
                    Text("\(share.path) · \(share.readOnly ? String(localized: "Read only") : String(localized: "Read and write"))\(share.guest ? " · " + String(localized: "Guests") : "")")
                }
            }
            HStack {
                Toggle("Read only", isOn: $readOnly)
                Toggle("Allow guests", isOn: $guest)
                Spacer()
                Button("Share a Folder…") { chooseFolder() }.disabled(server.busy)
            }
            HStack {
                Text("To log in from Windows, your user needs “Windows File Sharing” turned on in System Settings → Sharing → File Sharing → Options.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open…") { SMBServer.openSystemSharing() }
            }
        }
        .task { await server.refresh() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            let readOnly = readOnly, guest = guest
            Task { await server.share(url, readOnly: readOnly, guest: guest) }
        }
    }
}

struct SMBServerPreview: View {
    let running: Bool
    let address: String
    let shares: [SMBShare]
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below").font(.title)
                .foregroundStyle(running ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(running ? "Running" : "Stopped").font(.headline)
                Text(verbatim: address).font(.callout.monospaced()).textSelection(.enabled)
                ForEach(shares.prefix(4)) { share in
                    Label(share.name, systemImage: share.readOnly ? "lock" : "folder").font(.caption).foregroundStyle(.secondary)
                }
                if shares.isEmpty { Text("No shared folders").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .animation(.default, value: running)
    }
}

/// Menú «Servidores» de la barra de menús: un submenú por protocolo (FTP, SMB…), cada uno con
/// su cliente y su servidor. Protocolo nuevo → su submenú aquí.
struct ServersMenu: Commands {
    static let showsKey = "menu.showsServers"
    /// El mismo nombre en la barra de menús y en la pestaña de Ajustes.
    static let title = "Servers"
    @AppStorage(ServersMenu.showsKey) private var shows = true
    let currentFolder: () -> URL?
    let connectSMB: () -> Void

    var body: some Commands {
        if shows {
            CommandMenu(LocalizedStringKey(ServersMenu.title)) {
                FTPMenuItems(currentFolder: currentFolder)
                SMBMenuItems(currentFolder: currentFolder, connect: connectSMB)
                Divider()
                Button("Server Settings…") { SettingsOpener.open(tab: "servers", page: "ftpClient") }
            }
        }
    }
}

/// Ajustes → Servidores → Cliente SMB: conectarse a carpetas compartidas de otros equipos
/// (el «Conectar al servidor…» del autor) y sus servidores recientes.
struct SMBClientSettingsSection: View {
    static let recentKey = "recentSMBServers" // del autor (BrowserModel)
    @AppStorage(SMBServer.showsMenuKey) private var showsMenu = true
    @State private var recent = UserDefaults.standard.stringArray(forKey: SMBClientSettingsSection.recentKey) ?? []

    var body: some View {
        Section {
            SettingsPreviewBox(title: "Preview: connecting to another computer") {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer").font(.title)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Image(systemName: "externaldrive.connected.to.line.below").font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: recent.first ?? "smb://192.168.1.20/Documentos").font(.callout.monospaced())
                        Text("Opens in an Explorer tab, like any folder").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            LabeledContent {
                Button("Connect to SMB Server…") { KeyWindowFocus.shared.windowBrowser?.requestConnectToServer() }
            } label: {
                Label("Connect", systemImage: "link")
                Text("Opens shared folders from Windows, NAS drives or other Macs. macOS asks for the user and password.")
            }
            ForEach(recent, id: \.self) { address in
                LabeledContent {
                    Button("Forget") {
                        recent.removeAll { $0 == address }
                        UserDefaults.standard.set(recent, forKey: SMBClientSettingsSection.recentKey)
                    }
                } label: { Label(address, systemImage: "clock.arrow.circlepath") }
            }
            if recent.isEmpty { Text("No recent servers").font(.caption).foregroundStyle(.secondary) }
            Toggle(isOn: $showsMenu) {
                Label("SMB in the “Servers” menu", systemImage: "menubar.rectangle")
                Text("Shows the SMB submenu (client and server) in the menu bar.")
            }
        }
    }
}
