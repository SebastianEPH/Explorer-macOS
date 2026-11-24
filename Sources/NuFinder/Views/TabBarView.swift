import SwiftUI

struct TabBarView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(browser.tabs) { tab in
                    HStack(spacing: 6) {
                        Image(systemName: tab.isPinned ? "pin.fill" : "folder")
                            .foregroundStyle(.secondary)
                        Text(tab.title).lineLimit(1)
                        if browser.tabs.count > 1 && !tab.isPinned {
                            Button {
                                browser.closeTab(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        tab.id == browser.activeTabID ? Color.accentColor.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .hoverHighlight() // Fork
                    .contentShape(Rectangle())
                    .onTapGesture { browser.selectTab(tab.id) }
                    .onMiddleClick { MiddleClick.tabClicked(tab.id, in: browser) } // Fork: rueda = cerrar
                    .contextMenu {
                        Button(tab.isPinned ? String(localized: "Unpin Tab") : String(localized: "Pin Tab")) {
                            browser.togglePinnedTab(tab.id)
                        }
                        Button("Duplicate Tab") {
                            browser.duplicateTab(tab.id)
                        }
                        Divider()
                        Button("Close Tab") {
                            browser.closeTab(tab.id)
                        }
                        .disabled(tab.isPinned || browser.tabs.count == 1)
                    }
                }
                Button {
                    browser.newTab()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(HoverPressButtonStyle(padding: 4)) // Fork
                .padding(3)
                .help("New Tab")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(.bar)
        // Fork: un clic en esta barra ya no quita la selección (solo un clic en vacío u otro archivo)
    }
}
