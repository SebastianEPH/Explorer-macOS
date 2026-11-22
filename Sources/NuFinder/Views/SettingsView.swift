import SwiftUI

struct SettingsView: View {
    @AppStorage(TerminalService.applicationPathKey)
    private var terminalPath = "/System/Applications/Utilities/Terminal.app"
    @AppStorage("toolbar.showsSplit") private var toolbarShowsSplit = true
    @AppStorage("toolbar.showsTerminal") private var toolbarShowsTerminal = true
    @AppStorage("toolbar.showsOperations") private var toolbarShowsOperations = true
    @AppStorage("toolbar.showsWorkspaces") private var toolbarShowsWorkspaces = true // Fork
    @AppStorage("shortcut.commandPalette") private var commandPaletteKey = "p"
    @AppStorage("shortcut.terminal") private var terminalKey = "t"
    @AppStorage("gitStatusEnabled") private var gitStatusEnabled = false

    var body: some View {
        TabView { // Fork: Ajustes en pestañas
        Form {
            Picker(selection: $terminalPath) {
                ForEach(TerminalService.installedApplications, id: \.path) { application in
                    Label { Text(application.deletingPathExtension().lastPathComponent) } icon: { AppIconView(path: application.path) } // Fork
                        .tag(application.path)
                }
            } label: { Label("Terminal application", systemImage: "terminal") }
            Text("Used by the toolbar and Open in Terminal actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Section("Toolbar") {
                ToolbarPreview(workspaces: toolbarShowsWorkspaces, split: toolbarShowsSplit, terminal: toolbarShowsTerminal, operations: toolbarShowsOperations) // Fork
                Toggle(isOn: $toolbarShowsWorkspaces) { Label("Workspaces", systemImage: "square.stack.3d.up"); Text("Save and restore the open folders and the split pane.") }
                Toggle(isOn: $toolbarShowsSplit) { Label("Split Pane", systemImage: "rectangle.split.2x1"); Text("Shows two folders side by side.") }
                Toggle(isOn: $toolbarShowsTerminal) { Label("Terminal", systemImage: "terminal"); Text("Opens the current folder in the terminal.") }
                Toggle(isOn: $toolbarShowsOperations) { Label("File Operations", systemImage: "arrow.left.arrow.right.circle"); Text("Progress of copies and moves in progress.") }
            }
            Section("Keyboard Shortcuts") {
                LabeledContent { HStack { KeyCapsView(keys: ["⌘", "⇧", commandPaletteKey]); TextField("", text: $commandPaletteKey).frame(width: 40) } } label: { Label("Command Palette", systemImage: "command"); Text("Search for any action by name.") } // Fork
                LabeledContent { HStack { KeyCapsView(keys: ["⌘", "⌥", terminalKey]); TextField("", text: $terminalKey).frame(width: 40) } } label: { Label("Open Terminal", systemImage: "terminal"); Text("Opens the current folder in the terminal.") }
                Text("Enter a single letter. Changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Folders") {
                Toggle(isOn: $gitStatusEnabled) { Label("Show Git status badges", systemImage: "arrow.triangle.branch") }
                GitBadgePreview(enabled: gitStatusEnabled) // Fork
                Text("Disabled by default to avoid running Git in every folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LanguageSection()
        }
        .settingsTab("General", systemImage: "gearshape")
        Form { StartupSection() }.settingsTab("Startup", systemImage: "power")
        Form { ItemHitAreaSection(); FileBehaviorSection() }.settingsTab("Files", systemImage: "doc")
        Form { AppearanceSection(); AppIconSection(); WindowLayoutSection(); StatusBarSection() }.settingsTab("Appearance", systemImage: "paintpalette")
        Form { FavoritesSection() }.settingsTab("Favorites", systemImage: "star")
        Form { ContextMenuSection() }.settingsTab("Context Menu", systemImage: "contextualmenu.and.cursorarrow")
        Form {
            PermissionsSection()
            FinderRedirectSection()
            UpdatesSection()
        }
        .settingsTab("System", systemImage: "lock.shield")
        }
        .onChange(of: commandPaletteKey) { _, value in commandPaletteKey = sanitized(value, fallback: "p") }
        .onChange(of: terminalKey) { _, value in terminalKey = sanitized(value, fallback: "t") }
        .frame(minWidth: 780, minHeight: 720)
    }

    private func sanitized(_ value: String, fallback: String) -> String {
        String(value.lowercased().filter(\.isLetter).prefix(1)).isEmpty
            ? fallback
            : String(value.lowercased().filter(\.isLetter).prefix(1))
    }
}
