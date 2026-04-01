# Backend Missing Feature API Design

## 1. Scope

本设计覆盖 `groupmembers'markdown/backend_incomplete_review.json` 中提到的所有未完成后端能力：

- `BE-007` 上传入口缺少前置文件校验
- `BE-008` Outfit 持久化与缩略图接口缺失
- `BE-009` Creator / Card Pack / Browse / Import 平台内容能力缺失
- `BE-010` imported item 的 provenance 追踪字段缺失
- `BE-011` Virtual Wardrobe 自动创建与系统托管逻辑缺失

## 2. Design Principles

1. 尽量复用现有 `clothing_items + images + model_3d + processing_tasks` 主链路。
2. 导入内容不直接复用创作者的衣物记录，而是生成当前用户私有的 `IMPORTED` 副本。
3. Virtual Wardrobe 是系统资源，不要求前端先创建。
4. Outfit、Import 都是事务性聚合，不能继续沿用“每个 CRUD 方法各自 commit”的方式。
5. 尽量遵循现有 API 契约中的路径和字段命名，新增接口只补文档没有覆盖的缺口。

## 3. Data Model Changes

### 3.1 Extend Existing Tables

#### `clothing_items`

新增字段：

| Field | Type | Description |
| --- | --- | --- |
| `catalog_visibility` | `VARCHAR(20)` nullable | `PRIVATE` / `PACK_ONLY` / `PUBLIC`。仅 Creator Catalog 使用。 |
| `origin_clothing_item_id` | `UUID` nullable FK | imported 副本对应的原始 Creator Item。 |
| `origin_creator_id` | `UUID` nullable FK -> `users.id` | imported 内容来源创作者。 |
| `origin_card_pack_id` | `UUID` nullable FK -> `card_packs.id` | imported 内容来源 Pack。 |
| `origin_import_history_id` | `UUID` nullable FK -> `import_histories.id` | 导入批次。 |
| `imported_at` | `TIMESTAMP` nullable | 导入完成时间。 |

说明：

- `source` 仍沿用当前语义，但限制为用户域可见值：`OWNED` / `IMPORTED`。
- Creator 上传到平台的衣物仍使用 `clothing_items` 存储，但由 `users.user_type == CREATOR` 与 `catalog_visibility` 决定其是否属于平台目录。
- 搜索仍基于 `final_tags`，不需要为 provenance 另建检索表。

#### `wardrobes`

新增字段：

| Field | Type | Description |
| --- | --- | --- |
| `is_system_managed` | `BOOLEAN` default `false` | 是否为系统托管衣橱。 |
| `system_key` | `VARCHAR(50)` nullable | 当前只使用 `DEFAULT_VIRTUAL_IMPORTED`. |

约束：

- 对同一 `user_id`，`system_key='DEFAULT_VIRTUAL_IMPORTED'` 只能有一条记录。
- `is_system_managed=true` 的衣橱不允许重命名、删除或改类型。

### 3.2 New Tables

#### `creator_profiles`

| Field | Type | Description |
| --- | --- | --- |
| `user_id` | `UUID` PK/FK -> `users.id` | 与用户一对一。 |
| `display_name` | `VARCHAR(120)` | 对外展示名。 |
| `brand_name` | `VARCHAR(120)` nullable | 品牌名。 |
| `bio` | `TEXT` nullable | 简介。 |
| `avatar_storage_path` | `TEXT` nullable | 头像。 |
| `website_url` | `TEXT` nullable | 官网。 |
| `social_links` | `JSONB` | 社媒链接。 |
| `is_verified` | `BOOLEAN` | 是否认证。 |
| `verified_at` | `TIMESTAMP` nullable | 认证时间。 |
| `created_at` / `updated_at` | `TIMESTAMP` | 审计字段。 |

#### `card_packs`

