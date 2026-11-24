import AppKit
import Foundation
import Testing
@testable import NuFinder

/// Fork: casos límite de las pestañas en memoria, con ventanas reales.
/// Cada prueba es un recorrido que podría romper la selección, la ubicación o lo que se ve.
@Suite(.serialized) @MainActor
struct TabMemoryScenarioTests {
    private func spin(_ seconds: Double = 0.1) async throws {
        _ = NSApplication.shared
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private func folder(_ name: String, files: [String] = [], count: Int = 0) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TabMemory-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in files { try Data("x".utf8).write(to: url.appendingPathComponent(file)) }
        for i in 0..<count { FileManager.default.createFile(atPath: url.appendingPathComponent("f\(i).txt").path, contents: nil) }
        return url.standardizedFileURL
    }

    private func open(_ url: URL) async throws -> (NSWindow, BrowserModel) {
        let before = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        WindowService.open(at: url)
        try await spin(0.5)
        let window = try #require(try await TestWindows.window(at: url, excluding: before))
        let browser = try #require(KeyWindowFocus.shared.browser(for: window))
        try await settle(browser)
        return (window, browser)
    }

    /// Espera a que termine cualquier lectura (con o sin indicador).
    private func settle(_ browser: BrowserModel, until: (() -> Bool)? = nil) async throws {
        for _ in 0..<100 {
            try await spin(0.1)
            if browser.isLoading { continue }
            if let until, !until() { continue }
            try await spin(0.3)
            return
        }
    }

    private func withMemory(_ body: () async throws -> Void) async throws {
        let d = UserDefaults.standard
        let saved = d.object(forKey: TabMemory.enabledKey)
        defer { d.set(saved, forKey: TabMemory.enabledKey) }
        d.set(true, forKey: TabMemory.enabledKey)
        try await body()
    }

    /// 1. Carpeta grande: vuelvo, selecciono y empiezo a renombrar ANTES de que termine la
    /// lectura de fondo. Al terminar no se pierde la selección, ni el renombrado, ni la ubicación.
    @Test func selectionSurvivesBackgroundReloadOfBigFolder() async throws {
        try await withMemory {
            let big = try folder("big", count: 4000)
            let other = try folder("other", files: ["o.txt"])
            let (window, browser) = try await open(big)
            defer { window.close() }
            try await settle(browser) { browser.items.count == 4000 }
            let tabA = try #require(browser.activeTabID)
            browser.newTab(at: other)
            try await settle(browser) { browser.items.count == 1 }

            browser.selectTab(tabA)
            let picked = big.appendingPathComponent("f123.txt")
            browser.selection = [picked, big.appendingPathComponent("f7.txt")]
            browser.renameTarget = picked
            try await settle(browser)
            #expect(browser.selection == [picked, big.appendingPathComponent("f7.txt")], "se perdió la selección")
            #expect(browser.renameTarget == picked, "se cortó el renombrado")
            #expect(browser.currentURL == big, "cambió la ubicación")
            #expect(browser.items.count == 4000)
        }
    }

    /// 2. Cambio rápido A → B → C mientras A sigue leyendo: al final se ve C, nunca A ni B.
    @Test func rapidSwitchingShowsOnlyTheLastTab() async throws {
        try await withMemory {
            let a = try folder("A", count: 3000)
            let b = try folder("B", files: ["b.txt"])
            let c = try folder("C", files: ["c1.txt", "c2.txt"])
            let (window, browser) = try await open(a)
            defer { window.close() }
            let tabA = try #require(browser.activeTabID)
            browser.newTab(at: b); try await settle(browser) { browser.items.count == 1 }
            let tabB = try #require(browser.activeTabID)
            browser.newTab(at: c); try await settle(browser) { browser.items.count == 2 }
            let tabC = try #require(browser.activeTabID)

            browser.selectTab(tabA)
            browser.selectTab(tabB)
            browser.selectTab(tabC)
            #expect(browser.items.map(\.name).sorted() == ["c1.txt", "c2.txt"])
            try await settle(browser)
            #expect(browser.currentURL == c)
            #expect(browser.items.map(\.name).sorted() == ["c1.txt", "c2.txt"], "llegaron archivos de otra pestaña")
        }
    }

