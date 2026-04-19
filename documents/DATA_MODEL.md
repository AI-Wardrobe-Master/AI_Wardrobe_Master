# AI Wardrobe Master - Data Model

## Overview
This document defines the data model for the AI Wardrobe Master application Phase 1, including entities, relationships, and key attributes.

---

## Core Principles

1. **Single Source of Truth**: Clothing items are stored once, referenced by multiple wardrobes
2. **Source Isolation**: Clear separation between owned and imported items
3. **Provenance Tracking**: Full traceability for imported content
4. **Referential Integrity**: Deleting containers (wardrobes, outfits) never deletes clothing entities

---

## Entity Relationship Diagram

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   User      │────────<│  Wardrobe    │>────────│  Clothing   │
└─────────────┘         └──────────────┘         │   Item      │
      │                        │                  └─────────────┘
      │                        │                         │
      │                        │                         │
      │                 ┌──────────────┐                │
      └────────────────<│    Outfit    │>───────────────┘
                        └──────────────┘
                               │
                               │
                        ┌──────────────┐
                        │ OutfitItem   │
                        │ (Position)   │
                        └──────────────┘

┌─────────────┐         ┌──────────────┐
│  Creator    │────────<│  CardPack    │>────────┐
└─────────────┘         └──────────────┘         │
                               │                  │
                               └──────────────────┘
                                        │
                                        ▼
                                 ┌─────────────┐
                                 │  Clothing   │
                                 │   Item      │
                                 └─────────────┘
```

---

## Entity Definitions

### 1. User

Represents both consumers and creators in the system.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
class User with _$User {
  const factory User({
    required String id,
    required String username,
    required String email,
    required UserType type,
    required DateTime createdAt,
    required DateTime updatedAt,
    required UserProfile profile,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

@freezed
class UserProfile with _$UserProfile {
  const factory UserProfile({
    String? displayName,
    String? avatarUrl,
    String? bio,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
}

enum UserType {
  @JsonValue('CONSUMER')
  consumer,
  @JsonValue('CREATOR')
  creator,
}
```

**Indexes:**
- Primary: `id`
- Unique: `username`, `email`

---

### 2. ClothingItem

Core entity representing a single piece of clothing.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'clothing_item.freezed.dart';
part 'clothing_item.g.dart';

@freezed
class Tag with _$Tag {
  const factory Tag({
    required String key,
    required String value,
  }) = _Tag;

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);
}

