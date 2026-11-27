import AppKit
import SwiftUI

/// Fork: ajustes y estado del FTP (cliente y servidor). Todo apagado por defecto = original.
/// Se controla desde el menú «FTP» de la barra de menús y desde Ajustes → Red → FTP.
enum FTPSettings {
    static let clientEnabledKey = "ftp.client.enabled"
    static let serverEnabledKey = "ftp.server.enabled"
    static let serverPortKey = "ftp.server.port"
    static let serverRootKey = "ftp.server.root"
    static let serverUserKey = "ftp.server.user"
    static let serverAnonymousKey = "ftp.server.anonymous"
    static let serverReadOnlyKey = "ftp.server.readOnly"
    static let serverLocalOnlyKey = "ftp.server.localOnly"
    static let savedServersKey = "ftp.client.servers"
    static let showsMenuKey = "menu.showsFTP"
    static let serverPasswordAccount = "server"

    static let defaultPort = 2121

    static func config(_ defaults: UserDefaults = .standard) -> FTPServer.Config {
        let rootPath = defaults.string(forKey: serverRootKey) ?? ""
        let port = defaults.object(forKey: serverPortKey) as? Int ?? defaultPort
        return FTPServer.Config(
            port: UInt16(clamping: max(0, port)),
            root: URL(fileURLWithPath: rootPath.isEmpty ? NSHomeDirectory() : rootPath, isDirectory: true),
            user: defaults.string(forKey: serverUserKey) ?? NSUserName(),
            password: FTPSecrets.password(for: serverPasswordAccount) ?? "",
            anonymous: defaults.bool(forKey: serverAnonymousKey),
            readOnly: defaults.object(forKey: serverReadOnlyKey) as? Bool ?? true,
            localOnly: defaults.bool(forKey: serverLocalOnlyKey))
    }

    static func savedServers(_ defaults: UserDefaults = .standard) -> [FTPServerAddress] {
        guard let data = defaults.data(forKey: savedServersKey) else { return [] }
        return (try? JSONDecoder().decode([FTPServerAddress].self, from: data)) ?? []
    }

    static func save(_ address: FTPServerAddress, _ defaults: UserDefaults = .standard) {
        var list = savedServers(defaults).filter { $0.id != address.id }
        list.insert(address, at: 0)
        defaults.set(try? JSONEncoder().encode(Array(list.prefix(20))), forKey: savedServersKey)
    }

    static func forget(_ address: FTPServerAddress, _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(savedServers(defaults).filter { $0.id != address.id }), forKey: savedServersKey)
        FTPSecrets.setPassword(nil, for: address.id)
    }

    /// Direcciones IPv4 de este Mac en la red (para decir a otros a dónde conectarse).
    static func localAddresses() -> [String] {
        var result: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
        }
        return result
    }
}

/// Servidor FTP de la app: uno solo, se enciende/apaga según `ftp.server.enabled`.
@MainActor
final class FTPServerController: ObservableObject {
    static let shared = FTPServerController()
    @Published private(set) var state: FTPServer.State = .stopped
    private var server: FTPServer?
    private var observer: NSObjectProtocol?
    private var applying = false

    var isRunning: Bool { if case .running = state { true } else { false } }
    var port: UInt16? { if case .running(let port) = state { port } else { nil } }

    /// Dirección para conectarse desde otro equipo (o este Mac).
    var addresses: [String] {
        guard let port else { return [] }
        let hosts = server?.config.localOnly == true ? ["127.0.0.1"] : FTPSettings.localAddresses()
        return (hosts.isEmpty ? ["127.0.0.1"] : hosts).map { "ftp://\($0):\(port)" }
    }

    /// Al arrancar la app: si estaba encendido, arranca; y sigue los cambios de Ajustes.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Task { await FTPServerController.shared.apply() } }
        }
        Task { await apply() }
    }

    /// Enciende, apaga o reinicia (si cambió la configuración) según lo guardado.
    func apply(_ defaults: UserDefaults? = nil) async {
        let defaults = defaults ?? .standard
        // Si llega un cambio mientras arranca, se vuelve a mirar al terminar (no se pierde).
        guard !applying else { needsApply = true; return }
        applying = true
        repeat { needsApply = false; await applyOnce(defaults) } while needsApply
        applying = false
    }

    private var needsApply = false

    private func applyOnce(_ defaults: UserDefaults) async {
        let wanted = defaults.bool(forKey: FTPSettings.serverEnabledKey)
        if !wanted && server == nil { state = .stopped; return } // apagado: ni se lee el Llavero
        let config = FTPSettings.config(defaults)
        if !wanted || server?.config != config {
            server?.stop(); server = nil
            if !wanted { state = .stopped }
        }
        guard wanted, server == nil else { return }
        let new = FTPServer(config: config)
        server = new
        state = await new.start()
        new.onStateChange = { newState in Task { @MainActor in FTPServerController.shared.state = newState } }
    }

    func stopForTests() { server?.stop(); server = nil; state = .stopped }
}

