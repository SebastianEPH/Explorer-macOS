import AppKit
import Foundation
import Testing
@testable import NuFinder

/// La misma carpeta tiene que verse igual se abra desde donde se abra.
@Suite(.serialized) @MainActor
struct FolderViewConsistencyTests {
    private func defaults(on: Bool) -> UserDefaults {
        let d = UserDefaults(suiteName: "FolderView.\(UUID().uuidString)")!
        d.set(on, forKey: FolderViewConsistency.key)
        return d
    }

    private func folder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderView-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Guarda una vista para la carpeta como lo hace la ventana al cambiarla.
    private func save(_ mode: FileViewMode, at url: URL, in browser: BrowserModel) {
        browser.navigate(to: url)
        browser.viewMode = mode
        browser.saveViewPreferences()
    }

    @Test func offByDefault() {
        let d = UserDefaults(suiteName: "FolderView.\(UUID().uuidString)")!
        #expect(!FolderViewConsistency.isOn(d), "apagado = comportamiento original")
        #expect(DefaultSettings.mine[FolderViewConsistency.key] as? Bool == true, "en mi Mac viene encendido")
    }

    // Flujo: la carpeta en iconos, su favorito guardado en lista → abrirla desde la barra lateral.
    @Test func favoriteOpensWithFolderView() throws {
        let photos = try folder("Fotos"), other = try folder("Otra")
        let browser = BrowserModel(initialURL: other, restoresSession: false, defaults: defaults(on: true))
        _ = browser.addFavorite(photos)
        save(.list, at: photos, in: browser)
        browser.updateFavoriteView(photos)          // el favorito recuerda «lista»
        save(.icons, at: photos, in: browser)       // la carpeta pasa a iconos
        save(.compact, at: other, in: browser)
        browser.navigateToFavorite(photos)
        #expect(browser.viewMode == .icons, "desde la barra lateral sale igual que navegando")
    }

    @Test func favoriteKeepsOwnViewWhenOff() throws {
        let photos = try folder("Fotos"), other = try folder("Otra")
        let browser = BrowserModel(initialURL: other, restoresSession: false, defaults: defaults(on: false))
        _ = browser.addFavorite(photos)
        save(.list, at: photos, in: browser)
        browser.updateFavoriteView(photos)
        save(.icons, at: photos, in: browser)
        browser.navigateToFavorite(photos)
        #expect(browser.viewMode == .list, "apagado: como el original")
    }

    // Flujo: dos pestañas con carpetas guardadas distinto → ir y volver entre ellas.
    @Test func switchingTabsShowsEachFolderView() throws {
        let a = try folder("A"), b = try folder("B")
        let browser = BrowserModel(initialURL: a, restoresSession: false, defaults: defaults(on: true))
        save(.icons, at: a, in: browser)
        save(.list, at: b, in: browser)
        browser.navigate(to: a)
        let first = try #require(browser.activeTabID)
        browser.newTab(at: b)
        #expect(browser.viewMode == .list, "pestaña nueva en B → la vista de B")
        browser.selectTab(first)
        #expect(browser.viewMode == .icons, "volver a la pestaña de A → la vista de A")
    }

    // Abrir desde la Terminal = ventana nueva en esa carpeta, también por un enlace (/tmp → /private/tmp).
    @Test func newWindowAndSymlinkUseSavedView() throws {
        let real = try folder("Real")
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("FolderView-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let d = defaults(on: true)
        let first = BrowserModel(initialURL: real, restoresSession: false, defaults: d)
        save(.compact, at: real, in: first)
        #expect(BrowserModel(initialURL: real, restoresSession: false, defaults: d).viewMode == .compact)
        #expect(BrowserModel(initialURL: link, restoresSession: false, defaults: d).viewMode == .compact)
    }
}
