# Codex Pulse

Codex Pulse 是一款 Codex 风格的原生 macOS 菜单栏应用：切换 OpenAI 官方路由和多个自定义模型提供商，查看余额、配额与 Token 活动，并用动态图标显示 Codex 当前任务阶段。

## 主要功能

- OpenAI 官方路由与多个第三方提供商一键切换
- 支持 Responses API，以及 DeepSeek 等 Chat Completions 提供商的本地协议转换
- 提供商编辑页可发送一次最小测试请求，直接校验地址、API Key、模型与协议是否可用
- 官方登录状态以 Codex CLI 的真实账号状态为准，避免 app-server 临时返回空账号造成误报
- CodeAPI 显示余额、费用、请求数以及输入/输出 Token；官方账号显示配额剩余、重置时间和 Token 活动摘要
- 单一紧凑菜单栏入口，减少菜单栏空间不足时被系统隐藏的概率
- 状态颜色平滑过渡：红色表示模型执行，黄色表示工具、命令或等待，绿色表示整轮任务结束、输入框可继续发送
- 启动、切换路由和任务完成前播放三色跑马灯
- 四种状态图标：经典红绿灯、灵感灯泡、礼帽伙伴、状态圆环
- 礼帽伙伴在红色状态运球、黄色状态舞动，任务完成后显示绿色完成姿态
- 原生 macOS WidgetKit 桌面组件，提供小号与中号布局，展示当前路由、余额/配额、Token 和任务状态
- 切换路由时安全同步 Codex 的本地会话提供商标记，使同一项目的会话在官方与第三方路由下保持一致
- 同步前自动备份会话数据库和原提供商标记；不会复制、归档或删除会话
- Codex 风格设置界面：浅色模式使用纯白内容区与侧边栏，深色模式保持紧凑的黑白视觉
- 支持跟随系统、浅色和深色三种主题
- 文案支持选择复制，输入框支持标准的剪切、复制、粘贴与全选快捷键
- 每个第三方提供商使用独立 Codex Provider ID，并兼容旧版 CodeAPI 会话

## 系统要求

- Apple Silicon Mac
- macOS 13 或更高版本（桌面小组件需要 macOS 14 或更高版本）
- 已安装 Codex macOS 应用

## 一行命令安装

```bash
curl -fsSL https://raw.githubusercontent.com/chenshanghu749-beep/codex-pulse/main/install.sh | zsh
```

安装脚本会下载并校验 DMG 的 SHA-256，将应用安装到 `~/Applications/Codex Pulse.app` 后启动。可通过 `CODEX_PULSE_INSTALL_DIR` 修改安装目录。

## 手动安装

1. 下载 [`dist/Codex-Pulse-2.4.1.dmg`](dist/Codex-Pulse-2.4.1.dmg)。
2. 打开 DMG，按照窗口提示把 `Codex Pulse.app` 拖到右侧的 `Applications`。
3. 首次运行 `Codex Pulse`。若 macOS 阻止打开，请在 Finder 中右键应用并选择“打开”。

## 使用方式

1. 打开 Codex Pulse，选择 `OpenAI 官方` 或 `第三方提供商`。
2. 第三方路由可新增、编辑和删除提供商，并分别填写名称、Base URL、模型 ID、API Key 与 API 协议；DeepSeek 可保持“自动识别”。
3. 保存前可点击“测试连接”，应用会发送一次极小的真实请求并显示协议与耗时。
4. 点击“应用并打开 Codex”。应用会先关闭 Codex、同步会话提供商标记，再以新路由启动；同一项目的会话列表保持一致。
5. 左键菜单栏入口查看用量与刷新状态；右键选择“添加 macOS 桌面组件…”。
6. 在桌面空白处点按右键，选择“编辑小组件”，搜索 `Codex Pulse`，把小号或中号组件拖到桌面。

OpenAI 官方账号的配额和 Token 摘要只有在 Codex 已登录时可用。未登录不会阻止写入官方路由配置。

Chat Completions 路由由 Codex Pulse 在本机 `127.0.0.1` 上转换为 Codex 所需的 Responses 协议，因此使用这类路由时请保持 Codex Pulse 运行。

> 桌面小组件扩展需要 Apple Development 或 Developer ID 签名。临时签名的本地构建可运行主应用，但 macOS 可能不会加载它的小组件描述。

## 从源码构建

```bash
git clone https://github.com/chenshanghu749-beep/codex-pulse.git
cd codex-pulse
chmod +x build.sh package.sh install.sh
./build.sh
./package.sh
```

应用产物：`build/Codex Pulse.app`；拖拽式安装包：`dist/Codex-Pulse-2.4.1.dmg`。项目不依赖 Homebrew、SwiftBar 或 jq。

## API Key 与隐私

- CodeAPI Key 保存在 `~/.codex/codeapi-status/codeapi.key`，其他提供商 Key 保存在 `~/.codex/codeapi-status/keys/`。
- 提供商列表保存在 `~/.codex/codeapi-status/providers.json`，不包含 API Key。
- 凭据目录权限为 `700`，Key 文件权限为 `600`。
- 会话路由同步备份保存在 `~/.codex/codeapi-status/session-route-backups/`，自动保留最近 10 份。
- 应用不使用 macOS 钥匙串，因此不会触发钥匙串密码弹窗。
- API Key、Codex 配置、备份和本地环境文件均被 `.gitignore` 排除。

## 卸载

退出 Codex Pulse 后，将 `Codex Pulse.app` 移到废纸篓。若不再使用相关配置，可自行删除 `~/.codex/codeapi-status/`；原 Codex 配置备份位于 `~/.codex/config.toml.codeapi-status.bak`。

## 开发测试

```bash
./build/Codex\ Pulse.app/Contents/MacOS/CodexPulse --self-test
./build/Codex\ Pulse.app/Contents/MacOS/CodexPulse --task-state-test
./build/Codex\ Pulse.app/Contents/MacOS/CodexPulse --official-usage-test
./build/Codex\ Pulse.app/Contents/MacOS/CodexPulse --session-history-test
```

当前版本：`2.4.1`
