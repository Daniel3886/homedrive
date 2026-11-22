#!/bin/sh
# Builds HomeDrive.app into ./dist (release build, ad-hoc signed).
#   scripts/build-app.sh            build dist/HomeDrive.app
#   scripts/build-app.sh --install  also copy it to /Applications
set -e
cd "$(dirname "$0")/.."

VERSION=$(git describe --tags --always 2>/dev/null || echo "0.1.0")
APP=dist/HomeDrive.app

echo "▸ Building release binary"
swift build -c release --product HomeDrive
BIN=$(swift build -c release --show-bin-path)/HomeDrive

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HomeDrive"

echo "▸ Drawing icon"
ICONSET=$(mktemp -d)/HomeDrive.iconset
swift scripts/make-icon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/HomeDrive.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HomeDrive</string>
  <key>CFBundleDisplayName</key><string>HomeDrive</string>
  <key>CFBundleIdentifier</key><string>io.github.daniel3886.homedrive</string>
  <key>CFBundleExecutable</key><string>HomeDrive</string>
  <key>CFBundleIconFile</key><string>HomeDrive</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>HomeDrive shows your Desktop so you can send files from it.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>HomeDrive shows your Documents so you can send files from it.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>HomeDrive saves retrieved files to your Downloads folder.</string>
</dict>
</plist>
PLIST

echo "▸ Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

if [ "$1" = "--install" ]; then
  echo "▸ Installing to /Applications"
  rm -rf /Applications/HomeDrive.app
  cp -R "$APP" /Applications/
  echo "✓ Installed /Applications/HomeDrive.app"
else
  echo "✓ Built $APP  (run with: open $APP)"
fi
