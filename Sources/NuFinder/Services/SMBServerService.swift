import AppKit
import NetFS
import OpenDirectory
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
        /// El de verdad (no el de las pruebas).
        var isDefault = false
    }

    /// ¿Algo escucha en ese puerto de este Mac? Conexión TCP a 127.0.0.1 con 1 s de espera.
    static func portIsOpen(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pollfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pollfd, 1, 1000) > 0 else { return false }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
        return error == 0
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
        runAsAdmin: { script in AdminAuthorization.run(script) }, // Fork: Touch ID (sudo) o contraseña, recordado
        isDefault: true)

    static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Comillas simples de shell.
    static func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    // MARK: Estado (sin permisos)

    /// ¿Hay algo escuchando en el puerto 445? (lo abre launchd cuando Compartir archivos está activo).
    static func isRunning() -> Bool {
        // Dentro de la app `netstat` devolvía 0 bytes (siempre «Detenido»): se intenta conectar al 445.
        if runner.isDefault { return portIsOpen(445) }
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
    // Cada orden privilegiada va precedida de `$SUDO`: vacío cuando el guion ya corre como
    // administrador (Touch ID) y `sudo -n` cuando el permiso está recordado (`AdminAuthorization`).
    static let launchctlCommands = ["/bin/launchctl enable system/com.apple.smbd",
                                    "/bin/launchctl bootstrap system \(smbPlist)",
                                    "/bin/launchctl bootout system/com.apple.smbd",
                                    "/bin/launchctl disable system/com.apple.smbd",
                                    "/usr/bin/defaults write \(serverPrefs) EnabledServices -array disk",
                                    "/usr/bin/defaults delete \(serverPrefs) EnabledServices"]

    static func enableScript() -> String {
        "$SUDO /bin/launchctl enable system/com.apple.smbd; $SUDO /bin/launchctl bootstrap system \(smbPlist) 2>/dev/null; "
            + "$SUDO /usr/bin/defaults write \(serverPrefs) EnabledServices -array disk; true"
    }

    static func disableScript() -> String {
        "$SUDO /usr/bin/defaults delete \(serverPrefs) EnabledServices 2>/dev/null; "
            + "$SUDO /bin/launchctl bootout system/com.apple.smbd 2>/dev/null; $SUDO /bin/launchctl disable system/com.apple.smbd; true"
    }

    static func addScript(path: String, name: String, readOnly: Bool, guest: Bool) -> String {
        "$SUDO /usr/sbin/sharing -a \(quoted(path)) -n \(quoted(name)) -S \(quoted(name)) -s 001 -g \(guest ? "001" : "000") -R \(readOnly ? 1 : 0)"
    }

    static func removeScript(name: String) -> String { "$SUDO /usr/sbin/sharing -r \(quoted(name))" }

    /// Cambiar permisos de una carpeta ya compartida (sin dejar de compartirla).
    static func editScript(name: String, readOnly: Bool, guest: Bool) -> String {
        "$SUDO /usr/sbin/sharing -e \(quoted(name)) -s 001 -g \(guest ? "001" : "000") -R \(readOnly ? 1 : 0)"
    }

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

    private var lastRefresh = Date.distantPast
    private var refreshing = false

    /// Solo publica si algo cambió (publicar siempre rehacía los menús en bucle y colgaba la app)
    /// y como mucho una vez cada 2 s, salvo `force` (tras encender, apagar o compartir).
    func refresh(force: Bool = false) async {
        // Una comprobación pedida tras un cambio nunca se salta: espera a la que esté en marcha.
        while force && refreshing { try? await Task.sleep(for: .milliseconds(100)) }
        guard !refreshing, force || Date().timeIntervalSince(lastRefresh) > 2 else { return }
        refreshing = true; defer { refreshing = false; lastRefresh = Date() }
        let (isRunning, list) = await Task.detached { (SMBServer.isRunning(), SMBServer.shares()) }.value
        if running != isRunning { running = isRunning }
        if shares != list { shares = list }
    }

    private func change(_ work: @escaping @Sendable () -> String?) async {
        busy = true
        let error = await Task.detached { work() }.value
        if let error { message = error } else { message = nil }
        busy = false
        await refresh(force: true)
    }

    /// Enciende o apaga y espera a ver el cambio (macOS tarda un poco en abrir/cerrar el puerto).
    func setRunning(_ on: Bool) async {
        await change { SMBServer.setEnabled(on) }
        guard message == nil else { return }
        busy = true; defer { busy = false } // los botones siguen bloqueados mientras se espera el cambio
        for _ in 0..<16 where running != on {
            try? await Task.sleep(for: .milliseconds(500))
            await refresh(force: true)
        }
        if running != on {
            message = on ? String(localized: "macOS didn’t start the SMB server.") : String(localized: "macOS didn’t stop the SMB server.")
        }
    }

    func share(_ url: URL, readOnly: Bool = false, guest: Bool = false) async {
        // Invitados en una carpeta que en el disco solo abre su dueño no sirven: se comparte sin ellos.
        let guest = guest && SMBShare.guestsCanRead(url.path)
        let name = url.lastPathComponent, start = !running
        await change { SMBServer.share(path: url.path, name: name, readOnly: readOnly, guest: guest, startServer: start) }
    }

    func unshare(_ share: SMBShare) async { await change { SMBServer.unshare(share) } }

    /// Quita «invitados» de las carpetas que los invitados no pueden abrir en el disco.
    func fixGuestsWithoutAccess() async {
        for item in shares where item.guest && !item.guestsCanRead {
            await update(item, readOnly: item.readOnly, guest: false)
        }
    }

    func update(_ share: SMBShare, readOnly: Bool, guest: Bool) async {
        let guest = guest && share.guestsCanRead
        let script = SMBServer.editScript(name: share.name, readOnly: readOnly, guest: guest)
        await change { SMBServer.runner.runAsAdmin(script) }
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

/// Cuentas de este Mac que pueden entrar por SMB (las de personas: UID ≥ 501, no ocultas).
enum SMBUsers {
    /// `canUseSMB`: tiene activado «Compartir archivos de Windows» (contraseña SMB/NTLM). Sin eso,
    /// iPhone, Android y Windows no pueden entrar con ese usuario (solo como invitado).
    struct User: Sendable { let name: String; let fullName: String; let isAdmin: Bool; let canUseSMB: Bool }

    /// Permitir (o quitar) que un usuario entre desde iPhone, Android o Windows: lo mismo que la casilla
    /// «Compartir Archivos Windows» de Ajustes del Sistema. Pide su contraseña una vez (no se guarda):
    /// 1) se comprueba, 2) se activa el formato SMB-NT (administrador, ya recordado),
    /// 3) se vuelve a poner la misma contraseña con Open Directory (como el propio usuario, así no se
    /// desajustan el llavero ni FileVault) para que macOS genere ese formato.
    static func setSMBAccess(_ on: Bool, user: String, password: String) -> String? {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: user, attributes: nil)
            do { try record.verifyPassword(password) } catch { return String(localized: "Wrong password.") }
            let quoted = SMBServer.quoted(user)
            if let error = SMBServer.runner.runAsAdmin("$SUDO /usr/bin/pwpolicy -u \(quoted) -sethashtypes SMB-NT \(on ? "on" : "off")") {
                return error
            }
            try record.changePassword(password, toPassword: password)
        } catch { return error.localizedDescription }
        cache = nil
        return list().first { $0.name == user }?.canUseSMB == on ? nil : String(localized: "macOS didn’t apply the change.")
    }

    /// Prueba de verdad: inicia sesión en este Mac por SMB con ese usuario y contraseña (como un iPhone)
    /// y comprueba que ve la carpeta compartida. Con `smbutil view` (montar el propio Mac con NetFS da
    /// «No route to host»). La contraseña va en la dirección (`//usuario:clave@IP`) y solo se ve en la
    /// lista de procesos de este Mac durante la fracción de segundo que dura la prueba.
    static func testLogin(user: String, password: String, share: String) -> String? {
        let host = FTPSettings.localAddresses().first ?? "127.0.0.1"
        let allowed = CharacterSet.alphanumerics
        let u = user.addingPercentEncoding(withAllowedCharacters: allowed) ?? user
        let p = password.addingPercentEncoding(withAllowedCharacters: allowed) ?? password
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        process.arguments = ["view", "//\(u):\(p)@\(host)"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "smbutil" }
        let deadline = DispatchTime.now() + 15
        let group = DispatchGroup(); group.enter()
        var text = ""
        DispatchQueue.global().async { text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); group.leave() }
        if group.wait(timeout: deadline) == .timedOut { process.terminate(); return String(localized: "The server didn’t answer.") }
        process.waitUntilExit()
        if text.localizedCaseInsensitiveContains("authentication") { return String(localized: "The server refused the user or password.") }
        guard process.terminationStatus == 0 else { return text.replacingOccurrences(of: "smbutil: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return text.contains(share) ? nil : String(localized: "Logged in, but the folder isn’t shared with this user.")
    }

    /// Se lee una vez (dscl tarda); al volver a Ajustes se vuelve a leer.
    nonisolated(unsafe) private static var cache: (date: Date, users: [User])?
    static func list() -> [User] {
        if let cache, Date().timeIntervalSince(cache.date) < 30 { return cache.users }
        let users = read()
        cache = (Date(), users)
        return users
    }

    private static func read() -> [User] {
        let admins = Set(output("/usr/bin/dscl", [".", "-read", "/Groups/admin", "GroupMembership"])
            .replacingOccurrences(of: "GroupMembership:", with: "").split(separator: " ").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
        return output("/usr/bin/dscl", [".", "-list", "/Users", "UniqueID"]).split(separator: "\n").compactMap { line -> User? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, let uid = Int(parts[1]), uid >= 501, !parts[0].hasPrefix("_") else { return nil }
            let name = String(parts[0])
            let full = output("/usr/bin/dscl", [".", "-read", "/Users/\(name)", "RealName"])
                .replacingOccurrences(of: "RealName:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hashes = output("/usr/bin/pwpolicy", ["-u", name, "-gethashtypes"])
            return User(name: name, fullName: full.isEmpty ? name : full, isAdmin: admins.contains(name),
                        canUseSMB: hashes.contains("SMB-NT"))
        }
    }

    private static func output(_ tool: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

extension SMBShare {
    /// ¿Un invitado (usuario «nobody») puede leer la carpeta en el disco? Si no, verá «contenido no disponible».
    var guestsCanRead: Bool { SMBShare.guestsCanRead(path) }

    static func guestsCanRead(_ path: String) -> Bool {
        guard let mode = (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int else { return false }
        return mode & 0o005 == 0o005
    }
}
