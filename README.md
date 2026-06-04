# AI Wardrobe Master

AI Wardrobe Master is a Flutter + FastAPI wardrobe application. The current local stack includes:

- A Flutter client in `ai_wardrobe_app/`
- A FastAPI backend in `backend/`
- PostgreSQL and Redis through Docker Compose
- Local blob storage under `backend/storage/`
- An outfit recommendation Agent exposed at `POST /api/v1/agent/chat`

This README focuses on starting the full local app for development and testing.

## Repository Layout

```text
AI_Wardrobe_Master/
├── ai_wardrobe_app/          # Flutter frontend
├── backend/                  # FastAPI backend
├── documents/                # Architecture, API, data model, and feature docs
├── test/clothing/            # Prepared Agent test clothing metadata and PNG images
├── docker-compose.yml        # Local PostgreSQL, Redis, backend, workers, DreamO service
├── QUICKSTART.md             # Additional local setup notes
└── README.md                 # This file
```

## Prerequisites

Install or prepare the following:

- Docker Desktop, for PostgreSQL and Redis
- Python virtual environment for `backend/`
- Flutter SDK
- Chrome, for the easiest frontend development target

On this Windows workspace, Flutter is installed at:

```powershell
D:\Program\flutter\bin\flutter.bat
```

If `flutter` is not available in your current PowerShell session after updating PATH, either restart PowerShell or use the full path above.

## Start The Database

From the repository root:

```powershell
cd D:\AI_Wardrobe_Master
docker compose up -d db redis
```

If `docker` is not on PATH, use Docker Desktop's full path:

```powershell
cd D:\AI_Wardrobe_Master
& "C:\Program Files\Docker\Docker\resources\bin\docker.exe" compose up -d db redis
```

The backend expects PostgreSQL on `localhost:5432` with the development credentials configured in `backend/.env`.

## Start The Backend

Open a new PowerShell terminal:

```powershell
cd D:\AI_Wardrobe_Master\backend
uv sync
uv run alembic upgrade head
uv run uvicorn app.main:app --reload --port 8000
```

The API documentation should be available at:

```text
http://localhost:8000/docs
```

If `uv` is not installed, install it first from the official installer or use
your preferred Python package manager. The backend dependencies are tracked by
`pyproject.toml` and `uv.lock`; `uv sync` creates and updates the local virtual
environment.

```powershell
uv --version
```

## Seed Agent Test Clothing

For Agent testing, seed the prepared clothing images from `test/clothing/images_no_bg` into a local account.

The account used during local testing is:

```text
email: 11111@gmail.com
password: 11111111
```

Run the seed script:

```powershell
cd D:\AI_Wardrobe_Master\backend
uv run python scripts\seed_agent_clothing.py --email 11111@gmail.com
```

Expected result:

```text
Seed complete: created=30 updated=0 image_created=30 image_updated=0 image_unchanged=0 wardrobe_linked=30
```

You can verify that the Agent search tool can see the seeded wardrobe items:

```powershell
cd D:\AI_Wardrobe_Master\backend
uv run python scripts\test_search_wardrobe_tool.py --email 11111@gmail.com
```

Expected high-level result:

```text
agentSeedItemCount=30
processedFrontImageCount=30
search_tool_verification=success
```

## Start The Flutter Frontend

Open another PowerShell terminal:

```powershell
cd D:\AI_Wardrobe_Master\ai_wardrobe_app
D:\Program\flutter\bin\flutter.bat pub get
D:\Program\flutter\bin\flutter.bat run -d chrome
```

If your PowerShell session already recognizes Flutter, the shorter commands also work:

```powershell
cd D:\AI_Wardrobe_Master\ai_wardrobe_app
flutter pub get
flutter run -d chrome
```

The Flutter web app will open in Chrome on a local development port, for example:

```text
http://localhost:62735
```

The frontend API base URL defaults to:

```text
http://localhost:8000/api/v1
```

For Android emulator testing, the frontend uses `10.0.2.2` by default instead of `localhost`.

## Login Accounts

Development seed accounts:

```text
demo@example.com / demo123456
11111@gmail.com / 11111111
mobile.tester@example.com / test123456
import.tester@example.com / test123456
```

The `11111@gmail.com` account is recommended for Agent Chat testing after running `seed_agent_clothing.py`.

## Agent Chat Test Flow

After logging in as `11111@gmail.com`:

1. Open the `Agent` tab.
2. Ask a wardrobe question, for example:

   ```text
   给我推荐一下明天应该穿什么衣服
   ```

3. Send a follow-up, for example:

   ```text
   我想稍微正式一点
   ```

The current frontend sends one request per turn to:

```text
POST http://localhost:8000/api/v1/agent/chat
```

The backend returns the final Agent result in one response. Real-time streaming of tool calls is not implemented yet. The response includes a final `tools` trace, but the current frontend mainly renders the assistant message, outfit reason, and selected clothing items.

## Useful Checks

Run Flutter static analysis:

```powershell
cd D:\AI_Wardrobe_Master\ai_wardrobe_app
D:\Program\flutter\bin\flutter.bat analyze
```

Some existing files currently produce `info`-level lint messages, such as deprecated `withOpacity` usage and null-aware collection suggestions. These are not compile errors.

Run focused backend Agent tests:

```powershell
cd D:\AI_Wardrobe_Master\backend
uv run pytest tests/test_outfit_agent_conversation.py tests/test_outfit_agent_foundation.py tests/test_outfit_agent_weather.py
```

## Docker Compose Full Stack

For a broader backend stack, you can run:

```powershell
cd D:\AI_Wardrobe_Master
docker compose up --build
```

This starts PostgreSQL, Redis, the FastAPI backend, Celery workers, and the DreamO service. DreamO may require GPU support depending on the local setup.

Common Docker commands:

```powershell
docker compose logs -f backend
docker compose down
docker compose down -v
```

`docker compose down -v` removes the database volume, so use it only when you want a clean local reset.

## Documentation

Recommended reading:

1. `documents/AGENT_CONTEXT.md`
2. `documents/API_CONTRACT.md`
3. `documents/DATA_MODEL.md`
4. `documents/BACKEND_ARCHITECTURE.md`
5. `documents/FLUTTER_ARCHITECTURE.md`
6. `documents/AGENT_OUTFIT_RECOMMENDATION_PLAN.md`