| Field | Type | Description |
| --- | --- | --- |
| `id` | `UUID` PK | Pack 主键。 |
| `creator_id` | `UUID` FK -> `users.id` | 所属创作者。 |
| `name` | `VARCHAR(160)` | Pack 名称。 |
| `description` | `TEXT` nullable | Pack 描述。 |
| `type` | `VARCHAR(40)` | 例如 `CLOTHING_COLLECTION`。 |
| `status` | `VARCHAR(20)` | `DRAFT` / `PUBLISHED` / `ARCHIVED`。 |
| `cover_image_path` | `TEXT` nullable | Cover 图。 |
| `share_id` | `VARCHAR(64)` unique | 对外分享标识。 |
| `import_count` | `INTEGER` default `0` | 被导入次数。 |
| `published_at` | `TIMESTAMP` nullable | 发布时间。 |
| `created_at` / `updated_at` | `TIMESTAMP` | 审计字段。 |

#### `card_pack_items`

| Field | Type | Description |
| --- | --- | --- |
| `id` | `UUID` PK | Pack item 主键。 |
| `card_pack_id` | `UUID` FK | 所属 Pack。 |
| `clothing_item_id` | `UUID` FK | Creator Item。 |
| `display_order` | `INTEGER` | Pack 内展示顺序。 |
| `notes` | `TEXT` nullable | Pack 内备注。 |

唯一约束：

- `(card_pack_id, clothing_item_id)` 唯一。

#### `import_histories`

| Field | Type | Description |
| --- | --- | --- |
| `id` | `UUID` PK | 导入批次。 |
| `user_id` | `UUID` FK -> `users.id` | 导入目标用户。 |
| `card_pack_id` | `UUID` FK -> `card_packs.id` | 来源 Pack。 |
| `creator_id` | `UUID` FK -> `users.id` | 来源 Creator。 |
| `virtual_wardrobe_id` | `UUID` FK -> `wardrobes.id` | 导入落地衣橱。 |
| `request_id` | `VARCHAR(64)` nullable | 幂等请求标识。 |
| `status` | `VARCHAR(20)` | `PENDING` / `PROCESSING` / `COMPLETED` / `FAILED`。 |
| `item_count` | `INTEGER` | 导入件数。 |
| `imported_at` | `TIMESTAMP` nullable | 完成时间。 |
| `failure_reason` | `TEXT` nullable | 失败原因。 |
| `created_at` / `updated_at` | `TIMESTAMP` | 审计字段。 |

建议索引：

- `(user_id, created_at desc)`
- `(user_id, card_pack_id)`
- `(user_id, request_id)` 唯一约束，可作为幂等入口

说明：

- `status` 使用 `PROCESSING` 而非 `IMPORTING`，与 `processing_tasks` 保持一致

#### `import_history_items`

| Field | Type | Description |
| --- | --- | --- |
| `id` | `UUID` PK | 明细主键。 |
| `import_history_id` | `UUID` FK | 所属导入批次。 |
| `clothing_item_id` | `UUID` FK | 本次生成的 imported 副本。 |
| `origin_clothing_item_id` | `UUID` FK | 来源 Creator Item。 |

#### `outfits`

| Field | Type | Description |
| --- | --- | --- |
| `id` | `UUID` PK | Outfit 主键。 |
| `user_id` | `UUID` FK -> `users.id` | 所属用户。 |
| `name` | `VARCHAR(120)` | 搭配名称。 |
| `description` | `TEXT` nullable | 搭配描述。 |
| `thumbnail_path` | `TEXT` nullable | 缩略图存储路径。 |
| `thumbnail_status` | `VARCHAR(20)` | `NOT_GENERATED` / `GENERATING` / `READY` / `FAILED`。 |
| `created_at` / `updated_at` | `TIMESTAMP` | 审计字段。 |

#### `outfit_items`

| Field | Type | Description |
| --- | --- | --- |
| `id` | `UUID` PK | Outfit item 主键。 |
| `outfit_id` | `UUID` FK | 所属 Outfit。 |
| `clothing_item_id` | `UUID` FK | 用户域衣物。 |
| `layer` | `INTEGER` | 图层顺序。 |
| `position_x` | `NUMERIC(8,4)` | 画布 X。 |
| `position_y` | `NUMERIC(8,4)` | 画布 Y。 |
| `scale` | `NUMERIC(8,4)` | 缩放。 |
| `rotation` | `NUMERIC(8,4)` | 旋转角。 |

