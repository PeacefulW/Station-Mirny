# Ревью системы рек (water/hydrology)
_Дата: 2026-04-11_

## Контекст

Полный анализ пайплайна: `WorldPrePass.gd`, `world_prepass_kernels.cpp`, `chunk_generator.cpp`,
`surface_terrain_resolver.gd`, `world_gen_balance.gd`, `save_collectors/appliers`,
`world_creation_screen.gd`, профайл-логи из `debug_exports/`.

---

## Архитектура пайплайна (текущее состояние)

```
WorldPrePass.compute() — boot-only, worker thread
  sample_height_grid       →  184 ms  (GDScript, planet_sampler)
  spine_seeds              →  665 ms  (GDScript)
  ridge_graph              →   93 ms  (GDScript)
  ridge_strength_grid      →    1.5 ms (C++ native) ✓
  mountain_mass_grid       →  454 ms  (GDScript + planet_sampler)
  lake_aware_fill          →  783 ms
    priority_flood         →    ~7 ms  (C++ native) ✓
    extract_lake_records   →  776 ms  (GDScript!)
  flow_directions          →  870 ms  (GDScript!)
  flow_accumulation        →  1157 ms (GDScript!)
  drainage_grid            →    ~5 ms  (GDScript)
  river_extraction         →   47 ms  (C++ native) ✓
  floodplain_strength      →   26 ms baseline / 950 ms tuned! (GDScript!)
  erosion_proxy            →  452 ms baseline / 4117 ms tuned! (GDScript!)
  slope_grid               →  592 ms  (GDScript!)
  rain_shadow              → 1373 ms  (GDScript!)
  continentalness          →   57 ms  (native fallback) ✓
  ───────────────────────────────────────────────────────────────
  TOTAL                    ~ 6740 ms baseline / 10246 ms tuned!
```

Данные замеров: `debug_exports/world_previews/river_baseline_seed12345.log`
и `debug_exports/world_previews/river_after_tuned_seed12345.log`, seed=12345.

---

## Найденные проблемы

### 1. Катастрофическая регрессия при tuned-параметрах (критично)

**Файлы:** `core/systems/world/world_pre_pass.gd:911` (`_compute_floodplain_strength`),
`core/systems/world/world_pre_pass.gd:1114` (`_apply_floodplain_deposition`)

`_compute_floodplain_strength` и `_apply_floodplain_deposition` используют `Array[Dictionary]`
как heap:

```gdscript
var heap: Array[Dictionary] = []
_heap_push(heap, cell_index, 0.0, {
    "source_width": floodplain_width,   # Dictionary allocation на каждом шаге
})
```

Baseline: 26 ms. Tuned (больше рек → больше river sources): **950 ms — рост в 36 раз**.
Аналогично `_apply_floodplain_deposition`: baseline 452 ms → tuned **4117 ms (рост в 9 раз)**.

При увеличении рек через UI-слайдер игрок получает экран загрузки длиной **10+ секунд**
вместо 7 — главная причина роста с 6.7 с до 10.2 с.

---

### 2. Крупные стадии остаются на GDScript без нативного пути (производительность)

| Стадия | Время | Нативный путь |
|--------|-------|---------------|
| `extract_lake_records` | 648–776 ms | нет |
| `flow_directions` | 819–870 ms | нет |
| `flow_accumulation` | 927–1157 ms | нет |
| `slope_grid` | 424–592 ms | нет |
| `rain_shadow` | 1070–1373 ms | нет |

Для сравнения: `priority_flood`, `ridge_strength_grid`, `river_extraction` — нативные C++ ядра —
работают за 1–47 ms. Пять стадий, суммарно занимающие ~4.5–5 секунд, ждут нативизации.

---

### 3. Видимость рек в центральных широтах — ноль (геймплейно критично)

Диагностировано в `docs/02_system_specs/world/hydrology_world_settings_spec.md`:

- `visible_river_samples = 0` во **всех четырёх центральных широтных диапазонах**
- `nearest_visible_water = none`
- `nearest_authoritative_river = (3184, -464)` — авторитативные данные **есть** на расстоянии
  1023 tiles, но `SurfaceTerrainResolver` их не показывает

