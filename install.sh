#!/bin/zsh
set -euo pipefail

readonly APP_NAME="CodeAPI Status.app"
readonly VERSION="1.5.0"
readonly DMG_NAME="CodeAPI-Status-${VERSION}.dmg"
readonly DMG_URL="https://code.bitsland.io/inno/eryaya/skills/codeapi-status/-/raw/main/dist/${DMG_NAME}"
readonly EXPECTED_SHA256="ef826c652cc3d4c3e959232525e7d10e8854a1cda28dfc26dd07e11febef2099"

if [[ -z "${GITLAB_TOKEN:-}" ]]; then
    echo "缺少 GITLAB_TOKEN。请使用具有 read_repository 权限的 GitLab Token。" >&2
    exit 1
fi

install_dir="${CODEAPI_STATUS_INSTALL_DIR:-$HOME/Applications}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/codeapi-status-install.XXXXXX")"
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
echo "正在下载 CodeAPI Status ${VERSION}…"
/usr/bin/curl -fsSL --retry 3 --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$DMG_URL" -o "$dmg_path"

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
echo "正在启动 CodeAPI Status…"
/usr/bin/open "$target_app"
