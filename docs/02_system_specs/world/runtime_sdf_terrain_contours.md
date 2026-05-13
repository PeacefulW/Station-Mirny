---
title: Runtime SDF Terrain Contours
doc_type: system_spec
status: draft
owner: engineering+art
source_of_truth: true
version: 0.1
last_updated: 2026-05-12
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PROJECT_GLOSSARY.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0005-light-is-gameplay-system.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - world_grid_rebuild_foundation.md
  - world_runtime.md
  - terrain_hybrid_presentation.md
  - mountain_generation.md
  - runtime_sdf_contours_iteration_01_generator_recipe_export.md
  - runtime_sdf_contours_iteration_02_native_contour_field.md
  - runtime_sdf_contours_iteration_03_streaming_packets.md
  - runtime_sdf_contours_iteration_04_chunk_rendering.md
  - runtime_sdf_contours_iteration_05_collision_queries.md
  - runtime_sdf_contours_iteration_06_excavation_dirty_updates.md
  - runtime_sdf_contours_iteration_07_cutover_validation.md
---

# Runtime SDF Terrain Contours

## Purpose

Define the target runtime architecture for replacing square cell-based terrain
presentation with continuous SDF-authored contours for ground and mountains.

This spec exists because the tile generator preview and the current game runtime
do not share the same geometry model:

- the generator's live preview is a global signed-distance-field render over a
  map mask
- the current game renders ground and mountains through per-cell `autotile_47`
  TileMap atlases
- current movement blocking is tile-walkability sampling, not contour collision

The target is a full runtime transfer of the generator preview language:
rounded silhouettes, warped organic boundaries, mountain bottom outline,
top/face/base material separation, normal lighting, and collision that follows
the visible contour.

## Gameplay Goal

Terrain must stop reading as a square grid at gameplay distance. Mountains,
ground banks, dug cuts, lake shores, and mountain-ground contacts must use one
continuous contour vocabulary. A player must never collide with an invisible
square corner and must never walk through a visible mountain edge.

## Core Decision

Runtime ground and mountain presentation moves from tile atlas topology to a
native SDF contour layer.

The old `autotile_47` path is not a target fallback for ground or mountains
after cutover. It remains a legacy implementation detail until the cutover
iteration removes those terrain ids from the TileMap presentation path.

## Scope

This spec covers:

- authored generator recipes for runtime SDF contours
- native chunk-local SDF contour computation with halo sampling
- generated visual masks, height fields, normals, and collision fields
- ground and mountain contour rendering in loaded chunks
- movement collision aligned to the visible contour
- excavation dirty updates for mined mountain tiles
- acceptance tests and visual parity checks against generator preview output

## Out of Scope

This spec does not define:

- new worldgen terrain classes
- new save fields for contour data
- multiplayer replication of contour caches
- building placement redesign
- room solving or indoor solving changes
- subsurface terrain rendering
- runtime dependency on the generator shell application
- keeping a runtime `autotile_47` fallback for ground or mountains after cutover

## Dependencies

- `World Grid Rebuild Foundation` for `64 px` logical tiles and `16 x 16`
  chunks
- `World Runtime V0` for chunk packets, runtime diff, and streaming ownership
- `Terrain Hybrid Presentation` for material separation and registry concepts
- `Mountain Generation V1` for mountain ids, mountain flags, excavation, and
  cover behavior
- ADR-0001 for dirty update and runtime work classification
- ADR-0002 for cylindrical X wrapping
- ADR-0003 for immutable base plus runtime diff ownership
- ADR-0005 for light and normal-map boundaries
- ADR-0006 for surface/subsurface separation
- ADR-0007 for keeping worldgen distinct from environment runtime

## Current Runtime Facts

The current game:

- uses `terrain_ids`, `terrain_atlas_indices`, `walkable_flags`,
  `mountain_id_per_tile`, `mountain_flags`, and `mountain_atlas_indices` in
  chunk packets
- derives local mountain and ground atlas refreshes in `WorldStreamer`
- applies visual cells through `ChunkView` TileMap layers
- validates `autotile_47` shape sets with `47` cases in
  `TerrainPresentationRegistry`
- blocks player movement by sampling `WorldStreamer.is_walkable_at_world()` at
  multiple points around the player footprint
- exposes `WorldCore.build_mountain_contour_debug()` as debug-only data, not as
  collision, save, or gameplay truth

The generator:

