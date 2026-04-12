---
title: ChunkManager — план рефакторинга и оптимизации
doc_type: execution
status: proposed
owner: engineering
source_of_truth: false
version: 1.0
last_updated: 2026-04-12
related_docs:
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../02_system_specs/world/DATA_CONTRACTS.md
  - ../00_governance/PUBLIC_API.md
---

# ChunkManager — план рефакторинга и оптимизации

Этот документ фиксирует все выявленные проблемы в `core/systems/world/chunk_manager.gd`
(316 КБ, ~7 000 строк, ревью от 2026-04-12) и определяет конкретные итерации исправлений.

Это execution-документ. Он не заменяет `DATA_CONTRACTS.md` или `PUBLIC_API.md`
как источник истины для архитектуры мира. Он только описывает, **что и в каком порядке менять**.

---

## Контекст проблемы

`chunk_manager.gd` вырос в монолитный файл с 8+ несвязанными ответственностями.
Часть проблем критична для runtime-производительности (O(n) в горячем пути),
часть — структурная (невозможность изолированного тестирования, debug-код в hot path).

Ни одна из проблем не является blocker'ом для текущей итерации разработки.
Но совокупность проблем создаёт риск деградации FPS при росте контента.

---

## Полный список выявленных проблем

### Критические (прямое влияние на FPS)

| ID | Проблема | Строки | Runtime class |
|----|----------|--------|---------------|
| P-01 | O(n) линейный скан `_has_load_request` через весь `_load_queue` | 1394–1399 | interactive |
| P-02 | O(n) LRU-кэш: `find()` + `remove_at()` на каждый cache hit | 5813–5816 | interactive |
| P-03 | `has_method()` рефлексия в горячих оборачивающих функциях | 1314–1348 | interactive |
| P-04 | Debug/Forensics код исполняется в `_run_visual_scheduler` без guard | 550–1200 | interactive |

### Серьёзные (деградация при росте контента)

| ID | Проблема | Строки | Runtime class |
|----|----------|--------|---------------|
| P-05 | `_sync_loaded_chunk_display_positions` проходит по всем чанкам при каждом движении | 1388–1392 | interactive |
| P-06 | String-форматирование ключей задач в планировщике (`"%d:%d:%d:%d"`) | 3571–3574 | interactive |
| P-07 | `_update_chunks` сортирует `to_load` при каждом пересечении границы | 5131–5158 | interactive |
| P-08 | Topology BFS — GDScript fallback-путь параллельно нативному C++ | 6283–7000+ | background |
| P-09 | `query_local_underground_zone` — BFS flood fill в GDScript | 2246–2303 | interactive |
| P-10 | `Array[Dictionary]` для задач планировщика — heap allocation per task | 119–128 | background |

### Архитектурные (maintainability, SRP)

| ID | Проблема | Масштаб |
|----|----------|---------|
| P-11 | Один файл содержит 8+ ответственностей, 316 КБ | весь файл |
| P-12 | Дублирование кода: `_load_chunk_for_z` и `_finalize_chunk_install` | строки 5180, 5929 |
| P-13 | `_z_chunks` + `_loaded_chunks` алиас переназначается вручную | множественные места |
| P-14 | Два параллельных механизма staging (boot `_staged_*` vs runtime `_gen_*`) | переменные 212–248 |

---

## Принципы выполнения

1. **Итерации независимы**: каждая итерация может быть реализована и проверена отдельно.
2. **Интерфейс не меняется**: все публичные методы ChunkManager сохраняют сигнатуры.
3. **Нет silent drift**: если итерация влияет на DATA_CONTRACTS или PUBLIC_API — обновить их.
4. **Минимальное изменение**: не рефакторить то, что не нужно для конкретного фикса.
5. **Сначала критическое**: P-01..P-04 до P-11..P-14.

---

## Итерация 1 — O(1) lookup для load queue (P-01)

