import AppKit
import SwiftUI

/// Fork: ajustes de comportamiento y apariencia (pestañas Inicio, Archivos y Apariencia).
/// Sin tocar nada, todo se comporta como el original.
enum BehaviorSettings {
    static let restoresTabsKey = "startup.restoresTabs"
    static let startFolderKey = "startup.folder"          // "" = carpeta personal
    static let newTabFolderKey = "tabs.newTabFolder"      // "" = carpeta actual
    static let defaultViewKey = "view.default"
    static let hiddenByDefaultKey = "view.hiddenByDefault"
    static let foldersInNewTabKey = "open.foldersInNewTab"
    static let confirmTrashKey = "trash.confirm"
    static let iconSizeKey = "view.iconSize"
    static let defaultIconSize = 56.0
    static let showsLocationsKey = "sidebar.showsLocations"

    static func restoresTabs(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: restoresTabsKey) as? Bool ?? true
    }

    /// Carpeta con la que se abre la app cuando no se restauran pestañas.
    static func startURL(_ defaults: UserDefaults = .standard) -> URL? {
        folderURL(defaults.string(forKey: startFolderKey) ?? "")
    }

    /// nil = la nueva pestaña abre la carpeta actual (original).
    static var newTabURL: URL? {
        folderURL(UserDefaults.standard.string(forKey: newTabFolderKey) ?? "")
    }

    static var defaultViewMode: FileViewMode {
        FileViewMode(rawValue: UserDefaults.standard.string(forKey: defaultViewKey) ?? "") ?? .list
    }

    static var showsHiddenByDefault: Bool { UserDefaults.standard.bool(forKey: hiddenByDefaultKey) }
    static var foldersOpenInNewTab: Bool { UserDefaults.standard.bool(forKey: foldersInNewTabKey) }

    /// true = seguir. Pregunta solo si el usuario activó la confirmación.
    @MainActor
    static func confirmTrash(count: Int) -> Bool {
        guard UserDefaults.standard.bool(forKey: confirmTrashKey) else { return true }
        let alert = NSAlert()
        alert.messageText = count == 1
            ? String(localized: "Move this item to the Trash?")
            : String(localized: "Move \(count) items to the Trash?")
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// "" o "home" → personal; "desktop", "documents", "downloads"; otra cosa = ruta.
    static func folderURL(_ value: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch value {
        case "": return nil
        case "home": return home
        case "desktop": return home.appendingPathComponent("Desktop", isDirectory: true)
        case "documents": return home.appendingPathComponent("Documents", isDirectory: true)
        case "downloads": return home.appendingPathComponent("Downloads", isDirectory: true)
        default:
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: value, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return URL(filePath: value, directoryHint: .isDirectory)
        }
    }
}

enum AppearanceSettings {
    static let themeKey = "appearance.theme"          // "", "light", "dark"
    static let toolbarColorKey = "appearance.toolbarColor"

