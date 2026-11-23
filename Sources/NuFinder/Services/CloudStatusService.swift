import Foundation
import SwiftUI

/// Fork: estado de un archivo de una nube montada con File Provider (OneDrive, Google Drive,
/// Dropbox, iCloud Drive…), leído con las mismas claves que usa Finder.
enum CloudItemState: String, CaseIterable {
    case cloudOnly, downloading, uploading, downloaded, error

    /// Traduce los valores de macOS a un estado (función pura, para poder probarla).
    static func from(isUbiquitous: Bool, status: URLUbiquitousItemDownloadingStatus?,
                     isDownloading: Bool, isUploading: Bool, hasError: Bool) -> CloudItemState? {
        guard isUbiquitous else { return nil }
        if hasError { return .error }
        if isUploading { return .uploading }
        if isDownloading { return .downloading }
        if status == .notDownloaded { return .cloudOnly }
        return .downloaded
    }

    var symbol: String {
        switch self {
        case .cloudOnly: "icloud"
        case .downloading: "icloud.and.arrow.down"
        case .uploading: "icloud.and.arrow.up"
        case .downloaded: "checkmark.icloud"
        case .error: "exclamationmark.icloud"
        }
    }

    var color: Color {
        switch self {
        case .cloudOnly, .downloaded: .secondary
        case .downloading, .uploading: .accentColor
        case .error: .red
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .cloudOnly: "Only in the cloud"
        case .downloading: "Downloading"
        case .uploading: "Uploading"
        case .downloaded: "Downloaded"
        case .error: "Sync error"
        }
    }
}

enum CloudStatus {
    /// Mostrar el icono de estado junto al nombre (apagado = como el original).
    static let enabledKey = "cloud.statusEnabled"
    /// Mostrar también los ya descargados (Finder no los marca).
    static let showDownloadedKey = "cloud.showDownloaded"
    /// Opciones «Descargar ahora» / «Quitar descarga» en el clic derecho.
    static let menuKey = "cloud.menuActions"
    /// Cada cuánto se vuelve a mirar el estado de lo que se ve, en segundos.
    static let refreshKey = "cloud.refreshSeconds"

    static var defaults: [String: Any] {
        [enabledKey: true, showDownloadedKey: false, menuKey: true, refreshKey: 2.0]
    }

    /// Lector del estado; las pruebas lo sustituyen para simular una nube.
    nonisolated(unsafe) static var provider: (URL) -> CloudItemState? = read { didSet { resetCache() } }

    /// Estado reutilizable mientras está fresco (el menú contextual lo pide en cada redibujo
    /// de cada archivo; leer el disco ahí hacía ir a tirones el desplazamiento).
    static func state(for url: URL) -> CloudItemState? {
        let now = Date().timeIntervalSinceReferenceDate
        cacheLock.lock()
        if let hit = cache[url.path], now - hit.time < freshness { cacheLock.unlock(); return hit.state }
        cacheLock.unlock()
        return refresh(url)
    }

    /// Vuelve a leer el estado del disco (lo usa el icono al refrescarse).
    @discardableResult
    static func refresh(_ url: URL) -> CloudItemState? {
        let state = provider(url)
        cacheLock.lock()
        if cache.count > 20_000 { cache.removeAll() }
        cache[url.path] = (state, Date().timeIntervalSinceReferenceDate)
        cacheLock.unlock()
        return state
    }

    static func resetCache() { cacheLock.lock(); cache.removeAll(); cacheLock.unlock() }

    private static var freshness: Double { max(0.5, UserDefaults.standard.object(forKey: refreshKey) as? Double ?? 2) }
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (state: CloudItemState?, time: Double)] = [:]

    static func read(_ url: URL) -> CloudItemState? {
        let fresh = URL(fileURLWithPath: url.path) // sin valores en caché
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
                                         .ubiquitousItemIsDownloadingKey, .ubiquitousItemIsUploadingKey,
                                         .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey]
        guard let v = try? fresh.resourceValues(forKeys: keys) else { return nil }
        return CloudItemState.from(
            isUbiquitous: v.isUbiquitousItem ?? false, status: v.ubiquitousItemDownloadingStatus,
            isDownloading: v.ubiquitousItemIsDownloading ?? false, isUploading: v.ubiquitousItemIsUploading ?? false,
            hasError: v.ubiquitousItemUploadingError != nil || v.ubiquitousItemDownloadingError != nil)
    }

    /// Si una opción del menú puede salir para este archivo.
    static func menuAllows(_ option: ContextMenuOption, _ url: URL, store: UserDefaults = .standard) -> Bool {
        guard option == .cloudDownload || option == .cloudEvict else { return true }
        guard store.object(forKey: menuKey) == nil || store.bool(forKey: menuKey) else { return false }
        guard let state = state(for: url) else { return false }
        return option == .cloudDownload ? state == .cloudOnly : state == .downloaded
    }

    static func download(_ urls: [URL]) {
        for url in urls { try? FileManager.default.startDownloadingUbiquitousItem(at: url); refresh(url) }
    }

    static func evict(_ urls: [URL]) {
        for url in urls { try? FileManager.default.evictUbiquitousItem(at: url); refresh(url) }
    }
}

