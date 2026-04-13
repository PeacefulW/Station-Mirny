# Epic: Chunk System Refactor

**Spec**: docs/04_execution/chunk_system_refactor_spec_2026-04-12.md
**Started**: 2026-04-12
**Current iteration**: 10
**Total iterations**: 10
**Latest follow-up**: 2026-04-12 Iteration 10 completed (final contract freeze and dead-code deletion)

## Documentation debt

- [x] DATA_CONTRACTS.md - record native-only topology rebuild, native loaded open-pocket mirror ownership, and `truncated` semantics for unloaded boundary vs native tile cap.
- [x] PUBLIC_API.md - record `query_local_underground_zone()` native-only traversal semantics and `truncated` behavior.
- **Deadline**: after iteration 1 if semantics change
- **Status**: done

## Iterations

### Iteration 1 - Native-only contract and fail-fast startup

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] boot fails loudly and clearly if required native classes are missing
- [x] surface topology no longer has dual implementations
- [x] underground local zone query no longer has dual implementations
- [x] no code path silently downgrades behavior

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed
- [x] Grep PUBLIC_API.md for changed names - completed
- [x] Documentation debt section reviewed - completed

#### Files touched

- `.claude/agent-memory/active-epic.md` - tracker switched to chunk refactor and iteration 1 closure recorded
- `core/systems/world/chunk_manager.gd` - fail-fast native validation, native open-pocket query wiring, topology fallback retirement
- `gdextension/src/loaded_open_pocket_query.h` - native active-z open-pocket query interface
- `gdextension/src/loaded_open_pocket_query.cpp` - native capped open-pocket traversal implementation
- `gdextension/src/register_types.cpp` - GDExtension registration for the new native query class
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - native-only topology/query contract update
- `docs/00_governance/PUBLIC_API.md` - query semantics update

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- В `chunk_manager.gd` добавлена единоразовая проверка обязательных native-классов на старте: `MountainTopologyBuilder` для перестройки топологии (topology rebuild) и `LoadedOpenPocketQuery` для локального запроса открытого кармана (open-pocket query).
- Production fallback для синхронной GDScript-перестройки топологии (GDScript topology rebuild fallback) больше не выполняется: старые ветки теперь останавливаются через `push_error()` + `assert()`, а worker rebuild принимает только native snapshot path.
- `query_local_underground_zone()` переведён на native `LoadedOpenPocketQuery`, который держит derived active-z mirror текущих loaded chunks, обновляется на load/unload/mining и жёстко ограничивает обход через `LOADED_OPEN_POCKET_QUERY_TILE_CAP`.
- Контрактная документация обновлена под новый native-only режим и новую семантику `truncated`, которая теперь означает не только выход на unloaded continuation, но и достижение hard cap native query.

### Корневая причина (Root cause)
- Первая итерация спеки закрывает архитектурную двусмысленность: surface topology rebuild и local open-pocket query жили в dual-path режиме, где production мог молча скатиться в GDScript fallback. Это противоречило fail-fast политике и размывало контракт владения native/runtime path.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_manager.gd` - fail-fast native validation, active-z open-pocket mirror wiring, topology fallback retirement.
- `gdextension/src/loaded_open_pocket_query.h` - объявление native kernel для capped open-pocket traversal.
- `gdextension/src/loaded_open_pocket_query.cpp` - реализация native cardinal traversal с wrap-aware X canonicalization и hard cap.
- `gdextension/src/register_types.cpp` - регистрация `LoadedOpenPocketQuery`.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - контракт topology/query обновлён под native-only path и новый derived mirror.
- `docs/00_governance/PUBLIC_API.md` - описание `query_local_underground_zone()` приведено к новой native-only semantics.

### Проверки приёмки (Acceptance tests)
- [x] boot fails loudly and clearly if required native classes are missing — прошло (passed); проверено статически: `chunk_manager.gd` добавляет fail-fast ветки в `_validate_required_native_capabilities()`, `_create_topology_worker_builder()`, `_worker_build_topology_snapshot()` и `query_local_underground_zone()`.
- [x] surface topology no longer has dual implementations — прошло (passed); проверено статически: `chunk_manager.gd` больше не выполняет production GDS rebuild path, а `_ensure_topology_current()` и `_rebuild_loaded_mountain_topology()` теперь fail-fast вместо тихого fallback.
- [x] underground local zone query no longer has dual implementations — прошло (passed); проверено статически и сборкой: `query_local_underground_zone()` вызывает native `query_open_pocket`, добавлен и собран `LoadedOpenPocketQuery`.
- [x] no code path silently downgrades behavior — прошло (passed); проверено статически: missing-native paths теперь завершаются через `push_error()` + `assert()`, а не через fallback degradation.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `python -m SCons -Q -j1` в `gdextension/` — сборка успешна; `git diff --check` — без замечаний; точечные чтения `chunk_manager.gd` показали fail-fast в `_ensure_topology_current()` (строки 6312-6322) и `_worker_build_topology_snapshot()` (строки 6542-6552).
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): запустить игру с собранной GDExtension, затем проверить сценарии `S-01`, `S-03`, `S-05`, `S-06` из `chunk_system_refactor_spec_2026-04-12.md`; отдельно, при желании, временно сломать загрузку DLL и убедиться, что boot падает с явной ошибкой вместо тихого fallback.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): local open-pocket query больше не делает GDS flood fill по loaded chunk nodes; запрос идёт в native kernel с hard cap `LOADED_OPEN_POCKET_QUERY_TILE_CAP = 65536`, а active-z mirror обновляется только через load/unload/mining и rebuild на z-switch.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): в underground пройтись по mined pocket, затем добыть тайл рядом с границей и убедиться, что local zone / fog reveal продолжают работать без regressions при смене z-level.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `query_local_underground_zone`: есть совпадения на строках 56, 410, 412, 415, 416, 866, 881, 903 — обновлено.
- Grep DATA_CONTRACTS.md для `LoadedOpenPocketQuery`: есть совпадения на строках 56, 410, 417, 418, 881, 902 — обновлено.
- Grep DATA_CONTRACTS.md для `MountainTopologyBuilder`: есть совпадения на строках 55, 369, 370, 380, 382 — обновлено.
- Grep PUBLIC_API.md для `query_local_underground_zone`: есть совпадения на строках 346-349 — обновлено.
- Grep PUBLIC_API.md для `LoadedOpenPocketQuery`: есть совпадение на строке 349 — обновлено.
- Grep PUBLIC_API.md для `MountainTopologyBuilder`: 0 совпадений — not referenced.
- Секция "Required updates" в спеке: нет — `rg` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- В `chunk_manager.gd` всё ещё остаётся большой объём уже-retired topology helper кода ниже fail-fast веток; это ожидаемо для Iteration 1 и должно чиститься в поздних cleanup/decomposition итерациях, а не сейчас.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: topology ownership/native-only rebuild, новый loaded open-pocket query layer, `truncated` semantics и derived mirror ownership; grep-доказательство приведено выше.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Обновлено: `query_local_underground_zone()` теперь описан как native `LoadedOpenPocketQuery` path с `truncated` на unloaded continuation или hard cap; grep-доказательство приведено выше.

#### Blockers

- none

---

### Iteration 8 - Native heavy-work pass

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] no runtime pixel-loop interior macro generation remains in GDScript for the production path
- [x] underground zone query is fully native-backed
- [ ] feature behavior remains correct in validation scenarios - manual human verification required

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; interior macro presentation contract updated, underground query contract re-checked
- [x] Grep PUBLIC_API.md for changed names - completed; query docs still accurate, interior macro helpers remain internal-only
- [x] Documentation debt section reviewed - completed; spec has no separate `Required updates` / `Documentation debt` section

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 8 started/completed with closure evidence
- `core/systems/world/chunk.gd` - interior macro path re-enabled and routed through native overlay compute instead of GDScript pixel-loop generation
- `gdextension/src/chunk_visual_kernels.h` - native visual kernel API extended with interior macro overlay entrypoint
- `gdextension/src/chunk_visual_kernels.cpp` - native interior macro RGBA generation implemented and bound for GDScript apply
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - presentation contract updated for active native-backed interior macro overlay

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- В `chunk.gd` interior macro overlay снова включён и больше не строит `Image` через GDScript pixel-loop: `Chunk` теперь только собирает chunk-local target mask и применяет готовую texture.
- В `ChunkVisualKernels` добавлен native entrypoint `build_interior_macro_overlay()`, который генерирует RGBA overlay для interior macro по deterministic world-space sampling и biome tint data.
- `query_local_underground_zone()` дополнительно перепроверен как native-only path без возврата к GDScript fallback.
- `DATA_CONTRACTS.md` синхронизирован с новой owner boundary: interior macro compute живёт в native visual kernel, а `Chunk` остаётся apply-owner'ом Sprite2D layer.

### Корневая причина (Root cause)
- После раннего rollback interior macro overlay в коде всё ещё оставался GDScript path с per-pixel `Image` generation, который был несовместим с целью Iteration 8: тяжёлый pixel/algorithmic work должен жить в native compute, а не в script runtime path.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk.gd` - native-backed interior macro request/apply path, fail-fast guard for missing native helper, feature flag re-enabled.
- `gdextension/src/chunk_visual_kernels.h` - declared native interior macro overlay API.
- `gdextension/src/chunk_visual_kernels.cpp` - implemented native interior macro RGBA generation and binding.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - interior macro presentation ownership updated.
- `.claude/agent-memory/active-epic.md` - iteration 8 progress and closure recorded.

