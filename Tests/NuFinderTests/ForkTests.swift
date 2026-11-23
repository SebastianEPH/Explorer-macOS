import Foundation
import Combine
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

    @Test func appIconDefaultIsSquareWindow() {
        #expect(AppIconService.defaultID == "window-square")
        #expect(AppIconDesign.all.contains { $0.id == AppIconService.defaultID })
    }

    @Test func menuBarHidesEmojiByDefault() {
        let defaults = UserDefaults(suiteName: "ForkTests.\(UUID().uuidString)")!
        MenuBarSettings.applySystemItems(defaults)
        #expect(defaults.bool(forKey: "NSDisabledCharacterPaletteMenuItem"))
        defaults.set(false, forKey: MenuBarSettings.hidesEmojiKey)
        MenuBarSettings.applySystemItems(defaults)
        #expect(!defaults.bool(forKey: "NSDisabledDictationMenuItem"))
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

    @Test @MainActor func splitPaneIsPerWindow() throws {
        let suite = "ForkTests.split.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let panes = WindowSplitPanes(defaults: defaults)
        let first = BrowserModel(initialURL: URL(fileURLWithPath: "/tmp"), restoresSession: false, defaults: defaults)
        let second = BrowserModel(initialURL: URL(fileURLWithPath: "/tmp"), restoresSession: false, defaults: defaults)
        #expect(!panes.isOn(first) && !panes.isOn(second))
        panes.set(false, for: second)
        panes.toggle(first)
        #expect(panes.isOn(first))
        #expect(!panes.isOn(second)) // la otra ventana no cambia
        let third = BrowserModel(initialURL: URL(fileURLWithPath: "/tmp"), restoresSession: false, defaults: defaults)
        #expect(panes.isOn(third)) // la nueva empieza como la última usada
    }

    @Test func removedWorkspacesDataIsCleaned() throws {
        let suite = "ForkTests.ws.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("x", forKey: "launchWorkspaceID")
        defaults.set(Data(), forKey: "savedWorkspaces")
        defaults.set(true, forKey: "showsSplitPane")
        RemovedFeatures.cleanDefaults(defaults)
        #expect(defaults.object(forKey: "launchWorkspaceID") == nil)
        #expect(defaults.object(forKey: "savedWorkspaces") == nil)
        #expect(defaults.bool(forKey: "showsSplitPane")) // lo demás se conserva
    }

    // MARK: valores por defecto propios

    @Test func myDefaultsApplyOnlyWhenNothingSaved() throws {
        let d = try #require(UserDefaults(suiteName: "ForkTests.defaults.\(UUID().uuidString)"))
        let reg = UserDefaults.registrationDomain
        let savedReg = UserDefaults.standard.volatileDomain(forName: reg)
        defer { UserDefaults.standard.setVolatileDomain(savedReg, forName: reg) }
        DefaultSettings.register(d) // en pruebas no es la app instalada: no registra
        #expect(d.string(forKey: "view.default") == nil)
        DefaultSettings.register(d, force: true)
        #expect(d.string(forKey: "view.default") == "Icons")
        #expect(d.bool(forKey: "layout.compactTop"))
        d.set("List", forKey: "view.default")
        #expect(d.string(forKey: "view.default") == "List", "lo que cambio se guarda y manda")
    }

    /// Flujo: cambio un ajuste → se escribe el archivo → al «reiniciar» (dominio vacío,
    /// como si macOS no hubiera cargado mis ajustes) arranca con lo último que dejé.
    @Test func lastChangesBecomeDefaultsAfterRestart() throws {
        let suite = "ForkTests.snap.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
        let reg = UserDefaults.registrationDomain
        let savedReg = UserDefaults.standard.volatileDomain(forName: reg)
        defer { UserDefaults.standard.setVolatileDomain(savedReg, forName: reg) }
        d.set("Columns", forKey: "view.default")
        d.set("{1,2}", forKey: "NSWindow Frame x")
        DefaultSettings.saveSnapshot(d, domain: suite, file: file)
        d.removePersistentDomain(forName: suite)
        #expect(d.string(forKey: "view.default") == nil)
        DefaultSettings.register(d, force: true, file: file)
        #expect(d.string(forKey: "view.default") == "Columns", "no arrancó con lo último que dejé")
        #expect(d.bool(forKey: "layout.compactTop"), "falta mi configuración base")
        #expect(d.object(forKey: "NSWindow Frame x") == nil, "guardó estado de ventanas")
    }

    /// «Finder abre Explorer» se quitó de raíz: su ajuste guardado se borra al arrancar.
    @Test func finderRedirectSettingIsRemoved() throws {
        let d = try #require(UserDefaults(suiteName: "ForkTests.finder.\(UUID().uuidString)"))
        d.set(true, forKey: "finderRedirect.enabled")
        RemovedFeatures.cleanDefaults(d)
        #expect(d.object(forKey: "finderRedirect.enabled") == nil)
        #expect(DefaultSettings.mine["finderRedirect.enabled"] == nil)
    }

    // MARK: nube (File Provider)

    @Test func cloudStateMapsFinderValues() {
        #expect(CloudItemState.from(isUbiquitous: false, status: .notDownloaded, isDownloading: false, isUploading: false, hasError: false) == nil)
        #expect(CloudItemState.from(isUbiquitous: true, status: .notDownloaded, isDownloading: false, isUploading: false, hasError: false) == .cloudOnly)
        #expect(CloudItemState.from(isUbiquitous: true, status: .current, isDownloading: false, isUploading: false, hasError: false) == .downloaded)
        #expect(CloudItemState.from(isUbiquitous: true, status: .notDownloaded, isDownloading: true, isUploading: false, hasError: false) == .downloading)
        #expect(CloudItemState.from(isUbiquitous: true, status: .current, isDownloading: false, isUploading: true, hasError: false) == .uploading)
        #expect(CloudItemState.from(isUbiquitous: true, status: .current, isDownloading: false, isUploading: true, hasError: true) == .error)
    }

    @Test func normalFilesHaveNoCloudState() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(CloudStatus.read(file) == nil)
    }

    @Test func cloudMenuOptionsOnlyForMatchingState() throws {
        let d = try #require(UserDefaults(suiteName: "ForkTests.cloud.\(UUID().uuidString)"))
        let saved = CloudStatus.provider
        defer { CloudStatus.provider = saved }
        let url = URL(fileURLWithPath: "/tmp/x.docx")
        CloudStatus.provider = { _ in .cloudOnly }
        #expect(CloudStatus.menuAllows(.cloudDownload, url, store: d))
        #expect(!CloudStatus.menuAllows(.cloudEvict, url, store: d))
        CloudStatus.provider = { _ in .downloaded }
        #expect(CloudStatus.menuAllows(.cloudEvict, url, store: d))
        #expect(!CloudStatus.menuAllows(.cloudDownload, url, store: d))
        CloudStatus.provider = { _ in nil }
        #expect(!CloudStatus.menuAllows(.cloudDownload, url, store: d), "salió en un archivo normal")
        #expect(CloudStatus.menuAllows(.copy, url, store: d), "afectó a otras opciones")
        CloudStatus.provider = { _ in .cloudOnly }
        d.set(false, forKey: CloudStatus.menuKey)
        #expect(!CloudStatus.menuAllows(.cloudDownload, url, store: d), "salió con la opción apagada")
    }

    @Test func cloudOptionsAreInItemMenusOnly() {
        for scope in ContextMenuScope.allCases {
            #expect(scope.options.contains(.cloudDownload) == (scope != .background))
        }
        #expect(CloudStatus.defaults[CloudStatus.enabledKey] as? Bool == true)
        #expect(CloudStatus.defaults[CloudStatus.showDownloadedKey] as? Bool == false, "Finder no marca los descargados")
    }

    /// «Abrir carpetas en una pestaña nueva» se quitó: se borra lo guardado y no viene por defecto.
    @Test func foldersInNewTabSettingIsRemoved() throws {
        let d = try #require(UserDefaults(suiteName: "ForkTests.newtab.\(UUID().uuidString)"))
        d.set(true, forKey: "open.foldersInNewTab")
        RemovedFeatures.cleanDefaults(d)
        #expect(d.object(forKey: "open.foldersInNewTab") == nil)
        #expect(DefaultSettings.mine["open.foldersInNewTab"] == nil)
    }

    // MARK: pestañas en memoria

    @Test func tabMemoryKeepsHistoryAndFreesWhatIsNotUsed() {
        let store = FolderMemoryStore(watchPressure: false)
        let memory = TabMemory(store: store)
        let tab = UUID()
        let a = URL(fileURLWithPath: "/tmp/A"), b = URL(fileURLWithPath: "/tmp/B"), c = URL(fileURLWithPath: "/tmp/C")
        let items = [FileItem.load(URL(fileURLWithPath: "/tmp"))].compactMap { $0 }
        memory.save(tab: tab, url: a, hidden: false, items: items, history: [a], enabled: true, keepsHistory: true, budget: .max)
        memory.save(tab: tab, url: b, hidden: false, items: items, history: [a, b], enabled: true, keepsHistory: true, budget: .max)
        #expect(store.folderCount == 2, "no guardó la carpeta del historial")
        #expect(memory.restore(tab: tab, url: a, hidden: false, enabled: true) != nil, "atrás no es instantáneo")
        // A sale del historial (se navegó a C desde B tras volver) → se libera
        memory.save(tab: tab, url: c, hidden: false, items: items, history: [b, c], enabled: true, keepsHistory: true, budget: .max)
        #expect(store.items(tab: tab, url: a, hidden: false) == nil, "una carpeta fuera del historial sigue en RAM")
        // sin historial: solo la actual
        memory.save(tab: tab, url: c, hidden: false, items: items, history: [b, c], enabled: true, keepsHistory: false, budget: .max)
        #expect(store.folderCount == 1)
        // ocultos distinto → no sirve
        memory.clearShown()
        #expect(memory.restore(tab: tab, url: c, hidden: true, enabled: true) == nil)
        // carpeta con error → se descarta
        memory.discard(tab: tab, url: c)
        #expect(store.folderCount == 0)
        // cerrar pestaña → se libera
        memory.save(tab: tab, url: a, hidden: false, items: items, history: [a], enabled: true, keepsHistory: true, budget: .max)
        memory.forget(tab)
        #expect(store.folderCount == 0 && store.usedBytes == 0, "cerrar la pestaña no liberó la RAM")
        // apagado → vacía
        memory.save(tab: tab, url: a, hidden: false, items: items, history: [a], enabled: true, keepsHistory: true, budget: .max)
        _ = memory.restore(tab: tab, url: a, hidden: false, enabled: false)
        #expect(store.folderCount == 0)
    }

    @Test func folderMemoryRespectsBudgetAndWindowClose() {
        let store = FolderMemoryStore(watchPressure: false)
        let items = [FileItem.load(URL(fileURLWithPath: "/tmp"))].compactMap { $0 }
        let one = FolderMemoryStore.estimate(items)
        var memory: TabMemory? = TabMemory(store: store)
        let t1 = UUID(), t2 = UUID(), t3 = UUID()
        for (tab, name) in [(t1, "1"), (t2, "2"), (t3, "3")] {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            memory?.save(tab: tab, url: url, hidden: false, items: items, history: [url], enabled: true, keepsHistory: true, budget: one * 2)
        }
        #expect(store.folderCount == 2, "se pasó del presupuesto")
        #expect(!store.has(tab: t1), "debía soltar la usada hace más tiempo")
        memory = nil // cerrar la ventana
        #expect(store.folderCount == 0, "cerrar la ventana no liberó la RAM")
        store.save(tab: t1, url: URL(fileURLWithPath: "/tmp/x"), hidden: false, items: items)
        store.clear() // lo que hace el aviso de memoria de macOS
        #expect(store.usedBytes == 0)
    }

    @Test func memoryBudgetUsesTheMac() {
        #expect(MemoryBudget.automaticMB(physical: 48 * 1024) == 1966, "48 GB → ~1,9 GB")
        #expect(MemoryBudget.automaticMB(physical: 4 * 1024) == 256)
        #expect(MemoryBudget.automaticMB(physical: 256 * 1024) == 4096)
    }

    // MARK: iconos ya dibujados (fluidez)

    private func iconFolder(_ files: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IconCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in files { try Data("x".utf8).write(to: url.appendingPathComponent(file)) }
        return url
    }

    @Test func iconCacheSharesByTypeAndKeepsOwnIcons() throws {
        let dir = try iconFolder(["a.pdf", "b.pdf", "c.zip"])
        let sub = dir.appendingPathComponent("Carpeta", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let a = try #require(FileItem.load(dir.appendingPathComponent("a.pdf")))
        let b = try #require(FileItem.load(dir.appendingPathComponent("b.pdf")))
        let c = try #require(FileItem.load(dir.appendingPathComponent("c.zip")))
        let folder = try #require(FileItem.load(sub))
        #expect(IconCache.key(for: a, pixels: 80) == IconCache.key(for: b, pixels: 80), "dos PDF deben compartir icono")
        #expect(IconCache.key(for: a, pixels: 80) != IconCache.key(for: c, pixels: 80))
        #expect(IconCache.key(for: a, pixels: 80) != IconCache.key(for: a, pixels: 160), "cada tamaño su icono")
        #expect(IconCache.key(for: folder, pixels: 80).hasPrefix("path:"), "las carpetas pueden tener icono propio")
        IconCache.clear()
        let first = IconCache.icon(for: a, size: 40, enabled: true)
        #expect(IconCache.icon(for: b, size: 40, enabled: true) === first, "no se reutilizó")
        #expect(first.representations.count == 1, "debe ser un solo mapa de bits ya dibujado")
        #expect(IconCache.icon(for: a, size: 40, enabled: false) !== first, "apagado debe ser como el original")
    }

    /// Redibujar 60 iconos ya guardados debe caber de sobra en un fotograma (16 ms).
    @Test func cachedIconsRedrawWithinOneFrame() throws {
        let names = (0..<60).map { "f\($0).\(["pdf", "zip", "xlsx", "apk", "txt", "html"][$0 % 6])" }
        let dir = try iconFolder(names)
        let items = names.compactMap { FileItem.load(dir.appendingPathComponent($0)) }
        IconCache.clear()
        for item in items { _ = IconCache.icon(for: item, size: 40, enabled: true) }
        let start = Date()
        for item in items {
            _ = IconCache.icon(for: item, size: 40, enabled: true).cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        let ms = Date().timeIntervalSince(start) * 1000
        #expect(ms < 16, "redibujar 60 iconos tardó \(ms) ms")
    }

    // MARK: fluidez del menú contextual (se arma en cada redibujo de cada archivo)

    /// 58 archivos × todas las opciones, con mi lista de ocultos: debe caber de sobra en un fotograma.
    @Test func contextMenuVisibilityIsCheapPerRedraw() {
        let stored = DefaultSettings.mine[ContextMenuSettings.hiddenKey] as? String ?? ""
        #expect(stored.count > 500)
        _ = ContextMenuSettings.isVisible(.open, scope: .file, in: stored)
        let start = Date()
        for _ in 0..<58 {
            for option in ContextMenuSettings.order(.file, in: "") {
                _ = ContextMenuSettings.isVisible(option, scope: .file, in: stored)
            }
        }
        let ms = Date().timeIntervalSince(start) * 1000
        #expect(ms < 2, "armar los menús de 58 archivos tardó \(ms) ms")
    }

    /// Armar el menú no debe leer el disco por cada archivo y opción: el estado de la nube
    /// se reutiliza mientras está fresco.
    @Test func cloudMenuDoesNotReadDiskOnEveryRedraw() {
        let saved = CloudStatus.provider
        defer { CloudStatus.provider = saved; CloudStatus.resetCache() }
        var reads = 0
        let url = URL(fileURLWithPath: "/tmp/menu-\(UUID().uuidString).txt")
        // Solo este archivo: otras pruebas en paralelo dibujan ventanas que también preguntan.
        CloudStatus.provider = { if $0.path == url.path { reads += 1 }; return nil }
        CloudStatus.resetCache()
        for _ in 0..<20 {
            _ = CloudStatus.menuAllows(.cloudDownload, url)
            _ = CloudStatus.menuAllows(.cloudEvict, url)
        }
        #expect(reads == 1, "leyó el disco \(reads) veces para el mismo archivo")
    }

    /// El puntero solo avisa cuando cambia de archivo, y salir de uno ajeno no borra el actual.
    @Test func hoverTrackerOnlyPublishesRealChanges() {
        let tracker = HoverTracker()
        var changes = 0
        let sub = tracker.objectWillChange.sink { changes += 1 }
        defer { sub.cancel() }
        let a = URL(fileURLWithPath: "/tmp/a"), b = URL(fileURLWithPath: "/tmp/b")
        tracker.set(a, inside: true)
        tracker.set(a, inside: true)
        #expect(changes == 1, "avisó sin cambiar de archivo")
        tracker.set(b, inside: true)
        tracker.set(a, inside: false)
        #expect(tracker.url == b, "salir de otro archivo borró el actual")
        tracker.set(b, inside: false)
        #expect(tracker.url == nil)
        #expect(SmoothScrolling.isEnabled || UserDefaults.standard.object(forKey: SmoothScrolling.enabledKey) != nil)
    }
}
