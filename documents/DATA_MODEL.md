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
    required String creatorId,
    required String creatorName,
    String? cardPackId,
    String? cardPackName,
    required DateTime importedAt,
    String? importSource,
  }) = _Provenance;

  factory Provenance.fromJson(Map<String, dynamic> json) =>
      _$ProvenanceFromJson(json);
}

enum ItemSource {
  @JsonValue('OWNED')
  owned,
  @JsonValue('IMPORTED')
  imported,
}

enum ClothingType {
  // Tops - Core
  @JsonValue('T_SHIRT')
  tShirt,
  @JsonValue('SHIRT')
  shirt,
  @JsonValue('BLOUSE')
  blouse,
  @JsonValue('POLO')
  polo,
  @JsonValue('TANK_TOP')
  tankTop,
  @JsonValue('SWEATER')
  sweater,
  @JsonValue('HOODIE')
  hoodie,
  @JsonValue('SWEATSHIRT')
  sweatshirt,
  @JsonValue('CARDIGAN')
  cardigan,
  
  // Bottoms - Core
  @JsonValue('JEANS')
  jeans,
  @JsonValue('TROUSERS')
  trousers,
  @JsonValue('SHORTS')
  shorts,
  @JsonValue('SKIRT')
  skirt,
  @JsonValue('LEGGINGS')
  leggings,
  @JsonValue('SWEATPANTS')
  sweatpants,
  
  // Outerwear - Core
  @JsonValue('JACKET')
  jacket,
  @JsonValue('COAT')
  coat,
  @JsonValue('BLAZER')
  blazer,
  @JsonValue('PUFFER')
  puffer,
  @JsonValue('WIND_BREAKER')
  windBreaker,
  @JsonValue('VEST')
  vest,
  
  // Full Body - Core
  @JsonValue('DRESS')
  dress,
  @JsonValue('JUMPSUIT')
  jumpsuit,
  @JsonValue('ROMPER')
  romper,
  
  // Footwear - Core
  @JsonValue('SNEAKERS')
  sneakers,
  @JsonValue('BOOTS')
  boots,
  @JsonValue('SANDALS')
  sandals,
  @JsonValue('DRESS_SHOES')
  dressShoes,
  @JsonValue('HEELS')
  heels,
  @JsonValue('SLIPPERS')
  slippers,
  
  // Accessories - Core
  @JsonValue('HAT')
  hat,
  @JsonValue('SCARF')
  scarf,
  @JsonValue('BELT')
  belt,
  
