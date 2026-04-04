---
title: WorldLab - Single Seed World Viewer
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: false
version: 0.3
last_updated: 2026-04-02
depends_on:
  - world_generation_foundation.md
  - native_chunk_generation_spec.md
  - ../../00_governance/PUBLIC_API.md
related_docs:
  - ../../04_execution/world_generation_rollout.md
---

# Feature: WorldLab - Single Seed World Viewer

## Design Intent

Developer/designer tool for inspecting one world seed as one large overview map.

The goal is not comparing many seeds in a grid. The goal is seeing one seed clearly enough to evaluate the overall world shape, mountain chains, rivers, and biome distribution without loading gameplay and walking around the map.

Accessible from main menu as a separate screen. Not part of gameplay - pure dev/design tooling.

## What the user sees

One large global preview for the selected seed.

The preview samples the full wrap-width world (or the canonical latitude span used by the generator) and scales it into one large image that fills most of the screen.

### Supported map modes

1. Terrain preview
- Color by resolved terrain type (`GROUND`, `ROCK`, `WATER`, `SAND`)

2. Biome preview
- Color by biome identity using the registry palette

Only one preview is shown at a time. The user switches modes instead of viewing many tiny cards.

## Controls

- Seed input
- Map mode toggle: `Terrain` / `Biome`
- Generate button
- Cancel button
- Back button

No grid size toggle. No seed atlas. The workflow is: choose seed -> generate one large map -> inspect -> change seed if needed.

## Architecture

### WorldLabSampler

WorldLab does NOT depend on `ChunkManager`, loaded chunks, or gameplay runtime state.

`WorldLabSampler` is a thin preview-only sampling wrapper that:
1. Accepts seed + tile coordinate
2. Returns resolved terrain type and biome palette index
3. Uses native C++ chunk generation if available
4. Falls back to the GDScript sampling stack otherwise

Fallback stack:
- `PlanetSampler`
- `WorldPrePass`
- `WorldComputeContext`
- `BiomeResolver`
- `LocalVariationResolver`
- `SurfaceTerrainResolver`

### Sampling rules

- Sample the full global world view for the selected seed
- Derive preview resolution from screen-oriented limits instead of a seed-card size
- Never instantiate `Chunk`
- Never mutate `ChunkManager`
- Never emit gameplay world events
- Discard stale results via monotonically increasing `generation_id`

## Data Contracts

### Layer: WorldLab Preview Data

- What: one terrain image, one biome image, and preview metadata for the currently selected seed
- Where: `scenes/ui/world_lab.gd`
- Owner (WRITE): `WorldLab`
- Readers (READ): UI display only
- Invariants:
  - preview generation must not modify gameplay state
  - preview generation must not instantiate or mutate loaded chunks
  - preview generation must not use `ChunkManager` as a source of truth
  - stale generation results must be discarded by `generation_id`
- Forbidden:
  - direct reads from runtime chunk streaming state
  - persistence of preview data across sessions
  - gameplay-side event emission

## Iterations

### Iteration 1 - Single-seed global viewer

Goal: render one large seed overview map that can be regenerated for a new seed.

What is done:
- `WorldLab` opens from the main menu
- User enters one seed value
- Tool renders one large global preview instead of a seed grid
- `Terrain` and `Biome` modes are available from one shared preview area
- Generation runs on `WorkerThreadPool`
- Cancellation uses `generation_id` stale-discard pattern
- Native chunk generation is used when available
- GDScript fallback remains available when native generation is unavailable

Acceptance tests:
- [ ] `WorldLab` opens without affecting gameplay state
- [ ] One large preview renders for the selected seed
- [ ] Terrain mode shows the global world shape clearly enough to inspect generator output
- [ ] Biome mode shows different biome regions for the same seed
- [ ] Changing the seed and pressing Generate replaces the previous preview
- [ ] Cancel discards stale generation results cleanly
- [ ] UI remains responsive during generation

Files that may be touched:
- `scenes/ui/world_lab.gd`
- `scenes/ui/world_lab.tscn`
- `docs/02_system_specs/world/world_lab_spec.md`

Files that must NOT be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- gameplay save/load code
- mining / topology / reveal runtime code

## Out-of-scope

- Multi-seed atlas grid
- Metrics panel
- Spawn-local preview mode
- Detail/zoom comparison workflows
- Save/load of preview data
- Entering gameplay from WorldLab
