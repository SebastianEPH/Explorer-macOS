import SwiftUI

/// Fork: efectos sutiles para que se note qué se puede pulsar y cuándo se pulsa.

/// Botón con fondo suave al pasar el ratón y algo más oscuro (y hundido) al pulsar.
struct HoverPressButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 5
    var padding: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        HoverPressBody(configuration: configuration, cornerRadius: cornerRadius, padding: padding)
    }

    private struct HoverPressBody: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let padding: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, padding + 1)
                .padding(.vertical, padding)
                .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 && isEnabled }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var fill: Color {
            if configuration.isPressed { return Color.primary.opacity(0.16) }
            return hovering ? Color.primary.opacity(0.08) : .clear
        }
    }
}

extension View {
    /// Para menús y botones de color: se aclaran y crecen un poco al pasar el ratón.
    func hoverLift() -> some View { modifier(HoverLift()) }

    /// Para elementos que no son botones (p. ej. pestañas): fondo suave al pasar el ratón.
    func hoverHighlight(cornerRadius: CGFloat = 7) -> some View { modifier(HoverHighlight(cornerRadius: cornerRadius)) }
}

private struct HoverLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.08 : 0)
            .scaleEffect(hovering ? 1.07 : 1)
            .onHover { hovering = $0 && isEnabled }
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: hovering)
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
