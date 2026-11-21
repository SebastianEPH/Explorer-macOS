# CLAUDE.md

Fork personal de [Freeloader](https://github.com/KopitarFan/Freeloader) (reemplazo de Finder para macOS, SwiftUI + AppKit, licencia MIT) para añadirle opciones propias sin perder las novedades del autor. La app se llama **Explorer** (`PRODUCT_NAME`, `CFBundleName`); el bundle id sigue siendo `com.miguelrodriguez.NuFinder` para conservar la configuración y el módulo Swift sigue siendo `Freeloader`.

## Reglas

- **Idioma:** responde al usuario en español. Commits en español: una línea de resumen y una lista de cambios, sin `Co-Authored-By` ni menciones a herramientas. Haz commit y push a `main` (de `origin`) después de cada cambio terminado.
- **Conservar el aviso de copyright** del autor original (`LICENSE`, MIT).
- **Pocos conflictos con el original:** lo nuevo va en archivos propios (p. ej. `Services/UpdateService.swift`) y en los archivos del autor solo se añade lo mínimo (una línea que lo enganche). No reformatees ni reescribas código suyo.
- **No edites `Freeloader.xcodeproj` a mano:** se genera desde `Sources/` con `ruby Scripts/generate_xcode_project.rb` (gema `xcodeproj`). El pipeline lo regenera antes de compilar, así que no hace falta commitearlo.
- **La configuración del usuario** está en UserDefaults (`com.miguelrodriguez.NuFinder`), fuera del `.app`. Nada debe borrarla al actualizar o reinstalar.

## Remotos y sincronización

- `origin` = `SebastianEPH/Freeloader` (este fork) · `upstream` = `KopitarFan/Freeloader`.
- Traer novedades del autor: `git pull upstream main && git push origin main`. Si hay conflictos, se resuelven conservando las dos partes.

## Compilar

- **Todo se hace en este Mac:** `sh Scripts/install_local.sh` corre las pruebas, compila, firma con «Explorer Firma» e instala en `/Applications`. No esperar a GitHub ni depender de él: el pipeline solo publica Releases para otras personas y puede fallar por falta de máquinas sin que importe.

- Xcode 27.2 instalado en `/Applications/Xcode.app` (desde el 2026-11-20). Antes de subir: `swift test` y la compilación `xcodebuild` igual que el pipeline (`ruby Scripts/generate_xcode_project.rb` primero; no commitear `project.pbxproj` ni `build/`).
- Pipeline `.github/workflows/build.yml` (macos-latest): `swift test` → regenerar proyecto → `xcodebuild` Release sin firmar → escribe `FLBuildNumber` = `run_number` en el Info.plist → firma con el certificado propio «Explorer Firma» (secretos `SIGN_P12` y `SIGN_P12_PASSWORD`; copia en el llavero de inicio de sesión del Mac, válido hasta 2036) para que macOS conserve los permisos al actualizar; ad hoc en pull requests → sube `Explorer.zip` como artefacto y, en `main`, lo publica como Release `vX.Y.Z` (`--latest`).
- Ver el resultado: `gh run list -R SebastianEPH/Freeloader -L 1` y `gh run watch <id> --exit-status`.

## Actualizaciones dentro de la app

- `Sources/NuFinder/Services/UpdateService.swift` + sección «Actualizaciones» en `SettingsView`: consulta `releases/latest` del fork, compara la versión de la Release (`vX.Y.Z`) con `CFBundleShortVersionString` (número a número), descarga el zip, y un script `sh` espera a que la app se cierre, reemplaza el `.app`, quita la cuarentena y la vuelve a abrir.
- Si cambias el nombre de las Releases o del zip, cambia ambos lados (workflow y `UpdateService`).
- Compilaciones locales no tienen `FLBuildNumber` (se muestran como «local», build 0): cualquier Release se ofrece como actualización.

## Instalar a mano la última compilación

```bash
gh release download -R SebastianEPH/Freeloader --pattern Explorer.zip
ditto -x -k Explorer.zip . && rm -rf /Applications/Explorer.app && mv Explorer.app /Applications/
xattr -dr com.apple.quarantine /Applications/Explorer.app
```

## Idioma y traducciones

- Las claves de texto del código van **en inglés** (como el autor); las traducciones están en `Localization/<idioma>.lproj/Localizable.strings` (fuera de `Sources/` para que SwiftPM no las procese). El generador del proyecto las copia como carpetas en Resources.
- Interpolaciones: `String` → `%@`, `Int` → `%lld`, `Int32` → `%d`. Textos fuera de SwiftUI (NSAlert, NSMenu): `String(localized:)`.
- Texto nuevo en la interfaz → añade su línea en `es.lproj/Localizable.strings`.
- Ajustes → Idioma (`Services/LanguageService.swift`) guarda `AppleLanguages` de la app y la reinicia.
- Menú Ayuda → «Buscar actualizaciones…» (`UpdateService.checkFromMenu`).
- Ajustes → Favoritos (`Services/FavoritesSettings.swift`): mostrar/ocultar (también los de fábrica), nombre, icono, orden, añadir y quitar. Guarda en UserDefaults y avisa con `FavoritesSettings.didChange`; `BrowserModel.favorites` pasa por `FavoritesSettings.visible`.
- Ajustes → Permisos (`Services/PermissionsService.swift`): estado y botón «Solicitar» de Acceso total al disco, Accesibilidad, carpetas personales y Automatización (System Events, iTerm). macOS no deja concederlos desde la app: muestra el aviso del sistema o abre el panel de Ajustes del Sistema.
- Ventanas (`Services/KeyWindowFocus.swift`): cada ventana tiene su propio `BrowserModel`; «Nueva ventana» reemplaza a la de SwiftUI (que compartía el mismo modelo) y los menús actúan sobre la ventana activa (`browser` en `NuFinderApp` es calculado).
- Pruebas del fork en `Tests/NuFinderTests/ForkTests.swift` (las corre el pipeline con `swift test`). Cada función nueva que cambie datos o comportamiento lleva su prueba; no dar algo por hecho hasta que el pipeline pase.
- Ajustes → Finder (`Services/FinderRedirectService.swift`): con Finder cerrado (`QuitMenuItem`), si Finder arranca o pasa al frente (clic en el Dock) Explorer lo cierra y abre una ventana en la carpeta personal. Ignora los primeros 15 s tras abrir Explorer (al iniciar sesión macOS arranca Finder). Se registra al inicio de sesión con `SMAppService.mainApp`.

## Versiones

- Formato **X.Y.Z**. `X.Y` está en el archivo `VERSION` (súbelo a mano para cambios grandes: `1.1`, `2.0`); `Z` = commits desde el último cambio de `VERSION`, así que vuelve a 0 al subirla. Lo calcula el pipeline (`fetch-depth: 0`) y lo escribe en `CFBundleShortVersionString`; `CFBundleVersion` y `FLBuildNumber` = número de ejecución.
- Releases: etiqueta `vX.Y.Z`, título «Explorer X.Y.Z».
- iTerm (`Services/ITermService.swift`): si la terminal elegida es iTerm, «Abrir terminal aquí» le pide por AppleScript (`osascript`) una ventana nueva y hace `cd`; abrir la carpeta con NSWorkspace solo ponía delante la ventana existente. Necesita `NSAppleEventsUsageDescription` en `App-Info.plist`. Si la ventana de iTerm previa está en pantalla completa, la nueva también: se le quita con System Events (`AXFullScreen`), solo si Explorer tiene permiso de Accesibilidad.
- Menú Ayuda (`HelpVersionItems`): versión instalada, «Acerca de Explorer» (`AboutPanel`) y «Buscar actualizaciones…». El usuario no quiere enlaces a GitHub ahí.
- Ajustes en pestañas (General, Archivos, Favoritos, Menú contextual, Sistema): `TabView` en `SettingsView` con `.settingsTab(...)` (definido en `ContextMenuSettings.swift`). Sección nueva → en la pestaña que le toque.
- Vistas previas en Ajustes (`Services/SettingsPreviews.swift`): cada sección muestra un dibujo en vivo de lo que cambia (barra, atajos como teclas, insignias Git, zona de clic, menú contextual, Finder→Explorer) y cada opción lleva icono y explicación. Opción nueva en Ajustes → con su vista previa.
- Ajustes → Menú contextual (`Services/ContextMenuSettings.swift`): un menú por tipo (`ContextMenuScope`: carpeta, archivo, imagen, comprimido, espacio vacío) con vista previa dibujada. Oculta «tipo:opción» en `contextMenu.hidden` (una opción sin tipo = formato antiguo, oculta en todos). El orden también se elige por tipo (`contextMenu.order`, «tipo=a,b,c;…»). En `FileListView` los menús se arman con `ForEach` sobre `ContextMenuSettings.order` y cada opción está en `itemMenuEntry`/`backgroundMenuEntry` (un `case` por opción). Opción nueva → caso en `ContextMenuOption`, en `scope.options` y en el `switch`.
- Pestañas Inicio, Archivos y Apariencia (`Services/BehaviorSettings.swift`): pestañas al abrir, carpeta de inicio y de pestaña nueva, vista por defecto, ocultos, carpetas en pestaña nueva, confirmar Papelera, tamaño de iconos, tema, color de los botones de la barra, «Ubicaciones» en la barra lateral. Sin tocar nada se comporta como el original.
- Barra de estado (`Views/StatusBarView.swift`, enganchada con una línea en `ContentView.browserPane`): elementos, carpetas/archivos, seleccionados, tamaño de la selección (carpetas solo si `FolderSizeService` ya las calculó), espacio libre y botones de vista. Se configura en Ajustes → Apariencia → Barra de estado, con vista previa.
