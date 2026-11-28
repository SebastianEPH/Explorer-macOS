import SwiftUI

/// Fork: botón «Actualizar» en la barra de arriba: vuelve a leer la carpeta y recalcula el
/// tamaño de cada subcarpeta. `toolbar.showsRefresh`; apagado = original.
enum RefreshButton {
    static let key = "toolbar.showsRefresh"

    @MainActor
    static func press(from browser: BrowserModel) {
        let sizes = FolderSizeService.shared
        let folders = browser.items.filter(\.isDirectory)
        for item in folders {
            sizes.cancel(item)
            sizes.invalidate(item.url)
        }
        browser.reload()
        for item in folders { sizes.calculate(item) }
    }
}

struct RefreshToolbarButton: View {
    @AppStorage(RefreshButton.key) private var shows = false
    let browser: BrowserModel

    var body: some View {
        if shows {
            Button {
                RefreshButton.press(from: browser)
            } label: {
                FreeloaderToolbarIcon(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh Folder and Folder Sizes")
        }
    }
}
