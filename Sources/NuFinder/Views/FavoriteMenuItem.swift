import SwiftUI

/// Clic derecho sobre una carpeta → «Añadir a Favoritos» / «Quitar de Favoritos».
/// Solo guarda la ruta en la barra lateral: nunca mueve la carpeta.
struct FavoriteMenuItem: View {
    @EnvironmentObject private var browser: BrowserModel
    let url: URL

    private var isFavorite: Bool {
        browser.customFavorites.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    var body: some View {
        if isFavorite {
            Button("Remove from Favorites") { browser.removeFavorite(url) }
        } else {
            Button("Add to Favorites") { browser.addFavorite(url) }
        }
    }
}
