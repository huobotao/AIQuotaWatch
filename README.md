
# AI 额度观察 / AI Quota Watch

[中文](#中文) | [English](#english)

## 中文

一个原生 macOS 额度观察工具，用来同时查看：

- GPT Codex
- Claude Code 账号 1
- Claude Code 账号 2
- 每个 Claude 账号对应的 Fable 独立额度钱包

菜单栏固定显示三条小进度线：Codex、Claude 1、Claude 2。彩色长度表示额度已使用比例，细竖线表示当前额度窗口的时间进度。点开菜单栏后可查看三个账号的详细行；主窗口还包含重置倒计时、5 小时和 7 天窗口、消耗速度比较，以及 token 随时间变化图。

> **数据原则：**额度只来自 Codex 的结构化 `rate_limits` 数据或 Anthropic 官方 OAuth usage 接口。本项目不会根据本地 token 数量估算余额。

### 项目结构

```text
work/AIQuotaWatch/   macOS 主窗口、官方数据读取、本地 HTTP/Web 客户端
work/AIQuotaMenu/    macOS 菜单栏常驻程序
work/AIQuotaPhone/   原生 iPhone 客户端工程
scripts/             macOS 构建、安装和卸载脚本
packaging/           LaunchAgent 模板
```

### macOS 构建

要求：macOS 14 或更高版本、Apple Silicon、Swift 6/Xcode Command Line Tools。

```bash
bash scripts/build-macos.sh
```

构建结果位于 `dist/`：

```text
dist/AI 额度观察.app
dist/AI 额度菜单.app
```

### macOS 安装

```bash
bash scripts/install-macos.sh
```

安装脚本会：

1. 构建并签署两个本地 App
2. 安装到 `~/Applications`
3. 安装两个用户级 LaunchAgent
4. 启动主程序和菜单栏程序
5. 验证二者处于运行状态

卸载程序但保留额度历史和登录缓存：

```bash
bash scripts/uninstall-macos.sh
```

### iPhone 客户端

用 Xcode 打开：

```text
work/AIQuotaPhone/AIQuotaPhone.xcodeproj
```

iPhone 客户端连接 Mac 主程序提供的局域网接口。首次使用时，需要把客户端中的 Mac 地址改为该 Mac 当前的局域网地址。

### 隐私与安全

- 仓库不包含任何 Codex 或 Claude 账号令牌。
- 安装包也不应包含 `~/Library/Application Support/AIQuotaWatch`。
- Claude OAuth 凭据只在本机运行时读取，并缓存在本机 Application Support 中。
- Web/iPhone 接口默认服务于局域网使用场景，请勿直接暴露到公网。
- 公开 fork 或提交前请阅读 [SECURITY.md](SECURITY.md)。

### 制作信息

由 Codex（GPT-5）为 Richard 制作，2026。

本仓库公开用于源码审阅。当前未附加开源许可证，默认保留全部权利。

## English

AI Quota Watch is a native macOS utility for monitoring:

- GPT Codex
- Claude Code account 1
- Claude Code account 2
- The separate Fable quota wallet associated with each Claude account

The menu bar displays three compact progress lines for Codex, Claude 1, and Claude 2. The colored length represents quota consumed, while the thin vertical marker represents elapsed time in the current quota window. Opening the menu reveals detailed rows for all three accounts. The main window also provides reset countdowns, 5-hour and 7-day windows, burn-rate comparisons, and token-usage history over time.

> **Data integrity:** Quota values come only from Codex structured `rate_limits` data or Anthropic's official OAuth usage endpoint. This project never estimates remaining quota from locally counted tokens.

### Project structure

```text
work/AIQuotaWatch/   macOS dashboard, official data readers, and local HTTP/Web client
work/AIQuotaMenu/    Persistent macOS menu-bar app
work/AIQuotaPhone/   Native iPhone client project
scripts/             macOS build, install, and uninstall scripts
packaging/           LaunchAgent templates
```

### Build for macOS

Requirements: macOS 14 or later, Apple Silicon, and Swift 6/Xcode Command Line Tools.

```bash
bash scripts/build-macos.sh
```

Build artifacts are written to `dist/`:

```text
dist/AI 额度观察.app
dist/AI 额度菜单.app
```

### Install on macOS

```bash
bash scripts/install-macos.sh
```

The installer:

1. Builds and signs both local apps
2. Installs them in `~/Applications`
3. Installs two per-user LaunchAgents
4. Starts the dashboard and menu-bar app
5. Verifies that both processes are running

To uninstall the apps while preserving quota history and login caches:

```bash
bash scripts/uninstall-macos.sh
```

### iPhone client

Open the following project in Xcode:

```text
work/AIQuotaPhone/AIQuotaPhone.xcodeproj
```

The iPhone client connects to the local-network endpoint provided by the Mac app. Before first use, update the Mac address in the client to the Mac's current LAN address.

### Privacy and security

- The repository contains no Codex or Claude account tokens.
- Release packages must not include `~/Library/Application Support/AIQuotaWatch`.
- Claude OAuth credentials are read only at runtime on the local Mac and cached in local Application Support.
- The Web/iPhone endpoint is intended for LAN use and should not be exposed directly to the public Internet.
- Read [SECURITY.md](SECURITY.md) before publishing a fork or commit.

### Credits

Built for Richard by Codex (GPT-5), 2026.

This repository is public for source review. No open-source license is currently provided; all rights are reserved by default.
