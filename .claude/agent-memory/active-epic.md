# Epic: Natural World Generation Overhaul

**Spec**: `docs/02_system_specs/world/natural_world_generation_overhaul.md`
**Active constructive replacement**: `docs/02_system_specs/world/natural_world_constructive_runtime_spec.md`
**Started**: 2026-04-02
**Current iteration**: Constructive Iteration 9 in progress on 2026-04-09. Scope: finish native terrain/variation migration to `WorldPrePass`, remove the remaining directed-band structure system, delete legacy balance knobs/bridge params, and close docs/proof so runtime has one authoritative world-truth path.
**Total iterations**: Phase 1 steps 1.1-1.17 + constructive runtime activation Iterations 1-9

## 2026-04-04 Direction reset (critical)

The user explicitly rejected the old Phase 2 direction.

Do not resume or reintroduce any of the following in runtime bootstrap:
- `validate_landmarks()` as a new-game gate
- remediation loops with repeated full `WorldPrePass.compute()`
- wow-region detection in bootstrap
- threshold soft-fix per seed
- reroll / neighboring-seed search
- hot-path `sample_all() -> Dictionary`

New non-negotiable principle for future work:
- мир нужно строить по уму, а не искать случайно красивый вариант
- seed не должен проходить post-hoc beauty filter
- world quality must come from a constructive macro-skeleton, then deterministic derivation of ridges / rivers / climate
- runtime boot must build one deterministic world for the requested seed and stop

Historical notes below may mention Phase 2 landmark grammar as if it were valid. Treat that content as deprecated history only, not as an implementation plan.

## 2026-04-04 Constructive runtime replacement

Новый исполнимый план лежит в:

- `docs/02_system_specs/world/natural_world_constructive_runtime_spec.md`

Что делать дальше:

1. открыть curated read surface pre-pass и visual proof через `WorldLab`
2. переключить `sample_structure_context()` на pre-pass truth
3. довести `SurfaceTerrainResolver` до constructive terrain placement
4. расширить `BiomeData` и biome resources
5. перевести `BiomeResolver` на causal channels
6. ввести `BiomeResult` top-2 + `ecotone_factor`
7. подключить экотоны к flora / local variation / terrain
8. довести native parity
9. удалить legacy band path и дочистить balance/docs

Новый критерий прогресса:

- после каждой видимой итерации должен быть fixed-seed visual proof в `WorldLab`
- мир должен становиться красивее за счёт структуры и причинности, а не за счёт reroll/bootstrap filtering

## Documentation debt

- [ ] `DATA_CONTRACTS.md` — keep the `World Pre-pass` layer and read-contract text aligned whenever pre-pass channels stop being internal scaffolding.
- [ ] `PUBLIC_API.md` — update if `WorldPrePass` gains new safe entrypoints for external runtime callers.
- **Deadline**: review every iteration; update immediately on semantic drift.
- **Latest review**: constructive Iteration 8 grep-checked `WorldGenerator.resolve_biome`, `WorldComputeContext.resolve_biome`, `ChunkGenerator.initialize`, `biome_continental_drying_factor`, and `biome_drainage_moisture_bonus`; `DATA_CONTRACTS.md` and `PUBLIC_API.md` were updated in the same task because the sanctioned native bridge now consumes a serialized pre-pass snapshot and public biome reads no longer bypass the compute-context path.
- **Status**: reviewed through constructive Iteration 8; Iterations 1-2, 5, and 8 updated canonical docs, while Iterations 3-4 and 6-7 remained internal/derived/result-surface work and grep confirmed no new canonical updates were required.

## 2026-04-05 Perf follow-up

- Added staged world-init orchestration in `WorldGenerator`: `begin_initialize_world_async()` + `is_initialize_world_pending()` + `complete_pending_initialize_world()`.
- Intent: stop paying the entire `WorldPrePass.compute()` cost synchronously before the `GameWorld` scene can take ownership; keep publication as one deterministic snapshot on the main-thread completion step.
- Canonical docs updated in the same task because this introduced new sanctioned lifecycle entrypoints and changed the pre-pass publish semantics from sync-only to sync-or-staged.
- Latest proof artifacts:
  - `debug_exports/perf/boot_seed12345_postfix5_summary.md`
  - `debug_exports/perf/runtime_far_loop_postfix5_seed12345_summary.md`
- 2026-04-05 phase breakdown follow-up:
  - `WorldPrePass.compute()` now records nested subphase timings for `lake_aware_fill`, `river_extraction`, and `continentalness`, and `tools/perf_log_summary.gd` now surfaces those timings in the sanctioned summary artifact.
  - Latest artifact: `debug_exports/perf/boot_seed12345_postfix6_summary.md`
  - Current hottest subphases on fixed seed `12345`: `river_extraction.distance_propagation` (`1917.15 ms`), `continentalness.distance_propagation` (`1547.13 ms`), `lake_aware_fill.priority_flood` (`1084.76 ms`), with `lake_aware_fill.extract_lake_records` (`617.73 ms`) as the next contributor.
  - First native/worker candidate should be the shared distance/flood wavefront kernel family, starting with `river_extraction.distance_propagation`; the measured hotspot is pure-data, detached from runtime publication, and larger than the lake-record classification tail.
- 2026-04-05 native kernel follow-up:
  - Added `WorldPrePassKernels` GDExtension with shared pure-data kernels for wrapped distance propagation and lake priority flood, wired behind `WorldPrePass` with GDScript fallback retained.
  - Tightened chunk publication so `Chunk.is_first_pass_ready()` no longer treats terrain-only completion as visible-ready; streamed chunks stay hidden until cover phase closes, preventing transient green terrain-only publication.
  - Latest sanctioned boot artifact: `debug_exports/perf/boot_seed12345_postfix9_summary.md`
  - Latest sanctioned runtime artifact: `debug_exports/perf/runtime_far_loop_postfix9_seed12345_summary.md`
  - Fixed-seed `12345` boot proof now shows `WorldGenerator._setup_world_pre_pass.compute = 4582.27 ms` (down from `9185.35 ms` in `postfix6`), with native subphases at `river_extraction.distance_propagation = 5.03 ms`, `continentalness.distance_propagation = 5.57 ms`, and `lake_aware_fill.priority_flood = 5.13 ms`.
  - Runtime far-loop proof on the same seed improved over the last pre-native sanctioned baseline (`postfix6`) from `avg=14.60 / p99=33.80 / hitches=20` to `avg=12.30 / p99=28.10 / hitches=12`, and `ChunkManager.try_harvest_at_world` warnings dropped out of the summary. Topology and first-pass runtime visual budget remain the next blockers.
- Current status: the dominant `WorldPrePass` bottleneck is no longer hydrology distance propagation; the remaining boot/runtime debt is now centered on `rain_shadow`, `flow_accumulation`, `flow_directions`, boot apply > `8.0 ms`, and runtime topology / near first-pass visual catch-up.
- 2026-04-05 publication/acceptance reset:
  - Product requirement tightened: player-visible world handoff must not occur while chunks, flora, or shadows are still visibly building on screen.
  - Canonical docs now reject perf-only wins when the player can still catch green/raw chunks or incomplete near-world presentation.
  - `ChunkManager` internal `first_playable` remains a boot-finalization milestone, but `GameWorld` player handoff now waits for the fully-ready boot milestone.

## Iterations

### Constructive Iteration 1 — Curated Pre-pass Read Surface And Visual Proof
**Status**: completed
**Started**: 2026-04-04
**Completed**: 2026-04-04

#### Acceptance tests
- [x] `WorldComputeContext` safe sampler exists — verified by `Select-String` in `core/systems/world/world_compute_context.gd` (lines 66-75)
- [x] `WorldPrePass.sample()` / `get_grid_value()` expose `floodplain_strength`, `river_distance`, `river_width` — verified by `Select-String` in `core/systems/world/world_pre_pass.gd` (lines 30-32, 213-231, 258-278)
- [x] `WorldLab` wires `Terrain`, `Biome`, `Drainage`, `Ridges`, `Climate` and has no runtime chunk bootstrap calls — verified by `Select-String` hits in `scenes/ui/world_lab.gd` plus `0 matches` for `ChunkManager|boot_load_initial_chunks|_load_chunk(`
- [x] No new `sample_all() -> Dictionary` hot-path API — verified by `Select-String` across touched code files: `0 matches`
- [x] Fixed-seed screenshot proof — passed (manual visual confirmation from user on 2026-04-04)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `sample_prepass_channels|WorldPrePassChannels|river_width|river_distance|floodplain_strength` — matches at lines 95, 97, 197-198, 207-209, 225-228, 255, 260
- [x] Grep `PUBLIC_API.md` for `sample_prepass_channels|WorldPrePassChannels|river_width|river_distance|floodplain_strength` — matches at lines 618 and 625
- [x] Documentation debt section reviewed — spec lines 232-235 require both canonical docs; both updated in this iteration

#### Files touched
- `core/systems/world/world_pre_pass.gd` — expanded curated read channels
- `core/systems/world/world_compute_context.gd` — added `sample_prepass_channels(world_pos)`
- `core/systems/world/world_pre_pass_channels.gd` — new typed container
- `scenes/ui/world_lab.gd` — added `Drainage` / `Ridges` / `Climate` preview modes
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — updated pre-pass read contract
- `docs/00_governance/PUBLIC_API.md` — documented new safe sampler and channel list
- `.claude/agent-memory/active-epic.md` — tracking updated

#### Closure report
Implemented Iteration 1 code and doc work for the curated pre-pass read surface and WorldLab visual proof pipeline. Static/code-side proof was captured in-session; fixed-seed visual proof was confirmed manually by the user on 2026-04-04.

#### Blockers
- none

---

### 2026-04-09 — Native world-generation de-legacy migration
**Status**: completed

#### What changed
- Removed the old directed-band native structure stage from `gdextension/src/chunk_generator.{h,cpp}` and kept only pre-pass-backed structure semantics.
- `WorldPrePass` now exports the authoritative native snapshot for initialization, and runtime `ChunkGenerator.generate_chunk(...)` now fails closed unless it receives a chunk-local authoritative input snapshot from the published `WorldComputeContext` pipeline.
- `ChunkContentBuilder.build_chunk_native_data()` now assembles authoritative chunk-local inputs (`sample_world_channels` + `sample_prepass_channels` + `sample_structure_context`), passes them into native generation, tags payload provenance via `generation_source`, and keeps payload-shape validation.
- `WorldLabSampler` uses the same authoritative chunk-local snapshot path for native preview chunks.
- Removed legacy-only world balance knobs from `world_gen_balance.gd/.tres`.
- Updated public/API/contracts/spec docs so the native runtime contract explicitly requires immutable `WorldPrePass` init snapshot plus per-chunk authoritative inputs.

#### Verification
- `python -m SCons -Q --debug=stacktrace platform=windows target=template_debug` in `gdextension/` — PASS
- `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_verify_native_world_truth codex_native_truth_chunk_radius=2 codex_world_seed=12345` — PASS
  - `compared_chunks=25`
  - `compared_tiles=102400`
  - `terrain_mismatches=0`
  - `biome_mismatches=0`
  - `secondary_biome_mismatches=0`
  - `ecotone_mismatches=0`
  - `variation_mismatches=0`
  - `flora_density_mismatches=0`
  - `flora_modulation_mismatches=0`
  - `native_truth_status=PASS`
- Grep audit for legacy native helpers / balance knobs:
  - `rg -n "directed_coordinate|repeating_band\\(|sample_structure\\(|ridge_dir|ridge_secondary_dir|river_dir|ridge_spacing_tiles|ridge_core_width_tiles|ridge_feather_tiles|ridge_warp_frequency|ridge_warp_amplitude_tiles|ridge_cluster_frequency|ridge_secondary_spacing_tiles|ridge_secondary_core_width_tiles|ridge_secondary_feather_tiles|ridge_secondary_warp_frequency|ridge_secondary_warp_amplitude_tiles|ridge_secondary_weight|river_spacing_tiles|river_core_width_tiles|river_floodplain_width_tiles|river_warp_frequency|river_warp_amplitude_tiles|hot_evaporation_rate" gdextension/src/chunk_generator.cpp gdextension/src/chunk_generator.h core/autoloads/world_generator.gd scenes/ui/world_lab.gd data/world/world_gen_balance.gd data/world/world_gen_balance.tres` — no matches

#### Remaining blockers
- none

---

### Constructive Iteration 8 — Native Path Parity
**Status**: completed
**Started**: 2026-04-08
**Completed**: 2026-04-08

#### Acceptance tests
- [x] `WorldGenerator._build_generator_params()` exports causal biome fields and causal balance knobs for native init. — verified by `rg` in `core/autoloads/world_generator.gd` (lines 562, 623-675)
- [x] Native `ChunkGenerator` consumes `drainage`, `slope`, `rain_shadow`, `continentalness`, and `effective_moisture` in biome match/score resolution. — verified by `rg` in `gdextension/src/chunk_generator.{h,cpp}` (range/weight definitions at header lines 31-49 and cpp lines 237-262; causal match/score path at cpp lines 607-773)
- [x] Public `WorldGenerator.resolve_biome()` no longer calls the legacy `_biome_resolver.resolve_biome()` shortcut and now routes through `WorldComputeContext.resolve_biome()`. — verified by `rg` in `core/autoloads/world_generator.gd` (lines 231-240) and `0 matches` for `_biome_resolver.resolve_biome`
- [x] Canonical docs reflect the new native pre-pass bridge and authoritative public biome-read path. — verified by `rg` in `docs/02_system_specs/world/DATA_CONTRACTS.md` and `docs/00_governance/PUBLIC_API.md` (matches at lines 99-100, 201, and 634 after update)
- [x] Fixed-seed authoritative biome proof artifact captured through a sanctioned path. — verified by headless `GameWorldDebug` proof driver with `codex_export_ecotone_proof codex_world_seed=12345`; output saved to `debug_exports/world_previews/seed_12345_local_288_-352_r16_1775657535_x4_{biomes,terrain,structures,ecotone,vegetation}.png` plus log `debug_exports/world_previews/biome_seed12345_authoritative.log`
- [x] Fixed-seed native biome parity proof captured through a sanctioned path. — verified after successful `python -m SCons -Q --debug=stacktrace platform=windows target=template_debug`: headless compare reused existing `WorldLabSampler` from `scenes/ui/world_lab.gd` and saved log `debug_exports/world_previews/native_vs_script_seed12345_worldlab.log`, which reports `COARSE_BIOME_MISMATCHES=0` across `8192` coarse samples and `HOTSPOT_BIOME_MISMATCHES=0` across the `seed_12345_local_288_-352_r16...` hotspot window

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `WorldGenerator.resolve_biome|WorldComputeContext.resolve_biome|ChunkGenerator.initialize|biome_continental_drying_factor|biome_drainage_moisture_bonus` — matches at lines 99-100 and 201; updated where semantics changed
- [x] Grep `PUBLIC_API.md` for `WorldGenerator.resolve_biome|WorldComputeContext.resolve_biome|ChunkGenerator.initialize|biome_continental_drying_factor|biome_drainage_moisture_bonus` — match at line 634 for `ChunkGenerator.initialize`; `0 matches` for the others, so no additional public doc text existed to update
- [x] Documentation debt section reviewed — Iteration 8 spec requires updating both canonical docs; completed in this task

#### Files touched
- `core/autoloads/world_generator.gd` — native biome params/pre-pass snapshot export and public biome-read routing through compute context
- `gdextension/src/chunk_generator.h` — native causal biome/pre-pass config state and helper declarations
- `gdextension/src/chunk_generator.cpp` — native causal biome matching/scoring, effective moisture, pre-pass-backed structure sampling, and parity tie-break/fallback behavior
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — documented authoritative public biome path and native pre-pass snapshot reader semantics
- `docs/00_governance/PUBLIC_API.md` — documented the expanded `ChunkGenerator.initialize()` bridge surface
- `.claude/agent-memory/active-epic.md` — tracked Iteration 8 status, docs, proof, and blocker

#### Closure report
completed for the biome-parity scope: implementation, canonical doc updates, authoritative script proof, native rebuild, and fixed-seed native-vs-script biome compare all completed in this session. Terrain parity still shows large mismatches and remains outside this bugfix's accepted scope.

#### Blockers
- none for the biome-resolution task. Separate broader Iteration 8 terrain parity work remains open.

---

### Constructive Iteration 9 — Legacy Band Cleanup And Balance Closure
**Status**: in_progress
**Started**: 2026-04-09
**Completed**: —

#### Acceptance tests
- [ ] `generate_chunk()` no longer calls the legacy structure stage and native terrain/variation no longer depend on directed-band formulas.
- [ ] `gdextension/src/chunk_generator.{h,cpp}` no longer contain active `directed_coordinate`, `repeating_band`, `sample_structure`, `ridge_dir`, `ridge_secondary_dir`, or `river_dir` structure plumbing.
- [ ] `WorldGenerator` / `WorldLab` native bridge no longer exports legacy-only ridge/river band params, and `WorldGenBalance(.tres)` no longer carry dead knobs for the removed structure system.
- [ ] Fixed-seed script/native proof shows the same authoritative terrain/structure world truth after the cleanup.
- [ ] Canonical docs describe `WorldPrePass` as the single runtime source of truth with no active dual-path legacy notes.

#### Doc check
- [ ] Grep `DATA_CONTRACTS.md` for the final changed names and update ownership/read semantics where they drift.
- [ ] Grep `PUBLIC_API.md` for the final changed names and remove legacy native bridge surface if it is no longer sanctioned.
- [ ] Documentation debt section reviewed — Iteration 9 requires updates to both canonical docs.

#### Files touched
- `gdextension/src/chunk_generator.h` — audit confirms legacy directed-band helpers, directions, and params still exist and must be removed after pre-pass migration lands.
- `gdextension/src/chunk_generator.cpp` — audit confirms `generate_chunk()` still runs `sample_channels() -> sample_structure() -> resolve_biome() -> resolve_variation() -> resolve_terrain()`.
- `core/autoloads/world_generator.gd` — audit confirms native init still exports legacy ridge/river band params alongside the pre-pass snapshot.
- `scenes/ui/world_lab.gd` — audit confirms native proof bridge still forwards the same legacy param set into standalone native generator requests.
- `data/world/world_gen_balance.gd` / `data/world/world_gen_balance.tres` — audit confirms legacy-only ridge/river band knobs still exist.
- `docs/02_system_specs/world/native_chunk_generation_spec.md` — audit confirms canonical native spec still documents the legacy directed-band structure stage as active architecture.
- `.claude/agent-memory/active-epic.md` — Iteration 9 tracking started.

#### Closure report
pending

#### Blockers
- none
### Constructive Iteration 2 — Switch Structure Truth To `WorldPrePass`
**Status**: completed
**Started**: 2026-04-04
**Completed**: 2026-04-04

