#!/usr/bin/env bash
#
# release.sh — cut a Maspice release in one command.
#
#   ./scripts/release.sh X.Y.Z[-beta.N] [--yes]
# Stable releases run on main; betas run on codex/beta-X.Y.Z.
# SIGN_IDENTITY selects a local certificate; NOTARY_PROFILE selects credentials
# already stored by notarytool in Keychain (never a password in the environment).
#
# It bumps Resources/Info.plist (both version fields), rolls CHANGELOG.md
# (Unreleased -> [X.Y.Z], fresh Unreleased, compare-links), builds the .app +
# .zip + .sha256, verifies version consistency, shows you the diff, and ONLY THEN
# — after a y/N confirm — does the irreversible part (commit, tag, push, GitHub
# release). Say no and nothing is published; roll back with:
#   git checkout Resources/Info.plist CHANGELOG.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
PLIST="Resources/Info.plist"; CHANGELOG="CHANGELOG.md"
log() { printf '\033[1;34m[release]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[release] error:\033[0m %s\n' "$*" >&2; exit 1; }

VER="${1:-}"
[ -n "$VER" ] || die "usage: release.sh X.Y.Z[-beta.N] [--yes]"
[[ "$VER" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-beta\.[1-9][0-9]*)?$ ]] \
    || die "version must be X.Y.Z or X.Y.Z-beta.N (got '$VER')"
BASE_VER="${VER%%-beta.*}"
RELEASE_BRANCH=main
RELEASE_FLAGS=(--latest)
APPCAST_FLAGS=(--maximum-versions 1)
if [[ "$VER" == *-beta.* ]]; then
    RELEASE_BRANCH="codex/beta-$BASE_VER"
    RELEASE_FLAGS=(--prerelease --latest=false)
    APPCAST_FLAGS+=(--channel beta)
fi
FEED_BRANCH="codex/update-feed"
ASSUME_YES=0
[ "${2:-}" = "--yes" ] && ASSUME_YES=1
[ "${MASPICE_ASSUME_YES:-0}" = "1" ] && ASSUME_YES=1

# --- Preflight (all reversible to here) ------------------------------------
log "preflight"
[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty — commit or stash first"
[ "$(git branch --show-current)" = "$RELEASE_BRANCH" ] || die "release must run on $RELEASE_BRANCH"
git fetch origin "$RELEASE_BRANCH" "$FEED_BRANCH" --tags
VALIDATED_COMMIT="$(git rev-parse HEAD)"
FEED_COMMIT="$(git rev-parse "origin/$FEED_BRANCH")"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$RELEASE_BRANCH")" ]] \
    || die "local branch must match origin/$RELEASE_BRANCH"
