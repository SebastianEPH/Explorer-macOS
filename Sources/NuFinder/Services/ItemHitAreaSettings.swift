import SwiftUI

/// Fork: tamaño de la zona que ocupa cada archivo al hacer clic, para dejar más
/// espacio libre donde empezar una selección arrastrando.
enum ItemHitAreaSettings {
    /// true: la zona de clic se ajusta al icono y al nombre. false: ocupa todo el ancho (original).
    static let compactKey = "files.compactHitArea"
    /// Separación entre iconos en las vistas de iconos y mosaico.
    static let spacingKey = "files.gridSpacing"
    static let defaultSpacing = 18.0
}

/// Sección «Selection» de Ajustes.
struct ItemHitAreaSection: View {
    @AppStorage(ItemHitAreaSettings.compactKey) private var compact = true
    @AppStorage(ItemHitAreaSettings.spacingKey) private var spacing = ItemHitAreaSettings.defaultSpacing

    var body: some View {
        Section("Selection") {
            Toggle("Compact click area (icon and name only)", isOn: $compact)
            LabeledContent("Space between icons") {
                HStack {
                    Slider(value: $spacing, in: 4...48, step: 2)
                    Text("\(Int(spacing)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Text("A smaller click area leaves more empty space to start a drag selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
