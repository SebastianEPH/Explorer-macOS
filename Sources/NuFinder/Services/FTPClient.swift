import Foundation
import Security

/// Fork: cliente FTP. Usa `curl` (viene con macOS y habla FTP/FTPS); la contraseña se le pasa
/// por la entrada estándar, nunca en la línea de órdenes (se vería con `ps`).
struct FTPEntry: Identifiable, Hashable, Sendable {
    var name: String
    var isDirectory: Bool
    var size: Int64
    var modified: String
    var id: String { name }
}

struct FTPServerAddress: Codable, Hashable, Identifiable, Sendable {
    var host: String
    var port: Int = 21
    var user: String = ""
    var anonymous = false
    var id: String { "\(user)@\(host):\(port)" }
}

enum FTPClientError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): message }
    }
}

struct FTPClient: Sendable {
    var address: FTPServerAddress
    var password: String
    /// Ejecutable de curl (se cambia en pruebas si hiciera falta).
    nonisolated(unsafe) static var curlPath = "/usr/bin/curl"

    /// URL de una ruta remota («/a/b c»), con cada parte codificada.
    func url(_ path: String, directory: Bool = false) -> String {
        let encoded = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: "/?#;"))) ?? String($0)
        }.joined(separator: "/")
        let host = address.host.contains(":") && !address.host.hasPrefix("[") ? "[\(address.host)]" : address.host
        // «//» tras el puerto = ruta absoluta desde la raíz del servidor (no desde la carpeta del usuario).
        return "ftp://\(host):\(address.port)/%2F\(encoded)\(directory && !encoded.isEmpty ? "/" : "")"
            .replacingOccurrences(of: "/%2F/", with: "/%2F")
    }

    func list(_ path: String) async throws -> [FTPEntry] {
        let output = try await run([url(path, directory: true)])
        return FTPClient.parse(String(decoding: output, as: UTF8.self))
            .filter { $0.name != "." && $0.name != ".." }
            .sorted { ($0.isDirectory ? 0 : 1, $0.name.lowercased()) < ($1.isDirectory ? 0 : 1, $1.name.lowercased()) }
    }

    func download(_ path: String, to local: URL) async throws {
        _ = try await run([url(path), "-o", local.path])
    }

    func upload(_ local: URL, toDirectory directory: String) async throws {
        let remote = (directory.hasSuffix("/") ? directory : directory + "/") + local.lastPathComponent
        _ = try await run(["-T", local.path, url(remote)])
    }

    func makeDirectory(_ path: String) async throws { try await quote(["MKD \(path)"], in: parent(path)) }
    func delete(_ path: String, isDirectory: Bool) async throws {
        try await quote([isDirectory ? "RMD \(path)" : "DELE \(path)"], in: parent(path))
    }
    func rename(_ path: String, to newPath: String) async throws {
        try await quote(["RNFR \(path)", "RNTO \(newPath)"], in: parent(path))
    }

    private func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }

    /// Órdenes FTP sueltas (curl las manda tras iniciar sesión); el listado que sigue se descarta.
    private func quote(_ commands: [String], in directory: String) async throws {
        var arguments = [url(directory, directory: true), "-o", "/dev/null"]
        for command in commands { arguments += ["-Q", command] }
        _ = try await run(arguments)
    }

    private func run(_ arguments: [String]) async throws -> Data {
        let user = address.anonymous ? "anonymous:explorer@" : "\(address.user):\(password)"
        let config = "user = \"\(user.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FTPClient.curlPath)
        process.arguments = ["--silent", "--show-error", "--connect-timeout", "10", "--ftp-pasv", "-K", "-"] + arguments
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    input.fileHandleForWriting.write(Data(config.utf8))
                    try? input.fileHandleForWriting.close()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    let message = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: data)
                    } else {
                        let text = String(decoding: message, as: UTF8.self).replacingOccurrences(of: "curl: ", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: FTPClientError.failed(text.isEmpty ? "Error \(process.terminationStatus)" : text))
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Entiende listados Unix (`ls -l`) y de Windows/IIS (`11-27-26 10:00AM <DIR> nombre`).
    static func parse(_ text: String) -> [FTPEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw)
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if let first = line.first, "-dl".contains(first), fields.count >= 9 {
                // Nombre = todo tras la hora/año (puede llevar espacios).
                var index = line.startIndex
                for _ in 0..<8 {
                    index = line[index...].firstIndex(where: { $0 != " " }) ?? line.endIndex
                    index = line[index...].firstIndex(of: " ") ?? line.endIndex
                }
                var name = String(line[index...].drop(while: { $0 == " " }))
                if first == "l", let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
                return FTPEntry(name: name, isDirectory: first == "d", size: Int64(fields[4]) ?? 0,
                                modified: fields[5...7].joined(separator: " "))
            }
            if fields.count >= 4, fields[0].contains("-"), fields[1].contains(":") {
                let isDirectory = fields[2] == "<DIR>"
                return FTPEntry(name: fields[3...].joined(separator: " "), isDirectory: isDirectory,
                                size: isDirectory ? 0 : Int64(fields[2]) ?? 0, modified: "\(fields[0]) \(fields[1])")
            }
            return nil
        }
    }
}

