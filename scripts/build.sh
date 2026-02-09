#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────
# Noodles — Build, Sign, Notarize, Package
# ─────────────────────────────────────────────
# One-time setup (run this manually first):
#   xcrun notarytool store-credentials "noodles-notary" \
#     --apple-id YOUR_APPLE_ID \
#     --team-id 26GV92ZQ4L \
#     --password YOUR_APP_SPECIFIC_PASSWORD
#
# Generate an app-specific password at:
#   https://appleid.apple.com → Sign-In and Security → App-Specific Passwords
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_DIR="$PROJECT_ROOT/app"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Noodles.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Noodles.app"
DMG_PATH="$BUILD_DIR/Noodles.dmg"
KEYCHAIN_PROFILE="noodles-notary"

# Clean previous build
echo "🧹 Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Archive
echo "🔨 Archiving..."
xcodebuild -project "$APP_DIR/Noodles.xcodeproj" \
  -scheme Noodles \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -quiet \
  archive

echo "✅ Archive complete"

# Export with Developer ID signing
echo "🔏 Exporting with Developer ID..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$APP_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_PATH" \
  -quiet

echo "✅ Export complete"

# Notarize
echo "📦 Submitting for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/Noodles.zip"

xcrun notarytool submit "$BUILD_DIR/Noodles.zip" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "✅ Notarization complete"

# Staple
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "✅ Stapled"

# Create DMG
echo "💿 Creating DMG..."
rm -f "$DMG_PATH"

# Create a temporary folder with app + Applications symlink for drag-to-install
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "Noodles" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_STAGING"

# Notarize the DMG too
echo "📦 Notarizing DMG..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

xcrun stapler staple "$DMG_PATH"

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ Build complete!"
echo "  DMG: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "═══════════════════════════════════════════"