#### Acceptance tests
- [x] `WorldComputeContext.sample_structure_context()` больше не вызывает band/noise structure sampling. — verified by `rg`: `func sample_structure_context` exists in `core/systems/world/world_compute_context.gd` and `_structure_sampler.sample_structure_context` returns `0 matches`
- [x] `ridge_strength`, `mountain_mass`, `river_strength`, `floodplain_strength` в `WorldStructureContext` происходят из `WorldPrePass`. — verified by `rg` in `core/systems/world/world_compute_context.gd` (lines 67-72 show `WorldPrePass.*CHANNEL` reads plus `_derive_river_strength_from_prepass()`)
- [x] `river_distance` и `river_width` доступны runtime consumers через `WorldStructureContext`. — verified by `rg` in `core/systems/world/world_structure_context.gd` (lines 11-12, 19-20) and `core/systems/world/world_compute_context.gd` (lines 70-71)
- [ ] В `WorldLab` terrain preview для fixed seed set больше нет доминирования почти параллельных river/ridge band'ов через весь мир. — BLOCKED: requires manual `WorldLab` visual proof in Godot; `Get-Command godot, godot4, gdformat, gdlint` returned command-not-found for all four tools in this environment
- [x] requested seed создаёт один world snapshot без reroll/remediation. — verified by `rg` in `core/autoloads/world_generator.gd`: single pre-pass compute at line 395 and `0 matches` for `validate_landmarks|effective_seed|reroll|remediation`; `scenes/ui/world_lab.gd` also forces `"use_native": false` at line 651 for the constructive proof path

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `sample_structure_context` matches at lines 98, 199, 253, 262; `river_distance|river_width` remain documented at lines 95, 97, 98, 198, 208-209, 226-227, 257
- [x] Grep `PUBLIC_API.md` for changed names — `sample_structure_context` / `WorldStructureContext` / `river_distance|river_width` now match at lines 623-630
- [x] Documentation debt section reviewed — spec Iteration 2 `Required updates` at lines 283-286 requires `DATA_CONTRACTS.md` and conditionally `PUBLIC_API.md`; both updated in this task because the sanctioned structure-truth sampling path changed

#### Files touched
- `core/systems/world/world_compute_context.gd` — `sample_structure_context()` now reads structural truth from `WorldPrePass`, and `river_strength` is derived from sampled pre-pass river metrics
- `core/systems/world/world_structure_context.gd` — added `river_distance` / `river_width` fields and non-negative clamps for tile-space river metrics
- `scenes/ui/world_lab.gd` — constructive proof path now stays on GDScript (`"use_native": false`) so Iteration 2 visuals reflect the migrated script-side structure truth
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — documented `sample_structure_context()` as a pre-pass-backed reader and updated the pre-pass read surface / invariants
- `docs/00_governance/PUBLIC_API.md` — documented the sanctioned `sample_structure_context()` entrypoint and refreshed curated pre-pass channel list
- `.claude/agent-memory/active-epic.md` — tracked Iteration 2 start, proof status, and blocker

#### Closure report
## Closure Report

### Implemented
- Rewrote `WorldComputeContext.sample_structure_context()` so GDScript runtime structure truth comes from the published `WorldPrePass` instead of `LargeStructureSampler` band/noise sampling.
- Expanded `WorldStructureContext` with `river_distance` and `river_width`, and derived runtime `river_strength` from sampled pre-pass river metrics.
- Forced `WorldLab` constructive proof to stay on the GDScript path for this iteration so native legacy structure logic does not mask the script-side migration before Iteration 8.
- Updated `DATA_CONTRACTS.md` and `PUBLIC_API.md` to reflect the new source of truth and sanctioned structure-sampling facade.

### Root cause
- `WorldPrePass` already authored the real large-scale river/ridge/mountain fields, but `WorldComputeContext.sample_structure_context()` still delegated to the old `LargeStructureSampler`, leaving a second world-truth path in the runtime and making terrain consumers continue to read band-shaped structures instead of the constructive pre-pass result.

### Files changed
- `core/systems/world/world_compute_context.gd` — migrated structure sampling to `WorldPrePass`.
- `core/systems/world/world_structure_context.gd` — added pre-pass river metrics to the structure context object.
- `scenes/ui/world_lab.gd` — pinned constructive proof to the GDScript path for this stage.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — updated structure-context/pre-pass reader contract.
- `docs/00_governance/PUBLIC_API.md` — documented the new sanctioned structure-sampling entrypoint.
- `.claude/agent-memory/active-epic.md` — iteration tracking updated.

### Acceptance tests
- [x] `sample_structure_context()` no longer calls band/noise structure sampling — passed (`rg` shows `0 matches` for `_structure_sampler.sample_structure_context`)
- [x] `ridge_strength`, `mountain_mass`, `river_strength`, `floodplain_strength` now come from `WorldPrePass`-backed sampling — passed (`rg` shows `WorldPrePass.*CHANNEL` reads plus `_derive_river_strength_from_prepass()` in `world_compute_context.gd`)
- [x] `river_distance` and `river_width` are present on `WorldStructureContext` and populated by the compute context — passed (`rg` in `world_structure_context.gd` and `world_compute_context.gd`)
- [ ] Fixed-seed `WorldLab` terrain preview no longer shows dominating parallel bands — BLOCKED (manual Godot visual proof required; CLI tools unavailable)
- [x] requested seed creates one world snapshot without reroll/remediation — passed (`world_generator.gd` shows a single pre-pass compute at line 395 and `0 matches` for reroll/remediation keywords)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `sample_structure_context`: matches at lines 98, 199, 253, 262 — updated
- Grep `DATA_CONTRACTS.md` for `river_distance|river_width`: matches at lines 95, 97, 98, 198, 208-209, 226-227, 257 — updated/still accurate
- Grep `PUBLIC_API.md` for `sample_structure_context|WorldStructureContext|river_distance|river_width`: matches at lines 623-630 — updated
- Section `Required updates` in spec: exists at lines 283-286 — completed in this task because Iteration 2 changes the structure-context reader contract and sanctioned structure-sampling entrypoint

### Out-of-scope observations
- `LargeStructureSampler` still exists as compatibility ballast in the repository, but `WorldComputeContext.sample_structure_context()` no longer uses it as world truth.
- Native chunk generation remains on its own path until Iteration 8; this iteration only ensures that the proof harness and GDScript runtime stop reading legacy band structure.

### Remaining blockers
- Manual fixed-seed `WorldLab` visual proof in Godot is still required to close the visible acceptance criterion for this iteration.

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `sample_structure_context`, `river_distance`, and `river_width`

### PUBLIC_API.md updated
- updated — grep evidence recorded above for `sample_structure_context`, `WorldStructureContext`, `river_distance`, and `river_width`

#### Blockers
- Manual `WorldLab` visual proof remains blocked: `godot.exe` is available, but this session did not find an existing non-interactive `WorldLab` screenshot/export path in the repository, and workflow does not allow inventing a new validation harness without explicit approval.

### Constructive Iteration 3 — Constructive Surface Terrain Resolution
**Status**: blocked
**Started**: 2026-04-04
**Completed**: —

#### Acceptance tests
- [x] `SurfaceTerrainResolver` uses pre-pass-derived `river_width` / `river_distance` / `floodplain_strength`. — verified by `rg` in `core/systems/world/surface_terrain_resolver.gd` (lines 354-400, 445-510)
- [ ] river tiles visually expand downstream instead of staying near-constant width. — BLOCKED: code now derives river core radius from `river_width` and `river_distance` (lines 347-359, 445-472), but visible proof still requires manual `WorldLab` screenshots
- [ ] bank / floodplain tiles stay near river corridors instead of broad parallel noise stripes. — BLOCKED: code now gates bank/floodplain classification by `river_distance` and a bounded outer radius (lines 361-377, 477-515), but visible proof still requires manual `WorldLab` screenshots
- [x] mountain placement depends on ridge families and slope-aware carving rather than old threshold mixes alone. — verified by `rg` in `core/systems/world/surface_terrain_resolver.gd` (lines 380-400, 517-579 show slope-aware mountain core / foothill carve helpers)
- [ ] fixed-seed screenshots show noticeable terrain change before vs after Iteration 3. — BLOCKED: requires manual `WorldLab` screenshot capture in Godot

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `_resolve_surface_terrain_sq` matches at line 637 and remains accurate; `rg` for `_is_river_core_tile_sq|_is_bank_floodplain_tile_sq|_is_mountain_core_tile_sq|_is_foothill_tile_sq|populate_chunk_build_data` returned no new stale contract text besides the existing `_resolve_surface_terrain_sq` note
- [x] Grep `PUBLIC_API.md` for changed names — `populate_chunk_build_data` matches at line 664 and remains accurate; new helper names return `0 matches`
- [x] Documentation debt reviewed against Iteration 3 `Required updates` — spec lines 339-342 say canonical docs update only if payload/read semantics or caller-facing API changed; this iteration stayed inside `SurfaceTerrainResolver` internals and grep found no stale public docs to update

#### Files touched
- `core/systems/world/surface_terrain_resolver.gd` — terrain classification moved to constructive river core / bank / mountain core / foothill-carve helpers, with polar modifiers kept as overlay
- `.claude/agent-memory/active-epic.md` — iteration tracking updated
- `data/world/world_gen_balance.gd` / `core/systems/world/tile_gen_data.gd` / `core/systems/world/chunk_content_builder.gd` — not changed (`git diff --name-only` returned no output)

#### Closure report
pending manual `WorldLab` visual proof; static/code-side verification completed in this session

#### Blockers
- Manual `WorldLab` screenshot proof in Godot is still required for the visible Iteration 3 acceptance tests; `godot.exe` is available, but no existing non-interactive `WorldLab` export path was found in this session.
- Constructive Iteration 2 still lacks its own manual fixed-seed `WorldLab` visual proof; user explicitly requested moving ahead with Iteration 3 implementation while that proof remains outstanding.

### Constructive Iteration 4 — Biome Schema Expansion
**Status**: completed
**Started**: 2026-04-04
**Completed**: 2026-04-04

#### Acceptance tests
- [x] All biome resources load with the new fields without errors. — verified by `godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1` (exit code `0`, no parse/load errors) plus `rg` over `data/biomes/` showing every biome resource now declares the new ranges and weights
- [x] With `*_weight = 0.0`, the new channels do not affect the final score. — verified by `rg` in `data/biomes/biome_data.gd` (line 143) and `gdextension/src/chunk_generator.cpp` (lines 550-552): both scorers still use only the old structure keys/weights, so the new schema stays inert
- [x] `WorldLab` and biome debug/native dumps do not lose the new fields during serialization. — verified by `rg` in `scenes/ui/world_lab.gd` (lines 924-947) and `gdextension/src/chunk_generator.{h,cpp}` (header lines 31-49, parser lines 205-230)
- [x] Fixed-seed set before and after Iteration 4 yields the same biome winners with zeroed new weights. — verified statically: `WorldLab` constructive proof remains on GDScript (`"use_native": false` at `scenes/ui/world_lab.gd:651`), and both GDScript/native scorer key lists remain unchanged, so identical seeds still resolve identical winners

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `0 matches` for `min_drainage|max_drainage|min_slope|max_slope|min_rain_shadow|max_rain_shadow|min_continentalness|max_continentalness|drainage_weight|slope_weight|rain_shadow_weight|continentalness_weight`
- [x] Grep `PUBLIC_API.md` for changed names — `0 matches` for `min_drainage|max_drainage|min_slope|max_slope|min_rain_shadow|max_rain_shadow|min_continentalness|max_continentalness|drainage_weight|slope_weight|rain_shadow_weight|continentalness_weight`
- [x] Documentation debt section reviewed — spec Iteration 4 `Required updates` (lines 382-385 and summary line 617) says canonical docs are not required by default; grep confirmed the new schema is not yet referenced there

#### Files touched
- `data/biomes/biome_data.gd` — added causal schema ranges and zero-default weights
- `data/biomes/cold_zone_biome.tres` — serialized the new schema with backward-compatible defaults
- `data/biomes/foothills_biome.tres` — serialized the new schema with backward-compatible defaults
- `data/biomes/mountains_biome.tres` — serialized the new schema with backward-compatible defaults
- `data/biomes/plains_biome.tres` — serialized the new schema with backward-compatible defaults
- `data/biomes/scorched_biome.tres` — serialized the new schema with backward-compatible defaults
- `data/biomes/wet_lowland_biome.tres` — serialized the new schema with backward-compatible defaults
- `scenes/ui/world_lab.gd` — extended biome definition export with the new schema fields while keeping the constructive proof path on GDScript
- `gdextension/src/chunk_generator.h` — extended native `BiomeDef` storage with the new schema fields
- `gdextension/src/chunk_generator.cpp` — extended native biome-definition parsing with the new schema fields
- `.claude/agent-memory/active-epic.md` — iteration tracking updated

#### Closure report
## Closure Report

### Implemented
- Expanded `BiomeData` with causal schema ranges for `drainage`, `slope`, `rain_shadow`, and `continentalness`, plus zero-default weights for each.
- Updated every surface biome resource to serialize the new schema explicitly with backward-compatible defaults.
- Extended `WorldLab` biome-definition export and the native biome bridge so the new fields survive tooling/native serialization without changing current winner selection.

### Root cause
- The constructive runtime plan needed new biome metadata before causal scoring could land, but the repository still only serialized the legacy channel/structure schema. Without this schema pass, Iteration 5 would need to mix data-model migration with resolver behavior changes and would risk hidden serialization drift between GDScript tooling and the native bridge.

### Files changed
- `data/biomes/biome_data.gd` — schema expansion only; no scoring behavior change.
- `data/biomes/*.tres` — all six biome resources now declare the new fields explicitly.
- `scenes/ui/world_lab.gd` — biome export now includes the new schema fields.
- `gdextension/src/chunk_generator.h` / `gdextension/src/chunk_generator.cpp` — native bridge now stores/parses the new schema fields.
- `.claude/agent-memory/active-epic.md` — progress tracking updated.

### Acceptance tests
- [x] All biome resources load with the new fields without errors. — passed (`godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1`, exit code `0`; `rg` also shows the new fields in all six biome `.tres`)
- [x] With `*_weight = 0.0`, the new channels do not affect the final score. — passed (`rg` shows unchanged scorer key lists in `data/biomes/biome_data.gd:143` and `gdextension/src/chunk_generator.cpp:550-552`)
- [x] `WorldLab` and biome debug/native dumps do not lose the new fields during serialization. — passed (`rg` shows export lines in `scenes/ui/world_lab.gd:924-947` and native storage/parser lines in `gdextension/src/chunk_generator.h:31-49` plus `gdextension/src/chunk_generator.cpp:205-230`)
- [x] Fixed-seed set before and after Iteration 4 yields the same biome winners with zeroed new weights. — passed by static proof (`scenes/ui/world_lab.gd:651` keeps constructive proof on GDScript, and both scorers still use the same old winner inputs/weights)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `min_drainage|max_drainage|min_slope|max_slope|min_rain_shadow|max_rain_shadow|min_continentalness|max_continentalness|drainage_weight|slope_weight|rain_shadow_weight|continentalness_weight`: `0 matches` — not referenced
- Grep `PUBLIC_API.md` for `min_drainage|max_drainage|min_slope|max_slope|min_rain_shadow|max_rain_shadow|min_continentalness|max_continentalness|drainage_weight|slope_weight|rain_shadow_weight|continentalness_weight`: `0 matches` — not referenced
- Section `Required updates` in spec: exists at lines 382-385 and summary line 617 — reviewed; not applicable because this iteration stayed on biome resource schema/serialization and did not change caller-facing API or world-layer ownership

### Out-of-scope observations
- Constructive Iterations 2 and 3 still need their manual fixed-seed `WorldLab` screenshot proof; this schema-only iteration did not change that status.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- not required — grep confirmed `0 matches` for the new schema names

### PUBLIC_API.md updated
- not required — grep confirmed `0 matches` for the new schema names

#### Blockers
- none

### 2026-04-04 Hard milestone — single authoritative GDScript structure path
**Status**: completed
**Started**: 2026-04-04
**Completed**: 2026-04-04

#### Acceptance tests
- [x] `WorldPrePass -> WorldComputeContext.sample_structure_context() -> SurfaceTerrainResolver` is the only authoritative GDScript runtime path. — verified by `rg`: `WorldGenerator.sample_structure_context()` now delegates to `_compute_context.sample_structure_context(...)`, and `SurfaceTerrainResolver` reads structure only through `_world_context.sample_structure_context(...)`
- [x] GDScript runtime no longer instantiates or stores `LargeStructureSampler` in `WorldGenerator`, `WorldComputeContext`, or `WorldLab`. — verified by `rg` for `LargeStructureSampler.new|_setup_structure_sampler|_structure_sampler|_structure_sampler.sample_structure_context`: `0 matches`
- [x] Bootstrap still produces a valid compute context before first biome read. — verified by `rg` in `core/autoloads/world_generator.gd` showing the new order `current_biome = BiomeRegistry.get_default_biome()` -> `_setup_compute_context()` -> `current_biome = get_biome_at_tile(spawn_tile)` plus `_compute_context.current_biome = current_biome`
- [x] Project still loads headless after the milestone patch. — verified by `godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1` (exit code `0`)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `LargeStructureSampler|_setup_structure_sampler|_structure_sampler|WorldComputeContext.configure` — `0 matches`
- [x] Grep `PUBLIC_API.md` for `LargeStructureSampler|_setup_structure_sampler|_structure_sampler|WorldComputeContext.configure` — `0 matches`
- [x] Grep canonical docs for `sample_structure_context` — still aligned: `PUBLIC_API.md:623`; `DATA_CONTRACTS.md:98, 199, 253, 262`

#### Files touched
- `core/systems/world/world_compute_context.gd` — removed legacy structure-sampler plumbing and made `WorldPrePass` mandatory/fail-fast for GDScript structure sampling
- `core/autoloads/world_generator.gd` — removed runtime `LargeStructureSampler` ownership, routed structure reads through `_compute_context`, and reordered bootstrap so compute context exists before the first biome read
- `scenes/ui/world_lab.gd` — removed the now-dead structure-sampler configure argument
- `.claude/agent-memory/active-epic.md` — milestone tracking updated

#### Closure report
## Closure Report

### Implemented
- Removed `LargeStructureSampler` from the GDScript runtime structure path in `WorldGenerator`, `WorldComputeContext`, and `WorldLab`.
- Made `WorldGenerator.sample_structure_context()` a thin wrapper over `WorldComputeContext.sample_structure_context()`.
- Tightened `WorldComputeContext` so a published `WorldPrePass` snapshot is now required for structure sampling instead of being an optional compatibility path.
- Reordered `WorldGenerator.initialize_world()` so the compute context is created before the first biome lookup, then synchronized `current_biome` back into the already-created context/resolver.

### Root cause
- Iteration 2 had already moved `WorldComputeContext.sample_structure_context()` onto `WorldPrePass`, but the runtime still carried `LargeStructureSampler` as bootstrap plumbing in `WorldGenerator` and as an optional configure input in `WorldComputeContext`. That left a second structural authority path alive in the GDScript runtime even though terrain consumers were supposed to converge on the pre-pass-derived chain.

### Files changed
- `core/systems/world/world_compute_context.gd` — removed legacy sampler field/parameter; `WorldPrePass` is now required for authoritative GDScript structure sampling.
- `core/autoloads/world_generator.gd` — deleted runtime sampler setup/storage and switched all structure reads to `_compute_context`.
- `scenes/ui/world_lab.gd` — removed dead configure-time structure sampler plumbing.
- `.claude/agent-memory/active-epic.md` — recorded the milestone.

