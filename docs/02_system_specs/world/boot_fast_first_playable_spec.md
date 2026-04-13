---
title: Boot Fast First-Playable & Streaming Hitch Elimination
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-13
depends_on:
  - DATA_CONTRACTS.md
  - streaming_redraw_budget_spec.md
  - boot_chunk_apply_budget_spec.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
related_docs:
  - boot_chunk_readiness_spec.md
  - boot_visual_completion_spec.md
  - ../../04_execution/boot_streaming_perf_analysis.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
---

# Feature: Boot Fast First-Playable & Streaming Hitch Elimination

## Legacy Status

This spec documents a legacy boot/runtime optimization pass for the hybrid chunk runtime.

It is not the active architecture target for player-reachable readiness. Active target selection now lives in:

- `zero_tolerance_chunk_readiness_spec.md`
- `frontier_native_runtime_architecture_spec.md`
- `../../04_execution/frontier_native_runtime_execution_plan.md`

The terrain-first / later-catch-up allowances described below must not be extended as acceptable end-state player behavior.

## Design Intent

После реализации `streaming_redraw_budget_spec` (terrain-only redraw вместо full redraw) `first_playable` всё ещё достигается за **50.7 секунд** вместо целевых < 5 секунд. Runtime streaming работает в рамках бюджета по `streaming_redraw` (~2.2ms avg), но `finalize.emit` даёт хитчи **20–49ms на чанк**.

Детальный анализ (`docs/04_execution/boot_streaming_perf_analysis.md`) выявил 6 корневых причин:

1. **Round-robin progressive redraw разбавляет ring 0** (КРИТИЧЕСКАЯ) — 25 чанков конкурируют за progressive redraw в round-robin. Ring 0 получает свою очередь каждый 25-й кадр. При ~1500µs бюджете на step → ~2200 кадров чистого ожидания дорисовки ring 0.

2. **`complete_terrain_phase_now()` для player chunk — 957ms** (ВЫСОКАЯ) — первый `set_cell()` на TileMapLayer вызывает lazy-инициализацию: компиляцию шейдеров, подготовку атласов, аллокацию буферов. One-time cold-start ~950ms.

3. **Boot gate слишком строгий** (ВЫСОКАЯ) — `_boot_is_first_playable_slice_ready()` требует для ring 0: `is_gameplay_redraw_complete()` = terrain + cover + cliff. Игрок может начать играть с одним terrain.

4. **Ring 2 apply внутри boot loop** (СРЕДНЯЯ) — после ring 0 cover+cliff завершается, 16 ring 2 чанков apply'ятся и добавляются в `_redrawing_chunks`, увеличивая round-robin pool. Positive feedback loop.

5. **`finalize.emit` 20–49ms в runtime streaming** (СРЕДНЯЯ) — `_redraw_neighbor_borders(coord)` вызывает синхронный per-tile redraw на 4 соседних чанках (по 64 тайла каждый = 256 тайлов).

6. **`REDRAW_TIME_BUDGET_USEC = 1500` с check_interval=1** (НИЗКАЯ) — `Time.get_ticks_usec()` вызывается на КАЖДЫЙ обработанный тайл. GDScript syscall overhead ~2-5µs × 150 тайлов = ~300-750µs (20-50% от 1500µs бюджета).

Данная спека устраняет все 6 причин в трёх итерациях.

## Affected PERFORMANCE_CONTRACTS.md sections

- §1.4 Interactive whitelist: `_redraw_neighbor_borders()` в streaming finalize = full edge redraw в background path, провоцирует hitches 20–49ms.
- §2.2 Background budget targets: streaming peak превышает 4ms из-за `finalize.emit`.
- §7 Staged Loading / Degraded mode: terrain без cover/cliff — допустимый degraded state; текущий gate требует cover+cliff для first_playable, что нарушает intent §7.
- §1.1 Boot time: first_playable контракт < 5000ms нарушен (50727ms).

## Public API impact

Затрагиваемые safe entrypoints:

