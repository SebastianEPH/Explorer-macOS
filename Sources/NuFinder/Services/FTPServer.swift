import Foundation
import Network

/// Fork: servidor FTP propio (Network.framework, sin dependencias). Comparte una carpeta
/// en la red local; se enciende y apaga en el menú «FTP» o en Ajustes → Red → FTP.
/// Modo pasivo (PASV/EPSV), usuario y contraseña o anónimo, y solo lectura si se quiere.
final class FTPServer: @unchecked Sendable {
    struct Config: Equatable, Sendable {
        var port: UInt16 = 2121 // 0 = cualquiera libre (pruebas)
        var root: URL
        var user: String = ""
        var password: String = ""
        var anonymous = false
        var readOnly = true
        var localOnly = false // solo este Mac (127.0.0.1)
        /// Varios usuarios, cada uno con su contraseña (vacía = sin contraseña), permisos y carpeta.
        var accounts: [Account] = []
    }

    struct Account: Equatable, Sendable {
        var name: String
        var password: String = ""
        var readOnly = true
        /// Carpeta propia; nil = la carpeta compartida del servidor.
        var root: URL? = nil
    }

    enum State: Equatable, Sendable {
        case stopped
        case running(port: UInt16)
        case failed(String)
    }

    let config: Config
    private let queue = DispatchQueue(label: "explorer.ftp.server")
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: FTPSession] = [:]
    private(set) var state: State = .stopped
    private var startResumed = false
    var onStateChange: (@Sendable (State) -> Void)?

    init(config: Config) { self.config = config }

    /// Arranca y espera a saber si escucha o no (máx. 5 s).
    @discardableResult
    func start() async -> State {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                if config.localOnly {
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: config.port) ?? .any)
                }
                let listener: NWListener
                do {
                    listener = config.localOnly
                        ? try NWListener(using: parameters)
                        : try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: config.port) ?? .any)
                } catch {
                    setState(.failed(error.localizedDescription)); continuation.resume(returning: state); return
                }
                self.listener = listener
                startResumed = false
                listener.stateUpdateHandler = { [self] newState in
                    switch newState {
                    case .ready:
                        setState(.running(port: listener.port?.rawValue ?? config.port))
                    case .failed(let error):
                        setState(.failed(error.localizedDescription)); listener.cancel()
                    case .cancelled:
                        if case .running = state { setState(.stopped) }
                    default: return
                    }
                    if !startResumed { startResumed = true; continuation.resume(returning: state) }
                }
                listener.newConnectionHandler = { [self] connection in accept(connection) }
                listener.start(queue: queue)
                queue.asyncAfter(deadline: .now() + 5) { [self] in
                    if !startResumed { startResumed = true; setState(.failed("Timeout")); continuation.resume(returning: state) }
                }
            }
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel(); listener = nil
            for session in sessions.values { session.close() }
            sessions.removeAll()
            setState(.stopped)
        }
    }

    var connectionCount: Int { queue.sync { sessions.count } }

    private func setState(_ new: State) {
        state = new
        onStateChange?(new)
    }

    private func accept(_ connection: NWConnection) {
        let session = FTPSession(connection: connection, config: config, queue: queue)
        let id = ObjectIdentifier(session)
        sessions[id] = session
        session.onClose = { [weak self] in self?.sessions[id] = nil }
        session.start()
    }
}

