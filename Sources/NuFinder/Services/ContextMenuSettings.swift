import SwiftUI

/// Fork: opciones del menú contextual (clic derecho) que el usuario puede ocultar.
/// Las claves de texto son las mismas que usa el menú, así reutilizan sus traducciones.
enum ContextMenuOption: String, CaseIterable, Identifiable {
    // Sobre un archivo o carpeta
    case open, openInNewTab, openInNewWindow, showPackageContents, quickLook, getInfo
    case revealInFinder, openWith, share, imageActions, favorite, openInTerminal
    case cut, copy, paste, duplicate, compress, extract
    case copyPath, copyFilename, copyFileURL, calculateSize, checksums
    case batchRename, symbolicLink, alias, tags, compare, rename, trash
    case newFolder, newFile, newFromTemplate
    // Sobre el espacio vacío de la carpeta
    case bgNewFolder, bgNewFile, bgNewFromTemplate, bgOpenInTerminal, bgRevealInFinder
    case bgCopyFolderPath, bgPaste, bgPasteAs, bgHiddenFiles, bgRevealHidden, bgViewAs, bgReload

    var id: String { rawValue }

    var isBackground: Bool { rawValue.hasPrefix("bg") }

    /// Nombre tal como sale en el menú real de ese tipo (algunas opciones cambian de nombre).
    func title(in scope: ContextMenuScope) -> LocalizedStringKey {
        switch (self, scope) {
        case (.openInTerminal, .file), (.openInTerminal, .image), (.openInTerminal, .archive): "Open Parent in Terminal"
        case (.paste, .folder): "Paste into Folder"
        default: title
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .open: "Open"
        case .openInNewTab: "Open in New Tab"
        case .openInNewWindow: "Open in New Window"
        case .showPackageContents: "Show Package Contents"
        case .quickLook: "Quick Look"
        case .getInfo: "Get Info"
        case .revealInFinder, .bgRevealInFinder: "Reveal in Finder"
        case .openWith: "Open With"
        case .share: "Share…"
        case .imageActions: "Image Actions"
        case .favorite: "Add to Favorites"
        case .openInTerminal, .bgOpenInTerminal: "Open in Terminal"
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste, .bgPaste: "Paste"
        case .duplicate: "Duplicate"
        case .compress: "Compress to ZIP"
        case .extract: "Extract Here"
        case .copyPath: "Copy Path"
        case .copyFilename: "Copy Filename"
        case .copyFileURL: "Copy File URL"
        case .calculateSize: "Calculate Size"
        case .checksums: "Calculate Checksums"
        case .batchRename: "Batch Rename…"
        case .symbolicLink: "Create Symbolic Link"
        case .alias: "Create Alias"
        case .tags: "Tags…"
        case .compare: "Compare Files"
        case .rename: "Rename"
        case .trash: "Move to Trash"
        case .newFolder, .bgNewFolder: "New Folder…"
        case .newFile, .bgNewFile: "New File…"
        case .newFromTemplate, .bgNewFromTemplate: "New from Template"
        case .bgCopyFolderPath: "Copy Folder Path"
        case .bgPasteAs: "Paste As"
        case .bgHiddenFiles: "Show Hidden Files"
        case .bgRevealHidden: "Reveal Hidden Files for 30 Seconds"
        case .bgViewAs: "View As"
        case .bgReload: "Reload"
        }
    }
}

/// Fork: a qué se le hace clic derecho. Cada tipo tiene su propio menú configurable.
enum ContextMenuScope: String, CaseIterable, Identifiable {
    case folder, file, image, archive, background
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .folder: "Folder"
        case .file: "File"
        case .image: "Image"
        case .archive: "Archive"
        case .background: "Empty Space"
        }
    }

    var symbol: String {
        switch self {
        case .folder: "folder.fill"
        case .file: "doc.fill"
        case .image: "photo.fill"
        case .archive: "doc.zipper"
        case .background: "rectangle.dashed"
        }
    }

    var example: String {
        switch self {
        case .folder: "Proyectos"
        case .file: "Informe.pdf"
        case .image: "Vacaciones.jpg"
        case .archive: "Fotos.zip"
        case .background: ""
        }
    }

    static func of(_ item: FileItem) -> ContextMenuScope {
        if item.isDirectory { return .folder }
        if item.isImage { return .image }
        if ArchiveService.isArchive(item.url) { return .archive }
        return .file
    }

    /// Opciones que pueden salir en el menú de este tipo, en el mismo orden que el menú real.
    var options: [ContextMenuOption] {
        let folderOnly: Set<ContextMenuOption> = [.openInNewTab, .openInNewWindow, .showPackageContents, .favorite]
        let fileOnly: Set<ContextMenuOption> = [.imageActions, .extract, .compare]
        let items = ContextMenuOption.allCases.filter { !$0.isBackground }
        switch self {
        case .background: return ContextMenuOption.allCases.filter(\.isBackground)
        case .folder: return items.filter { !fileOnly.contains($0) }
        case .file: return items.filter { !folderOnly.contains($0) && $0 != .imageActions && $0 != .extract }
        case .image: return items.filter { !folderOnly.contains($0) && $0 != .extract }
        case .archive: return items.filter { !folderOnly.contains($0) && $0 != .imageActions }
        }
    }
}

enum ContextMenuSettings {
    /// Opciones ocultas, separadas por comas: "tipo:opción" (vacío = se ve todo, como el original).
    /// Una opción sin tipo (versión anterior) se oculta en todos los tipos.
    static let hiddenKey = "contextMenu.hidden"

