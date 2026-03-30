---
title: WorldLab — Seed Atlas Viewer
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: false
version: 0.2
last_updated: 2026-03-30
depends_on:
  - world_generation_foundation.md
  - native_chunk_generation_spec.md
  - ../../00_governance/PUBLIC_API.md
related_docs:
  - ../../04_execution/world_generation_rollout.md
---

# Feature: WorldLab — Seed Atlas Viewer

## Design Intent

Developer/designer tool for evaluating world generation quality across seeds. Instead of spawning into each world and running around, the user sees an atlas of seed thumbnails with analytical metrics — instantly comparing world structure, biome distribution, and landmark density.

Accessible from main menu as a separate screen. Not part of gameplay — pure dev/design tooling.

## What the player sees

A grid of seed cards (3×3, 4×4, or 5×5 configurable). Each card shows:

### Two preview modes

**Global preview (DEFAULT on card)** — the full wrap-width world or a large latitudinal slice, sampled at low resolution (1 sample per N tiles). Shows the big picture: continent shapes, mountain chain silhouettes, river systems, biome distribution. Safe zone and land guarantee are invisible at this scale.

**Spawn local preview** — 256×256 tile region around spawn at full resolution. Shows what the player actually sees at start. Available on click/toggle, not the default.

Global preview is the primary mode because the goal is evaluating world composition, not spawn quality.

### Three miniature maps per card
1. **Biome map** — colored by biome identity (plains=green, mountains=gray, water=blue, etc.)
2. **Terrain map** — colored by terrain type (GROUND, ROCK, WATER, SAND)
3. **Structure map** — colored by ridge_strength (red channel) / river_strength (blue) / floodplain_strength (cyan)

### Metrics panel (per seed)

All metrics are formally defined below in "Metric Definitions".

1. Longest river length (tiles)
2. Number of large river basins
3. Largest mountain chain size (tiles)
4. Top-3 biome coverage (% each)
5. Number of small biome noise islands
6. Average transition smoothness
7. Number of landmark zones

### Controls
- Grid size toggle: 9 / 16 / 25 seeds
- Starting seed input (first seed, rest = seed+1, seed+2, ...)
- Preview mode toggle: Global / Spawn Local
- Regenerate button
- Cancel button (stops in-progress generation)

## Metric Definitions

### 1. Longest river length
- **Definition**: the longest chain of connected WATER tiles on the global preview grid
- **Connectivity**: 4-connected (cardinal neighbors only)
- **Unit**: tiles at preview resolution
- **What counts as river**: terrain_type == WATER (not river_strength threshold; uses the resolved terrain output)

### 2. Number of large river basins
- **Definition**: count of 4-connected groups of WATER tiles with area >= `RIVER_BASIN_MIN_TILES`
- **`RIVER_BASIN_MIN_TILES`**: 50 (at preview resolution)
- **Connectivity**: 4-connected

### 3. Largest mountain chain size
- **Definition**: largest 4-connected group of ROCK tiles
- **Unit**: tiles at preview resolution
- **What counts as mountain**: terrain_type == ROCK

### 4. Top-3 biome coverage
- **Definition**: for each biome, count tiles with that biome_id, divide by total sampled tiles. Report top 3 by percentage.
- **Format**: `biome_name: XX.X%` × 3

### 5. Number of small biome noise islands
- **Definition**: count of 4-connected groups of same-biome tiles with area < `NOISE_ISLAND_MAX_TILES`
- **`NOISE_ISLAND_MAX_TILES`**: 20 (at preview resolution)
- **Purpose**: detects noisy/fragmented biome boundaries. Lower = cleaner.

### 6. Average transition smoothness
- **Definition**: for each non-edge tile, check if its biome matches all 4 cardinal neighbors. `smoothness = matching_pairs / total_pairs`. Range [0, 1]. Higher = smoother.
- **Connectivity**: 4-connected cardinal neighbors

### 7. Number of landmark zones
- **Definition**: count of feature hook placements resolved by the generator for the sampled region
- **Source**: `feature_and_poi_payload.placements` count from the generation pass
- **Note**: if feature/POI resolution is unavailable in preview path, report "N/A"

## Architecture

### WorldLabSampler (abstraction layer)

WorldLab does NOT directly depend on `ChunkGenerator` C++ or any specific backend. Instead:

```
WorldLabSampler
├── native path: ChunkGenerator.generate_chunk() if available
└── fallback path: PlanetSampler + LargeStructureSampler + BiomeResolver
                   + LocalVariationResolver + SurfaceTerrainResolver (GDScript)
```

`WorldLabSampler` is a thin wrapper that:
1. Accepts seed + tile coordinate
2. Returns terrain_type, biome_id, structure values (ridge/river/floodplain)
3. Uses native C++ if `WorldGenerator.get_native_chunk_generator()` is available
4. Falls back to GDScript samplers otherwise

This ensures the tool works even without the C++ DLL.

### Global preview sampling

