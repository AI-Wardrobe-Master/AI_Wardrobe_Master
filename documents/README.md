# AI Wardrobe Master - Documentation Index

This folder follows a small enterprise documentation structure: a single entry point, a small set of current source-of-truth documents, and archived references for older or narrower material. For coding agents, start with `AGENT_CONTEXT.md`.

## Current Core Documents

Use these for normal project work:

- `AGENT_CONTEXT.md`: first-read context for coding agents and new contributors.
- `API_CONTRACT.md`: API behavior, auth, request/response contracts, file access rules.
- `DATA_MODEL.md`: entity meanings, ownership, sharing rules, `uid`/`wid`, main-vs-sub wardrobe semantics.
- `BACKEND_ARCHITECTURE.md`: FastAPI structure, routers, services, async boundaries, backend responsibilities.
- `FLUTTER_ARCHITECTURE.md`: Flutter shell, screens, service layer, cache and shared/private UI boundaries.
- `AI_PIPELINES.md`: consolidated AI providers and pipelines, replacing separate DreamO/styled-generation/Agent pipeline notes for routine work.
- `DEVELOPMENT_GUIDE.md`: consolidated setup, Docker, Flutter, Android device, and Windows packaging guidance.
- `USER_STORIES.md`: product stories and acceptance criteria. Use for product decisions, not as the first implementation contract.

## Default Context Bundles

Minimum Agent context:

```text
documents/AGENT_CONTEXT.md
documents/API_CONTRACT.md
documents/DATA_MODEL.md
```

Backend task:

```text
documents/AGENT_CONTEXT.md
documents/API_CONTRACT.md
documents/DATA_MODEL.md
documents/BACKEND_ARCHITECTURE.md
```

Flutter task:

```text
documents/AGENT_CONTEXT.md
documents/API_CONTRACT.md
documents/FLUTTER_ARCHITECTURE.md
documents/DEVELOPMENT_GUIDE.md
```

AI pipeline or model-provider task:

```text
documents/AGENT_CONTEXT.md
documents/API_CONTRACT.md
documents/AI_PIPELINES.md
```

Product or UX task:

```text
documents/AGENT_CONTEXT.md
documents/USER_STORIES.md
documents/FLUTTER_ARCHITECTURE.md
```

## Archive And Reference

`archive/` contains older, narrower, or planning documents that were consolidated into current core docs. They are preserved for traceability, not default context.

Archived examples:

- `archive/AGENT_OUTFIT_RECOMMENDATION_PLAN.md`
- `archive/DREAMO_INTEGRATION.md`
- `archive/FLUTTER_STYLED_GENERATION_GUIDE.md`
- `archive/PROFILE_FACE_SOURCE_VISUALIZE_GUIDE.md`
- `archive/MODULE1.md`
- `archive/MODULE2_COMPLIANCE_SUMMARY.md`
- `archive/FLUTTER_GUIDE_ZH.md`
- `archive/FLUTTER_GUIDE_EN.md`
- `archive/WINDOWS_LOCAL_APP_PACKAGE_GUIDE.md`
- `archive/TECH_STACK.md`

`reference/` contains large or visual references:

- `reference/database_er_model.html`

Only open archived/reference files when the current task explicitly needs that historical or specialized detail. Current code and current core docs take precedence.

## Governance Rules

Keep the top-level `documents/` folder small. New documents should be added only when they create a stable source of truth that cannot fit into an existing core document.

When code changes alter request shapes, entity semantics, provider boundaries, setup commands, or user-visible workflows, update the relevant current core document in the same change.

When a document describes planned behavior, label it as planned. Do not present planned behavior as implemented unless the route/service/model exists in source code.

When in doubt, verify against:

```text
backend/app/api/v1/
backend/app/services/
backend/app/models/
backend/app/schemas/
ai_wardrobe_app/lib/services/
ai_wardrobe_app/lib/ui/screens/
docker-compose.yml
```
