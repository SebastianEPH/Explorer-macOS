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
struct AppIconDesign: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let light: [Color]
    let dark: [Color]
    let glyph: Glyph

    enum Glyph { case folderLens, compass, window, stack, tree, bolt, tiles, orbit, outline, paperPlane }

    nonisolated(unsafe) static let all: [AppIconDesign] = [
        .init(id: "classic", name: "Classic", light: [.init(hex: 0x5AB0FF), .init(hex: 0x1F6FE0)], dark: [.init(hex: 0x16233A), .init(hex: 0x0B1220)], glyph: .folderLens),
        .init(id: "compass", name: "Compass", light: [.init(hex: 0xFFB24D), .init(hex: 0xF0642E)], dark: [.init(hex: 0x2A1A12), .init(hex: 0x120A06)], glyph: .compass),
        .init(id: "window", name: "Window", light: [.init(hex: 0x6FD3FF), .init(hex: 0x2E8BEF)], dark: [.init(hex: 0x1C2633), .init(hex: 0x0D131B)], glyph: .window),
        .init(id: "stack", name: "Stack", light: [.init(hex: 0xB78CFF), .init(hex: 0x6A3DE8)], dark: [.init(hex: 0x231A38), .init(hex: 0x110B1E)], glyph: .stack),
        .init(id: "tree", name: "Tree", light: [.init(hex: 0x7BE495), .init(hex: 0x1FA463)], dark: [.init(hex: 0x14271C), .init(hex: 0x09140E)], glyph: .tree),
        .init(id: "bolt", name: "Fast", light: [.init(hex: 0xFFE066), .init(hex: 0xFFAA00)], dark: [.init(hex: 0x2B2410), .init(hex: 0x141006)], glyph: .bolt),
        .init(id: "tiles", name: "Tiles", light: [.init(hex: 0xF4F6FA), .init(hex: 0xD9DEE8)], dark: [.init(hex: 0x2A2D34), .init(hex: 0x15171B)], glyph: .tiles),
        .init(id: "orbit", name: "Orbit", light: [.init(hex: 0xFF7EB3), .init(hex: 0xC2185B)], dark: [.init(hex: 0x2E1220), .init(hex: 0x16080F)], glyph: .orbit),
        .init(id: "minimal", name: "Minimal", light: [.init(hex: 0xFFFFFF), .init(hex: 0xECEEF2)], dark: [.init(hex: 0x1E1F23), .init(hex: 0x0E0F11)], glyph: .outline),
        .init(id: "plane", name: "Paper Plane", light: [.init(hex: 0x4DE0D2), .init(hex: 0x1A8FA8)], dark: [.init(hex: 0x10282B), .init(hex: 0x071315)], glyph: .paperPlane)
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
                glyph(box: box)
            }
            .frame(width: box, height: box)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Color principal del dibujo: claro en fondos oscuros, y al revés.
    private var ink: Color {
        switch design.glyph {
        case .tiles, .outline: return dark ? .white : Color(hex: 0x2B6CF0)
        default: return dark ? (design.light.last ?? .white) : .white
        }
    }

    private var accent: Color { dark ? .white.opacity(0.92) : Color.white.opacity(0.75) }

    @ViewBuilder
    private func glyph(box: CGFloat) -> some View {
        let u = box / 100
        switch design.glyph {
        case .folderLens:
            ZStack {
                FolderShape().fill(ink).frame(width: 62 * u, height: 46 * u).offset(x: -6 * u, y: -2 * u)
                Circle().stroke(dark ? Color.white : Color(hex: 0x1F6FE0), lineWidth: 6 * u)
                    .background(Circle().fill(dark ? Color(hex: 0x16233A) : .white))
                    .frame(width: 26 * u, height: 26 * u).offset(x: 14 * u, y: 10 * u)
                Capsule().fill(dark ? Color.white : Color(hex: 0x1F6FE0))
                    .frame(width: 6 * u, height: 16 * u).rotationEffect(.degrees(-45)).offset(x: 27 * u, y: 23 * u)
            }
        case .compass:
            ZStack {
                Circle().stroke(ink, lineWidth: 6 * u).frame(width: 64 * u, height: 64 * u)
                ForEach(0..<4) { i in
                    Capsule().fill(ink.opacity(0.7)).frame(width: 3 * u, height: 8 * u)
                        .offset(y: -26 * u).rotationEffect(.degrees(Double(i) * 90))
                }
                NeedleShape().fill(dark ? Color(hex: 0xFF7A45) : .white).frame(width: 16 * u, height: 50 * u).rotationEffect(.degrees(40))
                Circle().fill(ink).frame(width: 7 * u, height: 7 * u)
            }
        case .window:
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7 * u).fill(dark ? Color(hex: 0x2A3442) : .white)
                RoundedRectangle(cornerRadius: 7 * u).fill(ink.opacity(dark ? 0.9 : 0.0)).frame(height: 0)
                HStack(spacing: 3 * u) {
                    ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) { Circle().fill($0).frame(width: 5 * u) }
                }
                .padding(5 * u)
                Rectangle().fill((dark ? Color.white : Color(hex: 0x2E8BEF)).opacity(0.18)).frame(width: 18 * u).padding(.top, 14 * u)
                VStack(alignment: .leading, spacing: 5 * u) {
                    ForEach(0..<3) { _ in
                        HStack(spacing: 3 * u) {
                            FolderShape().fill(dark ? Color(hex: 0x6FD3FF) : Color(hex: 0x2E8BEF)).frame(width: 9 * u, height: 7 * u)
                            RoundedRectangle(cornerRadius: 1.5 * u).fill((dark ? Color.white : Color.black).opacity(0.25)).frame(width: 22 * u, height: 3 * u)
                        }
                    }
                }
                .padding(.leading, 22 * u).padding(.top, 18 * u)
            }
            .frame(width: 66 * u, height: 54 * u)
            .shadow(color: .black.opacity(0.2), radius: 2 * u, y: 1 * u)
        case .stack:
            ZStack {
                FolderShape().fill(ink.opacity(0.45)).frame(width: 56 * u, height: 40 * u).offset(x: -8 * u, y: -10 * u)
                FolderShape().fill(ink.opacity(0.7)).frame(width: 56 * u, height: 40 * u).offset(x: 0, y: 0)
                FolderShape().fill(ink).frame(width: 56 * u, height: 40 * u).offset(x: 8 * u, y: 10 * u)
            }
        case .tree:
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 10 * u, y: 12 * u)); p.addLine(to: CGPoint(x: 10 * u, y: 52 * u))
                    for y in [24.0, 38.0, 52.0] { p.move(to: CGPoint(x: 10 * u, y: y * u)); p.addLine(to: CGPoint(x: 22 * u, y: y * u)) }
                    p.move(to: CGPoint(x: 30 * u, y: 38 * u)); p.addLine(to: CGPoint(x: 30 * u, y: 50 * u)); p.addLine(to: CGPoint(x: 40 * u, y: 50 * u))
                }
                .stroke(ink.opacity(0.85), style: StrokeStyle(lineWidth: 3.5 * u, lineCap: .round, lineJoin: .round))
                FolderShape().fill(ink).frame(width: 16 * u, height: 12 * u).offset(x: 2 * u, y: 2 * u)
                ForEach([24.0, 38.0], id: \.self) { y in
                    FolderShape().fill(ink).frame(width: 14 * u, height: 10 * u).offset(x: 22 * u, y: (y - 5) * u)
                }
                RoundedRectangle(cornerRadius: 2 * u).fill(accent).frame(width: 12 * u, height: 9 * u).offset(x: 22 * u, y: 47.5 * u)
                RoundedRectangle(cornerRadius: 2 * u).fill(accent).frame(width: 12 * u, height: 9 * u).offset(x: 40 * u, y: 45.5 * u)
            }
            .frame(width: 56 * u, height: 60 * u)
        case .bolt:
            ZStack {
                FolderShape().fill(dark ? Color(hex: 0xFFC233).opacity(0.25) : Color.white.opacity(0.35)).frame(width: 66 * u, height: 50 * u)
                BoltShape().fill(dark ? Color(hex: 0xFFC233) : .white).frame(width: 28 * u, height: 44 * u)
                    .shadow(color: .black.opacity(0.15), radius: 1.5 * u, y: 1 * u)
            }
        case .tiles:
            let colors: [UInt32] = [0x2B6CF0, 0x22B573, 0xF5A623, 0xE5484D]
            VStack(spacing: 6 * u) {
                ForEach(0..<2) { r in
                    HStack(spacing: 6 * u) {
                        ForEach(0..<2) { c in
                            RoundedRectangle(cornerRadius: 6 * u, style: .continuous)
                                .fill(Color(hex: colors[r * 2 + c]).opacity(dark ? 0.9 : 1))
                                .frame(width: 26 * u, height: 26 * u)
                        }
                    }
                }
            }
        case .orbit:
            ZStack {
                Ellipse().stroke(ink.opacity(0.8), lineWidth: 3.5 * u).frame(width: 72 * u, height: 26 * u).rotationEffect(.degrees(-25))
                FolderShape().fill(ink).frame(width: 40 * u, height: 30 * u)
                Circle().fill(dark ? Color(hex: 0xFF7EB3) : .white).frame(width: 9 * u, height: 9 * u).offset(x: 30 * u, y: -14 * u)
            }
        case .outline:
            ZStack {
                FolderShape().stroke(ink, style: StrokeStyle(lineWidth: 6 * u, lineJoin: .round)).frame(width: 60 * u, height: 46 * u)
                Capsule().fill(ink).frame(width: 22 * u, height: 5 * u).offset(y: 6 * u)
            }
        case .paperPlane:
            ZStack {
                PlaneShape().fill(dark ? Color(hex: 0x4DE0D2) : .white).frame(width: 60 * u, height: 50 * u).offset(x: 2 * u, y: -2 * u)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0)); p.addQuadCurve(to: CGPoint(x: 30 * u, y: 8 * u), control: CGPoint(x: 10 * u, y: 14 * u))
                }
                .stroke((dark ? Color(hex: 0x4DE0D2) : Color.white).opacity(0.6), style: StrokeStyle(lineWidth: 2.5 * u, lineCap: .round, dash: [4 * u, 4 * u]))
                .frame(width: 30 * u, height: 14 * u).offset(x: -24 * u, y: 22 * u)
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

struct NeedleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

struct BoltShape: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(0.62, 0), (0.08, 0.56), (0.46, 0.56), (0.34, 1), (0.92, 0.40), (0.54, 0.40)]
        var p = Path()
        p.move(to: CGPoint(x: r.minX + pts[0].0 * r.width, y: r.minY + pts[0].1 * r.height))
        for pt in pts.dropFirst() { p.addLine(to: CGPoint(x: r.minX + pt.0 * r.width, y: r.minY + pt.1 * r.height)) }
        p.closeSubpath()
        return p
    }
}

struct PlaneShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY * 0.95))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.62, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.45, y: r.minY + r.height * 0.62))
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
                    option(id: design.id, name: design.name) {
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

    private func option<Content: View>(id: String, name: LocalizedStringKey, @ViewBuilder _ preview: () -> Content) -> some View {
        Button { selected = id } label: {
            VStack(spacing: 4) {
                preview()
                Text(name).font(.caption)
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
