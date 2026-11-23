import AppKit
import Foundation
import Testing
@testable import NuFinder

/// Ordenar por tamaño tiene que tener en cuenta el tamaño ya calculado de las carpetas
/// (antes valía 0 y las carpetas, que van arriba, no cambiaban de sitio con ningún clic).
@Suite(.serialized) @MainActor
struct FolderSizeSortTests {
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SizeSort-\(UUID().uuidString)")
        for name in ["mediana", "grande", "chica"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data(count: 50).write(to: root.appendingPathComponent("x.txt"))
        try Data(count: 5).write(to: root.appendingPathComponent("y.txt"))
        return root
    }

    private let fake: [String: Int64] = ["chica": 100, "mediana": 5_000, "grande": 900_000]

    private func browser(at root: URL, on: Bool = true) async throws -> BrowserModel {
        let d = UserDefaults(suiteName: "SizeSort.\(UUID().uuidString)")!
        d.set(on, forKey: FolderSizeSort.key)
        FolderSizeSort.defaults = d
        let b = BrowserModel(initialURL: root, restoresSession: false, defaults: d)
        for _ in 0..<200 where b.items.count != 5 { try await Task.sleep(for: .milliseconds(20)) }
        return b
    }

    private func folders(_ b: BrowserModel) -> [String] { b.items.filter(\.isDirectory).map(\.name) }

    @Test func defaults() {
        #expect(UserDefaults(suiteName: "SizeSort.\(UUID().uuidString)")!.object(forKey: FolderSizeSort.key) == nil)
        #expect(DefaultSettings.mine[FolderSizeSort.key] as? Bool == true)
    }

    // Flujo: clic en «Tamaño» → menor a mayor → clic → mayor a menor → clic → otra vez (cada clic hace caso).
    @Test func everyClickOnSizeReordersFolders() async throws {
        FolderSizeSort.folderSize = { [fake] in fake[$0.name] }
        defer { FolderSizeSort.reset() }
        let b = try await browser(at: try makeFolder())
        var orders: [[String]] = []
        for ascending in [true, false, true, false] {
            b.columnSortOrder.wrappedValue = [ColumnSortComparator(field: .size, order: ascending ? .forward : .reverse)]
            orders.append(folders(b))
        }
        let up = ["chica", "mediana", "grande"]
        #expect(orders == [up, up.reversed(), up, up.reversed()], "\(orders)")
        #expect(b.items.first?.isDirectory == true, "las carpetas siguen arriba")
    }

    // Los tamaños llegan después de ordenar: al llegar, se vuelve a ordenar.
    @Test func resortsWhenSizesArrive() async throws {
        FolderSizeSort.folderSize = { _ in nil }
        defer { FolderSizeSort.reset() }
        let b = try await browser(at: try makeFolder())
        b.columnSortOrder.wrappedValue = [ColumnSortComparator(field: .size, order: .reverse)]
        FolderSizeSort.folderSize = { [fake] in fake[$0.name] }
        b.resortForFolderSizes()
        #expect(folders(b) == ["grande", "mediana", "chica"])
    }

    @Test func offKeepsOriginal() async throws {
        FolderSizeSort.folderSize = { [fake] in fake[$0.name] }
        defer { FolderSizeSort.reset() }
        let b = try await browser(at: try makeFolder(), on: false)
        b.columnSortOrder.wrappedValue = [ColumnSortComparator(field: .size, order: .reverse)]
        #expect(folders(b) == ["chica", "grande", "mediana"], "apagado: carpetas valen 0 → por nombre, como el original")
    }
}
