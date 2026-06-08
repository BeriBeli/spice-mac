#!/usr/bin/env bash
#
# upgrade-openssl.sh — replace the bundled EOL OpenSSL 1.1.1b (Feb 2019) in
# ./Frameworks with OpenSSL 1.1.1w (Sept 2023), the FINAL 1.1.1 release.
#
# 1.1.1w is ABI-compatible with 1.1.1b (same libssl.1.1 / libcrypto.1.1 SONAME),
# so it's a drop-in: spice-gtk does NOT need rebuilding. It includes the fix for
# CVE-2022-0778 (BN_mod_sqrt handshake DoS) and every other 1.1.1 CVE through the
# branch's EOL. (For a non-EOL stack you'd rebuild the whole sysroot against
# OpenSSL 3.x, which requires rebuilding spice-gtk — out of scope here.)
#
# Run AFTER scripts/fetch-sysroot.sh (needs the staged ssl.1.1/crypto.1.1
# frameworks), then re-run scripts/build-app.sh to repackage the .app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="$ROOT/Frameworks"
VER="1.1.1w"
# Official OpenSSL 1.1.1w source tarball SHA-256.
SHA256="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

log() { printf '\033[1;34m[upgrade-openssl]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[upgrade-openssl] error:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$FW/ssl.1.1.framework" ] && [ -d "$FW/crypto.1.1.framework" ] \
    || die "ssl.1.1/crypto.1.1 frameworks not found in Frameworks/ — run fetch-sysroot.sh first"

log "current: $(strings "$FW/crypto.1.1.framework/crypto.1.1" | grep -m1 -iE '^OpenSSL 1\.1')"

cd "$WORK"
log "downloading OpenSSL $VER source"
DL_URLS=(
    "https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-$VER.tar.gz"
    "https://www.openssl.org/source/openssl-$VER.tar.gz"
    "https://www.openssl.org/source/old/1.1.1/openssl-$VER.tar.gz"
)
ok=
for attempt in 1 2 3 4 5 6 7 8; do
    for url in "${DL_URLS[@]}"; do
        if curl -fL --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 20 \
                -o openssl.tgz "$url" 2>/dev/null \
           && [ "$(stat -f%z openssl.tgz 2>/dev/null || echo 0)" -gt 1000000 ]; then
            ok=1; break 2
        fi
    done
    log "  download attempt $attempt failed (flaky network); retrying"
done
[ -n "$ok" ] || die "download failed after retries"
echo "$SHA256  openssl.tgz" | shasum -a 256 -c - || die "source checksum mismatch — aborting"
tar xzf openssl.tgz
cd "openssl-$VER"

log "configuring + building libs (arm64)"
./Configure darwin64-arm64-cc shared no-tests --prefix="$WORK/out" >/dev/null
make -j"$(sysctl -n hw.ncpu)" build_libs >/dev/null 2>"$WORK/build.log" \
    || { tail -20 "$WORK/build.log"; die "build failed"; }

CRYPTO="$PWD/libcrypto.1.1.dylib"
SSL="$PWD/libssl.1.1.dylib"
[ -f "$CRYPTO" ] && [ -f "$SSL" ] || die "built dylibs not found"

# Match the bundled frameworks' install names exactly so it's a true drop-in.
install_name_tool -id "@rpath/crypto.1.1.framework/crypto.1.1" "$CRYPTO"
install_name_tool -id "@rpath/ssl.1.1.framework/ssl.1.1" "$SSL"
oldcrypto="$(otool -L "$SSL" | awk '/libcrypto/{print $1; exit}')"
[ -n "$oldcrypto" ] && install_name_tool -change "$oldcrypto" \
    "@rpath/crypto.1.1.framework/Versions/A/crypto.1.1" "$SSL"

log "swapping binaries into the frameworks"
cp "$CRYPTO" "$FW/crypto.1.1.framework/Versions/A/crypto.1.1"
cp "$SSL" "$FW/ssl.1.1.framework/Versions/A/ssl.1.1"

log "re-signing (ad-hoc)"
codesign --force --sign - "$FW/crypto.1.1.framework"
codesign --force --sign - "$FW/ssl.1.1.framework"

log "done. now: $(strings "$FW/crypto.1.1.framework/crypto.1.1" | grep -m1 -iE '^OpenSSL 1\.1')"
log "re-run scripts/build-app.sh to repackage SpiceMac.app with the updated OpenSSL."
