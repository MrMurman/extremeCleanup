#!/bin/sh
# Builds build/ExtremeCleanup.app (Apple silicon + Intel) with swiftc directly (no SwiftPM needed).
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
app="build/ExtremeCleanup.app"
work="build/work"
rm -rf "$app" "$work"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$work"
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos14.0 \
        -o "$work/ExtremeCleanup-$arch" Sources/ExtremeCleanup/*.swift
done
lipo -create -output "$app/Contents/MacOS/ExtremeCleanup" "$work"/ExtremeCleanup-*
cp Support/Info.plist "$app/Contents/"

iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size Support/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Support/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$work"

# A stable identity keeps macOS privacy grants across updates; ad-hoc (a new identity every build) otherwise.
identity=-
security find-identity -v -p codesigning | grep -q '"boroda studio"' && identity="boroda studio"
codesign --force --sign "$identity" "$app"
echo "$root/$app"
