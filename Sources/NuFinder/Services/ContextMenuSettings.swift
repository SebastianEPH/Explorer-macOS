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

enum ContextMenuSettings {
    /// Opciones ocultas, separadas por comas (vacío = se ve todo, como el original).
    static let hiddenKey = "contextMenu.hidden"

    static func hiddenSet(_ stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map(String.init))
    }

    static func isVisible(_ option: ContextMenuOption, in stored: String) -> Bool {
        !hiddenSet(stored).contains(option.rawValue)
    }

    static func setting(_ option: ContextMenuOption, visible: Bool, in stored: String) -> String {
        var hidden = hiddenSet(stored)
        if visible { hidden.remove(option.rawValue) } else { hidden.insert(option.rawValue) }
        return hidden.sorted().joined(separator: ",")
    }
}

/// Sección «Context Menu» de Ajustes.
struct ContextMenuSection: View {
    @AppStorage(ContextMenuSettings.hiddenKey) private var hidden = ""

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 20) {
                ContextMenuPreview(title: "Right-click on a file or folder", options: ContextMenuOption.allCases.filter { !$0.isBackground }, hidden: hidden)
                ContextMenuPreview(title: "Right-click on empty space", options: ContextMenuOption.allCases.filter(\.isBackground), hidden: hidden)
            }
            .frame(maxWidth: .infinity)
            Button("Show All Options") { hidden = "" }
                .disabled(hidden.isEmpty)
        } footer: {
            Text("Choose which options appear when you right-click.")
        }
        Section("On a file or folder") {
            toggles(ContextMenuOption.allCases.filter { !$0.isBackground })
        }
        Section("On empty space") {
            toggles(ContextMenuOption.allCases.filter(\.isBackground))
        }
    }

    private func toggles(_ options: [ContextMenuOption]) -> some View {
        ForEach(options) { option in
            Toggle(isOn: Binding(
                get: { ContextMenuSettings.isVisible(option, in: hidden) },
                set: { hidden = ContextMenuSettings.setting(option, visible: $0, in: hidden) }
            )) {
                Label(option.title, systemImage: option.symbol)
                if let condition = option.condition { Text(condition) }
            }
        }
    }
}

extension View {
    /// Fork: una pestaña de Ajustes con formulario agrupado y desplazable.
    func settingsTab(_ title: LocalizedStringKey, systemImage: String) -> some View {
        formStyle(.grouped).tabItem { Label(title, systemImage: systemImage) }
    }
}