### Проверки приёмки (Acceptance tests)
- [x] `no runtime pixel-loop interior macro generation remains in GDScript for the production path` - прошло (passed); проверено статически (static verification): `rg -n "set_pixel\\(|Image\\.create\\(" core/systems/world/chunk.gd` вернул `0 matches`, а `rg -n "create_from_data\\(|build_interior_macro_overlay" core/systems/world/chunk.gd gdextension/src/chunk_visual_kernels.cpp gdextension/src/chunk_visual_kernels.h` подтвердил native compute + GDS apply path.
- [x] `underground zone query is fully native-backed` - прошло (passed); проверено статически (static verification): `rg -n "func query_local_underground_zone|query_open_pocket|LOADED_OPEN_POCKET_QUERY_TILE_CAP|NATIVE_LOADED_OPEN_POCKET_QUERY_CLASS" core/systems/world/chunk_manager.gd` и чтение `chunk_manager.gd` на строках 1720-1738 показывают direct native `query_open_pocket` call и fail-fast при отсутствии `LoadedOpenPocketQuery`.
- [ ] `feature behavior remains correct in validation scenarios` - требуется ручная проверка пользователем (manual human verification required); visual/runtime сценарии для interior macro publication и underground query agent-run не запускались по policy.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `python -m SCons -Q -j1` в `gdextension` - `exit 0`, DLL пересобрана с новым `ChunkVisualKernels`.
- Статическая проверка (Static verification): `Godot_v4.6.1-stable_win64_console.exe --headless --path C:/Users/peaceful/Station Peaceful/Station Peaceful --quit` - `exit 0`.
- Статическая проверка (Static verification): `git diff --check -- .claude/agent-memory/active-epic.md core/systems/world/chunk.gd gdextension/src/chunk_visual_kernels.cpp gdextension/src/chunk_visual_kernels.h docs/02_system_specs/world/DATA_CONTRACTS.md` - без замечаний.
- Статическая проверка (Static verification): `rg -n "set_pixel\\(|Image\\.create\\(" core/systems/world/chunk.gd` - `0 matches`.
- Статическая проверка (Static verification): `rg -n "create_from_data\\(|build_interior_macro_overlay" core/systems/world/chunk.gd gdextension/src/chunk_visual_kernels.cpp gdextension/src/chunk_visual_kernels.h` подтвердил native interior macro compute и отсутствие возврата к GDScript pixel-loop.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): прогнать `S-02`, `S-04`, `S-05` и `S-06` из `docs/04_execution/chunk_system_refactor_spec_2026-04-12.md`; отдельно пройтись по freshly loaded surface/underground chunks и убедиться, что interior macro overlay появляется без визуальных швов, а local underground zone / fog reveal не деградировали.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): runtime work class для interior macro остаётся `presentation-only` derived work с dirty unit = один chunk overlay; тяжёлый sample/pixel compute перенесён в native `ChunkVisualKernels`, а `Chunk` на основном потоке (main thread) только создаёт `ImageTexture` из готового RGBA buffer.
- Статическая проверка (Static verification): `query_local_underground_zone()` остаётся native-backed read поверх active-z loaded mirror `LoadedOpenPocketQuery`; synchronous GDS flood-fill path не вернулся.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): при ручном прогоне `S-04`/`S-05` обратить внимание на отсутствие новых frame spikes при redraw/publish после mining и при underground reveal.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `_refresh_interior_macro_layer`: есть совпадения на строках 646 и 739 - обновлено под active native-backed overlay.
- Grep DATA_CONTRACTS.md для `build_interior_macro_overlay`: есть совпадение на строке 739 - обновлено.
- Grep DATA_CONTRACTS.md для `query_local_underground_zone`: есть совпадения на строках 56, 416, 418, 421, 422, 899, 914, 936, 1642 - актуально, контракт уже отражает native-only query.
- Grep DATA_CONTRACTS.md для `LoadedOpenPocketQuery`: есть совпадения на строках 56, 416, 423, 424, 935 - актуально.
- Grep PUBLIC_API.md для `_refresh_interior_macro_layer|build_interior_macro_overlay`: `0 matches` - internal presentation helpers, public API update не требовался.
- Grep PUBLIC_API.md для `query_local_underground_zone|LoadedOpenPocketQuery`: есть совпадения на строках 347 и 350 - актуально.
- Секция "Required updates" в спеке: нет - `rg -n "Documentation debt|Required updates|Required contract and API updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- `chunk.gd` по-прежнему остаётся крупным orchestration/presentation owner, а следующий крупный кусок архитектурного долга уже явно сидит в Iteration 9 (`chunk_manager` decomposition + scheduler/cache/seam extraction).

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: interior macro overlay contract теперь фиксирует active native-backed compute path через `_refresh_interior_macro_layer()` и `ChunkVisualKernels.build_interior_macro_overlay()`; grep-доказательство приведено выше.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) - `rg -n "_refresh_interior_macro_layer|build_interior_macro_overlay" docs/00_governance/PUBLIC_API.md` вернул `0 matches`, а существующие записи для `query_local_underground_zone|LoadedOpenPocketQuery` на строках 347 и 350 остаются актуальными.

#### Blockers

- none

---

### Iteration 9 - Manager decomposition pass 2 and scheduler cleanup

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] `chunk_manager.gd` is visibly reduced to orchestration/public API
- [x] scheduler internals are owned by the dedicated scheduler module
- [x] cache internals are owned by the cache module
- [x] seam internals are owned by the seam module

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; new scheduler/cache/seam owners documented
- [x] Grep PUBLIC_API.md for changed names - completed; new services documented as internal-only, not public gameplay APIs
- [x] Documentation debt section reviewed - completed; spec has no separate `Required updates` / `Documentation debt` section

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 9 started/completed with closure evidence
- `core/systems/world/chunk_manager.gd` - scheduler/cache/seam state moved behind services; manager wrappers retained for owner-facing orchestration
- `core/systems/world/chunk_visual_scheduler.gd` - new visual scheduler owner for queues, task maps, compute maps, telemetry containers, and scheduler tick facades
- `core/systems/world/chunk_visual_scheduler.gd.uid` - Godot UID for the new scheduler script
- `core/systems/world/chunk_surface_payload_cache.gd` - new surface payload/flora cache owner with bounded LRU state
- `core/systems/world/chunk_surface_payload_cache.gd.uid` - Godot UID for the new cache script
- `core/systems/world/chunk_seam_service.gd` - new seam refresh queue and border follow-up owner
- `core/systems/world/chunk_seam_service.gd.uid` - Godot UID for the new seam service script
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - ownership layers and postconditions updated for scheduler/cache/seam split
- `docs/00_governance/PUBLIC_API.md` - internal-service boundary documented

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- `ChunkManager` разгружен от трёх mutable responsibility buckets: visual scheduler state, surface payload cache и seam refresh queue.
- Добавлен `ChunkVisualScheduler`: владеет очередями визуальных задач (visual task queues), версиями задач (task versions), active/waiting/result maps для worker visual compute, apply-feedback и scheduler tick façade (`tick_budget()` / `tick_once()`).
- Добавлен `ChunkSurfacePayloadCache`: владеет surface z=0 cache entries, LRU touch-order и duplicated native/flora payload reuse.
- Добавлен `ChunkSeamService`: владеет pending seam refresh queue, duplicate-suppression lookup, neighbor border enqueue flow и mining-side seam follow-up repair.
- `DATA_CONTRACTS.md` и `PUBLIC_API.md` обновлены: новые сервисы зафиксированы как internal owners, не как public gameplay APIs.

### Корневая причина (Root cause)
- Iteration 9 закрывала архитектурный долг: `chunk_manager.gd` всё ещё смешивал orchestration/public API с runtime-only scheduler/cache/seam state ownership. Это размывало single-owner boundary и усложняло будущий cleanup/freeze.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_manager.gd` - thin service wiring/facades for scheduler/cache/seam ownership.
- `core/systems/world/chunk_visual_scheduler.gd` и `.uid` - новый internal owner scheduler state.
- `core/systems/world/chunk_surface_payload_cache.gd` и `.uid` - новый internal owner surface payload cache.
- `core/systems/world/chunk_seam_service.gd` и `.uid` - новый internal owner seam repair queue.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - новые слои/owners/invariants/postconditions.
- `docs/00_governance/PUBLIC_API.md` - internal-only service boundary.
- `.claude/agent-memory/active-epic.md` - Iteration 9 status/closure.

