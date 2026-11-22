import AppKit
import SwiftUI

/// Fork: estado de cada ventana. Antes el panel dividido era un ajuste global
/// (`showsSplitPane`) y al abrirlo en una ventana se abría en todas.
@MainActor
final class WindowSplitPanes: ObservableObject {
    static let shared = WindowSplitPanes()
    static let lastUsedKey = "showsSplitPane" // la ventana nueva empieza como la última que se usó

    @Published private var states: [ObjectIdentifier: Bool] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Valor con el que empezó cada ventana (fuera de @Published para poder fijarlo al dibujar).
    private var initial: [ObjectIdentifier: Bool] = [:]

    func isOn(_ window: BrowserModel) -> Bool {
        let id = ObjectIdentifier(window)
        if let value = states[id] ?? initial[id] { return value }
        let value = defaults.bool(forKey: Self.lastUsedKey) // se fija una vez: luego no cambia con las otras ventanas
        initial[id] = value
        return value
    }

    func set(_ value: Bool, for window: BrowserModel) {
        states[ObjectIdentifier(window)] = value
        defaults.set(value, forKey: Self.lastUsedKey)
    }

    func toggle(_ window: BrowserModel) { set(!isOn(window), for: window) }

    func binding(_ window: BrowserModel) -> Binding<Bool> {
        Binding(get: { self.isOn(window) }, set: { self.set($0, for: window) })
    }

    /// Panel dividido de la ventana activa (para los menús y la paleta de comandos).
    var keyWindowBinding: Binding<Bool> {
        Binding(
            get: { KeyWindowFocus.shared.windowBrowser.map(self.isOn) ?? false },
            set: { value in KeyWindowFocus.shared.windowBrowser.map { self.set(value, for: $0) } }
        )
    }
}

/// Fork: pone la carpeta en la ventana a la que pertenece la vista. Antes se usaba
/// `NSApp.keyWindow`, que al abrir una ventana nueva aún era la anterior y le cambiaba
/// la ruta (y «Reabrir ventana cerrada» abría otra carpeta).
struct WindowRepresentedURL: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let url = url
        DispatchQueue.main.async {
            guard let window = view.window, window.representedURL != url else { return }
            window.representedURL = url
        }
    }
}

/// Fork: la ventana del Dock. Sin ventanas visibles, SwiftUI creaba otra del grupo
/// principal que compartía el mismo modelo con la anterior; ahora se recupera una
/// minimizada o se abre una ventana nueva e independiente en la carpeta de inicio.
@MainActor
enum DockReopen {
    static func reopen(_ app: NSApplication) -> Bool {
        let browserWindows = app.windows.filter { KeyWindowFocus.shared.isBrowserWindow($0) }
        if let minimized = browserWindows.first(where: \.isMiniaturized) {
            minimized.deminiaturize(nil)
        } else if let hidden = browserWindows.first {
            hidden.makeKeyAndOrderFront(nil)
        } else {
            WindowService.open(at: BehaviorSettings.startURL() ?? FileManager.default.homeDirectoryForCurrentUser)
        }
        app.activate(ignoringOtherApps: true)
        return false
    }
}

/// Fork: quita los datos de «Espacios de trabajo», que se eliminó de la app.
enum RemovedFeatures {
    static func cleanDefaults(_ defaults: UserDefaults = .standard) {
        for key in ["savedWorkspaces", "launchWorkspaceID", "toolbar.showsWorkspaces"] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Fork: las ventanas de `WindowService` se liberaban solas al cerrarse
/// (`isReleasedWhenClosed`), y si algo aún las tenía, la app se caía.
@MainActor
enum WindowLifetime {
    private(set) static var windows: Set<NSWindow> = []

    static func keep(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        windows.insert(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                if let window { windows.remove(window) }
            }
        }
    }
}
