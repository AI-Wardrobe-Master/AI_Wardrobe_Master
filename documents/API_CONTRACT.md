# AI Wardrobe Master - API Contract

## Overview

本文档基于当前主分支实际实现整理。  
它合并了早期接口规划、后续 `/auth` 语义修正，以及 2026-04 已落地的共享子衣柜、Discover 与共享图片访问规则。

## Base Configuration

### Base URL

```text
Local demo backend: http://localhost:8000/api/v1
Legacy mock address: http://localhost:3000/api/v1
Production placeholder: https://api.aiwardrobe.com/v1
```

### Authentication

受保护接口使用：

```text
Authorization: Bearer <JWT_TOKEN>
```

本地联调用过的默认测试账号：

```text
demo@example.com / demo123456
```

### Common Headers

```text
Content-Type: application/json
Accept: application/json
X-Client-Version: 1.0.0
X-Platform: ios | android | web
```

### Common Status Codes

- `200 OK`
- `201 Created`
- `202 Accepted`
- `204 No Content`
- `400 Bad Request`
- `401 Unauthorized`
- `403 Forbidden`
- `404 Not Found`
- `409 Conflict`
- `422 Unprocessable Entity`
- `500 Internal Server Error`

## 1. Authentication

### `POST /auth/register`

注册用户并直接返回登录态。

请求体：

```json
{
  "username": "johndoe",
  "email": "john@example.com",
  "password": "SecurePass123!",
  "userType": "CREATOR"
}
```

字段说明：

| Field | Type | Required | Notes |
|---|---|---|---|
| `username` | string | yes | 3-50 chars, unique |
| `email` | string | yes | lowercased + trimmed, unique |
| `password` | string | yes | 8-255 chars |
| `userType` | string | no | `CONSUMER` or `CREATOR`, case-insensitive |

当前实现语义：

- 后端会 honor 客户端传入的 `userType`
- 传 `CREATOR` 会直接创建 `CREATOR` 类型账号
- 省略或传 `CONSUMER` 会创建普通用户
- 非法值返回 `422`
- 注册完成后会自动确保主衣柜存在
- 响应会返回 token、`uid` 和基础用户信息

响应示例：

```json
{
  "data": {
    "token": "jwt-token",
    "user": {
      "id": "8f1d...",
      "uid": "USR-9FDA6672",
      "username": "johndoe",
      "email": "john@example.com",
      "type": "CREATOR"
    }
  }
}
```

### `POST /auth/login`

请求体：

```json
{
  "email": "john@example.com",
  "password": "SecurePass123!"
}
```

当前实现说明：

- 登录成功后也会再次确保主衣柜存在
- 响应结构与注册一致

### `POST /auth/logout`

用于前端清理会话。当前实现为轻量响应接口。

## 2. Current User Context

### `GET /me`

返回当前登录用户在主壳层、Discover、个人页中真正使用的上下文。

```json
{
  "data": {
    "id": "8f1d...",
    "uid": "USR-9FDA6672",
    "username": "johndoe",
    "email": "john@example.com",
    "type": "CONSUMER",
    "creatorProfile": {
      "exists": false,
      "status": null,
      "displayName": null,
      "brandName": null
    },
    "capabilities": {
      "canApplyForCreator": true,
      "canPublishItems": false,
      "canCreateCardPacks": false,
      "canEditCreatorProfile": false,
      "canViewCreatorCenter": false
    }
  }
}
```

## 3. Clothing Items

### `POST /clothing-items`

当前通过 `multipart/form-data` 上传衣物资料，至少要求：

- `front_image`

可选：

- `back_image`
- `name`
- `description`

当前实现说明：

- 提交后会创建处理任务
- 自动分类当前重点仍是 `category`
- 处理完成后可通过详情接口与 `/files` 访问图片资源

### `GET /clothing-items/{id}`

返回衣物详情。  
当前系统中 `ClothingItem` 已经是统一衣物表，不再区分单独的 `creator_items` 数据表。

### `PATCH /clothing-items/{id}`

可更新：

- 名称
- 描述
- `finalTags`
- `isConfirmed`
- `customTags`

### `DELETE /clothing-items/{id}`

主衣柜长按删除时使用。  
语义为删除衣物实体本身，而不是只解除某个子衣柜关联。

## 4. Wardrobes

### Wardrobe Response Shape

当前 `WardrobeResponse` 主要字段如下：

