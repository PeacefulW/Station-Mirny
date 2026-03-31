# Performance Audit — 2026-03-31

Автоматический аудит performance-опасных паттернов согласно `docs/00_governance/PERFORMANCE_CONTRACTS.md`.

---

## 1. TileMapLayer.clear() в интерактивных путях

### Потенциально опасные вызовы

| Файл | Строка | Описание | Контракт |
|---|---:|---|---|
| `core/systems/world/chunk.gd` | 1041 | `_cover_layer.clear()` в `_rebuild_cover_layer()` — полный clear + полный перебор всех тайлов чанка | §1.4 Forbidden: full cover rebuild |
| `core/systems/world/chunk.gd` | 1050 | `_cliff_layer.clear()` в `refresh_cliffs()` — полный clear + полный перебор всех тайлов чанка | §1.4 Forbidden: full cliff rebuild |

**Контекст**: `_rebuild_cover_layer()` вызывается из `_redraw_dynamic_visibility()` (chunk.gd:672). Сейчас `_redraw_dynamic_visibility` не имеет внешних вызовов (мёртвый код или зарезервирован), поэтому **риск низкий**. Однако если эта функция будет подключена к интерактивному пути (например, после mine), она нарушит контракт.

`refresh_cliffs()` — public-метод. Если вызван во время gameplay, это полный rebuild cliff-слоя одного чанка.

### Безопасные вызовы (boot/background)

- `chunk.gd:442-447` — `_redraw_all()` — используется при boot/загрузке чанка. ✅
- `chunk.gd:471-476` — `_begin_progressive_redraw()` — background progressive path. ✅
- `chunk.gd:528-530` — `continue_first_pass()` — первый progressive pass, инициализация. ✅
- `chunk_manager.gd:217-246` — boot cleanup. ✅

---

## 2. Циклы по всем загруженным чанкам вне boot-time

| Файл | Строка | Описание | Контракт |
|---|---:|---|---|
| `core/systems/lighting/mountain_shadow_system.gd` | 239 | `_mark_all_dirty()` — `for coord in _chunk_manager.get_loaded_chunks()` — вызывается из `_process()` при смене sun angle | §4 Main-thread principle; §1.4 Forbidden: loop over all loaded chunks |
| `core/systems/world/chunk_manager.gd` | 492 | `_sync_loaded_chunk_display_positions()` — `for coord in _loaded_chunks` — вызывается из streaming tick и z-level change | §4 Main-thread principle |
| `core/systems/world/chunk_manager.gd` | 1141 | streaming tick — `for coord in _loaded_chunks` для определения чанков на выгрузку | §4 (допустимо если bounded) |
| `core/systems/world/chunk_manager.gd` | 2373 | `_start_topology_build()` — `for coord in _loaded_chunks` — snapshot ключей для инкрементальной стройки | ✅ (часть budgeted topology build) |
| `core/systems/world/chunk_manager.gd` | 2691 | `_rebuild_loaded_mountain_topology()` — `for chunk in _loaded_chunks` с вложенным `for each tile` — полный перестроение | §4 (вызывается из `_ensure_topology_current`, но уже убран из интерактивного пути, см. строку 2789) |

### Подробности по mountain_shadow_system.gd

`_mark_all_dirty()` (строка 236-241) итерирует все loaded chunks и вызывается:
- Строка 68: из `_process()` при превышении `shadow_angle_threshold` — **runtime, каждый раз при смене угла солнца**
- Строка 185: из `_on_z_level_changed` — допустимо (редкое событие)

**Проблема**: при ~20+ загруженных чанках `_process()` делает полный обход loaded chunks при каждой смене угла. Сама по себе итерация лёгкая (только `_mark_dirty`), но паттерн нарушает принцип "no loop over all loaded chunks in interactive path".

---

## 3. Массовые add_child/queue_free в одном фрейме

| Файл | Строка | Описание | Контракт |
|---|---:|---|---|
| `scenes/world/spawn_orchestrator.gd` | 138-139 | `clear_pickups()` — `queue_free()` для ВСЕХ pickups | §9 Main-thread hazards |
| `scenes/world/spawn_orchestrator.gd` | 145-146 | `clear_enemies()` — `queue_free()` для ВСЕХ enemies | §9 Main-thread hazards |

**Контекст**: обе функции вызываются только из `load_pickups()` / `load_enemy_runtime()` — это save/load path, под loading screen. **Риск низкий**, но при большом количестве сущностей может вызвать stutter при загрузке.

### UI-вызовы (допустимые)

- `world_lab.gd:160`, `inventory_ui.gd:147`, `power_ui.gd:177`, `pause_menu.gd:290`, `main_menu.gd:292` — UI rebuild при открытии/закрытии панелей. Обычно малое количество нод. ✅

---

## 4. Массовые set_cell вне boot

Все найденные `set_cell()` в `chunk.gd` (строки 757, 761, 789, 1085, 1102) — одиночные вызовы внутри per-tile redraw функций (`_redraw_terrain_tile`, `_redraw_cover_tile`, `_redraw_cliff_tile`). Используются в progressive/budgeted redraw. ✅

`_rebuild_cover_layer()` (chunk.gd:1038-1045) и `refresh_cliffs()` (chunk.gd:1047-1053) выполняют clear() + mass set_cell для всех тайлов чанка — **см. пункт 1 выше**.

---

## 5. randf()/randi() для позиционно-зависимого контента

