# cht / HongtianChan 个人贡献记录

## 1. 个人定位

- 主要负责：Flutter 前端基础框架、Web/移动端布局、Module 3 衣柜管理前端与体验打磨。
- 协作职责：维护个人工作记录，参与组内 FTR，并承担 Recorder 职责，记录讨论内容、任务状态和待办。
- 重点产出：让项目从初始 Flutter app 变成可演示的多页面前端，并补齐衣柜管理模块的交互、状态反馈和文档说明。

## 2. 关键文件索引

### 2.1 App 入口、导航与布局

- `ai_wardrobe_app/lib/main.dart`：Flutter App 入口与顶层应用初始化。
- `ai_wardrobe_app/lib/ui/root_shell.dart`：主导航壳，负责 Wardrobe / Discover / Add / Visualize / Profile 的整体入口。
- `ai_wardrobe_app/lib/ui/screens/splash_screen.dart`：开屏动画页面。
- `ai_wardrobe_app/lib/ui/screens/login_screen.dart`：登录/跳过登录入口。
- `ai_wardrobe_app/lib/theme/theme_controller.dart`：主题状态控制。
- `ai_wardrobe_app/lib/theme/app_theme.dart`：明暗主题颜色与 ThemeData。

### 2.2 多语言与文案

- `ai_wardrobe_app/lib/l10n/locale_controller.dart`：语言状态控制。
- `ai_wardrobe_app/lib/l10n/app_strings.dart`：中英文文案表。
- `ai_wardrobe_app/lib/l10n/app_strings_provider.dart`：在 Widget 树中读取文案。
- `ai_wardrobe_app/lib/ui/screens/profile_screen.dart`：Profile 设置页中的语言与深色模式入口。

### 2.3 衣柜管理 Module 3

- `ai_wardrobe_app/lib/ui/screens/wardrobe_screen.dart`：衣柜主页，多衣柜切换、衣物网格、分类筛选、搜索、错误/空状态。
- `ai_wardrobe_app/lib/ui/screens/wardrobe_management_screen.dart`：衣柜管理页，创建、重命名、删除、分享衣柜。
- `ai_wardrobe_app/lib/models/wardrobe.dart`：Wardrobe、ClothingItemBrief、WardrobeItemWithClothing 等前端模型。
- `ai_wardrobe_app/lib/services/wardrobe_service.dart`：衣柜相关 API 调用。
- `ai_wardrobe_app/lib/services/local_wardrobe_service.dart`：本地衣柜辅助数据。
- `ai_wardrobe_app/lib/state/current_wardrobe_controller.dart`：当前选中衣柜状态同步。
- `ai_wardrobe_app/lib/ui/screens/capture/clothing_result_screen.dart`：衣物处理结果页，加入当前衣柜入口。

### 2.4 搭配画布与可视化入口

- `ai_wardrobe_app/lib/ui/screens/outfit_canvas_screen.dart`：Outfit 画布与人台区域交互。
- `ai_wardrobe_app/lib/ui/screens/visualization_hub_screen.dart`：可视化功能入口。

### 2.5 Debug 与质量修复

- `ai_wardrobe_app/lib/ui/screens/capture/camera_capture_screen.dart`：清理未使用变量。
- `ai_wardrobe_app/lib/ui/screens/capture/processing_screen.dart`：修复 lint，补齐 `if` 花括号。
- `ai_wardrobe_app/test/widget_test.dart`：清理未使用 import。

### 2.6 文档与协作记录

- `README.md`：根目录英文 README，说明仓库结构、快速开始和推荐阅读顺序。
- `documents/FLUTTER_GUIDE_ZH.md`：中文 Flutter 运行指南。
- `documents/FLUTTER_GUIDE_EN.md`：英文 Flutter 运行指南。
- `documents/FLUTTER_ARCHITECTURE.md`：Flutter 前端架构说明。
- `groupmembers'markdown/cht.md`：个人工作记录与贡献核对。

## 3. 时间记录

### 3.1 2026.3.4：前端基础框架搭建

- 搭建 Flutter 前端样板 `ai_wardrobe_app`。
- 完成五个主 Tab：Wardrobe / Discover / Add / Visualize / Profile。
- 实现 Add BottomSheet，作为添加衣物与进入搭配画布的统一入口。
- 设计空状态页面，让 Wardrobe、Discover、Profile 等页面在无数据时也有基本展示。
- 设计并实现 Outfit 可视化画布：
  - 灰色剪影模特。（后面由bailujia更新）
  - 可点击身体区域。
  - 点击后弹出 BottomSheet，后续可连接帽子、上装、裤装、鞋子等衣物选择。
