---
title: Natural World Generation Overhaul
doc_type: system_spec
status: proposal
owner: engineering+design
source_of_truth: false
version: 0.3
last_updated: 2026-04-04
depends_on:
  - world_generation_foundation.md
  - DATA_CONTRACTS.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
related_docs:
  - native_chunk_generation_spec.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Natural World Generation Overhaul

## Purpose

Текущая система генерации мира архитектурно здорова (детерминизм, слои, chunk streaming, data-driven биомы), но визуально производит мир, который не выглядит натуральным.

Этот документ — спецификация поэтапного перевода генерации на физически мотивированные алгоритмы при сохранении всех существующих архитектурных контрактов: детерминизма, chunk-streaming, data-driven registries, command pattern, compute→apply.

## Direction Reset (2026-04-04)

Runtime landmark validation, soft-fix remediation, wow-region boot checks, and any form of lucky-seed search are rejected and removed from the active direction of this spec.

Новый принцип:
- мир должен становиться выразительным по конструкции, а не через post-hoc проверку «достаточно ли красиво»
- seed задаёт макро-скелет мира, а не становится кандидатом на отбраковку
- runtime bootstrap строит один детерминированный мир для запрошенного seed и не ищет соседний «получше»
- offline tooling может анализировать миры, но не подменяет конструктивный дизайн мира lucky-seed curator'ом

## Проблемный диагноз

### P1. Одна октава шума вместо FBM

`WorldNoiseUtils` выставляет `fractal_octaves`, `fractal_gain`, `fractal_lacunarity`, но не устанавливает `fractal_type` (Godot default = `TYPE_NONE`). Все каналы работают как single-octave simplex. Результат — мягкие блобы без мелкой детализации.

### P2. Реки — направленные band'ы

`LargeStructureSampler` генерирует реки как band'ы с одним direction vector `(-0.31, 0.90, 0.30)`, spacing 480 tiles, warp noise. Реки не следуют рельефу, не имеют притоков, не расширяются к устью, не формируют бассейны.

### P3. Горы — параллельные band'ы

Ridge system — два direction vector'а с band профилями. Результат — параллельные полосы с вариацией, но без иерархии spine→branches→foothills→valleys.

### P4. Отсутствие причинно-следственных каналов

Каналы `height`, `temperature`, `moisture`, `ruggedness`, `flora_density` — независимые шумы. Moisture не зависит от высоты (rain shadow), drainage не существует как канал, continentalness отсутствует. Биомы не выглядят как следствие физики.

### P5. Нет эрозии

Рельеф — чистый шум без следов водной/термической эрозии. Нет V-образных долин, нет осадочных предгорий, нет террас.

### P6. Winner-takes-all биомы

`BiomeResolver` выбирает одного победителя per tile. Нет экотонов, нет мягких переходов, нет gradient-based flora blending.

### P7. Нет конструктивного макро-скелета мира

Процедурный мир статистически однороден. Выразительные формы не задаются как причинная структура мира заранее. Плохое решение — пытаться после полной генерации проверять, «достаточно ли красиво», и чинить thresholds или искать соседний seed. Правильное решение — строить запоминающиеся реки, хребты и бассейны как следствие макро-скелета мира.

### P8. Нет широтно-зависимой гидрологии

Мир цилиндрический: верх (Y min) — вечная зима, низ (Y max) — выжженная пустошь. Но текущая генерация не использует это. Реки не начинаются от ледников, не пересыхают в горячей зоне. Temperature latitude gradient влияет только на biome scoring, но не на drainage, moisture transport или terrain type. Нет озёр как геологических объектов.

### P9. Нет озёр

Текущий terrain pipeline знает только GROUND, WATER (реки), SAND, ROCK. Озёра как отдельные водоёмы — стоячие, у подножия гор, ледниковые, пойменные — не генерируются. Sink filling в drainage pipeline полностью заполняет все впадины, вместо того чтобы оставлять крупные как озёра.

## Scope

Этот документ владеет:

- алгоритмами и data contracts для глобального пре-пасса (drainage, ridge skeleton, erosion proxy, rain shadow)
- новыми каналами (continentalness, drainage, slope, rain_shadow)
- переходом от band-based к drainage-based рек
- переходом от band-based к skeleton-based гор
- ecotone system
- конструктивным макро-скелетом мира как будущей заменой отвергнутой runtime landmark grammar
- atlas / diagnostic tooling для offline анализа, а не для runtime seed curation
- изменениями в `WorldGenBalance`
- широтно-зависимой гидрологией (latitude-driven evaporation, glacial sources)
- генерацией озёр (lake detection из modified sink filling)
- полярными terrain modifiers (ice/snow overlay, scorched overlay)

Этот документ не владеет:

- финальным контентным каталогом биомов
- runtime performance law (см. PERFORMANCE_CONTRACTS.md)
- рендерингом и presentation layer
- save/load форматом

## Архитектурные ограничения (наследованы)

1. **Детерминизм**: seed + canonical coordinates = identical result
2. **Chunk streaming**: chunk — единица стриминга, не источник мировой правды
3. **Immutable base + runtime diff**: генерация не мутируется gameplay'ем
4. **Compute→Apply**: тяжёлые вычисления — pure data, без scene tree
5. **6ms/frame budget**: runtime streaming не превышает бюджет
6. **Cylindrical wrap**: X wraps, Y latitude
7. **Data-driven registries**: контент через .tres + реестры
8. **No interactive-path rebuild**: player actions не форсируют регенерацию

## Новый архитектурный элемент: Global Pre-pass

### Обоснование

Drainage network, ridge skeleton, erosion и rain shadow требуют глобального контекста, который невозможно вычислить per-tile в streaming pipeline. Необходим глобальный пре-пасс при `initialize_world()`.

### Coarse Grid

- Resolution: 1 точка на 32 тайла
- Для мира 4096×8192: сетка 128×256 = 32 768 точек
- Формат: `PackedFloat32Array` для каждого канала, row-major indexing
- Координаты: `grid_x = world_x / 32`, `grid_y = world_y / 32`
- Wrap-aware: X-координата заворачивается на grid_width

### Ownership