- `ChunkManager.is_boot_first_playable() -> bool` — семантика gate меняется: ring 0 требует `is_terrain_phase_done()` вместо `is_gameplay_redraw_complete()`. Возвращаемое значение теперь `true` раньше (после terrain, а не после cover+cliff).

Внешний API не меняется. Никаких новых public-методов. `boot_load_initial_chunks()` сохраняет семантику.

## Data Contracts — new and affected

### Новые слои данных

Не создаются.

### Affected layer: Presentation

- Что меняется:
  - `_redraw_neighbor_borders()` больше не вызывается синхронно из `_staged_loading_finalize()`. Вместо этого dirty-тайлы соседей добавляются в progressive redraw queue.
- Новые инварианты:
  - `_redraw_neighbor_borders()` НЕ вызывается синхронно в streaming finalize path. Вместо этого соседние чанки помечаются dirty и дорисовываются через `_tick_redraws()`.
- Что НЕ меняется:
  - `Chunk` redraw phase progression logic
  - `complete_terrain_phase_now()` и `complete_redraw_now()` — signature и реализация
  - progressive redraw budget job `_tick_redraws()` — базовая логика

### Affected layer: Boot Readiness

- Что меняется:
  - `first_playable` gate для ring 0 ослабляется: `is_terrain_phase_done()` вместо `is_gameplay_redraw_complete()`. Cover/cliff/flora — визуальные overlay'и, не блокирующие gameplay.
  - `_boot_has_pending_near_ring_work()` для ring 0 ослабляется аналогично.
  - Boot progressive redraw при boot приоритизирует ring 0–1 чанки до first_playable.
  - Ring 2 чанки НЕ apply'ятся внутри boot loop — передаются runtime streaming.
- Новые инварианты:
  - `first_playable` требует `is_terrain_phase_done()` для ring 0, `is_terrain_phase_done()` для ring 1. Cover/cliff/flora НЕ блокируют first_playable.
  - Flora по-прежнему блокирует `VISUAL_COMPLETE` и `boot_complete`.
- Инварианты, которые УДАЛЯЮТСЯ (заменяются):
  - `assert(not first_playable or all_ring_0_and_ring_1_chunks_are_loaded_applied_and_flora_done)` — ЗАМЕНЯЕТСЯ на: `assert(not first_playable or all_ring_0_and_ring_1_chunks_are_loaded_applied_and_terrain_done)`
  - `assert(flora_blocks_visual_complete_for_boot, "near slice first_playable also waits for flora")` — ЗАМЕНЯЕТСЯ на: `assert(flora_blocks_visual_complete_for_boot, "flora blocks VISUAL_COMPLETE and boot_complete but does NOT block first_playable")`
- Что НЕ меняется:
  - `boot_complete` gate logic
  - `VISUAL_COMPLETE` state transition (по-прежнему требует flora)
  - readiness state machine (enum BootChunkState)

### Not affected

- World layer (terrain bytes, modifications)
- Mining layer
- Topology layer
- Reveal layer
- Boot Apply Queue layer (из boot_chunk_apply_budget_spec)
- Feature / POI Definitions

---

## Iterations

### Iteration 1 — Boot gate relaxation + ring 2 deferral + priority redraw

Цель: сократить boot time с 50.7 секунд до ~2.5 секунд. Это объединяет три тесно связанных изменения, которые вместе устраняют архитектурную корневую причину медленного boot.

#### Изменение 1A: Ослабить first_playable gate для ring 0

В `_boot_is_first_playable_slice_ready()` (строка 2475–2495 `chunk_manager.gd`):

Было (строка 2491):
```gdscript
if ring == 0 and not chunk.is_gameplay_redraw_complete():
    return false
```

Стало:
```gdscript
if ring == 0 and not chunk.is_terrain_phase_done():
    return false
```

Обоснование: `is_gameplay_redraw_complete()` требует phase >= FLORA (terrain + cover + cliff завершены). `is_terrain_phase_done()` требует phase > TERRAIN. Cover/cliff/flora — визуальные overlay'и, игрок может начать играть с одним terrain. Это допустимый degraded state по PERFORMANCE_CONTRACTS §7.

