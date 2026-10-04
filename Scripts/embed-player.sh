#!/bin/bash
set -euo pipefail
APP="$1"
HELPER="$APP/Contents/Helpers/Akito Station Player.app"
mkdir -p "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"
cp "$APP"/Contents/Resources/logo_*.png "$HELPER/Contents/Resources/"
cp "$APP/Contents/Resources/AppIcon.icns" "$HELPER/Contents/Resources/"
cp "$APP/Contents/MacOS/AkitoStation" "$HELPER/Contents/MacOS/AkitoStation"
cat > "$HELPER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.akitostation.player</string><key>CFBundleName</key><string>Akito Station Player</string><key>CFBundleDisplayName</key><string>Akito Station Player</string><key>CFBundleExecutable</key><string>AkitoStation</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/><key>CFBundleIconFile</key><string>AppIcon</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
PLIST
PARENT_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PARENT_ID.player" "$HELPER/Contents/Info.plist"
EDITION=Public
SIGN_TIMESTAMP=""
if [[ "${AKITO_SIGN_IDENTITY:--}" != "-" ]]; then SIGN_TIMESTAMP=--timestamp; fi
codesign --force --options runtime ${SIGN_TIMESTAMP:+--timestamp} --entitlements "$(dirname "$0")/../Resources/$EDITION.entitlements" --sign "${AKITO_SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY:--}}" "$HELPER"
