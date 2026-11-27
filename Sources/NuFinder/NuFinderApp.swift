import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MenuBarSettings.applySystemItems() // Fork: sin Emoji y dictado en Edición (antes de crear el menú)
        MenuBarSettings.applyWindowTabbing() // Fork: sin pestañas de ventana de macOS
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        RemovedFeatures.unregisterLoginItem() // Fork: sin «Finder abre Explorer», ya no arranca al iniciar sesión
        RemovedFeatures.cleanDefaults() // Fork: sin espacios de trabajo
        AppearanceSettings.apply() // Fork
        TextPredictionSettings.apply() // Fork: sin texto gris de predicción al escribir nombres
        AppIconService.start() // Fork: icono elegido en Ajustes (claro/oscuro)
        FTPServerController.shared.start() // Fork: servidor FTP si está encendido
        DispatchQueue.main.async { MenuBarSettings.startCleaning() } // Fork: sin «Autorrelleno» en Edición
        // A SwiftPM executable reaches didFinishLaunching before SwiftUI has
        // necessarily installed its WindowGroup. Activate on the next run-loop
        // turn so `swift run Freeloader` reliably comes in front of Terminal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.isVisible,
              let url = window.representedURL,
              url.isFileURL else { return }
        WindowService.recordClosedWindow(at: url)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { return DockReopen.reopen(sender) } // Fork: ventana independiente
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

