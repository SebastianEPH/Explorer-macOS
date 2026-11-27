import AppKit
import Foundation
import Testing
@testable import NuFinder

/// Cliente y servidor FTP.
@Suite(.serialized)
struct FTPTests {
    private func folder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FTP-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func server(root: URL, readOnly: Bool = false, anonymous: Bool = false) async throws -> (FTPServer, FTPClient) {
        let server = FTPServer(config: .init(port: 0, root: root, user: "ana", password: "s3cr\"et", anonymous: anonymous, readOnly: readOnly, localOnly: true))
        guard case .running(let port) = await server.start() else { Issue.record("no arrancó: \(server.state)"); throw CancellationError() }
        let client = FTPClient(address: .init(host: "127.0.0.1", port: Int(port), user: "ana"), password: "s3cr\"et")
        return (server, client)
    }

    // MARK: unitarias

    @Test func pathsNeverLeaveTheSharedFolder() throws {
        #expect(FTPPath.virtual(cwd: "/a/b", argument: "../c") == "/a/c")
        #expect(FTPPath.virtual(cwd: "/a", argument: "../../../etc") == "/etc")
        #expect(FTPPath.virtual(cwd: "/a", argument: "/x/./y") == "/x/y")
        let root = try folder("paths")
        #expect(FTPPath.resolve(root: root, virtual: "/etc")?.path == root.appendingPathComponent("etc").path)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("fuera"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        #expect(FTPPath.resolve(root: root, virtual: "/fuera") == nil)
        #expect(FTPPath.resolve(root: root, virtual: "/fuera/passwd") == nil)
    }