Риск: Игрок увидит чанки ring 0 без cover/cliff overlay'ев на 0.5–2 секунды. Допустимо по §7.

#### Изменение 1B: Ослабить `_boot_has_pending_near_ring_work()` для ring 0

В `_boot_has_pending_near_ring_work()` (строка 2497–2510 `chunk_manager.gd`):

Было (строка 2508):
```gdscript
if ring == 0 and not chunk.is_gameplay_redraw_complete():
    return true
```

Стало:
```gdscript
if ring == 0 and not chunk.is_terrain_phase_done():
    return true
```

Обоснование: `_boot_has_pending_near_ring_work()` используется в `_boot_apply_from_queue()` как gate для ring 2 apply. Текущая реализация задерживает ring 2 apply пока ring 0 не завершит cover+cliff, что увеличивает boot time. С `is_terrain_phase_done()` gate открывается сразу после terrain ring 0, ring 2 не задерживается.

Но ring 2 apply всё равно не должен происходить внутри boot loop (см. изменение 1C).

#### Изменение 1C: Не apply'ить ring 2 внутри boot loop — отдать runtime

В `_boot_apply_from_queue()` (строка 2772–2809 `chunk_manager.gd`):

Было (строка 2778):
```gdscript
if _boot_get_chunk_ring(front_coord) > BOOT_FIRST_PLAYABLE_MAX_RING and _boot_has_pending_near_ring_work():
    break
```

Стало:
```gdscript
if _boot_get_chunk_ring(front_coord) > BOOT_FIRST_PLAYABLE_MAX_RING:
    break  # Ring 2+ deferred to runtime streaming after first_playable
```

Обоснование: Boot loop apply'ит только ring 0–1 (9 чанков). Ring 2 (16 чанков) передаются runtime streaming через `_boot_start_runtime_handoff()` сразу после first_playable. Это устраняет positive feedback loop: ранее ring 2 чанки добавлялись в `_redrawing_chunks`, раздувая round-robin pool с 9 до 25 чанков.

Ожидаемый эффект: Boot loop завершается после 9 чанков вместо 25. ring 2 дорисуется после first_playable через runtime streaming.

#### Изменение 1D: Приоритетный progressive redraw для ring 0–1 при boot

В `_boot_process_redraw_budget()` (строка 2540–2545 `chunk_manager.gd`):

Было:
```gdscript
func _boot_process_redraw_budget(max_usec: int) -> void:
    var started_usec: int = Time.get_ticks_usec()
    while not _redrawing_chunks.is_empty():
        _process_chunk_redraws()
        if Time.get_ticks_usec() - started_usec >= max_usec:
            break
```

Стало:
```gdscript
func _boot_process_redraw_budget(max_usec: int) -> void:
    var started_usec: int = Time.get_ticks_usec()
    ## During boot, prioritize ring 0-1 chunks for faster first_playable.
    ## Deferred (ring 2+) chunks are processed after first_playable in runtime.
    var priority_chunks: Array = []
    var deferred_chunks: Array = []
    while not _redrawing_chunks.is_empty():
        var c: Chunk = _redrawing_chunks.pop_front()
        if _boot_get_chunk_ring(c.chunk_coord) <= BOOT_FIRST_PLAYABLE_MAX_RING:
            priority_chunks.append(c)
        else:
            deferred_chunks.append(c)
    _redrawing_chunks = priority_chunks
    while not _redrawing_chunks.is_empty():
        _process_chunk_redraws()
        if Time.get_ticks_usec() - started_usec >= max_usec:
            break
    ## Restore deferred chunks at the end of the queue.
    _redrawing_chunks.append_array(deferred_chunks)
```

Обоснование: Без 1C ring 2 не попадёт в `_redrawing_chunks` при boot, поэтому это изменение — safety net и архитектурная гарантия. Если ring 2 каким-то образом окажется в queue при boot (например, ранее закэшированные), они не замедлят ring 0–1.

