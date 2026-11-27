import AppKit
import SwiftUI
import Testing
@testable import NuFinder

/// Pruebas con ventanas reales: abren ventanas, esperan a que SwiftUI las dibuje y
/// revisan lo que se ve (barra de arriba, ruta de la ventana, menú del clic derecho).
@Suite(.serialized) @MainActor
struct WindowUITests {
    /// Espera sin bloquear: deja que SwiftUI dibuje y que la carpeta termine de cargar.
    private func spin(_ seconds: Double = 0.5) async throws {
        _ = NSApplication.shared
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private func folder(_ name: String, files: [String] = []) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowUITests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in files { try Data("x".utf8).write(to: url.appendingPathComponent(file)) }
        return url.standardizedFileURL
    }

    private func openWindow(at url: URL) async throws -> NSWindow {
        let before = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        WindowService.open(at: url)
        try await spin()
        return try #require(try await TestWindows.window(at: url, excluding: before))
    }

    /// Menú del clic derecho sobre la primera fila de la lista (vista de lista, un `NSTableView`).
    private func firstRowMenu(in window: NSWindow) -> [String]? {
        func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, table.numberOfRows > 0 { return table }
            return view.subviews.lazy.compactMap(table(in:)).first
        }
        guard let content = window.contentView, let table = table(in: content),
              let row = table.rowView(atRow: 0, makeIfNecessary: true) else { return nil }
        func menus(in view: NSView) -> [String]? {
            let center = view.convert(NSPoint(x: min(60, view.bounds.width / 2), y: view.bounds.midY), to: nil)
            if let event = NSEvent.mouseEvent(
                with: .rightMouseDown, location: center, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
               let menu = view.menu(for: event), !menu.items.isEmpty {
                return menu.items.map(\.title)
            }
            return view.subviews.lazy.compactMap(menus(in:)).first
        }
        return menus(in: row)
    }

    // MARK: ventanas

    @Test func newWindowHasSameTopBarAsMainWindow() async throws {
        let url = try folder("toolbar")
        let window = try await openWindow(at: url)
        defer { window.close() }
        #expect(window.toolbar != nil, "la ventana nueva no tiene barra de arriba")
        #expect((window.toolbar?.items.count ?? 0) > 0)
        #expect(window.tabbingMode == .disallowed)
    }

    @Test func eachWindowShowsItsOwnFolder() async throws {
        let first = try folder("first"), second = try folder("second")
        let a = try await openWindow(at: first)
        let b = try await openWindow(at: second)
        defer { a.close(); b.close() }
        try await spin()
        #expect(a.representedURL?.standardizedFileURL == first, "la ventana anterior recibió la ruta de la nueva")
        #expect(b.representedURL?.standardizedFileURL == second)
    }

    @Test func closingWindowDoesNotCrashAndReopensSameFolder() async throws {
        let url = try folder("reopen")
        let window = try await openWindow(at: url)
        let path = try #require(window.representedURL)
        window.close()
        try await spin(0.2)
        #expect(!WindowLifetime.windows.contains(window))
        WindowService.recordClosedWindow(at: path)
        let reopened = try await openWindow(at: url) // lo mismo que hace «Reabrir ventana cerrada»
        defer { reopened.close() }
        #expect(reopened.representedURL?.standardizedFileURL == url)
    }

    @Test func splitPaneOfOneWindowDoesNotChangeTheOther() async throws {
        let a = try await openWindow(at: try folder("splitA"))
        let b = try await openWindow(at: try folder("splitB"))
        defer { a.close(); b.close() }
        let browserA = try #require(KeyWindowFocus.shared.browser(for: a))
        let browserB = try #require(KeyWindowFocus.shared.browser(for: b))
        #expect(browserA !== browserB, "dos ventanas comparten el mismo modelo")
        let wasOn = WindowSplitPanes.shared.isOn(browserB)
        WindowSplitPanes.shared.set(!WindowSplitPanes.shared.isOn(browserA), for: browserA)
        #expect(WindowSplitPanes.shared.isOn(browserB) == wasOn)
        WindowSplitPanes.shared.set(false, for: browserA)
    }

    // MARK: menú contextual

