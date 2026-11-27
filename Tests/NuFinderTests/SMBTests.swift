import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NuFinder

/// Servidor SMB (el de macOS). Las pruebas sustituyen el ejecutor: nunca tocan Compartir archivos de verdad.
@Suite(.serialized) @MainActor
struct SMBTests {
    /// Sistema falso: guarda las órdenes de administrador y simula su efecto.
    final class FakeSystem: @unchecked Sendable {
        var running = false
        var shares: [String: (path: String, ro: Bool, guest: Bool)] = [:]
        var adminScripts: [String] = []
        var refuse = false

        var runner: SMBServer.Runner {
            SMBServer.Runner(
                run: { [self] executable, _ in
                    if executable.hasSuffix("netstat") {
                        return (0, running ? "tcp4  0  0  *.445   *.*   LISTEN\n" : "tcp4  0  0  *.22   *.*   LISTEN\n")
                    }
                    let json = shares.map { name, s in
                        "\"\(name)\": {\"path\": \"\(s.path)\", \"smb_name\": \"\(name)\", \"smb_shared\": 1, \"smb_read_only\": \(s.ro ? 1 : 0), \"smb_guest_access\": \(s.guest ? 1 : 0)}"
                    }.joined(separator: ",")
                    return (0, "{\(json)}")
                },
                runAsAdmin: { [self] script in
                    if refuse { return "Cancelled" }
                    adminScripts.append(script)
                    if script.contains("launchctl enable") { running = true }
                    if script.contains("launchctl disable") { running = false }
                    if let range = script.range(of: "sharing -a ") {
                        let parts = script[range.upperBound...].components(separatedBy: "'")
                        shares[parts[3]] = (parts[1], script.contains("-R 1"), script.contains("-g 001"))
                    }
                    if let range = script.range(of: "sharing -r '") {
                        shares[String(script[range.upperBound...].dropLast())] = nil
                    }
                    return nil
                })
        }
    }

    private func withFake(_ body: (FakeSystem) async throws -> Void) async rethrows {
        let old = SMBServer.runner, fake = FakeSystem()
        SMBServer.runner = fake.runner
        defer { SMBServer.runner = old }
        try await body(fake)
        await SMBServerController.shared.refresh()
    }

    // MARK: unitarias

    @Test func parsesRealSharingOutput() {
        let json = """
        {"Pública": {"path": "/Users/a/Public", "smb_name": "Pública", "smb_shared": 1, "smb_read_only": 0, "smb_guest_access": 1},
         "Oculta": {"path": "/x", "smb_shared": 0}}
        """
        #expect(SMBServer.parseShares(json) == [SMBShare(name: "Pública", path: "/Users/a/Public", readOnly: false, guest: true)])
        #expect(SMBServer.parseShares("basura").isEmpty)
        #expect(SMBServer.parseListening("tcp4 0 0 *.445 *.* LISTEN"))
        #expect(SMBServer.parseListening("tcp6 0 0 *.445 *.* LISTEN"))
        #expect(!SMBServer.parseListening("tcp4 0 0 *.4450 *.* LISTEN\ntcp4 0 0 10.0.0.2.445 10.0.0.3.5000 ESTABLISHED"))
    }

    // Rutas con espacios y comillas no rompen la orden de shell ni el AppleScript.
    @Test func scriptsAreSafelyQuoted() {
        let script = SMBServer.addScript(path: "/Users/a/Mis 'cosas'", name: "Mis 'cosas'", readOnly: true, guest: false)
        #expect(script == "$SUDO /usr/sbin/sharing -a '/Users/a/Mis '\\''cosas'\\''' -n 'Mis '\\''cosas'\\''' -S 'Mis '\\''cosas'\\''' -s 001 -g 000 -R 1")
        #expect(SMBServer.appleScriptEscaped(#"a "b" \c"#) == #"a \"b\" \\c"#)
        #expect(SMBServer.removeScript(name: "X") == "$SUDO /usr/sbin/sharing -r 'X'")
        // La regla de sudo solo permite las órdenes del servidor SMB.
        let rule = AdminAuthorization.sudoersRule(user: "ana")
        #expect(rule.contains("ana ALL=(root) NOPASSWD: /usr/sbin/sharing *") && !rule.contains("ALL=(ALL)") && !rule.contains("/bin/sh"))
        #expect(SMBServer.enableScript().contains("launchctl enable system/com.apple.smbd"))
        #expect(SMBServer.disableScript().contains("launchctl disable system/com.apple.smbd"))
    }

