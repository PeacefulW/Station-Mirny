---
title: Public API
doc_type: governance
status: draft
owner: engineering
source_of_truth: true
version: 0.7
last_updated: 2026-04-13
depends_on:
  - WORKFLOW.md
  - ../02_system_specs/world/DATA_CONTRACTS.md
related_docs:
  - WORKFLOW.md
  - ../02_system_specs/world/DATA_CONTRACTS.md
---

# PUBLIC API — Точки входа в системы

> Этот документ отвечает на вопрос: "я хочу сделать X — какую функцию вызвать?"
>
> Если функции нет в секции "Безопасные точки входа" — вызывать её запрещено.
> Если нужной операции нет в этом документе — спроси человека, не ищи сам.

## Как пользоваться этим документом

1. Определи, что ты хочешь сделать: читать terrain, копать, переключать z-level, дождаться topology, и т.д.
2. Найди соответствующую систему ниже.
3. Используй только функции из "Безопасные точки входа".
4. Для чтения данных используй только функции из "Чтение".
5. Для реакции на изменения подписывайся только на события из "События".
6. Если система ниже говорит "safe entry point отсутствует", не ищи обходной путь в коде.

---

## Quick Reference

| Я хочу X | Вызови Y |
| --- | --- |
| Прочитать terrain по global tile | `ChunkManager.get_terrain_type_at_global()` |
| Проверить walkability по world position | `ChunkManager.is_walkable_at_world()` |
| Выкопать rock tile | `ChunkManager.try_harvest_at_world()` |
| Переключить z-level | `ZLevelManager.change_level()` |
| Прочитать current z | `ZLevelManager.get_current_z()` |
| Сбросить или восстановить игровое время | `TimeManager.reset_for_new_game()` / `TimeManager.restore_persisted_state()` |
| Сохранить / загрузить слот | `SaveManager.save_game()` / `SaveManager.load_game()` |
| Поставить загрузку в очередь после смены сцены | `SaveManager.request_load_after_scene_change()` |
| Выдать игроку предмет | `Player.collect_item()` |
| Потратить item / scrap у игрока | `Player.spend_item()` / `Player.spend_scrap()` |
| Нанести урон сущности | `HealthComponent.take_damage()` |
| Добавить / убрать stack из inventory | `InventoryComponent.add_item()` / `InventoryComponent.remove_item()` |
| Переместить / разделить / отсортировать / выбросить stack | `InventoryComponent.move_slot_contents()` / `split_stack()` / `sort_slots_by_name()` / `remove_slot_contents()` |
| Экипировать / снять предмет через inventory handoff | `EquipmentComponent.equip_from_inventory_slot()` / `EquipmentComponent.unequip_to_inventory()` |
| Прочитать процент кислорода | `OxygenSystem.get_oxygen_percent()` |
| Проверить питание life support | `BaseLifeSupport.is_powered()` |
| Изменить demand life support | `BaseLifeSupport.set_power_demand()` |
| Выбрать / поставить / снести постройку | `BuildingSystem.set_selected_building()` / `BuildingSystem.place_selected_building_at()` / `BuildingSystem.remove_building_at()` |
| Проверить, можно ли поставить выбранную постройку | `BuildingSystem.can_place_selected_building_at()` |
| Проверить indoor tile | `BuildingSystem.is_cell_indoor()` |
| Прочитать power balance | `PowerSystem.get_balance()` / `PowerSystem.get_supply_ratio()` |
| Изменить runtime power config | `PowerSourceComponent.set_enabled()` / `PowerSourceComponent.set_condition()` / `PowerSourceComponent.set_max_output()` / `PowerConsumerComponent.set_demand()` / `PowerConsumerComponent.set_priority()` |
| Сохранить / восстановить pickups и enemy runtime | `SpawnOrchestrator.save_pickups()` / `load_pickups()` / `save_enemy_runtime()` / `load_enemy_runtime()` |
| Проверить enemy runtime state | `BasicEnemy.is_dead()` / `BasicEnemy.has_target()` |
| Включить / выключить шумный источник | `NoiseComponent.set_active()` |
| Запросить in-world z transition с overlay orchestration | `GameWorld.request_z_transition()` |
| Поставить время на паузу / изменить scale | `TimeManager.set_paused()` / `TimeManager.set_time_scale()` |
| Скрафтить рецепт | `CraftingSystem.execute_recipe()` |
| Выполнить game command | `CommandExecutor.execute()` |
| Получить read-only content data | `ItemRegistry.get_item()` / `BiomeRegistry.get_biome()` / `FloraDecorRegistry.get_flora_set()` / `WorldFeatureRegistry.get_feature_by_id()` / `WorldFeatureRegistry.get_poi_by_id()` |
| Проверить boot first-playable | `ChunkManager.is_boot_first_playable()` |
| Проверить boot complete | `ChunkManager.is_boot_complete()` |
| Показать F11 chunk debug overlay | `ChunkManager.get_chunk_debug_overlay_snapshot()` / `WorldPerfMonitor.get_debug_snapshot()` |

---

## World (terrain read/write)

`classification`: `canonical`  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Layer: World`, `Loaded Vs Unloaded Read-Path Rules`, `Source Of Truth Vs Derived State`.

### Безопасные точки входа

`ChunkManager.set_saved_data(data: Dictionary) -> void`
- Когда вызывать: при применении save-state overlay к world runtime до того, как начнутся authoritative unloaded reads.
- Что делает: нормализует ключи состояния чанков и заменяет текущий `_saved_chunk_data`.
- Гарантии: сохраняет canonical read ladder `loaded chunk -> saved overlay -> underground ROCK -> surface generator fallback`; не меняет loaded terrain напрямую.
- Пример вызова: `chunk_manager.set_saved_data(save_blob.get("chunks", {}))`

Примечание: generic runtime terrain mutation не имеет безопасного public API в world-layer. Для изменения `ROCK -> MINED_FLOOR / MOUNTAIN_ENTRANCE` используй safe entrypoint из секции `Mining`.

### Чтение

`ChunkManager.get_terrain_type_at_global(tile_pos: Vector2i) -> int`
- Что возвращает: текущий terrain type для global tile.
- Когда использовать: для любого authoritative terrain read, особенно если tile может быть в unloaded chunk.
- Особенности: authoritative read. Работает для loaded и unloaded; использует fallback chain из `DATA_CONTRACTS.md`.

`ChunkManager.is_walkable_at_world(world_pos: Vector2) -> bool`
- Что возвращает: проходим ли tile по world position (не `ROCK` и не `WATER`).
- Когда использовать: для gameplay walkability checks (movement, pathfinding).
- Особенности: делегирует в `get_terrain_type_at_global()` + `_is_walkable_terrain()`; корректен для loaded и unloaded tiles, включая underground (unloaded underground = `ROCK` = not walkable).

`ChunkManager.is_tile_loaded(gt: Vector2i) -> bool`
- Что возвращает: загружен ли chunk, содержащий tile.
- Когда использовать: перед loaded-only reads или loaded-only mutations.
- Особенности: не читает terrain; это только loaded-state probe.

`ChunkManager.get_chunk_at_tile(gt: Vector2i) -> Chunk`
- Что возвращает: loaded `Chunk` или `null`.
- Когда использовать: если нужен loaded chunk object для loaded-only read paths.
- Особенности: loaded-only; не даёт права на direct mutation.

`ChunkManager.get_chunk(cc: Vector2i) -> Chunk`
- Что возвращает: loaded `Chunk` по chunk coord или `null`.
- Когда использовать: для доступа к уже загруженному chunk по coord.
- Особенности: loaded-only; не authoritative для unloaded world.

`Chunk.get_terrain_type_at(local: Vector2i) -> int`
- Что возвращает: terrain type из local array loaded chunk.
- Когда использовать: только после `get_chunk()` / `get_chunk_at_tile()` и только для loaded chunk reads.
- Особенности: loaded-only; не authoritative для unloaded world. При невалидном local index now raises `push_error` + `assert` and falls back to `ROCK` instead of silently returning `GROUND`.

`ChunkManager.get_save_data() -> Dictionary`
- Что возвращает: snapshot unloaded overlay плюс dirty diffs загруженных чанков.
- Когда использовать: на save/export boundary.
- Особенности: не terrain read API для gameplay; это save collection API.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `Chunk._set_terrain_type(local_tile: Vector2i, terrain_type: int, mark_modified: bool = true) -> void` | Raw canonical write. Не запускает mining/topology/reveal orchestration сам по себе. |
| `Chunk.mark_tile_modified(tile_pos: Vector2i, state: Dictionary) -> void` | Пишет только diff и dirty-флаг; не обновляет topology, reveal, seam redraw. |
| `Chunk.populate_native(native_data: Dictionary, saved_modifications: Dictionary, instant: bool = false) -> void` | Lifecycle-only install path. Одновременно ставит native arrays, replay save diff и стартует redraw. |
| Direct access to `Chunk._terrain_bytes`, `Chunk._modified_tiles`, `ChunkManager._saved_chunk_data` | Ломает source-of-truth boundary из `DATA_CONTRACTS.md`; bypasses arbitration и invalidation chain. |

### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `none` | У world-layer нет dedicated terrain-changed signal в scope | gap |

---

## Mining

`classification`: `canonical`  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Layer: Mining`, `Postconditions: mine tile`, `Boundary Rules At Chunk Seams`.

### Безопасные точки входа

`ChunkManager.try_harvest_at_world(world_pos: Vector2) -> Dictionary`
- Когда вызывать: когда игрок или gameplay command пытается выкопать rock-tile по world position.
- Что делает: находит loaded chunk, вызывает chunk-local mining, re-normalizes same-chunk and cross-chunk seam neighbors, patch-обновляет topology, эмитит mining event, а на underground ещё и immediately updates fog reveal.
- Гарантии: соблюдает `Postconditions: mine tile`; safe orchestration point для mining-layer.
- Пример вызова: `var result: Dictionary = chunk_manager.try_harvest_at_world(hit_world_pos)`

`HarvestTileCommand.execute() -> Dictionary`
- Когда вызывать: из command pipeline, когда добыча должна пройти через command object, а не direct service call.
- Что делает: валидирует наличие `ChunkManager` и делегирует в `ChunkManager.try_harvest_at_world(_world_pos)`.
- Гарантии: сохраняет тот же orchestration contract, что и прямой safe mining entrypoint.
- Пример вызова: `var result := HarvestTileCommand.new().setup(chunk_manager, hit_pos).execute()`

### Чтение

`ChunkManager.has_resource_at_world(world_pos: Vector2) -> bool`
- Что возвращает: есть ли сейчас `ROCK` по world position через тот же terrain arbiter, что и world-layer reads.
- Когда использовать: перед попыткой mining interaction.
- Особенности: authoritative для loaded и unloaded tiles; unloaded underground now follows the same `ROCK` fallback as `get_terrain_type_at_global()`.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `Chunk.try_mine_at(local: Vector2i) -> Dictionary` | Guarded chunk-local mutation primitive. Без owner authorization from `ChunkManager.try_harvest_at_world()` теперь assert-ит и не должен использоваться как обходной mining path. |
| `Chunk._refresh_open_neighbors(local_tile: Vector2i) -> void` | Это normalization helper, а не safe mining API. Сам по себе не выполняет полный mining contract. |
| `Chunk._refresh_open_tile(local_tile: Vector2i) -> void` | Low-level helper для `MINED_FLOOR <-> MOUNTAIN_ENTRANCE` normalization. |
| `ChunkManager._seam_normalize_and_redraw(tile_pos: Vector2i, local_tile: Vector2i, source_chunk: Chunk) -> void` | Cross-chunk redraw helper. Нельзя использовать как substitute для mining orchestration. |
| `ChunkManager.ensure_underground_pocket(center_tile: Vector2i, pocket_tiles: Array) -> void` | Debug-only helper that now reuses `try_harvest_at_world()` internally after loading required underground chunks; still не gameplay API. |

### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.mountain_tile_mined` | После успешного `ChunkManager.try_harvest_at_world()` и immediate topology patch | `(tile_pos: Vector2i, old_type: int, new_type: int)` |

---

## Chunk Lifecycle

