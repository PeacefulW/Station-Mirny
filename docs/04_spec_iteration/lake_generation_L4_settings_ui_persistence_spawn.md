---
title: Lake Generation L4 — Settings UI, Persistence, Spawn Contract Amendment
doc_type: iteration_brief
status: ready
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-05-02
spec: docs/02_system_specs/world/lake_generation.md
depends_on:
  - lake_generation_L1_substrate_basin_solve.md
  - lake_generation_L2_bed_terrain_packet.md
  - lake_generation_L3_water_presentation_layer.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_foundation_v1.md
  - ../02_system_specs/world/world_runtime.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../02_system_specs/meta/system_api.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Lake Generation L4 — Settings UI, Persistence, Spawn Contract Amendment

## Required reading before you start

1. `AGENTS.md`
2. `docs/00_governance/WORKFLOW.md`
3. `docs/00_governance/ENGINEERING_STANDARDS.md`
4. `docs/00_governance/PROJECT_GLOSSARY.md`
5. `docs/02_system_specs/world/lake_generation.md`
6. Closure reports of L1, L2, L3
7. `docs/02_system_specs/world/world_foundation_v1.md` — Spawn
   Contract Amendment section. The new lake rejection extends the
   same amendment.
8. `docs/02_system_specs/world/world_runtime.md` — V1-R1B Spawn,
   Bounds, and Substrate Amendment
9. `docs/02_system_specs/meta/save_and_persistence.md`
10. `docs/02_system_specs/meta/packet_schemas.md`
    (`WorldFoundationSpawnResult` shape)
11. The current new-game panel scene + script (path is documented in
    `world_foundation_v1.md` Files That May Be Touched section;
    confirm exact path before code)

## Goal

Make `LakeGenSettings` player-controllable, persistent, and integrated
with spawn:

1. Add a "Water sector" panel to the new-game UI mirroring the
   existing mountain panel.
2. Persist the resource into `world.json` under
   `worldgen_settings.lakes` on new game; load it on world load.
3. Amend the spawn resolver to reject any candidate inside a coarse
   node with `lake_id > 0`.

After this iteration, V1 lake generation is feature-complete.

## Context

L1 introduced `LakeGenSettings` defaults via `data/balance/...tres`.
L2 made the chunk packet consume them through `settings_packed`. L3
added the visual water layer.

