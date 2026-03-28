---
title: Public API
doc_type: governance
status: draft
owner: engineering
source_of_truth: true
version: 0.1
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

`ChunkManager.set_active_z_level(z: int) -> void`
- Когда вызывать: при переходе между z-levels, когда reveal runtime должен переключиться вместе с active world.
- Что делает: на underground entry очищает shared fog state и immediately recomputes visible circle around player.
- Гарантии: соблюдает reveal-layer contract про transient underground fog state.
- Пример вызова: `chunk_manager.set_active_z_level(-1)`

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

`Chunk.complete_redraw_now() -> void`
- Когда вызывать: только из chunk lifecycle owner path, если уже созданный loaded chunk нужно redraw immediately.
- Что делает: полный terrain/cover/cliff redraw этого chunk.
- Гарантии: presentation-only, loaded-only; не меняет canonical terrain.
- Пример вызова: `chunk.complete_redraw_now()`

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

`classification`: orchestration over `canonical` active-z selection plus reveal/presentation switching.  
См. [World Data Contracts](../02_system_specs/world/DATA_CONTRACTS.md): `Layer: World`, `Layer: Reveal`, `Source Of Truth Vs Derived State`.

### Безопасные точки входа

`ChunkManager.set_active_z_level(z: int) -> void`
- Когда вызывать: когда higher-level scene orchestration переводит world stack на другой z-level.
- Что делает: переключает active chunk set, обновляет visibility z-containers, фильтрует load queue, а на underground entry очищает fog state и immediately recomputes visible fog around player.
- Гарантии: active z source-of-truth остаётся в `ChunkManager`; reveal/presentation side-effects выполняются в documented owner path.
- Пример вызова: `chunk_manager.set_active_z_level(new_z)`

### Чтение

`ChunkManager.get_active_z_level() -> int`
- Что возвращает: текущий active z-level world stack.
- Когда использовать: перед z-dependent world/topology/reveal/presentation reads.
- Особенности: authoritative active-z read in scope.

### Внутренние методы (НЕ вызывать)

| Метод | Почему нельзя вызывать напрямую |
|-------|-------------------------------|
| `GameWorld._on_z_level_changed(new_z: int, _old_z: int) -> void` | Scene glue. Координирует `ChunkManager`, daylight и `MountainShadowSystem`; не public API. |
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

## Current API Gaps

- У `Topology` нет dedicated `topology_changed` или `topology_ready` signal. Сейчас readiness читается только через `ChunkManager.is_topology_ready()`.
- У `Reveal` нет dedicated reveal-changed signal. Surface reveal и underground fog применяются owner-systems напрямую.
- У `World` нет generic public terrain-mutation API. Это хорошо как boundary, но агент должен явно знать, что mutation идёт только через `Mining`.
- У `Chunk Lifecycle` нет public per-chunk load/unload API в scope. Есть только boot-load orchestration и internal streaming paths.
- У `Presentation` нет generic public redraw API. Безопасный путь к redraw идёт через higher-level world/mining/lifecycle entrypoints.
- `EventBus.z_level_changed` используется внутри scope, но source emission находится вне текущего scope.
