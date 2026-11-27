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