## 4. Permission Model

### 4.1 New Dependency

新增：

```python
def get_current_creator_user_id(...)
```

行为：

- 基于现有 `get_current_user_id` 获取用户。
- 校验当前用户存在可用的 `creator_profile`，且 `status == "ACTIVE"`。
- 不满足时返回 `403 Forbidden`。

### 4.2 Ownership Rules

- Consumer 只能访问自己的 `clothing_items`、`wardrobes`、`import_histories`、`outfits`。
- Creator 只能编辑自己的 `creator_profiles`、`creator_items`、`card_packs`。
- `GET /creators/*` 与 `GET /card-packs/share/*` 是公开读接口，但只暴露 `PUBLISHED` 状态。
- Import 时禁止读取 DRAFT / ARCHIVED Pack。

落地约束：

- 所有写接口必须按 `resource_id + owner_id/current_user_id` 联合查询，不接受“先按 id 读出对象，再在路由层顺手比较 owner”的松散实现。
- CRUD 层至少需要提供 `get_owned_outfit(...)`、`get_owned_creator_item(...)`、`get_owned_card_pack(...)`、`get_owned_creator_profile(...)` 这类带所有权条件的读取函数。
- 对公开读接口，`PUBLISHED` 过滤必须在查询层完成，不能先取出任意状态对象再在响应层丢弃字段。

## 5. Shared Response Extensions

### 5.1 Clothing Item Response Extension

`GET /clothing-items/:id` 与 `GET /clothing-items` 的 `data.items[]` 增加：

```json
{
  "provenance": {
    "sourceType": "IMPORTED",
    "originClothingItemId": "item-creator-001",
    "creator": {
      "id": "creator-456",
      "displayName": "Fashion Guru"
    },
    "cardPack": {
      "id": "pack-001",
      "name": "Summer Essentials 2024"
    },
    "importHistoryId": "import-001",
    "importedAt": "2026-04-01T08:00:00Z"
  }
}
```

规则：

- `OWNED` 衣物的 `provenance` 返回 `null`。
- `IMPORTED` 衣物必须返回完整 provenance。

### 5.2 Wardrobe Response Extension

`GET /wardrobes`、`GET /wardrobes/:id` 增加：

```json
{
  "isSystemManaged": true,
  "systemKey": "DEFAULT_VIRTUAL_IMPORTED"
}
```

## 6. API Design

### 6.1 Upload Validation

#### `POST /clothing-items`

保留当前路径，增强校验规则。

`multipart/form-data`:

| Field | Required | Rule |
| --- | --- | --- |
| `front_image` | yes | `image/jpeg` / `image/png` / `image/webp`，`1KB-10MB` |
| `back_image` | no | 与 `front_image` 相同 |
| `name` | no | `1-200` 字符 |
| `description` | no | `0-2000` 字符 |

新增校验：

- 空文件直接拒绝
- 扩展名与 MIME 不一致直接拒绝
- 像素尺寸需在 `256x256` 到 `6000x6000` 之间
- 非图像内容直接拒绝

失败响应示例：

```json
{
  "success": false,
  "error": {
    "code": "INVALID_FILE_TYPE",
    "message": "front_image must be jpeg, png, or webp",
    "details": {
      "field": "front_image",
      "contentType": "application/pdf"
    }
  }
}
```

### 6.2 System Virtual Wardrobe

#### `GET /wardrobes/system/virtual`

用途：

- 返回当前用户的系统虚拟衣橱
- 若不存在，则创建后返回

响应 (200):

```json
{
  "success": true,
  "data": {
    "id": "wardrobe-virtual-001",
    "userId": "user-123",
    "name": "Virtual Wardrobe",
    "type": "VIRTUAL",
    "isSystemManaged": true,
    "systemKey": "DEFAULT_VIRTUAL_IMPORTED",
    "itemCount": 23,
    "createdAt": "2026-04-01T08:00:00Z",
    "updatedAt": "2026-04-01T08:00:00Z"
  }
}
```

