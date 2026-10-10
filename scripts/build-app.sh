#!/bin/bash
# Builds build/Vamp.app from the Swift package. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Vamp.app"
VERSION="$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.1.0)"

cd "$ROOT"
swift build -c "$CONFIG" --product Vamp
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Vamp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Vamp"
cp -R Resources/engine "$APP/Contents/Resources/engine"

# App icon: every size iconutil expects, cut from the 1024 px master.
ICONSET="$(mktemp -d)/Vamp.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/icon/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/icon/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Vamp.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Vamp</string>
  <key>CFBundleDisplayName</key><string>Vamp</string>
  <key>CFBundleIdentifier</key><string>com.vamp.app</string>
  <key>CFBundleExecutable</key><string>Vamp</string>
  <key>CFBundleIconFile</key><string>Vamp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
</dict>
</plist>
PLIST

# Ad-hoc signature, so macOS runs it locally. Not notarised.
codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
