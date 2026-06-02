# Flutter 使用手册（中文版）

> 适用于 AI Wardrobe Master 当前主分支联调。本文重点补充 Windows + Android 真机 + 本地后端场景。

## 1. 环境准备

最低需要：

- Flutter SDK
- Android Studio 或 Android SDK
- Git
- 已启动的本地后端
- Android 手机并开启 USB 调试

检查命令：

```bash
flutter --version
flutter doctor
adb devices
```

## 2. 常用命令

```bash
flutter pub get
flutter clean
flutter run
flutter run -d <device-id>
flutter test
flutter analyze
```

## 3. 启动本地后端

当前 Flutter 联调默认使用本地后端：

```text
http://localhost:8000/api/v1
```

在启动 Flutter 之前，先确保后端容器或本地服务已启动。  
如果后端没有起来，登录、Discover、共享图片和个人页 `/me` 都会失败。

## 4. Windows 上连接 Android 真机

### 前置步骤

1. 手机打开开发者选项
2. 开启 USB 调试
3. 用 USB 连接电脑
4. 执行：

```bash
adb devices
```

如果设备已连接，会看到一条 `device` 状态记录。

### 运行 Flutter

进入应用目录后执行：

```bash
flutter pub get
flutter run -d <device-id>
```

## 5. 本地后端 + Android 真机联调重点

如果后端运行在开发机本地 `8000` 端口，Android 真机不能直接把手机自己的 `127.0.0.1` 当成电脑。  
当前必须先执行：

```bash
adb reverse tcp:8000 tcp:8000
```

作用：

- 把手机访问的 `127.0.0.1:8000` 反向映射到开发机本地的 `8000`
- 这样手机上的 Flutter App 才能访问你电脑里的 FastAPI 服务

这一步是当前 Windows 真机联调里最容易漏掉的关键步骤。

## 6. 当前推荐联调顺序

```bash
cd ai_wardrobe_app
flutter pub get
adb devices
adb reverse tcp:8000 tcp:8000
flutter run -d <device-id>
```

如果后端是 Docker 启动，顺序应为：

1. 先起后端 Docker
2. 再执行 `adb reverse`
3. 最后 `flutter run`

## 7. 当前已验证过的真机场景

本地主分支最近已经在 Android 真机验证过以下链路：

- 注册和登录
- 个人页通过 `/me` 正确显示账号状态
- 子衣柜分享
- Discover 中公开 wardrobe 浏览
- 按 `wid` 和发布者 `uid` 搜索共享内容
- 跨账号查看共享衣柜
- 共享衣物图片跨账号显示
- 共享衣物只读详情页跳转
- 主衣柜长按删除并清缓存
- `Visualize` 双入口页面显示

## 8. 常见问题

### 8.1 手机能打开 App，但数据一直加载失败

优先检查：

1. 后端是否已启动
2. 是否执行过 `adb reverse tcp:8000 tcp:8000`
3. 当前 App 配置是否仍指向本地 `8000` 端口

### 8.2 登录成功后个人页显示异常

优先检查：

- `/me` 是否可访问
- token 是否正确保存
- 后端是否已完成登录后主衣柜初始化

### 8.3 共享衣柜里只能看到名称，看不到图片

优先检查：

- 当前后端是否已包含公开共享图片权限修复
- 目标衣物是否归属于公开 `SUB` wardrobe

### 8.4 修改了原生代码或依赖后热重载不生效

此时不要只按 `r`，应执行：

```bash
R
```

或直接停止后重新 `flutter run`。
