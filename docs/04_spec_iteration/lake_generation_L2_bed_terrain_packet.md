---
title: Lake Generation L2 — Bed Terrain IDs and `lake_flags` Packet Field
doc_type: iteration_brief
status: ready
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-05-02
spec: docs/02_system_specs/world/lake_generation.md
depends_on:
  - lake_generation_L1_substrate_basin_solve.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_runtime.md
  - ../02_system_specs/world/mountain_generation.md
  - ../02_system_specs/world/terrain_hybrid_presentation.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Lake Generation L2 — Bed Terrain IDs and `lake_flags` Packet Field

## Required reading before you start

1. `AGENTS.md`
2. `docs/00_governance/WORKFLOW.md`
3. `docs/00_governance/ENGINEERING_STANDARDS.md`
4. `docs/00_governance/PROJECT_GLOSSARY.md`
5. `docs/02_system_specs/world/lake_generation.md`
6. The closure report of the L1 iteration (substrate basin solve must
   be in)
7. `docs/02_system_specs/world/world_runtime.md` (chunk packet
   boundary, mutation path, `chunk_manager` compatibility surface)
8. `docs/02_system_specs/world/mountain_generation.md` (per-tile
   classification template)
9. `docs/02_system_specs/world/terrain_hybrid_presentation.md`
   (presentation profile contract for new terrain ids)
10. `docs/05_adrs/0003-immutable-base-plus-runtime-diff.md`

## Goal

Wire lake bed terrain into the chunk packet pipeline. After this
iteration, generated chunks contain `TERRAIN_LAKE_BED_SHALLOW` and
`TERRAIN_LAKE_BED_DEEP` cells, plus an additive `lake_flags` packet
field with the `is_water_present` bit. `WORLD_VERSION` bumps from `37`
to `38` because canonical packet output changes.

The bed tiles are visible on the existing base layer and on the
new-game overview. The water presentation layer is **not** part of
this iteration; that is L3.

## Context

L1 added `lake_id` and `lake_water_level_q16` substrate fields. L2 reads
them inside `WorldCore::_generate_chunk_packet`, computes per-tile
classification (mountain wins → shore land → shallow → deep), writes
the resolved `terrain_id`, `walkable_flags`, `terrain_atlas_indices`,
and `lake_flags`.

Save shape is unchanged. The dug-bed override flow uses the existing
plains-dig path; only the input terrain id changes.

## Boundary contract check

- Existing safe paths to use:
  - `WorldCore::_generate_chunk_packet` is the only place that writes
    `terrain_ids` / `walkable_flags` / `terrain_atlas_indices`
  - `WorldPrePass::Snapshot` (extended in L1) is the only source for
    `lake_id` / `lake_water_level_q16`
  - `MountainField::Evaluator::sample_elevation` already runs per tile;
    reuse its result rather than re-sampling
  - `terrain_presentation_registry.gd` is the registration seam for new
    terrain ids
  - `world_foundation_palette.gd` and native `write_overview_rgba` are
    the seams for adding bed-class colours to the overview
- Canonical docs to update in this task:
  - `docs/02_system_specs/meta/packet_schemas.md` — `ChunkPacketV1`
    extension with `lake_flags`
  - `docs/02_system_specs/meta/save_and_persistence.md` —
    `WORLD_VERSION = 38` boundary entry
- New public API / event / command: none. Packet boundary stays the
  same; only one new additive field appears.

## Performance / scalability guardrails

- Runtime class: `background` (native worker), one packet per chunk
- Target scale / density: a `large` preset has on order of `131072`
  chunks at full coverage; chunk packet generation must not regress
  median latency by more than `1 ms` on reference hardware
- Source of truth + write owner: `WorldCore` (native)
- Dirty unit: `32 x 32` chunk for canonical packet, one tile for
  excavation mutation
- Escalation path: if the per-tile FBM-warp call dominates cost,
  collapse it to a single-octave deterministic hash-noise; do not
  drop the warp entirely (it is required for organic shorelines)

## Scope — what to do

