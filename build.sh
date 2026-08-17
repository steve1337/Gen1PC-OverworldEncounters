#!/usr/bin/env bash
# Package Gen1PC-OverworldEncounters for drop-in install under mods/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MANIFEST="$ROOT/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "error: manifest.json not found" >&2
  exit 1
fi

MOD_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$MANIFEST")"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","0.0.0"))' "$MANIFEST")"

OUT_DIR="$ROOT/dist"
OUT_ZIP="$OUT_DIR/${MOD_ID}.zip"
OUT_VERSIONED="$OUT_DIR/${MOD_ID}-${VERSION}.zip"

mkdir -p "$OUT_DIR"
rm -f "$OUT_ZIP" "$OUT_VERSIONED"

# Zip contents at archive root (main.lua, manifest.json, ...) so the folder
# can be extracted straight into mods/<id>/. Skip build output and junk.
zip -r "$OUT_ZIP" \
  main.lua \
  manifest.json \
  mod.card \
  README.md \
  src \
  spawns \
  assets \
  -x "*.DS_Store" \
  -x "*__pycache__*" \
  -x "*/.git/*" \
  -x "dist/*"

cp "$OUT_ZIP" "$OUT_VERSIONED"

BYTES="$(wc -c < "$OUT_ZIP" | tr -d ' ')"
FILES="$(unzip -l "$OUT_ZIP" | tail -1 | awk '{print $2}')"
echo "wrote $OUT_ZIP ($BYTES bytes, $FILES entries)"
echo "wrote $OUT_VERSIONED"
