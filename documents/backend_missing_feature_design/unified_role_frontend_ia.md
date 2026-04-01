# Unified Role Frontend IA

## 1. 文档目标

这份文档把 [unified_role_ui_design.md](/mnt/d/ai_wardrobe_master/documents/backend_missing_feature_design/unified_role_ui_design.md) 里的策略继续细化成前端可落地的信息架构。

目标不是直接出视觉稿，而是先回答 4 个问题：

1. 统一界面的一级导航怎么定
2. 普通用户、申请中用户、已开通发布能力用户分别看到什么
3. 哪些创作者能力应该放在 `Discover`，哪些应该放在 `Profile`
4. 前端需要什么用户态接口来驱动显示

## 2. 设计前提

基于当前仓库，以下事实已经成立：

- 当前主导航已是统一壳，[root_shell.dart](/mnt/d/ai_wardrobe_master/ai_wardrobe_app/lib/ui/root_shell.dart)
- 当前主页面是 `Wardrobe / Discover / Outfit / Profile`
- `Discover` 目前是创作者内容预留页，[discover_screen.dart](/mnt/d/ai_wardrobe_master/ai_wardrobe_app/lib/ui/screens/discover_screen.dart)
- `Profile` 当前承载个人资料与虚拟衣橱入口，[profile_screen.dart](/mnt/d/ai_wardrobe_master/ai_wardrobe_app/lib/ui/screens/profile_screen.dart)

所以这份 IA 设计的核心原则是：

- 不推翻已有主导航
- 通过页面内分区和能力显隐实现“同壳不同能力”

## 3. 一级导航

建议继续保留四个一级导航，不新增单独的“Creator”一级 Tab。

### 3.1 `Wardrobe`

职责：

- 查看 owned 衣物
- 查看 imported 衣物
- 进入 virtual wardrobe
- 进行搜索、筛选、分类确认

原因：

- 这是所有用户的核心资产管理区
- 即便是创作者，也仍然需要消费侧衣橱能力

### 3.2 `Discover`

职责：

- 浏览创作者和 Card Pack
- 处理分享链接导入
- 承接创作者内容运营入口

原因：

- 这是统一内容生态入口
- 对普通用户是“逛”
- 对创作者是“发布内容与管理内容的前台入口”

### 3.3 `Outfit`

职责：

- 组合 owned + imported 衣物
- 保存 Outfit
- 查看已保存搭配

原因：

- 这是跨身份共享的使用场景
- 没必要按身份拆分

### 3.4 `Profile`

职责：

- 个人资料
- 账号设置
- 身份升级
- 创作者中心

原因：

- 最适合承接用户状态变化
- 最适合放“开通发布能力”和“管理个人发布资料”

## 4. 用户状态分层

前端不要只看 `type == CREATOR`。建议最少区分 4 种显示状态。

### 4.1 State A: 普通用户

定义：

- 已登录
- 没有创作者资料
- 没有发布能力

可见重点：

- 正常衣橱、Discover、Outfit、Profile
- Profile 中出现“开通发布能力”入口

不可见：

- 发布 Pack
- 我的内容管理
- 创作者数据页

### 4.2 State B: 创作者申请中

定义：

- 已提交开通申请
- 尚未生效

可见重点：

- 保持普通用户全部能力
- Profile 中显示申请状态卡片
- 创作者入口可见但禁用

不可见或禁用：

- 真正的发布动作
- Card Pack 创建提交

### 4.3 State C: 已开通发布能力

定义：

- creator profile 已存在
- 可以发布 Creator Item / Card Pack

可见重点：

- Discover 中出现“我的内容”
- Profile 中出现“创作者中心”
- 可创建 Pack、编辑 Creator Profile、查看我的 Pack

### 4.4 State D: 创作者受限

定义：

- 账号仍存在创作者资料
- 但当前发布能力被暂停

可见重点：

- 原入口仍可见
- 但顶部有状态提示
- 所有发布相关 CTA 禁用

原因：