说明：

- 这是前端的便利接口。
- Import Service 内部仍必须调用相同的 `get_or_create_virtual_wardrobe(user_id)`，不能依赖前端先调。

### 6.3 Creator Profile

#### `GET /creators`

查询参数：

- `verified`
- `search`
- `page`
- `limit`

响应字段：

- `id`
- `username`
- `displayName`
- `brandName`
- `avatarUrl`
- `bioSummary`
- `packCount`
- `isVerified`

#### `GET /creators/{creatorId}`

公开读取单个 Creator Profile，补齐详情页。

#### `PATCH /creators/{creatorId}`

权限：

- 仅 `creatorId == current_user_id` 或管理员可写

请求：

```json
{
  "displayName": "Fashion Guru",
  "brandName": "FG Fashion",
  "bio": "Sharing curated seasonal looks",
  "websiteUrl": "https://fashionguru.com",
  "socialLinks": {
    "instagram": "https://instagram.com/fashionguru",
    "tiktok": "https://tiktok.com/@fashionguru"
  }
}
```

### 6.4 Creator Items

#### `POST /creator-items`

作用：

- 补齐“Creator Upload”能力
- 上传链路复用现有 clothing pipeline

请求：

- 与 `POST /clothing-items` 的 multipart 字段一致
- 可额外带 `catalogVisibility`

响应 (202):

```json
{
  "success": true,
  "data": {
    "id": "creator-item-001",
    "processingTaskId": "task-001",
    "status": "PENDING",
    "catalogVisibility": "PACK_ONLY",
    "createdAt": "2026-04-01T08:00:00Z"
  }
}
```

#### `GET /creator-items/{id}`

返回 Creator Catalog 衣物详情，用于 Pack 选择和编辑。

#### `PATCH /creator-items/{id}`

可更新：

- `name`
- `description`
- `finalTags`
- `customTags`
- `catalogVisibility`

#### `DELETE /creator-items/{id}`

约束：

- 若衣物已被某个 `PUBLISHED` Pack 引用，则返回 `409 Conflict`

#### `GET /creators/{creatorId}/items`

公开浏览 Creator Catalog。只返回 `catalogVisibility != PRIVATE` 的条目。

### 6.5 Card Packs

#### `POST /card-packs`

请求：

```json
{
  "name": "Summer Essentials 2026",
  "description": "Light layers for daily styling",
  "type": "CLOTHING_COLLECTION",
  "itemIds": [
    "creator-item-001",
    "creator-item-002",
    "creator-item-003"
  ],
  "coverImage": "base64-or-storage-reference"
}
```

规则：

- `itemIds` 不能为空
- 所有 item 必须属于当前 Creator
- 同一个 Pack 中 item 不可重复

#### `GET /card-packs/{id}`

对 Creator 自己返回任意状态，对外部访问只允许读取 `PUBLISHED`。

#### `GET /card-packs/share/{shareId}`

公开入口，固定只读 `PUBLISHED` Pack。

#### `GET /creators/{creatorId}/card-packs`

对外只返回 `PUBLISHED`，Creator 自己可通过 `status` 查看 DRAFT / ARCHIVED。

#### `PATCH /card-packs/{id}`

仅允许修改：

- `name`
- `description`
- `itemIds`
- `coverImage`

限制：

- 仅 `DRAFT` 可改 `itemIds`

#### `POST /card-packs/{id}/publish`

发布前校验：

- Pack 至少包含 1 个 item
- 所有 item 已处理完成
- Creator Profile 必须存在

响应中返回：

- `status: PUBLISHED`
- `shareLink`
- `publishedAt`

#### `POST /card-packs/{id}/archive`

效果：

- `PUBLISHED -> ARCHIVED`
- 已导入记录保留，不影响既有 imported 副本

#### `DELETE /card-packs/{id}`

限制：

- 仅 `DRAFT` 可删除

### 6.6 Import APIs

#### `POST /imports/card-pack`

请求：