1. Add `TERRAIN_LAKE_BED_SHALLOW = 5` and `TERRAIN_LAKE_BED_DEEP = 6`
   constants in `core/systems/world/world_runtime_constants.gd` and
   mirror in `gdextension/src/world_core.cpp` (the existing
   anonymous-enum or `static constexpr` block at the top of the file).
2. Bump `WorldRuntimeConstants.WORLD_VERSION` from `37` to `38`.
3. Extend `gdextension/src/world_core.cpp` `_generate_chunk_packet`:
   - allocate `lake_flags` `PackedByteArray` of length `1024`
   - per tile, after mountain resolution, run the per-tile lake
     classification documented in the spec ("Per-Tile Classification"
     section), reusing the already-sampled `tile_elevation`
   - emit `LAKE_BED_SHALLOW` / `LAKE_BED_DEEP` `terrain_id`,
     corresponding `walkable` byte, and `is_water_present` bit
   - resolve `terrain_atlas_indices` using `autotile_47` against
     same-class neighbours (one autotile call per bed class group)
4. Extend `gdextension/src/lake_field.h` / `lake_field.cpp` (added in
   L1) with:
   - `fbm_shore(wx, wy, seed, world_version, scale, amplitude)`
     deterministic 2-octave FBM with salt distinct from mountain noise
   - per-`lake_id` cached `basin_min_elevation` lookup helper, built
     once when the substrate is built and read O(1) from the chunk
     packet loop
5. Extend the chunk packet result in `world_core.cpp`:
   - the existing `Dictionary` returned per coord gains one key
     `"lake_flags"` of type `PackedByteArray`
6. Update `core/systems/world/world_chunk_packet_backend.gd` (or
   wherever the GDScript side reads packet keys) to forward the new
   `lake_flags` array to `ChunkView` on publish, even though the water
   layer itself is not yet implemented (write to a stored buffer; L3
   will consume it).
7. Register presentation profiles for the bed terrain ids:
   - new resources `data/terrain/shape_sets/lake_bed_shallow.tres`
     and `lake_bed_deep.tres` (use the existing `autotile_47` shape
     family)
   - new `material_sets/lake_bed_shallow.tres` /
     `lake_bed_deep.tres` (placeholder textures are acceptable; the
     contract is that the registry recognises them)
   - new `presentation_profiles/lake_bed_shallow.tres` /
     `lake_bed_deep.tres` linking shape + material to the new terrain
     ids
   - update `terrain_presentation_registry.gd` validation list to
     accept ids `5` and `6`
8. Extend overview palette:
   - in `world_foundation_palette.gd`, add `COLOR_LAKE_BED_SHALLOW`
     (light blue, e.g. `(120, 168, 196)`) and `COLOR_LAKE_BED_DEEP`
     (dark blue, e.g. `(48, 84, 124)`)
   - in `gdextension/src/world_prepass.cpp` `write_overview_rgba`,
     extend `OverviewTerrainSampler` and the per-pixel terrain class
     resolution so that lake-bed pixels get the corresponding colour
     before water presentation lands in L3
9. Update the chunk diff path:
   - `WorldDiffStore` must continue to persist only
     `(local_x, local_y, terrain_id, walkable)`
   - confirm via static read that no diff payload writes `lake_flags`
10. Update canonical docs in the same task:
    - `docs/02_system_specs/meta/packet_schemas.md`: `ChunkPacketV1`
      table extended with `lake_flags`; current `world_version` value
      bumped to `38`; bit layout block added for `lake_flags`
    - `docs/02_system_specs/meta/save_and_persistence.md`: add
      `world_version = 38` boundary line documenting the lake-stack
      addition; record that the `worldgen_settings.lakes` field is
      planned for L4 and not yet required
    - `docs/02_system_specs/world/lake_generation.md`: status note
      ("L2 landed") and update `WORLD_VERSION` line if needed

## Scope — what NOT to do

- do not introduce `ChunkView.water_layer`, water atlas, or any water
  presentation resource (L3)
