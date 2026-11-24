import AppKit
@testable import NuFinder

/// Las suites corren en paralelo y todas abren ventanas reales: «la primera ventana nueva» puede
/// ser la de otra prueba (que luego se navegaba o se cerraba y le borraba la memoria de pestañas).
/// Aquí se busca la ventana nueva que muestra la carpeta pedida.
@MainActor
enum TestWindows {
    static func window(at url: URL, excluding before: Set<ObjectIdentifier>, timeout: Double = 3) async throws -> NSWindow? {
        _ = NSApplication.shared
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        func isMine(_ window: NSWindow) -> Bool {
            guard !before.contains(ObjectIdentifier(window)),
                  let browser = KeyWindowFocus.shared.browser(for: window) else { return false }
            return browser.currentURL.standardizedFileURL.resolvingSymlinksInPath().path == target
        }
        for _ in 0..<Int(timeout * 10) {
            if let window = NSApp.windows.first(where: isMine) { return window }
            try await Task.sleep(for: .milliseconds(100))
        }
        // Si la ventana se fue a otra carpeta, como antes: la primera nueva.
        return NSApp.windows.first { !before.contains(ObjectIdentifier($0)) }
    }
}
