# Станция «Мирный» — Фундамент производительности v1.1

> **СТОП. Если ты ИИ-агент и собираешься писать код, который:**
> - создаёт/загружает/рендерит чанки
> - работает с тайлами (mining, building, terrain)
> - обновляет визуальные слои (cover, shadow, cliff, fog)
> - спавнит сущности (фауна, деревья, ресурсы, враги)
> - пересчитывает кеши (topology, pathfinding, room detection)
> - делает что-либо в цикле по тайлам или нодам
> - работает с native/C++ bridge
>
> **→ Прочитай этот документ ПОЛНОСТЬЮ перед написанием кода.**
> **Нарушение этих правил = лаги = переделка.**

---

## 0. Почему этот документ существует

При 60 FPS у нас **16.6 мс на весь кадр**. Один чанк = 64×64 = 4096 тайлов. При `load_radius = 2` загружено 25 чанков = 102 400 тайлов. Любая операция, которая перебирает «все тайлы» или «все чанки» синхронно — убивает фреймрейт.

Этот документ устанавливает **архитектурные правила**, которые исключают **синхронные hitch/spike в gameplay path** как класс проблем. Не «мы оптимизируем потом», а «система спроектирована так, чтобы тяжёлая работа не попадала в интерактивный путь игрока».

---

## 1. Три класса работы (обязательная классификация)

**Каждая операция в игре относится к одному из трёх классов. Перед написанием кода — определи класс.**

### 1.1 Boot-time work (загрузка)

**Когда:** под loading screen, один раз при старте мира или загрузке сохранения.

**Что сюда входит:**
- генерация стартового пузыря чанков
- первичный расчёт topology/masks/caches
- tileset/material warmup
- загрузка Registry, данных модов

**Правила:**
- можно тратить сколько угодно времени (loading screen покрывает)
- должно быть атомарным и предсказуемым
- результат кешируется, не пересчитывается в runtime

### 1.2 Background work (фоновая работа)

**Когда:** каждый кадр, параллельно с геймплеем.

**Что сюда входит:**
- подготовка соседних чанков (streaming)
- progressive redraw тайлов
- rebuild topology после изменений
- обновление shadow/cover/cliff слоёв
- пересчёт pathfinding-кешей
- подготовка room detection
- спавн декораций, деревьев, ресурсных нод

**Правила:**
- СТРОГО по time budget (см. секцию 2)
- через очередь задач (dirty queue)
- порциями (N элементов за кадр)
- с degraded mode (показать незавершённый, но приемлемый результат)

### 1.3 Interactive work (реакция на действия игрока)

**Когда:** на удар кирки, шаг, установку здания, открытие двери, крафт.

**Что сюда входит:**
- изменение 1 тайла
- обновление 8 соседей
- добавление/удаление 1 постройки
- пересчёт 1 ячейки сетки
- спавн 1 предмета/эффекта

**Правила:**
- МАКСИМУМ 2 мс на всю цепочку
- только локальные изменения (dirty region, не full rebuild)
- тяжёлые последствия (topology, shadows, cover) → помечаются dirty и уходят в Background work
- НИКОГДА не вызывать full rebuild чего-либо

### 1.4 Разрешённые синхронные операции (whitelist)

Не вся синхронная работа запрещена. В Interactive path допустимы только **локальные O(1) / O(9)** операции.

**Разрешено синхронно:**
- изменить 1 тайл terrain
- обновить до 8 соседей вокруг тайла
- создать/удалить 1 lightweight node
- переключить state flag / animation / visibility у 1 объекта
- пересчитать 1 ячейку сетки
- добавить элемент в dirty queue
- отправить событие в `EventBus`, если обработчики не делают тяжёлую работу синхронно

**Запрещено синхронно:**
- full rebuild чанка
- full rebuild topology
- полный пересчёт shadow/cover/cliff/fog слоя
- массовое создание/удаление нод
- полный обход всех loaded chunks / all tiles / all entities

Если операция неочевидна — считать её **запрещённой**, пока не доказано обратное профилированием.

---

## 2. Performance Contracts (бюджеты по системам)

### 2.1 Бюджет одного кадра (16.6 мс при 60 FPS)

```
Движок Godot (рендер, физика, ввод):  ~4-6 мс
Игровая логика (_process):            ~2-3 мс
Background jobs (суммарно):           ~4-6 мс
Запас:                                ~2-4 мс
```

### 2.2 Бюджеты background jobs

