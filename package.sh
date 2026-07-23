#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Codex Pulse.app"
STAGING_DIR="$BUILD_DIR/dmg-staging"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
FINAL_DMG="$ROOT_DIR/dist/Codex-Pulse-${VERSION}.dmg"

if [[ ! -d "$APP_DIR" ]]; then
  echo "未找到构建产物，请先运行 ./build.sh。" >&2
  exit 1
fi

/bin/rm -rf "$STAGING_DIR"
/bin/mkdir -p "$STAGING_DIR" "$ROOT_DIR/dist"
/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/Codex Pulse.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/ditto "$ROOT_DIR/Resources/请把 Codex Pulse 拖到 Applications.txt" "$STAGING_DIR/请把 Codex Pulse 拖到 Applications.txt"

/usr/bin/hdiutil create \
  -volname "Codex Pulse" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$FINAL_DMG" >/dev/null

echo "$FINAL_DMG"
/usr/bin/shasum -a 256 "$FINAL_DMG"
