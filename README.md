# AI 额度观察

一个原生 macOS 额度观察工具，用来同时查看：

- GPT Codex
- Claude Code 账号 1
- Claude Code 账号 2
- 每个 Claude 账号对应的 Fable 独立额度钱包

菜单栏固定显示三条小进度线：Codex、Claude 1、Claude 2。彩色长度表示额度已使用比例，细竖线表示当前额度窗口的时间进度。点开菜单栏后可查看三个账号的详细行；主窗口还包含重置倒计时、5 小时/7 天窗口、消耗速度比较和 token 随时间变化图。

> 数据原则：额度只来自 Codex 的结构化 `rate_limits` 数据或 Anthropic 官方 OAuth usage 接口。项目不会根据本地 token 数量估算余额。

## 项目结构

```text
work/AIQuotaWatch/   macOS 主窗口、官方数据读取、本地 HTTP/Web 客户端
work/AIQuotaMenu/    macOS 菜单栏常驻程序
work/AIQuotaPhone/   原生 iPhone 客户端工程
scripts/             macOS 构建、安装和卸载脚本
packaging/           LaunchAgent 模板
```

## macOS 构建

要求：macOS 14 或更高版本，Apple Silicon，Swift 6/Xcode Command Line Tools。

```bash
./scripts/build-macos.sh
```

构建结果位于 `dist/`：

```text
dist/AI 额度观察.app
dist/AI 额度菜单.app
```

## macOS 安装

```bash
./scripts/install-macos.sh
```

安装脚本会：

1. 构建并签署两个本地 App
2. 安装到 `~/Applications`
3. 安装两个用户级 LaunchAgent
4. 启动主程序和菜单栏程序
5. 验证二者处于运行状态

卸载程序但保留额度历史和登录缓存：

```bash
./scripts/uninstall-macos.sh
```

## iPhone 客户端

用 Xcode 打开：

```text
work/AIQuotaPhone/AIQuotaPhone.xcodeproj
```

iPhone 客户端连接 Mac 主程序提供的局域网接口。首次使用时需要把客户端中的 Mac 地址改为该 Mac 当前的局域网地址。

## 隐私与安全

- 仓库不包含任何 Codex/Claude 账号令牌。
- 安装包也不应包含 `~/Library/Application Support/AIQuotaWatch`。
- Claude OAuth 凭据只在本机运行时读取，并缓存在本机 Application Support 中。
- Web/iPhone 接口默认服务于局域网使用场景；不要直接暴露到公网。
- 公开 fork 或提交前请阅读 [SECURITY.md](SECURITY.md)。

## 制作信息

由 Codex（GPT-5）为 Richard 制作，2026。

本仓库公开用于源码审阅。当前未附加开源许可证，默认保留全部权利。
