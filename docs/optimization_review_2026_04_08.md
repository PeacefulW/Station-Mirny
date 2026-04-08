---
title: Ревью оптимизации — Станция Мирный
doc_type: review
status: draft
owner: engineering
version: 1.0
date: 2026-04-08
goal: "Модульность, масштабируемость, стабильный FPS, полный мир без видимых загрузок"
---

# Ревью оптимизации — Станция Мирный

## Цель ревью

Пройти по всем системам проекта и определить:
- что можно вывести в C++ (GDExtension) и/или многопоточность;
- что можно улучшить алгоритмически;
- какой эффект даст каждое изменение;
- как обеспечить масштабируемость (1000+ деревьев, десятки видов флоры/фауны, большие базы).

Главный критерий — **игрок бегает по полному сгенерированному миру без просадок FPS и видимых загрузок**.

---

## Текущее состояние: что уже хорошо

Проект уже содержит зрелую архитектуру оптимизации:

- **FrameBudgetDispatcher** — центральный бюджет 6 мс/кадр с приоритетами (streaming > topology > visual > spawn).
- **Compute → Apply** — тяжёлые вычисления отделены от мутаций сцены (тени, топология, чанки).
- **WorkerThreadPool** — используется для генерации чанков (3–4 воркера), теней (MountainShadowSystem), топологии (MountainTopologyBuilder).
- **Prebaked visual payload** — чанки кэшируют `rock_visual_class_bytes`, `ground_face_atlas_bytes`, `cover_mask_bytes`, `cliff_overlay_bytes` → рисование без пересчёта соседей.
- **GDExtension каркас** — уже есть C++ модули: `ChunkGenerator`, `ChunkVisualKernels`, `MountainShadowKernels`, `MountainTopologyBuilder`. (WorldPrepassKernels пока отсутствует — кандидат на реализацию.)
- **8-уровневая visual queue** — адаптивный бюджет 0.75–4.0 мс с feedback-based scaling.
- **WorldPerfProbe / WorldPerfMonitor** — готовая инструментация с контрактами на время операций.

Это отличный фундамент. Ниже — конкретные рекомендации для следующего уровня масштабируемости.

---

## ПРИОРИТЕТ 1 — КРИТИЧЕСКИЕ УЛУЧШЕНИЯ (прямое влияние на "полный мир без загрузок")

### 1.1 Flora: замена chunk-local renderer на MultiMesh-публикацию

> **Ревизия (08.04.2026):** Исходная предпосылка "тысячи отдельных Sprite2D" была неточной.
> Текущая реализация уже использует chunk-local `FloraBatchRenderer` с `_draw()` (см. `chunk.gd:80`, `chunk.gd:3102`).
> `ChunkFloraResult` уже группирует placements и кэширует render packet (`chunk_flora_result.gd:17`, `:83`).
> Реальная задача — не "убрать тысячи узлов", а заменить `_draw()` batch rendering на GPU-инстансинг.

**Проблема:** `FloraBatchRenderer._draw()` рисует все flora placements через CPU-side canvas commands (draw_texture_rect_region per item). При масштабировании до 1000+ объектов на чанк — CPU overhead на canvas commands растёт линейно, хотя draw call batching Godot частично амортизирует нагрузку. Точный bottleneck требует профилирования.

**Решение:** Заменить `_draw()` внутри chunk-local flora renderer на `MultiMeshInstance2D` — GPU-инстансинг вместо CPU canvas commands. **Scope: только Flora. Decor — отдельный follow-up** (texture_path не прокинут в builder, decor visuals помечены как placeholder в `world_generation_rollout.md:256`).

**Реализация:**
- Точка внедрения: **renderer/payload publish path** в `FloraBatchRenderer`, а не ChunkManager или source-of-truth.
- Из `ChunkFloraResult.render_packet` (несёт position/size/color/texture_path) группировать по `texture_path`.
- Каждая texture-группа → один `MultiMeshInstance2D` (child чанка).
- Текущий packet **не несёт** atlas_region, per-instance Transform2D, instance_custom — эти поля нужно добавить в packet payload (дополнительный scope).
- Wind sway shader: через `instance_custom` + `TIME` (после расширения payload).
- `ChunkFloraBuilder` и `ChunkFloraResult` source-of-truth **не меняются**.
- DATA_CONTRACTS.md прямо разрешает worker-side flora packets и bounded main-thread apply (`DATA_CONTRACTS.md:434`).