- 避免用户误以为功能消失
- 更适合后续治理和申诉流程

## 5. 页面级 IA 设计

## 5.1 Wardrobe

建议结构：

1. 顶部搜索区
2. 分类筛选区
3. Owned / Imported 快捷切换
4. 衣橱列表
5. Virtual Wardrobe 入口

### 所有人都能看到

- 我的衣物
- 搜索
- 标签筛选
- Virtual Wardrobe

### 创作者不额外增强

这里不建议把“Creator Catalog 管理”塞进 Wardrobe。

原因：

- 个人衣橱和平台发布资产是两种不同语义
- 混在一起以后，筛选、权限和用户理解都会变复杂

建议 Creator Catalog 单独属于 `Discover -> 我的内容`。

## 5.2 Discover

这是统一界面里最关键的页面。

建议分为 4 个区块：

### A. 推荐内容区

所有人可见：

- 推荐 Creator
- 热门 Card Pack
- 分享链接导入入口

### B. 我的导入区

所有人可见：

- 最近导入的 Pack
- 进入 Virtual Wardrobe 的快捷入口

### C. 创作者工作区

仅开通发布能力的用户可见：

- 我的内容
- 新建 Card Pack
- 管理 Creator Items
- 最近发布表现

### D. 状态引导区

按状态显示：

- 普通用户：显示“成为创作者”
- 申请中：显示“申请审核中”
- 已开通：显示“继续发布”
- 受限：显示“当前发布能力受限”

### 推荐布局

普通用户：

- 内容推荐优先
- 导入入口次之
- 创作者入口只作为轻提示

创作者：

- 顶部仍先看到内容生态
- 下方增加“我的内容工作区”

这样可以避免页面变成纯后台。

## 5.3 Outfit

建议结构：

1. 已选衣物区域
2. 画布区域
3. 来源筛选：Owned / Imported / All
4. 保存 / 更新 Outfit
5. 已保存 Outfit 列表

所有用户结构一致，不按身份拆分。

理由：

- Outfit 是消费能力，不是创作者专属能力
- 创作者同样会使用这个能力

## 5.4 Profile

这是统一界面的第二关键页。

建议分成五个区块：

### A. 个人资料区

所有人可见：

- 头像
- 用户名
- 基础介绍

### B. 个人统计区

所有人可见：

- Clothes 数量
- Outfits 数量
- Imported Packs 数量

### C. 身份状态区

按状态显示：

- 普通用户：显示“开通发布能力”
- 申请中：显示审核状态和说明
- 已开通：显示 Creator 身份标签
- 受限：显示限制说明

### D. 创作者中心区

仅已开通发布能力可见：

- 编辑创作者资料
- 我的 Card Packs
- 我的 Creator Items
- 发布数据概览

### E. 设置区

所有人可见：

- 语言
- 主题
- 账号设置

## 6. 推荐入口设计

## 6.1 主导航不加 Creator Tab

不建议一开始就加第五个 `Creator` Tab。

原因：

- 当前四个导航已经足够
- Creator 能力还没重到需要独立一级入口
- 过早加 Tab 会让普通用户觉得产品重心不清楚

## 6.2 创作者入口放在哪里

建议双入口，但都不做一级导航：

### 入口 1：`Profile -> 创作者中心`

这是最稳定的入口。

适合：

- 资料编辑
- 身份状态查看
- 进入 Pack 管理

### 入口 2：`Discover -> 我的内容`

这是更偏业务运营的入口。

适合：

- 创建 Pack
- 查看最近内容表现
- 快速返回内容工作区

## 7. 关键页面流转

## 7.1 普通用户升级为创作者

推荐路径：

1. 进入 `Profile`
2. 点击“开通发布能力”
3. 填写基础创作者资料
4. 进入申请中状态
5. 通过后，`Profile` 与 `Discover` 自动出现创作者入口

## 7.2 创作者发布内容

推荐路径：

