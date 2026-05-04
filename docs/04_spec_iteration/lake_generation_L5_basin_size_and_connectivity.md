---
title: Lake Generation L5 — Basin Size Mapping and Lake Connectivity
doc_type: iteration_brief
status: ready
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-05-03
spec: docs/02_system_specs/world/lake_generation.md
depends_on:
  - lake_generation_v2_overview.md
  - lake_generation_L1_substrate_basin_solve.md
  - lake_generation_L2_bed_terrain_packet.md
  - lake_generation_L3_water_presentation_layer.md
  - lake_generation_L4_settings_ui_persistence_spawn.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_foundation_v1.md
  - ../02_system_specs/world/mountain_generation.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Lake Generation L5 — Basin Size Mapping and Lake Connectivity

## Required reading before you start

Read in order. Do not start broad code exploration in advance.

1. `AGENTS.md`
2. `docs/00_governance/WORKFLOW.md`
3. `docs/00_governance/ENGINEERING_STANDARDS.md`
4. `docs/00_governance/PROJECT_GLOSSARY.md`
5. `docs/04_spec_iteration/lake_generation_v2_overview.md`
6. `docs/02_system_specs/world/lake_generation.md` (this iteration
   amends it)
7. `docs/02_system_specs/world/world_foundation_v1.md` (frozen field
   set; **no new fields here**)
8. `docs/02_system_specs/world/mountain_generation.md` (template for
   the continuity / connectivity pattern; copy the spirit, not the
   numbers)
9. `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`

## Goal

Make basin size actually scale with `LakeGenSettings.scale` and
introduce a `connectivity` parameter that fuses neighbouring basins
with similar rim heights into a single `lake_id`, so the world can
hold both many small puddles and large connected lake systems.

This iteration **does not** touch per-tile classification, the
`ChunkPacketV1` shape, presentation, or the new-game UI. L6 owns the
per-tile shoreline; L7 owns the UI and shore-warp re-scaling.

## Context

Today `gdextension/src/lake_field.cpp:47-64` clamps
`max_basin_cells` to `[4, 256]` and the mapping `round(d*d)` saturates
at `scale ≈ 1024`. With `scale = 199` the basin can hold at most
`~10` coarse cells, ~640×640 tiles. There is no merge step, so two
adjacent shallow depressions that share a near-equal rim never
combine into one visible lake; this is what makes V1 lakes look
"shattered" instead of forming the connected systems the player
expects from the mountain side of the panel.

V2 design summary in `lake_generation_v2_overview.md` is normative.

## Boundary contract check

- Existing safe path to use:
  - `WorldPrePass::Snapshot` is the single owner of substrate fields;
    only `lake_id` and `lake_water_level_q16` are written by this
    iteration; the field set itself does **not** grow
  - `LakeSettings` POD struct in `gdextension/src/lake_field.h` /
    `world_core.cpp` is the existing unpacked-settings boundary
- Canonical docs to check before code:
  - `docs/02_system_specs/world/lake_generation.md` — "Lake Basin
    Solve" and "Worldgen Settings" sections must be amended in this
    task
  - `docs/02_system_specs/meta/packet_schemas.md` — note new
    `WORLD_VERSION = 40` packet boundary
  - `docs/02_system_specs/meta/save_and_persistence.md` — note new
    `WORLD_VERSION = 40` and that `worldgen_settings.lakes` gains the
    `connectivity` field (the persistence wiring itself lands in L7;
    L5 only adds the field with `default 0.4` flowing through
    `settings_packed`)
- New public API / event / schema / command: none. Settings packed
  layout grows by one index, which is a substrate-only contract
  already covered by `lake_generation.md`.

## Performance / scalability guardrails

- Runtime class: `boot/load` (worker-only)
- Target scale / density: substrate budget `≤ 900 ms` on `large`
  preset stays the same; basin solve + merge target `≤ 120 ms` on
  reference hardware on `large`
- Source of truth + write owner: `WorldPrePass` (native)
- Dirty unit: whole substrate, recomputed only on world load
- Escalation path: if the merge pass breaks budget, cap the merge
  iteration count and fall back to "merge nearest pair only", recorded
  in `lake_field.cpp` comments; do not introduce a new field

## Scope — what to do

### 1. Amend the spec

Edit `docs/02_system_specs/world/lake_generation.md` in the same
task:

- bump `version` and `last_updated`
- in "Status" add an "Amendment 2026-05-XX (V2 / L5)" paragraph that
  records the new `WORLD_VERSION = 40` boundary and the changes below
