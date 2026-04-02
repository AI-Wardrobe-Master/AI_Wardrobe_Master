# Code Implementation Agent Guide

## 1. 文档目的

本文档用于定义 agent 在当前后端功能开发流水线中的职责、位置、目标，以及下一阶段需要修改的代码范围与实现指导。

这里的 agent 不是产品规划 agent，也不是评审 agent，而是**代码实现 agent**。

它的主要职责是：

- 根据已有设计文档与已完成代码现状推进后端实现
- 在明确边界内修改模型、CRUD、schema、route、service、task、migration 与测试
- 保证实现顺序符合依赖关系，而不是跳过中间层直接实现下游能力
- 在没有部署服务器的情况下，使用本地与 Docker 环境完成验证

---

## 2. Agent 在整个流水线中的位置

当前流水线建议拆成 5 个角色：

1. 需求与架构定义
2. 缺失能力评审
3. 实现规划
4. **代码实现**
5. 本地 / Docker 验证与回归

本 agent 处于第 4 步，紧接第 3 步之后，并对第 5 步负责。

也就是说，它的输入不是原始模糊需求，而是：

- 已存在的产品与接口文档
- `groupmembers'markdown/backend_incomplete_review.json` 中的未完成项
- 已经落地的代码状态
- 前一轮已经确认的实现顺序

它的输出也不是抽象方案，而是：

- 实际代码改动
- migration
- 测试
- 可执行的本地 / Docker 验证结果

---

## 3. Agent 的核心目标

当前阶段，这个代码实现 agent 的目标不是“一次性补齐所有缺失功能”，而是按依赖顺序稳定推进。

### 当前总目标

围绕 Creator Content 这条主链路，把后端从“有 creator 基础能力”推进到“可创建并发布 Card Pack”。

### 当前迭代目标

在已完成 `creator_profiles`、`creator_items`、`GET /me` 和 creator 权限校验的基础上，继续实现：

- `card_packs`
- `card_pack_items`
- pack 创建 / 查询 / 更新 / 删除
- pack 发布 / 归档
- 公开分享读取能力

### 非目标

本阶段不处理以下内容：

- `imports`
- `import_histories`
- imported clothing provenance 回填
- `virtual_wardrobe_service`
- outfit 持久化
- creator dashboard 统计

这些能力依赖 Pack 已经可发布，因此不应提前落地。

---

## 4. 当前已完成的上游能力

根据前面的对话与当前代码状态，以下 creator foundation 已经实现：

- `creator_profiles`
- `creator_items`
- `GET /me`
- `get_current_creator_user_id`
- creator 公开资料查询
- creator item 的创建、读取、更新、删除
- creator item 处理流水线

当前可见代码入口包括：

- [backend/app/api/v1/me.py](/mnt/d/ai_wardrobe_master/backend/app/api/v1/me.py)
- [backend/app/api/v1/creators.py](/mnt/d/ai_wardrobe_master/backend/app/api/v1/creators.py)
- [backend/app/api/v1/creator_items.py](/mnt/d/ai_wardrobe_master/backend/app/api/v1/creator_items.py)
- [backend/app/models/creator.py](/mnt/d/ai_wardrobe_master/backend/app/models/creator.py)
- [backend/app/crud/creator.py](/mnt/d/ai_wardrobe_master/backend/app/crud/creator.py)
- [backend/app/crud/creator_item.py](/mnt/d/ai_wardrobe_master/backend/app/crud/creator_item.py)
- [backend/app/services/creator_pipeline.py](/mnt/d/ai_wardrobe_master/backend/app/services/creator_pipeline.py)
- [backend/app/services/creator_processing_task_service.py](/mnt/d/ai_wardrobe_master/backend/app/services/creator_processing_task_service.py)
- [backend/app/tasks.py](/mnt/d/ai_wardrobe_master/backend/app/tasks.py)

因此，下一步不应该重新设计 creator 基础层，而应直接在其之上补齐 Pack 层。

---

## 5. 为什么下一步是 Card Pack

从依赖关系看，`card_packs` 是 creator 域与 consumer 导入域之间的中间层。

数据链路如下：

`creator_profiles`
-> `creator_items`
-> `card_packs` + `card_pack_items`
-> `PUBLISHED pack`
-> `imports`
-> `virtual wardrobe`

因此：

- 没有 `card_packs`，就无法发布 creator 内容
- 没有 `PUBLISHED pack`，就无法定义 import 行为
- 没有稳定的 pack 状态机，`imports` 和 provenance 设计会反复返工

