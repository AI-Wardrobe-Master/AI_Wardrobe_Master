# Flutter Frontend Integration: Styled Generation

This guide explains how the Flutter team should integrate the new "Styled Generation" feature (DreamO-powered personalized fashion photos).

---

## Feature Overview

Users can:
1. Select an existing clothing item that has completed processing (has `processedFrontUrl`)
2. Upload a selfie (face clearly visible, one person only)
3. Enter a scene description (e.g., "standing in a coffee shop, warm natural light")
4. Submit to generate a realistic fashion portrait
5. Poll for status and view the result when done
6. Retry if generation fails

---

## New API Endpoints

Base URL: `http://localhost:8000/api/v1`

All endpoints require `Authorization: Bearer <JWT>`.

### 1. Create Styled Generation

```
POST /styled-generations
Content-Type: multipart/form-data
```

**Form fields:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `selfie_image` | File | Yes | - | Selfie image (JPEG/PNG, max 10 MB) |
| `clothing_item_id` | String | Yes | - | UUID of a processed clothing item |
| `scene_prompt` | String | Yes | - | Scene description text |
| `negative_prompt` | String | No | null | Additional negative prompt |
| `guidance_scale` | Float | No | 4.5 | 1.0-10.0, lower = more natural |
| `seed` | Integer | No | -1 | -1 for random |
| `width` | Integer | No | 1024 | 768-1024 |
| `height` | Integer | No | 1024 | 768-1024 |

**Response (202):**
```json
{
  "id": "uuid",
  "status": "PENDING",
  "estimatedTime": 120
}
```

**Dart example:**
```dart
final formData = FormData.fromMap({
  'selfie_image': MultipartFile.fromBytes(selfieBytes, filename: 'selfie.jpg'),
  'clothing_item_id': selectedClothingId,
  'scene_prompt': scenePromptController.text,
  if (negativePrompt != null) 'negative_prompt': negativePrompt,
  'guidance_scale': guidanceScale.toString(),
});

final resp = await dio.post('/styled-generations', data: formData);
final generationId = resp.data['id'];
```

### 2. Get Generation Detail (Polling)

```
GET /styled-generations/{id}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "userId": "uuid",
    "sourceClothingItemId": "uuid",
    "selfieOriginalUrl": "/files/...",
    "selfieProcessedUrl": "/files/...",
    "scenePrompt": "standing in a coffee shop",
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

### 3. List Generation History

```
GET /styled-generations?page=1&limit=20
```

Returns paginated list of all user's generations.

### 4. Retry Failed Generation

```
POST /styled-generations/{id}/retry
```

Returns 202 with new PENDING status. Only works for FAILED generations.

### 5. Delete Generation

```
DELETE /styled-generations/{id}
```

Returns 204. Cannot delete PENDING/PROCESSING generations (returns 409).

---

## Recommended UI Flow

### Screen: StyledGenerationCreateScreen

1. **Clothing selector**: Show grid of user's clothing items filtered to only those with `processedFrontUrl` (i.e., processing completed). Disable/hide items that are still processing.

2. **Selfie upload**: Camera capture or gallery picker. Show preview.

3. **Scene prompt input**: Text field with placeholder examples like:
   - "standing in a modern coffee shop, warm natural light"
   - "walking on a beach at sunset, full body"
   - "posing in a studio with white background"

4. **Advanced options** (collapsible):
   - Guidance scale slider (3.0 - 6.0, default 4.5)
   - Negative prompt text field (optional)

5. **Submit button**: Calls `POST /styled-generations`, then navigates to processing screen.

### Screen: StyledGenerationProcessingScreen

Reuse the same polling pattern as `processing_screen.dart`:

```dart
Timer.periodic(Duration(seconds: 3), (_) async {
  final resp = await dio.get('/styled-generations/$generationId');
  final data = resp.data['data'];
  final status = data['status'];
  final progress = (data['progress'] as num).toDouble() / 100;

  if (status == 'SUCCEEDED') {
    timer.cancel();
    // Navigate to result screen
  } else if (status == 'FAILED') {
    timer.cancel();
    // Show error with retry button
  }
});
```

Show progress indicator with percentage (0-100%).

### Screen: StyledGenerationResultScreen

Display the `resultImageUrl` as a full-screen image. Options:
- Save to device gallery
- Share
- Generate another (go back to create screen)
- View generation details (prompt, seed, etc.)

### Screen: StyledGenerationHistoryScreen

Grid/list view of all past generations. Accessible from profile or a dedicated tab.
Each card shows:
- Thumbnail of `resultImageUrl` (or placeholder if failed/pending)
- Status badge
- Scene prompt preview
- Created date

---

## Error Handling

| HTTP Status | Meaning | UI Action |
|-------------|---------|-----------|
| 202 | Task created | Navigate to processing screen |
| 404 | Item not found | Show "item not found" error |
| 409 | Garment not ready | Show "Please wait for clothing to finish processing" |
| 413 | Selfie too large | Show "Image too large (max 10 MB)" |
| 422 | Validation error | Show specific validation message |
| 503 | Queue unavailable | Show "Service temporarily unavailable, try again later" |

### Pipeline Failure Messages

The `failureReason` field contains human-readable errors:
- `"Selfie validation failed: NO_FACE_DETECTED"` - No face found
- `"Selfie validation failed: MULTIPLE_FACES_DETECTED"` - Too many faces
- `"Selfie validation failed: IMAGE_TOO_DARK"` - Poor lighting
- `"Selfie validation failed: IMAGE_TOO_BLURRY"` - Blurry image
- `"Garment asset not ready..."` - Clothing still processing
- `"DreamO service timed out..."` - GPU overloaded

---

## Suggested New Files

```
lib/
  services/
    styled_generation_api_service.dart    # API calls
  models/
    styled_generation.dart                # Data model
  ui/
    screens/
      styled_generation/
        styled_generation_create_screen.dart
        styled_generation_processing_screen.dart
        styled_generation_result_screen.dart
        styled_generation_history_screen.dart
```

---

## Checking Clothing Item Readiness

Before allowing the user to select a clothing item for styled generation, verify it has a processed front image:

```dart
final item = await ClothingApiService.getClothingItem(itemId);
final images = item['data']['images'];
final hasProcessedFront = images['processedFrontUrl'] != null;

if (!hasProcessedFront) {
  // Disable selection, show "Still processing..." label
}
```

Or check the processing status:

```dart
final status = await ClothingApiService.getProcessingStatus(itemId);
final isReady = status['data']['status'] == 'COMPLETED';
```
