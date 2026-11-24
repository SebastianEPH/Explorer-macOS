import SwiftUI

/// Fork: botón de la barra de arriba, junto al de Terminal, que abre otra ventana de Explorer
/// en la carpeta actual (como Archivo → Nueva ventana). `toolbar.showsNewWindow`; apagado = original.
enum NewWindowButton {
    static let key = "toolbar.showsNewWindow"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Abrir la ventana; se sustituye en pruebas.
    nonisolated(unsafe) static var openWindow: @MainActor (URL) -> Void = { WindowService.open(at: $0) }

    @MainActor
    static func press(from browser: BrowserModel) { openWindow(browser.currentURL) }
}

struct NewWindowToolbarButton: View {
    @AppStorage(NewWindowButton.key) private var shows = false
    let browser: BrowserModel

    var body: some View {
        if shows {
            Button {
                NewWindowButton.press(from: browser)
            } label: {
                FreeloaderToolbarIcon(systemName: "macwindow.badge.plus")
            }
            .buttonStyle(.plain)
            .help("Open a New Window Here")
        }
    }
}