    // Leer el estado real del Mac no pide permisos ni cambia nada.
    @Test func readingRealStateNeedsNoAdmin() {
        _ = SMBServer.isRunning()
        for share in SMBServer.shares() { #expect(!share.name.isEmpty && share.path.hasPrefix("/")) }
        #expect(SMBServer.addresses().allSatisfy { $0.hasPrefix("smb://") })
    }

    // MARK: completas y de flujo

    /// Flujo: en Ajustes/menú se comparte la carpeta actual (enciende el servidor con una sola contraseña)
    /// → aparece compartida → se deja de compartir → se apaga el servidor.
    @Test func shareFolderFlow() async throws {
        try await withFake { fake in
            let controller = SMBServerController.shared
            await controller.refresh()
            #expect(!controller.running && controller.shares.isEmpty)

            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Proyecto X")
            await controller.share(folder, readOnly: true)
            #expect(fake.adminScripts.count == 1) // encender + compartir = una sola petición de contraseña
            #expect(controller.running)
            #expect(controller.shares == [SMBShare(name: "Proyecto X", path: folder.path, readOnly: true, guest: false)])

            await controller.share(folder.deletingLastPathComponent().appendingPathComponent("Otra"), guest: true)
            #expect(!fake.adminScripts[1].contains("launchctl")) // ya estaba encendido
            #expect(controller.shares.map(\.name) == ["Otra", "Proyecto X"] && controller.shares[0].guest)

            await controller.unshare(controller.shares[1])
            #expect(controller.shares.map(\.name) == ["Otra"])
            await controller.setRunning(false)
            #expect(!controller.running && controller.message == nil)
        }
    }

    /// Si se cancela la contraseña de administrador no cambia nada y se dice por qué.
    @Test func cancelledPasswordChangesNothing() async throws {
        try await withFake { fake in
            fake.refuse = true
            let controller = SMBServerController.shared
            await controller.setRunning(true)
            #expect(!controller.running && controller.message == "Cancelled")
        }
    }

    // Menú y Ajustes con el mismo nombre («Red»), sin «cliente/servidor/FTP/SMB» en el menú.
    @Test func networkMenuAndSettingsShareName() throws {
        let settings = try String(contentsOfFile: "Sources/NuFinder/Views/SettingsView.swift", encoding: .utf8)
        #expect(settings.contains("settingsTab(LocalizedStringKey(NetworkMenu.title)"))
        let es = try #require(Bundle(path: "Localization/es.lproj"))
        #expect(es.localizedString(forKey: NetworkMenu.title, value: nil, table: nil) == "Red")
        let source = try String(contentsOfFile: "Sources/NuFinder/Views/NetworkWindows.swift", encoding: .utf8)
        let menu = source.components(separatedBy: "struct NetworkMenu")[1].components(separatedBy: "struct NetworkSettingsSection")[0]
        // FTP y SMB a la vista, cada acción dice a qué tipo de servidor va, y hay acceso a la configuración.
        for text in ["Menu(\"FTP\")", "Menu(\"SMB (Windows, NAS, Mac)\")", "Connect to an FTP Server…", "Connect to an SMB Server…",
                     "Share a Folder by FTP…", "Share a Folder by SMB…", "Network Settings…"] { #expect(menu.contains(text), "\(text)") }
    }
}
