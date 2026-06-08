#!/usr/bin/env bash
#
# run-as-root.sh — launch SpiceMac as root so libusb can CAPTURE (seize) USB
# devices that macOS kernel drivers claim (mass storage, HID, audio, serial,
# iOS, …). On a personal/ad-hoc-signed build this is the only entitlement-free
# way to redirect such devices: the alternative is the Apple-restricted
# `com.apple.vm.device-access` entitlement, which ad-hoc signatures cannot carry.
#
# You do NOT need this for "driverless" devices (vendor-specific class 0xFF,
# FTDI on macOS 12+, many JTAG/printer dongles) — those redirect unprivileged.
# Check with:  ioreg -p IOUSB -l | grep -i IOUSBHostInterface   (no class driver
# bound → libusb can claim it without root).
#
# CAVEATS (per Apple DTS + community): running a GUI app as root is discouraged —
# larger attack surface, and clipboard/TCC/Full-Disk-Access behave differently as
# root. Capture is WHOLE-DEVICE (all interfaces of a composite device are taken).
# HID devices may not detach even as root. Use only when you actually need it.
#
# Usage: ./scripts/run-as-root.sh <connection.vv>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/SpiceMac.app/Contents/MacOS/SpiceMac"
VV="${1:?usage: run-as-root.sh <connection.vv>}"
[ -x "$APP" ] || { echo "build first: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh"; exit 1; }
[ -f "$VV" ]  || { echo "no such .vv: $VV"; exit 1; }

echo "Launching SpiceMac as root for USB capture (you'll be prompted for your password)."
echo "Quit with ⌘Q. Driverless devices don't need this."
exec sudo "$APP" "$VV"