@main
struct FreeloaderApp: App {
    private let registeredDefaults: Void = DefaultSettings.register() // Fork: mis ajustes por defecto (antes que todo)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var mainBrowser = BrowserModel()
    @ObservedObject private var keyFocus = KeyWindowFocus.shared // Fork: menús → ventana activa
    @StateObject private var mainOperations = FileOperationManager()
    @StateObject private var paneFocus = PaneFocusCoordinator()
    @AppStorage("shortcut.commandPalette") private var commandPaletteKey = "p"
    @AppStorage("shortcut.terminal") private var terminalKey = "t"
    @AppStorage("previewPane.visible") private var previewVisible = true // Fork
    @AppStorage(ListColumnSettings.showsCreatedKey) private var showsCreatedColumn = false // Fork
    @AppStorage(MenuBarSettings.showsGoKey) private var showsGoMenu = false // Fork
    @AppStorage(MenuExtras.view.key) private var viewMenuExtras = true // Fork
    @AppStorage(MenuBarSettings.showsCommandsKey) private var showsCommandsMenu = false // Fork

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mainBrowser)
                .environmentObject(mainOperations)
                .environmentObject(paneFocus)
                .frame(minWidth: 820, minHeight: 480)
                .background(KeyWindowReader(focus: paneFocus, browser: mainBrowser, operations: mainOperations))
                .onOpenURL { mainBrowser.handleDeepLink($0) }
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { browser.undoLastAction() }
                    .keyboardShortcut("z")
                    .disabled(!browser.canUndo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    if !sendTextCommand(#selector(NSText.cut(_:))) {
                        browser.cutSelection()
                    }
                }
                    .keyboardShortcut("x")
                Button("Copy") {
                    if !sendTextCommand(#selector(NSText.copy(_:))) {
                        browser.copySelection()
                    }
                }
                    .keyboardShortcut("c")
                Button("Paste") {
                    if !sendTextCommand(#selector(NSText.paste(_:))) {
                        Task { await browser.paste(into: browser.currentURL, operations: operations) }
                    }
                }
                .keyboardShortcut("v")
                Divider()
                Button("Select All") {
                    if activeBrowser.isEditingAddress || activeBrowser.renameTarget != nil {
                        if sendTextCommand(#selector(NSText.selectAll(_:))) {
                            return
                        }
                    }
                    activeBrowser.selectAll()
                }
                    .keyboardShortcut("a")
                Button("Invert Selection") { browser.invertSelection() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Find Files…") { activeBrowser.requestSearchFocus() }
                    .keyboardShortcut("f")
                Button("Clear Search") {
                    activeBrowser.searchText = ""
                    activeBrowser.updateSearch()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(activeBrowser.searchText.isEmpty)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Window") { WindowService.open(at: browser.currentURL) }
                    .keyboardShortcut("n")
                Button("New Tab") { browser.newTab() }
                    .keyboardShortcut("t")
                Button("Close Tab") {
                    if browser.tabs.count > 1 {
                        browser.closeTab(browser.activeTabID)
                    } else {
                        NSApp.keyWindow?.close()
                    }
                }
                .keyboardShortcut("w")
                Button("Reopen Closed Tab") { browser.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(!browser.canReopenClosedTab)
                Button("Reopen Closed Window") { WindowService.reopenLastClosedWindow() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!WindowService.canReopenClosedWindow)
                Button("Go to Folder…") { browser.requestAddressFocus() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Connect to Server…") { browser.requestConnectToServer() }
                    .keyboardShortcut("k")
                Divider()
                Button("New File") { browser.requestNewFile() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Folder") { browser.showsNewFolderPrompt = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open in Terminal") { TerminalService.open(at: browser.currentURL) }
                    .keyboardShortcut(shortcutKey(terminalKey, fallback: "t"), modifiers: [.command, .option])
                Button("Duplicate") {
                    Task { await browser.duplicateSelection(using: operations) }
                }
                .keyboardShortcut("d")
                .disabled(browser.selection.isEmpty)
                Button("Get Info") { browser.showInfoForSelection() }
                    .keyboardShortcut("i")
                    .disabled(browser.selection.isEmpty)
                Button("Quick Look") { QuickLookService.shared.show(Array(browser.selection)) }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(browser.selection.isEmpty)
                Button("Batch Rename") { browser.showsBatchRenamePrompt = true }
                    .disabled(browser.selection.isEmpty)
                Button("Copy Path") { FileActionService.copyPaths(Array(browser.selection)) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                    .disabled(browser.selection.isEmpty)
                Divider()
                Button("Move to Trash") { browser.moveSelectionToTrash() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(browser.selection.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Toggle("Folder Tree in Sidebar", isOn: bind(\.showsTree))
                Toggle("Preview Pane", isOn: $previewVisible)
                    .keyboardShortcut("p", modifiers: [.command, .option])
                if !viewMenuExtras { // Fork: con los añadidos de Visualización ya están «Como lista/compacta/iconos» (⌘1–3)
                Picker("View Mode", selection: bind(\.viewMode)) {
                    ForEach(FileViewMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                    }
                }
                }
                Menu("Columns") {
                    Toggle("Kind", isOn: bind(\.showsKindColumn))
                    Toggle("Size", isOn: bind(\.showsSizeColumn))
                    Toggle("Date Modified", isOn: bind(\.showsModifiedColumn))
                    Toggle("Date Created", isOn: $showsCreatedColumn)
                }
                Button(browser.showsHiddenFiles ? String(localized: "Hide Hidden Files") : String(localized: "Show Hidden Files")) { // Fork: traducido
                    browser.toggleHiddenFiles()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                Button("Reload") { browser.reload() }
                    .keyboardShortcut("r")
            }
            if showsGoMenu { // Fork: oculto por defecto (Ajustes → General → Barra de menús)
            CommandMenu("Go") {
                Menu("Recent Locations") {
                    ForEach(browser.recentLocations, id: \.self) { url in
                        Button(url.path) { browser.navigate(to: url) }
                    }
                }
                Button("Back") { browser.goBack() }
                    .keyboardShortcut("[")
                    .disabled(!browser.canGoBack)
                Button("Forward") { browser.goForward() }
                    .keyboardShortcut("]")
                    .disabled(!browser.canGoForward)
                Button("Enclosing Folder") { browser.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
            }
            }
            CommandGroup(after: .help) {
                HelpVersionItems()
            }
            if showsCommandsMenu { // Fork: oculto por defecto
            CommandMenu("Commands") {
                Button("Command Palette…") { browser.showsCommandPalette = true }
                    .keyboardShortcut(shortcutKey(commandPaletteKey, fallback: "p"), modifiers: [.command, .shift])
            }
            }
            ExplorerMenus(browser: { browser }, commandPaletteKey: commandPaletteKey) // Fork: menú Opciones y navegación
            FTPMenu(currentFolder: { keyFocus.windowBrowser?.currentURL }) // Fork: cliente y servidor FTP
        }
        Settings {
            SettingsView()
        }
    }

    private func shortcutKey(_ value: String, fallback: Character) -> KeyEquivalent {
        KeyEquivalent(value.first ?? fallback)
    }

    private var activeBrowser: BrowserModel {
        browser
    }

    /// Fork: el BrowserModel de la ventana activa (cada ventana tiene el suyo).
    private var browser: BrowserModel {
        keyFocus.browser ?? paneFocus.activeBrowser ?? mainBrowser
    }

    /// Fork: las operaciones de archivo (y su ventana de progreso) de la ventana activa.
    private var operations: FileOperationManager {
        keyFocus.operations ?? mainOperations
    }

    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<BrowserModel, Value>) -> Binding<Value> {
        let model = browser
        return Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0 })
    }

    @MainActor
    private func sendTextCommand(_ selector: Selector) -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
              editor.isFieldEditor,
              editor.delegate is NSTextField else {
            return false
        }
        return NSApp.sendAction(selector, to: nil, from: nil)
    }
}
