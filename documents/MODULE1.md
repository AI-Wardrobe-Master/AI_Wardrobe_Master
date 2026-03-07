# Module 1: Clothing Digitalization — Implementation Plan

## 1. Overview

**Pipeline:** Capture photo (front required, back optional) → Background removal → 3D model generation via Hunyuan3D-2 → Render 8 angle views → Persist to database

```
Flutter App          FastAPI Backend         Hunyuan3D-2            Storage
┌──────────┐        ┌──────────────┐        ┌──────────────┐      ┌───────────┐
│ Camera    │──────→ │ Upload &     │──────→ │ Shape Gen    │────→ │PostgreSQL │
│ Capture   │  HTTP  │ Background   │        │ Texture Gen  │      │ S3/MinIO  │
│ Upload    │        │ Removal      │        │ Angle Render │      │           │
└──────────┘        └──────────────┘        └──────────────┘      └───────────┘
```

**Related documents:**
- API endpoints → see `API_CONTRACT.md` Section 2 and Section 8
- Data model (ImageSet, Model3D, ProcessingTask) → see `DATA_MODEL.md`
- Database tables (models_3d, processing_tasks) → see `BACKEND_ARCHITECTURE.md`

---

## 2. Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Frontend | Flutter + camera plugin | Photo capture, upload, progress UI |
| API | FastAPI | Image upload, pipeline orchestration |
| Background Removal | Hunyuan3D-2 built-in rembg | Foreground extraction → RGBA PNG |
| 3D Shape | Hunyuan3D-2 DiT (1.1B) / 2mv (multi-view) | 2D image → 3D mesh |
| Texture | Hunyuan3D-Paint (1.3B) | Mesh → textured 3D model |
| Angle Rendering | trimesh + pyrender | 3D model → 8 angle 2D images |
| Database | PostgreSQL + SQLAlchemy | Structured data persistence |
| Object Storage | S3 / MinIO / Local FS | Image and model file storage |
| Async Tasks | Celery + Redis | Background processing (~30s per item) |

**Hardware:** Minimum 16 GB VRAM for shape+texture (recommended RTX 3090/4090, 24 GB). Mini model (0.6B) available for lower-VRAM setups.

---

## 3. WBS 1.1 — Image Capture

### 1.1.1 Camera Integration

- Use Flutter `camera` package with rear camera at high resolution (1080p)
- **Front photo: required.** Back photo: optional (user can skip)
- Flow: Open camera → guide overlay ("Capture front") → take photo → preview & confirm/retake → prompt "Capture back?" → take or skip → submit

### 1.1.3 User Feedback

No client-side or server-side image quality checks. User captures and submits directly. If processing fails due to image issues, the backend returns an error and the user is prompted to retake.

---

## 4. WBS 1.2 — Background Removal

### 1.2.1 Algorithm Integration

Use `hy3dgen.rembg.BackgroundRemover` from Hunyuan3D-2. Accepts raw JPEG, outputs RGBA PNG with transparent background. Processes front image (always) and back image (if provided).

Fallback: standalone `rembg` Python library (CPU-capable) if GPU resources are constrained.

### 1.2.2 Image Storage

Storage path convention per clothing item:

```
{user_id}/{clothing_id}/
├── original_front.jpg
├── original_back.jpg          (if provided)
├── processed_front.png        (RGBA, background removed)
├── processed_back.png         (RGBA, if back exists)
├── model.glb                  (3D model)
└── angle_{000..315}.png       (8 angle views)
```

Original images stored at full resolution. Processed images as RGBA PNG. Angle views at 720×720. 3D model as GLB (geometry + texture).

---

## 5. WBS 1.3 — Multi-Angle View Generation

### 1.3.1 3D Model Generation (Hunyuan3D-2)

Hunyuan3D-2 is Tencent's open-source 3D generation system with a two-stage pipeline:
1. **Hunyuan3D-DiT** — Diffusion transformer generating 3D mesh from image
2. **Hunyuan3D-Paint** — Multi-view diffusion generating texture maps for the mesh

