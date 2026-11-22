import AppKit
import SwiftUI

/// Fork: iconos alternativos para Explorer (Ajustes → Apariencia → Icono de la app).
///
/// Diseños propios hechos con formas (sin SF Symbols, que Apple no permite en iconos de apps).
/// Cada uno tiene versión clara y oscura y cambia solo con el modo de macOS. Se aplica al Dock y a
/// ⌘Tab mientras Explorer está abierto; no se toca el .app para no romper la firma (y los permisos).
enum AppIconService {
    static let key = "appearance.appIcon"   // "" = original

    @MainActor private static var observer: NSKeyValueObservation?

    @MainActor
    static func start() {
        apply()
        observer = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in apply() }
        }
    }

    @MainActor
    static func apply() {
        let id = UserDefaults.standard.string(forKey: key) ?? ""
        guard let design = AppIconDesign.all.first(where: { $0.id == id }) else {
            NSApp.applicationIconImage = nil // vuelve al icono original del .app
            return
        }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSApp.applicationIconImage = image(design, dark: dark, size: 512)
    }

    @MainActor
    static func image(_ design: AppIconDesign, dark: Bool, size: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconArt(design: design, dark: dark).frame(width: size, height: size))
        renderer.scale = 2
        return renderer.nsImage
    }
}

