---
title: Lake Generation V2 — Overview and Iteration Plan
doc_type: iteration_overview
status: ready
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-05-03
spec: docs/02_system_specs/world/lake_generation.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_foundation_v1.md
  - ../02_system_specs/world/mountain_generation.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - lake_generation_L1_substrate_basin_solve.md
  - lake_generation_L2_bed_terrain_packet.md
  - lake_generation_L3_water_presentation_layer.md
  - lake_generation_L4_settings_ui_persistence_spawn.md
---

# Lake Generation V2 — Overview and Iteration Plan

## Why V2

V1 (`L1..L4`) shipped lakes that look correct inside their own coarse cells
but exhibit two visible problems on the new-game preview and in-game:

1. **Hard 64-tile clipping at coarse-cell boundaries.** Per-tile lake
   classification only fires for tiles whose own coarse cell has
   `lake_id > 0` (`gdextension/src/world_core.cpp:955-1016`). Tiles in
   neighbouring coarse cells with low `foundation_height` never become
   water even when the rim height is above them, producing rectangular
   tile-aligned cuts on the lake border. Inside a basin cell shorelines
   look organic; outside they snap to the 64-tile grid.
2. **Lakes cannot grow large.** `derive_basin_shape` clamps
   `max_basin_cells` at `256` and the mapping rolls off at
   `scale ≈ 1024`, so the `Масштаб озёр` slider stops doing anything
   past that point. There is also no analogue of the mountain
   `Связность хребтов` (continuity) parameter, so V1 cannot produce
   large connected lake systems.

V2 fixes both classes of problem additively, in three iterations, on
top of the V1 surface.

## V2 design summary

V2 is an additive amendment of `lake_generation.md`. It does **not**
introduce new substrate fields beyond the existing
`lake_id` / `lake_water_level_q16`. It does **not** change the
`ChunkPacketV1` field set (still adds only `lake_flags`). It changes:

- `BasinShape` mapping (uncap large basins, give small basins more
  cells)
- a deterministic basin-merge pass driven by a new `connectivity`
  setting, so neighbouring closed basins with similar rim heights
  share one `lake_id`
- per-tile lake classification reads the local **3×3 neighbourhood of
  coarse cells**, not just the tile's own cell, so water can extend
  organically across coarse-cell boundaries
- shoreline FBM amplitude is interpreted as a fraction of basin depth
  (`amplitude * (water_level - basin_min_elevation)`) instead of an
  absolute `foundation_height` number, so the same value behaves
  consistently on small and large basins
- `LakeGenSettings` gains one new field `connectivity`
  (`settings_packed[21]`), default `0.4`, range `[0.0, 1.0]`
- new-game UI gains one new slider `UI_WORLDGEN_LAKES_CONNECTIVITY`
  mirroring the mountain continuity slider, persisted via
  `worldgen_settings.lakes` exactly like the existing fields
- `WORLD_VERSION` advances from `39` to `42` across L5/L6/L7 because
  each iteration changes canonical output for the same `(seed, settings)`
- spawn rejection is broadened to consider the same 3×3 neighbourhood
  used by per-tile water classification, so the spawn resolver does
  not place the player on tiles that turn out to be water on
  publish

## Out of scope (V2)

- new substrate fields beyond `lake_id` / `lake_water_level_q16`
- rivers, hydrology, drying, swimming, water as a resource
- new presentation profiles or shaders
- migration of pre-V2 saves (active pre-alpha policy rejects
  non-current `world_version`)
- modding hooks beyond the existing extension seams

## Iteration plan

V2 ships as three sequential iterations. Land them strictly in order;
each closes its own acceptance gate before the next opens.

### `L5 — Basin size mapping and lake connectivity`

File: `docs/04_spec_iteration/lake_generation_L5_basin_size_and_connectivity.md`

- amend `lake_generation.md` ("Lake Basin Solve" + "Worldgen Settings"
  sections) and bump `WORLD_VERSION` 39 → 40
- raise the `max_basin_cells` clamp to allow real large basins
- expose `connectivity` in `LakeGenSettings` and `settings_packed[21]`
- run a deterministic basin-merge pass after BFS so basins that touch
  with similar rim heights share one `lake_id`

After L5, large lake **substrate** is possible but per-tile water
still snaps to coarse-cell boundaries.

### `L6 — Per-tile cross-cell shoreline`

File: `docs/04_spec_iteration/lake_generation_L6_cross_cell_shoreline.md`

- amend `lake_generation.md` "Per-Tile Classification" section
- read `lake_id` / `lake_water_level_q16` from the **3×3 neighbourhood
  of coarse cells** around each tile, choose a deterministic
  best-applicable lake, then run the existing shore-warp test
- broaden spawn rejection to use the same 3×3 lookup
- bump `WORLD_VERSION` 40 → 41

After L6, lake outlines look organic across coarse-cell boundaries
and the visible "chunk clipping" artefact is gone.

### `L7 — Shore-warp normalisation and UI`

File: `docs/04_spec_iteration/lake_generation_L7_shore_warp_normalization_and_ui.md`

- amend `lake_generation.md` "Per-Tile Classification" formula:
  shoreline FBM amplitude is `amplitude * basin_depth`
- update default `shore_warp_amplitude` to `0.4` (was `0.8`) under the
  new semantics; range becomes `[0.0, 1.0]`
- add the `UI_WORLDGEN_LAKES_CONNECTIVITY` slider to the new-game
  panel, with locale strings in `locale/ru/messages.po` and
  `locale/en/messages.po`
- update `world.json` shape and persistence to include
  `connectivity`
- bump `WORLD_VERSION` 41 → 42

After L7, the player can dial `connectivity` from the UI, the
default look is balanced across small and large basins, and the
canonical persistence shape is final.

## Hard rules common to all V2 iterations

- one task = one iteration; do not start L6 before L5 closure is
  accepted, or L7 before L6
- each iteration must update `lake_generation.md` in the same task as
  the code change (no silent doc drift, per `WORKFLOW.md`)
- each iteration must record the new `WORLD_VERSION` in
  `docs/02_system_specs/meta/save_and_persistence.md` and
  `docs/02_system_specs/meta/packet_schemas.md`
- no GDScript fallback for any lake compute is allowed (LAW 9)
- no new substrate field is allowed; the frozen-set extension from L1
  remains the only addition
- no change to `ChunkDiffV0` shape; persisted lake-bed dig overrides
  remain `(local_x, local_y, terrain_id, walkable)` rows

## Required reading before any V2 iteration

1. `AGENTS.md`
2. `docs/00_governance/WORKFLOW.md`
3. `docs/00_governance/ENGINEERING_STANDARDS.md`
4. `docs/00_governance/PROJECT_GLOSSARY.md`
5. `docs/02_system_specs/world/lake_generation.md`
6. `docs/02_system_specs/world/world_foundation_v1.md`
7. `docs/02_system_specs/world/mountain_generation.md` (template for
   the connectivity / continuity pattern)
8. `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
9. closure reports of L1..L4 if they exist in the repo

Code reading is bounded by the iteration brief that is currently
being executed. Do not pre-read code from later iterations.
