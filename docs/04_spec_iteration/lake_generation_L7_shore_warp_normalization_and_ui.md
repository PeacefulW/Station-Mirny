---
title: Lake Generation L7 — Shore-Warp Normalisation, Connectivity UI, and Persistence
doc_type: iteration_brief
status: ready
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-05-04
spec: docs/02_system_specs/world/lake_generation.md
depends_on:
  - lake_generation_v2_overview.md
  - lake_generation_L5_basin_size_and_connectivity.md
  - lake_generation_L6_cross_cell_shoreline.md
related_docs:
  - ../02_system_specs/world/lake_generation.md
  - ../02_system_specs/world/world_foundation_v1.md
  - ../02_system_specs/meta/packet_schemas.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../02_system_specs/meta/system_api.md
  - ../00_governance/WORKFLOW.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Lake Generation L7 — Shore-Warp Normalisation, Connectivity UI, and Persistence

## Required reading before you start

1. `AGENTS.md`
2. `docs/00_governance/WORKFLOW.md`
3. `docs/00_governance/ENGINEERING_STANDARDS.md`
4. `docs/00_governance/PROJECT_GLOSSARY.md`
5. `docs/04_spec_iteration/lake_generation_v2_overview.md`
6. closure reports of L5 and L6 (both must be fully closed)
7. `docs/02_system_specs/world/lake_generation.md`
8. `docs/02_system_specs/meta/save_and_persistence.md` —
   `worldgen_settings.lakes` shape
9. the current new-game panel scene + script (path documented in
   `world_foundation_v1.md` "Files That May Be Touched"; confirm
   exact path before code, do **not** scan the repo at large)
10. `locale/ru/messages.po` and `locale/en/messages.po` to keep
    parallel coverage

## Goal

Three closely-related deliveries that finish V2:

1. Make `shore_warp_amplitude` behave consistently across basin
   sizes by interpreting it as a **fraction of basin depth**
   instead of an absolute `foundation_height` number.
2. Expose the `connectivity` setting (added in L5) in the new-game
   UI as a `СВЯЗНОСТЬ ОЗЁР` slider mirroring the existing
   mountain `СВЯЗНОСТЬ ХРЕБТОВ` slider.
3. Make `worldgen_settings.lakes.connectivity` mandatory in
   `world.json`, persist it on new game, load it on world load.

After L7 the player can dial all V2 knobs from the new-game panel,
the visual quality is balanced across small and large basins, and
`world.json` has its final V2 shape.

## Context

Today shoreline FBM uses an absolute amplitude (`0.8` default,
range `[0.0, 2.0]`) directly added to `bilinear(foundation_height)`
in `[0,1]`. For small basins the noise dominates the rim
comparison; for large basins it is barely visible. The fix is to
scale the noise by `(water_level - basin_min_elevation)`, the
basin's own depth, so the same amplitude value produces equally
expressive shorelines on small and large lakes.

`connectivity` was wired through `LakeGenSettings` and
`settings_packed[21]` in L5 but defaults from
`data/balance/lake_gen_settings.tres`. L7 finalises persistence so
existing saves keep their value across runs, exactly like
`density`, `scale`, and the rest.

V2 design summary in `lake_generation_v2_overview.md` is normative.

## Boundary contract check

- Existing safe path to use:
  - `LakeGenSettings.write_to_settings_packed` (L5)
  - the existing `worldgen_settings.lakes` block in
    `save_collectors.gd` / `save_appliers.gd` / `save_io.gd`
  - the existing mountain continuity slider in
    `scenes/ui/new_game_panel.{tscn,gd}` is the structural template
- Canonical docs to check before code:
  - `docs/02_system_specs/world/lake_generation.md` — "Per-Tile
    Classification" formula, "Worldgen Settings" defaults table,
    `world.json` example, "Acceptance Criteria → Persistence"
  - `docs/02_system_specs/meta/save_and_persistence.md` — make the
    `connectivity` field **mandatory** under `WORLD_VERSION = 42`
  - `docs/02_system_specs/meta/packet_schemas.md` — note new
    `WORLD_VERSION = 42`
  - `docs/02_system_specs/meta/system_api.md` — confirm no public
    API surface change is forced; record grep evidence
- New public API / event / schema / command: none at the system
  level. The `world.json` `worldgen_settings.lakes` block schema
  changes by promoting `connectivity` from optional to mandatory.

## Performance / scalability guardrails

- Runtime class: `background` for the per-tile shore-warp change;
  `boot/load` for persistence; `interactive` for the UI slider
- Target scale / density: per-tile cost is a single multiplication,
  no perf delta beyond noise; UI slider follows the existing mountain
  slider's bounds and step
- Source of truth + write owner: `WorldCore` (native) for the
  per-tile formula, `world.json` for persistence
- Dirty unit: per-tile shore-warp evaluation (already inside the
  chunk packet loop)
- Escalation path: none required; the change is a re-scaling, not
  an additional sample

## Scope — what to do

### 1. Amend the spec

Edit `docs/02_system_specs/world/lake_generation.md`:

- bump `version` and `last_updated`
- in "Status" add an "Amendment 2026-05-XX (V2 / L7)" paragraph
  documenting the new `WORLD_VERSION = 42` boundary and the
  shore-warp / persistence changes
- in "Per-Tile Classification" replace the `shore_warp` formula:
  - dimensionless FBM:
    `fbm_unit = clamp(fbm_octaves(...), -1.0, 1.0)`
    (no amplitude scaling inside `fbm_shore`)
  - per-tile basin depth:
    `basin_depth = max(epsilon, water_level - basin_min_elevation)`
  - applied warp:
    `shore_warp = fbm_unit * shore_warp_amplitude * basin_depth`
  - note: `basin_min_elevation` comes from the **chosen** lake in
    the L6 3×3 selection; the lookup and cache are unchanged
- in "Worldgen Settings" replace the `shore_warp_amplitude` row:
  - new range `[0.0, 1.0]`
  - new default `0.4`
  - description: "Доля глубины бассейна, на которую шумом
    смещается береговая линия. 0 — берег чёткий, 1 — берег
    максимально извилистый."
- in "Worldgen Settings" mark `connectivity` as a mandatory entry of
  `worldgen_settings.lakes` for `world_version >= 42`
- in `world.json` example block update `shore_warp_amplitude` to
  `0.4` and add a final comment that all six fields are mandatory
  for `world_version >= 42`
- in "Acceptance Criteria → Persistence" add a bullet: "loading a
  current-version save without `worldgen_settings.lakes.connectivity`
  fails loudly before chunk diffs are applied"
- in "WORLD_VERSION" update the active value from `41` to `42`

Edit `docs/02_system_specs/meta/save_and_persistence.md`:

- `WORLD_VERSION = 42` boundary line
- mark `worldgen_settings.lakes.connectivity` mandatory under that
  boundary

Edit `docs/02_system_specs/meta/packet_schemas.md`:

- `WORLD_VERSION = 42` boundary line; same field set, only
  per-tile output changes

### 2. Native shore-warp re-scaling

In `gdextension/src/lake_field.cpp` `fbm_shore`:

- remove amplitude scaling from the helper; return only the
  dimensionless FBM in `[-1, 1]`
- update the helper signature accordingly (drop `p_amplitude` from
  the parameter list, or keep it for API stability and ignore the
  argument; prefer dropping it and fixing all call sites in this
  task)
- update the inline comment so the new contract is explicit

In `gdextension/src/world_core.cpp` per-tile lake branch (and any
other call site that uses `fbm_shore`):

- compute `basin_depth = max(0.0001f, water_level -
  basin_min_elevation)` for the chosen lake (already available via
  the L6 selection plus the existing
  `world_prepass_lake_basin_min_elevation_` cache)
- compute `shore_warp = fbm_unit * shore_warp_amplitude *
  basin_depth`
- the rest of the comparison and shallow/deep classification is
  unchanged
- update any spawn-side use of `fbm_shore` (e.g., the spawn
  resolver in `world_prepass.cpp` if it uses the same helper) to
  the new formula so spawn and chunk packet stay consistent

### 3. Settings, defaults, persistence

- `core/resources/lake_gen_settings.gd`:
  - keep `shore_warp_amplitude` exported, change range to
    `[0.0, 1.0]`, default `0.4`
- `data/balance/lake_gen_settings.tres`:
  - `shore_warp_amplitude = 0.4`
  - `connectivity = 0.4` (already added in L5; confirm)
- `core/autoloads/save_collectors.gd`, `save_appliers.gd`,
  `save_io.gd`: extend the `worldgen_settings.lakes` collector and
  applier to include `connectivity` exactly as the other five
  fields, with the same validation pattern. Loading must fail
  loudly when `connectivity` is missing under
  `WORLD_VERSION >= 42`.
- `core/systems/world/world_streamer.gd` (and any orchestrator
  that owns `settings_packed` flatten): make sure
  `connectivity` flows from the loaded resource into
  `settings_packed[21]` on world load (no-op if L5 already routed
  it through the resource flatten; confirm and record).

### 4. New-game UI slider

In `scenes/ui/new_game_panel.tscn` and `scenes/ui/new_game_panel.gd`
(or whichever current owner is named in `world_foundation_v1.md`
"Files That May Be Touched"; do **not** scan more broadly):

- add a `СВЯЗНОСТЬ ОЗЁР` slider next to the existing lake sliders
  (logical position: just under `Зазор от гор`, before `Режим
  точной настройки`)
- bind it to `LakeGenSettings.connectivity`, range `[0.0, 1.0]`,
  step `0.05` (mirror the mountain continuity slider step)
- the slider must update the new-game preview through the existing
  preview-refresh path; do **not** introduce a new signal

### 5. Localization

In both `locale/ru/messages.po` and `locale/en/messages.po`, add:

- `UI_WORLDGEN_LAKES_CONNECTIVITY` →
  ru: `СВЯЗНОСТЬ ОЗЁР`,
  en: `LAKE CONNECTIVITY`
