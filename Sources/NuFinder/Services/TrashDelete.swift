import AppKit
import SwiftUI

/// Fork: dentro de la Papelera, «Mover a la Papelera» (⌘⌫, menú, clic derecho) no hacía nada:
/// `NSWorkspace.recycle` no puede mover a la Papelera lo que ya está en ella. Ahora, si todo
/// lo seleccionado está dentro de la Papelera, se ofrece borrarlo para siempre (con aviso).
/// Apagado (`trash.deleteInside`) = comportamiento original.
enum TrashDelete {
    static let key = "trash.deleteInside"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Papeleras: la de la carpeta personal y las `.Trashes` de otros discos.
    nonisolated(unsafe) static var trashRoots: () -> [URL] = {
        [SidebarExtras.trashURL] + (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]) ?? []).map { $0.appendingPathComponent(".Trashes", isDirectory: true) }
    }

    static func isInsideTrash(_ url: URL, roots: [URL] = trashRoots()) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            return path.hasPrefix(rootPath + "/") && path != rootPath
        }
    }

    /// Confirmación; se sustituye en pruebas.
    nonisolated(unsafe) static var confirm: @MainActor (Int) -> Bool = { count in
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete \(count) items permanently?")
        alert.informativeText = String(localized: "They are already in the Trash. This can’t be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Delete Permanently"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Devuelve true si se ocupó (todo estaba en la Papelera); false = sigue el camino original.
    @MainActor
    static func handle(_ urls: [URL], model: BrowserModel) -> Bool {
        guard isOn, !urls.isEmpty, urls.allSatisfy({ isInsideTrash($0) }) else { return false }
        guard confirm(urls.count) else { return true }
        var failed: [String] = []
        for url in urls {
            do { try FileManager.default.removeItem(at: url) } catch { failed.append(error.localizedDescription) }
        }
        model.selection.subtract(urls)
        model.reload()
        if let first = failed.first {
            model.errorMessage = String(localized: "Couldn’t delete from the Trash: \(first). Explorer may need Full Disk Access (Settings → System).")
        }
        return true
    }
}

struct TrashDeleteToggle: View {
    @AppStorage(TrashDelete.key) private var on = false

    var body: some View {
        Toggle(isOn: $on) {
            Label("Delete permanently inside the Trash", systemImage: "trash.slash")
            Text("Inside the Trash, ⌘⌫ and “Move to Trash” delete the selected items for good (asks first). Off: they do nothing there, as before.")
        }
        HStack(spacing: 6) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Image(systemName: on ? "xmark.bin.fill" : "nosign").foregroundStyle(on ? Color.red : Color.secondary)
        }
        .accessibilityHidden(true)
    }
}
