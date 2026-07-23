# Codex Pulse

<img width="684" height="60" alt="image" src="https://github.com/user-attachments/assets/41266f0f-89f3-4a37-91da-4133f2eb09a9" />

一款为 Codex 设计的原生 macOS 菜单栏工具。快速切换 OpenAI 官方路由与第三方模型提供商，同时查看用量和任务状态。

## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/chenshanghu749-beep/codex-pulse/main/install.sh | zsh
```

安装完成后会自动启动 `Codex Pulse`。默认安装位置为 `~/Applications/Codex Pulse.app`。

## 核心功能

| 功能 | 说明 |
| --- | --- |
| 路由切换 | 在 OpenAI 官方路由和多个自定义提供商之间快速切换 |
| 用量展示 | 在菜单栏查看余额、配额、重置时间及 Token 活动 |
| 任务状态 | 红灯表示模型执行，黄灯表示工具或命令运行，绿灯表示任务完成 |
| 会话保持 | 切换路由时同步本地会话标记，尽量保持同一项目的会话列表一致 |

支持 Responses API，并可在本机将 DeepSeek 等 Chat Completions 接口转换为 Codex 所需协议。提供商配置支持连接测试，可在启用前校验 Base URL、API Key、模型与协议。

## 使用方式

1. 打开 Codex Pulse，选择 `OpenAI 官方` 或已配置的第三方提供商。
2. 第三方提供商填写名称、Base URL、模型 ID、API Key 和协议，然后点击“测试连接”。
3. 点击“应用并打开 Codex”，应用会切换路由并重新启动 Codex。

菜单栏图标会持续显示当前任务状态。启动、切换路由以及任务完成前会播放一次三色过渡动画。

## 系统要求

- Apple Silicon Mac
- macOS 13 或更高版本
- 已安装 Codex macOS 应用

## 手动安装

下载 [`Codex-Pulse-2.4.2.dmg`](dist/Codex-Pulse-2.4.2.dmg)，打开后将 `Codex Pulse.app` 拖入 `Applications`。

若 macOS 首次运行时阻止打开，请在 Finder 中右键应用并选择“打开”。

## 从源码构建

```bash
git clone https://github.com/chenshanghu749-beep/codex-pulse.git
cd codex-pulse
chmod +x build.sh package.sh
./build.sh
./package.sh
```

构建产物位于 `build/Codex Pulse.app`，安装包位于 `dist/Codex-Pulse-2.4.2.dmg`。

## 隐私与安全

- API Key 仅保存在本机，不会写入提供商列表或上传到仓库。
- 凭据文件权限为 `600`，凭据目录权限为 `700`。
- 路由切换前会备份相关本地配置和会话标记。
- 应用不使用 macOS 钥匙串，不会反复触发钥匙串授权弹窗。

## 卸载

退出 Codex Pulse，将 `Codex Pulse.app` 移到废纸篓即可。需要彻底清理配置时，可删除 `~/.codex/codeapi-status/`。

当前版本：`2.4.2`