`classification`: `canonical` for loaded chunk install/unload orchestration, `presentation-only` for redraw progress.  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Postconditions: generate chunk`, `Layer: World`, `Layer: Presentation`.

### Безопасные точки входа

`ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`
- Когда вызывать: в boot sequence, когда initial world bubble должен быть загружен и доведён до gameplay-ready state.
- Что делает: staged boot with bounded-parallel compute and split apply owned internally by `ChunkBootPipeline`. If the entrypoint is called in the same frame as `ChunkManager` creation, it first waits for the manager's deferred init instead of silently no-op returning; until this entrypoint really starts, `ChunkManager` stays boot-gated and must not leak into runtime `player_chunk_check` / `stream_load` behavior. Boot apply path only installs chunk nodes and attaches cached native/flora payloads; visual publication then goes through the budgeted chunk visual scheduler plus chunk-local `ChunkVisualState`. Fresh startup chunks stay `visible=false` until their first `Chunk.is_full_redraw_ready()` publication closes; first-pass work may still progress internally, but it no longer authorizes player-visible publication of a raw chunk. Returns after the near slice reaches the internal `first_playable` milestone, then unfinished startup coords continue through budgeted runtime scheduling and boot finalization until real completion. Surface topology convergence remains a separate boot-tracked dependency owned internally by `ChunkTopologyService`.
- Гарантии: `first_playable` = ring 0..1 chunks are loaded, applied, and fully converged to `Chunk.is_full_redraw_ready()` under Chebyshev distance (`max(abs(dx), abs(dy))`); topology is NOT part of the internal `ChunkBootPipeline` `first_playable` gate. `boot_complete` = all tracked startup chunks terminal (`VISUAL_COMPLETE`, meaning `Chunk.is_full_redraw_ready()`) + topology ready. Player-visible handoff must not rely on raw first-pass readiness; loading/UI handoff happens only after the full boot-ready milestone in `GameWorld` (startup chunks terminal + boot shadow work drained). Chunk visibility is gated on full publication for fresh loads, and perf wins do not count if the player can still see green/raw chunk build-up. См. `Boot Readiness State` и `Boot Compute Queue` layers в `DATA_CONTRACTS.md`.
- Пример вызова: `await chunk_manager.boot_load_initial_chunks(_on_boot_progress)`

`ChunkManager.sync_display_to_player() -> void`
- Когда вызывать: когда display positions loaded chunks нужно пересинхронизировать с player reference chunk.
- Что делает: вычисляет reference chunk и обновляет display position у всех loaded chunks.
- Гарантии: не меняет canonical terrain или topology; presentation-only display sync.
- Пример вызова: `chunk_manager.sync_display_to_player()`

Примечание: public per-chunk `load/unload` request API в scope сейчас нет. Runtime streaming paths остаются internal.
После R4 frontier planning runtime streaming internals route through `TravelStateResolver`, `ViewEnvelopeResolver`, `FrontierPlanner`, `FrontierScheduler`, and lane-owned queues inside `ChunkStreamingService`; `ChunkManager` остаётся world-facing facade и final install entry facade. Frontier-critical work has a reserved worker slot, and callers must not submit gameplay load/unload requests directly into those internal lanes.
После Iteration 9 visual scheduler state routed through internal `ChunkVisualScheduler`, surface payload reuse through internal `ChunkSurfacePayloadCache`, seam/border follow-up ownership through internal `ChunkSeamService`, boot readiness/compute ownership through internal `ChunkBootPipeline`, and topology runtime ownership through internal `ChunkTopologyService`. These services are not public gameplay APIs; callers still use the `ChunkManager` entrypoints listed here.

### Чтение

`ChunkManager.get_loaded_chunks() -> Dictionary`
- Что возвращает: текущий map loaded chunks для active z.
- Когда использовать: если owner-system должен итерировать только по already-loaded chunks.
- Особенности: loaded-only snapshot; не описывает unloaded world.

`ChunkManager.get_chunk_debug_overlay_snapshot(max_queue_rows: int = 14, debug_radius: int = -1) -> Dictionary`
- Что возвращает: read-only diagnostic snapshot для F11 overlay: `player_chunk`, `active_z`, factual radii, bounded chunk entries, capped/grouped `queue_rows`, timeline events, compact metrics, frontier plan/capacity/lane queue metrics, plus bounded debug-only `incident_summary`, `trace_events`, `chunk_causality_rows`, `task_debug_rows`, and `suspicion_flags`.
- Когда использовать: только для in-game debug overlay / diagnostics, когда нужно понять pipeline order `request -> queue -> generate -> apply -> build visual -> visible -> unload` во время движения игрока.
- Особенности: active-z scoped, bounded around player and clamped by `DEBUG_OVERLAY_MAX_RADIUS`; не public load/unload API, не gameplay truth, не persistence data. Frontier fields expose diagnostic labels such as `frontier_critical`, `camera_visible_support`, `background`, and `frontier_reserved_capacity_blocks`; they are read-only evidence of scheduler state, not caller commands. Snapshot rows may label `stalled` only as observed delay unless an owner diagnostic record proves root cause; `suspicion_flags` are observational hints, not proof.

`ChunkManager.is_tile_loaded(gt: Vector2i) -> bool`
- Что возвращает: загружен ли tile сейчас.
- Когда использовать: как guard перед loaded-only operations.
- Особенности: не инициирует загрузку.

`ChunkManager.get_chunk_at_tile(gt: Vector2i) -> Chunk`
- Что возвращает: loaded chunk containing tile или `null`.
- Когда использовать: при loaded-only lifecycle/presentation reads.
- Особенности: не authoritative для unloaded reads.

`Chunk.is_first_pass_ready() -> bool`
- Что возвращает: достиг ли chunk first-pass visual readiness (`terrain-ready`, `full-pending`, или `full-ready` state). `proxy`/native-only и terrain-only redraw этого gate не проходят.
- Когда использовать: scheduler-owned convergence bookkeeping, follow-up `TASK_FULL_REDRAW` scheduling, и owner-side проверки "дошёл ли chunk хотя бы до cover-complete first pass".
- Особенности: это больше не public visibility/publication contract. `first-pass` остаётся внутренним промежуточным milestone, но player-visible publication нового чанка и boot handoff должны опираться на `Chunk.is_full_redraw_ready()`.

`Chunk.is_full_redraw_ready() -> bool`
- Что возвращает: достиг ли chunk терминального full-redraw состояния (`ChunkVisualState.FULL_READY`).
- Когда использовать: initial chunk publication gates, boot/readiness gates, и owner-side проверки, где игрок уже может видеть chunk.
- Особенности: это canonical publication/terminal query. Fresh chunk load не должен становиться visible раньше этого состояния; perf-оптимизация не считается принятой, если игрок всё ещё видит достройку cliff/flora/near-world presentation на глазах. Flora render packets count as published when the chunk-local presenter has the packet, but texture priming is non-blocking and may temporarily use packet fallback colors instead of stalling the visual scheduler. Значение может снова стать `false`, если seam/mutation/approximation инвалидирует terminal convergence и owner path ещё не закрыл owed follow-up work.

`Chunk.needs_full_redraw() -> bool`
- Что возвращает: достиг ли chunk внутреннего first-pass milestone, но всё ещё ли должен дойти до terminal full redraw before visibility/occupancy is allowed.
- Когда использовать: только в lifecycle/scheduler owner-path, когда нужно решить, ставить ли follow-up `TASK_FULL_REDRAW`.
- Особенности: read-only helper над `ChunkVisualState`; не делает redraw сам по себе и не даёт права на publication/player entry. Используется и для первичного convergence после first-pass, и для повторного FULL_PENDING после owner-side invalidation.

`Chunk.is_redraw_complete() -> bool`
- Что возвращает: завершён ли progressive redraw этого chunk.
- Когда использовать: diagnostic/debug helper around the chunk-local progressive redraw machine; не использовать как visibility/occupancy gate.
- Особенности: `Chunk.is_full_redraw_ready()` — более честный owner-facing readiness query; terrain уже authoritative even if redraw not complete.

`Chunk.is_gameplay_redraw_complete() -> bool`
- Что возвращает: завершены ли terrain + cover + cliff фазы (phase >= FLORA).
- Когда использовать: если нужен gameplay-safe terrain/cover/cliff completion без ожидания flora/debug.
- Особенности: это phase helper, а не public boot/readiness contract. Больше не используется как честный `VISUAL_COMPLETE` / `boot_complete` gate.

`Chunk.is_flora_phase_done() -> bool`
- Что возвращает: завершилась ли flora фаза progressive redraw (phase > FLORA).
- Когда использовать: low-level debug/telemetry around legacy redraw phases.
- Особенности: не является основным query для boot readiness после Iteration 2.

`Chunk.is_terrain_phase_done() -> bool`
- Что возвращает: прошёл ли chunk terrain фазу progressive redraw (phase > TERRAIN).
- Когда использовать: compatibility/debug helper around the current redraw implementation.
- Особенности: это больше не публичная семантика "chunk можно показать"; для visibility/readiness используй `Chunk.is_full_redraw_ready()`.

`Chunk.get_redraw_phase_name() -> StringName`
- Что возвращает: текущую фазу progressive redraw.
- Когда использовать: debug/telemetry around chunk redraw.
- Особенности: presentation-only progress indicator.

`ChunkManager.is_boot_first_playable() -> bool`
- Что возвращает: достигнут ли internal `first_playable` gate — near slice ring 0..1 (Chebyshev distance, включая диагонали) честно доведена до `Chunk.is_full_redraw_ready()`, без topology.
- Когда использовать: boot progress UI и `GameWorld` boot sequence как сигнал "можно запускать post-ready finalization", но не как разрешение показать игроку сырой мир.
- Особенности: topology НЕ входит в `first_playable`. Возвращает `false` до вызова `boot_load_initial_chunks()`. Это больше не player-handoff milestone; loading screen/input/physics должны дождаться полного boot-ready handoff.

`ChunkManager.is_boot_complete() -> bool`
- Что возвращает: достигнут ли `boot_complete` gate — все startup chunks `VISUAL_COMPLETE` (full-ready) И topology ready.
- Когда использовать: для определения chunk/topology части полного boot sequence.
- Особенности: включает outer rings и topology. Возвращает `false` до полного завершения boot path. До финального `boot_complete` startup chunk может быть временно demoted из `VISUAL_COMPLETE` обратно в `APPLIED`, если поздняя seam/convergence invalidation снова делает его не full-ready. В `GameWorld` player-visible handoff должен дополнительно дождаться boot shadow completion.

`ChunkManager.get_boot_chunk_states_snapshot() -> Dictionary`
- Что возвращает: копию `Dictionary` { `Vector2i` -> `BootChunkState` } для всех startup chunks.
- Когда использовать: debug/instrumentation, boot progress visualization.
- Особенности: read-only snapshot; не влияет на boot state.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `ChunkManager._load_chunk(coord: Vector2i) -> void` | Internal streaming primitive for current active z only. |
| `ChunkManager._load_chunk_for_z(coord: Vector2i, z_level: int) -> void` | Thin facade over `ChunkStreamingService.load_chunk_for_z()` + final install commit. Нельзя дёргать как ad-hoc API. |
| `ChunkManager._unload_chunk(coord: Vector2i) -> void` | Thin facade over `ChunkStreamingService.unload_chunk()`; internal unload/save boundary с dirty diff save + topology invalidation. |
| `TravelStateResolver.resolve(...) -> Dictionary` | Internal runtime planning input. Не gameplay API для движения, транспорта или prediction tuning. |
| `ViewEnvelopeResolver.resolve(...) -> Dictionary` | Internal camera envelope derivation for streaming. Callers must not use it as visibility/gameplay truth. |
| `FrontierPlanner.build_plan(...) -> Dictionary` | Internal active-z streaming plan. Нельзя использовать как external load request или readiness guarantee. |
| `FrontierScheduler.resolve_lane_for_coord(...)` / `FrontierScheduler.build_capacity_snapshot(...)` | Internal lane classification and reservation policy. Bypassing it can starve frontier-critical work. |
| `ChunkStreamingService.update_chunks()`, `enqueue_load_request()`, `tick_loading()`, `submit_async_generate()`, `collect_completed_runtime_generates()` | Internal streaming scheduler and worker handoff. Эти методы исполняют owner-owned runtime queues; caller-facing per-chunk load/unload API intentionally absent. |
| `Chunk.setup(...) -> void` | Constructor-phase install only. Требует lifecycle owner и valid tilesets/manager wiring. |
| `Chunk.cleanup() -> void` | Unload-only cleanup path. |

### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.chunk_loaded` | После регистрации chunk и topology invalidation в load path | `(chunk_coord: Vector2i)` |
| `EventBus.chunk_unloaded` | После сохранения dirty diff, cleanup и topology invalidation в unload path | `(chunk_coord: Vector2i)` |

---

## Topology

`classification`: `derived`  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Layer: Topology`, `Loaded Vs Unloaded Read-Path Rules`.

### Безопасные точки входа

`ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`
- Когда вызывать: когда surface topology должна быть готова до старта gameplay.
- Что делает: инициализирует `ChunkBootPipeline` startup bubble и boot gates, после чего topology остается отдельной boot-tracked зависимостью, owned internally by `ChunkTopologyService`. Topology work может завершиться во время boot loop или продолжиться через budgeted topology pipeline после `first_playable`, без подмены visual/readiness semantics.
- Гарантии: topology ready is part of the internal `ChunkBootPipeline` `boot_complete` gate but NOT part of the internal `ChunkBootPipeline` `first_playable` gate. Rings use Chebyshev distance. См. `Boot Readiness State` layer в `DATA_CONTRACTS.md`.
- Пример вызова: `await chunk_manager.boot_load_initial_chunks(_on_boot_progress)`

`ChunkManager.try_harvest_at_world(world_pos: Vector2) -> Dictionary`
- Когда вызывать: когда topology должна обновиться после mining.
- Что делает: после successful mining вызывает manager-owned facade `_on_mountain_tile_changed()`, который обновляет loaded open-pocket mirror и прокидывает topology mutation в internal `ChunkTopologyService` до emission `EventBus.mountain_tile_mined`.
- Гарантии: immediate incremental topology patch runs before downstream listeners react; см. `Postconditions: mine tile`.
- Пример вызова: `var result := chunk_manager.try_harvest_at_world(hit_world_pos)`

### Чтение

`ChunkManager.is_topology_ready() -> bool`
- Что возвращает: готова ли surface topology для active runtime.
- Когда использовать: если код должен дождаться readiness before reading topology. Also used by `_tick_boot_remaining()` to poll topology completion for `boot_complete` gate.
- Особенности: authoritative only for currently loaded surface bubble; нет dedicated ready event. **Not part of `first_playable` gate** — topology is decoupled from first_playable. Part of `boot_complete` gate. Для managed scheduler path возвращает `false`, пока active dirty rebuild ещё находится в одном из owner-owned этапов `snapshot capture -> native worker compute -> ready-snapshot commit`.

`ChunkManager.get_mountain_key_at_tile(tile_pos: Vector2i) -> Vector2i`
- Что возвращает: component key for mountain topology tile.
- Когда использовать: для component membership reads на surface.
- Особенности: surface-only; на underground возвращает sentinel `Vector2i(999999, 999999)`. Не synthesizes unloaded topology.

`ChunkManager.get_mountain_tiles(mountain_key: Vector2i) -> Dictionary`
- Что возвращает: все tiles в tracked mountain component.
- Когда использовать: если нужен current loaded-bubble component domain.
- Особенности: derived, loaded-bubble scoped, surface-only.

`ChunkManager.get_mountain_open_tiles(mountain_key: Vector2i) -> Dictionary`
- Что возвращает: open subset (`MINED_FLOOR` / `MOUNTAIN_ENTRANCE`) для mountain component.
- Когда использовать: для derived open-pocket reads on surface topology cache.
- Особенности: derived, surface-only, loaded-bubble scoped.

`ChunkManager.query_local_underground_zone(seed_tile: Vector2i) -> Dictionary`
- Что возвращает: local loaded open-pocket product `{ zone_kind, seed_tile, tiles, chunk_coords, truncated }`.
- Когда использовать: reveal-layer queries around already-open mined zone.
- Особенности: loaded-only; запрос идёт через native `LoadedOpenPocketQuery`, который читает active-z loaded mirror, а `truncated = true`, если traversal упирается в unloaded continuation или достигает hard cap native query.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `ChunkManager._tick_topology() -> bool` | Owner-side budget job that delegates dirty topology convergence to internal `ChunkTopologyService.tick()` after streaming is idle; не caller-facing API. |
| `ChunkManager._setup_native_topology_builder() -> void` | Startup-only facade that activates the validated native topology backend through internal `ChunkTopologyService`; callers must not toggle topology backend policy manually. |
| `ChunkManager._on_mountain_tile_changed(tile_pos: Vector2i, old_type: int, new_type: int) -> void` | Internal mining follow-up that updates the loaded open-pocket mirror and forwards topology mutation into internal `ChunkTopologyService`; caller не должен поддерживать topology вручную. |
| Native builder calls `set_chunk`, `remove_chunk`, `update_tile`, `ensure_built` | Internal backend contract behind `ChunkTopologyService` / `ChunkManager`; direct callers рискуют разойтись с managed topology state. |

### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `none` | Dedicated `topology_changed` / `topology_ready` signal в scope отсутствует | gap |

---

## Reveal

`classification`: `derived`  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Layer: Reveal`, `Postconditions: mine tile`.

