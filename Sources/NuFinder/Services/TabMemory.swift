import AppKit
import Foundation
import SwiftUI

/// Fork: cuánta RAM puede usar Explorer para ir más rápido (carpetas ya leídas y miniaturas).
/// Prioriza la rapidez, pero lo que deja de usarse se libera: al cerrar pestañas o ventanas,
/// al salir una carpeta del historial, al pasarse del presupuesto y cuando macOS pide memoria.
enum MemoryBudget {
    /// Presupuesto total en MB (0 = automático según la RAM del Mac).
    static let budgetKey = "memory.budgetMB"
    /// Miniaturas con parte del presupuesto (apagado = 300 miniaturas / 96 MB, como el original).
    static let thumbnailsKey = "memory.bigThumbnailCache"

    static var physicalMB: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_048_576) }
    /// Automático: 4 % de la RAM, entre 256 MB y 4 GB (48 GB → ~1,9 GB).
    static func automaticMB(physical: Int = physicalMB) -> Int { min(4096, max(256, physical * 4 / 100)) }

    static var totalMB: Int {
        let stored = UserDefaults.standard.integer(forKey: budgetKey)
        return stored > 0 ? stored : automaticMB()
    }
    static var bigThumbnails: Bool {
        UserDefaults.standard.object(forKey: thumbnailsKey) == nil || UserDefaults.standard.bool(forKey: thumbnailsKey)
    }
    /// Mitad para carpetas y mitad para miniaturas (o todo para carpetas sin miniaturas grandes).
    static var folderBytes: Int { totalMB * 1_048_576 / (bigThumbnails ? 2 : 1) }
    static var thumbnailBytes: Int { bigThumbnails ? totalMB * 1_048_576 / 2 : 96 * 1_048_576 }
    static var thumbnailCount: Int { bigThumbnails ? 0 : 300 } // 0 = sin límite de cantidad, solo de tamaño
}

/// Memoria de carpetas de una ventana. Cada pestaña guarda su carpeta actual y las de su
/// historial (atrás/adelante instantáneos). Se libera sola al cerrarse la ventana.
final class TabMemory {
    static let enabledKey = "tabs.keepInMemory"
    static let historyKey = "tabs.historyInMemory"

    static var isEnabled: Bool { flag(enabledKey) }
    static var keepsHistory: Bool { flag(historyKey) }
    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key)
    }

    private let store: FolderMemoryStore
    private var tabs: Set<UUID> = []
    private var showing: (url: URL, hidden: Bool)?

    init(store: FolderMemoryStore = .shared) { self.store = store }
    deinit { for tab in tabs { store.forget(tab: tab) } }

    func stored(_ tab: UUID) -> Bool { store.has(tab: tab) }

    /// Archivos guardados de esta carpeta en esta pestaña (y la marca como «en pantalla»).
    func restore(tab: UUID, url: URL, hidden: Bool, enabled: Bool = TabMemory.isEnabled) -> [FileItem]? {
        guard enabled else { clearAll(); return nil }
        guard !isShowing(url, hidden: hidden, enabled: enabled),
              let items = store.items(tab: tab, url: url, hidden: hidden) else { return nil }
        shown(url, hidden: hidden)
        return items
    }

    /// Guarda lo leído y suelta las carpetas que ya no están en el historial de la pestaña.
    func save(tab: UUID, url: URL, hidden: Bool, items: [FileItem], history: [URL],
              enabled: Bool = TabMemory.isEnabled, keepsHistory: Bool = TabMemory.keepsHistory,
              budget: Int = MemoryBudget.folderBytes) {
        guard enabled else { clearAll(); return }
        tabs.insert(tab)
        store.save(tab: tab, url: url, hidden: hidden, items: items)
        let keep = keepsHistory ? Set(history.map(\.standardizedFileURL)).union([url.standardizedFileURL]) : [url.standardizedFileURL]
        store.prune(tab: tab, keeping: keep)
        store.trim(to: budget)
    }

    func forget(_ tab: UUID) { tabs.remove(tab); store.forget(tab: tab) }
    func discard(tab: UUID, url: URL) { store.discard(tab: tab, url: url) }

    func shown(_ url: URL, hidden: Bool) { showing = (url.standardizedFileURL, hidden) }
    func clearShown() { showing = nil }
    func isShowing(_ url: URL, hidden: Bool, enabled: Bool = TabMemory.isEnabled) -> Bool {
        guard enabled, let showing else { return false }
        return showing.url == url.standardizedFileURL && showing.hidden == hidden
    }

    private func clearAll() {
        for tab in tabs { store.forget(tab: tab) }
        tabs.removeAll()
    }
}

/// Almacén común a todas las ventanas: un solo presupuesto, se descarta lo usado hace más tiempo.
final class FolderMemoryStore: ObservableObject {
    nonisolated(unsafe) static let shared = FolderMemoryStore() // se usa solo desde el hilo principal

    private struct Key: Hashable { let tab: UUID; let url: URL; let hidden: Bool }
    private struct Entry { let items: [FileItem]; let bytes: Int; var used: UInt64 }
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    @Published private(set) var usedBytes = 0
    @Published private(set) var folderCount = 0
    private var pressure: DispatchSourceMemoryPressure?

