import SwiftUI

/// Fork: en la barra de arriba, un botón con icono por cada vista (lista, compacta,
/// iconos) en vez del menú desplegable con texto. Apagado = menú original.
enum ViewModeButtons {
    static let key = "toolbar.viewButtons"
    static let showsCompactKey = "toolbar.viewButtons.showsCompact"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Vistas con botón: la compacta se puede quitar (por defecto están las tres).
    static func modes(showsCompact: Bool) -> [FileViewMode] {
        FileViewMode.allCases.filter { showsCompact || $0 != .compact }
    }

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
    var showsCompact: Bool? = nil
    let choose: (FileViewMode) -> Void
    @AppStorage(ViewModeButtons.showsCompactKey) private var storedShowsCompact = true

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ViewModeButtons.modes(showsCompact: showsCompact ?? storedShowsCompact)) { mode in
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
    @AppStorage(ViewModeButtons.showsCompactKey) private var showsCompact = true
    @State private var previewMode = FileViewMode.list

    var body: some View {
        Toggle(isOn: $on) {
            Label("View buttons with icons", systemImage: "square.grid.2x2")
            Text("One button per view next to Sort, the current one highlighted. Off: a single menu with the view names.")
        }
        Toggle(isOn: $showsCompact) {
            Label("Compact view button", systemImage: "rectangle.grid.1x2")
            Text("Off: only List and Icons. The Compact view stays in the View menu and ⌘2.")
        }
        .lockedSetting(!on)
        if !on { DisabledReason("Only for view buttons with icons. Turn that on above.") }
        SettingsPreviewBox(title: "Preview: top bar") {
            HStack {
                if on {
                    ViewModeButtonRow(selected: previewMode, showsCompact: showsCompact) { previewMode = $0 }
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
