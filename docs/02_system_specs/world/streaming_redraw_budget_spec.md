---
title: Streaming & Boot Redraw Budget Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-31
depends_on:
  - DATA_CONTRACTS.md
  - boot_chunk_apply_budget_spec.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
related_docs:
  - boot_chunk_readiness_spec.md
  - boot_visual_completion_spec.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
---

# Feature: Streaming & Boot Redraw Budget

## Design Intent

При текущей реализации игрок при быстром перемещении натыкается на зелёные (непрогруженные) чанки, а первая загрузка мира сопровождается хитчем ~1.3 секунды. Лог подтверждает:

- `Chunk._redraw_all (0, 0): 1267.81 ms` — boot player chunk полный redraw
- `streaming_load peak=49.6ms` — runtime finalize ring≤1 чанков
- `Frame time p99=135.1 ms, hitches=31` — первые 300 кадров
- `hitches=7` при беге, бюджет `10.4ms/6.0ms` — превышен вдвое

Корневая причина — `complete_redraw_now()` вызывается синхронно как при boot (для player chunk), так и при runtime streaming (для ring 0-1). Этот вызов выполняет `_redraw_all()`: clear 6 TileMapLayer + цикл 64×64×3 фазы = полный redraw за один кадр.

Это нарушает PERFORMANCE_CONTRACTS.md §1.4 (full chunk redraw запрещён в interactive path) и §7 (staged loading — допустима деградированная визуализация).

Данная спека определяет четыре конкретных изменения для устранения проблемы.

## Affected PERFORMANCE_CONTRACTS.md sections

- §1.4 Interactive whitelist: `complete_redraw_now()` в streaming finalize = full chunk redraw в background path, что провоцирует hitches.
- §2.2 Background budget targets: streaming peak 49.6ms при бюджете 2-4ms.
- §7 Staged Loading / Degraded mode: terrain без cover/cliff/flora — допустимый degraded state.

## Public API impact

Затрагиваемые safe entrypoints:
- `Chunk.complete_redraw_now(include_flora: bool = false) -> void` — вызов остаётся owner-only, но область применения сужается (только boot ring 0 без flora).
- `Chunk.complete_terrain_phase_now() -> void` — существующий метод, использование расширяется на streaming ring≤1 и boot ring 0.

Внешний API не меняется. `boot_load_initial_chunks()` сохраняет свою семантику. Новых public API не создаётся.

## Data Contracts — new and affected

### Новые слои данных

Не создаются. Все изменения затрагивают существующие слои.

### Затронутые слои

### Affected layer: Presentation

- Что меняется:
  - boot player chunk больше не получает полный `_redraw_all(include_flora=true)`. Вместо этого — `complete_terrain_phase_now()` (только terrain). Cover/cliff/flora уходят в progressive redraw.
  - runtime streaming ring≤1 чанки больше не получают `complete_redraw_now()`. Вместо этого — `complete_terrain_phase_now()`.
- Новые инварианты:
  - `complete_redraw_now()` НЕ вызывается в streaming runtime path.
  - при boot только ring 0 получает `complete_terrain_phase_now()`, остальные — progressive.
  - после `complete_terrain_phase_now()` чанк имеет `is_terrain_phase_done() == true` и может быть показан игроку. Cover/cliff/flora дорисовываются прогрессивно.
- Допустимое degraded state (PERFORMANCE_CONTRACTS §7):
  - чанк с terrain, но без cover/cliff/flora — допустим на 0.5-2 секунды.
- Кто адаптируется:
  - `ChunkManager` (boot apply и streaming finalize paths)
- Что НЕ меняется:
  - `Chunk` redraw phase progression logic
  - `Chunk.complete_redraw_now()` signature и реализация
  - `Chunk.complete_terrain_phase_now()` signature и реализация
  - progressive redraw budget job `_tick_redraws()`
  - chunk ownership, lifecycle states, topology

### Affected layer: Boot Readiness

- Что меняется:
  - boot player chunk visual state при `first_playable` — terrain ready вместо full redraw ready.
- Новые инварианты:
  - `first_playable` требует terrain phase done для ring 0, но НЕ требует full redraw complete.
- Что НЕ меняется:
  - `boot_complete` gate logic
  - readiness state machine

### Not affected

- World layer (terrain bytes, modifications)
- Mining layer
- Topology layer
- Reveal layer
- Boot Apply Queue layer (из boot_chunk_apply_budget_spec)
- Feature / POI Definitions