    @Test func listingRoundTrip() {
        let now = Date()
        let line = FTPListing.line(name: "mi archivo.txt", isDirectory: false, size: 1234, modified: now, now: now)
        let dir = FTPListing.line(name: "Fotos", isDirectory: true, size: 0, modified: Date(timeIntervalSince1970: 0), now: now)
        let parsed = FTPClient.parse(line + "\r\n" + dir + "\r\n")
        #expect(parsed.map(\.name) == ["mi archivo.txt", "Fotos"])
        #expect(parsed[0].size == 1234 && !parsed[0].isDirectory && parsed[1].isDirectory)
        let windows = FTPClient.parse("11-27-26  10:00AM       <DIR>          Mis Docs\r\n11-27-26  10:01AM                 42 a b.txt")
        #expect(windows == [FTPEntry(name: "Mis Docs", isDirectory: true, size: 0, modified: "11-27-26 10:00AM"),
                            FTPEntry(name: "a b.txt", isDirectory: false, size: 42, modified: "11-27-26 10:01AM")])
    }

    @Test func clientURLsAreEncoded() {
        let client = FTPClient(address: .init(host: "example.com", port: 2121), password: "")
        #expect(client.url("/") == "ftp://example.com:2121/%2F")
        #expect(client.url("/a b/c#d.txt") == "ftp://example.com:2121/%2Fa%20b/c%23d.txt")
        #expect(client.url("/dir", directory: true) == "ftp://example.com:2121/%2Fdir/")
    }

    // MARK: completas (servidor de verdad + curl)

    @Test func clientAndServerTransferFiles() async throws {
        let root = try folder("root")
        try Data("hola".utf8).write(to: root.appendingPathComponent("saludo.txt"))
        let (server, client) = try await server(root: root)
        defer { server.stop() }

        #expect(try await client.list("/").map(\.name) == ["saludo.txt"])
        let local = try folder("local")
        try await client.download("/saludo.txt", to: local.appendingPathComponent("bajado.txt"))
        #expect(try String(contentsOf: local.appendingPathComponent("bajado.txt"), encoding: .utf8) == "hola")

        try await client.makeDirectory("/Nueva carpeta")
        let big = local.appendingPathComponent("grande.bin")
        try Data((0..<3_000_000).map { UInt8($0 % 251) }).write(to: big)
        try await client.upload(big, toDirectory: "/Nueva carpeta")
        #expect(try Data(contentsOf: root.appendingPathComponent("Nueva carpeta/grande.bin")) == Data(contentsOf: big))
        let listed = try await client.list("/")
        #expect(listed.map(\.name) == ["Nueva carpeta", "saludo.txt"] && listed[0].isDirectory)

        try await client.rename("/saludo.txt", to: "/adios.txt")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("adios.txt").path))
        try await client.delete("/adios.txt", isDirectory: false)
        try await client.delete("/Nueva carpeta/grande.bin", isDirectory: false)
        try await client.delete("/Nueva carpeta", isDirectory: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func readOnlyAndWrongPasswordAreRefused() async throws {
        let root = try folder("ro")
        let (server, client) = try await server(root: root, readOnly: true)
        defer { server.stop() }
        await #expect(throws: (any Error).self) { try await client.makeDirectory("/x") }
        var wrong = client; wrong.password = "mal"
        await #expect(throws: (any Error).self) { _ = try await wrong.list("/") }
        var anonymous = client; anonymous.address.anonymous = true
        await #expect(throws: (any Error).self) { _ = try await anonymous.list("/") }
        #expect(try await client.list("/").isEmpty)
    }

    @Test func stoppedServerRefusesConnections() async throws {
        let (server, client) = try await server(root: try folder("stop"), anonymous: true)
        var anonymous = client; anonymous.address.anonymous = true
        #expect(try await anonymous.list("/").isEmpty)
        server.stop()
        await #expect(throws: (any Error).self) { _ = try await anonymous.list("/") }
    }

    // MARK: unitarias de ~/.explorer/red.json

    @MainActor private func tempStore(_ legacy: UserDefaults? = nil) -> (NetworkStore, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("red-\(UUID().uuidString)/red.json")
        return (NetworkStore(file: file, legacy: legacy ?? UserDefaults(suiteName: "R.\(UUID().uuidString)")!), file)
    }

    // Nada compartido por defecto (= original); carpeta = inicio, solo lectura, 2121. Las pruebas nunca usan el archivo real.
    @Test @MainActor func defaultsAreOffAndTestsUseTempFile() {
        let (store, _) = tempStore()
        #expect(!store.config.share.enabled && store.config.share.readOnly && store.config.share.port == 2121)
        #expect(store.config.share.folderPath == NSHomeDirectory() && store.config.servers.isEmpty)
        #expect(NetworkStore.shared.file != NetworkStore.defaultFile)
    }

    // Se guarda como texto legible, sin contraseñas, y se lee igual al abrir de nuevo.
    @Test @MainActor func configIsSavedAsReadableJSONWithoutPasswords() throws {
        FTPSecrets.memory = [:]; defer { FTPSecrets.memory = nil }
        let (store, file) = tempStore()
        let nas = SavedServer(kind: .smb, host: "nas.local", user: "ana", path: "Fotos", name: "NAS de casa")
        store.remember(nas); store.remember(SavedServer(kind: .ftp, host: "b.com")); store.remember(nas)
        FTPSecrets.setPassword("clave", for: nas.id)
        store.config.share.folder = "/tmp"; store.config.share.enabled = true
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"host\" : \"nas.local\"") && text.contains("\"folder\" : \"/tmp\"") && !text.contains("clave"))
        let reopened = NetworkStore(file: file)
        #expect(reopened.config.servers.map(\.host) == ["nas.local", "b.com"] && reopened.config.share.enabled)
        reopened.forget(nas)
        #expect(reopened.config.servers.map(\.host) == ["b.com"] && FTPSecrets.password(for: nas.id) == nil)
        // Editado a mano con campos de menos: se entiende igual.
        try Data(#"{"servers":[{"host":"x"}]}"#.utf8).write(to: file)
        #expect(NetworkStore(file: file).config.servers.first?.port == 445)
    }

    // Lo de versiones anteriores (UserDefaults) pasa al archivo una vez y se borra de allí.
    @Test @MainActor func migratesOldSettings() throws {
        let d = UserDefaults(suiteName: "R.\(UUID().uuidString)")!
        d.set(true, forKey: "ftp.server.enabled"); d.set("/tmp", forKey: "ftp.server.root")
        d.set(try JSONEncoder().encode([FTPServerAddress(host: "viejo.com", port: 21, user: "u")]), forKey: "ftp.client.servers")
        let (store, file) = tempStore(d)
        #expect(store.config.share.enabled && store.config.share.folder == "/tmp")
        #expect(store.config.servers == [SavedServer(kind: .ftp, host: "viejo.com", port: 21, user: "u")])
        #expect(d.object(forKey: "ftp.server.enabled") == nil && FileManager.default.fileExists(atPath: file.path))
    }

    // Lo que escribe la persona en «Dirección»: se adivina el tipo.
    @Test func addressIsUnderstood() {
        #expect(SavedServer.parse("192.168.1.20") == SavedServer(kind: .smb, host: "192.168.1.20"))
        #expect(SavedServer.parse("nas.local/Fotos")?.path == "Fotos")
        #expect(SavedServer.parse("\\\\PC\\Documentos") == SavedServer(kind: .smb, host: "PC", path: "Documentos"))
        #expect(SavedServer.parse("ftp://ana@mi-web.com:2121/www") == SavedServer(kind: .ftp, host: "mi-web.com", port: 2121, user: "ana", path: "www"))
        #expect(SavedServer.parse("mi-web.com", kind: .ftp)?.port == 21)
        #expect(SavedServer.parse("  ") == nil)
        #expect(SMBMount.url(for: SavedServer(host: "nas.local", path: "Mis Fotos"))?.absoluteString == "smb://nas.local/Mis%20Fotos")
    }

    // MARK: completas y de flujo (app de verdad)

    /// Flujo «Compartir una carpeta»: se activa → escucha → se conecta con «Conectarse a un servidor»
    /// (dirección ftp://…) → se abre el explorador FTP con la carpeta → descarga y sube → se apaga → ya no responde.
    @Test @MainActor func shareAndConnectFlow() async throws {
        _ = NSApplication.shared
        FTPSecrets.memory = [FTPSettings.serverPasswordAccount: "pw"]; defer { FTPSecrets.memory = nil }
        let root = try folder("flow"), downloads = try folder("flow-dl")
        try Data("dato".utf8).write(to: root.appendingPathComponent("informe.txt"))
        var share = NetworkConfig.Share()
        share.folder = root.path; share.port = 0; share.user = "ana"; share.readOnly = false; share.localOnly = true
        let controller = FTPServerController.shared
        defer { controller.stopForTests() }

        await controller.apply(share)
        #expect(!controller.isRunning) // sin activar: no escucha
        share.enabled = true
        await controller.apply(share)
        let port = try #require(controller.port)
        #expect(controller.addresses == ["ftp://127.0.0.1:\(port)"])

        let (store, _) = tempStore()
        let server = try #require(SavedServer.parse("ftp://ana@127.0.0.1:\(port)"))
        #expect(server.kind == .ftp)
        let model = FTPClientModel.shared
        model.downloadFolder = { downloads }
        let error = await NetworkConnector.connect(server, password: "pw", remember: false, store: store)
        #expect(error == nil)
        let window = try #require(FTPClientWindow.current)
        defer { window.close(); model.disconnect() }
        #expect(model.entries.map(\.name) == ["informe.txt"])
        #expect(store.config.servers.first?.host == "127.0.0.1") // queda en «Recientes»

        model.selection = ["informe.txt"]
        await model.download()
        #expect(try String(contentsOf: downloads.appendingPathComponent("informe.txt"), encoding: .utf8) == "dato")
        let local = downloads.appendingPathComponent("subido.txt")
        try Data("arriba".utf8).write(to: local)
        await model.upload([local])
        #expect(model.entries.map(\.name) == ["informe.txt", "subido.txt"])

        // Contraseña mala: se dice por qué y no se abre nada nuevo.
        let bad = await NetworkConnector.connect(server, password: "mal", remember: false, store: store)
        #expect(bad != nil)

        share.enabled = false
        await controller.apply(share)
        #expect(!controller.isRunning && controller.addresses.isEmpty)
        await #expect(throws: (any Error).self) { _ = try await FTPClient(address: server.ftpAddress, password: "pw").list("/") }
    }

    /// Las dos ventanas se dibujan en rápida y en avanzada (la avanzada enseña más opciones).
    @Test @MainActor func connectAndShareWindowsHaveQuickAndAdvanced() async throws {
        let d = UserDefaults.standard
        let saved = [d.object(forKey: "network.connect.advanced"), d.object(forKey: "network.share.advanced")]
        defer { d.set(saved[0], forKey: "network.connect.advanced"); d.set(saved[1], forKey: "network.share.advanced") }
        for (kind, proto) in [(NetworkWindow.connect, SavedServer.Kind.ftp), (.connect, .smb), (.share, .ftp), (.share, .smb)] {
            d.set(false, forKey: "network.\(kind.rawValue).advanced")
            NetworkWindow.open(kind, proto)
            try await Task.sleep(for: .milliseconds(400))
            let window = try #require(NetworkWindow.current(kind, proto))
            let quick = window.frame.height
            d.set(true, forKey: "network.\(kind.rawValue).advanced")
            try await Task.sleep(for: .milliseconds(400))
            #expect(window.frame.height > quick, "\(kind) \(proto)")
            NetworkWindow.close(kind, proto)
        }
    }

    /// Clientes antiguos (FileZilla, Windows) usan PASV en vez de EPSV.
    @Test func passiveModeWithoutEPSV() async throws {
        let root = try folder("pasv")
        try Data("x".utf8).write(to: root.appendingPathComponent("a.txt"))
        let (server, client) = try await server(root: root)
        defer { server.stop() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "--disable-epsv", "--user", "ana:s3cr\"et", "--list-only", client.url("/", directory: true)]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        #expect(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("a.txt"))
        #expect(process.terminationStatus == 0)
    }
}