### Безопасные точки входа

`ChunkManager.try_harvest_at_world(world_pos: Vector2) -> Dictionary`
- Когда вызывать: когда successful underground mining должен сразу открыть newly mined tile и соседний halo в fog.
- Что делает: на underground success вызывает `UndergroundFogState.force_reveal()` для mined tile + 8 neighbors и сразу applies visible fog erase to loaded revealable tiles.
- Гарантии: immediate underground reveal side-effects из `Postconditions: mine tile`; canonical terrain semantics не меняются вне mining contract. На surface downstream `MountainRoofSystem` сначала пытается применить bounded local cover patch для incremental/bootstrap reveal case, более крупные cover deltas переводит в queued cover-apply path, а полный local-zone refresh теперь идёт staged multi-frame rebuild even when the player is still standing outside the newly opened pocket.
- Пример вызова: `var result := chunk_manager.try_harvest_at_world(hit_world_pos)`

Примечание: z-switch reveal side-effects достигаются через canonical owner-path `ZLevelManager.change_level()`. `ChunkManager.set_active_z_level()` остаётся downstream sink и не является public z-switch API.

Примечание: public surface reveal refresh API сейчас нет. `MountainRoofSystem` владеет refresh internally и сам реагирует на player movement, chunk load/unload и mining events. Mining-triggered surface reveal no longer depends on the player already standing on an opened mountain tile: system first tries a bounded immediate local patch by reusing the active zone seed when the mined tile touches it or by bootstrapping a one-tile zone, escalates larger cover apply work into the queued apply path, and runs full local-zone cover rebuild through a staged multi-frame refresh instead of a monolithic `_process()` rebuild.

### Чтение

`MountainRoofSystem.has_active_local_zone() -> bool`
- Что возвращает: есть ли сейчас active local reveal zone на surface.
- Когда использовать: для UI/debug around surface cave reveal state.
- Особенности: derived, surface-only, loaded-bubble scoped.

`MountainRoofSystem.get_active_local_zone_tile_count() -> int`
- Что возвращает: размер active local zone в тайлах.
- Когда использовать: debug/UI around reveal state size.
- Особенности: derived; не authoritative terrain read.

`MountainRoofSystem.is_active_local_zone_truncated() -> bool`
- Что возвращает: был ли active local zone traversal обрезан unloaded boundary.
- Когда использовать: если нужно понимать, что reveal state неполный.
- Особенности: derived gap marker; не меняет runtime behavior сам по себе.

`UndergroundFogState.is_revealed(tile: Vector2i) -> bool`
- Что возвращает: был ли tile когда-либо открыт в текущем underground runtime.
- Когда использовать: если уже есть доступ к shared fog-state instance у owner-system.
- Особенности: transient session state; не persisted.

`UndergroundFogState.is_visible(tile: Vector2i) -> bool`
- Что возвращает: входит ли tile в текущий visible set.
- Когда использовать: для owner-side fog presentation decisions.
- Особенности: transient; tied to current underground runtime.

`Chunk.is_fog_revealable(local_tile: Vector2i) -> bool`
- Что возвращает: должен ли local tile быть видимым для underground fog system.
- Когда использовать: внутри loaded-chunk fog application logic.
- Особенности: loaded-only chunk read; не source-of-truth reveal state.

`Chunk.is_revealable_cover_edge(local_tile: Vector2i) -> bool`
- Что возвращает: является ли local rock-tile revealable cover edge на surface.
- Когда использовать: reveal-layer cover halo logic.
- Особенности: loaded-only helper; не canonical terrain read.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `MountainRoofSystem._request_refresh(force_refresh: bool = false) -> void` | Internal refresh scheduler. Сам управляет cache/incremental/full refresh strategy. |
| `MountainRoofSystem._refresh_active_local_zone(seed_tile: Vector2i) -> void` | Full reveal recompute implementation. |
| `Chunk.set_revealed_local_cover_tiles(cover_tiles: Dictionary) -> void` | Presentation apply method. Внешний caller может разойтись с reveal source state. |
| `Chunk.apply_fog_visible(visible_locals: Dictionary) -> void` | Fog presentation apply, не fog-state source of truth. |
| `Chunk.apply_fog_discovered(discovered_locals: Dictionary) -> void` | Fog presentation apply, не fog-state source of truth. |
| `UndergroundFogState.update(player_tile: Vector2i) -> Dictionary` | Owner-only state transition method; внешний код не должен вести fog timeline напрямую. |
| `UndergroundFogState.force_reveal(tiles: Array) -> void` | Owner-only immediate reveal helper for mining path. |
| `UndergroundFogState.clear() -> void` | Owner-only reset on z-entry/new runtime. |

### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `none` | Dedicated reveal-changed signal в scope отсутствует | gap |

---

## Presentation

`classification`: `presentation-only`  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Layer: Presentation`, `Wall Atlas Selection`.

### Безопасные точки входа

`ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`
- Когда вызывать: когда initial chunk visuals должны быть готовы в boot sequence.
- Что делает: loads chunks with per-chunk readiness tracking and honest post-handoff continuation owned internally by `ChunkBootPipeline`. If the entrypoint is called in the same frame as `ChunkManager` creation, it first waits for deferred init instead of silently no-op returning; until the call actually begins, `ChunkManager` remains boot-gated so runtime player-chunk checks cannot race ahead of startup. Startup visual work is scheduled through the budgeted chunk visual scheduler and chunk-local `ChunkVisualState`; fresh chunks stay hidden until terminal `Chunk.is_full_redraw_ready()` publication closes. If detached/native critical compute is unavailable, boot/runtime now emit a zero-tolerance breach and fail closed instead of taking sync/compatibility fallback. Unfinished startup coords after internal `first_playable` remain boot-tracked and continue through runtime scheduling until real completion.
- Гарантии: canonical terrain authoritative после load; presentation строится через scheduler-owned redraw paths. Near slice full visual convergence (`Chunk.is_full_redraw_ready()`) is mandatory for `first_playable`; full startup bubble visual completion (`Chunk.is_full_redraw_ready()`) is still mandatory for `boot_complete`. `GameWorld` now uses full boot-ready handoff for player control/loading-screen dismissal; internal `first_playable` only starts post-ready finalization work. См. `Boot Readiness State` layer в `DATA_CONTRACTS.md`.
- Пример вызова: `await chunk_manager.boot_load_initial_chunks(_on_boot_progress)`

`ChunkManager.try_harvest_at_world(world_pos: Vector2) -> Dictionary`
- Когда вызывать: когда mining должен immediately обновить terrain/cover/cliff visuals и wall-form selection.
- Что делает: immediately patch-redraws локальный dirty set и same-chunk normalized neighbors для отзывчивости, затем переводит affected chunks в non-terminal convergence state и ставит explicit follow-up work через scheduler-owned `TASK_FULL_REDRAW` / `TASK_BORDER_FIX` для seam repair и terminal full-ready reconciliation; потом downstream reveal/shadow listeners обновляются через event.
- Гарантии: соблюдает `Postconditions: mine tile` и current `Wall Atlas Selection` contract. Immediate local redraw не считается сам по себе восстановлением terminal `FULL_READY`, если ещё остался owed seam/border convergence work.
- Пример вызова: `var result := chunk_manager.try_harvest_at_world(hit_world_pos)`

`MountainShadowSystem.prepare_boot_shadows(progress_callback: Callable) -> void`
- Когда вызывать: только если осознанно нужен blocking/progress-callback shadow bootstrap.
- Что делает: строит edge cache и shadow sprites для текущих loaded mountain chunks с прогресс-коллбеком.
- Гарантии: presentation-only; canonical terrain и topology не меняются. Runtime calls after `Boot.first_playable` are diagnostic warnings because this API intentionally blocks; normal runtime must use the budgeted `schedule_boot_shadows()` / `_tick_shadows()` path.
- Пример вызова: `_mountain_shadow_system.prepare_boot_shadows(_on_boot_progress)`

`MountainShadowSystem.build_boot_shadows() -> void`
- Когда вызывать: только если осознанно нужен synchronous boot shadow build без progress callback.
- Что делает: immediately builds edge cache и shadow sprites для current loaded surface chunks.
- Гарантии: presentation-only; same shadow contract as `prepare_boot_shadows()`. Runtime calls after `Boot.first_playable` are diagnostic warnings because this API intentionally blocks; normal runtime must use the budgeted `schedule_boot_shadows()` / `_tick_shadows()` path.
- Пример вызова: `_mountain_shadow_system.build_boot_shadows()`

`Chunk.complete_redraw_now(include_flora: bool = false) -> void`  `(owner-only safe entrypoint)`
- Когда вызывать: только из chunk lifecycle owner path для exceptional cases. **НЕ вызывается** в streaming runtime path и НЕ вызывается в boot path (streaming_redraw_budget_spec). Сохраняется для потенциальных будущих edge-cases.
- Что делает: полный terrain/cover/cliff redraw этого chunk; optional `include_flora=true` also finishes flora synchronously.
- Гарантии: presentation-only, loaded-only; не меняет canonical terrain и не является general external redraw API.

`Chunk.complete_terrain_phase_now() -> void`  `(owner-only safe entrypoint)`
- Когда вызывать: только как diagnostics/fallback helper в owner-side exceptional path. Нормальный boot path и normal streaming runtime path на него больше не опираются.
- Что делает: draws terrain layer for all tiles, advances progressive redraw to COVER phase. Cover/cliff/flora continue via `FrameBudgetDispatcher`.
- Гарантии: presentation-only, loaded-only. Only effective when chunk is in TERRAIN redraw phase. No-op if terrain phase already complete. Streaming/runtime boot visibility and readiness не должны зависеть от этого helper'а напрямую; они идут через scheduler + `Chunk.is_full_redraw_ready()` для initial publication. Допустимый hidden degraded state может существовать только пока chunk не показан игроку; player-visible publication нового чанка до full-ready (terrain/cover/cliff/flora) запрещена, и perf-метрики не могут это оправдать.
- Пример вызова: внутри owner path `chunk.complete_terrain_phase_now()`

`MountainShadowSystem.is_boot_shadow_work_drained() -> bool`
- Когда вызывать: в boot finalization после `schedule_boot_shadows()`.
- Что делает: возвращает, исчерпана ли реальная queued/active boot shadow work для surface context.
- Гарантии: `false` пока есть dirty queue, edge-cache build, active shadow build или пока boot shadow phase ещё не стартовала. Используется `GameWorld` как честный gate для full boot completion.

### Чтение

`Chunk.has_any_mountain() -> bool`
- Что возвращает: cached hint, содержит ли chunk mountain terrain.
- Когда использовать: для shadow/lifecycle gating на loaded chunk.
- Особенности: loaded-only derived hint; не заменяет terrain read.

`Chunk.get_terrain_bytes() -> PackedByteArray`
- Что возвращает: raw loaded terrain byte array.
- Когда использовать: только owner-systems вроде topology/shadow build, когда нужен быстрый loaded-only scan.
- Особенности: loaded-only raw access; не authoritative для unloaded reads и не write API.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `Chunk._redraw_all() -> void` | Full redraw implementation detail. Используется lifecycle owner path, не external API. |
| `Chunk._redraw_dirty_tiles(dirty_tiles: Dictionary) -> void` | Dirty redraw primitive without higher-level world/reveal orchestration. |
| `Chunk.build_visual_phase_batch(tile_budget: int) -> Dictionary` | Scheduler helper for serializable worker payload prep owned by the internal `ChunkVisualScheduler` / `ChunkManager` scheduler path; phase names come from the shared `ChunkVisualKernel.visual_phase_name()` contract, and pristine generated surface chunks may emit ready prebaked phase payload (`skip_worker_compute = true`), but this remains не caller-facing redraw API. |
| `Chunk.build_visual_dirty_batch(dirty_tiles: Dictionary, limit: int = -1) -> Dictionary` | Internal dirty-redraw payload builder for scheduler/border-fix work. |
| `Chunk.build_visual_dirty_batch_from_tiles(dirty_tiles: Array, limit: int = -1) -> Dictionary` | Internal dirty-redraw payload builder for scheduler/border-fix work when the dirty source already lives as an explicit tile list / queue instead of a `Dictionary<Vector2i, ...>` set. |
| `Chunk.compute_visual_batch(request: Dictionary) -> Dictionary` | Pure-data prepared-batch computation helper for worker paths; consumes the shared visual-kernel request contract (dense center arrays for terrain/surface meta plus sparse out-of-chunk `terrain_lookup`, or full `terrain_halo` in prebaked derivation), may derive commands from neighbor lookup tables or decode ready prebaked surface payload arrays into prepared commands / native-ready buffers, but never scene-tree writes. |
| `Chunk.apply_visual_phase_batch(batch: Dictionary) -> bool` | Owner-only prepared-batch apply helper; caller bypass risks redraw state drift. |
| `Chunk.apply_visual_dirty_batch(batch: Dictionary) -> bool` | Owner-only dirty prepared-batch apply helper; не external mutation entrypoint. |
| `Chunk._redraw_terrain_tile(local_tile: Vector2i) -> void` | Single-tile terrain draw helper. |
| `Chunk._redraw_cover_tile(local_tile: Vector2i) -> void` | Single-tile cover draw helper. |
| `Chunk._redraw_cliff_tile(local_tile: Vector2i) -> void` | Single-tile cliff overlay helper. |
| `Chunk._surface_rock_visual_class(local_tile: Vector2i) -> Vector2i` | Presentation-only wall-form selection helper; не terrain semantics. |
| `Chunk._rock_visual_class(local_tile: Vector2i) -> Vector2i` | Underground presentation-only wall-form helper; не topology/read API. |
| `MountainShadowSystem._mark_dirty(coord: Vector2i) -> void` | Internal invalidation queue helper. |
| `MountainShadowSystem._update_edges_at(tile_pos: Vector2i) -> Array[Vector2i]` | Low-level shadow edge cache patch helper. Returns only the actually affected shadow target coords after the edge delta is patched. |
| `MountainShadowSystem._start_shadow_build(coord: Vector2i) -> void` | Internal detached shadow-compute kickoff. Produces versioned pure-data job state only; renderer mutation stays in `_finalize_shadow_texture()` / `_finalize_shadow_apply()`. |
| `ChunkVisualScheduler.*` | Internal visual scheduler state owner. Not a gameplay or redraw API; external callers must not enqueue visual work or mutate scheduler queues directly. |
| `ChunkSurfacePayloadCache.*` | Internal generated terminal surface packet reuse cache. It validates `frontier_surface_final_packet` payloads with `ChunkFinalPacket.validate_terminal_surface_packet()` on write/read, is not terrain truth, is not persistence API, and is not safe for external reads/writes. |
| `ChunkSeamService.*` | Internal seam repair queue owner behind mining/streaming follow-up paths. External callers must not enqueue seam work directly; use `ChunkManager.try_harvest_at_world()` or lifecycle owner paths. |
| `ChunkTopologyService.*` | Internal topology runtime owner behind `ChunkManager` topology facades. External callers must not mutate dirty state, native builder handles, or chunk install/unload topology mirrors directly. |
| `ChunkBootPipeline.*` | Internal boot readiness, compute/apply queue, and runtime-handoff owner behind `ChunkManager.boot_load_initial_chunks()` and `_boot_*` facades. External callers must not mutate boot states, worker queues, or boot metrics directly. |

### Wall Atlas

- Surface wall-form selection идёт через `Chunk._surface_rock_visual_class(local_tile: Vector2i) -> Vector2i`.
- Эти helper methods in `chunk.gd` are thin facades over `core/systems/world/chunk_visual_kernel.gd`; direct redraw and prepared batch paths must not keep a second copy of the same wall/cover/cliff rules.
- Surface openness contract идёт через `Chunk._is_open_for_surface_rock_visual(terrain_type: int) -> bool`.
- В текущем коде surface visual-open = `GROUND`, `WATER`, `SAND`, `GRASS`, `MINED_FLOOR`, `MOUNTAIN_ENTRANCE`.
- Для pristine surface chunks generation-time `rock_visual_class`, `ground_face_atlas`, `variant_id`, `alt_id`, `cover_mask`, и `cliff_overlay` — это кэшированные outputs тех же `ChunkVisualKernel` presentation rules inside `build_chunk_native_data()` / `Chunk.populate_native()`. После terrain mutation этот cache invalidates and redraw returns to live neighbor reads through the same kernel contract.
- Underground wall-form selection идёт через `Chunk._rock_visual_class(local_tile: Vector2i) -> Vector2i`.
- Underground openness contract идёт через `Chunk._is_open_for_visual(terrain_type: int) -> bool`, то есть любой non-`ROCK` считается visual-open.
- Border fix / dirty redraw may narrow the explicit tile list, but still use the same visual-kernel request/command contract as full redraw and first-pass batch compute.
- Эти методы и контракты presentation-only. Их нельзя использовать как substitute для canonical terrain semantics, mining semantics или topology truth.

### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.chunk_loaded` | Chunk presentation и shadow systems могут построить visuals для нового loaded chunk | `(chunk_coord: Vector2i)` |
| `EventBus.chunk_unloaded` | Presentation cleanup path убирает chunk-local visuals / shadow sprite | `(chunk_coord: Vector2i)` |
| `EventBus.mountain_tile_mined` | Surface shadow/reveal listeners реагируют после mining orchestration | `(tile_pos: Vector2i, old_type: int, new_type: int)` |
| `EventBus.z_level_changed` | `MountainShadowSystem` скрывает/показывает surface shadow runtime по z-context | `(new_z: int, old_z: int)` |

