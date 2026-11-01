#!/usr/bin/env bash
set -euo pipefail

echo "=== BRWR Render Web Build ==="

npm install --prefix relay --omit=dev

GODOT_VERSION="4.7.2-stable"
GODOT_ZIP="/tmp/godot.zip"
GODOT_DIR="/tmp/godot"
GODOT="$GODOT_DIR/Godot_v4.7.2-stable_linux.x86_64"

mkdir -p "$GODOT_DIR"

curl -L \
  "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip" \
  -o "$GODOT_ZIP"

unzip -q "$GODOT_ZIP" -d "$GODOT_DIR"
chmod +x "$GODOT"

TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/4.7.2.stable"
mkdir -p "$TEMPLATE_DIR"

cp tools/render/web_nothreads_release.zip \
   "$TEMPLATE_DIR/web_nothreads_release.zip"

TMP="/tmp/brwr_web_build"
rm -rf "$TMP"
mkdir -p "$TMP"

cp -a . "$TMP/"

rm -rf "$TMP/output"
rm -rf "$TMP/.godot"
rm -rf "$TMP/.tls"
rm -rf "$TMP/.multiplayer_relay_backup"

# Sorgenti fotografici che sappiamo non essere usati nel gioco
rm -f "$TMP"/assets/mages/IMG*.jpg
rm -f "$TMP"/assets/schools/IMG*.jpg

# Ottimizzazione SOLO della copia Web.
# Gli asset originali nel repository non vengono modificati.
find "$TMP/assets" -type f -name "*.import" -print0 |
while IFS= read -r -d '' f; do
    sed -i \
      -e 's/^compress\/mode=.*/compress\/mode=1/' \
      -e 's/^compress\/lossy_quality=.*/compress\/lossy_quality=0.72/' \
      -e 's/^process\/size_limit=.*/process\/size_limit=1280/' \
      "$f"
done

mkdir -p "$TMP/output/web"

echo "Import + export Godot..."

"$GODOT" \
  --headless \
  --path "$TMP" \
  --editor \
  --export-release Web \
  "$TMP/output/web/index.html"

gzip -9 -k -f "$TMP/output/web/index.js" 2>/dev/null || true
gzip -9 -k -f "$TMP/output/web/index.wasm" 2>/dev/null || true
gzip -9 -k -f "$TMP/output/web/index.pck" 2>/dev/null || true

rm -rf output/web
mkdir -p output/web
cp -a "$TMP/output/web/." output/web/

echo "=== WEB BUILD READY ==="
du -h output/web/index.pck || true
du -h output/web/index.pck.gz || true