/// Rutas del FTP: el cliente ve «/» = carpeta compartida y nunca puede salir de ella.
enum FTPPath {
    /// Ruta virtual nueva («/a/b») a partir de la actual y lo que pide el cliente.
    static func virtual(cwd: String, argument: String) -> String {
        let start = argument.hasPrefix("/") ? [] : cwd.split(separator: "/").map(String.init)
        var parts = start
        for piece in argument.split(separator: "/").map(String.init) {
            switch piece {
            case "", ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(piece)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Archivo real; nil si (siguiendo enlaces) queda fuera de la carpeta compartida.
    static func resolve(root: URL, virtual: String) -> URL? {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        var url = URL(fileURLWithPath: rootPath, isDirectory: true)
        for piece in virtual.split(separator: "/") { url.appendPathComponent(String(piece)) }
        // Lo que ya existe se resuelve con sus enlaces; si no existe, se mira su carpeta.
        let fm = FileManager.default
        let check = fm.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        let real = check.resolvingSymlinksInPath().standardizedFileURL.path
        guard real == rootPath || real.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else { return nil }
        return url
    }
}

/// Listado al estilo `ls -l`, el que entienden todos los clientes FTP.
enum FTPListing {
    static func line(name: String, isDirectory: Bool, size: Int64, modified: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let sixMonths: TimeInterval = 180 * 24 * 3600
        formatter.dateFormat = abs(now.timeIntervalSince(modified)) < sixMonths ? "MMM dd HH:mm" : "MMM dd  yyyy"
        let mode = isDirectory ? "drwxr-xr-x" : "-rw-r--r--"
        return "\(mode) 1 owner group \(String(size).leftPad(13)) \(formatter.string(from: modified)) \(name)"
    }

    static func listing(of directory: URL, namesOnly: Bool) -> String {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url -> String in
                if namesOnly { return url.lastPathComponent }
                let values = try? url.resourceValues(forKeys: Set(keys))
                return line(name: url.lastPathComponent, isDirectory: values?.isDirectory ?? false,
                            size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? Date())
            }
            .map { $0 + "\r\n" }.joined()
    }
}

private extension String {
    func leftPad(_ width: Int) -> String { count >= width ? self : String(repeating: " ", count: width - count) + self }
}

/// Una conexión de control (un cliente). Todo corre en la cola del servidor.
final class FTPSession: @unchecked Sendable {
    private let connection: NWConnection
    private let config: FTPServer.Config
    private let queue: DispatchQueue
    private var buffer = Data()
    private var user: String?
    private var loggedIn = false
    private var cwd = "/"
    /// Carpeta y permisos del usuario que ha entrado (al principio, los del servidor).
    private lazy var root: URL = config.root
    private lazy var readOnly: Bool = config.readOnly
    private var renameFrom: URL?
    private var dataListener: NWListener?
    private var dataConnection: NWConnection?
    private var dataReady = false
    private var pendingData: ((NWConnection) -> Void)?
    var onClose: (() -> Void)?

    init(connection: NWConnection, config: FTPServer.Config, queue: DispatchQueue) {
        self.connection = connection
        self.config = config
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .failed, .cancelled: close()
            default: break
            }
        }
        connection.start(queue: queue)
        reply(220, "Explorer FTP ready")
        receive()
    }