---

## Z-Level Management

`classification`: orchestration over canonical active-z ownership plus downstream world/reveal/presentation switching.  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Layer: World`, `Layer: Reveal`, `Source Of Truth Vs Derived State`.

### Безопасные точки входа

`ZLevelManager.change_level(new_z: int) -> void`
- Когда вызывать: когда gameplay or scene orchestration должна перейти на другой z-level.
- Что делает: обновляет canonical `current_z`, эмитит z-change signals, а downstream world stack synchronizes through `GameWorld._on_z_level_changed()`.
- Гарантии: это primary owner-path для z traversal; `ChunkManager.set_active_z_level()` не должен использоваться как равноправный public API.
- Пример вызова: `z_manager.change_level(new_z)`

### Чтение

`ZLevelManager.get_current_z() -> int`
- Что возвращает: canonical current active z-level.
- Когда использовать: для общего gameplay / scene / API-level z reads.
- Особенности: authoritative read.

`ChunkManager.get_active_z_level() -> int`
- Что возвращает: downstream mirrored active z-level world stack.
- Когда использовать: только внутри world-stack reads/debug, когда нужен уже synchronized chunk-layer state.
- Особенности: mirror read; не global source of truth.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `GameWorld._on_z_level_changed(new_z: int, _old_z: int) -> void` | Scene glue. Координирует `ChunkManager`, daylight и `MountainShadowSystem`; не public API. |
| `ChunkManager.set_active_z_level(z: int) -> void` | Downstream world-stack sink. Должен вызываться только из `GameWorld._on_z_level_changed()` после canonical `ZLevelManager.change_level()`. |
| `MountainShadowSystem.set_active_z_level(new_z: int) -> void` | Secondary presentation sync helper. Safe only as part of higher-level z orchestration, не как primary z switch API. |
| `ChunkManager._generate_solid_rock_chunk() -> Dictionary` | Underground chunk generation helper, не z switch API. |
| `ChunkManager.ensure_underground_pocket(center_tile: Vector2i, pocket_tiles: Array) -> void` | Debug-only helper, не runtime z traversal API. |

### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.z_level_changed` | Project-level z manager сообщает о смене уровня; in-scope world systems это событие только потребляют | `(new_z: int, old_z: int)` |

---

## World Generator

