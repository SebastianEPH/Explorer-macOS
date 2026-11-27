import Combine
import Foundation

/// Fork: toda la configuración de «Red» en un archivo legible: `~/.explorer/red.json`
/// (servidores guardados y la carpeta que compartes). Las contraseñas NO van aquí: van al
/// Llavero de macOS (`FTPSecrets`). Se puede abrir, copiar o respaldar a mano.
struct SavedServer: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case ftp, smb }
    /// Identificador fijo (no cambia al editar): la contraseña del Llavero va con él.
    var key = UUID().uuidString
    var kind: Kind = .smb
    var host: String
    var port: Int = 445
    var user: String = ""
    var anonymous = false
    /// SMB: carpeta compartida del otro equipo («Fotos»). FTP: carpeta inicial («/»).
    var path: String = ""
    var name: String = ""

    var id: String { key }
    /// Mismo destino (para no repetir un servidor en la lista); no mira el nombre ni la clave.
    var target: String { "\(kind.rawValue)://\(user)@\(host):\(port)/\(path)" }
    static func == (a: SavedServer, b: SavedServer) -> Bool { a.target == b.target && a.anonymous == b.anonymous && a.name == b.name }
    func hash(into hasher: inout Hasher) { hasher.combine(target) }
    var title: String { host.isEmpty && name.isEmpty ? String(localized: "New connection") : name.isEmpty ? (user.isEmpty || anonymous ? host : "\(user)@\(host)") : name }
    static func defaultPort(_ kind: Kind) -> Int { kind == .ftp ? 21 : 445 }

    init(kind: Kind = .smb, host: String, port: Int? = nil, user: String = "", anonymous: Bool = false, path: String = "", name: String = "") {
        self.kind = kind; self.host = host; self.port = port ?? SavedServer.defaultPort(kind)
        self.user = user; self.anonymous = anonymous; self.path = path; self.name = name
    }

    init(from decoder: Decoder) throws { // tolera archivos editados a mano con campos de menos
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? UUID().uuidString
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .smb
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? SavedServer.defaultPort(kind)
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        anonymous = try c.decodeIfPresent(Bool.self, forKey: .anonymous) ?? false
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    /// Lo que escribe la persona en «Dirección» → servidor. `ftp://` = FTP; lo demás
    /// (IP, nombre, `smb://`, `\\equipo\carpeta` de Windows) = SMB.
    static func parse(_ input: String, kind forced: Kind? = nil) -> SavedServer? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("\\\\") { text = "smb://" + text.dropFirst(2).replacingOccurrences(of: "\\", with: "/") }
        if !text.contains("://") { text = "\(forced?.rawValue ?? "smb")://" + text }
        guard let components = URLComponents(string: text), let host = components.host, !host.isEmpty else { return nil }
        let kind = forced ?? (components.scheme?.lowercased() == "ftp" ? .ftp : .smb)
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return SavedServer(kind: kind, host: host, port: components.port, user: components.user ?? "", path: path)
    }

    var ftpAddress: FTPServerAddress { FTPServerAddress(host: host, port: port, user: user, anonymous: anonymous) }
}

struct NetworkConfig: Codable, Equatable, Sendable {
    /// La carpeta que compartes desde este Mac (servidor FTP propio de Explorer).
    struct Share: Codable, Equatable, Sendable {
        var enabled = false
        var folder = ""
        var port = 2121
        var user = NSUserName()
        var anonymous = false
        var readOnly = true
        var localOnly = false

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? ""
            port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 2121
            user = try c.decodeIfPresent(String.self, forKey: .user) ?? NSUserName()
            anonymous = try c.decodeIfPresent(Bool.self, forKey: .anonymous) ?? false
            readOnly = try c.decodeIfPresent(Bool.self, forKey: .readOnly) ?? true
            localOnly = try c.decodeIfPresent(Bool.self, forKey: .localOnly) ?? false
        }
        var folderPath: String { folder.isEmpty ? NSHomeDirectory() : folder }
    }

    var servers: [SavedServer] = []
    var share = Share()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        servers = try c.decodeIfPresent([SavedServer].self, forKey: .servers) ?? []
        share = try c.decodeIfPresent(Share.self, forKey: .share) ?? Share()
    }
}

@MainActor
final class NetworkStore: ObservableObject {
    /// Solo la app instalada usa `~/.explorer/red.json`; pruebas y `swift run` usan uno temporal.
    static let shared = NetworkStore(file: DefaultSettings.isInstalledApp ? NetworkStore.defaultFile
        : FileManager.default.temporaryDirectory.appendingPathComponent("explorer-tests-\(ProcessInfo.processInfo.processIdentifier)/red.json"))
    nonisolated static let defaultFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".explorer/red.json")

    let file: URL
    @Published var config: NetworkConfig { didSet { if config != oldValue { save() } } }

    init(file: URL, legacy: UserDefaults = .standard) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(NetworkConfig.self, from: data) {
            config = saved
        } else {
            // Primera vez: se pasa lo de versiones anteriores al archivo y se borra de UserDefaults.
            config = NetworkStore.migrate(legacy)
            save()
            for key in NetworkStore.legacyKeys { legacy.removeObject(forKey: key) }
        }
    }

    static let legacyKeys = ["ftp.server.enabled", "ftp.server.root", "ftp.server.port", "ftp.server.user",
                             "ftp.server.anonymous", "ftp.server.readOnly", "ftp.server.localOnly", "ftp.client.servers",
                             "ftp.client.enabled", "menu.showsFTP", "menu.showsSMB", "menu.showsServers"]

    /// Lo que guardaban las versiones anteriores en UserDefaults (servidor FTP y servidores guardados).
    static func migrate(_ d: UserDefaults) -> NetworkConfig {
        var config = NetworkConfig()
        config.share.enabled = d.bool(forKey: "ftp.server.enabled")
        config.share.folder = d.string(forKey: "ftp.server.root") ?? ""
        config.share.port = d.object(forKey: "ftp.server.port") as? Int ?? 2121
        config.share.user = d.string(forKey: "ftp.server.user") ?? NSUserName()
        config.share.anonymous = d.bool(forKey: "ftp.server.anonymous")
        config.share.readOnly = d.object(forKey: "ftp.server.readOnly") as? Bool ?? true
        config.share.localOnly = d.bool(forKey: "ftp.server.localOnly")
        if let data = d.data(forKey: "ftp.client.servers"),
           let old = try? JSONDecoder().decode([FTPServerAddress].self, from: data) {
            config.servers = old.map { SavedServer(kind: .ftp, host: $0.host, port: $0.port, user: $0.user, anonymous: $0.anonymous) }
        }
        return config
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// Guarda (o sube al principio) un servidor usado.
    func remember(_ server: SavedServer) {
        var server = server
        if let existing = config.servers.first(where: { $0.key == server.key || $0.target == server.target }) {
            server.key = existing.key
            if server.name.isEmpty { server.name = existing.name }
        }
        var list = config.servers.filter { $0.key != server.key }
        list.insert(server, at: 0)
        config.servers = Array(list.prefix(30))
    }

    func forget(_ server: SavedServer) {
        config.servers.removeAll { $0.key == server.key }
        FTPSecrets.setPassword(nil, for: server.id)
    }
}
