import AppKit
import SwiftUI

/// Fork: vistas previas en vivo para Ajustes, para ver a qué se refiere cada opción
/// y cómo queda antes de cerrar la ventana.

/// Marco común: título pequeño + dibujo de muestra.
struct SettingsPreviewBox<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "eye")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        }
        .padding(.vertical, 4)
    }
}

/// Barra de herramientas tal como aparece arriba a la derecha de la ventana.
struct ToolbarPreview: View {
    var workspaces = true
    let split: Bool
    let terminal: Bool
    let operations: Bool

    var body: some View {
        SettingsPreviewBox(title: "Preview: top right of the window") {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left").foregroundStyle(.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    .frame(height: 22)
                    .overlay(alignment: .leading) {
                        Text(verbatim: "~/Documents").font(.caption).foregroundStyle(.secondary).padding(.leading, 8)
                    }
                item("square.stack.3d.up", "Workspaces", on: workspaces)
                item("rectangle.split.2x1", "Split Pane", on: split)
                item("terminal", "Terminal", on: terminal)
                item("arrow.left.arrow.right.circle", "File Operations", on: operations)
            }
            .animation(.default, value: [workspaces, split, terminal, operations])
        }
    }

    @ViewBuilder
    private func item(_ symbol: String, _ name: LocalizedStringKey, on: Bool) -> some View {
        if on {
            VStack(spacing: 3) {
                FreeloaderToolbarIcon(systemName: symbol)
                Text(name).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
            }
            .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Icono de la app de terminal elegida.
struct AppIconView: View {
    let path: String
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable().frame(width: 20, height: 20)
    }
}

/// Atajo dibujado como teclas.
struct KeyCapsView: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(verbatim: key.uppercased())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
            }
        }
    }
}

/// Lista de archivos de ejemplo con o sin las insignias de Git.
struct GitBadgePreview: View {
    let enabled: Bool
    private let rows: [(String, String?, Color)] = [
        ("README.md", "M", .orange), ("main.swift", "A", .green), ("notas.txt", nil, .clear), ("viejo.swift", "D", .red)
    ]

    var body: some View {
        SettingsPreviewBox(title: "Preview: a folder inside a Git repository") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.0) { name, badge, color in
                    HStack(spacing: 6) {
                        Image(systemName: "doc").foregroundStyle(.secondary)
                        Text(verbatim: name).font(.callout)
                        if enabled, let badge {
                            Text(verbatim: badge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(color)
                        }
                        Spacer()
                    }
                }
                if enabled {
                    Text("M = modified · A = added · D = deleted").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Cuadrícula de iconos igual que la vista «Iconos» real: mismo tamaño, separación,
/// zona de clic (línea discontinua) y color de selección (el segundo está seleccionado).
struct HitAreaPreview: View {
    let compact: Bool
    let spacing: Double
    let iconSize: Double
    private let items = [("Fotos", "folder.fill"), ("Informe.pdf", "doc.fill"), ("Vacaciones.jpg", "photo.fill"), ("Música", "folder.fill")]

    var body: some View {
        SettingsPreviewBox(title: "Preview: Icons view · dashed line = click area · blue = selected") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: iconSize + 49), spacing: spacing)], spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 7) {
                        Image(systemName: item.1)
                            .font(.system(size: iconSize * 0.8))
                            .foregroundStyle(item.1 == "folder.fill" ? Color.accentColor : .secondary)
                            .frame(width: iconSize, height: iconSize)
                        Text(verbatim: item.0).font(.callout).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: compact ? iconSize + 36 : .infinity, minHeight: iconSize + 26)
                    .padding(7)
                    .background(index == 1 ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
            }
            .animation(.default, value: compact)
            .animation(.default, value: spacing)
            .animation(.default, value: iconSize)
        }
    }
}

/// Menú contextual dibujado tal como aparecerá, junto al elemento al que se le hace clic.
struct ContextMenuPreview: View {
    let scope: ContextMenuScope
    let hidden: String
    let order: [ContextMenuOption]

    var body: some View {
        let options = order
        let visible = options.filter { ContextMenuSettings.isVisible($0, scope: scope, in: hidden) }
        VStack(alignment: .leading, spacing: 6) {
            Label("Preview", systemImage: "eye").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .textBackgroundColor)
                if scope != .background {
                    VStack(spacing: 2) {
                        Image(systemName: scope.symbol).font(.system(size: 34))
                            .foregroundStyle(scope == .folder ? Color.accentColor : .secondary)
                        Text(verbatim: scope.example).font(.caption)
                            .padding(.horizontal, 4)
                            .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .padding(10)
                }
                Image(systemName: "cursorarrow").font(.system(size: 14)).offset(x: 42, y: 34)
                menu(visible).offset(x: 50, y: 44)
            }
            .frame(width: 290, height: CGFloat(max(visible.count, 1)) * 21 + 80, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            Text("\(visible.count) of \(options.count) options").font(.caption2).foregroundStyle(.secondary)
        }
        .animation(.default, value: hidden)
        .animation(.default, value: scope)
        .animation(.default, value: order)
    }