**Проблема**: `_has_load_request` делает линейный обход `_load_queue` при каждом вызове.
Вызывается в `_update_chunks` для каждой из ~121 координаты при радиусе загрузки 5.
При каждом пересечении границы чанка: O(121 × queue_size) операций.

**Изменение**: Добавить `_load_queue_set: Dictionary` (ключ `Vector3i(x, y, z)` → true)
и поддерживать его синхронно с `_load_queue`.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd`

**Запрещённые файлы**:
- Все остальные.

**Задачи**:

1. Добавить в раздел private vars:
   ```gdscript
   var _load_queue_set: Dictionary = {}  ## Vector3i(x, y, z) -> true
   ```

2. В `_enqueue_load_request` после `_load_queue.append(...)`:
   ```gdscript
   _load_queue_set[Vector3i(canonical_coord.x, canonical_coord.y, z_level)] = true
   ```

3. В `_prune_load_queue` при удалении элементов из `_load_queue`:
   ```gdscript
   _load_queue_set.erase(Vector3i(request_coord.x, request_coord.y, request_z))
   ```

4. В `_process_load_queue` при `pop_front()`:
   ```gdscript
   _load_queue_set.erase(Vector3i(coord.x, coord.y, request_z))
   ```

5. Заменить тело `_has_load_request`:
   ```gdscript
   func _has_load_request(coord: Vector2i, z_level: int) -> bool:
       var canonical_coord: Vector2i = _canonical_chunk_coord(coord)
       return _load_queue_set.has(Vector3i(canonical_coord.x, canonical_coord.y, z_level))
   ```

6. В `_exit_tree` и `set_active_z_level` добавить `_load_queue_set.clear()` рядом с
   `_load_queue.clear()` / `_load_queue = filtered_queue`.

**Acceptance tests**:
- [ ] `_has_load_request` не делает итерацию по `_load_queue`.
- [ ] Игрок пересекает 10+ границ чанков подряд — нет просадки FPS по сравнению с baseline.
- [ ] После `_exit_tree` оба контейнера пусты.
- [ ] После `set_active_z_level` в `_load_queue_set` нет записей для старого z-уровня.

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Итерация 2 — O(1) LRU-кэш surface payload (P-02)

**Проблема**: `_touch_surface_payload_cache_key` вызывает `Array.find()` (O(n)) и
`Array.remove_at()` (O(n) сдвиг памяти) на каждый hit кэша чанка.
При лимите 192 — до 192 операций сравнения + сдвиг массива на каждое обращение.

**Изменение**: Добавить `_surface_payload_cache_lru_pos: Dictionary`
(ключ Vector3i → индекс в LRU-массиве) для O(1) поиска.
Фактически: держать только dict + порядковый счётчик без `find`.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd`

**Задачи**:

1. Добавить в private vars:
   ```gdscript
   var _surface_payload_cache_lru_index: Dictionary = {}  ## Vector3i -> int (insertion_order)
   var _surface_payload_cache_lru_counter: int = 0
   ```

2. Заменить `_touch_surface_payload_cache_key`:
   ```gdscript
   func _touch_surface_payload_cache_key(cache_key: Vector3i) -> void:
       _surface_payload_cache_lru_counter += 1
       _surface_payload_cache_lru_index[cache_key] = _surface_payload_cache_lru_counter
   ```

3. Заменить `_trim_surface_payload_cache` — вместо `pop_front()` найти ключ с
   минимальным `_surface_payload_cache_lru_index` значением и вытеснить его:
   ```gdscript
   func _trim_surface_payload_cache() -> void:
       while _surface_payload_cache.size() > SURFACE_PAYLOAD_CACHE_LIMIT:
           var oldest_key: Vector3i = INVALID_CHUNK_STATE_KEY
           var oldest_order: int = _surface_payload_cache_lru_counter + 1
           for k: Variant in _surface_payload_cache_lru_index:
               var order: int = int(_surface_payload_cache_lru_index[k])
               if order < oldest_order:
                   oldest_order = order
                   oldest_key = k as Vector3i
           if oldest_key == INVALID_CHUNK_STATE_KEY:
               break
           _surface_payload_cache.erase(oldest_key)
           _surface_payload_cache_lru_index.erase(oldest_key)
   ```