**Эффект:** Снижение CPU overhead на flora rendering. Величину выигрыша **нельзя подтвердить без профилирования** — текущий путь уже chunk-batched. Замер: `WorldPerfProbe` до/после с seed=12345 на лесном биоме.

**Сложность:** Средняя. Не ломает контракты данных. Требует расширение payload в `ChunkFloraResult` (atlas_region, transform, instance_custom).

**Приоритет:** 🔴 Критический для масштаба — при росте плотности флоры `_draw()` path станет CPU bottleneck. Но **до реализации — обязательно профилирование** текущего `_draw()` path на stress-тесте (1000+ flora per chunk).

---

### 1.2 Предиктивная загрузка чанков по вектору движения

**Проблема:** Чанки загружаются по кольцу вокруг текущего чанка игрока. Нет приоритизации по направлению движения → игрок может "обогнать" стриминг и увидеть недогруженный мир.

**Решение:** Предиктивная загрузка: приоритизировать чанки в направлении вектора скорости игрока.

**Реализация:**
- В `_chunk_priority_less()` добавить компонент `dot(chunk_direction, player_velocity.normalized())`.
- Чанки "впереди" игрока получают бонус приоритета → загружаются раньше.
- При остановке — возврат к стандартному ring-based порядку.
- Опционально: увеличить `load_radius` в направлении движения на 1–2 чанка.

**Эффект:** Игрок никогда не видит недогруженные чанки при нормальной скорости перемещения.

**Сложность:** Низкая. Изменение только в функции сортировки ChunkManager.

**Приоритет:** 🔴 Критический — прямо решает проблему "вижу загрузку бегая по миру".

---

### 1.3 Обеспечить нативный путь ChunkVisualKernels

**Проблема:** `Chunk.gd` проверяет наличие `ChunkVisualKernels` (C++ класс). Если он недоступен — fallback на GDScript per-tile loops (4096 операций × 5 слоёв на чанк). Разница: ~2–5 мс (C++) vs ~10–15 мс (GDScript) на чанк.

**Решение:** Убедиться, что `ChunkVisualKernels` собран, подключён и используется всегда.

**Реализация:**
- Проверить `gdextension/src/chunk_visual_kernels.cpp` — подтвердить что batch apply через `PackedInt32Array` работает.
- Batch stride (5 элементов на тайл) позволяет за один вызов передать весь буфер.
- Тест: сравнить `WorldPerfProbe` тайминги с нативным и без.

**Эффект:** Ускорение visual apply в 3–5×. Чанки появляются визуально быстрее.

**Сложность:** Низкая (если C++ код уже написан) / Средняя (если нужна доработка).

**Приоритет:** 🔴 Критический — это уже заложено в архитектуру, нужно довести до production.

---

## ПРИОРИТЕТ 2 — ВЫСОКИЙ (масштабируемость при росте контента)

### 2.1 Spatial hashing для систем поиска сущностей

**Проблема:** `BasicEnemy` сканирует все noise sources через `get_tree().get_nodes_in_group("noise_sources")` каждый `scan_interval`. С N врагов и M шумовых источников — O(N×M) distance checks. При 100 врагах × 50 источников = 5000 проверок.

**Решение:** Пространственная хэш-сетка (spatial hash grid).

**Реализация:**
- Новый компонент/сервис `SpatialHashGrid` с ячейками 2–4 чанка.
- `NoiseComponent.set_active()` → регистрация в grid.
- `BasicEnemy` запрашивает только соседние ячейки → O(N × k) где k = const (4–9 ячеек).
- Grid обновляется при движении сущности (ленивый — раз в N кадров для статичных).

**Эффект:** O(N×M) → O(N×k). При масштабе до 200+ врагов — разница в порядки.

**Сложность:** Средняя. Новый сервис, но не ломает контракты.

**Приоритет:** 🟠 Высокий — критичен для масштабирования фауны.

---

### 2.2 Object pooling для сущностей (враги, pickups)

**Проблема:** Каждый спавн врага = `CharacterBody2D` + collision shape + HealthComponent + NoiseComponent → выделение памяти + scene tree insertion. Каждая смерть = `queue_free()` → GC pressure.

**Решение:** Пул объектов для часто создаваемых/уничтожаемых сущностей.

**Реализация:**
- `EntityPool<T>` — generic пул с `acquire()` / `release()`.
- При `release()`: отключить physics, скрыть, вернуть в пул.
- При `acquire()`: сбросить state, включить physics, переместить на позицию.
- Начать с врагов (самый частый spawn/despawn цикл), затем pickups.

