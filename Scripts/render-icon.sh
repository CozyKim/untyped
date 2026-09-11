#!/bin/zsh
# Rebuild all previews and the selected app icon using the macOS SDK tools.
set -euo pipefail
ROOT="${0:A:h}/.."
PREVIEWS="$ROOT/Scripts/icon-previews"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/untyped-icon.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

swift -module-cache-path "$TEMP_DIR/module-cache" "$ROOT/Scripts/render-icon.swift" "$PREVIEWS"
ICONSET="$TEMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
SOURCE="$PREVIEWS/b-speech-cursor.png"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Created Resources/AppIcon.icns (b-speech-cursor)"