`classification`: canonical source for unloaded surface base terrain only.  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Current Source Of Truth Summary`, `Source Of Truth Vs Derived State`.

### Безопасные точки входа

`WorldGenerator.initialize_world(seed_value: int) -> void`
- Когда вызывать: при старте новой сессии, если seed задан явно.
- Что делает: синхронно доводит generator graph до publish-ready state. Внутри может использовать detached worker compute для `WorldPrePass`, но сама функция не возвращается, пока read-only generator snapshot не опубликован, biome/variation resolvers и chunk content builder не готовы, и `world_initialized` не emitted.
- Гарантии: после этого generator-side surface reads/builds готовы; см. `Current Source Of Truth Summary`. `WorldFeatureRegistry` must already be boot-loaded before this call succeeds, so feature/POI definitions are not lazy-loaded during world generation. Invalid, duplicate, or unsupported feature definitions keep the registry not-ready, and this call fail-fast'ит instead of starting the world over a partial registry snapshot. Boot computes and publishes one deterministic pre-pass snapshot for the requested seed; runtime does not perform landmark validation, seed search, or threshold remediation during initialization. `EventBus.world_initialized` emits the requested/published seed value used for runtime state.
- Пример вызова: `WorldGenerator.initialize_world(world_seed)`

`WorldGenerator.initialize_random() -> void`
- Когда вызывать: при старте новой сессии без фиксированного seed.
- Что делает: выбирает random seed и делегирует в `initialize_world()`.
- Гарантии: те же generator initialization guarantees, что и у `initialize_world()`.
- Пример вызова: `WorldGenerator.initialize_random()`

`WorldGenerator.begin_initialize_world_async(seed_value: int) -> bool`
- Когда вызывать: когда owner-scene хочет начать compute `WorldPrePass` заранее под loading screen и завершить publish позже, не блокируя scene switch на всём pre-pass compute.
- Что делает: валидирует registry readiness, фиксирует runtime balance snapshot для запрошенного seed и запускает detached worker compute только для pure-data pre-pass. Не публикует partial runtime state и не emits `world_initialized`.
- Гарантии: safe staged-prewarm entrypoint. Пока pending init не завершён через `complete_pending_initialize_world()`, runtime readers должны считать `WorldGenerator` not initialized. Повторный вызов с тем же pending seed is idempotent.
- Пример вызова: `WorldGenerator.begin_initialize_world_async(seed_value)`

`WorldGenerator.is_initialize_world_pending() -> bool`
- Когда вызывать: когда owner-scene должен понять, есть ли незавершённый staged generator init.
- Что делает: возвращает, есть ли сейчас активный pending pre-pass compute/publish cycle.
- Гарантии: read-only lifecycle probe; не публикует state и не мутирует runtime snapshot.
- Пример вызова: `if WorldGenerator.is_initialize_world_pending():`

`WorldGenerator.complete_pending_initialize_world() -> bool`
- Когда вызывать: из owner-scene loading/boot loop, когда нужно попытаться завершить staged init и опубликовать generator snapshot, если worker compute уже готов.
- Что делает: если pending worker compute завершён, публикует один read-only runtime snapshot для requested seed, достраивает biome/variation/compute-context/builder graph на main thread и emits `EventBus.world_initialized`. Если compute ещё не завершён, returns `false` without partial publication.
- Гарантии: `true` means the requested generator snapshot is fully published and `_is_initialized` is now authoritative for runtime readers. Partial pre-pass truth is never exposed before this completion step.
- Пример вызова: `while WorldGenerator.is_initialize_world_pending() and not WorldGenerator.complete_pending_initialize_world(): await get_tree().process_frame`

`WorldGenerator.build_chunk_content(chunk_coord: Vector2i) -> ChunkBuildResult`
- Когда вызывать: когда нужен structured surface chunk payload в виде `ChunkBuildResult`.
- Что делает: canonicalizes chunk coord и строит full chunk content через `ChunkContentBuilder`, включая baseline `feature_and_poi_payload`.
- Гарантии: current surface generator semantics; не генерирует runtime-only `MINED_FLOOR` / `MOUNTAIN_ENTRANCE`. `feature_and_poi_payload` всегда присутствует в output shape и детерминирован для одного seed + canonical chunk coord. `variation` внутри `ChunkBuildResult` является presentation-only overlay metadata: кроме biome-local subzones туда могут попадать polar markers, но canonical terrain truth остаётся в `terrain`. Internal debug-only presentation may consume cached copies of this payload downstream, but presentation does not become authoritative for placement truth. Это structured/debug build shape, а не versioned player-reachable surface packet contract.
- Пример вызова: `var result: ChunkBuildResult = WorldGenerator.build_chunk_content(coord)`

`WorldGenerator.build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary`
- Когда вызывать: когда lifecycle/worker path нужен native payload dictionary для `Chunk.populate_native()`.
- Что делает: canonicalizes chunk coord, передаёт compact native generation request в `ChunkGenerator.generate_chunk(...)`, где C++ сам сэмплит channels/prepass/structure из immutable `WorldPrePass` snapshot и native noise/biome/flora/decor params, затем `ChunkContentBuilder` достраивает versioned terminal surface packet envelope `frontier_surface_final_packet` для lifecycle/install boundaries. Packet carries header/provenance fields `packet_kind`, `packet_version`, `generator_version`, `z_level`, `generation_source`, authoritative tile arrays `terrain` / `height` / `variation` / `biome` / `secondary_biome` / `ecotone_values` / `flora_density_values` / `flora_modulation_values`, deterministic placement payload `flora_placements`, terminal `flora_payload` when placements are non-empty, real `feature_and_poi_payload`, and presentation-only derived arrays `rock_visual_class`, `ground_face_atlas`, `cover_mask`, `cliff_overlay`, `variant_id`, и `alt_id`.
- Гарантии: player-reachable surface runtime consumes this versioned packet contract, not `ChunkBuildResult.to_native_data()`. `variation` в payload остаётся presentation-only overlay metadata, включая polar markers; canonical terrain semantics по-прежнему живут в `terrain`. Surface derived arrays are computed by native `ChunkVisualKernels.build_prebaked_visual_payload()` against a one-tile seam halo and are meant only for terrain/cover/cliff visual fast-path reuse inside `Chunk.populate_native()` / `Chunk.build_visual_phase_batch()` / `Chunk.compute_visual_batch()`; they do not become public terrain truth and may be invalidated after saved or runtime terrain mutations. When `use_native_chunk_generation` enabled, C++ `ChunkGenerator.generate_chunk()` must read only the immutable `WorldPrePass` snapshot exported during initialization plus the compact request metadata from `ChunkContentBuilder`; runtime GDScript must not build or bridge per-tile authoritative channel arrays. `generation_source` is attached for proof/debug provenance on surface runtime payloads (`native_chunk_generator` in the supported player path). `ChunkManager._complete_surface_final_packet_publication_payload()` completes the packet with serialized pure-data flora render payload from native placements, and `ChunkFinalPacket.validate_terminal_surface_packet()` requires that payload to match canonical chunk coord/chunk size, placement count, and prebuilt render packet. `ChunkStreamingService.prepare_chunk_install_entry()` and `ChunkSurfacePayloadCache` now validate the terminal packet before chunk creation/cache replay and fail closed on missing metadata, broken field alignment, missing terminal flora payload, or missing native visual packet payload. If the native DLL is unavailable or payload validation fails, surface player-reachable generation now fails closed instead of falling back to GDScript. Any debug presentation proof must stay downstream of this built payload instead of recomputing feature / POI decisions.
- Пример вызова: `var native_data: Dictionary = WorldGenerator.build_chunk_native_data(coord)`

`WorldGenerator.get_native_chunk_generator() -> RefCounted`
- Что возвращает: C++ `ChunkGenerator` instance или `null` если native generation отключена / DLL недоступна.
- Когда использовать: `ChunkContentBuilder.initialize()` получает native generator для use в `build_chunk_native_data()`.
- Особенности: controlled by `balance.use_native_chunk_generation` flag. `ChunkGenerator.initialize()` called once during `_setup_compute_context()`. Receives full balance params, causal biome balance knobs (`biome_continental_drying_factor`, `biome_drainage_moisture_bonus`), biome definitions, flora/decor set definitions including `texture_path`, and an immutable serialized `WorldPrePass` snapshot. Native structure truth is required to come only from that snapshot; initialization fails closed if the snapshot is missing or malformed. Runtime `generate_chunk()` requires compact request kind `native_chunk_generation_request_v1` and samples per-tile channels/prepass/structure inside C++ instead of accepting the normal runtime path's old GDScript-built 15-array bridge payload. Native `generate_chunk()` also returns serialized `flora_placements` with enough texture path data for terminal `flora_payload` construction; player-reachable runtime must not reintroduce a GDScript flora fallback when that key is missing.

`WorldGenerator.build_tile_data(tile_pos: Vector2i) -> TileGenData`
- Когда вызывать: когда нужен full generated surface tile description, а не только terrain type.
- Что делает: canonicalizes tile и строит `TileGenData` через `SurfaceTerrainResolver`.
- Гарантии: generator-side surface base terrain semantics only.
- Пример вызова: `var tile_data: TileGenData = WorldGenerator.build_tile_data(tile_pos)`

`WorldComputeContext.sample_prepass_channels(world_pos: Vector2i) -> WorldPrePassChannels`
- Когда вызывать: когда runtime/tooling consumer уже держит `WorldComputeContext` и ему нужен safe typed sample причинных pre-pass каналов без прямой работы со строковыми channel id.
- Что делает: canonicalizes tile и возвращает lightweight container с normalized `drainage`, `slope`, `rain_shadow`, и `continentalness`.
- Гарантии: safe facade над опубликованным `WorldPrePass`; при отсутствии pre-pass reference возвращает нулевой container вместо crash.

`WorldComputeContext.sample_structure_context(world_pos: Vector2i, channels: WorldChannels = null) -> WorldStructureContext`
- Когда вызывать: когда runtime/tooling consumer уже держит `WorldComputeContext` и ему нужен тот же structural context, который читает текущий GDScript world runtime.
- Что делает: canonicalizes tile и собирает `WorldStructureContext` из опубликованного `WorldPrePass`: `ridge_strength`, `mountain_mass`, `floodplain_strength`, `river_distance`, `river_width`; `mountain_mass` is the broader massif-fill companion to `ridge_strength` around local ridge neighborhoods, while `river_strength` derives as a continuous width-and-proximity semantic from the published `river_width` / `river_distance` pair, including qualifying lake basins that are folded into the same hydrology handoff, clamps to `0` when sampled `river_width` is absent, and is the same sanctioned river handoff used by both GDScript and native terrain consumers instead of legacy band/noise sampling. Legacy `channels` parameter retained only for consumer compatibility.
- Гарантии: sanctioned structure-truth sampler for GDScript runtime. Не вызывает legacy band/noise structure sampling; при отсутствии pre-pass reference возвращает нулевой context вместо альтернативной "второй правды".

`WorldPrePass.sample(channel: StringName, world_pos: Vector2i) -> float`
- Когда вызывать: когда owner-side generator consumer уже держит опубликованный `WorldPrePass` reference и нужен интерполированный coarse-grid канал по мировым координатам.
- Что делает: читает curated pre-pass channel (`height`, `drainage`, `river_width`, `river_distance`, `floodplain_strength`, `ridge_strength`, `mountain_mass`, `slope`, `rain_shadow`, `continentalness`) seam-safe по X-wrap и clamp-safe по latitude band. Published `river_width` / `river_distance` remain the sanctioned visible hydrology handoff for both river corridors and qualifying lake basins; raw `lake_mask` / `lake_records` stay internal.
- Гарантии: read-only API над опубликованным pre-pass snapshot; не публикует raw mutable grid access и не триггерит recompute.

`WorldPrePass.get_grid_value(channel: StringName, grid_x: int, grid_y: int) -> float`
- Когда вызывать: для debug/tooling/boot diagnostics, когда нужен прямой coarse-grid read без интерполяции.
- Что делает: возвращает значение публичного канала по coarse-grid index.
- Гарантии: read-only grid probe; out-of-range reads return `0.0` instead of mutating state.

### Чтение

`WorldGenerator.get_terrain_type_fast(tile_pos: Vector2i) -> TileGenData.TerrainType`
- Что возвращает: generated surface terrain type for canonical tile.
- Когда использовать: только для unloaded surface fallback или generator-side queries.
- Особенности: не authoritative для loaded chunks и не используется для unloaded underground, где authoritative fallback = `ROCK`.

`WorldGenerator.get_tile_data(tile_x: int, tile_y: int) -> TileGenData`
- Что возвращает: full generated tile data for surface.
- Когда использовать: generator-side inspection or tooling.
- Особенности: same source-of-truth boundary as `build_tile_data`; не runtime loaded-world read.

`WorldGenerator.get_chunk_biome(chunk_coord: Vector2i) -> BiomeData`
- Что возвращает: dominant biome for chunk.
- Когда использовать: chunk presentation/lifecycle setup on surface.
- Особенности: generator-side derived read; не terrain mutation API.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `WorldGenerator.get_chunk_data(chunk_coord: Vector2i) -> Dictionary` | Historical alias removed from `WorldGenerator` public surface; use `build_chunk_native_data()` explicitly. |
| `WorldGenerator.get_chunk_data_native(chunk_coord: Vector2i) -> Dictionary` | Legacy path, не использовать. Removed from `WorldGenerator` public surface; historical references should migrate to `build_chunk_native_data()`. |
| `WorldGenerator.create_detached_chunk_content_builder() -> ChunkContentBuilder` | Worker/staged loading owner helper, не generic gameplay API. |
| `ChunkContentBuilder.build_chunk(chunk_coord: Vector2i) -> ChunkBuildResult` | Generator plumbing behind `WorldGenerator`; direct callers обходят canonical generator facade. |
| `ChunkContentBuilder.build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary` | Generator plumbing behind `WorldGenerator`; same reason as above. |
| `SurfaceTerrainResolver.populate_chunk_build_data(canonical_tile: Vector2i, spawn_tile: Vector2i, data: TileGenData) -> void` | Low-level generation primitive, не caller-facing API. |
| `ChunkBuildResult.set_tile(index: int, terrain_type: int, height_value: float, variation_id: int = 0, biome_id: int = 0, p_flora_density: float = 0.5, p_flora_mod: float = 0.0) -> void` | Internal builder assembly step, не runtime world API. |

### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.world_initialized` | После `WorldGenerator.initialize_world()` или `WorldGenerator.complete_pending_initialize_world()` завершает setup и публикует generator snapshot для запрошенного seed | `(seed_value: int)` where `seed_value` is the requested/published runtime seed |

---

## Player & Survival APIs

### Player actor / movement / combat / harvest

`classification`: `canonical`

#### Безопасные точки входа

`Player.perform_attack() -> bool`
- Когда вызывать: когда нужно выполнить одну player attack action.
- Что делает: валидирует cooldown/attack area, наносит урон врагам через `HealthComponent.take_damage()`.
- Гарантии: respect current player death/cooldown gates.
- Пример: `var ok: bool = player.perform_attack()`

`Player.perform_harvest() -> bool`
- Когда вызывать: когда нужно попытаться добыть ресурс или refuel nearby burner из player action.
- Что делает: сначала пытается refuel `ThermoBurner`, затем идёт в `HarvestTileCommand -> ChunkManager.try_harvest_at_world()`, а успех кладёт в inventory.
- Гарантии: runtime mining идёт через canonical mining API.
- Пример: `var ok: bool = player.perform_harvest()`

`Player.collect_item(item_id: String, amount: int) -> int`
- Когда вызывать: когда authoritative item drop уже определён и его нужно положить игроку.
- Что делает: кладёт stack в `InventoryComponent` и эмитит `EventBus.item_collected` по реально добавленному количеству.
- Гарантии: не пишет inventory вручную.
- Пример: `var collected: int = player.collect_item("base:scrap", 3)`

`Player.spend_scrap(amount: int) -> bool` / `Player.spend_item(item_id: String, amount: int) -> bool`
- Когда вызывать: когда расход должен пройти через player-owned inventory boundary.
- Что делает: списывает stack через `InventoryComponent.remove_item()`.
- Гарантии: сохраняет inventory-layer contract.
- Пример: `if player.spend_scrap(5): ...`

#### Чтение

`Player.can_attack() -> bool`
- Read-only readiness probe for combat action.

`Player.can_harvest() -> bool`
- Read-only readiness probe for harvest action.

`Player.is_dead() -> bool`
- Read-only death-state probe.

`Player.get_inventory() -> InventoryComponent`
- Возвращает authoritative inventory component игрока.

`Player.get_oxygen_system() -> OxygenSystem`
- Возвращает player-owned oxygen component.

`Player.get_scrap_count() -> int`
- Возвращает текущее количество scrap через inventory scan.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `Player._find_harvest_target_position() -> Vector2` | Internal targeting helper; не action API и не гарантирует full harvest semantics сам по себе. |
| `Player._apply_terrain_blocking(delta: float) -> void` | Internal movement correction path; caller не должен вручную разруливать player/world collision contract. |
| `Player.update_movement_velocity() -> void` | State-machine internal movement primitive. |
| Direct writes to `Player._attack_timer`, `Player._harvest_timer`, `Player._is_dead` | Обходят action gates и death contract. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.item_collected` | После успешного добавления предметов игроку | `(item_id: String, amount: int)` |
| `EventBus.scrap_collected` | Когда player recomputes current scrap count | `(total_amount: int)` |
| `EventBus.player_died` | После player death handling | `()` |
| `EventBus.game_over` | После player death handling | `()` |

### Health / damage

`classification`: `canonical`

#### Безопасные точки входа

`HealthComponent.take_damage(amount: float) -> bool`
- Когда вызывать: когда сущность должна получить урон.
- Что делает: уменьшает `current_health`, эмитит `health_changed`, а при нуле эмитит `died`.
- Гарантии: централизованный damage/death contract.
- Пример: `var died: bool = health.take_damage(12.0)`

`HealthComponent.heal(amount: float) -> void`
- Когда вызывать: когда сущность должна восстановить здоровье.
- Что делает: увеличивает `current_health` до `max_health`, эмитит `health_changed`.
- Гарантии: respect current max clamp.
- Пример: `health.heal(5.0)`

`HealthComponent.restore_state(new_current_health: float, new_max_health: float) -> void`
- Когда вызывать: только на setup/save/load boundary, когда нужно authoritative restore текущего hp-состояния.
- Что делает: atomically обновляет `current_health` и `max_health`, затем эмитит `health_changed`.
- Гарантии: единый owner-side restore path для live state.
- Пример: `health.restore_state(32.0, 50.0)`

#### Чтение

`HealthComponent.get_health_percent() -> float`
- Возвращает нормализованное здоровье `0.0..1.0`.

`HealthComponent.current_health`
- Допустимо читать на host/save/UI boundaries. Не write-safe.

`HealthComponent.max_health`
- Допустимо читать на host/save/UI boundaries. Не write-safe.

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| Direct writes to `HealthComponent.current_health` / `max_health` | Обходят `health_changed` / `died` signals и ломают единый damage contract. |
| Host-specific direct setup paths in `BasicEnemy._ready()` / `ThermoBurner.setup()` / `ArkBattery.setup()` | Это lifecycle/setup boundaries, а не generic gameplay API. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `HealthComponent.health_changed` | После `take_damage()` или `heal()` | `(new_health: float, max_health: float)` |
| `HealthComponent.died` | Когда здоровье падает до нуля | `()` |

### Inventory runtime

`classification`: `canonical`

#### Безопасные точки входа

`InventoryComponent.add_item(item_data: ItemData, amount: int) -> int`
- Когда вызывать: когда нужно положить stack в inventory.
- Что делает: заполняет существующие стаки, потом пустые слоты; возвращает leftover.
- Гарантии: current stack rules и `EventBus.inventory_updated`.
- Пример: `var leftover: int = inventory.add_item(item_data, 4)`

`InventoryComponent.remove_item(item_data: ItemData, amount: int) -> bool`
- Когда вызывать: когда нужно снять stack из inventory.
- Что делает: проверяет наличие и списывает amount по слотам.
- Гарантии: failure не мутирует inventory.
- Пример: `if inventory.remove_item(item_data, 2): ...`

`InventoryComponent.move_slot_contents(from_index: int, to_index: int) -> bool`
- Когда вызывать: когда authoritative runtime должен swap/merge contents between two slots.
- Что делает: либо merge-ит одинаковые стаки, либо меняет содержимое слотов местами.
- Гарантии: emits `EventBus.inventory_updated`; UI не должен делать это вручную.

`InventoryComponent.split_stack(slot_index: int) -> bool`
- Когда вызывать: когда нужно split-нуть stack пополам в пустой слот.
- Что делает: делит stack и переносит половину в первый свободный слот.
- Гарантии: respects capacity and empty-slot availability.

`InventoryComponent.sort_slots_by_name() -> bool`
- Когда вызывать: когда нужен owner-side inventory sort.
- Что делает: сортирует непустые слоты по `ItemData.get_display_name()`.
- Гарантии: emits `EventBus.inventory_updated`.

`InventoryComponent.remove_amount_from_slot(slot_index: int, amount: int) -> Dictionary`
- Когда вызывать: когда owner/orchestration path снимает часть stack из конкретного слота.
- Что делает: уменьшает amount в слоте и возвращает `{ item, item_id, amount }`.
- Гарантии: authoritative per-slot removal API.

`InventoryComponent.remove_slot_contents(slot_index: int) -> Dictionary`
- Когда вызывать: когда нужно полностью вынуть stack из конкретного слота, например перед world-drop.
- Что делает: снимает весь stack и возвращает `{ item, item_id, amount }`.
- Гарантии: authoritative drop/export path.

`InventoryComponent.save_state() -> Dictionary` / `InventoryComponent.load_state(data: Dictionary) -> void`
- Когда вызывать: только на save/load boundary.
- Что делает: сериализует и восстанавливает capacity + slots.
- Гарантии: current save schema inventory-layer.

#### Чтение

`InventoryComponent.get_item_count(item_id: String) -> int`
- Read-only count query by item id.

`InventoryComponent.has_item(item_data: ItemData, amount: int) -> bool`
- Read-only availability probe for crafting/spend checks.

`InventoryComponent.slots`
- Допустимо читать для UI/save/debug. Не мутировать напрямую.

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| `InventoryComponent._initialize_slots() -> void` | Internal allocation helper, не gameplay API. |
| Direct mutation of `InventoryComponent.slots` or `InventorySlot.item` / `amount` | Обходит owner-layer и `inventory_updated`; вместо этого используй owner APIs `move_slot_contents()` / `split_stack()` / `sort_slots_by_name()` / `remove_*`. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.inventory_updated` | После inventory mutation или `load_state()` | `(inventory_node: Node)` |