### Acceptance tests
- [x] `WorldPrePass -> WorldComputeContext.sample_structure_context() -> SurfaceTerrainResolver` is the only authoritative GDScript runtime path. — passed (`rg` shows `WorldGenerator.sample_structure_context()` delegating to `_compute_context`, and `SurfaceTerrainResolver` consuming `_world_context.sample_structure_context()`)
- [x] GDScript runtime no longer instantiates or stores `LargeStructureSampler` in `WorldGenerator`, `WorldComputeContext`, or `WorldLab`. — passed (`rg` for `LargeStructureSampler.new|_setup_structure_sampler|_structure_sampler|_structure_sampler.sample_structure_context` returned `0 matches`)
- [x] Bootstrap still produces a valid compute context before first biome read. — passed (`rg` confirms initialize order in `core/autoloads/world_generator.gd`)
- [x] Project still loads headless after the milestone patch. — passed (`godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1`, exit code `0`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `LargeStructureSampler|_setup_structure_sampler|_structure_sampler|WorldComputeContext.configure`: `0 matches` — not referenced
- Grep `PUBLIC_API.md` for `LargeStructureSampler|_setup_structure_sampler|_structure_sampler|WorldComputeContext.configure`: `0 matches` — not referenced
- Grep canonical docs for `sample_structure_context`: `PUBLIC_API.md:623`; `DATA_CONTRACTS.md:98, 199, 253, 262` — still accurate after the milestone because the documented authoritative path was already `WorldComputeContext.sample_structure_context()`

### Out-of-scope observations
- `core/systems/world/large_structure_sampler.gd` still exists in the repository as a legacy artifact, but it is no longer part of the GDScript runtime authority chain.
- Native parity remains an Iteration 8 concern; this milestone intentionally only hardens the GDScript runtime path.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- not required — grep confirmed `0 matches` for the removed plumbing names, and existing `sample_structure_context` contract text remains accurate

### PUBLIC_API.md updated
- not required — grep confirmed `0 matches` for the removed plumbing names, and existing `sample_structure_context` API text remains accurate

#### Blockers
- none

### 2026-04-04 Cleanup — remove legacy directed-band sampler script and repo references
**Status**: completed
**Started**: 2026-04-04
**Completed**: 2026-04-04

#### Acceptance tests
- [x] `core/systems/world/large_structure_sampler.gd` is physically removed from the repository. — verified by `Test-Path ...\\large_structure_sampler.gd` returning `False`
- [x] Working docs/comments no longer reference `LargeStructureSampler` or `large_structure_sampler.gd`. — verified by `rg` across `docs/`, `docs_integrity_report_2026-03-31.md`, `temp/TASK_BRIEF.md`, `core/systems/world/world_noise_utils.gd`, and `gdextension/src/chunk_generator.cpp`: `0 matches`
- [x] Remaining repository hits are historical discussion only. — verified by full-repo `rg`, which now reports matches only in `discussion`
- [x] Project still loads headless after deleting the script. — verified by `godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1` (exit code `0`)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `LargeStructureSampler|large_structure_sampler.gd` — `0 matches`
- [x] Grep `PUBLIC_API.md` for `LargeStructureSampler|large_structure_sampler.gd` — `0 matches`
- [x] Documentation debt reviewed — canonical docs already described the new `WorldComputeContext.sample_structure_context()` path; this cleanup only removed stale non-canonical references and the deleted legacy script

#### Files touched
- `core/systems/world/large_structure_sampler.gd` — deleted from the repository
- `core/systems/world/world_noise_utils.gd` — removed stale class reference from the header comment
- `gdextension/src/chunk_generator.cpp` — updated legacy-structure comment wording
- `docs_integrity_report_2026-03-31.md` — removed deleted file from the helper-file list
- `docs/04_execution/world_generation_rollout.md` — updated rollout wording to the new authoritative structure path
- `docs/00_governance/PROJECT_GLOSSARY.md` — rewrote glossary entries away from the deleted class toward `WorldPrePass` / `WorldComputeContext`
- `docs/02_system_specs/world/world_lab_spec.md` — removed deleted class from the fallback stack
- `docs/02_system_specs/world/native_chunk_generation_spec.md` — replaced file/class references with legacy-stage wording
- `docs/02_system_specs/world/natural_world_constructive_runtime_spec.md` — updated the constructive plan to the current post-removal state
- `docs/02_system_specs/world/natural_world_generation_overhaul.md` — replaced removed class/file references with legacy-stage wording
- `temp/TASK_BRIEF.md` — removed the deleted file from the forbidden-files list
- `.claude/agent-memory/active-epic.md` — cleanup tracking updated

#### Closure report
## Closure Report

### Implemented
- Deleted the legacy `large_structure_sampler.gd` script from the repository.
- Rewrote current documentation and code comments so the repo now speaks in terms of `WorldPrePass` / `WorldComputeContext` or “legacy directed-band structure stage” instead of pointing at the removed file/class.
- Left only historical transcript mentions in `discussion`, which are intentionally preserved as archive rather than working documentation.

### Root cause
- After the hard GDScript structure-path milestone, the runtime no longer used `LargeStructureSampler`, but the repository still carried the deleted world model as a physical script plus multiple stale doc links. That left the project saying two different things: the code said “new world”, while the docs still hinted the old sampler existed.

### Files changed
- `core/systems/world/large_structure_sampler.gd` — deleted.
- `core/systems/world/world_noise_utils.gd` / `gdextension/src/chunk_generator.cpp` — stale references cleaned up.
- Working docs under `docs/` plus `docs_integrity_report_2026-03-31.md` and `temp/TASK_BRIEF.md` — stale links/mentions removed or rewritten.
- `.claude/agent-memory/active-epic.md` — tracked the cleanup.

### Acceptance tests
- [x] `large_structure_sampler.gd` is gone from the repository. — passed (`Test-Path` returned `False`)
- [x] Working docs/comments no longer reference `LargeStructureSampler` or `large_structure_sampler.gd`. — passed (`rg` across docs/comments returned `0 matches`)
- [x] Remaining hits are historical discussion only. — passed (full-repo `rg` returns only `discussion`)
- [x] Project still loads headless after deleting the script. — passed (`godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1`, exit code `0`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `LargeStructureSampler|large_structure_sampler.gd`: `0 matches` — not referenced
- Grep `PUBLIC_API.md` for `LargeStructureSampler|large_structure_sampler.gd`: `0 matches` — not referenced
- Spec/documentation debt review: canonical docs already point at `WorldComputeContext.sample_structure_context()`; cleanup was limited to stale non-canonical references and deletion of the unused legacy script

### Out-of-scope observations
- Historical transcript file `discussion` still mentions `LargeStructureSampler`; it was left untouched as archive, not working documentation.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- not required — grep confirmed `0 matches`

### PUBLIC_API.md updated
- not required — grep confirmed `0 matches`

#### Blockers
- none

### Constructive Iteration 5 — Causal `BiomeResolver`
**Status**: blocked
**Started**: 2026-04-04
**Completed**: —

#### Acceptance tests
- [x] `BiomeResolver` gets pre-pass input without direct `WorldPrePass` array reads. — verified by `rg` in `core/systems/world/biome_resolver.gd` (typed `prepass_channels` input at lines 37 and 202) plus `0 matches` for `WorldPrePass|_world_pre_pass|_drainage_grid|_slope_grid|_rain_shadow_grid|_continentalness_grid`.
- [x] `effective_moisture` is computed once and lands in debug summary. — verified by `rg` in `core/systems/world/biome_resolver.gd` (lines 84-123 and 229-245) plus `core/systems/world/biome_result.gd:39-47`, which forwards `channel_scores` into `get_debug_summary()`. `scenes/ui/world_lab.gd` now exposes that summary through `sample_biome_debug_summary()` and the inspect panel.
- [ ] Fixed-seed `Biome` preview shows wetter river corridors and drier lee-side regions. — BLOCKED: the six surface biome resources now have non-zero causal weights and narrower causal ranges, but this session could not drive the existing `GameWorldDebug` -> `WorldPreviewExporter` (`F6` local / `F8` full export) path non-interactively, so the visible shift still needs manual fixed-seed export/screenshot proof.
- [x] With zero new weights, ranking matches the old scheme. — verified statically by file read: `core/systems/world/biome_resolver.gd` still gates causal moisture/range influence behind `_uses_causal_moisture()` and `_matches_weighted_range()`, so the compatibility path remains intact even though the current biome resources now opt into non-zero tuning.
- [x] `BiomeResolver` remains deterministic for the same seed and `world_pos`. — verified by file read: `_is_better_score()` tie-break logic is unchanged, and the new causal inputs come only from sampled `WorldChannels`, typed `WorldPrePassChannels`, and deterministic balance constants.
- [x] Headless project parse/smoke still succeeds after the resolver changes. — verified by `godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1` (exit code `0`).

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `WorldComputeContext.resolve_biome()|BiomeResolver|sample_prepass_channels()`: matches at lines 97-99, 200, 263 — updated/still accurate after this task.
- [x] Grep `DATA_CONTRACTS.md` for `effective_moisture|sample_biome_debug_summary|biome_continental_drying_factor|biome_drainage_moisture_bonus`: `0 matches` — not referenced.
- [x] Grep `PUBLIC_API.md` for `sample_prepass_channels()`: match at line 618 — still accurate.
- [x] Grep `PUBLIC_API.md` for `WorldComputeContext.resolve_biome()|BiomeResolver|effective_moisture|sample_biome_debug_summary|biome_continental_drying_factor|biome_drainage_moisture_bonus`: `0 matches` — not referenced.
- [x] Documentation debt reviewed — Iteration 5 `Required updates` says `DATA_CONTRACTS.md` only if the pre-pass -> biome read chain changes and `PUBLIC_API.md` only for caller-facing API promotion; `DATA_CONTRACTS.md` was updated in this task, `PUBLIC_API.md` was not required.

#### Files touched
- `core/systems/world/biome_resolver.gd` — added typed pre-pass input, causal score channels, effective-moisture debug data, and zero-weight compatibility gates.
- `core/systems/world/world_compute_context.gd` — passes `WorldPrePassChannels` and balance into `BiomeResolver`.
- `data/biomes/wet_lowland_biome.tres` — enabled strong river/wet-side causal preference and constrained steep/dry/inland matches.
- `data/biomes/plains_biome.tres` — enabled low-weight causal buffering so plains stay broad fallback territory instead of ignoring geography completely.
- `data/biomes/foothills_biome.tres` — enabled slope-led upland tuning with moderate lee-side/inland preference and weaker drainage affinity.
- `data/biomes/mountains_biome.tres` — enabled strong slope preference plus low-drainage mountain filtering.
- `data/biomes/scorched_biome.tres` — enabled low-drainage, high-rain-shadow, high-continentalness tuning for dry interior/lee-side regions.
- `data/biomes/cold_zone_biome.tres` — enabled conservative causal tuning while keeping temperature/latitude dominance.
- `data/world/world_gen_balance.gd` — added causal moisture tuning knobs.
- `scenes/ui/world_lab.gd` — added biome debug sampling and inspect-panel summary for causal biome decisions.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — documented the pre-pass -> biome resolver read chain.
- `.claude/agent-memory/active-epic.md` — iteration tracking updated.

#### Closure report
pending final user-visible fixed-seed export/screenshot proof; static/code-side acceptance, biome-resource tuning, and headless parse proof were captured in-session

#### Blockers
- Manual fixed-seed `WorldLab` / `GameWorldDebug` export proof for this visible iteration remains outstanding; the existing exporter path is available via `scenes/world/game_world_debug.gd` (`F6` local save, `F8` full export) but was not callable non-interactively in this session.

### Constructive Iteration 6 — `BiomeResult` Top-2 And `Ecotone`
**Status**: blocked
**Started**: 2026-04-04
**Completed**: —

#### Acceptance tests
- [x] `BiomeResult` stores `primary_biome`, `secondary_biome`, `primary_score`, `secondary_score`, `dominance`, `ecotone_factor`. — verified by `rg` in `core/systems/world/biome_result.gd` (lines 8-15, 57, 87-98)
- [x] `ecotone_factor` stays near `0` in confident core areas and grows in disputed border zones. — verified by file read / `rg` in `core/systems/world/biome_result.gd`: no-secondary path forces `ecotone_factor = 0.0` (lines 92-94), while contested tiles use `1.0 - score_gap` from primary vs secondary score (lines 96-98)
- [x] `WorldLab` renders an `Ecotone` map. — verified by `Select-String` in `scenes/ui/world_lab.gd` (enum/mode/image/render path at lines 26, 74, 212, 320, 509, 534, 638, 706, 750, 918) plus `godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1` (exit code `0`)
- [x] Existing consumers that only need the primary biome keep working. — verified by `rg` hits that still read legacy-compatible `result.biome`, `result.biome_id`, and `result.score` in `core/autoloads/world_generator.gd` (lines 208, 695-696), `core/systems/world/surface_terrain_resolver.gd` (lines 97, 187, 190), `core/systems/world/world_feature_hook_resolver.gd` (lines 81, 114), and `core/systems/world/world_poi_resolver.gd` (line 166), plus headless project load success

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `WorldComputeContext.resolve_biome()|BiomeResolver` — matches at lines 99 and 200; still accurate because the doc describes the pre-pass read chain, not the internal result-object shape
- [x] Grep `DATA_CONTRACTS.md` for `BiomeResult|primary_biome|secondary_biome|dominance|ecotone_factor` — `0 matches`
- [x] Grep `PUBLIC_API.md` for `BiomeResult|resolve_biome|primary_biome|secondary_biome|dominance|ecotone_factor` — `0 matches`
- [x] Documentation debt reviewed — Iteration 6 `Required updates` says update `PUBLIC_API.md` only if `BiomeResult` or resolver signature is documented there; grep confirmed it is not

#### Files touched
- `core/systems/world/biome_result.gd` — added top-2 biome fields plus compatibility-preserving primary mirrors and ecotone metrics
- `core/systems/world/biome_resolver.gd` — ranked valid/fallback candidates as top-2, then attached a secondary biome to the returned primary result
- `scenes/ui/world_lab.gd` — added `Ecotone` map mode, render buffer, and inspect text for primary/secondary biome competition
- `.claude/agent-memory/active-epic.md` — iteration tracking updated

#### Closure report
## Closure Report

### Implemented
- Extended `BiomeResult` so the returned biome decision now carries `primary_biome`, `secondary_biome`, `primary_score`, `secondary_score`, `dominance`, and `ecotone_factor` while keeping the old `biome` / `biome_id` / `score` fields mapped to the primary result for compatibility.
- Updated `BiomeResolver` to keep the top-2 candidates instead of only the single winner, then attach the best distinct secondary biome to the returned result.
- Added `Ecotone` preview rendering to `WorldLab` together with inspect-panel output that shows the primary/secondary biome pair and their transition strength.

### Root cause
- The biome pipeline was still winner-takes-all: `BiomeResolver` threw away every near-miss candidate after selecting the winner, so the runtime had no first-class representation of contested biome borders. Without a secondary candidate and score gap, `WorldLab` and later consumers could not distinguish stable biome cores from transition belts.

### Files changed
- `core/systems/world/biome_result.gd` — top-2 biome result fields, compatibility mirrors, and transition-metric helper.
- `core/systems/world/biome_resolver.gd` — top-2 ranking and secondary-candidate selection for valid/fallback paths.
- `scenes/ui/world_lab.gd` — `Ecotone` preview mode plus inspect/debug surfacing of the new result fields.
- `.claude/agent-memory/active-epic.md` — tracking and closure notes.

### Acceptance tests
- [x] `BiomeResult` stores `primary_biome`, `secondary_biome`, `primary_score`, `secondary_score`, `dominance`, `ecotone_factor`. — passed (`rg` in `core/systems/world/biome_result.gd`: lines 8-15, 57, 87-98)
- [x] `ecotone_factor` stays near `0` in confident core areas and grows in disputed border zones. — passed (file read / `rg` in `core/systems/world/biome_result.gd`: lines 92-98)
- [x] `WorldLab` renders an `Ecotone` map. — passed (`Select-String` in `scenes/ui/world_lab.gd`: lines 26, 74, 212, 320, 509, 534, 638, 706, 750, 918; plus headless parse/smoke via `godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1`)
- [x] Existing consumers that only need the primary biome keep working. — passed (`rg` shows legacy field reads still intact in `world_generator.gd`, `surface_terrain_resolver.gd`, `world_feature_hook_resolver.gd`, and `world_poi_resolver.gd`; headless smoke also passed)
- [ ] Fixed-seed `WorldLab` screenshot proof for the visible `Ecotone` iteration. — BLOCKED: requires manual runtime/export confirmation through the existing `WorldLab` or debug preview path

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `WorldComputeContext.resolve_biome()|BiomeResolver`: matches at lines 99 and 200 — still accurate
- Grep `DATA_CONTRACTS.md` for `BiomeResult|primary_biome|secondary_biome|dominance|ecotone_factor`: `0 matches` — not referenced
- Grep `PUBLIC_API.md` for `BiomeResult|resolve_biome|primary_biome|secondary_biome|dominance|ecotone_factor`: `0 matches` — not referenced
- Section `Required updates` in spec: exists for Iteration 6 — not applicable here because `PUBLIC_API.md` only needs changes if `BiomeResult` or resolver signature is documented there, and grep confirmed it is not

### Out-of-scope observations
- `LocalVariationResolver` already has helper plumbing that talks about primary/secondary score blending, but Iteration 6 intentionally did not connect that path yet; actual ecotone consumers stay deferred to Iteration 7.

### Remaining blockers
- Manual fixed-seed `Ecotone` screenshots / export proof in `WorldLab` are still required before this visible iteration can be marked fully complete.

### DATA_CONTRACTS.md updated
- not required — grep confirmed `BiomeResult|primary_biome|secondary_biome|dominance|ecotone_factor` are not referenced, and the existing `resolve_biome` / `BiomeResolver` read-chain text remains accurate

### PUBLIC_API.md updated
- not required — grep confirmed `BiomeResult|resolve_biome|primary_biome|secondary_biome|dominance|ecotone_factor` are not referenced
#### Blockers
- Manual fixed-seed `Ecotone` screenshots / export proof in `WorldLab` are still required before this visible iteration can be marked complete.

### Constructive Iteration 7 — Ecotone Consumers
**Status**: blocked
**Started**: 2026-04-04
**Completed**: —

#### Acceptance tests
- [x] `LocalVariationResolver` использует `ecotone_factor` при расчёте modulation. — verified by `rg` in `core/systems/world/local_variation_resolver.gd` (lines 41, 219-258, 296-302) and `core/systems/world/local_variation_context.gd` (lines 22-24, 73, 87-90)
- [x] `ChunkFloraBuilder` умеет смешивать primary/secondary biome flora sets. — verified by `rg` in `core/systems/world/chunk_flora_builder.gd` (lines 42-56, 79-127, 171-180, 220-298, 363-408) plus payload transport hits in `surface_terrain_resolver.gd` (lines 97-102, 194-196), `chunk_content_builder.gd` (lines 63-64, 98-124, 138-139), `chunk_build_result.gd` (lines 15-16, 32-33, 50-60, 71-87), and `chunk_manager.gd` (lines 1021-1022, 1051-1052, 1088-1116, 2281-2282)
- [x] На fixed seed set есть наблюдаемые mixed-border regions, которые отсутствовали до этой итерации. — verified by headless export `godot.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_export_ecotone_proof codex_world_seed=12345 codex_ecotone_proof_count=1 codex_ecotone_radius=16`, which produced `seed_12345_local_288_-352_r16_1775308965_x4_ecotone.png` / `_vegetation.png` and logged `mixed=104`, `ecotone_tiles=1089`, `flora=104`
- [x] Один-тайлный резкий flip vegetation на biome boundary заметно уменьшается. — verified by the same fixed-seed export plus in-session image review of `debug_exports/world_previews/seed_12345_local_288_-352_r16_1775308965_x4_vegetation.png`, which shows a blended multi-tile transition region instead of a single hard vegetation stripe

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `LocalVariationResolver|ChunkFloraBuilder|WorldPreviewExporter|WorldPreviewProofDriver|codex_world_seed|codex_export_ecotone_proof|ecotone_factor|secondary_biome|secondary_biome_palette_index|ecotone_values` — `0 matches`
- [x] Grep `PUBLIC_API.md` for `LocalVariationResolver|ChunkFloraBuilder|WorldPreviewExporter|WorldPreviewProofDriver|codex_world_seed|codex_export_ecotone_proof|ecotone_factor|secondary_biome|secondary_biome_palette_index|ecotone_values` — `0 matches`
- [x] Documentation debt reviewed — Iteration 7 `Required updates` at spec lines 524-527 says canonical docs are not required by default for derived/presentation behavior without ownership or public-surface changes; grep confirmed that remains true here

#### Files touched
- `core/systems/world/local_variation_context.gd` — added secondary-biome/ecotone debug fields to the variation context
- `core/systems/world/local_variation_resolver.gd` — blended secondary biome tag bias into ecotone scoring and softened modulation intensity near transition belts
- `core/systems/world/tile_gen_data.gd` — added per-tile secondary biome palette index and `ecotone_factor` transport fields
- `core/systems/world/surface_terrain_resolver.gd` — populated the new per-tile ecotone transport fields from `BiomeResult`
- `core/systems/world/chunk_build_result.gd` — added packed arrays for secondary biome and ecotone payload export
- `core/systems/world/chunk_content_builder.gd` — wrote the new per-tile payload into chunk build/native-data output
- `core/systems/world/chunk_manager.gd` — forwarded optional ecotone payload arrays into `ChunkFloraBuilder` and duplicated them in staged native data
- `core/systems/world/chunk_flora_builder.gd` — added ecotone-aware mixed flora/decor candidate selection while keeping core-biome placement behavior unchanged outside ecotone buckets
- `scenes/ui/world_lab.gd` — extended Inspect output with local-variation debug surfacing for ecotone consumer proof
- `core/debug/world_preview_exporter.gd` — added local `ecotone` / `vegetation` preview rendering and export stats for proof artifacts
- `core/debug/world_preview_proof_driver.gd` — added a headless fixed-seed proof driver that scans nearby hotspot candidates and exports the best ecotone region
- `scenes/world/game_world_debug.gd` — wired the proof driver and surfaced `ecotone` / `vegetation` local preview cards plus saved-path logging
- `scenes/world/game_world.gd` — added `codex_world_seed=` debug override so proof runs can target fixed seeds deterministically
- `.claude/agent-memory/active-epic.md` — iteration tracking updated

#### Closure report
## Closure Report

### Implemented
- Added ecotone-aware local variation handling: `LocalVariationResolver` now records primary/secondary biome context, blends tag bias from the secondary biome into transition zones, and pulls modulation toward neutral as `ecotone_factor` rises.
- Added minimal per-tile ecotone transport (`secondary_biome_palette_index`, `ecotone_factor`) through the GDScript chunk build path so flora can consume biome-border context without touching the native path ahead of Iteration 8.
- Updated `ChunkFloraBuilder` so ecotone tiles build mixed primary/secondary flora/decor candidate sets and pick from them deterministically, while non-ecotone biome cores keep the old primary-only behavior.
- Extended `WorldLab` Inspect output with local variation debug summary so ecotone-consumer behavior can be inspected tile-by-tile during manual proof.
- Added a reproducible headless proof harness (`WorldPreviewExporter` local `ecotone` / `vegetation` layers, `WorldPreviewProofDriver`, and `codex_world_seed=` override) and captured fixed-seed export artifacts for seed `12345`.

### Root cause
- After Iteration 6 the runtime could identify disputed biome borders, but that information stopped at `BiomeResult`: local variation and flora placement still behaved as winner-takes-all consumers of the primary biome, so borders remained prone to abrupt vegetation flips instead of reading as mixed ecological regions.

### Files changed
- `core/systems/world/local_variation_context.gd` — secondary biome/ecotone debug state for local variation.
- `core/systems/world/local_variation_resolver.gd` — ecotone-aware tag bias and modulation softening.
- `core/systems/world/tile_gen_data.gd` — per-tile ecotone transport fields.
- `core/systems/world/surface_terrain_resolver.gd` — populated ecotone transport from `BiomeResult`.
- `core/systems/world/chunk_build_result.gd` — packed secondary biome/ecotone arrays.
- `core/systems/world/chunk_content_builder.gd` — wrote secondary biome/ecotone values into chunk payload output.
- `core/systems/world/chunk_manager.gd` — forwarded optional payload arrays into flora compute and staged native-data duplication.
- `core/systems/world/chunk_flora_builder.gd` — mixed flora/decor candidates for ecotone tiles.
- `scenes/ui/world_lab.gd` — inspect/debug surfacing for local variation on ecotone tiles.
- `core/debug/world_preview_exporter.gd` — local proof images/statistics for ecotone and vegetation.
- `core/debug/world_preview_proof_driver.gd` — headless fixed-seed proof driver.
- `scenes/world/game_world_debug.gd` — proof-driver wiring and local preview cards for ecotone/vegetation.
- `scenes/world/game_world.gd` — fixed-seed debug override for proof runs.
- `.claude/agent-memory/active-epic.md` — tracking and closure notes.

### Acceptance tests
- [x] `LocalVariationResolver` uses `ecotone_factor` during modulation calculation — passed (`rg` in `local_variation_resolver.gd`: lines 41, 219-258, 296-302; `local_variation_context.gd`: lines 22-24, 73, 87-90)
- [x] `ChunkFloraBuilder` can mix primary/secondary biome flora sets — passed (`rg` in `chunk_flora_builder.gd`: lines 42-56, 79-127, 171-180, 220-298, 363-408; payload transport hits in `surface_terrain_resolver.gd`, `chunk_content_builder.gd`, `chunk_build_result.gd`, and `chunk_manager.gd`)
- [x] Project still parses/boots after the ecotone-consumer changes — passed (`godot.exe --headless --path C:\Users\peaceful\Station Peaceful\Station Peaceful --quit-after 1`, exit code `0`)
- [x] Fixed-seed mixed-border regions are visibly present — passed (headless proof export at seed `12345`, center `(288, -352)`, radius `16` logged `mixed=104`, `ecotone_tiles=1089`, `flora=104` and saved `debug_exports/world_previews/seed_12345_local_288_-352_r16_1775308965_x4_ecotone.png` plus `_vegetation.png`)
- [x] One-tile vegetation flips are visibly reduced at biome borders — passed (same fixed-seed export, plus in-session image review of the generated vegetation proof shows a multi-tile blended transition instead of a single hard boundary stripe)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `LocalVariationResolver|ChunkFloraBuilder|WorldPreviewExporter|WorldPreviewProofDriver|codex_world_seed|codex_export_ecotone_proof|ecotone_factor|secondary_biome|secondary_biome_palette_index|ecotone_values`: `0 matches` — not referenced
- Grep `PUBLIC_API.md` for `LocalVariationResolver|ChunkFloraBuilder|WorldPreviewExporter|WorldPreviewProofDriver|codex_world_seed|codex_export_ecotone_proof|ecotone_factor|secondary_biome|secondary_biome_palette_index|ecotone_values`: `0 matches` — not referenced
- Section `Required updates` in spec: exists at lines 524-527 — not applicable here because Iteration 7 only changed derived/presentation behavior and internal GDScript payload plumbing, without ownership drift or new public caller surface

### Out-of-scope observations
- Native chunk generation still does not emit the new ecotone payload arrays; that parity remains deferred to Constructive Iteration 8 by spec.
- Constructive Iterations 2-3, 5, and 6 still need their own visible proof passes; this task only closed the Iteration 7 ecotone-consumer proof gap.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- not required — grep confirmed `LocalVariationResolver|ChunkFloraBuilder|WorldPreviewExporter|WorldPreviewProofDriver|codex_world_seed|codex_export_ecotone_proof|ecotone_factor|secondary_biome|secondary_biome_palette_index|ecotone_values` are not referenced, and Iteration 7 stayed within derived/presentation behavior

### PUBLIC_API.md updated
- not required — grep confirmed `LocalVariationResolver|ChunkFloraBuilder|WorldPreviewExporter|WorldPreviewProofDriver|codex_world_seed|codex_export_ecotone_proof|ecotone_factor|secondary_biome|secondary_biome_palette_index|ecotone_values` are not referenced, and no public caller surface changed

#### Blockers
- none
### Phase 2 - Landmark Grammar
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `validate_landmarks()` корректно определяет наличие/отсутствие каждого mandatory landmark-а и wow-region family. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 319, 421, 439, 450, 483, 501, 519, 535, 551, 590, 614, 636, 656, 678)
- [x] Soft fix path подстраивает borderline seeds через runtime thresholds и пересчитывает pre-pass. — verified by file read in `core/autoloads/world_generator.gd` (lines 401-425, 445-478)
- [x] Reroll path меняет effective seed и пересчитывает pre-pass snapshot. — verified by file read in `core/autoloads/world_generator.gd` (lines 401-425, especially line 408)
- [x] После validation boot path пытается добиться landmark guarantees (`great_river`, `mountain_arc`, `delta`) через validate → soft-fix → reroll до публикации accepted snapshot. — verified by file read in `core/autoloads/world_generator.gd` (lines 401-425) together with `core/systems/world/world_pre_pass.gd` (lines 319-481)
- [x] Validation не блокирует запуск: после исчерпания remediation остаётся warning fallback. — verified by file read in `core/autoloads/world_generator.gd` (lines 426-433)
- [ ] Performance: validation + remediation < 5s total. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` returned `NONE`; runtime timing could not be measured in this environment)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `validate_landmarks` matches at lines 52, 96, 97, 197, 198, 251, 261; `sample_all|get_grid_value` matches at lines 97 and 261; `initialize_world` landmark-remediation semantics match at lines 96, 196, 198, 199, 252
- [x] Grep `PUBLIC_API.md` for changed names — `validate_landmarks` matches at lines 585, 633, 636; `sample_all|get_grid_value` match at lines 623 and 628; `initialize_world|world_initialized|landmark_validation_enabled` semantics match at lines 583, 585, 586, 661, 662, 673
- [x] Documentation debt section reviewed — this phase updated both `DATA_CONTRACTS.md` and `PUBLIC_API.md` because `WorldPrePass.validate_landmarks()` was promoted to a documented read-only API and `initialize_world()` gained effective-seed remediation semantics

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `validate_landmarks()` plus landmark and wow-region detection helpers over the accepted pre-pass snapshot.
- `core/autoloads/world_generator.gd` — add boot-time landmark remediation loop with runtime balance duplication, soft-fix, reroll, and warning fallback.
- `data/world/world_gen_balance.gd` — add landmark grammar tuning exports.
- `data/world/world_gen_balance.tres` — seed default landmark grammar values.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document validation/remediation ownership and public read surface.
- `docs/00_governance/PUBLIC_API.md` — document `WorldPrePass.validate_landmarks()` and the effective-seed semantics of `initialize_world()`.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for Phase 2.

#### Closure report
## Closure Report

### Implemented
- Added `WorldPrePass.validate_landmarks()` and dedicated proof helpers for great river, mountain arc, delta, large lake, glacier front, dry belt, scorched wasteland, and wow-region detection (`canyon`, `caldera`, `marsh_basin`, `alpine_lake`, `glacial_fjord`).
- Added landmark grammar tuning knobs to `WorldGenBalance` / `world_gen_balance.tres`.
- Added boot-time landmark remediation in `WorldGenerator.initialize_world()`: duplicate runtime balance, compute pre-pass, validate landmarks, soft-fix pre-pass thresholds, reroll effective seed when needed, and fall back with warning instead of blocking startup.
- Updated canonical docs so `WorldPrePass.validate_landmarks()` and the accepted/effective-seed boot semantics are part of the documented contract.

### Root cause
- After Phase 1 the pre-pass already computed enough global structure to judge world quality, but boot had no rule that turned those channels into guaranteed memorable geography. Seeds could still initialize into statistically valid yet forgettable worlds because nothing validated or remediated landmark presence before publishing the generator state.

### Files changed
- `core/systems/world/world_pre_pass.gd` — validation/report helpers.
- `core/autoloads/world_generator.gd` — remediation loop and runtime balance handling.
- `data/world/world_gen_balance.gd` — landmark exports.
- `data/world/world_gen_balance.tres` — default landmark values.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — pre-pass ownership/read-surface update.
- `docs/00_governance/PUBLIC_API.md` — public API update for validation/effective seed.
- `.claude/agent-memory/active-epic.md` — phase tracking.

### Acceptance tests
- [x] `validate_landmarks()` detects each landmark / wow-region family — passed (file read)
- [x] Soft fix adjusts runtime thresholds and recomputes — passed (file read)
- [x] Reroll changes effective seed and recomputes — passed (file read)
- [x] Boot path attempts guaranteed landmark publication before final snapshot — passed (file read)
- [x] Validation does not block startup forever — passed (file read)
- [ ] Validation + remediation < 5s total — blocked (runtime tools unavailable)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `validate_landmarks`: matches at lines 52, 96, 97, 197, 198, 251, 261 — updated
- Grep `DATA_CONTRACTS.md` for `sample_all|get_grid_value`: matches at lines 97 and 261 — updated
- Grep `DATA_CONTRACTS.md` for `initialize_world`: matches at lines 96, 118, 140, 196, 198, 199, 252, 259 — updated where pre-pass semantics changed
- Grep `PUBLIC_API.md` for `validate_landmarks`: matches at lines 585, 633, 636 — updated
- Grep `PUBLIC_API.md` for `sample_all|get_grid_value`: matches at lines 623 and 628 — updated
- Grep `PUBLIC_API.md` for `initialize_world|world_initialized|landmark_validation_enabled`: matches at lines 583, 585, 586, 591, 592, 661, 662, 673, 1713 — updated where semantics changed
- Section `Фаза 2: Landmark Grammar` / `Acceptance criteria (landmark grammar)` / `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists at lines 735, 822, 1023, and 1034 — reviewed; this phase updated both canonical docs because landmark validation became a documented boot-time/public contract

### Out-of-scope observations
- Landmark validation currently relies on heuristic caldera/fjord detection over the coarse pre-pass grids; qualitative tuning against real atlas output still belongs to later tooling/seed-curation work.
- The remediation loop only adjusts `prepass_river_accumulation_threshold` and `prepass_ridge_min_height`, exactly as scoped by the spec; dry-belt/scorched misses still rely on reroll rather than deeper climate retuning.

### Remaining blockers
- Runtime/performance proof for the `< 5s total` acceptance remains blocked until a usable Godot/editor/runtime tool is available in the environment.

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `validate_landmarks`, `sample_all`, `get_grid_value`, and `initialize_world`

### PUBLIC_API.md updated
- updated — grep evidence recorded above for `validate_landmarks`, `sample_all`, `get_grid_value`, `initialize_world`, `world_initialized`, and `landmark_validation_enabled`

#### Blockers
- Runtime/performance proof remains blocked by missing Godot/editor tooling in this environment

---

### Phase 2 follow-up - WorldLab preview readability
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `WorldLab` exposes a dedicated `Landmarks` mode plus a readable sidebar (`Inspect`, legend, landmark report) instead of a single undersized overview. — verified by file read in `scenes/ui/world_lab.gd` (`MapMode.LANDMARKS`, UI sidebar block, `_refresh_legend()`, `_refresh_landmark_report()`, `_refresh_detail_preview()`)
- [x] `WorldLab` computes and displays `validate_landmarks()` output for the selected seed. — verified by file read in `scenes/ui/world_lab.gd` (`_world_pre_pass`, `sample_landmark_channels()`, `get_landmark_report()`, worker report wiring)
- [x] `git diff --check` passes for the touched file. — verified by command output: `git diff --check -- scenes/ui/world_lab.gd` returned no output

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for `WorldLab|world_lab|World Preview` — 0 matches
- [x] Grep `PUBLIC_API.md` for `WorldLab|world_lab|World Preview` — 0 matches
- [x] Documentation debt section reviewed — not required; this follow-up only changed internal tooling UI and consumed already-documented `WorldPrePass.validate_landmarks()` without altering runtime ownership or safe entrypoints

#### Files touched
- `scenes/ui/world_lab.gd` — add `Landmarks` mode, pre-pass-backed landmark report, inspect magnifier, legend, and higher-resolution preview cap.
- `.claude/agent-memory/active-epic.md` — record the follow-up completion.

#### Closure report
## Closure Report

### Implemented
- Added a `Landmarks` preview mode to `WorldLab` so drainage, mountain arcs, dry belts, and coast transitions read as an explanatory atlas rather than as muted terrain colors.
- Added a right-hand sidebar with an inspect magnifier, mode legend, and live landmark report derived from `WorldPrePass.validate_landmarks()`.
- Increased the preview height cap from `640` to `1024`, which reduces downsampling for tall world overviews before the inspect crop is applied.

### Root cause
- The existing WorldLab UI only showed a fit-to-panel terrain/biome atlas. For a tall cylindrical world that meant the overview became too narrow to read, and nothing in the UI told the user whether the selected seed actually contained the Phase 2 landmark set.

### Files changed
- `scenes/ui/world_lab.gd`
- `.claude/agent-memory/active-epic.md`

### Acceptance tests
- [x] `Landmarks` mode, inspect panel, legend, and landmark report exist in `WorldLab` — passed (file read)
- [x] `WorldLab` now calls `validate_landmarks()` through its local pre-pass snapshot — passed (file read)
- [x] `git diff --check -- scenes/ui/world_lab.gd` — passed (no output)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `WorldLab|world_lab|World Preview`: 0 matches
- Grep `PUBLIC_API.md` for `WorldLab|world_lab|World Preview`: 0 matches
- No spec `Required updates` section applied here; this was a tooling-only follow-up and did not change canonical runtime contracts or public APIs

### Out-of-scope observations
- `WorldLab` still previews the requested seed directly; it does not yet emulate `WorldGenerator.initialize_world()` remediation/effective-seed reroll semantics from Phase 2.
- Runtime/editor smoke verification is still blocked by missing Godot tooling in this environment.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- not required — grep proof above shows no `WorldLab` / `world_lab` / `World Preview` surface in `DATA_CONTRACTS.md`

### PUBLIC_API.md updated
- not required — grep proof above shows no `WorldLab` / `world_lab` / `World Preview` surface in `PUBLIC_API.md`

#### Blockers
- none

---

### Iteration 1.17 - Polar terrain modifiers
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose the polar tuning knobs from the spec, and `WorldGenerator._setup_native_chunk_generator()` forwards the relevant native params. — verified by file read in `data/world/world_gen_balance.gd` (lines 39, 72-80), `data/world/world_gen_balance.tres` (lines 31, 52-58), and `core/autoloads/world_generator.gd` (lines 485-492)
- [x] `SurfaceTerrainResolver` applies polar presentation overlays (ICE / SCORCHED / SALT_FLAT / DRY_RIVERBED), ice-cap height boost, and flora suppression without mutating canonical terrain. — verified by file read in `core/systems/world/surface_terrain_resolver.gd` (lines 16-19, 263-298)
- [x] Surface rendering + flora/decor payload consumers understand the new variation ids and polar subzone names. — verified by file read in `core/systems/world/chunk_tileset_factory.gd` (lines 55-58, 573, 586-592), `core/systems/world/chunk.gd` (lines 597, 808), and `core/systems/world/chunk_flora_builder.gd` (lines 14, 21-24, 68)
- [x] Native `ChunkGenerator` mirrors the new polar params, variation ids, payload packing, and subzone-name mapping for `variation` consumers. — verified by file read in `gdextension/src/chunk_generator.h` (lines 108-115, 190, 245) and `gdextension/src/chunk_generator.cpp` (lines 132-139, 750-804, 831-852, 1049)
- [ ] Runtime smoke / native rebuild verification. — blocked (`godot`, `godot4`, `scons`, `cl`, `clang++`, and `g++` all returned `NONE`; `python -c "print(123)"` returned only `Python`, indicating the Windows Store alias is not a usable interpreter)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `polar_ice|polar_scorched|polar_salt_flat|polar_dry_riverbed` now match at line 104 and describe `variation` as presentation-only overlay markers
- [x] Grep `PUBLIC_API.md` for changed names — polar / variation payload semantics now match at lines 598 and 604
- [x] Documentation debt section reviewed — this iteration updated both `DATA_CONTRACTS.md` and `PUBLIC_API.md` because payload `variation` semantics changed

#### Files touched
- `core/systems/world/surface_terrain_resolver.gd` — apply polar overlay selection, ice-cap height boost, and flora suppression on top of canonical terrain answers.
- `core/systems/world/chunk_tileset_factory.gd` — define/render the four new surface presentation tiles and expose them through `get_surface_variation_tile()`.
- `core/systems/world/chunk.gd` — allow surface redraw to honor variation-driven polar overlays for water / sand / grass / ground surfaces.
- `core/systems/world/chunk_flora_builder.gd` — recognize the new polar variation ids as named subzones for flora/decor filtering.
- `core/autoloads/world_generator.gd` — forward polar balance params into native chunk-generator setup.
- `data/world/world_gen_balance.gd` — add polar balance exports.
- `data/world/world_gen_balance.tres` — seed default polar balance values.
- `gdextension/src/chunk_generator.h` — add polar params, native variation ids, and helper declarations.
- `gdextension/src/chunk_generator.cpp` — mirror polar overlay selection, height/flora adjustments, and subzone-name mapping on the native path.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — record that polar overlays live in `variation` and stay presentation-only.
- `docs/00_governance/PUBLIC_API.md` — document `variation` payload semantics for `build_chunk_content()` / `build_chunk_native_data()`.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.17.

#### Closure report
## Closure Report

### Implemented
- Added four new surface presentation markers for polar terrain: `ICE`, `SCORCHED`, `SALT_FLAT`, and `DRY_RIVERBED`, all carried through `variation` rather than canonical terrain mutation.
- Applied cold-pole logic in `SurfaceTerrainResolver`: ice overlays on flat low surfaces, frozen-water overlays below `prepass_frozen_river_threshold`, ice-cap height boost, and strong flora suppression.
- Applied hot-pole logic in `SurfaceTerrainResolver`: scorched overlays on flat hot land, dry-riverbed overlays on sufficiently evaporated hot water, salt-flat overlays on hot flat sand/floodplain contexts, and strong flora suppression.
- Extended `ChunkTilesetFactory` + `Chunk` redraw so the new overlay ids render as dedicated biome-tinted tiles on surface chunks.
- Updated flora/decor subzone-name mapping to recognize the new polar overlay ids instead of silently collapsing them to `none`.
- Mirrored the same polar params / variation ids / height + flora adjustments into the native `ChunkGenerator` path so worker/native chunk payloads stay wire-compatible with the GDScript generator.
- Updated `DATA_CONTRACTS.md` and `PUBLIC_API.md` to state explicitly that `variation` is presentation-only overlay metadata and now includes polar markers.

### Root cause
- Step 1.17 required temperature-driven polar geography to affect surface presentation, local height shaping, and flora pressure without breaking the existing contract that canonical terrain remains `GROUND/WATER/SAND/ROCK`. Before this iteration, the generator had no dedicated polar overlay ids, no render path for them, and no native/GDScript parity for carrying those markers through chunk payloads.

### Files changed
- `core/systems/world/surface_terrain_resolver.gd` — polar overlay selection, height boost, and flora suppression.
- `core/systems/world/chunk_tileset_factory.gd` — new polar overlay tiles and variation lookup.
- `core/systems/world/chunk.gd` — variation-aware surface redraw for overlay tiles.
- `core/systems/world/chunk_flora_builder.gd` — polar subzone-name mapping.
- `core/autoloads/world_generator.gd` — native polar param forwarding.
- `data/world/world_gen_balance.gd` — polar tuning exports.
- `data/world/world_gen_balance.tres` — default polar tuning values.
- `gdextension/src/chunk_generator.h` — native polar params / variation ids / helper declarations.
- `gdextension/src/chunk_generator.cpp` — native polar overlay application and payload parity.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `variation` presentation-only contract update.
- `docs/00_governance/PUBLIC_API.md` — payload `variation` semantics update.
- `.claude/agent-memory/active-epic.md` — persistent tracking updated for this step.

### Acceptance tests
- [x] Polar balance params exist in `WorldGenBalance` / `.tres`, and native setup forwards them. — passed (file read)
- [x] `SurfaceTerrainResolver` applies polar overlays, ice-cap height boost, and flora suppression without mutating canonical terrain. — passed (file read)
- [x] Surface render + flora consumers understand the new overlay ids. — passed (file read)
- [x] Native `ChunkGenerator` mirrors the new polar overlay semantics and payload shape. — passed (file read)
- [ ] Runtime smoke / native rebuild verification. — blocked (`godot`, `godot4`, `scons`, `cl`, `clang++`, and `g++` unavailable; `python` alias unusable)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `polar_ice|polar_scorched|polar_salt_flat|polar_dry_riverbed`: match at line 104 — updated
- Grep `DATA_CONTRACTS.md` for `variation remains presentation-only`: match at line 632 — updated
- Grep `PUBLIC_API.md` for `variation` payload semantics: matches at lines 598 and 604 — updated
- Section `Шаг 1.17: Polar Terrain Modifiers` / `Acceptance criteria (erosion + rain shadow + polar + lakes)` / `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: reviewed before implementation; this iteration updated both canonical docs because payload `variation` semantics changed

### Out-of-scope observations
- Hot-zone salt-flat selection currently uses flat hot sand / floodplain context as a generator-side proxy; the current resolver path still does not consume explicit pre-pass lake records when choosing overlays.
- Native flatness still falls back to `ruggedness <= 0.28` because the C++ generator does not yet consume the boot-time pre-pass `slope` channel.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for the new polar variation markers and presentation-only `variation` semantics

### PUBLIC_API.md updated
- updated — grep evidence recorded above for `build_chunk_content()` / `build_chunk_native_data()` payload semantics

#### Blockers
- none

---

### Iteration 1.16 - Continentalness
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `_continentalness_grid` exists as a coarse-grid channel, is resized/reset alongside the other pre-pass grids, and `_compute_continentalness()` runs after `_compute_rain_shadow()`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 107, 139, 173-186, 207, 625-627)
- [x] The continentalness pass seeds water sources from Y-edge cells plus coarse cells where `_eroded_height_grid < prepass_sea_level_threshold`, expands distance with wrapped 8-neighbor travel costs, and normalizes the result to `[0,1]`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 630-670, 1686-1689, 2083-2086) against `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 619-645)
- [x] `WorldPrePass.sample(&"continentalness", pos)`, `sample_all(pos)`, and `get_grid_value(&"continentalness", ...)` expose the normalized channel. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 236-251, 282-285) and `docs/02_system_specs/world/DATA_CONTRACTS.md` (lines 95-96, 195, 213, 232, 252, 257)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose `prepass_sea_level_threshold`. — verified by file read in `data/world/world_gen_balance.gd` (lines 68-69), `data/world/world_gen_balance.tres` (line 51), and `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 629-645)
- [ ] Runtime qualitative check that coast-adjacent areas read lower continentalness than deep interior regions. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `continentalness` found at lines 52, 96, 195, 213, 232, 257 and updated; `_continentalness_grid` found at lines 95, 195, 213, 232, 252 and updated; `WorldPrePass.sample` found at lines 96 and 257 and remained accurate after the new channel was added
- [x] Grep `DATA_CONTRACTS.md` for new balance params — 0 matches for `prepass_sea_level_threshold`
- [x] Grep `PUBLIC_API.md` for changed names — 0 matches for `continentalness|_continentalness_grid|WorldPrePass.sample|sample_all|get_grid_value|prepass_sea_level_threshold`
- [x] Documentation debt section reviewed — `DATA_CONTRACTS.md` updated now for the normalized `continentalness` channel; `PUBLIC_API.md` remains unchanged because Iteration 1.16 did not promote a new safe runtime entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_continentalness_grid`, compute the normalized inland-distance field from sea-level / Y-edge water sources, and expose it through the pre-pass read surface.
- `data/world/world_gen_balance.gd` — add `prepass_sea_level_threshold`.
- `data/world/world_gen_balance.tres` — seed the default sea-level threshold value.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document `continentalness` ownership, invariants, forbidden writes, and read-surface exposure.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.16.

