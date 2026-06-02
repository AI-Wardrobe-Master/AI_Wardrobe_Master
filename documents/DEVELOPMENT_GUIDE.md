# AI Wardrobe Master - Development Guide

This guide consolidates local setup, backend startup, Flutter runs, Android real-device debugging, and Windows packaging notes. It replaces the need to read separate Flutter and Windows packaging guides for normal development.

## Repository Layout

```text
AI_Wardrobe_Master/
├── ai_wardrobe_app/      # Flutter client
├── backend/              # FastAPI backend
├── documents/            # Current documentation and archived references
├── DreamO/               # DreamO image generation service
├── Hunyuan3D-2/          # Hunyuan3D dependency
└── docker-compose.yml    # Local backend stack
```

## Backend Environment

Runtime configuration is loaded from environment variables. Docker Compose reads root `.env`; direct backend runs read `backend/.env`.

Create those files from `backend/.env.example`, or use a local helper script if one exists under `scripts/`.

Required provider boundaries:

```text
DASHSCOPE_API_KEY=<dashscope key>
LLM_PROVIDER_NAME=siliconflow
LLM_BASE_URL=https://api.siliconflow.cn/v1
LLM_API_KEY=<siliconflow key>
LLM_MODEL=<siliconflow model name>
ROBOFLOW_API_KEY=<roboflow key>
```

Secrets must stay in `.env` files and must not be committed.

## Docker Backend Startup

Recommended local startup:

```powershell
docker compose up --build
```

This starts:

- PostgreSQL
- Redis
- FastAPI backend
- Celery clothing worker
- Celery styled-generation worker
- DreamO service, if enabled by Compose and local hardware supports it

Useful commands:

```powershell
docker compose up --build -d
docker compose logs -f backend
docker compose down
```

Do not run `docker compose down -v` unless you intentionally want to clear persisted volumes.

Local API:

```text
http://localhost:8000/api/v1
http://localhost:8000/docs
```

Default local demo account created by backend startup:

```text
demo@example.com / demo123456
```

## Direct Backend Run

Use this when you are not running the backend service through Docker:

```powershell
cd backend
uvicorn app.main:app --reload --port 8000
```

If you run workers directly, keep database, Redis, storage, and provider environment variables aligned with `backend/.env`.

## Flutter Setup

From the Flutter app directory:

```powershell
cd ai_wardrobe_app
flutter pub get
flutter analyze
flutter test
```

Run in Chrome:

```powershell
flutter run -d chrome
```

List devices:

```powershell
flutter devices
```

Run on a selected device:

```powershell
flutter run -d <device-id>
```

Format before committing frontend changes:

```powershell
dart format lib test
```

## Android Real-Device Debugging On Windows

When the backend runs on the development machine at port `8000`, Android needs reverse port mapping:

```powershell
adb devices
adb reverse tcp:8000 tcp:8000
flutter run -d <device-id>
```

Without `adb reverse`, the phone cannot reach the Windows host through `127.0.0.1:8000`.

This flow is used for validating:

- login and `/me`
- public wardrobe search
- shared wardrobe detail
- cross-account shared images
- private wardrobe flows

## Windows Desktop Packaging

The project can be packaged as a Windows desktop Flutter app plus Docker-backed backend services. This is an operational/demo packaging path, not the normal development flow.

Important constraints:

- A Flutter Windows app is not a single standalone `.exe`; it must include `data/`, `flutter_windows.dll`, and plugin DLLs.
- Backend, PostgreSQL, Redis, Celery, DreamO, and model caches remain separate runtime services.
- Docker volumes preserve database and model cache unless explicitly removed.
- Hunyuan3D may be disabled in local package settings when hardware cannot support it reliably.

Only use packaging notes when preparing a local demo package. For day-to-day development, use Docker Compose plus `flutter run`.

## Common Failure Checks

Backend cannot start:

- Check `.env` and `backend/.env`.
- Check Docker Desktop is running.
- Check ports `5432`, `6379`, `8000`, and `9000`.
- Check `docker compose logs -f backend`.

Flutter cannot reach backend:

- Confirm backend is listening on port `8000`.
- On Android device, run `adb reverse tcp:8000 tcp:8000`.
- Check frontend API base URL configuration.

Agent endpoint fails:

- Check SiliconFlow variables in `.env`.
- Verify `LLM_MODEL` is set.
- Check backend logs for provider/tool-call errors.

Outfit preview fails:

- Check `DASHSCOPE_API_KEY`.
- Check selected garment assets are ready.

Styled generation fails:

- Check DreamO service health.
- Check GPU/model loading.
- Check selfie and garment asset validation.

## Current Documentation Entry Points

For project context, read:

```text
documents/AGENT_CONTEXT.md
documents/API_CONTRACT.md
documents/DATA_MODEL.md
```

For AI services, read:

```text
documents/AI_PIPELINES.md
```

For backend or Flutter structure, read:

```text
documents/BACKEND_ARCHITECTURE.md
documents/FLUTTER_ARCHITECTURE.md
```
