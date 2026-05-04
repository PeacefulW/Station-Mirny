---
title: Lake Generation L6 — Per-Tile Cross-Cell Shoreline
doc_type: iteration_brief
status: ready
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-05-03
spec: docs/02_system_specs/world/lake_generation.md
depends_on:
  - lake_generation_v2_overview.md
  - lake_generation_L5_basin_size_and_connectivity.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_foundation_v1.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Lake Generation L6 — Per-Tile Cross-Cell Shoreline

## Required reading before you start

1. `AGENTS.md`
2. `docs/00_governance/WORKFLOW.md`
3. `docs/00_governance/ENGINEERING_STANDARDS.md`
4. `docs/00_governance/PROJECT_GLOSSARY.md`
5. `docs/04_spec_iteration/lake_generation_v2_overview.md`
6. `docs/04_spec_iteration/lake_generation_L5_basin_size_and_connectivity.md`
   closure report (L5 must be fully closed)
7. `docs/02_system_specs/world/lake_generation.md` (this iteration
   amends it again, on top of L5)
8. `docs/02_system_specs/world/world_foundation_v1.md` — Spawn
   Contract section (this iteration broadens spawn rejection)
9. `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`

## Goal

Eliminate the visible 64-tile clipping at coarse-cell boundaries by
making per-tile lake classification look at the **3×3 neighbourhood
of coarse cells** around each tile, not just the tile's own cell.

After L6, water can extend organically across coarse-cell borders
wherever `bilinear(foundation_height) + shore_warp < water_level`,
and the rectangular tile-aligned cuts visible in the 2026-05-03
new-game preview disappear.

This iteration **does not** change the substrate solve, the
`ChunkPacketV1` field set, presentation, the UI, or the shoreline FBM
amplitude semantics. L7 owns the shoreline-FBM rescaling and UI
work.

## Context

`gdextension/src/world_core.cpp:955-1016` decides per-tile
"is this water?" only when the tile's own coarse cell satisfies
`lake_id > 0`. Tiles in adjacent coarse cells with low
`bilinear(foundation_height)` are skipped, even though physically
the water surface defined by `lake_water_level_q16` would flood
them. This is the root cause of the rectangular cuts the player
reports.

Spawn rejection in `WorldCore::resolve_world_foundation_spawn_tile`
mirrors the same per-coarse-cell check; once per-tile water grows
into adjacent cells, the spawn check must follow or the player can
spawn on a tile that becomes water on publish.

V2 design summary in `lake_generation_v2_overview.md` is normative.

## Boundary contract check

- Existing safe path to use:
  - per-tile lake branch in `WorldCore::_generate_chunk_packet`
    (around `world_core.cpp:955-1016`) is the only seam where the
    new 3×3 lookup runs
  - `lake_field::resolve_basin_min_elevation` is reused unchanged
- Canonical docs to check before code:
  - `docs/02_system_specs/world/lake_generation.md` "Per-Tile
    Classification" must be amended in this task
  - `docs/02_system_specs/world/world_foundation_v1.md` "Spawn
    Contract" must be amended in this task
  - `docs/02_system_specs/meta/packet_schemas.md` — note new
    `WORLD_VERSION = 41` packet boundary; same field shape, the
    canonical contents change
  - `docs/02_system_specs/meta/save_and_persistence.md` — note
    `WORLD_VERSION = 41`
- New public API / event / schema / command: none.

## Performance / scalability guardrails

- Runtime class: `background` (chunk-packet generation worker)
- Target scale / density: median chunk packet generation must not
  grow more than `≤ 1.0 ms` on reference hardware compared to
  pre-L6; the 3×3 lookup adds at most 8 extra coarse-cell reads per
  non-mountain tile (cap is `8 * 32 * 32 = 8192` reads per chunk,
  bounded)
- Source of truth + write owner: `WorldCore` (native), per the spec
- Dirty unit: one `32×32` chunk packet
- Escalation path: if budget breaks, cache the 3×3 lookup once per
  chunk into a small `(8 + chunk_side) × (8 + chunk_side)` scratch
  array of `(lake_id, water_level_q16)` keyed off the chunk's coarse
  span; do not introduce a new substrate field

## Scope — what to do

### 1. Amend the spec

Edit `docs/02_system_specs/world/lake_generation.md`:

- bump `version` and `last_updated`
- in "Status" add an "Amendment 2026-05-XX (V2 / L6)" paragraph
  documenting the new `WORLD_VERSION = 41` boundary
- in "Per-Tile Classification" replace step 3..5 with the new rule:
  - sample the **3×3 neighbourhood** of coarse cells
    `(cx-1..cx+1, cy-1..cy+1)` around the tile (X-wrapped, Y-clamped
    by `clamp_foundation_world_y`)
  - among neighbours with `lake_id > 0` and
    `lake_water_level_q16 > 0`, pick the **best applicable** as
    follows: highest `lake_water_level_q16`; ties broken by lowest
    `lake_id`; second tie broken by neighbour priority
    `(0,0), (0,-1), (1,0), (0,1), (-1,0), (-1,-1), (1,-1), (1,1), (-1,1)`
    (centre-first then 4-neighbours then 4-diagonals; deterministic)
  - if no neighbour qualifies, the tile keeps the existing plains
    pipeline and `lake_flags = 0`
  - otherwise compute `tile_foundation_height` and `shore_warp`
    exactly as today, compare `effective_elevation` against the
    chosen `water_level`, and classify shore vs.
    `LAKE_BED_SHALLOW` vs. `LAKE_BED_DEEP` against the **chosen
    lake's** `basin_min_elevation` (looked up in the existing
    `world_prepass_lake_basin_min_elevation_` cache by the chosen
    `lake_id`)
- in "Per-Tile Classification" add an explicit guard: a tile may
  enter the lake branch only when its own coarse cell is **not**
  classified as mountain wall / mountain foot. Mountain-wins remains
  the hard tiebreaker.
- update "Acceptance Criteria → Lake Geometry" with two new bullets:
  - "lake outlines do not snap to coarse-cell boundaries; visual
    inspection at the new-game preview shows organic edges across
    coarse-cell seams"
  - "no tile in the 3×3 neighbourhood of any basin cell becomes
    water unless `bilinear(foundation_height) + shore_warp <
    chosen_water_level`"
- in "WORLD_VERSION" update the active value from `40` to `41`

Edit `docs/02_system_specs/world/world_foundation_v1.md`:

- in the Spawn Contract Amendment section, broaden the lake
  rejection: a candidate tile is rejected when **any** coarse cell in
  its 3×3 neighbourhood has `lake_id > 0` and the candidate's
  computed `effective_elevation < water_level` for that lake (use
  the same selection rule as above)
- record the new `WORLD_VERSION = 41` boundary cross-reference

### 2. Native per-tile classification

In `gdextension/src/world_core.cpp` around lines `955-1016`:

- replace the single-cell `resolve_snapshot_index_at_world` call with
  a 3×3 neighbour scan. Helper signature suggestion (place in
  anonymous namespace next to `resolve_snapshot_index_at_world`):
  ```cpp
  struct NeighbourLake {
      int32_t lake_id = 0;
      int32_t water_level_q16 = 0;
  };
  NeighbourLake resolve_best_neighbour_lake(
      const world_prepass::Snapshot &snapshot,
      int64_t world_x,
      int64_t world_y,
      const FoundationSettings &foundation_settings
  );
  ```
- inside the helper, iterate the 3×3 in the deterministic order
  defined in the spec, return the first match with the strictly
  highest `water_level_q16` (ties broken as documented)
- the existing `effective_elevation < water_level` comparison and
  shallow/deep classification stay as they are; just feed them the
  chosen `(lake_id, water_level)`
- `lake_flag_grid[sample_index] = LAKE_FLAG_WATER_PRESENT` on
  matched water tiles, regardless of which neighbour cell the lake
  came from
- preserve the existing assert at the end of
  `_generate_chunk_packet` that catches mountain-wins violations

### 3. Native spawn rejection

In `gdextension/src/world_core.cpp` `resolve_world_foundation_spawn_tile`
(or its substrate counterpart in `world_prepass.cpp`):

- replace the in-cell `lake_id > 0` rejection with the same 3×3
  neighbour rule used above; reject when the candidate is at or
  below water for the best neighbour lake
- keep the existing escalation (search radius widening + loud
  failure)

### 4. WORLD_VERSION bump