Цепочка причин:

1. `prepass_river_accumulation_threshold = 72` — может быть слишком высоким для центральных
   широт с низкой precipitation.
2. В `surface_terrain_resolver.gd:484` gate `river_min_strength * 0.75` отсекает слабые реки
   даже при ненулевом `river_width`.

---

### 4. `_extract_lake_records` — 776 ms, полностью GDScript

**Файл:** `core/systems/world/world_pre_pass.gd:2526`

BFS по basin cells реализован с `Array[int]` (не Packed). Для каждого озера
`_classify_lake_type` вызывает `_planet_sampler.sample_world_channels(world_pos)` на
**каждой клетке** озера:

```gdscript
for cell_index: int in component_cells:
    var channels: WorldChannels = _planet_sampler.sample_world_channels(world_pos)
    total_temperature += channels.temperature
```

При крупном озере это O(N_lake_cells) дорогих noise lookups. Для классификации
достаточно 20–30 репрезентативных точек.

---

### 5. Дублирующиеся проходы по planet_sampler

Планетарный сэмплер вызывается минимум **4 раза** по всей сетке в разных стадиях:

| Стадия | Канал | Расположение |
|--------|-------|--------------|
| `sample_height_grid` | height | `world_pre_pass.gd:364` |
| `_build_temperature_grid` | temperature | `world_pre_pass.gd:2191` |
| `_build_moisture_grid` | moisture | `world_pre_pass.gd:2200` |
| `_compute_mountain_mass_grid` | ruggedness | `world_pre_pass.gd:1213` |

Каждый `sample_world_channels` выполняет несколько noise lookups. Все 4 канала можно
собрать за **один проход**.

---

### 6. `MAX_LAKE_MASK_ID = 255` — жёсткий overflow (масштабируемость)

**Файл:** `core/systems/world/world_pre_pass.gd:41, 2552`

`_lake_mask: PackedByteArray` хранит ID озёр в 1 байте. При достижении 255 озёр:

```gdscript
if _lake_records.size() >= MAX_LAKE_MASK_ID:
    push_error("WorldPrePass lake mask overflow: more than %d lakes detected" % MAX_LAKE_MASK_ID)
    break
```

При tuned-конфиге с низкими `prepass_lake_min_area`/`prepass_lake_min_depth` — реальный риск.

---

### 7. Save/load покрывает только 5 из ~12 hydrology параметров

**Файлы:** `core/autoloads/save_collectors.gd:70–74`, `core/autoloads/save_appliers.gd:25–29`

Сохраняется:
- `prepass_river_accumulation_threshold`
- `prepass_river_base_width`
- `prepass_river_width_scale`
- `prepass_lake_min_area`
- `prepass_lake_min_depth`

**Не сохраняются:** `prepass_floodplain_multiplier`, `prepass_glacial_melt_bonus`,
`prepass_latitude_evaporation_rate`, `prepass_frozen_river_threshold`,
`prepass_glacial_melt_temperature`, `prepass_frozen_lake_temperature`,
`prepass_erosion_valley_strength`, `prepass_thermal_iterations`, `prepass_deposit_rate`.

После save/load эти параметры сбрасываются к дефолтам `.tres`, что меняет мир при загрузке.

---

### 8. `_compute_flow_directions` — два прохода + потенциально O(N²) на плоском рельефе

**Файл:** `core/systems/world/world_pre_pass.gd:692`

```gdscript
# Первый проход — direct flow
for cell_index: int in range(_filled_height_grid.size()):
    var direct_direction: int = _find_direct_flow_direction(cell_index)
    ...
# Второй проход — plateau resolution
for cell_index: int in range(_filled_height_grid.size()):
    ...
    _resolve_flat_plateau_flow(cell_index, unresolved_plateau_cells)
```

`_resolve_flat_plateau_flow` может запускать внутренний BFS для каждой unresolved cell
и в худшем случае (плоский биом) итерировать одни клетки повторно.

---

### 9. `_apply_thermal_smoothing` — полная копия сетки на каждой итерации

**Файл:** `core/systems/world/world_pre_pass.gd:1090`

