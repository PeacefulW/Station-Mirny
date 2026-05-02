---
title: Lake Generation L1 — Substrate Basin Solve and LakeGenSettings Backend
doc_type: iteration_brief
status: ready
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-05-02
spec: docs/02_system_specs/world/lake_generation.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_foundation_v1.md
  - ../02_system_specs/world/mountain_generation.md
  - ../02_system_specs/world/world_runtime.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Lake Generation L1 — Substrate Basin Solve and `LakeGenSettings` Backend

## Required reading before you start

Read these in order before opening any code. Do not start broad code
exploration in advance.

1. `AGENTS.md`
2. `docs/00_governance/WORKFLOW.md`
3. `docs/00_governance/ENGINEERING_STANDARDS.md`
4. `docs/00_governance/PROJECT_GLOSSARY.md`
5. `docs/02_system_specs/world/lake_generation.md` (this iteration's
   spec)
6. `docs/02_system_specs/world/world_foundation_v1.md` (frozen
   substrate field set; this iteration extends it)
7. `docs/02_system_specs/world/mountain_generation.md` (template for
   the deterministic native-solve + settings-resource pattern)
8. `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`

## Goal

Add the two new substrate fields `lake_id` and `lake_water_level_q16`
to `WorldPrePass`, implement the bounded native lake-basin solve, and
introduce the `LakeGenSettings` resource plus its `settings_packed`
indices `15..20`.

This iteration **does not** change `terrain_ids`, `walkable_flags`,
`lake_flags`, or the chunk packet shape. It produces a fully working
substrate that the L2 packet path will consume.

This iteration **does not** bump `WORLD_VERSION`. Canonical chunk packet
output is unchanged in L1.

## Context

`WorldPrePass` already owns the coarse `64`-tile substrate consumed by
spawn resolution and the new-game overview. The lake stack reuses that
substrate by adding two additive fields. The basin solve runs once per
world load on the same worker that already builds the snapshot.

`LakeGenSettings` mirrors `MountainGenSettings`: a `Resource` that
flattens into `settings_packed` at fixed indices and is later persisted
in `world.json`. Persistence and UI wiring belong to L4; this iteration
only adds the backend and reads from `data/balance/lake_gen_settings.tres`.

## Boundary contract check

- Existing safe path to use:
  - `WorldPrePass::Snapshot` is the single owner of substrate fields
  - `WorldCore::_get_or_build_world_prepass(...)` is the only access seam
  - `MountainGenSettings.flatten_to_packed(...)` is the canonical pattern
    for `LakeGenSettings.write_to_settings_packed(...)`
- Canonical docs to check before code:
  - `docs/02_system_specs/meta/packet_schemas.md` —
    `WorldFoundationSnapshotDebug` shape (you must extend it
    additively)
  - `docs/02_system_specs/meta/save_and_persistence.md` — confirm no
    save shape changes are forced by L1
- New public API / event / schema / command added in L1: none. The
  substrate field extension is documented inside
  `world_foundation_v1.md`'s frozen-set amendment in the same task.

## Performance / scalability guardrails

- Runtime class: `boot/load` (worker-only), one-shot per world session
- Target scale / density: `large` preset substrate has `8192` coarse
  nodes; basin solve must add `≤ 100 ms` on reference hardware
- Source of truth + write owner: `WorldPrePass` (native)
- Dirty unit: whole substrate, recomputed only on world load
- Escalation path: if the budget breaks, sample the candidate scan
  every other coarse cell instead of every cell. The frozen field set
  remains the same. This is documented as Risk 1 in the spec.

## Scope — what to do

1. Add `core/resources/lake_gen_settings.gd` (new GDScript `Resource`).
   Exported fields with the ranges listed in the spec:
   `density`, `scale`, `shore_warp_amplitude`, `shore_warp_scale`,
   `deep_threshold`, `mountain_clearance`. Implement
   `write_to_settings_packed(packed: PackedFloat32Array) -> void`
   identical in pattern to `FoundationGenSettings.write_to_settings_packed`.
