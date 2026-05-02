---
title: Архитектура генерации гор (Mountain Generation Architecture)
doc_type: design_proposal
status: draft
owner: engineering
source_of_truth: false
version: 0.3
last_updated: 2026-04-27
related_docs:
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - world_runtime.md
  - world_grid_rebuild_foundation.md
  - rock_shader_presentation_iteration_brief.md
---

# Архитектура генерации гор (Mountain Generation Architecture)

> Это **pre-spec design proposal**, а не source of truth. Перед реализацией
> оформить полноценный `docs/02_system_specs/world/mountain_generation.md`
> со стандартным Law 0 / acceptance tests / file-scope и получить approval.
> Спек-first правило (WORKFLOW.md) — кодить без этого запрещено.

---

## 0. TL;DR

Текущая «генерация» гор в репозитории — это просто `h % 29 == 0` на каждой
плитке независимо (`gdextension/src/world_core.cpp:44`). Ни куч, ни массивов,
ни идентичности. Для настоящих массивных гор нужно пять кирпичей, каждый —
детерминированный и нативный:

1. **Поле высот на C++** — domain-warped FBM + ridge noise → силуэт гор.
2. **Идентичность горы (`mountain_id`)** — через детерминированные anchor-ячейки
   на грубой решётке, без глобальной connected-components свёртки.
3. **Слой-крыша (roof overlay)** — отдельный `TileMapLayer` поверх террейна,
   текстура = та же rock-top, что снаружи горы. Этот слой **прячет интерьер**,
   не является источником истины.
4. **MountainRevealRegistry** — runtime-овнер «какие `mountain_id` сейчас
   открыты». Плавный alpha-fade через `modulate`.
5. **Настройки worldgen** (`MountainGenSettings` resource) — density, scale,
   continuity, ruggedness; каждое изменение → bump `WORLD_VERSION`.

Всё остальное в этом документе — конкретизация этих пяти решений под реальный
код Station Mirny.

---

## 1. Статус проекта (на что мы опираемся)

### 1.1. Что уже есть

| Компонент | Файл | Что делает |
|---|---|---|
| Нативная генерация чанка | `gdextension/src/world_core.cpp` | Возвращает `ChunkPacketV0` с `terrain_ids`, `terrain_atlas_indices`, `walkable_flags`. В текущем `world_version >= 4` базовый path производит `PLAINS_GROUND`, а blocked mountain terrain идёт только через mountain field. |
| Autotile-47 | `gdextension/src/autotile_47.cpp` | Решает атлас-индекс для 8-соседнего rock-силуэта. Переиспользуется для гор 1-в-1. |
| Streamer | `core/systems/world/world_streamer.gd` | Worker-thread + `FrameBudgetDispatcher.CATEGORY_STREAMING` + sliced publish. Готов принимать расширенный пакет. |
| ChunkView | `core/systems/world/chunk_view.gd` | Уже имеет **два** слоя (`TerrainBaseLayer`, `TerrainOverlayLayer`). Добавить третий «roof» — естественное расширение. |
| Shader-крышка | `assets/shaders/mountain_cover_overlay.gdshader` | `hide_mask > 0.5 → alpha = 0`. **Это ровно нужный примитив для reveal-анимации по маске**, уже написан. |
| Shader-тумана | `assets/shaders/mountain_overlay.gdshader` | Заливает «скрытое» непрозрачным fog-color. Пригодится для плавного fade-in крыши. |
| Runtime seam | `core/autoloads/frame_budget_dispatcher.gd` + `RuntimeDirtyQueue` + `RuntimeWorkTypes` | ADR-0001 обязательный контракт деферред-работы. Всё тяжёлое идёт через это. |
| Immutable-base/diff | `WorldDiffStore` + `ChunkDiffV0` в `world.json` + `chunks/*.json` | Каждая копнутая клетка — запись в diff, база пересоздаётся из seed. |

### 1.2. Что **запрещено** по governance (без чего проект сломается)

- LAW 1: тяжёлый проход по тысячам тайлов **не** в GDScript. Всё сэмплирование
  поля гор — только C++ (GDExtension), one packet per chunk (LAW 6).
- LAW 2: main thread только `apply`, не `compute`. Никакого сэмплирования шума
  в `_process` или в interactive path.
- LAW 3: генератор чанка — чистая функция `f(seed, coord, world_version, settings)`.
  **Не** читать сцену, не читать «соседние чанки уже загруженные», не брать
  состояние камеры.
- LAW 4: любое изменение канонического выхода → bump `WORLD_VERSION` в
  `core/systems/world/world_runtime_constants.gd`.
- LAW 5: база гор **иммутабельна**. Копание = запись в `WorldDiffStore`, не
  перезапись базовой породы.
- LAW 9: никакого «временного GDScript fallback» для генерации горы.
  Не собран GDExtension — падаем явно.
- LAW 11: у каждой runtime-системы есть dirty unit. Для reveal — это
  `mountain_id`. Для локального копания — одна клетка.
- LAW 12: **никакого global planet prepass**. Мир бесконечный; генерировать
  горы как локальное поле на каждый чанк, без «сначала размести все горные
  хребты планеты».

### 1.3. Что спека уже **отложила**

`docs/02_system_specs/world/world_runtime.md` — V0 **явно исключает** горы
(«Out of Scope: mountains»). Значит, горы — это новая фича, и по spec-first
правилу коду должен предшествовать approved spec. Этот документ — вход в
процесс создания такого спека.

---

## 2. Корневые архитектурные решения

### 2.1. Поле гор — domain-warped FBM + ridge в C++

**Проблема.** Один шум `simplex(x,y) > t` даёт округлые «кляксы», не горы.
Настоящие горные массивы — это вытянутые хребты с нелинейными боковыми
отрогами и резкими гребнями.

**Решение (индустриальный паттерн, используется в No Man's Sky, Dwarf Fortress
style terrain, Minecraft 1.18+).**

