#!/bin/bash
# macOS Code Signing Script for Data-X
# This script signs the app for distribution to other Macs

set -e

APP_PATH="src-tauri/target/release/bundle/macos/Data-X.app"
DMG_PATH="src-tauri/target/release/bundle/dmg"

echo "=== Data-X macOS Signing Script ==="

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    echo "Please run 'npm run tauri build' first."
    exit 1
fi

echo "1. Removing quarantine attributes..."
xattr -cr "$APP_PATH"

echo "2. Signing app with ad-hoc signature..."
codesign --force --deep --sign - "$APP_PATH"

echo "3. Verifying signature..."
codesign --verify --verbose "$APP_PATH"

# Sign DMG if exists
for dmg in "$DMG_PATH"/*.dmg; do
    if [ -f "$dmg" ]; then
        echo "4. Removing quarantine from DMG..."
        xattr -cr "$dmg"

        echo "5. Signing DMG..."
        codesign --force --sign - "$dmg"

        echo "DMG signed: $dmg"
    fi
done

echo ""
echo "=== Signing Complete ==="
echo ""
echo "IMPORTANT: For users who still get 'damaged' error:"
echo "  1. Right-click on Data-X.app and select 'Open'"
echo "  2. Or run: xattr -cr /path/to/Data-X.app"
echo ""
echo "For full Gatekeeper bypass (run once after download):"
echo "  sudo spctl --master-disable"
echo "  (then re-enable after install: sudo spctl --master-enable)"
