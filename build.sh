#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Tomato Timer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/tomato.png Assets/bell.wav Assets/spaceship.wav "$APP/Contents/Resources/"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
BUILD_TMP=$(mktemp -d "${TMPDIR:-/tmp}/tomato-build.XXXXXX")
trap 'rm -rf "$BUILD_TMP"' EXIT
for ARCH in arm64 x86_64; do
    swiftc -parse-as-library Timer.swift -target "$ARCH-apple-macos13.0" -module-cache-path "${TMPDIR:-/tmp}/plant-companion-module-cache" -o "$BUILD_TMP/$ARCH" -framework AppKit
done
lipo -create "$BUILD_TMP/arm64" "$BUILD_TMP/x86_64" -output "$APP/Contents/MacOS/TomatoTimer"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TomatoTimer</string>
<key>CFBundleIdentifier</key><string>local.tomatotimer.app</string>
<key>CFBundleName</key><string>Tomato Timer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
