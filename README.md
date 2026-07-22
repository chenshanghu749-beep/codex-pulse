# CodeAPI Status

CodeAPI Status 是一款原生 macOS 菜单栏应用，用于切换 OpenAI 官方路由与 CodeAPI、查看账户用量，并通过红黄绿状态灯显示 Codex 当前执行阶段。

## 功能

- 一键切换 OpenAI 官方路由与 CodeAPI，切换后自动重新打开 ChatGPT
- CodeAPI 路由显示余额、费用、Token 用量和模型统计
- OpenAI 官方路由显示用量剩余和重置时间
- 每分钟刷新用量，每 0.5 秒检测 Codex 任务状态
- 横向三色状态灯，每次只点亮一个灯：
  - 红灯：LLM 正在推理或生成内容
  - 黄灯：正在执行本地命令、调用工具或等待结果
  - 绿灯：整轮任务结束，输入框可以发送下一条消息
- 启动、切换路由以及任务完成转绿前播放跑马灯

## 系统要求

- Apple Silicon Mac
- macOS 13 或更高版本
- 已安装 ChatGPT macOS 应用

## 一行命令安装

仓库位于私有 GitLab 群组，因此需要一个仅具备 `read_repository` 权限的 GitLab Token。Token 只保存在当前终端环境中，不要写入脚本或提交到仓库。

在终端执行：

```bash
export GITLAB_TOKEN='你的只读 GitLab Token'
curl -fsSL --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  https://code.bitsland.io/inno/eryaya/skills/codeapi-status/-/raw/main/install.sh | zsh
unset GITLAB_TOKEN
```

安装脚本会校验 DMG 的 SHA-256，将应用安装到 `~/Applications/CodeAPI Status.app`，然后启动应用。脚本不会读取、收集或上传 API Key。

如需安装到其他目录，可设置 `CODEAPI_STATUS_INSTALL_DIR` 后再运行脚本。

## 手动安装

1. 下载 [`dist/CodeAPI-Status-1.5.0.dmg`](dist/CodeAPI-Status-1.5.0.dmg)。
2. 打开 DMG。
3. 将 `CodeAPI Status.app` 拖入“应用程序”目录。
4. 首次运行 `CodeAPI Status`。

如果 macOS 阻止首次打开，请在 Finder 中右键应用并选择“打开”。

## 从源码构建

```bash
git clone https://code.bitsland.io/inno/eryaya/skills/codeapi-status.git
cd codeapi-status
chmod +x build.sh install.sh
./build.sh
```

构建产物位于：

```text
build/CodeAPI Status.app
```

项目不依赖 Homebrew、SwiftBar 或 jq。

## 使用方式

1. 启动应用后，在设置窗口选择 `OpenAI 官方` 或 `CodeAPI`。
2. 使用 CodeAPI 时输入 API Key；官方路由无需配置 CodeAPI Key。
3. 点击“确认并打开 ChatGPT”。应用会备份并更新 `~/.codex/config.toml`，然后重新打开 ChatGPT。
4. 菜单栏的用量入口显示余额或官方用量；点击后可查看明细、刷新用量或切换路由。
5. 菜单栏的红黄绿灯显示 Codex 当前任务阶段；点击灯箱可查看状态说明。

## API Key 与隐私

- API Key 只保存在本机 `~/.codex/codeapi-status/codeapi.key`。
- 凭据目录权限为 `700`，Key 文件权限为 `600`。
- 应用不使用 macOS 钥匙串，因此不会触发钥匙串密码弹窗。
- API Key、用户 Codex 配置、备份文件和本地环境文件均被 `.gitignore` 排除。
- 请勿把真实 Key 写入源码、Issue、日志或提交记录。

## 卸载

退出 CodeAPI Status 后，将 `CodeAPI Status.app` 移到废纸篓即可。若不再使用 CodeAPI，可自行删除 `~/.codex/codeapi-status/`；原 Codex 配置备份位于 `~/.codex/config.toml.codeapi-status.bak`。

## 开发测试

```bash
./build/CodeAPI\ Status.app/Contents/MacOS/CodeAPIStatus --self-test
./build/CodeAPI\ Status.app/Contents/MacOS/CodeAPIStatus --task-state-test
```

当前版本：`1.5.0`
