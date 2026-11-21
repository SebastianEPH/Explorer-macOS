import AppKit
import SwiftUI

/// Fork: qué se muestra en la parte de arriba de la ventana (Ajustes → Apariencia → Ventana).
/// Sin tocar nada se ve como el original.
enum LayoutSettings {
    static let showsTitleKey = "layout.showsTitle"
    static let tabBarKey = "layout.tabBar"       // "always", "multiple", "never"
    static let pathKey = "layout.path"           // "both", "buttons", "text"
    static let showsSearchKey = "layout.showsSearch"

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

    var body: some View {
        if LayoutSettings.showsTabBar(mode, tabCount: browser.tabs.count) {
            TabBarView()
            Divider()
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

/// Ruta en botones con copiar y editar, en la misma fila que atrás y adelante.
struct PathButtonsBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @Binding var editing: Bool
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            BreadcrumbView()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editing = true }
            Button { editing = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help(Text("Type a path"))
            Button {
                FileActionService.copyPaths([browser.currentURL])
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(Text("Copy path"))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Muestra u oculta el título «Explorer» de la ventana; los botones de arriba se quedan.
struct WindowTitleVisibility: NSViewRepresentable {
    @AppStorage(LayoutSettings.showsTitleKey) private var showsTitle = true

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let visibility: NSWindow.TitleVisibility = showsTitle ? .visible : .hidden
        DispatchQueue.main.async { view.window?.titleVisibility = visibility }
    }
}

/// Sección «Ventana» de Ajustes → Apariencia, con vista previa de la parte de arriba.
struct WindowLayoutSection: View {
    @AppStorage(LayoutSettings.showsTitleKey) private var showsTitle = true
    @AppStorage(LayoutSettings.tabBarKey) private var tabBar = "always"
    @AppStorage(LayoutSettings.pathKey) private var path = "both"
    @AppStorage(LayoutSettings.showsSearchKey) private var showsSearch = true

    var body: some View {
        Section("Window") {
            SettingsPreviewBox(title: "Preview: top of the window") { preview }
            Toggle(isOn: $showsTitle) {
                Label("Window title “Explorer”", systemImage: "textformat")
                Text("The buttons on the right stay.")
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
                Text("With buttons only, the pencil or a double-click lets you type a path.")
            }
            Toggle(isOn: $showsSearch) {
                Label("Search bar", systemImage: "magnifyingglass")
                Text("Hidden: ⌘F still searches.")
            }
            Button("Restore Defaults") {
                showsTitle = true; tabBar = "always"; path = "both"; showsSearch = true
            }
        }
    }

    // Dibujo simplificado de las filas de arriba de la ventana, en el orden real.
    private var preview: some View {
        VStack(spacing: 0) {
            row(height: 26) {
                HStack(spacing: 5) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 8) }
                    if showsTitle { Text(verbatim: "Explorer").font(.caption.weight(.semibold)).padding(.leading, 6) }
                    Spacer()
                    ForEach(0..<3, id: \.self) { _ in mini(.accentColor) }
                }
            }
            if tabBar != "never" {
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
                    if path == "buttons" { crumbs; Image(systemName: "pencil").font(.system(size: 9)); Image(systemName: "doc.on.doc").font(.system(size: 9)) }
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
        .animation(.default, value: [showsTitle, showsSearch])
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
