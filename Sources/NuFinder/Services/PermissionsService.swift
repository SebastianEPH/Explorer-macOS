import AppKit
import ApplicationServices
import SwiftUI

/// Fork: Ajustes → Permisos. Muestra qué permisos de macOS tiene Explorer y permite pedirlos.
/// macOS no deja concederlos desde la app: «Solicitar» muestra el aviso del sistema
/// o abre el panel correspondiente de Ajustes del Sistema para que el usuario los active.
enum PermissionKind: String, CaseIterable, Identifiable {
    case fullDisk, accessibility, folders, systemEvents, iTerm

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .fullDisk: "Full Disk Access"
        case .accessibility: "Accessibility"
        case .folders: "Desktop, Documents and Downloads"
        case .systemEvents: "Automation: System Events"
        case .iTerm: "Automation: iTerm"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .fullDisk: "Browse every folder without asking (Library, other volumes, protected files)."
        case .accessibility: "Bring the new iTerm window to the front and take it out of full screen."
        case .folders: "Open your personal folders. Not needed if Full Disk Access is on."
        case .systemEvents: "Control windows through System Events."
        case .iTerm: "Open a new iTerm window in the current folder."
        }
    }

    var settingsURL: URL? {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        switch self {
        case .fullDisk: return URL(string: base + "Privacy_AllFiles")
        case .accessibility: return URL(string: base + "Privacy_Accessibility")
        case .folders: return URL(string: base + "Privacy_FilesAndFolders")
        case .systemEvents, .iTerm: return URL(string: base + "Privacy_Automation")
        }
    }
}

enum PermissionState {
    case granted, denied, unknown

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .denied: .red
        case .unknown: .secondary
        }
    }
}

enum PermissionsService {
    private static let bundleIDs: [PermissionKind: String] = [
        .systemEvents: "com.apple.systemevents",
        .iTerm: "com.googlecode.iterm2"
    ]

    /// Comprueba sin mostrar avisos (puede tardar: llamar fuera del hilo principal).
    static func state(of kind: PermissionKind) -> PermissionState {
        switch kind {
        case .fullDisk:
            let tcc = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
            return FileManager.default.isReadableFile(atPath: tcc.path)
                && (try? FileHandle(forReadingFrom: tcc))?.readData(ofLength: 1).isEmpty == false
                ? .granted : .denied
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .folders:
            return state(of: .fullDisk) == .granted ? .granted : .unknown
        case .systemEvents, .iTerm:
            return automationState(bundleIDs[kind]!, ask: false)
        }
    }

    /// Pide el permiso: aviso del sistema si existe, y si no, abre Ajustes del Sistema.
    static func request(_ kind: PermissionKind) {
        switch kind {
        case .fullDisk:
            open(kind)
        case .accessibility:
            let key = "AXTrustedCheckOptionPrompt" // = kAXTrustedCheckOptionPrompt
            if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary) { open(kind) }
        case .folders:
            // Leer cada carpeta hace que macOS muestre su aviso la primera vez.
            let home = FileManager.default.homeDirectoryForCurrentUser
            for name in ["Desktop", "Documents", "Downloads"] {
                _ = try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(name).path)
            }
        case .systemEvents, .iTerm:
            let id = bundleIDs[kind]!
            if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
               let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: app, configuration: config)
                Thread.sleep(forTimeInterval: 1.5)
            }
            if automationState(id, ask: true) == .denied { open(kind) }
        }
    }

    static func open(_ kind: PermissionKind) {
        if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
    }

    private static func automationState(_ bundleID: String, ask: Bool) -> PermissionState {
        var target = AEAddressDesc()
        let status: OSStatus = bundleID.withCString { pointer in
            guard AECreateDesc(typeApplicationBundleID, pointer, strlen(pointer), &target) == noErr else {
                return OSStatus(-1)
            }
            defer { AEDisposeDesc(&target) }
            return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
        }
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unknown // aún no se ha preguntado, o la app no está abierta
        }
    }
}

/// Sección «Permissions» de Ajustes.
struct PermissionsSection: View {
    @State private var states: [PermissionKind: PermissionState] = [:]

    var body: some View {
        Section("Permissions") {
            ForEach(PermissionKind.allCases) { kind in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: (states[kind] ?? .unknown).symbol)
                        .foregroundStyle((states[kind] ?? .unknown).color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                        Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if states[kind] != .granted {
                        Button("Request") {
                            DispatchQueue.global(qos: .userInitiated).async {
                                PermissionsService.request(kind)
                                Thread.sleep(forTimeInterval: 0.5)
                                refresh()
                            }
                        }
                    }
                    Button { PermissionsService.open(kind) } label: { Image(systemName: "gear") }
                        .buttonStyle(.borderless)
                        .help(Text("Open System Settings"))
                }
            }
            HStack {
                Button("Request All") {
                    DispatchQueue.global(qos: .userInitiated).async {
                        for kind in PermissionKind.allCases where states[kind] != .granted {
                            PermissionsService.request(kind)
                        }
                        refresh()
                    }
                }
                Button("Check Again") { refresh() }
            }
            Text("macOS only lets you grant these yourself: accept the prompt or turn Explorer on in System Settings. Some changes need Explorer to restart.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            var result: [PermissionKind: PermissionState] = [:]
            for kind in PermissionKind.allCases { result[kind] = PermissionsService.state(of: kind) }
            DispatchQueue.main.async { states = result }
        }
    }
}
