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

/// Añadidos de Explorer en cada menú de arriba. Cada grupo se puede quitar en Ajustes → General → Barra de menús.
enum MenuExtras: String, CaseIterable, Identifiable {
    case app, file, edit, view, window, help, options
    var id: String { rawValue }
    var key: String { "menu.extras.\(rawValue)" }

    var title: LocalizedStringKey {
        switch self {
        case .app: "Explorer menu: Permissions"
        case .file: "File menu: compress, extract, AirDrop, empty Trash"
        case .edit: "Edit menu: copy name, rename, tags, paste as alias"
        case .view: "View menu: view modes, sort, icon size, bars, path, theme"
        case .window: "Window menu: next/previous tab, pin, duplicate, close other tabs, split pane"
        case .help: "Help menu: keyboard shortcuts"
        case .options: "“Options” menu: behaviour (folder sizes, Trash, new tabs, hidden files)"
        }
    }

    var menuName: String {
        switch self {
        case .app: "Explorer"
        case .file: "File"
        case .edit: "Edit"
        case .view: "View"
        case .window: "Window"
        case .help: "Help"
        case .options: "Options"
        }
    }
}

/// Menús de Explorer, sin depender del código del autor.
struct ExplorerMenus: Commands {
    /// Ventana activa.
    let browser: () -> BrowserModel
    let commandPaletteKey: String

    @AppStorage(MenuExtras.app.key) private var appExtras = true
    @AppStorage(MenuExtras.file.key) private var fileExtras = true
    @AppStorage(MenuExtras.edit.key) private var editExtras = true
    @AppStorage(MenuExtras.view.key) private var viewExtras = true
    @AppStorage(MenuExtras.window.key) private var windowExtras = true
    @AppStorage(MenuExtras.help.key) private var helpExtras = true
    @AppStorage(MenuExtras.options.key) private var showsOptions = true
    @AppStorage(MenuBarSettings.showsGoKey) private var showsGo = false
    @AppStorage(MenuBarSettings.showsCommandsKey) private var showsCommands = false
    @AppStorage(AppearanceSettings.themeKey) private var theme = ""
    @AppStorage(LayoutSettings.compactTopKey) private var compactTop = false
    @AppStorage(LayoutSettings.showsSearchKey) private var showsSearch = true
    @AppStorage(LayoutSettings.pathKey) private var path = "both"
    @AppStorage(LayoutSettings.tabBarKey) private var tabBar = "always"
    @AppStorage(StatusBarSettings.visibleKey) private var statusBar = true
    @AppStorage(FolderSizeQueue.autoKey) private var folderSizes = true
    @AppStorage(BehaviorSettings.confirmTrashKey) private var confirmTrash = false
    @AppStorage(BehaviorSettings.hiddenByDefaultKey) private var hiddenByDefault = false
    @AppStorage(BehaviorSettings.iconSizeKey) private var iconSize = BehaviorSettings.defaultIconSize
    @ObservedObject private var splitPanes = WindowSplitPanes.shared // Fork: panel de la ventana activa
    @ObservedObject private var keyFocus = KeyWindowFocus.shared

    private var hasSelection: Bool { !browser().selection.isEmpty }

