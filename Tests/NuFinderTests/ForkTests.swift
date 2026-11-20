import Foundation
import Testing
@testable import NuFinder

/// Pruebas de lo que añade el fork.
struct ForkTests {
    @MainActor
    private func loadedBrowser(at root: URL) async throws -> BrowserModel {
        let suite = "ForkTests.\(UUID().uuidString)"
        let browser = BrowserModel(initialURL: root, restoresSession: false, defaults: UserDefaults(suiteName: suite)!)
        for _ in 0..<200 where browser.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!browser.isLoading)
        return browser
    }

    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // b.txt el más grande, c.txt el más antiguo
        try Data(count: 10).write(to: root.appendingPathComponent("a.txt"))
        try Data(count: 3000).write(to: root.appendingPathComponent("b.txt"))
        try Data(count: 500).write(to: root.appendingPathComponent("c.txt"))
        let old = Date(timeIntervalSinceNow: -86_400 * 30)
        try FileManager.default.setAttributes([.modificationDate: old, .creationDate: old],
                                              ofItemAtPath: root.appendingPathComponent("c.txt").path)
        return root
    }

    @Test @MainActor func clickingColumnHeaderReordersList() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let browser = try await loadedBrowser(at: root)
        #expect(browser.displayedItems.map(\.name) == ["a.txt", "b.txt", "c.txt"])

        // Clic en «Tamaño»: de menor a mayor
        browser.columnSortOrder.wrappedValue = [ColumnSortComparator(field: .size, order: .forward)]
        #expect(browser.displayedItems.map(\.name) == ["a.txt", "c.txt", "b.txt"])

        // Segundo clic: de mayor a menor
        browser.columnSortOrder.wrappedValue = [ColumnSortComparator(field: .size, order: .reverse)]
        #expect(browser.displayedItems.map(\.name) == ["b.txt", "c.txt", "a.txt"])
        #expect(browser.columnSortOrder.wrappedValue.first?.order == .reverse)

        // Fecha de modificación: el más antiguo primero
        browser.columnSortOrder.wrappedValue = [ColumnSortComparator(field: .modified, order: .forward)]
        #expect(browser.displayedItems.first?.name == "c.txt")

        // Fecha de creación: el más antiguo primero
        browser.columnSortOrder.wrappedValue = [ColumnSortComparator(field: .created, order: .forward)]
        #expect(browser.displayedItems.first?.name == "c.txt")
    }

    @Test func comparatorMatchesItsColumn() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let items = try ["a.txt", "b.txt", "c.txt"].map { name -> FileItem in
            let url = root.appendingPathComponent(name)
            return try #require(FileItem.load(url))
        }
        let bySize = items.sorted(using: ColumnSortComparator(field: .size))
        #expect(bySize.map(\.name) == ["a.txt", "c.txt", "b.txt"])
        let byCreatedDesc = items.sorted(using: ColumnSortComparator(field: .created, order: .reverse))
        #expect(byCreatedDesc.last?.name == "c.txt")
    }

    @Test @MainActor func sharedClipboardIsVisibleFromAnotherWindow() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root); SharedClipboard.urls = [] }
        let first = try await loadedBrowser(at: root)
        let second = try await loadedBrowser(at: root)
        first.selection = [root.appendingPathComponent("a.txt")]
        first.cutSelection()
        #expect(second.canPaste)
    }

    @Test @MainActor func favoritesCanBeHiddenRenamedAndRestored() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locations = [FavoriteLocation(url: home, title: "Home", icon: "house", isBuiltIn: true)]
        defer {
            FavoritesSettings.setTitle("", home)
            FavoritesSettings.setIcon(nil, home)
            FavoritesSettings.setHidden(false, home)
        }
        FavoritesSettings.setTitle("Casa", home)
        FavoritesSettings.setIcon("star", home)
        #expect(FavoritesSettings.visible(locations).first?.title == "Casa")
        #expect(FavoritesSettings.visible(locations).first?.icon == "star")
        FavoritesSettings.setHidden(true, home)
        #expect(FavoritesSettings.visible(locations).isEmpty)
        FavoritesSettings.setHidden(false, home)
        FavoritesSettings.setTitle("", home)
        #expect(FavoritesSettings.visible(locations).first?.title == "Home")
    }

    @Test @MainActor func cuttingTwoFilesKeepsBothAndPastesBoth() async throws {
        let root = try makeFolder()
        let target = root.appendingPathComponent("destino", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); SharedClipboard.urls = [] }
        let browser = try await loadedBrowser(at: root)
        browser.selection = [root.appendingPathComponent("a.txt"), root.appendingPathComponent("b.txt")]
        browser.cutSelection()
        #expect(SharedClipboard.urls.count == 2)
        #expect(SharedClipboard.isCut)
        let other = try await loadedBrowser(at: target)
        let operations = FileOperationManager()
        operations.conflictPolicy = .keepBoth
        await other.paste(into: target, operations: operations)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("a.txt").path))
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("b.txt").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("a.txt").path))
        #expect(SharedClipboard.urls.isEmpty)
    }
}
