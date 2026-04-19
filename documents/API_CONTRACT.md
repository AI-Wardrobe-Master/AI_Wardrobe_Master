# AI Wardrobe Master - API Contract

## Overview
This document defines the API contract for the AI Wardrobe Master application Phase 1. The API follows RESTful principles and uses JSON for request/response payloads.

---

## Base Configuration

### Base URL
```
Development: http://localhost:3000/api/v1
Production: https://api.aiwardrobe.com/v1
```

**Current local demo backend:** `http://localhost:8000/api/v1`

### Authentication
```
Authorization: Bearer <JWT_TOKEN>
```

**Current implementation note:** The local backend now enforces Bearer JWT on protected endpoints. For local Docker-based development, a seed user is prepared automatically: `demo@example.com` / `demo123456`.

### Common Headers
```
Content-Type: application/json
Accept: application/json
X-Client-Version: 1.0.0
X-Platform: ios | android | web
```

### Response Format

#### Success Response
```json
{
  "success": true,
  "data": { /* response data */ },
  "meta": {
    "timestamp": "2024-01-15T10:30:00Z",
    "requestId": "req-123456"
  }
}
```

#### Error Response
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": { /* additional error context */ }
  },
  "meta": {
    "timestamp": "2024-01-15T10:30:00Z",
    "requestId": "req-123456"
  }
}
```

### HTTP Status Codes
- `200 OK` - Successful request
- `201 Created` - Resource created successfully
- `204 No Content` - Successful request with no response body
- `400 Bad Request` - Invalid request parameters
- `401 Unauthorized` - Missing or invalid authentication
- `403 Forbidden` - Insufficient permissions
- `404 Not Found` - Resource not found
- `409 Conflict` - Resource conflict (e.g., duplicate)
- `422 Unprocessable Entity` - Validation error
- `429 Too Many Requests` - Rate limit exceeded
- `500 Internal Server Error` - Server error

---

## API Endpoints

## 1. Authentication

### 1.1 Register User
```
POST /auth/register
```

**Request Body:**
```json
{
  "username": "johndoe",
  "email": "john@example.com",
  "password": "SecurePass123!",
  "userType": "CONSUMER"
}
```

**Current implementation note:** `userType` is accepted for forward compatibility, but the backend currently creates newly registered users as `CONSUMER` by default.

**Response (201):**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "user-123",
      "username": "johndoe",
      "email": "john@example.com",
      "type": "CONSUMER",
      "createdAt": "2024-01-15T10:30:00Z"
    },
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

**Error responses:**
- `409 Conflict` - email already registered or username already taken
- `422 Unprocessable Entity` - invalid username/email/password format

### 1.2 Login
```
POST /auth/login
```

**Request Body:**
```json
{
  "email": "john@example.com",
  "password": "SecurePass123!"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "user": { /* user object */ },
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

---

## 2. Clothing Items

### 2.1 Create Clothing Item
```
POST /clothing-items
```

**Request Body (multipart/form-data):**
```
front_image: <file>             (required, current backend implementation)
back_image: <file>              (optional — improves 3D generation quality)
name: "Blue Striped T-Shirt"
description: "Comfortable cotton t-shirt"
```

**Current implementation note:** `customTags` / `tags` are not accepted during creation in the current backend implementation. User-defined tags are added later via `PATCH /clothing-items/:id`.

**Validation Rules:**
- `front_image` is required and must be `image/jpeg`, `image/png`, or `image/webp`
- Empty files are rejected
- Backend validates MIME type, extension consistency, and actual decodability
- Image dimensions must stay within the backend-supported range
- `name` and `description` are optional, but must satisfy backend length checks when present

**Response (202 Accepted):**

> Returns 202 because the request only stores the originals, creates a processing task, and enqueues background work. Client should poll the processing-status endpoint.

```json
{
  "success": true,
  "data": {
    "id": "item-001",
    "processingTaskId": "task-001",
    "status": "PENDING",
    "estimatedTime": 30
  }
}
```

**Failure / retry semantics:**
- Original assets (`originalFrontUrl`, `originalBackUrl`) remain available after failure.
- Derived assets (`processedFrontUrl`, `processedBackUrl`, `model3dUrl`, `angleViews`) must be empty when the latest processing task is `FAILED`.
- `POST /clothing-items/:id/retry` creates a new processing task, reuses the original uploads, and clears previous derived outputs before rerunning.
- Only one active processing task (`PENDING` or `PROCESSING`) is allowed per clothing item.

**Response after processing completes (via GET /clothing-items/:id):**
```json
{
  "success": true,
  "data": {
    "id": "item-001",
    "userId": "user-123",
    "source": "OWNED",
    "images": {
      "originalFrontUrl": "/images/item-001-front-orig.jpg",
      "originalBackUrl": "/images/item-001-back-orig.jpg",
      "processedFrontUrl": "/images/item-001-front-proc.png",
      "processedBackUrl": "/images/item-001-back-proc.png",
      "angleViews": {
        "0": "/images/item-001-angle-0.png",
        "45": "/images/item-001-angle-45.png",
        "90": "/images/item-001-angle-90.png",
        "135": "/images/item-001-angle-135.png",
        "180": "/images/item-001-angle-180.png",
        "225": "/images/item-001-angle-225.png",
        "270": "/images/item-001-angle-270.png",
        "315": "/images/item-001-angle-315.png"
      }
    },
    "model3dUrl": "/models/item-001.glb",
    "predictedTags": [
      { "key": "category", "value": "t-shirt" }
    ],
    "finalTags": [
      { "key": "category", "value": "t-shirt" }
    ],
    "isConfirmed": false,
    "name": "Blue Striped T-Shirt",
    "description": "Comfortable cotton t-shirt",
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T10:30:00Z"
  }
}
```

**Note:** `originalBackUrl`, `processedBackUrl` will be `null` if no back image was provided.
```

### 2.2 Get Clothing Item
```
GET /clothing-items/:id
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "item-002",
    "userId": "user-123",
    "source": "IMPORTED",
    "provenance": {
      "sourceType": "IMPORTED",
      "originClothingItemId": "creator-item-456",
      "importHistoryId": "import-001",
      "creator": {
        "id": "creator-456",
        "displayName": "FashionGuru"
      },
      "cardPack": {
        "id": "pack-789",
        "name": "Summer Essentials 2024"
      },
      "importedAt": "2026-04-01T08:00:00Z"
    }
  }
}
```

**Current implementation notes:**
- The detail response now includes `customTags`.
- Automatic prediction currently only fills `category`. `season`, `style`, and `audience` are expected to be user-added later through `PATCH /clothing-items/:id`.
- For owned items, `provenance` is `null`.
- For imported items, `provenance` includes creator and pack summary data assembled from the imported item's stored origin fields.

### 2.3 Update Clothing Item (Including Tag Confirmation)
```
PATCH /clothing-items/:id
```

**Use Cases:**
1. **Confirm AI-predicted tags** - User reviews and confirms the predicted tags
2. **Edit tags** - User modifies tags to correct classification errors
3. **Update metadata** - User updates name, description, or custom tags

**Request Body:**
```json
{
  "name": "Updated Name",
  "finalTags": [
    { "key": "category", "value": "shirt" },
    { "key": "style", "value": "casual" },
    { "key": "season", "value": "summer" },
    { "key": "audience", "value": "unisex" }
  ],
  "isConfirmed": true,
  "customTags": ["cotton", "comfortable", "everyday"]
}
```

**Response (200):**
```json
{
  "success": true,
  "data": { /* Updated ClothingItem object */ }
}
```

**Important Notes:**
- When updating tags, provide the complete `finalTags` array (replaces all existing finalTags)
- The `predictedTags` remain immutable and cannot be modified
- Set `isConfirmed: true` when user has reviewed and confirmed the tags
- Search operations use `finalTags` only, not `predictedTags`

**Example - Confirming Predicted Tags:**
```json
{
  "isConfirmed": true,
  "finalTags": [
    { "key": "category", "value": "t-shirt" }
  ]
}
```

**Example - Correcting Classification:**
```json
{
  "isConfirmed": true,
  "finalTags": [
    { "key": "category", "value": "shirt" },
    { "key": "season", "value": "summer" },
    { "key": "style", "value": "casual" }
  ]
}
```

### 2.4 Delete Clothing Item
```
DELETE /clothing-items/:id
```

**Response (204):**
No content

### 2.5 List User's Clothing Items
```
GET /clothing-items
```

**Query Parameters:**
- `source` (optional): `OWNED` | `IMPORTED`
- `tagKey` (optional): Tag key to filter by (e.g., "category", "color")
- `tagValue` (optional): Tag value to filter by (requires tagKey)
- `search` (optional): Keyword search in name/description
- `page` (optional, default: 1): Page number
- `limit` (optional, default: 20): Items per page

**Example:**
```
GET /clothing-items?source=OWNED&tagKey=category&tagValue=t-shirt&page=1&limit=20
GET /clothing-items?tagKey=season&tagValue=summer&search=blue
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "items": [ /* Array of ClothingItem objects */ ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total": 45,
      "totalPages": 3
    }
  }
}
```

### 2.6 Search Clothing Items
```
POST /clothing-items/search
```

**Request Body:**
```json
{
  "query": "blue shirt",
  "filters": {
    "source": "OWNED",
    "tags": [
      { "key": "category", "value": "t-shirt" },
      { "key": "category", "value": "shirt" },
      { "key": "style", "value": "casual" },
      { "key": "season", "value": "summer" }
    ]
  },
  "page": 1,
  "limit": 20
}
```

**Current implementation note:** 

**Phase 1 Classification:**
- Backend auto-predicts only `category` tag during upload
- Supported category values (9 basic types): `dress`, `hat`, `longsleeve`, `outwear`, `pants`, `shirt`, `shoes`, `shorts`, `t-shirt`
- Classification runs synchronously during `POST /clothing-items` before 3D generation
- `season`, `style`, and `audience` tags are valid for search but must be user-supplied via `PATCH /clothing-items/:id`

**Future Expansion:**
- Phase 2+ will add 27 additional clothing types
- Additional auto-classification attributes may be added in future phases

**Response (200):**
```json
{
  "success": true,
  "data": {
    "items": [ /* Array of ClothingItem objects */ ],
    "pagination": { /* pagination info */ }
  }
}
```

**Note:** Search uses `finalTags` only (not `predictedTags`). Multiple tags with the same key are treated as OR conditions, different keys as AND conditions.

---

## 3. Wardrobes

### 3.1 Create Wardrobe
```
POST /wardrobes
```

**Request Body:**
```json
{
  "name": "Summer Collection",
  "description": "Light clothes for summer"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "wardrobe-001",
    "userId": "user-123",
    "name": "Summer Collection",
    "type": "REGULAR",
    "description": "Light clothes for summer",
    "itemCount": 0,
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T10:30:00Z"
  }
}
```

### 3.2 Get Wardrobe
```
GET /wardrobes/:id
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "wardrobe-virtual-001",
    "userId": "user-123",
    "name": "Virtual Wardrobe",
    "type": "VIRTUAL",
    "description": "Imported creator content",
    "isSystemManaged": true,
    "systemKey": "DEFAULT_VIRTUAL_IMPORTED",
    "itemCount": 23,
    "createdAt": "2026-04-01T08:00:00Z",
    "updatedAt": "2026-04-01T08:00:00Z"
  }
}
```

**Current implementation note:** `isSystemManaged` and `systemKey` are read-only system fields on virtual wardrobes. Regular wardrobes should return `false` and `null` respectively.

### 3.3 List User's Wardrobes
```
GET /wardrobes
```

**Query Parameters:**
- `type` (optional): `REGULAR` | `VIRTUAL`

**Response (200):**
```json
{
  "success": true,
  "data": {
    "wardrobes": [ /* Array of Wardrobe objects */ ]
  }
}
```

**Current implementation note:** every wardrobe object in list responses includes `isSystemManaged` and `systemKey`. Public and consumer-facing clients should treat those fields as read-only.

### 3.4 Update Wardrobe
```
PATCH /wardrobes/:id
```

**Request Body:**
```json
{
  "name": "Updated Name",
  "description": "Updated description"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": { /* Updated Wardrobe object */ }
}
```

### 3.5 Delete Wardrobe
```
DELETE /wardrobes/:id
```

**Response (204):**
No content

### 3.6 Add Item to Wardrobe
```
POST /wardrobes/:id/items
```

**Request Body:**
```json
{
  "clothingItemId": "item-001"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "wardrobe-item-001",
    "wardrobeId": "wardrobe-001",
    "clothingItemId": "item-001",
    "addedAt": "2024-01-15T10:30:00Z"
  }
}
```

### 3.7 Remove Item from Wardrobe
```
DELETE /wardrobes/:id/items/:clothingItemId
```

**Response (204):**
No content

### 3.8 List Wardrobe Items
```
GET /wardrobes/:id/items
```

**Query Parameters:**
- `page` (optional, default: 1)
- `limit` (optional, default: 50)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "items": [ /* Array of ClothingItem objects */ ],
    "pagination": { /* pagination info */ }
  }
}
```