/// Contraseñas FTP en el Llavero (nunca en UserDefaults). En pruebas se usa un almacén en memoria.
enum FTPSecrets {
    nonisolated(unsafe) static var memory: [String: String]? // pruebas
    private static let service = "Explorer FTP"

    /// Lee sin mostrar avisos de macOS (si hace falta permiso, devuelve nil y lo apunta en
    /// `needsPermission`; se concede en Ajustes → Sistema → Permisos → Llavero).
    static func password(for account: String, interactive: Bool = false) -> String? {
        if let memory { return memory[account] }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        if !interactive { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecInteractionRequired {
            needsPermission = true; return nil
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated(unsafe) static var needsPermission = false

    /// El Llavero clásico (donde están estas contraseñas) ignora `kSecUseAuthenticationUIFail`:
    /// la única forma de que macOS nunca muestre «Explorer quiere usar…» es desactivar los avisos
    /// del proceso. Se llama al arrancar; solo «Solicitar» (Sistema → Permisos) los reactiva un momento.
    static func silenceKeychainPrompts() {
        SecKeychainSetUserInteractionAllowed(false)
    }

    /// Cuentas guardadas de Explorer en el Llavero (solo nombres, sin leer contraseñas: no avisa).
    static func accounts() -> [String] {
        if let memory { return Array(memory.keys) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    /// ¿Explorer puede leer todas sus contraseñas sin que macOS pregunte?
    static func hasPermission() -> Bool {
        needsPermission = false
        for account in accounts() { _ = password(for: account) }
        return !needsPermission
    }

    /// Pide el permiso ahora: macOS pregunta por cada contraseña que no puede leer
    /// (pulsar «Permitir siempre» y no vuelve a salir).
    static func requestPermission() {
        SecKeychainSetUserInteractionAllowed(true)
        defer { SecKeychainSetUserInteractionAllowed(false) }
        for account in accounts() { _ = password(for: account, interactive: true) }
    }

    /// Guarda o borra sin mostrar nunca avisos de macOS. Si la contraseña existente no se puede
    /// tocar sin permiso, no se hace nada y queda marcado para Sistema → Permisos → Llavero.
    static func setPassword(_ password: String?, for account: String) {
        if memory != nil { memory?[account] = password; return }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        var quiet = base
        quiet[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        guard let password, !password.isEmpty else {
            let status = SecItemDelete(quiet as CFDictionary)
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecInteractionRequired { needsPermission = true }
            return
        }
        let data = Data(password.utf8)
        let status = SecItemUpdate(quiet as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        } else if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecInteractionRequired {
            needsPermission = true
        }
    }
}
