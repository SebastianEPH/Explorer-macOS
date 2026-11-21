import Foundation

@MainActor
final class FolderSizeService: ObservableObject {
    static let shared = FolderSizeService()

    struct Entry {
        let bytes: Int64
        let modified: Date?
    }

    @Published private(set) var entries: [URL: Entry] = [:]
    @Published private(set) var calculating: Set<URL> = []

    private init() {}

    func size(for item: FileItem) -> Int64? {
        guard let entry = entries[item.url], entry.modified == item.modified else { return nil }
        return entry.bytes
    }

    func calculate(_ item: FileItem) {
        guard item.isDirectory, size(for: item) == nil, !calculating.contains(item.url) else { return }
        calculating.insert(item.url)
        let url = item.url
        let modified = item.modified
        // Fork: cola propia (máx. 2 a la vez, cancelable) para no bloquear la apertura de carpetas.
        FolderSizeQueue.shared.calculate(url) { [weak self] bytes in
            self?.entries[url] = Entry(bytes: bytes, modified: modified)
            self?.calculating.remove(url)
        }
    }

    /// Fork: deja de calcular una carpeta que ya no se ve.
    func cancel(_ item: FileItem) {
        guard calculating.contains(item.url) else { return }
        FolderSizeQueue.shared.cancel(item.url)
        calculating.remove(item.url)
    }

    func invalidate(_ url: URL) {
        entries[url] = nil
    }
}