    /// 3. Vuelvo a la pestaña y entro en una subcarpeta antes de que termine la lectura de
    /// fondo: la lectura vieja no pisa la subcarpeta.
    @Test func navigatingDuringBackgroundReloadKeepsNewFolder() async throws {
        try await withMemory {
            let a = try folder("nav", count: 3000)
            let sub = a.appendingPathComponent("Sub", isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: sub.appendingPathComponent("dentro.txt"))
            let other = try folder("nav2", files: ["o.txt"])
            let (window, browser) = try await open(a)
            defer { window.close() }
            try await settle(browser) { browser.items.count == 3001 }
            let tabA = try #require(browser.activeTabID)
            browser.newTab(at: other); try await settle(browser) { browser.items.count == 1 }

            browser.selectTab(tabA)
            browser.navigate(to: sub)
            try await settle(browser)
            #expect(browser.currentURL.lastPathComponent == "Sub")
            #expect(browser.items.map(\.name) == ["dentro.txt"], "la lectura vieja pisó la subcarpeta")
        }
    }

    /// 4. La carpeta de la pestaña se borra mientras estoy en otra: al volver no deben
    /// quedarse los archivos guardados como si existieran.
    @Test func deletedFolderDoesNotShowStaleFiles() async throws {
        try await withMemory {
            let a = try folder("gone", files: ["x1.txt", "x2.txt"])
            let other = try folder("stay", files: ["o.txt"])
            let (window, browser) = try await open(a)
            defer { window.close() }
            let tabA = try #require(browser.activeTabID)
            browser.newTab(at: other); try await settle(browser) { browser.items.count == 1 }
            try FileManager.default.removeItem(at: a)

            browser.selectTab(tabA)
            try await settle(browser)
            #expect(browser.items.isEmpty, "muestra archivos de una carpeta borrada: \(browser.items.map(\.name))")
        }
    }

    /// 5. Cambios mientras estoy en otra pestaña (nuevo, borrado, renombrado): al volver
    /// queda al día y la selección de un archivo borrado no sobrevive como fantasma.
    @Test func changesWhileAwayAreApplied() async throws {
        try await withMemory {
            let a = try folder("changes", files: ["borrar.txt", "renombrar.txt", "queda.txt"])
            let other = try folder("changes2", files: ["o.txt"])
            let (window, browser) = try await open(a)
            defer { window.close() }
            let tabA = try #require(browser.activeTabID)
            browser.newTab(at: other); try await settle(browser) { browser.items.count == 1 }
            let fm = FileManager.default
            try fm.removeItem(at: a.appendingPathComponent("borrar.txt"))
            try fm.moveItem(at: a.appendingPathComponent("renombrar.txt"), to: a.appendingPathComponent("nuevo-nombre.txt"))
            try Data("x".utf8).write(to: a.appendingPathComponent("creado.txt"))

            browser.selectTab(tabA)
            try await settle(browser) { browser.items.count == 3 && browser.items.contains { $0.name == "creado.txt" } }
            #expect(browser.items.map(\.name).sorted() == ["creado.txt", "nuevo-nombre.txt", "queda.txt"])
        }
    }

