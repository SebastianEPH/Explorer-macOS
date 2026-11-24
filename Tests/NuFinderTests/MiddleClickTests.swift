import AppKit
import SwiftUI
import Testing
@testable import NuFinder

/// Botón central del ratón: cerrar pestañas y abrir carpetas en una ventana o pestaña nueva.
@Suite(.serialized) @MainActor
struct MiddleClickTests {
    private func spin(_ seconds: Double = 0.5) async throws {
        _ = NSApplication.shared
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private func folder(_ name: String, subfolders: [String] = [], files: [String] = []) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiddleClick-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for sub in subfolders {
            try FileManager.default.createDirectory(at: url.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
        for file in files { try Data("x".utf8).write(to: url.appendingPathComponent(file)) }
        return url.standardizedFileURL
    }

    /// Clic con la rueda (otherMouseUp, botón 2) en un punto de la ventana.
    private func middleUp(_ point: NSPoint, in window: NSWindow, button: Int64 = 2) throws -> NSEvent {
        let base = try #require(NSEvent.mouseEvent(with: .otherMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        let cg = try #require(base.cgEvent)
        cg.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return try #require(NSEvent(cgEvent: cg))
    }

    private func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { views(type, in: $0) }
    }

    /// Guarda y restaura los dos ajustes del botón central.
    private func withSettings(closesTab: Bool?, folder: MiddleClickFolderAction?, _ body: () async throws -> Void) async rethrows {
        let d = UserDefaults.standard
        let oldTab = d.object(forKey: MiddleClick.closesTabKey), oldFolder = d.object(forKey: MiddleClick.folderKey)
        let oldOpen = MiddleClick.openWindow
        defer {
            d.set(oldTab, forKey: MiddleClick.closesTabKey); d.set(oldFolder, forKey: MiddleClick.folderKey)
            MiddleClick.openWindow = oldOpen
        }
        d.set(closesTab, forKey: MiddleClick.closesTabKey)
        d.set(folder?.rawValue, forKey: MiddleClick.folderKey)
        try await body()
    }

    // MARK: unitarias

    // Por defecto apagado (= original); en mi configuración, encendido y «ventana nueva».
    @Test func defaults() {
        let d = UserDefaults(suiteName: "MC.\(UUID().uuidString)")!
        #expect(!d.bool(forKey: MiddleClick.closesTabKey))
        #expect(MiddleClickFolderAction(rawValue: d.string(forKey: MiddleClick.folderKey) ?? "") == nil)
        #expect(DefaultSettings.mine[MiddleClick.closesTabKey] as? Bool == true)
        #expect(DefaultSettings.mine[MiddleClick.folderKey] as? String == MiddleClickFolderAction.newWindow.rawValue)
    }

    // Solo carpetas; ni archivos ni apps/paquetes.
    @Test func actionOnlyForFolders() {
        #expect(MiddleClick.action(isFolder: true, isPackage: false, setting: .newWindow) == .newWindow)
        #expect(MiddleClick.action(isFolder: true, isPackage: false, setting: .newTab) == .newTab)
        #expect(MiddleClick.action(isFolder: true, isPackage: false, setting: .none) == .none)
        #expect(MiddleClick.action(isFolder: false, isPackage: false, setting: .newWindow) == .none)
        #expect(MiddleClick.action(isFolder: true, isPackage: true, setting: .newWindow) == .none)
    }

    // Solo el botón central cuenta (no el 3 o 4, botones laterales).
    @Test func onlyMiddleButton() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        #expect(MiddleClick.isMiddle(try middleUp(.init(x: 5, y: 5), in: window)))
        #expect(!MiddleClick.isMiddle(try middleUp(.init(x: 5, y: 5), in: window, button: 3)))
    }

    // MARK: completas y de flujo

