#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
swift build "${CITEKIT_FLAGS[@]}" -c release
BIN_DIR="$(swift build "${CITEKIT_FLAGS[@]}" -c release --show-bin-path)"
APP="$PWD/build/CiteKit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CiteKit" "$APP/Contents/MacOS/CiteKit"
cp -R "$BIN_DIR/CiteKit_CiteKitCore.bundle" "$APP/Contents/Resources/"
# SwiftPM also searches beside the executable for its resource bundle.
cp -R "$BIN_DIR/CiteKit_CiteKitCore.bundle" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CiteKit</string>
<key>CFBundleIdentifier</key><string>dev.citekit.mac</string>
<key>CFBundleName</key><string>CiteKit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
./scripts/bundle-zotero.sh
codesign --force --deep --sign - "$APP"
echo "Built $APP"