- in "Lake Basin Solve" replace the basin-shape mapping description:
  - `lake_seed_search_radius`: unchanged (`clamp(round(d/2.5), 1, 8)`)
  - `lake_max_basin_cells`: `clamp(round(d*d), 4, 4096)` (was 256)
  - `lake_min_basin_cells`: `clamp(round(d*d/16), 2, 64)`
    (was `/32`, capped at 16)
  - `d = scale / COARSE_CELL_SIZE_TILES`, with
    `COARSE_CELL_SIZE_TILES = 64` from `world_prepass.h`
- in "Lake Basin Solve" add a new step **8. Deterministic basin
  merge** after step 7 ("Write fields"):
  - inputs: completed `lake_id` array, `connectivity` setting, and
    rim heights per basin recorded during solve
  - rule: two basins `A` and `B` merge iff they touch on at least
    one shared 4-neighbour edge of coarse cells, **and**
    `|rim_height_A - rim_height_B| < merge_height_tolerance`,
    where
    `merge_height_tolerance = lerp(0.0, 0.06, connectivity)`
    (linear in `[0,1]`, units = `foundation_height`)
  - on merge, the surviving `lake_id` is the one with the **lower
    BFS root index** (`y * grid_width + x`); the merged
    `water_level_q16` is `min(level_A, level_B)` (lower spill wins
    so we do not flood beyond either rim)
  - iterate: compute candidate pairs, sort by
    `(min_lake_id, max_lake_id)`, merge in that order, repeat until
    a pass produces zero merges or until `merge_iteration_cap` is
    reached (define `merge_iteration_cap = 16` in code; document it
    in the spec)
  - all neighbour traversal must wrap on X
  - if `connectivity == 0.0`, the merge pass MUST be a no-op
- in "Worldgen Settings" replace the `LakeGenSettings` table to
  include the new field:
  - `connectivity`, range `[0.0, 1.0]`, default `0.4`,
    "Лимит схожести соседних бассейнов для слияния. 0 — каждое
    озеро своё; 1 — крупные связные системы."
- in "Worldgen Settings" update the `settings_packed` table:
  - add `21 = SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY`
  - update `22 = SETTINGS_PACKED_LAYOUT_FIELD_COUNT`
- in "WORLD_VERSION" update the active value from `39` to `40` and
  record the rationale (basin shape mapping + merge changes
  canonical output for same `(seed, settings)`)
- in `world.json` example block add `"connectivity": 0.4`
- in "Acceptance Criteria → Determinism" add a bullet: "varying
  `connectivity` produces a measurable difference at fixed seed"
- update the `last_updated` field at the top

### 2. Update `LakeGenSettings`

- `core/resources/lake_gen_settings.gd`: add exported field
  `@export var connectivity: float = 0.4` with the documented range
- update `write_to_settings_packed` to write
  `connectivity` at index `21` and bump the bounds check to `22`
- `data/balance/lake_gen_settings.tres`: persist
  `connectivity = 0.4`

### 3. Update settings-packed wiring (GDScript)

- `core/systems/world/world_runtime_constants.gd`:
  - `SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY = 21`
  - `SETTINGS_PACKED_LAYOUT_FIELD_COUNT = 22`
  - `WORLD_VERSION` advances from `39` to `40`
- any GDScript that asserts the packed length must use the constant,
  not a literal

### 4. Native unpack

- `gdextension/src/lake_field.h` (`LakeSettings` POD): add
  `float connectivity = 0.4f`
- `gdextension/src/world_core.cpp` `unpack_lake_settings`: read
  index `21` into `connectivity`; sanitise to `[0.0, 1.0]`

### 5. Native basin solve

In `gdextension/src/lake_field.cpp`:

- update `derive_basin_shape` to the new mapping:
  - `seed_search_radius = clamp(round(d/2.5), 1, 8)` (no change)
  - `max_basin_cells   = clamp(round(d*d), 4, 4096)`
  - `min_basin_cells   = clamp(round(d*d/16), 2, 64)`
  - update the inline comment so it documents the new formula and
    the `d = scale/COARSE_CELL_SIZE_TILES` definition
- record per-basin rim height in a `std::vector<BasinSummary>` (or
  similar) during `solve_lake_basins`, with each entry holding
  `lake_id`, `rim_height`, `bfs_root_index`
- after the candidate loop, run a deterministic merge pass:
  - build adjacency via 4-neighbour scan over `lake_id`, X-wrap
  - merge pairs by the rule above
  - on merge, rewrite every cell with the losing `lake_id` to the
    surviving `lake_id`, update its `lake_water_level_q16` to
    `round(min(level_a, level_b) * 65536)`
  - cap at `merge_iteration_cap = 16`
  - merge pass MUST be a no-op when `connectivity <= 0.0f`
- update the basin-min-elevation lookup
  (`build_basin_min_elevation_lookup`) so it uses the **post-merge**
  `lake_id` (it already iterates the snapshot, but it must run after
  the merge pass)

### 6. Determinism guards

- the merge pass must not depend on hash-map iteration order; use
  `std::vector` of pairs sorted by `(min_id, max_id)`