- uses a global SDF for map preview
- applies corner smoothing, diagonal smoothing, contour relax, warp, roughness,
  rim, face, and outline controls in the preview path
- exports material stacks, masks, height, and normal images
- currently does not export the live global SDF preview as a runtime-ready
  contour contract

## Non-Negotiable Requirements

- The visual contour and movement collision must be derived from the same SDF
  field.
- The runtime must not depend on Python, the desktop shell, or a generator
  process.
- Heavy contour computation must run in native code or worker-owned native
  tasks, not in GDScript loops.
- Main-thread work is limited to bounded resource upload and scene apply.
- The contour layer must be ready before a chunk becomes movement-ready.
- Contour cache data is never saved. It is recomputed from base chunk data plus
  runtime diff.
- Excavation mutates one logical tile, then refreshes only the bounded contour
  dirty region affected by that mutation.
- X sampling must wrap; Y sampling must clamp or report outside according to
  the existing world cylinder contract.
- Generator preview references and in-game render captures must have a defined
  parity test.
- There is no runtime ground/mountain fallback to `autotile_47` after cutover.
- Target ground and mountain chunks must fail closed for readiness: if contour
  collision data is missing, stale, or invalid, the chunk is not
  movement-ready. Initial missing visual data keeps the chunk hidden; a dirty
  already-published chunk may keep its previous visual revision visible while
  collision/readiness remain blocked.
- Iteration 07 active readiness is gated by `mountain_mass` and
  `ground_surface` results. `water_surface` remains a boundary/debug contour
  class and must not block chunk visibility or movement readiness while lake
  presentation still uses the existing water layer.

## Law 0 Classification

| Question | Answer |
|---|---|
| Canonical world data, runtime overlay, or visual only? | `terrain_ids`, `walkable_flags`, mountain ids, mountain flags, and runtime diff remain canonical. SDF masks, visual textures, meshes, and collision fields are derived runtime caches. |
| Save/load required? | No for contour data. Existing diff/save data remains the only persistence source for dug terrain. Generator recipes and authored material assets are repository assets. |
| Deterministic? | Yes. For a given world seed, world version, chunk data, diff state, contour recipe, and chunk coordinate, output must be stable. |
| Must work on unloaded chunks? | Canonical queries work as today. Contour collision only exists for loaded or actively prepared chunks; chunks do not become movement-ready until contour data is ready. |
| C++ compute or main-thread apply? | Native compute for SDF, masks, normals, and collision fields. Main thread only uploads textures/meshes and swaps chunk resources. |
| Dirty unit | Chunk plus halo for publish. One authoritative tile plus bounded contour halo for excavation and local runtime mutation. |
| Single owner | `WorldCore` and native contour modules own SDF computation. `WorldStreamer` owns scheduling and readiness. `ChunkView` owns visual apply. Movement queries read through `WorldStreamer`. |
| 10x / 100x scale path | Per-chunk native compute, compact masks, no whole-world scans, no per-pixel GDScript loops, no per-tile cross-language calls. |
| Main-thread blocking risk | Resource upload and node update only. Large texture generation, distance transforms, normal generation, and collision rasterization are outside the main thread. |
| Hidden GDScript fallback? | Forbidden. Missing native contour support fails loudly in development. |
| Whole-world prepass? | Forbidden. Each result is derived from one chunk plus bounded halo. |

## Runtime Architecture

### Logical Truth

The logical world remains tile/chunk based:

- one logical tile is `64 px`
- one chunk is `16 x 16` logical tiles
- runtime diff mutates logical tiles
- mining remains a logical tile mutation
- buildability remains tile-grid based until a separate building-placement spec
  changes it

This keeps persistence, worldgen, streaming, and excavation bounded.

### Contour Truth

The contour system derives a continuous field from effective terrain state:

```text
effective terrain state = base chunk packet + loaded runtime diff overrides
solid masks = terrain-class interpretation of effective state
SDF field = signed distance over solid masks with generator recipe shaping
visual masks = top / face / back / occupancy channels from SDF field
collision field = movement-blocking contour threshold from the same SDF field
```

The same SDF field drives pixels and blocking. Outline, shading, rim, debris,
and material tint do not define collision. Collision follows the occupancy
boundary.

### No-Fallback Readiness

The target contour path is not optional for terrain ids covered by this spec.
After cutover:

