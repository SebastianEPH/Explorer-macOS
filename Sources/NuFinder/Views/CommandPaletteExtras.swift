import SwiftUI

/// Fork: añadidos a la paleta de comandos del autor (⌘⇧P): cabecera con título, explicación y
/// botón de cerrar (antes solo se cerraba con Esc, sin decirlo) y búsqueda también en el idioma de la app.
enum CommandPaletteExtras {
    static let closeButtonKey = "palette.closeButton"

    /// Coincide con el nombre en inglés (original) o con el traducido («carpeta» → «New Folder»).
    static func matches(_ command: String, _ query: String, bundle: Bundle = .main) -> Bool {
        command.localizedCaseInsensitiveContains(query)
            || bundle.localizedString(forKey: command, value: command, table: nil)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
    }
}

struct CommandPaletteHeader: View {
    @AppStorage(CommandPaletteExtras.closeButtonKey) private var shows = true
    let close: () -> Void

    var body: some View {
        if shows {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Command Palette").font(.headline)
                    Text("Type to find an action and click it. Esc closes.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help(Text("Close"))
                    .accessibilityIdentifier("commandPalette.close")
            }
        }
    }
}

/// Ajustes → General → Atajos: interruptor con vista previa de la cabecera.
struct CommandPaletteSettingsRow: View {
    @AppStorage(CommandPaletteExtras.closeButtonKey) private var shows = true
    var body: some View {
        SettingsPreviewBox(title: "Preview: top of the Command Palette") {
            VStack(alignment: .leading, spacing: 8) {
                CommandPaletteHeader(close: {})
                RoundedRectangle(cornerRadius: 5).strokeBorder(.separator).frame(height: 22)
                    .overlay(alignment: .leading) { Text("Type a command").font(.caption).foregroundStyle(.tertiary).padding(.leading, 6) }
            }
            .animation(.default, value: shows)
        }
        Toggle(isOn: $shows) {
            Label("Title and close button in the Command Palette", systemImage: "xmark.circle")
            Text("The Command Palette (⌘⇧P) finds any action by name. Off: as in the original, it only closes with Esc.")
        }
    }
}
