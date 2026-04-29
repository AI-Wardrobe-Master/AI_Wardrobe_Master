# AI Wardrobe Master - Flutter Architecture

## Overview

本文档记录 Flutter 客户端当前真实页面结构、核心服务与缓存行为。  
旧文档中“fresh Flutter project with default template”的描述已经过时，不再适用。

## Current Project Status

- Flutter 3.x
- Dart 3.x
- Android 为当前主要联调平台
- Web 提供基础演示壳层
- 主分支已包含共享子衣柜、Discover 合并与可视化双入口

## Project Structure

当前 Flutter 代码组织虽然不是早期文档里的严格 Clean Architecture 模板，但依然保持了清晰的分层：

```text
ai_wardrobe_app/lib/
├── models/
├── services/
├── ui/
│   ├── screens/
│   └── widgets/
└── main.dart
```

其中：

- `models/` 负责前端消费的数据结构
- `services/` 负责 API、缓存、本地持久化与会话
- `ui/screens/` 负责主页面与流程页面
- `ui/widgets/` 负责复用组件

## Current App Shell

当前根壳层位于 `ai_wardrobe_app/lib/ui/root_shell.dart`。

### Mobile navigation

移动端底部结构为：

- `Wardrobe`
- `Discover`
- `Add`
- `Visualize`
- `Profile`

其中：

- `Wardrobe` -> `WardrobeScreen`
- `Discover` -> `DiscoverScreen`
- `Visualize` -> `VisualizationHubScreen`
- `Profile` -> `ProfileScreen`

中央 `Add` 为操作入口，不是普通内容页。它会弹出底部菜单，提供：

- 添加衣物：`CameraCaptureScreen -> ClothingIntakeScreen`
- 创建卡包：`CardPackCreatorScreen`

### Web navigation

Web 端使用 `NavigationRail`，与移动端保持同样的信息架构。

## Major Screens

### 1. `WardrobeScreen`

职责：

- 展示主衣柜与子衣柜
- 支持导出选择、分享、移除和删除

当前关键行为：

- 分享子衣柜前，若未公开则先把 `isPublic` 更新为 `true`
- 主衣柜长按：真实删除衣物并清本地缓存
- 子衣柜长按：仅从当前衣柜移除关联

### 2. `DiscoverScreen`

当前只有两个 tab：

- `Wardrobes`
- `Creators`

关键行为：

- 公开 `packs` 与共享 `wardrobes` 已合并在 `Wardrobes` tab
- 搜索支持名称、`wid`、`ownerUid`、`ownerUsername`、描述
- 点击卡片后进入 `SharedWardrobeDetailScreen`

### 3. `SharedWardrobeDetailScreen`

职责：

- 通过 `wid` 加载公开共享衣柜
- 展示共享衣柜中的衣物资料卡

关键行为：

- 通过 `fetchWardrobeByWid` 获取衣柜
- 通过 `fetchPublicWardrobeItemsByWid` 获取衣物列表
- 每张卡可点击进入 `SharedClothingDetailScreen`

### 4. `SharedClothingDetailScreen`

新增的只读共享详情页。

职责：

- 展示共享衣物图片
- 展示共享元数据：WID、Publisher UID、分类、材质、描述、标签

关键设计：

- 不复用私有详情页
- 不显示删除等私有操作

### 5. `VisualizationHubScreen`

当前 `Visualize` 不再是单页，而是双模式 Hub：

- `Canvas Studio`
- `Face + Scene`

前者承接已有的全身照穿搭画布，后者承接新增的 demo 流程。

### 6. `ScenePreviewDemoScreen`

职责：

- 上传人脸照
- 选择一张衣物卡
- 输入场景描述
- 返回 demo 预览图

当前状态：

- 页面与用户流程已打通
- 真实后端模型尚未接入

### 7. `ProfileScreen`

职责：

- 基于 `/me` 显示当前账号状态
- 展示 `uid`、账号信息、创作者资料和 capability 驱动的入口

当前结果：

- 已修复登录后仍显示 `not signed in` 的问题

## Services and Data Access

### Remote services

当前主要通过服务层访问后端，例如：

- `AuthApiService`
- `MeApiService`
- `ClothingApiService`
- `WardrobeService`

### Local caching

当前缓存策略以本地服务为主：

- `local_clothing_service.dart`
- `local_wardrobe_service.dart`

关键行为：

- 衣物列表支持本地缓存与远端回填
- `deleteItem(itemId)` 会同步清理本地记录和索引
- 共享衣柜详情不走私有缓存写路径，避免污染本人衣柜状态

### Session storage

JWT 与基础会话信息通过本地持久化保存，供启动恢复和接口调用使用。

## UI State Principles

1. 共享内容与私有内容分离建模
2. 个人页必须以 `/me` 为准
3. 主衣柜删除与子衣柜移除分开
4. Discover 公开列表只展示共享 wardrobe 抽象
5. 可视化第二入口明确标记为 demo，不伪装成真实生成

## Real-Device Android Notes

在 Windows 上连接 Android 真机联调本地后端时，当前流程为：

```bash
adb devices
adb reverse tcp:8000 tcp:8000
flutter run -d <device-id>
```

该流程已用于验证：

- 登录后个人页状态
- 子衣柜分享
- Discover 搜索和公开浏览
- 跨账号共享衣物图片
- 共享详情页跳转

## Remaining Risks

- 衣物新增后的性能与缓存策略仍有继续优化空间
- `Face + Scene` 仍是 demo 输出，不是正式 AI 生成
- Discover 和共享链路已稳定，但后续若新增“导入到我的衣柜”操作，需要继续扩展只读共享详情页

## Legacy Design Continuity

原文档里关于以下方向的建议仍然适用：

- Flutter 以服务层统一封装 API
- 本地缓存和远端同步并存
- 页面与组件分层组织
- Android 真机作为当前主要联调平台

这次更新只是把实际已经实现的导航结构、共享详情页面和可视化双入口补成当前规范。