```
Chunk streaming (загрузка/выгрузка):   2-4 мс/кадр
Topology rebuild (инкрементальный):    1-2 мс/кадр
Visual rebuild (cover/shadow/cliff):   1-2 мс/кадр
Entity spawn (деревья, ресурсы):       1-2 мс/кадр
```

Суммарно background jobs не должны превышать **6 мс/кадр**. `FrameBudgetDispatcher` распределяет бюджет между зарегистрированными системами.

### 2.3 Контракты на интерактивные операции

Это **контракты для gameplay path**. Они описывают максимально допустимое время **синхронной части** операции и **не включают** отложенную background-работу, ушедшую в dirty queue.

| Операция | Лимит | Что входит в синхронную часть |
|----------|-------|-----------|
| Mine tile (удар кирки) | < 2 мс | изменить тайл + пометить dirty + drop item |
| Place building | < 2 мс | создать ноду + обновить grid + пометить dirty |
| Remove building | < 2 мс | удалить ноду + обновить grid + пометить dirty |
| Enter mountain (вход в гору) | < 4 мс | определить mountain_key + поставить в очередь cover update |
| Player step (один шаг) | < 1 мс | обновить позицию + проверить indoor status |
| Craft item | < 1 мс | проверить + удалить inputs + создать output |
| Open/close door | < 1 мс | переключить state + пометить room dirty |

Это не целевые значения FPS и не маркетинговые обещания. Это **инженерные лимиты на синхронную часть интерактивной операции**. Если операция не укладывается — она спроектирована неправильно.

### 2.4 Как измерять

Используй `WorldPerfProbe` для всех измерений:

```gdscript
var started_usec: int = WorldPerfProbe.begin()
# ... операция ...
WorldPerfProbe.end("ИмяСистемы.имя_операции", started_usec)
```

В логах должно быть видно, если контракт нарушен.

`WorldPerfProbe` измеряет **операции**, а не весь кадр целиком. Если лог чистый, но hitch ощущается, нужно дополнительно проверять:
- frame time в Godot Profiler
- batching / TileMap update cost
- scene tree mutations (`add_child`, `queue_free`, массовые `set_cell`)
- bridge cost между GDScript и native (см. секцию 10.4)

### 2.5 Acceptance-критерии (целевое UX-качество)

Помимо контрактов на отдельные операции, фиксируем целевое поведение кадра:

- **Нет заметных hitches** в основном gameplay loop (ходьба, майнинг, строительство)
- **Frame time стабилен** в обычной игре (колебания < 3 мс)
- **Редкие spikes допустимы** только:
  - при старте мира под loading screen
  - при first-time warmup вне интерактивного действия игрока

Если система формально проходит `WorldPerfProbe`, но визуально даёт hitch — она **не считается принятой**.

---

## 3. Паттерн: Dirty Queue + Budget

**Это главный паттерн производительности проекта. Все тяжёлые системы ОБЯЗАНЫ его использовать.**

### 3.1 Суть

Вместо «сделать всё сразу» — «пометить грязным и обработать порциями».

```
Событие → Dirty Queue → _process() с бюджетом → Результат через 1-N кадров
```

### 3.1.1 Главное правило main thread

Dirty Queue существует не ради красоты архитектуры, а ради одного принципа:

> **Main thread никогда не должен выполнять большой объём world work в одном кадре по событию игрока.**

Если при событии игрока (`mine`, `step`, `place building`, `enter mountain`) запускается цикл по всем тайлам чанка, всем чанкам или всем нодам мира — это почти наверняка архитектурная ошибка.

### 3.2 Шаблон реализации

```gdscript
## Система, обрабатывающая обновления по бюджету.
class_name BudgetedSystem
extends Node

var _dirty_queue: Array[Variant] = []
var _budget_ms: float = 2.0  # из Resource-файла

func mark_dirty(item: Variant) -> void:
    if item not in _dirty_queue:
        _dirty_queue.append(item)

func _process(_delta: float) -> void:
    if _dirty_queue.is_empty():
        return
    var started_usec: int = Time.get_ticks_usec()
    while not _dirty_queue.is_empty():
        if _elapsed_ms(started_usec) >= _budget_ms:
            break  # остаток — на следующий кадр
        var item: Variant = _dirty_queue.pop_front()
        _process_single(item)

func _process_single(_item: Variant) -> void:
    pass  # переопределить в наследнике

func _elapsed_ms(started_usec: int) -> float:
    return float(Time.get_ticks_usec() - started_usec) / 1000.0
```

