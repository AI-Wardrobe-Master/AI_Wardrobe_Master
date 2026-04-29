# Profile 人脸素材与 Visualize 联通功能说明

## 1. 文档目的

本文档用于说明当前前端新增的“个人资料页人脸素材管理”以及它和 `Visualize > Face + Scene` 预览入口之间的联通关系，方便后续成员进行操作、测试和维护。

根据 `groupmembers'markdown/wzh.md` 中的工作记录，当前项目已经完成了较多前端业务链路整合、图片上传 Web 兼容修复、DreamO 本地低显存部署测试、衣物图片存储与回显修复等工作。本文只补充本次新增的人脸素材前端功能，不重复记录已有文档中已经覆盖的模块：

- DreamO 后端部署、模型配置与服务接口：见 `documents/DREAMO_INTEGRATION.md`
- Styled Generation 后端接口契约与轮询流程：见 `documents/FLUTTER_STYLED_GENERATION_GUIDE.md`
- Flutter 整体架构：见 `documents/FLUTTER_ARCHITECTURE.md`

## 2. 功能概述

新增功能由两部分组成：

1. 用户可在 `Profile` 页面设置生成用人脸素材。
2. `Visualize > Face + Scene` 页面会自动读取并使用 `Profile` 中保存的人脸素材。

用户在人脸素材上有三种选择：

- 上传真人照片，并通过裁切框裁出人脸区域。
- 选择虚拟男性头像。
- 选择虚拟女性头像。

这样做的原因是：部分用户不愿意上传真人头像，但仍然需要一个可用于生成流程的身份输入素材，因此提供了虚拟头像作为替代方案。

## 3. 用户操作流程

### 3.1 在 Profile 页面设置人脸素材

入口：

```text
Profile 页面 -> Face photo for generation
```

支持操作：

- 点击 `Upload and crop face photo` 从图库选择照片。
- 进入 `Crop face photo` 页面。
- 拖动裁切框对准人脸。
- 拖动右下角控制点调整裁切框大小。
- 点击 `Use crop` 保存裁切后的 512x512 PNG。
- 或直接选择 `Virtual Male` / `Virtual Female` 作为生成素材。
- 点击清除按钮可移除当前人脸素材。

保存后，Profile 顶部头像预览和人脸素材卡片会同步更新。

### 3.2 在 Visualize 中自动使用 Profile 头像

入口：

```text
Visualize -> Face + Scene
```

页面会在初始化时调用 `FaceProfileService.load()` 读取当前用户保存的人脸素材：

- 如果是上传并裁切过的人脸照片，则直接使用保存的 PNG 字节。
- 如果是虚拟男 / 女头像，则前端会将虚拟头像绘制成 PNG 字节。
- 如果没有设置人脸素材，生成按钮会保持不可用。

页面中仍提供两个辅助操作：

- `Upload Profile Face` / `Change Profile Face`：重新上传并裁切人脸，同时保存回 Profile。
- `Sync from Profile`：重新从 Profile 本地存储读取当前人脸素材。

## 4. 关键代码文件

### 4.1 人脸素材存储服务

```text
ai_wardrobe_app/lib/services/face_profile_service.dart
```

主要职责：

- 定义 `FaceProfileKind`
  - `none`
  - `custom`
  - `virtualMale`
  - `virtualFemale`
- 保存上传裁切后的真人头像。
- 保存虚拟头像选择。
- 清除当前选择。
- 按当前登录用户隔离本地存储 key，避免不同账号之间串数据。
- 将虚拟头像渲染为 PNG 字节，供 Visualize 使用。

当前存储方式：

```text
SharedPreferences
```

使用的 key 前缀：

```text
profile_face_kind_v1
profile_face_custom_png_v1
```

实际保存时会拼接当前用户 ID：

```text
profile_face_kind_v1_<userId>
profile_face_custom_png_v1_<userId>
```

如果当前没有登录用户，则使用 `_offline` 后缀。

