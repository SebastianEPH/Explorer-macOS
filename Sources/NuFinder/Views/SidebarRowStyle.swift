import SwiftUI

/// Fork: efecto sutil en las filas de la barra lateral: fondo suave al pasar el ratón,
/// algo más oscuro al pulsar y la carpeta abierta resaltada con el color de acento.
struct SidebarRowButtonStyle: ButtonStyle {
    var isCurrent = false

    func makeBody(configuration: Configuration) -> some View {
        SidebarRow(configuration: configuration, isCurrent: isCurrent)
    }

    private struct SidebarRow: View {
        let configuration: Configuration
        let isCurrent: Bool
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isCurrent)
        }

        private var background: Color {
            if configuration.isPressed { return Color.primary.opacity(0.14) }
            if isCurrent { return Color.accentColor.opacity(isHovering ? 0.24 : 0.18) }
            return isHovering ? Color.primary.opacity(0.07) : .clear
        }
    }
}