### 3.3 Где уже используется (правильно)

- `ChunkManager._process_chunk_redraws()` — progressive redraw по N строк за кадр
- `ChunkManager._process_topology_build()` — topology rebuild с бюджетом 2 мс
- `MountainShadowSystem._process_dirty_queue()` — shadows по 2 чанка за кадр

### 3.4 Где НЕ используется и ДОЛЖНО (текущие проблемы)

- `MountainRoofSystem._refresh_now()` — обновляет cover на ВСЕХ чанках синхронно (до 95 мс)
- `ChunkManager.try_harvest_at_world()` — вызывает `_ensure_topology_current()` синхронно (до 81 мс)
- `ChunkManager.set_active_mountain_key()` — перебирает все загруженные чанки (до 63 мс на чанк)

---

## 4. Паттерн: Immutable Base + Runtime Diff

### 4.1 Суть

Данные мира разделены на два слоя:

```
Base (неизменяемый)          Diff (изменения игрока)
─────────────────            ─────────────────────
terrain_bytes                _modified_tiles
height_bytes                 built structures
topology keys                mined tiles
shadow caster flags          opened doors
resource node positions      depleted nodes
```

### 4.2 Правила

- **Base** генерируется один раз (boot-time или chunk generation) и не пересчитывается
- **Diff** — это то, что сохраняется на диск (уже реализовано в `ChunkSaveSystem`)
- **Рендер = Base + Diff.** Не «пересчитать Base заново», а «наложить Diff поверх»
- При добавлении новой системы — определи, что является Base, а что Diff

### 4.3 Пример (уже работает)

```
Chunk._terrain_bytes     ← Base (от WorldGenerator)
Chunk._modified_tiles    ← Diff (от действий игрока)
_apply_saved_modifications() ← наложение Diff на Base при загрузке
```

### 4.4 Пример (нужно сделать так же)

```
Mountain topology:
  Base = component IDs при генерации чанка
  Diff = patch_tile() при майнинге (9 тайлов, не full BFS)

Shadow caster edges:
  Base = edge list при загрузке чанка (_cache_edges)
  Diff = incremental update при майнинге (±1 edge)

Room detection (будущее):
  Base = wall grid при первичном расчёте
  Diff = add_wall() / remove_wall() → обновить 1 комнату
```

### 4.5 Правило Precompute / Native Cache

> **Всё детерминированное, сеточное, тяжёлое** должно по возможности вычисляться **либо при генерации, либо в native-кэше**, а не в runtime GDScript.

**Кандидаты для precompute / native:**
- terrain classification
- mountain topology / component IDs
- edge / interior visual class
- shadow caster metadata
- room graph seeds
- pathfinding static grid

**Правила:**
- если данные можно вычислить один раз из terrain/grid — не пересчитывай их в interactive path
- если вычисление требует обхода большого числа тайлов — рассмотри C++ / generation stage
- native имеет смысл только если **данные живут там же**; бессмысленно гонять большие `Dictionary` туда-сюда каждый кадр

**Важно:** перенос в C++ **сам по себе** не является оптимизацией. Оптимизацией является:
1. перенос тяжёлого вычисления
2. сокращение объёма bridge / marshaling
3. хранение precomputed state на стороне native

---

## 5. Паттерн: Staged Loading (фазовая загрузка)

### 5.1 Суть

Тяжёлые операции разбиваются на фазы. Каждая фаза — отдельный шаг в очереди. Между фазами возвращаем управление движку (= кадр рендерится).

### 5.2 Chunk loading (текущий и целевой)

**Сейчас (монолитный):**
```
_load_chunk():
  1. WorldGenerator.get_chunk_data()     ← CPU-heavy
  2. Chunk.new() + setup()
  3. populate_native()                   ← записать все тайлы
  4. set_mountain_cover_hidden()         ← может быть дорого
  5. add_child()
  → всё в одном кадре = 20-35 мс
```

**Целевой (staged):**
```
Кадр 1: create chunk node + load data       (2-4 мс)
Кадр 2: populate terrain bytes               (1-2 мс)
Кадр 3+: progressive redraw (8 rows/frame)   (1-2 мс × N кадров)
Кадр N+1: apply overlays (cover, cliffs)      (1-2 мс)
Кадр N+2: finalize (add to tree, emit signal) (< 1 мс)
```

### 5.3 Degraded Mode