```json
{
  "id": "uuid",
  "wid": "WRD-61FF0565",
  "userId": "owner-uuid",
  "ownerUid": "USR-9FDA6672",
  "ownerUsername": "sharetest0420140508",
  "name": "Cross Account Share",
  "kind": "SUB",
  "type": "REGULAR",
  "source": "MANUAL",
  "isMain": false,
  "description": "shared wardrobe",
  "coverImageUrl": null,
  "autoTags": [],
  "manualTags": [],
  "tags": [],
  "isPublic": true,
  "parentWardrobeId": "uuid-or-null",
  "outfitId": null,
  "itemCount": 3,
  "createdAt": "2026-04-20T12:00:00Z",
  "updatedAt": "2026-04-20T12:00:00Z"
}
```

### `GET /wardrobes`

列出当前登录用户自己的衣柜。

### `POST /wardrobes`

创建衣柜，当前请求体关键字段：

```json
{
  "name": "Summer Share",
  "description": "sub wardrobe",
  "type": "REGULAR",
  "manualTags": ["summer"],
  "isPublic": false
}
```

### `PATCH /wardrobes/{id}`

更新衣柜名称、描述、标签与 `isPublic`。

### `GET /wardrobes/public`

列出公开共享子衣柜。

当前实现说明：

- 只返回公开的 `SUB` wardrobe
- `CARD_PACK` 来源的公开衣柜也出现在这里
- Discover 已将 `packs` 与 `wardrobes` 统一在这个列表浏览

当前搜索范围包括：

- 衣柜名称
- `wid`
- 描述
- `ownerUid`
- `ownerUsername`
- 自动标签
- 手动标签

### `GET /wardrobes/by-wid/{wid}`

按业务编号 `wid` 获取共享衣柜详情。

### `GET /wardrobes/by-wid/{wid}/items`

获取公开共享衣柜中的衣物列表。

### `POST /wardrobes/export-selection`

将当前选择的衣物导出为子衣柜，供后续分享或保存使用。

### `POST /wardrobes/{id}/items/{clothing_item_id}/move`

在不同衣柜之间移动衣物关联。

### `POST /wardrobes/{id}/items/{clothing_item_id}/copy`

向目标衣柜复制一份衣物关联。

## 5. Public Sharing Behavior

当前公开分享对象统一为“公开 `SUB` wardrobe”。

这包括两类来源：

- 用户手动创建并公开的共享子衣柜
- 创作者发布 card pack 后映射出来的公开子衣柜

Discover 中两者共用同一个公开列表接口，只通过 `source` 标签区分来源。

## 6. Shared Clothing Images

### `GET /files/clothing-items/{item_id}/{kind}`

返回衣物图片文件流。

当前权限规则已经修正为：

- 所有者本人可访问
- 如果该衣物属于公开 `SUB` wardrobe，其他账号也可访问
- 否则继续返回不可访问

这项修复解决了“共享衣柜里只能看到名称，看不到图片”的问题。

## 7. Card Packs

当前实现里，card pack 与公开 wardrobe 的关系是联动的：

- 发布 card pack 时，会创建或复用公开 `SUB` wardrobe
- 该 wardrobe 的 `source = CARD_PACK`
- 该 wardrobe `is_public = true`
- 归档 pack 时，会同步取消公开显示

因此在产品浏览层面，card pack 最终也是共享 wardrobe 的一种来源。

## 8. Legacy Scope Retained

虽然本轮重点同步的是 2026-04 已落地能力，但原接口规划中的这些模块范围仍然保留：

- clothing upload / processing / detail / search
- wardrobe CRUD 与衣物关联管理
- outfits 与 outfit preview task
- creator profile / creator items facade
- card pack publish / archive / public browse
- imports 与 imported-content lineage

Outfit preview 的 DashScope 实现备注：

- 若后端用 HTTP JSON 直调 DashScope，图片字段必须是公网可下载的 HTTP(S) URL。
- 若输入来自本机 CAS 文件，应使用 DashScope SDK 的 `file://` 本地路径能力，让 SDK 先上传本地文件；不要把 `file://` 直接作为 HTTP JSON 的 `image` URL。
- 示例本地相对路径：`file://test/image/car.webp`。

## 9. Real-Device Android Note

若后端运行在开发机本地 `8000` 端口，Android 真机联调需要先执行：

```bash
adb reverse tcp:8000 tcp:8000
```

否则手机端无法通过 `127.0.0.1:8000` 访问本机后端。
