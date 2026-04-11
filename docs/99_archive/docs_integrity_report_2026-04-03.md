# Отчёт о целостности документации — 2026-04-03

## Резюме

Проведена автоматическая проверка трёх ключевых governance-документов на соответствие реальному коду проекта.

**Общий результат:** документация в хорошем состоянии. Критических расхождений не обнаружено. Выявлен один пробел в SYSTEM_INVENTORY.md и несколько минорных рекомендаций.

---

## 1. PUBLIC_API.md — Проверка точек входа

**Проверено функций:** ~145 safe entry points и read-функций из 30 классов.

**Метод:** grep по `func FUNCTION_NAME` в соответствующих файлах.

### Результат: ВСЕ ФУНКЦИИ НАЙДЕНЫ

Каждая функция, перечисленная в PUBLIC_API.md как безопасная точка входа или функция чтения, существует в коде с корректной сигнатурой.

| Класс | Проверено функций | Статус |
|-------|------------------|--------|
| ChunkManager | 21 | OK |
| Chunk | 15 | OK |
| ZLevelManager | 2 | OK |
| MountainRoofSystem | 3 | OK |
| UndergroundFogState | 2 | OK |
| MountainShadowSystem | 3 | OK |
| WorldGenerator | 9 | OK |
| TimeManager | 11 | OK |
| SaveManager | 7 | OK |
| Player | 11 | OK |
| HealthComponent | 4 | OK |
| InventoryComponent | 10 | OK |
| EquipmentComponent | 7 | OK |
| OxygenSystem | 5 | OK |
| BaseLifeSupport | 3 | OK |
| BuildingSystem | 11 | OK |
| PowerSystem | 3 | OK |
| PowerSourceComponent | 4 | OK |
| PowerConsumerComponent | 2 | OK |
| SpawnOrchestrator | 9 | OK |
| BasicEnemy | 4 | OK |
| NoiseComponent | 3 | OK |
| GameWorld | 1 | OK |
| CraftingSystem | 2 | OK |
| CommandExecutor | 1 | OK |
| HarvestTileCommand | 1 | OK |
| ItemRegistry | 7 | OK |
| BiomeRegistry | 5 | OK |
| FloraDecorRegistry | 4 | OK |
| WorldFeatureRegistry | 4 | OK |

**Функции из PUBLIC_API.md, не найденные в коде:** нет.

---

## 2. DATA_CONTRACTS.md — Проверка слоёв данных

### Файлы из scope-списка

Все 22 файла из секции "Observed files for this version" существуют в репозитории.

### Классы и методы владельцев

| Проверка | Статус |
|----------|--------|
| WorldFeatureHookResolver.resolve_for_origin() | Найден |
| WorldPoiResolver.resolve_for_origin() | Найден |
| WorldPrePass.compute() | Найден |
| MountainTopologyBuilder (GDExtension C++) | Найден (gdextension/src/) |
| ChunkManager: topology-методы | Найдены |

### Результат: РАСХОЖДЕНИЙ НЕТ

Все слои данных, их владельцы и scope-файлы соответствуют реальной структуре кода.

---

## 3. SYSTEM_INVENTORY.md — Проверка списка систем

### Файлы систем

Все 42 системы из инвентаря имеют 100% существующих файлов. Ни одного отсутствующего файла или неправильного пути.

### Найденные расхождения

#### ПРОБЕЛ: WorldFeatureRegistry отсутствует в инвентаре

`core/autoloads/world_feature_registry.gd` — это autoload-реестр, являющийся owner'ом слоя "Feature / POI Definitions" в DATA_CONTRACTS.md. Он:

- Упомянут в CLAUDE.md как один из ключевых autoload-ов
- Является owner'ом canonical layer в DATA_CONTRACTS.md
- Имеет 4 функции в PUBLIC_API.md (get_feature_by_id, get_poi_by_id, get_all_feature_hooks, get_all_pois)
- Упомянут в спеке world_feature_and_poi_hooks.md

Но **НЕ включён** ни в одну из 42 строк SYSTEM_INVENTORY.md.

**Рекомендация:** Добавить строку в таблицу SYSTEM_INVENTORY.md:

```
| 43 | World feature / POI registry | `core/autoloads/world_feature_registry.gd` | canonical | no (immutable after boot) | yes (existing в DATA_CONTRACTS) | yes (existing в PUBLIC_API) | — |
```

Либо включить этот файл в System 1 (World generation), где он логически является частью стека. Учитывая, что DATA_CONTRACTS.md уже выделяет его как отдельный canonical layer owner, предпочтительнее отдельная строка.

### Незначительные наблюдения

Следующие файлы существуют в коде, но не документированы в инвентаре. Это корректно — они являются подкомпонентами или инфраструктурными файлами:

- `scenes/ui/z_transition_overlay.gd` — UI-компонент z-перехода (часть System 2)
- `scenes/ui/world_lab.gd` — dev-инструмент (часть System 41)
- `scenes/ui/draggable_panel.gd` — базовый UI-класс

Около 27 вспомогательных файлов (builders, resolvers, factories, command implementations) правильно вложены в scope родительских систем и не требуют отдельных записей.

---

## 4. Перекрёстная согласованность документов

| Проверка | Результат |
|----------|-----------|
| PUBLIC_API.md ↔ код | Полное соответствие |
| DATA_CONTRACTS.md ↔ код | Полное соответствие |
| SYSTEM_INVENTORY.md ↔ код | 1 пробел (WorldFeatureRegistry) |
| PUBLIC_API.md ↔ SYSTEM_INVENTORY.md | WorldFeatureRegistry есть в PUBLIC_API, нет в INVENTORY |
| DATA_CONTRACTS.md ↔ SYSTEM_INVENTORY.md | WorldFeatureRegistry — owner в DATA_CONTRACTS, нет в INVENTORY |

---

## 5. Рекомендации по обновлению

### Приоритет: средний

1. **Добавить WorldFeatureRegistry в SYSTEM_INVENTORY.md** — единственное реальное расхождение между документами. Реестр является canonical owner в DATA_CONTRACTS и имеет public API, но отсутствует в инвентаре систем.

### Приоритет: низкий (информационно)

2. **Рассмотреть обновление version/last_updated** в SYSTEM_INVENTORY.md (текущий: v0.1, 2026-03-28) — документ помечен как draft и source_of_truth: false. По мере стабилизации стоит повысить статус.

3. **Нет расхождений в именах функций, путях файлов или ownership boundaries** — документация актуальна на момент проверки.

---

*Отчёт сгенерирован автоматически 2026-04-03.*