/// Un diseño de icono: fondo y dibujo, en claro y en oscuro.
/// Todos parten de los dos que eligió el usuario: «Ventana» y «Mosaico».
struct AppIconDesign: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let light: [Color]
    let dark: [Color]
    let glyph: Glyph

    enum WindowContent { case list, icons, columns, split, tabs, stacked, gallery, search }
    enum TilesLayout { case grid2, grid3, bento, circles, folder, diagonal }

    enum Glyph {
        /// Ventana de Mac con barra lateral. `tint` = color de las carpetas; `darkWindow` = ventana oscura también en modo claro.
        case window(WindowContent, tint: UInt32, darkWindow: Bool = false)
        /// Cuadros de colores.
        case tiles(TilesLayout, colors: [UInt32])
    }

    /// Número que se muestra en Ajustes (1…20).
    var number: Int { (Self.all.firstIndex { $0.id == id } ?? 0) + 1 }

    private static let windowDark: [Color] = [.init(hex: 0x1C2633), .init(hex: 0x0D131B)]
    private static let tilesLight: [Color] = [.init(hex: 0xF4F6FA), .init(hex: 0xD9DEE8)]
    private static let tilesDark: [Color] = [.init(hex: 0x2A2D34), .init(hex: 0x15171B)]
    private static let classic: [UInt32] = [0x2B6CF0, 0x22B573, 0xF5A623, 0xE5484D]

    nonisolated(unsafe) static let all: [AppIconDesign] = [
        // Estilo «Ventana»
        .init(id: "window", name: "Window", light: [.init(hex: 0x6FD3FF), .init(hex: 0x2E8BEF)], dark: windowDark, glyph: .window(.list, tint: 0x2E8BEF)),
        .init(id: "window-graphite", name: "Window · Graphite", light: [.init(hex: 0xA8B0BD), .init(hex: 0x5B6472)], dark: [.init(hex: 0x24272D), .init(hex: 0x111317)], glyph: .window(.list, tint: 0x5B6472)),
        .init(id: "window-icons", name: "Window · Icons", light: [.init(hex: 0xC4A8FF), .init(hex: 0x7C4DEB)], dark: [.init(hex: 0x221A36), .init(hex: 0x100C1C)], glyph: .window(.icons, tint: 0x7C4DEB)),
        .init(id: "window-columns", name: "Window · Columns", light: [.init(hex: 0x8EE6A8), .init(hex: 0x23A45C)], dark: [.init(hex: 0x15281D), .init(hex: 0x09130D)], glyph: .window(.columns, tint: 0x23A45C)),
        .init(id: "window-split", name: "Window · Split", light: [.init(hex: 0xFFC07A), .init(hex: 0xF07A2E)], dark: [.init(hex: 0x2E1F12), .init(hex: 0x160E07)], glyph: .window(.split, tint: 0xF07A2E)),
        .init(id: "window-tabs", name: "Window · Tabs", light: [.init(hex: 0x6EE7D8), .init(hex: 0x14A3A0)], dark: [.init(hex: 0x10292A), .init(hex: 0x071415)], glyph: .window(.tabs, tint: 0x14A3A0)),
        .init(id: "window-dark", name: "Window · Dark", light: [.init(hex: 0x6FD3FF), .init(hex: 0x2E8BEF)], dark: windowDark, glyph: .window(.list, tint: 0x6FD3FF, darkWindow: true)),
        .init(id: "window-stacked", name: "Window · Stacked", light: [.init(hex: 0xFF9EC4), .init(hex: 0xE0457F)], dark: [.init(hex: 0x2E1220), .init(hex: 0x16080F)], glyph: .window(.stacked, tint: 0xE0457F)),
        .init(id: "window-gallery", name: "Window · Gallery", light: [.init(hex: 0x98A6FF), .init(hex: 0x4553D8)], dark: [.init(hex: 0x181B38), .init(hex: 0x0B0C1C)], glyph: .window(.gallery, tint: 0x4553D8)),
        .init(id: "window-search", name: "Window · Search", light: [.init(hex: 0x7FE3FF), .init(hex: 0x1E9BD7)], dark: [.init(hex: 0x10242F), .init(hex: 0x081218)], glyph: .window(.search, tint: 0x1E9BD7)),
        // Estilo «Mosaico»
        .init(id: "tiles", name: "Tiles", light: tilesLight, dark: tilesDark, glyph: .tiles(.grid2, colors: classic)),
        .init(id: "tiles-nine", name: "Tiles · 3×3", light: tilesLight, dark: tilesDark, glyph: .tiles(.grid3, colors: [0x2B6CF0, 0x22B573, 0xF5A623, 0xE5484D, 0x8B5CF6, 0x14B8A6, 0xEC4899, 0x64748B, 0xFACC15])),
        .init(id: "tiles-bento", name: "Tiles · Bento", light: tilesLight, dark: tilesDark, glyph: .tiles(.bento, colors: classic)),
        .init(id: "tiles-circles", name: "Tiles · Circles", light: tilesLight, dark: tilesDark, glyph: .tiles(.circles, colors: classic)),
        .init(id: "tiles-folder", name: "Tiles · Folder", light: tilesLight, dark: tilesDark, glyph: .tiles(.folder, colors: classic)),
        .init(id: "tiles-blue", name: "Tiles · Blue", light: tilesLight, dark: tilesDark, glyph: .tiles(.grid2, colors: [0x93C5FD, 0x3B82F6, 0x1D4ED8, 0x60A5FA])),
        .init(id: "tiles-pastel", name: "Tiles · Pastel", light: tilesLight, dark: tilesDark, glyph: .tiles(.grid2, colors: [0xA5B4FC, 0x86EFAC, 0xFDE68A, 0xFCA5A5])),
        .init(id: "tiles-night", name: "Tiles · Night", light: [.init(hex: 0x2A2D34), .init(hex: 0x15171B)], dark: [.init(hex: 0x1A1C21), .init(hex: 0x0A0B0D)], glyph: .tiles(.grid2, colors: [0x38BDF8, 0x4ADE80, 0xFBBF24, 0xF472B6])),
        .init(id: "tiles-diagonal", name: "Tiles · Diamond", light: tilesLight, dark: tilesDark, glyph: .tiles(.diagonal, colors: classic)),
        .init(id: "tiles-warm", name: "Tiles · Warm", light: tilesLight, dark: tilesDark, glyph: .tiles(.grid2, colors: [0xF97316, 0xEF4444, 0xF59E0B, 0xDB2777]))
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Dibuja el icono en un cuadrado; sigue la cuadrícula de macOS (fondo al 80 %, esquinas suaves).
struct AppIconArt: View {
    let design: AppIconDesign
    let dark: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let box = s * 0.8
            ZStack {
                RoundedRectangle(cornerRadius: box * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: dark ? design.dark : design.light, startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: box * 0.225, style: .continuous)
                            .strokeBorder(.white.opacity(dark ? 0.12 : 0.35), lineWidth: box * 0.008)
                    )
                    .shadow(color: .black.opacity(0.28), radius: s * 0.02, y: s * 0.012)
                glyph(u: box / 100)
            }
            .frame(width: box, height: box)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func glyph(u: CGFloat) -> some View {
        switch design.glyph {
        case let .window(content, tint, darkWindow):
            WindowGlyph(content: content, tint: Color(hex: tint), dark: dark || darkWindow, u: u)
        case let .tiles(layout, colors):
            TilesGlyph(layout: layout, colors: colors.map { Color(hex: $0).opacity(dark ? 0.9 : 1) }, dark: dark, u: u)
        }
    }
}