#### Closure report
## Closure Report

### Implemented
- Added the normalized coarse-grid channel `_continentalness_grid` to `WorldPrePass`.
- Inserted `_compute_continentalness()` after the rain-shadow stage so continentalness reads the stabilized eroded surface and remains an owned pre-pass output rather than an ad hoc downstream recomputation.
- Implemented continentalness as a wrapped multi-source distance field: sources are Y-edge cells plus coarse cells below `prepass_sea_level_threshold`, travel uses 8-neighbor coarse-grid distances, and the final field is normalized to `[0,1]`.
- Exposed `continentalness` through `WorldPrePass.sample()`, `sample_all()`, and `get_grid_value()`.
- Added `prepass_sea_level_threshold` to `WorldGenBalance` and the default `.tres`.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer records the new `continentalness` field, invariants, forbidden writes, and read contract.

### Root cause
- The pre-pass already owned hydrology, ridge, erosion, slope, and rain-shadow context, but it still lacked a canonical normalized signal for “how far inland is this cell from major water.” Without `continentalness`, later biome and effective-moisture work would have to recompute coastline distance ad hoc instead of consuming one deterministic shared field from the pre-pass.

### Files changed
- `core/systems/world/world_pre_pass.gd` — continentalness channel storage, compute pass, sea-level/Y-edge source detection, normalization, and read-surface exposure.
- `data/world/world_gen_balance.gd` — new continentalness tuning export.
- `data/world/world_gen_balance.tres` — default sea-level threshold value.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, writers, invariants, forbidden writes, and read-gap note updated for `continentalness`.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `_continentalness_grid` exists as a coarse-grid channel, is resized/reset alongside the other pre-pass grids, and `_compute_continentalness()` runs after `_compute_rain_shadow()`. — passed (file read)
- [x] The continentalness pass seeds water sources from Y-edge cells plus coarse cells where `_eroded_height_grid < prepass_sea_level_threshold`, expands distance with wrapped 8-neighbor travel costs, and normalizes the result to `[0,1]`. — passed (file read + spec read)
- [x] `WorldPrePass.sample(&"continentalness", pos)`, `sample_all(pos)`, and `get_grid_value(&"continentalness", ...)` expose the normalized channel. — passed (file read + contract read)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose `prepass_sea_level_threshold`. — passed (file read + spec read)
- [ ] Runtime qualitative check that coast-adjacent areas read lower continentalness than deep interior regions. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `continentalness`: matches at lines 52, 96, 195, 213, 232, 257 — updated
- Grep `DATA_CONTRACTS.md` for `_continentalness_grid`: matches at lines 95, 195, 213, 232, 252 — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: matches at lines 96 and 257 — still accurate after the new channel was added
- Grep `DATA_CONTRACTS.md` for `prepass_sea_level_threshold`: 0 matches — not referenced
- Grep `PUBLIC_API.md` for `continentalness|_continentalness_grid|WorldPrePass.sample|sample_all|get_grid_value|prepass_sea_level_threshold`: 0 matches — not referenced
- Section `Шаг 1.16: Continentalness` / `Acceptance criteria (erosion + rain shadow + polar + lakes)` / `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists at lines 619, 721, 1023, and 1034 — reviewed; this iteration updated `DATA_CONTRACTS.md` now and left `PUBLIC_API.md` unchanged because no new external safe runtime entrypoint was promoted

### Out-of-scope observations
- The new channel is now ready for downstream consumers, but `BiomeResolver`, `SurfaceTerrainResolver`, and biome `.tres` resources still do not read `continentalness`; that remains later work in the spec.
- The current source definition treats Y-edge cells as major-water boundaries per the spec, but no runtime visualization tooling was available in this session to inspect how that gradient reads across real seeds.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `continentalness`, `_continentalness_grid`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `continentalness|_continentalness_grid|WorldPrePass.sample|sample_all|get_grid_value|prepass_sea_level_threshold` returned 0 matches

#### Blockers
- none

---

### Iteration 1.15 - Rain shadow
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `_rain_shadow_grid` exists as a coarse-grid channel, is resized/reset alongside the other pre-pass grids, and `_compute_rain_shadow()` runs after the erosion/slope stages. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 105, 136, 168-180, 200, 583-606)
- [x] The rain-shadow pass samples baseline moisture from `PlanetSampler.moisture`, orders cells into wind-aligned columns, derives positive orographic lift from eroded-height gradients, and updates the moisture budget with precipitation plus evaporation-based recovery. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 588-605, 1502-1608, 1992-2012) against `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 599-614)
- [x] `WorldPrePass.sample(&"rain_shadow", pos)`, `sample_all(pos)`, and `get_grid_value(&"rain_shadow", ...)` expose the normalized channel. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 225-239, 266-269) and `docs/02_system_specs/world/DATA_CONTRACTS.md` (lines 95-96, 195, 212, 230, 250, 255)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose the four rain-shadow tuning knobs from the spec. — verified by file read in `data/world/world_gen_balance.gd` (lines 63-66), `data/world/world_gen_balance.tres` (lines 47-50), and `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 639-642)
- [ ] Runtime qualitative check that the world shows wetter windward slopes and drier leeward slopes. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `rain_shadow` found at lines 95, 96, 195, 212, 230, 250, 255 and updated; `_rain_shadow_grid` found at lines 95, 195, 212, 230, 250 and updated; `WorldPrePass.sample` found at lines 96 and 255 and remained accurate after the new channel was added
- [x] Grep `DATA_CONTRACTS.md` for new balance params — 0 matches for `prepass_prevailing_wind_direction|prepass_precipitation_rate|prepass_orographic_lift_factor|prepass_evaporation_rate`
- [x] Grep `PUBLIC_API.md` for changed names — 0 matches for `rain_shadow|_rain_shadow_grid|WorldPrePass.sample|sample_all|get_grid_value|prepass_prevailing_wind_direction|prepass_precipitation_rate|prepass_orographic_lift_factor|prepass_evaporation_rate`
- [x] Documentation debt section reviewed — `DATA_CONTRACTS.md` updated now for the normalized `rain_shadow` channel; `PUBLIC_API.md` remains unchanged because Iteration 1.15 did not promote a new safe runtime entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_rain_shadow_grid`, compute the rain-shadow channel from prevailing-wind moisture transport over eroded-height gradients, and expose it through the pre-pass read surface.
- `data/world/world_gen_balance.gd` — add `prepass_prevailing_wind_direction`, `prepass_precipitation_rate`, `prepass_orographic_lift_factor`, and `prepass_evaporation_rate`.
- `data/world/world_gen_balance.tres` — seed default values for the new rain-shadow parameters.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document `rain_shadow` ownership, invariants, forbidden writes, and read-surface exposure.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.15.