### Проверки приёмки (Acceptance tests)
- [x] `chunk_manager.gd` is visibly reduced to orchestration/public API - прошло (passed); проверено статически (static verification): line-count после extraction `chunk_manager.gd = 6392`, новые service files `195 / 137 / 131` строк; до extraction в этой сессии `chunk_manager.gd = 6661`.
- [x] scheduler internals are owned by the dedicated scheduler module - прошло (passed); проверено `rg`: `ChunkVisualScheduler` содержит `q_terrain_fast`, `task_versions`, `compute_active`, `clear_runtime_state()`, `tick_budget()` и `tick_once()`, а `ChunkManager._tick_visuals_budget()` делегирует в scheduler.
- [x] cache internals are owned by the cache module - прошло (passed); проверено `rg`: `ChunkSurfacePayloadCache` содержит `_entries`, `_touch_order`, `cache_native_payload()`, `cache_flora_payload()`, `try_get_native_data()`, а в `chunk_manager.gd` больше нет `var _surface_payload_cache`, `_surface_payload_cache_order` или `_surface_payload_cache_touch_serial`.
- [x] seam internals are owned by the seam module - прошло (passed); проверено `rg`: `ChunkSeamService` содержит `_pending_refresh_tiles`, `enqueue_neighbor_border_redraws()`, `seam_normalize_and_redraw()`, `process_queue_step()`, а в `chunk_manager.gd` больше нет `_pending_seam_refresh*`, `_enqueue_seam_refresh_tile()` или `_apply_seam_refresh_tile()`.
- [ ] manual validation scenarios S-01..S-08 remain correct - требуется ручная проверка пользователем (manual human verification required); agent-run world route/runtime proof не запускался по policy.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `Godot_v4.6.1-stable_win64_console.exe --headless --path . --quit` - `exit 0`.
- Статическая проверка (Static verification): `git diff --check -- core/systems/world/chunk_manager.gd docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md .claude/agent-memory/active-epic.md` - без замечаний.
- Статическая проверка (Static verification): `Select-String ... -Pattern '\s+$'` по новым service `.gd/.uid` файлам - `0 matches`.
- Статическая проверка (Static verification): targeted `rg` подтвердил новые class_name и отсутствие прежних manager-owned cache/seam mutable vars.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): прогнать `S-01` boot/first playable, `S-02` player chunk transition, `S-03` seam mining, `S-05` underground query/reveal, `S-07` cache reuse и `S-08` debug overlay из `docs/04_execution/chunk_system_refactor_spec_2026-04-12.md`.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): runtime work class остаётся `background` для visual scheduler/cache/seam follow-up; seam repair drain ограничен `SEAM_REFRESH_MAX_TILES_PER_STEP`, cache остаётся bounded LRU через `SURFACE_PAYLOAD_CACHE_LIMIT`, visual drain всё ещё идёт через registered scheduler budget.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): при `S-03` смотреть, что mining на шве не вызывает visible stall; при `S-02`/`S-07` проверить, что streamed surface chunks продолжают использовать cache без raw/half-published visuals.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `ChunkVisualScheduler`: есть совпадения на строках 58, 129, 492, 493, 495, 511-517, 524 - обновлено.
- Grep DATA_CONTRACTS.md для `ChunkSurfacePayloadCache`: есть совпадения на строках 59, 131, 535-549, 906 - обновлено.
- Grep DATA_CONTRACTS.md для `ChunkSeamService`: есть совпадения на строках 60, 132, 559-574, 945, 972 - обновлено.
- Grep PUBLIC_API.md для `ChunkVisualScheduler|ChunkSurfacePayloadCache|ChunkSeamService`: есть совпадения на строках 209, 512, 526-528 - обновлено как internal-only boundary.
- Grep PUBLIC_API.md для `_seam_normalize_and_redraw`: есть совпадение на строке 177 - актуально, остаётся internal helper/facade, не public entrypoint.
- Секция "Required updates" в спеке: нет - `rg -n "Documentation debt|Required updates|Required contract and API updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- Тело `_process_visual_task()` всё ещё физически находится в `chunk_manager.gd`, но выполняется against `ChunkVisualScheduler`-owned containers и вызывается через scheduler tick façade; Iteration 10 зафиксировала это как текущий coordinated owner path, а не как public API.
- В рабочем дереве остаются pre-existing dirty/untracked файлы предыдущих итераций (`chunk.gd`, native build artifacts, earlier service extractions); они не откатывались.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: Layer Map, Source Of Truth Summary, `Layer: Visual Task Scheduling`, новые `Layer: Surface Payload Cache` и `Layer: Seam Repair Queue`, а также generate/mine/seam postconditions; grep-доказательство приведено выше.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Обновлено: Chunk Lifecycle/Persistence boundary note и internal Presentation methods table для `ChunkVisualScheduler.*`, `ChunkSurfacePayloadCache.*`, `ChunkSeamService.*`; grep-доказательство приведено выше.

#### Blockers

- none

---

### Iteration 10 - Final contract freeze and dead-code deletion

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] no dead fallback branches remain for the decided native-only responsibilities
- [x] module ownership is documented and matches code
- [x] future contributors can tell where a responsibility belongs without guessing

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; topology write operations and ownership entries updated
- [x] Grep PUBLIC_API.md for changed names - completed; removed stale internal fallback rows
- [x] Documentation debt section reviewed - completed; spec has no separate `Required updates` / `Documentation debt` section

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 10 status/closure and epic completion tracking.
- `core/systems/world/chunk_manager.gd` - deleted retired direct border redraw helper and dead GDScript full-topology rebuild helpers.
- `docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` - added stable ownership freeze.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - synced topology write operations and read-path wording.
- `docs/00_governance/PUBLIC_API.md` - removed stale internal fallback rows and clarified native worker topology scheduler wording.

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Удалены retired/dead helpers из `chunk_manager.gd`: прямой redraw границ соседей (`_redraw_neighbor_borders`), старый синхронный full topology rebuild (`_rebuild_loaded_mountain_topology` / `_build_mountain_component`), старые GDScript component-scan helpers и неиспользуемый `_ensure_topology_current()`.
- Оставлен действующий managed scheduler path для topology: он собирает snapshot на main thread, запускает обязательный native `MountainTopologyBuilder` worker compute и коммитит готовый snapshot обратно на main thread.
- В execution spec добавлена стабильная карта владения модулей (stable ownership freeze), включая `ChunkVisualScheduler`, `ChunkSurfacePayloadCache`, `ChunkSeamService`, `ChunkDebugSystem`, chunk presenters и native requirements.
- `PUBLIC_API.md` и `DATA_CONTRACTS.md` очищены от stale fallback wording для удалённых topology helpers; дополнительно исправлена read-path строка для `has_resource_at_world()`.

### Корневая причина (Root cause)
- После Iteration 9 ownership уже был разделён, но в коде и API-доках оставались retired helper names и unreachable GDScript full-rebuild code. Это создавало ложное впечатление, что topology всё ещё имеет production fallback path, хотя контракт уже native-only.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_manager.gd` - dead helper/fallback deletion and topology scheduler cleanup.
- `docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` - final stable ownership freeze.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - topology write operations and read-path sync.
- `docs/00_governance/PUBLIC_API.md` - stale internal method rows removed and native topology scheduler wording updated.
- `.claude/agent-memory/active-epic.md` - iteration 10 closure recorded.

### Проверки приёмки (Acceptance tests)
- [x] no dead fallback branches remain for the decided native-only responsibilities - прошло (passed); `rg` по removed symbols (`_redraw_neighbor_borders|_ensure_topology_current|_rebuild_loaded_mountain_topology|_build_mountain_component|_find_next_topology_seed|_process_topology_component_step|_capture_topology_build_snapshot`) в `chunk_manager.gd`, `PUBLIC_API.md`, `DATA_CONTRACTS.md` вернул `0 matches`.
- [x] module ownership is documented and matches code - прошло (passed); `rg` подтвердил `Stable ownership freeze after Iteration 10` в execution spec и owner entries для `ChunkVisualScheduler`, `ChunkSurfacePayloadCache`, `ChunkSeamService`, `MountainTopologyBuilder`, `LoadedOpenPocketQuery` в spec/contract/API docs.
- [x] future contributors can tell where a responsibility belongs without guessing - прошло (passed); stable ownership freeze explicitly maps manager, streaming, scheduler, cache, seam, debug, chunk, presenters, visual kernel, and native requirements.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `rg -n "_redraw_neighbor_borders|_rebuild_loaded_mountain_topology|_ensure_topology_current|_build_mountain_component|_find_next_topology_seed|_process_topology_component_step|_capture_topology_build_snapshot" core/systems/world/chunk_manager.gd docs/00_governance/PUBLIC_API.md docs/02_system_specs/world/DATA_CONTRACTS.md` - `0 matches`.
- Статическая проверка (Static verification): `git diff --check -- core/systems/world/chunk_manager.gd docs/04_execution/chunk_system_refactor_spec_2026-04-12.md docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md .claude/agent-memory/active-epic.md` - `exit 0`.
- Статическая проверка (Static verification): `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --quit` - `exit 0`.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): headless project load only; manual world-route validation not run by policy.
- Ручная проверка пользователем (Manual human verification): требуется для visual/runtime validation matrix.
- Рекомендованная проверка пользователем (Suggested human check): прогнать `S-01` boot/first playable, `S-02` player chunk transition, `S-03` seam mining, `S-05` underground query/reveal, `S-07` cache reuse и `S-08` debug overlay из spec.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): interactive mining path no longer contains old direct neighbor border redraw helper or synchronous full topology rebuild helper; topology full rebuild remains background/native through `_tick_topology()` -> snapshot -> native worker -> main-thread commit.
- Статическая проверка (Static verification): seam follow-up remains `ChunkSeamService`-owned and bounded; visual work remains `ChunkVisualScheduler`-owned and budgeted.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): explicit perf route not run in this task by policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): при `S-03` проверить отсутствие frame spike при mining на chunk seam; при `S-02`/`S-07` проверить отсутствие raw/half-published chunks.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `MountainTopologyBuilder|LoadedOpenPocketQuery|ChunkVisualScheduler|ChunkSurfacePayloadCache|ChunkSeamService`: есть совпадения, ownership documented.
- Grep DATA_CONTRACTS.md для `_advance_topology_build_start_step|_build_native_topology_snapshot`: есть совпадения, topology write operations synced.
- Grep DATA_CONTRACTS.md для `_capture_topology_build_snapshot|_ensure_topology_current|_rebuild_loaded_mountain_topology`: `0 matches`, stale entries removed.
- Grep PUBLIC_API.md для `_ensure_topology_current|_rebuild_loaded_mountain_topology`: `0 matches`, stale internal rows removed.
- Grep PUBLIC_API.md для `MountainTopologyBuilder|LoadedOpenPocketQuery|ChunkVisualScheduler|ChunkSurfacePayloadCache|ChunkSeamService`: есть совпадения, API boundary updated/confirmed.
- Секция "Required updates" в спеке: нет - `rg -n "Required contract and API updates|Required updates|Documentation debt" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- В рабочем дереве остаются pre-existing dirty/untracked файлы предыдущих итераций (`chunk.gd`, native build artifacts, earlier service extractions); они не откатывались.
- `_process_visual_task()` всё ещё физически находится в `chunk_manager.gd`, но работает against `ChunkVisualScheduler`-owned containers; это отражено в `DATA_CONTRACTS.md` как текущий coordinated owner path.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: topology write operations now reference `_advance_topology_build_start_step()` and `_build_native_topology_snapshot()`, stale `_capture_topology_build_snapshot` / `_ensure_topology_current` references removed, ownership entries remain grep-confirmed.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Обновлено: stale `_ensure_topology_current()` and `_rebuild_loaded_mountain_topology()` rows removed; `_process_topology_build()` now documents mandatory native `MountainTopologyBuilder` worker compute.

#### Blockers

- none

---

### Iteration 6 - Visual kernel consolidation

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] duplicated visual-rule branches removed or clearly routed through one implementation
- [x] batch generation and direct redraw consume same kernel logic
- [ ] seam and mining manual checks produce same visuals as before or better - manual human verification required

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; updated for visual kernel contract
- [x] Grep PUBLIC_API.md for changed names - completed; updated for shared request/kernel note
- [x] Documentation debt section reviewed - completed; no extra spec debt due

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 6 tracker updated with completion evidence and closure report
- `core/systems/world/chunk.gd` - direct redraw helpers and request builders routed through shared visual kernel adapters
- `core/systems/world/chunk_visual_kernel.gd` - new single-source visual rule owner for terrain/ground-face/rock/cover/cliff decisions and prepared command generation
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - visual kernel request/phase contract and presentation ownership updated
- `docs/00_governance/PUBLIC_API.md` - internal visual batch/request notes updated for shared kernel semantics

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлен `ChunkVisualKernel`, который теперь является единым owner'ом для terrain / ground-face / rock / cover / cliff visual rules и prepared command emission.
- В `chunk.gd` batch-side `_visual_request_*` helpers и direct redraw helpers (`_surface_rock_visual_class()`, `_rock_visual_class()`, `_resolve_variant_atlas()`, `_resolve_variant_alt_id()`, `_redraw_cover_tile()`, `_redraw_cliff_tile()` и related adapters) переведены на thin delegation в `ChunkVisualKernel`.
- `_build_visual_compute_request()` уже собранный во время итерации request contract закреплён как единый источник входных данных для batch и direct path: terrain halo + `height` / `variation` / `biome` / `secondary_biome` / `ecotone`.
- Внутри `ChunkVisualKernel` исправлены semantic drift'ы относительно старой логики: surface variation снова учитывается при выборе `ground_face_atlas`, water-neighbor check снова использует reveal-radius с диагоналями, а surface face corner selection больше не подтягивает underground-only `_T` corner variants.
- Обновлены `DATA_CONTRACTS.md` и `PUBLIC_API.md`, чтобы контракт явно фиксировал request inputs, phase names, command structure и правило, что border-fix / dirty redraw / first-pass batch больше не имеют права жить на двух разных реализациях visual rules.

### Корневая причина (Root cause)
- До шестой итерации wall/cover/cliff visual rules были размазаны между direct redraw path и request/batch path. Это уже привело к drift-риску: например, batch-side biome resolution не гарантировал тот же `secondary_biome` / `ecotone` путь, а отдельный kernel draft начал расходиться со старой surface face logic. Главная задача итерации была не "сделать ещё один helper", а убрать саму возможность второго источника истины.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk.gd` - thin adapters к shared visual kernel и unified single-tile phase apply.
- `core/systems/world/chunk_visual_kernel.gd` - новый visual rule owner и prepared-command kernel.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - owner boundary и request/phase contract описаны явно.
- `docs/00_governance/PUBLIC_API.md` - internal method notes updated for shared kernel semantics.
- `.claude/agent-memory/active-epic.md` - recorded Iteration 6 completion evidence.

