#!/bin/bash
# Builds a downloadable release: a universal (Apple silicon + Intel), size-optimised
# DiskMap.app, ad-hoc signed and zipped into dist/DiskMap-macOS.zip.
# Usage: ./make_release.sh [version]   (default 1.0)
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:-1.0}"
BUILD="${DISKMAP_BUILD_DIR:-$HOME/Library/Caches/DiskMap-build}"

swift build -c release --arch arm64 --arch x86_64 --scratch-path "$BUILD" -Xswiftc -Osize

DIST=dist
APP="$DIST/DiskMap.app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS"
cp "$BUILD/apple/Products/Release/DiskMap" "$APP/Contents/MacOS/DiskMap"
strip -rSTx "$APP/Contents/MacOS/DiskMap"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>DiskMap</string>
<key>CFBundleDisplayName</key><string>DiskMap</string>
<key>CFBundleIdentifier</key><string>com.alexdekker.diskmap</string>
<key>CFBundleExecutable</key><string>DiskMap</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

(cd "$DIST" && ditto -c -k --keepParent --norsrc DiskMap.app DiskMap-macOS.zip)
echo "Built $(pwd)/$DIST/DiskMap-macOS.zip ($(du -h "$DIST/DiskMap-macOS.zip" | cut -f1))"
lipo -archs "$APP/Contents/MacOS/DiskMap"
shasum -a 256 "$DIST/DiskMap-macOS.zip"
