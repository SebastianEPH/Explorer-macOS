import Foundation

/// Fork: portapapeles de Explorer compartido entre todas las ventanas y paneles.
/// Antes cada BrowserModel tenía el suyo: cortar en una ventana no dejaba pegar en otra.
/// Al cambiar se avisa con `didChange` para que las demás ventanas activen «Pegar».
@MainActor
enum SharedClipboard {
    static let didChange = Notification.Name("SharedClipboard.didChange")

    static var urls: [URL] = [] {
        didSet { NotificationCenter.default.post(name: didChange, object: nil) }
    }
    static var isCut = false
}