### Проверки приёмки (Acceptance tests)
- [x] duplicated visual-rule branches removed or clearly routed through one implementation - прошло (passed); проверено статически (static verification): `_visual_request_*` helpers и direct visual helpers в `chunk.gd` теперь являются thin wrappers к `ChunkVisualKernel`, а old per-branch rule bodies removed.
- [x] batch generation and direct redraw consume same kernel logic - прошло (passed); проверено статически и headless parse: `Chunk.compute_visual_batch()` / `build_visual_phase_batch()` / `build_visual_dirty_batch()` и `_apply_single_tile_visual_phase()` / `_redraw_cover_tile()` / `_redraw_cliff_tile()` теперь route through the same `ChunkVisualKernel` request + command contract.
- [ ] seam and mining manual checks produce same visuals as before or better - требуется ручная проверка пользователем (manual human verification required); агент не прогонял интерактивные seam/mining scenarios, поэтому visual equivalence по runtime path остаётся pending human validation.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --quit` - `exit 0`.
- Статическая проверка (Static verification): `git diff --check -- core/systems/world/chunk.gd core/systems/world/chunk_visual_kernel.gd docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md` - без замечаний.
- Статическая проверка (Static verification): `rg -n "ChunkVisualKernel|_surface_rock_visual_class|_rock_visual_class|build_visual_phase_batch|build_visual_dirty_batch|compute_visual_batch" docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md` подтвердил shared-kernel contract и updated doc references.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): headless parse/startup only; gameplay mining/seam scenario не запускался.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): прогнать `S-03` и `S-05` из `docs/04_execution/chunk_system_refactor_spec_2026-04-12.md`, с акцентом на mining рядом с seam и на сравнение first-pass surface visuals до/после terrain mutation.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): direct redraw больше не держит отдельный rule graph; dirty/border-fix work ограничивается explicit tile list + one-tile halo через unified request contract, а first-pass phase path по-прежнему может использовать prebaked visual payload без второй rule implementation.
- Статическая проверка (Static verification): `ChunkVisualKernel` остаётся pure-data owner и не пишет в scene tree напрямую; apply ownership остаётся в `Chunk`, что сохраняет separation между compute и apply lanes.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy, кроме headless parse/startup.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): пройти mining seam scenario и быструю border-fix проверку, наблюдая отсутствие новых frame spikes и визуального рассинхрона между first-pass и dirty redraw.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `ChunkVisualKernel`: есть совпадения на строках 677, 685, 698, 699, 722 - обновлено.
- Grep DATA_CONTRACTS.md для `_build_visual_compute_request|_build_single_tile_visual_request|build_visual_phase_batch|build_visual_dirty_batch|compute_visual_batch`: есть совпадения на строках 677, 699, 711, 712, 721 - обновлено.
- Grep PUBLIC_API.md для `ChunkVisualKernel|build_visual_phase_batch|compute_visual_batch|_surface_rock_visual_class|_rock_visual_class`: есть совпадения на строках 511, 513, 519, 520, 527, 531, 532 - обновлено.
- Секция "Required updates" в спеке: нет - `rg -n "Required contract and API updates|Required updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- `flora` и debug marker phases по-прежнему имеют собственных owner'ов и не входят в `ChunkVisualKernel`; для Iteration 6 это осознанно, потому что здесь консолидация касалась именно terrain / cover / cliff visual rules, а не всей presentation pipeline целиком.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: `ChunkVisualKernel` зафиксирован как shared visual rule owner, request/phase/command contract записан явно, а prebaked payload section теперь ссылается на тот же kernel; grep-доказательство приведено выше.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Обновлено: internal visual batch helpers и Wall Atlas notes теперь явно говорят о shared `ChunkVisualKernel` contract; grep-доказательство приведено выше.

#### Blockers

- none

---

### Iteration 2 - Fast hot-path wins in `chunk_manager.gd`

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [ ] functionality unchanged in all manual scenarios - manual human verification required
- [x] `_update_chunks()` no longer depends on linear membership scan
- [x] repeated wrapper reflection is removed from hot loops
- [x] cache touch no longer uses array `find()` + `remove_at()` on every hit

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; no update required
- [x] Grep PUBLIC_API.md for changed names - completed; no update required
- [x] Documentation debt section reviewed - completed; no new debt due

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 2 tracker updated with acceptance/doc evidence and closure report
- `core/systems/world/chunk_manager.gd` - load queue membership index, cached WorldGenerator capability flags, display sync reference cache, monotonic surface payload cache bookkeeping, and small queue-sort guards

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- В `chunk_manager.gd` добавлен индекс очереди загрузки `_load_queue_set`, а `enqueue / pop / prune / z-switch` теперь синхронизируют его через `_make_load_request_key()`, `_rebuild_load_queue_set()` и `_pop_load_request()`, чтобы проверка membership больше не делала линейный проход по `_load_queue`.
- Capability flags `WorldGenerator` теперь кэшируются один раз в `_cache_world_generator_capabilities()`, а hot-path wrappers и builder entrypoints (`_canonical_tile()`, `_chunk_wrap_delta_x()`, `_ensure_worker_chunk_builder()`, `_submit_async_generate()`, `_boot_submit_pending_tasks()`) больше не платят повторный reflection check на каждом вызове.
- Полный sync display position теперь имеет reference-cache: `_sync_loaded_chunk_display_positions()` пропускает повторный полный обход loaded chunks, если reference chunk не менялся, а `set_active_z_level()` делает явную invalidation перед forced resync.
- Surface payload cache больше не использует array-based LRU touch с `find()` + `remove_at()` на каждом hit: `_touch_surface_payload_cache_key()` перешёл на monotonic serial, а `_trim_surface_payload_cache()` удаляет самый старый ключ только в момент trim.
- Добавлены небольшие guards, которые не запускают sort на очередях размера `0..1`, не меняя порядок или приоритеты там, где сортировка реально нужна.

