# AI Wardrobe Master - Data Model

## Overview

本文档记录当前主分支已经落地的数据模型重点，合并保留了：

- 原始 Phase 1 实体设计
- 统一 `clothing_items` 表后的建模语义
- 2026-04 共享子衣柜、Discover 检索与 `/me` 用户态补充字段

## Core Principles

1. `ClothingItem` 是衣物实体，衣柜只保存关联，不复制实体
2. 主衣柜与子衣柜语义不同，删除与移除必须分开
3. 公开分享统一落在公开 `SUB` wardrobe 上
4. `wid` 和 `uid` 是对外检索与分享的业务编号
5. 共享访问不等于私有所有权转移

## Relationship Summary

```text
User 1 --- n Wardrobe
User 1 --- n ClothingItem
Wardrobe n --- n ClothingItem  (via WardrobeItem)
User 1 --- 0..1 CreatorProfile
CreatorProfile 1 --- n CardPack
CardPack 1 --- 0..1 Wardrobe   (published public wardrobe mapping)
```

## Core Entities

### 1. User

关键字段：

- `id`
- `uid`
- `username`
- `email`
- `type`
- `is_active`
- `created_at`
- `updated_at`

业务说明：

- `uid` 用于 Discover、分享验证、跨账号检索
- `/me` 会把 `uid` 返回给前端个人页与共享检索使用

### 2. CreatorProfile

关键字段：

- `user_id`
- `status`
- `display_name`
- `brand_name`

业务说明：

- 是否显示创作者能力不再只看 `User.type`
- 前端改由 `/me.capabilities` 决定入口展示

### 3. ClothingItem

当前系统已采用统一 `ClothingItem` canonical table。  
原先独立的 `CreatorItem` 语义已经折叠进 `ClothingItem`，公开可见性通过字段表达，而不是靠第二张独立业务表。

关键字段：

- `id`
- `user_id`
- `source`：`OWNED | IMPORTED`
- `name`
- `description`
- `predicted_tags`
- `final_tags`
- `custom_tags`
- `is_confirmed`
- `catalog_visibility`
- `origin_clothing_item_id`
- `origin_creator_id`
- `origin_card_pack_id`
- `origin_import_history_id`
- `imported_at`

业务说明：

- 主衣柜长按删除会删除 `ClothingItem`
- 子衣柜移除只删除关联，不删除 `ClothingItem`
- creator 内容与 consumer 内容最终共用这张表

### 4. Wardrobe

关键字段：

- `id`
- `wid`
- `user_id`
- `name`
- `description`
- `kind`
- `type`
- `source`
- `cover_image_url`
- `auto_tags`
- `manual_tags`
- `is_public`
- `parent_wardrobe_id`
- `outfit_id`
- `created_at`
- `updated_at`

字段说明：

- `wid`：对外分享、检索、Discover 展示用业务编号
- `kind`：`MAIN | SUB`
- `type`：`REGULAR | VIRTUAL`
- `source`：`MANUAL | OUTFIT_EXPORT | IMPORTED | CARD_PACK`
- `is_public`：是否出现在公开共享列表

业务规则：

- 主衣柜通常是 `MAIN`
- Discover 公开浏览只列出公开的 `SUB` wardrobe
- 公开 card pack 在数据上也映射为一个 `source = CARD_PACK` 的公开 `SUB` wardrobe

### 5. WardrobeItem

关键字段：

- `wardrobe_id`
- `clothing_item_id`
- `display_order`
- `added_at`

业务规则：

- 一个衣物可出现在多个衣柜
- 删除衣柜关联不应删除衣物实体

### 6. CardPack

关键字段：

- `id`
- `creator_id`
- `name`
- `description`
- `status`
- `published_at`
- `archived_at`
- `wardrobe_id`

业务说明：

- 发布时会创建或更新公开共享 wardrobe
- 归档时会同步隐藏对应公开 wardrobe

### 7. ImportHistory

关键字段：

- `id`
- `user_id`
- `card_pack_id`
- `created_at`

## Public Sharing Rules

### Rule 1: Public sharing unit

系统对外共享的最小可浏览单元是公开 `SUB` wardrobe，而不是主衣柜本体。

### Rule 2: Discover source merge

Discover 中显示的公开列表，本质上都是共享 wardrobe：

- 手动共享子衣柜
- card pack 发布后生成的共享子衣柜

### Rule 3: Search identity

公开共享内容检索优先依赖：

- `wid`
- `ownerUid`
- `ownerUsername`

### Rule 4: File access

共享衣物图片只有在“衣物归属于公开 `SUB` wardrobe”时，其他账号才被允许访问。

## Example Public Wardrobe Object

```json
{
  "id": "uuid",
  "wid": "WRD-58BFCD59",
  "userId": "owner-uuid",
  "ownerUid": "USR-12345678",
  "ownerUsername": "demo_user",
  "name": "Outfit Export",
  "kind": "SUB",
  "type": "REGULAR",
  "source": "OUTFIT_EXPORT",
  "isMain": false,
  "description": "Shared from outfit flow",
  "coverImageUrl": null,
  "autoTags": [],
  "manualTags": ["share"],
  "tags": ["share"],
  "isPublic": true,
  "parentWardrobeId": null,
  "outfitId": null,
  "itemCount": 4
}
```

## Legacy Model Continuity

原文档中关于以下实体的总体建模思路仍然保留：

- `User`
- `ClothingItem`
- `Wardrobe`
- `WardrobeItem`
- `Outfit`
- `CreatorProfile`
- `CardPack`
- `ImportHistory`

本轮主要是在 `User` 和 `Wardrobe` 上补充了更适合公开共享和跨账号检索的业务字段与规则。
