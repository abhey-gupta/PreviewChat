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
swift build -c release
APP=build/PreviewChat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/PreviewChat "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"
