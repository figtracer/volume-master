#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH="${ARCH:-$(uname -m)}"
VERSION="${VERSION:-0.1.0}"
swift build -c release --arch "$ARCH" --product VolumeMaster
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"
APP="dist/Volume Master.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/VolumeMaster" "$APP/Contents/MacOS/VolumeMaster"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VolumeMaster</string>
<key>CFBundleIdentifier</key><string>com.figtracer.volumemaster</string>
<key>CFBundleName</key><string>Volume Master</string>
<key>CFBundleDisplayName</key><string>Volume Master</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.2</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAudioCaptureUsageDescription</key><string>Volume Master processes system audio locally to adjust volume, EQ, and bass. Audio is never recorded or uploaded.</string>
</dict></plist>
PLIST
swift scripts/icon.swift "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "dist/VolumeMaster-macOS-$ARCH.zip"
shasum -a 256 "dist/VolumeMaster-macOS-$ARCH.zip" > "dist/SHA256SUMS"
echo "$PWD/$APP"
