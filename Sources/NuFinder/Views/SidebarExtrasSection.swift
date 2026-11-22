import AppKit
import SwiftUI

/// Fork: accesos extra en «Ubicaciones»: AirDrop, Red, nubes (OneDrive, Google Drive, Dropbox…),
/// iCloud Drive, Aplicaciones y Papelera. Cada tipo se muestra u oculta en Ajustes → Apariencia.
enum SidebarExtras: String, CaseIterable, Identifiable {
    case airDrop, network, cloud, iCloud, applications, trash

    var id: String { rawValue }
    var key: String { "sidebar.shows.\(rawValue)" }

    var title: LocalizedStringKey {
        switch self {
        case .airDrop: "AirDrop"
        case .network: "Network"
        case .cloud: "Cloud storage (OneDrive, Google Drive, Dropbox…)"
        case .iCloud: "iCloud Drive"
        case .applications: "Applications"
        case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .airDrop: "airplayaudio"
        case .network: "network"
        case .cloud: "cloud"
        case .iCloud: "icloud"
        case .applications: "square.grid.3x3.fill"
        case .trash: Self.trashIsEmpty ? "trash" : "trash.fill"
        }
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var trashURL: URL { home.appendingPathComponent(".Trash", isDirectory: true) }
    static var iCloudURL: URL { home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true) }
    static let applicationsURL = URL(filePath: "/Applications", directoryHint: .isDirectory)

    static var trashIsEmpty: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: trashURL.path)) ?? []).allSatisfy { $0 == ".DS_Store" }
    }

    /// Carpetas de nubes que macOS monta en ~/Library/CloudStorage (OneDrive-Personal, GoogleDrive-…, Dropbox…).
    static func cloudFolders() -> [(name: String, url: URL)] {
        let root = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { (cloudName($0), root.appendingPathComponent($0, isDirectory: true)) }
    }

    /// "OneDrive-Personal" → "OneDrive (Personal)", "GoogleDrive-ana@x.com" → "Google Drive (ana@x.com)".
    static func cloudName(_ folder: String) -> String {
        let parts = folder.split(separator: "-", maxSplits: 1).map(String.init)
        let provider = parts[0] == "GoogleDrive" ? "Google Drive" : parts[0]
        return parts.count > 1 ? "\(provider) (\(parts[1]))" : provider
    }

    static func cloudSymbol(_ name: String) -> String {
        name.hasPrefix("Dropbox") ? "shippingbox" : name.hasPrefix("Google") ? "externaldrive.badge.icloud" : "cloud"
    }

    /// Abre una ventana que solo existe en Finder.
    @MainActor
    static func openFinderWindow(_ app: String) {
        NSWorkspace.shared.open(URL(filePath: "/System/Library/CoreServices/Finder.app/Contents/Applications/\(app).app"))
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
            for name in try FileManager.default.contentsOfDirectory(atPath: trashURL.path) {
                try FileManager.default.removeItem(at: trashURL.appendingPathComponent(name))
            }
            return nil
        } catch {
            return String(localized: "Couldn’t empty the Trash: \(error.localizedDescription). Explorer may need Full Disk Access (Settings → System).")
        }
    }
}

/// Filas que se añaden dentro de «Ubicaciones», antes de «Conectarse al servidor».
struct SidebarExtrasRows: View {
    @EnvironmentObject private var browser: BrowserModel
    @AppStorage(SidebarExtras.airDrop.key) private var showsAirDrop = true
    @AppStorage(SidebarExtras.network.key) private var showsNetwork = true
    @AppStorage(SidebarExtras.cloud.key) private var showsCloud = true
    @AppStorage(SidebarExtras.iCloud.key) private var showsICloud = true
    @AppStorage(SidebarExtras.applications.key) private var showsApplications = true
    @AppStorage(SidebarExtras.trash.key) private var showsTrash = true

    var body: some View {
        if showsAirDrop {
            row(SidebarExtras.airDrop.title, SidebarExtras.airDrop.symbol, url: nil) { airDrop() }
                .help(Text("Send the selected files by AirDrop, or open the AirDrop window"))
        }
        if showsNetwork {
            row(SidebarExtras.network.title, SidebarExtras.network.symbol, url: nil) { SidebarExtras.openFinderWindow("Network") }
        }
        if showsCloud {
            ForEach(SidebarExtras.cloudFolders(), id: \.url) { cloud in
                row(LocalizedStringKey(cloud.name), SidebarExtras.cloudSymbol(cloud.name), url: cloud.url) { browser.navigate(to: cloud.url) }
            }
        }
        if showsICloud, FileManager.default.fileExists(atPath: SidebarExtras.iCloudURL.path) {
            row(SidebarExtras.iCloud.title, SidebarExtras.iCloud.symbol, url: SidebarExtras.iCloudURL) { browser.navigate(to: SidebarExtras.iCloudURL) }
        }
        if showsApplications {
            row(SidebarExtras.applications.title, SidebarExtras.applications.symbol, url: SidebarExtras.applicationsURL) { browser.navigate(to: SidebarExtras.applicationsURL) }
        }
        if showsTrash {
            row(SidebarExtras.trash.title, SidebarExtras.trash.symbol, url: SidebarExtras.trashURL) { openTrash() }
                .contextMenu {
                    Button("Empty Trash…", role: .destructive) {
                        if let error = SidebarExtras.emptyTrash() { browser.errorMessage = error }
                        if browser.currentURL.standardizedFileURL == SidebarExtras.trashURL.standardizedFileURL { browser.reload() }
                    }
                    .disabled(SidebarExtras.trashIsEmpty)
                }
        }
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, url: URL?, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).lineLimit(1) }
            .buttonStyle(SidebarRowButtonStyle(isCurrent: url?.standardizedFileURL == browser.currentURL.standardizedFileURL))
            .contextMenu {
                if let url { Button("Open in New Tab") { browser.newTab(at: url) } }
            }
    }

    private func airDrop() {
        let urls = Array(browser.selection)
        if !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        } else {
            SidebarExtras.openFinderWindow("AirDrop")
        }
    }

    /// La Papelera necesita «Acceso total al disco»: sin él, se explica y se ofrece abrir el ajuste.
    private func openTrash() {
        if (try? FileManager.default.contentsOfDirectory(atPath: SidebarExtras.trashURL.path)) == nil {
            let alert = NSAlert()
            alert.messageText = String(localized: "Explorer needs Full Disk Access to show the Trash")
            alert.informativeText = String(localized: "macOS protects the Trash. Turn on Explorer in Privacy & Security → Full Disk Access, then reopen Explorer.")
            alert.addButton(withTitle: String(localized: "Open Settings"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn { PermissionsService.open(.fullDisk) }
            return
        }
        browser.navigate(to: SidebarExtras.trashURL)
    }
}

/// Opciones en Ajustes → Apariencia → Barra lateral.
struct SidebarExtrasToggles: View {
    var body: some View {
        ForEach(SidebarExtras.allCases) { item in ExtraToggle(item: item) }
        Text("They appear inside “Locations”. Cloud folders are found automatically.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private struct ExtraToggle: View {
        let item: SidebarExtras
        @AppStorage private var shows: Bool
        init(item: SidebarExtras) {
            self.item = item
            _shows = AppStorage(wrappedValue: true, item.key)
        }
        var body: some View {
            Toggle(isOn: $shows) { Label(item.title, systemImage: item == .trash ? "trash" : item.symbol) }
        }
    }
}