    @Test func contextMenuFollowsSettingsAfterChange() async throws {
        let defaults = UserDefaults.standard
        let savedHidden = defaults.string(forKey: ContextMenuSettings.hiddenKey)
        defer { defaults.set(savedHidden, forKey: ContextMenuSettings.hiddenKey) }
        defaults.set("", forKey: ContextMenuSettings.hiddenKey)

        let url = try folder("menu", files: ["nota.txt"])
        let window = try await openWindow(at: url)
        defer { window.close() }
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        for _ in 0..<40 where browser.displayedItems.isEmpty { try await spin(0.1) }
        browser.viewMode = .list
        try await spin(1)
        let before = try #require(firstRowMenu(in: window), "no se encontró el menú de la fila del archivo")
        #expect(before.contains("Copy Path"), "menú del archivo antes de cambiar Ajustes: \(before)")

        defaults.set("file:copyPath", forKey: ContextMenuSettings.hiddenKey) // lo mismo que el interruptor de Ajustes
        try await spin(1)
        let after = try #require(firstRowMenu(in: window), "no se encontró el menú de la fila del archivo")
        #expect(after.contains("Copy Filename"), "no es el menú del archivo: \(after)")
        #expect(!after.contains("Copy Path"), "el menú sigue con la opción oculta: \(after)")
    }

    /// Clic derecho sobre un archivo: «Abrir terminal aquí» (no «carpeta superior»), justo antes de la línea de Cortar.
    /// Flujo: en Ajustes se ve con el mismo nombre → en la ventana real sale igual y en el mismo sitio.
    @Test func terminalItemHasSameNameAndPlaceOnFiles() async throws {
        let defaults = UserDefaults.standard
        let savedHidden = defaults.string(forKey: ContextMenuSettings.hiddenKey)
        defer { defaults.set(savedHidden, forKey: ContextMenuSettings.hiddenKey) }
        defaults.set("", forKey: ContextMenuSettings.hiddenKey)
        #expect(ContextMenuOption.openInTerminal.title(in: .file) == "Open in Terminal") // lo que muestra Ajustes

        let url = try folder("terminal", files: ["nota.txt"])
        let window = try await openWindow(at: url)
        defer { window.close() }
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        for _ in 0..<40 where browser.displayedItems.isEmpty { try await spin(0.1) }
        browser.viewMode = .list
        try await spin(1)
        let menu = try #require(firstRowMenu(in: window))
        let terminal = String(localized: "Open in Terminal")
        #expect(!menu.contains(String(localized: "Open Parent in Terminal")), "\(menu)")
        let index = try #require(menu.firstIndex(of: terminal), "\(menu)")
        #expect(menu[index + 1].isEmpty && menu[index + 2] == String(localized: "Cut"), "\(menu)") // línea y luego Cortar
    }

    // MARK: valores por defecto propios

    /// Mi configuración por defecto: una ventana nueva abre en iconos y sin «Copy Path»;
    /// flujo: cambio una opción → la ventana siguiente usa lo que cambié.
    @Test func windowUsesMyDefaultsAndKeepsChanges() async throws {
        let defaults = UserDefaults.standard
        let reg = UserDefaults.registrationDomain
        let savedReg = defaults.volatileDomain(forName: reg)
        let keys = ["view.default", ContextMenuSettings.hiddenKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            defaults.setVolatileDomain(savedReg, forName: reg)
            for (k, v) in zip(keys, saved) { defaults.set(v, forKey: k) }
        }
        for k in keys { defaults.removeObject(forKey: k) }
        DefaultSettings.register(defaults, force: true)

        let url = try folder("mine", files: ["nota.txt"])
        let window = try await openWindow(at: url)
        defer { window.close() }
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        for _ in 0..<40 where browser.displayedItems.isEmpty { try await spin(0.1) }
        #expect(browser.viewMode == .icons, "la ventana no usa mi vista por defecto")
        browser.viewMode = .list
        try await spin(1)
        let menu = try #require(firstRowMenu(in: window), "no se encontró el menú del archivo")
        #expect(menu.contains("Open"), "no es el menú del archivo: \(menu)")
        #expect(!menu.contains("Copy Path"), "mis opciones ocultas siguen saliendo: \(menu)")

        defaults.set("List", forKey: BehaviorSettings.defaultViewKey)
        let window2 = try await openWindow(at: url)
        defer { window2.close() }
        let browser2 = try #require(KeyWindowFocus.shared.browser(for: window2))
        for _ in 0..<40 where browser2.displayedItems.isEmpty { try await spin(0.1) }
        #expect(browser2.viewMode == .list, "lo que cambié no se usa en la ventana nueva")
    }

