---
title: Public API
doc_type: governance
status: draft
owner: engineering
source_of_truth: true
version: 0.3
last_updated: 2026-03-28
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
| Выдать игроку предмет | `Player.collect_item()` |
| Потратить item / scrap у игрока | `Player.spend_item()` / `Player.spend_scrap()` |
| Нанести урон сущности | `HealthComponent.take_damage()` |
| Добавить / убрать stack из inventory | `InventoryComponent.add_item()` / `InventoryComponent.remove_item()` |
| Экипировать / снять предмет | `EquipmentComponent.equip()` / `EquipmentComponent.unequip()` |
| Прочитать процент кислорода | `OxygenSystem.get_oxygen_percent()` |
| Проверить питание life support | `BaseLifeSupport.is_powered()` |
| Выбрать / поставить / снести постройку | `BuildingSystem.set_selected_building()` / `BuildingSystem.place_selected_building_at()` / `BuildingSystem.remove_building_at()` |
| Проверить indoor tile | `BuildingSystem.is_cell_indoor()` |
| Прочитать power balance | `PowerSystem.get_balance()` / `PowerSystem.get_supply_ratio()` |
| Изменить runtime power config | `PowerSourceComponent.set_enabled()` / `PowerSourceComponent.set_condition()` / `PowerConsumerComponent.set_demand()` / `PowerConsumerComponent.set_priority()` |
| Сохранить / восстановить pickups | `SpawnOrchestrator.save_pickups()` / `SpawnOrchestrator.load_pickups()` |
| Проверить enemy runtime state | `BasicEnemy.is_dead()` / `BasicEnemy.has_target()` |
| Включить / выключить шумный источник | `NoiseComponent.set_active()` |
| Скрафтить рецепт | `CraftingSystem.execute_recipe()` |
| Выполнить game command | `CommandExecutor.execute()` |
| Получить read-only content data | `ItemRegistry.get_item()` / `BiomeRegistry.get_biome()` / `FloraDecorRegistry.get_flora_set()` |

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
- Особенности: loaded-only; не authoritative для unloaded world. Текущий gap: при невалидном индексе возвращает `GROUND`.

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
- Что возвращает: есть ли сейчас `ROCK` в loaded chunk по world position.
- Когда использовать: перед попыткой mining interaction.
- Особенности: loaded-only; не authoritative для unloaded chunks. Текущий gap из `DATA_CONTRACTS.md`: unloaded fallback отсутствует.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `Chunk.try_mine_at(local: Vector2i) -> Dictionary` | Делает raw chunk-local mutation и redraw, но сам не эмитит `EventBus.mountain_tile_mined`, не патчит topology через owner path и не применяет underground fog orchestration. |
| `Chunk._refresh_open_neighbors(local_tile: Vector2i) -> void` | Это normalization helper, а не safe mining API. Сам по себе не выполняет полный mining contract. |
| `Chunk._refresh_open_tile(local_tile: Vector2i) -> void` | Low-level helper для `MINED_FLOOR <-> MOUNTAIN_ENTRANCE` normalization. |
| `ChunkManager._seam_normalize_and_redraw(tile_pos: Vector2i, local_tile: Vector2i, source_chunk: Chunk) -> void` | Cross-chunk redraw helper. Нельзя использовать как substitute для mining orchestration. |
| `ChunkManager.ensure_underground_pocket(center_tile: Vector2i, pocket_tiles: Array) -> void` | Debug-only direct writer. Обходит production mining path. |

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
- Что делает: synchronously loads the initial radius, completes player-chunk redraw immediately, then forces topology ready before boot finishes.
- Гарантии: соблюдает `Postconditions: generate chunk`; initial surface topology ready before boot complete.
- Пример вызова: `await chunk_manager.boot_load_initial_chunks(_on_boot_progress)`

`ChunkManager.sync_display_to_player() -> void`
- Когда вызывать: когда display positions loaded chunks нужно пересинхронизировать с player reference chunk.
- Что делает: вычисляет reference chunk и обновляет display position у всех loaded chunks.
- Гарантии: не меняет canonical terrain или topology; presentation-only display sync.
- Пример вызова: `chunk_manager.sync_display_to_player()`

Примечание: public per-chunk `load/unload` request API в scope сейчас нет. Runtime streaming paths остаются internal.

