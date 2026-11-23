import SwiftUI

/// Fork: en la barra de arriba, un botón con icono por cada vista (lista, compacta,
/// iconos) en vez del menú desplegable con texto. Apagado = menú original.
enum ViewModeButtons {
    static let key = "toolbar.viewButtons"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static func icon(_ mode: FileViewMode) -> String {
        switch mode {
        case .list: "list.bullet"
        case .compact: "rectangle.grid.1x2"
        case .icons: "square.grid.2x2"
        }
    }
}

struct ViewModeButtonsView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        ViewModeButtonRow(selected: browser.viewMode) { browser.viewMode = $0 }
    }
}

/// Los tres botones juntos; el de la vista actual va resaltado.
struct ViewModeButtonRow: View {
    let selected: FileViewMode
    let choose: (FileViewMode) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(FileViewMode.allCases) { mode in
                Button { choose(mode) } label: {
                    FreeloaderToolbarIcon(systemName: ViewModeButtons.icon(mode), isActive: selected == mode)
                        .opacity(selected == mode ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey(mode.rawValue))
                .accessibilityLabel(Text(LocalizedStringKey(mode.rawValue)))
                .accessibilityAddTraits(selected == mode ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}

struct ViewModeButtonsToggle: View {
    @AppStorage(ViewModeButtons.key) private var on = false
    @State private var previewMode = FileViewMode.list

    var body: some View {
        Toggle(isOn: $on) {
            Label("View buttons with icons", systemImage: "square.grid.2x2")
            Text("One button per view next to Sort, the current one highlighted. Off: a single menu with the view names.")
        }
        SettingsPreviewBox(title: "Preview: top bar") {
            HStack {
                if on {
                    ViewModeButtonRow(selected: previewMode) { previewMode = $0 }
                } else {
                    HStack(spacing: 4) {
                        FreeloaderToolbarIcon(systemName: ViewModeButtons.icon(previewMode))
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(FileViewMode.allCases) { Text(LocalizedStringKey($0.rawValue)).font(.caption2) }
                        }
                        .padding(4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                Spacer()
            }
            .animation(.default, value: on)
        }
    }
}
