import Foundation

/// Fork: mi configuración es la de por defecto. Lo que no esté guardado toma
/// estos valores; lo que cambies en Ajustes se guarda y manda sobre ellos.
enum DefaultSettings {
    /// La configuración del usuario del 22-11-2026, ahora por defecto.
    static var mine: [String: Any] {
        let home = NSHomeDirectory()
        return [
            "appearance.appIcon": "window-square",
            "appearance.appIconBackground": false,
            "appearance.appIconMargin": 0.1,
            "appearance.toolbarColor": "blue",
            "appearance.toolbarColorDark": "blue",
            "contextMenu.hidden": hiddenMenu,
            "customFavoritePaths": ["\(home)/Software Projects", "\(home)/Pictures"],
            "favoriteOrderPaths": [home, "\(home)/Software Projects", "\(home)/Desktop",
                                   "\(home)/Documents", "\(home)/Downloads", "\(home)/Pictures"],
            "files.compactHitArea": true,
            "files.gridSpacing": 18.0,
            "layout.compactTop": true,
            "layout.path": "buttons",
            "layout.showsTitle": false,
            "preferredTerminalPath": "/Applications/iTerm.app",
            "previewPane.visible": false,
            "showsSplitPane": false,
            "toolbar.showsOperations": false,
            "toolbar.showsSplit": true,
            "view.default": "Icons",
            "view.sameEverywhere": true,
            "files.sortFoldersBySize": true,
            "files.folderSizeParallel": 0,
            "volumes.ejectRetries": 3,
            "trash.deleteInside": true,
            "middleClick.closesTab": true,
            "middleClick.folder": "newWindow",
            "layout.roundedTabs": true,
            "view.iconSize": 40.0,
            "shortcut.commandPalette": "p",
        ]
    }

    private static let hiddenMenu = [
        "archive:alias,archive:batchRename,archive:calculateSize,archive:checksums,archive:compare,archive:compress,archive:copyFileURL,archive:copyFilename,archive:copyPath,archive:duplicate,archive:getInfo,archive:newFile,archive:newFromTemplate,archive:openInTerminal,archive:quickLook,archive:revealInFinder,archive:share,archive:symbolicLink,archive:tags",
        "background:bgCopyFolderPath,background:bgHiddenFiles,background:bgPasteAs,background:bgRevealHidden,background:bgRevealInFinder",
        "file:alias,file:batchRename,file:calculateSize,file:checksums,file:compare,file:compress,file:copyFileURL,file:copyFilename,file:copyPath,file:duplicate,file:getInfo,file:newFile,file:newFolder,file:newFromTemplate,file:openInTerminal,file:quickLook,file:revealInFinder,file:share,file:symbolicLink,file:tags",
        "folder:alias,folder:batchRename,folder:calculateSize,folder:checksums,folder:compress,folder:copyFileURL,folder:copyFilename,folder:duplicate,folder:getInfo,folder:newFromTemplate,folder:quickLook,folder:symbolicLink,folder:tags",
        "image:alias,image:batchRename,image:calculateSize,image:checksums,image:compress,image:copyFileURL,image:copyFilename,image:copyPath,image:duplicate,image:getInfo,image:newFile,image:newFromTemplate,image:openInTerminal,image:quickLook,image:revealInFinder,image:share,image:symbolicLink,image:tags",
    ].joined(separator: ",")

    /// Solo en la app instalada: las pruebas usan los valores de fábrica.
    static var isInstalledApp: Bool { Bundle.main.bundleIdentifier == "com.miguelrodriguez.NuFinder" }

    /// Lo último que dejé configurado: se escribe al cambiar cualquier ajuste y
    /// se carga al arrancar como valor por defecto (gana sobre `mine`).
    static let snapshotFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Explorer/Ajustes.plist")

    /// Claves que no son ajustes (tamaño de ventanas, estado de macOS).
    static func isSetting(_ key: String) -> Bool {
        !["NSWindow Frame", "NSSplitView", "com_apple_", "NSNavPanel", "NSToolbar"].contains { key.hasPrefix($0) }
    }

    static func register(_ defaults: UserDefaults = .standard, force: Bool = false, file: URL = snapshotFile) {
        guard force || isInstalledApp else { return }
        var values = mine
        if let data = try? Data(contentsOf: file),
           let saved = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            values.merge(saved) { _, new in new }
        }
        defaults.register(defaults: values)
        if !force { startSaving() }
    }

    /// Escribe en el archivo lo guardado ahora (solo ajustes).
    static func saveSnapshot(_ defaults: UserDefaults = .standard,
                             domain: String = Bundle.main.bundleIdentifier ?? "Explorer", file: URL = snapshotFile) {
        let values = (defaults.persistentDomain(forName: domain) ?? [:]).filter { isSetting($0.key) }
        guard !values.isEmpty,
              let data = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    nonisolated(unsafe) private static var pending: DispatchWorkItem?
    nonisolated(unsafe) private static var observer: NSObjectProtocol?

    private static func startSaving() {
        guard observer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { saveSnapshot() } // la primera vez
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            pending?.cancel()
            let work = DispatchWorkItem { saveSnapshot() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }
}