```json
{
  "cardPackId": "pack-001",
  "requestId": "import-20260401-0001"
}
```

幂等与重复导入规则：

- `requestId` 必填，由客户端生成，推荐 UUID/ULID。
- 数据库对 `(user_id, request_id)` 建唯一约束，作为 API 级幂等键。
- 相同 `(user_id, request_id)` 且 `cardPackId` 相同的重试请求，必须返回第一次请求对应的导入结果或当前状态，不能再次创建导入记录。
- 如果同一个 `requestId` 被拿去请求不同的 `cardPackId`，应返回 `409 requestId conflict`。
- 当前 MVP 未定义“同一用户重复导入同一 Pack”的业务语义，因此默认禁止同一用户重复导入同一 `cardPackId`。
- 除 API 幂等外，服务层还要额外检查当前用户是否已经存在该 Pack 的 `PENDING`、`PROCESSING` 或 `COMPLETED` 导入记录；若存在，则返回既有结果或明确错误。
- 只有未来明确引入 `forceReimport`、Pack version 或增量导入语义后，才放开 `(user_id, card_pack_id)` 这一层业务限制。

处理步骤：

1. 按 `(user_id, request_id)` 执行幂等检查
2. 按 `(user_id, card_pack_id)` 执行重复导入检查
3. 校验 Pack 状态为 `PUBLISHED`
4. 获取或创建 `Virtual Wardrobe`
5. 为每个 Pack Item 生成当前用户私有 imported 副本
6. 回填 `origin_*` provenance 字段
7. 批量写入 `wardrobe_items`
8. 写入 `import_histories` 与 `import_history_items`
9. 递增 `card_packs.import_count`

响应：

```json
{
  "success": true,
  "data": {
    "importId": "import-001",
    "cardPackId": "pack-001",
    "itemsImported": 3,
    "virtualWardrobeId": "wardrobe-virtual-001",
    "importedAt": "2026-04-01T08:00:00Z",
    "importedItems": [
      {
        "id": "item-imported-001",
        "source": "IMPORTED",
        "provenance": {
          "sourceType": "IMPORTED",
          "originClothingItemId": "creator-item-001",
          "creator": {
            "id": "creator-456",
            "displayName": "Fashion Guru"
          },
          "cardPack": {
            "id": "pack-001",
            "name": "Summer Essentials 2026"
          },
          "importHistoryId": "import-001",
          "importedAt": "2026-04-01T08:00:00Z"
        }
      }
    ]
  }
}
```

错误：

- `404` Pack 不存在
- `409` Pack 不可导入
- `409` `requestId` 与其他 `cardPackId` 冲突
- `409` Pack 已导入或正在导入
- `422` Pack item 数据损坏

#### Import 可观测性要求

导入是关键链路，文档必须定义最小可观测性，而不是只定义接口。

建议最少补齐：

- 结构化日志字段：
  `request_id`、`import_history_id`、`user_id`、`card_pack_id`、`creator_id`、`item_count`、`status`、`failure_code`
- 关键 metrics：
  `card_pack_import_started_total`
  `card_pack_import_completed_total`
  `card_pack_import_failed_total`
  `card_pack_import_duration_ms`
  `card_pack_import_items_total`
- 失败原因要落标准化 `failure_code`，不要只写自由文本 `failure_reason`
- success rate 由 `completed_total / started_total` 计算，失败原因分布由 `failure_code` 维度聚合
- 所有导入重试请求必须带同一个 `requestId`，便于日志、metrics 和问题追踪串联

#### `GET /imports/history`

查询参数：

- `page`
- `limit`

响应：

响应 (200):

```json
{
  "success": true,
  "data": {
    "imports": [
      {
        "id": "import-001",
        "cardPackId": "pack-001",
        "cardPackName": "Summer Essentials 2026",
        "creatorId": "creator-456",
        "creatorName": "Fashion Guru",
        "itemCount": 3,
        "virtualWardrobeId": "wardrobe-virtual-001",
        "status": "COMPLETED",
        "importedAt": "2026-04-01T08:00:00Z",
        "createdAt": "2026-04-01T08:00:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total": 1,
      "totalPages": 1
    }
  }
}
```