- 实现全局明暗主题：
  - `ThemeController` 管理主题状态。
  - `app_theme.dart` 提供 Light / Dark ThemeData。
  - Profile 页提供 Dark Mode 开关。
- 完成移动端与 Web 端响应式布局：
  - 移动端使用底部导航栏。
  - Web/大屏使用左侧 `NavigationRail`。
  - 按平台和宽度自动切换。
- 补充前端文档：
  - `documents/FLUTTER_GUIDE_ZH.md`
  - `documents/FLUTTER_GUIDE_EN.md`
  - `documents/FLUTTER_ARCHITECTURE.md`
- 整理仓库结构，确保 `ai_wardrobe` 作为项目根目录。

### 3.2 2026.3 初：开屏、登录、多语言与 README

- 新增 `SplashScreen`：
  - Logo + 标题缩放/渐显动画。
  - 约 1.5 秒后进入登录页。
  - 去掉多余副标题，使开屏更干净。
- 新增 `LoginScreen`：
  - 提供 Continue / Skip for now 入口。
  - 支撑前期无完整账号系统时的前端演示流程。
- 优化 Web 端左侧导航：
  - 去掉顶部 AIW 文字与图标。
  - 保留 `NavigationRail` + Add 按钮。
- 将根目录 README 改为英文，并补充：
  - Repository structure。
  - Getting started。
  - Directory details。
  - Suggested reading order。
- 新增多语言结构：
  - `LocaleController`
  - `AppStrings`
  - `AppStringsProvider`
- 在 Profile 设置中加入语言下拉框，并与 `localeController` 联动。
- 将主要界面文案接入中英文：
  - Splash
  - Login
  - Navigation
  - Wardrobe
  - Discover
  - Profile
  - Add BottomSheet
  - Outfit Canvas

### 3.3 2026.3.8：Module 3 衣柜管理

- 完成 WBS 3.0 衣柜管理模块的主要前端实现。
- 实现 `WardrobeManagementScreen`：
  - 创建衣柜。
  - 重命名衣柜。
  - 删除衣柜。
  - 支持常规衣柜与虚拟衣柜类型。
- 实现 `WardrobeScreen`：
  - 多衣柜选择与切换。
  - 当前衣柜内衣物网格。
  - 分类 Chips。
  - 搜索过滤。
  - 长按移除衣物。
  - 虚拟衣柜标签与 imported item 展示。
- 接入 `WardrobeService` 与前端模型：
  - `Wardrobe`
  - `ClothingItemBrief`
  - `WardrobeItemWithClothing`
- 通过 `CurrentWardrobeController` 同步当前选中衣柜。
- 在 `ClothingResultScreen` 增加“加入当前衣柜”按钮：
  - 拍照录入完成后可一键加入当前衣柜。
  - 补齐 Module 3.2 添加衣物入口。

### 3.4 2026.4.29：前端 Debug 与体验打磨

- 运行 `flutter analyze` 排查前端静态问题。
  - 初始结果：87 个 issues。
  - 主要为 info / deprecated / unused warning。
  - 没有发现编译级 blocker。
- 清理真实 warning：
  - `ai_wardrobe_app/lib/models/wardrobe.dart`：将局部函数 `_stringList` 改为 `stringList`。
  - `ai_wardrobe_app/lib/ui/screens/capture/camera_capture_screen.dart`：删除未使用的 `isDark` 变量。
  - `ai_wardrobe_app/lib/ui/screens/capture/clothing_result_screen.dart`：让 `_currentWardrobeId` 真正参与“加入当前衣柜”的逻辑。
  - `ai_wardrobe_app/lib/ui/screens/capture/processing_screen.dart`：补全 `if` 语句花括号。
  - `ai_wardrobe_app/test/widget_test.dart`：删除未使用的 `material.dart` import。
- 优化 `WardrobeScreen` 状态体验：
  - 衣柜列表加载失败时，不再继续触发物品加载。
  - 显示错误卡片和 Retry 按钮。
  - 当前衣柜物品加载失败时保留错误状态与重试入口。
  - 搜索或分类筛选后无结果时显示“无匹配衣物”。
  - 提供“一键清除搜索和筛选”按钮。
  - 空衣柜状态继续保留“使用 Add 开始整理衣柜”的引导文案。