    var body: some Commands {
        // MARK: Explorer (menú de la app)
        CommandGroup(after: .appSettings) {
            if appExtras {
                Button("Permissions…") { SettingsOpener.open(tab: "system", page: "permissions") }
            }
        }
        // MARK: Archivo
        CommandGroup(after: .saveItem) {
            if fileExtras {
                Divider()
                Button("Compress to ZIP") { browser().createArchiveFromSelection() }
                    .disabled(!hasSelection)
                Button("Extract Here") { browser().extractSelectedArchives() }
                    .disabled(!browser().selection.contains(where: ArchiveService.isArchive))
                Button("Send with AirDrop") {
                    let urls = Array(browser().selection)
                    if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) { service.perform(withItems: urls) }
                }
                .disabled(!hasSelection)
                Button("Calculate Size") { browser().calculateSelectedSizes() }
                    .disabled(!hasSelection)
                Button("Reveal in Finder") { browser().revealSelectionInFinder() }
                    .disabled(!hasSelection)
                Divider()
                Button("Empty Trash…") {
                    if let error = SidebarExtras.emptyTrash() { browser().errorMessage = error }
                }
            }
        }
        // MARK: Edición
        CommandGroup(after: .pasteboard) {
            if editExtras {
                Divider()
                Button("Copy Filename") { FileActionService.copyNames(Array(browser().selection)) }
                    .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                    .disabled(!hasSelection)
                Menu("Paste As") {
                    Button("Alias") { browser().pasteAsLinks(into: browser().currentURL, symbolic: false) }
                    Button("Symbolic Link") { browser().pasteAsLinks(into: browser().currentURL, symbolic: true) }
                }
                .disabled(!browser().canPaste)
                Divider()
                Button("Rename") {
                    if let url = browser().selection.first { browser().selection = [url]; browser().renameTarget = url }
                }
                .disabled(browser().selection.count != 1)
                Button("Tags…") { browser().tagText = ""; browser().showsTagPrompt = true }
                    .disabled(!hasSelection)
            }
        }
        // MARK: Visualización (incluye la navegación de «Ir» si ese menú está oculto)
        CommandGroup(after: .sidebar) {
            if viewExtras {
                Divider()
                Button("As List") { browser().viewMode = .list }.keyboardShortcut("1")
                Button("As Compact") { browser().viewMode = .compact }.keyboardShortcut("2")
                Button("As Icons") { browser().viewMode = .icons }.keyboardShortcut("3")
                Menu("Sort By") {
                    ForEach(SortField.allCases) { field in
                        Button(LocalizedStringKey(field.rawValue)) {
                            let model = browser()
                            let ascending = model.sortCriteria.first?.field == field ? !(model.sortCriteria.first?.ascending ?? true) : true
                            model.sortCriteria = [SortCriterion(field: field, ascending: ascending)]
                            model.sortedAgain()
                        }
                    }
                }
                Button("Bigger Icons") { iconSize = min(128, iconSize + 8) }.keyboardShortcut("+")
                Button("Smaller Icons") { iconSize = max(32, iconSize - 8) }.keyboardShortcut("-")
                Divider()
                Toggle("Split Pane", isOn: splitPanes.keyWindowBinding).keyboardShortcut("s", modifiers: [.command, .option])
                Toggle("Tabs in the top bar (one row)", isOn: $compactTop)
                Picker("Tab bar", selection: $tabBar) {
                    Text("Always").tag("always")
                    Text("Only with 2 or more tabs").tag("multiple")
                    Text("Never").tag("never")
                }
                Toggle("Search bar", isOn: $showsSearch)
                Toggle("Status Bar", isOn: $statusBar)
                Picker("Path", selection: $path) {
                    Text("Buttons and text (two rows)").tag("both")
                    Text("Buttons with copy (one row)").tag("buttons")
                    Text("Text only").tag("text")
                }
                Picker("Theme", selection: $theme) {
                    Text("System").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .onChange(of: theme) { _, _ in AppearanceSettings.apply() }
            }
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
        // MARK: Ventana
        CommandGroup(before: .windowList) {
            if windowExtras {
                Button("Next Tab") { selectTab(offset: 1) }.keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { selectTab(offset: -1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
                Button("Duplicate Tab") { browser().duplicateTab(browser().activeTabID) }
                Button("Pin Tab") { browser().togglePinnedTab(browser().activeTabID) }
                Button("Close Other Tabs") {
                    let model = browser()
                    for tab in model.tabs where tab.id != model.activeTabID && !tab.isPinned { model.closeTab(tab.id) }
                }
                .disabled(browser().tabs.count < 2)
                Divider()
            }
        }
        // MARK: Ayuda
        // Sustituye «Ayuda de Explorer» (no abre nada útil) por los atajos de teclado.
        CommandGroup(replacing: .help) {
            if helpExtras {
                Button("Keyboard Shortcuts") { SettingsOpener.open(tab: "general", page: "shortcuts") }
                Divider()
            }
            HelpVersionItems() // versión, buscar actualizaciones y Acerca de (van en este mismo grupo)
        }
        // MARK: Opciones (comportamiento)
        if showsOptions {
            CommandMenu("Options") {
                Toggle("Calculate folder sizes automatically", isOn: $folderSizes)
                Toggle("Ask before moving to the Trash", isOn: $confirmTrash)
                Toggle("Show hidden files from the start", isOn: $hiddenByDefault)
                Divider()
                if !showsCommands {
                    Button("Command Palette…") { browser().showsCommandPalette = true }
                        .keyboardShortcut(KeyEquivalent(commandPaletteKey.first ?? "p"), modifiers: [.command, .shift])
                }
                SettingsLink { Text("All Settings…") }
            }
        }
    }

    private func selectTab(offset: Int) {
        let model = browser()
        guard let index = model.tabs.firstIndex(where: { $0.id == model.activeTabID }), !model.tabs.isEmpty else { return }
        let next = (index + offset + model.tabs.count) % model.tabs.count
        model.selectTab(model.tabs[next].id)
    }
}

/// Abre Ajustes en una pestaña y apartado concretos.
enum SettingsOpener {
    @MainActor
    static func open(tab: String, page: String) {
        UserDefaults.standard.set(page, forKey: "settings.page.\(tab)")
        UserDefaults.standard.set(tab, forKey: "settings.tab")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

/// Apartado «Barra de menús» de Ajustes → General.
struct MenuBarSection: View {
    @AppStorage(MenuExtras.options.key) private var showsOptions = true
    @AppStorage(MenuBarSettings.showsGoKey) private var showsGo = false
    @AppStorage(MenuBarSettings.showsCommandsKey) private var showsCommands = false
    @AppStorage(MenuBarSettings.hidesEmojiKey) private var hidesEmoji = true
    @AppStorage(MenuBarSettings.hidesWindowTabsKey) private var hidesWindowTabs = true
    @AppStorage(FTPSettings.showsMenuKey) private var showsFTP = true

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
            Toggle(isOn: $showsGo) {
                Label("“Go” menu", systemImage: "arrow.right.circle")
                Text("Off: Back, Forward and Enclosing Folder (⌘[ ⌘] ⌘↑) move to the View menu.")
            }
            Toggle(isOn: $showsCommands) {
                Label("“Commands” menu", systemImage: "command")
                Text("Off: the Command Palette moves to the Options menu.")
            }
            Toggle(isOn: $showsFTP) {
                Label("“FTP” menu", systemImage: "network")
                Text("Turns the FTP client and server on and off, connects to servers and shares the current folder.")
            }
            ForEach(MenuExtras.allCases) { extra in MenuExtraToggle(extra: extra) }
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
        if showsFTP { list.append("FTP") }
        list += ["Window", "Help"]
        return list
    }
}

private struct MenuExtraToggle: View {
    let extra: MenuExtras
    @AppStorage private var on: Bool
    init(extra: MenuExtras) {
        self.extra = extra
        _on = AppStorage(wrappedValue: true, extra.key)
    }
    var body: some View {
        Toggle(isOn: $on) { Label(extra.title, systemImage: "checklist") }
    }
}
