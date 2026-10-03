#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${2:-public}" = public ] || { echo "This sanitized tree builds Public only" >&2; exit 2; }
export AKITO_EDITION=public
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/akito-rc-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/akito-rc-swift-cache"
BUILD_DIR="${AKITO_STATION_BUILD_DIR:-/tmp/akito-public-rc-build}"
CONFIG="${1:-release}"
swift build --disable-sandbox --build-system native --scratch-path "$BUILD_DIR" -c "$CONFIG" -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/AkitoStation" -Xcc "-ffile-prefix-map=$PWD=/AkitoStation"
APP="$PWD/Build/Akito Station.app"
mkdir -p "$PWD/Build"
# A new staging bundle prevents stale resources from entering a rebuild.
STAGE=$(mktemp -d "$BUILD_DIR/public-bundle.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/Akito Station.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/Tools"
cp "$BUILD_DIR/$CONFIG/AkitoStation" "$BUNDLE/Contents/MacOS/AkitoStation"
strip -S "$BUNDLE/Contents/MacOS/AkitoStation"
cp Scripts/import-emulator-settings.py Scripts/manage-runtime.py Scripts/import-managed.py Scripts/import-core.py Scripts/install-release.py Scripts/install-console-package.py "$BUNDLE/Contents/Resources/Tools/"
cp Resources/AppIcon.icns Resources/upstreams.lock.json "$BUNDLE/Contents/Resources/"
cp Documentation/THIRD_PARTY_NOTICES.md Documentation/LICENSE_REPORT.md "$BUNDLE/Contents/Resources/"
cp -R Documentation/Licenses "$BUNDLE/Contents/Resources/"
cp Resources/Public-Info.plist "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.akitostation.public' "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Akito Station' "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Akito Station' "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 akito' "$BUNDLE/Contents/Info.plist"
Scripts/embed-player.sh "$BUNDLE"
xattr -cr "$BUNDLE"
SIGN_TIMESTAMP=""
if [[ "${AKITO_SIGN_IDENTITY:--}" != "-" ]]; then SIGN_TIMESTAMP=--timestamp; fi
codesign --force --options runtime ${SIGN_TIMESTAMP:+--timestamp} --entitlements Resources/Public.entitlements --sign "${AKITO_SIGN_IDENTITY:--}" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
# Replace the sole canonical output; temporary rollback stays inside staging.
if [ -e "$APP" ]; then mv "$APP" "$STAGE/previous.app"; fi
if ! mv "$BUNDLE" "$APP"; then
  if [ -e "$STAGE/previous.app" ]; then mv "$STAGE/previous.app" "$APP"; fi
  exit 1
fi
echo "$APP"
