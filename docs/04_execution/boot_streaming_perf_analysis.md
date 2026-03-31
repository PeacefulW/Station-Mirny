# Анализ производительности: Boot загрузка и Runtime Streaming

**Дата:** 2026-03-31
**Источник:** godot.log (свежий после streaming_redraw_budget_spec)
**Замер:** новый мир, затем бег от спавна

---

## TL;DR

**Boot загрузка занимает 50.7 секунд до `first_playable`.**

Причина — не медленная генерация и не тяжёлый apply. Причина — архитектурная: 25 чанков конкурируют за progressive redraw в round-robin, а boot loop ждёт пока ring 0 дорисует cover+cliff. Ring 0 получает свою очередь каждый 25-й кадр. При ~1500µs бюджете на step и 16.7ms на кадр, это ~2200 кадров × 16.7ms = ~37 секунд только на ожидание дорисовки ring 0.

**Runtime streaming работает приемлемо по бюджету (streaming_redraw ~2.2ms avg), но `finalize.emit` даёт хитчи 20-49ms на чанк.**

---

## Ключевые метрики из лога

### Boot

| Метрика | Значение | Контракт/ожидание |
|---------|----------|-------------------|
| `first_playable` | **50727.9 ms** | < 5000 ms |
| `Boot.redraw_terrain (0,0)` | **957.5 ms** | < 50 ms |
| `queue_wait` (cumulative) | **28697.6 ms** | — |
| `compute` (25 chunks) | 985.9 ms | OK (worker threads) |
| `apply` (25 chunks) | 945.9 ms | OK if budgeted |
| Boot loop iterations | **~2924** | — |
| Boot loop iter time | 5-7 ms | — |
| Ring 2 apply per chunk | 25-58 ms | 8 ms budget |
| Frame time p99 (first 300) | 127.8 ms | < 33 ms |
| hitches (first 300 frames) | 8 | 0 |

### Runtime Streaming

| Метрика | Значение | Контракт |
|---------|----------|----------|
| `streaming_redraw` avg | 2.0-2.4 ms | < 4 ms ✓ |
| `streaming_load` peak | 3.7 ms | < 4 ms ✓ |
| `phase2_finalize` per chunk | **19-49 ms** | < 20 ms ✗ |
| `finalize.emit` per chunk | **19-48 ms** | — |
| `streaming_redraw_step.terrain` | **5-7 ms** | < 2 ms ✗ |
| `topology_rebuild` per frame | 2.0-3.2 ms | < 4 ms ✓ |
| FPS (steady state) | 60 | 60 ✓ |

---

## Корневые причины

### Причина 1: Round-robin progressive redraw разбавляет ring 0 (КРИТИЧЕСКАЯ)

**Наблюдение:** Boot loop крутится 2924 итерации. Все 25 чанков applied к iter ~748. Но `first_playable` наступает только на iter ~2924 — ещё **~2176 итераций чистого progressive redraw**.

**Механизм:**
1. После apply всех 25 чанков, `_redrawing_chunks` содержит 25 записей
2. `_boot_process_redraw_budget(2500)` вызывает `_process_chunk_redraws()` → pop front, 1 step, push back (round-robin)
3. Каждый step ограничен `REDRAW_TIME_BUDGET_USEC = 1500` (1.5ms), проверка **каждый тайл**
4. При ~150 тайлов за step и 4096 тайлов в чанке → ~27 steps на фазу
5. Ring 0 нужен cover (27 steps) + cliff (~27 steps) = ~54 steps для `is_gameplay_redraw_complete()`
6. Ring 0 получает свою очередь каждый 25-й кадр (round-robin из 25 чанков)
7. **54 × 25 = 1350 кадров** × 16.7ms = **22.5 секунд** только на cover+cliff ring 0
8. Плюс ring 1 terrain (8 чанков × 27 steps × 25 = ~5400 кадров) — но ring 1 terrain завершается параллельно
9. Boot loop yield'ит каждый кадр через `await get_tree().process_frame` (строка 274)

**Влияние:** Это ГЛАВНАЯ причина 50-секундной загрузки. Одна строка в `_boot_process_redraw_budget` уничтожает весь pipeline.

### Причина 2: `complete_terrain_phase_now()` для player chunk — 957ms (ВЫСОКАЯ)

**Наблюдение:** Первый чанк (0,0) получает `Boot.redraw_terrain: 957.49 ms`. Последующие terrain steps в runtime: 5ms.

**Механизм:** Первый `set_cell()` на TileMapLayer вызывает lazy-инициализацию: компиляцию шейдеров, подготовку атласов, аллокацию буферов. Это one-time cold-start стоимостью ~950ms. После инициализации per-tile cost падает в ~50 раз.

**Влияние:** 1-секундный хитч при загрузке. После имплементации streaming_redraw_budget_spec (Iteration 1) уменьшился с 1267ms до 957ms (без cover/cliff/flora), но всё ещё огромен.

### Причина 3: Boot gate слишком строгий для first_playable (ВЫСОКАЯ)

