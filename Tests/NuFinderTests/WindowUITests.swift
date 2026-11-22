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
        return try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) })
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
}