- **Класс**: `WorldPrePass` (RefCounted)
- **Owner**: `WorldGenerator`
- **Lifecycle**: вычисляется один раз в `initialize_world()` после noise init, до chunk generation
- **Read access**: `PlanetSampler`, `LargeStructureSampler` (заменённые), `BiomeResolver`, `SurfaceTerrainResolver` — через lookup по world coordinate → interpolated grid value
- **Write access**: только `WorldPrePass` внутри `compute()`
- **Threading**: compute — чистый data, может быть вынесен в worker thread или GDExtension
- **Persistence**: не сохраняется; детерминистично пересчитывается из seed

### Performance budget

- Target: < 500ms для GDScript, < 100ms для GDExtension (C++)
- Это boot-time cost, не runtime
- Не влияет на frame budget

### Lookup API

```gdscript
class_name WorldPrePass
extends RefCounted

## Возвращает интерполированное значение канала в мировых координатах.
## Использует биллинейную интерполяцию между узлами coarse grid.
func sample(channel: StringName, world_pos: Vector2i) -> float:
    pass

## Прямой доступ к grid-ячейке (для debug/tooling).
func get_grid_value(channel: StringName, grid_x: int, grid_y: int) -> float:
    pass
```

---

## Фаза 0: Octave Fix

### Проблема

`WorldNoiseUtils` (или код, создающий `FastNoiseLite` инстансы) не устанавливает `noise.fractal_type`. Godot default = `FastNoiseLite.TYPE_NONE` → single octave.

### Решение

Для каждого шумового инстанса в `PlanetSampler`, `LargeStructureSampler`, `LocalVariationResolver`:

```gdscript
noise.fractal_type = FastNoiseLite.TYPE_FBM
```

### Affected files

- `core/systems/world/planet_sampler.gd`
- `core/systems/world/large_structure_sampler.gd`
- `core/systems/world/local_variation_resolver.gd`
- `core/systems/world/world_noise_utils.gd` (если централизованное создание)
- `gdextension/src/chunk_generator.cpp` (native path должен соответствовать)

### Побочные эффекты

Все текущие пороги (`river_min_strength`, `mountain_base_threshold`, банды биомов) настроены под single-octave диапазон. После включения FBM диапазон значений шума изменится (больше экстремальных значений, другое распределение). **Необходим проход по всем threshold'ам в `WorldGenBalance` и biome .tres ресурсах.**

### Acceptance criteria

- [ ] Все `FastNoiseLite` инстансы в generation pipeline имеют `fractal_type = TYPE_FBM`
- [ ] Native C++ path использует те же fractal параметры
- [ ] Threshold'ы в `WorldGenBalance` перенастроены под новый диапазон
- [ ] Biome ranges в .tres ресурсах перенастроены
- [ ] Визуально: terrain имеет multi-scale детализацию (крупные формы + мелкая вариация)
- [ ] Wrap-seam проверен на отсутствие артефактов

---

## Фаза 1: Global Pre-pass Infrastructure

### Gate перед реализацией

- Фаза 1 не стартует как код-задача, пока не закрыты acceptance criteria Фазы 0 (`FBM` baseline + retune thresholds / biome ranges).
- Фаза 1 слишком велика для одной agent-задачи; практический вход в неё всегда идёт через одну явную итерацию за раз.
- Для текущего runtime pre-pass по Y ограничивается существующим latitude-contract, а не бесконечным миром:
  - `prepass_min_y = equator_tile_y - latitude_half_span_tiles`
  - `prepass_max_y = equator_tile_y + latitude_half_span_tiles`
  - lookup вне этого диапазона clamp'ится к ближайшей граничной строке coarse grid, пока отдельный vertical-world contract не утверждён.

### Итерация 1.1 — `WorldPrePass` shell + coarse heightfield

**Цель:** ввести минимальный boot-time owner для global pre-pass и вычислить только coarse heightfield без изменения текущей terrain / biome / large-structure семантики.

**Что делается:**

- добавить `core/systems/world/world_pre_pass.gd` (`RefCounted`) с lifecycle `configure(...)`, `compute()`, `sample()`, `get_grid_value()`
- хранить только grid metadata и канал `height`; drainage / lakes / ridges / erosion / rain shadow в эту итерацию не входят
- вычислять `grid_width` из wrapped X-span, а `grid_height` из `latitude_half_span_tiles * 2`, используя `prepass_grid_step`
- в `WorldGenerator.initialize_world()` создавать и вычислять `WorldPrePass` после setup sampler'ов и до `_setup_compute_context()`
- пробросить ссылку на pre-pass в `WorldComputeContext` только как read-only holder; действующие resolver'ы и sampler'ы в этой итерации не меняют своё поведение
- добавить только `prepass_grid_step` в `WorldGenBalance` и `world_gen_balance.tres`

**Что не меняется:**

- `LargeStructureSampler`, `BiomeResolver`, `SurfaceTerrainResolver`, `ChunkContentBuilder` продолжают работать по текущему pipeline
- native chunk generation path не читает pre-pass в этой итерации
- terrain thresholds, biome `.tres` ranges и визуальные правила не ретюнятся; это остаётся в Фазе 0
- `ChunkManager`, `Chunk`, mining / topology / reveal / presentation не затрагиваются

**Файлы, которые можно трогать:**

- `core/autoloads/world_generator.gd`
- `core/systems/world/world_compute_context.gd`
- `core/systems/world/world_pre_pass.gd` (new)
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/natural_world_generation_overhaul.md`

**Файлы, которые нельзя трогать в Iteration 1.1:**

- `core/systems/world/large_structure_sampler.gd`
- `core/systems/world/biome_resolver.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `gdextension/src/chunk_generator.cpp`
- biome `.tres` resources
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

**Required contract and API updates:**

- `DATA_CONTRACTS.md`: не обновляется в Iteration 1.1, если `WorldPrePass` остаётся boot-time scaffolding без нового внешнего owner/read contract за пределами `WorldGenerator` / `WorldComputeContext`
- `PUBLIC_API.md`: не обновляется в Iteration 1.1, если не появляется новый safe entrypoint для внешних runtime callers
- если scope расширяется дальше inert shell/bootstrap ownership, итерацию надо остановить и обновить канонические docs в том же таске

**Acceptance tests для Iteration 1.1:**