### Корневая причина (Root cause)
- Во второй итерации спеки устранялись не контрактные ошибки поведения, а накопившиеся avoidable hot-path costs: линейная проверка membership в load queue, повторные `has_method()` в часто вызываемых wrappers, лишние полные sync passes для display position и O(n) cache touch bookkeeping в surface payload cache.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_manager.gd` - локальные hot-path optimizations Iteration 2 без расширения public/API semantics.
- `.claude/agent-memory/active-epic.md` - зафиксирован старт и завершение итерации 2 с доказательствами.

### Проверки приёмки (Acceptance tests)
- [ ] functionality unchanged in all manual scenarios - требуется ручная проверка пользователем (manual human verification required); явный runtime-прогон агентом (explicit agent-run runtime verification) не запускался в этой задаче по policy. Рекомендованная проверка пользователем (Suggested human check): прогнать сценарии `S-01` ... `S-08` из `chunk_system_refactor_spec_2026-04-12.md`, с акцентом на `S-02`, `S-03`, `S-06` и `S-07`.
- [x] `_update_chunks()` no longer depends on linear membership scan - прошло (passed); проверено статически (static verification): `_has_load_request()` теперь использует `_load_queue_set.has(...)` на строках 1466-1467, а синхронизация индекса идёт через `_rebuild_load_queue_set()` / `_pop_load_request()` на строках 1438-1451, `enqueue` на строках 2229-2243, `prune` на строках 5753-5786 и `set_active_z_level()` на строках 6268-6284.
- [x] repeated wrapper reflection is removed from hot loops - прошло (passed); проверено статически (static verification): `_cache_world_generator_capabilities()` централизует `WorldGenerator.has_method(...)` на строках 2759-2800, wrappers читают только cached flags на строках 1343-1384, а hot builder call sites используют `_wg_has_create_detached_chunk_content_builder` на строках 5555-5564, 5616-5620 и 7524-7535. Дополнительное grep-доказательство: `rg "WorldGenerator\\.has_method\\("` теперь возвращает только init-time блок 2775-2797.
- [x] cache touch no longer uses array `find()` + `remove_at()` on every hit - прошло (passed); проверено статически (static verification): `_touch_surface_payload_cache_key()` и `_trim_surface_payload_cache()` теперь работают через monotonic order на строках 5938-5957, а `rg "_surface_payload_cache_lru|find\\(cache_key\\)|remove_at\\(existing_index\\)" core/systems/world/chunk_manager.gd` вернул `0 matches`.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check -- .claude/agent-memory/active-epic.md core/systems/world/chunk_manager.gd` - без замечаний; точечные чтения `chunk_manager.gd` подтвердили `_sync_loaded_chunk_display_positions()` cache gate на строках 1420-1432, `load_queue` index helpers на строках 1434-1467 и monotonic cache bookkeeping на строках 5938-5957.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): новый мир (`S-01`), переходы через границы чанков (`S-02`), mining на шве (`S-03`), z-switch (`S-06`) и unload/reload cache reuse (`S-07`).

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): `load queue` membership теперь O(1) через `_load_queue_set`; redundant full display sync ограничен cached reference gate на строках 1423-1432 и invalidation в `set_active_z_level()` на строках 6274-6278; cached capability flags убрали reflection checks из wrappers и builder hot paths; surface payload cache touch ушёл от per-hit array churn.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): пройти `S-02`, `S-06`, `S-07` и посмотреть, что при границах чанков, z-switch и повторной загрузке не появилось regressions в publication / streaming behavior.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `_submit_async_generate`: 1 совпадение, строка 512 - актуально; документ по-прежнему описывает его как internal writer debug snapshot layer.
- Grep DATA_CONTRACTS.md для `_boot_submit_pending_tasks`: 2 совпадения, строки 766 и 781 - актуально; boot compute queue ownership и write operations не менялись.
- Grep DATA_CONTRACTS.md для `set_active_z_level`: 1 совпадение, строка 1444 - актуально; downstream sink semantics не менялись.
- Grep DATA_CONTRACTS.md для остальных hot-path helpers (`_has_load_request`, `_sync_loaded_chunk_display_positions`, `_make_load_request_key`, `_rebuild_load_queue_set`, `_pop_load_request`, `_sort_load_request_entries_by_priority`, `_sort_load_queue_by_priority`, `_cache_world_generator_capabilities`, `_canonical_tile`, `_chunk_wrap_delta_x`, `_resolve_chunk_biome_from_world_generator`, `_ensure_worker_chunk_builder`, `_submit_async_generate`, `_invalidate_display_sync_cache`, `_surface_payload_cache_order`, `_surface_payload_cache_touch_serial`, `_touch_surface_payload_cache_key`, `_trim_surface_payload_cache`): 0 новых релевантных совпадений, кроме строк выше - not referenced.
- Grep PUBLIC_API.md для `_boot_submit_pending_tasks`: 1 совпадение, строка 1798 - актуально; helper остаётся internal boot compute queue detail.
- Grep PUBLIC_API.md для `set_active_z_level`: 5 совпадений, строки 383, 555, 575, 576, 1375 - актуально; документ по-прежнему называет `ChunkManager.set_active_z_level()` downstream sink, а не public owner-path.
- Grep PUBLIC_API.md для остальных hot-path helpers (`_has_load_request`, `_sync_loaded_chunk_display_positions`, `_make_load_request_key`, `_rebuild_load_queue_set`, `_pop_load_request`, `_sort_load_request_entries_by_priority`, `_sort_load_queue_by_priority`, `_cache_world_generator_capabilities`, `_canonical_tile`, `_chunk_wrap_delta_x`, `_resolve_chunk_biome_from_world_generator`, `_ensure_worker_chunk_builder`, `_submit_async_generate`, `_invalidate_display_sync_cache`, `_surface_payload_cache_order`, `_surface_payload_cache_touch_serial`, `_touch_surface_payload_cache_key`, `_trim_surface_payload_cache`): 0 новых релевантных совпадений, кроме строк выше - not referenced.
- Секция "Required updates" в спеке: нет - `rg -n "Required contract and API updates|Required updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- Debug / forensics extraction из release hot path всё ещё остаётся отдельной работой для Iteration 3; текущая итерация намеренно не трогала ownership debug subsystem.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- не требовалось (not required) - grep подтвердил, что новые hot-path helpers не являются contract surface, а существующие упоминания `_submit_async_generate`, `_boot_submit_pending_tasks` и `set_active_z_level` остаются актуальными без semantic drift.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) - grep подтвердил, что новые hot-path helpers не входят в public API, а текущие упоминания `_boot_submit_pending_tasks` и `ChunkManager.set_active_z_level()` остаются точными.

#### Blockers

- none

---

### Iteration 3 - Isolate debug and forensics from release hot path

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [ ] debug overlay still works in debug builds - manual human verification required
- [x] release scheduler path no longer performs per-task forensic enrichment by default
- [ ] no behavior changes to chunk publication or streaming correctness - manual human verification required

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; contract updated for new debug owner boundary
- [x] Grep PUBLIC_API.md for changed names - completed; no update required
- [x] Documentation debt section reviewed - completed; no new debt due

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 3 tracker updated with closure evidence
- `core/systems/world/chunk_manager.gd` - debug service wiring, overlay delegation, release-path guard hookup, and GDScript parse fix for `_require_native_class()`
- `core/systems/world/chunk_debug_system.gd` - forensic/task metadata ownership, overlay snapshot assembly, release-gated hot-path bookkeeping
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - debug overlay ownership and release-path invariant update

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлен и доведён до рабочего состояния `ChunkDebugSystem`, который теперь владеет forensic incidents, trace contexts, visual-task debug metadata, bounded suspicion/task rows и сборкой F11 overlay snapshot.
- `ChunkManager` переведён на тонкий debug boundary: public `get_chunk_debug_overlay_snapshot()` теперь только делегирует сборку snapshot в `ChunkDebugSystem`, а manager-side debug helpers для task rows / suspicion flags / visual-task meta стали thin wrappers вместо owner-side реализации.
- Release guard закреплён через `ChunkDebugSystem.setup(self, OS.is_debug_build())`: в release runtime deep per-task forensic enrichment для visual scheduler path по умолчанию отключён, а debug-only bookkeeping остаётся доступным в debug builds.
- Обновлён `DATA_CONTRACTS.md`, чтобы owner boundary явно называла `ChunkDebugSystem` владельцем debug overlay assembly и bounded forensic/task metadata, а также фиксировала invariant, что release scheduler path не должен зависеть от deep per-task forensics.

### Корневая причина (Root cause)
- До третьей итерации `ChunkManager` одновременно владел scheduler hot path и значимой частью debug/forensics bookkeeping. Из-за этого release path платил за debug-oriented metadata churn, а owner boundary для overlay/forensics оставалась размытой.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_manager.gd` - thin debug wrappers, overlay delegation, debug service setup, parse-fix для `_require_native_class()`.
- `core/systems/world/chunk_debug_system.gd` - новый debug owner для incidents / traces / task metadata / overlay snapshot assembly.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - updated owner boundary и release invariant для chunk debug overlay layer.
- `.claude/agent-memory/active-epic.md` - closure evidence для Iteration 3.

