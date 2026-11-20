import AppKit
import SwiftUI

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
        // Vista previa de los dos archivos para decidir con cuál quedarse.
        let comparison = NSHostingView(rootView: ConflictComparisonView(
            existing: destination.appendingPathComponent(source.lastPathComponent),
            incoming: source
        ))
        comparison.frame = NSRect(x: 0, y: 0, width: 460, height: 250)
        alert.accessoryView = comparison
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

/// Los dos archivos lado a lado: miniatura, tamaño y fecha de modificación.
private struct ConflictComparisonView: View {
    let existing: URL
    let incoming: URL

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            FileCard(title: "Already in destination", url: existing, other: incoming)
            FileCard(title: "New (being pasted)", url: incoming, other: existing)
        }
        .padding(.vertical, 6)
        .frame(width: 460, height: 250)
    }
}

private struct FileCard: View {
    let title: LocalizedStringKey
    let url: URL
    let other: URL
    @State private var image: NSImage?

    private var values: URLResourceValues? {
        try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey, .contentModificationDateKey, .isDirectoryKey])
    }

    private func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                }
            }
            .frame(width: 200, height: 140)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
            .help(Text("Double-click to open"))
            if let size = values?.totalFileSize ?? values?.fileSize, values?.isDirectory != true {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.callout.monospacedDigit())
            } else if values?.isDirectory == true {
                Text("Folder").font(.callout)
            }
            if let date = modified(url) {
                HStack(spacing: 4) {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                    if let otherDate = modified(other), date > otherDate {
                        Text("Newer").font(.caption2.bold()).foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            image = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 200, height: 140), scale: 2)
        }
    }
}
