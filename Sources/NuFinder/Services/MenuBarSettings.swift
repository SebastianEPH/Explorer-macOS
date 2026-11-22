import AppKit
import SwiftUI

/// Fork: barra de menús de arriba (Explorer, Archivo, Edición, Visualización…), configurable en
/// Ajustes → General → Barra de menús. Por defecto quedan los menús útiles y un menú «Opciones»
/// con los ajustes de Explorer a un clic.
enum MenuBarSettings {
    static let showsGoKey = "menu.showsGo"
    static let showsCommandsKey = "menu.showsCommands"
    static let showsOptionsKey = "menu.showsOptions"
    static let hidesEmojiKey = "menu.hidesEmojiDictation"
    /// Pestañas de ventana de macOS («Mostrar barra de pestañas»): distintas de las de Explorer y confunden.
    static let hidesWindowTabsKey = "menu.hidesWindowTabs"

    @MainActor
    static func applyWindowTabbing(_ defaults: UserDefaults = .standard) {
        NSWindow.allowsAutomaticWindowTabbing = !(defaults.object(forKey: hidesWindowTabsKey) as? Bool ?? true)
    }

    /// Quita de Edición «Emoji y símbolos» e «Iniciar dictado» (los añade macOS).
    /// Debe llamarse antes de que se cree el menú, al arrancar.
    /// Quita también «Autorrelleno» (no tiene ajuste propio): se busca por su acción y se elimina
    /// cada vez que macOS vuelve a montar el menú.
    @MainActor
    static func removeAutoFill() {
        guard UserDefaults.standard.object(forKey: hidesEmojiKey) as? Bool ?? true else { return }
        func clean(_ menu: NSMenu) {
            for item in menu.items {
                let action = item.action.map(NSStringFromSelector)?.lowercased() ?? ""
                if action.contains("autofill") || item.identifier?.rawValue.lowercased().contains("autofill") == true {
                    menu.removeItem(item)
                } else if let sub = item.submenu { clean(sub) }
            }
        }
        if let main = NSApp.mainMenu { clean(main) }
    }

    @MainActor private static var observer: NSObjectProtocol?

    @MainActor
    static func startCleaning() {
        removeAutoFill()
        observer = NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { removeAutoFill() }
        }
    }

    static func applySystemItems(_ defaults: UserDefaults = .standard) {
        let hide = defaults.object(forKey: hidesEmojiKey) as? Bool ?? true
        defaults.set(hide, forKey: "NSDisabledCharacterPaletteMenuItem")
        defaults.set(hide, forKey: "NSDisabledDictationMenuItem")
    }
}

/// Menú «Opciones» y navegación, sin depender del código del autor.
struct ExplorerMenus: Commands {
    /// Ventana activa: atrás, adelante, carpeta superior, recientes y paleta de comandos.
    let browser: () -> BrowserModel
    let commandPaletteKey: String

    @AppStorage(MenuBarSettings.showsOptionsKey) private var showsOptions = true
    @AppStorage(MenuBarSettings.showsGoKey) private var showsGo = false
    @AppStorage(MenuBarSettings.showsCommandsKey) private var showsCommands = false
    @AppStorage(AppearanceSettings.themeKey) private var theme = ""
    @AppStorage(LayoutSettings.compactTopKey) private var compactTop = false
    @AppStorage(LayoutSettings.showsSearchKey) private var showsSearch = true
    @AppStorage(LayoutSettings.pathKey) private var path = "both"
    @AppStorage(StatusBarSettings.visibleKey) private var statusBar = true
    @AppStorage(FolderSizeQueue.autoKey) private var folderSizes = true
    @AppStorage(BehaviorSettings.confirmTrashKey) private var confirmTrash = false
    @AppStorage(BehaviorSettings.foldersInNewTabKey) private var foldersInNewTab = false
    @AppStorage(AppIconService.key) private var appIcon = AppIconService.defaultID

