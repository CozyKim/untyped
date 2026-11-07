#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
CONF="${1:-debug}"
# Capture the source revision at build time; the installed app never needs Git.
GIT_COMMIT="$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null || true)"
if [[ -n "$GIT_COMMIT" && -n "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]]; then
    GIT_COMMIT="$GIT_COMMIT-dirty"
fi
swift build -c "$CONF" --package-path "$ROOT"
BIN="$(swift build -c "$CONF" --package-path "$ROOT" --show-bin-path)/Untyped"
APP="$ROOT/build/Untyped.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Untyped"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "$GIT_COMMIT" ]]; then
    /usr/libexec/PlistBuddy -c "Add :UntypedGitCommit string $GIT_COMMIT" "$APP/Contents/Info.plist"
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
