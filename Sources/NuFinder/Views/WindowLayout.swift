import AppKit
import SwiftUI

/// Fork: qué se muestra en la parte de arriba de la ventana (Ajustes → Apariencia → Ventana).
/// Sin tocar nada se ve como el original.
enum LayoutSettings {
    static let showsTitleKey = "layout.showsTitle"
    static let tabBarKey = "layout.tabBar"       // "always", "multiple", "never"
    static let pathKey = "layout.path"           // "both", "buttons", "text"
    static let showsSearchKey = "layout.showsSearch"
    /// Sin barra de título: los botones van a la derecha de la fila de pestañas.
    static let compactTopKey = "layout.compactTop"
    /// Fork: el fondo de las pestañas en la barra de arriba con las esquinas redondeadas.
    static let roundedTabsKey = "layout.roundedTabs"

    static func showsTabBar(_ mode: String, tabCount: Int) -> Bool {
        switch mode {
        case "never": false
        case "multiple": tabCount > 1
        default: true
        }
    }
}

/// Barra de pestañas según el ajuste (con su línea de separación).
struct LayoutTabBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @AppStorage(LayoutSettings.tabBarKey) private var mode = "always"
    @AppStorage(LayoutSettings.compactTopKey) private var compactTop = false

    var body: some View {
        // En el modo compacto las pestañas van dentro de la barra de arriba (ver `CompactTabsToolbarItem`).
        if !compactTop && LayoutSettings.showsTabBar(mode, tabCount: browser.tabs.count) {
            TabBarView()
            Divider()
        }
    }
}

/// Pestañas dentro de la barra de arriba de la ventana. Ocupan el espacio libre hasta los botones,
/// para que estos queden en el borde derecho.
struct CompactTabs: View {
    @EnvironmentObject private var browser: BrowserModel
    @AppStorage(LayoutSettings.tabBarKey) private var mode = "always"
    @State private var width: CGFloat = 300
    @AppStorage("toolbar.showsSplit") private var showsSplit = true
    @AppStorage("toolbar.showsTerminal") private var showsTerminal = true
    @AppStorage("toolbar.showsOperations") private var showsOperations = true
    @AppStorage(LayoutSettings.roundedTabsKey) private var roundedTabs = false

    /// Espacio que ocupan los botones visibles de la derecha (unos 40 pt cada uno y un margen para que no se escondan en «»»).
    static func buttonsWidth(visible: Int) -> CGFloat { 22 + 40 * CGFloat(visible) }

    private var buttonsWidth: CGFloat {
        Self.buttonsWidth(visible: [showsSplit, showsTerminal, showsOperations].filter { $0 }.count)
    }

    var body: some View {
        // Las pestañas ocupan solo lo que necesitan; el resto sirve para mover la ventana.
        HStack(spacing: 0) {
            if LayoutSettings.showsTabBar(mode, tabCount: browser.tabs.count) {
                TabBarView()
                    .fixedSize(horizontal: true, vertical: false)
                    .clipShape(RoundedRectangle(cornerRadius: roundedTabs ? 14 : 0, style: .continuous)) // Fork: el fondo de las pestañas sigue la forma redondeada de la barra
                    .frame(maxWidth: width, alignment: .leading)
            }
            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width)
        .id(buttonsWidth) // vuelve a medir al mostrar u ocultar botones
        .background(ToolbarSpaceReader { available in
            let target = max(120, available - buttonsWidth)
            if abs(target - width) > 2 { width = target }
        })
    }
}

/// Espacio vacío desde el que se arrastra la ventana; doble clic la maximiza (como la barra de título).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        // Como la barra de título: se arrastra aunque la ventana no esté activa.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
                if action == "Minimize" { window?.performMiniaturize(nil) } else if action != "None" { window?.performZoom(nil) }
            } else {
                window?.performDrag(with: event)
            }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// Mide el espacio desde el inicio de esta vista hasta el borde derecho de la ventana.