```
sample_elevation(wx, wy, seed, wv, settings) -> float:
    # 1. Domain warp: искажает координаты, превращая диски в хребты
    qx = wx + warp_amp * fbm(wx * warp_freq, wy * warp_freq, seed^A)
    qy = wy + warp_amp * fbm(wx * warp_freq + 5.2, wy * warp_freq + 1.3, seed^B)

    # 2. Macro FBM: крупные массивы
    macro = fbm(qx * macro_freq, qy * macro_freq, seed^C,
                octaves=settings.continuity_octaves,
                lacunarity=2.0, gain=settings.continuity_gain)

    # 3. Ridge noise: гребни (|1 - |noise||)
    ridge = ridged_fbm(qx * ridge_freq, qy * ridge_freq, seed^D)

    # 4. Смесь: ridge усиливается там, где macro уже высокий
    elevation = macro + settings.ruggedness * ridge * smoothstep(0.0, 0.3, macro)

    # 5. Широтная подавка (ADR-0002: Y не оборачивается, Y — широта)
    # Делает экватор «равнинным», полюса «горными» или наоборот по лору
    elevation += latitude_bias(wy) * settings.latitude_influence

    return elevation
```

Пороговая классификация:
- `mountain_id > 0 && elevation >= t_wall`  → `TERRAIN_MOUNTAIN_WALL`
  (непроходимая скала, интерьер)
- `mountain_id > 0 && elevation >= t_edge`  → `TERRAIN_MOUNTAIN_FOOT`
  (подножье, видимый rock-face, `walkable = 0`, но **не** interior —
  автоматически открыто)
- `elevation <  t_edge`  → ground (`TERRAIN_PLAINS_GROUND`)

Полосы:
- `t_edge` и `t_wall` — оба сдвигаются параметром `density`.
- Разность `t_wall - t_edge` = ширина «подножья» в elevation-пространстве
  (контролируется `settings.foot_band`).
- `interior_mask = (elevation >= t_interior)` → именно для этих тайлов
  будет рисоваться крыша.

**Wrap-safe по X.** Всё сэмплирование должно проходить через
`wrap_x(wx, world_width_tiles)` перед подачей в noise (ADR-0002).

**Реализация шума.** Используем **FastNoise Lite** (header-only, C99/C++,
встраивается в `gdextension/src/third_party/`). Альтернативы:
- **OpenSimplex2** — выше качество, лицензия CC0.
- Своя реализация — плохая идея: шум должен быть вылизан, потеря октавы даёт
  визуальные артефакты.

**Критично для бесконечного мира:** все функции шума — pure, без глобального
состояния. Значение в мировой точке `(wx, wy)` должно быть воспроизводимым
независимо от того, в каком порядке игрок загрузил чанки.

### 2.2. Идентичность горы — детерминированные anchor-ячейки

**Проблема.** «Вошёл в одну гору → открывается только она» требует, чтобы
каждая плитка знала, **к какой горе она принадлежит**. Classical
connected-components (flood-fill по всем rock-плиткам) на бесконечном мире
невозможен — он не локализуется на один чанк.

**Решение: sparse deterministic anchors.**

```
ANCHOR_CELL_SIZE = 64 или 128 тайлов (настраиваемо, см. settings)

for each anchor-cell (ax, ay) in world:
    # 1. Детерминированная jitter-позиция внутри ячейки
    h = splitmix64(seed ^ ax * K1 ^ ay * K2)
    local_x = (h >> 0)  & 63
    local_y = (h >> 16) & 63
    world_px = ax * ANCHOR_CELL_SIZE + local_x
    world_py = ay * ANCHOR_CELL_SIZE + local_y

    # 2. Является ли эта точка якорем горы?
    if sample_elevation(world_px, world_py, ...) >= t_anchor:
        anchor_id = hash(seed, ax, ay)  # стабильный id горы
        anchor_position = (world_px, world_py)
```

Для каждой rock-плитки `(wx, wy)`:
```
nearest = argmin over anchors in bounded local anchor-neighborhood:
    chebyshev_distance((wx, wy), anchor.position)
mountain_id = nearest.anchor_id
```

**Ключевые свойства.**
- Полностью детерминированно и локально (bounded anchor-ячеек вокруг тайла,
  без global prepass).
- Бесконечно масштабируется — нет глобального списка гор.
- Две близкие горы с разными anchor-ячейками получают разные `mountain_id`,
  даже если их силуэты визуально соприкасаются.
- Сохраняется при любом размере чанка (anchor-ячейка независима от `32x32`).
- `mountain_id = 0` на elevated terrain в текущем `world_version >= 4` —
  diagnostic miss, а не штатная presentation branch.

**Хранение в пакете.** Новое поле `mountain_id_per_tile: PackedInt32Array`
длины 1024. `0` — не интерьер. Остальные значения — идентификаторы гор.

### 2.3. Крыша (roof overlay) — третий TileMapLayer в ChunkView

**Проблема пользователя.** «Я выкопал в горе — вижу комнату. Я вышел — гора
опять целая, как будто я её не трогал. Снаружи виден только вход».

**Решение.** Визуальное сокрытие интерьера **не совпадает** с диффом — это
разные слои ответственности:

- `WorldDiffStore` (LAW 5, LAW 8): authoritative — «эта клетка выкопана,
  теперь она floor». Сохраняется в `chunks/*.json`.
- `RoofLayer` (derived): визуальный оверлей поверх террейна. Рисуется
  **только там, где плитка имеет `mountain_id > 0` и wall/foot flag**,
  берётся из базового пакета. Никогда не персистится.

Код:

```gdscript
# chunk_view.gd — расширение текущего файла
# (сейчас: _base_layer, _overlay_layer)
# становится: _base_layer, _overlay_layer, roof_layers_by_mountain

var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {})
var roof_layer := TileMapLayer.new()
roof_layer.name = "MountainRoofLayer_%d_%d" % [mountain_id, terrain_id]
roof_layer.tile_set = WorldTileSetFactory.get_roof_tile_set(terrain_id)
roof_layer.z_index = 10  # поверх overlay
roof_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
terrain_layers[terrain_id] = roof_layer
roof_layers_by_mountain[mountain_id] = terrain_layers
```

