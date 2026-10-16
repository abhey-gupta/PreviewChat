#!/bin/bash
# Builds PreviewChat.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
# CommandLineTools lacks SwiftUI macro plugins; prefer a full Xcode if present
if [ -z "${DEVELOPER_DIR:-}" ]; then
  for x in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    [ -d "$x" ] && export DEVELOPER_DIR="$x/Contents/Developer" && break
  done
fi
swift build -c release --build-system native
APP=build/PreviewChat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/PreviewChat "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp -R Resources/Fonts Resources/AppIcon.icns "$APP/Contents/Resources/"
# SwiftPM resource bundles (e.g. SwiftMath's math fonts); Bundle.module looks in Contents/Resources
cp -R .build/release/*.bundle "$APP/Contents/Resources/"
# Signing identity: $SIGN_ID, else Developer ID, else Apple Development, else ad-hoc.
# A real identity keeps macOS permissions (Accessibility, Automation) across updates.
if [ -z "${SIGN_ID:-}" ]; then
  ids=$(security find-identity -v -p codesigning)
  SIGN_ID=$(grep -o '"Developer ID Application: [^"]*"' <<<"$ids" | head -1 | tr -d '"' || true)
  [ -z "$SIGN_ID" ] && SIGN_ID=$(grep -o '"Apple Development: [^"]*"' <<<"$ids" | head -1 | tr -d '"' || true)
  [ -z "$SIGN_ID" ] && SIGN_ID=-
fi
# Hardened runtime + secure timestamp: required for notarization
ts=--timestamp; [ "$SIGN_ID" = - ] && ts=
codesign --force --options runtime $ts --entitlements PreviewChat.entitlements --sign "$SIGN_ID" "$APP"
echo "Signed with: $SIGN_ID"
echo "Built $APP"