- assert in debug that `merge_iteration_cap` is not exceeded

### 7. Doc cross-updates

- `docs/02_system_specs/meta/packet_schemas.md`: add
  `WORLD_VERSION = 40` boundary line; same shape, only the algorithm
  changed
- `docs/02_system_specs/meta/save_and_persistence.md`: add the
  `WORLD_VERSION = 40` boundary line and note that
  `worldgen_settings.lakes.connectivity` is **not yet** mandatory in
  L5 (the persistence wiring lands in L7); L5 reads default from
  `lake_gen_settings.tres` for new worlds
- `docs/02_system_specs/world/world_foundation_v1.md`: confirm no
  frozen-set change; record grep evidence in closure report

## Scope — what NOT to do

- do not introduce any new substrate field
- do not extend `ChunkPacketV1`
- do not touch per-tile classification in `world_core.cpp` chunk
  packet loop (`world_core.cpp:955-1016`); L6 owns that
- do not change shoreline FBM semantics; L7 owns that
- do not add the connectivity slider to the UI; L7 owns that
- do not change `world.json` read/write code paths (the new key is
  read but writing is L7)
- do not refactor existing settings-packed indices `0..20`
- do not introduce a GDScript fallback for the merge pass
- do not change `ChunkDiffV0` shape
- do not bump `WORLD_VERSION` past `40` in this iteration
- do not modify mountain field internals
- do not attempt to "while you are here" speed up the existing BFS

## Files that may be touched

### Modified
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `core/resources/lake_gen_settings.gd`
- `data/balance/lake_gen_settings.tres`
- `core/systems/world/world_runtime_constants.gd`
- `gdextension/src/lake_field.h`
- `gdextension/src/lake_field.cpp`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_core.h` (only if `unpack_lake_settings`
  signature must change; prefer keeping it)

## Files that must NOT be touched

- `gdextension/src/world_prepass.{h,cpp}` (Snapshot field set is
  frozen for V2)
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `scenes/ui/new_game_panel.gd`
- `core/autoloads/save_collectors.gd`, `save_appliers.gd`,
  `save_io.gd`
- `locale/ru/messages.po`, `locale/en/messages.po`
- `gdextension/src/mountain_field.{h,cpp}` internals
- any building / power / combat / fauna / progression / lore system

## Acceptance tests

- [ ] Static check: `WorldRuntimeConstants.WORLD_VERSION == 40`,
      `SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY == 21`,
      `SETTINGS_PACKED_LAYOUT_FIELD_COUNT == 22`.
- [ ] Static check: `LakeGenSettings.connectivity` is a `@export`ed
      `float` with range `[0.0, 1.0]` and default `0.4`;
      `data/balance/lake_gen_settings.tres` carries `connectivity =
      0.4`.
- [ ] Static check: `derive_basin_shape` matches the documented
      mapping (verify the three lines in `lake_field.cpp`).
- [ ] Static check: in `lake_field.cpp` the merge pass is gated by
      `connectivity > 0.0f` and runs after `solve_lake_basins`'s
      candidate loop; `build_basin_min_elevation_lookup` runs after
      the merge pass.
- [ ] Determinism (manual or smoke test): same
      `(seed, world_version, world_bounds, settings_packed)` produces
      bit-identical `lake_id` and `lake_water_level_q16` arrays
      across two builds. Add or update a regression test under
      `tools/lake_generation_regression_smoke_test.gd` if practical;
      otherwise mark as `manual human verification required` and
      provide reproduction seed.
- [ ] Visual delta (manual human verification required): on a fixed
      seed, sweeping `connectivity = 0.0 → 1.0` visibly fuses
      neighbouring lakes on the new-game preview;
      `connectivity = 0.0` reproduces the V1 layout up to algorithm
      changes from the new mapping.
- [ ] Visual delta (manual human verification required): on a fixed
      seed at `scale = 2048`, single basins span at least
      `~32×32` coarse cells (vs. the V1 cap of `16×16`).
- [ ] Performance: substrate compute on `large` preset within
      `≤ 900 ms`. If the user has not measured, mark as
      `manual human verification required` with the suggested
      reproduction.
- [ ] Canonical docs (grep): `connectivity`, `WORLD_VERSION = 40`,
      and `SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY` appear in
      `lake_generation.md`, `packet_schemas.md`, and
      `save_and_persistence.md` with line numbers in the closure
      report.

## Result format

Closure report following the format from `WORKFLOW.md`. Mandatory
sections: Implemented, Root Cause, Files Changed, Acceptance Tests,
Proof Artifacts, Performance Artifacts, Canonical Documentation
Check, Out-of-Scope Observations, Remaining Blockers, Canonical Docs
Updated.

`not required` lines must be backed by grep evidence.