**Атлас крыши = presentation atlas соответствующего mountain surface.**
`TERRAIN_MOUNTAIN_WALL` и `TERRAIN_MOUNTAIN_FOOT` используют отдельные
47-tile ресурсы. Чтобы крыша снаружи выглядела как продолжение горы без шва,
autotile-47 индекс на крыше для клетки `(wx, wy)` считается так же, как для
mountain surface: по соседям, которые входят в mountain geometry.

Это означает: когда игрок снаружи, `base_layer` внутри горы уже рисует
rock-wall на всех interior-клетках, а `roof_layer` сверху дорисовывает
крышу. Визуально — сплошной горный массив. Когда игрок зашёл внутрь,
`roof_layer` для этой горы плавно уходит в `modulate.a = 0` — и игрок видит
выкопанные клетки и комнату через тот самый rock-wall, который теперь
**прорублен** в diff-е (там где было `_clear_cell`/ground).

**ВАЖНО.** Крыша должна рисоваться и над **не-выкопанными** стенами тоже,
чтобы сам `mountain_id` оставался цельным визуально. Когда игрок копает —
diff делает тайл проходимым и меняет текстуру базового слоя на floor-ground.
Крыша этого не видит (она всё ещё рисует rock-top). Это и даёт эффект:
«снаружи гора цельная, а я знаю, что внутри база».

**Вход (entrance).** Тайл на внешнем периметре выкопанного туннеля,
соседствующий хотя бы с одним **проходимым выходом из interior-shell**
(сосед walkable и при этом `mountain_id != self` либо `is_interior == 0`),
помечается `is_entrance`. Для таких тайлов крыша **не рисуется никогда** —
это и есть «вижу вход снаружи». Расчёт: за 1 `apply_runtime_cell` вызов
пересчитываем `is_entrance` для копнутой клетки и её 4-соседей. Dirty unit =
4+1 клетки.

### 2.4. Reveal — один bit per mountain, плавно

**Владелец** — новый `MountainRevealRegistry` (autoload или child of
WorldStreamer). Единственный writer.

```gdscript
# core/systems/world/mountain_reveal_registry.gd
class_name MountainRevealRegistry
extends Node

signal mountain_revealed(mountain_id: int)
signal mountain_concealed(mountain_id: int)

var _revealed: Dictionary = {}  # mountain_id -> reveal_progress (0.0..1.0)
var _target: Dictionary = {}    # mountain_id -> target (0.0 | 1.0)
const FADE_SECONDS: float = 0.35
const EXIT_DEBOUNCE: float = 0.5  # игрок вышел и вернулся — не дёргать крышу

func request_reveal(mountain_id: int) -> void:
    if mountain_id == 0:
        return
    _target[mountain_id] = 1.0
    if not _revealed.has(mountain_id):
        _revealed[mountain_id] = 0.0
        mountain_revealed.emit(mountain_id)

func request_conceal(mountain_id: int) -> void:
    if mountain_id == 0 or not _target.has(mountain_id):
        return
    _target[mountain_id] = 0.0  # после дебаунса сделаем fade-in

func get_roof_alpha(mountain_id: int) -> float:
    # 1.0 = крыша полностью видима (снаружи). 0.0 = крыша невидима (внутри).
    if mountain_id == 0:
        return 1.0  # не интерьер — крыши нет или всегда есть
    return 1.0 - _revealed.get(mountain_id, 0.0)
```

Процесс интерполяции — один job в `FrameBudgetDispatcher`
(`CATEGORY_PRESENTATION`, бюджет ~0.2 мс), **не** в `_process` каждой
`ChunkView`. Все чанки подписываются на `mountain_revealed`/`mountain_concealed`
и применяют alpha к `_roof_layer.modulate.a`.

**Частичное открытие — запрещено.** Reveal всегда по всей горе (user
требование «открывается целиком»). Это естественно: ключ — `mountain_id`, не
координата.

**Несколько гор рядом.** Игрок в горе A → `A.revealed = true`, `B` не тронута.
Если у игрока под ногами `mountain_id` сменился (прошёл коридор в соседнюю
гору), `A` plavno скрывается, `B` — открывается, пересечение fade не
мешает. У каждой горы своё собственное alpha-состояние.

### 2.5. Resolver — O(1) «в какой горе стоит игрок»

```gdscript
# core/systems/world/mountain_resolver.gd
class_name MountainResolver
extends RefCounted

var _streamer: WorldStreamer
var _last_mountain_id: int = 0

func update_from_player_position(world_pos: Vector2) -> void:
    var tile: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
    var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile)
    var local: Vector2i = WorldRuntimeConstants.tile_to_local(tile)
    var packet: Dictionary = _streamer.get_chunk_packet(chunk_coord)
    if packet.is_empty():
        return  # чанк не загружен, reveal не меняем
    var index: int = WorldRuntimeConstants.local_to_index(local)
    var ids: PackedInt32Array = packet["mountain_id_per_tile"]
    var current: int = ids[index] if index < ids.size() else 0

    if current == _last_mountain_id:
        return
    if _last_mountain_id != 0:
        MountainRevealRegistry.request_conceal(_last_mountain_id)
    if current != 0:
        MountainRevealRegistry.request_reveal(current)
    _last_mountain_id = current
```

Вызов — раз в кадр из `Player._physics_process` (это **не** тяжёлая работа:
один lookup в Dictionary + одно чтение массива). Дебаунс выхода на
`EXIT_DEBOUNCE` = защита от флика на границе.

Если игрок в **проёме** (тайл с `mountain_id == 0`, но физически окружён
интерьером выкопанной базы) — resolver смотрит на clamp-ed ближайшую
interior-плитку в 1-тайловом радиусе, чтобы не сбрасывать reveal при стоянии
в коридоре-входе. Doorway fallback разрешён только когда interior одной и той
же горы лежит на **противоположных** cardinal-соседях (`N+S` или `E+W`);
corner adjacency не считается проходом. Это очень локальная проверка (5
тайлов).

