import AppKit
import SwiftUI

/// Fork: sección de la barra lateral bajo «Ubicaciones» con Papelera, Aplicaciones e iCloud Drive.
enum SidebarExtras: String, CaseIterable, Identifiable {
    case trash, applications, iCloud

    var id: String { rawValue }
    var key: String { "sidebar.shows.\(rawValue)" }

    var title: LocalizedStringKey {
        switch self {
        case .trash: "Trash"
        case .applications: "Applications"
        case .iCloud: "iCloud Drive"
        }
    }

    var symbol: String {
        switch self {
        case .trash: Self.trashIsEmpty ? "trash" : "trash.fill"
        case .applications: "square.grid.3x3.fill"
        case .iCloud: "icloud"
        }
    }

    var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .trash: return home.appendingPathComponent(".Trash", isDirectory: true)
        case .applications: return URL(filePath: "/Applications", directoryHint: .isDirectory)
        case .iCloud: return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        }
    }

    /// iCloud Drive solo si está activado en este Mac.
    var isAvailable: Bool { self != .iCloud || FileManager.default.fileExists(atPath: url.path) }

    static var trashIsEmpty: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: SidebarExtras.trash.url.path)) ?? [])
            .allSatisfy { $0 == ".DS_Store" }
    }

    /// Borra para siempre lo que hay en la Papelera, tras confirmarlo.
    @MainActor
    static func emptyTrash() -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Empty the Trash?")
        alert.informativeText = String(localized: "The items will be deleted permanently. This can’t be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Empty Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        do {
            for name in try FileManager.default.contentsOfDirectory(atPath: trash.url.path) {
                try FileManager.default.removeItem(at: trash.url.appendingPathComponent(name))
            }
            return nil
        } catch {
            return String(localized: "Couldn’t empty the Trash: \(error.localizedDescription). Explorer may need Full Disk Access (Settings → System).")
        }
    }
}

struct SidebarExtrasSection: View {
    @EnvironmentObject private var browser: BrowserModel
    @AppStorage(SidebarExtras.trash.key) private var showsTrash = true
    @AppStorage(SidebarExtras.applications.key) private var showsApplications = true
    @AppStorage(SidebarExtras.iCloud.key) private var showsICloud = true

    private var visible: [SidebarExtras] {
        SidebarExtras.allCases.filter { item in
            item.isAvailable && (item == .trash ? showsTrash : item == .applications ? showsApplications : showsICloud)
        }
    }

    var body: some View {
        if !visible.isEmpty {
            Section("More") {
                ForEach(visible) { item in
                    Button { open(item) } label: {
                        Label(item.title, systemImage: item.symbol).lineLimit(1)
                    }
                    .buttonStyle(SidebarRowButtonStyle(isCurrent: item.url.standardizedFileURL == browser.currentURL.standardizedFileURL))
                    .contextMenu {
                        if item == .trash {
                            Button("Empty Trash…", role: .destructive) {
                                if let error = SidebarExtras.emptyTrash() { browser.errorMessage = error }
                                if browser.currentURL.standardizedFileURL == item.url.standardizedFileURL { browser.reload() }
                            }
                            .disabled(SidebarExtras.trashIsEmpty)
                        }
                        Button("Open in New Tab") { browser.newTab(at: item.url) }
                    }
                }
            }
        }
    }
}

extension SidebarExtrasSection {
    /// La Papelera necesita «Acceso total al disco»: sin él, se explica y se ofrece abrir el ajuste.
    fileprivate func open(_ item: SidebarExtras) {
        if item == .trash, (try? FileManager.default.contentsOfDirectory(atPath: item.url.path)) == nil {
            let alert = NSAlert()
            alert.messageText = String(localized: "Explorer needs Full Disk Access to show the Trash")
            alert.informativeText = String(localized: "macOS protects the Trash. Turn on Explorer in Privacy & Security → Full Disk Access, then reopen Explorer.")
            alert.addButton(withTitle: String(localized: "Open Settings"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn { PermissionsService.open(.fullDisk) }
            return
        }
        browser.navigate(to: item.url)
    }
}

/// Opciones en Ajustes → Apariencia → Barra lateral.
struct SidebarExtrasToggles: View {
    @AppStorage(SidebarExtras.trash.key) private var showsTrash = true
    @AppStorage(SidebarExtras.applications.key) private var showsApplications = true
    @AppStorage(SidebarExtras.iCloud.key) private var showsICloud = true

    var body: some View {
        Toggle(isOn: $showsTrash) {
            Label("Trash", systemImage: "trash")
            Text("Right-click it to empty the Trash.")
        }
        Toggle(isOn: $showsApplications) { Label("Applications", systemImage: "square.grid.3x3.fill") }
        Toggle(isOn: $showsICloud) {
            Label("iCloud Drive", systemImage: "icloud")
            Text("Only appears if iCloud Drive is turned on on this Mac.")
        }
    }
}
