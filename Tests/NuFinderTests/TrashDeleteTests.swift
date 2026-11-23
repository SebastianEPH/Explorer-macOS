import AppKit
import Testing
@testable import NuFinder

/// Borrar dentro de la Papelera. Se usa una «papelera» falsa en una carpeta temporal:
/// las pruebas nunca tocan la Papelera de verdad.
@Suite(.serialized) @MainActor
struct TrashDeleteTests {
    private func fakeTrash() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FakeTrash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // Unitaria: qué cuenta como «dentro de la Papelera»; apagado por defecto, encendido en los míos.
    @Test func insideTrash() throws {
        let root = try fakeTrash()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(TrashDelete.isInsideTrash(root.appendingPathComponent("a.txt"), roots: [root]))
        #expect(TrashDelete.isInsideTrash(root.appendingPathComponent("carpeta/b.txt"), roots: [root]))
        #expect(!TrashDelete.isInsideTrash(root, roots: [root]), "la Papelera misma no")
        #expect(!TrashDelete.isInsideTrash(URL(fileURLWithPath: "/tmp/otra.txt"), roots: [root]))
        #expect(!UserDefaults(suiteName: "TD.\(UUID().uuidString)")!.bool(forKey: TrashDelete.key))
        #expect(DefaultSettings.mine[TrashDelete.key] as? Bool == true)
    }

    // Flujo: abrir la Papelera → seleccionar → ⌘⌫ (moveSelectionToTrash) → aviso → «Borrar» → ya no está.
    // Sin el arreglo, recycle decía «hecho» y el archivo seguía ahí.
    @Test func deleteInsideTrashFlow() async throws {
        let root = try fakeTrash()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("borrar.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let oldRoots = TrashDelete.trashRoots, oldConfirm = TrashDelete.confirm
        let wasOn = UserDefaults.standard.object(forKey: TrashDelete.key)
        defer {
            TrashDelete.trashRoots = oldRoots; TrashDelete.confirm = oldConfirm
            UserDefaults.standard.set(wasOn, forKey: TrashDelete.key)
        }
        TrashDelete.trashRoots = { [root] }
        var asked = 0
        UserDefaults.standard.set(true, forKey: TrashDelete.key)
        let defaults = UserDefaults(suiteName: "TD.\(UUID().uuidString)")!
        let browser = BrowserModel(initialURL: root, restoresSession: false, defaults: defaults)

        // Cancelar: no se borra nada.
        TrashDelete.confirm = { _ in asked += 1; return false }
        browser.selection = [file]
        browser.moveSelectionToTrash()
        #expect(asked == 1 && FileManager.default.fileExists(atPath: file.path))

        TrashDelete.confirm = { _ in asked += 1; return true }
        browser.moveSelectionToTrash()
        #expect(asked == 2, "pide confirmación")
        #expect(!FileManager.default.fileExists(atPath: file.path), "borrado para siempre")
        #expect(browser.selection.isEmpty)
    }

    // Flujo: fuera de la Papelera no cambia nada (no pregunta, sigue el camino de siempre).
    @Test func outsideTrashUntouched() throws {
        let root = try fakeTrash()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldRoots = TrashDelete.trashRoots
        defer { TrashDelete.trashRoots = oldRoots }
        TrashDelete.trashRoots = { [root.appendingPathComponent("NoEs")] }
        let defaults = UserDefaults(suiteName: "TD.\(UUID().uuidString)")!
        let browser = BrowserModel(initialURL: root, restoresSession: false, defaults: defaults)
        #expect(!TrashDelete.handle([root.appendingPathComponent("x.txt")], model: browser))
    }
}
