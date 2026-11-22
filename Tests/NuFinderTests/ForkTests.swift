import Foundation
import Testing
@testable import NuFinder

/// Pruebas de lo que añade el fork.
@Suite(.serialized) // el portapapeles compartido es global: sin paralelo
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

    @Test func contextMenuIsConfiguredPerType() {
        var stored = ""
        #expect(ContextMenuScope.allCases.allSatisfy { scope in scope.options.allSatisfy { ContextMenuSettings.isVisible($0, scope: scope, in: stored) } })
        stored = ContextMenuSettings.setting(.copy, scope: .folder, visible: false, in: stored)
        #expect(!ContextMenuSettings.isVisible(.copy, scope: .folder, in: stored))
        #expect(ContextMenuSettings.isVisible(.copy, scope: .file, in: stored))
        // Formato antiguo (sin tipo): oculto en todos; al mostrarlo en uno, los demás siguen ocultos.
        stored = ContextMenuSettings.setting(.checksums, scope: .file, visible: true, in: "checksums")
        #expect(ContextMenuSettings.isVisible(.checksums, scope: .file, in: stored))
        #expect(!ContextMenuSettings.isVisible(.checksums, scope: .folder, in: stored))
        #expect(!ContextMenuSettings.isVisible(.checksums, scope: .image, in: stored))
        stored = ContextMenuSettings.resetting(.folder, in: stored)
        #expect(ContextMenuSettings.isVisible(.checksums, scope: .folder, in: stored))
        #expect(!ContextMenuSettings.isVisible(.checksums, scope: .archive, in: stored))
        #expect(ContextMenuScope.folder.options.contains(.favorite) && !ContextMenuScope.file.options.contains(.favorite))
        #expect(ContextMenuScope.image.options.contains(.imageActions) && ContextMenuScope.archive.options.contains(.extract))
    }

    @Test func contextMenuOrderPerType() {
        #expect(ContextMenuSettings.order(.file, in: "") == ContextMenuScope.file.options)
        var moved = ContextMenuScope.folder.options
        moved.swapAt(0, moved.count - 1)
        var stored = ContextMenuSettings.setting(moved, for: .folder, in: "")
        #expect(ContextMenuSettings.order(.folder, in: stored) == moved)
        #expect(ContextMenuSettings.order(.file, in: stored) == ContextMenuScope.file.options)
        // Una opción que falta en el orden guardado vuelve a su sitio original.
        stored = "file=trash,open"
        let order = ContextMenuSettings.order(.file, in: stored)
        #expect(order.count == ContextMenuScope.file.options.count)
        #expect(order.first == .trash)
        #expect(Set(order) == Set(ContextMenuScope.file.options))
        #expect(order.firstIndex(of: .newFolder)! < order.firstIndex(of: .open)!) // va tras su vecina (Papelera)
        stored = ContextMenuSettings.setting(nil, for: .file, in: stored)
        #expect(stored.isEmpty)
    }

    @Test func statusBarSelectionSize() {
        let root = URL(filePath: "/tmp")
        let file = FileItem(url: root.appendingPathComponent("a"), name: "a", isDirectory: false, isSymbolicLink: false, size: 1000, modified: nil, created: nil, kind: "")
        let folder = FileItem(url: root.appendingPathComponent("b"), name: "b", isDirectory: true, isSymbolicLink: false, size: 0, modified: nil, created: nil, kind: "")
        let pending = StatusBarSettings.selectionBytes([file, folder]) { _ in nil }
        #expect(pending.bytes == 1000 && pending.pendingFolders == 1)
        let known = StatusBarSettings.selectionBytes([file, folder]) { _ in 500 }
        #expect(known.bytes == 1500 && known.pendingFolders == 0)
    }

    @Test func contextMenuTitlesMatchRealMenu() {
        #expect(ContextMenuOption.openInTerminal.title(in: .file) == "Open Parent in Terminal")
        #expect(ContextMenuOption.openInTerminal.title(in: .folder) == "Open in Terminal")
        #expect(ContextMenuOption.paste.title(in: .folder) == "Paste into Folder")
        #expect(ContextMenuOption.paste.title(in: .file) == "Paste")
    }

    @Test func rightClickSelectsLikeWindows() {
        let a = URL(filePath: "/tmp/a"), b = URL(filePath: "/tmp/b"), c = URL(filePath: "/tmp/c")
        #expect(RightClickSelection.selection(afterRightClickOn: b, current: [a]) == [b])
        #expect(RightClickSelection.selection(afterRightClickOn: b, current: []) == [b])
        #expect(RightClickSelection.selection(afterRightClickOn: b, current: [a, b, c]) == [a, b, c])
    }

    @Test func tableMarqueeSelection() {
        #expect(TableMarquee.selection(rows: [2, 3], base: [0], additive: false) == [2, 3])
        #expect(TableMarquee.selection(rows: [2, 3], base: [0], additive: true) == [0, 2, 3])
        #expect(TableMarquee.selection(rows: [], base: [1], additive: false).isEmpty)
    }

    @Test func toolbarColorPerAppearance() {
        #expect(AppearanceSettings.toolbarColorID(light: "blue", dark: "", scheme: .dark) == "blue")
        #expect(AppearanceSettings.toolbarColorID(light: "blue", dark: "#112233", scheme: .dark) == "#112233")
        #expect(AppearanceSettings.toolbarColorID(light: "blue", dark: "#112233", scheme: .light) == "blue")
        #expect(AppearanceSettings.hex(AppearanceSettings.color(hex: "#3366CC")!) == "#3366CC")
        #expect(AppearanceSettings.color(hex: "blue") == nil)
    }

    @Test func tabBarVisibility() {
        #expect(LayoutSettings.showsTabBar("always", tabCount: 1))
        #expect(!LayoutSettings.showsTabBar("multiple", tabCount: 1))
        #expect(LayoutSettings.showsTabBar("multiple", tabCount: 2))
        #expect(!LayoutSettings.showsTabBar("never", tabCount: 5))
    }

    @Test func cloudFolderNames() {
        #expect(SidebarExtras.cloudName("OneDrive-Personal") == "OneDrive (Personal)")
        #expect(SidebarExtras.cloudName("GoogleDrive-ana@x.com") == "Google Drive (ana@x.com)")
        #expect(SidebarExtras.cloudName("Dropbox") == "Dropbox")
    }

    @Test func textPredictionIsTurnedOff() {
        let defaults = UserDefaults(suiteName: "ForkTests.\(UUID().uuidString)")!
        TextPredictionSettings.apply(defaults)
        #expect(defaults.object(forKey: TextPredictionSettings.key) as? Bool == false)
    }

    @Test func folderSizeQueueSumsAndCancels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ForkTests-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(count: 1000).write(to: root.appendingPathComponent("a.bin"))
        try Data(count: 500).write(to: root.appendingPathComponent("sub/b.bin"))
        #expect(FolderSizeQueue.totalBytes(of: root) { false } == 1500)
        for i in 0..<250 { try Data().write(to: root.appendingPathComponent("f\(i)")) }
        #expect(FolderSizeQueue.totalBytes(of: root) { true } == nil)
    }

    @Test func backgroundWorkReturnsResult() async {
        let value = await BackgroundWork.run { 21 * 2 }
        #expect(value == 42)
    }

    @Test func fastLoaderMatchesOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ForkTests-fast-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("carpeta"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<300 { try Data(count: i).write(to: root.appendingPathComponent("f\(i).\(i % 3 == 0 ? "txt" : "png")")) }
        try Data().write(to: root.appendingPathComponent("sin-extension"))
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [])
        let fast = Dictionary(uniqueKeysWithValues: FastDirectoryLoader.items(urls).map { ($0.url, $0) })
        let original = urls.compactMap(FileItem.load)
        #expect(fast.count == original.count)
        for item in original {
            let other = try #require(fast[item.url])
            #expect(other.isDirectory == item.isDirectory && other.size == item.size && other.kind == item.kind && other.modified == item.modified)
        }
    }

    @Test func appIconMarginDefault() {
        #expect(AppIconService.defaultMargin == 0.10)
        #expect(UserDefaults.standard.object(forKey: AppIconService.marginKey) == nil || AppIconService.margin >= 0)
    }

    @Test func behaviorSettingsDefaultToOriginal() {
        let defaults = UserDefaults(suiteName: "ForkTests.\(UUID().uuidString)")!
        #expect(BehaviorSettings.restoresTabs(defaults))
        #expect(BehaviorSettings.startURL(defaults) == nil)
        defaults.set("downloads", forKey: BehaviorSettings.startFolderKey)
        #expect(BehaviorSettings.startURL(defaults)?.lastPathComponent == "Downloads")
        #expect(BehaviorSettings.folderURL("/no/existe") == nil)
    }
}