**Наблюдение:** `_boot_is_first_playable_slice_ready()` требует для ring 0: `is_gameplay_redraw_complete()` = terrain + cover + cliff.

**Механизм:** Cover и cliff — визуальные overlay'и. Игрок может начать играть с одним terrain. Текущий gate заставляет boot loop крутиться ещё ~35 секунд после того, как terrain готов.

### Причина 4: Ring 2 apply внутри boot loop (СРЕДНЯЯ)

**Наблюдение:** Все 25 чанков applied к iter ~748 ВНУТРИ boot loop.

**Механизм:**
- Ring 2 (16 чанков) gated за ring 0 `is_gameplay_redraw_complete()` через `_boot_has_pending_near_ring_work()`
- После ring 0 cover+cliff завершается, gate открывается, 16 ring 2 чанков apply'ятся (25-58ms каждый)
- **Каждый applied чанк добавляется в `_redrawing_chunks`**, увеличивая round-robin pool

Это создаёт positive feedback loop: чем больше чанков в redraw pool → тем реже ring 0 получает очередь → тем дольше boot.

### Причина 5: `finalize.emit` 20-49ms в runtime streaming (СРЕДНЯЯ)

**Наблюдение:**
```
ChunkStreaming.finalize.emit (63, -3): 43.30 ms
ChunkStreaming.finalize.emit (2, -3): 48.88 ms
```

**Механизм:** `EventBus.chunk_loaded.emit(coord)` + `_redraw_neighbor_borders(coord)` работают синхронно в finalize path. `_redraw_neighbor_borders()` вызывает per-tile операции на соседних чанках.

**Влияние:** Каждый новый streaming чанк даёт 20-49ms хитч. При быстром беге — серия таких хитчей.

### Причина 6: `REDRAW_TIME_BUDGET_USEC = 1500` проверяется каждый тайл (НИЗКАЯ)

**Наблюдение:** `Time.get_ticks_usec()` вызывается на КАЖДЫЙ обработанный тайл (check_interval = 1, строка 1426 chunk.gd).

**Механизм:** GDScript syscall overhead ~2-5µs × 150 тайлов = ~300-750µs чистых overhead на step. Это 20-50% от 1500µs бюджета.

---

## Предлагаемые исправления

### Fix 1: Приоритетный progressive redraw для ring 0-1 при boot (КРИТИЧЕСКИЙ)

**Что:** В `_boot_process_redraw_budget()`, обрабатывать ТОЛЬКО ring 0-1 чанки до достижения first_playable gate.

**Как:**
```gdscript
func _boot_process_redraw_budget(max_usec: int) -> void:
    var started_usec: int = Time.get_ticks_usec()
    # During boot, prioritize ring 0-1 chunks for first_playable
    var priority_chunks: Array[Chunk] = []
    var deferred_chunks: Array[Chunk] = []
    while not _redrawing_chunks.is_empty():
        var c: Chunk = _redrawing_chunks.pop_front()
        if _boot_get_chunk_ring(c.chunk_coord) <= BOOT_FIRST_PLAYABLE_MAX_RING:
            priority_chunks.append(c)
        else:
            deferred_chunks.append(c)

    # Process only priority chunks
    _redrawing_chunks = priority_chunks
    while not _redrawing_chunks.is_empty():
        _process_chunk_redraws()
        if Time.get_ticks_usec() - started_usec >= max_usec:
            break

    # Restore deferred chunks at the end
    _redrawing_chunks.append_array(deferred_chunks)
```

**Ожидаемый эффект:** Ring 0 получает очередь каждый 9-й кадр (из 9 ring 0-1 чанков) вместо каждого 25-го. Сокращает time-to-first_playable с ~35 секунд progressive до ~10 секунд.

**Файлы:** `core/systems/world/chunk_manager.gd` — `_boot_process_redraw_budget()`

---

### Fix 2: Ослабить first_playable gate для ring 0 (КРИТИЧЕСКИЙ)

**Что:** Изменить требование для ring 0 с `is_gameplay_redraw_complete()` на `is_terrain_phase_done()`. Cover/cliff — визуальные и не блокируют gameplay.

**Как:**
```gdscript
# В _boot_is_first_playable_slice_ready():
# Было:
if ring == 0 and not chunk.is_gameplay_redraw_complete():
    return false
# Стало:
if ring == 0 and not chunk.is_terrain_phase_done():
    return false
```

И аналогично в `_boot_has_pending_near_ring_work()`:
```gdscript
# Было:
if ring == 0 and not chunk.is_gameplay_redraw_complete():
    return true
# Стало:
if ring == 0 and not chunk.is_terrain_phase_done():
    return true
```

**Ожидаемый эффект:** first_playable наступает сразу после terrain_phase_now() для ring 0 + progressive terrain для ring 1. Это ~1-2 секунды вместо 50.

**Файлы:** `core/systems/world/chunk_manager.gd` — `_boot_is_first_playable_slice_ready()`, `_boot_has_pending_near_ring_work()`

**Риск:** Игрок увидит чанк (0,0) без cover/cliff overlay'ев на 0.5-2 секунды. Это допустимый degraded state по PERFORMANCE_CONTRACTS §7.

