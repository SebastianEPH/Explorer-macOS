import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var operations: FileOperationManager
    @EnvironmentObject private var paneFocus: PaneFocusCoordinator
    @AppStorage("previewPane.visible") private var previewVisible = true // Fork
    @AppStorage(LayoutSettings.compactTopKey) private var compactTop = false // Fork
    @StateObject private var secondaryBrowser = BrowserModel(
        initialURL: BehaviorSettings.startURL() ?? FileManager.default.homeDirectoryForCurrentUser, // Fork: carpeta de inicio
        restoresSession: false
    )
    @ObservedObject private var splitPanes = WindowSplitPanes.shared // Fork: panel dividido de cada ventana
    private var showsSplitPane: Bool { splitPanes.isOn(browser) }
    @AppStorage("toolbar.showsSplit") private var toolbarShowsSplit = true
    @AppStorage("toolbar.showsTerminal") private var toolbarShowsTerminal = true
    @AppStorage("toolbar.showsOperations") private var toolbarShowsOperations = true
    @AppStorage("gitStatusEnabled") private var gitStatusEnabled = false
    @State private var newFileName = "Untitled.txt"
    @State private var newFolderName = String(localized: "untitled folder")

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if showsSplitPane {
                GeometryReader { geometry in
                    let paneWidth = max(0, (geometry.size.width - 1) / 2)
                    HStack(spacing: 0) {
                        browserPane(for: browser)
                            .frame(width: paneWidth)
                            .clipped()
                    Divider()
                    browserPane(for: secondaryBrowser)
                            .frame(width: paneWidth)
                            .clipped()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .transition(.opacity)
            } else {
                browserPane(for: browser)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsSplitPane)
        .background {
            WindowLayoutSizingView(
                minimumContentSize: showsSplitPane
                    ? CGSize(width: 1180, height: 560)
                    : CGSize(width: 820, height: 480)
            )
        }
        .toolbar { toolbar }
        .background(WindowTitleVisibility()) // Fork: título de la ventana según Ajustes
        .background(WindowRepresentedURL(url: activeBrowser.currentURL)) // Fork: ruta en su propia ventana
        .onAppear {
            paneFocus.activate(browser)
        }
        .alert("New File", isPresented: $browser.showsNewFilePrompt) {
            TextField("File name", text: $newFileName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                browser.createFile(named: newFileName)
                newFileName = "Untitled.txt"
            }
        } message: {
            Text("Create an empty file in \(browser.currentURL.lastPathComponent).")
        }
        .alert("New Folder", isPresented: $browser.showsNewFolderPrompt) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                browser.createFolder(named: newFolderName)
                newFolderName = String(localized: "untitled folder")
            }
        } message: {
            Text("Create a folder in \(browser.currentURL.lastPathComponent).")
        }
        .sheet(isPresented: $browser.showsBatchRenamePrompt) {
            BatchRenameView()
                .environmentObject(browser)
        }
        .sheet(isPresented: $browser.showsConnectToServer) {
            ConnectToServerView()
                .environmentObject(browser)
        }
        .sheet(isPresented: $browser.showsCommandPalette) {
            CommandPaletteView()
                .environmentObject(browser)
                .environmentObject(operations)
        }
        .alert("Tags", isPresented: $browser.showsTagPrompt) {
            TextField("work, important, red", text: $browser.tagText)
            Button("Cancel", role: .cancel) {}
            Button("Apply") { browser.applyTagsFromPrompt() }
        } message: {
            Text("Enter comma-separated Finder tags. Leave the field empty to remove tags.")
        }
        .alert("Explorer", isPresented: Binding(
            get: { browser.errorMessage != nil },
            set: { if !$0 { browser.errorMessage = nil } }
        )) {
            Button("OK") { browser.errorMessage = nil }
        } message: {
            Text(browser.errorMessage ?? "")
        }
        .sheet(isPresented: $operations.showsDetails) {
            OperationsPanelView() // Fork: panel rehecho
                .environmentObject(operations)
        }
        .sheet(item: $browser.itemForInfo) { item in
            FileInfoView(item: item)
                .environmentObject(browser)
        }
        .sheet(isPresented: detailPresented) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(browser.detailTitle ?? String(localized: "Details")).font(.title2.bold())
                    Spacer()
                    Button("Done") { browser.detailTitle = nil }
                        .keyboardShortcut(.defaultAction)
                }
                if browser.detailText.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(browser.detailText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 560, minHeight: 300)
        }
    }

    @ViewBuilder
    private func browserPane(for model: BrowserModel) -> some View {
        VStack(spacing: 0) {
            LayoutTabBar() // Fork: pestañas según Ajustes → Ventana
            AddressBarRow()
            Divider()
            LayoutSearchBar() // Fork: búsqueda según Ajustes
            HStack(spacing: 0) {
                FileListView()
                if let previewItem = previewItem(in: model) {
                    Divider()
                    ImagePreviewPane(item: previewItem)
                        .simultaneousGesture(
                            TapGesture().onEnded { model.clearSelection() }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: previewItem(in: model)?.url)
            StatusBarView() // Fork: barra de estado
        }
        .background {
            PaneInteractionMonitor {
                paneFocus.activate(model)
            }
        }
        .clipped()
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(
                        showsSplitPane && paneFocus.isActive(model) ? 0.85 : 0
                    ),
                    lineWidth: 2
                )
                .padding(1)
                .allowsHitTesting(false)
        }
        .environmentObject(model)
        .environmentObject(operations)
        .onChange(of: model.viewMode) { _, _ in model.saveViewPreferences() }
        .onChange(of: model.showsKindColumn) { _, _ in model.saveViewPreferences() }
        .onChange(of: model.showsSizeColumn) { _, _ in model.saveViewPreferences() }
        .onChange(of: model.showsModifiedColumn) { _, _ in model.saveViewPreferences() }
        .onChange(of: model.sortCriteria) { _, _ in model.saveViewPreferences() }
        .onReceive(FolderSizeService.shared.$entries.debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { _ in model.resortForFolderSizes() } // Fork
        .task(id: model.currentURL) {
            if gitStatusEnabled {
                GitStatusService.shared.refresh(for: model.currentURL)
            }
        }
    }

    private func previewItem(in model: BrowserModel) -> FileItem? {
        let selectedURL = model.selection.count == 1 ? model.selection.first : nil
        let previewURL = model.isMarqueeSelecting
            ? model.marqueePreviewURL
            : selectedURL
        guard previewVisible, let url = previewURL,
              let item = model.displayedItems.first(where: { $0.url == url }),
              !item.isDirectory,
              !isArchive(item.url) else {
            return nil
        }
        return item
    }

    private func isArchive(_ url: URL) -> Bool {
        if ArchiveService.isArchive(url) { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .archive)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if compactTop { // Fork: pestañas dentro de la barra de arriba
            ToolbarItem(placement: .navigation) { CompactTabs().environmentObject(activeBrowser) }
        }
        ToolbarItemGroup(placement: compactTop ? .primaryAction : .automatic) { // Fork: en compacto, a la derecha
            toolbarButtons // Fork: los mismos botones pueden ir en la fila de pestañas
        }
    }

    // Fork: botones de la barra en una vista aparte para poder ponerlos también junto a las pestañas.
    @ViewBuilder
    private var toolbarButtons: some View {
            if toolbarShowsSplit {
                Button {
                    splitPanes.toggle(browser)
                } label: {
                    FreeloaderToolbarIcon(
                        systemName: "rectangle.split.2x1",
                        isActive: showsSplitPane
                    )
                }
                .buttonStyle(.plain)
                .help(showsSplitPane ? String(localized: "Close Split Pane") : String(localized: "Open Split Pane"))
            }
            if toolbarShowsTerminal {
                Button {
                    TerminalService.open(at: activeBrowser.currentURL)
                } label: {
                    FreeloaderToolbarIcon(systemName: "terminal")
                }
                .buttonStyle(.plain)
                .help("Open in Terminal")
            }
            if toolbarShowsOperations {
                Button {
                    operations.showsDetails = true
                } label: {
                    FreeloaderToolbarIcon(
                        systemName: "arrow.left.arrow.right.circle",
                        badge: operations.operations.filter { $0.finishedAt == nil }.count
                    )
                }
                .buttonStyle(.plain)
                .help("File Operations")
            }
    }

    private var detailPresented: Binding<Bool> {
        Binding(
            get: { browser.detailTitle != nil },
            set: { isPresented in
                if !isPresented { browser.detailTitle = nil }
            }
        )
    }

    private var activeBrowser: BrowserModel {
        paneFocus.activeBrowser ?? browser
    }

}

