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

- En este Mac **no hay Xcode completo** (solo Command Line Tools): `swift build` falla y SourceKit da errores falsos ("Cannot find … in scope", macros no encontradas). Ignóralos; la verdad la da el pipeline.
- Pipeline `.github/workflows/build.yml` (macos-latest): `swift test` → regenerar proyecto → `xcodebuild` Release sin firmar → escribe `FLBuildNumber` = `run_number` en el Info.plist → firma ad hoc → sube `Explorer.zip` como artefacto y, en `main`, lo publica como Release `build-N` (`--latest`).
- Ver el resultado: `gh run list -R SebastianEPH/Freeloader -L 1` y `gh run watch <id> --exit-status`.

## Actualizaciones dentro de la app

- `Sources/NuFinder/Services/UpdateService.swift` + sección «Actualizaciones» en `SettingsView`: consulta `releases/latest` del fork, compara `build-N` con `FLBuildNumber`, descarga el zip, y un script `sh` espera a que la app se cierre, reemplaza el `.app`, quita la cuarentena y la vuelve a abrir.
- Si cambias el nombre de las Releases o del zip, cambia ambos lados (workflow y `UpdateService`).
- Compilaciones locales no tienen `FLBuildNumber` (se muestran como «local», build 0): cualquier Release se ofrece como actualización.

## Instalar a mano la última compilación

```bash
gh release download -R SebastianEPH/Freeloader --pattern Explorer.zip
ditto -x -k Explorer.zip . && rm -rf /Applications/Explorer.app && mv Explorer.app /Applications/
xattr -dr com.apple.quarantine /Applications/Explorer.app
```