### Проверки приёмки (Acceptance tests)
- [ ] debug overlay still works in debug builds - требуется ручная проверка пользователем (manual human verification required); статически подтверждено, что public entrypoint `ChunkManager.get_chunk_debug_overlay_snapshot()` теперь делегирует в `ChunkDebugSystem.build_overlay_snapshot()` (`chunk_manager.gd` строка 505, `chunk_debug_system.gd` строка 444), но реальный F11 overlay runtime агентом не запускался.
- [x] release scheduler path no longer performs per-task forensic enrichment by default - прошло (passed); проверено статически (static verification): `ChunkManager` настраивает debug system через `OS.is_debug_build()` на строке 318, а release-gated task bookkeeping находится в `ChunkDebugSystem.upsert_visual_task_meta()` / `note_visual_task_event()` / `note_budget_exhausted_trace_task()` на строках 517, 552 и 623.
- [ ] no behavior changes to chunk publication or streaming correctness - требуется ручная проверка пользователем (manual human verification required); статически проверено, что Iteration 3 меняла debug/overlay boundary и contract docs, а не publication / streaming ownership, но runtime сценарии `S-01` ... `S-08` агентом не прогонялись.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check -- .claude/agent-memory/active-epic.md core/systems/world/chunk_manager.gd core/systems/world/chunk_debug_system.gd docs/02_system_specs/world/DATA_CONTRACTS.md` - без замечаний.
- Статическая проверка (Static verification): loader-based compile check `godot.exe --headless --path . --script res://tmp_verify_script_load.gd` - `exit 0`; временный loader script последовательно `load()`-ил `chunk_debug_system.gd` и `chunk_manager.gd` в project context и затем был удалён.
- Статическая проверка (Static verification): `rg` по `chunk_manager.gd` для `_debug_forensics_incidents|_debug_chunk_trace_contexts|_debug_active_incident_id|_debug_next_trace_id|_debug_next_incident_id|_debug_forensics_incident_order|_debug_visual_task_meta|_debug_make_visual_task_meta\(` вернул `0 matches`, что подтверждает отсутствие прямого manager-owned forensic state.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): debug build с F11/Shift+F11 overlay, затем сценарии `S-02`, `S-03`, `S-06`, `S-07`, `S-08` из `chunk_system_refactor_spec_2026-04-12.md`, чтобы подтвердить и overlay, и отсутствие regressions в streaming/publication path.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): release guard включается на setup path (`chunk_manager.gd` строка 318), а `ChunkDebugSystem` short-circuit'ит deep per-task bookkeeping через `_hot_path_forensics_enabled` в `upsert_visual_task_meta()`, `note_visual_task_event()`, и `note_budget_exhausted_trace_task()` (`chunk_debug_system.gd` строки 517, 552, 623).
- Статическая проверка (Static verification): final overlay assembly перенесён в `ChunkDebugSystem.build_overlay_snapshot()` (`chunk_debug_system.gd` строка 444), а `ChunkManager.get_chunk_debug_overlay_snapshot()` остаётся thin public facade (`chunk_manager.gd` строка 505).
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): в release runtime пройти обычный streaming/mining маршрут и сравнить frame pacing с debug build, отдельно в debug build открыть overlay и убедиться, что forensic sections наполняются без влияния на chunk publication correctness.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `ChunkDebugSystem`: есть совпадения на строках 121, 122, 512, 513, 521, 524, 525 - обновлено.
- Grep DATA_CONTRACTS.md для `get_chunk_debug_overlay_snapshot`: есть совпадения на строках 122, 513, 524 - обновлено.
- Grep DATA_CONTRACTS.md для `release_scheduler_path_is_not_forensics_bound`: есть совпадение на строке 522 - обновлено.
- Grep PUBLIC_API.md для `ChunkDebugSystem|build_overlay_snapshot`: `0 matches` - not required; новый owner boundary остаётся internal contract detail, не public API.
- Grep PUBLIC_API.md для `get_chunk_debug_overlay_snapshot`: есть совпадения на строках 71 и 216 - актуально; public entrypoint и его semantics не менялись.
- Секция "Required updates" в спеке: нет - `rg -n "Required contract and API updates|Required updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- В `ChunkManager` всё ещё остаётся заметный объём queue/chunk row helper-кода для overlay reads и thin debug wrappers к сервису; это уже больше про позднюю decomposition/cleanup работу Iteration 4+, а не blocker для текущей extraction boundary.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: `ChunkDebugSystem` теперь зафиксирован как owner bounded forensic/task metadata и overlay assembly, а release scheduler path invariant добавлен с grep-доказательством выше.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) - `rg -n "ChunkDebugSystem|build_overlay_snapshot" docs/00_governance/PUBLIC_API.md` вернул `0 matches`, а существующие упоминания `ChunkManager.get_chunk_debug_overlay_snapshot()` на строках 71 и 216 остаются точными.

#### Blockers

- none

---

### Iteration 4 - Chunk install / streaming cleanup and manager decomposition pass 1

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] only one canonical chunk install finalization path remains
- [x] `chunk_manager.gd` shrinks measurably
- [ ] z-level switching still works cleanly - manual human verification required

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; updated for streaming owner boundary
- [x] Grep PUBLIC_API.md for changed names - completed; updated for internal lifecycle facade note
- [x] Documentation debt section reviewed - completed; no extra spec debt due

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 4 tracker updated with completion evidence and closure report
- `core/systems/world/chunk_manager.gd` - service wiring, thin streaming facades, centralized `_loaded_chunks` alias helpers, and z-switch cleanup handoff
- `core/systems/world/chunk_streaming_service.gd` - new owner for runtime load queue relevance/pruning, staged install handoff, async generation lifecycle, and unload routing
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - streaming owner boundary and canonical final install path update
- `docs/00_governance/PUBLIC_API.md` - chunk lifecycle internal facade note updated for `ChunkStreamingService`

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Добавлен `ChunkStreamingService`, который теперь владеет runtime streaming lifecycle: relevance/pruning очереди загрузки, worker generation handoff, staged install handoff, unload routing и z-switch cleanup для streaming state.
- `ChunkManager` переведён на тонкие streaming facades: `_update_chunks()`, `_tick_loading()`, `_load_chunk_for_z()`, `_unload_chunk()`, staged/runtime generation helpers и cleanup в `_exit_tree()` теперь делегируют в сервис вместо того, чтобы держать весь lifecycle внутри manager.
- Direct load path и staged runtime path теперь сходятся в один canonical финальный commit: `ChunkManager._finalize_chunk_install()`. Direct load идёт через `ChunkStreamingService.load_chunk_for_z()`, staged runtime path — через `stage_prepared_chunk_install() -> staged_loading_create() -> staged_loading_finalize()`, а boot apply уже и раньше сходился туда же.
- `_loaded_chunks` alias больше не перекидывается ad hoc: добавлены `_get_loaded_chunks_for_z()` и `_set_loaded_chunks_alias()`, а `set_active_z_level()` использует их вместе с `ChunkStreamingService.handle_active_z_changed()`.
- Обновлены `DATA_CONTRACTS.md` и `PUBLIC_API.md`, чтобы внутренняя owner boundary для runtime streaming была зафиксирована в канонических документах.

### Корневая причина (Root cause)
- До Iteration 4 lifecycle установки и выгрузки чанка был размазан между `ChunkManager._load_chunk_for_z()`, staged runtime path, z-switch cleanup и manager-owned state cleanup. Это создавало дублирование install/finalize логики и оставляло `ChunkManager` одновременно public facade и owner'ом слишком большого объёма streaming internals.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk_manager.gd` - thin streaming facades, service wiring, centralized `_loaded_chunks` alias helpers.
- `core/systems/world/chunk_streaming_service.gd` - новый streaming owner для runtime load/unload/stage/generate lifecycle.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - owner boundary и canonical install/finalize path обновлены.
- `docs/00_governance/PUBLIC_API.md` - internal chunk lifecycle note updated for `ChunkStreamingService`.
- `.claude/agent-memory/active-epic.md` - recorded Iteration 4 completion evidence.

### Проверки приёмки (Acceptance tests)
- [x] only one canonical chunk install finalization path remains - прошло (passed); проверено статически (static verification): `rg -n "_finalize_chunk_install\\(|load_chunk_for_z\\(|staged_loading_finalize\\(|_boot_apply_chunk_from_native_data\\(" core/systems/world/chunk_manager.gd core/systems/world/chunk_streaming_service.gd` показывает, что direct load, staged runtime finalize и boot apply сходятся в `ChunkManager._finalize_chunk_install()`.
- [x] `chunk_manager.gd` shrinks measurably - прошло (passed); проверено статически (static verification): `git diff --numstat -- core/systems/world/chunk_manager.gd` вернул `460 1525`, а `git status --short -- core/systems/world/chunk_streaming_service.gd` подтверждает вынесенный новый service file.
- [ ] z-level switching still works cleanly - требуется ручная проверка пользователем (manual human verification required); статически проверено, что `set_active_z_level()` теперь использует `_set_loaded_chunks_alias(z)` и `ChunkStreamingService.handle_active_z_changed(z)`, но реальный runtime переход между z-level агентом не запускался.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check -- .claude/agent-memory/active-epic.md core/systems/world/chunk_manager.gd core/systems/world/chunk_streaming_service.gd docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md` - без замечаний.
- Статическая проверка (Static verification): `Godot_v4.6.1-stable_win64_console.exe --headless --path . --quit` - `exit 0`.
- Статическая проверка (Static verification): `git diff --numstat -- core/systems/world/chunk_manager.gd docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md .claude/agent-memory/active-epic.md` - показал существенное сокращение `chunk_manager.gd` и отдельные contract/API updates.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): прогнать `S-01`, `S-02`, `S-06`, `S-07` из `docs/04_execution/chunk_system_refactor_spec_2026-04-12.md`, с акцентом на z-switch и повторную догрузку после unload/reload.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): runtime class остаётся `background`; load queue relevance/pruning, worker generation handoff, staged install handoff и unload routing теперь изолированы в `ChunkStreamingService`, а финальный main-thread commit остаётся локальным и единым через `_finalize_chunk_install()`.
- Статическая проверка (Static verification): `_loaded_chunks` alias reassignment больше не размазан по нескольким install/z-switch path и проходит через `_set_loaded_chunks_alias()`, что убирает ad hoc alias drift.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): пройти `S-02`, `S-06`, `S-07` и убедиться, что streaming publication, z-switch cleanup и cache reuse не дали regressions.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `ChunkStreamingService`: есть совпадения на строках 121, 799, 800 - обновлено.
- Grep DATA_CONTRACTS.md для `_finalize_chunk_install`: есть совпадения на строках 121, 514, 799, 800 - актуально после обновления.
- Grep DATA_CONTRACTS.md для `_load_chunk_for_z`: есть совпадение на строке 799 - обновлено.
- Grep DATA_CONTRACTS.md для `_set_loaded_chunks_alias|_get_loaded_chunks_for_z`: `0 matches` - not referenced.
- Grep PUBLIC_API.md для `ChunkStreamingService`: есть совпадения на строках 208, 292, 293 - обновлено.
- Grep PUBLIC_API.md для `_load_chunk_for_z`: есть совпадение на строке 292 - обновлено.
- Grep PUBLIC_API.md для `_unload_chunk`: есть совпадение на строке 293 - обновлено.
- Grep PUBLIC_API.md для `_set_loaded_chunks_alias|_get_loaded_chunks_for_z`: `0 matches` - not referenced.
- Секция "Required updates" в спеке: нет - `rg -n "Required contract and API updates|Required updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- В `ChunkManager` всё ещё остаются queue/debug/helper sections, которые можно дальше выносить в поздних decomposition iterations, но это уже следующая риск-surface, не Iteration 4.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: зафиксирован `ChunkStreamingService` как owner runtime streaming internals и описан единый canonical final install path через `_finalize_chunk_install()`; grep-доказательство приведено выше.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Обновлено: `Chunk Lifecycle` теперь явно отмечает `ChunkManager` как thin facade над `ChunkStreamingService` для internal `_load_chunk_for_z()` / `_unload_chunk()`; grep-доказательство приведено выше.

