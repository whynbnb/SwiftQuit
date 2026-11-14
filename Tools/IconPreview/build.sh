#!/bin/bash
# Builds the icon preview app and regenerates the static contact sheet.
# Usage: ./build.sh [--open]
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
ICON_SOURCE="$ROOT/SwiftQuit/MenuBarIcon.swift"

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "error: $ICON_SOURCE not found" >&2
    exit 1
fi

mkdir -p build

echo "Building IconSheet…"
swiftc -parse-as-library -O -o build/IconSheet "$ICON_SOURCE" IconSheet.swift

echo "Building IconPreview.app…"
mkdir -p build/IconPreview.app/Contents/MacOS
swiftc -parse-as-library -O \
    -o build/IconPreview.app/Contents/MacOS/IconPreview \
    "$ICON_SOURCE" PreviewApp.swift
cp Info.plist build/IconPreview.app/Contents/Info.plist

./build/IconSheet build/sheet.png

echo
echo "Built:"
echo "  build/IconPreview.app   (double-click or: open build/IconPreview.app)"
echo "  build/sheet.png         (static contact sheet)"

if [[ "${1:-}" == "--open" ]]; then
    open build/IconPreview.app
fi