Пока чанк не полностью загружен, он может:
- показывать базовый terrain без cover/cliff/shadow
- не участвовать в topology
- не спавнить декорации

Это **лучше**, чем задержка кадра. Игрок на краю экрана не заметит, что далёкий чанк ещё без теней.

### 5.4 Main-thread hazards при staged loading

Даже если загрузка разбита на фазы, следующие операции остаются дорогими и должны ограничиваться бюджетом:

- `TileMapLayer.clear()`
- массовый `set_cell()` (десятки и более за один вызов)
- массовый `add_child()` в цикле
- массовый `queue_free()` в цикле
- полная перестройка overlay/cover/shadow слоя
- полное применение больших `Dictionary` / `Array` payload

Staged loading считается выполненным правильно **только если каждая фаза сама укладывается в бюджет кадра**.

---

## 6. Паттерн: Incremental Update (инкрементальные обновления)

### 6.1 Золотое правило

> **Если изменился 1 тайл — синхронно обновить нужно максимум локальный dirty region (обычно 1–9 тайлов), а не весь чанк, не все чанки и не весь слой.**

### 6.2 Запрещённые операции в Interactive path

| Запрещено | Почему | Замена |
|-----------|--------|--------|
| Full topology BFS по всем чанкам | O(loaded_chunks × chunk²) | `patch_tile()` — O(9) |
| `TileMapLayer.clear()` + перерисовка | Перебирает все ячейки | `_redraw_dirty_tiles()` с маленьким dirty set |
| `_cache_edges()` на весь чанк | 64×64 = 4096 итераций | `_update_edge_at()` для 1-9 тайлов |
| `set_mountain_cover_hidden()` на все чанки | N чанков × стоимость | Очередь, 1-2 чанка за кадр |
| Пересоздание всех ресурсных нод в чанке | Удалить + создать всё | Добавить/удалить 1 ноду |

### 6.3 Правило проверки

Перед написанием любого цикла спроси себя:

```
"Этот цикл перебирает ВСЕ тайлы/чанки/ноды или только ИЗМЕНЁННЫЕ?"
```

Если ответ «все» и это Interactive path — **переделай**.

---

## 7. FrameBudgetDispatcher (архитектура)

### 7.1 Назначение

Центральный автолоад, который:
- принимает регистрации от систем с их бюджетами
- в `_process()` вызывает `tick()` каждой системы
- следит, чтобы суммарное время не превысило общий бюджет
- приоритизирует: chunk streaming > topology > visuals > spawning

### 7.2 Размещение

```
core/autoloads/frame_budget_dispatcher.gd
```

### 7.3 Интерфейс (контракт)

```gdscript
## Регистрация системы в диспетчере.
## category: строковый идентификатор ("streaming", "topology", "visual", "spawn")
## budget_ms: максимальный бюджет в миллисекундах
## callable: функция, которая обрабатывает одну порцию работы.
##           Возвращает true если работа осталась, false если очередь пуста.
func register_job(category: StringName, budget_ms: float, callable: Callable) -> void

## Убрать систему из диспетчера.
func unregister_job(category: StringName) -> void
```

### 7.4 Системы, которые должны регистрироваться

| Система | Категория | Бюджет | Что делает за тик |
|---------|-----------|--------|-------------------|
| ChunkManager (streaming) | `streaming` | 3 мс | загрузка 1 чанка или N строк redraw |
| ChunkManager (topology) | `topology` | 2 мс | incremental topology patch |
| MountainRoofSystem | `visual` | 2 мс | cover update 1-2 чанков |
| MountainShadowSystem | `visual` | 1 мс | shadow rebuild 1-2 чанков |
| ResourceNodeSpawner (будущее) | `spawn` | 1 мс | спавн N нод |
| FaunaSpawner (будущее) | `spawn` | 1 мс | спавн/AI update N существ |
| RoomDetector (будущее) | `topology` | 1 мс | пересчёт 1 комнаты |

### 7.5 Статус внедрения

`FrameBudgetDispatcher` — **целевая архитектура**, а не повод блокировать любую работу до его появления.

**До внедрения диспетчера** допустимо использовать локальные `_process_*()` очереди внутри систем, если они уже работают по тем же принципам: dirty queue, time budget, degraded mode.

Но новые системы должны **проектироваться так, чтобы переход на `FrameBudgetDispatcher` был прямолинейным** — выделять `_tick() -> bool` метод, хранить очередь, не зависеть от порядка вызова в `_process`.

---

