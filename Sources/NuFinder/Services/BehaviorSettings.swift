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
    static let toolbarColorKey = "appearance.toolbarColor"          // modo claro (y oscuro si no hay otro)
    static let toolbarColorDarkKey = "appearance.toolbarColorDark"  // "" = igual que el claro

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

    /// Color guardado para el modo actual: un color de la lista o "#RRGGBB".
    static func toolbarColorID(light: String, dark: String, scheme: ColorScheme) -> String {
        scheme == .dark && !dark.isEmpty ? dark : light
    }

    /// Color base: uno de la lista, uno propio en "#RRGGBB" o el morado original.
    static func toolbarBase(_ id: String) -> Color {
        if let custom = color(hex: id) { return custom }
        return toolbarColors.first { $0.id == id }?.color ?? toolbarColors[0].color
    }

    /// Tono oscuro para la sombra y el número de los botones.
    static func toolbarDeep(_ id: String) -> Color { toolbarBase(id).mix(with: .black, by: 0.5) }

    static func color(hex: String) -> Color? {
        guard hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static func hex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .purple
        return String(format: "#%02X%02X%02X", Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
    }

    /// Colores del degradado de los botones de la barra (el original es morado).
    static func toolbarGradient(_ id: String, active: Bool) -> [Color] {
        let base = toolbarBase(id)
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
    /// Fork: apartado a mostrar (nil = todos).
    var part: String? = nil
    private func shows(_ name: String) -> Bool { part == nil || part == name }
    @AppStorage(BehaviorSettings.restoresTabsKey) private var restoresTabs = true
    @AppStorage(BehaviorSettings.startFolderKey) private var startFolder = ""
    @AppStorage(BehaviorSettings.newTabFolderKey) private var newTabFolder = ""
    @AppStorage(BehaviorSettings.defaultViewKey) private var defaultView = FileViewMode.list.rawValue
    @AppStorage(BehaviorSettings.hiddenByDefaultKey) private var hiddenByDefault = false

    var body: some View {
        if shows("opens") {
            Section("When Explorer Opens") {
                Toggle(isOn: $restoresTabs) {
                    Label("Reopen the tabs from last time", systemImage: "arrow.counterclockwise")
                    Text("Off: always starts with one tab in the folder below.")
                }
                FolderChoicePicker(title: "Start folder", symbol: "house", emptyLabel: "Home", value: $startFolder)
                    .lockedSetting(restoresTabs)
                if restoresTabs {
                    DisabledReason("Not used while “Reopen the tabs from last time” is on. Turn it off to choose a start folder.")
                }
            }
        }
        if shows("tabs") {
            Section("Tabs") {
                FolderChoicePicker(title: "New tab opens", symbol: "plus.square.on.square",
                                   emptyLabel: "The current folder", value: $newTabFolder)
            }
        }
        if shows("view") {
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
                FolderViewConsistencyToggle() // Fork
            }
        }
    }
}

struct FileBehaviorSection: View {
    /// Fork: apartado a mostrar (nil = todos).
    var part: String? = nil
    private func shows(_ name: String) -> Bool { part == nil || part == name }
    @AppStorage(BehaviorSettings.confirmTrashKey) private var confirmTrash = false
    @AppStorage(ListColumnSettings.showsCreatedKey) private var showsCreated = false
    @AppStorage("previewPane.visible") private var previewVisible = true
    @AppStorage("operations.autoClose") private var autoClose = true
    @AppStorage(FolderSizeQueue.autoKey) private var autoFolderSizes = true

    var body: some View {
        if shows("opening") {
            Section("Opening and Deleting") {
                Toggle(isOn: $confirmTrash) {
                    Label("Ask before moving to the Trash", systemImage: "trash")
                    Text("Shows a confirmation before deleting with ⌘⌫ or the menu.")
                }
            }
        }
        if shows("panels") {
            Section("Panels") {
                Toggle(isOn: $showsCreated) {
                    Label("“Date Created” column in List view", systemImage: "calendar.badge.plus")
                }
                Toggle(isOn: $previewVisible) {
                    Label("Image preview pane", systemImage: "sidebar.right")
                    Text("Panel on the right that shows the selected image.")
                }
                Toggle(isOn: $autoFolderSizes) {
                    Label("Calculate folder sizes automatically", systemImage: "scalemass")
                    Text("Off: the Size column shows “—” for folders; right-click → Calculate Size when you need it.")
                }
                FolderSizeParallelPicker() // Fork
                FolderSizeSortToggle() // Fork
                Toggle(isOn: $autoClose) {
                    Label("Close the operations panel when done", systemImage: "arrow.left.arrow.right.circle")
                }
            }
        }
    }
}

