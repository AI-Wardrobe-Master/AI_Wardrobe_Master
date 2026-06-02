# AI Wardrobe Master - Agent Context

This is the first document to give to a coding or planning agent. It summarizes the current project shape and points to the documents that contain deeper details. If this document conflicts with source code, trust the source code.

## Project Snapshot

AI Wardrobe Master is a Flutter + FastAPI wardrobe application. Users can upload clothing, organize it into wardrobes, share public sub-wardrobes, browse public content, generate outfit previews, and ask an outfit recommendation Agent for structured outfit suggestions.

The repository has two active codebases:

- `ai_wardrobe_app/`: Flutter client. App code is under `lib/`, tests under `test/`, images under `assets/`.
- `backend/`: FastAPI backend. App code is under `app/`, with `api/`, `services/`, `crud/`, `models/`, `schemas/`, `db/`, and `core/`.

Supporting directories:

- `documents/`: architecture, API, data model, integration, and agent context docs.
- `DreamO/`: independent image generation service used by styled generation.
- `Hunyuan3D-2/`: clothing 3D generation dependency used by the clothing pipeline.
- `groupmembers'markdown/`: member notes and progress records; do not treat these as implementation truth.

## Current Source Of Truth

Use this priority when answering or editing:

1. Current source code in `backend/` and `ai_wardrobe_app/`.
2. Top-level docs in `documents/`, especially this file, `API_CONTRACT.md`, `DATA_MODEL.md`, `BACKEND_ARCHITECTURE.md`, and `FLUTTER_ARCHITECTURE.md`.
3. Archived planning and feature notes under `documents/archive/`, only when discussing intended future behavior or historical decisions.
4. Team notes under `groupmembers'markdown/`, only as historical context.

Important: some documents intentionally preserve older module language. When they mention a legacy idea, check whether the current code has already replaced it.

## Local Development

Recommended backend startup from the repository root:

```powershell
docker compose up --build
```

Runtime configuration is read from environment variables:

- root `.env`: consumed by `docker-compose.yml`.
- `backend/.env`: consumed by direct local backend runs.

If a local helper script exists under `scripts/`, it can generate those files. Otherwise, create them manually from `backend/.env.example` and the provider variables listed in `AI_PIPELINES.md`.

Do not commit `.env` files or API keys. The configured provider boundary is:

- Outfit recommendation Agent LLM: SiliconFlow through the OpenAI-compatible API.
- DashScope: outfit preview image generation.
- Roboflow: clothing classification workflow.
- Hunyuan3D: clothing digitization / 3D mesh / angle rendering.
- DreamO: face + garment + scene styled generation.

Backend direct run:

```powershell
cd backend
uvicorn app.main:app --reload --port 8000
```

Flutter local run:

```powershell
cd ai_wardrobe_app
flutter pub get
flutter run -d chrome
```

Android real-device backend access needs:

```powershell
adb reverse tcp:8000 tcp:8000
```

## Backend Architecture

The backend is a FastAPI app mounted at `/api/v1`. Main router files under `backend/app/api/v1/` include:

- `auth.py`: register, login, logout.
- `me.py`: current user context and creator capability flags.
- `clothing.py`: clothing upload, update, delete, search, processing status, retry, angle views, model download.
- `wardrobe.py`: personal wardrobes, public wardrobes, shared wardrobe lookup by `wid`, wardrobe item association.
- `files.py`: file serving and access control.
- `card_packs.py`: card pack list, publish, archive, delete.
- `creators.py` and `creator_items.py`: creator profile and legacy creator item facade.
- `imports.py`: import history and public content import flows.
- `outfit_preview.py`: outfit preview tasks and saved outfit previews.
- `styled_generation.py`: DreamO-backed styled generation tasks.
- `attributes.py`: taxonomy/options.
- `agent.py`: outfit recommendation Agent endpoint.

The main async boundaries are:

- Clothing processing tasks: upload originals, enqueue processing, remove background, classify, generate 3D, render angle views, persist assets.
- Outfit preview tasks: generate preview images for selected outfit items.
- Styled generation tasks: upload selfie, select processed garment, call DreamO through Celery, store generated portrait.

Background work uses Redis/Celery. PostgreSQL is the main database. Local file storage is the default storage mode, with S3-compatible settings available in configuration.

## Data Model Mental Model

`ClothingItem` is the canonical clothing entity. Creator items and consumer-owned clothing both resolve to this unified table. The legacy `creator-items` route exists as a compatibility facade, not as the canonical model.

`Wardrobe` is a container/association surface, not a copy of clothing data. A clothing item can appear in multiple wardrobes through `WardrobeItem`.

Main wardrobe and sub-wardrobe semantics are different:

- Main wardrobe delete means deleting the clothing entity.
- Sub-wardrobe removal means deleting only the wardrobe association.

Public sharing is modeled as public `SUB` wardrobes:

- A user-created shared wardrobe is a public `SUB` wardrobe.
- A published card pack is also mapped to a public `SUB` wardrobe with `source = CARD_PACK`.
- Discover shows these public wardrobes in one browse/search surface.
- `wid` is the external wardrobe identifier; `uid` is the external user identifier.

File access follows ownership plus public sharing:

- The owner can access their own clothing files.
- Other users can access clothing files only when the item belongs to a public `SUB` wardrobe.
- Private clothing remains inaccessible to unrelated users.

## Frontend Architecture

The Flutter root shell is `ai_wardrobe_app/lib/ui/root_shell.dart`.

Mobile navigation:

- `Wardrobe`: private wardrobe and sub-wardrobe management.
- `Discover`: public shared wardrobes and creators.
- `Add`: central action menu for adding clothing and creating card packs.
- `Visualize`: visualization hub.
- `Profile`: current user and creator capability state.

