---
title: Runtime SDF Contours - Iteration 01 Generator Recipe Export
doc_type: iteration_brief
status: draft
owner: engineering+art
source_of_truth: false
version: 0.1
last_updated: 2026-05-12
related_docs:
  - runtime_sdf_terrain_contours.md
  - terrain_hybrid_presentation.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Runtime SDF Contours - Iteration 01 Generator Recipe Export

## Goal

Teach the desktop autotile generator to export the same SDF contour contract
that its live map preview uses, so runtime implementation has a precise recipe
and reference images instead of reverse-engineering preview behavior from tile
atlases.

## Non-Goals

- no game runtime integration
- no `autotile_47` atlas compatibility work
- no native Godot collision generation
- no save/load changes
- no fallback export path for the target runtime contour feature

## Runtime Classification

- authoritative state: none
- derived state: authored contour recipe and reference images
- runtime work class: offline authoring
- dirty unit: one exported asset package

## Required Output

For each contour asset, the generator writes:

```text
<asset>_runtime_sdf_recipe.json
<asset>_reference_mask.png
<asset>_reference_height.png
<asset>_reference_normal.png
<asset>_reference_albedo.png
<asset>_top_albedo.png
<asset>_face_albedo.png
<asset>_base_albedo.png
<asset>_top_modulation.png
<asset>_face_modulation.png
<asset>_top_normal.png
<asset>_face_normal.png
```

Reference images are generated from the global SDF map-preview path, not from
per-cell marching-squares atlas rendering.

## Deterministic Reference Fixture

This iteration creates a committed reference fixture under:

```text
tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/
```

The fixture map is exactly `8 x 8` tiles:

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

The fixture uses:

```text
tile_size_px = 64
chunk_size_tiles = 16
seed = 13371337
forced_variant = 0
shape_supersampling = 4
preview_mode = "normal"
bake_height_shading = false
```

The `mountain` fixture exports `solid_class = "mountain_mass"`.
The `earth` fixture exports `solid_class = "ground_surface"`.

## Allowed Files

- `tools/rimworld-autotile-lab/desktop_app/core/src/model.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/render.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/sdf.rs`
- `tools/rimworld-autotile-lab/desktop_app/core/src/main.rs`
- `tools/rimworld-autotile-lab/desktop_app/shell/app.py`
- `tools/rimworld-autotile-lab/desktop_app/shell/presets.py`
- `tools/rimworld-autotile-lab/desktop_app/README.md`
- `tools/rimworld-autotile-lab/desktop_app/tests/*`

## Forbidden Boundaries

- no changes to game runtime files
- no new Godot resources in this iteration
- no change to current save format
- no reliance on generator process at runtime

## Implementation Shape

1. Add an export mode named `RuntimeSdfContour`.
2. Serialize the recipe fields defined in
   `runtime_sdf_terrain_contours.md#authoring-recipe`.
3. Reuse the live preview SDF path to build reference mask, height, normal, and
   albedo images for a deterministic test map.
4. Keep exported albedo unlit. Runtime lighting uses normals and game lighting.
5. Export material maps as standalone files named by the recipe.
6. Include `solid_class`, `tile_size_px`, `chunk_size_tiles`,
   `collision.threshold`, `collision.sampling_px`, and determinism fields in
   the recipe.
7. Add tests that run the export twice with the same seed and assert identical
   recipe JSON and identical image hashes.
8. Add a test that proves `RuntimeSdfContour` reference images do not use the
   16-case `canonical_signatures()` atlas path.

## Required Tests and Commands

Rust core tests:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful\tools\rimworld-autotile-lab\desktop_app\core"
cargo test
```

Python shell tests:

```powershell
cd "C:\Users\peaceful\Station Peaceful\Station Peaceful\tools\rimworld-autotile-lab\desktop_app\shell"
python -m unittest discover -s tests
```

Required new Rust tests live in `core/src/render.rs`:

- `runtime_sdf_contour_export_writes_recipe_and_reference_images`
- `runtime_sdf_contour_export_is_deterministic`
- `runtime_sdf_contour_export_uses_map_sdf_path_not_canonical_signatures`

Required new Python shell test lives in
`shell/tests/test_app_payload.py`:

- `test_runtime_sdf_contour_export_mode_is_sent_to_core`

## Smoke Tests

- generator shell can select `RuntimeSdfContour`
- `mountain` preset exports a runtime recipe with outline enabled
- `earth` preset exports a runtime recipe with outline disabled
- exported reference dimensions match the selected map preview dimensions
- deterministic export hash is stable across two runs
- output images for the fixture are `512 x 512` pixels
- recipe JSON contains `schema`,
  `station_peaceful.runtime_sdf_contour_recipe.v1`, `solid_class`,
  `collision.threshold_px`, and `collision.sampling_px`

## Definition of Done

- runtime SDF recipe JSON exists and contains all required fields
- reference images come from the same SDF path as the live preview
- generator docs state that `RuntimeSdfContour` is the target game export
- all required Rust and Python tests pass with the commands above
- no runtime code consumes the files yet
