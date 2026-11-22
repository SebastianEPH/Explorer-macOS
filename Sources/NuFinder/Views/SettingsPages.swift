import SwiftUI

/// Fork: dentro de cada pestaña de Ajustes, un panel a la izquierda con sus apartados;
/// a la derecha solo se ve el apartado elegido (páginas cortas y ordenadas).
struct SettingsPage: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let symbol: String
    let content: AnyView

    init<Content: View>(_ id: String, _ title: LocalizedStringKey, _ symbol: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.content = AnyView(content())
    }
}

struct SettingsPagesView: View {
    let tab: String
    let pages: [SettingsPage]
    @AppStorage private var selection: String

    init(tab: String, pages: [SettingsPage]) {
        self.tab = tab
        self.pages = pages
        // Recuerda el último apartado abierto de cada pestaña.
        _selection = AppStorage(wrappedValue: pages.first?.id ?? "", "settings.page.\(tab)")
    }

    private var current: SettingsPage? { pages.first { $0.id == selection } ?? pages.first }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { current?.id }, set: { if let id = $0 { selection = id } })) {
                ForEach(pages) { page in
                    Label(page.title, systemImage: page.symbol).tag(page.id)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            Form { current?.content }
                .formStyle(.grouped)
                .id(current?.id)
        }
    }
}
