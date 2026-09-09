#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
CONF="${1:-debug}"
swift build -c "$CONF" --package-path "$ROOT"
BIN="$(swift build -c "$CONF" --package-path "$ROOT" --show-bin-path)/TypelessLike"
APP="$ROOT/build/TypelessLike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TypelessLike"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
