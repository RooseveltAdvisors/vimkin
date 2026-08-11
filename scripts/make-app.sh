#!/bin/bash
# Build Vimkin.app bundle from the SwiftPM release build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.0.0}"
BUILD_DIR="$REPO_ROOT/.build/release"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/dist}"
APP="$OUT_DIR/Vimkin.app"

swift build -c release --package-path "$REPO_ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/Vimkin" "$APP/Contents/MacOS/Vimkin"
# SPM resource bundle (Content/) ships beside the binary
if [ -d "$BUILD_DIR/Vimkin_Vimkin.bundle" ]; then
  cp -R "$BUILD_DIR/Vimkin_Vimkin.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Vimkin</string>
    <key>CFBundleIdentifier</key><string>com.roosevelt.vimkin</string>
    <key>CFBundleName</key><string>Vimkin</string>
    <key>CFBundleDisplayName</key><string>Vimkin</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Ad-hoc sign so the bundle runs locally without a dev cert
codesign --force --deep -s - "$APP"

echo "Built $APP (version $VERSION)"