```gdscript
for _iteration_index: int in range(thermal_iterations):
    var next_grid: PackedFloat32Array = current_grid.duplicate()  # ~16 KB копия
```

При 3 итерациях и сетке 128×128 — 3 полных copy вместо ping-pong double-buffer.

---

### 10. Нет нативного пути для floodplain_strength, несмотря на нативный river_extraction

**Файл:** `core/systems/world/world_pre_pass.gd:911`

`river_extraction` имеет нативный путь через `compute_river_extraction` в C++.
Но `floodplain_strength` — прямое продолжение этого расчёта — остаётся на GDScript.
Это архитектурный gap: нативизация должна была идти парно.

---

## Практические советы по улучшению

### Приоритет 1 — устранить catastrophic regression (Array[Dictionary] heap)

Заменить `Array[Dictionary]` heap в `_compute_floodplain_strength` (строка 916–953)
и `_apply_floodplain_deposition` (строка 1126–1166) на Packed-структуры:

```gdscript
# Вместо Array[Dictionary]
var heap_indices: PackedInt32Array = PackedInt32Array()
var heap_priorities: PackedFloat32Array = PackedFloat32Array()
var heap_source_widths: PackedFloat32Array = PackedFloat32Array()
```

Это немедленно устраняет 36x регрессию, не требует C++, реализуется за одну итерацию.

Долгосрочно — добавить нативное ядро `compute_floodplain_strength` по образцу
`compute_river_extraction` в `world_prepass_kernels.cpp`.

---

### Приоритет 2 — нативизировать flow_directions + flow_accumulation

Суммарно 1700–2000 ms GDScript. Алгоритм D8 + topological accumulation — хорошо
известен, все вспомогательные функции уже есть в `world_prepass_kernels.h`
(`wrap_x`, `decode_index`, `get_flow_target_index`). Добавить:

```cpp
// world_prepass_kernels.h
Dictionary compute_flow_directions_and_accumulation(
    int grid_width, int grid_height,
    PackedFloat32Array filled_height_grid,
    PackedFloat32Array temperature_grid,
    PackedByteArray lake_mask,
    float frozen_threshold,
    float glacial_melt_temperature,
    float glacial_melt_bonus,
    float evaporation_rate
) const;
```

Возвращает: `flow_dir_grid`, `accumulation_grid`, `drainage_grid`.

---

### Приоритет 3 — нативизировать extract_lake_records

648–776 ms на GDScript. BFS по basin cells + измерение глубины — прямолинейная задача
для C++. Classify lake type — сэмплировать не все клетки, а до 30 детерминированных
точек (по hash от cell_index). Добавить:

```cpp
// world_prepass_kernels.h
Dictionary compute_lake_records(
    int grid_width, int grid_height,
    PackedFloat32Array height_grid,
    PackedFloat32Array filled_height_grid,
    int max_lake_id,
    int min_area,
    float min_depth,
    int max_classify_samples
) const;
```

---

### Приоритет 4 — исправить видимость рек в центральном поясе

Два независимых изменения:

**a) Снизить accumulation threshold:**
В `data/world/world_gen_balance.tres` попробовать `prepass_river_accumulation_threshold`
48–55 вместо 72. Верифицировать proof через `tools/world_preview_proof_driver.gd`.

**b) Убрать двойной strength gate в resolver:**
В `surface_terrain_resolver.gd:482–485` реки с `river_width > 0` и
`distance_to_river < river_core_radius` должны рендериться всегда, без
дополнительного `effective_river_strength` gate:

```gdscript
# Текущее:
if effective_river_strength < _balance.river_min_strength * 0.75:
    return false
# Предлагаемое: пропускать gate если river_width > 0 и distance < core_radius
```

---

### Приоритет 5 — единый проход planet_sampler

Добавить `_build_channel_grids() -> Dictionary` который за один проход собирает
height, temperature, moisture, ruggedness в четыре `PackedFloat32Array`.
Устраняет 3 дополнительных полных прохода по всей сетке.

