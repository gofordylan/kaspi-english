#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64), ad-hoc-signed "Kaspi in English.app" plus .zip and .dmg in ./dist.
# Usage: scripts/build-app.sh [version]   (run on macOS 15+ with Xcode 16+)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-1.0.0}}"
VERSION="${VERSION#v}"
BUILD="${GITHUB_RUN_NUMBER:-1}"
APP_NAME="Kaspi in English"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building $APP_NAME $VERSION ($BUILD)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KaspiEnglish" "$APP/Contents/MacOS/KaspiEnglish"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
cp Resources/glossary.json "$APP/Contents/Resources/glossary.json"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Architectures"
lipo -info "$APP/Contents/MacOS/KaspiEnglish"

echo "==> Ad-hoc signing (no Developer ID)"
codesign --force --sign - --timestamp=none \
  --entitlements Resources/KaspiEnglish.entitlements \
  "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" || true

echo "==> Packaging"
ZIP="$DIST/Kaspi-in-English-$VERSION.zip"
DMG="$DIST/Kaspi-in-English-$VERSION.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
( cd "$DIST" && shasum -a 256 *.zip *.dmg > SHA256SUMS.txt && cat SHA256SUMS.txt )
echo "==> Done: $ZIP, $DMG"