### 6.7 Outfits

#### `POST /outfits`

请求：

```json
{
  "name": "Casual Friday",
  "description": "Comfortable office look",
  "items": [
    {
      "clothingItemId": "item-001",
      "layer": 0,
      "position": { "x": 0.52, "y": 0.26 },
      "scale": 1.0,
      "rotation": 0
    },
    {
      "clothingItemId": "item-002",
      "layer": 1,
      "position": { "x": 0.49, "y": 0.61 },
      "scale": 1.04,
      "rotation": -2
    }
  ]
}
```

校验：

- `items` 至少 1 条
- 所有 `clothingItemId` 必须归属于当前用户
- 一个 Outfit 内不允许重复引用同一件衣物

响应：

```json
{
  "success": true,
  "data": {
    "id": "outfit-001",
    "name": "Casual Friday",
    "description": "Comfortable office look",
    "thumbnailUrl": null,
    "thumbnailStatus": "NOT_GENERATED",
    "items": []
  }
}
```

#### `GET /outfits`

返回当前用户的搭配列表，支持：

- `page`
- `limit`
- `search`

#### `GET /outfits/{id}`

返回完整布局和 clothing item 摘要，用于画布恢复。

#### `PATCH /outfits/{id}`

可更新：

- `name`
- `description`
- `items`

规则：

- 若更新 `items`，采用“全量替换”模式，避免复杂 diff
- 若更新了布局，`thumbnailStatus` 重置为 `NOT_GENERATED`

#### `DELETE /outfits/{id}`

硬删除 outfit 与 outfit_items，不删除被引用衣物。

#### `POST /outfits/{id}/thumbnail`

作用：

- 手动触发缩略图生成
- 幂等，若已有 `READY` 缩略图可覆盖或直接复用

响应：

```json
{
  "success": true,
  "data": {
    "outfitId": "outfit-001",
    "thumbnailStatus": "GENERATING"
  }
}
```

## 7. Route Modules And Services

建议新增文件：

- `backend/app/api/v1/creators.py`
- `backend/app/api/v1/creator_items.py`
- `backend/app/api/v1/card_packs.py`
- `backend/app/api/v1/imports.py`
- `backend/app/api/v1/outfits.py`

建议新增服务：

- `backend/app/services/upload_validation_service.py`
- `backend/app/services/virtual_wardrobe_service.py`
- `backend/app/services/card_pack_import_service.py`
- `backend/app/services/outfit_service.py`
- `backend/app/services/outfit_thumbnail_service.py`

建议新增 CRUD：

- `backend/app/crud/creator.py`
- `backend/app/crud/creator_item.py`
- `backend/app/crud/card_pack.py`
- `backend/app/crud/import_history.py`
- `backend/app/crud/outfit.py`

## 8. Transaction Boundaries

### 8.1 Import Transaction

必须在单一事务里完成：

1. 创建 `import_histories`
2. 批量创建 imported `clothing_items`
3. 批量创建 imported `images` / `models_3d` 引用
4. 批量创建 `wardrobe_items`
5. 批量创建 `import_history_items`
6. 更新 `card_packs.import_count`

任一步失败必须整体回滚。

### 8.2 Outfit Save Transaction

必须在单一事务里完成：

1. 创建或更新 `outfits`
2. 替换 `outfit_items`
3. 更新 `thumbnail_status`

缩略图渲染可异步，不能与主事务强耦合。

## 9. Recommended Delivery Order

1. 先实现上传前置校验，避免坏文件继续进入链路。
2. 再实现 `Virtual Wardrobe Service` 和衣橱系统字段。
3. 落 Outfit 数据模型和 `/outfits` 路由。
4. 落 Creator Profile / Creator Item / Card Pack。
5. 最后实现 `POST /imports/card-pack`、导入历史和 provenance 扩展。

这个顺序的原因是：前 3 步能最小化风险并尽快支撑前后端联调，导入链路则依赖前面所有资源已经稳定存在。