### Чтение

`ChunkManager.get_loaded_chunks() -> Dictionary`
- Что возвращает: текущий map loaded chunks для active z.
- Когда использовать: если owner-system должен итерировать только по already-loaded chunks.
- Особенности: loaded-only snapshot; не описывает unloaded world.

`ChunkManager.is_tile_loaded(gt: Vector2i) -> bool`
- Что возвращает: загружен ли tile сейчас.
- Когда использовать: как guard перед loaded-only operations.
- Особенности: не инициирует загрузку.

`ChunkManager.get_chunk_at_tile(gt: Vector2i) -> Chunk`
- Что возвращает: loaded chunk containing tile или `null`.
- Когда использовать: при loaded-only lifecycle/presentation reads.
- Особенности: не authoritative для unloaded reads.

`Chunk.is_redraw_complete() -> bool`
- Что возвращает: завершён ли progressive redraw этого chunk.
- Когда использовать: boot/lifecycle logic, если нужен fully drawn chunk before proceeding.
- Особенности: presentation progress only; terrain already authoritative even if redraw not complete.

`Chunk.get_redraw_phase_name() -> StringName`
- Что возвращает: текущую фазу progressive redraw.
- Когда использовать: debug/telemetry around chunk redraw.
- Особенности: presentation-only progress indicator.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `ChunkManager._load_chunk(coord: Vector2i) -> void` | Internal streaming primitive for current active z only. |
| `ChunkManager._load_chunk_for_z(coord: Vector2i, z_level: int) -> void` | Full load/install path with cache/native/flora/topology coupling. Нельзя дёргать как ad-hoc API. |
| `ChunkManager._unload_chunk(coord: Vector2i) -> void` | Internal unload/save boundary. Сам сохраняет dirty diffs и invalidates topology. |
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
- Что делает: после initial chunk load вызывает native `ensure_built()` или `_ensure_topology_current()`.
- Гарантии: topology ready at end of boot load path; см. `Postconditions: generate chunk`.
- Пример вызова: `await chunk_manager.boot_load_initial_chunks(_on_boot_progress)`

`ChunkManager.try_harvest_at_world(world_pos: Vector2) -> Dictionary`
- Когда вызывать: когда topology должна обновиться после mining.
- Что делает: после successful mining вызывает `_on_mountain_tile_changed()` до emission `EventBus.mountain_tile_mined`.
- Гарантии: immediate incremental topology patch runs before downstream listeners react; см. `Postconditions: mine tile`.
- Пример вызова: `var result := chunk_manager.try_harvest_at_world(hit_world_pos)`

### Чтение

`ChunkManager.is_topology_ready() -> bool`
- Что возвращает: готова ли surface topology для active runtime.
- Когда использовать: если код должен дождаться readiness before reading topology.
- Особенности: authoritative only for currently loaded surface bubble; нет dedicated ready event.

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
- Особенности: loaded-only; если traversal упирается в unloaded continuation, `truncated = true`.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `ChunkManager._mark_topology_dirty() -> void` | Dirty flag helper, не topology API. |
| `ChunkManager._ensure_topology_current() -> void` | Synchronous owner-only rebuild gate. Может форсить full rebuild. |
| `ChunkManager._process_topology_build() -> void` | Budgeted runtime worker step, а не caller-facing API. |
| `ChunkManager._rebuild_loaded_mountain_topology() -> void` | Full rebuild implementation, loaded-bubble scoped only. |
| `ChunkManager._incremental_topology_patch(tile_pos: Vector2i, new_type: int) -> void` | Low-level derived patch helper; caller не должен поддерживать topology вручную. |
| Native builder calls `set_chunk`, `remove_chunk`, `update_tile`, `ensure_built` | Internal backend contract behind `ChunkManager`; direct callers рискуют разойтись с managed topology state. |

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
- Гарантии: immediate underground reveal side-effects из `Postconditions: mine tile`; canonical terrain semantics не меняются вне mining contract.
- Пример вызова: `var result := chunk_manager.try_harvest_at_world(hit_world_pos)`

Примечание: z-switch reveal side-effects достигаются через canonical owner-path `ZLevelManager.change_level()`. `ChunkManager.set_active_z_level()` остаётся downstream sink и не является public z-switch API.

