import AppKit
import SwiftUI

/// Actualizaciones desde las compilaciones del fork (GitHub Releases `build-N`).
/// La configuración vive en UserDefaults, fuera de la app, así que reemplazar
/// el paquete .app no la toca.
@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()
    static let repository = "SebastianEPH/Freeloader"

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case installing(String)
        case failed(String)
    }

    private(set) var state: State = .idle

    /// Número de compilación que el pipeline escribe en `FLBuildNumber` (0 si se compiló a mano).
    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "FLBuildNumber") as? String ?? "") ?? 0
    }

    /// Versión X.Y.Z que pone el pipeline; una compilación local no cuenta como publicada.
    var currentVersion: String {
        currentBuild > 0 ? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") : "0"
    }

    /// Compara versiones número a número (1.0.10 > 1.0.9).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func check() async {
        state = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                state = .failed(String(localized: "No builds have been published yet."))
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard version.first?.isNumber == true,
                  let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
                  let url = URL(string: asset.browser_download_url) else {
                state = .failed(String(localized: "The latest release has no valid .zip file."))
                return
            }
            state = Self.isNewer(version, than: currentVersion) ? .available(version: version, url: url) : .upToDate
        } catch {
            state = .failed(String(localized: "Could not reach GitHub: \(error.localizedDescription)"))
        }
    }

    func install(from url: URL) async {
        do {
            state = .installing(String(localized: "Downloading…"))
            let (zip, _) = try await URLSession.shared.download(from: url)
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("FreeloaderUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            state = .installing(String(localized: "Unpacking…"))
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError(String(localized: "The .zip file does not contain the app."))
            }

            // Un script espera a que esta app se cierre, cambia el paquete y la vuelve a abrir.
            state = .installing(String(localized: "Installing and restarting…"))
            // Si la app cambió de nombre (p. ej. Freeloader.app → Explorer.app), se borra la vieja.
            let current = Bundle.main.bundleURL
            let target = current.deletingLastPathComponent().appendingPathComponent(newApp.lastPathComponent)
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            rm -rf "$4" "$2" && mv "$1" "$2" && xattr -dr com.apple.quarantine "$2" 2>/dev/null
            open "$2"
            rm -rf "$3"
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script, "sh", newApp.path, target.path, work.path, current.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed(String(localized: "Could not install: \(error.localizedDescription)"))
        }
    }

    /// Menú Ayuda → «Buscar actualizaciones…»: consulta y pregunta con una alerta.
    func checkFromMenu() async {
        await check()
        let alert = NSAlert()
        switch state {
        case .available(let version, let url):
            alert.messageText = String(localized: "Version \(version) is available")
            alert.informativeText = String(localized: "Explorer will download it, replace itself and restart. Your settings are kept.")
            alert.addButton(withTitle: String(localized: "Install and Restart"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn { await install(from: url) }
        case .upToDate:
            alert.messageText = String(localized: "You have the latest version")
            alert.informativeText = String(localized: "Installed version: \(currentVersion)")
            alert.runModal()
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Could not check for updates")
            alert.informativeText = message
            alert.runModal()
        default:
            break
        }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError(String(localized: "\(tool) failed (\(process.terminationStatus)).")) }
    }

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}

struct UpdatesSection: View {
    @State private var updates = UpdateService.shared

    var body: some View {
        Section("Updates") {
            LabeledContent("Installed version", value: updates.currentBuild > 0 ? updates.currentVersion : String(localized: "local"))
            HStack {
                switch updates.state {
                case .available(let version, let url):
                    Text("Version \(version) is available")
                    Spacer()
                    Button("Install and Restart") { Task { await updates.install(from: url) } }
                case .installing(let step):
                    ProgressView().controlSize(.small)
                    Text(step)
                default:
                    Button("Check for Updates") { Task { await updates.check() } }
                        .disabled(updates.state == .checking)
                    if updates.state == .checking { ProgressView().controlSize(.small) }
                    if updates.state == .upToDate { Text("You have the latest version").foregroundStyle(.secondary) }
                }
            }
            if case .failed(let message) = updates.state {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Text("Downloads the latest build from github.com/\(UpdateService.repository). Your settings are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Menú Ayuda: versión instalada, buscar actualizaciones y novedades en GitHub.
struct HelpVersionItems: View {
    private let updates = UpdateService.shared

    var body: some View {
        Divider()
        Text(updates.currentBuild > 0
             ? "Explorer \(updates.currentVersion) (build \(updates.currentBuild))"
             : "Explorer (local build)")
        Button("Check for Updates…") { Task { await updates.checkFromMenu() } }
        Button("Release Notes on GitHub") {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(UpdateService.repository)/releases")!)
        }
    }
}