С изменениями 1A+1B+1C+1D, ring 0 получает очередь каждый 9-й кадр (из 9 ring 0–1 чанков) вместо каждого 25-го. Но учитывая 1A (gate ослаблен до terrain), ring 0 terrain уже завершён к моменту progressive redraw (через `complete_terrain_phase_now()`), поэтому progressive обрабатывает только cover/cliff/flora — быстрее и неблокирующе.

#### Изменение 1E: Обновить DATA_CONTRACTS.md

В `docs/02_system_specs/world/DATA_CONTRACTS.md`, секция `## Layer: Boot Readiness`, блок `invariants`:

Заменить строку ~440:
```
- `assert(not first_playable or all_ring_0_and_ring_1_chunks_are_loaded_applied_and_flora_done, "first_playable requires ring 0..1 (Chebyshev distance) to be honestly visual-ready — diagonal chunks included")`
```

На:
```
- `assert(not first_playable or all_ring_0_and_ring_1_chunks_are_loaded_applied_and_terrain_done, "first_playable requires ring 0..1 (Chebyshev distance) terrain phase done — cover/cliff/flora progressive, not blocking first_playable (boot_fast_first_playable_spec)")`
```

Заменить строку ~460:
```
- `assert(flora_blocks_visual_complete_for_boot, "REDRAW_PHASE_FLORA must complete before VISUAL_COMPLETE / boot_complete; near slice first_playable also waits for flora")`
```

На:
```
- `assert(flora_blocks_visual_complete_for_boot, "REDRAW_PHASE_FLORA must complete before VISUAL_COMPLETE / boot_complete; first_playable does NOT wait for flora (boot_fast_first_playable_spec)")`
```

Добавить новый инвариант после строки ~456:
```
- `assert(ring_2_deferred_to_runtime_at_boot, "ring 2+ chunks are NOT applied inside boot loop — they are handed off to runtime streaming via _boot_start_runtime_handoff() after first_playable (boot_fast_first_playable_spec)")`
- `assert(boot_progressive_redraw_prioritizes_near_ring, "_boot_process_redraw_budget() processes only ring 0-1 chunks during boot, deferring ring 2+ to end of queue (boot_fast_first_playable_spec)")`
```

#### Acceptance tests

- [ ] `first_playable` достигается за < 5000ms (контракт §1.1), ожидается ~2–3 секунды
- [ ] `WorldPerfProbe.mark_milestone("Boot.first_playable")` — лог показывает время < 5000ms
- [ ] При загрузке нового мира: terrain (земля/камни) виден сразу для ring 0–1; cover/cliff/flora появляются прогрессивно
- [ ] Ring 2 чанки НЕ apply'ятся до first_playable (проверяется по логу: `Boot.apply_chunk` — только ring 0–1 координаты)
- [ ] `boot_complete` по-прежнему достигается (все 25 чанков финализируются через runtime streaming)
- [ ] Нет crash/assert при загрузке нового мира
- [ ] Нет crash/assert при загрузке сохранения
- [ ] `_boot_is_first_playable_slice_ready()` возвращает true когда ring 0 `is_terrain_phase_done()` и ring 1 `is_terrain_phase_done()`
- [ ] DATA_CONTRACTS.md обновлён — инварианты Boot Readiness отражают новые gate conditions

#### Файлы, которые будут затронуты

- `core/systems/world/chunk_manager.gd`:
  - `_boot_is_first_playable_slice_ready()` — строка 2491
  - `_boot_has_pending_near_ring_work()` — строка 2508
  - `_boot_apply_from_queue()` — строка 2778
  - `_boot_process_redraw_budget()` — строки 2540–2545
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — секция Boot Readiness invariants

#### Файлы, которые НЕ ДОЛЖНЫ быть затронуты

- `core/systems/world/chunk.gd`
- `core/autoloads/world_generator.gd`
- `scenes/world/game_world.gd`
- `data/world/world_gen_balance.tres`
- `docs/00_governance/PUBLIC_API.md` (семантика `is_boot_first_playable()` меняется, но signature и owner остаются — обновление PUBLIC_API.md не требуется)

