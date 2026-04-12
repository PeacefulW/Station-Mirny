# Ревью ChunkManager (`chunk_manager.gd`)
_Дата: 2026-04-12_

## Контекст

Полный анализ файла `core/systems/world/chunk_manager.gd` (316 КБ, ~7 000 строк GDScript).
Фокус: производительность в интерактивном и фоновом путях, нарушения SRP,
кандидаты для переноса в native C++.

---

## Общая оценка файла

Файл архитектурно зрелый: есть бюджетирование, compute→apply разделение,
WorkerThreadPool, adaptive tile budget с feedback-loop. Это хороший фундамент.

Проблема в масштабе: 316 КБ одного файла с 8+ несвязанными ответственностями.
Debug/forensics-код (~25% файла) исполняется в самом горячем цикле без guard.
Несколько алгоритмических деградаций в O(n)-операциях на интерактивном пути.

---

## Ответственности в одном файле

| Ответственность | Оценка масштаба |
|---|---|
| Стриминг чанков (загрузка/выгрузка) | ~200 строк |
| Визуальный планировщик (8 очередей, adaptive budget) | ~1 200 строк |
| Boot-пайплайн (first-playable gate, прогресс) | ~400 строк |
| Topology builder (BFS flood fill, commit-фаза) | ~800 строк |
| Debug / Forensics система (trace, incidents, overlay) | ~1 600 строк |
| Surface payload LRU-кэш | ~150 строк |
| Seam / Border fix очередь | ~250 строк |
| Underground fog | ~150 строк |

---

## Критические проблемы производительности

### 1. O(n) линейный скан в `_has_load_request` — горячий путь

**Строки 1394–1399:**
```gdscript
func _has_load_request(coord: Vector2i, z_level: int) -> bool:
    for request: Dictionary in _load_queue:   # O(n) при каждом вызове
        if request.get("coord", ...) == canonical_coord and ...
            return true
    return false
```

Вызывается в `_update_chunks` для каждой из ~121 координаты при радиусе загрузки 5
(`(2×5+1)² = 121 координата × размер очереди`) — на каждом пересечении границы чанка.

**Фикс**: добавить `_load_queue_set: Dictionary` (ключ `Vector3i(x, y, z)` → true),
поддерживать синхронно с `_load_queue`. `_has_load_request` становится O(1).

---

### 2. O(n) LRU-кэш: `find()` + `remove_at()` на каждый cache hit

**Строки 5813–5816:**
```gdscript
func _touch_surface_payload_cache_key(cache_key: Vector3i) -> void:
    var existing_index: int = _surface_payload_cache_lru.find(cache_key)  # O(n)
    if existing_index >= 0:
        _surface_payload_cache_lru.remove_at(existing_index)              # O(n) сдвиг
    _surface_payload_cache_lru.append(cache_key)
```

С лимитом `SURFACE_PAYLOAD_CACHE_LIMIT = 192` — при каждом обращении к кэшу чанка
выполняется до 192 сравнений + сдвиг памяти в массиве.

**Фикс**: добавить `_surface_payload_cache_lru_index: Dictionary` (Vector3i → int порядок),
тогда `find` за O(1). Актуальный LRU-evict — перебор dict по минимальному значению порядка.

---

### 3. `has_method()` в горячих обёртках — рефлексия в каждом вызове

**Строки 1314–1348** — паттерн повторяется в 7+ методах:
```gdscript
func _canonical_tile(tile_pos: Vector2i) -> Vector2i:
    if WorldGenerator and WorldGenerator.has_method("canonicalize_tile"):  # медленно
        return WorldGenerator.canonicalize_tile(tile_pos)
    return tile_pos
```

Эти обёртки вызываются в вложенных циклах: topology BFS, seam refresh, update_chunks.
`has_method()` — поиск по строке в таблице методов, не O(1).

**Фикс**: в `_deferred_init()` один раз закэшировать bool-флаги
(`_wg_has_canonicalize_tile`, `_wg_has_chunk_wrap_delta_x` и т.д.),
использовать флаги вместо повторных проверок.

---

### 4. Debug/Forensics система в горячем пути планировщика без guard

