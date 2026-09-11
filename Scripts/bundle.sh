#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
CONF="${1:-debug}"
swift build -c "$CONF" --package-path "$ROOT"
BIN="$(swift build -c "$CONF" --package-path "$ROOT" --show-bin-path)/Untyped"
APP="$ROOT/build/Untyped.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Untyped"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Use a named code signing identity to preserve Accessibility permission grants
# across rebuilds. The certificate keeps its original name from before the app
# was renamed to Untyped; only the bundle identifier changed. Ad-hoc signing
# changes the cdhash on every build, which invalidates permission grants keyed
# to that cdhash.
if security find-identity -p codesigning | grep -q "TypelessLike Local Dev"; then
    codesign --force --sign "TypelessLike Local Dev" "$APP"
else
    echo "warning: TypelessLike Local Dev identity not found; using ad-hoc signing. Accessibility permission will be revoked on each rebuild." >&2
    codesign --force --sign - "$APP"
fi
echo "$APP"
