# Notification Sweep

一个原生 macOS app，用辅助功能接口触发 `NotificationCenter` 里的 `Clear All` / `Close` 动作，效果接近通知中心里的清除按钮。

## 项目结构

- `src/NotificationSweepApp.m`
  原生 app 主逻辑，负责通过 Accessibility API 查找并触发 `Clear All` / `Close`。
- `tools/GenerateAppIcon.m`
  构建时使用的图标生成器，会输出 app 所需的 `.icns` 资源。
- `tools/build-app.sh`
  本地构建脚本，负责编译 app、生成图标、写入 `Info.plist`、签名并刷新 Dock。

## 应用标识

- 应用名：`Notification Sweep`
- bundle id：`local.notification-sweep.app`

## 构建

运行：

```bash
./tools/build-app.sh
```

构建脚本会：

- 编译原生 Cocoa app
- 生成自定义 `.icns` 图标
- 安装到 `~/Applications/Notification Sweep.app`
- 自动刷新 Dock 中的应用入口

## Contribution Guide

### 工具链依赖

这个项目当前依赖的是 macOS 自带原生工具链，而不是 Node.js、Python 包管理器或 Xcode 工程：

- macOS 13+  
  当前构建脚本写入的 `LSMinimumSystemVersion` 是 `13.0`。
- Xcode Command Line Tools  
  提供 `clang`、macOS SDK，以及 `AppKit` / `ApplicationServices` 相关 framework 头文件与链接能力。
- `iconutil`  
  用于把构建时生成的 iconset 转成 `.icns`。
- `codesign`  
  用于给 `.app` 做本地 ad-hoc 签名。
- `python3`  
  目前仅用于在构建脚本里安全修改 Dock 的 plist。

如果本机还没装命令行工具，先执行：

```bash
xcode-select --install
```

### 开发约定

- 业务逻辑放在 `src/`，构建和辅助脚本放在 `tools/`。
- 不要提交本地辅助代理相关内容；`.agents/` 和 `skills-lock.json` 已经默认忽略。
- 修改构建、签名、bundle id 或应用名后，记得重新运行构建脚本并检查辅助功能权限是否需要重新授权。

### 本地验证

完成修改后，至少跑一次：

```bash
./tools/build-app.sh
```

## 权限

首次点击 app 时，需要在这里给它开启辅助功能权限：

`系统设置 > 隐私与安全性 > 辅助功能 > Notification Sweep`

如果你修改过应用名、bundle id 或签名，macOS 可能会把它当成新应用，需要重新授权一次。

## 说明

- 这个工具依赖 macOS 当前版本里 `NotificationCenter` 的辅助功能结构。
- 不同 macOS 版本的 UI 层级可能会变化。
- 如果某些通知没有暴露 `Close` 或 `Clear All` 动作，它们无法被 app 强制关闭。
- 当前实现是原生 Cocoa + macOS Accessibility API，不依赖 Terminal、JXA、AppleScript 或 `System Events`。
