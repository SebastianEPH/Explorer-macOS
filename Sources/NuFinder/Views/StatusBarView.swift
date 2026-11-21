import SwiftUI

/// Fork: barra de estado bajo la lista de archivos (como la de Windows):
/// cantidad de elementos, selección, tamaño de lo seleccionado, espacio libre y botones de vista.
enum StatusBarSettings {
    static let visibleKey = "statusBar.visible"
    static let countKey = "statusBar.count"
    static let kindsKey = "statusBar.kinds"
    static let selectionKey = "statusBar.selection"
    static let sizeKey = "statusBar.size"
    static let freeSpaceKey = "statusBar.freeSpace"
    static let viewButtonsKey = "statusBar.viewButtons"

    nonisolated(unsafe) static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// Tamaño de lo seleccionado. Las carpetas solo suman si ya se calculó su tamaño.
    static func selectionBytes(_ items: [FileItem], folderSize: (FileItem) -> Int64?) -> (bytes: Int64, pendingFolders: Int) {
        var bytes: Int64 = 0
        var pending = 0
        for item in items {
            if item.isDirectory {
                if let size = folderSize(item) { bytes += size } else { pending += 1 }
            } else {
                bytes += item.size
            }
        }
        return (bytes, pending)
    }

    static func freeSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// Datos que muestra la barra (separados de la vista para reutilizarla en la vista previa de Ajustes).
struct StatusBarData: Equatable {
    var total: Int
    var folders: Int
    var selected: Int
    var selectedBytes: Int64
    var pendingFolders: Int
    var freeBytes: Int64?
}

struct StatusBarContent: View {
    let data: StatusBarData
    var viewMode: Binding<FileViewMode>?

    @AppStorage(StatusBarSettings.countKey) private var showsCount = true
    @AppStorage(StatusBarSettings.kindsKey) private var showsKinds = false
    @AppStorage(StatusBarSettings.selectionKey) private var showsSelection = true
    @AppStorage(StatusBarSettings.sizeKey) private var showsSize = true
    @AppStorage(StatusBarSettings.freeSpaceKey) private var showsFreeSpace = true
    @AppStorage(StatusBarSettings.viewButtonsKey) private var showsViewButtons = true

    var body: some View {
        HStack(spacing: 10) {
            if showsCount {
                Text("\(data.total) items")
            }
            if showsKinds {
                separator
                Text("\(data.folders) folders, \(data.total - data.folders) files")
            }
            if showsSelection && data.selected > 0 {
                separator
                Text("\(data.selected) selected")
            }
            if showsSize && data.selected > 0 && (data.selectedBytes > 0 || data.pendingFolders == 0) {
                separator
                Text(StatusBarSettings.formatter.string(fromByteCount: data.selectedBytes))
                    + Text(data.pendingFolders > 0 ? " + " : "")
                    + (data.pendingFolders > 0 ? Text("\(data.pendingFolders) folders") : Text(verbatim: ""))
            }
            Spacer(minLength: 8)
            if showsFreeSpace, let free = data.freeBytes {
                Text("\(StatusBarSettings.formatter.string(fromByteCount: free)) available")
            }
            if showsViewButtons, let viewMode {
                HStack(spacing: 2) {
                    viewButton(.list, "list.bullet", viewMode)
                    viewButton(.compact, "square.grid.3x1.below.line.grid.1x2", viewMode)
                    viewButton(.icons, "square.grid.2x2", viewMode)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private var separator: some View {
        Rectangle().fill(.separator).frame(width: 1, height: 12)
    }

    private func viewButton(_ mode: FileViewMode, _ symbol: String, _ binding: Binding<FileViewMode>) -> some View {
        Button { binding.wrappedValue = mode } label: {
            Image(systemName: symbol)
                .frame(width: 20, height: 18)
                .background(binding.wrappedValue == mode ? Color.accentColor.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(binding.wrappedValue == mode ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(Text(LocalizedStringKey(mode.rawValue)))
    }
}

/// Barra real, enganchada bajo la lista en `ContentView`.
struct StatusBarView: View {
    @EnvironmentObject private var browser: BrowserModel
    @ObservedObject private var folderSizes = FolderSizeService.shared
    @AppStorage(StatusBarSettings.visibleKey) private var visible = true

    var body: some View {
        if visible {
            VStack(spacing: 0) {
                Divider()
                StatusBarContent(data: data, viewMode: $browser.viewMode)
            }
            .background(.bar)
        }
    }

    private var data: StatusBarData {
        let items = browser.displayedItems
        let selected = items.filter { browser.selection.contains($0.url) }
        let sizes = StatusBarSettings.selectionBytes(selected) { folderSizes.size(for: $0) }
        return StatusBarData(
            total: items.count,
            folders: items.filter(\.isDirectory).count,
            selected: selected.count,
            selectedBytes: sizes.bytes,
            pendingFolders: sizes.pendingFolders,
            freeBytes: StatusBarSettings.freeSpace(at: browser.currentURL)
        )
    }
}

/// Sección «Barra de estado» de Ajustes, con vista previa.
struct StatusBarSection: View {
    @AppStorage(StatusBarSettings.visibleKey) private var visible = true
    @AppStorage(StatusBarSettings.countKey) private var showsCount = true
    @AppStorage(StatusBarSettings.kindsKey) private var showsKinds = false
    @AppStorage(StatusBarSettings.selectionKey) private var showsSelection = true
    @AppStorage(StatusBarSettings.sizeKey) private var showsSize = true
    @AppStorage(StatusBarSettings.freeSpaceKey) private var showsFreeSpace = true
    @AppStorage(StatusBarSettings.viewButtonsKey) private var showsViewButtons = true
    @State private var previewMode: FileViewMode = .list

    var body: some View {
        Section("Status Bar") {
            Toggle(isOn: $visible) {
                Label("Show the status bar below the files", systemImage: "rectangle.bottomthird.inset.filled")
                Text("Like Windows: item count, selection and size at the bottom of the window.")
            }
            SettingsPreviewBox(title: "Preview: bottom of the window, with 3 items selected") {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(["Fotos", "Informe.pdf", "Vacaciones.jpg", "notas.txt"], id: \.self) { name in
                            HStack {
                                Image(systemName: name.contains(".") ? "doc.fill" : "folder.fill")
                                    .foregroundStyle(name.contains(".") ? Color.secondary : Color.accentColor)
                                Text(verbatim: name).font(.caption)
                                Spacer()
                            }
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(name == "notas.txt" ? .clear : Color.accentColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(8)
                    if visible {
                        Divider()
                        StatusBarContent(
                            data: StatusBarData(total: 24, folders: 6, selected: 3, selectedBytes: 4_718_592, pendingFolders: 1, freeBytes: 182_000_000_000),
                            viewMode: $previewMode
                        )
                        .background(.bar)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .animation(.default, value: visible)
            }
            Group {
                Toggle(isOn: $showsCount) { Label("Number of items", systemImage: "number") }
                Toggle(isOn: $showsKinds) { Label("Folders and files separately", systemImage: "folder") }
                Toggle(isOn: $showsSelection) { Label("Number of selected items", systemImage: "checkmark.circle") }
                Toggle(isOn: $showsSize) {
                    Label("Size of the selection", systemImage: "scalemass")
                    Text("Folders count only after calculating their size.")
                }
                Toggle(isOn: $showsFreeSpace) { Label("Free space on the disk", systemImage: "internaldrive") }
                Toggle(isOn: $showsViewButtons) { Label("View buttons (List, Compact, Icons)", systemImage: "square.grid.2x2") }
            }
            .disabled(!visible)
        }
    }
}