---

### Fix 3: Не apply'ить ring 2 внутри boot loop — отдать runtime (ВЫСОКИЙ)

**Что:** Boot loop apply'ит только ring 0-1 (9 чанков). Ring 2 (16 чанков) передаются runtime streaming через `_boot_start_runtime_handoff()` сразу после first_playable.

**Как:** В `_boot_apply_from_queue()`, добавить hard limit:
```gdscript
if _boot_get_chunk_ring(front_coord) > BOOT_FIRST_PLAYABLE_MAX_RING:
    break  # Defer to runtime
```

Вместо текущего:
```gdscript
if _boot_get_chunk_ring(front_coord) > BOOT_FIRST_PLAYABLE_MAX_RING and _boot_has_pending_near_ring_work():
    break
```

**Ожидаемый эффект:** Boot loop завершается после 9 чанков. ring 2 дорисуется после first_playable через runtime streaming. Сокращает boot loop с 2924 итераций до ~200-300.

**Файлы:** `core/systems/world/chunk_manager.gd` — `_boot_apply_from_queue()`

---

### Fix 4: Warm up TileMapLayer до boot terrain redraw (ВЫСОКИЙ)

**Что:** Перед `complete_terrain_phase_now()` для player chunk, сделать один dummy `set_cell()` + `erase_cell()` на каждом TileMapLayer, чтобы вызвать shader compilation и atlas preparation вне тайминга.

**Альтернатива:** Сделать terrain redraw player chunk тоже progressive (не вызывать `complete_terrain_phase_now()` вообще), а пока terrain рисуется — показать простой color placeholder вместо зелёного.

**Ожидаемый эффект:** Устраняет 957ms хитч. Если warm-up: первый тайл оплачивает cold-start, остальные быстрые. Если progressive: хитч размазывается по кадрам.

**Файлы:** `core/systems/world/chunk_manager.gd` или `core/systems/world/chunk.gd`

---

### Fix 5: Defer `_redraw_neighbor_borders()` из streaming finalize (СРЕДНИЙ)

**Что:** Вместо синхронного `_redraw_neighbor_borders(coord)` внутри `_staged_loading_finalize()`, добавлять dirty-тайлы соседей в очередь progressive redraw.

**Ожидаемый эффект:** finalize.emit с 20-49ms → < 2ms. Neighbor borders дорисовываются за 1-2 следующих кадра.

**Файлы:** `core/systems/world/chunk_manager.gd` — `_staged_loading_finalize()`

---

### Fix 6: Увеличить `REDRAW_TIME_BUDGET_USEC` и check interval (НИЗКИЙ)

**Что:** Изменить `REDRAW_TIME_BUDGET_USEC` с 1500 на 2500. Изменить check_interval с 1 на 4 (проверять время каждые 4 тайла вместо каждого).

**Ожидаемый эффект:** Каждый step обрабатывает ~300 тайлов вместо ~150. Количество steps на чанк уменьшается вдвое. Весь progressive redraw ускоряется в ~2 раза.

**Файлы:** `core/systems/world/chunk.gd` — константы `REDRAW_TIME_BUDGET_USEC`, `_process_redraw_phase_tiles()`

---

## Рекомендуемый порядок

```
Fix 2 (gate) + Fix 3 (ring 2 defer) → мгновенный эффект, boot < 5 секунд
Fix 1 (priority redraw)             → ускоряет ring 1 terrain progressive
Fix 4 (warm-up)                     → устраняет 957ms хитч
Fix 5 (defer neighbor borders)      → устраняет 20-49ms runtime хитчи
Fix 6 (budget tuning)               → ускоряет все progressive redraws
```

---

## Timeline boot loop (текущее состояние)

```
t=0.0s    Boot start
t=0.04s   3 worker tasks submitted
t=0.08s   First chunks computed (38ms worker threads)
t=1.0s    Chunk (0,0) applied + terrain_phase_now (957ms)
t=1.1s    Ring 1 chunks start applying (1 per frame)
t=1.4s    All ring 0-1 applied (9 chunks)
t=1.5s    Ring 0 progressive cover/cliff starts (round-robin 9→25 chunks)
t=2.0s    All 25 computed, ring 2 waiting in apply_queue
t=12.0s   Ring 0 cover+cliff done, gate opens for ring 2
t=13.0s   16 ring 2 chunks applied (added to _redrawing_chunks)
t=50.7s   All ring 0-1 progressive done → first_playable
```

## Timeline после Fix 2+3:

```
t=0.0s    Boot start
t=0.04s   3 worker tasks submitted
t=1.0s    Chunk (0,0) applied + terrain_phase_now (957ms)
t=1.1s    Ring 1 applies start
t=1.4s    All ring 0-1 applied
t=1.4s    Ring 1 terrain progressive starts (9 chunks in pool)
t=2.5s    All ring 1 terrain_phase_done → first_playable ✓
t=2.5s    Game starts. Ring 2 deferred to runtime.
```

**Итого: с 50.7 секунд до ~2.5 секунд.**