## Iterations

### Iteration 1 — Boot: terrain-only redraw для player chunk

Цель: убрать 1267ms хитч при загрузке мира.

Что делается:
- В `ChunkManager._boot_apply_from_queue()`: заменить `chunk.complete_redraw_now(true)` на `chunk.complete_terrain_phase_now()` для boot center chunk.
- Cover/cliff/flora для player chunk уходят в progressive redraw через существующий `_redrawing_chunks` + `_tick_redraws()`.

Что НЕ делается:
- Не меняется логика `complete_redraw_now()` в `chunk.gd`
- Не меняется `complete_terrain_phase_now()` в `chunk.gd`
- Не меняется boot readiness state machine
- Не меняются другие boot paths

Acceptance tests:
- [ ] `WorldPerf Boot.redraw_full` log line отсутствует или показывает < 50ms (вместо ~1267ms)
- [ ] `WorldPerf Boot.apply_chunk` для player chunk < 20ms
- [ ] При загрузке мира: terrain (земля/камни) виден сразу, cover/cliff/flora появляются прогрессивно в течение ~1-2 секунд
- [ ] Нет crash/assert при загрузке нового мира
- [ ] Нет crash/assert при загрузке сохранения
- [ ] `first_playable` gate не заблокирован (gameplay начинается как раньше)

Файлы, которые будут затронуты:
- `core/systems/world/chunk_manager.gd` — `_boot_apply_from_queue()`, ~строка 2796-2801

Файлы, которые НЕ ДОЛЖНЫ быть затронуты:
- `core/systems/world/chunk.gd`
- `core/autoloads/world_generator.gd`
- `scenes/world/game_world.gd`
- `data/world/world_gen_balance.tres`

### Iteration 2 — Streaming: terrain-only redraw для ring≤1

Цель: убрать 40-50ms хитчи при runtime streaming finalize, устранить зелёные чанки при быстром беге.

Что делается:
- В `ChunkManager._staged_loading_finalize()`: заменить `chunk.complete_redraw_now()` на `chunk.complete_terrain_phase_now()` для ring≤1 чанков.
- Обновить condition check: `is_gameplay_redraw_complete()` → `is_terrain_phase_done()`.

Что НЕ делается:
- Не меняется `_tick_redraws()` budget job
- Не меняется chunk visibility logic (строка 1732 уже проверяет `is_terrain_phase_done()`)
- Не меняется staged loading pipeline (generate→create→finalize)
- Не меняется `_tick_loading()` state machine

Acceptance tests:
- [ ] `WorldPerf ChunkStreaming.phase2_finalize` < 20ms (вместо 40-50ms)
- [ ] При быстром беге: нет зелёных (placeholder) чанков — terrain виден сразу
- [ ] Cover/cliff/flora на новых чанках появляются прогрессивно (допустимый degraded state)
- [ ] `streaming_load` в FrameBudget summary не превышает 4ms avg (контракт §2.2)
- [ ] Нет crash/assert при быстром перемещении по миру
- [ ] Нет crash/assert при переходе surface↔underground

Файлы, которые будут затронуты:
- `core/systems/world/chunk_manager.gd` — `_staged_loading_finalize()`, ~строки 1689-1692

Файлы, которые НЕ ДОЛЖНЫ быть затронуты:
- `core/systems/world/chunk.gd`
- `core/autoloads/world_generator.gd`
- `scenes/world/game_world.gd`
- `data/world/world_gen_balance.tres`

### Iteration 3 — Увеличить progressive redraw throughput

Цель: ускорить визуальную конвергенцию после iterations 1-2 (cover/cliff/flora теперь всегда progressive).

Что делается:
- В `data/world/world_gen_balance.tres`: изменить `chunk_redraw_rows_per_frame` с 8 на 16.
- Это увеличивает количество строк, обрабатываемых за один тик `_tick_redraws()`, с 512 до 1024 тайлов.

Обоснование бюджета:
- Текущий streaming_redraw budget: 2.0ms (зарегистрирован в `_register_budget_jobs()`).
- Текущий terrain redraw step: ~4-5ms на 512 тайлов (лог: `streaming_redraw_step.terrain: 4-5ms`).
- С 16 строками terrain step вырастет до ~8-10ms, но terrain phase — это один step на весь чанк. Cover/cliff/flora phases будут по ~2-4ms за step, что укладывается в бюджет 2ms envelope из PERFORMANCE_CONTRACTS §2.2.
- Результат: full progressive redraw одного чанка завершается за ~4 тика вместо ~8.

