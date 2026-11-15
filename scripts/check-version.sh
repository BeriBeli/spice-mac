#!/usr/bin/env bash
#
# check-version.sh — assert the version is consistent across the sources that drift:
#   * Resources/Info.plist  MaspiceReleaseVersion (including an optional beta)
#   * Resources/Info.plist  numeric CFBundleShortVersionString / CFBundleVersion
#   * CHANGELOG.md          the newest released version heading
#   * CHANGELOG.md          a matching `[x.y.z]: <url>` footer compare-link
# Optionally (when $1 is given, e.g. a pushed tag "v0.1.7") also assert it matches.
# Dependency-free; exits non-zero with a precise message on mismatch. Used by CI
# and by scripts/release.sh as a final sanity check.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
CHANGELOG="$ROOT/CHANGELOG.md"
die() { printf '\033[1;31m[check-version] FAIL:\033[0m %s\n' "$*" >&2; exit 1; }

plist_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)" \
    || die "could not read CFBundleShortVersionString from $PLIST"
release_ver="$(/usr/libexec/PlistBuddy -c 'Print :MaspiceReleaseVersion' "$PLIST" 2>/dev/null)" \
    || release_ver="$plist_ver"
[[ "$release_ver" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-beta\.[1-9][0-9]*)?$ ]] \
    || die "release version must be X.Y.Z or X.Y.Z-beta.N"
[[ "$plist_ver" == "${release_ver%%-beta.*}" ]] \
    || die "CFBundleShortVersionString must be the numeric base of $release_ver"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null)"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || die "CFBundleVersion must be a positive integer"

# Newest released changelog version = first `## [x.y.z]` that is not [Unreleased].
cl_ver="$(sed -nE 's/^## \[([0-9]+\.[0-9]+\.[0-9]+(-beta\.[1-9][0-9]*)?)\].*/\1/p' "$CHANGELOG" | head -1)"
[ -n "$cl_ver" ] || die "no released '## [x.y.z]' heading found in $CHANGELOG"

[ "$release_ver" = "$cl_ver" ] \
    || die "Info.plist release version ($release_ver) != newest CHANGELOG entry ($cl_ver)"

grep -qF "[$cl_ver]: " "$CHANGELOG" \
    || die "CHANGELOG has '## [$cl_ver]' but no '[$cl_ver]: <url>' footer compare-link"

if [ "${1:-}" != "" ]; then
    tag_ver="${1#v}"
    [ "$tag_ver" = "$release_ver" ] \
        || die "tag $1 (=$tag_ver) != Info.plist/CHANGELOG version ($release_ver)"
fi

printf '\033[1;32m[check-version] OK\033[0m — Info.plist, CHANGELOG, and links agree on %s (build %s)\n' "$release_ver" "$build"