For global preview of a wrap-width world:
- Sample area: `wrap_width × latitude_span` tiles
- Preview resolution: 1 sample per `GLOBAL_PREVIEW_STEP` tiles (e.g., every 8 tiles → 512×512 preview for 4096×4096 world)
- Output: 3 Images at preview resolution (biome, terrain, structure)
- Sampling: iterate at step intervals, call WorldLabSampler per sample point

### Scene structure
```
WorldLab (Control)
├── TopBar (HBoxContainer)
│   ├── SeedInput (SpinBox)
│   ├── GridSizeButton (OptionButton: 3×3, 4×4, 5×5)
│   ├── PreviewModeButton (OptionButton: Global, Spawn Local)
│   ├── GenerateButton
│   └── CancelButton
├── ScrollContainer
│   └── GridContainer
│       └── SeedCard × N (PanelContainer)
│           ├── MinimapContainer (HBoxContainer)
│           │   ├── BiomePreview (TextureRect)
│           │   ├── TerrainPreview (TextureRect)
│           │   └── StructurePreview (TextureRect)
│           ├── SeedLabel (Label)
│           └── MetricsLabel (RichTextLabel)
└── StatusLabel (Label: "Generating seed X/N...")
```

### Cancellation + stale result protection

Each generation batch has a monotonic `generation_id` (int, incremented on each Generate press). Workers check generation_id before writing results. If user presses Generate again or changes grid size:
1. `generation_id` incremented
2. Old workers continue running but their results are discarded (generation_id mismatch)
3. New workers start for the new batch
4. UI shows "Cancelled" for stale cards

No `WorkerThreadPool.cancel()` — just stale-discard pattern (same as boot compute pipeline).

## Data Contracts

### New layer: WorldLab Preview Data
- What: rasterized preview images + computed metrics per seed
- Where: `scenes/ui/world_lab.gd` (transient, not persisted)
- Owner (WRITE): WorldLab scene
- Readers (READ): UI display only
- Invariants:
  - preview generation must not modify any game state
  - must not instantiate Chunk nodes or modify loaded_chunks
  - must not emit EventBus signals
  - stale generation results must be discarded by generation_id check
- Forbidden:
  - accessing ChunkManager or any runtime streaming state
  - persisting preview data across sessions

## Iterations

### Iteration 1 — Basic scene with global biome/terrain minimaps

Goal: see colored minimaps for multiple seeds side by side.

What is done:
- WorldLab scene accessible from main menu
- Grid of seed cards (configurable 3×3 / 4×4 / 5×5)
- WorldLabSampler with native + GDScript fallback
- Global preview: sample full world at low resolution
- Rasterize biome map (biome → color) and terrain map (terrain_type → color) to Image
- Display as TextureRect in grid
- Seed number label on each card
- Generation on WorkerThreadPool, progress indicator
- Cancellation via generation_id (stale discard)

Acceptance tests:
- [ ] WorldLab opens from main menu without affecting game state
- [ ] 9 seed cards display correctly with biome + terrain minimaps in global mode
- [ ] Different seeds show visually different worlds
- [ ] Global preview shows full world wrap-width, not just spawn region
- [ ] Cancel / re-generate discards stale results cleanly
- [ ] UI remains responsive during generation

Files that may be touched:
- `scenes/ui/world_lab.gd` (new)
- `scenes/ui/world_lab.tscn` (new)
- `scenes/ui/main_menu.tscn` (add button)

Files that must NOT be touched:
- `core/systems/world/chunk_manager.gd`
- `core/autoloads/world_generator.gd`
- Any gameplay code

### Iteration 2 — Structure map + metrics

Goal: add structure visualization and analytical numbers.

What is done:
- Structure map: ridge_strength (red), river_strength (blue), floodplain (cyan) as RGB channels
- Compute all 7 metrics during sampling pass (flood-fill on preview-resolution grid)
- Display metrics as formatted text under each card

Acceptance tests:
- [ ] Structure map shows ridge/river patterns clearly
- [ ] All 7 metrics computed and displayed with reasonable values
- [ ] Metrics vary meaningfully between seeds
- [ ] Flood-fill uses 4-connectivity as defined in metric spec

Files that may be touched:
- `scenes/ui/world_lab.gd`

Files that must NOT be touched:
- Same as iteration 1

### Iteration 3 — Detail view, spawn preview, polish

Goal: make the tool comfortable for extended use.

What is done:
- Click seed card → full-size detail panel with zoomable maps
- Toggle between Global and Spawn Local preview per card
- Spawn local preview: 256×256 region around spawn at full resolution
- Biome legend (color → biome name)
- Export seed list as text
- Keyboard navigation (arrow keys to browse)
- Seed comparison mode (select 2 seeds, see side by side)

Acceptance tests:
- [ ] Detail view shows full-resolution maps
- [ ] Spawn local preview shows safe zone / land guarantee area correctly
- [ ] Biome legend is accurate
- [ ] Tool is usable for 30+ minute evaluation sessions

Files that may be touched:
- `scenes/ui/world_lab.gd`
- `scenes/ui/world_lab.tscn`

## Out-of-scope

- Actual gameplay from WorldLab (no spawning into world)
- Save/load of preview data
- Network/multiplayer
- Modding API for WorldLab
- Real-time parameter tuning (adjusting balance live) — future iteration