Important screens:

- `WardrobeScreen`: own clothing, wardrobe actions, sharing, delete/remove semantics.
- `DiscoverScreen`: public wardrobe search and browsing.
- `SharedWardrobeDetailScreen`: read public wardrobe by `wid` and list items.
- `SharedClothingDetailScreen`: read-only public clothing details.
- `VisualizationHubScreen`: entry point for Canvas Studio and Face + Scene.
- `ScenePreviewDemoScreen`: demo face + scene flow.
- `ProfileScreen`: current account state from `/me`.

Frontend service layer files under `ai_wardrobe_app/lib/services/` encapsulate API access and local cache behavior. Keep shared/public flows separate from private cache mutation paths.

## API Surface To Remember

Base URL for local development:

```text
http://localhost:8000/api/v1
```

Authentication:

```text
Authorization: Bearer <JWT>
```

Local demo account created by Docker startup:

```text
demo@example.com / demo123456
```

Core endpoints:

- `POST /auth/register`
- `POST /auth/login`
- `GET /me`
- `POST /clothing-items`
- `GET /clothing-items`
- `GET /clothing-items/{id}`
- `PATCH /clothing-items/{id}`
- `DELETE /clothing-items/{id}`
- `GET /clothing-items/{id}/processing-status`
- `POST /clothing-items/{id}/retry`
- `POST /clothing-items/search`
- `GET /wardrobes`
- `POST /wardrobes`
- `PATCH /wardrobes/{id}`
- `GET /wardrobes/public`
- `GET /wardrobes/by-wid/{wid}`
- `GET /wardrobes/by-wid/{wid}/items`
- `POST /wardrobes/export-selection`
- `POST /styled-generations`
- `GET /styled-generations/{id}`
- `GET /styled-generations`
- `POST /styled-generations/{id}/retry`
- `DELETE /styled-generations/{id}`
- `POST /outfit-preview-tasks`
- `POST /agent/outfit-recommendation`

`/files/...` is mounted separately from `/api/v1` and serves stored images/models through backend access-control logic.

## Outfit Recommendation Agent

The Agent is a backend feature in `backend/app/services/outfit_agent_service.py`, exposed through `backend/app/api/v1/agent.py`.

Current public route:

```text
POST /api/v1/agent/outfit-recommendation
```

The request accepts natural language plus optional location/date/wardrobe/tag filters. The response returns provider metadata, structured outfit recommendation, reasons, missing items, preview result state, tool results, and optional raw model output.

Agent provider configuration:

- `LLM_PROVIDER_NAME=siliconflow`
- `LLM_BASE_URL=https://api.siliconflow.cn/v1`
- `LLM_API_KEY=<siliconflow key>`
- `LLM_MODEL=<siliconflow model name>`

The Agent should not invent database facts. It must use backend tools and validated clothing IDs. Tool-facing tag filters are constrained by backend taxonomy. Weather suitability is represented by controlled tags such as `season`, `weather_type`, and `weather_profile`, not by arbitrary model-created fields.

Archived Agent planning notes describe a broader intended conversation design. Treat archived planning context as historical unless the code confirms the endpoint or persistence behavior already exists.

## Visualization And Generation Pipelines

There are three related but distinct AI pipelines:

Clothing digitization:

```text
front/back image upload -> background removal -> category classification -> Hunyuan3D mesh -> angle rendering -> stored assets
```

Outfit preview:

```text
selected clothing items -> outfit preview task -> DashScope image generation -> preview image/file record
```

Styled generation:

```text
selfie + processed garment + scene prompt -> Celery styled_generation queue -> DreamO service -> generated fashion portrait
```

Do not confuse these:

- Hunyuan3D does not generate the final face + scene portrait.
- DreamO does not replace the clothing 3D pipeline.
- DashScope API key is not the Agent LLM key.
- SiliconFlow is the Agent LLM provider.

## Document Map

Read in this order for broad context:

1. `documents/AGENT_CONTEXT.md`: quick project context for agents.
2. `documents/API_CONTRACT.md`: API behavior and request/response contracts.
3. `documents/DATA_MODEL.md`: entity meanings and sharing rules.
4. `documents/BACKEND_ARCHITECTURE.md`: backend modules and responsibilities.
5. `documents/FLUTTER_ARCHITECTURE.md`: current Flutter shell, screens, and services.
6. `documents/AI_PIPELINES.md`: consolidated AI/model provider and pipeline reference.
7. `documents/DEVELOPMENT_GUIDE.md`: local setup, Docker, Flutter, Android, and packaging guide.

Use these for specific topics:

- `documents/USER_STORIES.md`: product stories and acceptance criteria.
- `documents/archive/`: historical, planning, and feature-specific documents preserved for traceability.
- `documents/reference/`: large or visual references such as ER diagrams.

Do not include every document by default. Archived and reference files are task-specific or historical references. Load them only when the current task needs that topic.

## Common Mistakes To Avoid

Do not treat `groupmembers'markdown/` as source of truth.

Do not assume all planned Agent endpoints exist. Check `backend/app/api/v1/agent.py`.

Do not merge DashScope and SiliconFlow configuration. DashScope is for image generation; SiliconFlow is for the Agent LLM.

Do not expose or commit API keys. `.env` files are local runtime configuration.

Do not treat public sharing as changing ownership. It only expands read access.

Do not reuse private clothing detail actions on shared clothing detail screens.

Do not delete a clothing entity when the user only removes it from a sub-wardrobe.

Do not bypass storage services when adding media records; use the existing blob/file service patterns.

Do not add new free-form clothing/weather tags for Agent behavior without checking backend taxonomy.
