---
title: Runtime SDF Contours - Iteration 02 Native Contour Field
doc_type: iteration_brief
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-05-12
related_docs:
  - runtime_sdf_terrain_contours.md
  - world_runtime.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
---

# Runtime SDF Contours - Iteration 02 Native Contour Field

## Goal

Implement the native SDF contour compute core that turns a chunk solid mask plus
halo into visual masks, height, normals, and collision samples using an exported
runtime contour recipe.

## Non-Goals

- no `ChunkView` rendering
- no player movement change
- no excavation dirty integration
- no TileMap atlas generation
- no GDScript implementation of pixel or distance-field loops

## Runtime Classification

- authoritative state: none
- derived state: `ContourChunkResultV1`
- runtime work class: native worker compute
- dirty unit: one chunk plus recipe-required halo

## Allowed Files

- `gdextension/src/world_core.cpp`
- `gdextension/src/world_core.h`
- `gdextension/src/mountain_contour.h`
- `gdextension/src/mountain_contour.cpp`
- new `gdextension/src/world_contour_recipe.h`
- new `gdextension/src/world_contour_recipe.cpp`
- new `gdextension/src/world_contour_field.h`
- new `gdextension/src/world_contour_field.cpp`
- new `tools/runtime_sdf_contour_field_smoke_test.gd`
- `docs/02_system_specs/meta/system_api.md`
- `docs/02_system_specs/meta/packet_schemas.md`

## Forbidden Boundaries

- no Godot scene rendering changes
- no player movement changes
- no save/load changes
- no generator process calls from runtime

## Implementation Shape

1. Define `ContourRecipeV1` in native code with explicit typed fields matching
   the recipe JSON.
2. Define `ContourChunkInputV1` and `ContourChunkResultV1` native structs.
3. Move the existing debug-only marching-squares helper in
   `mountain_contour.cpp` behind an explicit debug namespace or keep it as
   `mountain_contour::build_debug_mesh`; do not reuse it as the runtime SDF
   implementation.
4. Implement signed-distance computation over a halo mask with inside positive
   and outside negative.
5. Port the generator preview shaping functions from
   `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs` and
   `tools/rimworld-autotile-lab/desktop_app/core/src/sdf.rs`, specifically the
   logic equivalent to `MapSdf::compute_with_padding()`,
   `render_tile_with_sdf()`, `controlled_sdf_distance_px()`,
   `sample_global_height_with_sampler()`, and
   `apply_mountain_bottom_outline_for_field()`.
6. Produce mask channels with the same meaning as the generator:
   top in red, face in green, back in blue, occupancy in alpha.
7. Produce fixed-format outputs:
   `mask_rgba8`, `height_r16`, `normal_rgba8`, `collision_sdf_f32`,
   `collision_size`, and `collision_sample_px`.
8. Produce collision samples from the same occupancy/SDF threshold.
9. Respect cylindrical X wrapping at input assembly boundaries and keep Y
   outside-world samples empty.
10. Expose `WorldCore.build_contour_chunk(input: Dictionary) -> Dictionary`
    for tests and later
   streaming integration.
11. Add deterministic tests using the Iteration 01 fixed masks and fixed
    recipes.

## Required Tests and Commands

Build native extension:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful\gdextension"
scons platform=windows target=template_debug
```

Run Godot smoke test:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful"
godot --headless --path . --script res://tools/runtime_sdf_contour_field_smoke_test.gd
```

The smoke test must instantiate `WorldCore`, call `build_contour_chunk()` with
the Iteration 01 fixture mask and recipe, and assert:

- result has `mask_rgba8`, `height_r16`, `normal_rgba8`, `collision_sdf_f32`
- mask byte length is `1024 * 1024 * 4` for one `16 x 16` chunk at `64 px`
- height byte length is `1024 * 1024 * 2`
- normal byte length is `1024 * 1024 * 4`
- collision size is `257 x 257` at `collision_sample_px = 4`
- repeated calls return identical hashes

## Smoke Tests

- empty mask produces empty occupancy and no blocking samples
- full mask produces full occupancy and blocking samples inside the chunk
- single solid island produces rounded occupancy when corner smoothing is active
- diagonal contact respects `diagonal_smooth_px`
- output is deterministic for same input and recipe
- result size matches `chunk_size_tiles * tile_size_px`
- output channel names and byte lengths match `runtime_sdf_terrain_contours.md`

## Definition of Done

- native code can build `ContourChunkResultV1` without GDScript pixel loops
- result masks use generator-compatible channel semantics
- tests prove deterministic output and basic SDF behavior
- `system_api.md` records the new native contour build contract
- `packet_schemas.md` records the derived result dictionary shape