```gdscript
func _build_channel_grids() -> Dictionary:
    var height := PackedFloat32Array()
    var temperature := PackedFloat32Array()
    var moisture := PackedFloat32Array()
    var ruggedness := PackedFloat32Array()
    var size: int = _grid_width * _grid_height
    height.resize(size)
    temperature.resize(size)
    moisture.resize(size)
    ruggedness.resize(size)
    for cell_index: int in range(size):
        var world_pos := Vector2i(_grid_world_x_cache[cell_index], _grid_world_y_cache[cell_index])
        var channels: WorldChannels = _planet_sampler.sample_world_channels(world_pos)
        height[cell_index] = channels.height
        temperature[cell_index] = clampf(channels.temperature, 0.0, 1.0)
        moisture[cell_index] = clampf(channels.moisture, 0.0, 1.0)
        ruggedness[cell_index] = clampf(channels.ruggedness, 0.0, 1.0)
    return {"height": height, "temperature": temperature, "moisture": moisture, "ruggedness": ruggedness}
```

---

### Приоритет 6 — расширить lake_mask до PackedInt16Array

Заменить `_lake_mask: PackedByteArray` на `PackedInt16Array`.
Обновить `MAX_LAKE_MASK_ID` до 32767 (или 65535 при unsigned).
Изменение локальное, не затрагивает публичный API.

---

### Приоритет 7 — дополнить save/load

Добавить в `SaveCollectors.collect_world()`:
- `prepass_floodplain_multiplier`
- `prepass_glacial_melt_bonus`
- `prepass_latitude_evaporation_rate`
- `prepass_frozen_river_threshold`
- `prepass_erosion_valley_strength`
- `prepass_deposit_rate`
- `prepass_thermal_iterations`

В `SaveAppliers.apply_world()` — безопасный fallback к текущему balance для каждого
нового поля.

---

### Приоритет 8 — double-buffer в thermal_smoothing

```gdscript
# Вместо duplicate() на каждой итерации — ping-pong
var grid_read: PackedFloat32Array = _eroded_height_grid
var grid_write: PackedFloat32Array = PackedFloat32Array()
grid_write.resize(grid_read.size())
for _iteration_index: int in range(thermal_iterations):
    for cell_index: int in range(grid_read.size()):
        # ... читать из grid_read, писать в grid_write
    var tmp := grid_read
    grid_read = grid_write
    grid_write = tmp
_eroded_height_grid = grid_read
```

---

## Сводная таблица

| # | Проблема | Серьёзность | Усилие фикса |
|---|----------|-------------|--------------|
| 1 | Array[Dictionary] heap → 36x regression при tuned | Критично | Малое (GDScript) |
| 2 | flow_directions / accumulation на GDScript (1700+ ms) | Высокая | Среднее (C++ ядро) |
| 3 | extract_lake_records на GDScript (776 ms) | Высокая | Среднее (C++ ядро) |
| 4 | Видимость рек в central band = 0 | Высокая | Малое (порог + gate) |
| 5 | 4 отдельных прохода planet_sampler | Средняя | Малое (рефактор) |
| 6 | MAX_LAKE_MASK_ID=255 overflow risk | Средняя | Малое (тип данных) |
| 7 | Save/load не покрывает 7 hydrology params | Средняя | Малое |
| 8 | slope_grid / rain_shadow нет native (1000–1900 ms) | Средняя | Высокое (C++ ядра) |
| 9 | thermal_smoothing duplicate() на каждой итерации | Низкая | Малое |
| 10 | floodplain native gap при нативном river_extraction | Низкая | Среднее (C++ ядро) |

---

## Связанные файлы

- `core/systems/world/world_pre_pass.gd` — основной объект ревью
- `gdextension/src/world_prepass_kernels.cpp` / `.h` — нативные ядра, точка расширения
- `gdextension/src/chunk_generator.cpp` — terrain consumer, river/bank thresholds
- `core/systems/world/surface_terrain_resolver.gd` — terrain resolver, strength gates
- `data/world/world_gen_balance.gd` / `.tres` — конфиг параметров
- `core/autoloads/save_collectors.gd` / `save_appliers.gd` — save/load gap
- `docs/02_system_specs/world/hydrology_world_settings_spec.md` — canonical feature spec
- `debug_exports/world_previews/river_baseline_seed12345.log` — baseline замеры
- `debug_exports/world_previews/river_after_tuned_seed12345.log` — tuned замеры
