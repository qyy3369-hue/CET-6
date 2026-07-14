#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/Build/CET6DesktopWidget.app"
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
cp "$PROJECT_DIR/Support/AppIcon04.icns" "$RESOURCES_DIR/AppIcon04.icns"
cp "$PROJECT_DIR/Support/seal_texture.jpg" "$RESOURCES_DIR/seal_texture.jpg"
cp "$PROJECT_DIR/Support/bookmark_texture.jpg" "$RESOURCES_DIR/bookmark_texture.jpg"
chmod +x "$MACOS_DIR/CET6DesktopWidget"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