所以本 agent 当前最合理的实现目标是：**先把 Pack 层做完整，再做 imports 与 virtual wardrobe。**

---

## 6. 本阶段需要修改的代码范围

### 6.1 数据模型

需要在 [backend/app/models/creator.py](/mnt/d/ai_wardrobe_master/backend/app/models/creator.py) 中继续增加：

- `CardPack`
- `CardPackItem`

建议字段：

`CardPack`

- `id`
- `creator_id`
- `name`
- `description`
- `type`
- `status`，状态值：`DRAFT | PUBLISHED | ARCHIVED`
- `cover_image_storage_path`
- `share_id`
- `published_at`
- `archived_at`
- `import_count`
- `created_at`
- `updated_at`

`CardPackItem`

- `id`
- `card_pack_id`
- `creator_item_id`
- `sort_order`
- `created_at`

关键约束：

- 一个 pack 内 `creator_item_id` 不可重复
- `share_id` 唯一
- `sort_order` 必须稳定可排序
- `creator_id` 需要能快速按 owner 查询

### 6.2 数据迁移

新增 Alembic migration，创建：

- `card_packs`
- `card_pack_items`

并确保：

- 状态字段有约束
- 唯一索引完整
- 与 `creator_items`、`creator_profiles` 的外键关系正确

### 6.3 CRUD

新增：

- [backend/app/crud/card_pack.py](/mnt/d/ai_wardrobe_master/backend/app/crud/card_pack.py)

建议包含：

- `create_card_pack`
- `get_owned_card_pack`
- `get_public_card_pack`
- `list_creator_card_packs`
- `update_card_pack`
- `replace_card_pack_items`
- `publish_card_pack`
- `archive_card_pack`
- `delete_card_pack`

约束原则：

- Creator 侧一律按 `creator_id + pack_id` 查询，避免越权
- 非 owner 返回 `404`
- 对外查询只能读 `PUBLISHED`

### 6.4 API schema

新增：

- [backend/app/schemas/card_pack.py](/mnt/d/ai_wardrobe_master/backend/app/schemas/card_pack.py)

至少包含：

- `CardPackCreate`
- `CardPackUpdate`
- `CardPackItemSummary`
- `CardPackDetail`
- `CardPackListItem`
- `CardPackListResponse`
- `CardPackPublishResponse`

### 6.5 API route

新增：

- [backend/app/api/v1/card_packs.py](/mnt/d/ai_wardrobe_master/backend/app/api/v1/card_packs.py)

并在 [backend/app/api/v1/router.py](/mnt/d/ai_wardrobe_master/backend/app/api/v1/router.py) 注册。

本阶段建议实现的接口：

- `POST /card-packs`
- `GET /card-packs/{id}`
- `GET /card-packs/share/{share_id}`
- `GET /creators/{creator_id}/card-packs`
- `PATCH /card-packs/{id}`
- `POST /card-packs/{id}/publish`
- `POST /card-packs/{id}/archive`
- `DELETE /card-packs/{id}`

### 6.6 Service 层

如果 route 中出现以下逻辑，必须上收至 service：

- publish 前校验
- share id 生成
- pack item 替换事务
- 状态机跳转

建议新增：

- `backend/app/services/card_pack_service.py`

### 6.7 测试

新增：

- `backend/tests/test_card_pack_flow.py`

至少覆盖：

- creator 创建 pack
- 非 creator 无法创建
- pack 内 item 重复时报错
- 非本人无法读取或修改私有 draft pack
- `DRAFT -> PUBLISHED -> ARCHIVED` 成功路径
- 空 pack 不能 publish
- item 未处理完成不能 publish
- `PUBLISHED` 后不能再改 item 集合
- 公开 share 查询只能读 `PUBLISHED`
- 删除 creator item 时，若 item 属于已发布 pack，需要返回明确 `409` 提示
- owner 删除已发布 pack 的路径可用
- 关键状态流转的并发冲突会回滚并返回 `409`

---

## 7. 代码实现指导

### 7.1 实现原则

- 沿用现有目录结构，不把 Pack 逻辑硬塞进 `creator.py` route
- route 只做鉴权、入参解析、响应组装
- 业务校验与事务放 service / crud
- 不为了赶进度直接把 pack 逻辑散落在 route 中

### 7.2 状态机必须清晰

`CardPack.status` 只允许：

- `DRAFT`
- `PUBLISHED`
- `ARCHIVED`

允许跳转：

- `DRAFT -> PUBLISHED`
- `PUBLISHED -> ARCHIVED`

