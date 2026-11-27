import Foundation
import Security
import SwiftUI

/// Fork: permisos de administrador con el diálogo de autorización de macOS (el de los candados de
/// Ajustes del Sistema), que admite **Touch ID**, en vez de `do shell script … with administrator
/// privileges` de AppleScript, que solo pide la contraseña. La autorización se reutiliza mientras
/// macOS la dé por buena (unos minutos), así no se pide en cada cambio.
enum AdminAuthorization {
    nonisolated(unsafe) private static var authorization: AuthorizationRef?
    private static let lock = NSLock()

    /// `AuthorizationExecuteWithPrivileges` está marcada como no disponible en Swift, pero sigue en
    /// Security.framework: se busca con dlsym. Si no está, se usa AppleScript (contraseña).
    private typealias Execute = @convention(c) (
        AuthorizationRef, UnsafePointer<CChar>, AuthorizationFlags,
        UnsafePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    private static let execute: Execute? = {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
              let symbol = dlsym(handle, "AuthorizationExecuteWithPrivileges") else { return nil }
        return unsafeBitCast(symbol, to: Execute.self)
    }()

    static var supportsTouchID: Bool { sudoUsesTouchID() }

    /// Pide (o reutiliza) el permiso de administrador. nil si se concedió; si no, el motivo.
    private static func authorize() -> (AuthorizationRef?, String?) {
        lock.lock(); defer { lock.unlock() }
        if authorization == nil {
            var ref: AuthorizationRef?
            guard AuthorizationCreate(nil, nil, [], &ref) == errAuthorizationSuccess, let ref else {
                return (nil, String(localized: "Unknown error"))
            }
            authorization = ref
        }
        guard let ref = authorization else { return (nil, String(localized: "Unknown error")) }
        let status: OSStatus = kAuthorizationRightExecute.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCopyRights(ref, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        switch status {
        case errAuthorizationSuccess: return (ref, nil)
        case errAuthorizationCanceled: return (nil, String(localized: "Cancelled"))
        default:
            AuthorizationFree(ref, [])
            authorization = nil
            return (nil, String(localized: "Not authorized"))
        }
    }

    // MARK: Recordar el permiso (no volver a pedirlo)

    /// Encendido = tras el primer Touch ID se instala una regla de sudo solo para las órdenes del
    /// servidor SMB, y después no se vuelve a pedir nada. Apagado = Touch ID cada vez (tras unos minutos).
    static let rememberKey = "admin.remember"
    static let sudoersPath = "/etc/sudoers.d/explorer"
    static var wantsRemember: Bool { UserDefaults.standard.object(forKey: rememberKey) as? Bool ?? true }
    static var isRemembered: Bool { FileManager.default.fileExists(atPath: sudoersPath) }

    /// Solo estas órdenes, solo para este usuario, sin contraseña. Nada más.
    static func sudoersRule(user: String = NSUserName()) -> String {
        let commands = ["/usr/sbin/sharing *"] + SMBServer.launchctlCommands + ["/bin/rm -f \(sudoersPath)"]
        let escaped = commands.map { $0.replacingOccurrences(of: ":", with: "\\:").replacingOccurrences(of: ",", with: "\\,") }
        return "# Explorer: servidor SMB sin volver a pedir permiso (se quita en Ajustes → Red → SMB)\n"
            + "\(user) ALL=(root) NOPASSWD: " + escaped.joined(separator: ", ") + "\n"
    }

    /// Guion (como administrador) que instala la regla, comprobada antes con visudo.
    static func installRuleScript() -> String {
        let temp = "/tmp/explorer-sudoers-\(UUID().uuidString)"
        return "printf '%s' \(SMBServer.quoted(sudoersRule())) > \(temp) && /usr/sbin/visudo -cf \(temp) >/dev/null && "
            + "/usr/bin/install -m 0440 -o root -g wheel \(temp) \(sudoersPath); rm -f \(temp)"
    }

    /// Pedir el permiso ahora (Touch ID) y recordarlo, sin esperar a un cambio.
    static func rememberNow() -> String? { runPrivileged(installRuleScript()) }

    /// Olvidar el permiso recordado.
    static func forget() -> String? {
        guard isRemembered else { return nil }
        let (code, _) = shell("/usr/bin/sudo -n /bin/rm -f \(sudoersPath)")
        return code == 0 ? nil : runPrivileged("/bin/rm -f \(sudoersPath)")
    }

    private static func shell(_ script: String) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        guard (try? process.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Ejecuta un guion con permisos: si están recordados, sin preguntar; si no, Touch ID
    /// (y si se quiere recordar, aprovecha ese mismo Touch ID para instalar la regla).
    static func run(_ script: String) -> String? {
        if isRemembered {
            let (code, output) = shell("SUDO='/usr/bin/sudo -n'; " + script)
            if code == 0 { return nil }
            if !output.contains("password is required") && !output.contains("contraseña") {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // La regla ya no vale (p. ej. cambió el usuario): se pide de nuevo.
        }
        let body = "SUDO=''; " + script + (wantsRemember && !isRemembered ? "; " + installRuleScript() : "")
        return runPrivileged(body)
    }

    /// ¿Touch ID activado para `sudo`? (`auth sufficient pam_tid.so` sin comentar en sudo_local o sudo).
    static func sudoUsesTouchID(_ files: [String] = ["/etc/pam.d/sudo_local", "/etc/pam.d/sudo"]) -> Bool {
        files.contains { file in
            ((try? String(contentsOfFile: file, encoding: .utf8)) ?? "").split(separator: "\n").contains { line in
                let text = line.trimmingCharacters(in: .whitespaces)
                return !text.hasPrefix("#") && text.contains("pam_tid.so")
            }
        }
    }

    /// Ejecuta un guion de shell como administrador. nil = bien; si no, el error.
    /// Primero con `sudo` + Touch ID (si está activado en el Mac); si no, el diálogo de macOS (contraseña).
    static func runPrivileged(_ script: String) -> String? {
        if sudoUsesTouchID() {
            // -S lee la contraseña de /dev/null: si Touch ID falla o se cancela, termina en vez de esperar una terminal.
            let (code, output) = shell("/usr/bin/sudo -S -p '' /bin/sh -c \(SMBServer.quoted(script)) </dev/null")
            if code == 0 { return nil }
            let text = output.lowercased()
            let authFailed = text.contains("password") || text.contains("contraseña") || text.contains("sorry") || text.contains("incorrect")
            if !authFailed { return output.trimmingCharacters(in: .whitespacesAndNewlines) } // falló la orden, no el permiso
        }
        guard let execute else { return runWithAppleScript(script) }
        let (ref, error) = authorize()
        guard let ref else { return error }
        // La salida del guion lleva al final el código de salida, para saber si fue bien.
        let wrapped = "(\(script)) 2>&1; echo \"__EXIT:$?\""
        var pipe: UnsafeMutablePointer<FILE>?
        let status: OSStatus = "/bin/sh".withCString { tool in
            "-c".withCString { flag in
                wrapped.withCString { body in
                    let args: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: flag), UnsafeMutablePointer(mutating: body), nil]
                    return args.withUnsafeBufferPointer { execute(ref, tool, [], $0.baseAddress!, &pipe) }
                }
            }
        }
        guard status == errAuthorizationSuccess else {
            return status == errAuthorizationCanceled ? String(localized: "Cancelled") : String(localized: "Not authorized")
        }
        var output = ""
        if let pipe {
            var buffer = [CChar](repeating: 0, count: 4096)
            while fgets(&buffer, Int32(buffer.count), pipe) != nil { output += String(cString: buffer) }
            fclose(pipe)
        }
        guard let range = output.range(of: "__EXIT:", options: .backwards) else { return nil }
        let code = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let message = output[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return code == "0" ? nil : (message.isEmpty ? "Error \(code)" : message)
    }

    private static func runWithAppleScript(_ script: String) -> String? {
        let source = "do shell script \"\(SMBServer.appleScriptEscaped(script))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return String(localized: "Cancelled") }
        return error[NSAppleScript.errorMessage] as? String ?? String(localized: "Unknown error")
    }
}

/// Fila «Permiso de administrador» de Ajustes → Sistema → Permisos (mismo formato que las demás):
/// estado, «Solicitar» (Touch ID ya y queda recordado) y «Olvidar»; debajo, el interruptor «Recordar».
struct AdminPermissionRow: View {
    @AppStorage(AdminAuthorization.rememberKey) private var remember = true
    @State private var remembered = AdminAuthorization.isRemembered
    @State private var message: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: remembered ? "checkmark.circle.fill" : (AdminAuthorization.supportsTouchID ? "touchid" : "lock.fill"))
                .foregroundStyle(remembered ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Administrator")
                Text(remembered ? "Remembered: Explorer won’t ask again (SMB server: turn on/off and share folders)."
                                : AdminAuthorization.supportsTouchID
                                    ? "Needed to turn the SMB server on/off and share folders. Press Request and use Touch ID once."
                                    : "Needed to turn the SMB server on/off and share folders. Press Request and type your password once (Touch ID for sudo is off on this Mac).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Remember (don’t ask again)", isOn: $remember).font(.caption).toggleStyle(.checkbox)
                if let message { DisabledReason("\(message)") }
            }
            Spacer()
            if remembered {
                Button("Forget") { message = AdminAuthorization.forget(); remembered = AdminAuthorization.isRemembered }
            } else {
                Button("Request") {
                    Task.detached {
                        let error = AdminAuthorization.rememberNow()
                        await MainActor.run { message = error; remembered = AdminAuthorization.isRemembered }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            remembered = AdminAuthorization.isRemembered
        }
    }
}

/// Fila «Llavero» de Ajustes → Sistema → Permisos: las contraseñas de FTP guardadas por Explorer.
/// Explorer nunca provoca avisos al leerlas; si macOS pide permiso, se concede desde aquí.
struct KeychainPermissionRow: View {
    @State private var ok = true
    @State private var count = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keychain (FTP passwords)")
                Text(ok ? (count == 0 ? "No saved passwords yet." : "Explorer can read its \(count) saved passwords without asking.")
                        : "macOS asks before Explorer reads some saved passwords. Press Request and choose “Always Allow”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok {
                Button("Request") {
                    DispatchQueue.global(qos: .userInitiated).async {
                        FTPSecrets.requestPermission()
                        refresh()
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let granted = FTPSecrets.hasPermission(), total = FTPSecrets.accounts().count
            DispatchQueue.main.async { ok = granted; count = total }
        }
    }
}
