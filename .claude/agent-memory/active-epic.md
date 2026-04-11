# Epic: Living Rivers, Lakes, And Hydrology World Settings

**Spec**: docs/02_system_specs/world/hydrology_world_settings_spec.md
**Started**: 2026-04-11
**Current iteration**: 1
**Total iterations**: 1

## Documentation debt

- [x] DATA_CONTRACTS.md - updated for shared visible hydrology handoff (`river_width` / `river_distance`) covering rivers and qualifying lake basins.
- [x] PUBLIC_API.md - updated for `sample_structure_context()` / `WorldPrePass.sample()` hydrology semantics.
- [x] Localization files - added RU/EN keys for new world-creation river/lake controls.
- **Deadline**: after iteration 1
- **Status**: completed

## Iterations

### Iteration 1 - Hydrology visibility and world settings

**Status**: completed
**Started**: 2026-04-11
**Completed**: 2026-04-11

#### Проверки приёмки (Acceptance tests)

- [x] fixed-seed structure visibility proof for `seed=12345` shows non-zero visible river or bank samples inside the central 50% latitude span
- [x] `nearest_visible_water` is no longer `none` for `seed=12345`
- [x] structure visibility proof still reports `native_sample_failures=0` and `terrain_mismatches=0`
- [x] `WorldCreationScreen` exposes localized river and lake controls and maps them to `WorldGenBalance`
- [x] `SaveCollectors.collect_world()` and `SaveAppliers.apply_world()` include the new hydrology generation fields with backward-safe fallback
- [x] visual shape changes still route through the authoritative hydrology path instead of a second water override layer

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed hydrology names - completed
- [x] Grep PUBLIC_API.md for changed hydrology names - completed
- [x] Documentation debt section reviewed - completed

#### Files touched

- `docs/02_system_specs/world/hydrology_world_settings_spec.md` - new feature spec
- `.claude/agent-memory/active-epic.md` - new active epic tracker
- `core/systems/world/world_pre_pass.gd` - lake-aware visible hydrology seeding, native distance recompute, conservative lake floodplain shaping
- `data/world/world_gen_balance.gd` - new default hydrology balance values
- `data/world/world_gen_balance.tres` - serialized hydrology defaults
- `scenes/ui/world_creation_screen.gd` - river/lake sliders and world-start mapping
- `core/autoloads/save_collectors.gd` - hydrology generation save payload
- `core/autoloads/save_appliers.gd` - hydrology generation restore payload
- `locale/ru/messages.po` - RU labels/hint for new controls
- `locale/en/messages.po` - EN labels/hint for new controls
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - hydrology contract update
- `docs/00_governance/PUBLIC_API.md` - public hydrology semantics update

#### Отчёт о выполнении (Closure Report)

See session closure report on 2026-04-11. Key proof artifacts:
- `debug_exports/world_previews/river_baseline_seed12345.log`
- `debug_exports/world_previews/river_after_defaults_seed12345.log`
- `debug_exports/world_previews/structure_coverage_seed12345_1775881292.txt`

#### Blockers

- none
