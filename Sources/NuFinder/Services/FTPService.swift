import AppKit
import Combine
import SwiftUI

/// Fork: utilidades del FTP. La configuración vive en `~/.explorer/red.json` (`NetworkStore`).
enum FTPSettings {
    static let serverPasswordAccount = "server"
    static let defaultPort = 2121

    static func config(_ share: NetworkConfig.Share, password: String? = nil) -> FTPServer.Config {
        let root = URL(fileURLWithPath: share.folderPath, isDirectory: true)
        var config = FTPServer.Config(
            port: UInt16(clamping: max(0, share.port)), root: root,
            anonymous: share.anonymous, readOnly: share.readOnly, localOnly: share.localOnly)
        config.accounts = share.users.filter { !$0.name.isEmpty }.map { user in
            FTPServer.Account(name: user.name, password: FTPSecrets.password(for: user.key) ?? "", readOnly: user.readOnly,
                              root: user.folder.isEmpty ? nil : URL(fileURLWithPath: user.folder, isDirectory: true))
        }
        return config
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

/// Servidor FTP de la app: uno solo, se enciende/apaga según `share.enabled` de `red.json`.
@MainActor
final class FTPServerController: ObservableObject {
    static let shared = FTPServerController()
    @Published private(set) var state: FTPServer.State = .stopped
    private var server: FTPServer?
    private var subscription: AnyCancellable?
    private var applying = false
    private var pending: NetworkConfig.Share?

    var isRunning: Bool { if case .running = state { true } else { false } }
    var port: UInt16? { if case .running(let port) = state { port } else { nil } }

    /// Direcciones para conectarse desde otro equipo (o este Mac).
    var addresses: [String] {
        guard let port else { return [] }
        let hosts = server?.config.localOnly == true ? ["127.0.0.1"] : FTPSettings.localAddresses()
        return (hosts.isEmpty ? ["127.0.0.1"] : hosts).map { "ftp://\($0):\(port)" }
    }

    /// Al arrancar la app: sigue los cambios de `red.json`.
    func start(_ store: NetworkStore = .shared) {
        guard subscription == nil else { return }
        subscription = store.$config.map(\.share).removeDuplicates().sink { share in
            Task { await FTPServerController.shared.apply(share) }
        }
    }

    /// Reinicia con la contraseña nueva (está en el Llavero, no en el archivo).
    func passwordChanged() { Task { await apply(NetworkStore.shared.config.share, force: true) } }

    /// Enciende, apaga o reinicia según la configuración (los cambios que lleguen mientras arranca no se pierden).
    func apply(_ share: NetworkConfig.Share, force: Bool = false) async {
        if applying { pending = share; return }
        applying = true
        var next: NetworkConfig.Share? = share
        var restart = force
        while let current = next {
            pending = nil
            await applyOnce(current, restart: restart)
            restart = false
            next = pending
        }
        applying = false
    }

    private func applyOnce(_ share: NetworkConfig.Share, restart: Bool) async {
        guard share.enabled else { server?.stop(); server = nil; state = .stopped; return }
        let config = FTPSettings.config(share)
        if restart || server?.config != config { server?.stop(); server = nil }
        guard server == nil else { return }
        let new = FTPServer(config: config)
        server = new
        state = await new.start()
        new.onStateChange = { newState in Task { @MainActor in FTPServerController.shared.state = newState } }
    }

    func stopForTests() { server?.stop(); server = nil; state = .stopped }
}