    init(watchPressure: Bool = true) {
        guard watchPressure else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in self?.clear() } // macOS pide memoria: se suelta todo
        source.resume()
        pressure = source
        // Al cerrar una ventana se sueltan sus carpetas ya, sin esperar a que su modelo se destruya
        // (SwiftUI puede retenerlo un rato y la RAM no volvía).
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard let browser = KeyWindowFocus.shared.browser(for: window) else { return }
                for tab in browser.tabs { browser.tabMemory.forget(tab.id) }
                browser.tabMemory.clearShown()
            }
        }
    }

    /// Cálculo aproximado de lo que ocupa una carpeta en RAM.
    static func estimate(_ items: [FileItem]) -> Int {
        items.reduce(0) { $0 + 400 + $1.url.path.utf8.count + $1.name.utf8.count + $1.kind.utf8.count }
    }

    func has(tab: UUID) -> Bool { entries.keys.contains { $0.tab == tab } }

    func items(tab: UUID, url: URL, hidden: Bool) -> [FileItem]? {
        let key = Key(tab: tab, url: url.standardizedFileURL, hidden: hidden)
        guard var entry = entries[key] else { return nil }
        clock += 1; entry.used = clock; entries[key] = entry
        return entry.items
    }

    func save(tab: UUID, url: URL, hidden: Bool, items: [FileItem]) {
        clock += 1
        let url = url.standardizedFileURL
        entries[Key(tab: tab, url: url, hidden: !hidden)] = nil // la otra versión (con/sin ocultos) ya no sirve
        entries[Key(tab: tab, url: url, hidden: hidden)] = Entry(items: items, bytes: Self.estimate(items), used: clock)
        recount()
    }

    func prune(tab: UUID, keeping urls: Set<URL>) {
        entries = entries.filter { $0.key.tab != tab || urls.contains($0.key.url) }
        recount()
    }

    func trim(to budget: Int) {
        while usedBytes > budget, entries.count > 1,
              let oldest = entries.min(by: { $0.value.used < $1.value.used })?.key {
            entries[oldest] = nil
            recount()
        }
    }

    func forget(tab: UUID) {
        entries = entries.filter { $0.key.tab != tab }
        recount()
    }

    func clear() { entries.removeAll(); recount() }

    func discard(tab: UUID, url: URL) {
        let url = url.standardizedFileURL
        entries = entries.filter { $0.key.tab != tab || $0.key.url != url }
        recount()
    }

    private func recount() {
        usedBytes = entries.values.reduce(0) { $0 + $1.bytes }
        folderCount = entries.count
    }
}

/// Ajustes → Inicio → Pestañas: memoria de carpetas y miniaturas.
struct TabMemorySection: View {
    @AppStorage(TabMemory.enabledKey) private var enabled = true
    @AppStorage(TabMemory.historyKey) private var history = true
    @AppStorage(MemoryBudget.budgetKey) private var budgetMB = 0
    @AppStorage(MemoryBudget.thumbnailsKey) private var bigThumbnails = true
    @ObservedObject private var store = FolderMemoryStore.shared

    private var effectiveMB: Int { budgetMB > 0 ? budgetMB : MemoryBudget.automaticMB() }

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label("Keep tabs in memory", systemImage: "memorychip")
                Text("Switching back to a tab shows its files instantly and refreshes them in the background. Closing the tab frees the memory.")
            }
            Toggle(isOn: $history) {
                Label("Also keep the folders of each tab’s history", systemImage: "arrow.uturn.backward")
                Text("Back and Forward show the folder instantly. A folder is freed when it leaves the history.")
            }
            .disabled(!enabled)
            if !enabled { DisabledReason("Turn on “Keep tabs in memory” to use this.") }
            Toggle(isOn: $bigThumbnails) {
                Label("Use the memory for image thumbnails too", systemImage: "photo.stack")
                Text("Half of the memory keeps thumbnails so they don’t have to be made again. Off: 300 thumbnails (96 MB), as before. Applies the next time Explorer opens.")
            }
            LabeledContent {
                Picker("", selection: $budgetMB) {
                    Text("Automatic (\(MemoryBudget.automaticMB()) MB)").tag(0)
                    ForEach([512, 1024, 2048, 4096, 8192], id: \.self) { Text(verbatim: "\($0 >= 1024 ? "\($0 / 1024) GB" : "\($0) MB")").tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            } label: {
                Label("Memory for speed", systemImage: "gauge.with.dots.needle.67percent")
                Text("This Mac has \(MemoryBudget.physicalMB / 1024) GB. Automatic uses 4 %. When it fills up, what was used longest ago is freed; if macOS needs memory, everything is freed.")
            }
            MemoryUsagePreview(enabled: enabled, usedBytes: store.usedBytes, folders: store.folderCount,
                               budgetBytes: effectiveMB * 1_048_576 / (bigThumbnails ? 2 : 1))
        } header: {
            Text("Switching Tabs")
        } footer: {
            Text("Turned off, every tab switch reads the folder again and shows the loading indicator, as before.")
        }
    }
}

/// Vista previa: la barra de memoria en uso de verdad y qué pasa al volver a una pestaña.
struct MemoryUsagePreview: View {
    let enabled: Bool
    let usedBytes: Int
    let folders: Int
    let budgetBytes: Int

    private func format(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory) }

    var body: some View {
        SettingsPreviewBox(title: "Preview: memory in use right now") {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(Color.accentColor)
                            .frame(width: max(4, geo.size.width * min(1, Double(usedBytes) / Double(max(1, budgetBytes)))))
                    }
                }
                .frame(height: 8)
                Text("\(folders) folders · \(format(usedBytes)) of \(format(budgetBytes))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Label(enabled ? "Going back to a tab or folder: shown instantly" : "Going back to a tab: loads again (about 1 s)",
                      systemImage: enabled ? "bolt.fill" : "hourglass")
                    .font(.caption)
                    .foregroundStyle(enabled ? Color.green : Color.orange)
            }
            .opacity(enabled ? 1 : 0.5)
        }
    }
}
