# Epic: World Grid Rebuild

**Spec**: docs/02_system_specs/world/world_grid_rebuild_foundation.md
**Started**: 2026-04-18
**Current iteration**: 2
**Total iterations**: 3

## Documentation debt

- [x] Living world-grid contract introduced in canonical docs
- [ ] Save compatibility boundary for removed `64 x 64` world runtime - decide in iteration 3 or dedicated migration task
- [ ] Shared runtime constant home for tile/chunk size - decide in iteration 2
- **Deadline**: after iteration 3
- **Status**: in_progress

## Iterations

### Iteration 1 - Contract establishment
**Status**: completed
**Started**: 2026-04-18
**Completed**: 2026-04-18

#### Проверки приёмки (Acceptance tests)
- [x] `docs/00_governance/PROJECT_GLOSSARY.md` states `32 px` tile and `32 x 32` chunk contract
- [x] `data/balance/building_balance.tres` sets `grid_size = 32`
- [x] surviving world-facing scripts no longer contain `64 px` or `12 px` tile-size fallbacks

#### Doc check
- [x] Grep living canonical docs for changed names and removed legacy paths - matches checked in `docs/README.md`, the world spec, and the glossary
- [x] Grep living docs for `32x32`, `32 px`, and `grid_size` - matches found in glossary, docs indexes, and the new world-grid spec
- [x] Documentation debt section reviewed

#### Files touched
- `docs/02_system_specs/world/world_grid_rebuild_foundation.md` - canonical rebuild contract for tile/chunk sizing
- `docs/02_system_specs/README.md` - system spec index now links the new world spec
- `docs/README.md` - top-level docs index now links the new world spec
- `docs/00_governance/PROJECT_GLOSSARY.md` - chunk definition moved to `32x32`; new tile entry added
- `data/balance/building_balance.tres` - building/world grid size aligned to `32`
- `core/entities/player/player_visibility_indicator.gd` - fallback tile radius scale aligned to `32 px`
- `core/entities/structures/z_stairs.gd` - stair footprint aligned to one `32 px` tile
- `core/entities/structures/ark_battery.gd` - placeholder footprint aligned to one `32 px` tile
- `core/entities/structures/thermo_burner.gd` - placeholder footprint aligned to one `32 px` tile

#### Отчёт о выполнении (Closure Report)
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлена каноническая спецификация перестройки world grid: `docs/02_system_specs/world/world_grid_rebuild_foundation.md`.
- Обновлены индексы документации и глоссарий, чтобы rebuild-контракт явно фиксировал `tile = 32 px` и `chunk = 32 x 32`.
- Выставлен `grid_size = 32` в `data/balance/building_balance.tres`.
- Убраны surviving world-facing fallback-допущения `64 px` и `12 px` из `player_visibility_indicator.gd`, `z_stairs.gd`, `ark_battery.gd`, `thermo_burner.gd`.

### Корневая причина (Root cause)
- После удаления старого world stack в репо не осталось живого источника истины для размеров тайла и чанка, а в данных и surviving скриптах продолжали жить legacy-значения `64` и `12`.

### Изменённые файлы (Files changed)
- `docs/02_system_specs/world/world_grid_rebuild_foundation.md`
- `docs/02_system_specs/README.md`
- `docs/README.md`
- `docs/00_governance/PROJECT_GLOSSARY.md`
- `data/balance/building_balance.tres`
- `core/entities/player/player_visibility_indicator.gd`
- `core/entities/structures/z_stairs.gd`
- `core/entities/structures/ark_battery.gd`
- `core/entities/structures/thermo_burner.gd`
- `.claude/agent-memory/active-epic.md`

### Проверки приёмки (Acceptance tests)
- [x] Глоссарий и world-spec фиксируют `32 px` tile и `32 x 32` chunk - прошло (passed) (проверено `rg -n "32x32|32 x 32|32 px"` по `PROJECT_GLOSSARY.md`, новому spec и docs indexes)
- [x] `data/balance/building_balance.tres` задаёт `grid_size = 32` - прошло (passed) (проверено `rg -n "grid_size = 32" data/balance/building_balance.tres`)
- [x] В surviving world-facing scripts больше нет fallback `64 px` / `12 px` - прошло (passed) (проверено положительным grep по новым `32`-константам и отрицательным grep, вернувшим 0 совпадений для старых значений)

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `rg` по docs/code значениям `32`, `git diff --check`
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): при возврате runtime мира проверить, что одноклеточные объекты и радиус видимости визуально совпадают с сеткой `32 px`

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): добавлены только docs/data/constant changes; новых интерактивных циклов или broad rebuild path не введено
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy
- Ручная проверка пользователем (Manual human verification): не требуется
- Рекомендованная проверка пользователем (Suggested human check): в iteration 2/3 проверить, что streaming и save shard boundaries реально работают как `32 x 32`

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep living docs for `Chunk`, `grid_size`, `32 px`, and legacy removed paths: matches checked in `docs/README.md`, `docs/02_system_specs/world/world_grid_rebuild_foundation.md`, and `docs/00_governance/PROJECT_GLOSSARY.md`
- Legacy contract/API docs are absent from the repo and treated as removed names, not living contract targets
- Секция "Required updates" в спеке: есть - выполнено в этой же итерации (новый spec, docs index, glossary, live balance/resource cleanup)

### Наблюдения вне задачи (Out-of-scope observations)
- Текущая ветка всё ещё не содержит `Chunk`, `ChunkManager` и `GameWorld`; `Play` ведёт в `world_rebuild_notice`, а не в runtime мира

### Оставшиеся блокеры (Remaining blockers)
- Следующая итерация должна заново ввести минимальный world runtime, который потребляет этот контракт

### Обновление канонических документов (Canonical docs updated)
- Обновлены living canonical docs: новый world spec, docs indexes, glossary, и live resource/data references

#### Blockers
- Rebuilt world runtime (`Chunk`, `ChunkManager`, `GameWorld`) is intentionally absent in the current branch, so chunk-size implementation work beyond contract/data cleanup must happen in later iterations.

---

### Iteration 2 - World runtime scaffold
**Status**: pending

### Iteration 3 - Streaming, save, and rebuild implementation
**Status**: pending
