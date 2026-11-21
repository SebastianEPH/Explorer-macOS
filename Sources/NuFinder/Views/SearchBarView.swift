import SwiftUI

struct SearchBarView: View {
    @EnvironmentObject private var browser: BrowserModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: browser.searchContents ? "doc.text.magnifyingglass" : "magnifyingglass")
                .foregroundStyle(browser.searchText.isEmpty ? Color.secondary : Color.accentColor)

            TextField(prompt, text: $browser.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { browser.updateSearch() }
                .onChange(of: browser.searchText) { _, _ in browser.updateSearch() }

            if browser.isSearching {
                ProgressView().controlSize(.small)
            } else if !browser.searchText.isEmpty {
                Text("\(browser.searchResults.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if !browser.searchText.isEmpty {
                Button {
                    browser.searchText = ""
                    browser.updateSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear Search")
            }

            scopeMenu
            optionsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityLabel("File search")
        .onChange(of: browser.searchFocusToken) { _, _ in searchFocused = true }
        // Fork: un clic en esta barra ya no quita la selección (solo un clic en vacío u otro archivo)
    }

    private var prompt: String {
        browser.searchContents ? String(localized: "Search names and file contents") : String(localized: "Search by file name")
    }

    private var scopeMenu: some View {
        Menu {
            ForEach(SearchScope.allCases) { scope in
                Button {
                    browser.searchScope = scope
                    browser.searchSubfolders = scope != .folder
                    if scope == .folder { browser.searchContents = false }
                    if scope == .computer { browser.usesSpotlight = true }
                    browser.updateSearch()
                } label: {
                    Label(LocalizedStringKey(scope.rawValue), systemImage: scope.systemImage)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: browser.searchScope.systemImage)
                Text(LocalizedStringKey(browser.searchScope.rawValue))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(browser.searchScope == .folder ? Color.secondary : Color.accentColor)
            .background(Color.accentColor.opacity(browser.searchScope == .folder ? 0 : 0.1), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Search Scope")
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Search Inside Files", isOn: $browser.searchContents)
                .disabled(browser.searchScope == .folder)
                .onChange(of: browser.searchContents) { _, enabled in
                    if enabled { browser.searchMatchMode = .contains }
                    browser.updateSearch()
                }
            Toggle("Use Spotlight Index", isOn: $browser.usesSpotlight)
                .disabled(browser.searchScope == .folder || browser.searchScope == .computer)
                .onChange(of: browser.usesSpotlight) { _, _ in browser.updateSearch() }

            Divider()
            Picker("Name Matching", selection: $browser.searchMatchMode) {
                ForEach(SearchMatchMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            .onChange(of: browser.searchMatchMode) { _, _ in browser.updateSearch() }
            Picker("Kind", selection: $browser.searchKindFilter) {
                ForEach(SearchKindFilter.allCases) { kind in
                    Text(LocalizedStringKey(kind.rawValue)).tag(kind)
                }
            }
            .onChange(of: browser.searchKindFilter) { _, _ in browser.updateSearch() }

            Menu("Minimum Size: \(sizeLabel)") {
                ForEach([0, 1, 10, 100, 1000], id: \.self) { megabytes in
                    Button(megabytes == 0 ? String(localized: "Any Size") : "\(megabytes) MB") {
                        browser.minimumSearchSizeMB = megabytes
                        browser.updateSearch()
                    }
                }
            }
            Menu("Modified: \(dateLabel)") {
                ForEach([0, 1, 7, 30, 365], id: \.self) { days in
                    Button(days == 0 ? String(localized: "Any Time") : String(localized: "Within \(days) days")) {
                        browser.modifiedWithinDays = days
                        browser.updateSearch()
                    }
                }
            }

            Divider()
            Button("Save Search") { browser.saveCurrentSearch() }
                .disabled(browser.searchText.isEmpty)
            if !browser.savedSearches.isEmpty {
                Menu("Saved Searches") {
                    ForEach(browser.savedSearches, id: \.self) { query in
                        Button(query) {
                            browser.searchText = query
                            browser.updateSearch()
                        }
                        Button("Remove “\(query)”", role: .destructive) {
                            browser.removeSavedSearch(query)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: activeFilterCount > 0
                  ? "slider.horizontal.3.circle.fill"
                  : "slider.horizontal.3")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(activeFilterCount > 0 ? Color.accentColor : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(activeFilterCount > 0 ? String(localized: "Search Filters (\(activeFilterCount) Active)") : String(localized: "Search Filters"))
    }

    private var activeFilterCount: Int {
        (browser.searchContents ? 1 : 0) +
        (browser.searchKindFilter == .all ? 0 : 1) +
        (browser.minimumSearchSizeMB == 0 ? 0 : 1) +
        (browser.modifiedWithinDays == 0 ? 0 : 1) +
        (browser.searchMatchMode == .contains ? 0 : 1)
    }

    private var sizeLabel: String {
        browser.minimumSearchSizeMB == 0 ? "Any" : "\(browser.minimumSearchSizeMB) MB"
    }

    private var dateLabel: String {
        browser.modifiedWithinDays == 0 ? String(localized: "Any Time") : String(localized: "Last \(browser.modifiedWithinDays) Days")
    }
}