| Файл | Строка | Описание | Контракт |
|---|---:|---|---|
| `core/systems/world/resource_node.gd` | 39 | `randi_range(data.drop_amount_min, data.drop_amount_max)` — количество дропа из ресурсного нода | Deterministic hashing (CLAUDE.md) |
| `scenes/world/spawn_orchestrator.gd` | 44-45 | `randf() * TAU`, `randf_range(100, 400)` — позиция спавна pickup | Deterministic hashing |
| `scenes/world/spawn_orchestrator.gd` | 163-164 | `randf() * TAU`, `randf_range(...)` — позиция спавна enemy | Deterministic hashing |
| `scenes/world/spawn_orchestrator.gd` | 182-184 | `randi_range(...)`, `randf_range(-40, 40)` — количество и позиция scrap drop | Deterministic hashing |
| `core/entities/fauna/basic_enemy.gd` | 42-43 | `randf() * balance.scan_interval` — staggering таймеров | **Допустимо** — runtime jitter, не контент |
| `core/entities/fauna/basic_enemy.gd` | 150 | `randf() * TAU` — направление бродяжничества | **Допустимо** — runtime AI |
| `core/entities/fauna/basic_enemy.gd` | 187 | `randf() * 2.0` — jitter wander timer | **Допустимо** — runtime AI |

**Анализ**: `resource_node.gd:39` — количество дропа определяется `randi_range`, что делает его недетерминистичным. Однако это runtime gameplay event (не генерация мира), и результат не влияет на визуал мира. **Серьёзность низкая**.

`spawn_orchestrator.gd` — позиции спавна используют `randf()` для направления и расстояния. Это runtime spawning, не мировая генерация. **Допустимо**, если позиции не сохраняются и не влияют на топологию. Pickups сохраняются (`save_pickups`), но позиция записывается после спавна, а не регенерируется.

---

## 6. Прямые load("res://data/...") вместо обращений к реестрам

| Файл | Строка | Описание | Контракт |
|---|---:|---|---|
| `scenes/ui/z_transition_overlay.gd` | 14 | `load("res://data/balance/z_level_balance.tres")` | Data-driven Registries (CLAUDE.md) |
| `scenes/ui/world_lab.gd` | 351 | `load("res://data/world/world_gen_balance.tres")` | Data-driven Registries |
| `core/entities/structures/z_stairs.gd` | 18 | `load("res://data/balance/z_level_balance.tres")` | Data-driven Registries |
| `core/systems/building/building_catalog.gd` | 4 | `preload("res://data/balance/power_balance.tres")` | Data-driven Registries |

**Анализ**: balance ресурсы (`z_level_balance.tres`, `world_gen_balance.tres`, `power_balance.tres`) — это конфигурационные данные, не контент с namespace:id. Они не проходят через реестры по дизайну (WorldGenerator.balance — прямой доступ к balance). **Серьёзность: информационная**. Не является нарушением, если balance-ресурсы намеренно исключены из registry pattern.

### preload для скриптов-хелперов

- `data/flora/flora_set_data.gd:4` — `preload("res://data/flora/flora_entry.gd")`
- `data/decor/decor_set_data.gd:4` — `preload("res://data/decor/decor_entry.gd")`
- `core/systems/world/chunk_flora_builder.gd:9-12` — preload script references
- `core/autoloads/world_feature_registry.gd:4-5` — preload script references
- `core/autoloads/flora_decor_registry.gd:7-8` — preload script references

Это preload GDScript-классов для type checking, не runtime data load. **Допустимо**. ✅

---

## 7. Прямые вызовы приватных функций из forbidden-списков PUBLIC_API.md

PUBLIC_API.md не содержит явного forbidden-списка с перечислением запрещённых приватных функций. Документ использует позитивную модель: "если функции нет в 'Безопасные точки входа' — вызывать запрещено".

Аудит прямых кросс-системных вызовов приватных (`_prefix`) методов не проводился в полном объёме, так как это потребовало бы полного графа зависимостей. **Рекомендуется** провести целевой аудит в рамках отдельной задачи.

---

## Сводка находок

| # | Серьёзность | Файл | Строка | Проблема |
|---|---|---|---:|---|
| 1 | ⚠️ Medium | `chunk.gd` | 1041, 1050 | `_rebuild_cover_layer()` / `refresh_cliffs()` — полный clear + rebuild. Потенциально опасно при подключении к interactive path |
| 2 | ⚠️ Medium | `mountain_shadow_system.gd` | 68, 239 | `_mark_all_dirty()` из `_process()` итерирует все loaded chunks при смене sun angle |
| 3 | ℹ️ Low | `spawn_orchestrator.gd` | 138-146 | Mass `queue_free()` в `clear_pickups()`/`clear_enemies()` — допустимо (save/load path) |
| 4 | ℹ️ Info | `z_transition_overlay.gd`, `z_stairs.gd`, `building_catalog.gd` | 14, 18, 4 | Прямой load/preload balance .tres — допустимо если by design |
| 5 | ℹ️ Low | `resource_node.gd` | 39 | `randi_range()` для drop amount — недетерминистично, но runtime gameplay event |

---

## Рекомендации

1. **`_rebuild_cover_layer()` / `refresh_cliffs()`**: добавить инкрементальный путь (dirty region) если эти функции будут подключены к интерактивному пути (mine/build).

2. **`mountain_shadow_system._mark_all_dirty()`**: паттерн допустим, т.к. `_mark_dirty()` — O(1) per chunk и только добавляет в очередь. Однако формально нарушает §4. Рекомендуется добавить комментарий с обоснованием или заменить на event-driven подход (подписка на chunk_loaded для dirty marking).

3. **`spawn_orchestrator` mass queue_free**: при большом числе сущностей (100+) может вызвать hitch при save/load. Рекомендуется бюджетирование, если количество сущностей вырастет.

---

*Отчёт сгенерирован автоматически. Дата: 2026-03-31.*
