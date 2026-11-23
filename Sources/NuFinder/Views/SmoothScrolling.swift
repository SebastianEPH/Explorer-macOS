import SwiftUI

/// Fork: fluidez al desplazarse por la vista de iconos y la lista.
///
/// Medido con `sample` mientras se desplazaba Descargas (58 archivos): el hilo principal
/// estaba ocupado el 96 %. Dos cosas reconstruían la vista entera en cada fotograma:
/// - las posiciones de las celdas (`TileFrameReporter`, para el recuadro de selección) se
///   guardaban en un `@State`, y al desplazar cambian todas en cada fotograma;
/// - el archivo bajo el puntero (preselección) también era `@State` de toda la vista.
/// Aquí se guardan en objetos que la vista no observa: solo se redibuja lo que cambia.
enum SmoothScrolling {
    static let enabledKey = "files.smoothScrolling"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil || UserDefaults.standard.bool(forKey: enabledKey)
    }
}

/// Posiciones de las celdas: se leen solo al arrastrar el recuadro, nunca al dibujar.
final class TileFrameBox {
    var frames: [URL: CGRect] = [:]
}

/// Archivo bajo el puntero. Solo lo observa el fondo de cada celda.
final class HoverTracker: ObservableObject {
    @Published private(set) var url: URL?

    func set(_ url: URL, inside: Bool) {
        if inside { if self.url != url { self.url = url } } else if self.url == url { self.url = nil }
    }
}

/// Fondo de preselección de una celda (se redibuja ella sola al pasar el ratón).
struct HoverFill: View {
    @ObservedObject var tracker: HoverTracker
    let url: URL
    let active: Bool
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(active && tracker.url == url ? Color.accentColor.opacity(0.08) : .clear)
    }
}