2. Add `data/balance/lake_gen_settings.tres` with the documented
   defaults.
3. Extend `core/systems/world/world_runtime_constants.gd`:
   - add `SETTINGS_PACKED_LAYOUT_LAKE_DENSITY = 15`,
     `_LAKE_SCALE = 16`, `_LAKE_SHORE_WARP_AMPLITUDE = 17`,
     `_LAKE_SHORE_WARP_SCALE = 18`, `_LAKE_DEEP_THRESHOLD = 19`,
     `_LAKE_MOUNTAIN_CLEARANCE = 20`
   - update `SETTINGS_PACKED_LAYOUT_FIELD_COUNT` from `15` to `21`
   - **do not** bump `WORLD_VERSION` in this iteration
4. In `core/systems/world/world_streamer.gd` (and any orchestrator that
   builds `settings_packed`): make sure `LakeGenSettings` defaults are
   loaded from `data/balance/lake_gen_settings.tres` and flattened into
   indices `15..20` of `settings_packed` for the boot/load worker. Do
   not yet read or write `worldgen_settings.lakes` from `world.json`;
   that is L4.
5. Extend `gdextension/src/world_prepass.h`:
   - add `PackedInt32Array lake_id` and `PackedInt32Array lake_water_level_q16`
     to `Snapshot`
   - add `LakeSettings` POD struct unpacked from `settings_packed[15..20]`
6. Extend `gdextension/src/world_prepass.cpp`:
   - in the existing build pass, after `coarse_valley_score` is
     finalised, call a new `solve_lake_basins(snapshot, lake_settings,
     seed, world_version, world_bounds)` function
   - implement the algorithm exactly as documented in the spec's
     "Lake Basin Solve" section: bounded local-min scan, bounded BFS,
     reject masks, rim height, deterministic `lake_id` hash with salt
     sweep on collision
   - use `std::vector<Candidate>` with explicit deterministic sort by
     `(cy, cx)`; do not use `std::unordered_map` for any data that
     affects output
   - all X access must wrap through the existing wrap-safe helpers
   - new file pair `gdextension/src/lake_field.h` / `lake_field.cpp`
     for the basin solve, keeping it out of `world_prepass.cpp`'s
     line budget
7. Extend `gdextension/src/world_core.cpp`:
   - update `LakeGenSettings`-aware unpacking of `settings_packed`
     (read indices `15..20`)
   - **do not** read `lake_id` in the chunk packet loop yet (L2 does
     that)
   - extend the dev-only `WorldFoundationSnapshotDebug` dictionary
     returned by `get_world_foundation_snapshot(layer_mask, ...)` so
     that `lake_id` and `lake_water_level_q16` are exposed alongside
     existing fields, gated by the same dev-only compile flag
   - update `signature` computation to include the new lake fields so
     that determinism diagnostics catch drift
8. Update spec / canonical docs in the same task:
   - amend `docs/02_system_specs/world/world_foundation_v1.md` frozen
     field set table to include `lake_id` and `lake_water_level_q16`,
     with the spec link as cross-reference
   - update `docs/02_system_specs/meta/packet_schemas.md` to extend
     `WorldFoundationSnapshotDebug` with the two new arrays
   - confirm `docs/02_system_specs/meta/save_and_persistence.md` does
     not need a change in L1 (substrate is RAM-only); record grep
     evidence for the `not required` line in the closure report

## Scope — what NOT to do

- do not introduce `TERRAIN_LAKE_BED_SHALLOW` or `TERRAIN_LAKE_BED_DEEP`
- do not add `lake_flags` to `ChunkPacketV1`
- do not bump `WORLD_VERSION`
- do not add a water `TileMapLayer`, water atlas, or any presentation
  resource
