import SwiftUI

struct AddressBarRow: View {
    @EnvironmentObject private var browser: BrowserModel
    @AppStorage(LayoutSettings.pathKey) private var pathMode = "both" // Fork

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(browser.backHistory.reversed(), id: \.self) { url in
                        Button(url.path) { browser.navigateToHistory(url) }
                    }
                } label: {
                    paneNavigationIcon("chevron.left")
                } primaryAction: {
                    browser.goBack()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!browser.canGoBack)
                .help("Back; open the menu for history")

                Menu {
                    ForEach(browser.forwardHistory.reversed(), id: \.self) { url in
                        Button(url.path) { browser.navigateToHistory(url) }
                    }
                } label: {
                    paneNavigationIcon("chevron.right")
                } primaryAction: {
                    browser.goForward()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!browser.canGoForward)
                .help("Forward; open the menu for history")

                Button {
                    browser.goUp()
                } label: {
                    paneNavigationIcon("arrow.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Parent Folder")
                if pathMode == "buttons" { // Fork: ruta en botones con botón de copiar
                    PathButtonsBar()
                } else {
                Image(systemName: "location")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                AddressBarView()
                    .frame(maxWidth: .infinity)
                Button {
                    browser.navigateFromAddress()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .help("Go to Path")
                }
                viewModeMenu
                SortMenu()
                Button {
                    browser.showsGallery = true
                } label: {
                    FreeloaderToolbarIcon(systemName: "photo.on.rectangle.angled")
                }
                .buttonStyle(.plain)
                .help("Open Image Gallery")
            }
            if pathMode == "both" { BreadcrumbView() } // Fork
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        // Fork: un clic en esta barra ya no quita la selección (solo un clic en vacío u otro archivo)
    }

    private func paneNavigationIcon(_ systemName: String) -> some View {
        FreeloaderToolbarIcon(systemName: systemName)
    }

    private var viewModeMenu: some View {
        Menu {
            ForEach(FileViewMode.allCases) { mode in
                Button {
                    browser.viewMode = mode
                } label: {
                    Label(
                        mode.rawValue,
                        systemImage: browser.viewMode == mode ? "checkmark" : viewModeIcon(mode)
                    )
                }
            }
        } label: {
            FreeloaderToolbarIcon(
                systemName: viewModeIcon(browser.viewMode),
                isActive: browser.viewMode != .list
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("View Mode: \(String(localized: String.LocalizationValue(browser.viewMode.rawValue)))")
    }

    private func viewModeIcon(_ mode: FileViewMode) -> String {
        switch mode {
        case .list: "list.bullet"
        case .compact: "rectangle.grid.1x2"
        case .icons: "square.grid.2x2"
        }
    }
}
