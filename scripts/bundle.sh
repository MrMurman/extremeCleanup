#!/bin/sh
# Builds build/ExtremeCleanup.app with swiftc directly (no SwiftPM needed).
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
app="build/ExtremeCleanup.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
    -o "$app/Contents/MacOS/ExtremeCleanup" Sources/ExtremeCleanup/*.swift
cp Support/Info.plist "$app/Contents/"
# A stable local identity keeps macOS privacy grants across rebuilds; ad-hoc otherwise.
identity=-
security find-identity -v -p codesigning | grep -q '"DeskToy Dev"' && identity="DeskToy Dev"
codesign --force --sign "$identity" "$app"
echo "$root/$app"
