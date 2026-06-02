# AI Wardrobe Master - AI Pipelines

This document is the consolidated reference for AI-related services and generation flows. It replaces the need to read separate DreamO, styled-generation, profile-face, clothing-digitization, and Agent planning documents for ordinary implementation work.

## Provider Boundaries

Keep provider responsibilities separate:

- SiliconFlow is the outfit recommendation Agent LLM provider. It is called through an OpenAI-compatible `/chat/completions` API.
- DashScope is used for image generation in outfit preview flows.
- Roboflow is used by the clothing classification workflow.
- Hunyuan3D is used for clothing digitization: 2D garment image to 3D mesh and angle views.
- DreamO is used for styled generation: selfie plus garment images plus scene prompt to a realistic fashion portrait.

Do not reuse one provider key for another provider unless the provider is explicitly the same. Runtime secrets belong in `.env` files, never in documentation.

## Runtime Configuration

Important variables:

```text
DASHSCOPE_API_KEY=<dashscope key>
LLM_PROVIDER_NAME=siliconflow
LLM_BASE_URL=https://api.siliconflow.cn/v1
LLM_API_KEY=<siliconflow key>
LLM_MODEL=<siliconflow model name>
ROBOFLOW_API_KEY=<roboflow key>
```

Docker Compose reads the repository root `.env`. Direct backend runs read `backend/.env`.

## Clothing Digitization Pipeline

Purpose: turn uploaded clothing photos into processed garment assets and optional 3D views.

Flow:

```text
front/back clothing image
-> store original images
-> create processing task
-> background removal
-> Roboflow category classification
-> Hunyuan3D mesh generation
-> angle rendering
-> persist processed images, model, and task status
```

Main API surface:

```text
POST /api/v1/clothing-items
GET /api/v1/clothing-items/{id}
PATCH /api/v1/clothing-items/{id}
GET /api/v1/clothing-items/{id}/processing-status
POST /api/v1/clothing-items/{id}/retry
GET /api/v1/clothing-items/{id}/angle-views
GET /api/v1/clothing-items/{id}/model
```

Implementation anchors:

```text
backend/app/api/v1/clothing.py
backend/app/services/clothing_pipeline.py
backend/app/services/background_removal_service.py
backend/app/services/ai_service.py
backend/app/services/model_3d_service.py
backend/app/services/angle_renderer_service.py
```

Current local Docker defaults may disable or reduce Hunyuan3D work to keep development hardware usable. Check `docker-compose.yml` and `.env` before assuming full 3D generation is enabled.

## Outfit Preview Pipeline

Purpose: generate a preview image from selected clothing/outfit assets.

Provider: DashScope.

Flow:

```text
selected outfit/clothing items
-> create outfit preview task
-> resolve garment assets
-> call DashScope
-> persist preview task result
-> optionally save outfit
```

Main API surface:

```text
POST /api/v1/outfit-preview-tasks
GET /api/v1/outfit-preview-tasks
GET /api/v1/outfit-preview-tasks/{task_id}
POST /api/v1/outfit-preview-tasks/{task_id}/save
GET /files/outfit-preview-tasks/{task_id}/{kind}
GET /files/outfits/{outfit_id}/preview
```

Implementation anchors:

```text
backend/app/api/v1/outfit_preview.py
backend/app/services/outfit_preview_service.py
backend/app/services/prompt_builder_service.py
backend/app/models/outfit_preview.py
```

## Styled Generation Pipeline

Purpose: generate a realistic fashion portrait from a selfie, processed garment assets, and a scene prompt.

Provider/service: DreamO service, usually running on port `9000`.

Flow:

```text
selfie image + clothing item + scene prompt
-> POST /api/v1/styled-generations
-> store selfie and DB record
-> Celery styled_generation queue
-> validate garment has processed front asset
-> preprocess selfie
-> build prompt
-> call DreamO /generate
-> store result image
-> update generation status
```

Main API surface:

```text
POST /api/v1/styled-generations
GET /api/v1/styled-generations/{id}
GET /api/v1/styled-generations
POST /api/v1/styled-generations/{id}/retry
DELETE /api/v1/styled-generations/{id}
GET /files/styled-generations/{gen_id}/{kind}
```

Implementation anchors:

```text
backend/app/api/v1/styled_generation.py
backend/app/services/styled_generation_pipeline.py
backend/app/services/dreamo_client_service.py
backend/app/services/selfie_preprocessing_service.py
backend/app/models/styled_generation.py
DreamO/server.py
```

DreamO notes:

- DreamO is independent from Hunyuan3D.
- DreamO consumes already processed garment assets.
- `garment_images` supports multiple garments and expects the backend to order them by slot.
- GPU and model-cache behavior depends on local Docker/DreamO environment variables.

## Outfit Recommendation Agent

Purpose: produce a structured outfit recommendation from natural language, weather/location context, wardrobe contents, and controlled backend taxonomy.

Provider: SiliconFlow through OpenAI-compatible chat completions.

Current public endpoint:

```text
POST /api/v1/agent/outfit-recommendation
```

Current request shape includes:

- `message`
- optional `latitude` / `longitude`
- optional `city`
- optional `targetDate`
- optional `wardrobeId`
- optional `source`
- optional `tags`
- optional `limit`
- optional `generatePreview`

Current response includes:

- provider name/model
- structured outfit
- recommendation, weather, and preference reasons
- missing item notes
- preview status
- tool results
- optional raw model output

Implementation anchors:

```text
backend/app/api/v1/agent.py
backend/app/schemas/agent.py
backend/app/services/agent_llm_service.py
backend/app/services/outfit_agent_service.py
backend/app/services/outfit_agent_tools.py
backend/app/services/conversation_store.py
backend/app/services/clothing_taxonomy.py
```

Agent constraints:

- The model must not invent clothing IDs or database facts.
- Tool-facing filters are validated by backend schemas and taxonomy.
- Weather suitability uses controlled tags such as `season`, `weather_type`, and `weather_profile`.
- Preview generation may fail independently; the Agent should return a recommendation without pretending an image exists.

Planned conversation/chat behavior is described in archived planning material, but only source code determines what is implemented now.

## Frontend Touchpoints

Relevant Flutter service files:

```text
ai_wardrobe_app/lib/services/clothing_api_service.dart
ai_wardrobe_app/lib/services/outfit_preview_api_service.dart
ai_wardrobe_app/lib/services/styled_generation_api_service.dart
ai_wardrobe_app/lib/services/face_profile_service.dart
```

Relevant UI areas:

```text
ai_wardrobe_app/lib/ui/screens/visualization_hub_screen.dart
ai_wardrobe_app/lib/ui/screens/scene_preview_demo_screen.dart
ai_wardrobe_app/lib/ui/screens/profile_screen.dart
ai_wardrobe_app/lib/ui/screens/capture/
```

The Face + Scene page currently has demo behavior in parts of the frontend. Verify current code before describing it as a fully production DreamO submission flow.

## Troubleshooting Checklist

If Agent calls fail, check:

- `LLM_PROVIDER_NAME`
- `LLM_BASE_URL`
- `LLM_API_KEY`
- `LLM_MODEL`
- provider support for OpenAI-compatible `tool_calls`

If outfit preview fails, check:

- `DASHSCOPE_API_KEY`
- garment asset readiness
- task logs for `outfit_preview_service`

If styled generation fails, check:

- `DREAMO_SERVICE_URL`
- DreamO container health
- GPU/model loading state
- selfie validation
- garment processed-front availability

If clothing processing fails, check:

- worker queue state
- Roboflow key/workflow configuration
- Hunyuan3D enablement and hardware limits
- storage path and file permissions