4. Убрать `_surface_payload_cache_lru: Array[Vector3i]` и все его использования.

5. В `_exit_tree` добавить очистку `_surface_payload_cache_lru_index.clear()`.

**Acceptance tests**:
- [ ] `_touch_surface_payload_cache_key` не вызывает `Array.find()` или `Array.remove_at()`.
- [ ] При 200+ обращениях к кэшу размер не превышает `SURFACE_PAYLOAD_CACHE_LIMIT`.
- [ ] Самый старый элемент вытесняется первым (LRU-семантика сохранена).

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Итерация 3 — Кэш флагов has_method() при инициализации (P-03)

**Проблема**: Функции-обёртки `_canonical_tile`, `_canonical_chunk_coord`,
`_offset_tile`, `_offset_chunk_coord`, `_tile_to_local` вызывают `WorldGenerator.has_method()`
при каждом своём вызове. `has_method()` — рефлексия по строке, медленнее прямого вызова.
Эти обёртки вызываются в вложенных циклах (topology BFS, seam refresh, update_chunks).

**Изменение**: Закэшировать результаты `has_method()` как bool-флаги в `_deferred_init()`.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd`

**Задачи**:

1. Добавить в private vars:
   ```gdscript
   var _wg_has_canonicalize_tile: bool = false
   var _wg_has_canonicalize_chunk_coord: bool = false
   var _wg_has_offset_tile: bool = false
   var _wg_has_offset_chunk_coord: bool = false
   var _wg_has_tile_to_local_in_chunk: bool = false
   var _wg_has_chunk_local_to_tile: bool = false
   var _wg_has_chunk_wrap_delta_x: bool = false
   ```

2. В `_deferred_init()` после проверки WorldGenerator:
   ```gdscript
   if WorldGenerator:
       _wg_has_canonicalize_tile = WorldGenerator.has_method("canonicalize_tile")
       _wg_has_canonicalize_chunk_coord = WorldGenerator.has_method("canonicalize_chunk_coord")
       _wg_has_offset_tile = WorldGenerator.has_method("offset_tile")
       _wg_has_offset_chunk_coord = WorldGenerator.has_method("offset_chunk_coord")
       _wg_has_tile_to_local_in_chunk = WorldGenerator.has_method("tile_to_local_in_chunk")
       _wg_has_chunk_local_to_tile = WorldGenerator.has_method("chunk_local_to_tile")
       _wg_has_chunk_wrap_delta_x = WorldGenerator.has_method("chunk_wrap_delta_x")
   ```

3. Заменить в каждой обёртке `WorldGenerator.has_method("X")` на `_wg_has_X`.
   Например:
   ```gdscript
   func _canonical_tile(tile_pos: Vector2i) -> Vector2i:
       if WorldGenerator and _wg_has_canonicalize_tile:
           return WorldGenerator.canonicalize_tile(tile_pos)
       return tile_pos
   ```

**Acceptance tests**:
- [ ] Ни одна из обёрток (`_canonical_tile` и т.д.) не вызывает `has_method()` во время игры.
- [ ] Флаги инициализируются корректно при старте (`grep _wg_has_ chunk_manager.gd`).
- [ ] Поведение обёрток не изменилось (возвращают те же значения что и раньше).

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Итерация 4 — Guard для debug/forensics кода в hot path (P-04)

**Проблема**: Debug-система (`_debug_forensics_*`, `_debug_visual_task_meta`,
`_debug_note_visual_task_event`, `_debug_upsert_visual_task_meta`) вызывается из
`_run_visual_scheduler` — самого горячего цикла в игре (каждый кадр).
Каждое событие задачи порождает: создание Dictionary, строковое форматирование,
поиск incident по контексту, сравнение сигнатур.

**Изменение**: Обернуть все вызовы debug-кода в планировщике в `OS.is_debug_build()`.
Не удалять код — только изолировать от release-пути.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd`