- [ ] `WorldPrePass.compute()` создаёт `_height_grid` размера `grid_width * grid_height`
- [ ] одинаковые `seed + canonical world_pos` дают одинаковый `sample(&"height", world_pos)`
- [ ] `sample(&"height", pos)` seam-safe по X-wrap (`x` и `x ± world_wrap_width_tiles` дают один результат)
- [ ] `WorldGenerator.initialize_world()` создаёт и вычисляет pre-pass до `_setup_compute_context()` и `_setup_chunk_content_builder()`
- [ ] chunk terrain output до и после Iteration 1.1 бит-в-бит совпадает; pre-pass в этой итерации — inert scaffolding
- [ ] если acceptance Фазы 0 не подтверждены, coding по Iteration 1.1 не начинается

### Шаг 1.1: Coarse Heightfield

В рамках `WorldPrePass.compute()`:

1. Для каждой точки coarse grid: sample `PlanetSampler.height` (уже с FBM после Фазы 0)
2. Результат: `_height_grid: PackedFloat32Array` [grid_width × grid_height]

### Шаг 1.2: Sink Filling с Lake Detection

Heightfield из шума содержит локальные минимумы, из которых вода «не может вытечь». Для корректного drainage необходимо заполнить ямы — но крупные и глубокие впадины сохраняются как **озёра**.

Алгоритм: Modified Priority-Flood (Barnes et al., 2014) с lake extraction.

**Проход 1: обнаружение впадин.**

```
1. Flood-fill из границ (Y = 0, Y = max).
   X-граница не нужна (wrap world — вода может перетечь по X).
2. Для каждой ячейки из priority queue (min-height first):
   a. Для каждого из 8 соседей:
      - если сосед не посещён:
        - если height[сосед] < height[текущий]:
          sink_depth = height[текущий] - height[сосед]
          пометить как часть sink basin
        - добавить соседа в queue
        - пометить посещённым
3. Для каждого обнаруженного sink basin:
   - подсчитать area (количество ячеек) и max_depth
```

**Проход 2: классификация — озеро или заполнение.**

```
for each sink basin:
    if area >= lake_min_area AND max_depth >= lake_min_depth:
        → пометить как LAKE
        → lake_surface_height = spill_height (высота точки перелива)
        → все ячейки с height < lake_surface_height → terrain = WATER, height = lake_surface_height
        → drainage из озера: одна точка стока (spill point) → передаёт accumulated inflow downstream
    else:
        → заполнить яму как в стандартном Priority-Flood
        → filled_height[cell] = spill_height
```

**Типы озёр (определяются post-hoc по контексту):**

| Тип | Условие | Характер |
|-----|---------|----------|
| Горное | `ridge_strength > 0.3` у ≥30% береговых ячеек | Глубокое, малое, у подножия хребта |
| Ледниковое | `latitude_temperature < frozen_lake_threshold` | Elongated, у границы cold zone |
| Пойменное | `accumulation_inflow > 500` AND `slope < 0.1` | Большое, мелкое, вдоль крупной реки |
| Тектоническое | `area > 50 grid cells` AND `max_depth > 0.15` | Крупное, глубокое, в тектонической впадине |

Тип озера влияет на:
- biome resolution вокруг озера (береговой биом)
- flora placement (береговая растительность)
- feature hooks (POI у озера)

**Lake output:**

```gdscript
class LakeRecord:
    var id: int
    var grid_cells: PackedInt32Array        # indices в coarse grid
    var spill_point: Vector2i               # grid координата точки перелива
    var surface_height: float               # уровень воды
    var max_depth: float                    # максимальная глубина
    var area_grid_cells: int                # площадь в grid ячейках
    var lake_type: StringName               # "mountain", "glacial", "floodplain", "tectonic"
    var inflow_accumulation: float          # суммарный входящий drainage
```

Результат: `_filled_height_grid` (с озёрами на surface height), `_lake_records: Array[LakeRecord]`, `_lake_mask: PackedByteArray` (0 = не озеро, lake_id для ячеек озера).

### New WorldGenBalance parameters (lakes)

```gdscript
@export_group("Lakes")
@export_range(3, 100) var prepass_lake_min_area: int = 8
@export_range(0.01, 0.3) var prepass_lake_min_depth: float = 0.04
@export_range(0.0, 0.5) var prepass_frozen_lake_temperature: float = 0.15
```

Сложность: O(N log N), для 33K точек — <15ms (незначительное увеличение из-за lake classification).

### Шаг 1.3: Flow Direction (D8)

Для каждой точки filled grid: определить направление стока — в какого из 8 соседей «стекает» вода (наибольший downhill gradient). На плоских участках — к ближайшему non-flat.

```
flow_dir[i] = argmax_neighbor(filled_height[i] - filled_height[neighbor])
```

Формат: `_flow_dir_grid: PackedByteArray` (0–7 = 8 направлений, 255 = sink/edge)

### Шаг 1.4: Flow Accumulation с Latitude-Dependent Evaporation

Topological sort по flow direction (от вершин к стокам), каждая ячейка передаёт свой accumulation downstream. Ключевое дополнение: **широтно-зависимое испарение** уменьшает поток в горячих зонах и замораживает его в холодных.

```
temperature[i] = PlanetSampler.temperature at grid cell i  # [0,1], учитывает latitude

for each cell i:
    # Базовый вклад: в холодных зонах — ледниковый сток (талая вода),
    # в умеренных — дождевой сток, в горячих — минимальный
    if temperature[i] < glacial_melt_temperature:
        # Холодный полюс: вода появляется от таяния ледников на границе зоны
        glacial_proximity = clamp((glacial_melt_temperature - temperature[i]) / 0.15, 0, 1)
        base_contribution = 1.0 + glacial_melt_bonus * (1.0 - glacial_proximity)
        # Пик стока — на границе ледника, не в центре ледяной шапки
    else:
        base_contribution = 1.0

    accumulation[i] = base_contribution

for each cell in topological order (highest first):
    target = flow_dir[cell]

    # Испарение: горячие зоны теряют воду
    evaporation_loss = accumulation[cell] * latitude_evaporation_rate * temperature[cell]^2

    # Передача: что не испарилось — идёт downstream
    transfer = max(0, accumulation[cell] - evaporation_loss)
    accumulation[target] += transfer
```

**Эффект по широтным зонам:**

| Зона | Temperature | Поведение рек |
|------|-------------|---------------|
| Вечная зима (Y min) | 0.0 – 0.15 | Замёрзшие русла, минимальный flow. Ледники как «хранилища воды». |
| Граница ледника | 0.15 – 0.25 | Максимальный glacial melt → истоки крупнейших рек. Ледниковые озёра. |
| Умеренная зона | 0.25 – 0.65 | Полноводные реки, дельты, пойменные озёра. Максимальное биоразнообразие. |
| Жаркая зона | 0.65 – 0.85 | Реки сужаются, испарение растёт. Сезонные русла. |
| Выжженная пустошь (Y max) | 0.85 – 1.0 | Реки пересыхают. Сухие русла (wadis). Солончаки вместо озёр. |