- do not write `worldgen_settings.lakes` to `world.json`
- do not add new-game UI controls
- do not modify spawn resolution
- do not change mountain field internals
- do not touch save collectors / appliers / IO beyond confirming no
  shape change
- do not introduce a new `EventBus` signal
- do not refactor existing substrate fields
- do not "while you are here" reorder existing `settings_packed`
  indices
- do not introduce a GDScript fallback for the lake basin solve

## Files that may be touched

### New
- `core/resources/lake_gen_settings.gd`
- `data/balance/lake_gen_settings.tres`
- `gdextension/src/lake_field.h`
- `gdextension/src/lake_field.cpp`

### Modified
- `gdextension/src/world_prepass.h`
- `gdextension/src/world_prepass.cpp`
- `gdextension/src/world_core.h`
- `gdextension/src/world_core.cpp`
- `gdextension/SConstruct`
- `gdextension/station_mirny.gdextension`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_streamer.gd` (or whichever current owner
  flattens `settings_packed`; respect existing ownership)
- `docs/02_system_specs/world/lake_generation.md` (status note only,
  if needed)
- `docs/02_system_specs/world/world_foundation_v1.md` (frozen-set
  amendment)
- `docs/02_system_specs/meta/packet_schemas.md` (`WorldFoundationSnapshotDebug`
  extension)

## Files that must NOT be touched

- `core/systems/world/world_diff_store.gd`
- `core/autoloads/save_collectors.gd`, `save_appliers.gd`, `save_io.gd`
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `core/systems/world/world_foundation_palette.gd`
- `scenes/ui/new_game_panel.gd`
- `core/entities/player/player.gd`
- `core/systems/building/*`, `core/systems/power/*`,
  `core/systems/combat/*`, any UI / progression / lore / fauna systems
- `gdextension/src/mountain_field.{h,cpp}` internals (read-only access
  to `sample_elevation` is allowed via the existing call site)

## Acceptance tests

- [ ] Static check: `WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_FIELD_COUNT`
      equals `21`; new lake indices are `15..20`; `WORLD_VERSION` is
      still `37`.
- [ ] Static check: `LakeGenSettings` exports six fields with the spec
      ranges; `data/balance/lake_gen_settings.tres` carries the
      documented defaults.
- [ ] Static check: `WorldPrePass::Snapshot` exposes `lake_id` and
      `lake_water_level_q16` arrays of length
      `grid_width * grid_height`.
- [ ] Static check: `WorldFoundationSnapshotDebug` (dev-only) returns
      both new arrays alongside existing fields.
- [ ] Determinism check (manual or test): same `(seed, world_version,
      world_bounds, settings_packed)` produces bit-identical
      `lake_id` and `lake_water_level_q16` arrays across two builds
      on the same host.
- [ ] No mountain regression: with `lake_density = 0.0`, mountain
      output of `ChunkPacketV1` is identical to the pre-change build
      for a fixed seed (manual human verification on the new-game
      overview is acceptable; document the seed in the closure report).
- [ ] Performance: substrate compute remains within `≤ 900 ms` on the
      `large` preset on reference hardware. Closure must record the
      measured number from the existing `compute_time_ms` debug field;
      if the user has not measured this themselves, mark it as
      `manual human verification required`.
- [ ] Canonical doc check (grep): every term among `lake_id`,
      `lake_water_level_q16`, `LakeGenSettings`,
      `SETTINGS_PACKED_LAYOUT_LAKE_DENSITY` appears in the updated
      `world_foundation_v1.md` and `packet_schemas.md` with line
      numbers in the closure report.

## Result format

Closure report following the format from `WORKFLOW.md`. Mandatory
sections: Implemented, Root Cause, Files Changed, Acceptance Tests,
Proof Artifacts, Performance Artifacts, Canonical Documentation Check,
Out-of-Scope Observations, Remaining Blockers, Canonical Docs Updated.

`not required` lines must be backed by grep evidence.
