# Feature: Living Rivers, Lakes, And Hydrology World Settings

## Design Intent

Игрок должен видеть в обычном surface-мире не редкие случайные полосы воды, а длинные читаемые речные системы и заметные озёрные чаши, которые выглядят как часть рельефа, а не как исключение из него.

Пользователь также должен получать явные настройки рек и озёр на экране создания мира, чтобы один и тот же seed можно было запускать с более сухой или более водной гидрологией без ручной правки `.tres`.

## Current Diagnosis

На текущем checkout подтверждено:

- `WorldPrePass` уже считает hydrology truth: `_river_width_grid`, `_river_distance_grid`, `_floodplain_strength_grid`, `_lake_mask`, `_lake_records`.
- fixed-seed structure visibility proof для `seed=12345` показывает severe coverage gap:
  - central 50% latitude span имеет `visible_river_samples=0` во всех четырёх central bands;
  - `nearest_visible_water=none`;
  - `nearest_visible_bank=(4048, -2096)` на расстоянии `2096.5` tiles;
  - при этом `nearest_authoritative_river=(3184, -464)` уже существует на расстоянии `1023.2` tiles.
- экран `WorldCreationScreen` экспонирует только mountain knobs, хотя hydrology tuning уже существует в `WorldGenBalance`.
- save/load generation payload сохраняет только mountain settings, поэтому per-world hydrology overrides сейчас не восстанавливаются.

Итог:

- проблема не только в `WorldPrePass`, но и в handoff `authoritative hydrology -> visible WATER/SAND`;
- озёра вычисляются внутри pre-pass, но почти не участвуют в surface terrain consumer path;
- мир creation UX не даёт игроку контролировать hydrology.

## Performance / Scalability Contract

- Runtime class:
  - `boot` для hydrology compute и lake integration.
  - `interactive` только для UI slider changes до старта мира.
  - `save/load boundary` для generation overrides.
- Target scale / density:
  - весь wrapped world pre-pass snapshot при `world_wrap_width_tiles=4096`, `latitude_half_span_tiles=4096`, `prepass_grid_step=32`;
  - все surface chunks читают одну опубликованную authoritative hydrology truth.
- Authoritative source of truth:
  - tunables: `WorldGenBalance`;
  - generated hydrology truth: `WorldPrePass`;
  - published runtime owner: `WorldGenerator`.
- Write owner:
  - `WorldCreationScreen` записывает generation overrides до старта мира;
  - `SaveAppliers.apply_world()` восстанавливает сохранённые generation overrides;
  - `WorldPrePass.compute()` единственный пишет derived hydrology grids.
- Derived/cache state:
  - `_river_mask_grid`, `_river_width_grid`, `_river_distance_grid`, `_floodplain_strength_grid`, `_lake_mask`, `_lake_records`;
  - chunk-local authoritative input snapshots;
  - native `ChunkGenerator` snapshot mirror.
- Dirty unit:
  - whole-world pre-pass snapshot at new-game / load boundary only.
- Allowed synchronous work:
  - UI slider updates;
  - copying generation payload into runtime balance;
  - save/load dictionary reads and writes.
- Escalation path:
  - heavy hydrology compute stays inside existing `WorldGenerator.begin_initialize_world_async()` worker path and existing native chunk generation parity path.
- Degraded mode:
  - loading screen during world initialization is acceptable;
  - no new runtime catch-up loop is introduced for hydrology.
- Forbidden shortcuts:
  - no fake post-hoc water painting unrelated to `WorldPrePass`;
  - no separate mutable lake terrain truth outside existing hydrology channels;
  - no per-frame hydrology recompute;
  - no world settings that affect new-game only but disappear after save/load.

## Data Contracts - Affected

### Affected layer: World Pre-pass

- Что меняется:
  - hydrology rebalance may reduce extreme-latitude bias in river extraction;
  - lake basins may feed already-published hydrology channels so lakes reach the terrain consumer through the same authoritative path.
- New invariants:
  - `WorldPrePass` remains the only authoritative source of hydrology truth;
  - same seed + same generation settings -> same pre-pass snapshot;
  - lake contribution must not create a second independent terrain water path.