**Задачи**:

1. Добавить приватный флаг (инициализируется один раз):
   ```gdscript
   var _debug_enabled: bool = false
   ```
   В `_deferred_init()`:
   ```gdscript
   _debug_enabled = OS.is_debug_build()
   ```

2. Обернуть в `if _debug_enabled:` все вызовы из `_process_visual_task` и
   `_process_one_visual_task`:
   - `_debug_note_visual_task_event(...)`
   - `_debug_upsert_visual_task_meta(...)`
   - `_debug_note_budget_exhausted_trace_task()`

3. Обернуть в `if _debug_enabled:` все вызовы из `_run_visual_scheduler`:
   - `_maybe_log_player_chunk_visual_status(...)`
   - `_emit_visual_scheduler_tick_log(...)`

4. Обернуть `_debug_emit_chunk_event(...)` вызовы в `_load_chunk_for_z`,
   `_unload_chunk`, `_enqueue_load_request`, `_finalize_chunk_install`.

5. Обернуть вызовы `WorldRuntimeDiagnosticLog.emit_record(...)` из ChunkManager в
   `if _debug_enabled:`.

**Примечание**: `WorldPerfProbe.record(...)` и `WorldPerfProbe.end(...)` **не трогать** —
они используются для production телеметрии и должны работать в release.

**Acceptance tests**:
- [ ] В release-сборке (`OS.is_debug_build() == false`) ни один `_debug_*` метод не вызывается.
- [ ] В debug-сборке debug overlay и forensics работают как прежде.
- [ ] `WorldPerfProbe.end(...)` продолжает работать в обоих режимах.

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Итерация 5 — Vector3i ключи для visual task (P-06)

**Проблема**: `_make_visual_task_key` и `_make_visual_chunk_key` используют
строковое форматирование `"%d:%d:%d:%d"` на каждый доступ к очередям планировщика.
Строки — heap-объекты, создание + GC pressure на горячем пути.

**Изменение**: Заменить String-ключи на `Vector3i`-ключи где это возможно.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd`

**Задачи**:

1. Новая константа для кодирования kind в Vector3i:
   ```gdscript
   const VISUAL_KEY_KIND_SHIFT: int = 100000
   ```

2. Заменить `_make_visual_task_key` на возврат `Vector3i`:
   ```gdscript
   func _make_visual_task_key(coord: Vector2i, z_level: int, kind: int) -> Vector3i:
       return Vector3i(coord.x, coord.y, z_level * VISUAL_KEY_KIND_SHIFT + kind)
   ```

3. Заменить `_make_visual_chunk_key` на возврат `Vector3i`:
   ```gdscript
   func _make_visual_chunk_key(coord: Vector2i, z_level: int) -> Vector3i:
       return Vector3i(coord.x, coord.y, z_level)
   ```

4. Обновить типы всех Dictionary, индексированных этими ключами:
   - `_visual_task_versions`, `_visual_task_pending`, `_visual_task_enqueued_usec`
   - `_visual_apply_started_usec`, `_visual_convergence_started_usec`
   - `_visual_first_pass_ready_usec`, `_visual_full_ready_usec`
   - `_visual_compute_active`, `_visual_compute_waiting_tasks`, `_visual_compute_results`
   - `_visual_apply_feedback` (отдельный _make_visual_apply_feedback_key оставить строкой)
   - `_visual_chunks_processed_this_tick`

5. В debug-методах, где ключ конвертируется в строку для отображения — конвертировать
   явно через `str(key)` только внутри `if _debug_enabled:` блоков.

**Acceptance tests**:
- [ ] `_make_visual_task_key` не выполняет строковое форматирование.
- [ ] Планировщик работает корректно: задачи добавляются, находятся и удаляются по ключу.
- [ ] Нет регрессий в debug overlay при отображении task keys.

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Итерация 6 — Устранение GDScript fallback для topology (P-08)

**Проблема**: Существует два параллельных пути topology build:
- **Native** (`_native_topology_worker_available == true`): C++ `MountainTopologyBuilder`
- **GDScript fallback**: многофазный BFS на GDScript, ~800 строк

GDScript fallback поддерживается параллельно, усложняя код и создавая риск divergence.
По контракту производительности, topology BFS по 30 000+ тайлов в GDScript нарушает
интерактивный бюджет при отключённом native.

**Изменение**: Сделать native topology единственным поддерживаемым путём.
GDScript-fallback преобразовать в assert-путь с ошибкой при загрузке.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd`