    /// Bug: a veces la parte de arriba de la barra lateral (con los 3 botones) salía
    /// en blanco: las ventanas de `WindowService` no dejaban el contenido bajo la barra.
    @Test func newWindowSidebarReachesUnderTitlebar() async throws {
        let window = try await openWindow(at: try folder("titlebar"))
        defer { window.close() }
        #expect(window.styleMask.contains(.fullSizeContentView), "la barra de arriba tapa la barra lateral")
        let layout = window.contentLayoutRect.maxY
        #expect(layout < window.frame.height, "el contenido no llega bajo la barra de título")
    }

    // MARK: nube

    /// Completa: en una carpeta normal no salen las opciones de la nube.
    @Test func normalFolderHasNoCloudOptions() async throws {
        let url = try folder("nocloud", files: ["nota.txt"])
        let window = try await openWindow(at: url)
        defer { window.close() }
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        for _ in 0..<40 where browser.displayedItems.isEmpty { try await spin(0.1) }
        browser.viewMode = .list
        try await spin(1)
        let menu = try #require(firstRowMenu(in: window))
        #expect(!menu.contains("Download Now") && !menu.contains("Remove Download"), "\(menu)")
    }

    /// Flujo: archivo solo en la nube → clic derecho «Descargar ahora» → apago la opción
    /// en Ajustes → vuelvo a abrir la ventana → ya no sale.
    @Test func cloudMenuFollowsSettings() async throws {
        let defaults = UserDefaults.standard
        let savedHidden = defaults.string(forKey: ContextMenuSettings.hiddenKey)
        let savedMenu = defaults.object(forKey: CloudStatus.menuKey)
        let savedProvider = CloudStatus.provider
        defer {
            defaults.set(savedHidden, forKey: ContextMenuSettings.hiddenKey)
            defaults.set(savedMenu, forKey: CloudStatus.menuKey)
            CloudStatus.provider = savedProvider
        }
        defaults.set("", forKey: ContextMenuSettings.hiddenKey)
        defaults.set(true, forKey: CloudStatus.menuKey)
        let url = try folder("cloud", files: ["Informe.docx"])
        CloudStatus.provider = { $0.lastPathComponent == "Informe.docx" ? .cloudOnly : nil }

        func menuItems() async throws -> [String] {
            let window = try await openWindow(at: url)
            defer { window.close() }
            let browser = try #require(KeyWindowFocus.shared.browser(for: window))
            for _ in 0..<40 where browser.displayedItems.isEmpty { try await spin(0.1) }
            browser.viewMode = .list
            try await spin(1)
            return try #require(firstRowMenu(in: window))
        }
        let before = try await menuItems()
        #expect(before.contains("Download Now"), "\(before)")
        #expect(!before.contains("Remove Download"))
        defaults.set(false, forKey: CloudStatus.menuKey)
        let after = try await menuItems()
        #expect(!after.contains("Download Now"), "\(after)")
    }

    // MARK: abrir carpetas

