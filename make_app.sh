#!/bin/bash
# Builds DiskMap.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=DiskMap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DiskMap "$APP/Contents/MacOS/DiskMap"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>DiskMap</string>
<key>CFBundleIdentifier</key><string>com.example.diskmap</string>
<key>CFBundleExecutable</key><string>DiskMap</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
