# AI Wardrobe Master Agent Guide

## Purpose

This file captures the working rules for contributors touching the visualization, wardrobe, and demo-facing flows of this repository.

## Ground Truth First

- Never describe a static asset, mock image, or stitched demo as an AI-generated result.
- If a feature is only a front-end demo, label it as a demo in code review notes, personal logs, and delivery docs.
- Before starting feature work, compare the local `sync` workspace with the latest GitHub `origin/main` and merge the remote baseline first.

## Product Language

- App-facing copy should stay in English.
- Internal docs may be Chinese or English, but should clearly separate user-visible behavior from implementation notes.
- Avoid vague labels such as `generated` when the result is actually a fixed asset or manual composition.

## Visualization Rules

- Keep `Wardrobe`, `Virtual Wardrobe`, and `Outfit Collection` as separate concepts.
- `Wardrobe` is for owned or imported clothing items.
- `Outfit Collection` is a shareable saved combination containing tags, selected garments, layering notes, and a preview reference.
- Demo-only visuals are acceptable for presentations, but they must not pretend to be production AI output.
- Form-style export pages should keep a single primary save action instead of duplicating the same commit action in multiple places.

## Backend Truthfulness

- The current backend can process single clothing items through background removal, classification, 3D generation, and angle rendering.
- The current backend does not yet provide a true outfit preview or virtual try-on API.
- Any future “real preview” work must start from an explicit backend contract instead of silently extending the front-end demo.

## Git And Documentation Hygiene

- Do not push to GitHub until the owner reviews the local result.
- Update `groupmembers'markdown/BLJ.md` when visualization scope changes.
- Add or refresh implementation notes when behavior changes across modules.
- Keep prompt notes, Codex scratch files, and local planning artifacts ignored by Git.

## Validation Expectations

- Run static analysis before handoff when possible.
- Add or update widget tests for new visualization flows.
- Prefer a real Android install check for demo-critical changes.
- Record known blockers explicitly, especially backend/model limitations.
