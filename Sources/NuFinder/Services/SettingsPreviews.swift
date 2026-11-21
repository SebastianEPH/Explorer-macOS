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
                item("square.stack.3d.up", "Workspaces", on: true)
                item("rectangle.split.2x1", "Split Pane", on: split)
                item("terminal", "Terminal", on: terminal)
                item("arrow.left.arrow.right.circle", "File Operations", on: operations)
            }
            .animation(.default, value: [split, terminal, operations])
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

/// Cuadrícula de iconos con la zona de clic resaltada.
struct HitAreaPreview: View {
    let compact: Bool
    let spacing: Double

    var body: some View {
        SettingsPreviewBox(title: "Preview: blue = area that selects the file when clicked") {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(["Fotos", "Informe.pdf", "Música"], id: \.self) { name in
                    VStack(spacing: 4) {
                        Image(systemName: name.contains(".") ? "doc.fill" : "folder.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(name.contains(".") ? Color.secondary : Color.accentColor)
                        Text(verbatim: name).font(.caption)
                    }
                    .padding(6)
                    .frame(width: compact ? nil : 96)
                    .frame(maxHeight: compact ? nil : 80, alignment: .top)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.6)))
                }
            }
            .frame(height: 90)
            .animation(.default, value: compact)
            .animation(.default, value: spacing)
        }
    }
}

/// Menú contextual dibujado con las opciones que quedarán visibles.
struct ContextMenuPreview: View {
    let title: LocalizedStringKey
    let options: [ContextMenuOption]
    let hidden: String

    var body: some View {
        let visible = options.filter { ContextMenuSettings.isVisible($0, in: hidden) }
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                if visible.isEmpty {
                    Text("(empty menu)").font(.callout).foregroundStyle(.secondary).padding(8)
                }
                ForEach(visible) { option in
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol).frame(width: 16).foregroundStyle(.secondary)
                        Text(option.title).font(.system(size: 12))
                        Spacer(minLength: 0)
                        if option.hasSubmenu { Image(systemName: "chevron.right").font(.system(size: 9)) }
                    }
                    .foregroundStyle(option == .trash ? Color.red : Color.primary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 230, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .shadow(radius: 4, y: 2)
            Text("\(visible.count) of \(options.count) options").font(.caption2).foregroundStyle(.secondary)
        }
        .animation(.default, value: hidden)
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

    var hasSubmenu: Bool {
        [.openWith, .imageActions, .checksums, .newFromTemplate, .bgNewFromTemplate, .bgPasteAs, .bgViewAs].contains(self)
    }

    /// Cuándo aparece, para las opciones que no salen siempre.
    var condition: LocalizedStringKey? {
        switch self {
        case .openInNewTab, .openInNewWindow, .favorite: "Folders only"
        case .showPackageContents: "Only on app bundles and packages"
        case .imageActions: "Only on images"
        case .extract: "Only on ZIP and other archives"
        case .compare: "Only with two files selected"
        case .bgRevealHidden: "Only while hidden files are hidden"
        default: nil
        }
    }
}