- do not write `worldgen_settings.lakes` to `world.json` (L4)
- do not add the spawn rejection rule (L4)
- do not add new-game UI sliders (L4)
- do not write `lake_flags` into chunk diff files
- do not introduce new `EventBus` signals
- do not change `ChunkDiffV0` shape
- do not modify `MountainGenSettings`, `FoundationGenSettings`, or any
  unrelated worldgen owner
- do not change mountain field internals
- do not migrate `world_version <= 37` saves; pre-alpha policy rejects
  them

## Files that may be touched

### New
- `data/terrain/shape_sets/lake_bed_shallow.tres`
- `data/terrain/shape_sets/lake_bed_deep.tres`
- `data/terrain/material_sets/lake_bed_shallow.tres`
- `data/terrain/material_sets/lake_bed_deep.tres`
- `data/terrain/presentation_profiles/lake_bed_shallow.tres`
- `data/terrain/presentation_profiles/lake_bed_deep.tres`

### Modified
- `gdextension/src/lake_field.h`
- `gdextension/src/lake_field.cpp`
- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_prepass.cpp` (overview palette extension)
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `core/systems/world/world_foundation_palette.gd`
- `core/systems/world/chunk_view.gd` (only to receive the
  `lake_flags` buffer for L3; no water rendering yet)
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`

## Files that must NOT be touched

- `core/systems/world/world_diff_store.gd` (diff shape unchanged)
- `core/autoloads/save_collectors.gd`, `save_appliers.gd`, `save_io.gd`
- `gdextension/src/mountain_field.{h,cpp}` internals
- `gdextension/src/world_prepass.h` snapshot struct (substrate fields
  themselves are L1-frozen by the time L2 starts)
- `scenes/ui/new_game_panel.gd`
- `core/entities/player/player.gd`
- `core/systems/building/*`, combat, fauna, lore, UI flows unrelated
  to the new-game overview

## Acceptance tests

- [ ] Static: `WorldRuntimeConstants.WORLD_VERSION` equals `38`.
- [ ] Static: `TERRAIN_LAKE_BED_SHALLOW = 5` and
      `TERRAIN_LAKE_BED_DEEP = 6` are defined in both GDScript
      constants and native enum.
- [ ] Static: `ChunkPacketV1` documentation in
      `packet_schemas.md` lists `lake_flags` with bit-0 semantics.
- [ ] Static: `terrain_presentation_registry.gd` validation accepts
      ids `5` and `6` and links them to new shape/material/presentation
      profile resources.
- [ ] Static: chunk diff payload does not include any `lake_*` key
      (grep `chunks/<x>_<y>` and `WorldDiffStore.serialize_dirty_chunks`
      to prove).
- [ ] Determinism: for a fixed seed and `lake_density > 0`, two builds
      produce identical `terrain_ids`, `walkable_flags`, `lake_flags`
      arrays. Manual human verification acceptable; record the seed.
- [ ] Mountain wins: for any tile with `mountain_id > 0`, lake
      classification leaves it as `MOUNTAIN_WALL` / `MOUNTAIN_FOOT`.
      Add a debug assertion in `_generate_chunk_packet` (compiled in
      dev only) that fails if this invariant breaks.
- [ ] Spec acceptance: `walkable_flags` for `LAKE_BED_SHALLOW` is `1`,
      for `LAKE_BED_DEEP` is `0`.
- [ ] No regression at zero density: with `lake_density = 0.0`,
      `terrain_ids` / `walkable_flags` are identical to the pre-L2
      build for a fixed seed (manual or scripted).
- [ ] Overview: new-game overview shows lake patches in light/dark blue
      (manual human verification; record screenshot path or seed).
- [ ] Performance: chunk packet generation median latency on a
      reference seed grows by `≤ 1 ms` over the L1 baseline (manual
      human verification acceptable; record numbers).
- [ ] Canonical doc check (grep): `lake_flags`, `WORLD_VERSION`,
      `TERRAIN_LAKE_BED_SHALLOW`, `TERRAIN_LAKE_BED_DEEP` each appear
      in the updated `packet_schemas.md` and
      `save_and_persistence.md` with line numbers in the closure
      report.

## Result format

Closure report per `WORKFLOW.md`. `not required` for any canonical doc
must be backed by grep evidence.
