# AI Wardrobe Master - Backend Architecture

## Overview

当前后端使用 FastAPI，主功能已覆盖认证、衣物管理、衣柜管理、公开共享浏览、创作者资料、卡包、导入与可视化任务入口。  
本文档合并保留了早期后端架构设计、CAS 后续改造说明，以及 2026-04 新落地的共享子衣柜与 `/me` 用户态能力。

## Technology Stack

- FastAPI
- SQLAlchemy
- Alembic
- PostgreSQL
- Local file storage / S3-compatible storage
- JWT authentication
- Pillow / OpenCV
- Celery-based background work

## Project Structure

```text
backend/
├── app/
│   ├── api/
│   │   └── v1/
│   ├── core/
│   ├── crud/
│   ├── db/
│   ├── models/
│   ├── schemas/
│   └── services/
├── alembic/
│   └── versions/
├── tests/
└── scripts/
```

## Current Route Surface

主路由集中在 `backend/app/api/v1/`：

- `auth.py`
- `me.py`
- `clothing.py`
- `wardrobe.py`
- `files.py`
- `creators.py`
- `creator_items.py`
- `card_packs.py`
- `imports.py`
- `outfits.py`
- `outfit_preview.py`

## Implementation Notes Carried Forward

### 1. Unified clothing table

当前系统已经使用统一的 `clothing_items` 作为 canonical 衣物表：

- 原先独立的 `creator_items` 数据模型已被折叠进 `clothing_items`
- 对外仍可保留 `creator_items.py` 路由兼容层
- 发布可见性通过 `catalog_visibility` 表达

### 2. CAS and file serving

后端已在之前的改造中切换到内容寻址存储思路：

- 文件层通过 `/files/...` 业务路径暴露
- 调用方不直接依赖底层 blob hash
- 当前文档重点补充的是公开共享衣物图片的访问规则

### 3. Async boundaries

仍保留以下异步边界：

- `processing_tasks`：衣物处理
- `outfit_preview_tasks`：搭配预览

## April 2026 Implementation Status

### 1. Authentication and bootstrapping

`auth.py` 当前负责：

- 注册
- 登录
- 登出

关键实现点：

- 注册与登录后都会调用 `ensure_main_wardrobe`
- 登录响应会返回 `uid`
- `userType` 语义当前由客户端传值决定 `CONSUMER / CREATOR`

### 2. Unified current-user context

`me.py` 当前统一返回：

- 基础用户信息
- 创作者摘要
- capability flags

这使前端不需要在多处拼装状态，也解决了“登录后个人页仍显示未登录”的旧问题。

### 3. Wardrobe sharing architecture

`wardrobe.py` 已成为共享子衣柜能力的核心入口。

关键接口：

- `GET /wardrobes`
- `POST /wardrobes`
- `PATCH /wardrobes/{id}`
- `GET /wardrobes/public`
- `GET /wardrobes/by-wid/{wid}`
- `GET /wardrobes/by-wid/{wid}/items`
- `POST /wardrobes/export-selection`

关键原则：

- 对外分享对象统一为公开 `SUB` wardrobe
- 对外标识统一使用 `wid`
- Discover 与分享码访问都依赖 `wid`

### 4. Wardrobe model evolution

`models/wardrobe.py` 已支持以下字段：

- `wid`
- `parent_wardrobe_id`
- `outfit_id`
- `kind`
- `type`
- `source`
- `cover_image_url`
- `auto_tags`
- `manual_tags`
- `is_public`

### 5. Public browse and search

`crud/wardrobe.py` 当前公开搜索已经覆盖：

- wardrobe name
- `wid`
- description
- `ownerUid`
- `ownerUsername`
- `auto_tags`
- `manual_tags`

并且只返回公开 `SUB` wardrobe。  
这正是 Discover 合并 `packs` 与 `wardrobes` 后的数据基础。

### 6. Card pack publication mapping

