import AppKit
import SwiftUI

/// Fork: botón central del ratón (la rueda), como en los navegadores y el Explorador de Windows.
/// - En una pestaña la cierra, igual que su «X» (`middleClick.closesTab`).
/// - En una carpeta la abre en una ventana o pestaña nueva (`middleClick.folder`).
/// Apagado = comportamiento original (el botón central no hace nada).
enum MiddleClickFolderAction: String, CaseIterable, Identifiable {
    case none, newWindow, newTab
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .none: "Nothing"
        case .newWindow: "Open in New Window"
        case .newTab: "Open in New Tab"
        }
    }

    var symbol: String {
        switch self {
        case .none: "nosign"
        case .newWindow: "macwindow.badge.plus"
        case .newTab: "plus.rectangle.on.rectangle"
        }
    }
}

enum MiddleClick {
    static let closesTabKey = "middleClick.closesTab"
    static let folderKey = "middleClick.folder"

    static var closesTab: Bool { UserDefaults.standard.bool(forKey: closesTabKey) }
    static var folderAction: MiddleClickFolderAction {
        MiddleClickFolderAction(rawValue: UserDefaults.standard.string(forKey: folderKey) ?? "") ?? .none
    }

    /// El botón central del ratón (0 = izquierdo, 1 = derecho, 2 = central).
    static func isMiddle(_ event: NSEvent) -> Bool {
        event.type == .otherMouseUp && event.buttonNumber == 2
    }

    /// Qué se hace con un clic central sobre este elemento: solo carpetas (no apps ni paquetes).
    static func action(isFolder: Bool, isPackage: Bool, setting: MiddleClickFolderAction) -> MiddleClickFolderAction {
        isFolder && !isPackage ? setting : .none
    }

    /// Abrir una ventana; se sustituye en pruebas.
    nonisolated(unsafe) static var openWindow: @MainActor (URL) -> Void = { WindowService.open(at: $0) }

    /// Clic central en una pestaña: la cierra como su «X» (las fijadas y la última no se cierran).
    @MainActor @discardableResult
    static func tabClicked(_ id: UUID, in browser: BrowserModel) -> Bool {
        guard closesTab, browser.tabs.count > 1 else { return false }
        let before = browser.tabs.count
        browser.closeTab(id)
        return browser.tabs.count < before
    }

    /// Clic central en un elemento de la lista. Devuelve lo que hizo.
    @MainActor @discardableResult
    static func itemClicked(_ item: FileItem, in browser: BrowserModel) -> MiddleClickFolderAction {
        let action = action(isFolder: item.isDirectory, isPackage: item.isDirectory && item.isPackage, setting: folderAction)
        switch action {
        case .none: break
        case .newWindow: openWindow(item.url)
        case .newTab: browser.newTab(at: item.url)
        }
        return action
    }
}

extension View {
    /// Fork: llama a `action` al soltar el botón central del ratón sobre esta vista.
    func onMiddleClick(_ action: @escaping () -> Void) -> some View {
        background(MiddleClickReader(action: action))
    }

    /// Fork: clic central sobre una fila de la tabla (en cualquier columna). Recibe el índice de fila.
    func tableMiddleClick(_ onRow: @escaping (Int) -> Void) -> some View {
        background(TableMiddleClickInstaller(onRow: onRow))
    }
}

struct MiddleClickReader: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.action = action
    }

    final class ReaderView: NSView {
        var action: (() -> Void)?
        nonisolated(unsafe) private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        /// Devuelve true si el clic central cayó sobre esta vista y se llamó a la acción.
        @discardableResult
        func handle(_ event: NSEvent) -> Bool {
            guard MiddleClick.isMiddle(event), event.window === window, !isHiddenOrHasHiddenAncestor,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            action?()
            return true
        }
    }
}

struct TableMiddleClickInstaller: NSViewRepresentable {
    let onRow: (Int) -> Void

    func makeNSView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.onRow = onRow
        return view
    }

    func updateNSView(_ view: InstallerView, context: Context) {
        view.onRow = onRow
    }

    final class InstallerView: NSView {
        var onRow: ((Int) -> Void)?
        nonisolated(unsafe) private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        /// Devuelve la fila sobre la que se hizo clic central (o nil si no era sobre una fila).
        @discardableResult
        func handle(_ event: NSEvent) -> Int? {
            guard MiddleClick.isMiddle(event), event.window === window, !isHiddenOrHasHiddenAncestor,
                  convert(bounds, to: nil).contains(event.locationInWindow),
                  let table = tableUnder(event) else { return nil }
            let row = table.row(at: table.convert(event.locationInWindow, from: nil))
            guard row >= 0 else { return nil }
            onRow?(row)
            return row
        }

        private func tableUnder(_ event: NSEvent) -> NSTableView? {
            guard let content = window?.contentView else { return nil }
            var view = content.hitTest(content.convert(event.locationInWindow, from: nil))
            while let current = view {
                if let table = current as? NSTableView { return table }
                if let scroll = current as? NSScrollView, let table = scroll.documentView as? NSTableView { return table }
                if let clip = current as? NSClipView, let table = clip.documentView as? NSTableView { return table }
                view = current.superview
            }
            return nil
        }
    }
}

/// Ajustes → Archivos → Ratón: qué hace el botón central.
struct MiddleClickSection: View {
    @AppStorage(MiddleClick.closesTabKey) private var closesTab = false
    @AppStorage(MiddleClick.folderKey) private var folder = MiddleClickFolderAction.none.rawValue

    var body: some View {
        Section("Middle Mouse Button") {
            MiddleClickPreview(closesTab: closesTab, folder: MiddleClickFolderAction(rawValue: folder) ?? .none)
            Toggle(isOn: $closesTab) {
                Label("Middle-click a tab to close it", systemImage: "xmark.square")
                Text("Like clicking its X. Pinned tabs and the last tab stay open. Off: the middle button does nothing on tabs, as before.")
            }
            Picker(selection: $folder) {
                ForEach(MiddleClickFolderAction.allCases) { action in
                    Label(action.title, systemImage: action.symbol).tag(action.rawValue)
                }
            } label: {
                Label("Middle-click a folder", systemImage: "folder")
                Text("Opens the folder somewhere new and leaves the current one as it is. Files and apps are not affected. “Nothing” is the original behavior.")
            }
        }
    }
}

/// Vista previa: una barra de pestañas y una carpeta, con lo que pasa al pulsar la rueda.
private struct MiddleClickPreview: View {
    let closesTab: Bool
    let folder: MiddleClickFolderAction

    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    tab("Documents", active: true, closing: false)
                    tab("Downloads", active: false, closing: closesTab)
                }
                outcome(closesTab ? "xmark" : "nosign", closesTab ? Color.red : .secondary,
                        closesTab ? "Tab closes" : "Nothing happens")
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").font(.title2).foregroundStyle(Color.accentColor)
                    mouse
                }
                outcome(folder.symbol, folder == .none ? .secondary : Color.accentColor,
                        folder == .none ? "Nothing happens" : folder.title)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private func tab(_ name: LocalizedStringKey, active: Bool, closing: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "folder").font(.caption2)
            Text(name).font(.caption)
            if closing { mouse.scaleEffect(0.7) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6))
        .opacity(closing ? 0.45 : 1)
    }

    private var mouse: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).stroke(Color.secondary, lineWidth: 1.2).frame(width: 14, height: 20)
            Capsule().fill(Color.orange).frame(width: 3, height: 6).offset(y: -4)
        }
    }

    private func outcome(_ symbol: String, _ color: Color, _ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(color)
    }
}
