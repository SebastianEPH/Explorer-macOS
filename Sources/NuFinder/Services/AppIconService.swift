import AppKit
import SwiftUI

/// Fork: iconos alternativos para Explorer (Ajustes → Apariencia → Icono de la app).
///
/// Diseños propios hechos con formas (sin SF Symbols, que Apple no permite en iconos de apps).
/// Cada uno tiene versión clara y oscura y cambia solo con el modo de macOS. Se aplica al Dock y a
/// ⌘Tab mientras Explorer está abierto; no se toca el .app para no romper la firma (y los permisos).
enum AppIconService {
    static let key = "appearance.appIcon"
    /// Icono por defecto: el n.º 21 «Ventana cuadrada», que también es el icono oficial del .app.
    static let defaultID = "window-square"
    /// Fondo de color detrás del dibujo (el usuario lo prefiere sin fondo).
    static let backgroundKey = "appearance.appIconBackground"
    /// Espacio libre a cada lado del icono (0 = llena todo; 0,10 = como los iconos de Apple).
    static let marginKey = "appearance.appIconMargin"
    static let defaultMargin = 0.10
    static var margin: Double { UserDefaults.standard.object(forKey: marginKey) as? Double ?? defaultMargin }

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
        let saved = UserDefaults.standard.string(forKey: key) ?? defaultID
        guard let design = AppIconDesign.all.first(where: { $0.id == saved }) ?? AppIconDesign.all.first(where: { $0.id == defaultID }) else { return }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let background = UserDefaults.standard.bool(forKey: backgroundKey)
        NSApp.applicationIconImage = image(design, dark: dark, background: background, margin: margin, size: 512)
    }

    @MainActor
    static func image(_ design: AppIconDesign, dark: Bool, background: Bool, margin: Double = defaultMargin, size: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconArt(design: design, dark: dark, background: background, margin: margin).frame(width: size, height: size))
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
        case window(WindowContent, tint: UInt32, darkWindow: Bool = false, square: Bool = false)
        /// Cuadros de colores.
        case tiles(TilesLayout, colors: [UInt32])
        /// Ideas nuevas, cada una distinta (inspiradas en el cristal en capas de macOS Tahoe y en los exploradores de dos paneles).
        case glassLayers, dualPane, lensGrid, monogram, glassFolder, windowTiles, cards, millerColumns
        case sidebarApp, fileTypes, folderTabs, folderGrid, breadcrumb
        case isometric, duotone, sketch, soft3D, gradientMinimal
    }

    /// Lado más largo del dibujo en unidades (100 = todo el espacio). Sin fondo, el dibujo se
    /// escala para que ese lado ocupe exactamente el espacio disponible (con 0 % de margen, toca el borde).
    var extent: CGFloat {
        switch id {
        case "window": return 66
        case "window-square": return 62
        case "tiles", "file-types": return 58
        case "window-tiles": return 66
        case "dual-pane": return 69
        case "columns": return 78
        case "sidebar": return 66
        case "folder-tabs": return 82
        case "folder-grid": return 62
        case "breadcrumb": return 84
        case "glass-layers": return 72
        case "glass-folder", "isometric", "duotone", "soft3d", "gradient": return 66
        case "lens-grid": return 76
        case "monogram": return 56
        case "cards": return 76
        case "sketch": return 62
        default: return 66
        }
    }

    /// Número que se muestra en Ajustes (1…20).
    var number: Int { (Self.all.firstIndex { $0.id == id } ?? 0) + 1 }

    private static let windowDark: [Color] = [.init(hex: 0x1C2633), .init(hex: 0x0D131B)]
    private static let tilesLight: [Color] = [.init(hex: 0xF4F6FA), .init(hex: 0xD9DEE8)]
    private static let tilesDark: [Color] = [.init(hex: 0x2A2D34), .init(hex: 0x15171B)]
    private static let classic: [UInt32] = [0x2B6CF0, 0x22B573, 0xF5A623, 0xE5484D]

    private static let none: [Color] = [.init(hex: 0x6FD3FF), .init(hex: 0x2E8BEF)]

    nonisolated(unsafe) static let all: [AppIconDesign] = [
        // Grupo A — inspirados en «Ventana» y «Mosaico» (interfaz plana y colorida)
        .init(id: "window", name: "Window", light: [.init(hex: 0x6FD3FF), .init(hex: 0x2E8BEF)], dark: windowDark, glyph: .window(.list, tint: 0x2E8BEF)),
        .init(id: "tiles", name: "Tiles", light: tilesLight, dark: tilesDark, glyph: .tiles(.grid2, colors: classic)),
        .init(id: "window-tiles", name: "Window + Tiles", light: tilesLight, dark: tilesDark, glyph: .windowTiles),
        .init(id: "dual-pane", name: "Dual Pane", light: [.init(hex: 0x34D399), .init(hex: 0x0E7490)], dark: [.init(hex: 0x0E2A2A), .init(hex: 0x061414)], glyph: .dualPane),
        .init(id: "columns", name: "Columns", light: [.init(hex: 0xF8FAFC), .init(hex: 0xCBD5E1)], dark: [.init(hex: 0x1F2937), .init(hex: 0x0B1120)], glyph: .millerColumns),
        .init(id: "sidebar", name: "Sidebar", light: [.init(hex: 0xA5B4FC), .init(hex: 0x6366F1)], dark: windowDark, glyph: .sidebarApp),
        .init(id: "file-types", name: "File Types", light: tilesLight, dark: tilesDark, glyph: .fileTypes),
        .init(id: "folder-tabs", name: "Tabs", light: none, dark: windowDark, glyph: .folderTabs),
        .init(id: "folder-grid", name: "Folder Grid", light: tilesLight, dark: tilesDark, glyph: .folderGrid),
        .init(id: "breadcrumb", name: "Path", light: none, dark: windowDark, glyph: .breadcrumb),
        // Grupo B — otro estilo: cristal, 3D suave, isométrico, dos tonos, trazo a mano, minimalista
        .init(id: "glass-layers", name: "Glass Layers", light: [.init(hex: 0x7DD3FC), .init(hex: 0x6366F1)], dark: [.init(hex: 0x1A1F3D), .init(hex: 0x0B0D1E)], glyph: .glassLayers),
        .init(id: "glass-folder", name: "Glass Folder", light: [.init(hex: 0x60A5FA), .init(hex: 0x1D4ED8)], dark: [.init(hex: 0x111D3A), .init(hex: 0x070D1C)], glyph: .glassFolder),
        .init(id: "lens-grid", name: "Explore", light: [.init(hex: 0xFDE68A), .init(hex: 0xF97316)], dark: [.init(hex: 0x2E1D0E), .init(hex: 0x160D06)], glyph: .lensGrid),
        .init(id: "monogram", name: "Monogram E", light: [.init(hex: 0x1E293B), .init(hex: 0x0F172A)], dark: [.init(hex: 0x111827), .init(hex: 0x030712)], glyph: .monogram),
        .init(id: "cards", name: "Cards", light: [.init(hex: 0xF9A8D4), .init(hex: 0xA855F7)], dark: [.init(hex: 0x2A1233), .init(hex: 0x140819)], glyph: .cards),
        .init(id: "isometric", name: "Isometric", light: [.init(hex: 0x93C5FD), .init(hex: 0x3B82F6)], dark: [.init(hex: 0x172036), .init(hex: 0x0A101C)], glyph: .isometric),
        .init(id: "duotone", name: "Two-Tone", light: [.init(hex: 0x5EEAD4), .init(hex: 0x0D9488)], dark: [.init(hex: 0x0F2725), .init(hex: 0x071412)], glyph: .duotone),
        .init(id: "sketch", name: "Hand-Drawn", light: [.init(hex: 0xFEF3C7), .init(hex: 0xFDE68A)], dark: [.init(hex: 0x2A2410), .init(hex: 0x141106)], glyph: .sketch),
        .init(id: "soft3d", name: "Soft 3D", light: [.init(hex: 0xFDBA74), .init(hex: 0xF97316)], dark: [.init(hex: 0x2E1A0E), .init(hex: 0x170C06)], glyph: .soft3D),
        .init(id: "gradient", name: "Minimal Gradient", light: [.init(hex: 0xF472B6), .init(hex: 0x8B5CF6)], dark: [.init(hex: 0x24112E), .init(hex: 0x110817)], glyph: .gradientMinimal),
        .init(id: "window-square", name: "Square Window", light: [.init(hex: 0x6FD3FF), .init(hex: 0x2E8BEF)], dark: windowDark, glyph: .window(.list, tint: 0x2E8BEF, square: true))
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
    var background = true
    /// Espacio libre a cada lado (fracción del tamaño).
    var margin: Double = AppIconService.defaultMargin

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let box = s * (1 - 2 * min(max(margin, 0), 0.4))
            ZStack {
                if background {
                    RoundedRectangle(cornerRadius: box * 0.225, style: .continuous)
                        .fill(LinearGradient(colors: dark ? design.dark : design.light, startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: box * 0.225, style: .continuous)
                                .strokeBorder(.white.opacity(dark ? 0.12 : 0.35), lineWidth: box * 0.008)
                        )
                        .shadow(color: .black.opacity(0.28), radius: s * 0.02, y: s * 0.012)
                }
                // Sin fondo, el dibujo crece para ocupar el espacio y lo blanco toma el color del icono.
                glyph(u: box / (background ? 100 : design.extent)) // sin fondo: el dibujo llena el espacio menos el margen
                    .environment(\.iconTint, background ? nil : design.light)
                    .shadow(color: .black.opacity(background ? 0 : 0.18), radius: s * 0.015, y: s * 0.01)
            }
            .frame(width: box, height: box)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func glyph(u: CGFloat) -> some View {
        switch design.glyph {
        case let .window(content, tint, darkWindow, square):
            WindowGlyph(content: content, tint: Color(hex: tint), dark: dark || darkWindow, u: u, square: square)
        case let .tiles(layout, colors):
            TilesGlyph(layout: layout, colors: colors.map { Color(hex: $0).opacity(dark ? 0.9 : 1) }, dark: dark, u: u)
        default:
            NewGlyph(glyph: design.glyph, dark: dark, u: u)
        }
    }
}