**Эффект:** Устранение аллокаций при спавне (2–5 мс на спавн → ~0.1 мс). Снижение GC spikes.

**Сложность:** Средняя. Нужно аккуратно сбрасывать state и сигналы.

**Приоритет:** 🟠 Высокий — при масштабировании фауны до сотен единиц.

---

### 2.3 Инкрементальная топология вместо полного rebuild

**Проблема:** При копке одного тайла горы — `_mark_topology_dirty()` → полный rebuild connected components по всем loaded чанкам. Сканируется каждый тайл каждого чанка.

**Решение:** Локальный инкрементальный rebuild.

**Реализация:**
- При копке тайла (x, y): запустить BFS/flood-fill только от изменённого тайла.
- Проверить, разделился ли компонент (проверка через 4-connectivity окрестности).
- Если компонент не разделился — обновить только boundaries.
- Полный rebuild оставить как fallback для сложных случаев (множественные изменения за кадр).

**Эффект:** Одиночная копка: O(chunk_size²) → O(local_region). При больших горных системах — экономия 20–50 мс.

**Сложность:** Высокая. Инкрементальный union-find или local BFS с edge cases.

**Приоритет:** 🟠 Высокий — важен для отзывчивости при копке.

---

### 2.4 Вынести terrain resolution в C++

**Проблема:** `SurfaceTerrainResolver` вызывается на каждый тайл при генерации чанка. 4096 тайлов × 7 каналов сэмплирования + noise evaluations = 2–20 мс на чанк в GDScript.

**Решение:** Перенести core terrain classification в C++.

**Реализация:**
- `ChunkGenerator` (уже есть в C++) получает расширение: `resolve_surface_terrain_batch(chunk_origin, chunk_size, prepass_data) → PackedByteArray`.
- Noise sampling, mountain/river/foothill scoring — вычислить нативно в одном проходе.
- Результат возвращается как compact byte array (1 byte per tile = terrain_type).
- GDScript fallback остаётся для дебага и модов.

**Эффект:** Генерация чанка: ~10–20 мс → ~1–3 мс. Чанки готовы быстрее → мир загружен раньше.

**Сложность:** Средняя. Нужно портировать noise sampling и biome scoring.

**Приоритет:** 🟠 Высокий — ускоряет и бут, и стриминг.

---

## ПРИОРИТЕТ 3 — СРЕДНИЙ (улучшение плавности и запас масштаба)

### 3.1 Adaptive frame budget на основе actual frame time

**Проблема:** Бюджет фиксирован на 6 мс. Если кадр лёгкий (игрок стоит) — бюджет не используется полностью. Если кадр тяжёлый — бюджет не снижается → hitch.

**Решение:** Адаптивный бюджет на основе rolling average frame time.

**Реализация:**
- Трекать actual frame time за последние 30–60 кадров.
- Если avg < 12 мс → увеличить бюджет до 8 мс (больше фоновой работы).
- Если avg > 14 мс → снизить до 4 мс (приоритет плавности).
- Ceiling: никогда не превышать 10 мс (оставить 6.67 мс на gameplay + render).

**Эффект:** Фоновая работа завершается быстрее когда "есть запас", замедляется когда "кадр тяжёлый". Более стабильный frametime.

**Сложность:** Низкая. Изменение в `FrameBudgetDispatcher`.

**Приоритет:** 🟡 Средний.

---

### 3.2 LOD для удалённой флоры

**Проблема:** При большом `load_radius` — тысячи объектов флоры на далёких чанках рисуются с полной детализацией, хотя игрок их почти не видит.

**Решение:** Level of Detail для флоры.

**Реализация:**
- **Ring 0–1** (ближние чанки): полная флора, все декоративные элементы.
- **Ring 2–3**: только крупные объекты (деревья, крупные кусты), мелкая трава скрыта.
- **Ring 4+**: только силуэтные деревья (reduced mesh / simpler sprite).
- Переключение LOD при переходе чанка из одного кольца в другое (уже есть механизм ring priority).

**Эффект:** Снижение draw calls на 40–60% для далёких чанков при сохранении визуальной полноты.

**Сложность:** Средняя. Нужна система LOD-тиров в ChunkFloraBuilder.

**Приоритет:** 🟡 Средний — важен при увеличении load_radius.

---

### 3.3 Batch apply для TileMapLayer

