#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/Build/Goals.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$PROJECT_DIR"
swift build

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
rm -f "$RESOURCES_DIR"/AppIcon*.icns 2>/dev/null || true
cp "$PROJECT_DIR/.build/debug/CET6DesktopWidget" "$MACOS_DIR/CET6DesktopWidget"
cp "$PROJECT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
ICON_FILE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$CONTENTS_DIR/Info.plist")
cp "$PROJECT_DIR/Support/$ICON_FILE" "$RESOURCES_DIR/$ICON_FILE"
chmod +x "$MACOS_DIR/CET6DesktopWidget"
xattr -cr "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
