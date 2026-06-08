#!/usr/bin/env bash
#
# debug-run.sh — run SpiceMac with verbose SPICE / GStreamer logging.
# Usage: ./scripts/debug-run.sh <connection.vv>
#
# Captures the spice-gtk channel lifecycle, clipboard, and GStreamer audio logs
# (SPICE_DEBUG / G_MESSAGES_DEBUG / GST_DEBUG) to a file for diagnosing
# connection / channel / audio issues. Connect with a FRESH .vv (the ticket lasts
# ~30s), reproduce the issue, then quit (Cmd-Q).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/SpiceMac.app/Contents/MacOS/SpiceMac"
VV="${1:?usage: debug-run.sh <connection.vv>}"
LOG="${SPICEMAC_LOG:-/tmp/spicemac-debug.log}"

[ -x "$APP" ] || { echo "build first: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh"; exit 1; }

echo "running with SPICE/GStreamer tracing → $LOG"
echo "Reproduce the issue in the guest, then press Cmd-Q."
SPICE_DEBUG=1 G_MESSAGES_DEBUG=all GST_DEBUG="${GST_DEBUG:-2}" "$APP" "$VV" 2>&1 \
    | tee "$LOG" \
    | grep -iE "inputs channel|clipboard|audio|playback|gst|sink|zap|switching|migrat|reset|error" || true
echo ""
echo "Full log: $LOG  (channel events: grep -iE 'inputs|zap|switch|migrat' \"$LOG\")"
