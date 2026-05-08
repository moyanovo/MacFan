# MacFan

<p align="center">
  <strong>Native, ultra-lightweight fan control for MacBook Pro 13-inch M1.</strong><br>
  <span>菜单栏温度显示 · 原生 macOS 菜单 · 低占用风扇控制</span>
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">中文</a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange">
  <img alt="UI" src="https://img.shields.io/badge/UI-AppKit-blue">
  <img alt="Release" src="https://img.shields.io/badge/release-v1.0.0-brightgreen">
</p>

---

## English

MacFan is a small native macOS menu bar app built for the **MacBook Pro 13-inch, M1, 2020**. It shows temperature in the menu bar and lets you switch between macOS System Auto, four fixed fan presets, or a manual linear RPM slider.

The app is intentionally minimal: no charts, no background analytics, no heavy UI runtime, and no polling fan RPM while the menu is closed.

### Features

- **Native menu bar app** built with Swift and AppKit.
- **Temperature-only closed state**: the menu bar title refreshes temperature without reading fan RPM.
- **Dynamic open menu**: fan RPM and state refresh while the menu is open.
- **System Auto by default**: lets macOS control the fan until you choose another mode.
- **Four presets**: Silent, Balanced, Cool, and Max.
- **Manual Linear Control**: exact RPM slider with throttled writes.
- **Launch at Login** toggle.
- **Safe Quit**: restores System Auto before exiting.
- **AppleSMC helper boundary** with safe fallback if private SMC keys are unavailable.

### Target machine

Optimized and tested on:

- MacBook Pro, 13-inch, M1, 2020
- 8 GB memory
- macOS 26.5 Beta, build 25F5058e

MacFan should stay safe on unsupported systems: if AppleSMC access is unavailable, it displays `--°`, disables manual fan controls, and falls back to System Auto behavior.

### Install from release

1. Download `MacFan-v1.0.0.zip` from the GitHub Release.
2. Unzip it.
3. Double-click `Install.command`.
4. Approve the administrator prompt. This installs the small AppleSMC helper at `/Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper`, which is required for full temperature and fan control.

You can run `MacFan.app` directly, but without the installed helper the app may safely fall back to `--°` and disabled fan controls.

> Note: this release is ad-hoc signed for local use, not notarized through Apple Developer ID.

### Build from source

```bash
./Scripts/package_app.sh
```

The packaged app will be created at:

```text
dist/MacFan.app
```

Build the GitHub Release zip:

```bash
./Scripts/package_release.sh
```

The release zip will be created at:

```text
dist/MacFan-v1.0.0.zip
```

Install locally with the privileged helper:

```bash
./Scripts/install_local.sh
```

Uninstall:

```bash
./Scripts/uninstall_local.sh
```

### Verification

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift test --enable-swift-testing
```

In the Codex sandbox, add `--disable-sandbox`:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift test --disable-sandbox --enable-swift-testing
```

---

## 中文

MacFan 是一个为 **MacBook Pro 13-inch, M1, 2020** 专门优化的原生 macOS 菜单栏风扇控制器。它会在菜单栏显示温度，点开后可以选择 macOS 系统自动控制、四个固定风扇档位，或使用手动线性 RPM 滑杆。

这个项目的目标是极致轻量：不做图表、不做后台分析、不引入重 UI 运行时，并且在菜单收起时不读取风扇转速。

### 功能

- **原生菜单栏应用**：Swift + AppKit 实现。
- **收起时只读温度**：菜单栏只刷新温度，不读取风扇 RPM。
- **点开后动态刷新**：菜单打开后才刷新风扇转速和控制状态。
- **默认 System Auto**：默认交给 macOS 原生风扇控制。
- **四个档位**：Silent、Balanced、Cool、Max。
- **手动线性控制**：可用滑杆精确设置 RPM，并带写入节流。
- **开机启动开关**。
- **安全退出**：退出前恢复 System Auto。
- **AppleSMC helper 边界**：如果私有 SMC key 不可用，会安全降级，不崩溃、不高频重试。

### 目标设备

已针对以下环境优化和测试：

- MacBook Pro, 13-inch, M1, 2020
- 8GB 内存
- macOS 26.5 Beta，build 25F5058e

如果系统更新后 AppleSMC 不可用，MacFan 会显示 `--°`，禁用手动风扇控制，并回到 System Auto 的安全行为。

### 从 Release 安装

1. 在 GitHub Release 下载 `MacFan-v1.0.0.zip`。
2. 解压。
3. 双击 `Install.command`。
4. 批准管理员权限提示。这个步骤会把小型 AppleSMC helper 安装到 `/Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper`，完整温度读取和风扇控制需要它。

你也可以直接运行 `MacFan.app`，但如果没有安装 helper，应用会安全降级为 `--°` 和禁用风扇控制。

> 注意：这个版本使用本地 ad-hoc 签名，没有经过 Apple Developer ID notarization。

### 从源码构建

```bash
./Scripts/package_app.sh
```

打包结果：

```text
dist/MacFan.app
```

构建 GitHub Release zip：

```bash
./Scripts/package_release.sh
```

Release zip 输出位置：

```text
dist/MacFan-v1.0.0.zip
```

安装到本机并安装 privileged helper：

```bash
./Scripts/install_local.sh
```

卸载：

```bash
./Scripts/uninstall_local.sh
```

### 验证

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift test --enable-swift-testing
```

在 Codex sandbox 中使用：

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift test --disable-sandbox --enable-swift-testing
```
