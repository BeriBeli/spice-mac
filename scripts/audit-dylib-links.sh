#!/usr/bin/env bash
# Fail when distributable Mach-O files depend on build-host library paths.
set -euo pipefail

target="${1:?usage: audit-dylib-links.sh <Mach-O-or-directory>}"
[ -e "$target" ] || { echo "audit target does not exist: $target" >&2; exit 2; }

failures=0
audit_one() {
    local binary="$1" dependency rpath
    file -b "$binary" | grep -q 'Mach-O' || return 0
    while IFS= read -r dependency; do
        case "$dependency" in
            /opt/homebrew/*|/usr/local/*)
                printf 'forbidden Homebrew dependency: %s -> %s\n' "$binary" "$dependency" >&2
                failures=$((failures + 1))
                ;;
            /System/Library/*|/usr/lib/*|@rpath/*|@loader_path/*|@executable_path/*)
                ;;
            /*)
                printf 'forbidden build-host dependency: %s -> %s\n' "$binary" "$dependency" >&2
                failures=$((failures + 1))
                ;;
        esac
    done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}')

    while IFS= read -r rpath; do
        case "$rpath" in
            @loader_path|@loader_path/*|@executable_path|@executable_path/*)
                ;;
            *)
                printf 'forbidden runtime search path: %s -> %s\n' "$binary" "$rpath" >&2
                failures=$((failures + 1))
                ;;
        esac
    done < <(otool -l "$binary" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
        in_rpath && $1 == "path" { print $2; in_rpath = 0 }
    ')
}

if [ -d "$target" ]; then
    while IFS= read -r -d '' candidate; do audit_one "$candidate"; done \
        < <(find "$target" -type f -print0)
else
    audit_one "$target"
fi

if [ "$failures" -ne 0 ]; then
    printf '%d non-relocatable dynamic-library link(s) found. Fix the SwiftSpice artifact; do not rewrite them in Maspice.\n' "$failures" >&2
    exit 1
fi
printf 'dynamic-library audit passed: %s\n' "$target"
