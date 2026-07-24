#!/bin/zsh
set -euo pipefail

readonly APP_NAME="Codex Pulse.app"
readonly VERSION="2.4.5"
readonly DMG_NAME="Codex-Pulse-${VERSION}.dmg"
readonly DMG_URL="https://raw.githubusercontent.com/chenshanghu749-beep/codex-pulse/main/dist/${DMG_NAME}"
readonly EXPECTED_SHA256="3c2d5e8ad9feb2f2f68213362cf2ad084dac4e3c4fdfe899ccc935d91f0b1e1c"

install_dir="${CODEX_PULSE_INSTALL_DIR:-${CODEAPI_STATUS_INSTALL_DIR:-$HOME/Applications}}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-install.XXXXXX")"
dmg_path="$work_dir/$DMG_NAME"
mount_dir="$work_dir/mount"
mounted=false

cleanup() {
    if [[ "$mounted" == true ]]; then
        /usr/bin/hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    fi
    /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

/bin/mkdir -p "$mount_dir"
echo "正在下载 Codex Pulse ${VERSION}…"
/usr/bin/curl -fsSL --retry 3 "$DMG_URL" -o "$dmg_path"

actual_sha256="$(/usr/bin/shasum -a 256 "$dmg_path" | /usr/bin/awk '{print $1}')"
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
    echo "安装包校验失败，已停止安装。" >&2
    exit 1
fi

/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$dmg_path" >/dev/null
mounted=true

source_app="$mount_dir/$APP_NAME"
target_app="$install_dir/$APP_NAME"
if [[ ! -d "$source_app" ]]; then
    echo "安装包中未找到 $APP_NAME。" >&2
    exit 1
fi

/bin/mkdir -p "$install_dir"
/usr/bin/ditto "$source_app" "$target_app"
/usr/bin/hdiutil detach "$mount_dir" >/dev/null
mounted=false

echo "已安装到：$target_app"
echo "正在启动 Codex Pulse…"
/usr/bin/open "$target_app"
