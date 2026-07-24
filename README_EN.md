# Codex Pulse

<p align="center">
  <img src="docs/assets/codex-pulse.png" alt="Codex Pulse icon" width="160">
</p>

<p align="center">
  <a href="README.md">中文</a> | English
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/badge/release-2.4.4-111111">
  <img alt="Stars" src="https://img.shields.io/github/stars/chenshanghu749-beep/codex-pulse">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5-F05138">
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-native-111111">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-111111">
</p>

Codex Pulse is a native macOS menu bar routing and status tool for the OpenAI Codex desktop app. It provides official and third-party model provider switching, protocol conversion, usage monitoring, task status, and session continuity without modifying the Codex app itself.

<p align="center">
  <img src="docs/assets/menu-bar-preview.png" alt="Codex Pulse menu bar preview" width="100%">
</p>

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/chenshanghu749-beep/codex-pulse/main/install.sh | zsh
```

Codex Pulse launches automatically after installation. The default location is `~/Applications/Codex Pulse.app`.

## Core Features

| Feature | Description |
| --- | --- |
| Route switching | Quickly switch between the official OpenAI route and multiple custom providers |
| Usage display | View balance, quota, reset time, and token activity from the menu bar |
| Task status | Red indicates model execution, yellow indicates tools or commands, and green indicates completion |
| Session continuity | Synchronize local session metadata when switching routes to keep project conversations available |

Codex Pulse supports the Responses API and can locally convert Chat Completions providers such as DeepSeek to the protocol required by Codex. The built-in connection test validates the Base URL, API key, model, and protocol before a provider is enabled.

## Usage

1. Open Codex Pulse and select `OpenAI Official` or a configured third-party provider.
2. For a third-party provider, enter its name, Base URL, model ID, API key, and protocol, then click `Test Connection`.
3. Click `Apply and Open Codex` to switch the route and restart Codex.

The menu bar icon continuously reflects the current task status. A three-color transition animation runs at launch, during route changes, and immediately before a task returns to the completed state.

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- Codex for macOS installed

## Manual Installation

Download [`Codex-Pulse-2.4.4.dmg`](dist/Codex-Pulse-2.4.4.dmg), open it, and drag `Codex Pulse.app` into `Applications`.

If macOS blocks the first launch, right-click the app in Finder and select `Open`.

## Build from Source

```bash
git clone https://github.com/chenshanghu749-beep/codex-pulse.git
cd codex-pulse
chmod +x build.sh package.sh
./build.sh
./package.sh
```

The app is generated at `build/Codex Pulse.app`, and the installer is generated at `dist/Codex-Pulse-2.4.4.dmg`.

## Privacy and Security

- API keys are stored locally and are never written to the provider list or uploaded to the repository.
- Credential files use `600` permissions and the credential directory uses `700` permissions.
- Relevant local configuration and session metadata are backed up before route changes.
- Official authentication is backed up before entering a third-party route, then restored when switching back while third-party API keys remain isolated.
- Codex Pulse does not use macOS Keychain and does not repeatedly trigger Keychain authorization prompts.

## Uninstall

Quit Codex Pulse and move `Codex Pulse.app` to Trash. To remove all configuration, delete `~/.codex/codeapi-status/`.

## Support the Project

If Codex Pulse is useful to you, you can support its ongoing maintenance through WeChat.

<p align="center">
  <img src="docs/assets/wechat-pay.jpg" alt="WeChat payment QR code" width="320">
</p>

Current version: `2.4.4`