- 打磨 `WardrobeManagementScreen`：
  - 新建衣柜名称为空时，不再静默无反应，改为表单内错误提示。
  - 重命名衣柜时加入空名称校验。
  - 新旧名称相同时不发起无意义请求。
  - 删除衣柜确认文案加入衣柜名称和衣物数量。
  - 明确说明“衣物不会被删除，只会移除衣柜分组”。
  - 分享衣柜时加入异常捕获，失败会用 SnackBar 反馈。
- 补充 `app_strings.dart` 多语言文案：
  - `retry`
  - `wardrobeNameRequired`
  - `noMatchingClothes`
  - `clearSearchFilters`
  - `deleteWardrobeConfirmNamed`
- 运行 `dart format` 格式化改动文件。
- 再次运行 `flutter analyze`：
  - issues 从 87 降到 80。
  - 剩余主要为项目既有 deprecated/info，例如 `withOpacity`、`null-aware elements`、旧 `value` API 等。
  - 没有新增 linter error。

## 4. Module 3 WBS 对照

- **3.1 创建/重命名/删除衣柜**
  - `WardrobeManagementScreen` 支持创建、重命名、删除。
  - 创建/重命名增加名称校验。
  - 删除衣柜只移除衣柜分组，不删除衣物本体。
- **3.2 添加/移除服装**
  - `WardrobeScreen` 支持当前衣柜内衣物展示、搜索、分类和移除。
  - `ClothingResultScreen` 支持处理完成后加入当前衣柜。
  - `CurrentWardrobeController` 保持当前衣柜上下文。
- **3.3 虚拟衣柜**
  - 前端支持 `type=VIRTUAL` 衣柜展示。
  - 虚拟衣柜可用于 imported / non-owned item 的上下文浏览。
  - 前端已保留虚拟标签和不同来源衣物展示。

## 5. 个人贡献核对

### 5.1 前端项目初始化与基础框架

- 初始化 `ai_wardrobe` 项目结构，创建 Flutter 应用、组员 markdown 记录与根目录 README。
- 搭建 Flutter 前端主框架，完成五个主导航入口。
- 实现 Add BottomSheet。
- 设计并实现空状态页面。
- 实现全局明暗主题基础能力。

### 5.2 Web / 移动端响应式布局

- 完成移动端底部导航与 Web 端 `NavigationRail` 的布局区分。
- 优化 Web 端导航壳，去掉多余头部文字和图标。
- 补充 Flutter 运行指南，方便组员运行和调试前端。

### 5.3 基础用户流程

- 新增 SplashScreen。
- 新增 LoginScreen。
- 串联开屏、登录与主界面跳转流程。
- 为前期 demo 提供 Skip / Continue 入口。

### 5.4 多语言与界面文案

- 搭建中英文文案管理结构。
- 在 Profile 设置中加入语言切换入口。
- 将主要界面文案接入 `AppStringsProvider`。
- 在后续 Debug 中继续补充衣柜相关文案。

### 5.5 Module 3 衣柜管理

- 完成多衣柜管理界面。
- 完成衣柜主页展示和筛选。
- 完成当前衣柜状态同步。
- 补齐衣物处理结果页加入当前衣柜。
- 对 WBS 3.1 / 3.2 / 3.3 逐项核对。

### 5.6 前端 Debug 与质量改进

- 运行 `flutter analyze` 并修复部分真实 warning。
- 优化错误、空状态、筛选无结果状态。
- 优化表单校验和删除确认体验。
- 通过 `dart format` 和 `flutter analyze` 验证。

### 5.7 文档与协作记录

- 更新根目录 README。
- 更新 Flutter 运行与架构文档。
- 维护个人工作记录。
- 整理文档与实现之间的不协调点。
- FTR 过程中承担 Recorder 职责。

## 6. 不协调点与后续可做

- **Profile「已导入搭配」**：卡片无 onTap，未跳转到衣柜管理/虚拟衣柜，与“集中在这里管理”文案不一致。
- **前端设计想法文档**：早期文档仍写 `WardrobeScreen` 只做空状态，与当前已接 `WardrobeService` 和多衣柜实现不一致。
- **DATA_MODEL.md**：文档写“每个用户仅一个虚拟衣柜（自动创建）”；当前实现允许多个 `type=VIRTUAL` 衣柜，需要统一文档或逻辑。
- **API 响应格式**：部分文档写列表字段为 `wardrobes: []`，当前前端按 `items: []` 实现，需要与后端契约确认。
- **导航结构文档**：部分文档仍写“底部 3 区块”，实际是 5 个 tab，Add 为中间入口打开 sheet。
- **Analyze 剩余问题**：目前仍有 `withOpacity` deprecated、`null-aware elements`、旧 `value` API 等 info，可后续继续清理。