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

# Use a named code signing identity to preserve Accessibility permission grants
# across rebuilds. Ad-hoc signing changes the cdhash on every build, which
# invalidates permission grants keyed to that cdhash.
if security find-identity -p codesigning | grep -q "TypelessLike Local Dev"; then
    codesign --force --sign "TypelessLike Local Dev" "$APP"
else
    echo "warning: TypelessLike Local Dev identity not found; using ad-hoc signing. Accessibility permission will be revoked on each rebuild." >&2
    codesign --force --sign - "$APP"
fi
echo "$APP"