Repo: https://github.com/Tencent/Hunyuan3D-2

| Input Scenario | Model Used | Notes |
|---------------|-----------|-------|
| Front only | Hunyuan3D-2 (single-view) | Back side inferred by model |
| Front + Back | Hunyuan3D-2mv (multi-view) | More accurate geometry |

Pipeline: background-removed image(s) → DiT shape generation → Paint texture synthesis → export as GLB.

### 1.3.2 Angle Rendering & Storage

After obtaining the textured 3D model, render 8 views by placing a virtual camera around the Y-axis at 45° intervals (0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°).

Rendering params: 720×720 resolution, perspective camera, auto-calculated distance from bounding sphere, fixed three-point lighting, RGBA PNG output. Tool: trimesh or pyrender (headless server compatible).

### 1.3.3 Cross-Angle Consistency

Consistency is inherently guaranteed since all views are rendered from the same 3D model with identical resolution, FOV, lighting, and camera distance. Post-render validation confirms all 8 images exist, have matching dimensions, and are non-blank.

---

## 6. WBS 1.4 — Persistent Storage

Database schema and data model details are maintained in their respective documents:
- **New tables** (`models_3d`, `processing_tasks`): see `BACKEND_ARCHITECTURE.md`
- **New entities** (`Model3D`, `ProcessingTask`) and updated `ImageSet`: see `DATA_MODEL.md`

### 1.4.2 Persistence & Retrieval

**Write flow:** Create clothing_items record → store original images → background removal & store → generate 3D model & store → render angles & store → update processing_tasks to COMPLETED.

**Read flow:**
- Item detail: join clothing_items + images + models_3d, return all resource URLs
- Processing status: query processing_tasks, return status/progress (frontend polls this)
- Angle views: query images where type=ANGLE_VIEW, ordered by angle

### 1.4.3 Data Integrity

| Mechanism | Purpose |
|-----------|---------|
| Foreign key CASCADE | Deleting a clothing item auto-removes all images, models, tasks |
| DB transactions | Rollback on failure + cleanup uploaded files |
| Unique constraint | One 3D model per clothing item |
| Pydantic validation | Input validation at API boundary |
| Failure recovery | Failed tasks recorded with error; user can retry |
| Startup recovery | On restart, mark stale PROCESSING tasks as FAILED |

---

## 7. Frontend Flow

```
[Wardrobe Screen] → tap "+" to add
        │
        ▼
[Camera Screen] → "Capture front of clothing"
        │
        ▼
[Preview Screen] → Confirm / Retake
        │
        ▼
[Choice] → "Capture back?" → [Camera → Preview] or [Skip]
        │
        ▼
[Processing Screen] → Progress bar (polling backend)
        │               Upload → Background Removal → 3D Generation → Angle Rendering
        ▼
[Result Screen] → Background-removed image + 8-angle slider browser
        │
        ▼
[Item Detail] → Full Asset Card (feeds into Module 2 classification)
```

---

## 8. Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| Insufficient GPU VRAM | Use mini model (0.6B) or low_vram_mode |
| Slow 3D generation | Use Turbo variant (FlashVDM); async + progress feedback |
| Poor 3D quality for clothing | Abstract service layer; swap to TripoSR/InstantMesh if needed |
| Only front photo available | Single-view model produces reasonable inference; guide user to provide back |

---

## 9. API
 - POST /api/v1/clothing-items — 上传图片，触发全流程
 - GET /api/v1/clothing-items/:id — 获取衣物详情
 - GET /api/v1/clothing-items/:id/processing-status — 处理进度
 - POST /api/v1/clothing-items/:id/retry — 重试失败任务
 - GET /api/v1/clothing-items/:id/angle-views — 8 角度视图
 - GET /api/v1/clothing-items/:id/model — 下载 GLB 模型