Примечание: public surface reveal refresh API сейчас нет. `MountainRoofSystem` владеет refresh internally и сам реагирует на player movement, chunk load/unload и mining events.

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
- Что делает: loads chunks, forces immediate redraw where needed, оставляет non-player chunks на progressive redraw.
- Гарантии: canonical terrain уже authoritative после load; presentation строится через documented chunk redraw paths. См. `Postconditions: generate chunk`.
- Пример вызова: `await chunk_manager.boot_load_initial_chunks(_on_boot_progress)`

`ChunkManager.try_harvest_at_world(world_pos: Vector2) -> Dictionary`
- Когда вызывать: когда mining должен immediately обновить terrain/cover/cliff visuals и wall-form selection.
- Что делает: redraws local dirty set, same-chunk normalized neighbors и loaded cross-chunk seam strips; потом downstream reveal/shadow listeners обновляются через event.
- Гарантии: соблюдает `Postconditions: mine tile` и current `Wall Atlas Selection` contract.
- Пример вызова: `var result := chunk_manager.try_harvest_at_world(hit_world_pos)`

`MountainShadowSystem.prepare_boot_shadows(progress_callback: Callable) -> void`
- Когда вызывать: во время boot, если surface shadow presentation должна быть собрана до завершения загрузки.
- Что делает: строит edge cache и shadow sprites для текущих loaded mountain chunks с прогресс-коллбеком.
- Гарантии: presentation-only; canonical terrain и topology не меняются.
- Пример вызова: `_mountain_shadow_system.prepare_boot_shadows(_on_boot_progress)`

`MountainShadowSystem.build_boot_shadows() -> void`
- Когда вызывать: если нужен synchronous boot shadow build без progress callback.
- Что делает: immediately builds edge cache и shadow sprites для current loaded surface chunks.
- Гарантии: presentation-only; same shadow contract as `prepare_boot_shadows()`.
- Пример вызова: `_mountain_shadow_system.build_boot_shadows()`

`Chunk.complete_redraw_now() -> void`  `(owner-only safe entrypoint)`
- Когда вызывать: только из chunk lifecycle owner path, если уже созданный loaded chunk нужно redraw immediately.
- Что делает: полный terrain/cover/cliff redraw этого chunk.
- Гарантии: presentation-only, loaded-only; не меняет canonical terrain и не является general external redraw API.
- Пример вызова: внутри owner path `chunk.complete_redraw_now()`

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
| `Chunk._redraw_terrain_tile(local_tile: Vector2i) -> void` | Single-tile terrain draw helper. |
| `Chunk._redraw_cover_tile(local_tile: Vector2i) -> void` | Single-tile cover draw helper. |
| `Chunk._redraw_cliff_tile(local_tile: Vector2i) -> void` | Single-tile cliff overlay helper. |
| `Chunk._surface_rock_visual_class(local_tile: Vector2i) -> Vector2i` | Presentation-only wall-form selection helper; не terrain semantics. |
| `Chunk._rock_visual_class(local_tile: Vector2i) -> Vector2i` | Underground presentation-only wall-form helper; не topology/read API. |
| `MountainShadowSystem._mark_dirty(coord: Vector2i) -> void` | Internal invalidation queue helper. |
| `MountainShadowSystem._update_edges_at(tile_pos: Vector2i) -> void` | Low-level shadow edge cache patch helper. |
| `MountainShadowSystem._start_shadow_build(coord: Vector2i) -> void` | Internal progressive shadow build primitive. |

### Wall Atlas

- Surface wall-form selection идёт через `Chunk._surface_rock_visual_class(local_tile: Vector2i) -> Vector2i`.
- Surface openness contract идёт через `Chunk._is_open_for_surface_rock_visual(terrain_type: int) -> bool`.
- В текущем коде surface visual-open = `GROUND`, `WATER`, `SAND`, `GRASS`, `MINED_FLOOR`, `MOUNTAIN_ENTRANCE`.
- Underground wall-form selection идёт через `Chunk._rock_visual_class(local_tile: Vector2i) -> Vector2i`.
- Underground openness contract идёт через `Chunk._is_open_for_visual(terrain_type: int) -> bool`, то есть любой non-`ROCK` считается visual-open.
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
- Что делает: инициализирует generator graph, samplers, biome/variation resolvers, chunk content builder и emits `world_initialized`.
- Гарантии: после этого generator-side surface reads/builds готовы; см. `Current Source Of Truth Summary`.
- Пример вызова: `WorldGenerator.initialize_world(world_seed)`