**Замёрзшие реки:** В зоне `temperature < frozen_river_threshold` (default: 0.18) реки получают terrain type ICE вместо WATER. Визуально — замёрзшая поверхность, проходимая пешком, но с другими gameplay свойствами (скольжение, хрупкость).

Формат: `_accumulation_grid: PackedFloat32Array`

### New WorldGenBalance parameters (latitude hydrology)

```gdscript
@export_group("Latitude Hydrology")
@export_range(0.0, 0.5) var prepass_glacial_melt_temperature: float = 0.22
@export_range(0.0, 5.0) var prepass_glacial_melt_bonus: float = 2.5
@export_range(0.0, 0.3) var prepass_latitude_evaporation_rate: float = 0.08
@export_range(0.0, 0.3) var prepass_frozen_river_threshold: float = 0.18
```

### Шаг 1.5: Drainage Channel

```
drainage[i] = clamp(log2(accumulation[i]) / log2(max_accumulation), 0.0, 1.0)
```

Это нормализованный [0,1] канал, доступный через `WorldPrePass.sample(&"drainage", pos)`.

### Шаг 1.6: River Extraction

Ячейки с `accumulation > river_threshold` формируют русло. Русло — граф на coarse grid.

```
river_threshold = WorldGenBalance.prepass_river_accumulation_threshold  # default: 200
```

На tile-level resolution: distance field от ближайшего русла (интерполяция coarse grid → tile). Ширина реки:

```
river_width_tiles = base_river_width + width_scale * log2(accumulation / river_threshold)
```

Где `base_river_width = 2`, `width_scale = 6` (настраиваемы в `WorldGenBalance`).

### Шаг 1.7: Floodplain

Зона поймы — расширение русла:

```
floodplain_width = river_width * floodplain_multiplier  # default: 3.0
```

Strength = smooth falloff от русла к краю поймы.

### New WorldGenBalance parameters

```gdscript
@export_group("Pre-pass Grid")
@export_range(8, 128) var prepass_grid_step: int = 32
@export_range(50, 5000) var prepass_river_accumulation_threshold: int = 200
@export_range(1.0, 20.0) var prepass_river_base_width: float = 2.0
@export_range(1.0, 20.0) var prepass_river_width_scale: float = 6.0
@export_range(1.5, 8.0) var prepass_floodplain_multiplier: float = 3.0
```

### Acceptance criteria (Фаза 1, drainage)

- [ ] `WorldPrePass` создаётся в `WorldGenerator.initialize_world()` и доступен для чтения всем sampling/resolve компонентам
- [ ] Heightfield, filled heightfield, flow direction, flow accumulation вычислены корректно
- [ ] `drainage` канал доступен через `WorldPrePass.sample()`
- [ ] Реки следуют рельефу (текут вниз)
- [ ] Притоки сливаются (accumulation суммируется)
- [ ] Ширина реки растёт от истока к устью
- [ ] Устья — у самых низких точек terrain (побережье/край мира)
- [ ] Озёра обнаруживаются при sink filling и сохраняются как LakeRecord
- [ ] Озёра корректно интегрированы в drainage (spill point → downstream)
- [ ] Latitude evaporation: реки теряют accumulation в горячих зонах
- [ ] Glacial melt: повышенный базовый сток у границы ледника
- [ ] `initialize_world()` укладывается в < 1s (GDScript) / < 200ms (native)
- [ ] Wrap-seam: реки корректно обрабатывают X-wrap

---

## Фаза 1 (продолжение): Ridge Skeleton

### Шаг 1.8: Tectonic Spine Seeds

Вместо direction-band'ов — генерация «тектонических зёрен» как стартовых точек горных систем.

На coarse grid:

1. Poisson disk sampling с минимальным расстоянием `min_spine_distance` (default: 80 grid cells = 2560 tiles) для размещения spine seeds.
2. Количество seeds: `target_spine_count` (default: 3–6, зависит от мирового размера).
3. Seed placement biased к зонам с high ruggedness + high height.
4. Каждый seed получает:
   - `position`: Vector2i на grid
   - `strength`: float [0.5, 1.0] (из height + ruggedness)
   - `direction_bias`: Vector2 (локальный градиент ruggedness, задаёт предпочтительное направление хребта)

Детерминизм: Poisson disk sampling через детерминистичный hash от seed.

### Шаг 1.9: Ridge Graph Construction

Соединение spine seeds в граф хребтов:

1. Для каждого spine seed: grow ridge path по grid, шагая в направлении `direction_bias` с noise perturbation.
2. На каждом шаге: выбор следующей ячейки из 3 кандидатов (forward, forward-left, forward-right), weighted по:
   - height (prefer high)
   - ruggedness (prefer rough)
   - continuation_inertia (prefer straight)
   - noise perturbation (natural variation)
3. Ridge path растёт в обе стороны от seed, пока:
   - height падает ниже `ridge_min_height` (default: 0.35)
   - или достигнут max_ridge_length (default: 200 grid steps = 6400 tiles)
   - или пересечение с другим ridge (merge, не overlap)
4. Branch ridges: от основных ridge path ответвления с probability `branch_probability` (default: 0.15 per grid step), shorter length (max_branch_length = 60 grid steps).

### Шаг 1.10: Ridge Spline Smoothing

Raw ridge paths (polylines на grid) → smoothed splines:

1. Catmull-Rom или cubic B-spline через control points (каждые 4-6 grid points).
2. Результат: гладкие кривые, не ломаные линии.
3. Width profile вдоль spline: widest в центре (highest point), сужается к концам.

### Шаг 1.11: Ridge Distance Field

Для tile-level lookup: каждый ridge spline преобразуется в distance field на coarse grid, затем интерполируется на tile resolution.

```
ridge_strength(world_pos) = max over all ridges:
    profile(distance_to_nearest_ridge_spline / ridge_half_width)
```

Где `profile(t) = smoothstep(1.0, 0.0, t)` — плавный спад от центра к краю.

### Шаг 1.12: Mountain Mass