@freezed
class ClothingItem with _$ClothingItem {
  const factory ClothingItem({
    required String id,
    required String userId,
    required ItemSource source,
    Provenance? provenance,
    required ImageSet images,
    required List<Tag> predictedTags,
    required List<Tag> finalTags,
    required bool isConfirmed,
    String? name,
    String? description,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _ClothingItem;

  factory ClothingItem.fromJson(Map<String, dynamic> json) =>
      _$ClothingItemFromJson(json);
}

@freezed
class ImageSet with _$ImageSet {
  const factory ImageSet({
    required String originalFrontUrl,
    String? originalBackUrl,              // optional — back photo is not required
    required String processedFrontUrl,
    String? processedBackUrl,             // null if no back image provided
    required Map<int, String> angleViews,
  }) = _ImageSet;

  factory ImageSet.fromJson(Map<String, dynamic> json) =>
      _$ImageSetFromJson(json);
}

@freezed
class Provenance with _$Provenance {
  const factory Provenance({
    required String sourceType,
    required String originClothingItemId,
    required String importHistoryId,
    required ProvenanceCreator creator,
    ProvenanceCardPack? cardPack,
    required DateTime importedAt,
  }) = _Provenance;

  factory Provenance.fromJson(Map<String, dynamic> json) =>
      _$ProvenanceFromJson(json);
}

@freezed
class ProvenanceCreator with _$ProvenanceCreator {
  const factory ProvenanceCreator({
    required String id,
    required String displayName,
  }) = _ProvenanceCreator;

  factory ProvenanceCreator.fromJson(Map<String, dynamic> json) =>
      _$ProvenanceCreatorFromJson(json);
}

@freezed
class ProvenanceCardPack with _$ProvenanceCardPack {
  const factory ProvenanceCardPack({
    required String id,
    required String name,
  }) = _ProvenanceCardPack;

  factory ProvenanceCardPack.fromJson(Map<String, dynamic> json) =>
      _$ProvenanceCardPackFromJson(json);
}

enum ItemSource {
  @JsonValue('OWNED')
  owned,
  @JsonValue('IMPORTED')
  imported,
}

enum ClothingType {
  // Phase 1: Current Roboflow-supported values (9 basic categories)
  @JsonValue('t-shirt')
  tShirt,
  @JsonValue('shirt')
  shirt,
  @JsonValue('longsleeve')
  longSleeve,
  @JsonValue('pants')
  pants,
  @JsonValue('shorts')
  shorts,
  @JsonValue('outwear')
  outwear,
  @JsonValue('dress')
  dress,
  @JsonValue('shoes')
  shoes,
  @JsonValue('hat')
  hat,

  // Future expansion: Additional types to be supported in later phases
  // Phase 2+ will include:
  // - More tops: BLOUSE, POLO, TANK_TOP, SWEATER, HOODIE, SWEATSHIRT, CARDIGAN
  // - More bottoms: JEANS, TROUSERS, SKIRT, LEGGINGS, SWEATPANTS
  // - More outerwear: JACKET, COAT, BLAZER, PUFFER, WIND_BREAKER, VEST
  // - Full body: JUMPSUIT, ROMPER
  // - More footwear: SNEAKERS, BOOTS, SANDALS, DRESS_SHOES, HEELS, SLIPPERS
  // - More accessories: SCARF, BELT
  // - Fallback: OTHER
}

enum Pattern {
  @JsonValue('SOLID')
  solid,
  @JsonValue('STRIPED')
  striped,
  @JsonValue('CHECKED')
  checked,
  @JsonValue('FLORAL')
  floral,
  @JsonValue('GEOMETRIC')
  geometric,
  @JsonValue('POLKA_DOT')
  polkaDot,
  @JsonValue('ANIMAL_PRINT')
  animalPrint,
  @JsonValue('ABSTRACT')
  abstract,
  @JsonValue('OTHER')
  other,
}

enum Style {
  @JsonValue('CASUAL')
  casual,
  @JsonValue('FORMAL')
  formal,
  @JsonValue('BUSINESS')
  business,
  @JsonValue('SPORTY')
  sporty,
  @JsonValue('BOHEMIAN')
  bohemian,
  @JsonValue('VINTAGE')
  vintage,
  @JsonValue('MINIMALIST')
  minimalist,
  @JsonValue('STREETWEAR')
  streetwear,
  @JsonValue('ELEGANT')
  elegant,
  @JsonValue('OTHER')
  other,
}

enum Season {
  @JsonValue('SPRING')
  spring,
  @JsonValue('SUMMER')
  summer,
  @JsonValue('FALL')
  fall,
  @JsonValue('WINTER')
  winter,
  @JsonValue('ALL_SEASON')
  allSeason,
}

// 当前实现里，style / season / TargetAudience 不由后端自动预测，交给用户手动补充。
enum TargetAudience {
  @JsonValue('MEN')
  men,
  @JsonValue('WOMEN')
  women,
  @JsonValue('UNISEX')
  unisex,
  @JsonValue('KIDS')
  kids,
  @JsonValue('TEEN')
  teen,
}
```

**Indexes:**
- Primary: `id`
- Foreign Key: `userId`
- Composite: `(userId, source)` for filtering owned vs imported
- JSONB GIN Index: `final_tags` for fast tag-based search
- JSONB GIN Index: `predicted_tags` for analytics

**Backend persistence fields for `clothing_items`:**
- `catalog_visibility`: `PRIVATE` / `PACK_ONLY` / `PUBLIC` for creator catalog exposure
- `origin_clothing_item_id`: source creator item for imported copies
- `origin_creator_id`: source creator for imported copies
- `origin_card_pack_id`: source pack for imported copies
- `origin_import_history_id`: import batch reference for imported copies
- `imported_at`: import completion timestamp for imported copies

---

### 3. Wardrobe

Container for organizing clothing items. Many-to-many relationship with ClothingItem.

```dart
class Wardrobe {
  String id;                    // UUID
  String userId;                // Owner user ID
  String name;                  // Wardrobe name (e.g., "Summer", "Work")
  WardrobeType type;            // REGULAR | VIRTUAL
  String? description;          // Optional description
  bool isSystemManaged;         // Virtual wardrobe is system-managed
  String? systemKey;            // DEFAULT_VIRTUAL_IMPORTED for system wardrobe
  int itemCount;                // Cached count of items
  DateTime createdAt;
  DateTime updatedAt;
}

enum WardrobeType {
  REGULAR,                      // User-created wardrobe
  VIRTUAL                       // Auto-created for imported items
}
```

**Indexes:**
- Primary: `id`
- Foreign Key: `userId`
- Composite: `(userId, type)` for separating regular/virtual
- Unique: `(userId, systemKey)` when `systemKey` is not null

---

### 4. WardrobeItem (Junction Table)

Many-to-many relationship between Wardrobe and ClothingItem.

```dart
class WardrobeItem {
  String id;                    // UUID
  String wardrobeId;            // Wardrobe reference
  String clothingItemId;        // ClothingItem reference
  DateTime addedAt;             // When item was added to wardrobe
  int? displayOrder;            // Optional ordering within wardrobe
}
```

**Indexes:**
- Primary: `id`
- Foreign Keys: `wardrobeId`, `clothingItemId`
- Unique: `(wardrobeId, clothingItemId)` - prevent duplicates
- Index: `wardrobeId` for fast wardrobe queries

---

### 5. Outfit

Saved outfit result confirmed by the user after preview generation.

```dart
class Outfit {
  String id;                    // UUID
  String userId;                // Owner user ID
  String previewTaskId;         // Source outfit preview task
  String? name;                 // Optional user-defined name
  String previewImageUrl;       // Final confirmed preview image
  List<OutfitItem> items;       // Referenced clothing items
  DateTime createdAt;
  DateTime updatedAt;
}

class OutfitItem {
  String clothingItemId;        // Reference to ClothingItem
  DateTime createdAt;
}
```

**Indexes:**
- Primary: `id`
- Foreign Key: `userId`
- Foreign Key: `previewTaskId`
- Unique: `(previewTaskId)` if each successful preview can only be saved once

---

### 6. Creator (Extended User)

Additional information for creator accounts.

```dart
class Creator {
  String userId;                // Reference to User.id
  CreatorStatus status;         // PENDING | ACTIVE | SUSPENDED
  String displayName;           // Public display name
  String? brandName;            // Brand/channel name
  String? bio;                  // Creator introduction
  String? avatarUrl;            // Avatar asset URL
  String? websiteUrl;           // External website
  String? socialLinks;          // JSON: {platform: url}
  int followerCount;            // Number of followers
  int packCount;                // Number of published packs
  bool isVerified;              // Verified creator badge
  DateTime? verifiedAt;
  DateTime createdAt;
}

enum CreatorStatus {
  @JsonValue('PENDING')
  pending,                      // Application under review
  @JsonValue('ACTIVE')
  active,                       // Can publish content
  @JsonValue('SUSPENDED')
  suspended,                    // Temporarily restricted
}
```

**Indexes:**
- Primary: `userId`
- Index: `status` for filtering by creator state
- Index: `isVerified` for featured creators

---

### 7. CardPack

Collection of clothing items shared by creators.

```dart
class CardPack {
  String id;                    // UUID
  String creatorId;             // Creator user ID
  String name;                  // Pack name
  String? description;          // Pack description
  String? coverImageUrl;        // Cover image
  PackType type;                // CLOTHING_COLLECTION | OUTFIT
  List<String> itemIds;         // ClothingItem IDs in this pack
  int itemCount;                // Cached count
  String? shareId;              // Shareable ID exposed in public links
  PackStatus status;            // DRAFT | PUBLISHED | ARCHIVED
  int importCount;              // Number of times imported
  DateTime createdAt;
  DateTime? publishedAt;
  DateTime? archivedAt;
  DateTime updatedAt;
}

enum PackType {
  CLOTHING_COLLECTION,          // Collection of individual items
  OUTFIT                        // Pre-styled outfit combination
}

enum PackStatus {
  DRAFT,                        // Not yet published
  PUBLISHED,                    // Available for import
  ARCHIVED                      // No longer available
}
```

**Indexes:**
- Primary: `id`
- Foreign Key: `creatorId`
- Index: `status` for published packs
- Index: `shareId` for import lookups

### 7.1 CardPackItem

Junction table for creator pack contents.

```dart
class CardPackItem {
  String id;                    // UUID
  String cardPackId;            // Pack reference
  String clothingItemId;        // Creator item reference
  int displayOrder;             // Stable order inside the pack
  String? notes;                // Optional pack-specific note
  DateTime createdAt;
}
```

**Indexes:**
- Primary: `id`
- Foreign Keys: `cardPackId`, `clothingItemId`
- Unique: `(cardPackId, clothingItemId)`
- Index: `(cardPackId, displayOrder)` for ordered rendering

---

### 8. ImportHistory

Track user imports for analytics and provenance.

```dart
class ImportHistory {
  String id;                    // UUID
  String userId;                // Importing user ID
  String cardPackId;            // Imported pack ID
  String creatorId;             // Creator ID
  String virtualWardrobeId;     // Target system wardrobe
  String? requestId;            // Idempotency key
  String status;                // PENDING | PROCESSING | COMPLETED | FAILED
  int itemCount;                // Number of items imported
  DateTime? importedAt;         // Import completion time
  String? failureReason;        // Failure details when status = FAILED
}
```

**Indexes:**
- Primary: `id`
- Foreign Keys: `userId`, `cardPackId`, `creatorId`, `virtualWardrobeId`
- Composite: `(userId, createdAt)` for recent history
- Unique: `(userId, requestId)` when request id is provided

### 8.1 ImportHistoryItem

Junction table for imported item provenance.

```dart
class ImportHistoryItem {
  String id;                    // UUID
  String importHistoryId;       // Import batch reference
  String clothingItemId;        // Imported copy created for the user
  String originClothingItemId;  // Source creator item
  DateTime createdAt;
}
```

**Indexes:**
- Primary: `id`
- Foreign Keys: `importHistoryId`, `clothingItemId`, `originClothingItemId`
- Unique: `(importHistoryId, clothingItemId)`

---

### 9. OutfitPreviewTask

Asynchronous try-on / preview generation request.

```dart
class OutfitPreviewTask {
  String id;                    // UUID
  String userId;                // Request owner
  String personImageUrl;        // Uploaded selfie asset
  String personViewType;        // FULL_BODY | UPPER_BODY
  List<String> garmentCategories; // TOP | BOTTOM | SHOES
  int inputCount;               // Number of selected clothing items
  String promptTemplateKey;     // Selected backend prompt template
  String providerName;          // DashScope
  String providerModel;         // wan2.7-image-pro
  String? providerJobId;        // External provider task id if any
  String status;                // PENDING | PROCESSING | COMPLETED | FAILED
  String? previewImageUrl;      // Generated result image
  String? errorCode;            // Provider or domain error code
  String? errorMessage;         // Human-readable failure message
  DateTime? startedAt;
  DateTime? completedAt;
  DateTime createdAt;
  List<OutfitPreviewTaskItem> items;
}

class OutfitPreviewTaskItem {
  String clothingItemId;        // Referenced clothing item
  String garmentCategory;       // TOP | BOTTOM | SHOES
  int sortOrder;                // Stable provider input order
  String garmentImageUrl;       // Concrete image used for generation
  DateTime createdAt;
}
```

**Indexes:**
- Primary: `id`
- Foreign Key: `userId`
- Index: `(userId, createdAt)` for history
- Index: `(status, createdAt)` for worker polling

---

### 10. Model3D

Stores 3D model reference for a clothing item (generated by Hunyuan3D-2).

```dart
class Model3D {
  String id;                    // UUID
  String clothingItemId;        // Reference to ClothingItem (unique — one model per item)
  String modelFormat;           // "glb", "obj", or "ply"
  String storagePath;           // S3/MinIO/local file path
  int? vertexCount;             // Number of vertices in the mesh
  int? faceCount;               // Number of faces in the mesh
  int? fileSize;                // File size in bytes
  DateTime createdAt;
}
```

**Indexes:**
- Primary: `id`
- Unique Foreign Key: `clothingItemId`

---

### 11. ProcessingTask

Tracks asynchronous processing tasks (background removal, 3D generation, angle rendering).

```dart
class ProcessingTask {
  String id;                    // UUID
  String clothingItemId;        // Reference to ClothingItem
  ProcessingTaskType taskType;  // BACKGROUND_REMOVAL | 3D_GENERATION | ANGLE_RENDERING | FULL_PIPELINE
  int attemptNo;                // 1 for first run, increments on retry
  String? retryOfTaskId;        // Previous failed task if this is a retry
  ProcessingStatus status;      // PENDING | PROCESSING | COMPLETED | FAILED
  int progress;                 // 0-100
  String? errorMessage;         // Error details if FAILED
  String? workerId;             // Worker currently processing the task
  DateTime? leaseExpiresAt;     // Claim lease timeout for worker recovery
  DateTime? startedAt;
  DateTime? completedAt;
  DateTime createdAt;
}

enum ProcessingTaskType {
  BACKGROUND_REMOVAL,
  THREE_D_GENERATION,
  ANGLE_RENDERING,
  FULL_PIPELINE
}

enum ProcessingStatus {
  PENDING,
  PROCESSING,
  COMPLETED,
  FAILED
}
```

**Indexes:**
- Primary: `id`
- Foreign Key: `clothingItemId`
- Index: `status` for querying active/failed tasks

---

## Relationships Summary

### One-to-Many
- `User` → `ClothingItem` (user owns/creates many items)
- `User` → `Wardrobe` (user has many wardrobes)
- `User` → `Outfit` (user has many outfits)
- `User` → `OutfitPreviewTask` (user submits many preview tasks)
- `Creator` → `CardPack` (creator publishes many packs)
- `ClothingItem` → `ProcessingTask` (one item can have multiple task records)

### Many-to-Many
- `Wardrobe` ↔ `ClothingItem` (via `WardrobeItem`)
- `CardPack` ↔ `ClothingItem` (via `CardPackItem`)
- `ImportHistory` ↔ `ClothingItem` (via `ImportHistoryItem`)
- `Outfit` ↔ `ClothingItem` (via `OutfitItem`)
- `OutfitPreviewTask` ↔ `ClothingItem` (via `OutfitPreviewTaskItem`)

### One-to-One
- `User` → `Creator` (optional, only for creator accounts)
- `ClothingItem` → `Model3D` (one item has at most one 3D model)

---

## Data Constraints

### Business Rules

1. **Clothing Item Lifecycle**
   - ClothingItem can exist without being in any wardrobe
   - Deleting wardrobe does NOT delete ClothingItem
   - Deleting ClothingItem removes all WardrobeItem references
   - Failed clothing processing keeps original uploads and task history, but not derived outputs
   - At most one `PENDING` or `PROCESSING` task may exist per clothing item

2. **Source Isolation**
   - `source = OWNED`: Must have `provenance = null`
   - `source = IMPORTED`: Must have valid `provenance` object
   - Virtual wardrobe only contains items with `source = IMPORTED`
   - Imported copies keep `originClothingItemId`, `importHistoryId`, creator summary, and optional card pack summary

3. **Wardrobe Rules**
   - Each user has exactly one virtual wardrobe (auto-created)
   - User can have unlimited regular wardrobes
   - Same ClothingItem can be in multiple wardrobes
   - System-managed wardrobes cannot be renamed or deleted by end users

4. **Outfit Rules**
   - Outfit can reference both owned and imported items
   - Outfit is created from a successful `OutfitPreviewTask`
   - Deleting ClothingItem invalidates outfit (mark as incomplete)

5. **Outfit Preview Rules**
   - Preview task accepts one selfie plus one or more referenced clothing items
   - Same preview task cannot repeat the same garment category
   - Preview task and processing task are separate async domains

6. **Card Pack Rules**
   - Only users with `type = CREATOR` can create CardPacks
   - Published packs may be deleted only if backend explicitly allows the transition
   - Pack items must belong to the creator

### Data Validation

```dart
// Tag validation
assert(tag.key.isNotEmpty);
assert(tag.value.isNotEmpty);

// ClothingItem validation
assert(source == ItemSource.OWNED ? provenance == null : provenance != null);
assert(predictedTags.isNotEmpty);
assert(finalTags.isNotEmpty);
assert(isConfirmed ? finalTags.isNotEmpty : true);

// OutfitItem validation
assert(layer >= 0);
assert(scale >= 0.5 && scale <= 2.0);
assert(rotation >= 0 && rotation < 360);
assert(position.x >= 0.0 && position.x <= 1.0);
assert(position.y >= 0.0 && position.y <= 1.0);

// Wardrobe validation
assert(type == WardrobeType.VIRTUAL ? name == "Virtual Wardrobe" : true);
```

---

## Tag System

### Tag Structure

Tags are key-value pairs used for classification and search:

```dart
class Tag {
  String key;    // e.g., "category", "color", "style"
  String value;  // e.g., "t-shirt", "blue", "casual"
}
```

### Tag Keys

Standard tag keys used in the system:

- `category`: Clothing type (current backend auto-prediction only supports the active Roboflow labels)
- `color`: Color name (e.g., "blue", "red", "black")
- `pattern`: Pattern type (uses Pattern enum values)
- `style`: Style category (currently user-supplied)
- `season`: Season suitability (currently user-supplied)
- `audience`: Target audience (currently user-supplied)
- `material`: Fabric material (e.g., "cotton", "wool", "polyester")
- `brand`: Brand name (optional)
- `custom`: User-defined custom tags

### Predicted vs Final Tags

**Predicted Tags (`predictedTags`):**
- Generated by AI/ML classification
- Immutable after creation
- Used for analytics and model improvement
- NOT used for search

**Final Tags (`finalTags`):**
- User-confirmed or user-edited tags
- Mutable (can be updated by user)
- Used for search and filtering
- Initially copied from `predictedTags`
- When user edits, `isConfirmed` is set to `true`

### Tag Confirmation Flow

The system follows this workflow for tag management:

1. **Create Clothing Item** (POST /clothing-items)
   - User uploads clothing images
   - Backend synchronously runs AI classification on the front image
   - Backend stores `predictedTags` (immutable)
   - Backend copies `predictedTags` to `finalTags` (mutable)
   - Sets `isConfirmed: false`

2. **User Review** (Frontend UI)
   - User sees both `predictedTags` and `finalTags`
   - User can accept or modify tags
   - User can add additional tags

3. **Tag Confirmation** (PATCH /clothing-items/:id)
   - User submits modified `finalTags: Tag[]`
   - Backend updates `final_tags` column
   - Backend sets `isConfirmed: true`
   - `predictedTags` remain unchanged for analytics

4. **Search** (POST /clothing-items/search)
   - Search uses `finalTags` only
   - `predictedTags` are never used for search
   - Ensures search reflects user-confirmed data

### Tag-Based Search

Search uses `finalTags` only:

```dart
// Search by category
finalTags.any((tag) => tag.key == "category" && tag.value == "T_SHIRT")

// Search by color
finalTags.any((tag) => tag.key == "color" && tag.value == "blue")

// Multi-tag search (AND logic)
finalTags.any((tag) => tag.key == "category" && tag.value == "T_SHIRT") &&
finalTags.any((tag) => tag.key == "season" && tag.value == "SUMMER")
```

---

## Storage Strategy

### Backend (FastAPI + PostgreSQL)
- **Database**: PostgreSQL for all structured data
- **Object Storage**: S3/MinIO/Local file system for images
- **Database stores**: Metadata and file paths only
- **Images stored**: In object storage with path references

### Flutter App (Local Cache)
- **Local Cache**: SQLite for offline access
- **Image Cache**: cached_network_image for image caching
- **Sync Strategy**: Pull from backend API, cache locally
- **Conflict Resolution**: Server-side timestamp wins

### Image Storage Paths
- **Format**: `{user_id}/{clothing_id}/{image_type}_{timestamp}.{ext}`
- **Example**: `user-123/item-456/original_front_1642248000.jpg`
- **Storage Tiers**:
  - Original images: High resolution (up to 4K)
  - Processed images: Medium resolution (1080p)
  - Angle views: Optimized resolution (720p)
  - Thumbnails: Low resolution (256x256)

---

## Migration Strategy

### Version 1.0 (Phase 1)
- Initial schema with all core entities
- Support for owned items only
- Basic wardrobe management

### Version 1.1 (Phase 1 Complete)
- Add Creator and CardPack entities
- Add Provenance tracking
- Add ImportHistory

### Future Versions
- Add social features (followers, likes, comments)
- Add recommendation engine data
- Add analytics and metrics

---

## Sample Data

### Example ClothingItem (Owned)

```json
{
  "id": "item-001",
  "userId": "user-123",
  "source": "OWNED",
  "provenance": null,
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
  "predictedTags": [
    { "key": "category", "value": "T_SHIRT" },
    { "key": "color", "value": "blue" },
    { "key": "color", "value": "white" },
    { "key": "pattern", "value": "STRIPED" },
    { "key": "style", "value": "CASUAL" },
    { "key": "season", "value": "SUMMER" },
    { "key": "audience", "value": "UNISEX" }
  ],
  "finalTags": [
    { "key": "category", "value": "T_SHIRT" },
    { "key": "color", "value": "blue" },
    { "key": "color", "value": "white" },
    { "key": "pattern", "value": "STRIPED" },
    { "key": "style", "value": "CASUAL" },
    { "key": "season", "value": "SUMMER" },
    { "key": "audience", "value": "UNISEX" },
    { "key": "material", "value": "cotton" }
  ],
  "isConfirmed": true,
  "name": "Blue Striped T-Shirt",
  "description": "Comfortable cotton t-shirt",
  "createdAt": "2024-01-15T10:30:00Z",
  "updatedAt": "2024-01-15T10:35:00Z"
}
```

### Example ClothingItem (Imported)

```json
{
  "id": "item-002",
  "userId": "user-123",
  "source": "IMPORTED",
  "provenance": {
    "sourceType": "IMPORTED",
    "originClothingItemId": "creator-item-456",
    "importHistoryId": "import-789",
    "creator": {
      "id": "creator-456",
      "displayName": "FashionGuru"
    },
    "cardPack": {
      "id": "pack-789",
      "name": "Summer Essentials 2024"
    },
    "importedAt": "2024-01-20T14:00:00Z",
  },
  "images": { /* ... */ },
  "predictedTags": [
    { "key": "category", "value": "DRESS" },
    { "key": "color", "value": "red" },
    { "key": "pattern", "value": "FLORAL" },
    { "key": "style", "value": "BOHEMIAN" },
    { "key": "season", "value": "SPRING" },
    { "key": "audience", "value": "WOMEN" }
  ],
  "finalTags": [
    { "key": "category", "value": "DRESS" },
    { "key": "color", "value": "red" },
    { "key": "pattern", "value": "FLORAL" },
    { "key": "style", "value": "BOHEMIAN" },
    { "key": "season", "value": "SPRING" },
    { "key": "audience", "value": "WOMEN" }
  ],
  "isConfirmed": false,
  "name": "Floral Summer Dress",
  "description": "Light and breezy dress perfect for summer",
  "createdAt": "2024-01-10T08:00:00Z",
  "updatedAt": "2024-01-10T08:00:00Z"
}
```

---

## Performance Considerations

### Indexing Strategy
- Index all foreign keys for join performance
- Composite indexes for common filter combinations
- Full-text search index on tags and descriptions

### Caching
- Cache wardrobe item counts
- Cache outfit thumbnails
- Cache frequently accessed images

### Pagination
- Wardrobe items: 50 per page
- Search results: 20 per page
- Outfit history: 20 per page

### Query Optimization
- Lazy load images (load on demand)
- Batch load wardrobe items
- Use database views for complex queries
