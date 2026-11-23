import AppKit

/// Fork: expulsar discos (USB, imágenes ISO/DMG montadas) sin que falle porque el propio
/// Explorer lo tiene ocupado.
///
/// Antes `unmountAndEjectDevice` se llamaba en el hilo principal (la ventana se congelaba
/// mientras macOS desmontaba) y, si en ese momento se estaba calculando el tamaño de alguna
/// carpeta del disco (eso deja carpetas abiertas), macOS respondía «en uso» y no se reintentaba.
/// Ahora: se cancela ese trabajo, se expulsa en segundo plano y se reintenta unas veces.
enum VolumeEject {
    static let retriesKey = "volumes.ejectRetries"

    /// Intentos en total (Ajustes → Archivos → Paneles). Sin tocar nada: 1, como el original.
    static var attempts: Int {
        let stored = UserDefaults.standard.integer(forKey: retriesKey)
        return stored > 0 ? min(stored, 10) : 1
    }

    /// Hace falta un `eject` sustituible en pruebas: por defecto, el de macOS.
    nonisolated(unsafe) static var ejector: @Sendable (URL) throws -> Void = { url in
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }

    @MainActor
    static func eject(_ url: URL, attempts: Int = attempts, pause: Duration = .milliseconds(600)) async throws {
        FolderSizeService.shared.cancelAll(under: url)
        var lastError: Error?
        for attempt in 1...max(1, attempts) {
            let ejector = ejector
            let result: Error? = await BackgroundWork.run {
                do { try ejector(url); return nil } catch { return error }
            }
            guard let result else { return }
            lastError = result
            if attempt < attempts { try? await Task.sleep(for: pause) }
        }
        if let lastError { throw lastError }
    }
}

/// Fork: cuántas carpetas calculan su tamaño a la vez.
/// Sin tocar nada: 2 (original). 0 = automático, la mitad de los núcleos del Mac.
enum FolderSizeParallel {
    static let key = "files.folderSizeParallel"

    static func count(setting: Int?, cores: Int) -> Int {
        guard let setting else { return 2 }
        if setting <= 0 { return max(2, cores / 2) }
        return min(setting, 64)
    }

    static var current: Int {
        count(setting: UserDefaults.standard.object(forKey: key) as? Int,
              cores: ProcessInfo.processInfo.activeProcessorCount)
    }
}

import SwiftUI

struct FolderSizeParallelPicker: View {
    @AppStorage(FolderSizeParallel.key) private var parallel = 2
    @AppStorage(VolumeEject.retriesKey) private var ejectRetries = 1
    private let cores = ProcessInfo.processInfo.activeProcessorCount

    var body: some View {
        Picker(selection: $parallel) {
            Text("2 (original)").tag(2)
            Text("Automatic (\(FolderSizeParallel.count(setting: 0, cores: cores)))").tag(0)
            ForEach([4, 8, 16], id: \.self) { Text("\($0)").tag($0) }
        } label: {
            Label("Folder sizes calculated at once", systemImage: "cpu")
            Text("More at once fills the Size column sooner. Automatic uses half of this Mac’s \(cores) cores.")
        }
        HStack(spacing: 4) {
            ForEach(0..<min(FolderSizeParallel.count(setting: parallel, cores: cores), 16), id: \.self) { _ in
                Image(systemName: "folder.fill").foregroundStyle(.tint)
            }
        }
        .font(.caption)
        .accessibilityHidden(true)
        Stepper(value: $ejectRetries, in: 1...10) {
            Label("Eject attempts: \(ejectRetries)", systemImage: "eject")
            Text("If a disk or mounted image (ISO, DMG) is busy, Explorer stops its own work on it and tries again. 1 = original.")
        }
    }
}