/// Estilo «Ventana»: ventana de Mac con botones, barra lateral y contenido.
private struct WindowGlyph: View {
    let content: AppIconDesign.WindowContent
    let tint: Color
    let dark: Bool
    let u: CGFloat
    var square = false

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
        .frame(width: (square ? 62 : 66) * u, height: (square ? 62 : 54) * u)
        .clipShape(RoundedRectangle(cornerRadius: (square ? 9 : 7) * u))
        .shadow(color: .black.opacity(0.2), radius: 2 * u, y: 1 * u)
    }

    @ViewBuilder
    private func body(_ kind: AppIconDesign.WindowContent) -> some View {
        switch kind {
        case .list, .stacked:
            rows(3).padding(.leading, 22 * u).padding(.top, (square ? 7 : 4) * u)
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
        VStack(alignment: .leading, spacing: (square ? 9 : 5) * u) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 3 * u) {
                    FolderShape().fill(folderColor).frame(width: 9 * u, height: 7 * u)
                    RoundedRectangle(cornerRadius: 1.5 * u).fill(line).frame(width: 18 * u, height: 3 * u)
                }
            }
        }
    }
}

/// Cristal: blanco translúcido con borde que capta la luz (como los iconos de macOS Tahoe).
/// Colores del icono para el modo sin fondo (nil = con fondo, se usa blanco).
private struct IconTintKey: EnvironmentKey { static let defaultValue: [Color]? = nil }
extension EnvironmentValues {
    var iconTint: [Color]? {
        get { self[IconTintKey.self] }
        set { self[IconTintKey.self] = newValue }
    }
}