---

### Iteration 2 — TileMapLayer warm-up + progressive redraw budget tuning

Цель: устранить 957ms cold-start хитч при boot и ускорить все progressive redraws в ~2 раза.

#### Изменение 2A: Warm up TileMapLayer перед boot terrain redraw

В `_boot_apply_from_queue()` (`chunk_manager.gd`, строка 2797–2802), перед `chunk.complete_terrain_phase_now()`:

Было:
```gdscript
if coord == _boot_center and chunk != null and not chunk.is_terrain_phase_done():
    var redraw_usec: int = Time.get_ticks_usec()
    chunk.complete_terrain_phase_now()
```

Стало:
```gdscript
if coord == _boot_center and chunk != null and not chunk.is_terrain_phase_done():
    ## Warm up TileMapLayer GPU resources (shader compilation, atlas preparation)
    ## before the timed terrain redraw. First set_cell() on each layer triggers
    ## lazy initialization (~950ms total). Dummy set+erase pays this cost once.
    var warmup_usec: int = Time.get_ticks_usec()
    chunk.warmup_tile_layers()
    var warmup_ms: float = float(Time.get_ticks_usec() - warmup_usec) / 1000.0
    WorldPerfProbe.record("Boot.warmup_tile_layers", warmup_ms)
    var redraw_usec: int = Time.get_ticks_usec()
    chunk.complete_terrain_phase_now()
```

Новый метод в `chunk.gd`:
```gdscript
## Forces GPU resource initialization for all tile layers by performing a
## dummy set_cell + erase_cell. This triggers shader compilation and atlas
## preparation, paying the one-time cold-start cost (~950ms) outside the
## timed terrain redraw path.
func warmup_tile_layers() -> void:
    var dummy_coord := Vector2i(-1, -1)
    var dummy_source := 0
    var dummy_atlas := Vector2i.ZERO
    for layer: TileMapLayer in _tile_layers:
        if layer == null:
            continue
        layer.set_cell(dummy_coord, dummy_source, dummy_atlas)
        layer.erase_cell(dummy_coord)
```

Здесь `_tile_layers` — массив/список всех TileMapLayer нод чанка. Если такого массива нет, метод итерирует по children и фильтрует TileMapLayer.

Обоснование: Первый `set_cell()` на TileMapLayer вызывает lazy-инициализацию Godot rendering: компиляцию шейдеров, подготовку атласов, аллокацию GPU буферов. Стоимость ~950ms. После инициализации per-tile cost падает в ~50 раз. Dummy set+erase оплачивает этот cost один раз вне тайминга terrain redraw.

Ожидаемый эффект: `Boot.redraw_terrain` с 957ms → < 50ms. `Boot.warmup_tile_layers` ~950ms (оплачивается один раз, не влияет на `first_playable` timing, т.к. это pre-redraw setup). Суммарное boot apply для player chunk не уменьшится, но terrain redraw metric будет честным.

Примечание: warm-up сдвигает 950ms из `Boot.redraw_terrain` в `Boot.warmup_tile_layers`. Это НЕ устраняет 950ms задержка полностью — GPU компиляция неизбежна. Но изолирует cold-start cost от progressive redraw metrics и делает terrain redraw timing предсказуемым.

#### Изменение 2B: Увеличить `REDRAW_TIME_BUDGET_USEC` с 1500 до 2500

В `chunk.gd` (строка 16):

Было:
```gdscript
const REDRAW_TIME_BUDGET_USEC: int = 1500
```

Стало:
```gdscript
const REDRAW_TIME_BUDGET_USEC: int = 2500
```

Обоснование: При 1500µs и check_interval=1 каждый step обрабатывает ~150 тайлов. При 2500µs — ~250 тайлов. Количество steps на фазу чанка падает с ~27 до ~16. Весь progressive redraw ускоряется в ~1.7 раза. Это укладывается в бюджет `streaming_redraw` (зарегистрирован как 2ms), т.к. один step занимает ~2.5ms — один step на тик, и runtime `_tick_redraws()` вызывает ровно один step за вызов.