### 2.6. Копание — без изменения архитектуры

Текущий V0-путь:
- `WorldStreamer.try_harvest_at_world(...)` → запись в `_diff_store` → локальный
  `chunk_view.apply_runtime_cell(...)`.

Для гор добавляется **ровно одна строка**: после записи диффа,
если плитка имела `mountain_id > 0` и её сосед теперь не-mountain —
пересчитать `is_entrance` для 5-клеточного ядра. Это bounded local patch,
укладывается в LAW 11.

Копание **не** трогает `_roof_layer`. Крыша остаётся, потому что базовое
состояние плитки (`mountain_id`, `is_interior`) не изменилось — это свойство
базы, а не диффа. Игрок, стоя внутри, просто не видит крышу, потому что её
alpha обнулена для этой горы.

Строить внутри горы — стандартный `BuildingSystem` путь: placement идёт в
diff-overlay, снаружи не видно, потому что крыша всё прячет.

---

## 3. Контракт пакета — ChunkPacketV1

Текущий `ChunkPacketV0`:

```
chunk_coord, world_seed, world_version,
terrain_ids[1024], terrain_atlas_indices[1024], walkable_flags[1024]
```

Предлагаемый `ChunkPacketV1` (additive):

```
+ mountain_id_per_tile: PackedInt32Array      length 1024, 0 = not mountain
+ mountain_flags:       PackedByteArray        length 1024
                         bit 0 = is_interior (крыть крышей)
                         bit 1 = is_wall     (непроходимая скала)
                         bit 2 = is_foot     (подножье, видимое снаружи)
                         bit 3 = is_anchor   (центр горы, для миникарты)
+ mountain_atlas_indices: PackedInt32Array    length 1024, индексы для roof-слоя
```

**Почему не отдельные массивы?** Упакованные byte-флаги = 1 байт/тайл = 1 КБ
на чанк вместо 4×1 КБ. Для 100 загруженных чанков это экономит ~400 КБ.

**Границы.**
- Канонический docs update (обязательно per WORKFLOW.md):
  - `docs/02_system_specs/meta/packet_schemas.md` — добавить `ChunkPacketV1`.
  - `docs/02_system_specs/world/mountain_generation.md` (новый) — сам спек.
  - `docs/02_system_specs/meta/event_contracts.md` — `mountain_revealed`,
    `mountain_concealed`.
- `WORLD_VERSION` **обязательно** поднимается при любом изменении
  canonical mountain output. M1 поднял его с `1` на `2`; named-mountain
  ownership fix поднимает с `2` на `3`.
  Иначе существующие save-файлы сломают детерминизм.

---

## 4. Настройки worldgen (никакого хардкода)

### 4.1. Ресурс `MountainGenSettings`

Создать `data/balance/mountain_gen_settings.tres` на базе `Resource`:

```gdscript
class_name MountainGenSettings
extends Resource

# Плотность гор. Сдвигает порог elevation.
# 0.0 — гор нет вообще; 1.0 — почти вся карта горы.
@export_range(0.0, 1.0, 0.01) var density: float = 0.25

# Размер горы. Длина волны noise.
# Меньше = больше мелких сопок. Больше = меньше, но массивнее.
@export_range(32.0, 2048.0) var scale: float = 512.0

# Продолжительность (вытянутость). Сила domain warp.
# 0.0 — круглые кляксы; 1.0 — длинные хребты.
@export_range(0.0, 1.0, 0.01) var continuity: float = 0.6

# Скалистость. Вес ridged-noise.
# 0.0 — гладкие холмы; 1.0 — острые гребни.
@export_range(0.0, 1.0, 0.01) var ruggedness: float = 0.5

# Размер anchor-ячейки в тайлах. Чем больше — тем крупнее минимальная
# единица «одна гора». Рекомендуется 64..256.
@export_range(32, 512) var anchor_cell_size: int = 128

# Ширина полосы «подножье». Сколько elevation-единиц между границей
# и стеной. Больше = более длинные склоны.
@export_range(0.02, 0.3, 0.01) var foot_band: float = 0.08

# Сколько тайлов вглубь интерьера должна быть плитка, чтобы её крыла
# крыша. 0 — крышу рисуем на любой interior-плитке.
@export_range(0, 4) var interior_margin: int = 1

# Влияние широты. 0 = везде одинаково; 1 = на экваторе меньше гор.
@export_range(-1.0, 1.0, 0.05) var latitude_influence: float = 0.0
```

### 4.2. Прокидывание в C++

Signature расширяется:

```
WorldCore.generate_chunk_packet(seed, coord, world_version, settings_packed)
```

`settings_packed` — `PackedFloat32Array` длины ~12 (плоский layout). C++
читает его один раз на чанк, не на тайл. Ноль новых Variant-маршалов.

**Дефолты при отсутствии settings_packed**: нулевое заполнение — горы
отключены. Это позволяет V0 сцене не ломаться, пока контент-пайплайн не
подхватил ресурс.

### 4.3. Хранение настроек и роль world_version

**Решение принято** (см. §10, Q4): настройки хранятся явно в `world.json`, а
`world_version` — **отдельная** граница «версия алгоритма/схемы». Не
смешиваются.

Модель:
- `world_version` — целое число, bump-ится только при изменении алгоритма
  генератора (новые поля пакета, новая форма шума, новая формула entrance,
  и т.п.). LAW 4 применяется к **алгоритму**, не к настройкам пользователя.
- `worldgen_settings` — детерминированный input конкретного сейва. Пишется
  в `world.json` при `new game` и **никогда** не переписывается при
  загрузке из текущего ресурса в сцене.

Форма `world.json` после M1:

```json
{
  "world_seed": 42,
  "world_version": 3,
  "worldgen_settings": {
    "mountains": {
      "density": 0.30,
      "scale": 512.0,
      "continuity": 0.65,
      "ruggedness": 0.55,
      "anchor_cell_size": 128,
      "foot_band": 0.08,
      "interior_margin": 1,
      "latitude_influence": 0.0
    }
  }
}
```