**Задачи**:

1. В `_setup_native_topology_builder()`:
   ```gdscript
   if not _native_topology_worker_available:
       push_error("ChunkManager: MountainTopologyBuilder C++ extension not available. " +
                  "GDScript topology fallback is no longer supported. " +
                  "Build gdextension with scons before running.")
   ```

2. В `_process_topology_build()` убрать GDScript ветку — оставить только native:
   ```gdscript
   func _process_topology_build() -> bool:
       if not _is_native_topology_enabled():
           return false
       if _native_topology_dirty and _load_queue.is_empty() and not _has_pending_visual_tasks():
           _native_topology_builder.call("ensure_built")
           _native_topology_dirty = false
       return _native_topology_dirty
   ```

3. В `_tick_topology()` убрать ветки с `_process_topology_build_step()` и
   `_process_topology_retired_cleanup_step()` — они становятся мёртвым кодом.

4. Пометить GDScript-методы topology как `## @deprecated — удалить после Iteration 6`:
   `_process_topology_build_step`, `_advance_topology_build_start_step`,
   `_find_next_topology_seed`, `_process_topology_component_step`,
   `_finalize_topology_component_step`, `_process_topology_build_commit_step`,
   `_process_topology_retired_cleanup_step`, `_worker_rebuild_topology`,
   `_worker_build_topology_components`, `_worker_finalize_topology_component_step`.

5. **Не удалять** deprecated-методы в этой итерации — только добавить аннотацию.
   Удаление — в отдельной итерации после проверки в проде.

**Acceptance tests**:
- [ ] При запуске без gdextension — появляется `push_error` с понятным сообщением.
- [ ] При запуске с gdextension — topology строится через native path.
- [ ] `_is_native_topology_enabled()` возвращает `true` при нормальном запуске.
- [ ] Никакой GDScript BFS не запускается в `_process_topology_build`.

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Итерация 7 — Оптимизация `_update_chunks` (P-05, P-07)

**Проблема**: При каждом пересечении границы чанка:
1. `_sync_loaded_chunk_display_positions` проходит по всем загруженным чанкам O(all).
2. `_update_chunks` сортирует `to_load` при каждом вызове.

