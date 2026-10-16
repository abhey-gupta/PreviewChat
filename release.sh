#!/bin/bash
# Builds a signed, versioned DMG into ./dist and (optionally) notarizes it.
# Usage: ./release.sh            → dist/PreviewChat-<version>.dmg
#        NOTARY_PROFILE=name ./release.sh   → also notarize + staple (needs Developer ID)
#   one-time: xcrun notarytool store-credentials <name> --apple-id … --team-id …
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
NAME=PreviewChat-$VERSION
DMG=dist/$NAME.dmg

# Release from a clean, committed tree so the DMG matches the tag
if [ -n "$(git status --porcelain)" ] && [ -z "${ALLOW_DIRTY:-}" ]; then
  echo "Working tree dirty; commit first (or ALLOW_DIRTY=1)." >&2; exit 1
fi

rm -rf .build/release build dist
./build.sh
SIGN_ID=$(codesign -dvv build/PreviewChat.app 2>&1 | sed -n 's/^Authority=//p' | head -1)
[ -z "$SIGN_ID" ] && SIGN_ID=-

# DMG: app + /Applications shortcut for drag-to-install
stage=$(mktemp -d)
cp -R build/PreviewChat.app "$stage/"
ln -s /Applications "$stage/Applications"
mkdir -p dist
hdiutil create -volname "PreviewChat $VERSION" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$stage"
codesign --force --sign "$SIGN_ID" "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
else
  echo "⚠︎ Not notarized: Gatekeeper will block first launch on other Macs / after download."
fi

(cd dist && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256")
echo "Built $DMG"; cat "$DMG.sha256"
