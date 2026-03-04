# Flutter 使用手册（中文版）

> 适用于 AI Wardrobe Master 项目。Flutter 3.38.7 / Dart 3.10.7。

---

## 目录

1. [环境准备](#1-环境准备)
2. [常用命令速查](#2-常用命令速查)
3. [在真机上运行（iOS）](#3-在真机上运行ios)
4. [在真机上运行（Android）](#4-在真机上运行android)
5. [iOS vs Android 区别一览](#5-ios-vs-android-区别一览)
6. [调试与热重载](#6-调试与热重载)
7. [构建发布包](#7-构建发布包)
8. [常见问题](#8-常见问题)

---

## 1. 环境准备

```bash
# 检查 Flutter 版本
flutter --version

# 检查环境是否完整（会列出缺少的依赖）
flutter doctor

# 如果 flutter doctor 报问题，按提示安装缺少的组件
# 常见：Xcode（iOS）、Android Studio / SDK（Android）、CocoaPods（iOS）
```

**最低要求：**

| 平台 | 需要安装 |
|------|---------|
| iOS | macOS + Xcode（App Store 下载）+ CocoaPods |
| Android | Android Studio + Android SDK + 真机开启 USB 调试 |
| 通用 | Flutter SDK、Git |

---

## 2. 常用命令速查

```bash
# ========== 项目相关 ==========

# 拉取依赖（clone 项目后第一件事）
flutter pub get

# 清理构建缓存（遇到奇怪编译错误时试试）
flutter clean

# 清理后重新拉依赖
flutter clean && flutter pub get

# ========== 查看设备 ==========

# 列出所有已连接的设备（手机、模拟器、浏览器）
flutter devices

# ========== 运行 ==========

# 在默认设备上运行（如果只连了一个设备会自动选）
flutter run

# 指定设备运行（device-id 从 flutter devices 里复制）
flutter run -d <device-id>

# 以 release 模式运行（更快、无调试信息）
flutter run --release

# 以 profile 模式运行（用于性能分析）
flutter run --profile

# ========== 构建 ==========

# 构建 iOS（生成 .app / .ipa）
flutter build ios

# 构建 Android APK
flutter build apk

# 构建 Android App Bundle（上传 Google Play 用）
flutter build appbundle

# ========== 测试 ==========

# 运行所有单元测试
flutter test

# 运行某个测试文件
flutter test test/widget_test.dart

# ========== 代码生成 / 分析 ==========

# 分析代码（检查 lint）
flutter analyze

# 格式化代码
dart format .
```

---

## 3. 在真机上运行（iOS）

### 前置条件

1. **macOS** — iOS 开发只能在 Mac 上进行。
2. **Xcode** — 从 App Store 安装最新版。
3. **Apple ID** — 用于签名。免费 Apple ID 即可（个人开发者账号不是必须的）。
4. **CocoaPods** — Flutter iOS 依赖管理。
5. **用 Lightning / USB-C 线把 iPhone 连到 Mac**。

### 步骤

```bash
# 1. 安装 CocoaPods（如果没有）
sudo gem install cocoapods
# 或者用 Homebrew：
brew install cocoapods

# 2. 进入项目目录
cd ai_wardrobe/ai_wardrobe_app

# 3. 拉取依赖
flutter pub get

# 4. 安装 iOS 原生依赖
cd ios && pod install && cd ..

# 5. 查看设备列表，找到你的 iPhone
flutter devices

# 输出示例：
# Drunk (mobile) • 00008120-000A6DE10293C01E • ios • iOS 26.3
# macOS (desktop) • macos • darwin-arm64
# Chrome (web)    • chrome • web-javascript

# 6. 指定设备运行
flutter run -d 00008120-000A6DE10293C01E
# 或者用设备名（有空格要加引号）
flutter run -d "Drunk"
```

### 首次运行 iOS 真机的签名配置

1. 用 Xcode 打开 `ios/Runner.xcworkspace`（**不是** `.xcodeproj`）。
2. 在左侧选中 **Runner** → 点击 **Signing & Capabilities**。
3. 勾选 **Automatically manage signing**。
4. **Team** 选择你的 Apple ID（没有的话点 Add Account 登录）。
5. 如果 Bundle Identifier 冲突，改成唯一的，比如 `com.yourname.aiwardrobeapp`。
6. 关闭 Xcode，回终端 `flutter run -d <device-id>`。

### iPhone 上信任开发者

首次安装后，iPhone 上可能弹「不受信任的开发者」：

> 设置 → 通用 → VPN 与设备管理 → 找到你的开发者证书 → 点「信任」。

---

## 4. 在真机上运行（Android）

### 前置条件

1. **Android Studio**（或至少安装 Android SDK + 命令行工具）。
2. **手机开启 USB 调试**。
3. **用 USB 线把 Android 手机连到电脑**。

### 开启 USB 调试

> 设置 → 关于手机 → 连续点击「版本号」7 次 → 返回设置 → 开发者选项 → 打开「USB 调试」。

（不同品牌路径略有不同，小米/华为可能还需要额外开启「USB 安装」。）

### 步骤

```bash
# 1. 进入项目目录
cd ai_wardrobe/ai_wardrobe_app

# 2. 拉取依赖
flutter pub get

# 3. 查看设备
flutter devices

# 输出示例：
# Pixel 7 (mobile) • adb-28291FDH300074-cYflow • android-arm64 • Android 14

# 4. 运行
flutter run -d adb-28291FDH300074-cYflow
# 或直接（只连了一个 Android 设备时）
flutter run
```

### Android 无需签名配置

和 iOS 不同，Android debug 模式下**不需要任何签名**，直接就能 `flutter run`。只有发布到 Google Play 时才需要配置 keystore。

---

## 5. iOS vs Android 区别一览

| 对比项 | iOS | Android |
|-------|-----|---------|
| **开发系统** | 只能用 macOS | macOS / Windows / Linux 都行 |
| **IDE 依赖** | 必须安装 Xcode | 必须安装 Android Studio 或 SDK |
| **签名** | 首次需配置 Apple ID + 信任开发者 | Debug 模式无需签名 |
| **原生依赖** | CocoaPods（`pod install`） | Gradle（自动处理） |
| **连接方式** | Lightning / USB-C 线 | USB 线 + 开启 USB 调试 |
| **模拟器** | Xcode → iOS Simulator | Android Studio → AVD Manager |
| **启动模拟器命令** | `open -a Simulator` | `flutter emulators --launch <name>` |
| **构建产物** | `.app`（调试）/ `.ipa`（发布） | `.apk` / `.aab`（发布） |
| **首次编译速度** | 较慢（1–3 分钟） | 较慢（1–3 分钟） |
| **热重载** | 一样快（< 1 秒） | 一样快（< 1 秒） |

---

## 6. 调试与热重载

运行 `flutter run` 后，终端会进入交互模式：

| 按键 | 功能 |
|------|------|
| `r` | **Hot Reload** — 保留状态，刷新 UI（最常用） |
| `R` | **Hot Restart** — 重置状态，从头重新运行 |
| `q` | 退出运行 |
| `d` | 断开设备（不退出 app） |
| `o` | 切换 iOS / Android 平台视觉预览 |
| `p` | 显示/隐藏网格辅助线 |

**Hot Reload 的限制：** 改了 `main()` 函数、改了全局变量初始化、改了原生代码、加了新的依赖包 → 这些情况下 hot reload 不生效，需要按 `R`（Hot Restart）或停止重新 `flutter run`。

---

## 7. 构建发布包

### iOS（需要 Apple Developer 账号，$99/年）

```bash
# 构建 release
flutter build ios --release

# 然后用 Xcode 打开 ios/Runner.xcworkspace
# Product → Archive → 上传到 App Store Connect
```

### Android

```bash
# 构建 APK（可以直接安装到手机）
flutter build apk --release

# 产物路径：build/app/outputs/flutter-apk/app-release.apk

# 构建 AAB（上传 Google Play）
flutter build appbundle --release
```

---

## 8. 常见问题

### Q: `flutter run` 报 "No devices found"

```bash
# 检查设备是否连接
flutter devices

# iOS：确认 iPhone 已解锁、信任了电脑
# Android：确认 USB 调试已开启，电脑已被手机授权
```

### Q: iOS 编译报 CocoaPods 错误

```bash
cd ios
pod deintegrate
pod install
cd ..
flutter run
```

### Q: Android 编译报 Gradle 错误

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### Q: 改了代码但 Hot Reload 没反应

- 确认改的不是 `main()` / 原生代码 / 新增依赖。
- 按 `R` 做一次 Hot Restart。
- 还不行就 `q` 退出，重新 `flutter run`。

### Q: "Untrusted Developer" 弹窗（iOS）

> 设置 → 通用 → VPN 与设备管理 → 找到证书 → 信任。

### Q: 首次运行特别慢

正常。首次编译 iOS / Android 需要下载并编译原生依赖，通常 1–5 分钟。之后热重载秒级。

---

## 快速起手（30 秒版）

```bash
cd ai_wardrobe/ai_wardrobe_app
flutter pub get
flutter devices          # 确认设备
flutter run -d <设备ID>   # 开跑
# 改代码后按 r 热重载
```