struct AppearanceSection: View {
    /// Fork: apartado a mostrar (nil = todos).
    var part: String? = nil
    private func shows(_ name: String) -> Bool { part == nil || part == name }
    @AppStorage(AppearanceSettings.themeKey) private var theme = ""
    @AppStorage(AppearanceSettings.toolbarColorKey) private var toolbarColor = ""
    @AppStorage(AppearanceSettings.toolbarColorDarkKey) private var toolbarColorDark = ""
    @AppStorage(BehaviorSettings.showsLocationsKey) private var showsLocations = true
    @AppStorage(SidebarTransparency.key) private var sidebarTransparency = "system"

    var body: some View {
        if shows("theme") {
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
        }
        if shows("buttons") {
            Section("Toolbar Buttons") {
                ToolbarColorRow(title: "Light mode", symbol: "sun.max", value: $toolbarColor, allowsSame: false)
                ToolbarColorRow(title: "Dark mode", symbol: "moon", value: $toolbarColorDark, allowsSame: true)
                SettingsPreviewBox(title: "Preview: the purple buttons of the window, in light and dark mode") {
                    HStack(spacing: 12) {
                        toolbarSample(.light)
                        toolbarSample(.dark)
                    }
                }
                Text("These colors are used by the toolbar buttons, the up button, sorting, the gallery and the badges.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if shows("sidebar") {
            Section("Sidebar") {
                Picker(selection: $sidebarTransparency) {
                Text("Like Finder (system)").tag("system")
                Text("Less transparent").tag("less")
                Text("Solid").tag("solid")
            } label: {
                Label("Transparency", systemImage: "square.on.square.intersection.dashed")
                Text("“Like Finder” uses the same macOS material as Finder’s sidebar.")
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $showsLocations) {
                    Label("Show “Locations” (disks and servers)", systemImage: "externaldrive")
                }
                SidebarExtrasToggles()
            }
        }
    }

    private func toolbarSample(_ scheme: ColorScheme) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(["arrow.up", "square.stack.3d.up", "rectangle.split.2x1", "terminal", "arrow.left.arrow.right.circle"], id: \.self) {
                    FreeloaderToolbarIcon(systemName: $0, badge: $0 == "arrow.left.arrow.right.circle" ? 2 : 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.96), in: RoundedRectangle(cornerRadius: 8))
            .environment(\.colorScheme, scheme)
            Text(scheme == .dark ? "Dark mode" : "Light mode").font(.caption).foregroundStyle(.secondary)
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

/// Fila para elegir el color de los botones: colores de la lista o uno propio.
struct ToolbarColorRow: View {
    let title: LocalizedStringKey
    let symbol: String
    @Binding var value: String
    let allowsSame: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 7) {
                if allowsSame {
                    Button { value = "" } label: {
                        Text("Same").font(.caption)
                            .padding(.horizontal, 6).frame(height: 20)
                            .overlay(Capsule().strokeBorder(.primary, lineWidth: value.isEmpty ? 2 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(Text("Same color as light mode"))
                }
                ForEach(AppearanceSettings.toolbarColors, id: \.id) { choice in
                    let selected = !(allowsSame && value.isEmpty) && value == choice.id
                    Button { value = choice.id.isEmpty && allowsSame ? "purple" : choice.id } label: {
                        Circle().fill(choice.color).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: selected || (allowsSame && choice.id.isEmpty && value == "purple") ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(Text(choice.name))
                }
                ColorPicker("", selection: Binding(
                    get: { AppearanceSettings.toolbarBase(value) },
                    set: { value = AppearanceSettings.hex($0) }
                ), supportsOpacity: false)
                .labelsHidden()
                .help(Text("Any color"))
                .overlay(alignment: .bottom) {
                    if value.hasPrefix("#") { Circle().fill(.primary).frame(width: 4, height: 4).offset(y: 6) }
                }
            }
        } label: { Label(title, systemImage: symbol) }
    }
}

/// Fork: transparencia de la barra lateral. «system» = el material de macOS, igual que Finder.
enum SidebarTransparency {
    static let key = "sidebar.transparency"   // "system", "less", "solid"
}

extension View {
    func sidebarTransparency() -> some View { modifier(SidebarTransparencyModifier()) }
}

private struct SidebarTransparencyModifier: ViewModifier {
    @AppStorage(SidebarTransparency.key) private var mode = "system"
    func body(content: Content) -> some View {
        switch mode {
        case "less":
            content.scrollContentBackground(.hidden).background(.thickMaterial)
        case "solid":
            content.scrollContentBackground(.hidden).background(Color(nsColor: .windowBackgroundColor))
        default:
            content
        }
    }
}