git rev-parse "v$VER" >/dev/null 2>&1 && die "tag v$VER already exists"
./scripts/check-version.sh
CUR="$(/usr/libexec/PlistBuddy -c 'Print :MaspiceReleaseVersion' "$PLIST")"
CUR_BASE="${CUR%%-beta.*}"
if [[ "$CUR_BASE" == "$BASE_VER" ]]; then
    [[ "$CUR" == *-beta.* ]] || die "version $VER must be greater than $CUR"
    if [[ "$VER" == *-beta.* ]]; then
        (( ${VER##*-beta.} > ${CUR##*-beta.} )) || die "beta number must increase from $CUR"
    fi
else
    [[ "$(printf '%s\n%s\n' "$CUR_BASE" "$BASE_VER" | sort -V | tail -1)" == "$BASE_VER" ]] \
        || die "version $VER must be greater than $CUR"
fi
# [Unreleased] must have content (lines between it and the next '## [')
unrel="$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' "$CHANGELOG" | grep -v '^[[:space:]]*$' || true)"
[ -n "$unrel" ] || die "CHANGELOG '## [Unreleased]' is empty — add notes for $VER first"
command -v gh >/dev/null 2>&1 || die "gh CLI not found (needed to publish)"

PREV="$CUR"
BASEURL="$(grep -m1 '^\[Unreleased\]: ' "$CHANGELOG" | sed -E 's|^\[Unreleased\]: (.*)/compare/.*|\1|')"
[ -n "$PREV" ] && [ -n "$BASEURL" ] || die "could not parse previous version / base URL from CHANGELOG footer"
TODAY="$(date +%F)"
log "preparing $PREV -> $VER ($TODAY)"

# --- Mutate (local, reversible) --------------------------------------------
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BASE_VER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :MaspiceReleaseVersion $VER" "$PLIST"
CURBUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
FEED_BUILD="$(git show "origin/$FEED_BRANCH:appcast.xml" | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.stdin)
print(max(int(item.text) for item in root.findall("channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}version")))
')"
NEXT_BUILD=$(( (CURBUILD > FEED_BUILD ? CURBUILD : FEED_BUILD) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PLIST"
log "Info.plist -> $VER (build $NEXT_BUILD)"

tmp="$(mktemp)"
awk -v v="$VER" -v d="$TODAY" -v prev="$PREV" -v base="$BASEURL" '
  $0 == "## [Unreleased]" { print "## [Unreleased]"; print ""; print "## [" v "] — " d; next }
  $0 ~ /^\[Unreleased\]: / { print "[Unreleased]: " base "/compare/v" v "...HEAD";
                             print "[" v "]: " base "/compare/v" prev "...v" v; next }
  { print }
' "$CHANGELOG" > "$tmp" && mv "$tmp" "$CHANGELOG"
log "CHANGELOG rolled (Unreleased -> [$VER], links updated)"

# --- Build + verify --------------------------------------------------------
log "building"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" ./scripts/build-app.sh
./scripts/check-version.sh "v$VER"
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$PLIST" 2>/dev/null || echo Maspice)"
ZIP="build/$DISPLAY_NAME.app.zip"
SHA="$(awk '{print $1}' "$ZIP.sha256" 2>/dev/null)"
SIGNING_NOTE="Ad-hoc signed; not notarized."
if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
    SIGNING_NOTE="Code signed; not notarized."
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ "${SIGN_IDENTITY:--}" != "-" ]] || die "notarization requires a Developer ID identity"
    log "submitting signed app for Apple notarization"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json > build/notarization.json
    [[ "$(python3 -c 'import json; print(json.load(open("build/notarization.json"))["status"])')" == "Accepted" ]] \
        || die "Apple did not accept notarization; inspect build/notarization.json"
    xcrun stapler staple "build/$DISPLAY_NAME.app"
    xcrun stapler validate "build/$DISPLAY_NAME.app"
    codesign --verify --deep --strict "build/$DISPLAY_NAME.app"
    spctl --assess --type execute --verbose=2 "build/$DISPLAY_NAME.app"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "build/$DISPLAY_NAME.app" "$ZIP"
    (cd build && shasum -a 256 "$DISPLAY_NAME.app.zip" > "$DISPLAY_NAME.app.zip.sha256")
    SHA="$(awk '{print $1}' "$ZIP.sha256")"
    SIGNING_NOTE="Developer ID signed, Apple notarized, with a stapled ticket."
fi
SPARKLE_TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_TOOLS/generate_appcast"
[ -x "$GENERATE_APPCAST" ] || die "Sparkle generate_appcast tool not found"
APPCAST_WORK="$(mktemp -d)"
FEED_WORK="$(mktemp -d)"
cleanup() {
    if [[ -f "$FEED_WORK/.git" ]]; then git worktree remove --force "$FEED_WORK"; else rm -rf "$FEED_WORK"; fi
    rm -rf "$APPCAST_WORK"
}
trap cleanup EXIT
git worktree add --detach "$FEED_WORK" "origin/$FEED_BRANCH"
cp "$ZIP" "$APPCAST_WORK/"
log "generating signed Sparkle appcast"
"$GENERATE_APPCAST" \
    --account io.github.beribeli.Maspice \
    --download-url-prefix "https://github.com/BeriBeli/spice-mac/releases/download/v$VER/" \
    --full-release-notes-url "https://github.com/BeriBeli/spice-mac/releases/tag/v$VER" \
    --link "https://github.com/BeriBeli/spice-mac/releases/tag/v$VER" \
    "${APPCAST_FLAGS[@]}" \
    -o "$APPCAST_WORK/appcast.xml" \
    "$APPCAST_WORK"
APPCAST="build/appcast.xml"
python3 -B scripts/update-appcast.py "$VER" "$FEED_WORK/appcast.xml" \
    "$APPCAST_WORK/appcast.xml" "$APPCAST"
python3 -B scripts/test-update-appcast.py

git fetch origin "$RELEASE_BRANCH" "$FEED_BRANCH" --tags
[[ "$(git rev-parse HEAD)" == "$VALIDATED_COMMIT" \
    && "$(git rev-parse "origin/$RELEASE_BRANCH")" == "$VALIDATED_COMMIT" \
    && "$(git rev-parse "origin/$FEED_BRANCH")" == "$FEED_COMMIT" ]] \
    || die "release branch or update feed changed during validation; do not publish this candidate"
unexpected="$(git status --porcelain | grep -Ev '^ M (CHANGELOG\.md|Resources/Info\.plist)$' || true)"
[[ -z "$unexpected" ]] || die "validation changed unexpected files: $unexpected"

# --- Review + confirm (publish is irreversible) ----------------------------
echo; log "prepared. changes:"; git --no-pager diff --stat; echo
log "SHA-256: ${SHA:-<none>}"
if [ "$ASSUME_YES" != 1 ]; then
    printf '\033[1;33mPublish v%s — commit, tag, push, and create the GitHub release? [y/N] \033[0m' "$VER" >&2
    read -r reply || reply=n
    case "$reply" in [yY]|[yY][eE][sS]) ;; *)
        echo "Not published. Roll back with: git checkout $PLIST $CHANGELOG" >&2; exit 0 ;;
    esac
fi

# --- Publish (irreversible) ------------------------------------------------
notes="$(mktemp)"
awk -v heading="## [$VER]" 'index($0,heading)==1{f=1;next} f&&/^## \[/{f=0} f' "$CHANGELOG" > "$notes"
# The backticks and command text are intentionally literal Markdown.
# shellcheck disable=SC2016
printf '\n### Download\n`%s.app.zip` — Apple Silicon, macOS 26+. %s\n\nSHA-256: `%s`\n' \
    "$DISPLAY_NAME" "$SIGNING_NOTE" "${SHA:-see asset}" >> "$notes"

git add "$PLIST" "$CHANGELOG"
git commit -q -m "Release $VER"
git tag -a "v$VER" -m "Maspice $VER"
log "pushing"
git push origin "$RELEASE_BRANCH"
git push origin "v$VER"
log "creating GitHub release"
gh release create "v$VER" "$ZIP" "$ZIP.sha256" "$APPCAST" \
    --title "Maspice $VER" --verify-tag --notes-file "$notes" "${RELEASE_FLAGS[@]}"
rm -f "$notes"
log "publishing the shared Sparkle feed after release assets are available"
cp "$APPCAST" "$FEED_WORK/appcast.xml"
git -C "$FEED_WORK" add appcast.xml
git -C "$FEED_WORK" commit -m "Publish Sparkle feed for v$VER"
git -C "$FEED_WORK" push origin "HEAD:refs/heads/$FEED_BRANCH"
log "released v$VER ✓  https://github.com/BeriBeli/spice-mac/releases/tag/v$VER"