### 3.9 Get System Virtual Wardrobe
```
GET /wardrobes/system/virtual
```

**Response (200):**
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

**Behavior:**
- Returns the current user's imported-content wardrobe
- Creates the virtual wardrobe on first access if it does not already exist
- Import flows must use the same backend service; frontend does not need to pre-create this resource

---

## 4. Outfits And Outfit Preview

### 4.1 Create Outfit Preview Task
```
POST /outfit-preview-tasks
```

**Request Body (multipart/form-data):**
```text
person_image: <file>
person_view_type: FULL_BODY | UPPER_BODY
clothing_item_ids[]: item-001, item-002
garment_categories[]: TOP, BOTTOM
```

**Rules:**
- `person_image` is the only uploaded person photo
- Clothing inputs must reference existing user-accessible clothing items
- `clothing_item_ids[]` and `garment_categories[]` must be aligned one-to-one
- Backend performs light validation only; complex category inference stays in frontend

**Response (202):**
```json
{
  "success": true,
  "data": {
    "id": "preview-task-001",
    "status": "PENDING",
    "clothingItemIds": ["item-001", "item-002"],
    "personViewType": "FULL_BODY",
    "garmentCategories": ["TOP", "BOTTOM"],
    "createdAt": "2026-04-02T12:00:00Z"
  }
}
```

