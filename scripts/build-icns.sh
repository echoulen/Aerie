#!/bin/bash
# Convert the AppIcon.appiconset PNGs (Xcode asset-catalog format) into
# a macOS .icns file using iconutil.
#
# iconutil requires the input directory to be named `*.iconset/` (NOT
# `*.appiconset/`) and to contain files named `icon_NxN.png` /
# `icon_NxN@2x.png`. Our Phase 21 icon generator already names files
# that way; we just need to repackage them into a .iconset/ directory.

set -e

ICON_SRC="${1:-Sources/Aerie/Resources/Assets.xcassets/AppIcon.appiconset}"
ICNS_OUT="${2:-Resources/AppIcon.icns}"

if [ ! -d "$ICON_SRC" ]; then
    echo "✗ Icon source not found: $ICON_SRC" >&2
    echo "  Run 'swift scripts/generate-app-icon.swift' first to (re)generate the PNGs." >&2
    exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
    echo "✗ iconutil not found — this script requires macOS." >&2
    exit 1
fi

# Skip if up to date — .icns newer than every PNG in source.
if [ -f "$ICNS_OUT" ]; then
    STALE=0
    for png in "$ICON_SRC"/icon_*.png; do
        [ -f "$png" ] || continue
        if [ "$png" -nt "$ICNS_OUT" ]; then
            STALE=1
            break
        fi
    done
    if [ "$STALE" -eq 0 ]; then
        exit 0
    fi
fi

mkdir -p "$(dirname "$ICNS_OUT")"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ICONSET="$TMPDIR/AppIcon.iconset"
mkdir -p "$ICONSET"

PNG_COUNT=0
for png in "$ICON_SRC"/icon_*.png; do
    [ -f "$png" ] || continue
    cp "$png" "$ICONSET/$(basename "$png")"
    PNG_COUNT=$((PNG_COUNT + 1))
done

if [ "$PNG_COUNT" -eq 0 ]; then
    echo "✗ No icon PNGs found in $ICON_SRC" >&2
    exit 1
fi

if ! iconutil -c icns "$ICONSET" -o "$ICNS_OUT"; then
    echo "✗ iconutil failed" >&2
    exit 1
fi

echo "→ Wrote $ICNS_OUT ($PNG_COUNT source PNGs)"
