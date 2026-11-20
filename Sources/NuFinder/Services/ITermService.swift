import AppKit

/// iTerm ignora «abrir carpeta» si ya está abierto (solo se pone delante).
/// Con AppleScript se le pide siempre una ventana nueva en esa carpeta.
/// La primera vez macOS pregunta si Explorer puede controlar iTerm.
/// Con el permiso de Accesibilidad, además, la ventana nueva nunca sale en pantalla completa.
enum ITermService {
    static func handles(_ application: URL) -> Bool {
        application.lastPathComponent.lowercased().hasPrefix("iterm")
    }

    static func openWindow(at url: URL) {
        let script = """
        on run argv
            set dirPath to item 1 of argv
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "cd " & quoted form of dirPath & " && clear"
                end tell
            end tell
            -- Si la ventana de iTerm de antes estaba en pantalla completa, la nueva también:
            -- se le quita (necesita el permiso de Accesibilidad; sin él, se ignora).
            try
                delay 0.6
                tell application "System Events" to tell process "iTerm2"
                    set value of attribute "AXFullScreen" of window 1 to false
                end tell
            end try
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, url.path]
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "Could not open iTerm: \(message)")
                alert.runModal()
            }
        }
        try? process.run()
    }
}