- `UI_WORLDGEN_LAKES_CONNECTIVITY_DESC` →
  ru: `Степень слияния соседних бассейнов в крупные связные
  системы. 0 — каждое озеро своё; 1 — единые крупные водоёмы.`,
  en: `Degree to which neighbouring basins fuse into connected lake
  systems. 0 — each basin stays separate; 1 — large unified bodies
  of water.`

Update `UI_WORLDGEN_LAKES_SHORE_WARP_AMPLITUDE_DESC` in both files
so the description matches the new "доля глубины бассейна" /
"fraction of basin depth" semantics.

### 6. WORLD_VERSION bump

- `core/systems/world/world_runtime_constants.gd`: `WORLD_VERSION`
  advances from `41` to `42`

## Scope — what NOT to do

- do not introduce any new substrate field
- do not extend `ChunkPacketV1`
- do not change basin solve / merge from L5
- do not change the 3×3 selection rule from L6
- do not refactor existing settings-packed indices
- do not change `ChunkDiffV0` shape
- do not bump `WORLD_VERSION` past `42`
- do not add additional UI sliders beyond `connectivity`
- do not redesign the new-game panel layout
- do not localise to languages other than `ru` and `en`
- do not modify `mountain_field` internals
- do not introduce a GDScript fallback

## Files that may be touched

### Modified
- `docs/02_system_specs/world/lake_generation.md`
- `docs/02_system_specs/meta/packet_schemas.md`
- `docs/02_system_specs/meta/save_and_persistence.md`
- `core/resources/lake_gen_settings.gd`
- `data/balance/lake_gen_settings.tres`
- `core/systems/world/world_runtime_constants.gd`
- `core/systems/world/world_streamer.gd` (only if confirmation
  reveals the flatten path needs an update)
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `core/autoloads/save_io.gd`
- `scenes/ui/new_game_panel.tscn`
- `scenes/ui/new_game_panel.gd`
- `gdextension/src/lake_field.h`
- `gdextension/src/lake_field.cpp`
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_prepass.cpp` (only if its spawn
  pre-screen calls `fbm_shore`; mirror the formula change)
- `locale/ru/messages.po`
- `locale/en/messages.po`

## Files that must NOT be touched

- `gdextension/src/world_prepass.h` (Snapshot field set is frozen)
- `core/systems/world/chunk_view.gd`
- `core/systems/world/world_tile_set_factory.gd`
- `core/systems/world/terrain_presentation_registry.gd`
- `core/systems/world/world_foundation_palette.gd`
- `gdextension/src/mountain_field.{h,cpp}`
- any building / power / combat / fauna / progression / lore
  system
- any other UI scene than the new-game panel

## Acceptance tests

- [ ] Static check: `WorldRuntimeConstants.WORLD_VERSION == 42`.
- [ ] Static check: `LakeGenSettings.shore_warp_amplitude` range is
      `[0.0, 1.0]` with default `0.4`;
      `data/balance/lake_gen_settings.tres` carries that value.
- [ ] Static check: `fbm_shore` returns the dimensionless FBM
      (no amplitude multiplication inside the helper);
      callers compute `shore_warp = fbm_unit *
      shore_warp_amplitude * basin_depth`.
- [ ] Static check: `worldgen_settings.lakes` collector / applier
      reads and writes all six fields including `connectivity`;
      missing `connectivity` under `WORLD_VERSION >= 42` triggers a
      loud failure before chunk diffs.
- [ ] Static check: new-game panel exposes a
      `UI_WORLDGEN_LAKES_CONNECTIVITY` slider bound to
      `LakeGenSettings.connectivity`; both `ru` and `en` locale
      files have the matching strings.
- [ ] Determinism (smoke test or manual): same
      `(seed, world_version, world_bounds, settings_packed)`
      produces bit-identical chunk packets across two builds; the
      regression test under
      `tools/lake_generation_regression_smoke_test.gd` passes.
- [ ] Visual (manual human verification required): on a fixed seed
      with a tiny basin and a large basin, the shoreline FBM is
      visually proportional to basin depth (no longer washes out
      tiny basins, no longer disappears on huge basins).
- [ ] Save/load round-trip (manual or smoke test): a new world
      created with `connectivity = 0.7`, saved, loaded, and resumed
      retains the same lake layout; `world.json` contains
      `worldgen_settings.lakes.connectivity = 0.7`.
- [ ] Performance: median chunk packet time on `large` preset is
      not measurably worse than post-L6.
- [ ] Canonical docs (grep): every change above is reflected in
      `lake_generation.md`, `save_and_persistence.md`,
      `packet_schemas.md`; line numbers in the closure report.
- [ ] `system_api.md` grep: no public API change required for L7;
      include the grep result in the closure report.

## Result format

Closure report following the format from `WORKFLOW.md`. Mandatory
sections as in L5 / L6. `not required` lines must be backed by
grep evidence.

After L7 closure, V2 lake generation is feature-complete; no
further iterations are planned for this amendment.
