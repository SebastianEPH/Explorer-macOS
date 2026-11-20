import AppKit

/// Fork: si un archivo ya existe en el destino y la opción es «Preguntar», se pregunta
/// qué hacer. «Aplicar a todos» vale solo para el resto de esa misma operación.
@MainActor
enum ConflictPrompt {
    struct Answer {
        let policy: ConflictPolicy
        let applyToAll: Bool
    }

    /// nil = detener la operación.
    static func ask(for source: URL, in destination: URL) -> Answer? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "“\(source.lastPathComponent)” already exists in “\(destination.lastPathComponent)”.")
        alert.informativeText = String(localized: "What do you want to do?")
        alert.addButton(withTitle: String(localized: "Replace"))
        alert.addButton(withTitle: String(localized: "Keep Both"))
        alert.addButton(withTitle: String(localized: "Skip"))
        alert.addButton(withTitle: String(localized: "Stop"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Apply to all")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let applyToAll = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn: return Answer(policy: .replace, applyToAll: applyToAll)
        case .alertSecondButtonReturn: return Answer(policy: .keepBoth, applyToAll: applyToAll)
        case .alertThirdButtonReturn: return Answer(policy: .skip, applyToAll: applyToAll)
        default: return nil
        }
    }
}