## 8. Roadmap реализации

**Порядок важен. Каждый шаг опирается на предыдущий.**

---

### Итерация 1: Убрать синхронные hitches

> **Цель:** ни одна операция по событию игрока не занимает > 4 мс.
> **Acceptance:** быстрый майнинг (удержание кнопки) и вход/выход из горы без заметных hitches.

#### 1.1 Разорвать цепочку в `try_harvest_at_world`

**Файл:** `core/systems/world/chunk_manager.gd`

**Текущая проблема:** `try_harvest_at_world()` после `chunk.try_mine_at()` вызывает `_on_mountain_tile_changed()`, который может привести к `_ensure_topology_current()` — синхронному full BFS (до 81 мс).

**Что сделать:**
1. В `_on_mountain_tile_changed()` — только `_mark_topology_dirty()` и добавление тайла в `_incremental_dirty_tiles: Array[Vector2i]`
2. Убедиться, что нигде на пути от `try_harvest_at_world` до `return result` нет вызова `_ensure_topology_current()`
3. `_ensure_topology_current()` вызывается ТОЛЬКО из `_process_topology_build()` в `_process()`

**Ожидаемый результат:** `try_harvest_at_world` падает с 46–81 мс до ~1–2 мс.

**Как проверить:** в логах `[WorldPerf] ChunkManager.try_harvest_at_world` должен быть < 3 мс.

#### 1.2 Перевести MountainRoofSystem на dirty queue

**Файл:** `core/systems/world/mountain_roof_system.gd`

**Текущая проблема:** `_refresh_now()` вызывает `_chunk_manager.set_active_mountain_key()`, который перебирает ВСЕ загруженные чанки и на каждом вызывает `set_mountain_cover_hidden()` (17–63 мс × N чанков = до 95 мс).

**Что сделать:**
1. `_refresh_now()` переименовать в `_request_refresh()` — она только определяет новый `_active_mountain_key` и формирует список чанков для обновления в `_cover_dirty_queue: Array[Vector2i]`
2. Новый метод `_process_cover_queue()` в `_process()` — обрабатывает 1–2 чанка за кадр с бюджетом 2 мс
3. `ChunkManager.set_active_mountain_key()` больше не перебирает все чанки синхронно — только сохраняет ключ; каждый чанк обновляется из очереди

**Ожидаемый результат:** `_refresh_now` падает с 36–95 мс до < 1 мс (только постановка в очередь). Визуально крыша складывается за 2–4 кадра — выглядит как анимация.

**Как проверить:** в логах `MountainRoofSystem._refresh_now` исчезает. Новая строка `MountainRoofSystem._process_cover_step` показывает < 2 мс.

#### 1.3 Acceptance testing

**Тест 1 — быстрый майнинг:** удерживать кнопку майнинга 10 секунд. В логах — ни одной строки `try_harvest_at_world` > 4 мс.

**Тест 2 — вход в гору:** подойти к раскопанной горе и зайти внутрь. Крыша скрывается плавно за 2–5 кадров. Нет фризов.

**Тест 3 — выход из горы:** выйти наружу. Крыша восстанавливается плавно. Нет фризов.

---

### Итерация 2: Frame-time acceptance + профилирование

> **Цель:** зафиксировать baseline метрик, с которым будем сравнивать все следующие изменения.
> **Acceptance:** стабильный frame time, отсутствие визуальных hitches.

#### 2.1 Расширить `WorldPerfProbe`

**Файл:** `core/autoloads/world_perf_probe.gd` (или где он живёт)

**Что сделать:**
1. Добавить автоматический warning если операция превышает контракт:
   ```
   [WorldPerf] WARNING: ChunkManager.try_harvest_at_world took 5.2 ms (contract: 2 ms)
   ```
2. Добавить периодический лог суммарного frame budget usage:
   ```
   [WorldPerf] Frame budget: streaming=2.1ms topology=0.8ms visual=1.3ms total=4.2ms/6.0ms
   ```
3. Добавить FPS дропы в лог — если FPS < 50, писать что именно в этом кадре было тяжёлым

#### 2.2 Baseline тестирование

Прогнать сценарии из итерации 1.3 и записать:
- средний frame time
- 99-percentile frame time
- количество hitches (кадры > 22 мс) за минуту

Эти числа фиксируются как baseline. Каждая следующая итерация не должна их ухудшать.

---

### Итерация 3: FrameBudgetDispatcher