- `core/systems/world/world_runtime_constants.gd`: `WORLD_VERSION`
  advances from `40` to `41`
- `LAKE_PACKET_VERSION` constant in `gdextension/src/world_core.cpp`
  stays the V1 boundary (`38`); only `WORLD_VERSION` advances. The
  packet shape is unchanged in L6.

### 5. Doc cross-updates

- `docs/02_system_specs/meta/packet_schemas.md`: add the
  `WORLD_VERSION = 41` boundary line and a one-line note about the
  per-tile rule change
- `docs/02_system_specs/meta/save_and_persistence.md`: add the
  `WORLD_VERSION = 41` boundary line

## Scope — what NOT to do

- do not introduce any new substrate field
- do not add fields to `ChunkPacketV1`
- do not change shoreline FBM amplitude semantics; L7 owns that
- do not touch the substrate solve in `lake_field.cpp` (L5 owns it;
  if L5's mapping needs adjustment because of L6 visuals, flag it
  in `Out-of-Scope Observations`)
- do not change presentation in `chunk_view.gd` /
  `world_tile_set_factory.gd`
- do not modify the new-game UI; L7 owns it
- do not touch `world.json` read/write code paths
- do not refactor existing settings-packed indices
- do not change `ChunkDiffV0` shape
- do not bump `WORLD_VERSION` past `41` in this iteration
- do not modify mountain field internals
- do not change the basin-min-elevation lookup behaviour
- do not introduce a GDScript fallback

## Files that may be touched

### Modified
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/world/world_foundation_v1.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `core/systems/world/world_runtime_constants.gd`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_core.h` (only if a new helper requires a
  declaration; prefer anonymous namespace inside the .cpp)
- `gdextension/src/world_prepass.cpp` (only if spawn rejection lives
  there for substrate-level checks; mirror the same 3×3 rule)

## Files that must NOT be touched

- `gdextension/src/world_prepass.h` (Snapshot field set is frozen)
- `gdextension/src/lake_field.{h,cpp}`
- `core/resources/lake_gen_settings.gd`
- `data/balance/lake_gen_settings.tres`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `scenes/ui/new_game_panel.gd`
- `core/autoloads/save_collectors.gd`, `save_appliers.gd`,
  `save_io.gd`
- `locale/ru/messages.po`, `locale/en/messages.po`
- `gdextension/src/mountain_field.{h,cpp}`
- any building / power / combat / fauna / progression / lore system

## Acceptance tests

- [ ] Static check: `WorldRuntimeConstants.WORLD_VERSION == 41`.
- [ ] Static check: `world_core.cpp` per-tile lake branch reads
      `lake_id` / `lake_water_level_q16` from a 3×3 neighbour scan
      with the documented deterministic priority order; the central
      `if (lake_id <= 0 || water_level_q16 <= 0) continue;` early
      bail still applies only when **no neighbour** qualifies.
- [ ] Static check: spawn resolver rejects candidates whose 3×3
      neighbour scan yields water at the candidate's
      `effective_elevation`, with the existing widening fallback
      preserved.
- [ ] Determinism (manual or smoke test): same
      `(seed, world_version, world_bounds, settings_packed)`
      produces bit-identical `terrain_ids`, `walkable_flags`,
      `lake_flags` across two builds.
- [ ] Visual (manual human verification required): on a fixed seed
      with at least one mid-size lake, the lake outline shows no
      vertical/horizontal cuts that align with 64-tile coarse-cell
      boundaries; the shoreline crosses coarse-cell seams smoothly.
- [ ] No mountain regression: on a seed with no lakes
      (`lake_density = 0.0`) the chunk packet output is identical
      to the post-L5 build (manual or smoke test).
- [ ] Performance: median chunk packet time on `large` preset grows
      `≤ 1.0 ms` vs. post-L5. If not measured, mark as
      `manual human verification required`.
- [ ] Spawn: across a sample of seeds, the spawn resolver never
      emits a tile that turns out to be water on publish.
- [ ] Canonical docs (grep): `WORLD_VERSION = 41` and the new
      "3×3 neighbourhood" wording appear in `lake_generation.md` and
      `world_foundation_v1.md`; report line numbers.

## Result format

Closure report following the format from `WORKFLOW.md`. Mandatory
sections as in L5. `not required` lines must be backed by grep
evidence.