### 4.2 Get Outfit Preview Task
```
GET /outfit-preview-tasks/:id
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "preview-task-001",
    "status": "COMPLETED",
    "previewImageUrl": "/files/outfit-previews/user-123/preview-task-001/result.png",
    "errorCode": null,
    "errorMessage": null,
    "createdAt": "2026-04-02T12:00:00Z",
    "startedAt": "2026-04-02T12:00:03Z",
    "completedAt": "2026-04-02T12:00:21Z"
  }
}
```

### 4.3 List My Outfit Preview Tasks
```
GET /outfit-preview-tasks
```

**Query Parameters:**
- `page` (optional, default: 1)
- `limit` (optional, default: 20)
- `status` (optional): `PENDING` | `PROCESSING` | `COMPLETED` | `FAILED`

### 4.4 Save Successful Preview As Outfit
```
POST /outfit-preview-tasks/:id/save
```

**Request Body:**
```json
{
  "name": "Casual Friday"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "outfit-001",
    "userId": "user-123",
    "previewTaskId": "preview-task-001",
    "name": "Casual Friday",
    "previewImageUrl": "/files/outfit-previews/user-123/preview-task-001/result.png",
    "items": [
      { "clothingItemId": "item-001" },
      { "clothingItemId": "item-002" }
    ],
    "createdAt": "2026-04-02T12:01:00Z",
    "updatedAt": "2026-04-02T12:01:00Z"
  }
}
```