```
mountain_mass = ridge_strength * height_factor * ruggedness_factor
height_factor = clamp((height - 0.25) / 0.35, 0, 1)
ruggedness_factor = clamp(ruggedness / 0.6, 0, 1)
```

### New WorldGenBalance parameters

```gdscript
@export_group("Ridge Skeleton")
@export_range(2, 12) var prepass_target_spine_count: int = 4
@export_range(20, 200) var prepass_min_spine_distance_grid: int = 80
@export_range(50, 500) var prepass_max_ridge_length_grid: int = 200
@export_range(10, 200) var prepass_max_branch_length_grid: int = 60
@export_range(0.0, 0.5) var prepass_branch_probability: float = 0.15
@export_range(0.1, 0.7) var prepass_ridge_min_height: float = 0.35
@export_range(0.3, 1.0) var prepass_ridge_continuation_inertia: float = 0.65
```

### Acceptance criteria (ridge skeleton)

- [ ] Spine seeds размещены Poisson disk на coarse grid
- [ ] Ridge paths растут по рельефу, не параллельными полосами
- [ ] Branch ridges отходят от main ridges
- [ ] Spline smoothing даёт плавные хребты
- [ ] `ridge_strength` и `mountain_mass` доступны через `WorldPrePass.sample()`
- [ ] Визуально: горы образуют иерархию spine→branches→foothills, не полосы
- [ ] Старый `LargeStructureSampler` ridge code заменён lookup'ами из pre-pass

---

## Фаза 1 (продолжение): Erosion Proxy + Rain Shadow

### Шаг 1.13: Cheap Erosion Proxy

Не полная гидравлическая эрозия, а proxy-операции на coarse grid:

**Valley carving:**
```
valley_depth[i] = erosion_valley_strength * sqrt(accumulation[i]) * local_slope[i]
eroded_height[i] = filled_height[i] - valley_depth[i]
```

Где `local_slope[i] = max gradient to neighbors`.

Эффект: русла рек и дренажные каналы углубляются пропорционально стоку. Чем больше воды протекает — тем глубже долина.

**Thermal smoothing (скалы):**
```
for each iteration (thermal_iterations = 3):
    for each cell where ridge_strength > 0.3:
        height += average_neighbor_height_diff * thermal_rate * (1.0 - ridge_strength)
```

Эффект: предгорья становятся мягче, пики остаются острыми.

**Floodplain deposition:**
```
for each cell in river channel (accumulation > river_threshold):
    for each neighbor within floodplain_width:
        deposition = deposit_rate * (1.0 - dist_to_river / floodplain_width)
        eroded_height[neighbor] = lerp(eroded_height[neighbor], river_height, deposition)
```

Эффект: поймы выравниваются, создавая плоские долины вдоль рек.

### Шаг 1.14: Slope Channel

```
slope[i] = max_gradient_to_8_neighbors(eroded_height)
```

Нормализованный [0,1]. Доступен через `WorldPrePass.sample(&"slope", pos)`.

### Шаг 1.15: Rain Shadow

Требует: направление преобладающего ветра (`prevailing_wind_direction: Vector2`, default: `(1.0, 0.0)` — с запада).

Алгоритм (один проход по grid в направлении ветра):

```
moisture_budget = base_moisture (из PlanetSampler.moisture)

for each column along wind direction:
    for each cell in column:
        orographic_lift = max(0, height_gradient_in_wind_direction)
        precipitation = moisture_budget * precip_rate * (1.0 + orographic_lift * lift_factor)
        moisture_budget -= precipitation
        moisture_budget += evaporation_rate  // медленное восстановление
        rain_shadow[cell] = clamp(moisture_budget, 0.0, 1.0)
```

Эффект: наветренная сторона гор влажная, подветренная — сухая. Асимметричные биомы.

### Шаг 1.16: Continentalness

```
continentalness[i] = distance_to_nearest_water_body / max_distance
```

Где «water body» = ячейки с `eroded_height < sea_level_threshold` (default: 0.15) или edge of Y-axis.

Нормализованный [0,1]: 0 = побережье, 1 = глубокий континент.

### New WorldGenBalance parameters

```gdscript
@export_group("Erosion Proxy")
@export_range(0.0, 0.5) var prepass_erosion_valley_strength: float = 0.12
@export_range(1, 10) var prepass_thermal_iterations: int = 3
@export_range(0.0, 0.3) var prepass_thermal_rate: float = 0.08
@export_range(0.0, 0.5) var prepass_deposit_rate: float = 0.15

@export_group("Rain Shadow")
@export var prepass_prevailing_wind_direction: Vector2 = Vector2(1.0, 0.0)
@export_range(0.0, 0.5) var prepass_precipitation_rate: float = 0.12
@export_range(0.5, 8.0) var prepass_orographic_lift_factor: float = 3.0
@export_range(0.0, 0.2) var prepass_evaporation_rate: float = 0.02

@export_group("Continentalness")
@export_range(0.0, 0.5) var prepass_sea_level_threshold: float = 0.15
```

### Шаг 1.17: Polar Terrain Modifiers

Цилиндрический мир имеет два климатических полюса. Terrain generation должна учитывать их как первоклассные географические зоны, а не просто как «крайние значения temperature».

**Cold Pole (Y min) — Вечная зима:**

```
cold_factor = clamp((cold_pole_temperature - temperature) / cold_pole_transition_width, 0, 1)
```

Модификации при `cold_factor > 0`:
- **Terrain overlay**: ICE terrain type для плоских поверхностей (height < ice_cap_max_height AND slope < 0.15). Поверх GROUND, не заменяя его в base layer — это presentation modifier, не мутация canonical terrain.
- **Height boost**: `height += cold_factor * ice_cap_height_bonus` — ледяной щит поднимает рельеф, создавая пологий купол (ice sheet dome). Это питает drainage: вода стекает ОТ ледяного купола.
- **Flora suppression**: `flora_density *= (1.0 - cold_factor * 0.9)` — минимальная растительность, только лишайники у границы.
- **River freezing**: реки с `temperature < frozen_river_threshold` → terrain ICE вместо WATER.
- **Glacial lakes**: озёра в этой зоне получают type "glacial", elongated вдоль стока.

**Hot Pole (Y max) — Выжженная пустошь:**

```
hot_factor = clamp((temperature - hot_pole_temperature) / hot_pole_transition_width, 0, 1)
```