private struct Glass: ViewModifier {
    let dark: Bool
    let radius: CGFloat
    @Environment(\.iconTint) private var tint
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.map { LinearGradient(colors: $0, startPoint: .topLeading, endPoint: .bottomTrailing) }
                          ?? LinearGradient(colors: [.white.opacity(dark ? 0.28 : 0.6), .white.opacity(dark ? 0.08 : 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: radius * 0.12)
            )
            .shadow(color: .black.opacity(dark ? 0.35 : 0.15), radius: radius * 0.4, y: radius * 0.2)
    }
}

/// Las ideas nuevas.
private struct NewGlyph: View {
    let glyph: AppIconDesign.Glyph
    let dark: Bool
    let u: CGFloat
    @Environment(\.iconTint) private var tint

    /// Blanco con fondo; sin fondo, el color principal del icono para que se vea.
    private var solid: Color { tint?.last ?? .white }
    private var soft: Color { tint?.first ?? .white }

    private func glass(_ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 8) -> some View {
        Color.clear.frame(width: w * u, height: h * u).modifier(Glass(dark: dark, radius: r * u))
    }

    var body: some View {
        switch glyph {
        case .glassLayers:
            // Tres paneles de cristal superpuestos con una carpeta en el de delante.
            ZStack {
                glass(46, 36).rotationEffect(.degrees(-12)).offset(x: -10 * u, y: -8 * u)
                glass(46, 36).rotationEffect(.degrees(6)).offset(x: 8 * u, y: -2 * u)
                glass(50, 38).offset(y: 8 * u)
                    .overlay(FolderShape().fill(tint == nil ? Color.white : Color.white.opacity(0.95)).frame(width: 22 * u, height: 17 * u).offset(y: 8 * u))
            }
        case .dualPane:
            // Dos paneles (como ForkLift o Commander One) y flechas que intercambian archivos.
            ZStack {
                HStack(spacing: 5 * u) {
                    pane()
                    pane()
                }
                Circle().fill(tint == nil ? Color.white : Color(white: 0.97)).frame(width: 22 * u, height: 22 * u)
                    .shadow(color: .black.opacity(0.2), radius: 2 * u, y: 1 * u)
                VStack(spacing: 2.5 * u) {
                    ArrowRight().fill(Color(hex: 0x0E7490)).frame(width: 12 * u, height: 5.5 * u)
                    ArrowRight().fill(Color(hex: 0x10B981)).frame(width: 12 * u, height: 5.5 * u).rotationEffect(.degrees(180))
                }
            }
        case .lensGrid:
            // Lupa de cristal sobre una cuadrícula de archivos.
            ZStack {
                VStack(spacing: 5 * u) {
                    ForEach(0..<3) { _ in HStack(spacing: 5 * u) { ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 3 * u).fill(tint == nil ? Color.white.opacity(dark ? 0.35 : 0.75) : soft).frame(width: 14 * u, height: 14 * u) } } }
                }
                .offset(x: -6 * u, y: -6 * u)
                Circle().fill(.white.opacity(dark ? 0.18 : 0.35)).frame(width: 34 * u, height: 34 * u)
                    .overlay(Circle().strokeBorder(solid, lineWidth: 5 * u))
                    .shadow(color: .black.opacity(0.25), radius: 3 * u, y: 2 * u)
                    .offset(x: 8 * u, y: 8 * u)
                Capsule().fill(solid).frame(width: 7 * u, height: 18 * u).rotationEffect(.degrees(-45)).offset(x: 27 * u, y: 27 * u)
            }
        case .monogram:
            // Letra «E» de Explorer formada por tres barras de colores, como pestañas de carpeta.
            HStack(spacing: 4 * u) {
                RoundedRectangle(cornerRadius: 4 * u).fill(LinearGradient(colors: [Color(hex: 0x60A5FA), Color(hex: 0x2563EB)], startPoint: .top, endPoint: .bottom)).frame(width: 12 * u, height: 54 * u)
                VStack(alignment: .leading, spacing: 9 * u) {
                    RoundedRectangle(cornerRadius: 4 * u).fill(Color(hex: 0x22C55E)).frame(width: 32 * u, height: 12 * u)
                    RoundedRectangle(cornerRadius: 4 * u).fill(Color(hex: 0xF59E0B)).frame(width: 24 * u, height: 12 * u)
                    RoundedRectangle(cornerRadius: 4 * u).fill(Color(hex: 0xEF4444)).frame(width: 32 * u, height: 12 * u)
                }
            }
            .offset(x: 2 * u)
        case .glassFolder:
            // Carpeta con la parte de delante de cristal y documentos dentro.
            ZStack {
                FolderShape().fill(tint == nil ? Color.white.opacity(dark ? 0.3 : 0.5) : solid).frame(width: 64 * u, height: 50 * u).offset(y: -4 * u)
                RoundedRectangle(cornerRadius: 3 * u).fill(.white).frame(width: 36 * u, height: 38 * u).rotationEffect(.degrees(-8)).offset(x: -6 * u, y: -6 * u)
                RoundedRectangle(cornerRadius: 3 * u).fill(Color(hex: 0xFDE68A)).frame(width: 36 * u, height: 38 * u).rotationEffect(.degrees(6)).offset(x: 8 * u, y: -4 * u)
                glass(64, 34, 7).offset(y: 12 * u)
            }
        case .windowTiles:
            // Lo mejor de los dos favoritos: una ventana de Mac cuyo contenido es un mosaico.
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7 * u).fill(dark ? Color(hex: 0x2A3442) : .white)
                HStack(spacing: 3 * u) {
                    ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) { Circle().fill($0).frame(width: 5 * u) }
                }
                .padding(5 * u)
                VStack(spacing: 4 * u) {
                    HStack(spacing: 4 * u) { tile(0x2B6CF0); tile(0x22B573) }
                    HStack(spacing: 4 * u) { tile(0xF5A623); tile(0xE5484D) }
                }
                .padding(.leading, 13 * u).padding(.top, 15 * u)
            }
            .frame(width: 66 * u, height: 58 * u)
            .shadow(color: .black.opacity(0.2), radius: 2 * u, y: 1 * u)
        case .cards:
            // Archivos como tarjetas en abanico, cada una con su tipo.
            ZStack {
                card(0x60A5FA, angle: -18, x: -14)
                card(0x34D399, angle: -6, x: -5)
                card(0xFBBF24, angle: 6, x: 5)
                card(0xF87171, angle: 18, x: 14)
            }
            .offset(y: 4 * u)
        case .millerColumns:
            // Vista en columnas con la ruta resaltada de una columna a otra.
            HStack(spacing: 3 * u) {
                column(highlight: 1)
                column(highlight: 2)
                column(highlight: 0, last: true)
            }
        case .sidebarApp:
            // Barra lateral de colores con lista, como la ventana del explorador.
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5 * u) {
                    ForEach([0x3B82F6, 0x22C55E, 0xF59E0B, 0xEF4444] as [UInt32], id: \.self) { hex in
                        HStack(spacing: 2.5 * u) {
                            Circle().fill(Color(hex: hex)).frame(width: 5 * u)
                            RoundedRectangle(cornerRadius: 1 * u).fill(.white.opacity(0.85)).frame(width: 9 * u, height: 2.5 * u)
                        }
                    }
                }
                .padding(5 * u)
                .frame(width: 24 * u, height: 54 * u, alignment: .topLeading)
                .background(Color(hex: 0x6366F1))
                VStack(spacing: 4 * u) {
                    ForEach(0..<2) { _ in HStack(spacing: 4 * u) { ForEach(0..<2) { _ in RoundedRectangle(cornerRadius: 3 * u).fill(Color(hex: 0xE0E7FF)).frame(width: 15 * u, height: 15 * u) } } }
                }
                .frame(width: 42 * u, height: 54 * u)
                .background(dark ? Color(hex: 0x2A3442) : .white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7 * u))
            .shadow(color: .black.opacity(0.2), radius: 2 * u, y: 1 * u)
        case .fileTypes:
            // Mosaico donde cada cuadro es un tipo de archivo: documento, imagen, música, vídeo.
            VStack(spacing: 6 * u) {
                HStack(spacing: 6 * u) {
                    typeTile(0x3B82F6) { VStack(spacing: 2.5 * u) { ForEach(0..<3) { _ in Capsule().fill(.white).frame(width: 13 * u, height: 2.5 * u) } } }
                    typeTile(0x22C55E) { MountainShape().fill(.white).frame(width: 15 * u, height: 10 * u) }
                }
                HStack(spacing: 6 * u) {
                    typeTile(0xF59E0B) { NoteShape().fill(.white).frame(width: 11 * u, height: 14 * u) }
                    typeTile(0xEF4444) { PlayShape().fill(.white).frame(width: 11 * u, height: 12 * u) }
                }
            }
        case .folderTabs:
            // Carpetas como pestañas del navegador, una delante.
            ZStack(alignment: .bottom) {
                HStack(spacing: -6 * u) {
                    tabShape(0x93C5FD); tabShape(0x60A5FA); tabShape(0x2563EB, front: true)
                }
                .offset(x: -14 * u, y: -35.5 * u)
                RoundedRectangle(cornerRadius: 6 * u).fill(dark ? Color(hex: 0x2A3442) : .white).frame(width: 64 * u, height: 36 * u)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4 * u) { ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 1 * u).fill(Color(hex: 0x2563EB).opacity(0.35)).frame(width: 34 * u, height: 3 * u) } }.padding(7 * u)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 2 * u, y: 1 * u)
            }
            .frame(height: 56 * u)
        case .folderGrid:
            // Cuadrícula de carpetas de colores.
            VStack(spacing: 5 * u) {
                ForEach(0..<2) { r in
                    HStack(spacing: 6 * u) {
                        ForEach(0..<2) { c in
                            FolderShape().fill(Color(hex: [0x3B82F6, 0x22C55E, 0xF59E0B, 0xEF4444][r * 2 + c])).frame(width: 28 * u, height: 22 * u)
                        }
                    }
                }
            }
        case .breadcrumb:
            // La ruta en botones: chips encadenados.
            VStack(alignment: .leading, spacing: 6 * u) {
                chip(0x2563EB, width: 30)
                HStack(spacing: 2 * u) { arrow(); chip(0x22C55E, width: 26) }.padding(.leading, 10 * u)
                HStack(spacing: 2 * u) { arrow(); chip(0xF59E0B, width: 24) }.padding(.leading, 20 * u)
            }
            .scaleEffect(1.45)
        case .isometric:
            // Carpeta en perspectiva isométrica, con caras de tres tonos.
            ZStack {
                IsoFace(.top).fill(Color(hex: 0xBFDBFE))
                IsoFace(.left).fill(Color(hex: 0x3B82F6))
                IsoFace(.right).fill(Color(hex: 0x1D4ED8))
                IsoTab().fill(Color(hex: 0x93C5FD))
            }
            .frame(width: 64 * u, height: 62 * u)
        case .duotone:
            // Dos tonos: carpeta rellena desplazada y su contorno encima.
            ZStack {
                FolderShape().fill(Color(hex: 0x5EEAD4).opacity(dark ? 0.6 : 0.9)).frame(width: 56 * u, height: 42 * u).offset(x: 5 * u, y: 5 * u)
                FolderShape().stroke(dark ? Color.white : Color(hex: 0x0F766E), style: StrokeStyle(lineWidth: 4.5 * u, lineJoin: .round)).frame(width: 56 * u, height: 42 * u).offset(x: -3 * u, y: -3 * u)
            }
        case .sketch:
            // Trazo a mano: varias líneas un poco desplazadas, como un dibujo con lápiz.
            ZStack {
                ForEach(0..<3) { i in
                    FolderShape().stroke(dark ? Color.white.opacity(0.85) : Color(hex: 0x1F2937), style: StrokeStyle(lineWidth: (2.2 - Double(i) * 0.4) * u, lineCap: .round, lineJoin: .round))
                        .frame(width: 58 * u, height: 44 * u)
                        .rotationEffect(.degrees(Double(i) * 1.6 - 1.6))
                        .offset(x: CGFloat(i - 1) * 0.9 * u, y: CGFloat(1 - i) * 0.7 * u)
                }
                Path { p in
                    for k in 0..<5 { let x = CGFloat(k) * 9 * u; p.move(to: CGPoint(x: x, y: 18 * u)); p.addLine(to: CGPoint(x: x + 14 * u, y: 0)) }
                }
                .stroke(Color(hex: 0xF59E0B).opacity(0.8), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
                .frame(width: 50 * u, height: 18 * u).offset(y: 9 * u)
            }
        case .soft3D:
            // 3D suave: una sola carpeta con volumen, brillo y sombra.
            ZStack {
                FolderShape().fill(LinearGradient(colors: [Color(hex: 0xFDBA74), Color(hex: 0xEA580C)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 64 * u, height: 50 * u)
                FolderBody3D().fill(LinearGradient(colors: [Color(hex: 0xFFEDD5), Color(hex: 0xFB923C)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 64 * u, height: 50 * u)
                    .overlay(FolderBody3D().stroke(.white.opacity(0.7), lineWidth: 1.2 * u).frame(width: 64 * u, height: 50 * u))
                Capsule().fill(.white.opacity(0.55)).frame(width: 30 * u, height: 4 * u).offset(y: -2 * u).blur(radius: 1 * u)
            }
            .shadow(color: Color(hex: 0x9A3412).opacity(0.45), radius: 5 * u, y: 4 * u)
        case .gradientMinimal:
            // Minimalista: una carpeta de un solo degradado con una flecha vaciada.
            ZStack {
                FolderShape().fill(LinearGradient(colors: [Color(hex: 0xF472B6), Color(hex: 0x8B5CF6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64 * u, height: 50 * u)
                ArrowRight().fill(.white.opacity(0.92)).frame(width: 22 * u, height: 12 * u).offset(y: 5 * u)
            }
        default:
            EmptyView()
        }
    }

    private func typeTile<C: View>(_ hex: UInt32, @ViewBuilder _ content: () -> C) -> some View {
        RoundedRectangle(cornerRadius: 6 * u, style: .continuous).fill(Color(hex: hex)).frame(width: 26 * u, height: 26 * u).overlay(content())
    }

    private func tabShape(_ hex: UInt32, front: Bool = false) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 4 * u, topTrailingRadius: 4 * u).fill(Color(hex: hex)).frame(width: 24 * u, height: 12 * u)
            .zIndex(front ? 1 : 0)
    }

    private func chip(_ hex: UInt32, width: CGFloat) -> some View {
        HStack(spacing: 2 * u) {
            FolderShape().fill(.white).frame(width: 8 * u, height: 6 * u)
            Capsule().fill(.white.opacity(0.8)).frame(width: (width - 14) * u, height: 2.5 * u)
        }
        .padding(.horizontal, 3.5 * u).frame(height: 12 * u)
        .background(Capsule().fill(Color(hex: hex)))
        .shadow(color: .black.opacity(0.15), radius: 1 * u, y: 0.5 * u)
    }

    private func arrow() -> some View {
        ChevronIcon().stroke(dark ? Color.white.opacity(0.8) : Color(hex: 0x64748B), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round, lineJoin: .round)).frame(width: 4 * u, height: 7 * u)
    }

    private func pane() -> some View {
        VStack(alignment: .leading, spacing: 5 * u) {
            ForEach(0..<4) { i in
                HStack(spacing: 3 * u) {
                    FolderShape().fill(i == 1 ? Color(hex: 0xFDE68A) : .white).frame(width: 7 * u, height: 5.5 * u)
                    RoundedRectangle(cornerRadius: 1 * u).fill(.white.opacity(0.7)).frame(width: 14 * u, height: 2.5 * u)
                }
            }
        }
        .padding(5 * u)
        .frame(width: 32 * u, height: 50 * u, alignment: .topLeading)
        .modifier(Glass(dark: dark, radius: 6 * u))
    }

    private func tile(_ hex: UInt32) -> some View {
        RoundedRectangle(cornerRadius: 4 * u, style: .continuous).fill(Color(hex: hex)).frame(width: 18 * u, height: 16 * u)
    }

    private func card(_ hex: UInt32, angle: Double, x: CGFloat) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4 * u).fill(.white)
            RoundedRectangle(cornerRadius: 2 * u).fill(Color(hex: hex)).frame(height: 10 * u).padding(3 * u)
        }
        .frame(width: 28 * u, height: 38 * u)
        .shadow(color: .black.opacity(0.18), radius: 1.5 * u, y: 1 * u)
        .rotationEffect(.degrees(angle), anchor: .bottom)
        .offset(x: x * u)
    }

    private func column(highlight: Int, last: Bool = false) -> some View {
        VStack(spacing: 4 * u) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1.5 * u)
                    .fill(i == highlight && !last ? Color(hex: 0x3B82F6) : (dark ? Color.white : Color(hex: 0x334155)).opacity(last && i == 0 ? 0.6 : 0.22))
                    .frame(width: 18 * u, height: 5 * u)
            }
        }
        .padding(3 * u)
        .background(RoundedRectangle(cornerRadius: 4 * u).fill(dark ? Color.white.opacity(0.06) : .white))
    }
}