Правила:
- Ключ `worldgen_settings` сразу **namespaced** (`mountains`, позже
  `biomes`, `climate`). Не плоский `mountain_settings`.
- Ресурс `mountain_gen_settings.tres` в репозитории — источник **дефолтов
  для новых миров**, не источник истины для существующих.
- Патч баланса в ресурсе → старые сейвы грузятся как были, новые миры
  получают новые дефолты.
- Отсутствующие поля при загрузке старого сейва подстанавливаются
  hard-coded defaults в коде загрузчика — не из ресурса.
- Опционально можно писать `worldgen_signature` (hash of settings) для
  диагностики/дебага, но **не** как source of truth.

Что это даёт:
- `world_version` остаётся **читаемым** integer — видно в changelog, видно
  в логах.
- Полная воспроизводимость конкретного мира — достаточно одного
  `world.json`.
- Простой путь миграции: если алгоритм поменялся несовместимо, bump
  `world_version`, в коде загрузчика явно отрабатываем old → new.

---

## 5. Производительность — runtime work classes

Классификация по ADR-0001:

| Операция | Класс | Dirty unit | Бюджет |
|---|---|---|---|
| Сэмплирование поля гор | background (C++ worker) | 32×32 чанк | вне main thread |
| Sliced publish mountain tiles | background apply | 128 cells/tick | 1.5 ms/frame (в `CATEGORY_STREAMING`, уже есть) |
| Mountain resolver (player tile lookup) | interactive | 1 tile | <0.05 ms |
| Reveal fade interpolation | background | 1 mountain_id | 0.2 ms/frame (`CATEGORY_PRESENTATION`) |
| Excavation diff + entrance recompute | interactive | 5 tiles | <1.0 ms |

**Что гарантирует отсутствие хитчей:**
1. Генерация одного чанка (1024 тайла × ~6 шумовых сэмплов + anchor lookup)
   в нативном коде — порядок **0.3–1.0 мс на одном ядре**. Идёт в worker,
   main thread не трогается.
2. Publish — уже sliced (в `chunk_view.apply_next_batch`), это не меняется.
3. Reveal fade — один tween-job на весь мир, не per-chunk.
4. Копание — bounded, как в V0.

**Что может взорвать производительность (и запрещено).**
- ❌ flood-fill по всем интерьер-тайлам горы при входе («выделить всю
  комнату»). Нет, `mountain_id` уже всё решил на этапе генерации.
- ❌ пересчёт `mountain_id` после копания. Идентичность горы — из базы,
  не из диффа.
- ❌ попытка определить «какая гора» через scene-query (коллайдеры,
  groups). Только packet lookup.
- ❌ alpha-fade per-tile (каждая interior-клетка тянет свой tween).
  Только per-mountain через `modulate` всего `TileMapLayer`.
- ❌ пересчёт autotile-47 для крыши на каждый reveal. Индексы крыши
  решаются один раз в генерации.

---

## 6. Отображение (presentation integration)

### 6.1. Связка со слоями

**Решение принято** (см. §10, Q1): roof ownership остаётся **per
`mountain_id`**, но визуальные roof-`TileMapLayer` создаются отдельно для
каждого presentation terrain (`TERRAIN_MOUNTAIN_WALL` /
`TERRAIN_MOUNTAIN_FOOT`) внутри этой горы. Без агрегации. Агрегированный
alpha на чанк **запрещён**, потому что нарушает ключевой UX-инвариант
«opening mountain A must not reveal mountain B» на стыках гор.

```
ChunkView layout:
  [z=0]   _base_layer                          — ground (plains), rock-wall mountain faces
  [z=1]   _overlay_layer                       — существующий (deco, etc.)
  [z=10+] roof_layers_by_mountain[mountain_id][terrain_id] — wall/foot roof-слои горы
```

Внутри `ChunkView`:

```gdscript
var roof_layers_by_mountain: Dictionary = {}  # int mountain_id -> Dictionary[int terrain_id, TileMapLayer]

func _ensure_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
    var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {})
    if terrain_layers.has(terrain_id):
        return terrain_layers[terrain_id]
    var layer: TileMapLayer = TileMapLayer.new()
    layer.name = "RoofLayer_%d_%d" % [mountain_id, terrain_id]
    layer.tile_set = WorldTileSetFactory.get_roof_tile_set(terrain_id)
    layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    layer.z_index = 10
    add_child(layer)
    terrain_layers[terrain_id] = layer
    roof_layers_by_mountain[mountain_id] = terrain_layers
    return layer
```

`ChunkView` подписывается на `MountainRevealRegistry` и применяет alpha
через общий per-`mountain_id` mask/texture ко всем wall/foot roof-слоям этой
горы:

```gdscript
func _on_mountain_reveal_alpha_changed(mountain_id: int, alpha: float) -> void:
    var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {})
    if terrain_layers.is_empty():
        return
    for layer in terrain_layers.values():
        layer.modulate.a = alpha
```

**Почему не агрегированный alpha на чанк.**
- На стыке двух гор (A открыта, B закрыта) агрегированный `max(1-revealA, 1-revealB)`
  всё равно оставляет крышу над интерьером A. Игрок внутри A над своей
  базой видит крышу — нарушение главного требования.
- Проблема не «косметический артефакт», а разрушение инварианта.
- 32×32 тайла — маленький чанк; в типичной сцене 0–2 `mountain_id` в чанке,
  редко 3. Несколько `TileMapLayer` на такой footprint — мизерная нагрузка.

**Guardrail (обязательный, M1+).** Дебаг-метрика
`WorldStreamer.roof_layers_per_chunk_max`. Если значение > 4:
- warning в лог: `"roof layer explosion: chunk %s has %d mountains"`;
- сигнал для дизайнера: либо `density` слишком высок, либо
  `anchor_cell_size` слишком мал относительно чанка.

При unload чанка все `roof_layers_by_mountain` уничтожаются вместе с
`ChunkView` — стандартный `queue_free()`, никаких утечек.

