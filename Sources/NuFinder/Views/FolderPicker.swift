import AppKit
import SwiftUI

/// Fork: selector de carpetas de Explorer (sin el panel de macOS, que es el del Finder).
/// Como una ventana de Explorer en pequeño: favoritos y discos a la izquierda, contenido con iconos
/// reales, fecha y tipo (los archivos se ven en gris, no se pueden elegir), ruta en botones,
/// atrás/adelante/subir, buscar, escribir una ruta y crear carpetas.
struct FolderPicker: View {
    let title: LocalizedStringKey
    let confirm: LocalizedStringKey
    let done: (URL?) -> Void
    @State private var folder: URL
    @State private var back: [URL] = []
    @State private var forward: [URL] = []
    @State private var selection: URL?
    @State private var search = ""
    @State private var typingPath = false
    @State private var pathText = ""
    @State private var newFolderName = ""
    @State private var showsNewFolder = false
    @State private var error: String?

    init(title: LocalizedStringKey, confirm: LocalizedStringKey, start: URL? = nil, done: @escaping (URL?) -> Void) {
        self.title = title
        self.confirm = confirm
        self.done = done
        let initial = start ?? KeyWindowFocus.shared.windowBrowser?.currentURL ?? FileManager.default.homeDirectoryForCurrentUser
        _folder = State(initialValue: initial.standardizedFileURL)
    }

    struct Entry: Identifiable, Hashable {
        let url: URL
        let isFolder: Bool
        let modified: Date?
        let kind: String
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    /// Contenido de una carpeta: primero carpetas, luego archivos (en gris), como en Explorer.
    static func entries(of url: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .localizedTypeDescriptionKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.map { item in
            let values = try? item.resourceValues(forKeys: Set(keys))
            return Entry(url: item, isFolder: values?.isDirectory == true && values?.isPackage != true,
                         modified: values?.contentModificationDate, kind: values?.localizedTypeDescription ?? "")
        }
        .sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
    }

    /// Solo las subcarpetas (para pruebas y para saber si se puede entrar).
    static func subfolders(of url: URL) -> [URL] { entries(of: url).filter(\.isFolder).map(\.url) }

    private var favorites: [FavoriteLocation] { FavoritesSettings.visible(FavoritesSettings.allLocations()) }
    private var volumes: [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
    }
    private var shown: [Entry] {
        let all = FolderPicker.entries(of: folder)
        return search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    private var chosen: URL { selection ?? folder }

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.headline).padding(.top, 12).padding(.bottom, 8)
            toolbar
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 160, idealWidth: 180, maxWidth: 240)
                list.frame(minWidth: 400)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 540)
        .alert("New Folder", isPresented: $showsNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Barra de arriba

    private var toolbar: some View {
        HStack(spacing: 8) {
            Group {
                Button { goBack() } label: { Image(systemName: "chevron.left") }.disabled(back.isEmpty).help(Text("Back"))
                Button { goForward() } label: { Image(systemName: "chevron.right") }.disabled(forward.isEmpty).help(Text("Forward"))
                Button { go(folder.deletingLastPathComponent()) } label: { Image(systemName: "chevron.up") }
                    .disabled(folder.path == "/").help(Text("Enclosing Folder"))
            }
            .buttonStyle(.borderless)
            if typingPath {
                TextField("Path", text: $pathText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { openTypedPath() }
                    .onExitCommand { typingPath = false }
            } else {
                breadcrumb
            }
            Button { pathText = folder.path; typingPath.toggle() } label: { Image(systemName: "character.cursor.ibeam") }
                .buttonStyle(.borderless).help(Text("Type a path"))
            TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 150)
            Button { newFolderName = ""; showsNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                .buttonStyle(.borderless).help(Text("New Folder"))
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                let parts = folder.pathComponents
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                    Button {
                        go(URL(fileURLWithPath: NSString.path(withComponents: Array(parts[...index]))))
                    } label: {
                        Text(part == "/" ? (FileManager.default.displayName(atPath: "/")) : part)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                    }
                    .buttonStyle(HoverPressButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Barra lateral

    private var sidebar: some View {
        List {
            Section("Favorites") {
                ForEach(favorites) { place in
                    Label(place.title, systemImage: place.icon)
                        .contentShape(Rectangle())
                        .onTapGesture { go(place.url) }
                        .listRowBackground(place.url.standardizedFileURL == folder ? Color.accentColor.opacity(0.2) : Color.clear)
                }
            }
            Section("Locations") {
                ForEach(volumes, id: \.self) { volume in
                    Label(FileManager.default.displayName(atPath: volume.path), systemImage: volume.path == "/" ? "internaldrive" : "externaldrive")
                        .contentShape(Rectangle())
                        .onTapGesture { go(volume) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Lista

    private var list: some View {
        Table(shown, selection: Binding(get: { selection }, set: { url in
            // Los archivos se ven pero no se eligen: aquí se elige una carpeta.
            if let url, shown.first(where: { $0.url == url })?.isFolder == true { selection = url } else if url == nil { selection = nil }
        })) {
            TableColumn("Name") { entry in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 18, height: 18)
                    Text(entry.name)
                }
                .opacity(entry.isFolder ? 1 : 0.4)
            }
            TableColumn("Date Modified") { entry in
                Text(entry.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    .foregroundStyle(.secondary).opacity(entry.isFolder ? 1 : 0.5)
            }
            .width(min: 120, ideal: 150)
            TableColumn("Kind") { entry in
                Text(entry.kind).foregroundStyle(.secondary).opacity(entry.isFolder ? 1 : 0.5)
            }
            .width(min: 80, ideal: 120)
        }
        .contextMenu(forSelectionType: URL.self) { _ in } primaryAction: { urls in
            if let url = urls.first, shown.first(where: { $0.url == url })?.isFolder == true { go(url) } // doble clic = entrar
        }
        .overlay {
            if shown.isEmpty {
                Text(search.isEmpty ? "This folder is empty" : "No results").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Abajo

    private var footer: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: chosen.path)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(chosen.lastPathComponent.isEmpty ? chosen.path : chosen.lastPathComponent).fontWeight(.medium)
                Text(chosen.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption) }
            Spacer()
            Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
            Button(confirm) { done(chosen) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    // MARK: Navegación

    private func go(_ url: URL) {
        let target = url.standardizedFileURL
        guard target != folder else { return }
        back.append(folder); forward.removeAll()
        folder = target; selection = nil; search = ""; error = nil
    }

    private func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(folder); folder = previous; selection = nil
    }

    private func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(folder); folder = next; selection = nil
    }

    private func openTypedPath() {
        let url = URL(fileURLWithPath: (pathText as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            go(url); typingPath = false
        } else { error = String(localized: "That folder doesn’t exist") }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let url = folder.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            selection = url
        } catch { self.error = error.localizedDescription }
    }
}