private struct MountainShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.25))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.55, y: r.minY + r.height * 0.6))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.72, y: r.minY + r.height * 0.4))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: r.maxX - r.width * 0.28, y: r.minY - r.height * 0.15, width: r.width * 0.22, height: r.width * 0.22))
        return p
    }
}

private struct NoteShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: r.minX, y: r.maxY - r.height * 0.36, width: r.width * 0.55, height: r.height * 0.36))
        p.addRect(CGRect(x: r.minX + r.width * 0.42, y: r.minY, width: r.width * 0.14, height: r.height * 0.8))
        p.addRect(CGRect(x: r.minX + r.width * 0.42, y: r.minY, width: r.width * 0.58, height: r.height * 0.16))
        return p
    }
}

private struct PlayShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

private struct ChevronIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}

/// Caras de una carpeta isométrica (cubo plano).
private struct IsoFace: Shape {
    enum Side { case top, left, right }
    let side: Side
    init(_ side: Side) { self.side = side }
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let top = CGPoint(x: r.midX, y: r.minY + h * 0.18), left = CGPoint(x: r.minX, y: r.minY + h * 0.36)
        let right = CGPoint(x: r.maxX, y: r.minY + h * 0.36), center = CGPoint(x: r.midX, y: r.minY + h * 0.54)
        let dy = h * 0.4
        var p = Path()
        switch side {
        case .top: p.addLines([top, right, center, left])
        case .left: p.addLines([left, center, CGPoint(x: center.x, y: center.y + dy), CGPoint(x: left.x, y: left.y + dy)])
        case .right: p.addLines([center, right, CGPoint(x: right.x, y: right.y + dy), CGPoint(x: center.x, y: center.y + dy)])
        }
        p.closeSubpath()
        _ = w
        return p
    }
}

