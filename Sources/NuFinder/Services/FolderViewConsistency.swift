import SwiftUI

/// Fork: la misma carpeta se ve igual se abra desde donde se abra.
/// En el original, los favoritos guardaban su propia vista (distinta de la de la
/// carpeta) y al cambiar de pestaña no se leía la vista guardada de su carpeta.
/// Apagado = comportamiento original.
enum FolderViewConsistency {
    static let key = "view.sameEverywhere"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}

struct FolderViewConsistencyToggle: View {
    @AppStorage(FolderViewConsistency.key) private var on = false

    var body: some View {
        Toggle(isOn: $on) {
            Label("Same view wherever you open a folder from", systemImage: "rectangle.on.rectangle")
            Text("Favorites, tabs, new windows and the Terminal all use the folder’s own saved view. Off: favorites keep a separate view and switching tabs keeps the previous view.")
        }
        FolderViewConsistencyPreview(on: on)
    }
}

/// Vista previa: tres sitios desde los que se abre la misma carpeta y cómo se ve.
struct FolderViewConsistencyPreview: View {
    let on: Bool
    private let sources: [(String, String, FileViewMode)] = [
        ("Sidebar", "sidebar.left", .list),
        ("Tab", "square.on.square", .icons),
        ("Terminal", "terminal", .compact),
    ]

    var body: some View {
        SettingsPreviewBox(title: "Preview: opening “Fotos” from three places") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sources, id: \.0) { name, symbol, mode in
                    HStack(spacing: 8) {
                        Image(systemName: symbol).frame(width: 18)
                        Text(LocalizedStringKey(name)).font(.caption).frame(width: 70, alignment: .leading)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: icon(on ? .icons : mode)).foregroundStyle(Color.accentColor)
                        Text(LocalizedStringKey((on ? FileViewMode.icons : mode).rawValue)).font(.caption)
                    }
                }
            }
            .animation(.default, value: on)
        }
    }

    private func icon(_ mode: FileViewMode) -> String {
        switch mode {
        case .list: "list.bullet"
        case .compact: "square.grid.3x1.below.line.grid.1x2"
        case .icons: "square.grid.2x2"
        }
    }
}