Каждый `_process_one_visual_task` вызывает:
- `_debug_note_visual_task_event(...)` — создание Dictionary + поиск trace context
- `_debug_upsert_visual_task_meta(...)` — форматирование строк + incident lookup
- `_debug_record_forensics_event(...)` — подпись `"%s|%s|%s|..."`, сравнение

Весь этот код работает в `_run_visual_scheduler` — самый горячий цикл в игре,
каждый кадр, без `OS.is_debug_build()` guard.

**Фикс**: bool-флаг `_debug_enabled = OS.is_debug_build()`, инициализируется
в `_deferred_init()`. Все `_debug_*` вызовы из планировщика оборачиваются в
`if _debug_enabled:`. В release-режиме нулевая стоимость.

---

## Серьёзные проблемы (деградация при росте контента)

### 5. `_sync_loaded_chunk_display_positions` — O(all) при каждом движении

**Строки 1388–1392:**
```gdscript
func _sync_loaded_chunk_display_positions(reference_chunk: Vector2i) -> void:
    for coord: Vector2i in _loaded_chunks:      # все чанки каждый раз
        _sync_chunk_display_position(chunk, canonical_reference)
```

Вызывается из `_check_player_chunk`, `_update_chunks`, `sync_display_to_player`,
`set_active_z_level`. При 100+ загруженных чанках — 100 вызовов на каждое пересечение.

**Фикс**: кэшировать `_last_display_sync_reference: Vector2i`, пропускать вызов
если `canonical_reference == _last_display_sync_reference`.

---

### 6. String-ключи для visual tasks — heap allocation в планировщике

**Строки 3571–3574:**
```gdscript
func _make_visual_task_key(coord: Vector2i, z_level: int, kind: int) -> String:
    return "%d:%d:%d:%d" % [coord.x, coord.y, z_level, kind]
```

Вызывается десятки раз за кадр при работе планировщика. Каждый вызов создаёт
новый String-объект на куче.

**Фикс**: `Vector3i(coord.x, coord.y, z_level * SHIFT + kind)` как ключ словаря —
быстрее строкового форматирования, нет heap allocation.

---

### 7. `_update_chunks` — сортировка и O(n×m) при каждом пересечении

**Строки 5131–5158:**
```gdscript
for coord: Vector2i in needed:
    if not _loaded_chunks.has(coord)
        and not _has_load_request(coord, _active_z)   # O(queue) на каждую координату
        ...
to_load.sort_custom(...)   # сортировка каждый раз
```

С фиксом из п.1 `_has_load_request` станет O(1). Сортировку дополнительно
оптимизировать через `if to_load.size() > 1:`.

---

### 8. Topology BFS — GDScript fallback-путь параллельно нативному C++

**Строки 6283–7000+** — `_process_topology_component_step` и цепочка методов:
BFS по mountain-тайлам всех загруженных чанков в GDScript. При радиусе 5
и чанке 16×16 — до ~30 000 тайлов.

Нативный C++ воркер (`MountainTopologyBuilder`) уже реализован, но GDScript-fallback
поддерживается параллельно — 800 строк дополнительной сложности.

**Фикс**: убрать GDScript-путь, сделать native единственным. При отсутствии
native — `push_error` с понятным сообщением о необходимости сборки gdextension.

---

### 9. `query_local_underground_zone` — BFS flood fill в GDScript на интерактивном пути

**Строки 2246–2303:** flood fill pocket-обнаружения без верхнего ограничения на
количество тайлов (только флаг `truncated`). Выполняется синхронно на главном потоке
в интерактивном пути.

**Фикс**: перенести BFS в C++ GDExtension (`WorldPrepassKernels` или
`UndergroundQueryKernels`) с жёстким лимитом 2048 тайлов на запрос.

---

### 10. `Array[Dictionary]` для задач планировщика — heap pressure

8 очередей хранят задачи как `Array[Dictionary]`. Dictionary — heap-allocation
на каждую задачу. При интенсивной загрузке многих чанков одновременно —
давление на GC.

