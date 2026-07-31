#!/bin/bash
# Builds Overtone and packages it as a drag-to-Applications DMG.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION=$(awk '/MARKETING_VERSION/ {gsub(/"/, "", $2); print $2}' project.yml)
APP=.build/Build/Products/Release/Overtone.app
DMG="dist/Overtone-$VERSION.dmg"

if [ ! -d Runtime/onnx ]; then
    echo "Runtime/ is missing — see 'Build from source' in the README." >&2
    exit 1
fi

xcodegen generate
xcodebuild -project Overtone.xcodeproj -scheme Overtone -configuration Release \
    -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "Overtone $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "$DMG"
du -h "$DMG" | cut -f1
