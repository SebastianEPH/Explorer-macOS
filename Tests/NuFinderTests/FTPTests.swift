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

    // MARK: unitarias de ajustes

    // Todo apagado por defecto (= original): ni cliente ni servidor; el servidor, solo lectura en 2121.
    @Test func defaultsAreOff() {
        let d = UserDefaults(suiteName: "FTP.\(UUID().uuidString)")!
        #expect(!d.bool(forKey: FTPSettings.clientEnabledKey) && !d.bool(forKey: FTPSettings.serverEnabledKey))
        let config = FTPSettings.config(d)
        #expect(config.port == 2121 && config.readOnly && !config.anonymous && !config.localOnly)
        #expect(config.root.path == NSHomeDirectory())
        #expect(DefaultSettings.mine[FTPSettings.serverEnabledKey] == nil)
    }

    @Test func savedServersKeepPasswordsOutOfDefaults() {
        let d = UserDefaults(suiteName: "FTP.\(UUID().uuidString)")!
        FTPSecrets.memory = [:]; defer { FTPSecrets.memory = nil }
        let a = FTPServerAddress(host: "a.local", port: 21, user: "ana")
        FTPSettings.save(a, d); FTPSettings.save(.init(host: "b.local"), d); FTPSettings.save(a, d)
        #expect(FTPSettings.savedServers(d).map(\.host) == ["a.local", "b.local"])
        FTPSecrets.setPassword("clave", for: a.id)
        #expect(String(decoding: d.data(forKey: FTPSettings.savedServersKey) ?? Data(), as: UTF8.self).contains("clave") == false)
        FTPSettings.forget(a, d)
        #expect(FTPSettings.savedServers(d).map(\.host) == ["b.local"] && FTPSecrets.password(for: a.id) == nil)
    }

    // MARK: completas y de flujo (app de verdad)

    /// Flujo: en Ajustes se enciende el servidor → escucha → el cliente de la app se conecta en su
    /// ventana, ve la carpeta, descarga a la carpeta de Explorer y sube → se apaga → ya no responde.
    @Test @MainActor func settingsServerAndClientWindowFlow() async throws {
        _ = NSApplication.shared
        FTPSecrets.memory = [FTPSettings.serverPasswordAccount: "pw"]; defer { FTPSecrets.memory = nil }
        let d = UserDefaults(suiteName: "FTP.\(UUID().uuidString)")!
        let root = try folder("flow"), downloads = try folder("flow-dl")
        try Data("dato".utf8).write(to: root.appendingPathComponent("informe.txt"))
        d.set(root.path, forKey: FTPSettings.serverRootKey)
        d.set(0, forKey: FTPSettings.serverPortKey)
        d.set("ana", forKey: FTPSettings.serverUserKey)
        d.set(false, forKey: FTPSettings.serverReadOnlyKey)
        d.set(true, forKey: FTPSettings.serverLocalOnlyKey)
        let controller = FTPServerController.shared
        defer { controller.stopForTests() }

        await controller.apply(d)
        #expect(!controller.isRunning) // apagado: no escucha
        d.set(true, forKey: FTPSettings.serverEnabledKey)
        await controller.apply(d)
        let port = try #require(controller.port)
        #expect(controller.addresses == ["ftp://127.0.0.1:\(port)"])

        let model = FTPClientModel()
        model.address = .init(host: "127.0.0.1", port: Int(port), user: "ana")
        model.password = "pw"; model.remember = false
        model.downloadFolder = { downloads }
        FTPClientWindow.open(model: model)
        let window = try #require(FTPClientWindow.current)
        #expect(window.title == String(localized: "FTP Client"))
        await model.connect()
        #expect(model.client != nil && model.message == nil)
        #expect(model.entries.map(\.name) == ["informe.txt"])

        model.selection = ["informe.txt"]
        await model.download()
        #expect(try String(contentsOf: downloads.appendingPathComponent("informe.txt"), encoding: .utf8) == "dato")
        let local = downloads.appendingPathComponent("subido.txt")
        try Data("arriba".utf8).write(to: local)
        await model.upload([local])
        #expect(model.entries.map(\.name) == ["informe.txt", "subido.txt"])
        await model.makeFolder("Carpeta")
        await model.open(model.child("Carpeta"))
        #expect(model.path == "/Carpeta" && model.entries.isEmpty)
        await model.goUp()
        #expect(model.entries.first?.name == "Carpeta")

        // Cambiar la contraseña en Ajustes reinicia el servidor con la nueva.
        FTPSecrets.memory?[FTPSettings.serverPasswordAccount] = "otra"
        await controller.apply(d)
        await model.reload()
        #expect(model.message != nil)

        d.set(false, forKey: FTPSettings.serverEnabledKey)
        await controller.apply(d)
        #expect(!controller.isRunning && controller.addresses.isEmpty)
        let client = FTPClient(address: model.address, password: "otra")
        await #expect(throws: (any Error).self) { _ = try await client.list("/") }
        window.close()
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