### Equipment runtime

`classification`: `canonical`

#### Безопасные точки входа

`EquipmentComponent.equip(slot: int, item: ItemData) -> ItemData`
- Когда вызывать: когда item already authoritative и нужно положить его в equipment slot.
- Что делает: ставит item в slot и возвращает ранее экипированный item.
- Гарантии: emits `equipment_changed`.

`EquipmentComponent.unequip(slot: int) -> ItemData`
- Когда вызывать: когда нужно снять item из slot.
- Что делает: очищает slot и возвращает снятый item.
- Гарантии: emits `equipment_changed`.

`EquipmentComponent.equip_from_inventory_slot(inventory: InventoryComponent, slot_index: int) -> bool`
- Когда вызывать: когда runtime flow переносит предмет из inventory в equipment через owner path.
- Что делает: снимает один предмет из inventory slot, экипирует его и возвращает прежний предмет обратно в inventory.
- Гарантии: authoritative inventory/equipment handoff без UI-side direct mutation.

`EquipmentComponent.unequip_to_inventory(slot: int, inventory: InventoryComponent) -> bool`
- Когда вызывать: когда нужно снять предмет из equipment обратно в inventory.
- Что делает: сначала резервирует место в inventory, затем снимает item со слота.
- Гарантии: failure не теряет item.

#### Чтение

`EquipmentComponent.get_equipped(slot: int) -> ItemData`
- Read-only slot query.

`EquipmentComponent.can_equip(slot: int, item: ItemData) -> bool`
- Read-only compatibility check.

`EquipmentComponent.get_all_equipped() -> Dictionary`
- Snapshot of current equipment map.

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| Direct mutation of `EquipmentComponent._equipped` | Обходит `equipment_changed` и ломает slot contract. |
| `EquipmentComponent.load_state(data: Dictionary) -> void` | Component-level save/load boundary only; current `SaveManager` flow вызывает его через `SaveAppliers.apply_player()`, но это не generic runtime equip API. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EquipmentComponent.equipment_changed` | После `equip()` / `unequip()` / `load_state()` | `(slot: int, item: ItemData)` |

### Oxygen / survival

`classification`: `canonical`

#### Безопасные точки входа

`OxygenSystem.get_oxygen_percent() -> float`
- Когда вызывать: для read-only survival/UI checks.
- Что делает: возвращает `_current_oxygen / max_oxygen`.
- Гарантии: current normalized oxygen read.

`OxygenSystem.set_indoor(indoor: bool) -> void`
- Когда вызывать: только из authoritative indoor owner path.
- Что делает: переключает indoor flag и эмитит `player_entered_indoor` / `player_exited_indoor`.
- Гарантии: не меняет oxygen amount напрямую.

`OxygenSystem.set_base_powered(powered: bool) -> void`
- Когда вызывать: только из authoritative life-support power owner path.
- Что делает: обновляет power context для следующего survival tick.
- Гарантии: не переопределяет indoor state.

`OxygenSystem.save_state() -> Dictionary` / `OxygenSystem.load_state(data: Dictionary) -> void`
- Когда вызывать: только на save/load boundary.
- Что делает: сериализует и восстанавливает oxygen amount + context flags.

#### Чтение

`Player.get_oxygen_system() -> OxygenSystem`
- Preferred read access from player host.

`OxygenSystem.get_oxygen_percent() -> float`
- Preferred normalized read.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `OxygenSystem._update_oxygen(delta: float) -> void` | Frame-owned survival tick; caller не должен сам вести drain/refill timeline. |
| `OxygenSystem._apply_effects() -> void` | Internal signal/effect propagation step. |
| Direct writes to `_current_oxygen`, `_is_indoor`, `_is_base_powered` | Обходят survival owner contract. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.oxygen_changed` | После изменения количества O₂ | `(current: float, maximum: float)` |
| `EventBus.oxygen_depleting` | При входе в low-O₂ zone | `(remaining_percent: float)` |
| `EventBus.player_entered_indoor` | После `set_indoor(true)` | `()` |
| `EventBus.player_exited_indoor` | После `set_indoor(false)` | `()` |
| `OxygenSystem.speed_modifier_changed` | После расчёта oxygen effects | `(modifier: float)` |

### Base life support

`classification`: `canonical`

#### Безопасные точки входа

`BaseLifeSupport.is_powered() -> bool`
- Когда вызывать: когда нужен canonical read of current life-support power state.
- Что делает: возвращает powered-state внутреннего `PowerConsumerComponent`.
- Гарантии: read-only projection of the owner layer.

`BaseLifeSupport.set_power_demand(new_demand: float) -> void`
- Когда вызывать: когда owner life-support node меняет свой demand.
- Что делает: обновляет owner demand и делегирует его во внутренний consumer через sanctioned setter path.
- Гарантии: не требует прямого доступа к child `PowerConsumerComponent`.

#### Чтение

`BaseLifeSupport.is_powered() -> bool`
- Preferred read API for gameplay/UI checks.

`BaseLifeSupport.get_power_demand() -> float`
- Read-only owner demand probe.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `BaseLifeSupport._on_powered_changed(powered: bool) -> void` | Internal bridge from power component to event bus. |
| `BaseLifeSupport._emit_state() -> void` | Internal initial-state broadcast. |
| Direct access to child `PowerConsumer` | Внешний caller обходит BaseLifeSupport ownership. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.life_support_power_changed` | После смены powered-state | `(is_powered: bool)` |

---

## Building / Power APIs

### Building placement / building runtime

`classification`: `canonical`

#### Безопасные точки входа

`BuildingSystem.set_selected_building(building: BuildingData) -> void`
- Когда вызывать: когда UI или gameplay orchestration выбирает тип постройки.
- Что делает: обновляет текущий selected building у owner-system.
- Гарантии: дальнейшие placement calls используют именно этот building.

`BuildingSystem.place_selected_building_at(world_pos: Vector2) -> Dictionary`
- Когда вызывать: когда нужно поставить выбранную постройку.
- Что делает: валидирует наличие выбранной постройки, scrap budget, active-z, occupancy, walkability и запрет `ROCK` / `WATER`, тратит scrap, создаёт building node, помечает room topology dirty и эмитит `building_placed`.
- Гарантии: authoritative placement path для текущего surface-only building runtime.
- Пример: `var result: Dictionary = building_system.place_selected_building_at(mouse_pos)`

`BuildingSystem.can_place_selected_building_at(world_pos: Vector2) -> bool`
- Когда вызывать: когда нужен authoritative pre-check placement без фактической мутации.
- Что делает: проверяет current selected building, active-z, occupancy, walkability и запрет `ROCK` / `WATER`.
- Гарантии: использует тот же validation contract, что и реальный placement path.

`BuildingSystem.remove_building_at(world_pos: Vector2) -> Dictionary`
- Когда вызывать: когда нужно снести постройку.
- Что делает: удаляет building node, возвращает refund, помечает room topology dirty и эмитит `building_removed`.
- Гарантии: authoritative remove path для building runtime.

`BuildingSystem.save_state() -> Dictionary` / `BuildingSystem.load_state(data: Dictionary) -> void`
- Когда вызывать: только на save/load boundary.
- Что делает: сериализует и восстанавливает placed buildings через persistence helper.

#### Чтение

`BuildingSystem.world_to_grid(world_pos: Vector2) -> Vector2i`
- Canonical world->grid conversion for building-space logic.

`BuildingSystem.grid_to_world(grid_pos: Vector2i) -> Vector2`
- Canonical grid->world conversion for building-space logic.

`BuildingSystem.is_cell_indoor(grid_pos: Vector2i) -> bool`
- Read-only indoor query through current room topology.

`BuildingSystem.get_grid_size() -> int`
- Read-only building grid size.

`BuildingSystem.has_building_at(grid_pos: Vector2i) -> bool`
- Read-only occupancy probe through owner layer.

`BuildingSystem.get_building_node_at(grid_pos: Vector2i) -> Node2D`
- Owner-approved node lookup for save/load/debug glue that already owns the building runtime boundary.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `BuildingSystem._toggle_build_mode() -> void` | Input/UI internal mode toggle, не placement API. |
| `BuildingSystem._on_building_destroyed(grid_pos: Vector2i) -> void` | Destruction callback path tied to health binding. |
| `BuildingPlacementService.place_selected_at(mouse_world: Vector2) -> Vector2i` | Low-level creation helper; safe placement orchestration живёт в `BuildingSystem.place_selected_building_at()`. |
| Direct mutation of `BuildingSystem._walls` or `BuildingPlacementService.walls` | Ломает canonical occupancy map и room invalidation chain. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.build_mode_changed` | После переключения build mode | `(is_active: bool)` |
| `EventBus.building_placed` | После успешного placement | `(position: Vector2i)` |
| `EventBus.building_removed` | После remove/destroy | `(position: Vector2i)` |

### Indoor room topology

`classification`: `derived`

#### Безопасные точки входа

`BuildingSystem.is_cell_indoor(grid_pos: Vector2i) -> bool`
- Когда вызывать: когда нужен current indoor/outdoor answer для grid cell.
- Что делает: читает derived `indoor_cells`.
- Гарантии: read-only query through the owner.

`BuildingSystem.has_pending_room_recompute() -> bool`
- Когда вызывать: если code path должен дождаться room topology stabilization.
- Что делает: сообщает, есть ли dirty-room recompute в процессе.
- Гарантии: owner-side readiness probe.

#### Чтение

`BuildingSystem.indoor_cells`
- Допустимо читать для owner-adjacent debug/UI. Не мутировать напрямую.