不允许：

- 直接 `DRAFT -> ARCHIVED` 之外的隐式删除替代发布
- `ARCHIVED -> DRAFT`
- `PUBLISHED` 后继续自由修改 item 集合

### 7.3 publish 前校验

publish 时至少校验：

- pack 至少有 1 个 item
- 所有 item 均属于当前 creator
- 所有 item 已处理完成
- 当前 creator profile 处于有效状态

publish 成功后应落库：

- `status = PUBLISHED`
- `share_id`
- `published_at`

### 7.4 owner 与 public 查询边界

内部查询与公开查询必须拆开。

不要使用“先查任意 pack，再在响应层判断要不要返回”的写法。应在查询阶段直接区分：

- owner 可读任意状态
- public 只能读 `PUBLISHED`

### 7.5 删除与修改规则

当前实现已确定：

- `DRAFT` 可修改 metadata 与 `itemIds`
- `PUBLISHED` 不可修改 `itemIds`，但当前实现仍允许有限 metadata 更新
- `ARCHIVED` 不可更新
- owner 可删除任意状态的 pack，用于支持“先删已发布 pack，再删除 pack 内 creator item”的管理链路
- 删除 creator item 时，如果该 item 仍属于某个已发布 pack，接口应返回明确提示：
  - `Creator item belongs to a published pack. Delete the published pack first.`

给前端的直接含义：

- pack 管理页不能把“删除 pack”只做成草稿态入口
- creator item 删除弹窗需要能承接上述 `409`，并引导用户先处理 pack
- 不能在前端本地假设“发布后完全不可编辑”，应以后端返回为准

### 7.6 并发与错误处理

当前实现策略：

- `PATCH /card-packs/{id}`
- `POST /card-packs/{id}/publish`
- `POST /card-packs/{id}/archive`
- `DELETE /card-packs/{id}`
- `DELETE /creator-items/{id}`

上述入口在读取 owner 资源时使用行锁，避免状态检查与提交之间被并发请求打穿。

同时，涉及唯一约束或事务冲突的 `flush/commit` 需要：

- `rollback`
- 返回 `409`
- 使用可直接展示给前端的 detail 文案

给前端的直接含义：

- 这类 `409` 更接近“状态已变化，请刷新后重试”，不是“后端挂了”
- 发布、归档、删除按钮在收到 `409` 后应保留当前页并触发数据刷新

这样能减少后续 import 语义漂移。

---

## 8. 本地与 Docker 验证要求

当前没有部署服务器，因此代码实现 agent 必须把 Docker 视为准运行环境。

最少验证包括：

### 8.1 Migration 验证

- 容器启动后 migration 能执行到最新 revision
- `card_packs`、`card_pack_items` 表成功创建

### 8.2 自动化验证

至少运行：

- `tests/test_creator_foundation.py`
- 新增的 `tests/test_card_pack_flow.py`
- 与鉴权相关的基础测试

### 8.3 API 冒烟验证

在 Docker 中使用真实 HTTP 请求完成：

1. 登录 demo creator
2. 创建 creator item
3. 创建 pack
4. publish pack
5. 用公开接口读取 pack
6. archive pack

### 8.4 数据库校验

通过 SQL 或 ORM 确认：

- `card_pack_items` 顺序正确
- `share_id` 已生成
- `published_at` / `archived_at` 正确写入
- 状态跳转后数据一致

---

## 9. Agent 的交付标准

当本阶段完成时，代码实现 agent 应交付：

- 可运行的 `card_packs` 模型与 migration
- CRUD / service / route / schema 完整代码
- 覆盖主流程和关键失败路径的测试
- Docker 下可重复执行的验证步骤
- 更新后的实现状态文档或 review 文件

满足以下条件时，才能认为本阶段完成：

1. creator 可以基于自己的 `creator_items` 创建 draft pack
2. draft pack 可以被读取、修改、删除
3. pack 能成功 publish 并生成公开分享入口
4. 匿名用户只能读取 `PUBLISHED` pack
5. published pack 可以 archive
6. 验证结果可在本地 Docker 里复现

---

## 10. 下一阶段衔接

当 `card_packs` 稳定后，下一阶段才进入：

- `POST /imports/card-pack`
- `import_histories`
- imported clothing provenance
- `virtual_wardrobe_service`

也就是说，Pack 层完成后，这个 agent 的后续目标会从“发布平台内容”切换为“将平台内容安全导入用户域”。

在那之前，不应跳过 Pack 直接实现 import。
