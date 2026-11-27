#!/bin/sh
# Compila, prueba, firma e instala Explorer en este Mac (sin GitHub).
# Uso: sh Scripts/install_local.sh            (sin pruebas, rápido)
#      sh Scripts/install_local.sh --tests    (con todas las pruebas antes)
set -e
cd "$(dirname "$0")/.."

if [ "$1" = "--tests" ]; then
  echo "==> Pruebas"
  log=$(mktemp)
  if swift test >"$log" 2>&1; then status=0; else status=1; fi
  grep -E "error:|✘|Test run with" "$log"
  rm -f "$log"
  [ "$status" = 0 ] || { echo "Las pruebas fallaron"; exit 1; }
fi

echo "==> Compilando"
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
ruby Scripts/generate_xcode_project.rb >/dev/null
xcodebuild -project Freeloader.xcodeproj -target Freeloader -configuration Release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
git checkout -- Freeloader.xcodeproj/project.pbxproj 2>/dev/null || true

APP=build/Release/Explorer.app
PLIST="$APP/Contents/Info.plist"
BASE=$(tr -d '[:space:]' < VERSION)
SINCE=$(git log -1 --format=%H -- VERSION)
VERSION="$BASE.$(git rev-list --count "$SINCE"..HEAD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :FLBuildNumber 9999" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :FLBuildNumber string 9999" "$PLIST"

echo "==> Firmando con «Explorer Firma» (conserva los permisos de macOS)"
codesign --force --deep --sign "Explorer Firma" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Instalando Explorer $VERSION"
osascript -e 'tell application id "com.miguelrodriguez.NuFinder" to quit' 2>/dev/null || true
sleep 2
rm -rf /Applications/Explorer.app
ditto "$APP" /Applications/Explorer.app
xattr -dr com.apple.quarantine /Applications/Explorer.app
open /Applications/Explorer.app
echo "Listo: Explorer $VERSION instalado"