### 4.2 人脸裁切页面

```text
ai_wardrobe_app/lib/ui/screens/face_crop_screen.dart
```

主要职责：

- 接收原始图片字节。
- 在页面中显示图片。
- 绘制方形裁切框。
- 支持拖动裁切框位置。
- 支持拖动右下角控制点调整裁切框大小。
- 点击确认后输出 512x512 PNG 字节。

该页面使用 `Image.memory` 和 `dart:ui` 进行图片显示与裁切，因此兼容 Flutter Web，避免了 `Image.file is not supported on Flutter Web` 的问题。

### 4.3 Profile 页面入口

```text
ai_wardrobe_app/lib/ui/screens/profile_screen.dart
```

主要职责：

- 展示当前用户资料。
- 展示当前已选的人脸素材。
- 提供上传、裁切、虚拟头像选择和清除操作。
- Profile 页面内容改为可滚动，避免新增卡片后在小屏设备上溢出。

新增或相关组件：

```text
_FaceSourceCard
_VirtualFaceButton
_FaceAvatarPreview
_VirtualFaceAvatar
_VirtualFacePainter
```

### 4.4 Visualize 联通页面

```text
ai_wardrobe_app/lib/ui/screens/scene_preview_demo_screen.dart
```

主要职责：

- 初始化时自动读取 Profile 的人脸素材。
- 将人脸素材作为 `Face + Scene` 流程的默认人脸输入。
- 在页面上显示当前使用的人脸来源。
- 当用户在该页面上传新头像时，复用裁切页面，并保存回 Profile。
- 没有人脸素材时禁用生成按钮。

注意：当前该页面仍是 demo 预览流程，展示固定的 demo 结果图。它已经拿到了 Profile 人脸素材，但还没有真正把该素材提交到后端 DreamO 任务接口。

## 5. 当前数据流

```text
Profile 上传图片
        |
        v
FaceCropScreen 裁切为 512x512 PNG
        |
        v
FaceProfileService.saveCustom()
        |
        v
SharedPreferences 按用户保存
        |
        v
Visualize / Face + Scene 初始化读取
        |
        v
Image.memory 显示人脸素材
        |
        v
Generate Demo Preview
```

虚拟头像的数据流：

```text
Profile 选择 Virtual Male / Virtual Female
        |
        v
FaceProfileService.saveVirtual()
        |
        v
Visualize / Face + Scene 读取选择
        |
        v
FaceProfileService.resolveImageBytes()
        |
        v
前端 Canvas 绘制虚拟头像 PNG
        |
        v
作为人脸输入素材显示和后续生成使用
```

## 6. 维护注意事项

### 6.1 不要在 Web 端使用 Image.file

此前项目已经遇到过 Flutter Web 不支持 `Image.file` 的问题。本功能中所有用户上传图片均应优先使用：

```dart
Image.memory(bytes)
```

如果后续需要读取文件，也应使用 `XFile.readAsBytes()`，不要依赖本地文件路径。

### 6.2 不要把大图长期写入 localStorage

此前项目也遇到过浏览器 `QuotaExceededError`。本功能目前只保存裁切后的 512x512 PNG，体积相对可控。

如果后续要保存更大的人脸图、全身图或生成图，建议改为：

- 上传到后端文件存储。
- 前端只保存文件 URL 或 blob ID。

### 6.3 用户隔离必须保留

`FaceProfileService` 当前按 `ApiSession.currentUserId` 隔离本地 key。不要改回全局 key，否则新账号登录后可能看到旧账号的人脸素材。

### 6.4 虚拟头像当前是前端绘制

虚拟头像不是外部图片资源，而是由 `FaceProfileService._renderVirtualAvatar()` 使用 `dart:ui` 绘制为 PNG。

优点：

- 不需要额外图片资产。
- Web / 桌面 / 移动端都能使用同一套逻辑。

缺点：

- 头像风格比较简单。
- 如果生成模型对真实照片要求较高，虚拟头像可能只能作为隐私友好的占位输入，不能保证生成质量。