#### Closure report
## Closure Report

### Implemented
- Added the normalized coarse-grid channel `_rain_shadow_grid` to `WorldPrePass`.
- Inserted `_compute_rain_shadow()` after the existing erosion/slope stages so rain shadow derives from the stabilized eroded surface rather than raw height noise.
- Implemented rain shadow as wind-aligned coarse-grid moisture transport: baseline moisture comes from `PlanetSampler.moisture`, columns are ordered along the prevailing wind direction, positive eroded-height gradients create orographic lift, precipitation spends the current moisture budget, and evaporation recovers toward the local baseline moisture.
- Exposed `rain_shadow` through `WorldPrePass.sample()`, `sample_all()`, and `get_grid_value()`.
- Added the four Rain Shadow tuning knobs to `WorldGenBalance` and the default `.tres`.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer records the new `rain_shadow` field, invariants, and read contract.

### Root cause
- The pre-pass already owned erosion, slope, ridge, and drainage context, but moisture was still only a local sampler noise source with no mountain-aware transport. Without a normalized `rain_shadow` field, later effective-moisture and biome work could not create deterministic wet windward / dry leeward asymmetry from the same canonical pre-pass state.

### Files changed
- `core/systems/world/world_pre_pass.gd` — rain-shadow channel storage, compute pass, wind-column ordering, orographic lift helper, moisture recovery helper, and read-surface exposure.
- `data/world/world_gen_balance.gd` — new rain-shadow tuning exports.
- `data/world/world_gen_balance.tres` — default rain-shadow values.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, writers, invariants, forbidden writes, and read-gap note updated for `rain_shadow`.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `_rain_shadow_grid` exists as a coarse-grid channel, is resized/reset alongside the other pre-pass grids, and `_compute_rain_shadow()` runs after the erosion/slope stages. — passed (file read)
- [x] The rain-shadow pass samples baseline moisture from `PlanetSampler.moisture`, orders cells into wind-aligned columns, derives positive orographic lift from eroded-height gradients, and updates the moisture budget with precipitation plus evaporation-based recovery. — passed (file read + spec read)
- [x] `WorldPrePass.sample(&"rain_shadow", pos)`, `sample_all(pos)`, and `get_grid_value(&"rain_shadow", ...)` expose the normalized channel. — passed (file read + contract read)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose the four rain-shadow tuning knobs from the spec. — passed (file read + spec read)
- [ ] Runtime qualitative check that the world shows wetter windward slopes and drier leeward slopes. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `rain_shadow`: matches at lines 95, 96, 195, 212, 230, 250, 255 — updated
- Grep `DATA_CONTRACTS.md` for `_rain_shadow_grid`: matches at lines 95, 195, 212, 230, 250 — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: matches at lines 96 and 255 — still accurate after the new channel was added
- Grep `DATA_CONTRACTS.md` for `prepass_prevailing_wind_direction|prepass_precipitation_rate|prepass_orographic_lift_factor|prepass_evaporation_rate`: 0 matches — not referenced
- Grep `PUBLIC_API.md` for `rain_shadow|_rain_shadow_grid|WorldPrePass.sample|sample_all|get_grid_value|prepass_prevailing_wind_direction|prepass_precipitation_rate|prepass_orographic_lift_factor|prepass_evaporation_rate`: 0 matches — not referenced
- Section `Шаг 1.15: Rain Shadow` / `Acceptance criteria (erosion + rain shadow + polar + lakes)` / `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists at lines 599, 714, 1023, and 1034 — reviewed; this iteration updated `DATA_CONTRACTS.md` now and left `PUBLIC_API.md` unchanged because no new external safe runtime entrypoint was promoted

### Out-of-scope observations
- The new channel is now ready for downstream consumers, but `BiomeResolver`, `SurfaceTerrainResolver`, and biome `.tres` resources still do not read `rain_shadow`; that remains later work in the spec.
- The horizontally wrapped default wind uses an internal stabilization pass for seam continuity, but no runtime visualization or seed-diff tooling was available in this session to inspect the qualitative result in-game.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `rain_shadow`, `_rain_shadow_grid`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `rain_shadow|_rain_shadow_grid|WorldPrePass.sample|sample_all|get_grid_value|prepass_prevailing_wind_direction|prepass_precipitation_rate|prepass_orographic_lift_factor|prepass_evaporation_rate` returned 0 matches

#### Blockers
- none

---

### Iteration 1.14 - Slope channel
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `_slope_grid` exists as a coarse-grid channel, is resized alongside the other pre-pass grids, and `_compute_slope_grid()` runs after `_compute_erosion_proxy()`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 103, 163-164, 192-193, 553-555)
- [x] `slope[i]` is computed from the max 8-neighbor gradient over `_eroded_height_grid` and stays normalized to `[0,1]`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 553-565, 1405-1415) against `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 594-597)
- [x] `WorldPrePass.sample(&"slope", pos)`, `sample_all(pos)`, and `get_grid_value(&"slope", ...)` expose the normalized slope channel. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 196-227, 230-253) and `docs/02_system_specs/world/DATA_CONTRACTS.md` (lines 96, 253)
- [ ] Runtime smoke / parse check in Godot. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `_slope_grid` found at lines 95, 195, 211, 228, 248 and updated; `slope` found at lines 52, 96, 195, 228, 253 and updated; `WorldPrePass.sample` found at lines 96 and 253 and remained accurate
- [x] Grep `PUBLIC_API.md` for changed names — 0 matches for `_slope_grid|slope|WorldPrePass.sample|sample_all|get_grid_value`
- [x] Documentation debt section reviewed — `DATA_CONTRACTS.md` updated now for the normalized slope channel; `PUBLIC_API.md` remains unchanged because Iteration 1.14 did not promote a new safe runtime entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_slope_grid`, compute the normalized slope field from `_eroded_height_grid`, and expose it through the pre-pass read surface.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document `slope` ownership, invariants, forbidden writes, and normalized read-surface exposure.
- `.claude/agent-memory/active-epic.md` — track Iteration 1.14 progress.

#### Closure report
## Closure Report

### Implemented
- Added the normalized coarse-grid channel `_slope_grid` to `WorldPrePass`.
- Inserted `_compute_slope_grid()` immediately after `_compute_erosion_proxy()` so slope samples the canonical eroded surface from Iteration 1.13 instead of reconstructing gradients downstream.
- Implemented slope sampling as the max 8-neighbor gradient over `_eroded_height_grid`, normalized by the tightest possible neighbor distance for the configured coarse grid.
- Exposed `slope` through `WorldPrePass.sample()`, `sample_all()`, and `get_grid_value()`.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now records `slope` ownership, invariants, forbidden writes, and normalized read exposure.

### Root cause
- Iteration 1.13 produced the canonical eroded terrain surface, but the pre-pass still lacked an owned normalized slope read channel. Without `slope`, later rain-shadow, continentalness, and biome passes would have to recompute local gradients ad hoc from internal `eroded-height` state instead of consuming a shared pre-pass field.

### Files changed
- `core/systems/world/world_pre_pass.gd` — slope channel storage, post-erosion compute hook, normalized gradient helper, and read-surface exposure.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, writers, invariants, forbidden writes, and current-gap note updated for `slope`.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `_slope_grid` exists as a coarse-grid channel, is resized alongside the other pre-pass grids, and `_compute_slope_grid()` runs after `_compute_erosion_proxy()`. — passed (file read)
- [x] `slope[i]` is computed from the max 8-neighbor gradient over `_eroded_height_grid` and stays normalized to `[0,1]`. — passed (file read + spec read)
- [x] `WorldPrePass.sample(&"slope", pos)`, `sample_all(pos)`, and `get_grid_value(&"slope", ...)` expose the normalized slope channel. — passed (file read + contract read)
- [ ] Runtime smoke / parse check in Godot. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_slope_grid`: matches at lines 95, 195, 211, 228, 248 — updated
- Grep `DATA_CONTRACTS.md` for `slope`: matches at lines 52, 96, 195, 228, 253 — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: matches at lines 96 and 253 — still accurate
- Grep `PUBLIC_API.md` for `_slope_grid|slope|WorldPrePass.sample|sample_all|get_grid_value`: 0 matches — not referenced
- Section `Шаг 1.14: Slope Channel` / `Acceptance criteria (erosion + rain shadow + polar + lakes)` / `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists at lines 594, 714, 1023, and 1034 — reviewed; this iteration updated `DATA_CONTRACTS.md` now and left `PUBLIC_API.md` unchanged because no new safe runtime entrypoint was promoted

### Out-of-scope observations
- `rain_shadow` and `continentalness` remain unimplemented; this iteration only creates the normalized slope input they depend on.
- No project-local Godot CLI or GDScript linter/formatter was available, so runtime/static parser validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_slope_grid`, `slope`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `_slope_grid|slope|WorldPrePass.sample|sample_all|get_grid_value` returned 0 matches

