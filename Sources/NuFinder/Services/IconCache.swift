import AppKit
import SwiftUI

/// Fork: iconos ya dibujados en memoria. `NSWorkspace.icon(forFile:)` devuelve una imagen con
/// todos los tamaños sin dibujar y SwiftUI la rasterizaba en cada redibujo (~2,6 ms por icono:
/// al moverse por una carpeta de 58 archivos iba a tirones). Aquí se dibuja una vez por tipo y
/// tamaño. Apagado = como el original.
enum IconCache {
    static let enabledKey = "files.iconCache"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil || UserDefaults.standard.bool(forKey: enabledKey)
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 128 * 1_048_576 // NSCache además suelta solo si macOS pide memoria
        return cache
    }()

    /// Archivos normales comparten el icono de su tipo; carpetas, apps, paquetes y alias
    /// pueden tener uno propio y van por ruta.
    static func key(for item: FileItem, pixels: Int) -> String {
        let ext = item.url.pathExtension.lowercased()
        let ownIcon = item.isDirectory || item.isSymbolicLink || ext.isEmpty || ["app", "icns", "webloc", "alias"].contains(ext)
        return "\(ownIcon ? "path:" + item.url.path : "ext:" + ext)@\(pixels)"
    }

    static func icon(for item: FileItem, size: CGFloat, enabled: Bool = IconCache.isEnabled) -> NSImage {
        guard enabled else { return item.icon }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int(size * scale)
        let key = key(for: item, pixels: pixels) as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = rendered(item.icon, size: size, scale: scale)
        cache.setObject(image, forKey: key, cost: pixels * pixels * 4)
        return image
    }

    /// Dibuja el icono una sola vez en un mapa de bits del tamaño exacto en pantalla.
    static func rendered(_ source: NSImage, size: CGFloat, scale: CGFloat) -> NSImage {
        let pixels = max(1, Int(size * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return source }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }

    static func clear() { cache.removeAllObjects() }
}

/// Ajustes → Archivos → Iconos y selección: iconos ya dibujados.
struct IconCacheSection: View {
    @AppStorage(IconCache.enabledKey) private var enabled = true

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Label("Keep icons drawn in memory", systemImage: "bolt.horizontal")
                Text("Each icon is drawn once per file type and size, so moving through a folder and scrolling stay smooth. Off: every redraw draws the icons again, as before.")
            }
            IconCachePreview(enabled: enabled)
        } header: {
            Text("Smooth Scrolling")
        }
    }
}

struct IconCachePreview: View {
    let enabled: Bool
    private let names = ["Informe.pdf", "Fotos.zip", "Datos.xlsx", "Programa.apk", "Notas.txt"]

    var body: some View {
        SettingsPreviewBox(title: "Preview: icons drawn per redraw") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    ForEach(names, id: \.self) { name in
                        VStack(spacing: 3) {
                            Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: (name as NSString).pathExtension) ?? .data))
                                .resizable().frame(width: 32, height: 32)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: enabled ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill")
                                        .font(.system(size: 11)).foregroundStyle(enabled ? .green : .orange)
                                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                                }
                            Text(verbatim: name).font(.caption2).lineLimit(1)
                        }
                    }
                }
                Label(enabled ? "Drawn once and reused: about 0.4 ms for 58 files" : "Drawn again on every redraw: about 50–150 ms for 58 files (stutters)",
                      systemImage: enabled ? "hare.fill" : "tortoise.fill")
                    .font(.caption)
                    .foregroundStyle(enabled ? Color.green : Color.orange)
            }
        }
    }
}