**Изменение**: Отложить sync display positions только для изменившихся чанков;
сортировать только если `to_load.size() > 1`.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd`

**Задачи**:

1. В `_update_chunks` добавить ранний выход для сортировки:
   ```gdscript
   if to_load.size() > 1:
       to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
           return _chunk_priority_less(a, b, center)
       )
   ```

2. В `_sync_loaded_chunk_display_positions` добавить кэш последней reference_chunk
   и пропускать вызов если reference не изменился:
   ```gdscript
   var _last_display_sync_reference: Vector2i = Vector2i(99999, 99999)

   func _sync_loaded_chunk_display_positions(reference_chunk: Vector2i) -> void:
       var canonical_reference: Vector2i = _resolve_display_reference_chunk(reference_chunk)
       if canonical_reference == _last_display_sync_reference:
           return
       _last_display_sync_reference = canonical_reference
       for coord: Vector2i in _loaded_chunks:
           var chunk: Chunk = _loaded_chunks[coord]
           _sync_chunk_display_position(chunk, canonical_reference)
   ```

3. Инвалидировать `_last_display_sync_reference` при `set_active_z_level` и
   при загрузке нового чанка через `_finalize_chunk_install`.

**Acceptance tests**:
- [ ] При неизменной позиции игрока `_sync_loaded_chunk_display_positions` не итерирует чанки.
- [ ] При пересечении границы sync выполняется ровно один раз.
- [ ] Чанки отображаются на правильных позициях при движении.
- [ ] Сортировка не выполняется когда `to_load.size() <= 1`.

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Итерация 8 — native `query_local_underground_zone` (P-09)

**Проблема**: `query_local_underground_zone` (строки 2246–2303) — BFS flood fill
в GDScript без верхнего ограничения на размер зоны (только `truncated` флаг).
Вызывается в интерактивном пути (при взаимодействии с underground pocket).

**Изменение**: Перенести BFS flood fill в C++ GDExtension.
Создать метод `query_local_pocket(seed_tile)` в `WorldPrepassKernels` или
отдельном `UndergroundQueryKernels`.

**Разрешённые файлы**:
- `gdextension/src/world_prepass_kernels.h`
- `gdextension/src/world_prepass_kernels.cpp`
- `core/systems/world/chunk_manager.gd`

**Задачи**:

1. В C++ реализовать BFS по terrain_bytes чанков:
   - вход: seed_tile (Vector2i), список загруженных chunk_bytes (через callback/snapshot)
   - выход: Dictionary {"tiles": PackedInt32Array, "chunk_coords": Array, "truncated": bool}
   - лимит: максимум 2048 тайлов на один запрос (предотвратить unbounded BFS)

2. Зарегистрировать метод в `register_types.cpp`.

3. В `chunk_manager.gd` заменить GDScript BFS-тело на:
   ```gdscript
   if _native_query_available:
       return _native_query_builder.call("query_local_pocket", seed_tile, ...)
   ```

4. Сохранить GDScript-путь как fallback с `push_warning` (в отличие от topology,
   этот путь менее критичен и fallback допустим на переходный период).

**Acceptance tests**:
- [ ] `query_local_underground_zone` не запускает GDScript BFS при наличии native.
- [ ] Результат совпадает с GDScript-путём для тестового pocket (regression test).
- [ ] При pocket > 2048 тайлов возвращается `truncated: true`.
- [ ] Производительность: < 0.5 мс для типичного pocket (≤ 200 тайлов).

**DATA_CONTRACTS.md**: требует проверки на изменение семантики `query_local_underground_zone`.
**PUBLIC_API.md**: если метод публичный — проверить контракт.

---

## Итерация 9 — Декомпозиция файла (P-11)

**Проблема**: 316 КБ, 8+ ответственностей в одном файле.
Невозможность изолированного тестирования. Debug-система смешана с core-логикой.

**Целевая структура** (все файлы в `core/systems/world/`):

```
chunk_manager.gd              — координатор: player pos, lifecycle, routing, public API
chunk_visual_scheduler.gd     — 8 очередей, adaptive budget, worker compute
chunk_debug_system.gd         — forensics, incident tracking, overlay data
chunk_stream_cache.gd         — surface payload LRU, flora hydration
chunk_seam_manager.gd         — cross-chunk border fix, seam refresh queue
```

Boot pipeline и topology builder уже достаточно изолированы через внутренние
prefix-группы (`_boot_*`, `_topology_*`) — их выносить только если файл
остаётся больше 150 КБ после разделения первых трёх компонентов.

**Порядок декомпозиции** (чтобы минимизировать риск регрессий):

**Шаг 9А — Debug system**:
- Создать `ChunkDebugSystem` класс
- Перенести все `_debug_*` методы и переменные
- ChunkManager получает ссылку `_debug_system: ChunkDebugSystem`
- Все внешние вызовы `get_chunk_debug_overlay_snapshot()` остаются на ChunkManager
  (делегируют в debug system)

**Шаг 9Б — Stream cache**:
- Создать `ChunkStreamCache` класс
- Перенести `_surface_payload_cache*`, flora hydration методы
- Передавать через dependency injection в конструкторе

**Шаг 9В — Seam manager**:
- Создать `ChunkSeamManager` класс
- Перенести `_pending_seam_refresh_*`, `_enqueue_seam_refresh_tile`,
  `_process_seam_refresh_queue_step`, `_apply_seam_refresh_tile`

**Шаг 9Г — Visual scheduler**:
- Создать `ChunkVisualScheduler` класс
- Перенести все `_visual_q_*`, `_visual_task_*`, `_visual_compute_*`
- Это наибольший риск: scheduler тесно связан с chunk state

**Правила декомпозиции**:
- Каждый шаг — отдельный PR/commit
- После каждого шага прогнать игру и проверить, что loading/debug/mining работают
- Публичный API ChunkManager не меняется

**Acceptance tests** (для каждого шага):
- [ ] Файл ChunkManager уменьшился в размере.
- [ ] Debug overlay показывает те же данные что и до шага.
- [ ] Mining, chunk loading, border fix работают без регрессий.
- [ ] `get_save_data()` / `set_saved_data()` работают без изменений.

**DATA_CONTRACTS.md**: обновить owner boundaries если изменились.
**PUBLIC_API.md**: обновить если публичные методы переехали в другой класс.

---

## Итерация 10 — Typed task structs (P-10)

**Проблема**: 8 очередей хранят задачи как `Array[Dictionary]`.
Dictionary — heap allocation на каждую задачу. При интенсивной загрузке (много
чанков одновременно) — давление на GC.

**Изменение**: Заменить Dictionary-задачи на typed class.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd` (или `chunk_visual_scheduler.gd` после Итерации 9Г)

