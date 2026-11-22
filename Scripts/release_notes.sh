#!/bin/sh
# Notas de una Release, al grano: Features / Fix / Remove, una línea por cambio desde la Release anterior.
# El tipo sale del prefijo del commit (feat:, fix:, remove:); si no tiene, se deduce de la primera palabra.
# Uso: sh Scripts/release_notes.sh [etiqueta-anterior]
set -e
cd "$(dirname "$0")/.."
PREV="${1:-$(git describe --tags --abbrev=0 --match 'v*' HEAD^ 2>/dev/null || true)}"
RANGE="${PREV:+$PREV..}HEAD"
git log "$RANGE" --no-merges --format='%s' | awk '
  BEGIN { IGNORECASE = 1 }
  {
    line = $0; low = tolower(line)
    if (low ~ /^fix:/)          { kind = "fix";    sub(/^[^:]*: */, "", line) }
    else if (low ~ /^remove:/)  { kind = "remove"; sub(/^[^:]*: */, "", line) }
    else if (low ~ /^feat:/)    { kind = "feat";   sub(/^[^:]*: */, "", line) }
    else if (low ~ /^(arregl|corrig|solucion|fix)/) kind = "fix"
    else if (low ~ /^(quit|elimin|borr|remove)/)    kind = "remove"
    else kind = "feat"
    if (low ~ /^(claude\.md|readme)/) next
    item[kind] = item[kind] "- " line "\n"
  }
  END {
    if (item["feat"])   printf "## Features\n%s\n", item["feat"]
    if (item["fix"])    printf "## Fix\n%s\n", item["fix"]
    if (item["remove"]) printf "## Remove\n%s\n", item["remove"]
  }'