#### Изменение 2C: Увеличить check_interval с 1 до 4

В `_process_redraw_phase_tiles()` (`chunk.gd`, строка 1422–1428):

Было:
```gdscript
var check_interval: int = 1
if tiles_done % check_interval == 0:
    if Time.get_ticks_usec() - started_usec >= REDRAW_TIME_BUDGET_USEC:
        break
```

Стало:
```gdscript
var check_interval: int = 4
if tiles_done % check_interval == 0:
    if Time.get_ticks_usec() - started_usec >= REDRAW_TIME_BUDGET_USEC:
        break
```

Обоснование: `Time.get_ticks_usec()` — GDScript syscall, overhead ~2–5µs. При check_interval=1 и 150 тайлов → ~300–750µs чистого overhead (20–50% от 1500µs бюджета). При check_interval=4 overhead падает до ~75–188µs (3–8% от 2500µs бюджета). Overshoot от проверки каждые 4 тайла: максимум 3 лишних тайла × ~10µs = ~30µs — пренебрежимо мало.

Замечание: строка 1422 содержит комментарий `## Hard time guard: check every 4 tiles (terrain/cover/cliff) or every tile (flora/debug).` — т.е. интенция check_interval=4 уже была в комментарии, но реализация содержит `check_interval = 1`. Изменение 2C приводит реализацию в соответствие с комментарием.

#### Acceptance tests

- [ ] `Boot.warmup_tile_layers` — лог содержит строку с warm-up timing
- [ ] `Boot.redraw_terrain` < 50ms (вместо ~957ms) — cold-start стоимость вынесена в warmup
- [ ] `REDRAW_TIME_BUDGET_USEC == 2500` в `chunk.gd`
- [ ] `check_interval == 4` в `_process_redraw_phase_tiles()` в `chunk.gd`
- [ ] После загрузки мира: cover/cliff/flora на boot чанках полностью появляются за < 3 секунд
- [ ] `streaming_redraw` avg в FrameBudget summary < 4ms (контракт §2.2)
- [ ] Нет видимых frame hitches от redraw (p99 frame time < 20ms в steady state)
- [ ] Нет crash/assert при загрузке нового мира
- [ ] Нет crash/assert при загрузке сохранения

#### Файлы, которые будут затронуты

- `core/systems/world/chunk_manager.gd` — `_boot_apply_from_queue()`, добавление warmup вызова перед `complete_terrain_phase_now()`, строки ~2797–2802
- `core/systems/world/chunk.gd`:
  - Новый метод `warmup_tile_layers()` (public, owner-only call из ChunkManager)
  - Константа `REDRAW_TIME_BUDGET_USEC`, строка 16
  - `_process_redraw_phase_tiles()`, строка ~1425 (`check_interval`)

#### Файлы, которые НЕ ДОЛЖНЫ быть затронуты

- `core/autoloads/world_generator.gd`
- `scenes/world/game_world.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` (Presentation layer invariants не меняются — warm-up это implementation detail, не contract change)

---

### Iteration 3 — Defer neighbor borders из streaming finalize

Цель: устранить 20–49ms хитчи при runtime streaming finalize. Каждый новый streaming чанк вызывает `_redraw_neighbor_borders(coord)` синхронно, что перерисовывает border-тайлы 4 соседей (4 × 64 = 256 тайлов) за один кадр.

#### Изменение 3A: Defer `_redraw_neighbor_borders()` — dirty marking вместо синхронного redraw

В `_staged_loading_finalize()` (`chunk_manager.gd`, строки 1707–1710):

Было:
```gdscript
sub_usec = WorldPerfProbe.begin()
EventBus.chunk_loaded.emit(coord)
_redraw_neighbor_borders(coord)
WorldPerfProbe.end("ChunkStreaming.finalize.emit %s" % [coord], sub_usec)
```