**Задачи**:

1. Добавить inner class:
   ```gdscript
   class VisualTask:
       var chunk_coord: Vector2i
       var z: int
       var kind: int
       var priority_band: int
       var invalidation_version: int
       var camera_score: float
       var prepared_batch: Dictionary  # только при наличии
       var force_sync_border_fix: bool = false
       var force_inline_prepare: bool = false
       var wait_recorded: bool = false
   ```

2. Заменить `Array[Dictionary]` на `Array[VisualTask]` для всех 8 очередей.

3. Обновить `_build_visual_task` для возврата `VisualTask`.

4. Обновить `_pop_next_visual_task`, `_requeue_visual_task`, `_push_visual_task_front`.

**Acceptance tests**:
- [ ] Визуальный планировщик работает корректно (нет dropped tasks).
- [ ] Нет регрессий в adaptive budget feedback.
- [ ] Profiler показывает уменьшение GC allocations при интенсивной загрузке.

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Итерация 11 — Устранение дублирования (P-12, P-13)

**Проблема**:
- `_load_chunk_for_z` (строка 5180) и `_finalize_chunk_install` (строка 5929)
  содержат одинаковый финальный блок: EventBus emit, topology mark, debug emit.
- `_loaded_chunks = _z_chunks[_active_z]` алиас переназначается в нескольких местах
  вручную — риск рассинхронизации.

**Изменение**: Вынести дублирующийся финальный блок в `_finalize_chunk_install`,
`_load_chunk_for_z` должен его вызывать. Алиас `_loaded_chunks` инвалидировать через
единственный метод.

**Разрешённые файлы**:
- `core/systems/world/chunk_manager.gd`

**Задачи**:

1. В `_load_chunk_for_z` заменить финальный блок (строки 5246–5278) на вызов
   `_finalize_chunk_install(coord, z_level, chunk)`.

