# Blender Grass Tuft Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a non-runtime prototype Blender grass atlas that follows the same Station Peaceful bake contract family as layered tree assets.

**Architecture:** Blender generates procedural grass tuft frame PNGs in the existing `4x8` atlas layout. A Python postprocess packs frames into atlas textures and derives wind, snow, season, shadow, and preview images without touching the live runtime asset.

**Tech Stack:** Blender Python, Pillow, unittest, existing layered asset bake profile.

---

### Task 1: Grass Bake Contract

**Files:**
- Create: `C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/grass_atlas/test_grass_tuft_bake_contract.py`
- Create: `C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/grass_atlas/grass_tuft_bake_profile.json`

- [ ] Write a failing contract test for profile inheritance, atlas layout, and mask helper behavior.
- [ ] Run `python -m unittest test_grass_tuft_bake_contract.py` from `tools/grass_atlas` and confirm it fails because the profile/helper module is missing.
- [ ] Add the grass profile and helper module entry points.
- [ ] Re-run the unittest and confirm it passes.

### Task 2: Blender Tuft Renderer

**Files:**
- Create: `C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/grass_atlas/blender_grass_tuft_bake.py`

- [ ] Generate 32 procedural tuft frames with deterministic seeds.
- [ ] Use the shared sun direction and render settings from the grass bake profile.
- [ ] Save frame PNGs to `artifacts/blender_grass_tufts/frames`.

### Task 3: Atlas Postprocess

**Files:**
- Create: `C:/Users/peaceful/Station Peaceful/Station Peaceful/tools/grass_atlas/postprocess_grass_tuft_atlas.py`

- [ ] Pack frame PNGs into `grass_tuft_albedo_atlas.png`.
- [ ] Derive `grass_tuft_wind_mask_atlas.png`, `grass_tuft_snow_mask_atlas.png`, `grass_tuft_season_mask_atlas.png`, `grass_tuft_shadow_atlas.png`, and `grass_tuft_snow_overlay_atlas.png`.
- [ ] Generate `preview_panel.png` and `meta.json`.

### Task 4: Verify Prototype

**Files:**
- Output only: `C:/Users/peaceful/Station Peaceful/Station Peaceful/artifacts/blender_grass_tufts`

- [ ] Run unit tests.
- [ ] Run Blender bake.
- [ ] Run postprocess.
- [ ] Open the preview image and report exact output paths.