private struct IsoTab: Shape {
    func path(in r: CGRect) -> Path {
        let h = r.height
        var p = Path()
        p.addLines([CGPoint(x: r.minX + r.width * 0.12, y: r.minY + h * 0.30), CGPoint(x: r.minX + r.width * 0.34, y: r.minY + h * 0.19),
                    CGPoint(x: r.minX + r.width * 0.46, y: r.minY + h * 0.25), CGPoint(x: r.minX + r.width * 0.24, y: r.minY + h * 0.36)])
        p.closeSubpath()
        return p
    }
}

/// Frente de la carpeta en 3D suave (un poco más bajo que la trasera).
private struct FolderBody3D: Shape {
    func path(in r: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(r.width, r.height) * 0.14, style: .continuous)
            .path(in: CGRect(x: r.minX, y: r.minY + r.height * 0.24, width: r.width, height: r.height * 0.76))
    }
}

private struct ArrowRight: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.6, y: r.minY + r.height * 0.3))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.6, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.6, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.6, y: r.minY + r.height * 0.7))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.7))
        p.closeSubpath()
        return p
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
    @AppStorage(AppIconService.key) private var selected = AppIconService.defaultID
    @AppStorage(AppIconService.backgroundKey) private var background = false
    @AppStorage(AppIconService.marginKey) private var margin = AppIconService.defaultMargin
    @Environment(\.colorScheme) private var colorScheme
    /// Qué versión se ve en la vista previa (nil = la del modo actual de macOS).
    @State private var previewDark: Bool?
    private var showsDark: Bool { previewDark ?? (colorScheme == .dark) }

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        Section("App Icon") {
            Picker(selection: Binding(get: { showsDark }, set: { previewDark = $0 })) {
                Label("Light", systemImage: "sun.max").tag(false)
                Label("Dark", systemImage: "moon").tag(true)
            } label: {
                Label("Preview", systemImage: "eye")
                Text("See how each icon looks in light or dark mode.")
            }
            .pickerStyle(.segmented)
            LabeledContent {
                HStack {
                    Slider(value: $margin, in: 0...0.3, step: 0.01)
                    Text("\(Int((margin * 100).rounded())) %").monospacedDigit().frame(width: 44, alignment: .trailing)
                    Button("Reset") { margin = AppIconService.defaultMargin }.disabled(abs(margin - AppIconService.defaultMargin) < 0.001)
                }
            } label: {
                Label("Icon margin", systemImage: "square.dashed")
                Text("Empty space around the drawing. 0 % fills everything; 10 % matches Apple’s icons.")
            }
            Toggle(isOn: $background) {
                Label("Colored background", systemImage: "app")
                Text("Off: only the drawing, without the rounded colored square.")
            }
            LazyVGrid(columns: columns, spacing: 12) {
                // Fondo de la cuadrícula según la versión elegida, para ver el icono como en el Dock.
                ForEach(AppIconDesign.all) { design in
                    option(id: design.id, name: design.name, number: design.number) {
                        // Uno solo, en el modo actual (dos copias claro/oscuro parecían iconos repetidos).
                        AppIconArt(design: design, dark: showsDark, background: background, margin: margin).frame(width: 60, height: 60)
                    }
                }
            }
            .padding(8)
            .background(showsDark ? Color(white: 0.14) : Color(white: 0.97), in: RoundedRectangle(cornerRadius: 10))
            .environment(\.colorScheme, showsDark ? .dark : .light)
            .animation(.easeInOut(duration: 0.2), value: showsDark)
            Text("Each icon has a light and a dark version that change with macOS. It is shown in the Dock and ⌘Tab while Explorer is open; Finder keeps the original so macOS doesn’t ask for the permissions again.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: selected) { _, _ in AppIconService.apply() }
        .onChange(of: background) { _, _ in AppIconService.apply() }
        .onChange(of: margin) { _, _ in AppIconService.apply() }
    }

    private func option<Content: View>(id: String, name: LocalizedStringKey, number: Int? = nil, @ViewBuilder _ preview: () -> Content) -> some View {
        // Fork: toque directo en vez de Button: dentro del formulario el botón a veces no recibía el clic.
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
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { selected = id }
        .hoverHighlight(cornerRadius: 10)
    }
}
