---
title: Runtime SDF Contours - Iteration 04 Chunk Rendering
doc_type: iteration_brief
status: draft
owner: engineering+art
source_of_truth: false
version: 0.1
last_updated: 2026-05-12
related_docs:
  - runtime_sdf_terrain_contours.md
  - terrain_hybrid_presentation.md
  - mountain_generation.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
---

# Runtime SDF Contours - Iteration 04 Chunk Rendering

## Goal

Render ground and mountain contour results in `ChunkView` using chunk-sized SDF
mask, height, normal, and material data instead of per-cell `autotile_47`
TileMap atlas cells.

## Non-Goals

- no movement collision change
- no excavation dirty refresh
- no save/load change
- no legacy ground/mountain TileMap fallback after this rendering path is
  activated for the target terrain ids
- no GDScript constant contour generation or immediate ground placeholder after
  cutover; active contour visuals come from native contour results only

## Runtime Classification

- authoritative state: unchanged terrain packet and runtime diff
- derived state: contour textures and scene resources
- runtime work class: main-thread resource upload and scene apply
- dirty unit: one chunk contour visual resource per class

## Allowed Files

- `core/systems/world/chunk_view.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `data/terrain/presentation_profiles/*.tres`
- `data/terrain/shader_families/*.tres`
- `data/terrain/contour_recipes/*.json`
- `assets/shaders/contour_ground_material.gdshader`
- `assets/shaders/contour_mountain_material.gdshader`
- `assets/textures/terrain/*`
- new `tools/runtime_sdf_contour_rendering_smoke_test.gd`

## Forbidden Boundaries

- no GDScript contour generation
- no pixel loops in `ChunkView`
- no 1x1 ground placeholder or empty/full constant contour fast path in
  GDScript
- no movement query changes
- no save/load changes

## Implementation Shape

1. Add a contour visual layer owner inside `ChunkView`.
2. Convert `ContourChunkResultV1` byte arrays into Godot textures on the main
   thread.
3. Create one visible contour node per terrain class per chunk.
4. Use world-space material sampling so adjacent chunks do not show material UV
   seams.
5. Apply the mask texture channels as top, face, back, and occupancy.
6. Apply normal and height textures to the contour shader.
7. Preserve mountain cover visibility by applying cover masks to the mountain
   contour material.
8. Stop applying ground and mountain terrain ids to TileMap layers in contour
   mode. If initial native contour resources are missing, the chunk remains
   hidden. During a later dirty refresh, an already-published chunk may keep
   its previous visual revision visible while readiness/collision remain stale.
9. Keep water rendering outside this cutover unless the lake spec explicitly
   moves water to contour rendering.

## Layering and Cover Contract

`ChunkView` uses this z-order:

| Layer | z_index | Role |
|---|---:|---|
| ground contour | `0` | ground material and organic ground edges |
| water layer | `1` | existing water presentation |
| mountain contour | `10` | mountain top/face/outline, cover-gated |
| debug overlays | `100` | developer-only diagnostics |

Mountain contour rendering remains keyed by `mountain_id` for cover. A chunk may
have multiple mountain contour visual resources when multiple mountain ids are
present. Each mountain visual samples the same class recipe but receives its own
cover mask and mountain id membership mask.

If a mountain tile belongs to `mountain_id = 0`, it renders through an explicit
`mountain_id = -1` visual bucket so missing ids are visible as data errors in
debug state rather than silently hidden.

## Required Tests and Commands

Run Godot smoke test:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful"
godot --headless --path . --script res://tools/runtime_sdf_contour_rendering_smoke_test.gd
```

The smoke test must assert:

- `ChunkView` creates contour visual nodes for ground and mountain classes
- target terrain ids do not call the active TileMap terrain apply path in
  contour mode
- stale contour revisions do not become ready; initial stale/missing native
  resources keep the chunk hidden, while dirty refresh may keep the previous
  visual revision visible
- mountain contour material receives mask, height, normal, cover mask,
  chunk origin, and tile size uniforms
- two mountain ids in one chunk create two cover-gated mountain visual buckets

## Smoke Tests

- a chunk with only plains ground shows the ground contour material
- a chunk with mountain mass shows top/face split and bottom outline
- adjacent chunks render without visible contour seams
- cover mask hides unrevealed mountain areas without changing contour shape
- toggling debug views does not mutate contour textures
- no `autotile_47` TileMap cells are applied for cutover ground/mountain ids
- missing initial contour resources keep the chunk hidden instead of rendering
  legacy TileMap cells or a placeholder

## Definition of Done

- ground and mountain visuals come from contour result textures
- contour shader reproduces generator channel semantics
- contour shader samples exported unlit albedo/normal material maps and does
  not bake alternate height tint or hardcoded color grading into albedo
- mountain outline, rim, face, and top zones are visible in game
- legacy tile atlas cells are not used for target ground and mountain rendering