## 7. 后续接入真实 DreamO 生成的建议

当前 `ScenePreviewDemoScreen` 已经可以拿到 `_faceImageBytes`。如果后续要接入真实后端生成，需要新增或复用前端 API service，将以下字段提交到后端：

```text
POST /api/v1/styled-generations
```

需要提交的关键字段参考 `documents/FLUTTER_STYLED_GENERATION_GUIDE.md`：

- `selfie_image`：使用 `_faceImageBytes`
- `gender`：可由人脸素材类型推断
  - `virtualFemale` -> `FEMALE`
  - 其他默认可先用 `MALE`，或在 UI 中让用户选择
- `scene_prompt`：使用场景输入框文本
- `clothing_items`：当前选择的衣物卡片 ID 和 slot
- `guidance_scale`
- `seed`
- `width`
- `height`

接入后建议将当前按钮文案从：

```text
Generate Demo Preview
```

调整为：

```text
Generate Preview
```

并补充任务轮询、失败提示、结果图保存等流程。

## 8. 测试建议

### 8.1 静态检查

在 `ai_wardrobe_app` 目录下执行：

```bash
dart analyze lib/services/face_profile_service.dart lib/ui/screens/face_crop_screen.dart lib/ui/screens/profile_screen.dart lib/ui/screens/scene_preview_demo_screen.dart
```

当前实现已通过上述静态检查。

### 8.2 手动测试用例

建议至少测试以下场景：

1. 登录账号 A，Profile 上传真人照片，裁切保存。
2. 进入 Visualize > Face + Scene，确认自动显示账号 A 的人脸图。
3. 选择衣物卡片，确认生成按钮可点击。
4. 回到 Profile，切换为虚拟女性头像。
5. 回到 Visualize，点击 `Sync from Profile`，确认头像变为虚拟女性。
6. 清除 Profile 人脸素材。
7. 回到 Visualize，确认生成按钮禁用。
8. 注册或登录账号 B，确认不会看到账号 A 的人脸素材。
9. 在 Flutter Web 下上传 PNG/JPG，确认不会出现 `Image.file is not supported on Flutter Web`。

### 8.3 常见问题

| 问题 | 可能原因 | 处理方式 |
| --- | --- | --- |
| Visualize 页面没有显示头像 | Profile 尚未设置人脸素材 | 在 Profile 中上传或选择虚拟头像 |
| 切换 Profile 头像后 Visualize 没变化 | 页面仍使用旧状态 | 点击 `Sync from Profile` 或重新进入页面 |
| 生成按钮不可点击 | 未选择衣物或无人脸素材 | 同时选择衣物卡片并设置人脸素材 |
| 新账号看到旧头像 | 用户隔离 key 被破坏 | 检查 `FaceProfileService._scopeSuffix()` |
| Web 上传后报 `Image.file` | 新代码又使用了文件路径渲染 | 改为 `readAsBytes()` + `Image.memory` |

## 9. 当前限制

- 当前 Profile 人脸素材只保存在前端本地，不会同步到后端账号资料。
- 当前 `Face + Scene` 页面仍然是 demo 预览结果，没有真正提交 DreamO 后端任务。
- 虚拟头像是简化绘制头像，不保证能达到真实自拍照片同等生成效果。
- 自定义上传头像保存为 base64 字符串，虽然已经裁切压缩到 512x512，但仍不适合保存大量高分辨率图片。

## 10. 本次涉及文件清单

```text
ai_wardrobe_app/lib/services/face_profile_service.dart
ai_wardrobe_app/lib/ui/screens/face_crop_screen.dart
ai_wardrobe_app/lib/ui/screens/profile_screen.dart
ai_wardrobe_app/lib/ui/screens/scene_preview_demo_screen.dart
```

以上文件共同完成了 Profile 人脸素材管理、裁切、虚拟头像选择，以及 Visualize 自动取用 Profile 人脸素材的前端链路。