Что НЕ делается:
- Не меняется `_tick_redraws()` logic
- Не меняется `_register_budget_jobs()` бюджет
- Не меняется `Chunk.continue_redraw()` logic

Acceptance tests:
- [ ] `chunk_redraw_rows_per_frame == 16` в world_gen_balance.tres
- [ ] После загрузки мира: cover/cliff/flora на boot чанках полностью появляются за < 3 секунд (вместо ~5-6)
- [ ] `streaming_redraw` avg в FrameBudget summary < 4ms (контракт §2.2)
- [ ] Нет видимых frame hitches от redraw (p99 frame time < 20ms в steady state)

Файлы, которые будут затронуты:
- `data/world/world_gen_balance.tres` — `chunk_redraw_rows_per_frame`

Файлы, которые НЕ ДОЛЖНЫ быть затронуты:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`

### Iteration 4 — Увеличить параллельность worker compute

Цель: уменьшить задержку между запросом чанка и его готовностью к stage, чтобы streaming pipeline успевал за быстрым перемещением игрока.

Что делается:
- В `core/systems/world/chunk_manager.gd`: изменить `RUNTIME_MAX_CONCURRENT_COMPUTE` с 3 на 4.

Обоснование:
- Каждая задача генерации: 33-55ms в WorkerThreadPool.
- При 3 задачах: throughput ~1 чанк / 15ms. При быстром беге новые запросы приходят чаще.
- При 4 задачах: throughput ~1 чанк / 12ms. Достаточно для load_radius=2 при нормальной скорости бега.
- Worker tasks — чистые compute (никаких Node/scene tree), запускаются в detached builders, contention минимален.
- Не увеличиваем больше 4, потому что: (а) каждый builder аллоцирует native memory; (б) нужна проверка на целевом железе.

Что НЕ делается:
- Не меняется `_tick_loading()` state machine
- Не меняется `_submit_async_generate()` logic
- Не меняется `_collect_completed_runtime_generates()` logic
- Не меняется `_worker_generate()` logic

Acceptance tests:
- [ ] `RUNTIME_MAX_CONCURRENT_COMPUTE == 4` в chunk_manager.gd
- [ ] При быстром беге: количество видимых green placeholder чанков уменьшается по сравнению с iteration 2
- [ ] `gen_active_tasks.size()` достигает 4 при быстром перемещении (проверяется через лог или debug)
- [ ] Нет crash/assert от concurrent worker tasks
- [ ] Нет рост memory leak (проверяется: запуск 5 минут бега, memory stable)

Файлы, которые будут затронуты:
- `core/systems/world/chunk_manager.gd` — константа `RUNTIME_MAX_CONCURRENT_COMPUTE`, строка ~100

Файлы, которые НЕ ДОЛЖНЫ быть затронуты:
- `core/systems/world/chunk.gd`
- `core/autoloads/world_generator.gd`
- `data/world/world_gen_balance.tres`

## Порядок реализации и зависимости

```
Iteration 1 (boot redraw)     — независим, можно делать первым
Iteration 2 (streaming redraw) — независим от 1, но логически продолжает
Iteration 3 (redraw throughput) — зависит от 1+2, компенсирует переход на progressive
Iteration 4 (worker compute)   — независим, но проверять лучше после 2
```

Рекомендуемый порядок: 1 → 2 → 3 → 4. Каждая итерация — отдельный closure report.

## Required contract and API updates after implementation

После всех итераций обновить:
- `DATA_CONTRACTS.md`:
  - Presentation layer: добавить инвариант "complete_redraw_now() не вызывается в streaming runtime path"
  - Boot Readiness layer: уточнить что first_playable требует terrain phase, не full redraw
- `PUBLIC_API.md`:
  - Уточнить семантику `Chunk.complete_redraw_now()` — только boot ring 0 (если вообще)
  - Уточнить `Chunk.complete_terrain_phase_now()` — streaming ring≤1 и boot ring 0

## Out-of-scope

- Рефакторинг `_redraw_all()` в chunk.gd (разбиение на sub-phase)
- Оптимизация `_build_surface_chunk_native_data()` (33-55ms generation time)
- Изменение `load_radius` / `unload_radius`
- Flora native fallback (native flora empty → GDScript fallback)
- Boot pipeline restructuring (уже покрыт boot_chunk_apply_budget_spec)
- VSync / frame rate cap настройки (внешний фактор, не код проекта)