`BuildingSystem.has_pending_room_recompute() -> bool`
- Read-only pending-state probe.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `BuildingSystem._room_recompute_tick() -> bool` | Budgeted owner tick for derived room state. |
| `BuildingSystem._begin_full_room_rebuild() -> void` | Owner-only staged rebuild entry. |
| `IndoorSolver.recalculate(walls: Dictionary) -> Dictionary` | Solver implementation detail behind `BuildingSystem`. |
| `IndoorSolver.solve_local_patch(...) -> Dictionary` | Low-level patch solver, не caller-facing API. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.rooms_recalculated` | После применения patch/full rebuild | `(indoor_cells: Dictionary)` |

### Power network

`classification`: `canonical`

#### Безопасные точки входа

`PowerSystem.force_recalculate() -> void`
- Когда вызывать: только на boot/load boundary, когда registry уже собран, а баланс нужно пересчитать сразу.
- Что делает: synchronously recomputes supply/demand and powered-state.
- Гарантии: authoritative owner-side recompute.

`PowerSystem.get_balance() -> float`
- Когда вызывать: когда нужен current surplus/deficit read.
- Что делает: возвращает `total_supply - total_demand`.

`PowerSystem.get_supply_ratio() -> float`
- Когда вызывать: для HUD / gameplay read of current power coverage.
- Что делает: возвращает `total_supply / total_demand` либо `1.0`, если demand нет.

`PowerSourceComponent.set_enabled(enabled: bool) -> void`
- Когда вызывать: когда structure-owner включает или выключает источник.
- Что делает: пересчитывает `current_output` и эмитит `output_changed`.
- Гарантии: invalidates owner power system через signal path.

`PowerSourceComponent.set_condition(multiplier: float) -> void`
- Когда вызывать: когда внешний фактор меняет производительность источника.
- Что делает: clamp-ит multiplier, пересчитывает output и эмитит `output_changed`.

`PowerSourceComponent.set_max_output(output: float) -> void`
- Когда вызывать: когда owner источника меняет его nominal output.
- Что делает: обновляет `max_output`, пересчитывает `current_output` и эмитит `output_changed`.
- Гарантии: sanctioned config path for source capacity.

`PowerSourceComponent.force_shutdown() -> void`
- Когда вызывать: аварийное отключение источника.
- Что делает: мгновенно обнуляет output и эмитит `output_changed(0.0)`.

`PowerConsumerComponent.set_demand(new_demand: float) -> void` / `PowerConsumerComponent.set_priority(new_priority: Priority) -> void`
- Когда вызывать: когда owner потребителя меняет power config.
- Что делает: обновляет config и эмитит `configuration_changed`.
- Ограничение: safe только для owner-managed consumer-ов; не применять к внутреннему child consumer у `BaseLifeSupport`.

#### Чтение

`PowerSystem.total_supply`, `PowerSystem.total_demand`, `PowerSystem.is_deficit`
- Read-only aggregate state for HUD/debug/owner systems. Не write-safe.

`PowerSystem.get_debug_snapshot() -> Dictionary`
- Aggregate debug/export snapshot of current `supply/demand/deficit`. Не persistence API.

`PowerSystem.get_registered_source_count() -> int` / `get_registered_consumer_count() -> int`
- Read-only registry size probes.

`PowerConsumerComponent.is_powered`
- Current powered-state projection for consumer owner/UI. Не write-safe.

`PowerSourceComponent.current_output`
- Current output projection for source owner/UI. Не write-safe.

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| `PowerSystem._power_recompute_tick() -> bool` | Budgeted owner tick, не public recompute API. |
| `PowerSystem._apply_brownout(consumers: Array[PowerConsumerComponent]) -> void` | Internal brownout policy implementation. |
| `PowerSystem._power_all(consumers: Array[PowerConsumerComponent]) -> void` | Internal no-deficit apply step. |
| Direct writes to `PowerSourceComponent.is_enabled`, `condition_multiplier`, `PowerConsumerComponent.demand`, `priority` | Обходят setter-ы и invalidation signals. |
| Direct config writes on `BaseLifeSupport` child `PowerConsumer` | Обходят локальный ownership `BaseLifeSupport` и конфликтуют с life-support contract. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.power_changed` | После recompute power balance | `(total_supply: float, total_demand: float)` |
| `EventBus.power_deficit` | При входе в дефицит | `(deficit_amount: float)` |
| `EventBus.power_restored` | При выходе из дефицита | `()` |
| `PowerSourceComponent.output_changed` | После source output change | `(new_output: float)` |
| `PowerConsumerComponent.configuration_changed` | После demand/priority change | `()` |
| `PowerConsumerComponent.powered_changed` | После смены powered-state | `(is_powered: bool)` |

## World Entities APIs

### Spawn / pickup orchestration

`classification`: `canonical`

#### Безопасные точки входа

`SpawnOrchestrator.spawn_initial_scrap() -> void`
- Когда вызывать: только на new-session bootstrap.
- Что делает: раскладывает стартовые scrap pickups вокруг игрока.
- Гарантии: canonical bootstrap path для initial pickups.

`SpawnOrchestrator.save_pickups() -> Array[Dictionary]`
- Когда вызывать: на save boundary.
- Что делает: сериализует текущие pickups в canonical save shape.

`SpawnOrchestrator.load_pickups(entries: Array) -> void`
- Когда вызывать: на load boundary.
- Что делает: очищает текущие pickups и восстанавливает их из save shape.

`SpawnOrchestrator.save_enemy_runtime() -> Dictionary` / `SpawnOrchestrator.load_enemy_runtime(data: Dictionary) -> void`
- Когда вызывать: на world save/load boundary.
- Что делает: сериализует и восстанавливает enemy population, spawn timer и enable flag.
- Гарантии: hostile runtime now participates in canonical world save/load.

`SpawnOrchestrator.clear_pickups() -> void`
- Когда вызывать: owner-side reset before load/reset.
- Что делает: удаляет все текущие pickup nodes.

`SpawnOrchestrator.clear_enemies() -> void`
- Когда вызывать: owner-side reset before world load/reset.
- Что делает: удаляет текущие enemy nodes и синхронизирует internal enemy count.

`SpawnOrchestrator.set_enemy_spawning_enabled(enabled: bool) -> void`
- Когда вызывать: только из owner/session orchestration path.
- Что делает: включает или выключает timer-driven enemy spawning.
- Гарантии: sanctioned writer for `_enemy_spawning_enabled`.

`SpawnOrchestrator.sync_pickups_to_player() -> void`
- Когда вызывать: после wrap/canonicalization, если pickup display positions нужно пересчитать.
- Что делает: синхронизирует visual position pickups относительно player reference position.

#### Чтение

`SpawnOrchestrator.save_pickups() -> Array[Dictionary]`
- Current read/export API for pickup state.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `SpawnOrchestrator._spawn_enemy() -> void` | Internal timer-driven spawn primitive. |
| `SpawnOrchestrator._update_enemy_spawning(delta: float) -> void` | Internal per-frame orchestration tick. |
| `SpawnOrchestrator._on_pickup_collected(body: Node2D, pickup: Area2D) -> void` | Internal pickup/command bridge. |
| Direct writes to pickup metadata `item_id`, `amount`, `logical_position` | Ломают save/load and wrap sync contracts. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.enemy_spawned` | После успешного enemy spawn | `(enemy_node: Node2D)` |
| `EventBus.enemy_killed` | Потребляется оркестратором для drop/count logic | `(position: Vector2)` |
| `EventBus.item_dropped` | Потребляется оркестратором для world pickup spawn | `(item_id: String, amount: int, world_pos: Vector2)` |

### Enemy AI / fauna runtime

`classification`: `canonical`

#### Безопасные точки входа

Прямой generic behavior-driving API сейчас нет. После spawn `BasicEnemy` ведёт себя автономно.

#### Чтение

`BasicEnemy.is_dead() -> bool`
- Read-only death-state probe.

`BasicEnemy.has_target() -> bool`
- Read-only target-acquired probe.

`BasicEnemy.has_attack_target() -> bool`
- Read-only attack-target probe.

`BasicEnemy.reached_target() -> bool`
- Read-only arrival probe for owner/debug checks.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `BasicEnemy._update_scan(delta: float) -> void` | Internal perception tick. |
| `BasicEnemy._try_attack_target(target_node: Node2D) -> void` | Internal attack resolution path. |
| `BasicEnemy.move_to_target(speed_mult: float) -> void` | State-machine movement primitive, не caller-facing AI API. |
| `BasicEnemy.clear_target() -> void` | Internal AI state mutation. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.enemy_killed` | После enemy death handling | `(position: Vector2)` |
| `EventBus.enemy_reached_wall` | Когда enemy ударяет wall-like target | `(wall_position: Vector2i)` |
| `EventBus.time_of_day_changed` | Потребляется для phase-based hearing multiplier | `(new_phase: int, old_phase: int)` |

### Noise / hearing input

`classification`: `canonical`

#### Безопасные точки входа

`NoiseComponent.set_active(active: bool) -> void`
- Когда вызывать: когда owner объекта включает или выключает шум.
- Что делает: меняет runtime active-flag noise source.
- Гарантии: эмитит `EventBus.noise_source_changed`, поэтому perception owner может инициировать immediate rescan.

#### Чтение

`NoiseComponent.get_noise_position() -> Vector2`
- Read-only world position of the current source.

`NoiseComponent.is_audible_at(world_pos: Vector2) -> bool`
- Read-only helper for current radius/active-state check.

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| Direct writes to `noise_radius`, `noise_level`, `is_active` | Обходят even the minimal owner API and create hidden behavior changes. |
| `NoiseComponent._ready() -> void` | Lifecycle-only group registration. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.noise_source_changed` | После `NoiseComponent.set_active()` на реальном state change | `(noise_source: Node)` |

---

## Session & Time APIs

### Z-level switching / stairs

`classification`: `canonical`

#### Безопасные точки входа

`ZLevelManager.change_level(new_z: int) -> void`
- Когда вызывать: когда gameplay or scene orchestration должна перейти на другой z-level.
- Что делает: проверяет bounds, обновляет private canonical z state, эмитит local signal и `EventBus.z_level_changed`.
- Гарантии: canonical z-switch API; downstream world/presentation systems подписаны на это событие. `ChunkManager.set_active_z_level()` не является альтернативным public owner-path.
- Пример: `z_manager.change_level(-1)`

`GameWorld.request_z_transition(new_z: int) -> bool`
- Когда вызывать: из scene/in-world trigger path, если переход должен пройти через overlay orchestration.
- Что делает: запускает overlay transition, а затем вызывает `ZLevelManager.change_level(new_z)`.
- Гарантии: sanctioned scene-level transition API for `ZStairs` and similar triggers.

#### Чтение

`ZLevelManager.get_current_z() -> int`
- Authoritative read of current active z-level.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `ZStairs._trigger_transition() -> void` | Internal trigger path; sanctioned scene entrypoint lives in `GameWorld.request_z_transition()`. |
| `ZStairs._on_body_entered(body: Node2D) -> void` | Collision-driven trigger path, не generic z-switch API. |
| Direct writes to `ZLevelManager._current_z` | Обходят signal/event emission и downstream sync. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `ZLevelManager.z_level_changed` | После реального z transition | `(new_z: int, old_z: int)` |
| `EventBus.z_level_changed` | Глобальный bridge для world/presentation listeners | `(new_z: int, old_z: int)` |

### Time / calendar / day-night

`classification`: `canonical`

#### Безопасные точки входа

`TimeManager.reset_for_new_game() -> void`
- Когда вызывать: на new-session bootstrap.
- Что делает: сбрасывает время к стартовым значениям и эмитит initial time signals.
- Гарантии: canonical reset path for time state.

`TimeManager.restore_persisted_state(hour: float, day: int, season: int) -> void`
- Когда вызывать: только на load boundary.
- Что делает: восстанавливает authoritative time state и эмитит initial time signals.
- Гарантии: canonical load path for time layer.

`TimeManager.set_paused(paused: bool) -> void`
- Когда вызывать: когда owner scene/UI должен поставить время на паузу или снять с паузы.
- Что делает: обновляет private pause flag.
- Гарантии: sanctioned pause API instead of direct field writes.

`TimeManager.set_time_scale(scale: float) -> void`
- Когда вызывать: когда owner path меняет global time scale.
- Что делает: clamp-ит и применяет private time scale.
- Гарантии: sanctioned scale API instead of direct field writes.

#### Чтение

`TimeManager.get_hour() -> int`
- Read-only current hour.

`TimeManager.get_day_progress() -> float`
- Read-only normalized day progress.

`TimeManager.get_sun_progress() -> float`
- Read-only normalized sun position.

`TimeManager.get_sun_angle() -> float`
- Read-only daylight/shadow angle query.

`TimeManager.get_shadow_length_factor() -> float`
- Read-only daylight/shadow length query.

`TimeManager.is_time_paused() -> bool`
- Read-only pause-state probe.

`TimeManager.get_time_scale() -> float`
- Read-only time-scale probe.

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| `TimeManager._advance_time(delta: float) -> void` | Internal frame-owned time progression step. |
| `TimeManager._apply_authoritative_time_state(hour: float, day: int, season: int) -> void` | Internal shared setup helper behind reset/load. |
| Direct writes to `TimeManager.current_hour`, `current_day`, `current_season`, `_is_paused`, `_time_scale` | Обходят explicit API и затрудняют ownership of time semantics. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.time_tick` | Каждый frame/tick времени | `(current_hour: float, day_progress: float)` |
| `EventBus.hour_changed` | При переходе через целый час | `(hour: int)` |
| `EventBus.time_of_day_changed` | При смене фазы суток | `(new_phase: int, old_phase: int)` |
| `EventBus.day_changed` | При переходе на новый день | `(day_number: int)` |
| `EventBus.season_changed` | При смене сезона | `(new_season: int, old_season: int)` |

### Save / load orchestration

`classification`: `canonical`

#### Безопасные точки входа

`SaveManager.save_game(slot_name: String = "") -> bool`
- Когда вызывать: когда нужно сохранить игру в слот.
- Что делает: запускает full save orchestration, вызывает collectors, chunk save system и пишет JSON/chunk data на диск.
- Гарантии: canonical save boundary for current runtime.
- Пример: `var ok: bool = SaveManager.save_game("save_01")`

`SaveManager.load_game(slot_name: String) -> bool`
- Когда вызывать: когда нужно восстановить runtime из слота.
- Что делает: применяет world, chunk overlay, time, buildings, player и эмитит `load_completed`.
- Гарантии: current load order contract.
- Пример: `var ok: bool = SaveManager.load_game("save_01")`

`SaveManager.get_save_list() -> Array[Dictionary]`
- Когда вызывать: для UI/read-only listing сохранений.
- Что делает: возвращает нормализованный список метаданных по слотам.

`SaveManager.delete_save(slot_name: String) -> bool`
- Когда вызывать: когда нужно удалить слот через canonical owner path.
- Что делает: удаляет chunk blobs и slot directory.

`SaveManager.save_exists(slot_name: String) -> bool`
- Read-only existence probe for slot.

`SaveManager.request_load_after_scene_change(slot_name: String) -> void`
- Когда вызывать: когда UI/main-menu/death flow должны поставить слот в очередь на загрузку после scene change.
- Что делает: записывает canonical pending-load request в owner layer.
- Гарантии: sanctioned alternative to direct pending-slot mutation.