`crud/card_pack.py` 当前已把 card pack 发布与共享 wardrobe 建立双向联动：

- 发布 pack：创建或复用公开 `SUB` wardrobe
- 该 wardrobe `source = CARD_PACK`
- 该 wardrobe `is_public = true`
- 归档 pack：将对应 wardrobe 重新隐藏

### 7. Shared file access control

`files.py` 本轮修复的重点在图片权限：

- 旧逻辑只允许衣物所有者访问图片
- 新逻辑通过 `_can_view_shared_clothing_item` 判断：
  - 所有者本人可访问
  - 若衣物属于公开 `SUB` wardrobe，其他账号也可访问
  - 私有衣物仍不可见

## Services and Responsibilities

### Auth and identity

- JWT 签发与校验
- 当前用户解析
- 主衣柜初始化

### Clothing pipeline

- 上传
- 处理任务排队
- 标签确认
- 详情读取与删除

### Wardrobe management

- 创建和编辑衣柜
- 添加 / 移动 / 复制衣物关联
- 导出选择结果到子衣柜
- 公开共享浏览

### Public content

- 创作者资料
- creator facade item
- card pack 发布与归档
- import history

### Visualization-related backend

- outfit 保存
- outfit preview task 接口

当前说明：

- `Face + Scene` 前端 demo 已接好入口
- 真实生成模型尚未在后端完成部署

#### DashScope outfit preview 调用约定

Outfit preview 使用 DashScope `wan2.6-image` 时，需要区分两种调用方式：

- HTTP JSON 直调 `/api/v1/services/aigc/multimodal-generation/generation` 时，`content[].image` 必须是 DashScope 服务端可下载的 HTTP(S) URL。直接传后端本机的 `file://...` 路径会失败，DashScope 服务端无法读取本机文件。
- DashScope Python SDK 支持 `file://` 本地文件路径。SDK 会在请求前识别本地文件，并先上传到 DashScope 文件中转 OSS，再把可访问的临时文件 URL 放入模型请求。因此如果 backend worker 使用本地 CAS 文件作为输入，应优先走 SDK 调用，而不是手写 HTTP JSON 请求。

本地路径格式要求：

```text
file://test/image/car.webp
file://test/image/paint.webp
```

相对路径相对于当前 Python 进程的工作目录解析；生产代码应确保 worker 的 `cwd` 可预测，或者用 `Path(...).resolve().as_uri()` 生成绝对 `file://` URI 后交给 SDK。不要把 `file://` URI 直接传给 HTTP JSON endpoint。

当前 CAS 文件仍通过 `blob_hash -> BlobStorage.path_for(blob_hash)` 找到本地物理文件。DashScope SDK 调用应在 worker 内部用该本地路径构造 `file://...`，由 SDK 负责上传。若未来切到 S3/OSS 存储，也可以改用 storage presigned URL 直接走 HTTP JSON。

## Data Ownership Rules

1. 删除 wardrobe 不自动删除 `ClothingItem`
2. 从子衣柜移除衣物，只删除 `WardrobeItem` 关联
3. 从主衣柜执行删除，才是删除衣物实体
4. 公开共享不改变衣物所有权
5. 公开共享只扩大读取权限，不扩大写权限

## Real-Device Validation Notes

当前真机联调链路为：

1. 启动本地后端
2. Android 设备 USB 连接到 Windows
3. 执行 `adb reverse tcp:8000 tcp:8000`
4. Flutter 真机访问 `127.0.0.1:8000`

这条链路已用于验证：

- 跨账号公开共享浏览
- 共享图片访问
- 个人页登录态
- Discover 搜索和跳转

## Remaining Gaps

- 真实的 `Face + Scene` 生成模型仍未在后端部署
- 创作者与普通用户的更细颗粒业务规则仍可继续扩展
- 性能与缓存策略仍有优化空间，但不影响当前共享链路功能闭环