#### Blockers

- none

---

### Iteration 5 - Peripheral extraction from `chunk.gd`

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] `chunk.gd` no longer directly owns debug marker scene construction
- [x] `chunk.gd` no longer directly owns flora presentation implementation details
- [ ] underground fog still works - manual human verification required
- [ ] flora still renders correctly after unload/reload - manual human verification required

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; updated for extracted presentation owners
- [x] Grep PUBLIC_API.md for changed names - completed; no update required
- [x] Documentation debt section reviewed - completed; no extra spec debt due

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 5 tracker updated with completion evidence and closure report
- `core/systems/world/chunk.gd` - thin facade wiring for extracted flora/fog/debug presenters
- `core/systems/world/chunk_debug_renderer.gd` - new batched debug marker renderer without per-marker scene-node spam
- `core/systems/world/chunk_fog_presenter.gd` - new fog-layer owner for creation and visible/discovered apply
- `core/systems/world/chunk_flora_presenter.gd` - new flora presenter with shared texture cache and packet publication
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - presentation ownership and observed-file list updated for the new presenter modules

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- Из `chunk.gd` вынесены три периферийных presentation-owner модуля: `ChunkDebugRenderer`, `ChunkFogPresenter` и `ChunkFloraPresenter`.
- `ChunkDebugRenderer` заменил прямое создание `Polygon2D` на один batched `Node2D` с `draw_rect()`, поэтому debug markers больше не создают отдельный scene node на каждый прямоугольник.
- `ChunkFogPresenter` теперь владеет созданием `FogLayer` и apply-path для `visible` / `discovered` fog updates, а `chunk.gd` оставлен как thin facade с прежними safe chunk methods.
- `ChunkFloraPresenter` забрал у `chunk.gd` packet publication, payload/result ownership и draw path для флоры; texture lookups теперь идут через shared texture cache, а не через per-chunk renderer cache.
- `DATA_CONTRACTS.md` обновлён под новый extracted layout presentation-layer.

### Корневая причина (Root cause)
- К пятой итерации `chunk.gd` всё ещё напрямую держал fog-layer creation, flora renderer/payload state и debug marker scene construction. Это раздувало ответственность чанка и сохраняло лишний hot-path baggage, включая per-marker node churn и per-chunk texture-cache policy.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk.gd` - заменён на thin facade над extracted presenters для fog/flora/debug.
- `core/systems/world/chunk_debug_renderer.gd` - новый batched debug renderer.
- `core/systems/world/chunk_fog_presenter.gd` - новый fog presenter для layer lifecycle и visible/discovered apply.
- `core/systems/world/chunk_flora_presenter.gd` - новый flora presenter с shared texture cache.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - presentation-owner detail и observed files приведены к новому layout.
- `.claude/agent-memory/active-epic.md` - recorded Iteration 5 completion evidence.

### Проверки приёмки (Acceptance tests)
- [x] `chunk.gd` no longer directly owns debug marker scene construction - прошло (passed); проверено статически (static verification): `rg -n "\\bFloraBatchRenderer\\b|\\bPolygon2D\\b|_debug_root\\b|var _fog_layer\\b|var _flora_renderer\\b|_texture_cache\\b" core/systems/world/chunk.gd` вернул `0 matches`, а `ChunkDebugRenderer` подключён в `chunk.gd` через preload/new на строках 4, 176-179.
- [x] `chunk.gd` no longer directly owns flora presentation implementation details - прошло (passed); проверено статически (static verification): `ChunkFloraPresenter` вынесен в отдельный файл (`chunk_flora_presenter.gd:1`), shared texture cache объявлен на строке 8, а `chunk.gd` делегирует `set_flora_result`, `set_flora_payload`, packet build/apply и clear в presenter на строках 171-175, 3458-3481.
- [ ] underground fog still works - требуется ручная проверка пользователем (manual human verification required); статически подтверждено, что public chunk methods `init_fog_layer()`, `apply_fog_visible()`, `apply_fog_discovered()` сохранены и делегируют в `ChunkFogPresenter`, но runtime reveal/fog proof агентом не запускался.
- [ ] flora still renders correctly after unload/reload - требуется ручная проверка пользователем (manual human verification required); статически подтверждено, что flora packet/result wiring сохранён, а unload path по-прежнему идёт через existing chunk lifecycle, но визуальный runtime proof агентом не запускался.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `Godot_v4.6.1-stable_win64_console.exe --headless --path . --quit` - `exit 0`.
- Статическая проверка (Static verification): `git diff --check -- .claude/agent-memory/active-epic.md core/systems/world/chunk.gd core/systems/world/chunk_debug_renderer.gd core/systems/world/chunk_fog_presenter.gd core/systems/world/chunk_flora_presenter.gd docs/02_system_specs/world/DATA_CONTRACTS.md` - без замечаний.
- Статическая проверка (Static verification): `rg -n "ChunkDebugRenderer|ChunkFogPresenter|ChunkFloraPresenter" core/systems/world/chunk.gd core/systems/world/chunk_debug_renderer.gd core/systems/world/chunk_fog_presenter.gd core/systems/world/chunk_flora_presenter.gd` подтвердил thin facade wiring и новые owner files.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): прогнать `S-05` и `S-07` из `docs/04_execution/chunk_system_refactor_spec_2026-04-12.md`, а также один debug-build проход с включённой mountain debug visualization, чтобы увидеть batched debug markers вместо старого node spam.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): debug marker publication больше не использует `Polygon2D` per marker и идёт через один `ChunkDebugRenderer` с batched `draw_rect()` path; `rg` по `chunk.gd` для `Polygon2D` / `_debug_root` / `FloraBatchRenderer` вернул `0 matches`.
- Статическая проверка (Static verification): flora presentation больше не держит per-chunk texture cache inside `chunk.gd`; `ChunkFloraPresenter` использует `static var _shared_texture_cache` на строке 8.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): проверить `S-07` (unload/reload surface chunks) и debug scenario с включённой mountain debug visualization, чтобы подтвердить отсутствие regressions в flora publication и debug marker draw cost.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `ChunkDebugRenderer`: есть совпадения на строках 84, 612, 613, 917 - обновлено.
- Grep DATA_CONTRACTS.md для `ChunkFogPresenter`: есть совпадения на строках 85, 612, 613, 917 - обновлено.
- Grep DATA_CONTRACTS.md для `ChunkFloraPresenter`: есть совпадения на строках 86, 612, 613, 821, 917 - обновлено.
- Grep PUBLIC_API.md для `ChunkDebugRenderer|ChunkFogPresenter|ChunkFloraPresenter`: `0 matches` - not referenced.
- Секция "Required updates" в спеке: нет - `rg -n "Required contract and API updates|Required updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- Debug marker rule selection, fog revealability rules и flora packet shape всё ещё определяются в `chunk.gd`; это ожидаемо для Iteration 5, потому что visual kernel consolidation явно отложен на Iteration 6.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: observed files и presentation-owner detail теперь явно отражают `ChunkDebugRenderer`, `ChunkFogPresenter` и `ChunkFloraPresenter`; grep-доказательство приведено выше.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- не требовалось (not required) - `rg -n "ChunkDebugRenderer|ChunkFogPresenter|ChunkFloraPresenter" docs/00_governance/PUBLIC_API.md` вернул `0 matches`.

#### Blockers

- none

---

### Iteration 7 - Data-oriented hot-path conversion in `chunk.gd`

**Status**: completed
**Started**: 2026-04-12
**Completed**: 2026-04-12

#### Проверки приёмки (Acceptance tests)

- [x] chunk-local hot structures no longer depend on broad `Dictionary<Vector2i, ...>` usage where dense array access is possible
- [ ] border fix and cover behavior remain correct - manual human verification required
- [ ] no visible regression in chunk publication order - manual human verification required

#### Doc check

