#!/usr/bin/env bash
#
# debug-run.sh — run SpiceMac with input tracing for debugging keyboard/mouse.
# Usage: ./scripts/debug-run.sh <connection.vv>
#
# Connect with a FRESH .vv (the ticket lasts ~30s), try the keyboard and mouse in
# the guest, then quit (Cmd-Q). Share the [SpiceInput] lines from the log file.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/SpiceMac.app/Contents/MacOS/SpiceMac"
VV="${1:?usage: debug-run.sh <connection.vv>}"
LOG="${SPICEMAC_LOG:-/tmp/spicemac-input.log}"

[ -x "$APP" ] || { echo "build first: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh"; exit 1; }

echo "running with input tracing → $LOG"
echo "In the guest: move the mouse, click, and type a few keys. Then press Cmd-Q."
# Only our [SpiceInput] traces + errors (drop the verbose SPICE/GLib debug spew).
SPICEMAC_INPUT_DEBUG=1 "$APP" "$VV" 2>&1 | tee "$LOG" | grep -E "\[SpiceInput\]|error|Error" || true
echo ""
echo "Full log: $LOG"
echo "Input traces:"
grep "\[SpiceInput\]" "$LOG" | tail -40 || echo "  (none — input events never reached the view)"