`WorldGenerator.initialize_random() -> void`
- Когда вызывать: при старте новой сессии без фиксированного seed.
- Что делает: выбирает random seed и делегирует в `initialize_world()`.
- Гарантии: те же generator initialization guarantees, что и у `initialize_world()`.
- Пример вызова: `WorldGenerator.initialize_random()`

`WorldGenerator.build_chunk_content(chunk_coord: Vector2i) -> ChunkBuildResult`
- Когда вызывать: когда нужен structured surface chunk payload в виде `ChunkBuildResult`.
- Что делает: canonicalizes chunk coord и строит full chunk content через `ChunkContentBuilder`.
- Гарантии: current surface generator semantics; не генерирует runtime-only `MINED_FLOOR` / `MOUNTAIN_ENTRANCE`.
- Пример вызова: `var result: ChunkBuildResult = WorldGenerator.build_chunk_content(coord)`

`WorldGenerator.build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary`
- Когда вызывать: когда lifecycle/worker path нужен native payload dictionary для `Chunk.populate_native()`.
- Что делает: canonicalizes chunk coord и возвращает packed arrays for terrain/height/variation/biome/flora.
- Гарантии: payload fields соответствуют `ChunkBuildResult.to_native_data()` contract из `DATA_CONTRACTS.md`.
- Пример вызова: `var native_data: Dictionary = WorldGenerator.build_chunk_native_data(coord)`

`WorldGenerator.build_tile_data(tile_pos: Vector2i) -> TileGenData`
- Когда вызывать: когда нужен full generated surface tile description, а не только terrain type.
- Что делает: canonicalizes tile и строит `TileGenData` через `SurfaceTerrainResolver`.
- Гарантии: generator-side surface base terrain semantics only.
- Пример вызова: `var tile_data: TileGenData = WorldGenerator.build_tile_data(tile_pos)`

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
| `EventBus.world_initialized` | После `WorldGenerator.initialize_world()` завершает setup | `(seed_value: int)` |

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
| Direct mutation of `InventoryComponent.slots` or `InventorySlot.item` / `amount` | Обходит owner-layer и `inventory_updated`; текущий UI сам так делает, но это contract gap. |

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
| `EquipmentComponent.load_state(data: Dictionary) -> void` | Save/load boundary only; не generic runtime equip API. |

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

#### Чтение

`BaseLifeSupport.is_powered() -> bool`
- Preferred read API for gameplay/UI checks.

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
- Что делает: валидирует выбор/стоимость/размещение, тратит scrap, создаёт building node, помечает room topology dirty и эмитит `building_placed`.
- Гарантии: authoritative placement path для building runtime.
- Пример: `var result: Dictionary = building_system.place_selected_building_at(mouse_pos)`

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

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `BuildingSystem._toggle_build_mode() -> void` | Input/UI internal mode toggle, не placement API. |
| `BuildingSystem._on_building_destroyed(grid_pos: Vector2i) -> void` | Destruction callback path tied to health binding. |
| `BuildingPlacementService.place_selected_at(mouse_world: Vector2) -> Vector2i` | Low-level creation helper; safe placement orchestration живёт в `BuildingSystem.place_selected_building_at()`. |
| Direct mutation of `BuildingSystem.walls` | Ломает canonical occupancy map и room invalidation chain. |

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

`PowerSourceComponent.force_shutdown() -> void`
- Когда вызывать: аварийное отключение источника.
- Что делает: мгновенно обнуляет output и эмитит `output_changed(0.0)`.

`PowerConsumerComponent.set_demand(new_demand: float) -> void` / `PowerConsumerComponent.set_priority(new_priority: Priority) -> void`
- Когда вызывать: когда owner потребителя меняет power config.
- Что делает: обновляет config и эмитит `configuration_changed`.

#### Чтение

`PowerSystem.total_supply`, `PowerSystem.total_demand`, `PowerSystem.is_deficit`
- Read-only aggregate state for HUD/debug/owner systems. Не write-safe.

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

