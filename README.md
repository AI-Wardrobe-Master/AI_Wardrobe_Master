# AI Wardrobe Master

## Repository structure

```
ai_wardrobe/
├── ai_wardrobe_app/              # Flutter demo app (wardrobe UI)
│   ├── lib/                      # UI, theming, navigation
│   ├── android/, ios/, web/ ...  # platform-specific projects
│   └── README.md
├── documents/                    # project documentation (architecture, API, data model, etc.)
├── groupmembers'markdown/        # member notes (progress, responsibilities, contributions)
└── README.md                     # this file
```

## Getting started

```bash
# 1. download Hunyuan3D-2 and its pretrained models
git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git

# 2. Go to app directory
cd ai_wardrobe_app

# 3. Install dependencies
flutter pub get

# 4. Run in browser (good for layout preview)
flutter run -d chrome

# 5. Run on a physical device (iOS / Android)
flutter devices              # list device IDs
flutter run -d <device-id>
```

> For detailed environment setup, running on iOS/Android, and common commands, see  
> `documents/FLUTTER_GUIDE_ZH.md` / `documents/FLUTTER_GUIDE_EN.md`.

## Directory details

- **`ai_wardrobe_app/`**  
  - Flutter front-end demo including:  
    - Bottom navigation on mobile / left-side navigation shell on web (Wardrobe / Discover / Add / Visualize / Profile)  
    - Empty-state screens for Wardrobe / Discover / Profile  
    - Outfit visualization canvas (grey mannequin silhouette with tappable body regions)  
    - Light / dark theme toggle (Profile → Settings → Dark mode)

- **`documents/`** – technical documentation entry point  
  - `README.md`: documentation index and overview  
  - `TECH_STACK.md`: overall tech stack and architecture overview  
  - `USER_STORIES.md`: user stories and requirements  
  - `DATA_MODEL.md`: data model and entity relationships  
  - `API_CONTRACT.md`: API design and contract  
  - `BACKEND_ARCHITECTURE.md`: backend architecture (FastAPI + PostgreSQL)  
  - `FLUTTER_ARCHITECTURE.md`: Flutter architecture and layering guidelines  
  - `FLUTTER_GUIDE_ZH.md` / `FLUTTER_GUIDE_EN.md`: Flutter usage guides (ZH / EN)

- **`groupmembers'markdown/`**  
  - Per-member notes on work items, responsibilities, and progress, e.g. `cht.md` (front-end skeleton, docs, etc.).

## Suggested reading order

1. `documents/TECH_STACK.md`: high-level tech stack and system overview  
2. `documents/USER_STORIES.md`: what problems we are solving  
3. `documents/DATA_MODEL.md` + `documents/API_CONTRACT.md`: entities and APIs  
4. `documents/FLUTTER_ARCHITECTURE.md`: recommended Flutter architecture  
5. `documents/FLUTTER_GUIDE_ZH.md` or `FLUTTER_GUIDE_EN.md`: get the app running locally
