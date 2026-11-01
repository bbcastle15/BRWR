#!/usr/bin/env bash
set -euo pipefail

echo "=== BRWR WEB OPTIMIZED BUILD ON RENDER ==="

ROOT="$(pwd)"
TMP="/tmp/BRWR_web_render_optimized"
GODOT_DIR="/tmp/godot"
GODOT_ZIP="/tmp/godot.zip"
GODOT="$GODOT_DIR/Godot_v4.7.2-stable_linux.x86_64"

# ------------------------------------------------------------
# NODE
# ------------------------------------------------------------

npm install --prefix relay --omit=dev

# ------------------------------------------------------------
# GODOT 4.7.2
# ------------------------------------------------------------

rm -rf "$GODOT_DIR"
mkdir -p "$GODOT_DIR"

curl -fL --retry 3 \
"https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip" \
-o "$GODOT_ZIP"

unzip -q "$GODOT_ZIP" -d "$GODOT_DIR"
chmod +x "$GODOT"

echo "Godot:"
"$GODOT" --version

# ------------------------------------------------------------
# STESSO TEMPLATE DELLA BUILD WINDOWS FUNZIONANTE
# ------------------------------------------------------------

TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/4.7.2.stable"
mkdir -p "$TEMPLATE_DIR"

cp "$ROOT/tools/render/web_nothreads_release.zip" \
"$TEMPLATE_DIR/web_nothreads_release.zip"

# ------------------------------------------------------------
# COPIA TEMPORANEA DEL PROGETTO
# ------------------------------------------------------------

rm -rf "$TMP"
mkdir -p "$TMP"

cp -a "$ROOT/." "$TMP/"

rm -rf \
"$TMP/.git" \
"$TMP/.godot" \
"$TMP/output" \
"$TMP/.tls" \
"$TMP/.multiplayer_relay_backup"

find "$TMP" -type f \( \
-name "*.bak" -o \
-name "*.backup" -o \
-name "*.tmp" \
\) -delete

# ------------------------------------------------------------
# REPLICA ESATTA DELLA LOGICA DELLO SCRIPT POWERSHELL:
# - elimina solo IMG*.jpg non referenziati
# - aggiunge anche parametri mancanti nei .import
# ------------------------------------------------------------

python3 - "$ROOT" "$TMP" <<'PY'
import sys
import re
from pathlib import Path

source = Path(sys.argv[1])
temp = Path(sys.argv[2])

text_ext = {".gd", ".tscn", ".tres", ".json", ".cfg", ".txt"}
excluded = {".git", ".godot", "output", ".tls", ".multiplayer_relay_backup"}

corpus = []

for p in source.rglob("*"):
    if not p.is_file():
        continue
    if any(part in excluded for part in p.parts):
        continue
    if p.suffix.lower() not in text_ext:
        continue

    try:
        corpus.append(p.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        pass

corpus = "\n".join(corpus)

for pattern in (
    "assets/mages/IMG*.jpg",
    "assets/schools/IMG*.jpg",
):
    for img in temp.glob(pattern):
        if img.name not in corpus:
            print("Escludo sorgente non referenziata:", img.relative_to(temp))
            img.unlink(missing_ok=True)

            imp = Path(str(img) + ".import")
            imp.unlink(missing_ok=True)
        else:
            print("Mantengo immagine referenziata:", img.name)


def set_option(content, key, value):
    escaped = re.escape(key)

    if re.search(rf"^{escaped}=", content, flags=re.MULTILINE):
        return re.sub(
            rf"^{escaped}=.*$",
            f"{key}={value}",
            content,
            flags=re.MULTILINE,
        )

    match = re.search(r"^\[params\]\s*$", content, flags=re.MULTILINE)

    if match:
        pos = match.end()
        return content[:pos] + f"\n{key}={value}" + content[pos:]

    return content + f"\n[params]\n{key}={value}\n"


edited = 0
missing = 0

assets = temp / "assets"

for img in assets.rglob("*"):
    if not img.is_file():
        continue

    if img.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"}:
        continue

    imp = Path(str(img) + ".import")

    if not imp.exists():
        missing += 1
        continue

    content = imp.read_text(encoding="utf-8", errors="ignore")

    content = set_option(content, "compress/mode", "1")
    content = set_option(content, "compress/lossy_quality", "0.72")
    content = set_option(content, "process/size_limit", "1280")

    imp.write_text(content, encoding="utf-8", newline="\n")
    edited += 1

print("Import texture modificati:", edited)
print("Immagini senza .import:", missing)
PY

# ------------------------------------------------------------
# EXPORT
# ------------------------------------------------------------

mkdir -p "$TMP/output/web"

LOG="$TMP/web-render-export.log"

echo "=== GODOT IMPORT + EXPORT ==="

set +e

"$GODOT" \
--headless \
--path "$TMP" \
--editor \
--export-release Web \
"$TMP/output/web/index.html" \
> "$LOG" 2>&1

CODE=$?

set -e

if [ "$CODE" -ne 0 ] || grep -Eq "SCRIPT ERROR:|ERROR:" "$LOG"; then
    echo "=== GODOT EXPORT FAILED ==="
    tail -n 100 "$LOG"
    exit 1
fi

for name in index.js index.wasm index.pck; do

    if [ ! -f "$TMP/output/web/$name" ]; then
        echo "File export mancante: $name"
        exit 1
    fi

    gzip -9 -k -f "$TMP/output/web/$name"
done

# ------------------------------------------------------------
# PUBBLICA LA BUILD NELLA CARTELLA SERVITA DAL RELAY
# ------------------------------------------------------------

rm -rf "$ROOT/output/web"
mkdir -p "$ROOT/output/web"

cp -a "$TMP/output/web/." "$ROOT/output/web/"

echo ""
echo "=== WEB BUILD READY ==="

du -h "$ROOT/output/web/index.pck"
du -h "$ROOT/output/web/index.pck.gz"
du -h "$ROOT/output/web/index.wasm"
du -h "$ROOT/output/web/index.wasm.gz"

echo ""
echo "BRWR Web build completed successfully."