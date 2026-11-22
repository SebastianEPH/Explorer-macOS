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
            "finderRedirect.enabled": true,
            "layout.compactTop": true,
            "layout.path": "buttons",
            "layout.showsTitle": false,
            "open.foldersInNewTab": true,
            "preferredTerminalPath": "/Applications/iTerm.app",
            "previewPane.visible": false,
            "showsSplitPane": false,
            "toolbar.showsOperations": false,
            "toolbar.showsSplit": true,
            "view.default": "Icons",
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

    static func register(_ defaults: UserDefaults = .standard, force: Bool = false) {
        guard force || isInstalledApp else { return }
        defaults.register(defaults: mine)
    }
}