Стало:
```gdscript
sub_usec = WorldPerfProbe.begin()
EventBus.chunk_loaded.emit(coord)
_enqueue_neighbor_border_redraws(coord)
WorldPerfProbe.end("ChunkStreaming.finalize.emit %s" % [coord], sub_usec)
```

Новый метод в `chunk_manager.gd`:
```gdscript
## Instead of synchronously redrawing all border tiles of 4 neighbors (256
## tiles, 20-49ms), mark dirty tiles and add neighbors to the progressive
## redraw queue. Border tiles will be processed by _tick_redraws() over
## the next 1-2 frames.
func _enqueue_neighbor_border_redraws(coord: Vector2i) -> void:
    var chunk_size: int = WorldGenerator.balance.chunk_size_tiles
    for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
        var neighbor_coord: Vector2i = _offset_chunk_coord(coord, dir)
        var neighbor_chunk: Chunk = _loaded_chunks.get(neighbor_coord) as Chunk
        if not neighbor_chunk:
            continue
        if not neighbor_chunk.is_terrain_phase_done():
            continue  # Neighbor hasn't drawn terrain yet, border will be drawn naturally
        var dirty: Dictionary = {}
        if dir == Vector2i.LEFT:
            for y: int in range(chunk_size):
                dirty[Vector2i(chunk_size - 1, y)] = true
        elif dir == Vector2i.RIGHT:
            for y: int in range(chunk_size):
                dirty[Vector2i(0, y)] = true
        elif dir == Vector2i.UP:
            for x: int in range(chunk_size):
                dirty[Vector2i(x, chunk_size - 1)] = true
        elif dir == Vector2i.DOWN:
            for x: int in range(chunk_size):
                dirty[Vector2i(x, 0)] = true
        neighbor_chunk.enqueue_dirty_border_redraw(dirty)
        ## Add to progressive redraw queue if not already there.
        if not _redrawing_chunks.has(neighbor_chunk):
            _redrawing_chunks.append(neighbor_chunk)
```

Новый метод в `chunk.gd`:
```gdscript
## Enqueue border tiles for deferred redraw. Called by ChunkManager when a
## new neighbor chunk is loaded and border seam tiles need updating.
## The actual redraw happens during the next progressive redraw tick.
func enqueue_dirty_border_redraw(dirty_tiles: Dictionary) -> void:
    _pending_border_dirty.merge(dirty_tiles, true)
```

И в `continue_redraw()` или в отдельном вызове из `_tick_redraws()` — проверка `_pending_border_dirty`:
```gdscript
## In _tick_redraws() after chunk.continue_redraw(), or as a separate step:
## If chunk has pending border dirty tiles, process them under budget.
if not chunk._pending_border_dirty.is_empty():
    chunk._redraw_dirty_tiles(chunk._pending_border_dirty)
    chunk._pending_border_dirty.clear()
```

Альтернативная реализация (проще): вместо нового механизма dirty queue, просто вызывать `_redraw_dirty_tiles()` внутри `_tick_redraws()` для чанков с pending borders. Это минимальное изменение, которое переносит 256-тайловый redraw из finalize в budgeted tick.

Обоснование: `_redraw_neighbor_borders()` вызывает `neighbor_chunk._redraw_dirty_tiles(dirty)` синхронно для 4 направлений × 64 тайла = 256 тайлов per-tile redraw. При ~100–200µs на тайл (terrain + cover + cliff layers) → 25–50ms. Перенос в progressive redraw queue размазывает эту работу по 1–2 кадрам.

Ожидаемый эффект: `ChunkStreaming.finalize.emit` с 20–49ms → < 2ms. Neighbor borders дорисовываются за 1–2 следующих кадра через `_tick_redraws()`.

Важно: `_redraw_neighbor_borders()` (строка 620) остаётся в коде для других call sites (mining seam, building placement). Удаляется только вызов из `_staged_loading_finalize()`.

#### Acceptance tests

