# AI Wardrobe Master - Documentation Overview

## 文档结构

```text
documents/
├── README.md
├── TECH_STACK.md
├── USER_STORIES.md
├── DATA_MODEL.md
├── API_CONTRACT.md
├── BACKEND_ARCHITECTURE.md
├── FLUTTER_ARCHITECTURE.md
├── FLUTTER_GUIDE_ZH.md
├── FLUTTER_GUIDE_EN.md
└── archive/
```

## 当前维护原则

- 以仓库当前实现为准，不再把早期草案当作主规范
- 顶层文档持续维护，`archive/` 只做历史追溯
- 本轮文档同步基于主分支最新实现 `e4e6a9f`

## 2026-04 最新实现同步

本轮文档已经同步以下实际功能状态：

- 认证与用户态：`/auth/register`、`/auth/login`、`/auth/logout`、`/me`
- 个人页修正：登录后不再显示 `not signed in`
- 子衣柜公开分享：公开对象统一为 `SUB` wardrobe，并以 `wid` 对外标识
- Discover 合并：公开 `packs` 与共享 `wardrobes` 统一在 `Wardrobes` tab 展示
- 共享检索：支持按 `wid`、`ownerUid`、`ownerUsername`、名称、描述、标签搜索
- 共享详情：共享衣柜内的衣物卡可点开，只读详情页可跨账号查看图片
- 图片权限：公开共享衣物图片可被其他账号访问，私有衣物仍受保护
- 删除语义：主衣柜长按为真实删除并清缓存，子衣柜长按为解除关联
- 可视化入口：`Visualize` 升级为 `Canvas Studio` + `Face + Scene` 双模式
- 真机联调：Android 实机已通过本地后端 + `adb reverse` 验证共享链路

## 文档用途

### `USER_STORIES.md`

描述当前产品需求、关键用户故事和本轮新增验收点，重点覆盖：

- 公开子衣柜分享
- Discover 搜索
- 共享衣物只读详情
- `/me` 驱动的用户态展示
- `Face + Scene` demo 可视化流程

### `DATA_MODEL.md`

描述当前后端与前端共同依赖的数据结构，重点包括：

- `User.uid`
- `Wardrobe.wid`
- `Wardrobe.kind / type / source / isPublic`
- 卡包发布与公开子衣柜的映射关系

### `API_CONTRACT.md`

描述实际接口行为，重点包括：

- 最新本地开发地址 `http://localhost:8000/api/v1`
- `/me` 返回结构
- 公开衣柜浏览与 `by-wid` 查询接口
- 共享衣物图片访问权限规则

### `BACKEND_ARCHITECTURE.md`

描述当前 FastAPI 实现边界，重点包括：

- 认证与主衣柜自动创建
- 公开共享衣柜查询
- 卡包发布与共享子衣柜同步
- `/files` 对公开共享图片的访问控制

### `FLUTTER_ARCHITECTURE.md`

描述当前 Flutter 真实页面结构，重点包括：

- `Wardrobe / Discover / Add / Visualize / Profile`
- `VisualizationHubScreen`
- `SharedWardrobeDetailScreen`
- 本地缓存与远端同步策略

### `FLUTTER_GUIDE_ZH.md`

描述实际开发和真机联调方式，已补充：

- Windows + Android 真机运行步骤
- 本地后端联调时的 `adb reverse tcp:8000 tcp:8000`
- Docker 后端先启动的注意事项

## 建议阅读顺序

1. 先看 `README.md`
2. 再看 `USER_STORIES.md`
3. 再看 `DATA_MODEL.md`
4. 接着看 `API_CONTRACT.md`
5. 最后按职责分工阅读 `BACKEND_ARCHITECTURE.md` 或 `FLUTTER_ARCHITECTURE.md`

## 归档说明

`archive/` 下的文档保留历史设计过程，但如果与顶层文档冲突，应以顶层文档为准。

## 备注

这次文档更新不是把仓库原有文档另起炉灶，而是将原有结构、原始模块划分和 2026-04 实际完成的共享链路改动合并进同一套规范中。
