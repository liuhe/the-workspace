#!/bin/bash
# Package the release-built binary into a minimal tasker.app bundle.
# Usage: bash scripts/make-app-bundle.sh <version> [binary-path]
#
# If binary-path is omitted, defaults to app/tasker/.build/universal/tasker.
# Requires scripts/make-icon.sh to have produced app/tasker/AppIcon.icns
# (icon is optional but recommended).
set -euo pipefail

VERSION="${1:-0.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$ROOT/app/tasker"

BIN="${2:-$APP_ROOT/.build/universal/tasker}"
if [ ! -x "$BIN" ]; then
    echo "Binary not found at $BIN" >&2
    exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/tasker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/tasker"
if [ -f "$APP_ROOT/AppIcon.icns" ]; then
    cp "$APP_ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>tasker</string>
    <key>CFBundleDisplayName</key><string>tasker</string>
    <key>CFBundleIdentifier</key><string>com.liuhe.tasker</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>tasker</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

echo "Built $APP"
lipo -info "$APP/Contents/MacOS/tasker"
