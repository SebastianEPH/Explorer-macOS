import AppKit
import SwiftUI

/// Fork: recuadro de selección en la vista de lista, como en el Explorador de Windows.
/// Al pulsar en una zona vacía de la lista y arrastrar, se dibuja un recuadro y se seleccionan
/// las filas que toca. También empieza desde el espacio de una fila fuera del nombre.
/// Con ⌘ o ⇧ se añade a la selección; un clic sin arrastrar en vacío la quita.
enum TableMarquee {
    /// Filas que quedan seleccionadas: las que toca el recuadro, más las de antes si se suma.
    static func selection(rows: [Int], base: Set<Int>, additive: Bool) -> Set<Int> {
        additive ? base.union(rows) : Set(rows)
    }

    /// Margen (pt) junto a los bordes izquierdo, derecho e inferior donde macOS redimensiona la ventana.
    static let resizeMargin: CGFloat = 8

    /// Un clic aquí es para cambiar el tamaño de la ventana: el recuadro no se lo queda.
    /// Antes se lo quedaba si la tabla llegaba a la esquina inferior izquierda: salía el cursor
    /// de redimensionar pero la ventana no cambiaba.
    static func isResizeZone(_ point: NSPoint, windowSize: NSSize, margin: CGFloat = resizeMargin) -> Bool {
        point.x <= margin || point.x >= windowSize.width - margin || point.y <= margin
    }
}

extension View {
    /// `onSelect(filas, sumar)` recibe los índices de fila de la tabla (= `displayedItems`).
    func tableMarquee(onSelect: @escaping (_ rows: Set<Int>) -> Void, current: @escaping () -> Set<Int>) -> some View {
        background(TableMarqueeInstaller(onSelect: onSelect, current: current))
    }
}

struct TableMarqueeInstaller: NSViewRepresentable {
    let onSelect: (Set<Int>) -> Void
    let current: () -> Set<Int>

    func makeNSView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.onSelect = onSelect
        view.current = current
        return view
    }

    func updateNSView(_ view: InstallerView, context: Context) {
        view.onSelect = onSelect
        view.current = current
    }

    final class InstallerView: NSView {
        var onSelect: ((Set<Int>) -> Void)?
        var current: (() -> Set<Int>)?
        nonisolated(unsafe) private var monitor: Any?
        private weak var table: NSTableView?
        private var start: NSPoint = .zero
        private var base: Set<Int> = []
        private var additive = false
        private var dragging = false
        private var startRow = -1
        private var overlay: NSView?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        func handle(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .leftMouseDown:
                guard event.window === window, !isHiddenOrHasHiddenAncestor,
                      let win = event.window, !(win.styleMask.contains(.resizable)
                          && TableMarquee.isResizeZone(event.locationInWindow, windowSize: win.frame.size)),
                      !event.modifierFlags.contains(.control),
                      convert(bounds, to: nil).contains(event.locationInWindow),
                      let table = tableUnder(event) else { return event }
                let point = table.convert(event.locationInWindow, from: nil)
                // Como en Windows: desde una zona vacía o desde el espacio de una fila fuera del nombre
                // (columnas Tipo, Tamaño, Fecha…). Sobre el nombre se sigue arrastrando el archivo.
                guard table.bounds.contains(point) else { return event }
                let row = table.row(at: point)
                guard row == -1 || table.column(at: point) > 0 else { return event }
                // Doble clic en una fila (fuera del nombre): es para abrirla, se deja pasar a la tabla.
                // Antes el recuadro se quedaba también el segundo clic y la carpeta no se abría.
                guard !(row >= 0 && event.clickCount >= 2) else { return event }
                startRow = row
                self.table = table
                start = point
                additive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
                base = current?() ?? []
                dragging = false
                window?.makeFirstResponder(table)
                return nil
            case .leftMouseDragged:
                guard let table else { return event }
                table.autoscroll(with: event)
                let point = table.convert(event.locationInWindow, from: nil)
                if !dragging, hypot(point.x - start.x, point.y - start.y) < 3 { return nil }
                dragging = true
                let rect = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                  width: abs(point.x - start.x), height: abs(point.y - start.y))
                    .intersection(table.bounds)
                showOverlay(rect, in: table)
                let range = table.rows(in: rect)
                let rows = range.length > 0 ? Array(range.location..<(range.location + range.length)) : []
                onSelect?(TableMarquee.selection(rows: rows, base: base, additive: additive))
                return nil
            case .leftMouseUp:
                guard table != nil else { return event }
                if !dragging {
                    // Clic sin arrastrar: en una fila la selecciona (⌘/⇧ la suma o la quita); en vacío, deselecciona.
                    if startRow >= 0 {
                        onSelect?(additive ? base.symmetricDifference([startRow]) : [startRow])
                    } else if !additive {
                        onSelect?([])
                    }
                }
                overlay?.removeFromSuperview()
                overlay = nil
                table = nil
                dragging = false
                return nil
            default:
                return event
            }
        }

        private func tableUnder(_ event: NSEvent) -> NSTableView? {
            guard let content = window?.contentView else { return nil }
            var view = content.hitTest(content.convert(event.locationInWindow, from: nil))
            while let current = view {
                if let table = current as? NSTableView { return table }
                if let scroll = current as? NSScrollView, let table = scroll.documentView as? NSTableView { return table }
                if let clip = current as? NSClipView, let table = clip.documentView as? NSTableView { return table }
                view = current.superview
            }
            return nil
        }

        private func showOverlay(_ rect: NSRect, in table: NSTableView) {
            let overlay = self.overlay ?? {
                let view = NSView()
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
                view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
                view.layer?.borderWidth = 1
                view.layer?.cornerRadius = 2
                table.addSubview(view)
                self.overlay = view
                return view
            }()
            overlay.frame = rect
        }
    }
}