// MARK: Menú «FTP»

/// Submenú «FTP» del menú «Red». Cliente y servidor por separado, cada uno con su estado
/// arriba (qué está pasando ahora) y botones claros (Conectar / Desconectar, Iniciar / Detener).
struct FTPMenuItems: View {
    @AppStorage(FTPSettings.showsMenuKey) private var showsMenu = true
    @AppStorage(FTPSettings.clientEnabledKey) private var clientEnabled = false
    @AppStorage(FTPSettings.serverEnabledKey) private var serverEnabled = false
    @AppStorage(FTPSettings.serverRootKey) private var serverRoot = ""
    @AppStorage(FTPSettings.serverReadOnlyKey) private var readOnly = true
    @ObservedObject private var server = FTPServerController.shared
    @ObservedObject private var client = FTPClientModel.shared
    let currentFolder: () -> URL?

    private var rootPath: String { serverRoot.isEmpty ? NSHomeDirectory() : serverRoot }

    var body: some View {
        if showsMenu {
            Menu("FTP") {
                Section("Client") {
                    if let host = client.connectedHost {
                        Label("Connected to \(host)", systemImage: "circle.fill")
                        Button("Show FTP Client") { FTPClientWindow.open() }
                        Button("Disconnect") { client.disconnect() }
                    } else {
                        Label("Not connected", systemImage: "circle")
                        Button("Connect to FTP Server…") { clientEnabled = true; FTPClientWindow.open() }
                            .keyboardShortcut("k", modifiers: [.command, .option])
                    }
                    if !client.saved.isEmpty {
                        Menu("Recent Servers") {
                            ForEach(client.saved) { saved in
                                Button(saved.anonymous ? saved.host : "\(saved.user)@\(saved.host)") {
                                    clientEnabled = true
                                    client.pick(saved)
                                    FTPClientWindow.open()
                                    Task { await client.connect() }
                                }
                            }
                        }
                    }
                    Button("FTP Client Settings…") { SettingsOpener.open(tab: "servers", page: "ftpClient") }
                }
                Section("Server") {
                    switch server.state {
                    case .running:
                        Label("Running at \(server.addresses.first ?? "")", systemImage: "circle.fill")
                        Button("Stop Server") { serverEnabled = false }
                        Button("Copy Server Address") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(server.addresses.first ?? "", forType: .string)
                        }
                    case .failed(let message):
                        Label("Couldn’t start: \(message)", systemImage: "exclamationmark.triangle")
                        Button("Start Server") { serverEnabled = false; serverEnabled = true }
                    case .stopped:
                        Label("Stopped", systemImage: "circle")
                        Button("Start Server") { serverEnabled = true }
                    }
                    Label("Shared folder: \((rootPath as NSString).lastPathComponent) · \(readOnly ? String(localized: "Read only") : String(localized: "Read and write"))",
                          systemImage: "folder")
                    Button("Change Shared Folder…") { FTPSettings.chooseRoot() }
                    if let url = currentFolder(), url.path != rootPath {
                        Button("Share “\(url.lastPathComponent)” (current folder)") { serverRoot = url.path; serverEnabled = true }
                    }
                    Button("Show Shared Folder in Explorer") { WindowService.open(at: URL(fileURLWithPath: rootPath)) }
                    Button("FTP Server Settings…") { SettingsOpener.open(tab: "servers", page: "ftpServer") }
                }
            }
        }
    }
}

extension FTPSettings {
    /// Elegir la carpeta compartida del servidor FTP (menú y Ajustes).
    @MainActor static func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Share")
        let current = UserDefaults.standard.string(forKey: serverRootKey) ?? ""
        panel.directoryURL = URL(fileURLWithPath: current.isEmpty ? NSHomeDirectory() : current)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { UserDefaults.standard.set(url.path, forKey: serverRootKey) }
    }
}
