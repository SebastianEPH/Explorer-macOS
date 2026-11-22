import SwiftUI

struct SettingsView: View {
    @AppStorage(TerminalService.applicationPathKey)
    private var terminalPath = "/System/Applications/Utilities/Terminal.app"
    @AppStorage("toolbar.showsSplit") private var toolbarShowsSplit = true
    @AppStorage("toolbar.showsTerminal") private var toolbarShowsTerminal = true
    @AppStorage("toolbar.showsOperations") private var toolbarShowsOperations = true
    @AppStorage("shortcut.commandPalette") private var commandPaletteKey = "p"
    @AppStorage("shortcut.terminal") private var terminalKey = "t"
    @AppStorage("gitStatusEnabled") private var gitStatusEnabled = false
    @AppStorage("settings.tab") private var settingsTab = "general" // Fork: pestaña abierta (la eligen también los menús)

    var body: some View {
        TabView(selection: $settingsTab) { // Fork: Ajustes en pestañas, y dentro de cada una un panel con sus apartados
            SettingsPagesView(tab: "general", pages: [
                SettingsPage("terminal", "Terminal application", "terminal") { terminalSection },
                SettingsPage("toolbar", "Toolbar", "menubar.rectangle") { toolbarSection },
                SettingsPage("shortcuts", "Keyboard Shortcuts", "command") { shortcutsSection },
                SettingsPage("git", "Git", "arrow.triangle.branch") { gitSection },
                SettingsPage("menubar", "Menu Bar", "menubar.rectangle") { MenuBarSection() },
                SettingsPage("language", "Language", "globe") { LanguageSection() }
            ])
            .settingsTab("General", systemImage: "gearshape").tag("general")
            SettingsPagesView(tab: "startup", pages: [
                SettingsPage("opens", "When Explorer Opens", "power") { StartupSection(part: "opens") },
                SettingsPage("tabs", "Tabs", "rectangle.stack") { StartupSection(part: "tabs") },
                SettingsPage("view", "Default View", "eye") { StartupSection(part: "view") }
            ])
            .settingsTab("Startup", systemImage: "power").tag("startup")
            SettingsPagesView(tab: "files", pages: [
                SettingsPage("icons", "Icons and Selection", "square.grid.2x2") { ItemHitAreaSection() },
                SettingsPage("opening", "Opening and Deleting", "trash") { FileBehaviorSection(part: "opening") },
                SettingsPage("panels", "Panels", "sidebar.right") { FileBehaviorSection(part: "panels") },
                SettingsPage("cloud", "Cloud Files", "icloud") { CloudStatusSection() } // Fork
            ])
            .settingsTab("Files", systemImage: "doc").tag("files")
            SettingsPagesView(tab: "appearance", pages: [
                SettingsPage("theme", "Theme", "circle.lefthalf.filled") { AppearanceSection(part: "theme") },
                SettingsPage("buttons", "Toolbar Buttons", "paintbrush") { AppearanceSection(part: "buttons") },
                SettingsPage("sidebar", "Sidebar", "sidebar.left") { AppearanceSection(part: "sidebar") },
                SettingsPage("icon", "App Icon", "app") { AppIconSection() },
                SettingsPage("window", "Window", "macwindow") { WindowLayoutSection() },
                SettingsPage("status", "Status Bar", "rectangle.bottomthird.inset.filled") { StatusBarSection() }
            ])
            .settingsTab("Appearance", systemImage: "paintpalette").tag("appearance")
            Form { FavoritesSection() }.settingsTab("Favorites", systemImage: "star").tag("favorites")
            Form { ContextMenuSection() }.settingsTab("Context Menu", systemImage: "contextualmenu.and.cursorarrow").tag("contextmenu")
            SettingsPagesView(tab: "system", pages: [
                SettingsPage("permissions", "Permissions", "lock.shield") { PermissionsSection() },
                SettingsPage("updates", "Updates", "arrow.down.circle") { UpdatesSection() }
            ])
            .settingsTab("System", systemImage: "lock.shield").tag("system")
        }
        .onChange(of: commandPaletteKey) { _, value in commandPaletteKey = sanitized(value, fallback: "p") }
        .onChange(of: terminalKey) { _, value in terminalKey = sanitized(value, fallback: "t") }
        .frame(minWidth: 780, minHeight: 720)
    }

    // Fork: apartados de la pestaña General (mismo contenido que antes, ahora separado).
    private var terminalSection: some View {
        Section {
            Picker(selection: $terminalPath) {
                ForEach(TerminalService.installedApplications, id: \.path) { application in
                    Label { Text(application.deletingPathExtension().lastPathComponent) } icon: { AppIconView(path: application.path) } // Fork
                        .tag(application.path)
                }
            } label: { Label("Terminal application", systemImage: "terminal") }
            Text("Used by the toolbar and Open in Terminal actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var toolbarSection: some View {
        Section("Toolbar") {
            ToolbarPreview(split: toolbarShowsSplit, terminal: toolbarShowsTerminal, operations: toolbarShowsOperations) // Fork
            Toggle(isOn: $toolbarShowsSplit) { Label("Split Pane", systemImage: "rectangle.split.2x1"); Text("Shows two folders side by side.") }
            Toggle(isOn: $toolbarShowsTerminal) { Label("Terminal", systemImage: "terminal"); Text("Opens the current folder in the terminal.") }
            Toggle(isOn: $toolbarShowsOperations) { Label("File Operations", systemImage: "arrow.left.arrow.right.circle"); Text("Progress of copies and moves in progress.") }
        }
    }

    private var shortcutsSection: some View {
        Section("Keyboard Shortcuts") {
            LabeledContent { HStack { KeyCapsView(keys: ["⌘", "⇧", commandPaletteKey]); TextField("", text: $commandPaletteKey).frame(width: 40) } } label: { Label("Command Palette", systemImage: "command"); Text("Search for any action by name.") } // Fork
            LabeledContent { HStack { KeyCapsView(keys: ["⌘", "⌥", terminalKey]); TextField("", text: $terminalKey).frame(width: 40) } } label: { Label("Open Terminal", systemImage: "terminal"); Text("Opens the current folder in the terminal.") }
            Text("Enter a single letter. Changes apply immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var gitSection: some View {
        Section("Folders") {
            Toggle(isOn: $gitStatusEnabled) { Label("Show Git status badges", systemImage: "arrow.triangle.branch") }
            GitBadgePreview(enabled: gitStatusEnabled) // Fork
            Text("Disabled by default to avoid running Git in every folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sanitized(_ value: String, fallback: String) -> String {
        String(value.lowercased().filter(\.isLetter).prefix(1)).isEmpty
            ? fallback
            : String(value.lowercased().filter(\.isLetter).prefix(1))
    }
}
