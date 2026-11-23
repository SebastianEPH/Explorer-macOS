import AppKit
import SwiftUI
import Testing
@testable import NuFinder

/// Barra de arriba con la ventana de verdad: botones de vista con icono y sin galería.
@Suite(.serialized) @MainActor
struct ViewModeButtonsTests {
    private func spin(_ seconds: Double = 0.5) async throws {
        _ = NSApplication.shared
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    @Test func defaultsAreOriginal() {
        #expect(!UserDefaults(suiteName: "VMB.\(UUID().uuidString)")!.bool(forKey: ViewModeButtons.key))
        #expect(DefaultSettings.mine[ViewModeButtons.key] as? Bool == true)
    }

    /// Clic de ratón en un punto de la ventana (bajar y subir).
    private func click(_ point: NSPoint, in window: NSWindow) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
            try await spin(0.1)
        }
    }

    // Los tres botones en una ventana de verdad: cada clic elige su vista, también los repetidos.
    @Test func eachButtonChoosesItsView() async throws {
        var chosen: [FileViewMode] = []
        let host = NSHostingView(rootView: ViewModeButtonRow(selected: .list) { chosen.append($0) })
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 120, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await spin()
        let width = host.fittingSize.width
        #expect(abs(width - (29 * 3 + 6)) < 2, "tres botones de icono juntos, sin texto: ancho \(width)")
        let y = host.bounds.midY
        let x0 = (host.bounds.width - width) / 2
        for index in [2, 0, 1, 1, 2] {
            try await click(host.convert(NSPoint(x: x0 + 14.5 + CGFloat(index) * 32, y: y), to: nil), in: window)
        }
        #expect(chosen == [.icons, .list, .compact, .compact, .icons], "\(chosen)")
    }

    @Test func compactButtonAndRoundedTabsDefaults() {
        let d = UserDefaults(suiteName: "VMB.\(UUID().uuidString)")!
        #expect(d.object(forKey: ViewModeButtons.showsCompactKey) == nil && d.object(forKey: LayoutSettings.roundedTabsKey) == nil,
                "sin tocar nada: tres botones y borde recto, como antes")
        #expect(DefaultSettings.mine[ViewModeButtons.showsCompactKey] as? Bool == false)
        #expect(DefaultSettings.mine[LayoutSettings.roundedTabsKey] as? Bool == true)
        #expect(ViewModeButtons.modes(showsCompact: false) == [.list, .icons])
        #expect(ViewModeButtons.modes(showsCompact: true) == [.list, .compact, .icons])
    }

    // Flujo: quitar el botón compacto → solo dos botones (Lista e Iconos) y cada clic elige el suyo.
    @Test func twoButtonsWithoutCompact() async throws {
        var chosen: [FileViewMode] = []
        let host = NSHostingView(rootView: ViewModeButtonRow(selected: .list, showsCompact: false) { chosen.append($0) })
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 120, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await spin()
        let width = host.fittingSize.width
        #expect(abs(width - (29 * 2 + 3)) < 2, "dos botones: ancho \(width)")
        let x0 = (host.bounds.width - width) / 2
        for index in [1, 0, 1] {
            try await click(host.convert(NSPoint(x: x0 + 14.5 + CGFloat(index) * 32, y: host.bounds.midY), to: nil), in: window)
        }
        #expect(chosen == [.icons, .list, .icons], "\(chosen)")
    }
}
