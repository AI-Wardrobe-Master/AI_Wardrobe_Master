# Visualization Backend Status

## Exact Conclusion

The repository does **not** currently provide a real backend outfit-preview generation service that the Flutter `Generate Preview` button can call.

## Evidence

### Frontend

- `ai_wardrobe_app/lib/ui/screens/outfit_canvas_screen.dart` shows the preview modal with the local asset:
  - `assets/visualization/preview/generated_outfit_preview.jpg`
- The current preview modal does not make a network call before rendering the preview image.

### Backend Router

- `backend/app/api/v1/router.py` only registers:
  - `auth`
  - `ai`
  - `clothing`
  - `wardrobe`
- No implemented `outfit preview`, `try-on`, or `visualization render` router is currently mounted.

### Existing Model Pipeline

The backend does contain a real pipeline for **single clothing items**:

- background removal
- classification
- Hunyuan3D mesh generation
- angle rendering

This pipeline is defined in:

- `backend/app/services/background_removal_service.py`
- `backend/app/services/model_3d_service.py`
- `backend/app/services/clothing_pipeline.py`

## Why This Is Still Not Usable For Real Outfit Preview

- The pipeline works on one clothing item, not a multi-item outfit combination.
- There is no API contract implemented for “submit selected outfit and get preview image back”.
- The current Docker/backend setup does not fully install the Hunyuan runtime stack required by `hy3dgen`.
- The async processing path now depends on Celery/Redis behavior, but the repository compose setup still needs full worker support for reliable production execution.

## Practical Meaning For The Team

- Current visualization preview remains a front-end demo.
- Current backend work is useful groundwork, but it is **not yet** the missing outfit-preview model.
- To make preview real, the team must add both:
  - a preview-capable backend rendering/model path
  - a front-end integration contract for request, polling, success, and failure states

## Frontend Demo Status After Latest Fixes

- The local demo export flow is now stable enough for presentation use.
- `Export to Outfit Collection` saves locally and surfaces the result in `Discover`.
- The export form now supports multiple user-defined tags instead of one paragraph-style tag field.
- The duplicate top-bar `Save Collection` action was removed so the page keeps a single primary save action at the bottom.
- Real-device verification confirmed that the save flow no longer throws the earlier red-screen assertion during export.
- This improves demo reliability, but it does **not** change the core backend conclusion above:
  - preview generation is still not backed by a real outfit-rendering service