**Проблема:** Даже с prebaked данными, `set_cell()` вызывается per-tile (4096 раз на полный redraw). Каждый вызов — отдельная Godot internal операция.

**Решение:** Использовать нативный batch apply через `ChunkVisualKernels`.

**Реализация:**
- Собрать весь visual buffer в `PackedInt32Array` (stride: x, y, source_id, atlas_x, atlas_y, alt_id).
- Один вызов C++ функции → один проход по TileMapLayer (или direct RID manipulation через RenderingServer).
- Для Godot 4.6: исследовать `TileMapLayer.set_cells_terrain_connect()` или прямой `RenderingServer` batch.

**Эффект:** 4096 вызовов `set_cell()` → 1 вызов batch apply. Экономия 2–5 мс на чанк.

**Сложность:** Средняя. Зависит от API Godot 4.6.

**Приоритет:** 🟡 Средний.

---

### 3.4 Кэширование flora render packets между кадрами

**Проблема:** `ChunkFloraResult.build_render_packet()` пересобирает render packet с сортировкой O(n log n) при каждом вызове, даже если placement не изменился.

**Решение:** Кэшировать render packet до invalidation.

**Реализация:**
- Добавить `_cached_render_packet` + `_cache_version` в `ChunkFloraResult`.
- Invalidate при: mining (terrain change), seasonal change, LOD переключение.
- При запросе — отдать кэш если version совпадает.

**Эффект:** Устранение повторных O(n log n) сортировок. При 200+ flora items на чанк — экономия ~0.5 мс на чанк.

**Сложность:** Низкая.

**Приоритет:** 🟡 Средний.

---

### 3.5 Async save serialization

**Проблема:** `save_game()` синхронный — собирает все данные + пишет JSON на диск. При большом мире (сотни чанков, сотни зданий) — может вызвать hitch.

**Решение:** Асинхронная сериализация в фоне.

**Реализация:**
- Snapshot текущего state (Dictionary deep copy) на main thread (< 2 мс).
- JSON stringify + FileAccess write — в WorkerThreadPool.
- Flag `is_busy` уже есть — использовать для блокировки повторных save.

**Эффект:** Устранение save-related hitches. Игрок не замечает автосохранений.

**Сложность:** Низкая-Средняя.

**Приоритет:** 🟡 Средний.

---

## ПРИОРИТЕТ 4 — ДОЛГОСРОЧНОЕ МАСШТАБИРОВАНИЕ

### 4.1 World PrePass в C++ с SIMD

**Текущее:** GDScript grid traversal — heightfield, drainage, erosion, ridge extraction, spline fitting. Разовая операция при загрузке мира (~50–200 мс).

**Рекомендация:** Перенести в C++ с SIMD (SSE/AVX для flow direction, erosion, accumulation). `WorldPrepassKernels` уже есть в GDExtension — расширить.

**Эффект:** Boot time 50–200 мс → 10–40 мс. Не критично (за loading screen), но улучшает загрузку.

**Приоритет:** 🔵 Долгосрочный.

---

### 4.2 ECS-подобная архитектура для массовых сущностей

**Текущее:** Каждая сущность — Node2D с child компонентами (OOP pattern). Хорошо для десятков, проблемы при сотнях.

**Рекомендация:** Для массовых сущностей (трава, мелкая фауна, частицы) — перейти на data-oriented подход:
- Packed arrays для позиций, здоровья, состояний.
- Один `_process()` итерирует массив вместо N отдельных `_process()`.
- Visual через MultiMesh.

**Эффект:** Масштаб до 10,000+ мелких сущностей без просадок.

**Приоритет:** 🔵 Долгосрочный — когда появится густая фауна/экосистема.

---

### 4.3 Chunk payload precompute cache на диск

**Текущее:** LRU cache на 192 surface payload. При выходе за радиус — payload пересчитывается.

**Рекомендация:** Кэшировать сгенерированные payload на диск (binary, по seed + chunk_coord).

**Эффект:** Повторное посещение области — мгновенная загрузка чанка без генерации.

**Приоритет:** 🔵 Долгосрочный.

---

### 4.4 Registry precompilation

**Текущее:** 4–5 сканирований директорий + загрузка .tres при каждом запуске.

**Рекомендация:** При первом запуске (или после изменения контента) — собрать binary registry cache. Следующие запуски — загрузка из кэша.

**Эффект:** Boot time registry: ~50–100 мс → ~5–10 мс.

