import Foundation
import SwiftUI

/// Fork: guarda en memoria lo que muestra cada pestaña. Al volver a ella se ve al instante
/// y se actualiza en segundo plano; al cerrarla (o al cerrar la ventana) se libera.
/// Apagado = como el original: cada cambio de pestaña vuelve a leer la carpeta.
final class TabMemory {
    static let enabledKey = "tabs.keepInMemory"
    /// Cuántas pestañas se guardan como máximo; se descarta la usada hace más tiempo.
    static let limitKey = "tabs.memoryLimit"
    static let defaultLimit = 10

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil || UserDefaults.standard.bool(forKey: enabledKey)
    }
    static var limit: Int {
        let value = UserDefaults.standard.integer(forKey: limitKey)
        return value > 0 ? value : defaultLimit
    }

    private struct Entry { let url: URL; let hidden: Bool; let items: [FileItem] }
    private var entries: [UUID: Entry] = [:]
    private var recent: [UUID] = []

    func stored(_ tab: UUID) -> Bool { entries[tab] != nil }

    /// Guarda la pestaña que se deja y devuelve lo guardado de la que se abre (si sigue siendo la misma carpeta).
    func swap(leaving old: UUID, url oldURL: URL, items: [FileItem],
              entering new: UUID, url newURL: URL, hidden: Bool,
              enabled: Bool = TabMemory.isEnabled, limit: Int = TabMemory.limit) -> [FileItem]? {
        guard enabled else { clear(); return nil }
        if old != new, !items.isEmpty {
            entries[old] = Entry(url: oldURL, hidden: hidden, items: items)
            touch(old)
        }
        while recent.count > max(1, limit) { entries[recent.removeFirst()] = nil }
        guard let entry = entries[new], entry.url == newURL, entry.hidden == hidden else { return nil }
        touch(new)
        return entry.items
    }

    func forget(_ tab: UUID) {
        entries[tab] = nil
        recent.removeAll { $0 == tab }
    }

    func clear() { entries.removeAll(); recent.removeAll() }

    private func touch(_ tab: UUID) {
        recent.removeAll { $0 == tab }
        recent.append(tab)
    }
}

/// Ajustes → Inicio → Pestañas: guardar las pestañas en memoria.
struct TabMemorySection: View {
    @AppStorage(TabMemory.enabledKey) private var enabled = true
    @AppStorage(TabMemory.limitKey) private var limit = TabMemory.defaultLimit

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label("Keep tabs in memory", systemImage: "memorychip")
                Text("Switching back to a tab shows its files instantly and refreshes them in the background. Closing the tab frees the memory.")
            }
            Stepper(value: $limit, in: 1...50) {
                Label("Tabs kept in memory: \(limit)", systemImage: "square.stack.3d.up")
                Text("When there are more, the one used longest ago is reloaded from disk.")
            }
            .disabled(!enabled)
            if !enabled { DisabledReason("Turn on “Keep tabs in memory” to use this.") }
            TabMemoryPreview(enabled: enabled)
        } header: {
            Text("Switching Tabs")
        } footer: {
            Text("Turned off, every tab switch reads the folder again and shows the loading indicator, as before.")
        }
    }
}

struct TabMemoryPreview: View {
    let enabled: Bool

    var body: some View {
        SettingsPreviewBox(title: "Preview: going back to the “Documents” tab") {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(verbatim: "Documents").font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
                        Text(verbatim: "Downloads").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                    }
                    ZStack {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(["Informe.pdf", "Notas.txt", "Fotos"], id: \.self) { name in
                                Label { Text(verbatim: name).font(.callout) } icon: {
                                    Image(systemName: name == "Fotos" ? "folder" : "doc").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .opacity(enabled ? 1 : 0.25)
                        if !enabled { ProgressView().controlSize(.small) }
                    }
                    .frame(width: 170, height: 64, alignment: .leading)
                }
                Label(enabled ? "Shown instantly" : "Loads again (about 1 s)",
                      systemImage: enabled ? "bolt.fill" : "hourglass")
                    .font(.caption)
                    .foregroundStyle(enabled ? Color.green : Color.orange)
            }
        }
    }
}
