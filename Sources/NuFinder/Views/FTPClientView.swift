import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Fork: ventana del cliente FTP. Conectarse, recorrer carpetas, descargar a la carpeta de
/// la ventana de Explorer activa, subir (botón o arrastrando archivos), crear carpetas,
/// renombrar y borrar.
@MainActor
final class FTPClientModel: ObservableObject {
    /// El de la ventana del cliente: el menú «Red» muestra si está conectado y a qué.
    static let shared = FTPClientModel()
    var connectedHost: String? { client.map { $0.address.host } }
    @Published var address = FTPServerAddress(host: "")
    @Published var password = ""
    @Published private(set) var client: FTPClient?
    @Published private(set) var path = "/"
    @Published private(set) var entries: [FTPEntry] = []
    @Published var selection: Set<String> = []
    @Published private(set) var busy = false
    @Published var message: String?
    /// Carpeta donde se descarga: la de la ventana de Explorer activa (o Descargas).
    var downloadFolder: () -> URL = {
        KeyWindowFocus.shared.windowBrowser?.currentURL
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// Conecta; devuelve el error si no se pudo (la conexión anterior, si había, se mantiene).
    @discardableResult
    func connect(startPath: String = "/") async -> String? {
        let candidate = FTPClient(address: address, password: password)
        busy = true; defer { busy = false }
        do {
            entries = try await candidate.list(startPath)
            client = candidate; path = startPath; message = nil
            return nil
        } catch { return error.localizedDescription }
    }

    func disconnect() { client = nil; entries = []; selection = []; path = "/" }

    func open(_ folder: String) async {
        guard let client else { return }
        busy = true; defer { busy = false }
        do { entries = try await client.list(folder); path = folder; selection = [] } catch { message = error.localizedDescription }
    }

    func child(_ name: String) -> String { (path as NSString).appendingPathComponent(name) }
    func goUp() async { await open((path as NSString).deletingLastPathComponent) }
    func reload() async { await open(path) }

    private func perform(_ work: (FTPClient) async throws -> Void) async {
        guard let client else { return }
        busy = true
        do { try await work(client) } catch { message = error.localizedDescription }
        busy = false
        await reload()
    }

    func download() async {
        let folder = downloadFolder()
        let chosen = entries.filter { selection.contains($0.id) && !$0.isDirectory }
        await perform { client in
            for entry in chosen { try await client.download(child(entry.name), to: folder.appendingPathComponent(entry.name)) }
        }
        if !chosen.isEmpty, message == nil { message = String(localized: "Downloaded to \(folder.lastPathComponent)") }
    }

    func upload(_ urls: [URL]) async {
        let files = urls.filter { !$0.hasDirectoryPath }
        await perform { client in for url in files { try await client.upload(url, toDirectory: path) } }
    }

    func makeFolder(_ name: String) async {
        guard !name.isEmpty else { return }
        await perform { try await $0.makeDirectory(child(name)) }
    }

    func rename(_ entry: FTPEntry, to name: String) async {
        guard !name.isEmpty, name != entry.name else { return }
        await perform { try await $0.rename(child(entry.name), to: child(name)) }
    }

    func deleteSelection() async {
        let chosen = entries.filter { selection.contains($0.id) }
        await perform { client in
            for entry in chosen { try await client.delete(child(entry.name), isDirectory: entry.isDirectory) }
        }
    }
}

enum FTPClientWindow {
    @MainActor private static var window: NSWindow?

    @MainActor
    static func open(model: FTPClientModel = .shared) {
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = String(localized: "FTP Client")
        window.identifier = NSUserInterfaceItemIdentifier("explorer.ftp.client")
        window.contentViewController = NSHostingController(rootView: FTPClientView(model: model))
        window.setContentSize(NSSize(width: 720, height: 480))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    @MainActor static var current: NSWindow? { window?.isVisible == true ? window : nil }
}

struct FTPClientView: View {
    @ObservedObject var model: FTPClientModel
    @State private var newFolderName = ""
    @State private var showsNewFolder = false
    @State private var renaming: FTPEntry?
    @State private var renameText = ""
    @State private var confirmsDelete = false

    var body: some View {
        Group {
            if model.client == nil { connectForm } else { browser }
        }
        .frame(minWidth: 560, minHeight: 360)
        .overlay(alignment: .bottom) {
            if let message = model.message {
                Text(message).font(.caption).padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(10)
                    .onTapGesture { model.message = nil }
            }
        }
    }

    private var connectForm: some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Not connected").font(.title3)
            Button("My FTP Connections…") { NetworkSettingsPages.open(.ftp) }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { Task { await model.goUp() } } label: { Image(systemName: "chevron.up") }
                    .disabled(model.path == "/").help(Text("Enclosing Folder"))
                Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }.help(Text("Reload"))
                Text(verbatim: "\(model.address.host)\(model.path)").font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { showsNewFolder = true } label: { Image(systemName: "folder.badge.plus") }.help(Text("New Folder…"))
                Button { chooseUpload() } label: { Image(systemName: "arrow.up.doc") }.help(Text("Upload…"))
                Button { Task { await model.download() } } label: { Image(systemName: "arrow.down.doc") }
                    .help(Text("Download to the current Explorer folder")).disabled(model.selection.isEmpty)
                Button { confirmsDelete = true } label: { Image(systemName: "trash") }
                    .help(Text("Delete")).disabled(model.selection.isEmpty)
                Button("Disconnect") { model.disconnect() }
            }
            .buttonStyle(.borderless)
            .padding(10)
            Divider()
            Table(model.entries, selection: $model.selection) {
                TableColumn("Name") { entry in
                    Label(entry.name, systemImage: entry.isDirectory ? "folder.fill" : "doc")
                }
                TableColumn("Size") { entry in
                    Text(entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                }
                .width(90)
                TableColumn("Modified") { entry in Text(entry.modified) }.width(130)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let entry = model.entries.first(where: { ids.contains($0.id) }) {
                    Button("Rename") { renaming = entry; renameText = entry.name }
                }
                Button("Download to the current Explorer folder") { model.selection = ids; Task { await model.download() } }
                Button("Delete") { model.selection = ids; confirmsDelete = true }
            } primaryAction: { ids in
                if let entry = model.entries.first(where: { ids.contains($0.id) }), entry.isDirectory {
                    Task { await model.open(model.child(entry.name)) }
                } else { Task { await model.download() } }
            }
            .dropDestination(for: URL.self) { urls, _ in
                Task { await model.upload(urls) }
                return true
            }
        }
        .alert("New Folder…", isPresented: $showsNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { let name = newFolderName; newFolderName = ""; Task { await model.makeFolder(name) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let entry = renaming { let name = renameText; Task { await model.rename(entry, to: name) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete the selected items from the server?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) { Task { await model.deleteSelection() } }
        }
    }

    private func chooseUpload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { Task { await model.upload(panel.urls) } }
    }
}
