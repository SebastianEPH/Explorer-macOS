import AppKit
import SwiftUI
import Testing
@testable import NuFinder

/// Fork: genera los PNG del icono oficial del .app desde un diseño de AppIconService.
/// Solo se ejecuta con EXPORT_ICON_DIR (ver Scripts/export_app_icon.sh); en las pruebas normales no hace nada.
struct ExportAppIconTests {
    @Test @MainActor func exportAppIcon() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["EXPORT_ICON_DIR"] else { return }
        let id = env["EXPORT_ICON_ID"] ?? "window-square"
        let background = env["EXPORT_ICON_BACKGROUND"] == "1"
        let margin = Double(env["EXPORT_ICON_MARGIN"] ?? "") ?? AppIconService.defaultMargin
        let design = try #require(AppIconDesign.all.first { $0.id == id })
        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let pixels = CGFloat(points * scale)
            let renderer = ImageRenderer(content: AppIconArt(design: design, dark: false, background: background, margin: margin)
                .frame(width: pixels, height: pixels))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let rep = NSBitmapImageRep(cgImage: image)
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }
}
