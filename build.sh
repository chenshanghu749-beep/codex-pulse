#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Codex Pulse.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
WIDGET_DIR="$PLUGINS_DIR/CodexPulseWidget.appex"
WIDGET_CONTENTS_DIR="$WIDGET_DIR/Contents"
WIDGET_MACOS_DIR="$WIDGET_CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_SOURCE="$BUILD_DIR/AppIcon-1024.png"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR" "$ICONSET_DIR" "$WIDGET_MACOS_DIR"

swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  -framework WidgetKit \
  "$ROOT_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/CodexPulse"

swiftc \
  -O \
  -parse-as-library \
  -application-extension \
  -target arm64-apple-macos14.0 \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework SwiftUI \
  -framework WidgetKit \
  "$ROOT_DIR"/WidgetExtension/CodexPulseWidget.swift \
  -o "$WIDGET_MACOS_DIR/CodexPulseWidget"

cp "$ROOT_DIR/WidgetExtension/Info.plist" "$WIDGET_CONTENTS_DIR/Info.plist"
chmod +x "$WIDGET_MACOS_DIR/CodexPulseWidget"

swiftc \
  -O \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework AppKit \
  "$ROOT_DIR/Tools/IconGenerator.swift" \
  -o "$BUILD_DIR/IconGenerator"

"$BUILD_DIR/IconGenerator" "$ICON_SOURCE"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
swiftc \
  -O \
  -module-cache-path "$MODULE_CACHE_DIR" \
  "$ROOT_DIR/Tools/IconPackager.swift" \
  -o "$BUILD_DIR/IconPackager"
"$BUILD_DIR/IconPackager" "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/BasketballMascot.png" "$RESOURCES_DIR/BasketballMascot.png"
chmod +x "$MACOS_DIR/CodexPulse"
codesign --force --sign - --entitlements "$ROOT_DIR/WidgetExtension/CodexPulseWidget.entitlements" "$WIDGET_DIR"
codesign --force --sign - --entitlements "$ROOT_DIR/Resources/CodexPulse.entitlements" "$APP_DIR"

echo "$APP_DIR"