- What does not change:
  - no runtime mutation path is added;
  - no save serialization of pre-pass grids;
  - compute remains boot-only.

### Affected layer: World / terrain consumer

- Что меняется:
  - `SurfaceTerrainResolver` and native `ChunkGenerator` must make central-band rivers more discoverable from the same pre-pass truth;
  - hydrology-fed water bodies must become visible `WATER` / `SAND` without inventing a parallel water system.
- New invariants:
  - script/native parity remains mandatory;
  - terrain truth still resolves from authoritative pre-pass-backed inputs, not from ad-hoc overrides.
- What does not change:
  - canonical terrain enum stays `GROUND / ROCK / WATER / SAND`;
  - spawn safety and land guarantee remain in force.

### Affected layer: Save / load orchestration

- Что меняется:
  - per-world hydrology generation overrides must be stored and restored together with existing mountain settings.
- New invariants:
  - generation overrides restore through `SaveManager -> SaveAppliers.apply_world()`;
  - missing old-save fields fall back safely to current runtime balance defaults.
- What does not change:
  - chunk diff save shape;
  - world terrain base/diff ownership.

### Affected layer: World creation UI

- Что меняется:
  - the start-of-world screen exposes user-facing river and lake controls.
- New invariants:
  - all new labels use localization keys;
  - UI writes balance values only before world initialization begins.
- What does not change:
  - screen remains presentation-only;
  - same seed + same settings still yields the same world.

## Required Contract And API Updates

- `DATA_CONTRACTS.md`:
  - update required if hydrology channel semantics broaden to include lake-fed water-body visibility through existing pre-pass channels;
  - update required if save/load world generation payload semantics become newly documented.
- `PUBLIC_API.md`:
  - update required if documented meaning of pre-pass-backed structure / terrain semantics changes;
  - otherwise grep proof is still mandatory before saying `not required`.
- Other canonical docs:
  - localization files require RU/EN coverage for new world-creation labels.

## Iterations

### Iteration 1 - Hydrology Visibility And World Settings

Goal: make rivers and lakes visible in normal play bands and expose the main hydrology knobs at world start without introducing a second truth path.

What will be done:

- rebalance `WorldPrePass` hydrology extraction so central bands stop collapsing to almost no visible rivers;
- integrate lake basins into the existing hydrology channels that already feed script/native terrain consumers;
- adjust surface/native water and bank thresholds only as needed to make authoritative hydrology visible;
- add world-creation controls for rivers and lakes;
- persist those generation overrides through save/load.

Acceptance tests:

- [ ] fixed-seed structure visibility proof for `seed=12345` shows non-zero visible river or bank samples inside the central 50% latitude span.
- [ ] `nearest_visible_water` is no longer `none` for `seed=12345`.
- [ ] structure visibility proof still reports `native_sample_failures=0` and `terrain_mismatches=0`.
- [ ] `WorldCreationScreen` exposes localized river and lake controls and maps them to `WorldGenBalance`.
- [ ] `SaveCollectors.collect_world()` and `SaveAppliers.apply_world()` include the new hydrology generation fields with backward-safe fallback.
- [ ] visual shape changes remain routed through `WorldPrePass -> WorldComputeContext/authoritative inputs -> SurfaceTerrainResolver/ChunkGenerator`, not through a second water override path.

Files allowed for this iteration:

- `docs/02_system_specs/world/hydrology_world_settings_spec.md`
- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/world_compute_context.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/autoloads/world_generator.gd`
- `gdextension/src/chunk_generator.cpp`
- `gdextension/src/chunk_generator.h`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `scenes/ui/world_creation_screen.gd`
- `locale/ru/messages.po`
- `locale/en/messages.po`
- `core/autoloads/save_collectors.gd`
- `core/autoloads/save_appliers.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` if semantics change
- `docs/00_governance/PUBLIC_API.md` if semantics change

Files that must not be touched:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- mining / topology / reveal runtime paths
- unrelated UI screens
- unrelated save/load collectors or appliers

