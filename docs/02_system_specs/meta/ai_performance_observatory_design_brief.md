---
title: "Design Brief: AI Performance Observatory"
doc_type: design_brief
status: approved
owner: engineering
version: 0.1
created: 2026-04-16
related_docs:
  - docs/00_governance/PERFORMANCE_CONTRACTS.md
  - docs/00_governance/ENGINEERING_STANDARDS.md
  - docs/02_system_specs/world/streaming_redraw_budget_spec.md
  - docs/02_system_specs/world/frontier_native_runtime_architecture_spec.md
---

# Design Brief: AI Performance Observatory

## 1. Цель

Создать инфраструктуру, которая позволяет ИИ-агентам:

1. **Моментально тестировать** весь core gameplay loop через headless-прогоны
2. **Видеть числа** — машиночитаемая телеметрия, не текстовые логи
3. **Сравнивать с baseline** — "стало лучше или хуже после моего изменения?"
4. **Диагностировать** — видеть внутрь C++ функций, находить конкретный bottleneck
5. **Фиксить петлю** — изменил код → прогнал тест → увидел результат → итерировал

Конечная цель: игрок бегает по миру свободно, как в Factorio. Ни швов, ни загрузок,
ни фризов. Транспорт (поезда, машины) должен быть архитектурно возможен.

## 2. Диагноз текущего стриминга

### 2.1 Ключевые числа

