import AppKit
import SwiftUI
import Testing
@testable import NuFinder

/// Esquina inferior izquierda para redimensionar, botones de vista quitados, expulsar discos y paralelismo.
@Suite(.serialized) @MainActor
struct WindowEdgeAndEjectTests {
    private func spin(_ seconds: Double = 0.3) async throws {
        _ = NSApplication.shared
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    // Unitaria: los bordes izquierdo, derecho e inferior son zona de redimensionar; el centro no.
    @Test func resizeZone() {
        let size = NSSize(width: 800, height: 600)
        #expect(TableMarquee.isResizeZone(NSPoint(x: 2, y: 2), windowSize: size))
        #expect(TableMarquee.isResizeZone(NSPoint(x: 798, y: 3), windowSize: size))
        #expect(TableMarquee.isResizeZone(NSPoint(x: 400, y: 4), windowSize: size))
        #expect(!TableMarquee.isResizeZone(NSPoint(x: 400, y: 300), windowSize: size))
    }

    /// Ventana redimensionable con una tabla que llega hasta las esquinas, y el monitor del recuadro.
    private func tableWindow() async throws -> (NSWindow, TableMarqueeInstaller.InstallerView, NSTableView) {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let table = NSTableView(frame: content.bounds)
        table.addTableColumn(NSTableColumn(identifier: .init("name")))
        table.addTableColumn(NSTableColumn(identifier: .init("kind")))
        table.tableColumns[0].width = 150
        table.tableColumns[1].width = 240
        let scroll = NSScrollView(frame: content.bounds)
        scroll.documentView = table
        content.addSubview(scroll)
        let installer = TableMarqueeInstaller.InstallerView(frame: content.bounds)
        content.addSubview(installer)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        try await spin()
        return (window, installer, table)
    }

    private func mouseDown(_ point: NSPoint, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    // Completa (el fallo): con la tabla llegando a la esquina inferior, el clic de redimensionar
    // tiene que llegar a la ventana; antes el recuadro se lo quedaba (devolvía nil).
    @Test func cornerClickReachesWindow() async throws {
        let (window, installer, _) = try await tableWindow()
        defer { window.close() }
        #expect(installer.handle(try mouseDown(NSPoint(x: 3, y: 3), in: window)) != nil, "esquina inferior izquierda")
        #expect(installer.handle(try mouseDown(NSPoint(x: 397, y: 3), in: window)) != nil, "esquina inferior derecha")
        #expect(installer.handle(try mouseDown(NSPoint(x: 200, y: 3), in: window)) != nil, "borde inferior")
    }

    // Flujo: el recuadro sigue funcionando lejos de los bordes (columna Tipo, centro de la ventana).
    @Test func marqueeStillStartsInside() async throws {
        let (window, installer, table) = try await tableWindow()
        defer { window.close() }
        let rows = Rows()
        table.dataSource = rows
        table.reloadData()
        try await spin()
        let point = table.convert(NSPoint(x: 300, y: table.rect(ofRow: 1).midY), to: nil)
        #expect(installer.handle(try mouseDown(point, in: window)) == nil, "un clic en la columna Tipo empieza el recuadro")
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        _ = installer.handle(up)
    }

    // Unitaria: los botones de vista de arriba se quitaron de raíz y sus claves se borran.
    @Test func topViewButtonsRemoved() {
        let d = UserDefaults(suiteName: "VMB.\(UUID().uuidString)")!
        d.set(true, forKey: "toolbar.viewButtons")
        d.set(false, forKey: "toolbar.viewButtons.showsCompact")
        RemovedFeatures.cleanDefaults(d)
        #expect(d.object(forKey: "toolbar.viewButtons") == nil && d.object(forKey: "toolbar.viewButtons.showsCompact") == nil)
        #expect(DefaultSettings.mine["toolbar.viewButtons"] == nil && DefaultSettings.mine["toolbar.viewButtons.showsCompact"] == nil)
        #expect(DefaultSettings.mine[LayoutSettings.roundedTabsKey] as? Bool == true)
        #expect(DefaultSettings.mine[StatusBarSettings.viewButtonsKey] as? Bool != false, "los de abajo siguen")
    }

    // Unitaria: tamaños en paralelo. Sin tocar nada = 2 (original); automático = mitad de núcleos.
    @Test func folderSizeParallel() {
        #expect(FolderSizeParallel.count(setting: nil, cores: 18) == 2)
        #expect(FolderSizeParallel.count(setting: 0, cores: 18) == 9)
        #expect(FolderSizeParallel.count(setting: 0, cores: 2) == 2)
        #expect(FolderSizeParallel.count(setting: 8, cores: 18) == 8)
        #expect(DefaultSettings.mine[FolderSizeParallel.key] as? Int == 0)
        #expect(DefaultSettings.mine[VolumeEject.retriesKey] as? Int == 3)
    }

    // Flujo: el disco está «en uso» las dos primeras veces → se reintenta y se expulsa; y en segundo plano.
    @Test func ejectRetriesWhenBusy() async throws {
        final class Box: @unchecked Sendable { var calls = 0; var onMain = false }
        let box = Box()
        let old = VolumeEject.ejector
        defer { VolumeEject.ejector = old }
        let target = URL(fileURLWithPath: "/Volumes/PruebaExplorer-\(UUID().uuidString)")
        VolumeEject.ejector = { url in
            guard url == target else { return }
            box.calls += 1
            if Thread.isMainThread { box.onMain = true }
            if box.calls < 3 { throw CocoaError(.fileWriteNoPermission) }
        }
        try await VolumeEject.eject(target, attempts: 3, pause: .milliseconds(10))
        #expect(box.calls == 3)
        #expect(!box.onMain, "no congela la ventana")

        box.calls = 0
        await #expect(throws: (any Error).self) {
            try await VolumeEject.eject(target, attempts: 1, pause: .milliseconds(10))
        }
        #expect(box.calls == 1, "1 intento = original")
    }

    final class Rows: NSObject, NSTableViewDataSource {
        func numberOfRows(in tableView: NSTableView) -> Int { 20 }
        func tableView(_ t: NSTableView, objectValueFor c: NSTableColumn?, row: Int) -> Any? { "fila \(row)" }
    }

    // Completa (el fallo): doble clic en una fila fuera de la columna Nombre (Tipo, Tamaño, Fecha)
    // tiene que llegar a la tabla para abrir la carpeta; antes el recuadro se lo quedaba.
    @Test func doubleClickOnRowReachesTable() async throws {
        let (window, installer, table) = try await tableWindow()
        defer { window.close() }
        let rows = Rows()
        table.dataSource = rows
        table.reloadData()
        try await spin()
        let rect = table.rect(ofRow: 1)
        let point = table.convert(NSPoint(x: 300, y: rect.midY), to: nil)
        #expect(table.row(at: table.convert(point, from: nil)) == 1)
        let double = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 2, pressure: 1))
        #expect(installer.handle(double) != nil, "el doble clic llega a la tabla (doubleAction = abrir)")
    }
}
