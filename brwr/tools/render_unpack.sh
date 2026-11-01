#!/usr/bin/env bash
set -euo pipefail

echo "=== BRWR WEB BUNDLE ==="

npm install --prefix relay --omit=dev

rm -rf output/web
mkdir -p output/web

# Copia i file che non sono spezzati
find deploy/web_bundle -maxdepth 1 -type f \
    ! -name '*.part[0-9][0-9][0-9]' \
    -exec cp {} output/web/ \;

# Ricompone i file grandi
for first in deploy/web_bundle/*.part001; do

    [ -e "$first" ] || continue

    base="${first%.part001}"
    name="$(basename "$base")"

    echo "Ricompongo $name"

    : > "output/web/$name"

    for part in "${base}".part*; do
        cat "$part" >> "output/web/$name"
    done
done

echo ""
echo "=== WEB BUILD READY ==="
du -h output/web/*

echo ""
echo "Starting BRWR relay."