> **Цель:** единая точка контроля бюджета для всех background-систем.
> **Acceptance:** все background jobs работают через диспетчер; суммарное время < 6 мс/кадр.

#### 3.1 Создать `FrameBudgetDispatcher`

**Файл:** `core/autoloads/frame_budget_dispatcher.gd`

**Что сделать:**
1. Реализовать интерфейс из секции 7.3
2. Приоритеты: `streaming` > `topology` > `visual` > `spawn`
3. Общий бюджет: 6 мс (из Resource-файла, настраиваемый)
4. Если один job не израсходовал бюджет — остаток перераспределяется
5. Логирование: раз в 60 кадров — суммарные затраты по категориям

#### 3.2 Подключить существующие системы

| Шаг | Система | Метод | Категория |
|-----|---------|-------|-----------|
| 3.2a | `ChunkManager._process_chunk_redraws` | Обернуть в `_tick_redraws() -> bool` | `streaming` |
| 3.2b | `ChunkManager._process_topology_build` | Обернуть в `_tick_topology() -> bool` | `topology` |
| 3.2c | `ChunkManager._process_load_queue` | Обернуть в `_tick_loading() -> bool` | `streaming` |
| 3.2d | `MountainRoofSystem._process_cover_queue` (из итерации 1) | `_tick_cover() -> bool` | `visual` |
| 3.2e | `MountainShadowSystem._process_dirty_queue` | `_tick_shadows() -> bool` | `visual` |

#### 3.3 Убрать прямые `_process()` очереди

После подключения к диспетчеру — убрать дублирующие вызовы из `_process()` каждой системы. Вся background-работа идёт только через диспетчер.

---

### Итерация 4: Loading screen для стартового пузыря

> **Цель:** старт мира — атомарный, предсказуемый, без лагов.
> **Acceptance:** от нажатия «Играть» до управления — loading screen с прогрессом. Первый кадр геймплея — чистые 60 FPS.

#### 4.1 Собрать boot-time sequence

**Что входит в boot (порядок):**
1. `WorldGenerator.initialize_world()` — генерация seed, noise setup
2. Генерация player chunk (instant redraw)
3. Генерация соседних чанков (instant redraw для load_radius = 1, progressive для остальных)
4. Первичный topology build для стартового пузыря
5. Tileset warmup
6. Спавн стартовых ресурсных нод и scrap

#### 4.2 Loading screen UI

**Файл:** `scenes/ui/loading_screen.tscn` + `scenes/ui/loading_screen.gd`

- Прогресс-бар (0–100%)
- Текст этапа («Генерация мира...», «Подготовка местности...», «Высадка...»)
- Минимум 1 кадр рендерится между этапами (чтобы прогресс обновлялся)

#### 4.3 Переход в геймплей

После завершения boot — fade-in в геймплей. Оставшиеся дальние чанки загружаются через streaming (уже в gameplay, через FrameBudgetDispatcher).

---

### Итерация 5: Incremental topology patch

> **Цель:** майнинг не пересчитывает всю карту.
> **Acceptance:** при майнинге topology обновляется за < 0.1 мс (один тайл), а не за 60+ мс.

#### 5.1 `patch_tile()` в native

**Файл:** `gdextension/src/native_mountain_topology.cpp` (или как называется)

**Логика:**
1. Получить `mountain_key` изменённого тайла
2. Если тайл был ROCK и стал MINED_FLOOR:
   - убрать из «закрытых» тайлов компонента
   - добавить в «открытые» тайлы компонента
   - проверить 8 соседей — обновить их статус
3. Если тайл стал ROCK (строительство?):
   - обратная операция
4. Проверить, не разделился ли компонент (редкий случай — только если удалён перешеек). Если да — пометить full rebuild для этого компонента (не для всех).

**Сложность:** O(9) вместо O(N²).

#### 5.2 GDScript fallback

Для тестирования без компиляции C++ — аналогичная логика в `ChunkManager._incremental_topology_patch()`.

#### 5.3 Incremental shadow edge update

**Файл:** `core/systems/lighting/mountain_shadow_system.gd`

Текущая `_cache_edges()` перебирает 4096 тайлов. Заменить на `_update_edges_at(tile_pos: Vector2i)` — проверяет 9 тайлов, обновляет edge list для чанка.

---

### Итерация 6: Staged chunk loading

> **Цель:** загрузка чанка не сжирает кадр.
> **Acceptance:** при быстром беге по миру FPS не падает ниже 50.