Модификации при `hot_factor > 0`:
- **Terrain overlay**: SCORCHED terrain type для плоских поверхностей. Визуально — потрескавшаяся, выжженная земля.
- **Moisture kill**: `effective_moisture *= (1.0 - hot_factor * 0.85)` — практически полное подавление влажности.
- **River evaporation**: реки с `hot_factor > 0.5` теряют `accumulation * hot_evaporation_rate` — русла пересыхают, оставляя сухие вади (dry riverbeds). Terrain: SAND вместо WATER.
- **Salt flats**: озёра в горячей зоне не заполняются водой, а становятся солончаками (terrain: SALT_FLAT). Плоские, белёсые, безжизненные.
- **Flora suppression**: `flora_density *= (1.0 - hot_factor * 0.95)` — только экстремофильная растительность у остатков воды.

**Terrain Type расширение:**

Текущие 4 типа (GROUND, WATER, SAND, ROCK) дополняются:

| Тип | Источник | Зона |
|-----|----------|------|
| ICE | Frozen river/lake/terrain в cold zone | Cold pole |
| SCORCHED | Выжженная поверхность в hot zone | Hot pole |
| SALT_FLAT | Высохшее озеро в hot zone | Hot pole |
| DRY_RIVERBED | Пересохшее русло в hot zone | Hot pole → warm transition |

Эти типы — **presentation-layer markers**, не canonical terrain mutations. Base terrain остаётся GROUND/WATER/SAND/ROCK. Polar modifiers применяются как overlay в `SurfaceTerrainResolver` на основе temperature.

**Transition Zones — самые интересные места:**

Граница ледника (`cold_factor ≈ 0.3–0.7`): талая вода, истоки великих рек, ледниковые озёра, морены (rocky debris). Биом: tundra → boreal transition.

Граница пустоши (`hot_factor ≈ 0.3–0.7`): последние оазисы, пересыхающие реки, засушливые степи, солончаки. Биом: savanna → scorched transition.

Эти transition zones — главные зоны биоразнообразия и gameplay-интереса. В будущем их наличие должно следовать из конструктивного макро-скелета мира, а не из post-hoc landmark validation.

### New WorldGenBalance parameters (polar modifiers)

```gdscript
@export_group("Cold Pole")
@export_range(0.0, 0.4) var cold_pole_temperature: float = 0.20
@export_range(0.05, 0.3) var cold_pole_transition_width: float = 0.12
@export_range(0.0, 0.3) var ice_cap_height_bonus: float = 0.10
@export_range(0.0, 0.8) var ice_cap_max_height: float = 0.55

@export_group("Hot Pole")
@export_range(0.6, 1.0) var hot_pole_temperature: float = 0.82
@export_range(0.05, 0.3) var hot_pole_transition_width: float = 0.15
@export_range(0.0, 0.5) var hot_evaporation_rate: float = 0.25
```

### Acceptance criteria (erosion + rain shadow + polar + lakes)

- [ ] Valley carving углубляет русла пропорционально flow accumulation
- [ ] Thermal smoothing сглаживает предгорья, не затрагивая пики
- [ ] Floodplain deposition выравнивает поймы
- [ ] `slope` канал корректно отражает локальный gradient
- [ ] Rain shadow создаёт влажную наветренную и сухую подветренную сторону гор
- [ ] `continentalness` корректно отражает distance to major water
- [ ] Все новые каналы доступны через `WorldPrePass.sample()`
- [ ] Озёра генерируются в впадинах рельефа (горные, ледниковые, пойменные, тектонические)
- [ ] Озёра имеют spill point → вода вытекает из озера дальше в drainage network
- [ ] `_lake_records` содержат корректные данные для каждого озера
- [ ] Latitude-dependent evaporation: реки полноводнее в умеренной зоне, пересыхают в горячей
- [ ] Glacial melt: максимальный сток на границе ледника, не в центре ледяной шапки
- [ ] Cold pole: ICE terrain overlay, height boost (ледяной купол), flora suppression
- [ ] Hot pole: SCORCHED terrain overlay, river evaporation, salt flats вместо озёр
- [ ] Transition zones визуально различимы: tundra-boreal и savanna-scorched
- [ ] Новые terrain types (ICE, SCORCHED, SALT_FLAT, DRY_RIVERBED) — presentation overlays, не мутации base terrain

---

## Фаза 2: Runtime Landmark Grammar (Rejected)

### Статус

Rejected on `2026-04-04`.

### Почему отклонено

Этот подход строил дорогой pre-pass, потом судил мир по checklist-метрикам, потом пытался чинить thresholds и добиваться прохождения seed через post-hoc validation. Это противоречит целевой причинности генерации и уже привело к бесконечному reroll / тяжёлому boot path.

### Что больше не допускается

- обязательный runtime gate вида `validate_landmarks()` перед стартом новой игры
- remediation loop с повторным полным `WorldPrePass.compute()`
- wow-region detection как часть bootstrap
- soft-fix через мутацию runtime thresholds под конкретный seed
- seed curation / lucky-seed search как способ гарантировать красивый мир

### Что должно прийти на замену

Будущая замена этой фазы — отдельная конструктивная спецификация macro skeleton world generation:

- seed сначала задаёт макро-скелет мира
- из макро-скелета детерминированно выводятся крупные бассейны, spine/ridge families, главные реки и климатические переходы
- выразительные регионы появляются как следствие конструкции, а не как результат фильтрации готовых миров

До появления такой спецификации эта фаза считается закрытой и не подлежит реанимации в runtime bootstrap.

---

## Фаза 3: Причинные каналы и экотоны

### Шаг 3.1: Интеграция новых каналов в BiomeResolver

После Фаз 0–1 доступны новые каналы из `WorldPrePass`:

| Канал | Источник | Тип |
|-------|----------|-----|
| `drainage` | flow accumulation (normalized log) | [0, 1] |
| `slope` | max gradient eroded height | [0, 1] |
| `rain_shadow` | wind-based moisture transport | [0, 1] |
| `continentalness` | distance to major water | [0, 1] |

Эти каналы добавляются в `WorldChannels` (или в отдельную структуру `WorldPrePassChannels`).

`BiomeResolver` получает расширенный input:

```gdscript
func resolve_biome(
    world_pos: Vector2i,
    channels: WorldChannels,
    prepass_channels: WorldPrePassChannels  # NEW
) -> BiomeResult:
    pass
```

`BiomeData` расширяется новыми ranges и weights:

```gdscript
@export var min_drainage: float = 0.0
@export var max_drainage: float = 1.0
@export var drainage_weight: float = 0.0
@export var min_slope: float = 0.0
@export var max_slope: float = 1.0
@export var slope_weight: float = 0.0
@export var min_rain_shadow: float = 0.0
@export var max_rain_shadow: float = 1.0
@export var rain_shadow_weight: float = 0.0
@export var min_continentalness: float = 0.0
@export var max_continentalness: float = 1.0
@export var continentalness_weight: float = 0.0
```

### Шаг 3.2: Moisture как следствие

Ключевое изменение: `moisture` в `PlanetSampler` перестаёт быть единственным источником влажности для биомов. Эффективная влажность:

```
effective_moisture = base_moisture * rain_shadow * (1.0 - continentalness * continental_drying_factor)
    + drainage * drainage_moisture_bonus
```

Это означает:
- За горами — суше (rain_shadow)
- Далеко от воды — суше (continentalness)
- Вдоль рек — влажнее (drainage)
- Биомы теперь — *следствие* физики, не score ranges

### Шаг 3.3: Ecotone System

Заменяет winner-takes-all в `BiomeResolver`:

1. Resolver вычисляет scores для всех valid биомов (как сейчас).
2. Сохраняет top-2 кандидатов + ecotone factor:

```gdscript
class_name BiomeResult
extends RefCounted

var primary_biome: BiomeData
var primary_score: float
var secondary_biome: BiomeData        # NEW — может быть null
var secondary_score: float            # NEW
var ecotone_factor: float             # NEW — [0,1], 0 = pure primary, 1 = pure secondary
var dominance: float                  # NEW — primary_score - secondary_score
```

```
ecotone_factor = 1.0 - clamp(dominance / ecotone_threshold, 0.0, 1.0)
```

Где `ecotone_threshold` (default: 0.15) — при разнице scores меньше порога, начинается зона перехода.

### Шаг 3.4: Ecotone Application

Потребители `BiomeResult`:

- **Flora placement**: blend flora sets двух биомов пропорционально `ecotone_factor`
- **Terrain coloring**: lerp между tile atlases (или overlay blending)
- **Local variation**: modulation weights скорректированы по ecotone
- **Feature hooks**: могут требовать `ecotone_factor > X` (edge-of-biome features)

### New WorldGenBalance parameters

```gdscript
@export_group("Ecotone")
@export_range(0.01, 0.5) var ecotone_threshold: float = 0.15
@export_range(0.0, 1.0) var continental_drying_factor: float = 0.3
@export_range(0.0, 1.0) var drainage_moisture_bonus: float = 0.2
```

### Acceptance criteria (каналы + экотоны)

- [ ] `WorldPrePassChannels` доступны в BiomeResolver
- [ ] effective_moisture учитывает rain_shadow, continentalness, drainage
- [ ] BiomeResult содержит secondary_biome и ecotone_factor
- [ ] Зоны перехода визуально отличаются от core биомов (смешанная флора)
- [ ] Rain shadow визуально заметен: наветренная сторона гор зеленее подветренной
- [ ] Все .tres биом-ресурсы расширены новыми ranges (defaults: 0–1, weight: 0)
- [ ] Обратная совместимость: weight=0 → канал не влияет (MVP биомы не ломаются)

---

## Фаза 4: Atlas & Scenic Diagnostics Tooling

### World Atlas Generator

Отдельный инструмент (скрипт в `tools/`), запускаемый из editor:

```gdscript
# tools/world_atlas_generator.gd
# Прогоняет N seeds, для каждого:
# 1. initialize_world(seed)
# 2. читает опубликованный WorldPrePass
# 3. рендерит minimap (drainage, height, biomes, ridges)
# 4. сохраняет PNG + JSON metrics
```

Важно: tooling здесь существует для offline анализа и балансировки. Он не должен превращаться в runtime gate, whitelist сидов или механизм поиска «правильного» мира для игрока.

### Metrics JSON

```json
{
    "seed": 42,
    "great_river_max_accumulation": 3200,
    "great_river_length_tiles": 12800,
    "longest_ridge_length_grid": 145,
    "delta_count": 2,
    "dry_belt_area_grid": 720,
    "major_basin_count": 3,
    "ridge_spine_count": 2,
    "generation_time_ms": 340
}
```

### Acceptance criteria (tooling)

- [ ] Atlas generator создаёт PNG minimaps для batch of seeds
- [ ] JSON metrics содержат диагностические hydrology / ridge / climate measurements без runtime pass/fail gate
- [ ] Tool запускается из Godot editor
- [ ] 100 seeds прогоняются за < 5 минут

---

## Impact на существующие компоненты

### Заменяемые компоненты

| Компонент | Текущий | После overhaul |
|-----------|---------|----------------|
| `LargeStructureSampler.river_strength` | Band-based | Lookup из `WorldPrePass.drainage` + distance-to-river |
| `LargeStructureSampler.floodplain_strength` | Band-based | Lookup из `WorldPrePass` floodplain distance field |
| `LargeStructureSampler.ridge_strength` | Band-based | Lookup из `WorldPrePass` ridge distance field |
| `LargeStructureSampler.mountain_mass` | Cluster noise + terrain gate | Lookup из `WorldPrePass.mountain_mass` |

`LargeStructureSampler` может быть переименован в `LargeStructureAccessor` — он больше не *семплирует* noise, а *читает* pre-computed data.

### Сохраняемые компоненты (без изменений или minimal changes)

| Компонент | Изменения |
|-----------|-----------|
| `PlanetSampler` | FBM fix (Фаза 0), остальное без изменений |
| `BiomeResolver` | Расширенный input (Фаза 3), ecotone output |
| `LocalVariationResolver` | FBM fix, ecotone-aware modulation |
| `SurfaceTerrainResolver` | Читает из WorldPrePass вместо LargeStructureSampler + polar overlay logic |
| `ChunkContentBuilder` | Передаёт prepass channels в pipeline |
| `ChunkManager` | Без изменений (streaming logic не затрагивается) |
| `Chunk` | Без изменений |
| `WorldGenerator` | Добавляет WorldPrePass.compute() в initialize_world() |

### Data Contracts изменения

Новый layer в DATA_CONTRACTS.md:

```
| World Pre-pass | canonical | WorldPrePass | boot-time compute from seed |
|   Readers: PlanetSampler, BiomeResolver, SurfaceTerrainResolver, |
|   ChunkContentBuilder, LargeStructureAccessor |
|   Rebuild: boot-time only, deterministic from seed |
```

