import AppKit
import SwiftUI

/// Idioma de la app. macOS lo lee de `AppleLanguages` al arrancar, así que
/// cambiarlo requiere reiniciar. «Sistema» borra la preferencia propia.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System Default"
        case .english: "English"
        case .spanish: "Español"
        }
    }

    static var current: AppLanguage {
        guard let languages = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        return first.hasPrefix("es") ? .spanish : first.hasPrefix("en") ? .english : .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$1\"", "sh", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}

struct LanguageSection: View {
    @State private var selection = AppLanguage.current
    @State private var initial = AppLanguage.current

    var body: some View {
        Section("Language") {
            Picker("Language", selection: $selection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .onChange(of: selection) { _, value in value.apply() }
            if selection != initial {
                HStack {
                    Text("Restart Explorer to apply the change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { AppLanguage.relaunch() }
                }
            }
        }
    }
}