- [ ] `ChunkStreaming.finalize.emit` < 5ms (вместо 20–49ms)
- [ ] `ChunkStreaming.phase2_finalize` < 10ms (вместо 19–49ms)
- [ ] При быстром беге: нет заметных frame hitches при загрузке новых чанков
- [ ] Border seam тайлы между чанками корректно отрисованы (нет визуальных артефактов на границах)
- [ ] `streaming_load` в FrameBudget summary < 4ms avg (контракт §2.2)
- [ ] Нет crash/assert при быстром перемещении по миру
- [ ] Нет crash/assert при переходе surface↔underground

#### Файлы, которые будут затронуты

- `core/systems/world/chunk_manager.gd`:
  - `_staged_loading_finalize()` — строки 1707–1710 (замена `_redraw_neighbor_borders` на `_enqueue_neighbor_border_redraws`)
  - Новый метод `_enqueue_neighbor_border_redraws()`
  - `_tick_redraws()` — добавление обработки `_pending_border_dirty` (если выбран вариант с tick processing)
- `core/systems/world/chunk.gd`:
  - Новая переменная `_pending_border_dirty: Dictionary = {}`
  - Новый метод `enqueue_dirty_border_redraw()`

#### Файлы, которые НЕ ДОЛЖНЫ быть затронуты

- `core/autoloads/world_generator.gd`
- `scenes/world/game_world.gd`
- `data/world/world_gen_balance.tres`
- `_redraw_neighbor_borders()` — метод остаётся без изменений (используется другими call sites)
- `docs/02_system_specs/world/DATA_CONTRACTS.md` — border redraw deferral это implementation detail, не contract change. Существующий инвариант `runtime_near_chunks_get_instant_terrain` не затрагивается.

---

## Порядок реализации и зависимости

```
Iteration 1 (gate + ring 2 defer + priority redraw) — независим, делается первым
Iteration 2 (warm-up + budget tuning)                — независим от 1, но лучше после 1
Iteration 3 (defer neighbor borders)                  — независим от 1 и 2
```

Рекомендуемый порядок: 1 → 2 → 3. Каждая итерация — отдельный closure report.

## Ожидаемый результат после всех итераций

| Метрика | Было | Станет | Контракт |
|---------|------|--------|----------|
| `first_playable` | 50727 ms | ~2500 ms | < 5000 ms ✓ |
| `Boot.redraw_terrain` | 957 ms | < 50 ms | < 50 ms ✓ |
| `ChunkStreaming.finalize.emit` | 20–49 ms | < 2 ms | — ✓ |
| `ChunkStreaming.phase2_finalize` | 19–49 ms | < 10 ms | < 20 ms ✓ |
| Progressive redraw steps per chunk | ~27 | ~16 | — |
| Boot loop iterations | ~2924 | ~200 | — |

## Required contract and API updates after implementation

Выполняются в рамках Iteration 1 (изменение 1E):

- `DATA_CONTRACTS.md`:
  - Boot Readiness layer: заменить `all_ring_0_and_ring_1_chunks_are_loaded_applied_and_flora_done` на `all_ring_0_and_ring_1_chunks_are_loaded_applied_and_terrain_done`
  - Boot Readiness layer: уточнить `flora_blocks_visual_complete_for_boot` — flora НЕ блокирует first_playable
  - Boot Readiness layer: добавить инварианты для ring 2 deferral и priority redraw

- `PUBLIC_API.md`: обновление НЕ требуется (signature и owner `is_boot_first_playable()` не меняются; семантика "first_playable = terrain ready" уже implied по PERFORMANCE_CONTRACTS §7).

## Out-of-scope

- Рефакторинг `_redraw_all()` в chunk.gd
- Оптимизация `_build_surface_chunk_native_data()` (33–55ms generation time)
- Изменение `load_radius` / `unload_radius`
- Flora native fallback
- Boot pipeline restructuring (покрыт boot_chunk_apply_budget_spec)
- VSync / frame rate cap настройки
- Параллельность worker compute (RUNTIME_MAX_CONCURRENT_COMPUTE уже увеличен до 4 в streaming_redraw_budget_spec Iteration 4)