#### Blockers
- none

---

### Iteration 1.13 - Erosion proxy
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `_eroded_height_grid` exists as a coarse-grid channel, is resized alongside the other pre-pass grids, and `_compute_erosion_proxy()` runs after floodplain strength. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 101, 158-159, 186, 527-535)
- [x] Valley carving uses `prepass_erosion_valley_strength * sqrt(accumulation) * max-neighbor-gradient` against `_filled_height_grid`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 537-552, 1375-1387) against `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 558-570)
- [x] Thermal smoothing applies `prepass_thermal_iterations` passes only where `ridge_strength > 0.3`, scaled by `prepass_thermal_rate * (1.0 - ridge_strength)`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 554-576, 1812-1819) against `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 572-579)
- [x] Floodplain deposition propagates river height over floodplain-width falloff and lerps neighbors with `prepass_deposit_rate`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 578-640, 1822-1825) against `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 581-589)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose the four erosion-proxy tuning knobs. — verified by file read in `data/world/world_gen_balance.gd` (lines 56-60) and `data/world/world_gen_balance.tres` (lines 43-46)
- [ ] Runtime smoke / parse check in Godot. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `_eroded_height_grid` found at lines 95, 195, 210, 226, 227, 246 and updated; `eroded-height` found at lines 52, 96, 251 and updated; `erosion proxy` found at lines 195, 226, 227 and updated; `WorldPrePass.sample` found at line 96 and remained accurate
- [x] Grep `DATA_CONTRACTS.md` for new balance params — 0 matches for `prepass_erosion_valley_strength|prepass_thermal_iterations|prepass_thermal_rate|prepass_deposit_rate`
- [x] Grep `PUBLIC_API.md` for changed names — 0 matches for `_eroded_height_grid|prepass_erosion_valley_strength|prepass_thermal_iterations|prepass_thermal_rate|prepass_deposit_rate|WorldPrePass.sample|eroded_height`
- [x] Documentation debt section reviewed — `DATA_CONTRACTS.md` updated now for the internal erosion channel; `PUBLIC_API.md` remains unchanged because Iteration 1.13 did not promote a new safe runtime entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_eroded_height_grid`, run valley carving / thermal smoothing / floodplain deposition after hydrology, and add the local erosion helper/resolver methods.
- `data/world/world_gen_balance.gd` — add `prepass_erosion_valley_strength`, `prepass_thermal_iterations`, `prepass_thermal_rate`, and `prepass_deposit_rate`.
- `data/world/world_gen_balance.tres` — seed default values for the new erosion proxy parameters.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document `eroded-height` ownership, invariants, forbidden writes, and the still-internal read status.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.13.

#### Closure report
## Closure Report

### Implemented
- Added the internal coarse-grid channel `_eroded_height_grid` to `WorldPrePass`.
- Inserted `_compute_erosion_proxy()` after floodplain-strength generation so the erosion proxy consumes the canonical filled / accumulation / ridge / river inputs from earlier pre-pass steps.
- Implemented valley carving from `_filled_height_grid` using `prepass_erosion_valley_strength * sqrt(accumulation) * max-neighbor-gradient`.
- Implemented ridge-only thermal smoothing using `prepass_thermal_iterations`, `prepass_thermal_rate`, and the `ridge_strength > 0.3` gate so foothills soften while stronger peaks stay sharper.
- Implemented floodplain deposition as a distance-weighted river-height propagation that lerps nearby cells toward the strongest river source with `prepass_deposit_rate`.
- Added the four new erosion balance knobs to `WorldGenBalance` and the default `.tres`.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now records `eroded-height` ownership, invariants, and the still-internal read contract.

### Root cause
- Iteration 1.11/1.12 left the pre-pass with hydrology and mountain structure, but no owned post-hydrology terrain-shaping stage. Without an internal erosion proxy, later `slope`, `rain_shadow`, and `continentalness` passes would have to reconstruct valley carving, foothill smoothing, or floodplain flattening ad hoc from the raw filled surface.

### Files changed
- `core/systems/world/world_pre_pass.gd` — erosion channel storage, orchestration hook in `compute()`, valley/thermal/deposition passes, and helper balance resolvers.
- `data/world/world_gen_balance.gd` — new erosion proxy tuning exports.
- `data/world/world_gen_balance.tres` — default erosion proxy values.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, writers, invariants, forbidden writes, and current-gap note updated for `eroded-height`.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `_eroded_height_grid` exists as a coarse-grid channel, is resized alongside the other pre-pass grids, and `_compute_erosion_proxy()` runs after floodplain strength. — passed (file read)
- [x] Valley carving uses `prepass_erosion_valley_strength * sqrt(accumulation) * max-neighbor-gradient` against `_filled_height_grid`. — passed (file read + spec read)
- [x] Thermal smoothing applies `prepass_thermal_iterations` passes only where `ridge_strength > 0.3`, scaled by `prepass_thermal_rate * (1.0 - ridge_strength)`. — passed (file read + spec read)
- [x] Floodplain deposition propagates river height over floodplain-width falloff and lerps neighbors with `prepass_deposit_rate`. — passed (file read + spec read)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose the four erosion-proxy tuning knobs. — passed (file read)
- [ ] Runtime smoke / parse check in Godot. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_eroded_height_grid`: matches at lines 95, 195, 210, 226, 227, 246 — updated
- Grep `DATA_CONTRACTS.md` for `eroded-height`: matches at lines 52, 96, 251 — updated
- Grep `DATA_CONTRACTS.md` for `erosion proxy`: matches at lines 195, 226, 227 — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: match at line 96 — still accurate
- Grep `DATA_CONTRACTS.md` for `prepass_erosion_valley_strength|prepass_thermal_iterations|prepass_thermal_rate|prepass_deposit_rate`: 0 matches — not referenced
- Grep `PUBLIC_API.md` for `_eroded_height_grid|prepass_erosion_valley_strength|prepass_thermal_iterations|prepass_thermal_rate|prepass_deposit_rate|WorldPrePass.sample|eroded_height`: 0 matches — not referenced
- Section `Шаг 1.13: Cheap Erosion Proxy` / `Acceptance criteria (erosion + rain shadow + polar + lakes)` / `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists at lines 558, 714, 1023, and 1034 — reviewed; this iteration updated `DATA_CONTRACTS.md` now and left `PUBLIC_API.md` unchanged because no new safe runtime entrypoint was promoted

### Out-of-scope observations
- The shared epic tracker still has no dedicated Iteration 1.12 section even though the worktree already contained `mountain_mass` support before this task; I did not reconstruct that historical closure here.
- No project-local Godot CLI or GDScript linter/formatter was available, so runtime/static parser validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_eroded_height_grid`, `eroded-height`, `erosion proxy`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `_eroded_height_grid|prepass_erosion_valley_strength|prepass_thermal_iterations|prepass_thermal_rate|prepass_deposit_rate|WorldPrePass.sample|eroded_height` returned 0 matches

#### Blockers
- none

---

### Iteration 1.1 — WorldPrePass shell + coarse heightfield
**Status**: completed
**Started**: prior to 2026-04-02
**Completed**: prior to 2026-04-02

#### Acceptance tests
- [x] `WorldPrePass` shell and coarse `height` grid exist in repository state before this session.

#### Doc check
- [ ] Grep `DATA_CONTRACTS.md` for changed names — not reconstructed from earlier session.
- [ ] Grep `PUBLIC_API.md` for changed names — not reconstructed from earlier session.
- [ ] Documentation debt section reviewed — pending current iteration review.

#### Files touched
- Repository state predates this session; no new edits recorded here.

#### Closure report
Not reconstructed; present in repository history only.

#### Blockers
- none

---

### Iteration 1.11 — Ridge distance field
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `_ridge_strength_grid` exists as a coarse-grid channel, is resized alongside the other pre-pass grids, and is computed immediately after ridge spline smoothing. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 94, 145-146, 164, 502-511)
- [x] `ridge_strength(world_pos)` is computed as the max contribution over all ridges using nearest spline-segment distance, interpolated half-width, and a smoothstep falloff. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 513-558, 1201-1205) against `docs/02_system_specs/world/natural_world_generation_overhaul.md` (lines 512, 517-518)
- [x] `WorldPrePass.sample(&"ridge_strength", pos)`, `sample_all(pos)`, and `get_grid_value(&"ridge_strength", ...)` expose the normalized channel without exposing raw ridge spline state. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 173-212) and `docs/02_system_specs/world/DATA_CONTRACTS.md` (lines 96, 246)
- [ ] Runtime smoke / parse check in Godot. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `_ridge_strength_grid` found at lines 95, 195, 208, 222, 241 and updated; `ridge_strength` found at lines 52, 96, 195, 222, 246 and updated; `WorldPrePass.sample` found at lines 96 and 246 and updated/still accurate
- [x] Grep `PUBLIC_API.md` for changed names — 0 matches for `ridge_strength|_ridge_strength_grid|WorldPrePass.sample|sample_all|get_grid_value`
- [x] Documentation debt section reviewed — `DATA_CONTRACTS.md` updated now for the normalized ridge read channel; `PUBLIC_API.md` remains unchanged because Iteration 1.11 did not add a new safe runtime entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_ridge_strength_grid`, compute the coarse ridge distance field from smoothed spline segments, and expose the new channel via `sample()`, `sample_all()`, and `get_grid_value()`.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document `ridge_strength` ownership, invariants, forbidden writes, and the updated `WorldPrePass.sample()` read semantics.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.11.

#### Closure report
## Closure Report

### Implemented
- Added the normalized coarse-grid channel `_ridge_strength_grid` to `WorldPrePass`.
- Inserted `_compute_ridge_strength_grid()` immediately after `_smooth_ridge_paths()` so the ridge distance field is derived from the canonical smoothed spline state before later passes.
- Implemented `ridge_strength` as the max contribution over all ridge splines by projecting each coarse-grid cell onto the nearest spline segment, interpolating per-segment half-width, and applying the smoothstep falloff from the spec.
- Exposed `ridge_strength` through `WorldPrePass.sample()`, `sample_all()`, and `get_grid_value()` without exposing raw spline internals.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer records the new ridge-strength field and the expanded `sample()` read contract.

### Root cause
- Iteration 1.10 produced smoothed ridge geometry, but downstream systems still had no canonical scalar field to read mountain proximity from. Without a precomputed ridge distance field, later `mountain_mass`, rain-shadow, lake typing, and large-structure lookups would have to reconstruct ridge falloff ad hoc from raw spline geometry.

### Files changed
- `core/systems/world/world_pre_pass.gd` — ridge-strength channel storage, distance-field compute pass, wrap-aware nearest-segment sampling, and read-surface exposure.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, writers, invariants, forbidden writes, and contract-gap note updated for `ridge_strength`.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `_ridge_strength_grid` exists as a coarse-grid channel, is resized alongside the other pre-pass grids, and is computed immediately after ridge spline smoothing. — passed (file read)
- [x] `ridge_strength(world_pos)` is computed as the max contribution over all ridges using nearest spline-segment distance, interpolated half-width, and a smoothstep falloff. — passed (file read + spec read)
- [x] `WorldPrePass.sample(&"ridge_strength", pos)`, `sample_all(pos)`, and `get_grid_value(&"ridge_strength", ...)` expose the normalized channel without exposing raw ridge spline state. — passed (file read + contract read)
- [ ] Runtime smoke / parse check in Godot. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_ridge_strength_grid`: matches at lines 95, 195, 208, 222, 241 — updated
- Grep `DATA_CONTRACTS.md` for `ridge_strength`: matches at lines 52, 96, 195, 222, 246 — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: matches at lines 96 and 246 — updated/still accurate
- Grep `PUBLIC_API.md` for `ridge_strength|_ridge_strength_grid|WorldPrePass.sample|sample_all|get_grid_value`: 0 matches — not referenced
- Section `Required contract and API updates` / `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists at lines 242, 1023, and 1034 — reviewed; this iteration updated `DATA_CONTRACTS.md` now and left `PUBLIC_API.md` unchanged because no new safe runtime entrypoint was promoted beyond the existing internal pre-pass read surface

### Out-of-scope observations
- `mountain_mass` is still not exposed through `WorldPrePass.sample()`; Iteration 1.12 remains responsible for combining `ridge_strength` with height and ruggedness into the next normalized mountain channel.
- No project-local Godot CLI or GDScript linter/formatter was available, so runtime/static parser validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_ridge_strength_grid`, `ridge_strength`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `ridge_strength|_ridge_strength_grid|WorldPrePass.sample|sample_all|get_grid_value` returned 0 matches

#### Blockers
- none

---

### Iteration 1.10 — Ridge spline smoothing
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] Ridge paths produce internal spline samples instead of only raw coarse-grid polylines. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 21-22, 747-777)
- [x] Spline smoothing uses deterministic Catmull-Rom interpolation over wrap-aware control points sampled every 4 coarse-grid steps. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 47-48, 793-834)
- [x] Each ridge stores a positive width profile that peaks near the highest point and narrows toward both ends. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 836-931) and `docs/02_system_specs/world/DATA_CONTRACTS.md` (lines 231-234)
- [ ] Runtime smoke / parse check in Godot. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `spline_samples` found at lines 95, 231, 232, 239; `spline_half_widths` found at lines 95, 232, 239; `_ridge_paths` found at lines 95, 195, 210, 228-234, 239; `WorldPrePass.sample` found at lines 96, 244
- [x] Grep `PUBLIC_API.md` for changed names — 0 matches for `spline_samples|spline_half_widths|_ridge_paths|WorldPrePass.sample`
- [x] Documentation debt section reviewed — `DATA_CONTRACTS.md` updated for internal ridge spline ownership/invariants; `PUBLIC_API.md` remains unchanged because Iteration 1.10 did not add a new safe entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `RidgePath.spline_samples` / `spline_half_widths`, wrap-aware Catmull-Rom smoothing, and per-sample width profile generation.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document internal ridge spline ownership, invariants, and internal-only read status.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.10.

#### Closure report
## Closure Report

### Implemented
- Added internal spline state to each `RidgePath` via `spline_samples` and `spline_half_widths`.
- Added `_smooth_ridge_paths()` to `WorldPrePass.compute()` immediately after raw ridge graph construction, keeping the work boot-time and deterministic.
- Implemented wrap-aware ridge unwrapping plus Catmull-Rom interpolation over control points sampled every 4 coarse-grid cells.
- Derived a positive half-width profile per spline sample, with maximum width near the ridge's highest coarse-grid point and tapered ends.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now records ridge spline ownership and invariants while keeping the data internal-only.

### Root cause
- Iteration 1.9 stopped at jagged coarse-grid ridge polylines. Without an owned smoothing step inside `WorldPrePass`, later ridge-distance and mountain-mass iterations would have to reconstruct smooth geometry ad hoc, risking seam jumps and inconsistent width semantics.

### Files changed
- `core/systems/world/world_pre_pass.gd` — spline storage on `RidgePath`, smoothing pass, wrap-local point unwrapping, Catmull-Rom sampling, and width-profile helpers.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, writers, invariants, forbidden writes, and internal-only note updated for ridge spline data.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] Ridge paths produce internal spline samples instead of only raw coarse-grid polylines. — passed (file read)
- [x] Spline smoothing uses deterministic Catmull-Rom interpolation over wrap-aware control points sampled every 4 coarse-grid steps. — passed (file read)
- [x] Each ridge stores a positive width profile that peaks near the highest point and narrows toward both ends. — passed (file read + contract read)
- [ ] Runtime smoke / parse check in Godot. — blocked (`godot`, `godot4`, `gdlint`, and `gdformat` all returned `NONE`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `spline_samples`: 4 matches at lines 95, 231, 232, 239 — updated
- Grep `DATA_CONTRACTS.md` for `spline_half_widths`: 3 matches at lines 95, 232, 239 — updated
- Grep `DATA_CONTRACTS.md` for `_ridge_paths`: 11 matches at lines 95, 195, 210, 228-234, 239 — updated/still accurate
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: 2 matches at lines 96, 244 — still accurate
- Grep `PUBLIC_API.md` for `spline_samples|spline_half_widths|_ridge_paths|WorldPrePass.sample`: 0 matches — not referenced
- Section `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists — reviewed; current iteration updated `DATA_CONTRACTS.md` now and left `PUBLIC_API.md` unchanged because ridge spline data remains internal to `WorldPrePass`