    @MainActor
    static func apply() {
        switch UserDefaults.standard.string(forKey: themeKey) ?? "" {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    nonisolated(unsafe) static let toolbarColors: [(id: String, name: LocalizedStringKey, color: Color)] = [
        ("", "Purple", Color(red: 0.50, green: 0.22, blue: 0.56)),
        ("blue", "Blue", Color(red: 0.16, green: 0.40, blue: 0.80)),
        ("green", "Green", Color(red: 0.16, green: 0.55, blue: 0.32)),
        ("orange", "Orange", Color(red: 0.85, green: 0.45, blue: 0.12)),
        ("red", "Red", Color(red: 0.78, green: 0.20, blue: 0.22)),
        ("pink", "Pink", Color(red: 0.85, green: 0.30, blue: 0.58)),
        ("graphite", "Graphite", Color(red: 0.38, green: 0.38, blue: 0.42))
    ]

    /// Colores del degradado de los botones de la barra (el original es morado).
    static func toolbarGradient(_ id: String, active: Bool) -> [Color] {
        let base = toolbarColors.first { $0.id == id }?.color ?? toolbarColors[0].color
        return active ? [base.mix(with: .white, by: 0.12), base.mix(with: .black, by: 0.40)]
                      : [base, base.mix(with: .black, by: 0.50)]
    }
}

// MARK: - Secciones de Ajustes

/// Elegir una carpeta: personal, Escritorio, Documentos, Descargas u otra.
struct FolderChoicePicker: View {
    let title: LocalizedStringKey
    let symbol: String
    let emptyLabel: LocalizedStringKey
    @Binding var value: String

    var body: some View {
        Picker(selection: $value) {
            Text(emptyLabel).tag("")
            Label("Home", systemImage: "house").tag("home")
            Label("Desktop", systemImage: "menubar.dock.rectangle").tag("desktop")
            Label("Documents", systemImage: "doc").tag("documents")
            Label("Downloads", systemImage: "arrow.down.circle").tag("downloads")
            if !["", "home", "desktop", "documents", "downloads"].contains(value) {
                Label(URL(filePath: value).lastPathComponent, systemImage: "folder").tag(value)
            }
        } label: { Label(title, systemImage: symbol) }
        Button("Choose Another Folder…", systemImage: "folder.badge.plus") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let url = panel.url { value = url.path }
        }
        .buttonStyle(.link)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct StartupSection: View {
    @AppStorage(BehaviorSettings.restoresTabsKey) private var restoresTabs = true
    @AppStorage(BehaviorSettings.startFolderKey) private var startFolder = ""
    @AppStorage(BehaviorSettings.newTabFolderKey) private var newTabFolder = ""
    @AppStorage(BehaviorSettings.defaultViewKey) private var defaultView = FileViewMode.list.rawValue
    @AppStorage(BehaviorSettings.hiddenByDefaultKey) private var hiddenByDefault = false

    var body: some View {
        Section("When Explorer Opens") {
            Toggle(isOn: $restoresTabs) {
                Label("Reopen the tabs from last time", systemImage: "arrow.counterclockwise")
                Text("Off: always starts with one tab in the folder below.")
            }
            FolderChoicePicker(title: "Start folder", symbol: "house", emptyLabel: "Home", value: $startFolder)
                .disabled(restoresTabs)
        }
        Section("Tabs") {
            FolderChoicePicker(title: "New tab opens", symbol: "plus.square.on.square",
                               emptyLabel: "The current folder", value: $newTabFolder)
        }
        Section("Default View") {
            Picker(selection: $defaultView) {
                Label("List", systemImage: "list.bullet").tag(FileViewMode.list.rawValue)
                Label("Compact", systemImage: "square.grid.3x1.below.line.grid.1x2").tag(FileViewMode.compact.rawValue)
                Label("Icons", systemImage: "square.grid.2x2").tag(FileViewMode.icons.rawValue)
            } label: { Label("View new windows as", systemImage: "eye") }
                .pickerStyle(.segmented)
            ViewModePreview(mode: FileViewMode(rawValue: defaultView) ?? .list)
            Toggle(isOn: $hiddenByDefault) {
                Label("Show hidden files from the start", systemImage: "eye.slash")
                Text("Files whose name starts with a dot, like .gitignore.")
            }
            Text("Folders with their own saved view keep it.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FileBehaviorSection: View {
    @AppStorage(BehaviorSettings.foldersInNewTabKey) private var foldersInNewTab = false
    @AppStorage(BehaviorSettings.confirmTrashKey) private var confirmTrash = false
    @AppStorage(ListColumnSettings.showsCreatedKey) private var showsCreated = false
    @AppStorage("previewPane.visible") private var previewVisible = true
    @AppStorage("operations.autoClose") private var autoClose = true

    var body: some View {
        Section("Opening and Deleting") {
            Toggle(isOn: $foldersInNewTab) {
                Label("Open folders in a new tab", systemImage: "plus.square.on.square")
                Text("Double-clicking a folder opens it in a new tab instead of the same one.")
            }
            Toggle(isOn: $confirmTrash) {
                Label("Ask before moving to the Trash", systemImage: "trash")
                Text("Shows a confirmation before deleting with ⌘⌫ or the menu.")
            }
        }
        Section("Panels") {
            Toggle(isOn: $showsCreated) {
                Label("“Date Created” column in List view", systemImage: "calendar.badge.plus")
            }
            Toggle(isOn: $previewVisible) {
                Label("Image preview pane", systemImage: "sidebar.right")
                Text("Panel on the right that shows the selected image.")
            }
            Toggle(isOn: $autoClose) {
                Label("Close the operations panel when done", systemImage: "arrow.left.arrow.right.circle")
            }
        }
    }
}

struct AppearanceSection: View {
    @AppStorage(AppearanceSettings.themeKey) private var theme = ""
    @AppStorage(AppearanceSettings.toolbarColorKey) private var toolbarColor = ""
    @AppStorage(BehaviorSettings.showsLocationsKey) private var showsLocations = true

    var body: some View {
        Section("Theme") {
            Picker(selection: $theme) {
                Label("System", systemImage: "circle.lefthalf.filled").tag("")
                Label("Light", systemImage: "sun.max").tag("light")
                Label("Dark", systemImage: "moon").tag("dark")
            } label: { Label("Appearance", systemImage: "paintpalette") }
                .pickerStyle(.segmented)
                .onChange(of: theme) { _, _ in AppearanceSettings.apply() }
            HStack(spacing: 16) {
                themeSwatch("", "System")
                themeSwatch("light", "Light")
                themeSwatch("dark", "Dark")
            }
            .frame(maxWidth: .infinity)
        }
        Section("Toolbar Buttons") {
            LabeledContent {
                HStack(spacing: 8) {
                    ForEach(AppearanceSettings.toolbarColors, id: \.id) { choice in
                        Button { toolbarColor = choice.id } label: {
                            Circle().fill(choice.color).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: toolbarColor == choice.id ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .help(Text(choice.name))
                    }
                }
            } label: { Label("Color", systemImage: "paintbrush") }
            SettingsPreviewBox(title: "Preview: top right of the window") {
                HStack(spacing: 8) {
                    ForEach(["square.stack.3d.up", "rectangle.split.2x1", "terminal", "arrow.left.arrow.right.circle"], id: \.self) {
                        FreeloaderToolbarIcon(systemName: $0)
                    }
                }
            }
        }
        Section("Sidebar") {
            Toggle(isOn: $showsLocations) {
                Label("Show “Locations” (disks and servers)", systemImage: "externaldrive")
            }
            SidebarExtrasToggles()
        }
    }

    private func themeSwatch(_ id: String, _ name: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Group {
                if id.isEmpty {
                    HStack(spacing: 0) { swatchWindow(dark: false); swatchWindow(dark: true) }
                } else {
                    swatchWindow(dark: id == "dark")
                }
            }
            .frame(width: 90, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme == id ? Color.accentColor : .gray.opacity(0.4), lineWidth: theme == id ? 3 : 1))
            Text(name).font(.caption)
        }
        .onTapGesture { theme = id; AppearanceSettings.apply() }
    }

    private func swatchWindow(dark: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            (dark ? Color(white: 0.15) : Color(white: 0.96))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) { ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 5) } }
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2).fill(dark ? Color(white: 0.35) : Color(white: 0.8)).frame(width: 34, height: 4)
                }
            }
            .padding(6)
        }
    }
}

/// Dibujo de las tres vistas.
struct ViewModePreview: View {
    let mode: FileViewMode
    private let names = ["Fotos", "Informe.pdf", "Música", "notas.txt"]

    var body: some View {
        SettingsPreviewBox(title: "Preview: how a folder looks") {
            Group {
                switch mode {
                case .list:
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(names, id: \.self) { name in
                            HStack { icon(name, 14); Text(verbatim: name).font(.caption); Spacer(); Text(verbatim: "12 KB").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                case .compact:
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(names, id: \.self) { name in HStack { icon(name, 18); Text(verbatim: name).font(.caption) } }
                    }
                case .icons:
                    HStack(spacing: 14) {
                        ForEach(names, id: \.self) { name in VStack(spacing: 3) { icon(name, 30); Text(verbatim: name).font(.caption2) } }
                    }
                }
            }
            .frame(height: 76)
            .animation(.default, value: mode)
        }
    }

    private func icon(_ name: String, _ size: CGFloat) -> some View {
        Image(systemName: name.contains(".") ? "doc.fill" : "folder.fill")
            .font(.system(size: size))
            .foregroundStyle(name.contains(".") ? Color.secondary : Color.accentColor)
    }
}