- [x] Grep DATA_CONTRACTS.md for changed names - completed; packed reveal mask and dense visual request contract updated
- [x] Grep PUBLIC_API.md for changed names - completed; internal dirty-batch helper and request contract note updated
- [x] Documentation debt section reviewed - completed; spec has no separate `Required updates` / `Documentation debt` section

#### Files touched

- `.claude/agent-memory/active-epic.md` - iteration 7 started and scope captured
- `core/systems/world/chunk.gd` - packed chunk-local hot storage, border-dirty queue helpers, and dense visual request payloads
- `core/systems/world/chunk_manager.gd` - scheduler and border-fix paths switched to explicit dirty-tile helpers instead of direct dictionary access
- `core/systems/world/chunk_visual_kernel.gd` - dense request-array readers and prebaked payload contract normalization
- `core/systems/world/mountain_roof_system.gd` - cover-edge reads now use chunk-local cached lookup instead of materializing a dictionary copy
- `gdextension/src/chunk_visual_kernels.cpp` - native visual kernel reads dense arrays plus secondary biome / ecotone blend inputs
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - packed reveal mask and dense visual request contract documented
- `docs/00_governance/PUBLIC_API.md` - helper/API contract notes updated for dirty-batch builder and compute request shape

#### Отчёт о выполнении (Closure Report)

## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- В `chunk.gd` горячие chunk-local структуры `pending border dirty`, `revealed local cover` и `cover edge` переведены с широких `Dictionary<Vector2i, ...>`-паттернов на packed chunk-local storage (`PackedByteArray`) и явные tile-list helpers.
- `ChunkManager` больше не читает `_pending_border_dirty` напрямую: scheduler, border-fix и dirty redraw path используют `has_pending_border_dirty()`, `collect_pending_border_dirty_tiles()`, `discard_pending_border_dirty_tiles()` и `build_visual_dirty_batch_from_tiles()`.
- Visual request builder перестал собирать большие lookup-словари для dense local data: в `Chunk._build_visual_compute_request()` и `ChunkVisualKernel` теперь проходят `terrain_bytes`, `height_bytes`, `variation_bytes`, `biome_bytes`, `secondary_biome_bytes` и `ecotone_values`, а sparse `terrain_lookup` остался только для out-of-chunk halo reads.
- `MountainRoofSystem` перестал материализовывать полный cover-edge dictionary ради membership-check и теперь опирается на `Chunk.has_cover_edge_cached()`.
- Native visual kernel в `chunk_visual_kernels.cpp` обновлён под новый request contract и использует primary/secondary biome plus ecotone factor для той же effective palette resolution, что и GDScript path.
- `DATA_CONTRACTS.md` и `PUBLIC_API.md` обновлены синхронно с изменённым manager/kernel/chunk contract.

### Корневая причина (Root cause)
- На hot path всё ещё оставались chunk-local структуры, которые repeatedly materialized или merge-или `Dictionary<Vector2i, ...>` ради простых membership / queue / dense lookup операций. Это раздувало GDScript allocation churn в seam fix, cover reveal и dirty visual request building, хотя authoritative state уже естественно индексируется как chunk-local dense grid.

### Изменённые файлы (Files changed)
- `core/systems/world/chunk.gd` - packed hot storage, dirty-tile queue helpers, reveal-mask helpers и dense request contract.
- `core/systems/world/chunk_manager.gd` - scheduler/border-fix integration через новые chunk helpers.
- `core/systems/world/chunk_visual_kernel.gd` - чтение dense arrays вместо обязательных dense lookup dictionaries.
- `core/systems/world/mountain_roof_system.gd` - cover-edge membership checks без materialized dictionary copy.
- `gdextension/src/chunk_visual_kernels.cpp` - native request context для `secondary_biome_bytes` и `ecotone_values`.
- `docs/02_system_specs/world/DATA_CONTRACTS.md` - contract text для packed reveal mask и dense visual requests.
- `docs/00_governance/PUBLIC_API.md` - helper/API notes для dirty batch builder и compute request shape.
- `.claude/agent-memory/active-epic.md` - recorded Iteration 7 completion evidence.

### Проверки приёмки (Acceptance tests)
- [x] `chunk-local hot structures no longer depend on broad Dictionary<Vector2i, ...> usage where dense array access is possible` - прошло (passed); проверено статически (static verification): `rg -n "var _cover_edge_set: PackedByteArray|var _pending_border_dirty: PackedByteArray|var _revealed_local_cover_tiles: PackedByteArray|func build_visual_dirty_batch_from_tiles|func has_pending_border_dirty|func collect_pending_border_dirty_tiles|terrain_bytes|secondary_biome_bytes|ecotone_values" core/systems/world/chunk.gd core/systems/world/chunk_manager.gd core/systems/world/chunk_visual_kernel.gd core/systems/world/mountain_roof_system.gd gdextension/src/chunk_visual_kernels.cpp` подтвердил packed hot fields, queue helpers и dense request arrays.
- [ ] `border fix and cover behavior remain correct` - требуется ручная проверка пользователем (manual human verification required); статически подтверждено, что `ChunkManager` и `MountainRoofSystem` используют те же safe entrypoints и общий `ChunkVisualKernel` contract, но seam/cover runtime proof агентом не прогонялся.
- [ ] `no visible regression in chunk publication order` - требуется ручная проверка пользователем (manual human verification required); headless startup прошёл, а direct/batch visual requests сохранены в одном contract, но визуальный publish-order сценарий агентом не прогонялся.

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): `git diff --check -- .claude/agent-memory/active-epic.md core/systems/world/chunk.gd core/systems/world/chunk_manager.gd core/systems/world/chunk_visual_kernel.gd core/systems/world/mountain_roof_system.gd docs/02_system_specs/world/DATA_CONTRACTS.md docs/00_governance/PUBLIC_API.md gdextension/src/chunk_visual_kernels.cpp` - без замечаний.
- Статическая проверка (Static verification): `python -m SCons -Q -j1` в `gdextension` - `exit 0`.
- Статическая проверка (Static verification): `Godot_v4.6.1-stable_win64_console.exe --headless --path C:/Users/peaceful/Station Peaceful/Station Peaceful --quit` - `exit 0`.
- Статическая проверка (Static verification): `rg -n "var _cover_edge_set: PackedByteArray|var _pending_border_dirty: PackedByteArray|var _revealed_local_cover_tiles: PackedByteArray|func build_visual_dirty_batch_from_tiles|func has_pending_border_dirty|func collect_pending_border_dirty_tiles|terrain_bytes|secondary_biome_bytes|ecotone_values" ...` подтвердил packed-storage conversion и dense request inputs в затронутых файлах.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): прогнать `S-02` (player chunk transition), `S-03` (seam mining) и `S-04` (interior mining) из `docs/04_execution/chunk_system_refactor_spec_2026-04-12.md`; отдельно посмотреть reveal/cover поведение в `S-05`, если в вашей ветке активно используется underground reveal.

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): runtime work class остался split между `interactive` dirty unit и `background/native` visual compute; синхронный update теперь ограничен chunk-local tile index / explicit dirty tile list вместо широких `Dictionary` merge path.
- Статическая проверка (Static verification): `Chunk._build_visual_compute_request()` передаёт dense center arrays напрямую, а `terrain_lookup` остаётся sparse halo fallback only, поэтому request building больше не создаёт большой dense dictionary для каждого batch.
- Статическая проверка (Static verification): `MountainRoofSystem` больше не материализует full cover-edge dictionary ради `has()`-проверок, а использует `Chunk.has_cover_edge_cached()` по local index.
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): не запускался в этой задаче по policy.
- Ручная проверка пользователем (Manual human verification): требуется.
- Рекомендованная проверка пользователем (Suggested human check): сравнить seam mining и border-fix сценарии `S-03`/`S-04` до и после правки на предмет frame spike и визуальной эквивалентности.

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `_revealed_local_cover_tiles`: есть совпадение на строке 451 - обновлено, теперь это packed chunk-local erase mask.
- Grep DATA_CONTRACTS.md для `terrain_bytes|secondary_biome_bytes|ecotone_values|build_visual_dirty_batch_from_tiles`: есть совпадения на строках 677, 701, 712, 722 - обновлено под dense request contract и explicit dirty-tile batch builder.
- Grep PUBLIC_API.md для `build_visual_dirty_batch_from_tiles`: есть совпадение на строке 513 - обновлено.
- Grep PUBLIC_API.md для `terrain_bytes|secondary_biome_bytes|ecotone_values`: есть совпадения на строках 500 и 637 - request contract note согласован.
- Grep DATA_CONTRACTS.md и PUBLIC_API.md для `has_pending_border_dirty|get_pending_border_dirty_count|collect_pending_border_dirty_tiles|discard_pending_border_dirty_tiles|has_cover_edge_cached`: `0 matches` - internal helpers, отдельной contract/API documentation не требуют.
- Секция "Required updates" в спеке: нет - `rg -n "Documentation debt|Required updates|Required contract and API updates" docs/04_execution/chunk_system_refactor_spec_2026-04-12.md` вернул `0 matches`.

### Наблюдения вне задачи (Out-of-scope observations)
- `chunk.gd` остаётся крупным owner-файлом даже после data-oriented cleanup; вынесение оставшегося heavy work и дальнейшая manager decomposition уже зарезервированы в Iteration 8-9 и не расширялись в этой итерации.

### Оставшиеся блокеры (Remaining blockers)
- нет

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- Обновлено: packed reveal-mask semantics и dense visual request contract зафиксированы на строках 451, 677, 701, 712 и 722; grep-доказательство приведено выше.

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- Обновлено: `Chunk.build_visual_dirty_batch_from_tiles(...)` добавлен на строке 513, а note для compute/request payload согласован на строке 637; grep-доказательство приведено выше.

#### Blockers

- none