2. Удалить из `_load_chunk_for_z` дублирующийся код:
   `_sync_chunk_visibility_for_publication`, `_boot_on_chunk_applied`, topology mark,
   `_enqueue_neighbor_border_redraws`, `EventBus.chunk_loaded.emit`,
   `_debug_record_recent_lifecycle_event`, `_debug_emit_chunk_event`.

3. Создать `_set_active_loaded_chunks(z: int)` — единственный метод для переназначения
   `_loaded_chunks`:
   ```gdscript
   func _set_active_loaded_chunks(z: int) -> void:
       _loaded_chunks = _z_chunks.get(z, {})
       _last_display_sync_reference = Vector2i(99999, 99999)  # инвалидируем кэш
   ```

4. Заменить все прямые присвоения `_loaded_chunks = ...` на вызов `_set_active_loaded_chunks`.

**Acceptance tests**:
- [ ] Поведение `_load_chunk_for_z` идентично поведению до рефакторинга.
- [ ] `_finalize_chunk_install` покрывает оба пути (sync и async загрузка).
- [ ] Нет двойных EventBus emit при загрузке чанков.

**DATA_CONTRACTS.md / PUBLIC_API.md**: обновление не требуется.

---

## Порядок выполнения итераций

```
Фаза 1 — Критические perf-фиксы (независимы, можно параллельно):
  Итерация 1  — O(1) load queue lookup        [P-01]
  Итерация 2  — O(1) LRU кэш                  [P-02]
  Итерация 3  — Кэш флагов has_method()       [P-03]
  Итерация 4  — Debug guard в hot path        [P-04]

Фаза 2 — Серьёзные perf-улучшения (Фаза 1 должна быть завершена):
  Итерация 5  — Vector3i ключи task           [P-06]
  Итерация 7  — Оптимизация _update_chunks    [P-05, P-07]
  Итерация 6  — Удаление GDScript topology    [P-08]

Фаза 3 — Native переносы (требует C++ работы):
  Итерация 8  — native query_local_pocket     [P-09]

Фаза 4 — Структурный рефакторинг (требует стабильной Фазы 1+2):
  Итерация 9А — Debug system separation       [P-11]
  Итерация 9Б — Stream cache separation       [P-11]
  Итерация 9В — Seam manager separation       [P-11]
  Итерация 9Г — Visual scheduler separation   [P-11]
  Итерация 10 — Typed task structs            [P-10]
  Итерация 11 — Устранение дублирования       [P-12, P-13]
```

---

## Риски и ограничения

| Риск | Итерация | Митигация |
|------|----------|-----------|
| Рассинхронизация `_load_queue_set` и `_load_queue` | 1 | Единый helper для вставки/удаления |
| Сломанный debug overlay после Vector3i ключей | 5 | Тест overlay до и после |
| Регрессия topology при удалении GDScript пути | 6 | Убедиться что gdextension доступен |
| Потеря связей при декомпозиции файла | 9 | Шаг за шагом, тест после каждого шага |
| Typed structs ломают debug-метаданные | 10 | Выполнять после Итерации 9А |

---

## Метрики успеха

| Метрика | До | Цель |
|---------|-----|------|
| Размер `chunk_manager.gd` | 316 КБ | < 120 КБ (после Фазы 4) |
| `_has_load_request` сложность | O(n) | O(1) |
| LRU cache hit сложность | O(n) | O(1) |
| Debug код в release | исполняется | не исполняется |
| GDScript topology BFS | активен | удалён |
| `query_local_underground_zone` | GDScript BFS | native C++ |

---

## Зависимости

- Итерация 6 требует рабочего `MountainTopologyBuilder` в gdextension.
- Итерация 8 требует создания нового C++ метода (scope уточнить с командой).
- Итерации 9Г и 10 зависят от завершения Итерации 4 (debug guard должен быть на месте).
