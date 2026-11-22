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
    /// Color de acento del dibujo (detalles sobre la carpeta).
    let accent: Color
    let glyph: Glyph

    enum Glyph {
        case stack, orbit, fan, open, cloud, star, lock, download, gear, tags
        case doubleOrbit, leaf, moon, grid, terminal, glass, heart, drive, sparkle, wave
    }

    /// Número que se muestra en Ajustes (1…20).
    var number: Int { (Self.all.firstIndex { $0.id == id } ?? 0) + 1 }

    nonisolated(unsafe) static let all: [AppIconDesign] = [
        .init(id: "stack", name: "Stack", light: [.init(hex: 0xB78CFF), .init(hex: 0x6A3DE8)], dark: [.init(hex: 0x231A38), .init(hex: 0x110B1E)], accent: .init(hex: 0x8B5CF6), glyph: .stack),
        .init(id: "orbit", name: "Orbit", light: [.init(hex: 0xFF7EB3), .init(hex: 0xC2185B)], dark: [.init(hex: 0x2E1220), .init(hex: 0x16080F)], accent: .init(hex: 0xFF7EB3), glyph: .orbit),
        .init(id: "ocean", name: "Ocean Stack", light: [.init(hex: 0x5EC8FF), .init(hex: 0x1F5FD8)], dark: [.init(hex: 0x10223B), .init(hex: 0x07101D)], accent: .init(hex: 0x3B82F6), glyph: .fan),
        .init(id: "sunset", name: "Sunset", light: [.init(hex: 0xFFB36B), .init(hex: 0xF0517A)], dark: [.init(hex: 0x33171C), .init(hex: 0x180A0D)], accent: .init(hex: 0xF97362), glyph: .open),
        .init(id: "cloud", name: "Cloud", light: [.init(hex: 0x8FD3FF), .init(hex: 0x4A8DF0)], dark: [.init(hex: 0x15243A), .init(hex: 0x0A121E)], accent: .init(hex: 0x60A5FA), glyph: .cloud),
        .init(id: "star", name: "Favorites", light: [.init(hex: 0xFFD66B), .init(hex: 0xF59E0B)], dark: [.init(hex: 0x2E2510), .init(hex: 0x161106)], accent: .init(hex: 0xF59E0B), glyph: .star),
        .init(id: "lock", name: "Private", light: [.init(hex: 0x8A95A8), .init(hex: 0x3E4757)], dark: [.init(hex: 0x23262D), .init(hex: 0x111317)], accent: .init(hex: 0x64748B), glyph: .lock),
        .init(id: "download", name: "Downloads", light: [.init(hex: 0x6EE7B7), .init(hex: 0x0EA5A0)], dark: [.init(hex: 0x0F2A27), .init(hex: 0x071513)], accent: .init(hex: 0x14B8A6), glyph: .download),
        .init(id: "gear", name: "Utility", light: [.init(hex: 0xA5B4FC), .init(hex: 0x4F46E5)], dark: [.init(hex: 0x1C1B3A), .init(hex: 0x0D0C1D)], accent: .init(hex: 0x6366F1), glyph: .gear),
        .init(id: "tags", name: "Tags", light: [.init(hex: 0xF5F7FA), .init(hex: 0xD6DCE5)], dark: [.init(hex: 0x2A2D34), .init(hex: 0x141519)], accent: .init(hex: 0x3B82F6), glyph: .tags),
        .init(id: "doubleOrbit", name: "Galaxy", light: [.init(hex: 0x67E8F9), .init(hex: 0x6D28D9)], dark: [.init(hex: 0x16163A), .init(hex: 0x0A0A1C)], accent: .init(hex: 0x22D3EE), glyph: .doubleOrbit),
        .init(id: "leaf", name: "Leaf", light: [.init(hex: 0xA3E635), .init(hex: 0x16A34A)], dark: [.init(hex: 0x15270F), .init(hex: 0x0A1407)], accent: .init(hex: 0x22C55E), glyph: .leaf),
        .init(id: "moon", name: "Night", light: [.init(hex: 0x818CF8), .init(hex: 0x312E81)], dark: [.init(hex: 0x14132E), .init(hex: 0x080817)], accent: .init(hex: 0xFDE68A), glyph: .moon),
        .init(id: "grid", name: "Folders", light: [.init(hex: 0xFDA4AF), .init(hex: 0xE11D48)], dark: [.init(hex: 0x2E1018), .init(hex: 0x16070B)], accent: .init(hex: 0xF43F5E), glyph: .grid),
        .init(id: "terminal", name: "Terminal", light: [.init(hex: 0x4B5563), .init(hex: 0x111827)], dark: [.init(hex: 0x1F2227), .init(hex: 0x0A0B0D)], accent: .init(hex: 0x4ADE80), glyph: .terminal),
        .init(id: "glass", name: "Glass", light: [.init(hex: 0xC4B5FD), .init(hex: 0x38BDF8)], dark: [.init(hex: 0x1B1F3A), .init(hex: 0x0B0E1C)], accent: .init(hex: 0x818CF8), glyph: .glass),
        .init(id: "heart", name: "Loved", light: [.init(hex: 0xFF9EAD), .init(hex: 0xEF4469)], dark: [.init(hex: 0x30121A), .init(hex: 0x18080D)], accent: .init(hex: 0xF43F5E), glyph: .heart),
        .init(id: "drive", name: "Drive", light: [.init(hex: 0xD1D5DB), .init(hex: 0x6B7280)], dark: [.init(hex: 0x26282C), .init(hex: 0x121315)], accent: .init(hex: 0x22C55E), glyph: .drive),
        .init(id: "sparkle", name: "Sparkle", light: [.init(hex: 0xF0ABFC), .init(hex: 0x9333EA)], dark: [.init(hex: 0x2A1236), .init(hex: 0x14081B)], accent: .init(hex: 0xE879F9), glyph: .sparkle),
        .init(id: "wave", name: "Wave", light: [.init(hex: 0x5EEAD4), .init(hex: 0x2563EB)], dark: [.init(hex: 0x0F2233), .init(hex: 0x07111A)], accent: .init(hex: 0x38BDF8), glyph: .wave)
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
                        // Brillo suave arriba, como los iconos de macOS.
                        RoundedRectangle(cornerRadius: box * 0.225, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(dark ? 0.06 : 0.22), .clear], startPoint: .top, endPoint: .center))
                    )
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

    // Carpeta «de Mac»: blanca con degradado en claro; teñida del color del icono en oscuro.
    private var folderFill: LinearGradient {
        dark
            ? LinearGradient(colors: [design.accent.mix(with: .white, by: 0.15), design.accent.mix(with: .black, by: 0.25)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom)
    }
    private var folderBack: Color { dark ? design.accent.mix(with: .black, by: 0.45) : Color.white.opacity(0.55) }
    /// Detalles encima de la carpeta: color del icono en claro, blanco en oscuro.
    private var mark: Color { dark ? .white : design.accent }

    private func folder(_ w: CGFloat, _ h: CGFloat, _ u: CGFloat) -> some View {
        ZStack {
            FolderShape().fill(folderBack).offset(y: -h * 0.04)
            FolderBodyShape().fill(folderFill)
        }
        .frame(width: w * u, height: h * u)
        .shadow(color: .black.opacity(dark ? 0.35 : 0.18), radius: 2 * u, y: 1.5 * u)
    }

    @ViewBuilder
    private func glyph(u: CGFloat) -> some View {
        switch design.glyph {
        case .stack:
            ZStack {
                FolderShape().fill(dark ? design.accent.opacity(0.35) : Color.white.opacity(0.45)).frame(width: 56 * u, height: 40 * u).offset(x: -8 * u, y: -10 * u)
                FolderShape().fill(dark ? design.accent.opacity(0.6) : Color.white.opacity(0.7)).frame(width: 56 * u, height: 40 * u)
                FolderShape().fill(dark ? design.accent : Color.white).frame(width: 56 * u, height: 40 * u).offset(x: 8 * u, y: 10 * u)
                    .shadow(color: .black.opacity(0.2), radius: 2 * u, y: 1 * u)
            }
        case .orbit:
            ZStack {
                Ellipse().stroke((dark ? design.accent : .white).opacity(0.85), lineWidth: 3.5 * u).frame(width: 72 * u, height: 26 * u).rotationEffect(.degrees(-25))
                FolderShape().fill(dark ? design.accent.mix(with: .black, by: 0.2) : .white).frame(width: 40 * u, height: 30 * u)
                Circle().fill(dark ? design.accent : .white).frame(width: 9 * u, height: 9 * u).offset(x: 30 * u, y: -14 * u)
            }
        case .fan:
            ZStack {
                folder(46, 34, u).rotationEffect(.degrees(-16)).offset(x: -12 * u, y: 2 * u).opacity(0.75)
                folder(46, 34, u).rotationEffect(.degrees(16)).offset(x: 12 * u, y: 2 * u).opacity(0.85)
                folder(50, 37, u).offset(y: 6 * u)
            }
        case .open:
            ZStack {
                FolderShape().fill(folderBack).frame(width: 62 * u, height: 46 * u)
                RoundedRectangle(cornerRadius: 2 * u).fill(.white).frame(width: 40 * u, height: 34 * u).rotationEffect(.degrees(-6)).offset(x: -3 * u, y: -8 * u)
                    .shadow(color: .black.opacity(0.12), radius: 1 * u)
                RoundedRectangle(cornerRadius: 2 * u).fill(Color(white: 0.96)).frame(width: 40 * u, height: 34 * u).rotationEffect(.degrees(5)).offset(x: 4 * u, y: -6 * u)
                FolderBodyShape().fill(folderFill).frame(width: 62 * u, height: 46 * u).offset(y: 0)
                    .shadow(color: .black.opacity(0.18), radius: 2 * u, y: 1 * u)
            }
        case .cloud:
            ZStack {
                folder(62, 46, u)
                CloudShape().fill(mark).frame(width: 28 * u, height: 17 * u).offset(y: 5 * u)
            }
        case .star:
            ZStack {
                folder(62, 46, u)
                StarShape(points: 5).fill(mark).frame(width: 22 * u, height: 22 * u).offset(y: 5 * u)
            }
        case .lock:
            ZStack {
                folder(62, 46, u)
                Circle().trim(from: 0.5, to: 1).stroke(mark, lineWidth: 3.5 * u).frame(width: 13 * u, height: 13 * u).offset(y: 1.5 * u)
                Rectangle().fill(mark).frame(width: 3.5 * u, height: 5 * u).offset(x: -4.75 * u, y: 4 * u)
                Rectangle().fill(mark).frame(width: 3.5 * u, height: 5 * u).offset(x: 4.75 * u, y: 4 * u)
                RoundedRectangle(cornerRadius: 2.5 * u).fill(mark).frame(width: 20 * u, height: 14 * u).offset(y: 12 * u)
            }
        case .download:
            ZStack {
                folder(62, 46, u)
                ArrowDownShape().fill(mark).frame(width: 18 * u, height: 22 * u).offset(y: 5 * u)
            }
        case .gear:
            ZStack {
                folder(62, 46, u)
                GearShape(teeth: 8).fill(mark, style: FillStyle(eoFill: true)).frame(width: 24 * u, height: 24 * u).offset(y: 5 * u)
            }
        case .tags:
            ZStack {
                folder(62, 46, u)
                HStack(spacing: 3 * u) {
                    ForEach([0xEF4444, 0xF59E0B, 0x22C55E, 0x3B82F6, 0xA855F7] as [UInt32], id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 7 * u, height: 7 * u) }
                }
                .offset(y: 6 * u)
            }
        case .doubleOrbit:
            ZStack {
                Ellipse().stroke((dark ? design.accent : .white).opacity(0.8), lineWidth: 3 * u).frame(width: 74 * u, height: 24 * u).rotationEffect(.degrees(-28))
                Ellipse().stroke((dark ? Color(hex: 0xA78BFA) : .white).opacity(0.6), lineWidth: 3 * u).frame(width: 74 * u, height: 24 * u).rotationEffect(.degrees(28))
                folder(38, 28, u)
                Circle().fill(dark ? design.accent : .white).frame(width: 7 * u).offset(x: 31 * u, y: -16 * u)
                Circle().fill(dark ? Color(hex: 0xA78BFA) : .white).frame(width: 6 * u).offset(x: -31 * u, y: -16 * u)
            }
        case .leaf:
            ZStack {
                folder(62, 46, u)
                LeafShape().fill(mark).frame(width: 18 * u, height: 24 * u).rotationEffect(.degrees(35)).offset(y: 5 * u)
            }
        case .moon:
            ZStack {
                folder(62, 46, u)
                MoonShape().fill(dark ? design.accent : design.accent.mix(with: .orange, by: 0.3)).frame(width: 20 * u, height: 20 * u).offset(y: 5 * u)
                StarShape(points: 4).fill(dark ? design.accent : Color(hex: 0xF59E0B)).frame(width: 7 * u, height: 7 * u).offset(x: 13 * u, y: -2 * u)
            }
        case .grid:
            VStack(spacing: 5 * u) {
                ForEach(0..<2) { _ in HStack(spacing: 5 * u) { folder(28, 21, u); folder(28, 21, u) } }
            }
        case .terminal:
            ZStack {
                folder(62, 46, u)
                HStack(spacing: 2 * u) {
                    ChevronShape().stroke(dark ? design.accent : Color(hex: 0x111827), style: StrokeStyle(lineWidth: 3.5 * u, lineCap: .round, lineJoin: .round)).frame(width: 8 * u, height: 12 * u)
                    Capsule().fill(dark ? design.accent : Color(hex: 0x111827)).frame(width: 11 * u, height: 3.5 * u).offset(y: 5 * u)
                }
                .offset(y: 5 * u)
            }
        case .glass:
            ZStack {
                FolderShape().fill(.white.opacity(dark ? 0.12 : 0.3)).frame(width: 56 * u, height: 40 * u).offset(x: -6 * u, y: -8 * u)
                FolderShape().fill(.white.opacity(dark ? 0.2 : 0.45)).frame(width: 56 * u, height: 40 * u).offset(x: 6 * u, y: 6 * u)
                    .overlay(FolderShape().stroke(.white.opacity(0.7), lineWidth: 1.5 * u).frame(width: 56 * u, height: 40 * u).offset(x: 6 * u, y: 6 * u))
            }
        case .heart:
            ZStack {
                folder(62, 46, u)
                HeartShape().fill(mark).frame(width: 20 * u, height: 18 * u).offset(y: 6 * u)
            }
        case .drive:
            ZStack {
                RoundedRectangle(cornerRadius: 7 * u, style: .continuous).fill(LinearGradient(colors: dark ? [Color(white: 0.42), Color(white: 0.26)] : [.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom)).frame(width: 66 * u, height: 30 * u).offset(y: 10 * u)
                    .shadow(color: .black.opacity(0.2), radius: 2 * u, y: 1 * u)
                Circle().fill(design.accent).frame(width: 5 * u).offset(x: 24 * u, y: 10 * u)
                folder(36, 27, u).offset(y: -14 * u)
            }
        case .sparkle:
            ZStack {
                folder(62, 46, u)
                StarShape(points: 4, inner: 0.3).fill(mark).frame(width: 22 * u, height: 22 * u).offset(y: 5 * u)
                StarShape(points: 4, inner: 0.3).fill(mark.opacity(0.8)).frame(width: 9 * u, height: 9 * u).offset(x: 14 * u, y: -3 * u)
            }
        case .wave:
            ZStack {
                folder(62, 46, u)
                WaveShape().stroke(mark, style: StrokeStyle(lineWidth: 3.5 * u, lineCap: .round)).frame(width: 34 * u, height: 10 * u).offset(y: 2 * u)
                WaveShape().stroke(mark.opacity(0.6), style: StrokeStyle(lineWidth: 3.5 * u, lineCap: .round)).frame(width: 34 * u, height: 10 * u).offset(y: 11 * u)
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

/// Parte delantera de la carpeta (sin pestaña), para dar volumen.
struct FolderBodyShape: Shape {
    func path(in r: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(r.width, r.height) * 0.12, style: .continuous)
            .path(in: CGRect(x: r.minX, y: r.minY + r.height * 0.2, width: r.width, height: r.height * 0.8))
    }
}

struct StarShape: Shape {
    var points: Int
    var inner: CGFloat = 0.45
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2
        var p = Path()
        for i in 0..<(points * 2) {
            let a = Double(i) * .pi / Double(points) - .pi / 2
            let rad = i.isMultiple(of: 2) ? R : R * inner
            let pt = CGPoint(x: c.x + rad * cos(a), y: c.y + rad * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct CloudShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addEllipse(in: CGRect(x: r.minX, y: r.minY + h * 0.35, width: w * 0.45, height: h * 0.65))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.22, y: r.minY, width: w * 0.5, height: h * 0.85))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.5, y: r.minY + h * 0.25, width: w * 0.5, height: h * 0.75))
        p.addRect(CGRect(x: r.minX + w * 0.2, y: r.minY + h * 0.6, width: w * 0.6, height: h * 0.4))
        return p
    }
}