### 4.5 Get Outfit
```
GET /outfits/:id
```

### 4.6 List User's Outfits
```
GET /outfits
```

**Query Parameters:**
- `page` (optional, default: 1)
- `limit` (optional, default: 20)

### 4.7 Update Outfit Metadata
```
PATCH /outfits/:id
```

**Request Body:**
```json
{
  "name": "Updated Name"
}
```

### 4.8 Delete Outfit
```
DELETE /outfits/:id
```

---

## 5. Card Packs (Creator Content)

**Current implementation notes for frontend:**
- `GET /card-packs/:id` is dual-mode. Owner can read `DRAFT` / `PUBLISHED` / `ARCHIVED`; public callers only receive `PUBLISHED`.
- `GET /creators/:creatorId/card-packs` is also dual-mode. Public callers only receive `PUBLISHED`; the creator themself receives all statuses.
- Current response payload uses `coverImage`, not `coverImageUrl`.
- Current list response shape is `{ success, data: { items, pagination } }`, not `{ packs, pagination }`.
- Current create/update/detail payloads return full pack objects with nested `items`; there is no top-level `itemIds` array in the response.
- `DELETE /card-packs/:id` currently allows deleting owner-owned `PUBLISHED` packs as well as `DRAFT` packs. Frontend should treat delete as a destructive action and require confirmation for published packs.
- When deleting a creator item that belongs to a published pack, backend returns `409` with a user-facing message instructing the user to delete the published pack first.
- State-changing endpoints now use row locks and return `409` on transaction / uniqueness conflicts. Frontend should treat these as retry-or-refresh situations, not as generic server errors.

### 5.1 Create Card Pack
```
POST /card-packs
```

**Request Body:**
```json
{
  "name": "Summer Essentials 2024",
  "description": "Must-have items for summer",
  "type": "CLOTHING_COLLECTION",
  "itemIds": ["item-001", "item-002", "item-003"],
  "coverImage": "packs/cover.jpg"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "pack-001",
    "creatorId": "creator-456",
    "name": "Summer Essentials 2024",
    "type": "CLOTHING_COLLECTION",
    "status": "DRAFT",
    "description": "Must-have items for summer",
    "coverImage": "packs/cover.jpg",
    "shareId": null,
    "importCount": 0,
    "itemCount": 3,
    "archivedAt": null,
    "createdAt": "2024-01-15T10:30:00Z",
    "publishedAt": null,
    "updatedAt": "2024-01-15T10:30:00Z",
    "items": [
      {
        "id": "pack-item-001",
        "creatorItemId": "item-001",
        "sortOrder": 0,
        "name": "White Shirt",
        "description": "Relaxed fit",
        "catalogVisibility": "PACK_ONLY",
        "processingStatus": "COMPLETED",
        "coverUrl": "/files/items/item-001/front.jpg",
        "finalTags": [
          { "key": "category", "value": "shirt" }
        ],
        "createdAt": "2024-01-15T10:30:00Z"
      }
    ]
  }
}
```

**Frontend handling:**
- `itemIds` is write-only in create/update requests. Use `data.items[*].creatorItemId` when you need selected item ids after persistence.
- `coverImage` is currently treated as a storage path string. Frontend should not send base64 here unless backend upload flow changes.

### 5.2 Get Card Pack
```
GET /card-packs/:id
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    /* CardPack object with populated ClothingItem details */
  }
}
```

**Frontend handling:**
- If creator opens their own draft or archived pack, the same endpoint works with auth.
- If a public caller or another user requests a non-published pack, backend returns `404`, not `403`.

### 5.3 Get Card Pack by Share Link
```
GET /card-packs/share/:shareId
```

**Response (200):**
```json
{
  "success": true,
  "data": { /* CardPack object */ }
}
```

### 5.4 List Creator's Card Packs
```
GET /creators/:creatorId/card-packs
```

