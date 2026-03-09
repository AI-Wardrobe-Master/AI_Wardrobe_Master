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

**Current implementation note:** Module 2 demo backend still uses a fixed demo user internally and does not enforce real JWT verification yet.

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

**Response (202 Accepted):**

> Returns 202 instead of 201 because 3D model generation and angle rendering are processed asynchronously (~30s). Client should poll the processing-status endpoint.

```json
{
  "success": true,
  "data": {
    "id": "item-001",
    "processingTaskId": "task-001",
    "status": "PROCESSING",
    "estimatedTime": 30
  }
}
```

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
  "data": { /* ClothingItem object */ }
}
```

**Current implementation notes:**
- The detail response now includes `customTags`.
- Automatic prediction currently only fills `category`. `season`, `style`, and `audience` are expected to be user-added later through `PATCH /clothing-items/:id`.

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

**Current implementation note:** the backend currently auto-predicts only `category`, and the supported values are `dress`, `hat`, `longsleeve`, `outwear`, `pants`, `shirt`, `shoes`, `shorts`, `t-shirt`. `season`, `style`, and `audience` remain valid searchable tags, but are expected to be user-supplied in `finalTags`.

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
  "data": { /* Wardrobe object */ }
}
```

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

---

## 4. Outfits

### 4.1 Create Outfit
```
POST /outfits
```

**Request Body:**
```json
{
  "name": "Casual Friday",
  "description": "Comfortable office look",
  "items": [
    {
      "clothingItemId": "item-001",
      "layer": 0,
      "position": { "x": 0.5, "y": 0.3 },
      "scale": 1.0,
      "rotation": 0
    },
    {
      "clothingItemId": "item-002",
      "layer": 1,
      "position": { "x": 0.5, "y": 0.6 },
      "scale": 1.0,
      "rotation": 0
    }
  ]
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "outfit-001",
    "userId": "user-123",
    "name": "Casual Friday",
    "description": "Comfortable office look",
    "thumbnailUrl": "/images/outfit-001-thumb.jpg",
    "items": [ /* Array of OutfitItem objects */ ],
    "createdAt": "2024-01-15T10:30:00Z",
    "updatedAt": "2024-01-15T10:30:00Z"
  }
}
```

### 4.2 Get Outfit
```
GET /outfits/:id
```

**Response (200):**
```json
{
  "success": true,
  "data": { /* Outfit object with populated ClothingItem details */ }
}
```

### 4.3 List User's Outfits
```
GET /outfits
```

**Query Parameters:**
- `page` (optional, default: 1)
- `limit` (optional, default: 20)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "outfits": [ /* Array of Outfit objects */ ],
    "pagination": { /* pagination info */ }
  }
}
```

### 4.4 Update Outfit
```
PATCH /outfits/:id
```

**Request Body:**
```json
{
  "name": "Updated Name",
  "description": "Updated description",
  "items": [ /* Updated OutfitItem array */ ]
}
```

**Response (200):**
```json
{
  "success": true,
  "data": { /* Updated Outfit object */ }
}
```

### 4.5 Delete Outfit
```
DELETE /outfits/:id
```

**Response (204):**
No content

### 4.6 Generate Outfit Thumbnail
```
POST /outfits/:id/thumbnail
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "thumbnailUrl": "/images/outfit-001-thumb.jpg"
  }
}
```

---

## 5. Card Packs (Creator Content)

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
  "coverImage": "<base64_encoded_image>"
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
    "description": "Must-have items for summer",
    "coverImageUrl": "/images/pack-001-cover.jpg",
    "type": "CLOTHING_COLLECTION",
    "itemIds": ["item-001", "item-002", "item-003"],
    "itemCount": 3,
    "shareLink": "https://app.com/pack/pack-001",
    "status": "DRAFT",
    "importCount": 0,
    "createdAt": "2024-01-15T10:30:00Z",
    "publishedAt": null,
    "updatedAt": "2024-01-15T10:30:00Z"
  }
}
```

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
- `status` (optional): `DRAFT` | `PUBLISHED` | `ARCHIVED`
- `page` (optional, default: 1)
- `limit` (optional, default: 20)

**Response (200):**
```json
{
  "success": true,
  "data": {
    "packs": [ /* Array of CardPack objects */ ],
    "pagination": { /* pagination info */ }
  }
}
```

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

### 5.6 Publish Card Pack
```
POST /card-packs/:id/publish
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    /* CardPack object with status: "PUBLISHED" and publishedAt timestamp */
  }
}
```

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

### 5.8 Delete Card Pack
```
DELETE /card-packs/:id
```

**Note:** Only DRAFT packs can be deleted. Published packs must be archived first.

**Response (204):**
No content

---

## 6. Import Operations

### 6.1 Import Card Pack
```
POST /imports/card-pack
```

**Request Body:**
```json
{
  "cardPackId": "pack-001"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "importId": "import-001",
    "cardPackId": "pack-001",
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
    "verifiedAt": "2024-01-01T00:00:00Z"
  }
}
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

### 7.3 Update Creator Profile
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
      "backgroundRemoval": "completed",
      "modelGeneration": "processing",
      "angleRendering": "pending"
    },
    "errorMessage": null
  }
}
```

**Status values:** `PENDING` | `PROCESSING` | `COMPLETED` | `FAILED`

### 8.5 Retry Failed Processing
```
POST /clothing-items/:id/retry
```

**Response (202):**
```json
{
  "success": true,
  "data": {
    "processingTaskId": "task-002",
    "status": "PROCESSING"
  }
}
```

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
```
POST /ai/classify
```

**Request Body:**
```json
{
  "imageUrl": "/images/img-001.jpg"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "predictedTags": [
      { "key": "category", "value": "T_SHIRT" },
      { "key": "color", "value": "blue" },
      { "key": "color", "value": "white" },
      { "key": "pattern", "value": "striped" },
      { "key": "style", "value": "casual" },
      { "key": "season", "value": "summer" },
      { "key": "audience", "value": "unisex" }
    ]
  }
}
```

**Note:** The response returns an array of Tag objects. Each tag has a `key` (attribute type) and `value` (attribute value). No confidence scores are included.

**Tag Confirmation Flow:**
1. Frontend receives `predictedTags` from this endpoint
2. User reviews the predicted tags in the UI
3. User can accept or modify the tags
4. Frontend calls `PATCH /clothing-items/:id` with `finalTags` and `isConfirmed: true`
5. Backend stores the confirmed tags in `final_tags` column

See section **2.3 Update Clothing Item** for the tag confirmation API.

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