`SaveManager.clear_pending_load_request() -> void`
- Когда вызывать: когда new-game/bootstrap flow должен гарантированно очистить pending load.
- Что делает: очищает queued load request.

#### Чтение

`SaveManager.current_slot`
- Read-only probe of current active slot name. Never assign directly.

`SaveManager.is_busy`
- Read-only probe for save/load UI/orchestration. Never assign directly.

`SaveManager.get_save_list() -> Array[Dictionary]`
- Canonical save-slot listing API.

`SaveManager.consume_pending_load_slot() -> String`
- Owner-only read/write queue consumer for `GameWorld` boot sequence.

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| Direct writes to `SaveManager._pending_load_slot`, `current_slot`, `is_busy` | Обходят canonical save/load orchestration. |
| `SaveCollectors.collect_*()` | Internal collection helpers behind `SaveManager.save_game()`. |
| `SaveAppliers.apply_*()` | Internal apply helpers behind `SaveManager.load_game()`. |
| `SaveIO.write_json()` / `read_json()` / `delete_save_slot()` | Filesystem helper layer, не gameplay API. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.save_requested` | В начале save orchestration | `()` |
| `EventBus.save_completed` | После успешной записи | `()` |
| `EventBus.load_completed` | После успешного apply load-state | `()` |

## Cross-system orchestration APIs

### Crafting service

`classification`: `derived`

#### Безопасные точки входа

`CraftingSystem.can_craft(recipe: RecipeData, inventory: InventoryComponent) -> bool`
- Когда вызывать: когда нужно проверить доступность recipe для текущего inventory.
- Что делает: валидирует все inputs через `InventoryComponent`.
- Гарантии: read-only check; не хранит собственного authoritative state.

`CraftingSystem.execute_recipe(recipe: RecipeData, inventory: InventoryComponent) -> Dictionary`
- Когда вызывать: когда нужно выполнить crafting operation.
- Что делает: снимает inputs и кладёт outputs в inventory.
- Гарантии: мутирует только inventory-layer; своего canonical state не хранит.

#### Чтение

`CraftingSystem.can_craft(...) -> bool`
- Main read-only recipe availability check.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `CraftRecipeCommand.execute() -> Dictionary` | Command wrapper over `CraftingSystem.execute_recipe()`. Предпочтительный слой выбирается по orchestration need, а не обходом API. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `EventBus.item_crafted` | После успешного output step | `(item_id: String, amount: int)` |

### Command layer

`classification`: `derived`

#### Безопасные точки входа

`CommandExecutor.execute(command: GameCommand) -> Dictionary`
- Когда вызывать: когда действие должно пройти через uniform command envelope.
- Что делает: вызывает `command.execute()` и нормализует структуру результата.
- Гарантии: общий command result shape `{ success, message_key, message_args, ... }`.

#### Чтение

Current commands in scope:
- `HarvestTileCommand` -> delegates to `ChunkManager.try_harvest_at_world()`
- `PickupItemCommand` -> delegates to `Player.collect_item()`
- `PlaceBuildingCommand` -> delegates to `BuildingSystem.place_selected_building_at()`
- `RemoveBuildingCommand` -> delegates to `BuildingSystem.remove_building_at()`
- `CraftRecipeCommand` -> delegates to `CraftingSystem.execute_recipe()`

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `GameCommand.execute() -> Dictionary` on ad hoc subclasses not listed above | Разрешён только для конкретной команды, которую создал owner/orchestration path. |
| Direct field writes on command instances after `setup()` | Нарушают command immutability-by-convention before execution. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `none` | Command layer itself не эмитит dedicated event; события идут из целевых систем | gap |

## Content registries (read-only)

### Item / building / resource registry

`classification`: `canonical`

#### Безопасные точки входа

`ItemRegistry.get_item(id: String) -> ItemData`
- Read-only item lookup. Loaded at boot; runtime mutation запрещена.

`ItemRegistry.get_recipe(id: String) -> RecipeData`
- Read-only recipe lookup. Loaded lazily/at boot boundary; runtime mutation запрещена.

`ItemRegistry.get_building(id: StringName) -> BuildingData`
- Read-only building lookup. Loaded at boot; runtime mutation запрещена.

`ItemRegistry.get_resource_node(id: StringName) -> ResourceNodeData`
- Read-only resource-node lookup. Loaded at boot; runtime mutation запрещена.

#### Чтение

`ItemRegistry.get_all_recipes() -> Array[RecipeData]`
- Snapshot of current recipe registry.

`ItemRegistry.get_all_buildings() -> Array[BuildingData]`
- Snapshot of current building registry.

`ItemRegistry.get_all_resource_nodes() -> Array[ResourceNodeData]`
- Snapshot of current resource-node registry.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `ItemRegistry.register_item()` / `register_recipe()` / `register_building()` / `register_resource_node()` | Registry mutation layer, не runtime gameplay API для этой codebase iteration. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `none` | Dedicated registry-changed events в runtime scope отсутствуют | gap |

### Biome registry

`classification`: `canonical`

#### Безопасные точки входа

`BiomeRegistry.get_biome(id: StringName) -> BiomeData`
- Read-only biome lookup. Loaded at boot; runtime mutation запрещена.

`BiomeRegistry.get_biome_by_short_id(short_id: StringName) -> BiomeData`
- Read-only short-id lookup with base namespace fallback.

`BiomeRegistry.get_default_biome() -> BiomeData`
- Read-only fallback biome lookup.

#### Чтение

`BiomeRegistry.get_all_biomes() -> Array[BiomeData]`
- Snapshot of loaded biome registry.

`BiomeRegistry.get_palette_index(biome_id: StringName) -> int`
- Read-only palette index lookup.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `BiomeRegistry.register_biome()` / `load_mod_biomes()` | Registry mutation/loading API, не runtime gameplay entrypoint для этого проекта. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `none` | Dedicated biome-registry events отсутствуют | gap |

### Flora / decor registry

`classification`: `canonical`

#### Безопасные точки входа

`FloraDecorRegistry.get_flora_set(id: StringName) -> Resource`
- Read-only flora-set lookup. Loaded at boot; runtime mutation запрещена.

`FloraDecorRegistry.get_decor_set(id: StringName) -> Resource`
- Read-only decor-set lookup. Loaded at boot; runtime mutation запрещена.

#### Чтение

`FloraDecorRegistry.get_flora_sets_for_ids(ids: Array[StringName]) -> Array[Resource]`
- Batch flora-set read lookup.

`FloraDecorRegistry.get_decor_sets_for_ids(ids: Array[StringName]) -> Array[Resource]`
- Batch decor-set read lookup.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `FloraDecorRegistry.register_flora_set()` / `register_decor_set()` / `load_mod_flora()` / `load_mod_decor()` | Registry mutation/loading API, не runtime gameplay entrypoint для этого проекта. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `none` | Dedicated flora/decor-registry events отсутствуют | gap |

### World feature / POI registry

`classification`: `canonical`

#### Безопасные точки входа

`WorldFeatureRegistry.get_feature_by_id(id: StringName) -> FeatureHookData`
- Read-only feature-hook definition lookup. Loaded at boot; runtime mutation запрещена. Safe only after strict boot load succeeds.

`WorldFeatureRegistry.get_poi_by_id(id: StringName) -> PoiDefinition`
- Read-only POI definition lookup. Loaded at boot; runtime mutation запрещена. Safe only after strict boot load succeeds.

#### Чтение

`WorldFeatureRegistry.get_all_feature_hooks() -> Array[FeatureHookData]`
- Snapshot of the loaded feature-hook registry. Failed boot load returns no partial runtime snapshot.

`WorldFeatureRegistry.get_all_pois() -> Array[PoiDefinition]`
- Snapshot of the loaded POI registry. Failed boot load returns no partial runtime snapshot.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `WorldFeatureRegistry.is_ready() -> bool` | Boot/runtime guard used by `WorldGenerator.initialize_world()`, не generic gameplay/content query API. |
| `WorldFeatureRegistry._load_base_definitions()` / `_load_definitions_from_directory()` / `_register_feature()` / `_register_poi()` | Internal registry loading path. Runtime code must not re-scan resources or mutate the catalog directly. |

#### События

| Событие | Когда срабатывает | Payload |
|---------|-------------------|---------|
| `none` | Dedicated world-feature-registry events отсутствуют | gap |

---

## Runtime diagnostics

`classification`: `derived` / `debug-only`

### Чтение

`WorldPerfMonitor.get_debug_snapshot() -> Dictionary`
- Что возвращает: last-frame debug snapshot with `fps`, `frame_time_ms`, `world_update_ms`, `chunk_generation_ms`, `visual_build_ms`, `dispatcher_ms`, raw category totals, and raw op labels captured after `WorldPerfProbe.flush_frame()`.
- Когда использовать: debug overlays and diagnostics that need compact performance metrics without consuming `WorldPerfProbe` directly.
- Особенности: read-only, transient, not persistence data, not proof by itself for acceptance-level runtime performance. Runtime/perf acceptance still requires explicit runtime proof or manual human verification per `PERFORMANCE_CONTRACTS.md`.

`WorldRuntimeDiagnosticLog.get_timeline_snapshot(limit: int = 24) -> Array[Dictionary]`
- Что возвращает: bounded structured timeline events with Russian `summary`, technical `record`, `detail_fields`, `timestamp_label`, `repeat_count`, and dedupe metadata. When present, debug-only `trace_id` / `incident_id` survive into the snapshot for correlation with overlay forensics.
- Когда использовать: debug overlays and validation tooling that need the recent causal sequence without parsing console text.
- Особенности: debug-only, cooldown-deduped, not gameplay truth, not persistence data. Human summaries remain Russian-first diagnostic text; structured fields keep `actor/action/target/reason/impact/state/code` for engineer/agent inspection.

### Debug artifacts

`user://debug/f11_chunk_overlay.log`
- Что содержит: full F11 overlay session snapshots while the overlay is visible: top HUD metrics, player/radii, capped/grouped queue rows, error/stalled chunk summary, timeline events, bounded chunk rows, and raw metrics.
- Кто пишет: only `WorldChunkDebugOverlay`.
- Когда пишется: file is overwritten on the first F11 open in a fresh game process; later F11 opens in the same process append; no snapshots are written while F11 is hidden.
- Особенности: debug-only derived artifact, not gameplay truth, not save/load data, and not an API for reconstructing world state. `Shift+F11` cycles overlay modes, including `forensics`; the log header includes `ProjectSettings.globalize_path(LOG_PATH)` so humans can find the OS path.

`user://debug/f11_chunk_incident_<timestamp>.log`
- Что содержит: explicit incident capture from one bounded F11-style snapshot: `incident_summary`, `suspicion_flags`, `trace_events`, `chunk_causality_rows`, `task_debug_rows`, timeline excerpts, and raw snapshot payload. May legitimately contain `no_active_incident`.
- Кто пишет: only `WorldChunkDebugOverlay`.
- Когда пишется: only on explicit `Ctrl+F11` manual capture; capture works even if the overlay is hidden.
- Особенности: debug-only derived artifact, not gameplay truth, not save/load data, and not a second diagnostics bus. The dump serializes existing bounded debug state and must not enqueue/load/generate/publish chunks.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| Direct writes to `WorldRuntimeDiagnosticLog._timeline_events` or `WorldPerfMonitor._latest_debug_snapshot` | Bypasses bounded/deduped owner paths and may desync overlay diagnostics from emitted logs. |
| Direct calls to `WorldPerfProbe.flush_frame()` from overlay code | `WorldPerfMonitor` is the single frame-level consumer; a second consumer would steal metrics from the monitor. |
| Direct writes to `user://debug/f11_chunk_overlay.log` from systems other than `WorldChunkDebugOverlay` | The artifact must stay a serialized F11 snapshot, not a second diagnostics bus or gameplay log sink. |
| Direct writes to `user://debug/f11_chunk_incident_<timestamp>.log` from systems other than `WorldChunkDebugOverlay` | Incident dumps must stay explicit bounded captures owned by the overlay, not ad-hoc gameplay/system logs. |

---

## Current API Gaps

- У `Topology` нет dedicated `topology_changed` или `topology_ready` signal. Сейчас readiness читается только через `ChunkManager.is_topology_ready()`.
- У `Reveal` нет dedicated reveal-changed signal. Surface reveal и underground fog применяются owner-systems напрямую.
- У `World` нет generic public terrain-mutation API. Это хорошо как boundary, но агент должен явно знать, что mutation идёт только через `Mining`.
- У `Chunk Lifecycle` нет public per-chunk load/unload API в scope. Есть только boot-load orchestration и internal streaming paths. Boot compute queue (`_boot_submit_pending_tasks`, `_boot_worker_compute`, `_boot_collect_completed`) остаётся internal; public surface — только read-only: `get_boot_compute_active_count()`, `get_boot_compute_pending_count()`, `get_boot_failed_coords()`.
- У `Presentation` нет generic public redraw API. Безопасный путь к redraw идёт через higher-level world/mining/lifecycle entrypoints.
- Feature-hook and POI resolver APIs are intentionally not public in the current iteration; runtime callers get only read-only definition-registry access plus the existing `WorldGenerator` build entrypoints.
- `WorldFeatureDebugOverlay` remains an internal debug-only payload consumer. `WorldChunkDebugOverlay` has a read-only diagnostic snapshot API, but there is still no public `ChunkManager` / `Chunk` placement-generation API and no public overlay API that recomputes feature or POI truth.
- `EventBus.z_level_changed` используется внутри scope, но source emission находится вне текущего scope.
- У `Spawn / pickup orchestration` нет public generic enemy-spawn API; spawn loop остаётся owner-only even though enable/save-load ownership уже оформлены.
- У `Enemy AI / fauna runtime` нет public behavior-driving API. Это допустимо, но важно явно понимать, что поведение автономно после spawn.
- У `Save / load orchestration` `current_slot` и `is_busy` остаются public read probes, поэтому caller discipline всё ещё зависит от соблюдения этого документа.