**Query Parameters:**
- `page` (optional, default: 1)
- `limit` (optional, default: 20)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "items": [ /* Array of CardPack summary objects */ ],
    "pagination": { /* pagination info */ }
  }
}
```

**Frontend handling:**
- There is no `status` query parameter in the current backend.
- Frontend should infer visibility from auth:
  - with creator auth on own profile, expect `DRAFT` / `PUBLISHED` / `ARCHIVED`
  - otherwise expect only `PUBLISHED`

### 5.5 Update Card Pack
```
PATCH /card-packs/:id
```

**Request Body:**
```json
{
  "name": "Updated Name",
  "description": "Updated description",
  "itemIds": ["item-001", "item-002", "item-003", "item-004"]
}
```

**Response (200):**
```json
{
  "success": true,
  "data": { /* Updated CardPack object */ }
}
```

**Conflict cases the frontend should surface directly:**
- `409 Published packs cannot change items`
- `409 Archived packs cannot be updated`
- `409 Card pack update conflicts with current database state`

### 5.6 Publish Card Pack
```
POST /card-packs/:id/publish
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    /* CardPack object with status: "PUBLISHED", publishedAt, and shareLink */
  }
}
```

**Conflict cases the frontend should surface directly:**
- `409 Pack cannot be published`
- `409 Pack must contain at least one item`
- `409 All pack items must be processed before publishing`
- `409 Card pack publish conflicts with current database state`

### 5.7 Archive Card Pack
```
POST /card-packs/:id/archive
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    /* CardPack object with status: "ARCHIVED" */
  }
}
```

**Conflict cases the frontend should surface directly:**
- `409 Pack cannot be archived`
- `409 Card pack archive conflicts with current database state`

### 5.8 Delete Card Pack
```
DELETE /card-packs/:id
```

**Current implementation note:** Owner can currently delete both `DRAFT` and `PUBLISHED` packs. `ARCHIVED` packs are also deletable if the owner explicitly calls delete. This is implementation behavior and may be tightened later, so frontend should not hard-code a stricter local rule than the backend.

**Response (204):**
No content

**Conflict cases the frontend should surface directly:**
- `409 Card pack delete conflicts with current database state`

### 5.9 Creator Item Delete Guard
```
DELETE /creator-items/:id
```

**Current implementation note:** If the item belongs to any published pack, backend returns:

```json
{
  "detail": "Creator item belongs to a published pack. Delete the published pack first."
}
```

**Frontend handling:**
- Show this message directly in the delete flow.
- Offer a secondary action that routes the creator to pack management instead of retrying the same delete.

---

## 6. Import Operations

### 6.1 Import Card Pack
```
POST /imports/card-pack
```

**Request Body:**
```json
{
  "cardPackId": "pack-001",
  "requestId": "import-user-123-pack-001-20260402"
}
```

**Idempotency behavior:**
- The backend deduplicates by `(userId, requestId)`
- Repeating the same `requestId` for the same `cardPackId` must return the original import record or current import status instead of creating a new import
- Repeating the same `requestId` for a different `cardPackId` should be treated as a conflict
- Clients should send `requestId` for every import call

**Response (201):**
```json
{
  "success": true,
  "data": {
    "importId": "import-001",
    "cardPackId": "pack-001",
    "status": "COMPLETED",
    "itemsImported": 3,
    "importedItems": [
      { /* ClothingItem object with provenance */ }
    ],
    "virtualWardrobeId": "wardrobe-virtual-001",
    "importedAt": "2024-01-15T10:30:00Z"
  }
}
```

### 6.2 Get Import History
```
GET /imports/history
```

**Query Parameters:**
- `page` (optional, default: 1)
- `limit` (optional, default: 20)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "imports": [
      {
        "id": "import-001",
        "userId": "user-123",
        "cardPackId": "pack-001",
        "cardPackName": "Summer Essentials 2024",
        "creatorId": "creator-456",
        "creatorName": "FashionGuru",
        "status": "COMPLETED",
        "itemCount": 3,
        "importedAt": "2024-01-15T10:30:00Z"
      }
    ],
    "pagination": { /* pagination info */ }
  }
}
```

---

## 7. Creators

### 7.1 Get Creator Profile
```
GET /creators/:id
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "userId": "creator-456",
    "username": "fashionguru",
    "status": "ACTIVE",
    "displayName": "Fashion Guru",
    "brandName": "FG Fashion",
    "bio": "Sharing fashion inspiration",
    "avatarUrl": "/images/creator-456-avatar.jpg",
    "websiteUrl": "https://fashionguru.com",
    "socialLinks": {
      "instagram": "https://instagram.com/fashionguru",
      "tiktok": "https://tiktok.com/@fashionguru"
    },
    "followerCount": 1250,
    "packCount": 15,
    "isVerified": true,
    "verifiedAt": "2024-01-01T00:00:00Z",
    "createdAt": "2024-01-01T00:00:00Z"
  }
}
```

**Status values:** `PENDING` | `ACTIVE` | `SUSPENDED`
```

### 7.2 List Creators
```
GET /creators
```

**Query Parameters:**
- `verified` (optional): `true` | `false`
- `search` (optional): Search by name
- `page` (optional, default: 1)
- `limit` (optional, default: 20)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "creators": [ /* Array of Creator objects */ ],
    "pagination": { /* pagination info */ }
  }
}
```

