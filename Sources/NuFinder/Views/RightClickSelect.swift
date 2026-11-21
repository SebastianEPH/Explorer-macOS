import AppKit
import SwiftUI

/// Fork: como en el Explorador de Windows, el clic derecho (o Control+clic) sobre un archivo
/// lo selecciona antes de abrir el menú, salvo que ya forme parte de la selección.
/// Así las opciones actúan sobre el archivo bajo el ratón y no sobre el seleccionado antes.
enum RightClickSelection {
    static func selection(afterRightClickOn url: URL, current: Set<URL>) -> Set<URL> {
        current.contains(url) ? current : [url]
    }
}

extension View {
    func onRightMouseDown(_ action: @escaping () -> Void) -> some View {
        background(RightMouseDownReader(action: action))
    }
}

private struct RightMouseDownReader: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.action = action
    }

    final class ReaderView: NSView {
        var action: (() -> Void)?
        nonisolated(unsafe) private var monitor: Any?

        // No intercepta clics: solo mira los eventos que pasan por la ventana.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor else { return event }
                let isContextClick = event.type == .rightMouseDown
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
                guard isContextClick else { return event }
                if self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.action?()
                }
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