### PUBLIC_API.md изменения

Новые safe entry points:

```gdscript
WorldPrePass.sample(channel: StringName, world_pos: Vector2i) -> float
WorldPrePass.get_grid_value(channel: StringName, grid_x: int, grid_y: int) -> float
```

Изменённые entry points:

```gdscript
BiomeResolver.resolve_biome(world_pos, channels, prepass_channels) -> BiomeResult  # extended signature
BiomeResult.secondary_biome  # new field
BiomeResult.ecotone_factor   # new field
```

---

## Phasing и зависимости

```
Фаза 0 ─── Octave fix
  │          (нет зависимостей, может быть сделана немедленно)
  │
  ▼
Фаза 1 ─── Global Pre-pass
  │          1.1  Coarse heightfield
  │          1.2  Sink filling + Lake detection   ← зависит от 1.1
  │          1.3  Flow direction                  ← зависит от 1.2
  │          1.4  Flow accumulation + Latitude evaporation ← зависит от 1.3
  │          1.5  Drainage channel                ← зависит от 1.4
  │          1.6  River extraction                ← зависит от 1.4
  │          1.7  Floodplain                      ← зависит от 1.6
  │          1.8  Tectonic spine seeds            ← зависит от 1.1
  │          1.9  Ridge graph                     ← зависит от 1.8
  │          1.10 Ridge spline smoothing          ← зависит от 1.9
  │          1.11 Ridge distance field            ← зависит от 1.10
  │          1.12 Mountain mass                   ← зависит от 1.11
  │          1.13 Erosion proxy                   ← зависит от 1.4, 1.11
  │          1.14 Slope channel                   ← зависит от 1.13
  │          1.15 Rain shadow                     ← зависит от 1.11, 1.13
  │          1.16 Continentalness                 ← зависит от 1.13
  │          1.17 Polar terrain modifiers         ← зависит от 1.2, 1.4, 1.13
  │
  ▼
Фаза 2 ─── Runtime Landmark Grammar (rejected 2026-04-04)
  │          Не реализовывать. Будущая замена: отдельная constructive macro-skeleton spec
  │
  ▼
Фаза 3 ─── Причинные каналы + экотоны
  │          Зависит от Фазы 1 (каналы)
  │
  ▼
Фаза 4 ─── Atlas & Scenic Diagnostics Tooling
             Зависит от Фаз 1–3, но не вводит runtime landmark validation
```

## Risks

### R1. Threshold re-tuning avalanche

FBM fix и новые каналы меняют диапазоны значений. Все существующие пороги и biome ranges потребуют перенастройки. **Mitigation**: Фаза 0 делается отдельно, с полным проходом по thresholds, прежде чем начинается Фаза 1.

### R2. Boot time regression

Global pre-pass добавляет compute на boot. **Mitigation**: coarse grid (33K points) + O(N log N) алгоритмы → <500ms GDScript. GDExtension path → <100ms. Бюджет: 1s total для pre-pass допустим при boot.

### R3. Memory for pre-pass data

9 каналов × 33K points × 4 bytes + lake mask (33K × 1 byte) + lake records (~50 × 64 bytes) ≈ 1.2MB. Пренебрежимо.

### R4. Chunk streaming coupling

`WorldPrePass` lookup в chunk build pipeline добавляет bilinear interpolation per tile. Для 64×64 chunk = 4096 lookups × ~7 channels = 28K interpolations. **Mitigation**: cache-friendly row-major layout + precomputed inverse grid step. Estimated cost: <0.1ms per chunk.

### R5. Native path divergence

GDExtension C++ path должен использовать те же pre-pass данные. **Mitigation**: pre-pass results передаются как flat arrays в native build, не пересчитываются.

### R6. Terrain type expansion

Новые типы (ICE, SCORCHED, SALT_FLAT, DRY_RIVERBED) затрагивают `TerrainType` enum, `SurfaceTerrainResolver`, `ChunkTilesetFactory`, walkability rules, save format. **Mitigation**: реализовать как presentation overlay поверх base 4 типов. Base terrain не меняется, overlay применяется при рендере и walkability check. Save хранит только base terrain + runtime diff.

### R7. Lake-drainage coupling complexity

Озёра с spill point создают нетривиальную топологию drainage graph (вода может входить в озеро с нескольких сторон, но выходит только через один spill point). **Mitigation**: при sink filling каждое озеро заменяется одной «виртуальной ячейкой» в drainage graph с суммарным inflow и единственным outflow через spill point.

## Open questions

- Точные default'ы для всех новых WorldGenBalance параметров потребуют визуальной итерации
- Формат ridge skeleton cache (flat arrays vs. structured graph) — TBD при реализации
- Нужен ли ocean/sea как terrain type или достаточно WATER — зависит от GDD
- Exact ecotone rendering strategy (tile atlas blending vs. overlay) — presentation layer decision
- GDExtension priority: port WorldPrePass.compute() вместе с chunk generation или отдельно
- ICE terrain: gameplay implications (проходимость, скольжение, добыча льда, строительство) — требует GDD решения
- Замёрзшие реки: сезонное оттаивание в gameplay или статичное состояние? Текущая спека — статичное (определяется latitude, не временем года). Сезонность — отдельная feature.
- Salt flats: добываемый ресурс (соль) или чисто визуальный terrain? — зависит от content bible
- Озёра: рыбалка / water gathering как gameplay mechanic? — зависит от GDD
- Максимальное количество озёр на мир: нужен ли cap для performance (tile-level distance field для каждого озера)?

## Transitional source note

Этот документ объединяет анализ текущей реализации (диагноз из code review март 2026), предложения по drainage-based рекам и skeleton-based горам, и рекомендации по причинным каналам.

v0.2 дополнения: latitude-dependent hydrology (ледниковый сток, широтное испарение), генерация озёр (modified sink filling с lake detection), polar terrain modifiers (cold pole: ICE/glaciers, hot pole: SCORCHED/salt flats/dry riverbeds), а также now-rejected runtime landmark grammar.

v0.3 reset: runtime landmark validation / remediation / wow-region bootstrap / lucky-seed search removed from the active direction. Future memorable worlds must come from constructive macro-skeleton generation rather than post-hoc filtering.

Является proposal, требует approval перед реализацией.
