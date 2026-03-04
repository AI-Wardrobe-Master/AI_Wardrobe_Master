# Flutter Quick Guide (English)

> For the AI Wardrobe Master project. Flutter 3.38.7 / Dart 3.10.7.

---

## Table of Contents

1. [Setup](#1-setup)
2. [Command Cheat Sheet](#2-command-cheat-sheet)
3. [Run on a Physical iPhone (iOS)](#3-run-on-a-physical-iphone-ios)
4. [Run on a Physical Android Device](#4-run-on-a-physical-android-device)
5. [iOS vs Android Comparison](#5-ios-vs-android-comparison)
6. [Debugging & Hot Reload](#6-debugging--hot-reload)
7. [Building for Release](#7-building-for-release)
8. [FAQ](#8-faq)

---

## 1. Setup

```bash
# Check Flutter version
flutter --version

# Check if your environment is complete (lists missing dependencies)
flutter doctor

# Common requirements:
#   iOS   → macOS + Xcode + CocoaPods
#   Android → Android Studio + Android SDK + USB debugging enabled
#   Both  → Flutter SDK, Git
```

| Platform | Requirements |
|----------|-------------|
| iOS | macOS + Xcode (from App Store) + CocoaPods |
| Android | Android Studio + Android SDK + USB debugging on device |
| Both | Flutter SDK, Git |

---

## 2. Command Cheat Sheet

```bash
# ========== Project ==========

# Install dependencies (first thing after cloning)
flutter pub get

# Clean build cache (try this when you hit weird build errors)
flutter clean

# Clean + reinstall
flutter clean && flutter pub get

# ========== Devices ==========

# List all connected devices (phones, emulators, browsers)
flutter devices

# ========== Run ==========

# Run on the default device
flutter run

# Run on a specific device (copy device-id from `flutter devices`)
flutter run -d <device-id>

# Run in release mode (faster, no debug overhead)
flutter run --release

# Run in profile mode (for performance profiling)
flutter run --profile

# ========== Build ==========

# Build for iOS
flutter build ios

# Build Android APK
flutter build apk

# Build Android App Bundle (for Google Play)
flutter build appbundle

# ========== Test ==========

# Run all tests
flutter test

# Run a specific test file
flutter test test/widget_test.dart

# ========== Code Quality ==========

# Analyze code (lint check)
flutter analyze

# Format code
dart format .
```

---

## 3. Run on a Physical iPhone (iOS)

### Prerequisites

1. **macOS** — iOS development is Mac-only.
2. **Xcode** — Install the latest version from the App Store.
3. **Apple ID** — For code signing. A free Apple ID works (paid Developer account is not required for testing).
4. **CocoaPods** — Manages iOS native dependencies.
5. **Connect your iPhone to the Mac** via Lightning / USB-C cable.

### Steps

```bash
# 1. Install CocoaPods (if not already installed)
sudo gem install cocoapods
# Or via Homebrew:
brew install cocoapods

# 2. Navigate to the project
cd ai_wardrobe/ai_wardrobe_app

# 3. Install Flutter dependencies
flutter pub get

# 4. Install iOS native dependencies
cd ios && pod install && cd ..

# 5. List devices to find your iPhone
flutter devices

# Example output:
# Drunk (mobile) • 00008120-000A6DE10293C01E • ios • iOS 26.3
# macOS (desktop) • macos • darwin-arm64
# Chrome (web)    • chrome • web-javascript

# 6. Run on your device
flutter run -d 00008120-000A6DE10293C01E
# Or use the device name (quote if it contains spaces)
flutter run -d "Drunk"
```

### First-Time iOS Signing Setup

1. Open `ios/Runner.xcworkspace` in Xcode (**not** `.xcodeproj`).
2. Select **Runner** in the left sidebar → click **Signing & Capabilities**.
3. Check **Automatically manage signing**.
4. Under **Team**, select your Apple ID (click "Add Account" if needed).
5. If the Bundle Identifier conflicts, change it to something unique, e.g. `com.yourname.aiwardrobeapp`.
6. Close Xcode, go back to terminal and run `flutter run -d <device-id>`.

### Trust the Developer on iPhone

After the first install, your iPhone may show "Untrusted Developer":

> Settings → General → VPN & Device Management → find your developer certificate → tap "Trust".

---

## 4. Run on a Physical Android Device

### Prerequisites

1. **Android Studio** (or at least Android SDK + command line tools).
2. **USB Debugging enabled** on the phone.
3. **Connect via USB cable**.

### Enable USB Debugging

> Settings → About Phone → tap "Build Number" 7 times → go back to Settings → Developer Options → enable "USB Debugging".

(Exact path varies by manufacturer. Xiaomi/Huawei may require enabling "Install via USB" as well.)

### Steps

```bash
# 1. Navigate to the project
cd ai_wardrobe/ai_wardrobe_app

# 2. Install dependencies
flutter pub get

# 3. List devices
flutter devices

# Example output:
# Pixel 7 (mobile) • adb-28291FDH300074-cYflow • android-arm64 • Android 14

# 4. Run
flutter run -d adb-28291FDH300074-cYflow
# Or simply (if only one Android device is connected):
flutter run
```

### No Signing Required for Android Debug

Unlike iOS, Android debug builds require **no signing configuration**. You only need a keystore when publishing to Google Play.

---

## 5. iOS vs Android Comparison

| Aspect | iOS | Android |
|--------|-----|---------|
| **Dev OS** | macOS only | macOS / Windows / Linux |
| **IDE Dependency** | Xcode required | Android Studio or SDK required |
| **Code Signing** | Apple ID + trust developer on first run | No signing needed for debug |
| **Native Deps** | CocoaPods (`pod install`) | Gradle (handled automatically) |
| **Connection** | Lightning / USB-C cable | USB cable + USB debugging enabled |
| **Emulator** | Xcode → iOS Simulator | Android Studio → AVD Manager |
| **Launch Emulator** | `open -a Simulator` | `flutter emulators --launch <name>` |
| **Build Output** | `.app` (debug) / `.ipa` (release) | `.apk` / `.aab` (release) |
| **First Build Time** | Slow (1–3 min) | Slow (1–3 min) |
| **Hot Reload** | Equally fast (< 1 sec) | Equally fast (< 1 sec) |

---

## 6. Debugging & Hot Reload

After `flutter run`, the terminal enters interactive mode:

| Key | Action |
|-----|--------|
| `r` | **Hot Reload** — preserves state, refreshes UI (most common) |
| `R` | **Hot Restart** — resets state, restarts from scratch |
| `q` | Quit |
| `d` | Detach (leave app running, exit terminal) |
| `o` | Toggle between iOS / Android visual style |
| `p` | Toggle debug paint (layout grid) |

**When Hot Reload won't work:** Changes to `main()`, global variable initializers, native code, or newly added packages require `R` (Hot Restart) or a full `flutter run` restart.

---

## 7. Building for Release

### iOS (requires Apple Developer account, $99/year)

```bash
# Build release
flutter build ios --release

# Then open ios/Runner.xcworkspace in Xcode
# Product → Archive → Upload to App Store Connect
```

### Android

```bash
# Build APK (can be installed directly)
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk

# Build AAB (for Google Play upload)
flutter build appbundle --release
```

---

## 8. FAQ

### Q: `flutter run` says "No devices found"

```bash
flutter devices

# iOS: Make sure iPhone is unlocked and has trusted the computer.
# Android: Make sure USB debugging is on and you tapped "Allow" on the phone.
```

### Q: iOS build fails with CocoaPods errors

```bash
cd ios
pod deintegrate
pod install
cd ..
flutter run
```

### Q: Android build fails with Gradle errors

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### Q: Code changes don't show after Hot Reload

- Make sure you didn't change `main()`, native code, or add new dependencies.
- Press `R` for a full Hot Restart.
- If that fails, press `q` and re-run `flutter run`.

### Q: "Untrusted Developer" popup on iPhone

> Settings → General → VPN & Device Management → find certificate → Trust.

### Q: First run is very slow

That's normal. The first build downloads and compiles native dependencies (1–5 minutes). Subsequent hot reloads are near-instant.

---

## Quick Start (30 seconds)

```bash
cd ai_wardrobe/ai_wardrobe_app
flutter pub get
flutter devices          # confirm your device
flutter run -d <device-id>   # go
# press r after code changes to hot reload
```