struct ArrowDownShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX + w * 0.35, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.65, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.65, y: r.minY + h * 0.5))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.5))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.5))
        p.addLine(to: CGPoint(x: r.minX + w * 0.35, y: r.minY + h * 0.5))
        p.closeSubpath()
        return p
    }
}

struct GearShape: Shape {
    var teeth: Int
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2, r1 = R * 0.78
        var p = Path()
        let steps = teeth * 4
        for i in 0..<steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            let rad = (i % 4 == 1 || i % 4 == 2) ? R : r1
            let pt = CGPoint(x: c.x + rad * cos(a), y: c.y + rad * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: c.x - R * 0.32, y: c.y - R * 0.32, width: R * 0.64, height: R * 0.64))
        return p
    }
}

struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX + r.width * 0.3, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX - r.width * 0.3, y: r.midY))
        return p
    }
}

struct MoonShape: Shape {
    func path(in r: CGRect) -> Path {
        let outer = Path(ellipseIn: r)
        let inner = Path(ellipseIn: r.offsetBy(dx: r.width * 0.32, dy: -r.height * 0.18))
        return outer.subtracting(inner)
    }
}

struct HeartShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.3), control1: CGPoint(x: r.minX + w * 0.2, y: r.minY + h * 0.75), control2: CGPoint(x: r.minX, y: r.minY + h * 0.55))
        p.addArc(center: CGPoint(x: r.minX + w * 0.25, y: r.minY + h * 0.27), radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: r.minX + w * 0.75, y: r.minY + h * 0.27), radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + h * 0.55), control2: CGPoint(x: r.maxX - w * 0.2, y: r.minY + h * 0.75))
        return p
    }
}

struct ChevronShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}

struct WaveShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.midY), control1: CGPoint(x: r.minX + r.width * 0.15, y: r.minY), control2: CGPoint(x: r.minX + r.width * 0.35, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.midY), control1: CGPoint(x: r.midX + r.width * 0.15, y: r.maxY), control2: CGPoint(x: r.midX + r.width * 0.35, y: r.maxY))
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
