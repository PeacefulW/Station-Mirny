---
title: Lake Generation L8 — Mask and Connected Components
doc_type: iteration_brief
status: ready
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-05-04
spec: docs/02_system_specs/world/lake_generation.md
depends_on:
  - lake_generation_L7_shore_warp_normalization_and_ui.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_foundation_v1.md
  - ../02_system_specs/world/mountain_generation.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../02_system_specs/meta/system_api.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Lake Generation L8 — Mask and Connected Components

## Required reading before you start

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/00_governance/WORKFLOW.md`
4. `docs/00_governance/ENGINEERING_STANDARDS.md`
5. `docs/00_governance/PROJECT_GLOSSARY.md`
6. `docs/02_system_specs/world/lake_generation.md`
7. `docs/02_system_specs/world/world_foundation_v1.md`
8. `docs/02_system_specs/world/mountain_generation.md`
9. `docs/02_system_specs/meta/packet_schemas.md`
10. `docs/02_system_specs/meta/save_and_persistence.md`
11. `docs/02_system_specs/meta/system_api.md`
12. ADR-0001, ADR-0002, ADR-0003, ADR-0006, ADR-0007

## Goal

Replace the V1 / V2 local-minimum watershed lake solve with the V3 / L8
algorithm approved in `lake_generation.md`:

- elevation-threshold mask over eligible coarse substrate cells
- deterministic face-connected-component labeling with X-wrap and bounded Y
- `LakeGenSettings.density` as target submerged-area fraction
- `LakeGenSettings.scale` as minimum component diameter in tiles
- `LakeGenSettings.connectivity` as a canonical no-op for
  `world_version >= 43`
- `WORLD_VERSION` bump from `42` to `43`

## Boundary contract check

- Existing safe path to use:
  - `WorldPrePass` substrate owned by native `WorldCore`
  - existing `ChunkPacketV1` fields, including `lake_flags`
  - existing `worldgen_settings.lakes` save shape and `settings_packed[15..21]`
  - existing spawn resolver output shape
- New public API / event / command / packet field: none.
- Canonical docs to update:
  - `packet_schemas.md`: add the `WORLD_VERSION = 43` L8 algorithm boundary
  - `save_and_persistence.md`: mark `WORLD_VERSION = 43` current and document
    that `connectivity` remains mandatory but no-op for canonical output
  - `world_foundation_v1.md`: update `lake_water_level_q16` semantics for
    `world_version >= 43`
  - `system_api.md`: update current version wording only if stale; no new safe
    surface expected

## Performance / scalability guardrails

- Runtime class: `boot/load` for substrate solve, `background` for per-tile
  chunk packet classification, no new interactive work.
- Target scale: largest preset coarse grid stays at `128 x 64 = 8192` nodes.
- Source of truth + write owner: `WorldCore` native owns substrate fields;
  `world.json` owns per-save lake settings.
- Dirty unit: whole `WorldPrePass` substrate at world load; `32 x 32` chunk for
  packet generation; one tile for excavation remains unchanged.
- Escalation path: if sort cost breaches budget, replace percentile selection
  with a deterministic bucket/counting threshold without changing output.

## Scope — what to do

- Extend `tools/lake_generation_regression_smoke_test.gd` before production
  code so it catches:
  - current `WORLD_VERSION == 43`
  - native source contains the L8 threshold + connected-component path
  - varying `connectivity` does not change `lake_id` or
    `lake_water_level_q16` at fixed seed/settings
- In `gdextension/src/lake_field.cpp`, implement V3 / L8 for
  `world_version >= 43`:
  - reject-mask filtering
  - percentile threshold from eligible `foundation_height`
  - 4-neighbour union-find, X-wrap-safe, bounded Y
  - discard components smaller than
    `min_lake_component_cells = clamp(round(scale / 64), 1, 4096)`
  - deterministic representative cell, lake id salt sweep, and uniform
    `lake_water_level_q16`
- Preserve V1 / V2 historical behaviour only for `world_version <= 42` if the
  old code path remains in the file.
- Keep per-tile classification, water presentation, excavation, save shape, and
  `ChunkPacketV1` shape unchanged.
- Update locale copy for `UI_WORLDGEN_LAKES_CONNECTIVITY_DESC` in `ru` and
  `en` so the no-op behaviour is visible to players.
- Update required canonical docs and `WORLD_VERSION`.

## Scope — what NOT to do

- Do not add substrate fields.
- Do not extend `ChunkPacketV1`.
- Do not change `settings_packed` indices or field count.
- Do not remove `worldgen_settings.lakes.connectivity` from saves or UI.
- Do not add rivers, streams, drying, swimming, or water resources.
- Do not touch subsurface, environment runtime, building, power, combat,
  fauna, progression, inventory, crafting, or lore systems.
- Do not introduce a GDScript fallback.

## Files that may be touched

- `docs/04_spec_iteration/lake_generation_L8_mask_connected_components.md`
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/world/world_foundation_v1.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/meta/system_api.md` only for stale current-version text
- `core/systems/world/world_runtime_constants.gd`
- `gdextension/src/lake_field.cpp`
- `gdextension/src/lake_field.h` only if helper signatures change
- `locale/ru/messages.po`
- `locale/en/messages.po`
- `tools/lake_generation_regression_smoke_test.gd`

## Files that must NOT be touched

- `ChunkDiffV0` shape and chunk diff save files
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `gdextension/src/mountain_field.{h,cpp}`
- any building, power, combat, fauna, progression, inventory, crafting, lore,
  subsurface, or environment-runtime file

## Acceptance tests

- [ ] Static check: `WorldRuntimeConstants.WORLD_VERSION == 43`.
- [ ] Static check: `lake_field.cpp` contains the V3 / L8
      threshold-mask and union-find connected-component path.
- [ ] Smoke check: same seed/settings at `connectivity = 0.0` and
      `connectivity = 1.0` produces identical `lake_id` and
      `lake_water_level_q16` arrays for current `world_version`.
- [ ] Smoke check: same seed/settings still produces deterministic
      `lake_id`, `lake_water_level_q16`, `terrain_ids`, `walkable_flags`,
      and `lake_flags` across repeated native calls.
- [ ] Static check: `settings_packed` length remains `22`; no new packet or
      save field appears.
- [ ] Static check: `UI_WORLDGEN_LAKES_CONNECTIVITY_DESC` exists in `ru` and
      `en` and describes `connectivity` as no-op for V3 worlds.
- [ ] Performance: existing large-preset substrate smoke remains `<= 900 ms`
      on `compute_time_ms`; if the local environment cannot run native Godot,
      mark explicit runtime verification as not run and hand off the check.
- [ ] Canonical docs: grep evidence for `WORLD_VERSION = 43`,
      `lake_water_level_q16`, and `connectivity` in updated docs.

## Result format

Closure report following `AGENTS.md` / `WORKFLOW.md`, in Russian with canonical
English terms in parentheses. `not required` doc updates must include grep
evidence.