    func close() {
        closeData()
        connection.cancel()
        let done = onClose
        onClose = nil
        done?()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, complete, error in
            if let data { buffer.append(data) }
            while let range = buffer.range(of: Data("\n".utf8)) {
                let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                    .trimmingCharacters(in: .init(charactersIn: "\r"))
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                handle(line)
            }
            if complete || error != nil { close() } else { receive() }
        }
    }

    private func reply(_ code: Int, _ text: String) {
        connection.send(content: Data("\(code) \(text)\r\n".utf8), completion: .contentProcessed { _ in })
    }

    private func replyLines(_ code: Int, _ lines: [String], last: String) {
        let body = "\(code)-" + lines.joined(separator: "\r\n ") + "\r\n\(code) \(last)\r\n"
        connection.send(content: Data(body.utf8), completion: .contentProcessed { _ in })
    }

    // MARK: Órdenes

    private func handle(_ line: String) {
        let space = line.firstIndex(of: " ")
        let command = String(space.map { line[..<$0] } ?? Substring(line)).uppercased()
        let argument = space.map { String(line[line.index(after: $0)...]) } ?? ""
        let open: Set<String> = ["USER", "PASS", "QUIT", "FEAT", "SYST", "OPTS", "NOOP", "AUTH"]
        if !loggedIn && !open.contains(command) { reply(530, "Please log in"); return }
        switch command {
        case "USER":
            user = argument
            if config.anonymous && ["anonymous", "ftp"].contains(argument.lowercased()) {
                reply(331, "Anonymous login, send any password")
            } else { reply(331, "Password required") }
        case "PASS":
            let anonymous = config.anonymous && ["anonymous", "ftp"].contains((user ?? "").lowercased())
            // Usuario de la lista: contraseña vacía = entra con cualquier contraseña (o ninguna).
            if let account = config.accounts.first(where: { $0.name == user }),
               account.password.isEmpty || account.password == argument {
                root = account.root ?? config.root
                readOnly = account.readOnly
                loggedIn = true; reply(230, "Logged in"); return
            }
            let valid = !config.user.isEmpty && user == config.user && argument == config.password
            if anonymous || valid { loggedIn = true; reply(230, "Logged in") } else { reply(530, "Login incorrect") }
        case "AUTH": reply(502, "TLS not supported")
        case "SYST": reply(215, "UNIX Type: L8")
        case "FEAT": replyLines(211, ["Features:", "EPSV", "PASV", "SIZE", "MDTM", "UTF8"], last: "End")
        case "OPTS": reply(200, "OK")
        case "NOOP": reply(200, "OK")
        case "QUIT": reply(221, "Bye"); queue.asyncAfter(deadline: .now() + 0.1) { [self] in close() }
        case "TYPE", "MODE", "STRU": reply(200, "OK")
        case "PWD", "XPWD": reply(257, "\"\(cwd)\" is the current directory")
        case "CWD", "XCWD": changeDirectory(argument)
        case "CDUP", "XCUP": changeDirectory("..")
        case "PASV": openPassive(extended: false)
        case "EPSV": openPassive(extended: true)
        case "PORT", "EPRT": reply(502, "Use passive mode")
        case "LIST", "NLST": list(argument, namesOnly: command == "NLST")
        case "RETR": retrieve(argument)
        case "STOR", "APPE": store(argument, append: command == "APPE")
        case "SIZE":
            guard let url = target(argument), let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { reply(550, "Not found"); return }
            reply(213, String(size))
        case "MDTM":
            guard let url = target(argument), let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { reply(550, "Not found"); return }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMddHHmmss"
            reply(213, formatter.string(from: date))
        case "DELE": modify(argument) { try FileManager.default.removeItem(at: $0) } done: { self.reply(250, "Deleted") }
        case "RMD", "XRMD": modify(argument) { try FileManager.default.removeItem(at: $0) } done: { self.reply(250, "Removed") }
        case "MKD", "XMKD":
            modify(argument, mustExist: false) { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: false) } done: {
                self.reply(257, "\"\(FTPPath.virtual(cwd: self.cwd, argument: argument))\" created")
            }
        case "RNFR":
            guard !readOnly else { reply(550, "Read-only"); return }
            guard let url = target(argument) else { reply(550, "Not found"); return }
            renameFrom = url; reply(350, "Ready for RNTO")
        case "RNTO":
            guard let from = renameFrom else { reply(503, "RNFR first"); return }
            renameFrom = nil
            modify(argument, mustExist: false) { try FileManager.default.moveItem(at: from, to: $0) } done: { self.reply(250, "Renamed") }
        default: reply(502, "Command not implemented")
        }
    }

    /// Archivo que existe dentro de la carpeta compartida.
    private func target(_ argument: String) -> URL? {
        guard let url = FTPPath.resolve(root: root, virtual: FTPPath.virtual(cwd: cwd, argument: argument)),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func modify(_ argument: String, mustExist: Bool = true, _ action: (URL) throws -> Void, done: () -> Void) {
        guard !readOnly else { reply(550, "Read-only server"); return }
        let path = FTPPath.virtual(cwd: cwd, argument: argument)
        guard path != "/", let url = mustExist ? target(argument) : FTPPath.resolve(root: root, virtual: path) else {
            reply(550, "Not found"); return
        }
        do { try action(url); done() } catch { reply(550, error.localizedDescription) }
    }

    private func changeDirectory(_ argument: String) {
        let path = FTPPath.virtual(cwd: cwd, argument: argument)
        var isDirectory: ObjCBool = false
        guard let url = FTPPath.resolve(root: root, virtual: path),
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            reply(550, "No such directory"); return
        }
        cwd = path
        reply(250, "Directory changed to \(path)")
    }

    // MARK: Datos (modo pasivo)

    private func openPassive(extended: Bool) {
        closeData()
        guard let listener = try? NWListener(using: .tcp, on: .any) else { reply(425, "Can't open data connection"); return }
        dataListener = listener
        listener.newConnectionHandler = { [self] connection in
            guard dataConnection == nil else { connection.cancel(); return }
            dataConnection = connection
            connection.stateUpdateHandler = { [self] state in
                if case .ready = state {
                    dataReady = true
                    if let pending = pendingData { pendingData = nil; pending(connection) }
                }
            }
            connection.start(queue: queue)
            listener.cancel()
        }
        listener.stateUpdateHandler = { [self] state in
            guard case .ready = state, let port = listener.port?.rawValue else { return }
            if extended {
                reply(229, "Entering Extended Passive Mode (|||\(port)|)")
            } else {
                let host = localIPv4() ?? "127.0.0.1"
                let numbers = host.split(separator: ".").joined(separator: ",")
                reply(227, "Entering Passive Mode (\(numbers),\(port >> 8),\(port & 0xFF))")
            }
        }
        listener.start(queue: queue)
    }

    /// IP de este Mac tal como la ve el cliente (la de la conexión de control).
    private func localIPv4() -> String? {
        guard case .hostPort(let host, _)? = connection.currentPath?.localEndpoint else { return nil }
        switch host {
        case .ipv4(let address): return "\(address)".split(separator: "%").first.map(String.init)
        case .ipv6(let address):
            let text = "\(address)"
            return text.hasPrefix("::ffff:") ? String(text.dropFirst(7)) : nil
        default: return nil
        }
    }

    private func withData(_ work: @escaping (NWConnection) -> Void) {
        guard dataListener != nil || dataConnection != nil else { reply(425, "Use PASV or EPSV first"); return }
        reply(150, "Opening data connection")
        if let connection = dataConnection, dataReady { work(connection) } else { pendingData = work }
    }

    private func closeData() {
        dataListener?.cancel(); dataListener = nil
        dataConnection?.cancel(); dataConnection = nil
        dataReady = false; pendingData = nil
    }

    private func finishData(_ ok: Bool, _ message: String = "Transfer complete") {
        dataConnection?.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [self] _ in
            closeData()
            reply(ok ? 226 : 451, message)
        })
        if dataConnection == nil { reply(ok ? 226 : 451, message) }
    }

    private func list(_ argument: String, namesOnly: Bool) {
        let cleaned = argument.split(separator: " ").filter { !$0.hasPrefix("-") }.joined(separator: " ")
        guard let url = cleaned.isEmpty ? FTPPath.resolve(root: root, virtual: cwd) : target(cleaned) else {
            reply(550, "Not found"); return
        }
        withData { [self] connection in
            let text = FTPListing.listing(of: url, namesOnly: namesOnly)
            connection.send(content: Data(text.utf8), completion: .contentProcessed { [self] error in finishData(error == nil) })
        }
    }

    private func retrieve(_ argument: String) {
        guard let url = target(argument), let handle = try? FileHandle(forReadingFrom: url) else { reply(550, "Not found"); return }
        withData { [self] connection in sendChunks(handle, connection) }
    }

    private func sendChunks(_ handle: FileHandle, _ connection: NWConnection) {
        let chunk = (try? handle.read(upToCount: 256 * 1024)) ?? nil
        guard let chunk, !chunk.isEmpty else { try? handle.close(); finishData(true); return }
        connection.send(content: chunk, completion: .contentProcessed { [self] error in
            if error != nil { try? handle.close(); finishData(false, "Transfer aborted") } else { sendChunks(handle, connection) }
        })
    }

    private func store(_ argument: String, append: Bool) {
        guard !readOnly else { reply(550, "Read-only server"); return }
        let path = FTPPath.virtual(cwd: cwd, argument: argument)
        guard path != "/", let url = FTPPath.resolve(root: root, virtual: path) else { reply(550, "Not allowed"); return }
        if !append || !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { reply(550, "Can't create file"); return }
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { reply(550, "Can't write file"); return }
        if append { _ = try? handle.seekToEnd() }
        withData { [self] connection in receiveChunks(handle, connection) }
    }

    private func receiveChunks(_ handle: FileHandle, _ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [self] data, _, complete, error in
            if let data, !data.isEmpty { try? handle.write(contentsOf: data) }
            if complete || error != nil {
                try? handle.close()
                closeData()
                reply(complete ? 226 : 451, complete ? "Transfer complete" : "Transfer aborted")
            } else { receiveChunks(handle, connection) }
        }
    }
}
