---
title: Runtime SDF Contours - Iteration 07 Ground and Mountain Cutover Validation
doc_type: iteration_brief
status: draft
owner: engineering+art+qa
source_of_truth: false
version: 0.1
last_updated: 2026-05-12
related_docs:
  - runtime_sdf_terrain_contours.md
  - terrain_hybrid_presentation.md
  - mountain_generation.md
  - world_runtime.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
---

# Runtime SDF Contours - Iteration 07 Ground and Mountain Cutover Validation

## Goal

Complete the cutover so ground and mountains use runtime SDF contour rendering
and contour collision as the only active in-game path for their target terrain
ids.

## Non-Goals

- no retained `autotile_47` runtime fallback for ground or mountains
- no new terrain ids
- no save format change unless base worldgen changes are introduced separately
- no building placement redesign
- no water rendering replacement beyond its role as a contour boundary

## Runtime Classification

- authoritative state: existing terrain packet plus runtime diff
- derived state: contour visual and collision caches
- runtime work class: normal streaming, main-thread apply, movement-time O(1)
  reads
- dirty unit: chunk publish and one-tile excavation mutation

## Allowed Files

- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `data/terrain/presentation_profiles/*.tres`
- `data/terrain/shape_sets/*.tres` only to remove ground/mountain target
  ownership from active runtime profiles
- `data/terrain/contour_recipes/*.json`
- `assets/shaders/contour_ground_material.gdshader`
- `assets/shaders/contour_mountain_material.gdshader`
- visual parity tests and movement collision tests

## Forbidden Boundaries

- no hidden legacy rendering path for target ground/mountain ids
- no silent collision downgrade to tile walkability
- no save cache of contour textures or collision fields
- no whole-world precompute

## Implementation Shape

1. Make contour recipes the active presentation source for plains ground,
   dug ground, legacy blocked, mountain wall, and mountain foot.
2. Remove ground and mountain target ids from the active `autotile_47` TileMap
   rendering path.
3. Keep raw logical terrain ids and diff behavior unchanged.
4. Verify chunk readiness requires active contour visual and collision
   readiness for `mountain_mass` and `ground_surface`.
5. Run generator parity exports for mountain and earth presets.
6. Capture matching in-game chunks and compare mask/normal/albedo behavior
   against reference output within documented tolerance.
7. Run movement tests around rounded corners, thin edges, diagonal contacts,
   chunk seams, and newly dug openings.
8. Run streaming tests for load, unload, reload, and save/load around dug
   contour areas.
9. Update docs and screenshots after cutover.

## Cutover Terrain Ids

These terrain ids are contour-only after this iteration:

| Constant | Value | Target contour class |
|---|---:|---|
| `TERRAIN_PLAINS_GROUND` | `0` | `ground_surface` |
| `TERRAIN_LEGACY_BLOCKED` | `1` | `mountain_mass` |
| `TERRAIN_PLAINS_DUG` | `2` | `ground_surface` |
| `TERRAIN_MOUNTAIN_WALL` | `3` | `mountain_mass` |
| `TERRAIN_MOUNTAIN_FOOT` | `4` | `mountain_mass` |

Lake terrain ids keep their existing water presentation in this cutover but
participate in ground contour boundaries as `water_surface`. `water_surface`
must remain available to halo classification and debug readback, but it is not
an independent active readiness gate in this iteration.

## Required Tests and Commands

Run Godot smoke tests:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful"
godot --headless --path . --script res://tools/runtime_sdf_contour_rendering_smoke_test.gd
godot --headless --path . --script res://tools/runtime_sdf_contour_collision_smoke_test.gd
godot --headless --path . --script res://tools/runtime_sdf_contour_excavation_smoke_test.gd
```

Run generator parity tests:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful\tools\rimworld-autotile-lab\desktop_app\core"
cargo test
```

Cutover validation must also search for active TileMap leakage:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful"
rg -n "TERRAIN_PLAINS_GROUND|TERRAIN_PLAINS_DUG|TERRAIN_MOUNTAIN_WALL|TERRAIN_MOUNTAIN_FOOT|TERRAIN_LEGACY_BLOCKED" core/systems/world data/terrain
```

Every remaining match must either be raw logical data handling, contour
assembly, contour rendering, or explicit non-target terrain handling. No match
may route those ids to an active `autotile_47` presentation source.

## Smoke Tests

- no active TileMap cells render target ground or mountain ids
- mountains show organic silhouette, face/top split, bottom outline, rim, and
  normal lighting in normal gameplay camera
- ground edges and dug cuts use the same contour language
- player collision matches visible mountain occupancy at corners and seams
- mining updates both visual opening and collision opening
- saving and loading a dug area recomputes the same contour from diff
- `TERRAIN_LEGACY_BLOCKED` does not leak through the old mountain wall profile

## Definition of Done

- target ground and mountain visuals are contour-only
- target movement blocking is contour-aware only
- visual parity and collision tests pass
- docs index points to the runtime SDF contour spec and iteration briefs
- legacy `autotile_47` remains available only for terrain classes not covered
  by this cutover