    /// 6. Mostrar ocultos y cambiar el orden mientras la pestaña está guardada.
    @Test func hiddenFilesAndSortChangesWhileAway() async throws {
        try await withMemory {
            let a = try folder("hidden", files: [".oculto", "b.txt", "a.txt"])
            let other = try folder("hidden2", files: ["o.txt"])
            let (window, browser) = try await open(a)
            defer { window.close() }
            let hiddenBefore = browser.showsHiddenFiles
            defer { if browser.showsHiddenFiles != hiddenBefore { browser.toggleHiddenFiles() } }
            if browser.showsHiddenFiles { browser.toggleHiddenFiles() }
            try await settle(browser) { !browser.items.contains { $0.name == ".oculto" } }
            let tabA = try #require(browser.activeTabID)
            browser.newTab(at: other); try await settle(browser) { browser.items.count == 1 }
            browser.toggleHiddenFiles()
            try await settle(browser)

            browser.selectTab(tabA)
            try await settle(browser) { browser.items.count == 3 }
            #expect(browser.items.contains { $0.name == ".oculto" }, "no aplicó «mostrar ocultos» al volver")
        }
    }

    /// 7. La misma carpeta en dos pestañas: un cambio hecho en una se ve al volver a la otra.
    @Test func sameFolderInTwoTabs() async throws {
        try await withMemory {
            let a = try folder("twice", files: ["uno.txt"])
            let (window, browser) = try await open(a)
            defer { window.close() }
            let tabA = try #require(browser.activeTabID)
            browser.newTab(at: a); try await settle(browser) { browser.items.count == 1 }
            try Data("x".utf8).write(to: a.appendingPathComponent("dos.txt"))
            try await settle(browser) { browser.items.count == 2 }

            browser.selectTab(tabA)
            try await settle(browser) { browser.items.count == 2 }
            #expect(browser.items.map(\.name).sorted() == ["dos.txt", "uno.txt"])
        }
    }

    /// 8. Cerrar varias pestañas y la ventana libera la memoria.
    @Test func closingFreesMemory() async throws {
        try await withMemory {
            let a = try folder("free", files: ["a.txt"])
            let b = try folder("free2", files: ["b.txt"])
            let (window, browser) = try await open(a)
            let tabA = try #require(browser.activeTabID)
            browser.newTab(at: b); try await settle(browser)
            #expect(browser.tabMemory.stored(tabA))
            weak var memory = browser.tabMemory
            browser.closeTab(tabA)
            #expect(!browser.tabMemory.stored(tabA))
            window.close()
            try await spin(0.5)
            _ = memory // la memoria vive dentro del modelo de la ventana: se va con él
        }
    }

    /// 9. Atrás y adelante: la carpeta anterior sale al instante, sin carga.
    @Test func backAndForwardAreInstant() async throws {
        try await withMemory {
            let a = try folder("backA", files: ["a1.txt", "a2.txt"])
            let sub = a.appendingPathComponent("Sub", isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: sub.appendingPathComponent("s.txt"))
            let (window, browser) = try await open(a)
            defer { window.close() }
            try await settle(browser) { browser.items.count == 3 }
            browser.navigate(to: sub)
            try await settle(browser) { browser.items.count == 1 }
            browser.goBack()
            #expect(!browser.isLoading, "atrás mostró la carga")
            #expect(browser.items.count == 3)
            browser.goForward()
            #expect(!browser.isLoading, "adelante mostró la carga")
            #expect(browser.items.map(\.name) == ["s.txt"])
        }
    }

    /// 10. Cerrar la ventana libera de verdad su RAM en el almacén común.
    @Test func closingWindowFreesItsFolders() async throws {
        try await withMemory {
            let a = try folder("winA", files: ["a.txt"])
            let b = try folder("winB", files: ["b.txt"])
            var opened: (NSWindow, BrowserModel)? = try await open(a)
            let browser = try #require(opened?.1)
            browser.newTab(at: b)
            try await settle(browser) { browser.items.count == 1 }
            let tabs = browser.tabs.map(\.id)
            #expect(tabs.contains { FolderMemoryStore.shared.has(tab: $0) })
            opened?.0.close()
            opened = nil
            for _ in 0..<30 where tabs.contains(where: { FolderMemoryStore.shared.has(tab: $0) }) { try await spin(0.1) }
            #expect(!tabs.contains { FolderMemoryStore.shared.has(tab: $0) }, "la ventana cerrada sigue ocupando RAM")
        }
    }
}