`SpawnOrchestrator.clear_pickups() -> void`
- Когда вызывать: owner-side reset before load/reset.
- Что делает: удаляет все текущие pickup nodes.

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
- Гарантии: enemy AI увидит change на следующем scan tick.

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
| `none` | Dedicated noise-changed event отсутствует | gap |

---

## Session & Time APIs

### Z-level switching / stairs

`classification`: `canonical`

#### Безопасные точки входа

`ZLevelManager.change_level(new_z: int) -> void`
- Когда вызывать: когда gameplay or scene orchestration должна перейти на другой z-level.
- Что делает: проверяет bounds, обновляет `current_z`, эмитит local signal и `EventBus.z_level_changed`.
- Гарантии: canonical z-switch API; downstream world/presentation systems подписаны на это событие. `ChunkManager.set_active_z_level()` не является альтернативным public owner-path.
- Пример: `z_manager.change_level(-1)`

#### Чтение

`ZLevelManager.get_current_z() -> int`
- Authoritative read of current active z-level.

#### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `ZStairs._trigger_transition() -> void` | Internal scene-glue path via `GameWorld`, overlay, and `ZLevelManager`. |
| `ZStairs._on_body_entered(body: Node2D) -> void` | Collision-driven trigger path, не generic z-switch API. |
| Direct writes to `ZLevelManager.current_z` | Обходят signal/event emission и downstream sync. |

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

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| `TimeManager._advance_time(delta: float) -> void` | Internal frame-owned time progression step. |
| `TimeManager._apply_authoritative_time_state(hour: float, day: int, season: int) -> void` | Internal shared setup helper behind reset/load. |
| Direct writes to `TimeManager.current_hour`, `current_day`, `current_season`, `is_paused`, `time_scale` | Обходят explicit API и затрудняют ownership of time semantics. |

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

#### Чтение

`SaveManager.current_slot`
- Read-only probe of current active slot name. Never assign directly.

`SaveManager.is_busy`
- Read-only probe for save/load UI/orchestration. Never assign directly.

`SaveManager.get_save_list() -> Array[Dictionary]`
- Canonical save-slot listing API.

#### Внутренние методы (НЕ вызывать)

| Метод / поле | Почему нельзя вызывать напрямую |
|-------------|---------------------------------|
| Direct writes to `SaveManager.pending_load_slot`, `current_slot`, `is_busy` | Обходят canonical save/load orchestration. |
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

---

## Current API Gaps

- У `Topology` нет dedicated `topology_changed` или `topology_ready` signal. Сейчас readiness читается только через `ChunkManager.is_topology_ready()`.
- У `Reveal` нет dedicated reveal-changed signal. Surface reveal и underground fog применяются owner-systems напрямую.
- У `World` нет generic public terrain-mutation API. Это хорошо как boundary, но агент должен явно знать, что mutation идёт только через `Mining`.
- У `Chunk Lifecycle` нет public per-chunk load/unload API в scope. Есть только boot-load orchestration и internal streaming paths.
- У `Presentation` нет generic public redraw API. Безопасный путь к redraw идёт через higher-level world/mining/lifecycle entrypoints.
- `EventBus.z_level_changed` используется внутри scope, но source emission находится вне текущего scope.
- У `Inventory runtime` нет authoritative public API для move/split/sort/drop. Эти semantics сейчас частично живут в `InventoryPanel`.
- У `Equipment runtime` нет authoritative public API, который одновременно оркестрирует inventory + equipment handoff.
- У `Spawn / pickup orchestration` нет public generic enemy-spawn API; текущий spawn loop остаётся owner-only и сейчас не включается public path-ом.
- У `Enemy AI / fauna runtime` нет public behavior-driving API. Это допустимо, но важно явно понимать, что поведение автономно после spawn.
- У `Noise / hearing input` нет dedicated noise-changed signal; реакция идёт только через polling enemy scan.
- У `Z-level switching` нет dedicated public transition orchestrator beyond `ZLevelManager.change_level()`; `ZStairs` использует internal scene glue.
- У `Time / calendar` нет public pause/resume API; текущие callers мутируют `TimeManager.is_paused` напрямую.
- У `Save / load orchestration` UI-код всё ещё может обойти owner-layer direct writes в `pending_load_slot` и direct filesystem logic, если не придерживаться этого документа.