### Out-of-scope observations
- `WorldPrePass.sample()` still does not expose `ridge_strength` or `mountain_mass`; those read channels remain deferred to Iterations 1.11 and 1.12.
- No project-local Godot CLI or GDScript linter/formatter was available, so runtime/static parser validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `spline_samples`, `spline_half_widths`, `_ridge_paths`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `spline_samples|spline_half_widths|_ridge_paths|WorldPrePass.sample` returned 0 matches

#### Blockers
- none

---

### Iteration 1.5 — Drainage channel
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `_drainage_grid` exists and stays index-aligned with the coarse pre-pass grid. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 60, 98-99, 346-350) and `DATA_CONTRACTS.md` (lines 95, 195, 203)
- [x] Drainage values are log-normalized from accumulation and clamped to `[0,1]`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 351-363) and `DATA_CONTRACTS.md` (line 212)
- [x] `WorldPrePass.sample(&"drainage", world_pos)` and `get_grid_value(&"drainage", ...)` expose the normalized channel without exposing raw accumulation. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 15, 131-155) and `DATA_CONTRACTS.md` (lines 96, 228)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names. — `_drainage_grid` found at lines 52, 95, 195, 203, 212, 223; `WorldPrePass.sample` found at line 96 and remained accurate
- [x] Grep `PUBLIC_API.md` for changed names. — 0 matches for `_drainage_grid|DRAINAGE_CHANNEL|WorldPrePass`
- [x] Documentation debt section reviewed. — `DATA_CONTRACTS.md` already reflects the normalized drainage read channel; `PUBLIC_API.md` remains unchanged because no new safe entrypoint was added in this step

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_drainage_grid`, log normalization from accumulation, and drainage reads through `sample()` / `get_grid_value()`.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document drainage ownership, invariants, and the still-internal status of raw pre-pass channels.
- `.claude/agent-memory/active-epic.md` — backfill the completed drainage iteration.

#### Closure report
## Closure Report

### Implemented
- Added `_drainage_grid` to `WorldPrePass` as a normalized `[0,1]` read channel derived from `_accumulation_grid`.
- Exposed `drainage` through the existing `WorldPrePass.sample()` / `sample_all()` / `get_grid_value()` surface without promoting raw accumulation or lake internals into the public contract.
- Kept the pre-pass ownership model canonical and boot-time only, then aligned `DATA_CONTRACTS.md` with the new drainage semantics.

### Root cause
- Iteration 1.4 produced flow volume but left later terrain/biome work without a stable normalized wetness proxy. Without a drainage channel, downstream consumers would have to read raw accumulation directly or re-normalize it ad hoc.

### Files changed
- `core/systems/world/world_pre_pass.gd` — drainage storage, normalization, and public read wiring.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, invariants, and internal-only read notes updated for drainage.
- `.claude/agent-memory/active-epic.md` — tracker backfill for Iteration 1.5.

### Acceptance tests
- [x] `_drainage_grid` exists and stays index-aligned with the coarse pre-pass grid. — passed (file read)
- [x] Drainage values are log-normalized from accumulation and clamped to `[0,1]`. — passed (file read)
- [x] `WorldPrePass.sample(&"drainage", world_pos)` and `get_grid_value(&"drainage", ...)` expose the normalized channel without exposing raw accumulation. — passed (file read)
- [ ] Runtime smoke / parse check in Godot. — blocked (no local Godot CLI discovered in this session)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_drainage_grid`: matches at lines 52, 95, 195, 203, 212, 223 — updated/still accurate
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: match at line 96 — still accurate
- Grep `PUBLIC_API.md` for `_drainage_grid|DRAINAGE_CHANNEL|WorldPrePass`: 0 matches — not referenced
- Section `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists — reviewed; current iteration kept API promotion deferred because only the existing `WorldPrePass` read surface was extended with normalized drainage

### Out-of-scope observations
- No project-local Godot executable or CLI alias was available, so runtime validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_drainage_grid` and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `_drainage_grid|DRAINAGE_CHANNEL|WorldPrePass` returned 0 matches

#### Blockers
- none

---

### Iteration 1.6 — River extraction
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] Coarse-grid river membership is extracted from the accumulation threshold into `_river_mask_grid`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 61, 100-105, 365-408) and `DATA_CONTRACTS.md` (lines 95, 195, 204, 213)
- [x] River width follows the spec formula `base + width_scale * log2(accumulation / river_threshold)` using `WorldGenBalance` parameters. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 375, 381, 410-417, 804-816), `data/world/world_gen_balance.gd` (lines 41-44), and `data/world/world_gen_balance.tres` (lines 32-34)
- [x] A non-negative nearest-river distance field is propagated over the coarse grid with wrap-safe neighbor traversal. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 384-423) and `DATA_CONTRACTS.md` (lines 206, 215)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names. — `_river_mask_grid` / `_river_width_grid` / `_river_distance_grid` found at lines 95, 195, 204-206, 213-215, 223, 228 and updated; `WorldPrePass.sample` found at line 96 and remained accurate
- [x] Grep `PUBLIC_API.md` for changed names. — 0 matches for `_river_mask_grid|_river_width_grid|_river_distance_grid|prepass_river_accumulation_threshold|prepass_river_base_width|prepass_river_width_scale|WorldPrePass`
- [x] Documentation debt section reviewed. — `DATA_CONTRACTS.md` updated for the new internal river channels; `PUBLIC_API.md` remains unchanged because Iteration 1.6 did not add a new safe entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_river_mask_grid`, `_river_width_grid`, `_river_distance_grid`, thresholded river extraction, and nearest-river distance propagation.
- `data/world/world_gen_balance.gd` — add `prepass_river_accumulation_threshold`, `prepass_river_base_width`, and `prepass_river_width_scale`.
- `data/world/world_gen_balance.tres` — seed default river extraction values.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document river pre-pass ownership, invariants, and internal-only read status.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.6.

#### Closure report
## Closure Report

### Implemented
- Added river extraction to `WorldPrePass`: cells at or above the configured accumulation threshold now become a coarse river graph via `_river_mask_grid`.
- Added `_river_width_grid` using the spec's logarithmic width growth formula and exposed the required tuning knobs in `WorldGenBalance` / `world_gen_balance.tres`.
- Added `_river_distance_grid`, propagated from river cells with wrap-safe neighbor traversal so later tile-level consumers can interpolate nearest-river distance without re-traversing the hydrology graph.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now includes river mask, width, and distance ownership/invariants while keeping them internal-only.

### Root cause
- Iterations 1.4 and 1.5 established downstream flow volume and normalized drainage, but the pre-pass still had no canonical representation of where rivers actually exist or how wide they are. Without an extracted river network, later floodplain, biome, and terrain steps would have no stable hydrology structure to sample.

### Files changed
- `core/systems/world/world_pre_pass.gd` — river membership, width derivation, and nearest-river distance propagation.
- `data/world/world_gen_balance.gd` — river threshold/base-width/width-scale exports.
- `data/world/world_gen_balance.tres` — default values for the new river parameters.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, invariants, and internal-only note updated for river extraction.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] Coarse-grid river membership is extracted from the accumulation threshold into `_river_mask_grid`. — passed (file read)
- [x] River width follows the spec formula `base + width_scale * log2(accumulation / river_threshold)` using `WorldGenBalance` parameters. — passed (file read)
- [x] A non-negative nearest-river distance field is propagated over the coarse grid with wrap-safe neighbor traversal. — passed (file read)
- [ ] Runtime smoke / parse check in Godot. — blocked (no local Godot CLI discovered in this session)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_river_mask_grid|_river_width_grid|_river_distance_grid|prepass_river_base_width`: matches at lines 95, 195, 204-206, 213-215, 223, 228 — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: match at line 96 — still accurate
- Grep `PUBLIC_API.md` for `_river_mask_grid|_river_width_grid|_river_distance_grid|prepass_river_accumulation_threshold|prepass_river_base_width|prepass_river_width_scale|WorldPrePass`: 0 matches — not referenced
- Section `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists — reviewed; current iteration updated canonical contracts now and left API promotion deferred because river extraction stayed internal to `WorldPrePass`

### Out-of-scope observations
- The shared epic tracker had no Iteration 1.5 entry even though drainage code already existed in the working tree, so this session backfilled that tracker history for continuity.
- No project-local Godot executable or CLI alias was available, so runtime validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_river_mask_grid`, `_river_width_grid`, `_river_distance_grid`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `_river_mask_grid|_river_width_grid|_river_distance_grid|prepass_river_accumulation_threshold|prepass_river_base_width|prepass_river_width_scale|WorldPrePass` returned 0 matches

#### Blockers
- none

---

### Iteration 1.7 — Floodplain
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `_floodplain_strength_grid` exists and stays index-aligned with the coarse pre-pass grid. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 64, 108-109, 407-409) and `DATA_CONTRACTS.md` (lines 95, 207)
- [x] Floodplain reach scales from `_river_width_grid * prepass_floodplain_multiplier` and fades smoothly from river cells to the outer edge. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 416, 467-476, 878-881), `data/world/world_gen_balance.gd` (line 45), and `data/world/world_gen_balance.tres` (line 35)
- [x] Overlapping river reaches resolve deterministically to the strongest floodplain contribution without breaking wrap-safe neighbor traversal. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 423-447, 631-638)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names. — `_floodplain_strength_grid` found at lines 95, 195, 207, 217, 218, 226, 231 and updated; `WorldPrePass.sample` found at line 96 and remained accurate; `prepass_floodplain_multiplier` returned 0 matches
- [x] Grep `PUBLIC_API.md` for changed names. — 0 matches for `_floodplain_strength_grid|prepass_floodplain_multiplier|WorldPrePass`
- [x] Documentation debt section reviewed. — `DATA_CONTRACTS.md` updated for the new internal floodplain channel; `PUBLIC_API.md` remains unchanged because Iteration 1.7 did not add a new safe entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_floodplain_strength_grid`, river-width-scaled floodplain propagation, and strongest-source overlap arbitration.
- `data/world/world_gen_balance.gd` — add `prepass_floodplain_multiplier`.
- `data/world/world_gen_balance.tres` — seed default floodplain multiplier.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document floodplain pre-pass ownership, invariants, and internal-only read status.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.7.

#### Closure report
## Closure Report

### Implemented
- Added `_floodplain_strength_grid` to `WorldPrePass` and compute-time floodplain expansion after river extraction.
- Seeded river cells at full floodplain strength, scaled each source reach by `_river_width_grid * prepass_floodplain_multiplier`, and used a smoothstep falloff to the outer edge of the floodplain.
- Resolved overlapping river reaches by keeping the strongest contribution per coarse cell while reusing the existing wrap-safe neighbor traversal and skipping lake cells.
- Added `prepass_floodplain_multiplier` to `WorldGenBalance` / `world_gen_balance.tres`.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now includes floodplain strength ownership, invariants, and internal-only status.

### Root cause
- Iteration 1.6 established where rivers exist and how wide they are, but the pre-pass still lacked a canonical lowland-reach field around those channels. Without a floodplain layer, later erosion, terrain, and biome work would have to recreate river widening and overlap arbitration ad hoc.

### Files changed
- `core/systems/world/world_pre_pass.gd` — floodplain storage, width-scaled propagation, overlap resolution, and helper plumbing.
- `data/world/world_gen_balance.gd` — `prepass_floodplain_multiplier` export.
- `data/world/world_gen_balance.tres` — default value for the floodplain multiplier.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, invariants, forbidden writes, and internal-only note updated for floodplain strength.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `_floodplain_strength_grid` exists and stays index-aligned with the coarse pre-pass grid. — passed (file read)
- [x] Floodplain reach scales from `_river_width_grid * prepass_floodplain_multiplier` and fades smoothly from river cells to the outer edge. — passed (file read)
- [x] Overlapping river reaches resolve deterministically to the strongest floodplain contribution without breaking wrap-safe neighbor traversal. — passed (file read)
- [ ] Runtime smoke / parse check in Godot. — blocked (no `godot`, `gdlint`, or `gdformat` found in PATH)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_floodplain_strength_grid`: matches at lines 95, 195, 207, 217, 218, 226, 231 — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: match at line 96 — still accurate
- Grep `DATA_CONTRACTS.md` for `prepass_floodplain_multiplier`: 0 matches — not referenced
- Grep `PUBLIC_API.md` for `_floodplain_strength_grid|prepass_floodplain_multiplier|WorldPrePass`: 0 matches — not referenced
- Section `Required contract and API updates` in spec: exists (line 242) — reviewed; current iteration updated canonical contracts now and left `PUBLIC_API.md` unchanged because floodplain remains internal to `WorldPrePass`

### Out-of-scope observations
- Floodplain strength is computed and documented, but no runtime consumer reads it yet; replacing band-based `LargeStructureSampler.floodplain_strength` remains a later iteration.
- No project-local Godot CLI or GDScript linter/formatter was available, so runtime/static parser validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_floodplain_strength_grid` and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `_floodplain_strength_grid|prepass_floodplain_multiplier|WorldPrePass` returned 0 matches

#### Blockers
- none

---

### Iteration 1.8 — Tectonic spine seeds
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `WorldPrePass.compute()` now runs a dedicated tectonic spine seed pass after coarse height sampling and before downstream hydrology steps. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 133, 462-489)
- [x] Spine seeds enforce wrap-aware coarse-grid spacing and store `position`, `strength`, and `direction_bias` derived from height/ruggedness sampling. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 14-17, 491-553)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose deterministic tuning knobs for target count and minimum spacing. — verified by file read in `data/world/world_gen_balance.gd` (lines 47-49) and `data/world/world_gen_balance.tres` (lines 36-37)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names. — `_spine_seeds` found at lines 95, 195, 209, 223-226, 231, 236 and updated; `prepass_target_spine_count` found at line 209; `prepass_min_spine_distance_grid` found at line 226; `WorldPrePass.sample` found at lines 96 and 236 and remained accurate; `sample_ruggedness|get_world_seed` returned 0 matches
- [x] Grep `PUBLIC_API.md` for changed names. — 0 matches for `_spine_seeds|prepass_target_spine_count|prepass_min_spine_distance_grid|sample_ruggedness|get_world_seed|WorldPrePass.sample`
- [x] Documentation debt section reviewed. — `DATA_CONTRACTS.md` updated for the new internal spine-seed records; `PUBLIC_API.md` remains unchanged because Iteration 1.8 did not add a new safe entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `SpineSeed` records, deterministic seeded candidate ordering, wrap-aware Poisson spacing, and ruggedness-gradient direction bias.
- `core/systems/world/planet_sampler.gd` — expose internal ruggedness/world-seed helpers needed by the pre-pass seed pass.
- `data/world/world_gen_balance.gd` — add `prepass_target_spine_count` and `prepass_min_spine_distance_grid`.
- `data/world/world_gen_balance.tres` — seed default ridge-skeleton spacing/count values.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document internal spine-seed ownership, invariants, and internal-only read status.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.8.

#### Closure report
## Closure Report

### Implemented
- Added a dedicated tectonic spine seed pass to `WorldPrePass` that runs immediately after coarse height sampling and before the existing lake/flow/drainage pipeline.
- Added internal `SpineSeed` records with grid position, normalized ridge strength in `[0.5, 1.0]`, and ruggedness-gradient `direction_bias`.
- Implemented deterministic candidate ordering from height+ruggedness bias plus seeded hash jitter, then enforced wrap-aware minimum coarse-grid spacing before accepting a seed.
- Added `prepass_target_spine_count` and `prepass_min_spine_distance_grid` to `WorldGenBalance` and the default `.tres`.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now includes internal spine-seed ownership, invariants, and internal-only status.

### Root cause
- The pre-pass had drainage, river, and floodplain structure, but ridge generation still had no canonical seed set to start from. Without deterministic tectonic seed records, Iteration 1.9 would have to regrow ridge starts ad hoc from band-era heuristics instead of an owned pre-pass artifact.

### Files changed
- `core/systems/world/world_pre_pass.gd` — spine seed record/type, seeded selection pass, spacing guard, gradient bias helpers, and balance lookups.
- `core/systems/world/planet_sampler.gd` — `sample_ruggedness()` and `get_world_seed()` helpers for pre-pass-only use.
- `data/world/world_gen_balance.gd` — ridge skeleton tuning exports for seed count and spacing.
- `data/world/world_gen_balance.tres` — default values for the new ridge skeleton fields.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, writers, invariants, forbidden writes, and internal-only note updated for spine seeds.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `WorldPrePass.compute()` now runs a dedicated tectonic spine seed pass after coarse height sampling and before downstream hydrology steps. — passed (file read)
- [x] Spine seeds enforce wrap-aware coarse-grid spacing and store `position`, `strength`, and `direction_bias` derived from height/ruggedness sampling. — passed (file read)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose deterministic tuning knobs for target count and minimum spacing. — passed (file read)
- [ ] Runtime smoke / parse check in Godot. — blocked (`Get-Command godot, godot4, gdlint, gdformat` returned `NONE`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_spine_seeds`: matches at lines 95, 195, 209, 223-226, 231, 236 — updated
- Grep `DATA_CONTRACTS.md` for `prepass_target_spine_count|prepass_min_spine_distance_grid`: matches at lines 209, 226 — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: matches at lines 96, 236 — still accurate
- Grep `DATA_CONTRACTS.md` for `sample_ruggedness|get_world_seed`: 0 matches — not referenced
- Grep `PUBLIC_API.md` for `_spine_seeds|prepass_target_spine_count|prepass_min_spine_distance_grid|sample_ruggedness|get_world_seed|WorldPrePass.sample`: 0 matches — not referenced
- Section `Required contract and API updates` / step-local spec guidance: exists at line 242 for the phase scaffold, and the Iteration 1.8 section plus ridge-skeleton parameter block are at lines 472-546 / 531-542 — reviewed; this iteration updated `DATA_CONTRACTS.md` now and left `PUBLIC_API.md` unchanged because spine seeds remain internal to `WorldPrePass`

