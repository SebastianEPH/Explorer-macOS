import AppKit
import SwiftUI

/// Fork: iconos alternativos para Explorer (Ajustes → Apariencia → Icono de la app).
///
/// Diseños propios hechos con formas (sin SF Symbols, que Apple no permite en iconos de apps).
/// Cada uno tiene versión clara y oscura y cambia solo con el modo de macOS. Se aplica al Dock y a
/// ⌘Tab mientras Explorer está abierto; no se toca el .app para no romper la firma (y los permisos).
enum AppIconService {
    static let key = "appearance.appIcon"   // "" = original
    /// Fondo de color detrás del dibujo (el usuario lo prefiere sin fondo).
    static let backgroundKey = "appearance.appIconBackground"

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
        let background = UserDefaults.standard.bool(forKey: backgroundKey)
        NSApp.applicationIconImage = image(design, dark: dark, background: background, size: 512)
    }

    @MainActor
    static func image(_ design: AppIconDesign, dark: Bool, background: Bool, size: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconArt(design: design, dark: dark, background: background).frame(width: size, height: size))
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
        /// Ideas nuevas, cada una distinta (inspiradas en el cristal en capas de macOS Tahoe y en los exploradores de dos paneles).
        case glassLayers, dualPane, lensGrid, monogram, glassFolder, windowTiles, cards, millerColumns
    }

    /// Número que se muestra en Ajustes (1…20).
    var number: Int { (Self.all.firstIndex { $0.id == id } ?? 0) + 1 }

    private static let windowDark: [Color] = [.init(hex: 0x1C2633), .init(hex: 0x0D131B)]
    private static let tilesLight: [Color] = [.init(hex: 0xF4F6FA), .init(hex: 0xD9DEE8)]
    private static let tilesDark: [Color] = [.init(hex: 0x2A2D34), .init(hex: 0x15171B)]
    private static let classic: [UInt32] = [0x2B6CF0, 0x22B573, 0xF5A623, 0xE5484D]

    nonisolated(unsafe) static let all: [AppIconDesign] = [
        // Los dos que eligió el usuario, tal como estaban.
        .init(id: "window", name: "Window", light: [.init(hex: 0x6FD3FF), .init(hex: 0x2E8BEF)], dark: windowDark, glyph: .window(.list, tint: 0x2E8BEF)),
        .init(id: "tiles", name: "Tiles", light: tilesLight, dark: tilesDark, glyph: .tiles(.grid2, colors: classic)),
        // Ideas nuevas, todas distintas.
        .init(id: "glass-layers", name: "Glass Layers", light: [.init(hex: 0x7DD3FC), .init(hex: 0x6366F1)], dark: [.init(hex: 0x1A1F3D), .init(hex: 0x0B0D1E)], glyph: .glassLayers),
        .init(id: "dual-pane", name: "Dual Pane", light: [.init(hex: 0x34D399), .init(hex: 0x0E7490)], dark: [.init(hex: 0x0E2A2A), .init(hex: 0x061414)], glyph: .dualPane),
        .init(id: "lens-grid", name: "Explore", light: [.init(hex: 0xFDE68A), .init(hex: 0xF97316)], dark: [.init(hex: 0x2E1D0E), .init(hex: 0x160D06)], glyph: .lensGrid),
        .init(id: "monogram", name: "Monogram E", light: [.init(hex: 0x1E293B), .init(hex: 0x0F172A)], dark: [.init(hex: 0x111827), .init(hex: 0x030712)], glyph: .monogram),
        .init(id: "glass-folder", name: "Glass Folder", light: [.init(hex: 0x60A5FA), .init(hex: 0x1D4ED8)], dark: [.init(hex: 0x111D3A), .init(hex: 0x070D1C)], glyph: .glassFolder),
        .init(id: "window-tiles", name: "Window + Tiles", light: tilesLight, dark: tilesDark, glyph: .windowTiles),
        .init(id: "cards", name: "Cards", light: [.init(hex: 0xF9A8D4), .init(hex: 0xA855F7)], dark: [.init(hex: 0x2A1233), .init(hex: 0x140819)], glyph: .cards),
        .init(id: "columns", name: "Columns", light: [.init(hex: 0xF8FAFC), .init(hex: 0xCBD5E1)], dark: [.init(hex: 0x1F2937), .init(hex: 0x0B1120)], glyph: .millerColumns)
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

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let box = s * 0.8
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
                glyph(u: box / 100 * (background ? 1 : 1.3))
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
        case let .window(content, tint, darkWindow):
            WindowGlyph(content: content, tint: Color(hex: tint), dark: dark || darkWindow, u: u)
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
        default:
            EmptyView()
        }
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
    @AppStorage(AppIconService.key) private var selected = ""
    @AppStorage(AppIconService.backgroundKey) private var background = false

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        Section("App Icon") {
            Toggle(isOn: $background) {
                Label("Colored background", systemImage: "app")
                Text("Off: only the drawing, without the rounded colored square.")
            }
            LazyVGrid(columns: columns, spacing: 12) {
                option(id: "", name: "Original") {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 52, height: 52)
                }
                ForEach(AppIconDesign.all) { design in
                    option(id: design.id, name: design.name, number: design.number) {
                        HStack(spacing: 2) {
                            AppIconArt(design: design, dark: false, background: background).frame(width: 52, height: 52)
                                .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 6))
                            AppIconArt(design: design, dark: true, background: background).frame(width: 52, height: 52)
                                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            Text("Each icon has a light and a dark version (left and right) that change with macOS. It is shown in the Dock and ⌘Tab while Explorer is open; Finder keeps the original so macOS doesn’t ask for the permissions again.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: selected) { _, _ in AppIconService.apply() }
        .onChange(of: background) { _, _ in AppIconService.apply() }
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