#### 6.1 Разбить `_load_chunk()` на фазы

**Файл:** `core/systems/world/chunk_manager.gd`

Ввести enum `ChunkLoadPhase { CREATE, POPULATE, REDRAW, OVERLAY, FINALIZE }`.

Каждый чанк в `_load_queue` проходит фазы последовательно. За один тик streaming budget — одна фаза одного чанка (или N строк progressive redraw).

#### 6.2 Degraded mode

Чанк добавляется в scene tree после фазы POPULATE (terrain видно, но без overlays). Cover, cliffs, shadows дорисовываются в фоне.

#### 6.3 Приоритетная загрузка

Чанки ближе к игроку загружаются первыми (уже есть сортировка по расстоянию). Добавить: чанки в направлении движения игрока получают буст приоритета.

---

### Итерация 7: Формализация + масштабирование

> **Цель:** можно безопасно добавлять новые системы (кузница, верстак, комнаты, фауна).
> **Acceptance:** шаблон из секции 11 работает; новая система подключается к диспетчеру за 30 минут.

#### 7.1 Автоматические warnings в `WorldPerfProbe`

Если контракт нарушен — warning в лог с именем системы и фактическим временем. В дебаг-билде — опционально визуальный overlay с frame budget graph.

#### 7.2 Шаблон интеграции

Обновить секцию 11 (шаблон для новых систем) по результатам итераций 1–6. Убедиться, что шаблон реально работает copy-paste.

#### 7.3 Первая «gameplay на фундаменте» система

Выбрать одну из: кузница / верстак / room detection. Реализовать по шаблону. Это будет proof-of-concept, что фундамент держит.

---

## 9. Чеклист производительности (дополнение к основному чеклисту)

**Проверяй ДО написания кода:**

- [ ] К какому классу работы относится операция? (Boot / Background / Interactive)
- [ ] Если Interactive — укладывается ли в контракт из секции 2.3?
- [ ] Если есть цикл по тайлам/чанкам — он по ВСЕМ или по DIRTY?
- [ ] Если операция затрагивает несколько чанков — есть ли dirty queue?
- [ ] Есть ли degraded mode (что показать пока считается)?
- [ ] Определено ли, что в системе Base, а что Diff? (секция 4)
- [ ] Можно ли данные precompute при генерации? (секция 4.5)

**Проверяй ПОСЛЕ написания кода:**

- [ ] Добавлен `WorldPerfProbe` для измерения времени
- [ ] Время в логах не превышает контракт
- [ ] При стресс-тесте (быстрый майнинг, быстрое перемещение) нет визуальных hitches
- [ ] Нет `_ensure_*_current()` или `_rebuild_*()` в Interactive path
- [ ] Нет `clear()` + full `set_cell()` в Interactive path
- [ ] Нет массового `add_child()` / `queue_free()` в Interactive path
- [ ] Если используется native bridge — payload минимален (секция 10.4)

---

## 10. Запрещённые паттерны (антипаттерны)

### 10.1 «Пересчитай всё на всякий случай»

```gdscript
# ЗАПРЕЩЕНО — full rebuild в interactive path
func on_tile_mined(tile: Vector2i) -> void:
    _rebuild_entire_topology()      # O(N²) — НЕЛЬЗЯ
    _refresh_all_chunk_covers()     # O(chunks) — НЕЛЬЗЯ
    _recache_all_shadow_edges()     # O(chunks × tiles) — НЕЛЬЗЯ
```

```gdscript
# ПРАВИЛЬНО — пометить dirty, обработать потом
func on_tile_mined(tile: Vector2i) -> void:
    _mark_topology_dirty_at(tile)   # O(1)
    _queue_cover_update(tile)       # O(1)
    _update_shadow_edge_at(tile)    # O(9)
```

### 10.2 «Сделаю в _process каждый кадр»

```gdscript
# ЗАПРЕЩЕНО — тяжёлая работа каждый кадр
func _process(_delta: float) -> void:
    for chunk in all_loaded_chunks:
        chunk.recalculate_everything()   # НЕЛЬЗЯ
```

```gdscript
# ПРАВИЛЬНО — только если есть dirty items, с бюджетом
func _process(_delta: float) -> void:
    if _dirty_queue.is_empty():
        return
    var budget_start: int = Time.get_ticks_usec()
    while not _dirty_queue.is_empty() and _elapsed_ms(budget_start) < _budget_ms:
        _process_single(_dirty_queue.pop_front())
```