private struct ConnectToServerView: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect to Server")
                        .font(.title2.bold())
                    Text("Mount an SMB share using macOS authentication.")
                        .foregroundStyle(.secondary)
                }
            }

            TextField("smb://server/share", text: $browser.serverAddress)
                .textFieldStyle(.roundedBorder)
                .focused($addressFocused)
                .onSubmit { connect() }

            if !browser.recentServers.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Recent Servers")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(browser.recentServers, id: \.self) { address in
                        Button {
                            browser.serverAddress = address
                        } label: {
                            Label(address, systemImage: "clock")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                if browser.isConnectingToServer {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    browser.showsConnectToServer = false
                }
                .disabled(browser.isConnectingToServer)
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(browser.isConnectingToServer)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear { addressFocused = true }
        .interactiveDismissDisabled(browser.isConnectingToServer)
    }

    private func connect() {
        Task { await browser.connectToServer() }
    }
}

struct FreeloaderToolbarIcon: View {
    let systemName: String
    var isActive = false
    var badge = 0

    @AppStorage(AppearanceSettings.toolbarColorKey) private var toolbarColorLight = "" // Fork
    @AppStorage(AppearanceSettings.toolbarColorDarkKey) private var toolbarColorDark = "" // Fork
    @Environment(\.colorScheme) private var colorScheme // Fork
    private var toolbarColor: String { AppearanceSettings.toolbarColorID(light: toolbarColorLight, dark: toolbarColorDark, scheme: colorScheme) } // Fork
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .symbolEffect(.bounce, value: isActive)
            .foregroundStyle(.white)
            .frame(width: 29, height: 25)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppearanceSettings.toolbarGradient(toolbarColor, active: isActive), // Fork
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 0.7)
                    }
                    .shadow(
                        color: AppearanceSettings.toolbarDeep(toolbarColor).opacity(isHovering ? 0.38 : 0.22), // Fork
                        radius: isHovering ? 5 : 2,
                        y: isHovering ? 2 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text(badge > 9 ? "9+" : "\(badge)")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(AppearanceSettings.toolbarDeep(toolbarColor)) // Fork
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12, minHeight: 12)
                        .background(.white, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .scaleEffect(isHovering ? 1.06 : 1)
            .brightness(isHovering ? 0.08 : 0) // Fork: más visible al pasar el ratón
            .rotationEffect(.degrees(isHovering ? -1.5 : 0))
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: isHovering)
            .onHover { isHovering = $0 }
    }
}