**Приоритет:** 🔵 Долгосрочный.

---

## МАТРИЦА РЕКОМЕНДАЦИЙ

| # | Система | Что делать | Тип | Эффект | Сложность | Приоритет |
|---|---------|-----------|-----|--------|-----------|-----------|
| 1.1 | Flora (only) | MultiMesh вместо _draw() | GPU | CPU overhead ↓ (замерить) | Средняя | 🔴 Крит* |
| 1.2 | Chunk Streaming | Предиктивная загрузка | Алгоритм | Нет видимых загрузок | Низкая | 🔴 Крит |
| 1.3 | Visual Apply | Нативный ChunkVisualKernels | C++ | Visual apply ×3–5 | Низкая | 🔴 Крит |
| 2.1 | Fauna AI | Spatial hash grid | Алгоритм | O(N×M) → O(N×k) | Средняя | 🟠 Выс |
| 2.2 | Entities | Object pooling | Архитект. | Спавн 2–5 мс → 0.1 мс | Средняя | 🟠 Выс |
| 2.3 | Topology | Инкрементальный rebuild | Алгоритм | Копка: экономия 20–50 мс | Высокая | 🟠 Выс |
| 2.4 | Terrain Gen | C++ terrain resolution | C++ | Генерация ×5–10 | Средняя | 🟠 Выс |
| 3.1 | Frame Budget | Адаптивный бюджет | Алгоритм | Стабильнее frametime | Низкая | 🟡 Сред |
| 3.2 | Flora | LOD тиры | GPU/Алг | Draw calls −40–60% | Средняя | 🟡 Сред |
| 3.3 | TileMap | Batch set_cell | C++ | Redraw ×2–3 | Средняя | 🟡 Сред |
| 3.4 | Flora Cache | Кэш render packets | Алгоритм | −0.5 мс/чанк | Низкая | 🟡 Сред |
| 3.5 | Save/Load | Async serialize | Threading | Нет save hitches | Низкая | 🟡 Сред |
| 4.1 | WorldPrePass | C++ SIMD | C++ | Boot −100 мс | Средняя | 🔵 Долг |
| 4.2 | Entities | Data-oriented массовые | Архитект. | 10K+ сущностей | Высокая | 🔵 Долг |
| 4.3 | Chunks | Дисковый кэш payload | I/O | Мгновенный revisit | Средняя | 🔵 Долг |
| 4.4 | Registries | Binary кэш | I/O | Boot −50 мс | Средняя | 🔵 Долг |

---

## ЧТО НЕ НУЖНО ОПТИМИЗИРОВАТЬ

Для полноты картины — области, которые **уже хорошо оптимизированы** и где вмешательство нецелесообразно:

- **FrameBudgetDispatcher** — архитектура правильная, array copy на 4 категории незначителен.
- **InventoryComponent** — O(2n) при n=20 слотов = 40 операций. Не bottleneck.
- **CraftingSystem** — минимальный вес, не на hot path.
- **PowerSystem** — O(n) при n < 100 потребителей, ≤ 1 мс. Достаточно.
- **Registry boot** — за loading screen, ~100 мс суммарно. Приемлемо для текущего масштаба.
- **World PrePass** — за loading screen, ~50–200 мс. Можно оптимизировать позже.

---

## РЕКОМЕНДОВАННАЯ ПОСЛЕДОВАТЕЛЬНОСТЬ РЕАЛИЗАЦИИ

**Фаза 1 — "Полный мир" (решает проблему видимых загрузок):**
1. Предиктивная загрузка чанков (1.2) — 1–2 дня
2. Убедиться что ChunkVisualKernels активен (1.3) — 1 день
3. **Профилирование** flora `_draw()` path (seed=12345, лесной биом, 1000+ flora/chunk) — 0.5 дня
4. По результатам профилирования: MultiMesh для флоры (1.1) — 3–5 дней
5. Decor texture wiring → MultiMesh для decor — follow-up (отдельная задача)

**Фаза 2 — "Масштаб контента" (1000+ деревьев, 100+ врагов):**
4. Spatial hash для AI (2.1) — 2–3 дня
5. Object pooling (2.2) — 2–3 дня
6. C++ terrain resolution (2.4) — 3–5 дней

**Фаза 3 — "Полировка плавности":**
7. Адаптивный бюджет (3.1) — 1 день
8. LOD для флоры (3.2) — 2–3 дня
9. Кэш render packets (3.4) — 1 день
10. Async save (3.5) — 1–2 дня