### 10.3 «Один вызов — одна огромная цепочка»

```gdscript
# ЗАПРЕЩЕНО — каскад синхронных вызовов
func try_harvest(pos: Vector2) -> Dictionary:
    var result: Dictionary = chunk.try_mine_at(local)        # 1 мс — ок
    _ensure_topology_current()                                # 60 мс — КАСКАД
    _refresh_mountain_cover()                                 # 95 мс — КАСКАД
    return result
    # итого: 156 мс на один удар кирки
```

```gdscript
# ПРАВИЛЬНО — только мгновенная работа, остальное в очередь
func try_harvest(pos: Vector2) -> Dictionary:
    var result: Dictionary = chunk.try_mine_at(local)        # 1 мс — ок
    _mark_topology_dirty()                                    # 0.001 мс — в очередь
    EventBus.mountain_tile_mined.emit(tile_pos, old, new)    # сигнал, не rebuild
    return result
    # итого: ~1 мс
```

### 10.4 «Тяжёлый native bridge в realtime»

```gdscript
# ЗАПРЕЩЕНО — каждый кадр/каждое действие тянуть большие Dictionary из native
func refresh() -> void:
    var all_tiles: Dictionary = native.get_big_tile_map()
    var by_chunk: Dictionary = native.get_big_grouping()
    _apply_everything(all_tiles, by_chunk)
```

```gdscript
# ПРАВИЛЬНО — держать тяжёлый state в native, запрашивать только локальный payload
func refresh(tile_pos: Vector2i) -> void:
    var key: Vector2i = native.get_component_key_at_tile(tile_pos)
    var affected_chunks: Array = native.get_component_chunk_coords(key)
    _queue_local_updates(affected_chunks)
```

**Правило:** native-код полезен только тогда, когда он уменьшает не только вычисление, но и **объём данных, которые возвращаются в GDScript**.

---

## 11. Шаблон для новых систем

При создании **любой новой системы**, которая работает с миром, используй этот шаблон:

```gdscript
class_name NewWorldSystem
extends Node

## [Описание системы].
## Работает по паттерну Dirty Queue + Budget.
## Регистрируется в FrameBudgetDispatcher.

# --- Константы ---
const DEFAULT_BUDGET_MS: float = 2.0

# --- Приватные ---
var _dirty_queue: Array[Variant] = []
var _budget_ms: float = DEFAULT_BUDGET_MS

# --- Встроенные ---
func _ready() -> void:
    # Подписка на события
    EventBus.some_event.connect(_on_some_event)
    # Регистрация в диспетчере бюджета (когда доступен)
    # FrameBudgetDispatcher.register_job(&"new_system", _budget_ms, _tick)

func _process(_delta: float) -> void:
    # Вариант без диспетчера (если диспетчер ещё не внедрён)
    _tick()

# --- Публичные методы ---

## Пометить элемент для обработки.
func mark_dirty(item: Variant) -> void:
    if item not in _dirty_queue:
        _dirty_queue.append(item)

# --- Приватные методы ---

## Обработать порцию работы в рамках бюджета.
## Возвращает true если работа осталась.
func _tick() -> bool:
    if _dirty_queue.is_empty():
        return false
    var started_usec: int = Time.get_ticks_usec()
    while not _dirty_queue.is_empty():
        if _elapsed_ms(started_usec) >= _budget_ms:
            return true  # остаток на следующий кадр
        _process_single(_dirty_queue.pop_front())
    return false

## Обработать один элемент. Переопределить в наследнике.
func _process_single(_item: Variant) -> void:
    pass

## Реакция на событие — только пометить dirty.
func _on_some_event(data: Variant) -> void:
    mark_dirty(data)  # НЕ обрабатывать здесь

func _elapsed_ms(started_usec: int) -> float:
    return float(Time.get_ticks_usec() - started_usec) / 1000.0
```

---

## 12. Финальный принцип

> **Производительность проекта обеспечивается не «оптимизацией потом», а тем, что тяжёлая работа изначально не попадает в путь игрока.**

Если новая фича требует full rebuild, обхода всех чанков, массового redraw или синхронного ожидания кеша — сначала нужно менять **архитектуру фичи**, а не писать код «как получится».

---

*Документ создан: v1.0 → v1.1 (патч по рецензии Codex)*
*Последнее обновление: Март 2026*
*Статус: ОБЯЗАТЕЛЕН К ПРОЧТЕНИЮ перед любой работой с игровыми системами*