**Фикс**: inner class `VisualTask` с typed полями. Заменить `Array[Dictionary]`
на `Array[VisualTask]` для всех 8 очередей.

---

## Архитектурные проблемы

### 11. Нарушение SRP — 316 КБ в одном файле

Предлагаемое разбиение:

```
chunk_manager.gd              — координатор: player pos, lifecycle, routing, public API
chunk_visual_scheduler.gd     — 8 очередей, adaptive budget, worker compute
chunk_debug_system.gd         — forensics, incident tracking, overlay data
chunk_stream_cache.gd         — surface payload LRU, flora hydration
chunk_seam_manager.gd         — cross-chunk border fix, seam refresh queue
```

Boot pipeline и topology builder достаточно изолированы через prefix-группы
(`_boot_*`, `_topology_*`) — выносить только если файл остаётся > 150 КБ
после разделения первых трёх компонентов.

---

### 12. Дублирование в lifecycle финализации

`_load_chunk_for_z` (строка 5180) и `_finalize_chunk_install` (строка 5929)
содержат идентичный финальный блок: EventBus emit, topology mark, border redraw,
debug emit. Это два параллельных пути с одинаковым кодом.

**Фикс**: `_load_chunk_for_z` делегирует финальный блок в `_finalize_chunk_install`.

---

### 13. Ручное переназначение алиаса `_loaded_chunks`

`_loaded_chunks = _z_chunks[_active_z]` переназначается в нескольких местах
(`set_active_z_level`, `_load_chunk_for_z`, `_finalize_chunk_install`).
Риск рассинхронизации при добавлении нового места изменения z.

**Фикс**: единственный метод `_set_active_loaded_chunks(z: int)` для переназначения.

---

### 14. Два параллельных staging-механизма

Boot использует `_staged_chunk`, `_staged_coord`, `_staged_z`, `_staged_data`.
Runtime использует `_gen_active_tasks`, `_gen_active_z_levels`, `_gen_builders`, `_gen_ready_queue`.
Оба механизма делают похожее — staging данных до применения на главном потоке.

Не является blocker'ом, но усложняет понимание и расширение boot/runtime handoff.

---

## Что перенести в native C++

| Кандидат | Приоритет | Обоснование |
|---|---|---|
| **Topology BFS** (mountain flood fill) | Высокий | Уже есть `MountainTopologyBuilder`. Убрать GDScript-fallback |
| **`query_local_underground_zone`** (BFS pocket) | Высокий | Вызывается в интерактивном пути, неограниченный размер |
| **LRU-кэш surface payload** | Средний | O(n) операции на горячем пути загрузки |
| **Tile coord canonicalization** | Низкий | `has_method()` рефлексия убирается кэшом флагов — нативный перенос необязателен |

---

## Итоговая таблица проблем

| ID | Проблема | Тип | Приоритет |
|----|----------|-----|-----------|
| P-01 | O(n) `_has_load_request` | perf, interactive | Критический |
| P-02 | O(n) LRU cache hit | perf, interactive | Критический |
| P-03 | `has_method()` в hot path | perf, interactive | Критический |
| P-04 | Debug код без guard в планировщике | perf, interactive | Критический |
| P-05 | O(all) display sync при движении | perf, interactive | Серьёзный |
| P-06 | String-ключи задач планировщика | perf, hot | Серьёзный |
| P-07 | Лишняя сортировка в `_update_chunks` | perf, interactive | Серьёзный |
| P-08 | GDScript topology fallback | perf, background | Серьёзный |
| P-09 | BFS pocket в GDScript | perf, interactive | Серьёзный |
| P-10 | `Array[Dictionary]` для задач | perf, GC | Умеренный |
| P-11 | Монолит 316 КБ, 8+ ответственностей | architecture | Умеренный |
| P-12 | Дублирование lifecycle финализации | architecture | Низкий |
| P-13 | Ручной алиас `_loaded_chunks` | architecture | Низкий |
| P-14 | Два staging-механизма | architecture | Низкий |

---

_Детальный план исправлений с итерациями, acceptance tests и порядком выполнения:_
_`docs/04_execution/chunk_manager_refactor_plan.md`_
