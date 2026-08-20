#!/usr/bin/env bash
# Build Maspice and assemble a distributable app only from relocatable inputs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
SWIFTPM_BUILD_SYSTEM="${SWIFTPM_BUILD_SYSTEM:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
PLIST="$ROOT/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { printf '\033[1;34m[build-app]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[build-app] error:\033[0m %s\n' "$*" >&2; exit 1; }

xcode-select -p >/dev/null 2>&1 || die "Xcode command-line tools are unavailable"

BUILD_SYSTEM_ARGS=()
if [ -n "$SWIFTPM_BUILD_SYSTEM" ]; then
    BUILD_SYSTEM_ARGS=(--build-system "$SWIFTPM_BUILD_SYSTEM")
fi
log "swift build -c $CONFIG${SWIFTPM_BUILD_SYSTEM:+ ($SWIFTPM_BUILD_SYSTEM build system)}"
swift build --disable-sandbox -c "$CONFIG" "${BUILD_SYSTEM_ARGS[@]}"
BIN_PATH="$(swift build --disable-sandbox -c "$CONFIG" \
    "${BUILD_SYSTEM_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_PATH/$EXECUTABLE_NAME"
[ -x "$BINARY" ] || die "built executable not found at $BINARY"
SWIFTSPICE_SOURCE="$ROOT/.build/checkouts/spice-swift"
[ -f "$SWIFTSPICE_SOURCE/Package.swift" ] \
    || die "resolved SwiftSpice release checkout not found at $SWIFTSPICE_SOURCE"
SPARKLE_ROOT="$ROOT/.build/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_FRAMEWORK" ] \
    || die "resolved Sparkle framework not found at $SPARKLE_FRAMEWORK"

# This gate intentionally runs before assembling or signing. Maspice never uses
# install_name_tool to disguise Homebrew paths supplied by SwiftSpice.
log "auditing native dependency closure"
"$ROOT/scripts/audit-dylib-links.sh" "$BINARY"

log "assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$BINARY" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

METAL_BUNDLE="$BIN_PATH/SwiftSpice_SpiceMetalCompositor.bundle"
[ -f "$METAL_BUNDLE/SpiceVideoCompositor.metallib" ] \
    || die "SwiftSpice Metal resource bundle is missing from the SwiftPM build"
cp -R "$METAL_BUNDLE" "$APP/Contents/Resources/"

ICON_SOURCE="$ROOT/Resources/AppIcon.icon"
ICON_OUTPUT="$WORK/icon-assets"
[ -d "$ICON_SOURCE" ] || die "Icon Composer source not found: $ICON_SOURCE"
mkdir -p "$ICON_OUTPUT"
log "compiling Icon Composer artwork"
xcrun actool "$ICON_SOURCE" \
    --compile "$ICON_OUTPUT" \
    --output-format human-readable-text \
    --notices --warnings \
    --app-icon AppIcon \
    --include-all-app-icons \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --output-partial-info-plist "$ICON_OUTPUT/partial.plist" \
    >"$WORK/actool.log" 2>&1 \
    || { sed 's/^/         actool: /' "$WORK/actool.log" >&2; die "icon compilation failed"; }
cp "$ICON_OUTPUT/Assets.car" "$APP/Contents/Resources/Assets.car"
cp "$ICON_OUTPUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

log "bundling license notices"
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$SWIFTSPICE_SOURCE/LICENSE" \
    "$APP/Contents/Resources/Licenses/SwiftSpice-MIT.txt"
cp "$SWIFTSPICE_SOURCE/THIRD_PARTY_NOTICES.md" \
    "$APP/Contents/Resources/Licenses/SwiftSpice-THIRD_PARTY_NOTICES.md"
cp "$SPARKLE_ROOT/LICENSE" \
    "$APP/Contents/Resources/Licenses/Sparkle-MIT.txt"
while IFS= read -r -d '' license; do
    cp "$license" "$APP/Contents/Resources/Licenses/"
done < <(find "$SWIFTSPICE_SOURCE/Artifacts" -path '*/Licenses/*' -type f -print0)
cp "$ROOT/THIRD-PARTY-LICENSES.txt" "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

"$ROOT/scripts/audit-dylib-links.sh" "$APP"

SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" = "-" ]; then SIGN_ARGS+=(--timestamp=none); else SIGN_ARGS+=(--timestamp); fi
if [ "${HARDENED:-0}" = "1" ]; then
    SIGN_ARGS+=(--options runtime)
fi
log "signing embedded Sparkle framework"
codesign "${SIGN_ARGS[@]}" --deep "$APP/Contents/Frameworks/Sparkle.framework"
log "signing app (identity: $SIGN_IDENTITY)"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [ "${PACKAGE:-1}" = "1" ]; then
    ZIP="$OUT/$APP_NAME.app.zip"
    rm -f "$ZIP" "$ZIP.sha256"
    log "packaging $ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    (cd "$OUT" && shasum -a 256 "$APP_NAME.app.zip" > "$APP_NAME.app.zip.sha256")
fi
log "done -> $APP"
