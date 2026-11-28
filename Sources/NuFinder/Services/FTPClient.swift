import CryptoKit
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

/// Contraseñas de Red (conexiones FTP y usuarios de mi servidor FTP), cifradas con AES-GCM en
/// `~/.explorer/secretos` con la clave en `~/.explorer/.clave`, ambos solo legibles por tu usuario
/// (0600), como las claves de `~/.ssh`. **No se usa el Llavero**: su ventana no admite Touch ID,
/// salía sola y volvía tras cada actualización. En pruebas, `memory`.
enum FTPSecrets {
    nonisolated(unsafe) static var memory: [String: String]? // pruebas
    nonisolated(unsafe) static var directory: URL = {
        DefaultSettings.isInstalledApp ? NetworkStore.defaultFile.deletingLastPathComponent()
            : FileManager.default.temporaryDirectory.appendingPathComponent("explorer-tests-\(ProcessInfo.processInfo.processIdentifier)")
    }()
    private static let lock = NSLock()
    /// Ya no hay permisos que pedir (se queda por compatibilidad con la fila de Permisos).
    nonisolated(unsafe) static var needsPermission = false

    static var secretsFile: URL { directory.appendingPathComponent("secretos") }
    private static var keyFile: URL { directory.appendingPathComponent(".clave") }

    private static func key() -> SymmetricKey? {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: keyFile), data.count == 32 { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = key.withUnsafeBytes { Data($0) }
        guard fm.createFile(atPath: keyFile.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return nil }
        return key
    }

    private static func load() -> [String: String] {
        guard let sealed = try? Data(contentsOf: secretsFile), let key = key(),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key),
              let dict = try? JSONDecoder().decode([String: String].self, from: plain) else { return [:] }
        return dict
    }

    private static func save(_ dict: [String: String]) {
        guard let key = key(), let plain = try? JSONEncoder().encode(dict),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? sealed.write(to: secretsFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsFile.path)
    }

    static func password(for account: String, interactive: Bool = false) -> String? {
        if let memory { return memory[account] }
        lock.lock(); defer { lock.unlock() }
        return load()[account]
    }

    static func setPassword(_ password: String?, for account: String) {
        if memory != nil { memory?[account] = password; return }
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        if let password, !password.isEmpty { dict[account] = password } else { dict[account] = nil }
        save(dict)
    }

    static func accounts() -> [String] {
        if let memory { return Array(memory.keys) }
        lock.lock(); defer { lock.unlock() }
        return Array(load().keys)
    }

    /// ¿Los archivos solo los puede leer tu usuario? (para la fila de Permisos)
    static func filesArePrivate() -> Bool {
        [secretsFile, keyFile].allSatisfy { url in
            guard let perms = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int else { return true }
            return perms & 0o077 == 0
        }
    }
}