    private func menu(_ visible: [ContextMenuOption]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if visible.isEmpty {
                Text("(empty menu)").font(.callout).foregroundStyle(.secondary).padding(8)
            }
            ForEach(Array(visible.enumerated()), id: \.element) { index, option in
                if index > 0, option.startsGroup { Divider().padding(.vertical, 2) }
                HStack(spacing: 6) {
                    Image(systemName: option.symbol).frame(width: 16).foregroundStyle(.secondary)
                    Text(option.title(in: scope)).font(.system(size: 12))
                    Spacer(minLength: 0)
                    if option.hasSubmenu { Image(systemName: "chevron.right").font(.system(size: 9)) }
                }
                .foregroundStyle(option == .trash ? Color.red : Color.primary)
                .padding(.horizontal, 8).frame(height: 19)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 225, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

/// Esquema: clic en Finder del Dock → se abre Explorer.
struct FinderRedirectPreview: View {
    let enabled: Bool

    var body: some View {
        SettingsPreviewBox(title: "Preview: what happens when you click Finder in the Dock") {
            HStack(spacing: 14) {
                appIcon("/System/Library/CoreServices/Finder.app", "Finder")
                Image(systemName: "arrow.right").font(.title2).foregroundStyle(.secondary)
                if enabled {
                    appIcon(Bundle.main.bundlePath, "Explorer")
                } else {
                    appIcon("/System/Library/CoreServices/Finder.app", "Finder")
                }
            }
        }
    }

    private func appIcon(_ path: String, _ name: String) -> some View {
        VStack(spacing: 2) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 40, height: 40)
            Text(verbatim: name).font(.caption)
        }
    }
}

extension ContextMenuOption {
    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .openInNewTab: "plus.square.on.square"
        case .openInNewWindow: "macwindow.badge.plus"
        case .showPackageContents: "shippingbox"
        case .quickLook: "eye"
        case .getInfo: "info.circle"
        case .revealInFinder, .bgRevealInFinder: "magnifyingglass"
        case .openWith: "app.badge"
        case .share: "square.and.arrow.up"
        case .imageActions: "photo"
        case .favorite: "star"
        case .openInTerminal, .bgOpenInTerminal: "terminal"
        case .cut: "scissors"
        case .copy: "doc.on.doc"
        case .paste, .bgPaste: "doc.on.clipboard"
        case .duplicate: "plus.square.on.square"
        case .compress: "doc.zipper"
        case .extract: "arrow.down.doc"
        case .copyPath, .bgCopyFolderPath: "link"
        case .copyFilename: "textformat"
        case .copyFileURL: "globe"
        case .calculateSize: "scalemass"
        case .checksums: "number"
        case .batchRename: "pencil.and.list.clipboard"
        case .symbolicLink: "arrow.triangle.branch"
        case .alias: "arrowshape.turn.up.right"
        case .tags: "tag"
        case .compare: "rectangle.split.2x1"
        case .rename: "pencil"
        case .trash: "trash"
        case .newFolder, .bgNewFolder: "folder.badge.plus"
        case .newFile, .bgNewFile: "doc.badge.plus"
        case .newFromTemplate, .bgNewFromTemplate: "doc.on.doc.fill"
        case .bgPasteAs: "doc.on.clipboard.fill"
        case .bgHiddenFiles: "eye.slash"
        case .bgRevealHidden: "timer"
        case .bgViewAs: "square.grid.2x2"
        case .bgReload: "arrow.clockwise"
        }
    }

    /// Donde el menú real pone una línea separadora antes de esta opción.
    var startsGroup: Bool {
        [.cut, .trash, .newFolder, .bgOpenInTerminal, .bgPaste, .bgHiddenFiles].contains(self)
    }

    var hasSubmenu: Bool {
        [.openWith, .imageActions, .checksums, .newFromTemplate, .bgNewFromTemplate, .bgPasteAs, .bgViewAs].contains(self)
    }

    /// Cuándo aparece, para las opciones que no salen siempre.
    var condition: LocalizedStringKey? {
        switch self {
        case .showPackageContents: "Only on app bundles and packages"
        case .compare: "Only with two files selected"
        case .bgRevealHidden: "Only while hidden files are hidden"
        default: nil
        }
    }
}

/// Fork: explica por qué un control está desactivado y cómo activarlo
/// (si no, parece que «no hace caso» al hacer clic).
struct DisabledReason: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "lock.fill") }
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