### 6.2. Использовать уже написанный шейдер

`assets/shaders/mountain_cover_overlay.gdshader` — ровно hide-by-mask
шейдер. Для плавности: либо `modulate.a`, либо делаем `hide_mask` как
ramp-текстуру (sdf от центра «входа» → постепенно раскрывается наружу).
Второй вариант даёт эффект «двери раскрываются» — визуально шикарно, но
дороже. На MVP — обычный `modulate.a` на всём TileMapLayer, это O(1) на
кадр.

### 6.3. Rock-shader brief (уже approved draft)

`docs/02_system_specs/world/rock_shader_presentation_iteration_brief.md`
параллельно апгрейдит визуал rock-tiles на shape-atlas + shader. Эта
работа совместима: крыша использует **тот же** rock-top шейдер и атлас,
что mountain-wall. Визуальный шов между ними исключён.

---

## 7. Реализация по шагам

### Итерация M0 — Spec и скелет (обязательно до кода)

1. Создать `docs/02_system_specs/world/mountain_generation.md` с Law 0
   классификацией, acceptance tests, file-scope, forbidden paths.
2. Обновить `packet_schemas.md` — объявить `ChunkPacketV1`.
3. Обновить `event_contracts.md` — `mountain_revealed`, `mountain_concealed`.
4. Approved → переход к M1.

### Итерация M1 — Нативный mountain field (без reveal)

1. Добавить `gdextension/src/third_party/FastNoiseLite.h`.
2. Добавить `gdextension/src/mountain_field.{h,cpp}` — чистые функции
   `sample_elevation`, `resolve_anchor_id`.
3. Расширить `generate_chunk_packet` → возвращает V1 packet.
4. Поднять `WORLD_VERSION: int = 4` в `world_runtime_constants.gd`.
5. `WorldStreamer` просто передаёт новые поля в `ChunkView` (пока
   roof-layer не включён — просто чтобы тайлы рисовались как
   mountain-wall).
6. Smoke test: видны горные массивы, FBM-форма, FPS стабильный.

### Итерация M2 — Roof overlay и resolver

1. Добавить `_roof_layer` в `ChunkView` + `set_roof_alpha(float)`.
2. Создать `MountainRevealRegistry` + job в `FrameBudgetDispatcher`.
3. Создать `MountainResolver`, вызывать из `Player._physics_process`.
4. Подписать `ChunkView` на сигналы регистра.
5. Smoke test: вошёл в гору → крыша плавно исчезает; вышел → возвращается;
   две соседние горы → реагируют независимо.

### Итерация M3 — Копание и вход

1. Runtime-only кэш `_entrance_cache: PackedByteArray` внутри `ChunkView`
   (см. Q2). В пакете/диффе **не** хранится.
2. Функция `recompute_entrance_flag(world_tile)` — единственный источник
   истины; вызывается из обоих путей.
3. Interactive путь: в `try_harvest_at_world` после записи диффа —
   `recompute_entrance_flag` для копнутой клетки + 4 соседей (5 тайлов).
4. Boot/load путь: при публикации чанка после load — пробегаем все dirty
   тайлы чанка и вызываем ту же функцию. Под loading screen.
5. `ChunkView` — если `is_entrance`, на roof-слое соответствующей горы в
   этой клетке ставим `TileMapLayer.set_cell(..., -1)` (пустая ячейка),
   а не alpha-override. Чисто и дёшево.
6. Smoke test: копаю ход снаружи → вижу вход снаружи, остальная крыша
   цела.

### Итерация M4 — Settings и UI

1. `MountainGenSettings.tres` + интеграция в `WorldStreamer.reset_for_new_game`.
2. UI main-menu → new-game → слайдеры density/scale/continuity/ruggedness.
3. `WORLD_VERSION` включает hash настроек; save хранит полный
   `settings_packed`.
4. Acceptance: каждый слайдер реально меняет результат генерации (grep +
   визуальная проверка).

### Итерация M5 — Polish

- SDF-based door opening (расхождение крыши от входа).
- Mountain-top shader с variance (per-mountain цвет/текстура для
  визуального различения).
- Minimap рендер: anchor = иконка горы.
- Доразметка biome influence (mountain в tundra != mountain в desert).

---

## 8. Инварианты и грабли

### Инварианты (никогда не нарушать)

- `mountain_id` у тайла **не изменяется никогда** после генерации базы
  (LAW 5). Только `walkable` и `terrain_id` меняются через diff.
- Reveal state — **всегда** runtime-only, не персистится. После загрузки
  сейва все горы закрыты, resolver при первом кадре откроет ту, в которой
  стоит игрок.
- `mountain_id == 0` означает «не часть горы» — такие плитки крышу не
  получают, независимо от elevation.
- Крыша никогда не закрывает наружный обзор игроку: если его `mountain_id
  == 0`, все крыши вокруг него видимы на 100% (текущее значение их alpha).

### Типичные ошибки, которые надо не делать

1. **«Давай посмотрим, есть ли у игрока крыша над головой».** Нет. Это
   raycasting в сцене и привязка presentation к gameplay. Используй
   `mountain_id` через packet lookup.
2. **«Детектим вход как “игрок рядом со стеной с diff-проходом”».** Нет.
   Вход — derived из `mountain_id + diff + neighbor mountain_id`,
   считается один раз на копание.
3. **«Сохраним текущее reveal в сейве, чтобы было красиво».** Нет. При
   загрузке всё равно придётся перевычислить из позиции игрока, и
   полусохранённое состояние даст рассинхрон.
4. **«Загрузим settings из ресурса в interactive path».** Нет. Settings
   читаются один раз при `reset_for_new_game`/`load_world_state` и
   пакуются в packed array, который кэшируется в `WorldStreamer`.
5. **«Flood-fill при копании для проверки, “пробил ли насквозь”».** Нет.
   Эта проверка не нужна: вход — локальная проверка соседей.

---

## 9. Исследование: индустриальные паттерны

