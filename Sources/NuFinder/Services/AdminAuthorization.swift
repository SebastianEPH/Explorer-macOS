import Foundation
import Security

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

    static var supportsTouchID: Bool { execute != nil }

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

    /// Ejecuta un guion de shell como administrador. nil = bien; si no, el error.
    static func run(_ script: String) -> String? {
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