/// Estilo «Ventana»: ventana de Mac con botones, barra lateral y contenido.
private struct WindowGlyph: View {
    let content: AppIconDesign.WindowContent
    let tint: Color
    let dark: Bool
    let u: CGFloat

    private var paper: Color { dark ? Color(hex: 0x2A3442) : .white }
    private var folderColor: Color { dark ? tint.mix(with: .white, by: 0.35) : tint }
    private var line: Color { (dark ? Color.white : Color.black).opacity(0.25) }

    var body: some View {
        switch content {
        case .stacked:
            ZStack {
                window(.list).scaleEffect(0.86).offset(x: -7 * u, y: -7 * u).opacity(0.75)
                window(.list).scaleEffect(0.86).offset(x: 7 * u, y: 7 * u)
            }
        case .split:
            window(.split)
        default:
            window(content)
        }
    }

    private func window(_ kind: AppIconDesign.WindowContent) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7 * u).fill(paper)
            HStack(spacing: 3 * u) {
                ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) { Circle().fill($0).frame(width: 5 * u) }
            }
            .padding(5 * u)
            if kind != .split && kind != .gallery {
                Rectangle().fill(folderColor.opacity(0.18)).frame(width: 18 * u).padding(.top, 14 * u)
            }
            body(kind).padding(.top, 14 * u)
        }
        .frame(width: 66 * u, height: 54 * u)
        .clipShape(RoundedRectangle(cornerRadius: 7 * u))
        .shadow(color: .black.opacity(0.2), radius: 2 * u, y: 1 * u)
    }

    @ViewBuilder
    private func body(_ kind: AppIconDesign.WindowContent) -> some View {
        switch kind {
        case .list, .stacked:
            rows(3).padding(.leading, 22 * u).padding(.top, 4 * u)
        case .icons:
            VStack(spacing: 4 * u) {
                ForEach(0..<2) { _ in
                    HStack(spacing: 4 * u) { ForEach(0..<3) { _ in FolderShape().fill(folderColor).frame(width: 10 * u, height: 8 * u) } }
                }
            }
            .padding(.leading, 23 * u).padding(.top, 6 * u)
        case .columns:
            HStack(spacing: 2 * u) {
                ForEach(0..<2) { col in
                    VStack(alignment: .leading, spacing: 3 * u) {
                        ForEach(0..<4) { row in
                            RoundedRectangle(cornerRadius: 1 * u)
                                .fill(row == 1 ? folderColor : line)
                                .frame(width: 18 * u, height: 3 * u)
                        }
                    }
                    if col == 0 { Rectangle().fill(line).frame(width: 0.8 * u, height: 26 * u) }
                }
            }
            .padding(.leading, 21 * u).padding(.top, 5 * u)
        case .split:
            HStack(spacing: 0) {
                rows(3).frame(width: 33 * u, alignment: .leading).padding(.leading, 4 * u)
                Rectangle().fill(line).frame(width: 1 * u, height: 34 * u)
                rows(3).padding(.leading, 4 * u)
            }
            .padding(.top, 4 * u)
        case .tabs:
            VStack(alignment: .leading, spacing: 3 * u) {
                HStack(spacing: 2 * u) {
                    RoundedRectangle(cornerRadius: 2 * u).fill(folderColor.opacity(0.35)).frame(width: 18 * u, height: 5 * u)
                    RoundedRectangle(cornerRadius: 2 * u).fill(line).frame(width: 14 * u, height: 5 * u)
                }
                rows(2)
            }
            .padding(.leading, 22 * u).padding(.top, 2 * u)
        case .gallery:
            VStack(spacing: 3 * u) {
                RoundedRectangle(cornerRadius: 3 * u)
                    .fill(LinearGradient(colors: [folderColor, folderColor.mix(with: .white, by: 0.5)], startPoint: .bottomLeading, endPoint: .topTrailing))
                    .frame(width: 52 * u, height: 22 * u)
                HStack(spacing: 3 * u) { ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 1.5 * u).fill(line).frame(width: 11 * u, height: 7 * u) } }
            }
            .padding(.leading, 7 * u).padding(.top, 2 * u)
        case .search:
            VStack(alignment: .leading, spacing: 4 * u) {
                Capsule().fill(line.opacity(0.6)).frame(width: 38 * u, height: 6 * u)
                    .overlay(alignment: .leading) { Circle().stroke(folderColor, lineWidth: 1.2 * u).frame(width: 3.5 * u).padding(.leading, 2 * u) }
                rows(2)
            }
            .padding(.leading, 22 * u).padding(.top, 2 * u)
        }
    }

    private func rows(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5 * u) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 3 * u) {
                    FolderShape().fill(folderColor).frame(width: 9 * u, height: 7 * u)
                    RoundedRectangle(cornerRadius: 1.5 * u).fill(line).frame(width: 18 * u, height: 3 * u)
                }
            }
        }
    }
}

