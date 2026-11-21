import Foundation

/// Fork: macOS muestra en gris cómo sigue la palabra al escribir (predicción de texto).
/// En un explorador de archivos estorba al renombrar, así que se desactiva solo dentro de Explorer.
enum TextPredictionSettings {
    static let key = "NSAutomaticInlinePredictionEnabled"

    static func apply(_ defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: key)
    }
}
