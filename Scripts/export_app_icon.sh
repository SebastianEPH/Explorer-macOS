#!/bin/sh
# Pone como icono oficial del .app uno de los diseños de Ajustes → Apariencia → Icono de la app.
# Uso: sh Scripts/export_app_icon.sh [id] [fondo 0|1] [margen 0–0.3]   (por defecto: window-square, sin fondo, 0.1)
set -e
cd "$(dirname "$0")/.."
EXPORT_ICON_DIR="$PWD/Assets/Assets.xcassets/AppIcon.appiconset" \
EXPORT_ICON_ID="${1:-window-square}" EXPORT_ICON_BACKGROUND="${2:-0}" EXPORT_ICON_MARGIN="${3:-0.1}" \
  swift test --filter ExportAppIconTests 2>&1 | grep -E "error:|✘|passed after" | head -3
echo "Icono oficial: ${1:-window-square}"
