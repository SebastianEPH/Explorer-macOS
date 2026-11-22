import AppKit
import Combine
import SwiftUI

/// Fork: cada ventana tiene su propio BrowserModel. Esto recuerda cuál es la ventana
/// activa para que los menús (⌘T, ⌘C, Ver, Ir…) actúen sobre ella y no sobre la primera.
@MainActor
final class KeyWindowFocus: ObservableObject {
    static let shared = KeyWindowFocus()

    private struct Entry {
        let focus: PaneFocusCoordinator
        let browser: BrowserModel
        let operations: FileOperationManager
    }

    private let entries = NSMapTable<NSWindow, AnyObject>.weakToStrongObjects()
    private var focusSubscription: AnyCancellable?
    private var browserSubscription: AnyCancellable?
    @Published private(set) var browser: BrowserModel?
    @Published private(set) var operations: FileOperationManager?
    /// Modelo principal de la ventana activa (el panel izquierdo), aunque el foco esté en el derecho.
    @Published private(set) var windowBrowser: BrowserModel?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in self?.windowBecameKey(window) }
        }
    }

    func register(_ window: NSWindow, focus: PaneFocusCoordinator, browser: BrowserModel,
                  operations: FileOperationManager) {
        entries.setObject(Box(Entry(focus: focus, browser: browser, operations: operations)), forKey: window)
        if window.isKeyWindow || self.browser == nil { windowBecameKey(window) }
    }

    private func windowBecameKey(_ window: NSWindow) {
        guard let entry = (entries.object(forKey: window) as? Box<Entry>)?.value else { return }
        operations = entry.operations
        windowBrowser = entry.browser
        focusSubscription = entry.focus.$activeBrowser.sink { [weak self] active in
            self?.follow(active ?? entry.browser)
        }
    }

    func isBrowserWindow(_ window: NSWindow) -> Bool { entries.object(forKey: window) != nil }
    /// Modelo principal de una ventana concreta.
    func browser(for window: NSWindow) -> BrowserModel? { (entries.object(forKey: window) as? Box<Entry>)?.value.browser }

    private func follow(_ model: BrowserModel) {
        guard model !== browser else { return }
        browser = model
        browserSubscription = model.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private final class Box<T> {
        let value: T
        init(_ value: T) { self.value = value }
    }
}

/// Se pone de fondo en la raíz de cada ventana para registrarla.
struct KeyWindowReader: NSViewRepresentable {
    let focus: PaneFocusCoordinator
    let browser: BrowserModel
    let operations: FileOperationManager

    func makeNSView(context: Context) -> NSView {
        ReaderView(focus: focus, browser: browser, operations: operations)
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let focus: PaneFocusCoordinator
        let browser: BrowserModel
        let operations: FileOperationManager

        init(focus: PaneFocusCoordinator, browser: BrowserModel, operations: FileOperationManager) {
            self.focus = focus
            self.browser = browser
            self.operations = operations
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            MainActor.assumeIsolated {
                KeyWindowFocus.shared.register(window, focus: focus, browser: browser, operations: operations)
            }
        }
    }
}