1. 进入 `Discover`
2. 打开“我的内容”
3. 上传 Creator Item
4. 创建 Card Pack
5. 发布

这里不建议从 `Wardrobe` 直接发起内容发布。

## 7.3 普通用户导入内容

推荐路径：

1. 进入 `Discover`
2. 浏览 Pack 或打开分享链接
3. 预览内容
4. 点击导入
5. 自动进入 Virtual Wardrobe

## 8. 前端所需接口

为了支撑这套 IA，前端至少需要一个统一的用户态接口。

## 8.1 `GET /me`

推荐返回：

```json
{
  "success": true,
  "data": {
    "id": "user-123",
    "username": "alice",
    "email": "alice@example.com",
    "type": "CONSUMER",
    "creatorProfile": {
      "exists": true,
      "status": "ACTIVE",
      "displayName": "Alice Looks",
      "brandName": "Alice Studio"
    },
    "capabilities": {
      "canApplyForCreator": false,
      "canPublishItems": true,
      "canCreateCardPacks": true,
      "canEditCreatorProfile": true,
      "canViewCreatorCenter": true
    }
  }
}
```

### 为什么这里只返回 `capabilities`

这里不建议让后端再返回 `entryHints` 一类的展示提示。

原因是：

- `capabilities` 是领域事实，`entryHints` 本质上是前端信息架构和展示策略。
- 同一组 capability，在 `Discover`、`Profile`、Web 端、Flutter 端里的显示方式可能不同，不应该绑死在后端契约里。
- 如果后续需要做灰度、AB test 或运营位调整，更适合走前端配置或远程配置，而不是污染 `GET /me` 的领域接口。

因此，这个接口应该只返回：

- 用户基础身份信息
- creator profile 摘要
- capability 集合

至于“在哪个页面展示入口”“展示成 Banner 还是卡片”，由前端根据 capability 自己推导。

## 8.2 `GET /creators/me/profile`

如果 `GET /me` 只返回轻量状态，则可以再补一个创作者详情接口：

- 返回完整创作者资料
- 供 `Profile -> 创作者中心` 使用

## 8.3 `GET /creators/me/dashboard`

推荐做轻量统计接口，供 Discover 和 Profile 中的创作者模块使用：

- packCount
- publishedPackCount
- importCount
- draftCount

## 9. 前端组件建议

为了避免后续页面分裂，建议做下面几类通用组件。

### 9.1 `CapabilityGate`

作用：

- 根据 capability 或 creator status 控制显隐

用途：

- 创作者入口卡片
- 发布按钮
- 创作者中心模块

### 9.2 `CreatorStatusCard`

作用：

- 统一展示 `NOT_ENABLED / PENDING / ACTIVE / SUSPENDED`

放置位置：

- Profile 顶部
- Discover 内引导区

### 9.3 `EntryCard`

作用：

- 用统一样式承载“我的内容”“申请创作者”“虚拟衣橱”等二级入口

这样 UI 会更整齐，不会出现每页都各写一套入口样式。

## 10. 推荐实施顺序

### 第一阶段

只做前端结构性准备：

- 保持现有四个一级导航
- 增加 `GET /me`
- 在前端建立统一用户态模型

### 第二阶段

改造 `Profile`：

- 申请开通
- 创作者资料编辑
- 我的 Pack 列表

### 第三阶段

改造 `Discover`：

- 加“我的内容”区
- 查看分享数据

### 第四阶段

再考虑是否需要补一个二级的独立页面：

- `Creator Center`
- `My Packs`
- `Creator Items`

这些页面可以存在，但不必升成一级导航。

## 11. 最终建议

对这个项目，前端 IA 最稳的方案是：

- 保留现有统一壳
- 不拆双端
- 不新增独立 Creator 主导航
- 用 `Discover + Profile` 承接创作者能力
- 用 capability 驱动显隐

可以把最终原则浓缩成一句话：

> 主导航统一，内容生态集中在 Discover，身份与能力管理集中在 Profile，创作者能力通过二级入口渐进展开。