    /// Barra de pestañas real (la del autor) en una ventana, con su modelo.
    private func tabBarWindow(_ browser: BrowserModel) async throws -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TabBarView().environmentObject(browser))
        window.makeKeyAndOrderFront(nil)
        try await spin()
        return window
    }

    private func readers(in window: NSWindow) -> [MiddleClickReader.ReaderView] {
        views(MiddleClickReader.ReaderView.self, in: window.contentView!)
            .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    }

    // Flujo: Ajustes (encendido) → dos pestañas → rueda sobre la segunda → se cierra como con la X.
    @Test func middleClickClosesTab() async throws {
        try await withSettings(closesTab: true, folder: nil) {
            let a = try folder("A"), b = try folder("B")
            let browser = BrowserModel(initialURL: a, restoresSession: false, defaults: UserDefaults(suiteName: "MC.\(UUID().uuidString)")!)
            browser.newTab(at: b)
            #expect(browser.tabs.count == 2)
            let window = try await tabBarWindow(browser)
            defer { window.close() }
            let tabs = readers(in: window)
            #expect(tabs.count == 2, "una zona de clic central por pestaña")
            let second = try #require(tabs.last)
            let center = second.convert(NSPoint(x: second.bounds.midX, y: second.bounds.midY), to: nil)
            #expect(second.handle(try middleUp(center, in: window)))
            #expect(browser.tabs.count == 1)
            #expect(browser.tabs.first?.url.standardizedFileURL == a)
            try await spin(0.2)
            // La última pestaña no se cierra (como la X, que ni aparece).
            let last = try #require(readers(in: window).first)
            last.handle(try middleUp(last.convert(NSPoint(x: last.bounds.midX, y: last.bounds.midY), to: nil), in: window))
            #expect(browser.tabs.count == 1)
        }
    }

    // Flujo: apagado → la rueda sobre una pestaña no hace nada (original). Fijada → tampoco se cierra.
    @Test func middleClickOffOrPinnedKeepsTab() async throws {
        let a = try folder("A"), b = try folder("B")
        let browser = BrowserModel(initialURL: a, restoresSession: false, defaults: UserDefaults(suiteName: "MC.\(UUID().uuidString)")!)
        browser.newTab(at: b)
        let second = try #require(browser.tabs.last?.id)
        try await withSettings(closesTab: false, folder: nil) {
            #expect(!MiddleClick.tabClicked(second, in: browser))
        }
        try await withSettings(closesTab: true, folder: nil) {
            browser.togglePinnedTab(second)
            #expect(!MiddleClick.tabClicked(second, in: browser))
            #expect(browser.tabs.count == 2)
        }
    }

    /// Lista real: la ventana de Explorer con su `NSTableView`.
    private func listWindow(at url: URL) async throws -> (NSWindow, TableMiddleClickInstaller.InstallerView, NSTableView) {
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        WindowService.open(at: url)
        try await spin(0.8)
        let window = try #require(NSApp.windows.first { !before.contains(ObjectIdentifier($0)) })
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        for _ in 0..<40 where browser.displayedItems.isEmpty { try await spin(0.1) }
        browser.viewMode = .list
        try await spin(1)
        let installer = try #require(views(TableMiddleClickInstaller.InstallerView.self, in: window.contentView!).first,
                                     "la lista tiene su detector de rueda")
        let table = try #require(views(NSTableView.self, in: window.contentView!).first { $0.numberOfRows > 0 })
        return (window, installer, table)
    }

    // Completa + flujo: ventana real en vista de lista → rueda sobre la carpeta (en la columna Tipo
    // también) → se abre en una ventana nueva; sobre un archivo no pasa nada.
    @Test func middleClickFolderOpensNewWindow() async throws {
        let root = try folder("Lista", subfolders: ["Carpeta"], files: ["zz.txt"])
        try await withSettings(closesTab: nil, folder: .newWindow) {
            var opened: [String] = []
            MiddleClick.openWindow = { opened.append($0.lastPathComponent) }
            let (window, installer, table) = try await listWindow(at: root)
            defer { window.close() }
            for column in [0, table.numberOfColumns - 1] {
                opened.removeAll()
                let rect = table.frameOfCell(atColumn: column, row: 0)
                let point = table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
                #expect(installer.handle(try middleUp(point, in: window)) == 0)
                #expect(opened == ["Carpeta"], "columna \(column): \(opened)")
            }
            opened.removeAll()
            let rect = table.frameOfCell(atColumn: 0, row: 1)
            installer.handle(try middleUp(table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil), in: window))
            #expect(opened.isEmpty, "un archivo no se abre con la rueda")
        }
    }

    // Flujo: «Abrir en una pestaña nueva» → la carpeta sale en otra pestaña y la actual sigue.
    // «Nada» → no pasa nada (original).
    @Test func middleClickFolderNewTabOrNothing() async throws {
        let root = try folder("Pestaña", subfolders: ["Sub"])
        let browser = BrowserModel(initialURL: root, restoresSession: false, defaults: UserDefaults(suiteName: "MC.\(UUID().uuidString)")!)
        let sub = FileItem.load(root.appendingPathComponent("Sub", isDirectory: true))
        let item = try #require(sub)
        try await withSettings(closesTab: nil, folder: MiddleClickFolderAction.none) {
            MiddleClick.openWindow = { _ in Issue.record("no debe abrir ventana") }
            #expect(MiddleClick.itemClicked(item, in: browser) == .none)
            #expect(browser.tabs.count == 1)
        }
        try await withSettings(closesTab: nil, folder: .newTab) {
            #expect(MiddleClick.itemClicked(item, in: browser) == .newTab)
            #expect(browser.tabs.count == 2)
            #expect(browser.tabs.contains { $0.url.lastPathComponent == "Sub" })
            #expect(browser.tabs.contains { $0.url.standardizedFileURL == root })
        }
    }
}