private struct ToolbarSpaceReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class ReaderView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            DispatchQueue.main.async { self.report() }
        }

        func report() {
            guard let window else { return }
            let minX = convert(bounds, to: nil).minX
            let available = window.frame.width - minX
            DispatchQueue.main.async { self.onChange?(available) }
        }
    }
}

/// Barra de búsqueda según el ajuste. Oculta, ⌘F la muestra mientras se busca.
struct LayoutSearchBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @AppStorage(LayoutSettings.showsSearchKey) private var shows = true
    @State private var revealed = false

    var body: some View {
        Group {
            if shows || revealed || !browser.searchText.isEmpty {
                SearchBarView()
                Divider()
            }
        }
        .onChange(of: browser.searchFocusToken) { _, _ in
            guard !shows, !revealed else { return }
            revealed = true
            // La barra recién creada necesita recibir el aviso de foco después de aparecer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { browser.searchFocusToken = UUID() }
        }
        .onChange(of: browser.searchText) { _, text in
            if text.isEmpty { revealed = false }
        }
    }
}

/// Ruta en botones (la de siempre, sin cambios) más un botón que solo copia la ruta.
struct PathButtonsBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            BreadcrumbView()
            Button {
                FileActionService.copyPaths([browser.currentURL])
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.green : Color.secondary)
            }
            .buttonStyle(HoverPressButtonStyle())
            .help(Text("Copy path"))
        }
    }
}

/// Muestra u oculta el título «Explorer» de la ventana; los botones de arriba se quedan.
struct WindowTitleVisibility: NSViewRepresentable {
    @AppStorage(LayoutSettings.showsTitleKey) private var showsTitle = true
    @AppStorage(LayoutSettings.compactTopKey) private var compactTop = false

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let visibility: NSWindow.TitleVisibility = showsTitle && !compactTop ? .visible : .hidden
        let compact = compactTop
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = visibility
            _ = compact
        }
    }
}

/// Sección «Ventana» de Ajustes → Apariencia, con vista previa de la parte de arriba.
struct WindowLayoutSection: View {
    @AppStorage(LayoutSettings.showsTitleKey) private var showsTitle = true
    @AppStorage(LayoutSettings.tabBarKey) private var tabBar = "always"
    @AppStorage(LayoutSettings.pathKey) private var path = "both"
    @AppStorage(LayoutSettings.showsSearchKey) private var showsSearch = true
    @AppStorage(LayoutSettings.compactTopKey) private var compactTop = false
    @AppStorage(LayoutSettings.roundedTabsKey) private var roundedTabs = false

    var body: some View {
        Section("Window") {
            SettingsPreviewBox(title: "Preview: top of the window") { preview }
            Toggle(isOn: $compactTop) {
                Label("Tabs in the top bar (one row)", systemImage: "rectangle.topthird.inset.filled")
                Text("The tabs go into the window’s top bar, next to its buttons, instead of a row of their own.")
            }
            Toggle(isOn: $roundedTabs) {
                Label("Rounded tabs background", systemImage: "capsule")
                Text("The dark background behind the tabs and the + button gets rounded ends like the bar. Off: it ends in a straight edge.")
            }
            .lockedSetting(!compactTop)
            if !compactTop {
                DisabledReason("Only for tabs in the top bar. Turn on “Tabs in the top bar” above.")
            }
            Toggle(isOn: $showsTitle) {
                Label("Window title “Explorer”", systemImage: "textformat")
                Text("The buttons on the right stay.")
            }
            .lockedSetting(compactTop)
            if compactTop {
                DisabledReason("Not available while the tabs are in the top bar: they take the title’s place. Turn off “Tabs in the top bar” to show it.")
            }
            Picker(selection: $tabBar) {
                Text("Always").tag("always")
                Text("Only with 2 or more tabs").tag("multiple")
                Text("Never").tag("never")
            } label: { Label("Tab bar", systemImage: "rectangle.topthird.inset.filled") }
            Picker(selection: $path) {
                Text("Buttons and text (two rows)").tag("both")
                Text("Buttons with copy (one row)").tag("buttons")
                Text("Text only").tag("text")
            } label: {
                Label("Path", systemImage: "folder")
            }
            Toggle(isOn: $showsSearch) {
                Label("Search bar", systemImage: "magnifyingglass")
                Text("Hidden: ⌘F still searches.")
            }
            Button("Restore Defaults") {
                showsTitle = true; tabBar = "always"; path = "both"; showsSearch = true; compactTop = false
            }
        }
    }

