#!/usr/bin/env bash
#
# Builds Chroma Cascade and packages it as an unsigned .ipa.
#
# No Apple Developer account is needed: the app is compiled with code signing
# switched off and the resulting .app is wrapped in the Payload/ layout by hand,
# which is all an .ipa actually is. Install it with Sideloadly or AltStore,
# which re-sign it locally with a free Apple ID.
#
# Used by both .github/workflows/ios.yml and codemagic.yaml so CI and local
# builds cannot drift apart.
set -euo pipefail

SCHEME="${SCHEME:-ChromaCascade}"
PROJECT="${PROJECT:-ChromaCascade.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-build}"
IPA_NAME="${IPA_NAME:-ChromaCascade-unsigned.ipa}"

cd "$(dirname "$0")/.."

echo "==> Generating Xcode project from project.yml"
xcodegen generate

echo "==> Building $SCHEME ($CONFIGURATION, unsigned, device slice)"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="" \
  ENABLE_BITCODE=NO \
  clean build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: expected app bundle not found at $APP_PATH" >&2
  find "$BUILD_DIR/DerivedData/Build/Products" -maxdepth 3 -name "*.app" >&2 || true
  exit 1
fi

echo "==> Packaging $APP_PATH into $IPA_NAME"
rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && rm -f "$IPA_NAME" && zip -qry "$IPA_NAME" Payload)

echo "==> Done: $BUILD_DIR/$IPA_NAME ($(du -h "$BUILD_DIR/$IPA_NAME" | cut -f1))"