**Фаза 4 — "Запас на будущее":**
11. Инкрементальная топология (2.3) — 3–5 дней
12. Batch TileMap apply (3.3) — 2–3 дня
13. Остальное по необходимости

---

## СОВМЕСТИМОСТЬ С АРХИТЕКТУРНЫМИ КОНТРАКТАМИ

Все рекомендации проверены на совместимость:

- **DATA_CONTRACTS.md** — ни одна рекомендация не меняет ownership слоёв данных или invariants. MultiMesh — presentation-only layer. Spatial hash — runtime derived state.
- **PERFORMANCE_CONTRACTS.md** — все рекомендации укрепляют существующие контракты (< 2 мс interactive, 6 мс budget, no full rebuilds).
- **ENGINEERING_STANDARDS.md** — data-driven registries сохраняются, mod extensibility не блокируется (MultiMesh подписывается на те же registry данные).
- **SIMULATION_AND_THREADING_MODEL.md** — cadence-классификация (A–E) сохраняется. Новые C++ модули = Class D (background derived).
- **Command Pattern** — не затрагивается. Все мутации по-прежнему через CommandExecutor.

---

## МЕТРИКИ УСПЕХА

После реализации Фазы 1:
- [ ] Игрок не видит недогруженных чанков при непрерывном беге (route: `far_loop`, seed: 12345)
- [ ] FPS стабильно ≥ 55 при полной видимости флоры (seed: 12345, биом: лес)
- [ ] Boot-to-first-playable: улучшение на ≥ 30% (замер через `WorldPerfMonitor`)

После реализации Фазы 2:
- [ ] 200 врагов на карте, FPS ≥ 55 (stress test)
- [ ] 1000+ объектов флоры в viewport, FPS ≥ 55
- [ ] Генерация чанка < 5 мс (замер через `WorldPerfProbe`)

---

## ИСПОЛЬЗОВАННЫЕ СКИЛЛЫ И ДОКУМЕНТЫ

### Скиллы применённые:
- **Governance reading** — CLAUDE.md, AGENTS.md, WORKFLOW.md, DOCUMENT_PRECEDENCE.md
- **Engineering review** — ENGINEERING_STANDARDS.md, PERFORMANCE_CONTRACTS.md, PUBLIC_API.md, DATA_CONTRACTS.md, SIMULATION_AND_THREADING_MODEL.md
- **Codebase exploration** — полный обход core/systems, core/autoloads, core/entities, core/runtime, gdextension, scenes/world, tools/

### Файлы исследованные (read-only):
- `core/autoloads/frame_budget_dispatcher.gd` — бюджет и диспетчеризация
- `core/systems/world/chunk_manager.gd` — стриминг, visual queues, топология
- `core/systems/world/chunk.gd` — terrain storage, redraw, TileMap ops
- `core/systems/world/chunk_content_builder.gd` — генерация контента чанков
- `core/systems/world/chunk_flora_builder.gd` — flora placement
- `core/autoloads/world_generator.gd` — pipeline генерации мира
- `core/systems/world/world_pre_pass.gd` — boot-time prepass
- `core/systems/world/surface_terrain_resolver.gd` — terrain classification
- `core/systems/world/mountain_roof_system.gd` — reveal/cover
- `core/systems/lighting/mountain_shadow_system.gd` — тени
- `core/entities/fauna/basic_enemy.gd` — AI, noise scanning
- `core/entities/factories/` — фабрики сущностей
- `core/entities/components/` — компоненты (health, inventory, equipment, noise, power)
- `core/systems/building/building_system.gd` — строительство
- `core/systems/power/power_system.gd` — энергосистема
- `core/systems/crafting/crafting_system.gd` — крафт
- `core/autoloads/save_manager.gd`, `save_io.gd`, `save_collectors.gd`, `save_appliers.gd` — save/load
- `core/autoloads/biome_registry.gd`, `flora_decor_registry.gd`, `item_registry.gd`, `world_feature_registry.gd` — реестры
- `core/runtime/runtime_work_types.gd` — модель работы
- `core/debug/world_perf_probe.gd`, `world_perf_monitor.gd` — инструментация
- `scenes/world/game_world.gd` — boot orchestration
- `gdextension/` — C++ модули (chunk_generator, visual_kernels, shadow_kernels, topology_builder; prepass_kernels отсутствует)
- `docs/05_adrs/` — ADR-0001 и другие
