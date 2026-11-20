import Foundation

/// Fork: portapapeles de Explorer compartido entre todas las ventanas y paneles.
/// Antes cada BrowserModel tenía el suyo: cortar en una ventana no dejaba pegar en otra.
@MainActor
enum SharedClipboard {
    static var urls: [URL] = []
    static var isCut = false
}