/// Icono de estado de la nube junto al nombre, que se actualiza solo mientras se ve.
struct CloudStatusBadge: View {
    let url: URL
    @AppStorage(CloudStatus.enabledKey) private var enabled = true
    @AppStorage(CloudStatus.showDownloadedKey) private var showDownloaded = false
    @AppStorage(CloudStatus.refreshKey) private var refresh = 2.0
    @State private var state: CloudItemState?

    var body: some View {
        Group {
            if enabled, let state, state != .downloaded || showDownloaded {
                Image(systemName: state.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(state.color)
                    .help(Text(state.title))
                    .accessibilityLabel(Text(state.title))
            }
        }
        .task(id: "\(url.path)|\(enabled)") {
            guard enabled else { state = nil; return }
            state = CloudStatus.state(for: url)
            while state != nil, !Task.isCancelled { // fuera de la nube se mira una sola vez
                try? await Task.sleep(for: .seconds(max(0.5, refresh)))
                state = CloudStatus.refresh(url)
            }
        }
    }
}

/// Ajustes → Archivos → Nube.
struct CloudStatusSection: View {
    @AppStorage(CloudStatus.enabledKey) private var enabled = true
    @AppStorage(CloudStatus.showDownloadedKey) private var showDownloaded = false
    @AppStorage(CloudStatus.menuKey) private var menuActions = true
    @AppStorage(CloudStatus.refreshKey) private var refresh = 2.0

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label("Show cloud status icons", systemImage: "icloud")
                Text("Next to each file in OneDrive, Google Drive, Dropbox or iCloud Drive: only in the cloud, downloading, uploading or with an error, like Finder.")
            }
            Toggle(isOn: $showDownloaded) {
                Label("Also mark downloaded files", systemImage: "checkmark.icloud")
                Text("Finder shows nothing on files that are already on this Mac.")
            }
            .disabled(!enabled)
            if !enabled { DisabledReason("Turn on “Show cloud status icons” to use this.") }
            LabeledContent {
                Slider(value: $refresh, in: 0.5...10, step: 0.5).frame(width: 160)
                Text(verbatim: String(format: "%.1f s", refresh)).monospacedDigit().frame(width: 44)
            } label: {
                Label("Refresh every", systemImage: "arrow.clockwise")
                Text("How often the status of visible files is checked again.")
            }
            .disabled(!enabled)
            Toggle(isOn: $menuActions) {
                Label("“Download Now” and “Remove Download” in the right-click menu", systemImage: "icloud.and.arrow.down")
                Text("Only on cloud files. Removing the download frees space; the file stays in the cloud.")
            }
            CloudStatusPreview(enabled: enabled, showDownloaded: showDownloaded, menuActions: menuActions)
        } header: {
            Text("Cloud Files")
        } footer: {
            Text("Turned off, cloud folders look like normal folders, as before.")
        }
    }
}

struct CloudStatusPreview: View {
    let enabled: Bool
    let showDownloaded: Bool
    let menuActions: Bool
    private let rows: [(String, CloudItemState)] = [
        ("Informe.docx", .cloudOnly), ("Fotos.zip", .downloading), ("Notas.txt", .uploading),
        ("Presupuesto.xlsx", .downloaded), ("Copia.pdf", .error)
    ]

    var body: some View {
        SettingsPreviewBox(title: "Preview: a OneDrive folder") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows, id: \.0) { name, state in
                        HStack(spacing: 6) {
                            Image(systemName: "doc").foregroundStyle(.secondary)
                            Text(verbatim: name).font(.callout)
                            if enabled, state != .downloaded || showDownloaded {
                                Image(systemName: state.symbol).font(.system(size: 11)).foregroundStyle(state.color)
                                Text(state.title).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                if menuActions {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Right-click on “Informe.docx”").font(.caption2).foregroundStyle(.secondary)
                        Label("Download Now", systemImage: "icloud.and.arrow.down").font(.callout)
                        Text("Right-click on “Presupuesto.xlsx”").font(.caption2).foregroundStyle(.secondary)
                        Label("Remove Download", systemImage: "icloud.slash").font(.callout)
                    }
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}