  // Other - Fallback
  @JsonValue('OTHER')
  other,
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

# 这个让用户自己选比较合适
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

Saved outfit combination with positioning information.

```dart
class Outfit {
  String id;                    // UUID
  String userId;                // Owner user ID
  String name;                  // Outfit name
  String? description;          // Optional description
  String? thumbnailUrl;         // Preview image URL
  List<OutfitItem> items;       // Items in this outfit
  DateTime createdAt;
  DateTime updatedAt;
}

class OutfitItem {
  String clothingItemId;        // Reference to ClothingItem
  int layer;                    // Z-index for layering (0 = bottom)
  Position position;            // X, Y coordinates on canvas
  double scale;                 // Scale factor (0.5 - 2.0)
  int rotation;                 // Rotation angle (0-359)
}

class Position {
  double x;                     // X coordinate (0.0 - 1.0, normalized)
  double y;                     // Y coordinate (0.0 - 1.0, normalized)
}
```

**Indexes:**
- Primary: `id`
- Foreign Key: `userId`
- Index: `userId` for user's outfit list

---

### 6. Creator (Extended User)

Additional information for creator accounts.

```dart
class Creator {
  String userId;                // Reference to User.id
  String? brandName;            // Brand/channel name
  String? websiteUrl;           // External website
  String? socialLinks;          // JSON: {platform: url}
  int followerCount;            // Number of followers
  int packCount;                // Number of published packs
  bool isVerified;              // Verified creator badge
  DateTime? verifiedAt;
}
```

**Indexes:**
- Primary: `userId`
- Index: `isVerified` for featured creators

---

### 7. CardPack

Collection of clothing items shared by creators.

```dart
class CardPack {
  String id;                    // UUID
  String creatorId;             // Creator user ID
  String name;                  // Pack name
  String description;           // Pack description
  String? coverImageUrl;        // Cover image
  PackType type;                // CLOTHING_COLLECTION | OUTFIT
  List<String> itemIds;         // ClothingItem IDs in this pack
  int itemCount;                // Cached count
  String shareLink;             // Shareable URL
  PackStatus status;            // DRAFT | PUBLISHED | ARCHIVED
  int importCount;              // Number of times imported
  DateTime createdAt;
  DateTime publishedAt;
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
- Index: `shareLink` for import lookups

---

### 8. ImportHistory

Track user imports for analytics and provenance.

```dart
class ImportHistory {
  String id;                    // UUID
  String userId;                // Importing user ID
  String cardPackId;            // Imported pack ID
  String creatorId;             // Creator ID
  int itemCount;                // Number of items imported
  DateTime importedAt;          // Import timestamp
}
```

**Indexes:**
- Primary: `id`
- Foreign Keys: `userId`, `cardPackId`, `creatorId`
- Composite: `(userId, cardPackId)` for duplicate detection

---

### 9. Model3D

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

### 10. ProcessingTask

Tracks asynchronous processing tasks (background removal, 3D generation, angle rendering).

```dart
class ProcessingTask {
  String id;                    // UUID
  String clothingItemId;        // Reference to ClothingItem
  ProcessingTaskType taskType;  // BACKGROUND_REMOVAL | 3D_GENERATION | ANGLE_RENDERING | FULL_PIPELINE
  ProcessingStatus status;      // PENDING | PROCESSING | COMPLETED | FAILED
  int progress;                 // 0-100
  String? errorMessage;         // Error details if FAILED
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
- `Creator` → `CardPack` (creator publishes many packs)
- `ClothingItem` → `ProcessingTask` (one item can have multiple task records)

### Many-to-Many
- `Wardrobe` ↔ `ClothingItem` (via `WardrobeItem`)
- `CardPack` ↔ `ClothingItem` (via item IDs array)
- `Outfit` ↔ `ClothingItem` (via `OutfitItem` embedded)

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

2. **Source Isolation**
   - `source = OWNED`: Must have `provenance = null`
   - `source = IMPORTED`: Must have valid `provenance` object
   - Virtual wardrobe only contains items with `source = IMPORTED`

3. **Wardrobe Rules**
   - Each user has exactly one virtual wardrobe (auto-created)
   - User can have unlimited regular wardrobes
   - Same ClothingItem can be in multiple wardrobes

4. **Outfit Rules**
   - Outfit can reference both owned and imported items
   - Deleting ClothingItem invalidates outfit (mark as incomplete)
   - OutfitItem positions are normalized (0.0-1.0) for responsive layout

5. **Card Pack Rules**
   - Only users with `type = CREATOR` can create CardPacks
   - Published packs cannot be deleted (only archived)
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
  String value;  // e.g., "T_SHIRT", "blue", "CASUAL"
}
```

### Tag Keys

Standard tag keys used in the system:

- `category`: Clothing type (uses ClothingType enum values)
- `color`: Color name (e.g., "blue", "red", "black")
- `pattern`: Pattern type (uses Pattern enum values)
- `style`: Style category (uses Style enum values)
- `season`: Season suitability (uses Season enum values)
- `audience`: Target audience (uses TargetAudience enum values)
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

1. **AI Classification** (POST /ai/classify)
   - User uploads clothing images
   - AI returns `predictedTags: Tag[]`
   - No confidence scores included

2. **Initial Storage** (POST /clothing-items)
   - Backend stores `predictedTags` (immutable)
   - Backend copies `predictedTags` to `finalTags` (mutable)
   - Sets `isConfirmed: false`

3. **User Review** (Frontend UI)
   - User sees both `predictedTags` and `finalTags`
   - User can accept or modify tags
   - User can add additional tags

4. **Tag Confirmation** (PATCH /clothing-items/:id)
   - User submits modified `finalTags: Tag[]`
   - Backend updates `final_tags` column
   - Backend sets `isConfirmed: true`
   - `predictedTags` remain unchanged for analytics

5. **Search** (POST /clothing-items/search)
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
    "creatorId": "creator-456",
    "creatorName": "FashionGuru",
    "cardPackId": "pack-789",
    "cardPackName": "Summer Essentials 2024",
    "importedAt": "2024-01-20T14:00:00Z",
    "importSource": "https://app.com/pack/pack-789"
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
