import AppKit
import SwiftUI

/// Fork: al seleccionar arrastrando en las vistas de iconos y mosaico, si el ratón se acerca
/// al borde de arriba o de abajo la vista se desplaza sola para poder seguir seleccionando.
@MainActor
final class MarqueeAutoScroller {
    weak var scrollView: NSScrollView?
    private var timer: Timer?
    private var speed: CGFloat = 0
    var onScroll: (() -> Void)?

    /// Desplazamiento vertical actual del contenido (0 = arriba).
    var offsetY: CGFloat {
        guard let clip = scrollView?.contentView else { return 0 }
        return clip.isFlipped ? clip.bounds.origin.y : flippedOffset(clip)
    }

    var viewportHeight: CGFloat { scrollView?.contentView.bounds.height ?? 0 }

    /// `y` es la posición del ratón dentro de la parte visible.
    func update(pointerY y: CGFloat) {
        let height = viewportHeight
        guard height > 0 else { return stop() }
        let edge: CGFloat = 40
        if y < edge {
            speed = -min(40, (edge - y) / 2 + 4)
        } else if y > height - edge {
            speed = min(40, (y - (height - edge)) / 2 + 4)
        } else {
            return stop()
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        speed = 0
    }

    private func tick() {
        guard let scrollView, let document = scrollView.documentView else { return stop() }
        let clip = scrollView.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        var origin = clip.bounds.origin
        let delta = clip.isFlipped ? speed : -speed
        let newY = min(max(0, origin.y + delta), maxY)
        guard newY != origin.y else { return }
        origin.y = newY
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        onScroll?()
    }

    private func flippedOffset(_ clip: NSClipView) -> CGFloat {
        guard let document = scrollView?.documentView else { return 0 }
        return document.frame.height - clip.bounds.height - clip.bounds.origin.y
    }
}

/// Se pone de fondo dentro del ScrollView para encontrar su NSScrollView.
struct ScrollViewFinder: NSViewRepresentable {
    let scroller: MarqueeAutoScroller

    func makeNSView(context: Context) -> NSView { FinderView(scroller: scroller) }
    func updateNSView(_ nsView: NSView, context: Context) {
        if scroller.scrollView == nil { scroller.scrollView = nsView.enclosingScrollView }
    }

    private final class FinderView: NSView {
        let scroller: MarqueeAutoScroller
        init(scroller: MarqueeAutoScroller) {
            self.scroller = scroller
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            MainActor.assumeIsolated { scroller.scrollView = enclosingScrollView }
        }
    }
}
