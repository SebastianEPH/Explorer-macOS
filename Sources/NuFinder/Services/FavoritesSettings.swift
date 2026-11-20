import AppKit
import SwiftUI

/// Fork: Ajustes → Favoritos. Todo se guarda en UserDefaults:
/// - `customFavoritePaths` y `favoriteOrderPaths` (las mismas claves que usa BrowserModel)
/// - `favorites.hiddenPaths`, `favorites.titles`, `favorites.icons` (propias del fork)
/// Al cambiar algo se avisa con `didChange` y cada BrowserModel vuelve a leer la lista.
enum FavoritesSettings {
    static let didChange = Notification.Name("FavoritesSettings.didChange")

    private static let hiddenKey = "favorites.hiddenPaths"
    private static let titlesKey = "favorites.titles"
    private static let iconsKey = "favorites.icons"
    private static var defaults: UserDefaults { .standard }

    static let iconChoices = [
        "folder", "folder.fill", "house", "menubar.dock.rectangle", "doc", "doc.text",
        "arrow.down.circle", "photo", "music.note", "film", "star", "heart",
        "briefcase", "hammer", "terminal", "chevron.left.forwardslash.chevron.right",
        "externaldrive", "icloud", "tray", "archivebox", "book", "graduationcap",
        "gamecontroller", "cart", "person", "globe", "lock", "tag"
    ]

    // MARK: Lectura

    static func path(_ url: URL) -> String { url.standardizedFileURL.path }

    static var hiddenPaths: Set<String> { Set(defaults.stringArray(forKey: hiddenKey) ?? []) }
    static var titles: [String: String] { defaults.dictionary(forKey: titlesKey) as? [String: String] ?? [:] }
    static var icons: [String: String] { defaults.dictionary(forKey: iconsKey) as? [String: String] ?? [:] }

    /// Lo que se ve en la barra lateral: sin los ocultos y con nombre e icono propios.
    static func visible(_ locations: [FavoriteLocation]) -> [FavoriteLocation] {
        let hidden = hiddenPaths, titles = titles, icons = icons
        return locations
            .filter { !hidden.contains(path($0.url)) }
            .map { location in
                let key = path(location.url)
                let title = titles[key].flatMap { $0.isEmpty ? nil : $0 } ?? location.title
                return FavoriteLocation(url: location.url, title: title,
                                        icon: icons[key] ?? location.icon, isBuiltIn: location.isBuiltIn)
            }
    }

    /// Lista completa (también los ocultos), en el orden guardado, con valores originales.
    static func allLocations() -> [FavoriteLocation] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let builtIn = [
            FavoriteLocation(url: home, title: "Home", icon: "house", isBuiltIn: true),
            FavoriteLocation(url: home.appendingPathComponent("Desktop"), title: "Desktop",
                             icon: "menubar.dock.rectangle", isBuiltIn: true),
            FavoriteLocation(url: home.appendingPathComponent("Documents"), title: "Documents",
                             icon: "doc", isBuiltIn: true),
            FavoriteLocation(url: home.appendingPathComponent("Downloads"), title: "Downloads",
                             icon: "arrow.down.circle", isBuiltIn: true)
        ]
        let custom = (defaults.stringArray(forKey: "customFavoritePaths") ?? []).map {
            let url = BrowserModel.storedDirectoryURL($0)
            return FavoriteLocation(url: url, title: url.lastPathComponent, icon: "folder", isBuiltIn: false)
        }
        var remaining = builtIn + custom
        var ordered: [FavoriteLocation] = []
        for key in defaults.stringArray(forKey: "favoriteOrderPaths") ?? [] {
            if let index = remaining.firstIndex(where: { path($0.url) == key }) {
                ordered.append(remaining.remove(at: index))
            }
        }
        return ordered + remaining
    }

    // MARK: Escritura

    static func setHidden(_ hidden: Bool, _ url: URL) {
        var set = hiddenPaths
        if hidden { set.insert(path(url)) } else { set.remove(path(url)) }
        defaults.set(Array(set), forKey: hiddenKey)
        notify()
    }

    static func setTitle(_ title: String, _ url: URL) {
        var dict = titles
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        dict[path(url)] = trimmed.isEmpty ? nil : trimmed
        defaults.set(dict, forKey: titlesKey)
        notify()
    }

    static func setIcon(_ icon: String?, _ url: URL) {
        var dict = icons
        dict[path(url)] = icon
        defaults.set(dict, forKey: iconsKey)
        notify()
    }

    static func move(from index: Int, by offset: Int) {
        var list = allLocations()
        guard list.indices.contains(index), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        defaults.set(list.map { path($0.url) }, forKey: "favoriteOrderPaths")
        notify()
    }

    static func add(_ url: URL) {
        let key = path(url)
        guard !allLocations().contains(where: { path($0.url) == key }) else {
            setHidden(false, url)
            return
        }
        var custom = defaults.stringArray(forKey: "customFavoritePaths") ?? []
        custom.append(key)
        defaults.set(custom, forKey: "customFavoritePaths")
        notify()
    }

    static func remove(_ url: URL) {
        let key = path(url)
        defaults.set((defaults.stringArray(forKey: "customFavoritePaths") ?? []).filter { $0 != key },
                     forKey: "customFavoritePaths")
        defaults.set((defaults.stringArray(forKey: "favoriteOrderPaths") ?? []).filter { $0 != key },
                     forKey: "favoriteOrderPaths")
        var t = titles; t[key] = nil; defaults.set(t, forKey: titlesKey)
        var i = icons; i[key] = nil; defaults.set(i, forKey: iconsKey)
        var h = hiddenPaths; h.remove(key); defaults.set(Array(h), forKey: hiddenKey)
        notify()
    }

    /// Vuelve a los favoritos de fábrica (no toca las carpetas, solo la barra lateral).
    static func reset() {
        for key in [hiddenKey, titlesKey, iconsKey, "favoriteOrderPaths"] {
            defaults.removeObject(forKey: key)
        }
        notify()
    }

    private static func notify() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// Sección «Favorites» de Ajustes.
