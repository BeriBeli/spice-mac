#!/usr/bin/env bash
# Sign embedded Sparkle code inside-out, then the Maspice app bundle.
set -euo pipefail

APP="${1:?usage: sign-app.sh path/to/Maspice.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
[[ -f "$APP/Contents/Info.plist" && -d "$SPARKLE" ]] \
    || { echo '[sign-app] expected a complete Maspice app bundle' >&2; exit 1; }

SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_ARGS+=(--timestamp=none)
else
    SIGN_ARGS+=(--timestamp --options runtime)
fi
if [[ "${HARDENED:-0}" == "1" && "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_ARGS+=(--options runtime)
fi

# Preserve Sparkle's shipped helper entitlements. --deep is for verification,
# not signing: each nested code object receives an explicit signature.
for nested in \
    "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
    "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
    "$SPARKLE/Versions/B/Autoupdate" \
    "$SPARKLE/Versions/B/Updater.app"; do
    codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$nested"
done
codesign "${SIGN_ARGS[@]}" "$SPARKLE"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
