#!/usr/bin/env bash
#
# debug-run.sh — run Maspice from a terminal and retain SwiftSpice diagnostics.
# Usage: ./scripts/debug-run.sh <connection.vv>
#
# Captures stdout/stderr. SwiftSpice's structured OSLog messages remain available
# in Console.app under the Maspice subsystem.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
APP="$ROOT/build/$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"
VV="${1:?usage: debug-run.sh <connection.vv>}"
LOG="${MASPICE_LOG:-/tmp/maspice-debug.log}"

[ -x "$APP" ] || { echo "build first: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh"; exit 1; }

echo "running Maspice → $LOG"
echo "Reproduce the issue in the guest, then press Cmd-Q."
OS_ACTIVITY_DT_MODE=YES "$APP" "$VV" 2>&1 | tee "$LOG"
echo ""
echo "Terminal log: $LOG"
