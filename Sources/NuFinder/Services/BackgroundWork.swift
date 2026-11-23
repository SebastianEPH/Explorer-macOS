import Foundation

/// Fork: trabajo pesado fuera del grupo de hilos de Swift (async/await).
///
/// Las tareas `Task.detached` que hacen trabajo bloqueante (recorrer carpetas enteras) ocupan
/// los pocos hilos de ese grupo; mientras tanto, abrir una carpeta tenía que esperar turno y
/// se veía «cargando». Con estas colas eso ya no pasa.
enum BackgroundWork {
    /// Ejecuta `work` en una cola de GCD y espera el resultado sin ocupar hilos de Swift.
    static func run<T: Sendable>(qos: DispatchQoS.QoSClass = .userInitiated, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: qos).async { continuation.resume(returning: work()) }
        }
    }
}

/// Cola propia para el tamaño de las carpetas: como mucho 2 a la vez y se pueden cancelar
/// (por ejemplo al salir de la carpeta antes de que terminen).
final class FolderSizeQueue: @unchecked Sendable {
    static let shared = FolderSizeQueue()
    static let autoKey = "files.autoFolderSizes"

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()
    private let lock = NSLock()
    private var operations: [URL: Operation] = [:]

    /// Calcula el tamaño de `url` y llama a `done` en el hilo principal (no se llama si se cancela).
    func calculate(_ url: URL, done: @escaping @MainActor (Int64) -> Void) {
        queue.maxConcurrentOperationCount = FolderSizeParallel.current // Fork: Ajustes → Archivos
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard let operation else { return }
            let bytes = Self.totalBytes(of: url) { operation.isCancelled }
            guard !operation.isCancelled, let bytes else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(bytes) } }
        }
        operation.completionBlock = { [weak self] in self?.remove(url) }
        lock.withLock { operations[url]?.cancel(); operations[url] = operation }
        queue.addOperation(operation)
    }

    func cancel(_ url: URL) {
        lock.withLock { operations[url]?.cancel(); operations[url] = nil }
    }

    /// Fork: cancela todo lo que esté dentro de `root` (p. ej. antes de expulsar un disco).
    func cancelAll(under root: URL) {
        let prefix = root.standardizedFileURL.path
        lock.withLock {
            for (url, operation) in operations where url.standardizedFileURL.path.hasPrefix(prefix) {
                operation.cancel()
                operations[url] = nil
            }
        }
    }

    private func remove(_ url: URL) {
        lock.withLock { if operations[url]?.isFinished == true || operations[url]?.isCancelled == true { operations[url] = nil } }
    }

    /// Suma los archivos de la carpeta; devuelve nil si se cancela a mitad.
    static func totalBytes(of url: URL, isCancelled: () -> Bool) -> Int64? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]
        ) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            if count % 200 == 0, isCancelled() { return nil }
            if let values = try? child.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}