### 7.3 Get Creator Items
```
GET /creators/:creatorId/items
```

**Query Parameters:**
- `page` (optional, default: 1)
- `limit` (optional, default: 20)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "items": [ /* Array of Creator Item objects */ ],
    "pagination": { /* pagination info */ }
  }
}
```

**Visibility rules:**
- Public callers only receive items where `catalogVisibility != PRIVATE`
- The creator themselves can see their full catalog, including private items

### 7.4 Update Creator Profile
```
PATCH /creators/:id
```

**Request Body:**
```json
{
  "brandName": "Updated Brand",
  "bio": "Updated bio",
  "websiteUrl": "https://newsite.com",
  "socialLinks": { /* updated social links */ }
}
```

**Response (200):**
```json
{
  "success": true,
  "data": { /* Updated Creator object */ }
}
```

### 7.5 Get My Creator Profile
```
GET /creators/me/profile
```

**Purpose:**
- Returns the authenticated creator's full editable profile
- Used by `Profile -> Creator Center`

### 7.6 Get My Creator Dashboard
```
GET /creators/me/dashboard
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "packCount": 12,
    "publishedPackCount": 7,
    "importCount": 134,
    "draftCount": 5
  }
}
```

### 7.7 Create Creator Item
```
POST /creator-items
```

**Request Body:**
- Same multipart fields as `POST /clothing-items`
- Optional `catalogVisibility`: `PRIVATE` | `PACK_ONLY` | `PUBLIC`

**Response (202):**
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

### 7.8 Get Creator Item
```
GET /creator-items/:id
```

### 7.9 Update Creator Item
```
PATCH /creator-items/:id
```

**Allowed Fields:**
- `name`
- `description`
- `finalTags`
- `customTags`
- `catalogVisibility`

### 7.10 Delete Creator Item
```
DELETE /creator-items/:id
```

**Conflict Note:**
- If the item belongs to a published pack, backend returns `409`
- Frontend should surface the backend message directly instead of collapsing it into a retry toast

---

## 8. Image Processing

### 8.1 Upload Image
```
POST /images/upload
```

**Request Body (multipart/form-data):**
```
image: <file>
type: "clothing" | "profile" | "cover"
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "imageId": "img-001",
    "url": "/images/img-001.jpg",
    "thumbnailUrl": "/images/img-001-thumb.jpg",
    "uploadedAt": "2024-01-15T10:30:00Z"
  }
}
```

### 8.2 Process Background Removal
```
POST /images/:id/remove-background
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "originalUrl": "/images/img-001.jpg",
    "processedUrl": "/images/img-001-nobg.png",
    "processedAt": "2024-01-15T10:30:15Z"
  }
}
```

### 8.3 Generate Multi-Angle Views
```
POST /images/:id/generate-angles
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "angleViews": {
      "0": "/images/img-001-angle-0.png",
      "45": "/images/img-001-angle-45.png",
      "90": "/images/img-001-angle-90.png",
      "135": "/images/img-001-angle-135.png",
      "180": "/images/img-001-angle-180.png",
      "225": "/images/img-001-angle-225.png",
      "270": "/images/img-001-angle-270.png",
      "315": "/images/img-001-angle-315.png"
    },
    "generatedAt": "2024-01-15T10:30:30Z"
  }
}
```

### 8.4 Get Processing Status
```
GET /clothing-items/:id/processing-status
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "status": "PROCESSING",
    "progress": 60,
    "steps": {
      "upload": "completed",
      "classification": "completed",
      "backgroundRemoval": "completed",
      "modelGeneration": "processing",
      "angleRendering": "pending"
    },
    "errorMessage": null
  }
}
```

**Status values:** `PENDING` | `PROCESSING` | `COMPLETED` | `FAILED`

**Processing step values:** `pending` | `processing` | `completed` | `failed`

**Classification Flow:**
1. **Upload Phase**: Frontend uploads images via `POST /clothing-items`
2. **Synchronous Classification**: Backend immediately runs AI classification on front image
3. **Async 3D Pipeline**: Backend then enqueues background removal → 3D generation → angle rendering
4. **Early Tag Access**: Since classification completes synchronously, `steps.classification` is always `completed` when processing status is queried
5. **Frontend Strategy**: Call `GET /clothing-items/:id` immediately after upload to get `predictedTags` and initial `finalTags`, without waiting for 3D generation to finish

**Tag availability note:**
- Classification happens synchronously during `POST /clothing-items`, NOT as part of the async processing pipeline
- `predictedTags` and initial `finalTags` are available immediately after the upload request returns
- Frontend can display tags and allow user editing while 3D generation continues in background
- `GET /clothing-items/:id/processing-status` tracks only the async 3D pipeline steps

**FAILED example:**
```json
{
  "success": true,
  "data": {
    "status": "FAILED",
    "progress": 25,
    "steps": {
      "upload": "completed",
      "classification": "completed",
      "backgroundRemoval": "failed",
      "modelGeneration": "pending",
      "angleRendering": "pending"
    },
    "errorMessage": "Background removal failed"
  }
}
```

### 8.5 Retry Failed Processing
```
POST /clothing-items/:id/retry
```

**Response (202):**
```json
{
  "success": true,
  "data": {
    "id": "item-001",
    "processingTaskId": "task-002",
    "status": "PENDING"
  }
}
```

**Retry rules:**
- Latest task must be `FAILED`.
- If the clothing item already has an active `PENDING` or `PROCESSING` task, retry returns `409 Conflict`.
- Retry preserves the original uploads, removes previous derived outputs, and creates a brand new processing task for auditability.

### 8.6 Get Angle Views
```
GET /clothing-items/:id/angle-views
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "angleViews": {
      "0": "/images/item-001-angle-0.png",
      "45": "/images/item-001-angle-45.png",
      "90": "/images/item-001-angle-90.png",
      "135": "/images/item-001-angle-135.png",
      "180": "/images/item-001-angle-180.png",
      "225": "/images/item-001-angle-225.png",
      "270": "/images/item-001-angle-270.png",
      "315": "/images/item-001-angle-315.png"
    }
  }
}
```

### 8.7 Download 3D Model
```
GET /clothing-items/:id/model
```

**Response (200):**
Returns the GLB file as binary with `Content-Type: model/gltf-binary`.

---

## 9. AI Classification

### 9.1 Classify Clothing Item
AI classification is included in `POST /clothing-items`; there is no standalone `POST /ai/classify` endpoint in the current backend.

**Behavior:**
- `POST /clothing-items` synchronously runs classification on the uploaded front image before the async 3D pipeline is dispatched
- The created clothing item immediately stores `predictedTags`, copies them into initial `finalTags`, and sets `isConfirmed` to `false`
- `GET /clothing-items/{id}/processing-status` includes a `classification` step. When it is `completed`, the frontend can call `GET /clothing-items/{id}` to read tags before 3D generation finishes
- User tag edits are submitted through `PATCH /clothing-items/{id}` and must not be overwritten by later 3D processing

---

## 10. User Profile

### 10.1 Get User Profile
```
GET /users/:id
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "user-123",
    "username": "johndoe",
    "email": "john@example.com",
    "type": "CONSUMER",
    "profile": {
      "displayName": "John Doe",
      "avatarUrl": "/images/user-123-avatar.jpg",
      "bio": "Fashion enthusiast"
    },
    "createdAt": "2024-01-01T00:00:00Z",
    "updatedAt": "2024-01-15T10:30:00Z"
  }
}
```

### 10.2 Update User Profile
```
PATCH /users/:id
```

**Request Body:**
```json
{
  "profile": {
    "displayName": "John Doe Updated",
    "bio": "Updated bio"
  }
}
```

**Response (200):**
```json
{
  "success": true,
  "data": { /* Updated User object */ }
}
```

### 10.3 Get Current User Context
```
GET /me
```

**Response (200):**
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

---

## 10. Styled Generations (DreamO)

> **New module**: Personalized scene outfit generation using DreamO. Does NOT modify existing clothing-items endpoints.

### 10.1 Create Styled Generation
```
POST /styled-generations
```

**Request Body (multipart/form-data):**
```
selfie_image: <file>                     (required, JPEG/PNG, max 10 MB)
clothing_item_id: "item-uuid"            (required, must have PROCESSED_FRONT)
scene_prompt: "standing in a cafe..."    (required)
negative_prompt: "blurry, bad anatomy"   (optional)
guidance_scale: 4.5                      (optional, default 4.5, range 1.0-10.0)
seed: -1                                 (optional, -1 = random)
width: 1024                              (optional, 768-1024)
height: 1024                             (optional, 768-1024)
```

**Response (202 Accepted):**
```json
{
  "id": "gen-uuid",
  "status": "PENDING",
  "estimatedTime": 120
}
```

**Error responses:**
- `404` - Clothing item not found
- `409` - Clothing item has not finished processing (no PROCESSED_FRONT image)
- `413` - Selfie image exceeds size limit
- `422` - Validation error (invalid UUID, invalid dimensions, not an image)
- `503` - Processing queue unavailable

### 10.2 Get Styled Generation
```
GET /styled-generations/:id
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "gen-uuid",
    "userId": "user-uuid",
    "sourceClothingItemId": "item-uuid",
    "selfieOriginalUrl": "/files/.../selfie_original.jpg",
    "selfieProcessedUrl": "/files/.../selfie_processed.png",
    "scenePrompt": "standing in a coffee shop, warm light",
    "negativePrompt": null,
    "dreamoVersion": "v1.1",
    "status": "SUCCEEDED",
    "progress": 100,
    "resultImageUrl": "/files/.../result.png",
    "failureReason": null,
    "guidanceScale": 4.5,
    "seed": 42,
    "width": 1024,
    "height": 1024,
    "createdAt": "2026-04-13T10:00:00Z",
    "updatedAt": "2026-04-13T10:02:30Z"
  }
}
```

**Status values:** `PENDING` | `PROCESSING` | `SUCCEEDED` | `FAILED`

### 10.3 List Styled Generations
```
GET /styled-generations?page=1&limit=20
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "items": [ /* Array of StyledGeneration objects */ ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total": 5,
      "totalPages": 1
    }
  }
}
```

### 10.4 Retry Failed Generation
```
POST /styled-generations/:id/retry
```

Only allowed when status is `FAILED`.

**Response (202):**
```json
{
  "id": "gen-uuid",
  "status": "PENDING",
  "estimatedTime": 120
}
```

### 10.5 Delete Styled Generation
```
DELETE /styled-generations/:id
```

Cannot delete while status is `PENDING` or `PROCESSING` (returns 409).

**Response (204):**
No content.

---

## 11. Card Pack Import / Un-import

### 11.1 Import Card Pack
```
POST /imports/card-pack
```

**Request Body:**
```json
{
  "card_pack_id": "pack-uuid"
}
```

**Response (201):**
```json
{
  "cardPackId": "pack-uuid",
  "importedItemIds": ["item-1", "item-2", "item-3"]
}
```

**Error responses:**
- `404` — Pack not found or not published
- `409` — Pack already imported by this user

### 11.2 Un-import Card Pack
```
DELETE /imports/card-pack/{pack_id}
```

Removes the import record and all clothing_items that originated from this pack for the current user.

**Response (204):** No content

### 11.3 Delete Clothing Item
```
DELETE /clothing-items/{id}
```

Permanently deletes a clothing item (OWNED or IMPORTED) and releases blob storage references.

**Response (204):** No content

**Error responses:**
- `404` — Item not found
- `409` — Cannot delete while processing (active PENDING/PROCESSING task)

### 11.4 Archive Card Pack
```
POST /card-packs/{id}/archive
```

Archives a published card pack (hides from discovery). Existing imports are unaffected.

**Response (200):** Updated card pack object

### 11.5 URL Format Change

All file URLs now use business paths instead of raw storage paths:
- Clothing images: `/files/clothing-items/{id}/{kind}` where kind is `original-front`, `processed-front`, `angle-0`..`angle-315`, `model`
- Creator items: `/files/creator-items/{id}/{kind}`
- Styled generations: `/files/styled-generations/{id}/{kind}` where kind is `selfie-original`, `selfie-processed`, `result`
- Card pack covers: `/files/card-packs/{id}/cover`
- Outfit previews: `/files/outfit-preview-tasks/{id}/preview` or `/files/outfits/{id}/preview`

---

## Error Codes

### Authentication Errors
- `AUTH_001` - Invalid credentials
- `AUTH_002` - Token expired
- `AUTH_003` - Token invalid
- `AUTH_004` - Insufficient permissions

### Validation Errors
- `VAL_001` - Missing required field
- `VAL_002` - Invalid field format
- `VAL_003` - Field value out of range
- `VAL_004` - Invalid enum value

### Resource Errors
- `RES_001` - Resource not found
- `RES_002` - Resource already exists
- `RES_003` - Resource conflict
- `RES_004` - Cannot delete resource (has dependencies)

### Business Logic Errors
- `BIZ_001` - Cannot add item to wardrobe (already exists)
- `BIZ_002` - Cannot delete published card pack
- `BIZ_003` - Cannot import own card pack
- `BIZ_004` - Virtual wardrobe cannot be deleted
- `BIZ_005` - Insufficient items for outfit

### Processing Errors
- `PROC_001` - Image processing failed
- `PROC_002` - Background removal failed
- `PROC_003` - Angle generation failed
- `PROC_004` - Classification failed

### Rate Limiting
- `RATE_001` - Too many requests
- `RATE_002` - Upload quota exceeded

---

## Rate Limits

### Per User
- Authentication: 10 requests/minute
- Clothing Items: 100 requests/minute
- Image Upload: 20 uploads/hour
- Search: 60 requests/minute
- Other endpoints: 120 requests/minute

### Response Headers
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1642248000
```

---

## Webhooks (Future Phase)

### Events
- `clothing_item.created`
- `clothing_item.updated`
- `clothing_item.deleted`
- `card_pack.published`
- `card_pack.imported`
- `outfit.created`

### Webhook Payload
```json
{
  "event": "clothing_item.created",
  "timestamp": "2024-01-15T10:30:00Z",
  "data": { /* Event-specific data */ }
}
```

---

## Pagination

All list endpoints support pagination with consistent parameters:

**Query Parameters:**
- `page` (default: 1): Page number
- `limit` (default: 20, max: 100): Items per page

**Response Format:**
```json
{
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 150,
    "totalPages": 8,
    "hasNext": true,
    "hasPrev": false
  }
}
```

---

## Versioning

API versioning is handled via URL path:
- Current: `/api/v1`
- Future: `/api/v2`

Breaking changes will result in a new version. Non-breaking changes will be added to existing versions.

---

## SDK Support (Future)

Official SDKs will be provided for:
- Flutter/Dart (primary)
- JavaScript/TypeScript
- Python
- Swift (iOS native)
- Kotlin (Android native)
