# Отчёт о целостности документации — 2026-03-31

> Автоматическая проверка согласованности PUBLIC_API.md, DATA_CONTRACTS.md и SYSTEM_INVENTORY.md с кодовой базой проекта «Станция Мирный».

## Общий результат

| Документ | Статус | Расхождений |
|----------|--------|-------------|
| PUBLIC_API.md | **OK** | 0 критических |
| DATA_CONTRACTS.md | **OK с замечаниями** | 1 организационное |
| SYSTEM_INVENTORY.md | **OK с замечаниями** | 1 пропущенная система |

---

## 1. PUBLIC_API.md — Проверка safe entry points

**Проверено 173 функции** из всех систем: World, Mining, Chunk Lifecycle, Topology, Reveal, Presentation, Z-Level, WorldGenerator, Player, Health, Inventory, Equipment, Oxygen, BaseLifeSupport, Building, Power, Spawn, Enemy AI, Noise, Time, Save/Load, Crafting, Command, Content Registries.

### Результат: все 173 функции найдены в коде

Ни одна функция из секций «Безопасные точки входа» и «Чтение» не отсутствует в кодовой базе. Сигнатуры соответствуют документированным. Функции находятся в классах, указанных в документе.

### Замечания

- Нет расхождений между документированными и реальными точками входа.

---

## 2. DATA_CONTRACTS.md — Проверка слоёв данных и владельцев

### 2.1 Observed files (21 файл)

**Все 21 файл из секции «Observed files for this version» существуют** в кодовой базе по указанным путям.

### 2.2 Владельцы слоёв

Все 8 классов-владельцев из Layer Map найдены в коде:
- WorldFeatureRegistry, ChunkManager, Chunk, WorldGenerator
- MountainRoofSystem, UndergroundFogState, MountainShadowSystem, WorldFeatureDebugOverlay

### 2.3 Ключевые функции (spot check)

Все проверенные ключевые функции, упомянутые в контрактах слоёв, существуют:
- `WorldFeatureHookResolver.resolve_for_origin()`
- `WorldPoiResolver.resolve_for_origin()`
- `ChunkBuildResult.to_native_data()`
- `WorldGenerator.build_chunk_content()`, `build_chunk_native_data()`, `initialize_world()`
- `ChunkManager.get_terrain_type_at_global()`, `_saved_chunk_data`
- `Chunk._terrain_bytes`, `_modified_tiles`

### 2.4 Расхождения

**[ЗАМЕЧАНИЕ] ZLevelManager не включён в Layer Map таблицу и Observed files**

- Файл `core/systems/world/z_level_manager.gd` реально существует и полностью реализован.
- В DATA_CONTRACTS.md он документирован в отдельной секции «Domain: Session & Time», но **не включён в основную Layer Map таблицу** (строки 47–57) и **не указан в «Observed files for this version»**.
- Это организационное замечание — код и документация согласованы по содержанию, но структура документа может вводить в заблуждение.

**[ИНФО] 15 файлов в `core/systems/world/` не включены в Observed files**

Следующие файлы не перечислены в секции «Observed files», но являются implementation-деталями документированных слоёв (World, Mining, Generation):

- `biome_resolver.gd`, `biome_result.gd` — поддержка World layer
- `chunk_flora_builder.gd`, `chunk_flora_result.gd` — генерация флоры
- `local_variation_context.gd`, `local_variation_resolver.gd` — вариация terrain
- `large_structure_sampler.gd` — размещение крупных структур
- `planet_sampler.gd`, `world_channels.gd`, `world_noise_utils.gd` — шум/сэмплинг
- `world_structure_context.gd` — контекст генерации структур
- `chunk_save_system.gd` — персистенция чанков
- `resource_node.gd` — сущность ресурсного узла
- `world_perf_probe.gd` — инструментация производительности

Эти файлы — внутренние хелперы, не вводят новых слоёв данных и не нарушают контракты. Включение в Observed files — на усмотрение автора документа.

---

## 3. SYSTEM_INVENTORY.md — Проверка списка систем

### 3.1 Файлы из инвентаря

**Все 80 файловых путей, перечисленных в SYSTEM_INVENTORY.md, существуют** в кодовой базе. Нет ни одного отсутствующего файла или ошибочного пути.

### 3.2 Расхождения

**[РАСХОЖДЕНИЕ] WorldFeatureRegistry не включён в SYSTEM_INVENTORY.md**

- Файл: `core/autoloads/world_feature_registry.gd`
- Класс: `WorldFeatureRegistrySingleton`
- Тип: autoload, реестр контента (canonical, read-only после boot)
- Это полноценный реестр определений feature hook и POI, аналогичный BiomeRegistry (#33), FloraDecorRegistry (#34) и ItemRegistry (#31).
- В PUBLIC_API.md и DATA_CONTRACTS.md система **полностью задокументирована** (секция «World feature / POI registry» в PUBLIC_API.md, Layer «Feature / POI Definitions» в DATA_CONTRACTS.md).
- Но в SYSTEM_INVENTORY.md строка для WorldFeatureRegistry **отсутствует**.

### 3.3 Системы в коде, не найденные в инвентаре

Кроме WorldFeatureRegistry, других пропущенных автолоадов или крупных систем не обнаружено. Все autoloads из `core/autoloads/` и все системы из `core/systems/` и `scenes/world/` учтены.

---

## Рекомендации по обновлению

### Приоритет 1 (рекомендуется)

1. **SYSTEM_INVENTORY.md** — добавить строку для `WorldFeatureRegistry`:

   | # | System | Main files | Classification | Owns gameplay state? | In DATA_CONTRACTS? | In PUBLIC_API? | Reason if excluded |
   |---|--------|-----------|----------------|---------------------|--------------------|----------------|-------------------|
   | 35* | World feature / POI registry | `core/autoloads/world_feature_registry.gd`<br>`data/world/features/feature_hook_data.gd`<br>`data/world/features/poi_definition.gd` | canonical | no | yes (existing) | yes (existing) | — |

### Приоритет 2 (на усмотрение)

2. **DATA_CONTRACTS.md** — рассмотреть добавление `z_level_manager.gd` в секцию «Observed files for this version» и/или создать отдельный Layer entry в Layer Map для Z-level canonical state, чтобы избежать путаницы при навигации по документу.

3. **DATA_CONTRACTS.md** — рассмотреть перечисление `chunk_save_system.gd` в Observed files, т.к. он участвует в персистенции World layer.

### Не требует действий

- PUBLIC_API.md полностью актуален и не требует обновлений.
- Все 173 safe entry points подтверждены.
- Все файловые пути из всех трёх документов валидны.
- Владельцы слоёв и ключевые функции DATA_CONTRACTS.md подтверждены.

---

*Отчёт сгенерирован автоматически 2026-03-31.*
