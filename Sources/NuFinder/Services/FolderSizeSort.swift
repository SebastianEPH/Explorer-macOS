import SwiftUI

/// Fork: al ordenar por tamaño, las carpetas usan el tamaño que ya calculó
/// `FolderSizeService` (el mismo que se ve en la columna). En el original una carpeta
/// valía su tamaño de directorio (~0), así que, como van arriba, ningún clic en
/// «Tamaño» las movía y parecía que el botón no hacía caso. Apagado = original.
@MainActor
enum FolderSizeSort {
    static let key = "files.sortFoldersBySize"
    static var defaults: UserDefaults = .standard
    /// Tamaño calculado de una carpeta (sustituible en pruebas).
    static var folderSize: (FileItem) -> Int64? = { FolderSizeService.shared.size(for: $0) }

    static func reset() {
        defaults = .standard
        folderSize = { FolderSizeService.shared.size(for: $0) }
    }

    static var isOn: Bool { defaults.bool(forKey: key) }

    static func size(_ item: FileItem) -> Int64 {
        guard item.isDirectory, isOn, let bytes = folderSize(item) else { return item.size }
        return bytes
    }
}

extension BrowserModel {
    /// Se llama cuando llegan tamaños de carpetas: reordena solo si se ordena por tamaño.
    func resortForFolderSizes() {
        guard FolderSizeSort.isOn, sortCriteria.contains(where: { $0.field == .size }) else { return }
        let resorted = items
        sortedAgain()
        if items.map(\.id) == resorted.map(\.id) { items = resorted }
    }
}

struct FolderSizeSortToggle: View {
    @AppStorage(FolderSizeSort.key) private var on = false

    var body: some View {
        Toggle(isOn: $on) {
            Label("Sort folders by their calculated size", systemImage: "arrow.up.arrow.down.square")
            Text("Sorting by Size also moves folders, using the size shown in the column. Off: folders count as empty and stay in name order.")
        }
        SettingsPreviewBox(title: "Preview: sorted by Size, largest first") {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(on ? [("Videos", "11.8 GB"), ("Fotos", "6.9 MB"), ("Notas", "192 KB")]
                           : [("Fotos", "6.9 MB"), ("Notas", "192 KB"), ("Videos", "11.8 GB")], id: \.0) { name, size in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                        Text(verbatim: name).font(.caption)
                        Spacer()
                        Text(verbatim: size).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.default, value: on)
        }
    }
}