    static func hiddenSet(_ stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map(String.init))
    }

    static func isVisible(_ option: ContextMenuOption, scope: ContextMenuScope, in stored: String) -> Bool {
        let hidden = hiddenSet(stored)
        return !hidden.contains(option.rawValue) && !hidden.contains("\(scope.rawValue):\(option.rawValue)")
    }

    static func setting(_ option: ContextMenuOption, scope: ContextMenuScope, visible: Bool, in stored: String) -> String {
        var hidden = hiddenSet(stored)
        if hidden.remove(option.rawValue) != nil { // pasar el formato antiguo a uno por tipo
            for other in ContextMenuScope.allCases where other != scope && other.options.contains(option) {
                hidden.insert("\(other.rawValue):\(option.rawValue)")
            }
        }
        let key = "\(scope.rawValue):\(option.rawValue)"
        if visible { hidden.remove(key) } else { hidden.insert(key) }
        return hidden.sorted().joined(separator: ",")
    }

    /// Orden propio de cada tipo: "tipo=a,b,c;tipo2=…" (vacío = orden original).
    static let orderKey = "contextMenu.order"

    private static func orders(_ stored: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for part in stored.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            result[String(pair[0])] = pair[1].split(separator: ",").map(String.init)
        }
        return result
    }

    /// Opciones del tipo en el orden elegido; las que falten (opciones nuevas) van en su sitio original.
    static func order(_ scope: ContextMenuScope, in stored: String) -> [ContextMenuOption] {
        let defaults = scope.options
        guard let saved = orders(stored)[scope.rawValue] else { return defaults }
        var result = saved.compactMap(ContextMenuOption.init(rawValue:)).filter(defaults.contains)
        for (index, option) in defaults.enumerated() where !result.contains(option) {
            let previous = defaults[..<index].last(where: result.contains)
            let position = previous.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(option, at: position)
        }
        return result
    }

    static func setting(_ order: [ContextMenuOption]?, for scope: ContextMenuScope, in stored: String) -> String {
        var all = orders(stored)
        all[scope.rawValue] = order?.map(\.rawValue)
        return all.keys.sorted().compactMap { key in all[key].map { "\(key)=\($0.joined(separator: ","))" } }
            .joined(separator: ";")
    }

    static func resetting(_ scope: ContextMenuScope, in stored: String) -> String {
        var hidden = hiddenSet(stored)
        hidden = hidden.filter { !$0.hasPrefix("\(scope.rawValue):") }
        for option in scope.options where hidden.remove(option.rawValue) != nil {
            for other in ContextMenuScope.allCases where other != scope && other.options.contains(option) {
                hidden.insert("\(other.rawValue):\(option.rawValue)")
            }
        }
        return hidden.sorted().joined(separator: ",")
    }
}

/// Pestaña «Menú contextual» de Ajustes: un menú por tipo, con su vista previa.
/// Las opciones se ocultan con el interruptor y se mueven arrastrando o con las flechas.
struct ContextMenuSection: View {
    @AppStorage(ContextMenuSettings.hiddenKey) private var hidden = ""
    @AppStorage(ContextMenuSettings.orderKey) private var orderStore = ""
    @State private var scope: ContextMenuScope = .folder

    private var order: [ContextMenuOption] { ContextMenuSettings.order(scope, in: orderStore) }

    var body: some View {
        Section {
            Picker("Right-click on", selection: $scope) {
                ForEach(ContextMenuScope.allCases) { scope in
                    Label(scope.title, systemImage: scope.symbol).tag(scope)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Each type has its own menu. Turn options off, drag them or use the arrows to move them, and watch the preview change.")
        }
        Section {
            HStack(alignment: .top, spacing: 24) {
                ContextMenuPreview(scope: scope, hidden: hidden, order: order)
                VStack(alignment: .leading, spacing: 0) {
                    List {
                        ForEach(order) { option in row(option) }
                            .onMove { from, to in
                                var moved = order
                                moved.move(fromOffsets: from, toOffset: to)
                                orderStore = ContextMenuSettings.setting(moved, for: scope, in: orderStore)
                            }
                    }
                    .listStyle(.plain)
                    .frame(height: CGFloat(order.count) * 34)
                    .scrollDisabled(true)
                    HStack {
                        Button("Hide All") {
                            for option in scope.options {
                                hidden = ContextMenuSettings.setting(option, scope: scope, visible: false, in: hidden)
                            }
                        }
                        Button("Show All") { hidden = ContextMenuSettings.resetting(scope, in: hidden) }
                        Spacer()
                        Button("Original Order") { orderStore = ContextMenuSettings.setting(nil, for: scope, in: orderStore) }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func row(_ option: ContextMenuOption) -> some View {
        let index = order.firstIndex(of: option) ?? 0
        return HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help(Text("Drag to move"))
            Toggle(isOn: Binding(
                get: { ContextMenuSettings.isVisible(option, scope: scope, in: hidden) },
                set: { hidden = ContextMenuSettings.setting(option, scope: scope, visible: $0, in: hidden) }
            )) {
                Label(option.title(in: scope), systemImage: option.symbol)
                if let condition = option.condition { Text(condition) }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Spacer(minLength: 4)
            Button { move(option, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(index == 0).help(Text("Move up"))
            Button { move(option, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(index == order.count - 1).help(Text("Move down"))
        }
        .frame(height: 26)
    }

    private func move(_ option: ContextMenuOption, by delta: Int) {
        var moved = order
        guard let index = moved.firstIndex(of: option), moved.indices.contains(index + delta) else { return }
        moved.swapAt(index, index + delta)
        orderStore = ContextMenuSettings.setting(moved, for: scope, in: orderStore)
    }
}

extension View {
    /// Fork: una pestaña de Ajustes con formulario agrupado y desplazable.
    func settingsTab(_ title: LocalizedStringKey, systemImage: String) -> some View {
        formStyle(.grouped).tabItem { Label(title, systemImage: systemImage) }
    }
}