Что было изучено / чем вдохновлены решения:

- **Minecraft 1.18 (Caves & Cliffs)** — многослойный noise, domain warp для
  горных хребтов, stable biome noise ≥ 1000-block wavelength. Наш macro-FBM
  ≥ scale=512 — та же идея.
- **No Man's Sky** — generative mountains via stacked ridged multifractal
  noise. Наш `ruggedness * ridge * smoothstep(macro)` — упрощённая версия.
- **Dwarf Fortress** — regional identity через deterministic anchors
  (civilization sites). Наш `mountain_id` через anchor-cell — тот же
  паттерн.
- **RimWorld** — подземные комнаты «видны снаружи только вход». Реализовано
  через hide-overlay, который убирается при входе в «indoor area». Наш
  roof-layer + reveal registry — прямой аналог, но per-mountain, а не
  per-room.
- **Factorio** — infinite world, chunk-based procedural generation, all
  heavy lifting in C++. Наш native `WorldCore` + packet boundary — тот же
  принцип.
- **Terraria** — масштаб гор меньше, но тот же принцип static noise base +
  player diff. Никакого «real-time reshaping terrain» — корневой закон.

Общий вывод всех этих систем: **разделение base (детерминированный noise) +
identity (sparse anchors / regions) + overlay (runtime presentation) — это
не опциональная оптимизация, это единственный способ сделать бесконечный
мир без хитчей.** Наш ADR-0003 («immutable base + runtime diff») ровно об
этом же.

Источники noise-библиотек:
- FastNoise Lite: https://github.com/Auburn/FastNoiseLite (header-only, MIT)
- OpenSimplex2: https://github.com/KdotJPG/OpenSimplex2 (CC0)
Рекомендация: **FastNoise Lite** — активно поддерживается, C++ header-only,
поддерживает domain warp, ridged multifractal, cellular noise из коробки.

---

## 10. Решения по открытым вопросам (Resolved Decisions)

Все пять вопросов закрыты. Ниже — canonical decision blocks (на английском,
для spec-extraction) + обоснование (на русском).

### Q1. Roof ownership per mountain_id, not per chunk

> **Decision:** roof presentation is owned per `mountain_id` inside a chunk,
> not per chunk. Each `ChunkView` keeps `Dictionary[int, Dictionary[int,
> TileMapLayer]] roof_layers_by_mountain`, where the nested key is the
> presentation terrain (`TERRAIN_MOUNTAIN_WALL` or `TERRAIN_MOUNTAIN_FOOT`).
> Reveal alpha/mask state is shared per mountain across those presentation
> layers, so adjacent mountains in the same chunk can open/close independently.
> A single aggregated roof alpha per chunk is **forbidden** because it
> violates the gameplay invariant "opening mountain A must not reveal
> mountain B".

**Обоснование.** Агрегированный alpha корректен только при одиночных
массивах. На стыке гор он ломает главный UX-инвариант системы. 32×32 чанк
при нормальной генерации содержит 0–2 `mountain_id`, редко 3 — несколько
`TileMapLayer` здесь ничтожная цена в сравнении с необходимостью чинить
архитектуру reveal позже.

**Guardrail:** дебаг-метрика `roof_layers_per_chunk_max`. Если > 4 →
warning: либо `density` слишком высок, либо `anchor_cell_size` режет
ownership слишком шумно.

См. §6.1 для детализации кода.

### Q2. Entrance is derived, mutation + rebuild paths share one function

> **Decision:** entrance state is **derived**, not persisted. Interactive
> mutations use local recompute on the changed tile and its 4-neighbors.
> Save/load and cold chunk rebuild paths recompute entrance flags from
> `base + diff` for all dirty tiles in the chunk. Single source of truth is
> `recompute_entrance_flag(world_tile)`; both mutation-time and load-time
> paths call the same function.

**Обоснование.** V0 runtime требует: одна tile-mutation = один локальный
diff write + bounded local visual patch. Interactive путь не должен
платить за полный пересчёт. Но при загрузке сейва всё равно нужен
разовый пересчёт из `base + diff` под loading screen — это boot/load work
по ADR-0001, оно допустимо. Главное — **одна функция** на оба пути, чтобы
логика entrance не раздваивалась.

**Следствия для schema (обязательные).**
- `is_entrance` **не** хранится в `ChunkDiffFile` — только канонические
  изменения тайла. Presentation-флаги восстанавливаются.
- `is_entrance` живёт в runtime-only кэше внутри `ChunkView` (например,
  `PackedByteArray _entrance_cache`).
- Функция `recompute_entrance_flag(world_tile)` — одна точка истины,
  вызывается и на копании (5 тайлов), и на load/rebuild (все dirty тайлы
  чанка).

### Q3. SDF door-opening deferred, first playable uses plain alpha fade

> **Decision:** first playable mountain reveal uses only time-based alpha
> fade (`modulate.a`) on roof presentation. Spatial reveal effects (SDF
> fan-out / door-opening / wave expansion) are explicitly deferred. They
> are presentation-only polish and must not change ownership, topology, or
> save semantics.

**Обоснование.** Сначала правильная ownership-модель, правильный reveal
per component, отсутствие хитчей, корректный save/load. Наличие готового
шейдера-примитива (`mountain_cover_overlay.gdshader`) не повод тащить его
в первую итерацию — это отдельный presentation polish, который может
родить баги на reload, multi-entrance и chunk boundaries. Равномерный fade
0.25–0.35 сек читается нормально.

**Защитный инвариант.** Даже когда SDF будет добавлен на M5+, он
**никогда** не может менять ownership, topology или save. Только
presentation-слой.

### Q4. Settings in world.json, world_version stays a version boundary

> **Decision:** canonical generation inputs are stored explicitly in
> `world.json` under `worldgen_settings`. `world_version` remains an
> algorithm/schema version boundary, not a hash of runtime settings. New
> worlds read defaults from resource files; existing saves always load
> their own embedded `worldgen_settings`. Optional debug-only
> `worldgen_signature` may be stored for diagnostics, but it is not a
> source of truth.

