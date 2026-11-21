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

/// Sección «Iconos y selección» de Ajustes: tamaño, separación y zona de clic con una sola vista previa.
struct ItemHitAreaSection: View {
    @AppStorage(ItemHitAreaSettings.compactKey) private var compact = true
    @AppStorage(ItemHitAreaSettings.spacingKey) private var spacing = ItemHitAreaSettings.defaultSpacing
    @AppStorage(BehaviorSettings.iconSizeKey) private var iconSize = BehaviorSettings.defaultIconSize

    var body: some View {
        Section("Icons and Selection") {
            HitAreaPreview(compact: compact, spacing: spacing, iconSize: iconSize)
            LabeledContent {
                HStack {
                    Slider(value: $iconSize, in: 32...128, step: 4)
                    Text("\(Int(iconSize)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                }
            } label: { Label("Icon size", systemImage: "arrow.up.left.and.arrow.down.right") }
            LabeledContent {
                HStack {
                    Slider(value: $spacing, in: 4...48, step: 2)
                    Text("\(Int(spacing)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                }
            } label: { Label("Space between icons", systemImage: "arrow.left.and.right") }
            Toggle(isOn: $compact) {
                Label("Compact click area (icon and name only)", systemImage: "cursorarrow.click")
                Text("A smaller click area leaves more empty space to start a drag selection.")
            }
            Button("Restore Defaults") {
                compact = true
                spacing = ItemHitAreaSettings.defaultSpacing
                iconSize = BehaviorSettings.defaultIconSize
            }
        }
    }
}