| Параметр | Значение |
|---|---|
| `chunk_size_tiles` | 64 |
| `tile_size` | 64 px |
| Размер чанка | 64 × 64 = **4096 px** |
| `load_radius` | 2 (сетка 5×5 = 25 чанков) |
| `unload_radius` | 4 |
| `player_speed` (норма) | 150 px/sec (текущий .tres = 350 — тестовая) |
| `vehicle_speed` (цель) | 500 px/sec |
| `train_speed` (цель) | 700 px/sec |
| Время пересечения чанка пешком | 4096 / 150 ≈ **27.3 сек** |
| Время пересечения чанка на транспорте | 4096 / 500 ≈ **8.2 сек** |
| Время пересечения чанка на поезде | 4096 / 700 ≈ **5.9 сек** |
| `RUNTIME_MAX_CONCURRENT_COMPUTE` | 4 (параллельных worker'ов) |

### 2.2 Pipeline загрузки чанка (текущий)

```
1. enqueue_load_request          → добавить в очередь с frontier-приоритетом
2. submit_async_generate         → WorkerThreadPool (C++ ChunkGenerator)
3. collect_completed_generates   → собрать результат из worker'а
4. promote_to_stage              → подготовить install entry
5. staged_loading_create         → создать Chunk node + shell      [1 кадр]
6. staged_loading_finalize       → 6-фазный finalize               [6 кадров]
   ├── PAYLOAD_ATTACH   → populate_native + flora
   ├── SCENE_ATTACH     → add_child в scene tree
   ├── VISUAL_ENQUEUE   → поставить в очередь визуальной сборки
   ├── TOPOLOGY_HANDOFF → интеграция топологии
   ├── SEAM_EVENTBUS    → правка швов + EventBus
   └── PUBLISH_GATE     → видимость
7. Visual build                  → first_pass + full_redraw через FrameBudgetDispatcher
```

### 2.3 Bottleneck: серийный install

**Критическая проблема**: `staged_chunk` — это одна переменная. Только один чанк
может быть в стадии install/finalize одновременно. Даже с 4 параллельными генераторами,
main-thread pipeline — последовательный.

- Install одного чанка: 1 (create) + 6 (finalize) = **7 кадров** ≈ 117ms @60fps
- 3 чанка (ряд при движении на север): 3 × 117ms = **351ms** только install
- Плюс визуальная сборка (first_pass + full_redraw) через FrameBudgetDispatcher
- Плюс topology rebuild, seam fix, shadow refresh...

При нормальной пешей скорости (150 px/s, 27с на чанк) запас формально большой,
но на практике хрупкий:
- 3 чанка install: 351ms — формально OK, но visual build добавляет сотни мс сверху
- При смене направления все 3 чанка нужно грузить заново
- FrontierPlanner с `max_forward_chunks=1` (walk) / 2 (sprint) — lookahead недостаточен для транспорта
- При тестовой скорости 350 px/s (текущий .tres) уже видны красные чанки
- **Для транспорта** (500 px/s) и **поездов** (700 px/s) текущая архитектура непригодна — бюджет на 3 чанка < 4 сек

### 2.4 Что должно быть

**Инвариант стриминга**: когда игрок находится в чанке, все 8 соседних чанков
должны быть в состоянии `full_ready` (terrain + visual complete). При движении
в любом направлении, 3 новых чанка по ходу движения должны загрузиться быстрее,
чем игрок пробежит текущий чанк.

**Формула**: `T_load(3 chunks) < T_traverse(1 chunk) × safety_margin`

| Режим | Скорость | Чанк за | Бюджет на 3 чанка (×0.5) |
|---|---|---|---|
| Пешком (норма) | 150 px/s | 27.3 сек | **13.6 сек** — должно хватать, но сейчас не хватает |
| Тестовая скорость | 350 px/s | 11.7 сек | **5.8 сек** — уже видны красные чанки |
| Транспорт (цель) | 500 px/s | 8.2 сек | **4.1 сек** — жёсткое ограничение |
| Поезд (цель) | 700 px/s | 5.9 сек | **2.9 сек** — архитектурный предел |

Факт: при тестовой скорости 350 px/s стриминг уже не успевает.
Это значит что при нормальных 150 px/s запас есть, но он хрупкий — visual build
или topology rebuild может его съесть. Для транспорта текущая архитектура непригодна.

## 3. Архитектура решения

### 3.1 Обзор компонентов

```
┌─────────────────────────────────────────────────────────────┐
│                  AI Performance Observatory                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Telemetry   │  │  Scenario    │  │  Native          │  │
│  │  Pipeline    │  │  Factory     │  │  Profiling       │  │
│  │              │  │              │  │                  │  │
│  │  JSON output │  │  Modular     │  │  C++ timers      │  │
│  │  Baselines   │  │  test cases  │  │  Tracy (opt)     │  │
│  │  Regression  │  │  Stress      │  │  _prof_ payload  │  │
│  │  detection   │  │  presets     │  │                  │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                    │            │
│  ┌──────┴─────────────────┴────────────────────┴─────────┐  │
│  │              Headless Test Runner                      │  │
│  │  CLI: --headless --scene game_world.tscn              │  │
│  │  Args: codex_perf_test codex_world_seed=N             │  │
│  │  Output: debug_exports/perf/result.json               │  │
│  └───────────────────────┬───────────────────────────────┘  │
│                          │                                  │
│  ┌───────────────────────┴───────────────────────────────┐  │
│  │              AI Agent Skill                            │  │
│  │  "Запусти перф-тест" → run → read JSON → diff         │  │
│  │  baseline → report violations → suggest fixes          │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 4. Направление A: JSON Telemetry Pipeline

### 4.1 Что делаем

Каждый headless перф-прогон производит один JSON-файл с полной телеметрией.
Файл самодостаточен — ИИ читает его и видит всё.

### 4.2 Формат вывода

```json
{
  "meta": {
    "timestamp": "2026-04-16T14:30:00Z",
    "seed": 12345,
    "godot_version": "4.6.1",
    "commit": "abc1234",
    "route": "far_loop",
    "scenarios": ["route", "room", "power", "mining"]
  },

  "boot": {
    "total_ms": 2340,
    "loading_screen_visible_ms": 180,
    "startup_bubble_ready_ms": 1200,
    "boot_complete_ms": 2340,
    "phases": {
      "compute": {"total_ms": 890, "per_chunk_avg_ms": 35.6},
      "apply": {"total_ms": 420, "per_chunk_avg_ms": 16.8},
      "redraw": {"total_ms": 680, "per_chunk_avg_ms": 27.2},
      "topology": {"total_ms": 210},
      "shadow": {"total_ms": 140}
    }
  },

  "streaming": {
    "chunks_loaded": 47,
    "chunks_unloaded": 22,
    "avg_generate_ms": 42.3,
    "avg_install_ms": 118.0,
    "avg_visual_first_pass_ms": 85.0,
    "avg_visual_full_ready_ms": 340.0,
    "max_generate_ms": 98.1,
    "max_install_ms": 145.0,
    "frontier_reservation_blocks": 3,
    "cache_hits": 12,
    "chunk_readiness_timeline": [
      {
        "coord": [2, -3],
        "requested_frame": 1200,
        "generate_complete_frame": 1205,
        "install_complete_frame": 1212,
        "first_pass_complete_frame": 1218,
        "full_ready_frame": 1230,
        "total_ms": 500.0
      }
    ]
  },

  "frame_summary": {
    "total_frames": 3600,
    "avg_ms": 14.2,
    "p50_ms": 12.8,
    "p95_ms": 16.1,
    "p99_ms": 18.4,
    "max_ms": 45.2,
    "hitches_over_22ms": 3,
    "hitches_over_33ms": 1,
    "categories_avg": {
      "streaming_load": 2.1,
      "streaming_redraw": 1.8,
      "topology": 0.8,
      "visual": 0.6,
      "shadow": 0.4,
      "building": 0.3,
      "power": 0.1,
      "spawn": 0.2,
      "interactive": 0.0,
      "dispatcher": 0.1,
      "other": 7.8
    },
    "categories_peak": {
      "streaming_load": 8.3,
      "streaming_redraw": 6.2,
      "topology": 3.1,
      "interactive": 3.7
    }
  },

  "contract_violations": [
    {
      "contract": "mine_tile < 2ms",
      "source": "PERFORMANCE_CONTRACTS §2.3",
      "actual_ms": 3.7,
      "context": {"tile": [142, 88], "terrain": "ROCK"}
    },
    {
      "contract": "background_budget < 6ms",
      "source": "PERFORMANCE_CONTRACTS §2.2",
      "actual_ms": 8.3,
      "context": {"category": "streaming_load", "frame": 1847}
    }
  ],

  "scenarios": {
    "route": {
      "status": "pass",
      "preset": "far_loop",
      "waypoints_reached": "6/6",
      "convergence": "finished",
      "blocker": "none"
    },
    "room": {
      "status": "pass",
      "steps": ["build_walls", "verify_indoor", "breach", "verify_outdoor",
                 "reclose", "verify_indoor", "destroy", "verify_outdoor"]
    },
    "power": {
      "status": "pass",
      "battery_placed": true,
      "supply_increased": true,
      "life_support_powered": true,
      "battery_removed": true,
      "supply_restored": true
    },
    "mining": {
      "status": "pass",
      "entry_mined": true,
      "reveal_activated": true,
      "zone_expanded": true,
      "save_roundtrip": true,
      "presentation_leak": false
    }
  },

  "native_profiling": {
    "chunk_generator": {
      "avg_total_ms": 42.3,
      "avg_noise_sampling_ms": 3.2,
      "avg_biome_resolution_ms": 2.1,
      "avg_terrain_resolve_ms": 4.8,
      "avg_variation_resolve_ms": 1.9,
      "avg_flora_placement_ms": 22.4,
      "avg_feature_poi_ms": 7.9
    },
    "topology_builder": {
      "avg_rebuild_ms": 12.3,
      "avg_flood_fill_ms": 8.1
    }
  }
}
```

### 4.3 Где собирать

| Данные | Источник | Что менять |
|---|---|---|
| Boot milestones | WorldPerfProbe `Startup.*` | Собирать в structured dict вместо print |
| Frame summary | WorldPerfMonitor `_print_summary` | Дублировать в JSON accumulator |
| Streaming timeline | ChunkStreamingService debug events | Записывать lifecycle per chunk |
| Contract violations | WorldPerfProbe | Проверять контракты при `record()` |
| Native profiling | ChunkGenerator C++ | Добавить `_prof_*` ключи в результат |
| Scenario results | RuntimeValidationDriver | Собирать результаты по сценариям |

### 4.4 Trigger

```
codex_perf_test                          — включить JSON телеметрию
codex_perf_output=path/to/result.json    — путь вывода (default: debug_exports/perf/result.json)
codex_quit_on_perf_complete              — quit после завершения всех сценариев
```

### 4.5 Baselines

Файл `debug_exports/perf/baseline_seed12345.json` коммитится в репозиторий.
Содержит "known good" значения для ключевых метрик.

При сравнении ИИ-агент (или скрипт) вычисляет дельты:

```
boot_ms:              2340 → 2280  (✓ -2.6%)
mine_tile_peak_ms:    1.8  → 3.7   (✗ +105%, нарушение контракта < 2ms)
avg_generate_ms:      42.3 → 38.1  (✓ -9.9%)
streaming_load_peak:  8.3  → 4.1   (✓ -51%)
```

**Простое правило для ИИ**: если `contract_violations` не пуст — это баг. Если метрика
ухудшилась > 20% — это регрессия. Если улучшилась > 10% — это прогресс.

### 4.6 Реализация

**Шаг 1**: `PerfTelemetryCollector` — новый RefCounted, собирает данные в Dictionary.
- Подписывается на WorldPerfProbe/WorldPerfMonitor через direct call (не EventBus — это debug infra).
- Активируется только при `codex_perf_test` в user args.
- Записывает JSON в `_ready_to_write()` → `FileAccess.store_string(JSON.stringify())`.

**Шаг 2**: RuntimeValidationDriver вызывает `PerfTelemetryCollector.record_scenario_result()`.

**Шаг 3**: WorldPerfMonitor передаёт frame data в collector каждый кадр.

**Шаг 4**: При `codex_quit_on_perf_complete` — пишем файл и `get_tree().quit()`.

**Файлы**:
- `core/debug/perf_telemetry_collector.gd` — основной сборщик
- Изменения в `world_perf_monitor.gd`, `runtime_validation_driver.gd`

**Оценка**: 2-3 дня.

## 5. Направление B: Scenario Factory

### 5.1 Текущее покрытие

RuntimeValidationDriver покрывает:
- ✅ Route traversal (streaming convergence)
- ✅ Room validation (build/breach/reclose/destroy)
- ✅ Power validation (place battery/remove/check)
- ✅ Mining + reveal + zone expansion + save/load roundtrip

### 5.2 Недостающие сценарии

| Сценарий | Что тестирует | Почему важно |
|---|---|---|
| **Crafting** | create item → verify inventory | Рецепты работают, инвентарь не ломается |
| **Mass Placement** | place 50 walls → measure total ms | Накопление хитчей при массовом строительстве |
| **Deep Mine** | mine 15+ tiles вглубь горы | Reveal zone scaling, topology rebuild depth |
| **Entity Stress** | spawn 200 items on ground | Количество entities в чанке |
| **Chunk Revisit** | walk 10 chunks away → return | Save/reload roundtrip, visual восстановление |
| **Survival Tick** | 600 game ticks with all systems | Голод/жажда/температура не тормозят |
| **Speed Traverse** | simulate 1000px/s movement | Стриминг при транспортной скорости |

### 5.3 Архитектура сценариев

```gdscript
class_name ValidationScenario extends RefCounted

## Базовый класс сценария автотестирования.

signal scenario_completed(result: Dictionary)

## Уникальный ID сценария.
func get_scenario_id() -> StringName:
    return &""

## Человекочитаемое имя.
func get_scenario_name() -> String:
    return ""

## Нужны ли определённые системы (building, power, etc.)?
func get_required_systems() -> Array[StringName]:
    return []

## Подготовка (вызывается один раз после boot).
func prepare(context: ValidationContext) -> bool:
    return true

## Шаг сценария (вызывается каждый кадр, пока не завершится).
## Возвращает true если сценарий ещё работает, false если завершён.
func process_step(context: ValidationContext, delta: float) -> bool:
    return false

## Результат сценария.
func get_result() -> Dictionary:
    return {"status": "not_run"}
```

```gdscript
class_name ValidationContext extends RefCounted

## Контекст, передаваемый сценариям. Содержит ссылки на системы.

var game_world: GameWorld
var player: Player
var building_system: BuildingSystem
var power_system: PowerSystem
var chunk_manager: ChunkManager
var command_executor: CommandExecutor
var mountain_roof_system: MountainRoofSystem
var telemetry: PerfTelemetryCollector
```

RuntimeValidationDriver рефакторится: текущие room/power/mining валидации
становятся отдельными `ValidationScenario` подклассами.

CLI-аргумент для выбора:
```
codex_validate_scenarios=route,room,power,mining,crafting,mass_build,deep_mine
codex_validate_scenarios=all   — все зарегистрированные
```

### 5.4 Реализация

**Шаг 1**: Создать `ValidationScenario`, `ValidationContext` базовые классы.

**Шаг 2**: Извлечь текущие room/power/mining из RuntimeValidationDriver в отдельные
файлы: `room_validation_scenario.gd`, `power_validation_scenario.gd`, `mining_validation_scenario.gd`.

**Шаг 3**: RuntimeValidationDriver становится оркестратором:
- Парсит `codex_validate_scenarios`
- Создаёт контекст
- Запускает сценарии последовательно
- Собирает результаты

**Шаг 4**: Добавить новые сценарии по приоритету:
1. `SpeedTraverseScenario` (критично — тест стриминга при транспортных скоростях)
2. `MassPlacementScenario` (обнаружение хитчей при массовом строительстве)
3. `DeepMineScenario` (тест масштаба reveal/topology)
4. `ChunkRevisitScenario` (roundtrip save/load)
5. `CraftingScenario`, `EntityStressScenario`, `SurvivalTickScenario` — позже

**Файлы**:
- `core/debug/scenarios/validation_scenario.gd`
- `core/debug/scenarios/validation_context.gd`
- `core/debug/scenarios/route_scenario.gd`
- `core/debug/scenarios/room_scenario.gd`
- `core/debug/scenarios/power_scenario.gd`
- `core/debug/scenarios/mining_scenario.gd`
- `core/debug/scenarios/speed_traverse_scenario.gd`
- `core/debug/scenarios/mass_placement_scenario.gd`
- `core/debug/scenarios/deep_mine_scenario.gd`
- `core/debug/scenarios/chunk_revisit_scenario.gd`
- Рефакторинг `runtime_validation_driver.gd`

**Оценка**: 5-7 дней (2 дня рефакторинг + 1 день на каждый новый сценарий).

## 6. Направление C: Native Profiling

### 6.1 Проблема

WorldPerfProbe измеряет время на уровне GDScript-вызовов. Внутри C++ — чёрный ящик.
Если `generate_chunk()` занимает 42ms, неизвестно — это noise, biome, terrain, flora или POI.

### 6.2 Простое решение: _prof_ payload

Добавить таймеры внутрь C++ функций. Результаты возвращаются в Dictionary
рядом с данными (zero overhead когда не используется — ключи просто не читаются).

```cpp
// chunk_generator.cpp :: generate_chunk()

Dictionary result;

auto t0 = OS::get_singleton()->get_ticks_usec();
// --- noise sampling ---
for (int y = 0; y < chunk_size; y++) {
    for (int x = 0; x < chunk_size; x++) {
        channels[y * chunk_size + x] = sample_channels(base_x + x, base_y + y);
    }
}
double noise_ms = double(OS::get_singleton()->get_ticks_usec() - t0) / 1000.0;

auto t1 = OS::get_singleton()->get_ticks_usec();
// --- biome resolution ---
// ...
double biome_ms = double(OS::get_singleton()->get_ticks_usec() - t1) / 1000.0;

auto t2 = OS::get_singleton()->get_ticks_usec();
// --- terrain resolve ---
// ...
double terrain_ms = double(OS::get_singleton()->get_ticks_usec() - t2) / 1000.0;

auto t3 = OS::get_singleton()->get_ticks_usec();
// --- flora placement ---
// ...
double flora_ms = double(OS::get_singleton()->get_ticks_usec() - t3) / 1000.0;

auto t4 = OS::get_singleton()->get_ticks_usec();
// --- feature/POI ---
// ...
double poi_ms = double(OS::get_singleton()->get_ticks_usec() - t4) / 1000.0;

result["_prof_noise_ms"] = noise_ms;
result["_prof_biome_ms"] = biome_ms;
result["_prof_terrain_ms"] = terrain_ms;
result["_prof_flora_ms"] = flora_ms;
result["_prof_poi_ms"] = poi_ms;
result["_prof_total_ms"] = noise_ms + biome_ms + terrain_ms + flora_ms + poi_ms;
```

GDScript-сторона:
```gdscript
# В collect_completed_runtime_generates или PerfTelemetryCollector
var prof_keys: Array[String] = []
for key: String in native_data:
    if key.begins_with("_prof_"):
        prof_keys.append(key)
        WorldPerfProbe.record("ChunkGenerator.%s" % key.trim_prefix("_prof_"), float(native_data[key]))
```

### 6.3 Аналогично для других C++ компонентов

| C++ класс | Фазы для профилирования |
|---|---|
| `ChunkGenerator` | noise, biome, terrain, variation, flora, poi |
| `MountainTopologyBuilder` | flood_fill, component_ids, edge_classification |
| `ChunkVisualKernels` | terrain_tiles, cover_tiles, cliff_tiles |
| `MountainShadowKernels` | ray_cast, shadow_map |
| `WorldPrepassKernels` | drainage, slope, ridge, river |

### 6.4 Tracy (продвинутое решение)

**godot-tracy** — модуль для интеграции Tracy профайлера с Godot.

Tracy даёт:
- Наносекундная точность
- Flame graphs (визуализация вложенности вызовов)
- JSON export для автоматического анализа
- Сетевое подключение — профилируй запущенную игру удалённо
- Memory profiling
- Lock contention

**Интеграция**:
1. Подключить godot-tracy как GDExtension или модуль
2. Добавить `ZoneScoped` макросы в C++ функции
3. GDScript-сторона: опциональный `TracyZone` wrapper
4. CLI: `--tracy` или `codex_tracy_capture=path.tracy`
5. После прогона: `tracy-csvexport trace.tracy > trace.csv` → AI парсит CSV

**Оценка для _prof_ payload**: 1-2 дня.
**Оценка для Tracy**: 3-5 дней (подключение + настройка + CI).

**Рекомендация**: начать с `_prof_` payload (быстро, zero deps), Tracy — второй шаг.

## 7. Направление D: Stress / Scale Presets

### 7.1 Зачем

Текущие тесты работают при нормальной плотности. Но архитектура должна держать
масштаб: 200 зданий, 500 предметов, 50 чанков traversal, транспортные скорости.

### 7.2 Пресеты

```
codex_stress_mode=mass_buildings   codex_stress_count=200
codex_stress_mode=entity_swarm     codex_stress_count=500
codex_stress_mode=long_traverse    codex_stress_chunks=50
codex_stress_mode=speed_traverse   codex_stress_speed=1000
codex_stress_mode=deep_mine        codex_stress_depth=30
codex_stress_mode=dense_world      codex_stress_flora_multiplier=3.0
```

### 7.3 StressDriver

Отдельный debug-нод (аналогично RuntimeValidationDriver), но с другой целью:
не "проверить что работает", а "нагрузить до предела и измерить".

Результат — блок в JSON телеметрии:

```json
"stress": {
  "mode": "mass_buildings",
  "target_count": 200,
  "actual_count": 200,
  "total_placement_ms": 1240,
  "avg_placement_ms": 6.2,
  "peak_placement_ms": 45.0,
  "frame_avg_during_ms": 18.4,
  "frame_p99_during_ms": 42.0,
  "hitches_during": 12
}
```

**Оценка**: 3-5 дней.

## 8. Направление E: AI Agent Skill

### 8.1 Что делаем

Claude Code skill `perf-observatory` который:

1. Запускает headless тест с нужными аргументами
2. Дожидается завершения
3. Читает JSON результат
4. Сравнивает с baseline (если есть)
5. Формулирует отчёт: что нарушено, что регрессировало, где искать

### 8.2 Примеры использования

```
User: "Запусти перф-тест"
→ Skill запускает headless, читает JSON
→ "3 нарушения контрактов, 2 регрессии относительно baseline.
   mine_tile: 3.7ms (контракт <2ms) — см. ChunkManager.try_harvest_at_world
   streaming_load peak: 8.3ms (было 5.1ms) — ChunkGenerator._prof_flora_ms вырос с 22ms до 38ms"

User: "Оптимизируй flora placement"
→ Skill запускает тест до, правит код, запускает тест после
→ "flora_ms: 22.4ms → 8.1ms (✓ -64%). Контракт streaming_load peak теперь 4.2ms (OK)."
```

### 8.3 Skill файл

```yaml
# .claude/skills/perf-observatory.md
name: perf-observatory
description: >
  Запуск перф-тестов Station Mirny, чтение результатов,
  сравнение с baseline, диагностика bottleneck'ов.
triggers:
  - "запусти перф-тест"
  - "проверь производительность"
  - "perf test"
  - "benchmark"
```

**Оценка**: 1 день (поверх направления A).

## 9. Рекомендации по оптимизации стриминга

Отдельно от observatory — конкретные идеи по ускорению загрузки чанков, 
основанные на диагнозе из §2.

### 9.1 Параллельный install (снять серийный bottleneck)

**Проблема**: `staged_chunk` — один. Install последовательный.

**Решение**: Позволить нескольким чанкам проходить finalize параллельно.
Не в смысле потоков — а в смысле "несколько чанков в разных фазах finalize
в одном кадре". Каждый finalize phase < 1ms, можно обработать 3-4 чанка за кадр
без нарушения бюджета.

**Форма**: `staged_queue: Array[StagedChunkEntry]` вместо `staged_chunk: Chunk`.
Каждый entry хранит свою `finalize_phase`. В `tick_loading` обработать столько
entries сколько влезает в бюджет.

### 9.2 Предиктивная загрузка с запасом

**Проблема**: `load_radius = 2` — только 2 чанка вперёд. При быстром движении
этого мало.

**Решение**: FrontierPlanner уже учитывает вектор движения. Увеличить
`max_forward_chunks` до 3-4 при быстром движении. Для транспорта — до 6-8.
Это `TravelStateResolver` + `ViewEnvelopeResolver`.

### 9.3 Кэш визуальных данных

**Проблема**: при revisit (уход и возврат) чанк перерисовывается заново.

**Решение**: `ChunkSurfacePayloadCache` (уже есть, 192 entry) кэширует native data.
Но визуальный результат (какие tile coords какие atlas coords) не кэшируется.
Кэш визуального payload'а — snap tiles → cache → restore without redraw.

### 9.4 C++ TileMap batch population

**Проблема**: `populate_native()` вызывает `set_cell()` на каждый тайл.
64×64 = 4096 вызовов через GDScript→Engine bridge.

**Решение**: C++ функция `batch_set_cells(tilemap, cells: PackedArray)` которая
делает все set_cell в одном native вызове без bridge overhead на каждый тайл.
Или использовать `TileMapLayer.set_cells_terrain_connect()` если applicable.

### 9.5 Deferred visual build

**Проблема**: первый визуальный проход (terrain tiles) должен завершиться
до того как игрок увидит чанк.

**Решение**: при staged finalize делать "terrain-only fast pass" — только
основные terrain tiles без flora, cover, shadows. Это значительно быстрее.
Остальное — через FrameBudgetDispatcher в background. Чанк визуально "готов"
после fast pass (может не хватать деталей), полностью готов после full_redraw.

## 10. Итерации

### Iteration 1: Telemetry + Native Profiling (3-4 дня)

**Цель**: ИИ может запустить тест и получить JSON с числами.

Что делаем:
- [ ] `PerfTelemetryCollector` — JSON сборщик
- [ ] `_prof_*` таймеры в `ChunkGenerator.cpp`
- [ ] `_prof_*` таймеры в `MountainTopologyBuilder.cpp`
- [ ] WorldPerfMonitor → collector feed
- [ ] RuntimeValidationDriver → scenario results feed
- [ ] CLI args: `codex_perf_test`, `codex_perf_output`
- [ ] Baseline файл для seed 12345

Acceptance:
- `codex_perf_test codex_world_seed=12345` → `result.json` с boot, streaming,
  frame_summary, contract_violations, scenarios, native_profiling
- JSON парсится без ошибок
- native_profiling показывает breakdown внутри ChunkGenerator

### Iteration 2: F11 Overlay Simplification (1-2 дня)

**Цель**: F11 показывает только визуальную карту чанков для человека. Вся детальная
телеметрия уходит в JSON для ИИ-агентов.

**Мотивация**: текущий debug overlay имеет 6 режимов (compact, expanded, queue, timeline,
perf, forensics) с текстовыми панелями, легендами, графиками. Человеку это непонятно
и бесполезно — нужны только цветные прямоугольники чанков. ИИ-агенту нужны структурированные
данные, а не пиксели на экране. Разделяем каналы: глаза → overlay, машина → JSON.

Что делаем:
- [ ] Оставить в `WorldChunkDebugOverlay` только один режим: chunk rectangles
  - Цветные прямоугольники по статусу чанка (loaded/generating/queued/staged/unloading)
  - Радиусные кольца (load_radius, unload_radius)
  - FPS counter (compact, в углу)
  - Позиция игрока (чанковые координаты)
- [ ] Удалить режимы: expanded, queue, timeline, perf, forensics, legend
- [ ] Удалить переключение режимов (Tab cycling) — F11 toggle on/off
- [ ] Все данные из удалённых режимов (queue состояние, timeline истории,
  perf breakdown, forensics) → `PerfTelemetryCollector` JSON output
- [ ] Цветовая схема чанков: зелёный=loaded, жёлтый=generating, синий=staged,
  красный=error/timeout, серый=queued
- [ ] Упростить код overlay с ~834 строк до ~150-200

Acceptance:
- F11 показывает только цветные прямоугольники чанков + FPS + координаты
- Нет текстовых панелей, нет переключения режимов
- Все детальные данные доступны в JSON через `PerfTelemetryCollector`
- Overlay код < 250 строк

### Iteration 3: Scenario Factory (5-7 дней)

**Цель**: модульные сценарии, новые тест-кейсы.

Что делаем:
- [ ] `ValidationScenario` / `ValidationContext` базовые классы
- [ ] Рефакторинг room/power/mining из RuntimeValidationDriver
- [ ] `SpeedTraverseScenario` (1000 px/s)
- [ ] `MassPlacementScenario` (50 walls)
- [ ] `DeepMineScenario` (15 tiles)
- [ ] `ChunkRevisitScenario` (10 chunks away + return)
- [ ] CLI: `codex_validate_scenarios=route,speed_traverse,mass_build,...`

Acceptance:
- Каждый сценарий → свой блок в JSON
- `SpeedTraverseScenario` проверяет что chunk readiness < traverse time
- Старые тесты не сломаны

### Iteration 4: AI Skill + Tracy (2-3 дня)

**Цель**: ИИ-агент может одной командой запустить тест и получить диагноз.

Что делаем:
- [ ] `.claude/skills/perf-observatory.md`
- [ ] Подключить godot-tracy (если решим)
- [ ] Baseline comparison script
- [ ] Документация workflow для ИИ-агента

Acceptance:
- ИИ запускает "перф-тест", получает машиночитаемый отчёт
- Отчёт содержит конкретные файлы и строки для исследования
- Tracy trace записывается и может быть проанализирован

### Iteration 4: Stress Presets (3-5 дней)

**Цель**: тестирование на масштабе.

Что делаем:
- [ ] `StressDriver` (debug-нод)
- [ ] Пресеты: mass_buildings, entity_swarm, long_traverse, speed_traverse, deep_mine
- [ ] Результаты → JSON телеметрия
- [ ] Stress baselines

Acceptance:
- `codex_stress_mode=mass_buildings codex_stress_count=200` работает headless
- JSON содержит stress-блок с метриками
- 200 зданий не роняют FPS ниже 30

### Iteration 5: Streaming Optimization (отдельная спека)

**Цель**: решить корневую проблему — игрок обгоняет стриминг.

Это **не часть observatory** — это отдельная feature spec, которая использует
observatory для измерения и верификации. Направления из §9:
- Параллельный install (staged_queue)
- Предиктивная загрузка
- C++ batch TileMap population
- Визуальный кэш
- Deferred terrain-only fast pass

## 11. Открытые вопросы

1. **Tracy vs _prof_**: начать только с `_prof_` payload, или сразу подключать Tracy?
   Рекомендация: `_prof_` first, Tracy — Iteration 3.

2. **Baseline seed**: использовать один fixed seed (12345) или несколько?
   Рекомендация: один primary (12345), один secondary (99999) для cross-validation.

3. **Headless rendering**: при `--headless` TileMap set_cell всё равно выполняется
   (Godot не пропускает). Нужен ли "data-only" режим без visual build для чистого
   тестирования логики? Рекомендация: да, как отдельный CLI arg `codex_skip_visual`.

4. **Streaming optimization scope**: включать ли §9 (streaming fixes) в эту же спеку,
   или выносить в отдельную? Рекомендация: отдельная спека, но с acceptance test
   через observatory ("до: avg_install_ms=118, после: <50").