- `TERRAIN_PLAINS_GROUND`
- `TERRAIN_PLAINS_DUG`
- `TERRAIN_MOUNTAIN_WALL`
- `TERRAIN_MOUNTAIN_FOOT`
- `TERRAIN_LEGACY_BLOCKED`

must not render through ground or mountain `autotile_47` TileMap sources.

If a loaded chunk contains any of those terrain ids and no matching contour
result has ever been published, the chunk may only become visible through a
fresh `ground_surface` loading placeholder while `mountain_mass` is still
pending. This placeholder is visual-only, is not contour-ready, and does not
make movement into the chunk ready. If no fresh `ground_surface` result exists
yet, the chunk stays hidden. If a later dirty revision is pending, the previous
visual revision may remain visible, but movement into the stale contour region
still returns not ready. This is an intentional fail-closed readiness rule, not
a fallback.

Contour worker requests must produce `ground_surface` before
`mountain_mass` so the visual-only placeholder can be published quickly on
startup or teleport while the heavier mountain SDF continues on the worker.
If the worker `ground_surface` result is not available at chunk publish time,
the streamer may apply a 1x1 constant `ground_surface` placeholder on the main
thread. That placeholder is a bounded presentation cache only and must never be
stored as the authoritative contour result.

### Terrain Classes

The first cutover handles these contour classes:

| Class | Logical source | Visual role | Collision role |
|---|---|---|---|
| `mountain_mass` | effective mountain wall/foot tiles with mountain flags, plus legacy blocked terrain after cutover | mountain top/face/outline contour | blocks movement inside the contour |
| `ground_surface` | walkable ground and dug terrain | base ground material under active cutover terrain; native constant result is allowed in the first cutover when no blocking ground contour is required | non-blocking |
| `water_surface` | lake shallow/deep terrain | shore boundary participant | uses existing water movement semantics unless a lake spec changes them |

Ground is not a blocking solid. In the first cutover, `ground_surface` may use a
constant native contour result as the base material plane so chunk readiness is
not held by a second heavy SDF pass. That constant result must still encode
`height_r16` as valid Godot `Image.FORMAT_RH` half-float data, not as arbitrary
filled bytes. Organic blocking shape, visible mountain occupancy, and movement
collision are owned by `mountain_mass`; later lake or ground-edge specs may
promote more ground-edge SDF detail without changing the movement owner.
In Iteration 07, only `mountain_mass` and `ground_surface` are active contour
result classes for chunk readiness. `water_surface` remains available for halo
classification and debug readback, but it is not an independent readiness gate
until a later lake cutover spec promotes it.

### Fixed Texture and Field Formats

Contour output formats are fixed for implementation and tests:

| Field | Format | Size | Encoding |
|---|---|---|---|
| `mask_rgba8` | RGBA8 | `chunk_px_w * chunk_px_h * 4` bytes | R = top coverage, G = face coverage, B = back coverage, A = occupancy coverage. All channels are `0..255` UNORM. |
| `height_r16` | R16 half-float little-endian | `chunk_px_w * chunk_px_h * 2` bytes | IEEE 754 binary16 stores normalized `0..1` surface height and is uploaded as Godot `Image.FORMAT_RH`. |
| `normal_rgba8` | RGBA8 | `chunk_px_w * chunk_px_h * 4` bytes | XYZ normal encoded as `(n * 0.5 + 0.5) * 255`, A = occupancy coverage. |
| `collision_sdf_f32` | Float32 little-endian | `collision_w * collision_h * 4` bytes | Signed distance in world pixels; inside blocking mountain mass is positive, outside is negative. |

The first implementation uses `collision_sample_px = 4`. Collision texture
size is:

```text
collision_w = ceil(chunk_pixel_width / collision_sample_px) + 1
collision_h = ceil(chunk_pixel_height / collision_sample_px) + 1
```

Collision sampling is bilinear over `collision_sdf_f32`. A movement sample is
blocked when:

```text
sampled_sdf_px >= recipe.collision.threshold_px
```

The initial threshold is `0.0`.

### Authoring Recipe

The generator must export a runtime recipe rather than only baked tile atlases.

Required recipe fields:

```text
{
  "schema": "station_peaceful.runtime_sdf_contour_recipe.v1",
  "asset_name": String,
  "preset": String,
  "tile_size_px": 64,
  "chunk_size_tiles": 16,
  "solid_class": "mountain_mass" | "ground_surface" | "water_surface",
  "geometry": {
    "south_height_px": float,
    "north_height_px": float,
    "side_height_px": float,
    "roughness_px": float,
    "edge_width_px": float,
    "face_power": float,
    "back_drop": float,
    "crown_bevel_px": float,
    "outer_corner_radius_px": float,
    "inner_corner_radius_px": float,
    "corner_round_px": float,
    "diagonal_smooth_px": float,
    "contour_relax": float,
    "contour_warp_px": float,
    "corner_variation": float,
    "rim_width_px": float,
    "outline_enabled": bool,
    "outline_width_px": float,
    "edge_debris": float,
    "edge_color_strength": float,
    "geometry_variance": float,
    "shape_supersampling": int
  },
  "materials": {
    "top_albedo": String,
    "face_albedo": String,
    "base_albedo": String,
    "top_modulation": String,
    "face_modulation": String,
    "top_normal": String,
    "face_normal": String,
    "texture_scale": float,
    "normal_strength": float,
    "normal_detail_strength": float
  },
  "collision": {
    "threshold": 0.0,
    "sampling_px": 4,
    "blocks_inside": bool
  },
  "determinism": {
    "seed": int,
    "variant_count": int
  }
}
```

The recipe is authored by the desktop generator, loaded by Godot as an asset,
and consumed by native runtime code through explicit fields. Runtime code must
not parse visual PNG names to infer geometry behavior.

### Native Contour Input

Native contour compute receives a compact chunk request:

```text
ContourChunkInputV1 {
  chunk_coord: Vector2i,
  world_seed: int,
  world_version: int,
  tile_size_px: int,
  render_tile_size_px?: int,
  chunk_size_tiles: int,
  halo_tiles: int,
  recipe_id: StringName,
  solid_mask_with_halo: PackedByteArray,
  contour_class_mask_with_halo: PackedByteArray,
  mountain_id_with_halo: PackedInt32Array,
  diff_revision: int
}
```

`solid_mask_with_halo` uses one byte per halo tile:

```text
0 = empty for this contour class
1 = solid / included for this contour class
```

`contour_class_mask_with_halo` uses one byte per halo tile:

```text
0 = none / outside world
1 = ground_surface
2 = mountain_mass
3 = water_surface
```

The halo is fixed to `2` tiles for Iterations 02-07. This covers the initial
SDF smoothing and diagonal shaping budget. Increasing halo size requires a spec
version bump because it changes streaming cost and seam behavior.

`tile_size_px` remains the logical SDF and collision coordinate scale. Runtime
may provide `render_tile_size_px` for a lower-resolution visual cache, provided
the result is scaled to the logical chunk size and collision buffers keep using
logical `tile_size_px` coordinates.

Halo data is not limited to already loaded neighbor chunks. `WorldStreamer`
must assemble halo input from:

1. loaded effective packet data when present
2. runtime diff overlays when present
3. on-demand native base chunk generation for unloaded neighbor cells

X reads wrap across world width. Y reads outside the world return empty class
and empty solid.

### Native Contour Result

Native contour compute returns:

```text
ContourChunkResultV1 {
  chunk_coord: Vector2i,
  recipe_id: StringName,
  diff_revision: int,
  pixel_size: Vector2i,
  mask_rgba8: PackedByteArray,
  height_r16: PackedByteArray,
  normal_rgba8: PackedByteArray,
  collision_sdf_f32: PackedByteArray,
  collision_origin_world_px: Vector2,
  collision_sample_px: int,
  collision_size: Vector2i,
  solid_bounds_world_px: Rect2,
  ready: bool
}
```

The result is a runtime cache. It is not written to save files and is not sent
through current save slot chunk JSON.

### Determinism and Parity Contract

Generator and runtime parity is tested through golden fixtures. Iteration 01
creates these reference assets:

```text
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/mountain_runtime_sdf_recipe.json
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/mountain_reference_mask.png
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/mountain_reference_height.png
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/mountain_reference_normal.png
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/mountain_reference_albedo.png
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/earth_runtime_sdf_recipe.json
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/earth_reference_mask.png
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/earth_reference_height.png
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/earth_reference_normal.png
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/earth_reference_albedo.png
```

The deterministic fixture map is `8 x 8` tiles:

```text
00000000
00111100
01111110
01101110
01111110
00111000
00010000
00000000
```

`1` means included in the active contour class. `0` means empty. The same mask,
seed, recipe, tile size, and material settings must produce byte-identical
generator output across repeated exports.

