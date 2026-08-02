#!/usr/bin/env bash
# Report whether this checkout is ready to build Maspice.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
fails=0
pass() { printf '  \033[1;32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[1;31m✗\033[0m %s\n     ↳ %s\n' "$1" "$2"; fails=$((fails+1)); }

printf '\033[1;34m[doctor]\033[0m checking the Maspice build environment\n'
macos_version="$(sw_vers -productVersion 2>/dev/null || true)"
macos_major="${macos_version%%.*}"
if [ -n "$macos_major" ] && [ "$macos_major" -ge 26 ] 2>/dev/null; then pass "macOS $macos_version (26+)"
else fail "unsupported macOS ${macos_version:-unknown}" "Maspice requires macOS 26 or later."; fi

if [ "$(uname -m)" = "arm64" ]; then pass "Apple Silicon (arm64)"
else fail "unsupported architecture $(uname -m)" "SwiftSpice now supports Apple Silicon only."; fi

xc="$(xcode-select -p 2>/dev/null || true)"
if printf '%s' "$xc" | grep -q 'Xcode.app'; then pass "full Xcode selected ($xc)"
else fail "full Xcode not selected" "sudo xcode-select -s /Applications/Xcode.app"; fi

swift_line="$(swift --version 2>/dev/null | head -1 || true)"
swift_version="$(printf '%s\n' "$swift_line" | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p')"
if [ -n "$swift_version" ] && awk -v v="$swift_version" 'BEGIN { split(v,a,"."); exit !(a[1] > 6 || (a[1] == 6 && a[2] >= 3)) }'; then
    pass "Swift $swift_version (6.3+)"
else fail "Swift 6.3+ required (got: ${swift_line:-unknown})" "select Xcode 26.3 or later."; fi

sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
sdk_major="${sdk_version%%.*}"
if [ -n "$sdk_major" ] && [ "$sdk_major" -ge 26 ] 2>/dev/null; then pass "macOS SDK $sdk_version (26+)"
else fail "macOS 26+ SDK not found" "install and select Xcode 26 or later."; fi

metal_path="$(xcrun -f metal 2>/dev/null || true)"
if [ -x "$metal_path" ]; then pass "Metal toolchain ($metal_path)"
else fail "Metal toolchain not found" "xcodebuild -downloadComponent MetalToolchain"; fi

expected_version="$(
    awk '
        /url:[[:space:]]*"https:\/\/github.com\/BeriBeli\/spice-swift\.git"/ {
            in_swiftspice = 1
        }
        in_swiftspice && /exact:[[:space:]]*"[^"]+"/ {
            version = $0
            sub(/^.*exact:[[:space:]]*"/, "", version)
            sub(/".*$/, "", version)
            print version
            exit
        }
        in_swiftspice && /\)/ {
            in_swiftspice = 0
        }
    ' "$ROOT/Package.swift"
)"
resolved_version="$(sed -nE '/"identity"[[:space:]]*:[[:space:]]*"spice-swift"/,/}/{s/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p;}' "$ROOT/Package.resolved" 2>/dev/null | head -1)"
if [ -z "$expected_version" ]; then
    fail "SwiftSpice exact version not found" "declare an exact SwiftSpice version in Package.swift"
elif [ "$resolved_version" = "$expected_version" ]; then
    pass "SwiftSpice release $expected_version resolved"
else
    fail "SwiftSpice release $expected_version is not resolved" "swift package resolve"
fi

printf '\n'
if [ "$fails" -eq 0 ]; then printf '\033[1;32m[doctor] ready for development builds\033[0m\n'
else printf '\033[1;31m[doctor] %d issue(s) found\033[0m\n' "$fails"; exit 1; fi
