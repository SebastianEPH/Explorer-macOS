import AppKit
import ServiceManagement
import SwiftUI

/// «Abrir Explorer al pulsar Finder»: con Finder cerrado, pulsar su icono del Dock
/// lo arranca; Explorer lo detecta, lo vuelve a cerrar y abre una ventana propia.
/// Solo funciona mientras Explorer está abierto (por eso se añade al inicio de sesión).
@MainActor
enum FinderRedirectService {
    static let enabledKey = "finderRedirect.enabled"
    private static let finderID = "com.apple.finder"
    private static var observers: [NSObjectProtocol] = []
    private static let startedAt = Date()
    private static var redirecting = false

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func start() {
        guard observers.isEmpty else { return }
        // Arrancar (Finder estaba cerrado) o pasar al frente (ya estaba abierto):
        // las dos cosas pasan al pulsar su icono del Dock.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == "com.apple.finder" else { return }
                MainActor.assumeIsolated { redirect(app) }
            })
        }
    }

    private static func redirect(_ finder: NSRunningApplication?) {
        // Al iniciar sesión macOS arranca Finder por su cuenta: eso no es un clic.
        guard isEnabled, Date().timeIntervalSince(startedAt) > 15, !redirecting else { return }
        redirecting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            finder?.terminate()
            WindowService.open(at: FileManager.default.homeDirectoryForCurrentUser)
            NSApp.activate(ignoringOtherApps: true)
            redirecting = false
        }
    }

    /// Activar: permite cerrar Finder, lo cierra y abre Explorer al iniciar sesión.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            shell("defaults write com.apple.finder QuitMenuItem -bool true")
            NSRunningApplication.runningApplications(withBundleIdentifier: finderID).forEach { $0.terminate() }
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
            shell("open -b \(finderID)")
        }
    }

    private static func shell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try? process.run()
        process.waitUntilExit()
    }
}

struct FinderRedirectSection: View {
    @State private var enabled = FinderRedirectService.isEnabled

    var body: some View {
        Section("Finder") {
            Toggle("Open Explorer when clicking Finder in the Dock", isOn: $enabled)
                .onChange(of: enabled) { _, value in FinderRedirectService.setEnabled(value) }
            FinderRedirectPreview(enabled: enabled) // Fork
            Text("Finder is closed; clicking its Dock icon opens Explorer instead. Explorer opens at login so it can catch the click.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