    var body: some Commands {
        // Navegación (antes en «Ir»): se queda en Visualización para no perder los atajos.
        CommandGroup(after: .sidebar) {
            if !showsGo {
                Divider()
                Button("Back") { browser().goBack() }.keyboardShortcut("[")
                Button("Forward") { browser().goForward() }.keyboardShortcut("]")
                Button("Enclosing Folder") { browser().goUp() }.keyboardShortcut(.upArrow, modifiers: .command)
                Menu("Recent Locations") {
                    ForEach(browser().recentLocations, id: \.self) { url in
                        Button(url.path) { browser().navigate(to: url) }
                    }
                }
            }
        }
        if showsOptions {
        CommandMenu("Options") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .onChange(of: theme) { _, _ in AppearanceSettings.apply() }
                Divider()
                Toggle("Tabs in the top bar (one row)", isOn: $compactTop)
                Toggle("Search bar", isOn: $showsSearch)
                Toggle("Status Bar", isOn: $statusBar)
                Picker("Path", selection: $path) {
                    Text("Buttons and text (two rows)").tag("both")
                    Text("Buttons with copy (one row)").tag("buttons")
                    Text("Text only").tag("text")
                }
                Divider()
                Toggle("Calculate folder sizes automatically", isOn: $folderSizes)
                Toggle("Open folders in a new tab", isOn: $foldersInNewTab)
                Toggle("Ask before moving to the Trash", isOn: $confirmTrash)
                Divider()
                Picker("App Icon", selection: $appIcon) {
                    ForEach(AppIconDesign.all) { design in
                        Text("\(design.number). \(Text(design.name))").tag(design.id)
                    }
                }
                .onChange(of: appIcon) { _, _ in AppIconService.apply() }
                Divider()
                if !showsCommands {
                    Button("Command Palette…") { browser().showsCommandPalette = true }
                        .keyboardShortcut(KeyEquivalent(commandPaletteKey.first ?? "p"), modifiers: [.command, .shift])
                }
                SettingsLink { Text("All Settings…") }
            }
        }
    }
}

/// Apartado «Barra de menús» de Ajustes → General.
struct MenuBarSection: View {
    @AppStorage(MenuBarSettings.showsOptionsKey) private var showsOptions = true
    @AppStorage(MenuBarSettings.showsGoKey) private var showsGo = false
    @AppStorage(MenuBarSettings.showsCommandsKey) private var showsCommands = false
    @AppStorage(MenuBarSettings.hidesEmojiKey) private var hidesEmoji = true
    @AppStorage(MenuBarSettings.hidesWindowTabsKey) private var hidesWindowTabs = true

    var body: some View {
        Section("Menu Bar") {
            SettingsPreviewBox(title: "Preview: menus at the top of the screen") {
                HStack(spacing: 14) {
                    ForEach(menus, id: \.self) { name in
                        Text(LocalizedStringKey(name)).font(.system(size: 12, weight: name == "Explorer" ? .bold : .regular))
                    }
                    Spacer()
                }
                .animation(.default, value: menus)
            }
            Toggle(isOn: $showsOptions) {
                Label("“Options” menu", systemImage: "slider.horizontal.3")
                Text("Theme, tabs, search bar, status bar, path, icon and more, one click away.")
            }
            Toggle(isOn: $showsGo) {
                Label("“Go” menu", systemImage: "arrow.right.circle")
                Text("Off: Back, Forward and Enclosing Folder (⌘[ ⌘] ⌘↑) move to the View menu.")
            }
            Toggle(isOn: $showsCommands) {
                Label("“Commands” menu", systemImage: "command")
                Text("Off: the Command Palette moves to the Options menu.")
            }
            Toggle(isOn: $hidesEmoji) {
                Label("Remove Emoji & Symbols, Dictation and AutoFill from Edit", systemImage: "face.smiling")
                Text("macOS adds them; takes effect when Explorer restarts.")
            }
            Toggle(isOn: $hidesWindowTabs) {
                Label("Remove macOS window tabs", systemImage: "macwindow.on.rectangle")
                Text("Hides “Show Tab Bar” in View and stops macOS from grouping Explorer windows as tabs. Explorer’s own tabs are not affected. Takes effect when Explorer restarts.")
            }
        }
    }

    private var menus: [String] {
        var list = ["Explorer", "File", "Edit", "View"]
        if showsGo { list.append("Go") }
        if showsCommands { list.append("Commands") }
        if showsOptions { list.append("Options") }
        list += ["Window", "Help"]
        return list
    }
}
