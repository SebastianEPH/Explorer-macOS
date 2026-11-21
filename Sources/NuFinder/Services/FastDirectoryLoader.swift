import Foundation
import UniformTypeIdentifiers

/// Fork: lectura rápida de los datos de una carpeta con muchos archivos.
///
/// Medido en una carpeta de 205.617 archivos: el original tardaba ~9,8 s porque pedía a macOS,
/// archivo por archivo, el tipo («Imagen WebP»), que es lo más lento. Aquí el tipo se calcula
/// una vez por extensión y el resto de datos se lee en paralelo (~0,3 s). El resultado es el mismo
/// que `FileItem.load`.
enum FastDirectoryLoader {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
        .creationDateKey, .isHiddenKey, .isSymbolicLinkKey
    ]

    static func items(_ urls: [URL]) -> [FileItem] {
        let count = urls.count
        guard count > 200 else { return urls.compactMap(FileItem.load) } // carpetas normales: como siempre
        let chunks = min(32, max(1, ProcessInfo.processInfo.activeProcessorCount * 2))
        let kinds = KindCache()
        let parts = Parts(count: chunks)
        DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
            let start = chunk * count / chunks, end = (chunk + 1) * count / chunks
            var local: [FileItem] = []
            local.reserveCapacity(end - start)
            for index in start..<end {
                if let item = load(urls[index], kinds: kinds) { local.append(item) }
            }
            parts.set(chunk, local)
        }
        return parts.all
    }

    private static func load(_ url: URL, kinds: KindCache) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isSymbolicLink = values.isSymbolicLink ?? false
        let isDirectory = values.isDirectory == true ||
            (isSymbolicLink && FileItem.isNavigableDirectory(url.resolvingSymlinksInPath()))
        let kind: String
        let ext = url.pathExtension.lowercased()
        if isDirectory || isSymbolicLink || ext.isEmpty {
            // Carpetas, apps, enlaces y archivos sin extensión: el tipo exacto de macOS.
            kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
                ?? (isDirectory ? "Folder" : "File")
        } else {
            kind = kinds.kind(forExtension: ext, url: url)
        }
        return FileItem(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate,
            created: values.creationDate,
            kind: kind
        )
    }

    /// Resultados de cada trozo, escritos desde varios hilos.
    final class Parts: @unchecked Sendable {
        private var parts: [[FileItem]]
        private let lock = NSLock()
        init(count: Int) { parts = Array(repeating: [], count: count) }
        func set(_ index: Int, _ items: [FileItem]) { lock.withLock { parts[index] = items } }
        var all: [FileItem] { lock.withLock { parts.flatMap { $0 } } }
    }

    /// Tipo por extensión, compartido entre hilos.
    final class KindCache: @unchecked Sendable {
        private var cache: [String: String] = [:]
        private let lock = NSLock()

        func kind(forExtension ext: String, url: URL) -> String {
            if let cached = lock.withLock({ cache[ext] }) { return cached }
            let kind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
                ?? UTType(filenameExtension: ext)?.localizedDescription
                ?? "File"
            lock.withLock { cache[ext] = kind }
            return kind
        }
    }
}
