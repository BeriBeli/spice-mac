#!/usr/bin/env bash
#
# upgrade-openssl.sh — replace the bundled EOL OpenSSL 1.1.1 in ./Frameworks with
# a supported OpenSSL 3.5 LTS (security-maintained to 2030), built from source.
#
# THE MASQUERADE. OpenSSL 3.x bumps the SONAME (1.1 -> 3), but spice-client-glib in
# this sysroot was compiled against 1.1.1 and loads `@rpath/ssl.1.1.framework/ssl.1.1`
# + `crypto.1.1.framework/crypto.1.1`. We build 3.5.x and give it those SAME install
# names, so it's a drop-in WITHOUT rebuilding spice-gtk. This is safe here because:
#   * spice-client-glib imports only ~72 OpenSSL symbols, ALL of which are documented
#     public-API functions present in 3.x (the few deprecated-in-3.0 ones — RSA_size,
#     RSA_public_encrypt, EVP_PKEY_cmp/get0_RSA — are retained, not removed). There
#     are no data symbols, and spice-gtk uses opaque pointers (since 1.1.0), so the
#     public-API ABI is preserved.
#   * The script VERIFIES this after swapping: every OpenSSL symbol spice-client-glib
#     imports must resolve in the new 3.x libs, or it aborts (so a future incompatible
#     change can't ship silently). Still, run a real TLS connection to confirm.
# The fully clean alternative is rebuilding the sysroot against 3.x (rebuilds
# spice-gtk); the entitlement-style drop-in here avoids that.
#
# Run AFTER scripts/fetch-sysroot.sh (needs the staged ssl.1.1/crypto.1.1 frameworks),
# then re-run scripts/build-app.sh to repackage the .app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="$ROOT/Frameworks"
VER="3.5.6"
# Official OpenSSL 3.5.6 source tarball SHA-256 (github.com/openssl + openssl.org agree).
SHA256="deae7c80cba99c4b4f940ecadb3c3338b13cb77418409238e57d7f31f2a3b736"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

log() { printf '\033[1;34m[upgrade-openssl]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[upgrade-openssl] error:\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$FW/ssl.1.1.framework" ] && [ -d "$FW/crypto.1.1.framework" ] \
    || die "ssl.1.1/crypto.1.1 frameworks not found in Frameworks/ — run fetch-sysroot.sh first"

log "current: $(strings "$FW/crypto.1.1.framework/crypto.1.1" | grep -m1 -iE '^OpenSSL [0-9]')"

cd "$WORK"
log "downloading OpenSSL $VER source"
DL_URLS=(
    "https://github.com/openssl/openssl/releases/download/openssl-$VER/openssl-$VER.tar.gz"
    "https://www.openssl.org/source/openssl-$VER.tar.gz"
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

# Keep deprecated symbols (RSA_size/EVP_PKEY_cmp/… that spice-gtk imports) — the
# DEFAULT build retains them; do NOT pass no-deprecated. no-docs/no-tests speed it up.
log "configuring + building libs (arm64) — a few minutes"
./Configure darwin64-arm64-cc shared no-tests no-docs --prefix="$WORK/out" >/dev/null
make -j"$(sysctl -n hw.ncpu)" build_libs >/dev/null 2>"$WORK/build.log" \
    || { tail -25 "$WORK/build.log"; die "build failed"; }

# OpenSSL 3.x emits libcrypto.3.dylib / libssl.3.dylib (real files; *.dylib are symlinks).
CRYPTO="$(/usr/bin/find "$PWD" -maxdepth 1 -name 'libcrypto.*.dylib' -type f | head -1)"
SSL="$(/usr/bin/find "$PWD" -maxdepth 1 -name 'libssl.*.dylib' -type f | head -1)"
[ -f "$CRYPTO" ] && [ -f "$SSL" ] || die "built dylibs not found"

# Masquerade: give the 3.x libs the bundled frameworks' 1.1 install names, and point
# libssl's libcrypto dependency at the 1.1-named crypto framework.
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

# --- Safety gate: every OpenSSL symbol spice-client-glib imports MUST resolve ------
log "verifying spice-client-glib's OpenSSL imports all resolve in $VER"
SPICE="$FW/spice-client-glib-2.0.8.framework/Versions/A/spice-client-glib-2.0.8"
OSSL_RE='^_(SSL|TLS|X509|EVP|BIO|RSA|BN|ASN1|PEM|ERR|CRYPTO|OPENSSL|RAND|HMAC|SHA|MD5|AES|DH|EC|PKCS|d2i|i2d|OBJ|GENERAL_NAME|DSA|CONF|ENGINE)'
imported="$(nm -u "$SPICE" 2>/dev/null | grep -oE '_[A-Za-z0-9_]+' | grep -E "$OSSL_RE" | sort -u)"
exported="$( { nm -g "$FW/crypto.1.1.framework/Versions/A/crypto.1.1"; \
               nm -g "$FW/ssl.1.1.framework/Versions/A/ssl.1.1"; } 2>/dev/null \
             | awk '$2 ~ /^[TSDBR]$/ {print $3}' | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$imported") <(printf '%s\n' "$exported"))"
if [ -n "$missing" ]; then
    printf '%s\n' "$missing" | sed 's/^/  MISSING: /' >&2
    die "$(printf '%s\n' "$missing" | grep -c .) OpenSSL symbol(s) spice-client-glib needs are NOT in $VER — masquerade unsafe, NOT swapping a broken stack. Investigate before shipping."
fi
log "all $(printf '%s\n' "$imported" | grep -c .) imported OpenSSL symbols resolve ✓"

log "done. now: $(strings "$FW/crypto.1.1.framework/crypto.1.1" | grep -m1 -iE '^OpenSSL [0-9]')"
log "re-run scripts/build-app.sh to repackage SpiceMac.app, then test a real TLS connection."