Native parity compares the native contour result to generator reference images:

- mask maximum per-channel absolute difference: `<= 2`
- height maximum absolute difference after binary16 decode: `<= 2` units
- normal maximum per-channel absolute difference: `<= 3`
- occupancy threshold classification at `alpha >= 128`: exact match
- collision sign at every `4 px` sample: exact match against reference
  occupancy/SDF threshold

Albedo visual parity is evaluated by screenshot/reference comparison after
shader integration. Because runtime lighting is dynamic, albedo references must
be unlit and normal-driven lighting is tested separately.

### Rendering Model

`ChunkView` gains contour rendering for terrain classes. The target rendering
shape is one contour visual resource per class per chunk:

- a chunk-sized mask texture with top/face/back/occupancy channels
- a chunk-sized normal texture
- a height texture or encoded height channel when needed by the shader
- material maps from the generator recipe
- world-space material sampling to avoid visible texture seams

Mountain cover remains a mask-driven concept, but the cover material samples
the contour mask instead of a 47-case TileMap atlas. If cover data and contour
data disagree, contour data wins for shape and cover only gates visibility.

### Collision Model

Movement blocking reads the contour collision field for loaded chunks:

```text
blocked = mountain_mass.collision_sdf(world_px) >= recipe.collision.threshold
walkable = base_walkable_at_tile(world_tile) and not blocked
```

The player footprint keeps multiple sample points, but each point samples the
continuous collision field. This preserves the current movement call shape while
removing square tile corners.

Collision readiness is part of chunk readiness. A chunk cannot be exposed as
movement-ready until its contour collision result is ready.

Movement and raw tile-grid queries are separate:

```text
WorldStreamer.is_walkable_at_world(world_pos: Vector2) -> bool
WorldStreamer.is_movement_blocked_at_world(world_pos: Vector2) -> bool
WorldStreamer.is_raw_tile_walkable_at_world(world_pos: Vector2) -> bool
WorldStreamer.get_effective_tile_data_at_world(world_pos: Vector2) -> Dictionary
```

`is_walkable_at_world()` is movement-facing and contour-aware.
`is_raw_tile_walkable_at_world()` and `get_effective_tile_data_at_world()` are
for building placement, mining, debug, and systems that intentionally need
logical tile truth.

### Excavation Dirty Updates

Excavation still writes one logical tile override into runtime diff. After the
diff write:

1. `WorldDiffStore` increments a monotonic `diff_revision`
2. the effective terrain state changes for that tile
3. the affected loaded chunk and direct seam-neighbor chunks are marked contour
   dirty
4. native contour compute refreshes the full affected chunk result for each
   dirty contour class
5. `ChunkView` swaps visual textures only when the result revision matches the
   chunk's required contour revision
6. movement queries read the refreshed collision revision

If the new collision revision is not ready yet, movement into the affected dirty
region is blocked until readiness catches up. Already-published chunks may keep
the previous visual revision visible during this dirty refresh to avoid
chunk-sized holes; the stale visual must not be treated as movement-ready and
must be atomically replaced with the matching visual/collision revision when it
arrives.

The global `WorldDiffStore.diff_revision` is a monotonic change id, not a
requirement that every loaded chunk rebuild after every diff. `WorldStreamer`
tracks a per-chunk required revision. Only chunks whose own tiles or bounded
halo can observe the changed tile are marked dirty for the new revision; already
ready unaffected chunks keep their previous ready revision valid.

Bounded immediate visual feedback is allowed through a chunk-local runtime
cutout mask for the mutated logical tile. This mask is presentation-only,
shader-smoothed in tile space with a rounded organic falloff to avoid a hard
square before the SDF refresh, and
must not make movement ready. The authoritative visual/collision contour still
arrives through the full affected chunk worker refresh and revision swap.

Mountain outline coverage is derived from the same SDF field as occupancy. It
must not use vertical pixel-probe expansion, because that reintroduces
chunk/tile-corner brackets on diagonal silhouettes.

## File Ownership Plan

Generator:

- `tools/rimworld-autotile-lab/desktop_app/core/src/model.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/sdf.rs`
- `tools/rimworld-autotile-lab/desktop_app/shell/app.py`
- `tools/rimworld-autotile-lab/desktop_app/shell/presets.py`
- generator tests under `tools/rimworld-autotile-lab/desktop_app/tests`

