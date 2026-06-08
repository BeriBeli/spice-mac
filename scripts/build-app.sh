#!/usr/bin/env bash
#
# build-app.sh — build SpiceMac via SwiftPM and assemble a runnable SpiceMac.app.
#
# Requirements:
#   * Full Xcode (the Metal toolchain compiles CocoaSpice's shader; Command Line
#     Tools alone cannot build the app).
#   * Native SPICE frameworks staged under ./Frameworks (run scripts/fetch-sysroot.sh).
#
# Environment overrides:
#   CONFIG=release|debug            (default: release)
#   SIGN_IDENTITY="Developer ID Application: …"   (default: "-" ad-hoc)
#   HARDENED=1                      sign with hardened runtime + entitlements
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="SpiceMac"
OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"

log() { printf '\033[1;34m[build-app]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[build-app] error:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Preconditions ---------------------------------------------------------
if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    log "WARNING: full Xcode does not appear to be selected."
    log "         CocoaSpice's Metal shader needs the Xcode Metal toolchain;"
    log "         'swift build' will fail under Command Line Tools only."
    log "         Install Xcode and: sudo xcode-select -s /Applications/Xcode.app"
fi

shopt -s nullglob
frameworks=(Frameworks/*.framework)
if [ ${#frameworks[@]} -eq 0 ]; then
    die "Frameworks/ is empty — run scripts/fetch-sysroot.sh first."
fi

# --- Build -----------------------------------------------------------------
log "swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
[ -x "$BIN_PATH/$APP_NAME" ] || die "built executable not found at $BIN_PATH/$APP_NAME"

# --- Assemble .app ---------------------------------------------------------
log "assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_PATH/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# SwiftPM resource bundles (e.g. the compiled Metal shader for the renderer).
# Place next to the executable so Bundle.module resolves at runtime.
for bundle in "$BIN_PATH"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/MacOS/"
done

# Native SPICE frameworks.
for fw in "${frameworks[@]}"; do
    cp -R "$fw" "$APP/Contents/Frameworks/"
done

# --- Sign ------------------------------------------------------------------
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" = "-" ]; then
    SIGN_ARGS+=(--timestamp=none)
else
    SIGN_ARGS+=(--timestamp)
fi

APP_SIGN_ARGS=("${SIGN_ARGS[@]}")
if [ "${HARDENED:-0}" = "1" ]; then
    APP_SIGN_ARGS+=(--options runtime --entitlements "$ROOT/Resources/$APP_NAME.entitlements")
fi

log "signing frameworks (identity: $SIGN_IDENTITY)"
# Sign nested code first (deepest first), then the app.
find "$APP/Contents/Frameworks" -type d -name "*.framework" -print0 |
    while IFS= read -r -d '' fw; do
        codesign "${SIGN_ARGS[@]}" "$fw" 2>/dev/null || codesign "${SIGN_ARGS[@]}" "$fw"
    done
for bundle in "$APP/Contents/MacOS/"*.bundle; do
    [ -e "$bundle" ] && codesign "${SIGN_ARGS[@]}" "$bundle"
done

log "signing app"
codesign "${APP_SIGN_ARGS[@]}" "$APP"

log "verifying"
codesign --verify --deep --strict --verbose=2 "$APP" || log "WARNING: codesign verification reported issues"

log "done → $APP"
log "run with: open \"$APP\"   (or pass a file: open -a \"$APP\" connection.vv)"