    /// Flujo: aunque quedara guardado el ajuste viejo «Abrir carpetas en una pestaña nueva»,
    /// abrir una carpeta entra en ella en la misma pestaña (el ajuste se quitó).
    @Test func openingFolderStaysInSameTab() async throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "open.foldersInNewTab")
        RemovedFeatures.cleanDefaults(defaults)
        #expect(defaults.object(forKey: "open.foldersInNewTab") == nil, "el ajuste quitado sigue guardado")
        defaults.set(true, forKey: "open.foldersInNewTab") // aunque siguiera ahí, no debe contar
        defer { defaults.removeObject(forKey: "open.foldersInNewTab") }

        let url = try folder("opensame")
        let sub = url.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let window = try await openWindow(at: url)
        defer { window.close() }
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        for _ in 0..<40 where browser.displayedItems.isEmpty { try await spin(0.1) }
        let tabsBefore = browser.tabs.count
        let item = try #require(browser.displayedItems.first { $0.name == "Sub" })
        browser.open(item)
        try await spin()
        #expect(browser.tabs.count == tabsBefore, "abrió una pestaña nueva")
        #expect(browser.currentURL.lastPathComponent == "Sub")
    }

    // MARK: pestañas en memoria

    /// Flujo: abro una pestaña nueva → vuelvo a la primera → se ve al instante, sin cargar.
    /// Con la opción apagada vuelve a cargar como el original. Al cerrar la pestaña se libera.
    @Test func switchingTabsShowsContentWithoutLoading() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: TabMemory.enabledKey)
        defer { defaults.set(saved, forKey: TabMemory.enabledKey) }
        defaults.set(true, forKey: TabMemory.enabledKey)

        let first = try folder("tabA", files: ["a.txt", "b.txt"])
        let second = try folder("tabB", files: ["c.txt"])
        let window = try await openWindow(at: first)
        defer { window.close() }
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        for _ in 0..<40 where browser.items.isEmpty { try await spin(0.1) }
        let firstTab = try #require(browser.activeTabID)
        browser.newTab(at: second)
        for _ in 0..<40 where browser.items.count != 1 { try await spin(0.1) }
        let secondTab = try #require(browser.activeTabID)

        browser.selectTab(firstTab)
        #expect(!browser.isLoading, "mostró la carga al volver a la pestaña")
        #expect(Set(browser.items.map(\.name)) == ["a.txt", "b.txt"])
        // ni un instante después: la recarga de fondo y el vigilante no deben mostrar la carga
        var sawLoading = false
        for _ in 0..<30 { try await spin(0.05); if browser.isLoading { sawLoading = true } }
        #expect(!sawLoading, "la carga apareció después de cambiar de pestaña")
        // y si alguien pulsa «Recargar» o la carpeta cambia, tampoco
        try Data("x".utf8).write(to: first.appendingPathComponent("nuevo.txt"))
        browser.reload()
        #expect(!browser.isLoading, "una recarga de la carpeta ya mostrada sacó la carga")
        for _ in 0..<40 where browser.items.count != 3 { try await spin(0.1) }
        #expect(browser.items.count == 3, "no se actualizó en segundo plano")

        browser.closeTab(secondTab)
        #expect(browser.tabMemory.stored(secondTab) == false, "la pestaña cerrada sigue en memoria")

        defaults.set(false, forKey: TabMemory.enabledKey)
        browser.newTab(at: second)
        for _ in 0..<40 where browser.items.count != 1 { try await spin(0.1) }
        browser.selectTab(firstTab)
        #expect(browser.isLoading, "apagado debe cargar como el original")
    }

    /// Flujo: corto un archivo en la pestaña A → paso a la B y pego → vuelvo a la A:
    /// el archivo ya no está ahí (la memoria no deja ver lo viejo) y en B sí está.
    @Test func cutPasteBetweenTabsWithTabMemory() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: TabMemory.enabledKey)
        defer { defaults.set(saved, forKey: TabMemory.enabledKey) }
        defaults.set(true, forKey: TabMemory.enabledKey)

        let a = try folder("cutA", files: ["mover.txt", "queda.txt"])
        let b = try folder("cutB")
        let window = try await openWindow(at: a)
        defer { window.close() }
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        for _ in 0..<40 where browser.items.count != 2 { try await spin(0.1) }
        let tabA = try #require(browser.activeTabID)
        browser.selection = [try #require(browser.items.first { $0.name == "mover.txt" }).url]
        browser.cutSelection()

        browser.newTab(at: b)
        try await spin()
        await browser.paste(into: b, operations: FileOperationManager())
        for _ in 0..<40 where browser.items.isEmpty { try await spin(0.1) }
        #expect(browser.items.map(\.name) == ["mover.txt"], "no se pegó en B")

        browser.selectTab(tabA)
        for _ in 0..<40 where browser.items.count != 1 { try await spin(0.1) }
        #expect(browser.items.map(\.name) == ["queda.txt"], "A sigue mostrando el archivo cortado: \(browser.items.map(\.name))")
        #expect(!FileManager.default.fileExists(atPath: a.appendingPathComponent("mover.txt").path))
    }
}