Native runtime:

- `gdextension/src/world_core.cpp`
- `gdextension/src/mountain_contour.h`
- `gdextension/src/mountain_contour.cpp`
- new `gdextension/src/world_contour_field.h`
- new `gdextension/src/world_contour_field.cpp`
- new `gdextension/src/world_contour_recipe.h`
- new `gdextension/src/world_contour_recipe.cpp`
- Godot smoke tests under `tools/runtime_sdf_contour_*_smoke_test.gd`

Godot runtime:

- `core/systems/world/world_streamer.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_tile_set_factory.gd` only for removing
  ground/mountain TileMap presentation ownership after cutover
- `core/entities/player/player.gd` only if the movement call site must change
  from walkability to contour-aware walkability

Assets and resources:

- `data/terrain/contour_recipes/*.json`
- `data/terrain/presentation_profiles/*.tres`
- `data/terrain/shader_families/*.tres`
- `assets/shaders/contour_ground_material.gdshader`
- `assets/shaders/contour_mountain_material.gdshader`
- `assets/textures/terrain/*`

Docs:

- this spec
- the iteration briefs linked in this spec
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/README.md`
- `docs/02_system_specs/README.md`

## API Changes

Add native APIs:

```text
WorldCore.build_contour_chunk(input: Dictionary) -> Dictionary
```

`WorldCore.build_contour_chunk()` is the only native API required for the first
runtime cutover. Collision sampling happens in `WorldStreamer` from cached
`collision_sdf_f32` data so movement does not cross the GDExtension boundary per
sample.

Add runtime reads:

```text
WorldStreamer.is_movement_blocked_at_world(world_pos: Vector2) -> bool
WorldStreamer.is_walkable_at_world(world_pos: Vector2) -> bool
WorldStreamer.is_raw_tile_walkable_at_world(world_pos: Vector2) -> bool
WorldStreamer.get_effective_tile_data_at_world(world_pos: Vector2) -> Dictionary
```

`is_walkable_at_world()` becomes contour-aware. Existing callers that ask about
movement keep using it. Building placement, mining, debug tools, and systems
that need logical tile truth must use `is_raw_tile_walkable_at_world()` or
`get_effective_tile_data_at_world()`.

## Versioning

Contour caches do not require save migration because they are derived.

`WORLD_VERSION` changes only if base worldgen terrain ids, mountain flags,
walkable flags, or generated mountain identity change. The cutover changes
movement collision semantics, so the system API and test fixtures must update
even when save data stays unchanged.

## Performance Budget

Native contour compute must satisfy:

- no whole-world scan
- no GDScript pixel loops
- no per-pixel main-thread work
- no per-tile C++ calls from GDScript
- one compact native call per contour request
- result apply sliced through the existing streaming frame budget
- collision sampling O(1) per movement sample
- local excavation refresh bounded to affected chunks and halo

## Acceptance Criteria

The work is complete when:

- generator exports a runtime SDF contour recipe and parity reference images
- native runtime can generate the same mask semantics from chunk masks and the
  recipe
- ground and mountains no longer render through `autotile_47` TileMap cells
  after cutover
- mountain bottom outline, face/top split, rim, and organic silhouette are
  visible in game
- ground edges, dug cuts, mountain contact edges, and shore participants use the
  same contour language
- movement collision samples the contour field and matches the visible mountain
  occupancy boundary
- excavation updates visual contour and collision without full world refresh
- chunk readiness includes contour visual and collision readiness
- visual parity tests compare generator references to in-game output
- collision tests sample near contour edges and prove there are no square
  blocking corners

## Implementation Iterations

1. [Generator Runtime SDF Recipe Export](runtime_sdf_contours_iteration_01_generator_recipe_export.md)
2. [Native Contour Field](runtime_sdf_contours_iteration_02_native_contour_field.md)
3. [Runtime Contour Streaming Packets](runtime_sdf_contours_iteration_03_streaming_packets.md)
4. [Chunk Contour Rendering](runtime_sdf_contours_iteration_04_chunk_rendering.md)
5. [Contour Collision Queries](runtime_sdf_contours_iteration_05_collision_queries.md)
6. [Excavation Dirty Contour Updates](runtime_sdf_contours_iteration_06_excavation_dirty_updates.md)
7. [Ground and Mountain Cutover Validation](runtime_sdf_contours_iteration_07_cutover_validation.md)