### Out-of-scope observations
- `WorldPrePass.sample()` still does not expose ridge data; Iteration 1.9+ will need to decide when ridge graph / ridge strength become readable without promoting raw internal seed records too early.
- No project-local Godot CLI or GDScript linter/formatter was available, so runtime/static parser validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_spine_seeds`, `prepass_target_spine_count`, and `prepass_min_spine_distance_grid`

### PUBLIC_API.md updated
- not required — grep for `_spine_seeds|prepass_target_spine_count|prepass_min_spine_distance_grid|sample_ruggedness|get_world_seed|WorldPrePass.sample` returned 0 matches

#### Blockers
- none

---

### Iteration 1.2 — Sink filling + lake detection
**Status**: completed
**Started**: prior to 2026-04-02
**Completed**: prior to 2026-04-02

#### Acceptance tests
- [x] `WorldPrePass` stores `_filled_height_grid`, `_lake_mask`, and `_lake_records` in repository state before this session.

#### Doc check
- [ ] Grep `DATA_CONTRACTS.md` for changed names — not reconstructed from earlier session.
- [ ] Grep `PUBLIC_API.md` for changed names — not reconstructed from earlier session.
- [ ] Documentation debt section reviewed — pending current iteration review.

#### Files touched
- Repository state predates this session; no new edits recorded here.

#### Closure report
Not reconstructed; present in repository history only.

#### Blockers
- none

---

### Iteration 1.3 — Flow direction (D8)
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `_flow_dir_grid` exists and keeps one direction value per coarse-grid cell. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 57, 83-84, 243-247)
- [x] Boundary Y-edge cells remain outlet markers (`255`) instead of inventing wrapped exits. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 252, 389-391)
- [x] Cells with a downhill neighbor choose the steepest D8 descent deterministically. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 264-285)
- [x] Flat filled plateaus route toward the nearest resolved outlet through equal-height neighbors. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 287-361)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names. — `_flow_dir_grid` / `WorldPrePass.compute` / `WorldPrePass.sample` found at lines 95, 195, 201, 204, 205, 210, 212, 217 and updated
- [x] Grep `PUBLIC_API.md` for changed names. — 0 matches for `_flow_dir_grid|WorldPrePass|sample\(|get_grid_value`
- [x] Documentation debt section reviewed. — `DATA_CONTRACTS.md` updated for the new internal flow-direction channel; `PUBLIC_API.md` remains unchanged because no safe entrypoint was added

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add D8 flow-direction storage and flat routing.
- `.claude/agent-memory/active-epic.md` — start persistent tracking for this feature.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document `_flow_dir_grid` ownership, invariants, and Iteration 1.3 internal-only status.

#### Closure report
## Closure Report

### Implemented
- Added `_flow_dir_grid` to `WorldPrePass` and compute-time D8 routing on top of `_filled_height_grid`.
- Kept Y-edge cells as terminal outlets (`255`) and preserved cylindrical X-wrap for neighbor lookup.
- Added deterministic flat-plateau routing toward the nearest already-resolved outlet without expanding the public `WorldPrePass` read API.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now includes flow-direction ownership and invariants.

### Root cause
- Iteration 1.2 produced filled terrain and lake surfaces, but the pre-pass still had no canonical downstream direction grid for later drainage accumulation. Without `flow_dir`, Phase 1 could not progress to accumulation, drainage, or river extraction.

### Files changed
- `core/systems/world/world_pre_pass.gd` — D8 storage, direct downslope selection, flat-routing propagation.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, invariants, forbidden writes, and current-gap note updated for Iteration 1.3.
- `.claude/agent-memory/active-epic.md` — persistent task tracking initialized and updated for this step.

### Acceptance tests
- [x] `_flow_dir_grid` exists and keeps one direction value per coarse-grid cell. — passed (file read)
- [x] Boundary Y-edge cells remain outlet markers (`255`) instead of inventing wrapped exits. — passed (file read)
- [x] Cells with a downhill neighbor choose the steepest D8 descent deterministically. — passed (file read)
- [x] Flat filled plateaus route toward the nearest resolved outlet through equal-height neighbors. — passed (file read)
- [ ] Runtime smoke / parse check in Godot. — blocked (no local Godot CLI discovered in this session)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_flow_dir_grid`: 6 matches (lines 95, 195, 201, 204, 205, 212) — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: 1 match (line 217) — still accurate after update
- Grep `PUBLIC_API.md` for `_flow_dir_grid`: 0 matches — not referenced
- Grep `PUBLIC_API.md` for `WorldPrePass`: 0 matches — not referenced
- Section `Required contract and API updates` in spec: exists for Iteration 1.1 scaffolding — reviewed; current iteration still updated canonical docs because semantics moved beyond inert shell state

### Out-of-scope observations
- No project-local Godot executable or CLI alias was available, so runtime validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_flow_dir_grid` and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `_flow_dir_grid` and `WorldPrePass` returned 0 matches

#### Blockers
- none

---

### Iteration 1.4 — Flow accumulation + latitude evaporation
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `_accumulation_grid` exists and stays index-aligned with the coarse pre-pass grid. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 58, 77, 87-88, 272-273) and `DATA_CONTRACTS.md` (line 202)
- [x] Flow accumulation transfers downstream in topological order over `_flow_dir_grid`. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 278-303)
- [x] Hot latitude zones lose downstream transfer through evaporation while keeping accumulation non-negative. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 327-329, 684-687) and `DATA_CONTRACTS.md` (line 207)
- [x] Cold-to-temperate glacial edge cells receive stronger base contribution than deep frozen cells and hotter zones. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 320-325, 674-682)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names. — `_accumulation_grid` found at lines 95, 195, 202, 207, 215; `inflow_accumulation` found at line 210; `WorldPrePass.sample` found at line 220 and updated/still accurate
- [x] Grep `PUBLIC_API.md` for changed names. — 0 matches for `_accumulation_grid|prepass_glacial_melt_temperature|prepass_glacial_melt_bonus|prepass_latitude_evaporation_rate|prepass_frozen_river_threshold|WorldPrePass|inflow_accumulation`
- [x] Documentation debt section reviewed. — `DATA_CONTRACTS.md` updated for the new internal accumulation channel; `PUBLIC_API.md` remains unchanged because `sample()` still exposes only `height`

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `_accumulation_grid`, topological downstream transfer, latitude evaporation, and lake inflow accounting.
- `data/world/world_gen_balance.gd` — add latitude hydrology tuning parameters.
- `data/world/world_gen_balance.tres` — seed default latitude hydrology values.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document accumulation ownership, invariants, and Iteration 1.4 internal-only status.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.4.

#### Closure report
## Closure Report

### Implemented
- Added `_accumulation_grid` to `WorldPrePass` and computed it after D8 routing using a deterministic indegree queue over `_flow_dir_grid`.
- Added latitude-shaped hydrology: glacial-edge base contribution, hot-zone evaporation loss, and non-negative downstream transfer.
- Updated lake records so `inflow_accumulation` now reflects external inflow into each lake without promoting any new public pre-pass read channel.
- Added the latitude-hydrology balance knobs to `WorldGenBalance` / `world_gen_balance.tres`.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now includes accumulation ownership, invariants, and the still-internal read contract for Iteration 1.4.

### Root cause
- Iteration 1.3 produced deterministic downstream directions, but the pre-pass still had no canonical flow-volume layer. Without accumulation and latitude-aware transfer, later drainage, river extraction, erosion, and polar hydrology steps had no shared source of truth.

### Files changed
- `core/systems/world/world_pre_pass.gd` — accumulation storage, topological propagation, evaporation, glacial contribution, lake inflow bookkeeping.
- `data/world/world_gen_balance.gd` — `prepass_glacial_melt_temperature`, `prepass_glacial_melt_bonus`, `prepass_latitude_evaporation_rate`, `prepass_frozen_river_threshold`.
- `data/world/world_gen_balance.tres` — default values for the new latitude hydrology parameters.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, invariants, forbidden writes, and current-gap note updated for Iteration 1.4.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `_accumulation_grid` exists and stays index-aligned with the coarse pre-pass grid. — passed (file read)
- [x] Flow accumulation transfers downstream in topological order over `_flow_dir_grid`. — passed (file read)
- [x] Hot latitude zones lose downstream transfer through evaporation while keeping accumulation non-negative. — passed (file read)
- [x] Cold-to-temperate glacial edge cells receive stronger base contribution than deep frozen cells and hotter zones. — passed (file read)
- [ ] Runtime smoke / parse check in Godot. — blocked (no local Godot CLI discovered in this session)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_accumulation_grid`: 5 matches (lines 95, 195, 202, 207, 215) — updated
- Grep `DATA_CONTRACTS.md` for `inflow_accumulation`: 1 match (line 210) — updated
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: 1 match (line 220) — still accurate after update
- Grep `PUBLIC_API.md` for `_accumulation_grid|prepass_glacial_melt_temperature|prepass_glacial_melt_bonus|prepass_latitude_evaporation_rate|prepass_frozen_river_threshold|WorldPrePass|inflow_accumulation`: 0 matches — not referenced
- Section `Data Contracts изменения` / `PUBLIC_API.md изменения` in spec: exists — reviewed; current iteration updated canonical contracts now and left API promotion deferred because `WorldPrePass.sample()` intentionally remains height-only until later iterations

### Out-of-scope observations
- No project-local Godot executable or CLI alias was available, so runtime validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_accumulation_grid`, `inflow_accumulation`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `_accumulation_grid|prepass_glacial_melt_temperature|prepass_glacial_melt_bonus|prepass_latitude_evaporation_rate|prepass_frozen_river_threshold|WorldPrePass|inflow_accumulation` returned 0 matches

#### Blockers
- none

---

### Iteration 1.9 — Ridge graph construction
**Status**: completed
**Started**: 2026-04-03
**Completed**: 2026-04-03

#### Acceptance tests
- [x] `WorldPrePass.compute()` grows internal ridge paths from `_spine_seeds` before downstream hydrology steps. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 149, 507-518)
- [x] Main ridge growth picks among forward / forward-left / forward-right candidates using height, ruggedness, continuation inertia, and deterministic noise perturbation. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 530-575, 653-712)
- [x] Ridge growth stops deterministically on min-height, max-length, or merge with an existing ridge instead of overlapping it. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 534-585, 667-685, 888-911)
- [x] Branch ridges can split from main ridge paths using deterministic probability and shorter max length. — verified by file read in `core/systems/world/world_pre_pass.gd` (lines 598-649, 893-901)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose ridge-graph tuning knobs for length, branch probability, min height, and continuation inertia. — verified by file read in `data/world/world_gen_balance.gd` (lines 50-54) and `data/world/world_gen_balance.tres` (lines 38-42)
- [ ] Runtime smoke / parse check in Godot. — blocked (`Get-Command godot, godot4, gdlint, gdformat` returned command-not-found for all four tools)

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `_ridge_paths` found at lines 95, 195, 210, 228-230, 235 and updated; `prepass_max_ridge_length_grid|prepass_max_branch_length_grid` found at lines 228-229 and updated; `prepass_branch_probability|prepass_ridge_min_height|prepass_ridge_continuation_inertia` returned 0 matches; `WorldPrePass.sample` found at lines 96 and 240 and remained accurate
- [x] Grep `PUBLIC_API.md` for changed names — 0 matches for `_ridge_paths|prepass_max_ridge_length_grid|prepass_max_branch_length_grid|prepass_branch_probability|prepass_ridge_min_height|prepass_ridge_continuation_inertia|WorldPrePass.sample`
- [x] Documentation debt section reviewed — `DATA_CONTRACTS.md` updated for the new internal ridge graph; `PUBLIC_API.md` remains unchanged because Iteration 1.9 did not add a new safe entrypoint

#### Files touched
- `core/systems/world/world_pre_pass.gd` — add `RidgePath` records, bidirectional ridge growth from `_spine_seeds`, merge-without-overlap behavior, and deterministic branch spawning.
- `data/world/world_gen_balance.gd` — add ridge-graph tuning exports for max lengths, branch probability, min height, and continuation inertia.
- `data/world/world_gen_balance.tres` — seed default ridge-graph tuning values.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — document `_ridge_paths` ownership, invariants, and internal-only status.
- `.claude/agent-memory/active-epic.md` — track and close Iteration 1.9.

#### Closure report
## Closure Report

### Implemented
- Added internal `RidgePath` records to `WorldPrePass` and run a dedicated ridge-graph pass immediately after `_spine_seeds` are selected.
- Implemented deterministic bidirectional ridge growth from each spine seed using forward / forward-left / forward-right candidate arbitration over height, ruggedness, continuation inertia, and hash-based perturbation.
- Stopped ridge growth on the first deterministic blocker: low height, length budget exhaustion, or merge into an already-built ridge cell, without overlapping another path.
- Added deterministic branch generation from main ridge paths with a shorter branch budget.
- Added `prepass_max_ridge_length_grid`, `prepass_max_branch_length_grid`, `prepass_branch_probability`, `prepass_ridge_min_height`, and `prepass_ridge_continuation_inertia` to `WorldGenBalance` and the default `.tres`.
- Updated `DATA_CONTRACTS.md` so the `World Pre-pass` layer now includes internal ridge-path ownership and invariants while keeping the graph internal-only.

### Root cause
- Iteration 1.8 produced canonical tectonic spine seeds, but the pre-pass still had no owned ridge skeleton connecting them. Without an internal ridge graph, later spline smoothing, ridge distance fields, and mountain mass would have to regenerate mountain structure ad hoc instead of extending a canonical pre-pass artifact.

### Files changed
- `core/systems/world/world_pre_pass.gd` — ridge graph records, growth pass, branch generation, and new balance-backed stop conditions.
- `data/world/world_gen_balance.gd` — new ridge graph tuning exports.
- `data/world/world_gen_balance.tres` — default values for the new ridge graph parameters.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — `World Pre-pass` summary, invariants, forbidden writes, and current-gap note updated for `_ridge_paths`.
- `.claude/agent-memory/active-epic.md` — persistent task tracking updated for this step.

### Acceptance tests
- [x] `WorldPrePass.compute()` grows internal ridge paths from `_spine_seeds` before downstream hydrology steps. — passed (file read)
- [x] Main ridge growth picks among forward / forward-left / forward-right candidates using height, ruggedness, continuation inertia, and deterministic noise perturbation. — passed (file read)
- [x] Ridge growth stops deterministically on min-height, max-length, or merge with an existing ridge instead of overlapping it. — passed (file read)
- [x] Branch ridges can split from main ridge paths using deterministic probability and shorter max length. — passed (file read)
- [x] `WorldGenBalance` and `world_gen_balance.tres` expose ridge-graph tuning knobs for length, branch probability, min height, and continuation inertia. — passed (file read)
- [ ] Runtime smoke / parse check in Godot. — blocked (`Get-Command godot, godot4, gdlint, gdformat` returned command-not-found for all four tools)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `_ridge_paths`: matches at lines 95, 195, 210, 228-230, 235 — updated
- Grep `DATA_CONTRACTS.md` for `prepass_max_ridge_length_grid|prepass_max_branch_length_grid`: matches at lines 228-229 — updated
- Grep `DATA_CONTRACTS.md` for `prepass_branch_probability|prepass_ridge_min_height|prepass_ridge_continuation_inertia`: 0 matches — not referenced
- Grep `DATA_CONTRACTS.md` for `WorldPrePass.sample`: matches at lines 96 and 240 — still accurate
- Grep `PUBLIC_API.md` for `_ridge_paths|prepass_max_ridge_length_grid|prepass_max_branch_length_grid|prepass_branch_probability|prepass_ridge_min_height|prepass_ridge_continuation_inertia|WorldPrePass.sample`: 0 matches — not referenced
- Section `Required contract and API updates` / step-local spec guidance: exists at line 242 for the phase scaffold, and the Iteration 1.9 section plus ridge-skeleton parameter block are at lines 488-544 / 537-541 — reviewed; this iteration updated `DATA_CONTRACTS.md` now and left `PUBLIC_API.md` unchanged because ridge graph data remains internal to `WorldPrePass`

### Out-of-scope observations
- `WorldPrePass.sample()` still does not expose ridge data; Iteration 1.10+ will need to decide when smoothed ridge output or later `ridge_strength` becomes a readable channel without leaking raw graph internals too early.
- No project-local Godot CLI or GDScript linter/formatter was available, so runtime/static parser validation was not attempted in this session.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- updated — grep evidence recorded above for `_ridge_paths`, `prepass_max_ridge_length_grid`, `prepass_max_branch_length_grid`, and `WorldPrePass.sample`

### PUBLIC_API.md updated
- not required — grep for `_ridge_paths|prepass_max_ridge_length_grid|prepass_max_branch_length_grid|prepass_branch_probability|prepass_ridge_min_height|prepass_ridge_continuation_inertia|WorldPrePass.sample` returned 0 matches

#### Blockers
- none

## 2026-04-09 — Post-closure cleanup follow-up

### Status
- Removed local generated build artifacts after the native world-generation migration proof pass:
  - `gdextension/.sconsign.dblite`
  - `gdextension/src/chunk_generator.windows.template_debug.x86_64.obj`
  - `gdextension/src/register_types.windows.template_debug.x86_64.obj`
  - `gdextension/bin/~station_mirny.windows.template_debug.x86_64.dll~RF*.TMP`
- Cleanup stopped on the two tracked debug DLL outputs because they are currently locked by active local Godot editor processes.

### Blocker
- `Godot_v4.6.1-stable_win64.exe --editor` holds `gdextension/bin/~station_mirny.windows.template_debug.x86_64.dll`
- child play session process holds `gdextension/bin/station_mirny.windows.template_debug.x86_64.dll`

### Resolution
- After the user closed the editor and child play session, the remaining tracked debug DLL outputs were deleted:
  - `gdextension/bin/station_mirny.windows.template_debug.x86_64.dll`
  - `gdextension/bin/~station_mirny.windows.template_debug.x86_64.dll`
- Removed leftover preview proof images from `debug_exports/world_previews/` so the working tree no longer carries untracked verification artifacts from this migration.

## 2026-04-09 — Post-migration review: missing rivers / mountains

### Findings snapshot
- River runtime classification now appears vulnerable to a unit mismatch:
  - `WorldPrePass` stores `river_distance` on the coarse pre-pass grid (`prepass_grid_step = 32`) and samples it bilinearly per tile.
  - `SurfaceTerrainResolver` compares that sampled distance against tile-scale radii derived from `river_width` defaults (`~0.9..1.3` for the river core on base-width rivers).
  - This can make most tiles inside a coarse river source cell read as too far from the river core, collapsing visible runtime water/bank tiles even when the pre-pass says a river exists.
- Hydrology also has an apparent glacial-melt inversion:
  - `_resolve_base_accumulation()` gives the largest melt bonus near the melt threshold and removes it again in colder cells.
  - That weakens cold-source runoff and compounds river scarcity when river seeding already depends on a high accumulation threshold.
- Mountain coverage in the new authoritative system is likely much sparser than the legacy band world:
  - default `prepass_target_spine_count = 4`
  - default `prepass_min_spine_distance_grid = 80`
  - ridge graph growth only originates from those seeds
- Mountain terrain classification appears to double-discount non-peak ridges:
  - `mountain_mass` already multiplies ridge by height and ruggedness in `WorldPrePass`
  - `SurfaceTerrainResolver` then multiplies the mountain decision by another height/ruggedness/slope terrain gate

### Status
- Review only; no code changes applied for this follow-up yet.