/// Estilo «Mosaico»: cuadros de colores.
private struct TilesGlyph: View {
    let layout: AppIconDesign.TilesLayout
    let colors: [Color]
    let dark: Bool
    let u: CGFloat

    private func tile(_ i: Int, _ w: CGFloat, _ h: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius * u, style: .continuous)
            .fill(colors[i % colors.count])
            .frame(width: w * u, height: h * u)
    }

    var body: some View {
        switch layout {
        case .grid2:
            grid(2, size: 26, gap: 6)
        case .grid3:
            grid(3, size: 17, gap: 4.5, radius: 4.5)
        case .bento:
            HStack(spacing: 6 * u) {
                tile(0, 26, 58)
                VStack(spacing: 6 * u) { tile(1, 26, 26); tile(2, 26, 26) }
            }
            .overlay(alignment: .bottom) { EmptyView() }
        case .circles:
            VStack(spacing: 6 * u) {
                ForEach(0..<2) { r in
                    HStack(spacing: 6 * u) { ForEach(0..<2) { c in Circle().fill(colors[r * 2 + c]).frame(width: 26 * u, height: 26 * u) } }
                }
            }
        case .folder:
            VStack(spacing: 6 * u) {
                HStack(spacing: 6 * u) {
                    tile(0, 26, 26).overlay(FolderShape().fill(.white).frame(width: 15 * u, height: 11 * u))
                    tile(1, 26, 26)
                }
                HStack(spacing: 6 * u) { tile(2, 26, 26); tile(3, 26, 26) }
            }
        case .diagonal:
            grid(2, size: 22, gap: 5).rotationEffect(.degrees(45))
        }
    }

    private func grid(_ n: Int, size: CGFloat, gap: CGFloat, radius: CGFloat = 6) -> some View {
        VStack(spacing: gap * u) {
            ForEach(0..<n, id: \.self) { r in
                HStack(spacing: gap * u) {
                    ForEach(0..<n, id: \.self) { c in tile(r * n + c, size, size, radius: radius) }
                }
            }
        }
    }
}

// MARK: - Formas

struct FolderShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, c = min(w, h) * 0.12
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.36, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.46, y: r.minY + h * 0.14))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY + h * 0.14))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.14 + c), control: CGPoint(x: r.maxX, y: r.minY + h * 0.14))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Ajustes

/// Sección «Icono de la app» de Ajustes → Apariencia.
struct AppIconSection: View {
    @AppStorage(AppIconService.key) private var selected = ""

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        Section("App Icon") {
            LazyVGrid(columns: columns, spacing: 12) {
                option(id: "", name: "Original") {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 52, height: 52)
                }
                ForEach(AppIconDesign.all) { design in
                    option(id: design.id, name: design.name, number: design.number) {
                        HStack(spacing: 2) {
                            AppIconArt(design: design, dark: false).frame(width: 52, height: 52)
                            AppIconArt(design: design, dark: true).frame(width: 52, height: 52)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            Text("Each icon has a light and a dark version (left and right) that change with macOS. It is shown in the Dock and ⌘Tab while Explorer is open; Finder keeps the original so macOS doesn’t ask for the permissions again.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: selected) { _, _ in AppIconService.apply() }
    }

    private func option<Content: View>(id: String, name: LocalizedStringKey, number: Int? = nil, @ViewBuilder _ preview: () -> Content) -> some View {
        Button { selected = id } label: {
            VStack(spacing: 4) {
                preview()
                HStack(spacing: 3) {
                    if let number { Text(verbatim: "\(number).").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                    Text(name).font(.caption)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(selected == id ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected == id ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 10)
    }
}