struct FavoritesSection: View {
    @State private var locations = FavoritesSettings.allLocations()
    @State private var hidden = FavoritesSettings.hiddenPaths
    @State private var titles = FavoritesSettings.titles
    @State private var icons = FavoritesSettings.icons
    @State private var confirmingReset = false

    var body: some View {
        Section("Favorites") {
            ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                row(location, index: index)
            }
            HStack {
                Button("Add Folder…", systemImage: "plus") { addFolder() }
                Spacer()
                Button("Restore Defaults") { confirmingReset = true }
            }
            Text("Changes appear in the sidebar right away. Folders are never moved or deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Restore the default Favorites?", isPresented: $confirmingReset) {
            Button("Restore Defaults", role: .destructive) { FavoritesSettings.reset() }
        } message: {
            Text("Names, icons, order and hidden items are reset. Added folders stay.")
        }
        .onReceive(NotificationCenter.default.publisher(for: FavoritesSettings.didChange)) { _ in reload() }
    }

    private func row(_ location: FavoriteLocation, index: Int) -> some View {
        let key = FavoritesSettings.path(location.url)
        return HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { !hidden.contains(key) },
                set: { FavoritesSettings.setHidden(!$0, location.url) }
            ))
            .labelsHidden()
            .help(Text("Show in sidebar"))

            Menu {
                Button("Default") { FavoritesSettings.setIcon(nil, location.url) }
                Divider()
                ForEach(FavoritesSettings.iconChoices, id: \.self) { symbol in
                    Button { FavoritesSettings.setIcon(symbol, location.url) } label: {
                        Label(symbol, systemImage: symbol)
                    }
                }
            } label: {
                Image(systemName: icons[key] ?? location.icon)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(Text("Icon"))

            TextField(location.title, text: Binding(
                get: { titles[key] ?? "" },
                set: { FavoritesSettings.setTitle($0, location.url) }
            ))
            .help(location.url.path)

            Button { FavoritesSettings.move(from: index, by: -1) } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless)
                .disabled(index == 0)
            Button { FavoritesSettings.move(from: index, by: 1) } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(index == locations.count - 1)
            Button { FavoritesSettings.remove(location.url) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .disabled(location.isBuiltIn)
                .help(Text("Remove from Favorites"))
        }
        .opacity(hidden.contains(key) ? 0.5 : 1)
    }

    private func reload() {
        locations = FavoritesSettings.allLocations()
        hidden = FavoritesSettings.hiddenPaths
        titles = FavoritesSettings.titles
        icons = FavoritesSettings.icons
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(FavoritesSettings.add)
    }
}