    // Dibujo simplificado de las filas de arriba de la ventana, en el orden real.
    private var preview: some View {
        VStack(spacing: 0) {
            if compactTop {
                row(height: 24) {
                    HStack(spacing: 4) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 8) }
                        if tabBar != "never" {
                            HStack(spacing: 4) { tab("Proyectos", selected: true); tab("Descargas", selected: false); Image(systemName: "plus").font(.system(size: 8, weight: .bold)) }
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: roundedTabs ? 9 : 0, style: .continuous))
                                .padding(.leading, 6)
                                .animation(.default, value: roundedTabs)
                        }
                        Spacer()
                        ForEach(0..<3, id: \.self) { _ in mini(.accentColor) }
                    }
                }
            } else {
            row(height: 26) {
                HStack(spacing: 5) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 8) }
                    if showsTitle { Text(verbatim: "Explorer").font(.caption.weight(.semibold)).padding(.leading, 6) }
                    Spacer()
                    ForEach(0..<3, id: \.self) { _ in mini(.accentColor) }
                }
            }
            }
            if tabBar != "never" && !compactTop {
                row(height: 22) {
                    HStack(spacing: 4) {
                        tab("Proyectos", selected: true)
                        tab("Descargas", selected: false)
                        Spacer()
                    }
                }
                .opacity(tabBar == "multiple" ? 0.55 : 1)
                .overlay(alignment: .trailing) {
                    if tabBar == "multiple" { Text("only with 2+ tabs").font(.system(size: 9)).foregroundStyle(.secondary).padding(.trailing, 6) }
                }
            }
            row(height: 26) {
                HStack(spacing: 4) {
                    mini(.accentColor); mini(.accentColor); mini(.accentColor)
                    if path == "buttons" { crumbs; Image(systemName: "doc.on.doc").font(.system(size: 9)) }
                    else { textField }
                    mini(.accentColor); mini(.accentColor)
                }
            }
            if path == "both" { row(height: 20) { crumbs.frame(maxWidth: .infinity, alignment: .leading) } }
            if showsSearch {
                row(height: 22) {
                    HStack { Image(systemName: "magnifyingglass").font(.system(size: 9)); Text("Search by file name").font(.system(size: 9)).foregroundStyle(.secondary); Spacer() }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(["Assets", "Sources", "README.md"], id: \.self) { name in
                    HStack(spacing: 4) {
                        Image(systemName: name.contains(".") ? "doc" : "folder.fill").font(.system(size: 9)).foregroundStyle(Color.accentColor)
                        Text(verbatim: name).font(.system(size: 9))
                        Spacer()
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .animation(.default, value: [showsTitle, showsSearch, compactTop])
        .animation(.default, value: tabBar + path)
    }

    private func row<Content: View>(height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content().padding(.horizontal, 6).frame(height: height)
            Divider()
        }
        .background(.bar)
    }

    private func mini(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.85)).frame(width: 13, height: 11)
    }

    private func tab(_ name: String, selected: Bool) -> some View {
        Text(verbatim: name).font(.system(size: 9))
            .padding(.horizontal, 6).frame(height: 15)
            .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private var crumbs: some View {
        HStack(spacing: 2) {
            ForEach(["Users", "sebastian", "Proyectos"], id: \.self) { name in
                Image(systemName: "folder").font(.system(size: 8))
                Text(verbatim: name).font(.system(size: 9))
                if name != "Proyectos" { Image(systemName: "chevron.right").font(.system(size: 7)).foregroundStyle(.tertiary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textField: some View {
        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            .frame(height: 15)
            .overlay(alignment: .leading) { Text(verbatim: "/Users/sebastian/Proyectos").font(.system(size: 9)).foregroundStyle(.secondary).padding(.leading, 4) }
    }
}