L4 closes the loop: settings travel with the save (so editing the
repo's `.tres` does not retroactively change existing worlds), the UI
exposes the settings (so players can tune their world), and the spawn
resolver respects lake geometry.

## Boundary contract check

- Existing safe paths to use:
  - `SaveCollectors` / `SaveAppliers` are the only authors of
    `world.json` save shape
  - `WorldStreamer` (or the documented owner of `worldgen_settings`
    plumbing in V1-R1A) is the only seam between `world.json` and
    `settings_packed`
  - the new-game panel already binds `MountainGenSettings` and
    `FoundationGenSettings`; reuse the same control wiring pattern
  - `WorldCore::resolve_world_foundation_spawn_tile(...)` is the only
    seam for spawn resolution rules
- Canonical docs that **must** be updated in this task:
  - `docs/02_system_specs/meta/save_and_persistence.md` — add
    `worldgen_settings.lakes` schema
  - `docs/02_system_specs/meta/packet_schemas.md` — extend
    `WorldFoundationSpawnResult` notes with the new lake rejection
    rule
  - `docs/02_system_specs/world/world_foundation_v1.md` — extend
    Spawn Contract Amendment with the lake rejection
  - `docs/02_system_specs/world/world_runtime.md` — mirror the spawn
    amendment in the V1-R1B Spawn section if it duplicates the rules
- New public API / event / command: none. Settings UI binds to an
  existing resource pattern; spawn surface keeps its dictionary shape.

## Performance / scalability guardrails

- Runtime class: `boot/load` (settings persistence + spawn). UI work
  is non-runtime.
- Target scale / density: spawn resolver still inspects O(1) coarse
  cells per candidate; lake rejection adds one more substrate read
  per candidate
- Source of truth + write owner: `world.json` for persisted settings,
  `WorldCore` for spawn rejection
- Dirty unit: settings on world creation; spawn rejection per
  candidate
- Escalation path: if the spawn resolver fails to find a candidate
  on lake-heavy seeds, expand the search radius deterministically and
  fail loudly if no candidate is found at the documented preset cap

## Scope — what to do

1. New-game panel additions (Russian-first labels, English in
   parentheses where the existing UI uses that convention):
   - new "Сектор воды (Water sector)" group with sliders for
     `density`, `scale`, `shore_warp_amplitude`, `shore_warp_scale`,
     `deep_threshold`, `mountain_clearance`
   - bind to a `LakeGenSettings` instance hosted by the panel scene
     exactly like the existing mountain group binds to
     `MountainGenSettings`
   - the panel writes into the same `world.json` builder used for
     other `worldgen_settings` sections at "Start"
2. Persistence:
   - `core/autoloads/save_collectors.gd` `collect_world()` includes
     `worldgen_settings.lakes` from the current `WorldStreamer`
   - `core/autoloads/save_appliers.gd` `apply_world()` reads
     `worldgen_settings.lakes` and pushes the values into
     `LakeGenSettings`, then forwards into `settings_packed` indices
     `15..20` for the load path
   - missing `worldgen_settings.lakes` for current `world_version` is
     a load failure; reuse the existing failure path used by mountain
     and foundation settings
3. Spawn contract amendment:
   - in `gdextension/src/world_core.cpp`
     `resolve_world_foundation_spawn_tile`, after the existing
     ocean / burning / wall_density / continent rules, add:
     - **reject** if the candidate's coarse node has `lake_id > 0`
   - `WorldFoundationSpawnResult` keeps its existing key set; no new
     keys
   - update the failure escalation rule in code comments to mention
     lakes alongside the existing mountain massif language
4. Documentation updates in the same task:
   - `docs/02_system_specs/world/lake_generation.md`: status moves
     from `draft` to `approved` once L4 closes; record final
     `WORLD_VERSION` boundary
   - `docs/02_system_specs/world/world_foundation_v1.md`: extend
     Spawn Contract Amendment list with the lake rule
   - `docs/02_system_specs/world/world_runtime.md`: mirror the lake
     rule into the V1-R1B Spawn section if that section enumerates
     rejection rules
   - `docs/02_system_specs/meta/save_and_persistence.md`: add
     `worldgen_settings.lakes` schema and confirm the
     `WORLD_VERSION = 38` boundary line introduced in L2 stays valid
   - `docs/02_system_specs/meta/packet_schemas.md`: note the
     `lake_id > 0` rejection in the `WorldFoundationSpawnResult`
     "Current code notes" list

## Scope — what NOT to do

- do not change the chunk packet shape (L2-frozen)
- do not change the substrate field set (L1-frozen)
- do not change the water presentation layer behaviour (L3-frozen)
- do not bump `WORLD_VERSION` again
- do not introduce a new `EventBus` signal
- do not introduce a new save file or collector beyond the
  `worldgen_settings.lakes` extension
- do not silently expand the spawn API surface (no new dictionary keys
  in `WorldFoundationSpawnResult`)
- do not migrate `world_version <= 37` saves; pre-alpha rejects them
- do not add tooltips, lore, or design content beyond field labels
  and a short value summary

## Files that may be touched

### Modified
- `scenes/ui/new_game_panel.gd` (and corresponding `.tscn` if the UI
  builder is scene-driven)
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `core/systems/world/world_streamer.gd`
- `gdextension/src/world_core.cpp` (spawn rejection rule)
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/world/world_foundation_v1.md`
- `docs/02_system_specs/world/world_runtime.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `docs/02_system_specs/meta/packet_schemas.md`

### New
- none expected; the bindings reuse existing UI patterns

## Files that must NOT be touched

- `core/systems/world/world_runtime_constants.gd`
  (`WORLD_VERSION` was last bumped in L2)
- `core/systems/world/world_diff_store.gd`
- `gdextension/src/world_prepass.{h,cpp}` (substrate is L1-frozen)
- `gdextension/src/lake_field.{h,cpp}` (basin solve is L1-frozen)
- `gdextension/src/mountain_field.{h,cpp}`
- `core/systems/world/chunk_view.gd` (water layer is L3-frozen)
- `core/systems/world/world_tile_set_factory.gd`,
  `terrain_presentation_registry.gd`,
  `world_foundation_palette.gd`
- combat, fauna, progression, inventory, crafting, lore systems
- subsurface or environment-runtime files

## Acceptance tests

- [ ] Static: `SaveCollectors.collect_world()` writes
      `worldgen_settings.lakes` with all six fields when a
      `LakeGenSettings` is active.
- [ ] Static: `SaveAppliers.apply_world()` reads
      `worldgen_settings.lakes` and routes the values into
      `settings_packed` indices `15..20`.
- [ ] Static: missing `worldgen_settings.lakes` on current
      `world_version` causes load to fail through the same path that
      mountain/foundation use.
- [ ] Static: `WorldCore::resolve_world_foundation_spawn_tile`
      rejects coarse nodes with `lake_id > 0`.
- [ ] Round-trip persistence: new game writes the section once;
      reloading the same save reproduces the same lake layout even
      after the repository's `data/balance/lake_gen_settings.tres`
      defaults are intentionally edited (manual human verification
      acceptable; record the experiment in the closure report).
- [ ] UI binding: every slider visibly changes overview previews
      after the existing debounce; the mountain panel still works.
- [ ] Spawn safety: across a sample of 10 seeds for each preset
      (`small`, `medium`, `large`) at default `lake_density`, the
      spawn tile is never inside a `lake_id > 0` coarse node. Manual
      human verification with seeds recorded.
- [ ] No regression: with `lake_density = 0.0`, all V1-R1A and V1-R1B
      acceptance tests still pass.
- [ ] Canonical doc check (grep): `worldgen_settings.lakes`,
      `lake_id`, `lake rejection` (or equivalent) appear in
      `save_and_persistence.md`, `packet_schemas.md`,
      `world_foundation_v1.md`, `world_runtime.md`. Line numbers in
      the closure report.
- [ ] Status flip: `lake_generation.md` `status` changes from `draft`
      to `approved` and `last_updated` is bumped. The closure report
      records the change.

## Result format

Closure report per `WORKFLOW.md`. `not required` for any canonical doc
must be backed by grep evidence.
