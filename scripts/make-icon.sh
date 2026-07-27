#!/usr/bin/env bash
#
# make-icon.sh — validate the Icon Composer source and refresh the README preview.
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SRC="${1:-Resources/AppIcon.icon}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
log() { printf '\033[1;34m[make-icon]\033[0m %s\n' "$*"; }

[ -d "$SRC" ] || { echo "Icon Composer source not found: $SRC" >&2; exit 1; }
COMPILED="$WORK/compiled"; mkdir -p "$COMPILED"

log "compiling $SRC"
xcrun actool "$SRC" \
    --compile "$COMPILED" \
    --output-format human-readable-text \
    --notices --warnings \
    --app-icon AppIcon \
    --include-all-app-icons \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --output-partial-info-plist "$COMPILED/partial.plist"

[ -f "$COMPILED/Assets.car" ] || { echo "actool did not produce Assets.car" >&2; exit 1; }
[ -f "$COMPILED/AppIcon.icns" ] || { echo "actool did not produce AppIcon.icns" >&2; exit 1; }

ICONSET="$WORK/AppIcon.iconset"
iconutil --convert iconset --output "$ICONSET" "$COMPILED/AppIcon.icns"
PREVIEW="$ICONSET/icon_128x128@2x.png"
[ -f "$PREVIEW" ] || { echo "compiled icon preview not found" >&2; exit 1; }

log "refreshing design/icon/icon.png"
sips -z 512 512 "$PREVIEW" --out design/icon/icon.png >/dev/null
log "valid Icon Composer source; README preview refreshed"