**Обоснование.** `world_version` должен оставаться **читаемым** integer,
не opaque хэшем. Это критично для debug, changelog, migration. Баланс-патч
в репозитории не ломает существующие сейвы, только влияет на новые миры.
Ключ namespaced (`worldgen_settings.mountains`), потому что туда же
потом пойдут `biomes`, `climate`.

См. §4.3 для точной формы `world.json`.

### Q5. Subsurface is separate domain, surface mountains pass only a modifier

> **Decision:** subsurface remains a separate generation and runtime
> domain. Surface `mountain_id` does **not** persist as canonical identity
> below z=0. At most, surface mountains contribute a local generation
> modifier (for example `under_mountain_strength`) to z=-1 generation.
> Roof/reveal/ownership/topology do not cross the surface–subsurface
> boundary.

**Обоснование.** ADR-0006 жёстко фиксирует: surface и subsurface —
отдельные world layers, surface code не знает underground internals,
cover/roof skip `z != 0`. Протаскивание surface `mountain_id` вниз —
прямое размывание границы, которую ADR уже прибил. При этом фантазия
«под горой глубже/плотнее/опаснее» сохраняется — через дешёвый hint в
генераторе z=-1.

**Что конкретно делает hint.**
- Underground generator на z=-1 получает чистую функцию
  `under_mountain_strength(wx, wy) -> float` (0.0..1.0).
- Внутри — тот же sampler elevation от surface mountain field, но
  **без** публикации identity/reveal/roof вниз.
- Underground использует это значение как модификатор: плотность камня,
  шанс руды, частота caves, тип стен.
- Никакая surface-сущность (roof layer, reveal registry, resolver) не
  виздна subsurface-коду.

---

## 11. Итоговый чеклист соответствия governance

- [x] LAW 0: все 12 вопросов адресованы явно по секциям.
- [x] LAW 1: тяжёлый цикл по 1024 тайлам — C++, не GDScript.
- [x] LAW 2: main thread только publish + apply_cell.
- [x] LAW 3: `generate_chunk_packet` — чистая функция.
- [x] LAW 4: `WORLD_VERSION` bump прописан явно.
- [x] LAW 5: база иммутабельна, крыша — derived, reveal — transient.
- [x] LAW 6: один пакет на чанк, `ChunkPacketV1` — packed arrays.
- [x] LAW 7: никаких `load()` в runtime — все ресурсы preload в
  `WorldTileSetFactory`.
- [x] LAW 8: owners: `WorldCore` = base, `WorldDiffStore` = diff,
  `MountainRevealRegistry` = reveal, `ChunkView` = presentation.
- [x] LAW 9: assert на `WorldCore` — никакого GDScript fallback.
- [x] LAW 10: чанк становится `visible = true` только после publish
  завершён (текущее поведение сохраняется).
- [x] LAW 11: dirty units прописаны в §5.
- [x] LAW 12: глобального prepass нет, всё локально per-chunk + per
  anchor-cell.
- [x] LAW 13: никаких `add_child` на тайл — всё через TileMapLayer.
- [x] ADR-0002: wrap-safe X при сэмплировании.
- [x] ADR-0003: base+diff split соблюдён.
- [x] ADR-0006: surface/subsurface остаются разделены.
- [x] ADR-0007: worldgen не читает environment runtime, reveal не лезет в
  genfield.

---

## 12. Файлы, которые надо будет изменить (полный список)

### Новые

- `docs/02_system_specs/world/mountain_generation.md` (spec, M0)
- `gdextension/src/third_party/FastNoiseLite.h` (M1)
- `gdextension/src/mountain_field.{h,cpp}` (M1)
- `core/systems/world/mountain_reveal_registry.gd` (M2, возможно autoload)
- `core/systems/world/mountain_resolver.gd` (M2)
- `data/balance/mountain_gen_settings.tres` (M4)
- `core/resources/mountain_gen_settings.gd` (class_name resource, M4)

### Изменяемые

- `gdextension/src/world_core.{h,cpp}` — расширить packet, принять settings
- `gdextension/SConstruct` — добавить mountain_field в сборку
- `core/systems/world/world_runtime_constants.gd` — bump `WORLD_VERSION`,
  добавить константы полей и битов `mountain_flags`
- `core/systems/world/world_streamer.gd` — принять новые поля в packet,
  передать в ChunkView; читать `MountainGenSettings` при reset/load;
  сохранять `settings_packed` в `world.json`
- `core/systems/world/chunk_view.gd` — добавить `roof_layers_by_mountain`,
  `set_roof_alpha`, reveal-subscription
- `core/systems/world/world_tile_set_factory.gd` — `get_roof_tile_set(terrain_id)`
- `core/systems/world/terrain_presentation_registry.gd` — регистрация
  mountain_wall, mountain_foot
- `core/entities/player/player.gd` — вызов `MountainResolver.update_*`
- `core/autoloads/event_bus.gd` — `mountain_revealed`, `mountain_concealed`
- `core/autoloads/save_collectors.gd`, `save_appliers.gd`,
  `save_io.gd` — хранение `settings_packed` в `world.json`
- `scenes/ui/main_menu.gd` (или соответствующий new-game экран) —
  слайдеры настроек

### Абсолютно не трогаем

- `BuildingSystem`, `PowerSystem` — не зависят от гор.
- Existing V0 plains pipeline — остаётся как есть. Горы — **additive**.
- Legacy удалённые файлы (64×64 мира и т.п.) — не оживляем.

---

## 13. Что этот документ НЕ делает

- Не заменяет spec. Перед первым PR всё равно нужен approved
  `docs/02_system_specs/world/mountain_generation.md` с полной структурой
  по шаблону WORKFLOW.md.
- Не фиксирует конкретные значения noise frequency — они подбираются на
  M1 итерации эмпирически, в пределах ranges, прописанных в settings.
- Не авторизует реализацию — только design foundation. Next step:
  согласовать с пользователем → оформить spec → по одной итерации.

---

*Конец документа.*
