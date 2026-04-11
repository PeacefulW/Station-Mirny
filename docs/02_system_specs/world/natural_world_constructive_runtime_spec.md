---
title: Natural World Constructive Runtime Spec
doc_type: feature_spec
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-04
depends_on:
  - natural_world_generation_overhaul.md
related_docs:
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - world_lab_spec.md
---

# Natural World Constructive Runtime Spec

## Purpose

Эта спека описывает конструктивную замену отклонённой Phase 2.

Её задача не "искать красивый сид", а довести уже сделанную полезную Phase 1 до состояния, где:

- `WorldPrePass` становится источником правды для крупных структур мира;
- `SurfaceTerrainResolver` реально рисует мир по этим структурам;
- биомы начинают следовать причинным каналам (`drainage`, `slope`, `rain_shadow`, `continentalness`);
- переходы между биомами перестают быть жёсткими и становятся видимыми через экотоны;
- результат виден в `WorldLab` на фиксированных seed без reroll, bootstrap-фильтров и lucky-seed search.

## Design Intent

Игрок должен видеть не "случайную удачу шума", а мир, у которого есть понятная макро-логика:

- реки текут по бассейнам и собираются в русла, а не выглядят как повторяющиеся полосы;
- горы образуют семейства хребтов и массивов, а не сетку параллельных band'ов;
- речные долины влажнее окружающего мира;
- за горными цепями заметны сухие lee-side зоны;
- внутренние континентальные области ощущаются иначе, чем побережья;
- границы биомов не обрываются одним тайлом, а дают переходную полосу.

Ключевой принцип:

- requested seed -> one deterministic world -> stop.

Никаких post-hoc проверок "достаточно ли красиво получилось" в runtime bootstrap здесь не допускается.

## Player-Visible Success Definition

К концу этой спеки пользователь должен видеть в `WorldLab` и в обычной генерации мира одновременно:

- 2-3 главных речных системы с естественным ветвлением и разной шириной;
- хребты, которые формируют выраженные горные регионы, а не просто повышают шанс `ROCK`;
- поймы и песчаные/влажные речные коридоры, привязанные к рекам;
- dry side / wet side вокруг крупных ridge families;
- заметную разницу между coastal и inland biome composition;
- мягкие переходы между соседними биомами через смешанную флору и локальные вариации.

## Global Non-Negotiables

В этой спеки запрещено:

- возвращать `validate_landmarks()` как new-game gate;
- снова вводить remediation loop с многократным `WorldPrePass.compute()`;
- делать soft-fix thresholds под конкретный seed;
- искать соседние seed или lucky seed;
- превращать tooling в runtime whitelist мира;
- возвращать `sample_all() -> Dictionary` как hot-path API;
- держать две независимые "правды мира", где pre-pass считает одно, а runtime рисует другое.

## Current Diagnosis

На момент старта этой спеки полезная часть overhaul уже частично существует, но не замкнута на финальный результат:

- `WorldPrePass` уже считает полезные крупномасштабные каналы и структуры;
- GDScript runtime уже читает structure truth через `WorldPrePass -> WorldComputeContext.sample_structure_context() -> SurfaceTerrainResolver`;
- native path всё ещё несёт старую band/noise структуру и потому пока не совпадает с GDScript path;
- `BiomeResolver`, `BiomeData` и `BiomeResult` всё ещё работают по старой схеме;
- `LocalVariationResolver` и `ChunkFloraBuilder` ещё не ecotone-aware;
- native path всё ещё опирается на старую band/noise модель и старую схему биомов.

Итог: полезные данные уже считаются, но мир ещё не обязан выглядеть как следствие этих данных.

## Proof Harness

Эта спека считается удачной только если её прогресс можно увидеть, а не только прочитать в коде.

Обязательный visual proof pipeline для всех "видимых" итераций:

- использовать `WorldLab` как основной single-seed proof tool;
- использовать `GameWorldDebug` local preview export как sanctioned artifact path для runtime-visible proof, когда нужен chunk/flora/ecotone result в реальном world boot;
- работать на фиксированном наборе seed: `42`, `1337`, `9001`, `424242`, `777777`;
- для каждой видимой итерации сохранять минимум два режима предпросмотра:
- `Terrain`
- `Biome`
- по мере появления новых режимов также:
- `Drainage`
- `Ridges`
- `Climate`
- `Ecotone`
- для каждой видимой итерации прикладывать before/after screenshots в задачу или PR.
- если proof снят не вручную, а через exporter, в closure report обязательно указывать seed, команду запуска и пути к сохранённым PNG.
- если итерация меняет flora / decor / biome-border behavior, proof должен включать не только `Terrain` / `Biome`, но и слой, на котором видно сам consumer result (`vegetation`, `ecotone`, или эквивалентный режим).

Нельзя завершать видимую итерацию словами "на глаз стало лучше" без хотя бы одного fixed-seed сравнения.

### Standard world proof recipe

Чтобы следующие итерации не изобретали новый proof path каждый раз, использовать следующий порядок по умолчанию.

#### A. Macro truth proof через `WorldLab`

Использовать:
- scene: `res://scenes/ui/world_lab.tscn`
- fixed seed из agreed seed set
- минимум два режима:
- `Terrain`
- режим, который показывает changed truth (`Biome`, `Drainage`, `Ridges`, `Climate`, `Ecotone`)

Когда применять:
- изменение world truth
- изменение крупных river / ridge / biome shapes
- causal biome tuning
- native/script parity по крупной форме мира

#### B. Runtime consumer proof через `GameWorldDebug`

Использовать:
- scene: `res://scenes/world/game_world.tscn`
- `F6` — local snapshot + save
- `F7` — hide/show panel
- `F8` — full export
- export root: `debug_exports/world_previews/`

Когда применять:
- terrain consumers
- flora / decor placement
- ecotone consumers
- любые local chunk-visible изменения, которые должны быть видны в реальном runtime world

#### C. Headless fixed-seed proof

Если нужен reproducible artifact без ручного UI, использовать sanctioned runtime exporter вместо нового механизма.

Текущий стандартный runtime proof command:

```powershell
godot.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_export_ecotone_proof codex_world_seed=<seed> codex_ecotone_proof_count=1 codex_ecotone_radius=16
```

Что делает:
- запускает `GameWorld`
- принудительно использует указанный seed через `codex_world_seed=<seed>`
- находит hotspot с выраженным ecotone / mixed-border behavior
- сохраняет `biomes`, `terrain`, `structures`, `ecotone`, `vegetation` PNG в `debug_exports/world_previews/`

Когда применять:
- Iteration 7 style proof для mixed-border flora / ecotone consumers
- любые следующие world-visible итерации, если существующий exporter уже покрывает нужный слой

#### D. Правило расширения

Если новой итерации нужен дополнительный proof layer:
- сначала расширить `WorldLab` mode или `WorldPreviewExporter`
- только потом думать о новом harness

Цель:
- один устойчивый proof pipeline
- повторяемые fixed-seed артефакты
- минимум ad-hoc tooling на каждую итерацию

## Data Contracts - New And Touched

### Новый derived object: `WorldPrePassChannels`

- Что: компактный runtime-safe набор sampled значений pre-pass для одного тайла.
- Где: `core/systems/world/world_pre_pass_channels.gd`
- WRITE owner: `WorldComputeContext.sample_prepass_channels()`
- READ consumers: `BiomeResolver`, `SurfaceTerrainResolver`, `LocalVariationResolver`, `WorldLab`, native bridge
- Состав полей MVP:
- `drainage`
- `slope`
- `rain_shadow`
- `continentalness`
- Инварианты:
- все поля нормализованы в `[0, 1]`;
- структура read-only после создания;
- отсутствие `WorldPrePass` даёт безопасные нули, а не crash.
- Запрещено:
- хранить там сырые массивы coarse-grid;
- пробрасывать туда lake/ridge graph internals;
- расширять его ad hoc полями без обновления спеки и канонических доков.

### Затронутый object: `WorldStructureContext`

- Что меняется: структура остаётся "про крупные формы", но начинает читаться из `WorldPrePass`, а не из band-noise.
- WRITE owner: только `WorldComputeContext.sample_structure_context()`
- READ consumers: `SurfaceTerrainResolver`, `LocalVariationResolver`, biome scoring там, где ещё нужны именно structure-only признаки
- Минимальный состав после миграции:
- `ridge_strength`
- `mountain_mass`
- `river_strength`
- `floodplain_strength`
- `river_distance`
- `river_width`
- Инварианты:
- все поля нормализованы или приведены к документированному диапазону;
- данные детерминированы от requested seed;
- структура не семплирует noise напрямую после Iteration 2.

### Затронутый canonical layer: `World Pre-pass`

- Что меняется: curated public read surface расширяется настолько, чтобы runtime мог опираться на pre-pass, не лезя в его внутренние массивы.
- Что не меняется:
- слой остаётся boot-time only;
- не сохраняется в save;
- не получает runtime mutation path;
- не занимается validation/reroll/remediation.

### Затронутый object: `BiomeResult`

- Что меняется: вместо одного победителя хранит primary + secondary кандидата и силу перехода.
- Новые поля MVP:
- `primary_biome`
- `primary_score`
- `secondary_biome`
- `secondary_score`
- `dominance`
- `ecotone_factor`
- Что не меняется:
- determinism при одинаковом seed и одинаковых входных каналах;
- stable tie-break по priority и biome id.

## Execution Order

Порядок обязателен.

Нельзя прыгать сразу в ecotones, пока runtime всё ещё рисует старые band rivers и band ridges.

1. Сделать pre-pass channels публично и безопасно читаемыми.
2. Переключить structure truth на pre-pass.
3. Довести terrain placement до нового structure truth.
4. Расширить biome schema.
5. Перевести `BiomeResolver` на причинные каналы.
6. Добавить top-2 biome result и `ecotone_factor`.
7. Подключить экотоны к flora / local variation / terrain presentation.
8. Довести native parity.
9. Выпилить legacy band path и дочистить баланс/доки.

## Iterations

### Iteration 1 - Curated Pre-pass Read Surface And Visual Proof

Цель: открыть недостающие полезные каналы наружу и сразу дать себе способ их видеть на fixed seed.

Что делается:

- добавить `WorldPrePassChannels` как отдельный lightweight container;
- добавить в `WorldComputeContext` safe entrypoint `sample_prepass_channels(world_pos)`;
- расширить curated `WorldPrePass.sample()` / `get_grid_value()` новыми read-only каналами:
- `floodplain_strength`
- `river_distance`
- `river_width`
- не публиковать lake records, ridge graph и другие сырые внутренности;
- расширить `WorldLab` режимами просмотра:
- `Drainage`
- `Ridges`
- `Climate`
- при необходимости временно собрать climate mode как composite из `rain_shadow` и `continentalness`.

Видимый результат:

- можно увидеть, хорошие ли сами pre-pass данные, ещё до переподключения terrain и биомов;
- становится видно, где уже есть красивые river basins, ridge families и dry/wet macro regions.

Acceptance tests:

- [ ] `WorldComputeContext` имеет отдельный safe sampler для pre-pass channels.
- [ ] `WorldPrePass.sample()` и `get_grid_value()` отдают `floodplain_strength`, `river_distance`, `river_width` без доступа к raw arrays.
- [ ] `WorldLab` рендерит `Terrain`, `Biome`, `Drainage`, `Ridges`, `Climate` на fixed seed set без runtime chunk bootstrap.
- [ ] В коде нет нового hot-path API вида `sample_all() -> Dictionary`.
- [ ] Скриншоты fixed seed set позволяют визуально различать drainage map, ridge map и climate map.

Файлы, которые будут затронуты:

- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/world_compute_context.gd`
- `core/systems/world/world_structure_context.gd`
- `core/systems/world/world_pre_pass_channels.gd`
- `scenes/ui/world_lab.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Файлы, которые не должны быть затронуты:

- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/biome_resolver.gd`
- `gdextension/src/chunk_generator.cpp`

Required updates:

- `DATA_CONTRACTS.md`: да, потому что у `World Pre-pass` расширяется documented read surface.
- `PUBLIC_API.md`: да, потому что появляются новые safe read semantics.

### Iteration 2 - Switch Structure Truth To `WorldPrePass`

Цель: сделать так, чтобы крупные структуры мира читались из pre-pass, а не из старого band-noise sampler.

Что делается:

- переписать `WorldComputeContext.sample_structure_context()` на pre-pass-derived structure sampling;
- убрать legacy directed-band sampler plumbing из GDScript runtime, чтобы не оставалось второй structural truth;
- заполнить `WorldStructureContext` из pre-pass значений:
- `ridge_strength`
- `mountain_mass`
- `river_strength`
- `floodplain_strength`
- `river_distance`
- `river_width`
- оставить старые band параметры в балансе только как временный compatibility ballast, но перестать использовать их как source of truth в GDScript runtime.

Видимый результат:

- даже без отдельной переделки resolver'ов часть мира уже меняется, потому что текущие runtime consumers начинают получать не band noise, а реальную pre-pass структуру;
- линии рек и гор перестают следовать искусственным повторяющимся направлениям.

Acceptance tests:

- [ ] `WorldComputeContext.sample_structure_context()` больше не вызывает band/noise structure sampling.
- [ ] `ridge_strength`, `mountain_mass`, `river_strength`, `floodplain_strength` в `WorldStructureContext` происходят из `WorldPrePass`.
- [ ] `river_distance` и `river_width` доступны runtime consumers через `WorldStructureContext`.
- [ ] В `WorldLab` terrain preview для fixed seed set больше нет доминирования почти параллельных river/ridge band'ов через весь мир.
- [ ] requested seed создаёт один world snapshot без reroll/remediation.

Файлы, которые будут затронуты:

- `core/autoloads/world_generator.gd`
- `core/systems/world/world_compute_context.gd`
- `core/systems/world/world_structure_context.gd`
- `scenes/ui/world_lab.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Файлы, которые не должны быть затронуты:

- `core/systems/world/biome_resolver.gd`
- `data/biomes/*.tres`
- `gdextension/src/chunk_generator.cpp`

Required updates:

- `DATA_CONTRACTS.md`: да, потому что меняется reader contract и source of truth для structure context.
- `PUBLIC_API.md`: да, если меняется sanctioned entrypoint для structure sampling.

### Iteration 3 - Constructive Surface Terrain Resolution

Цель: сделать так, чтобы тайлы поверхности визуально следовали новой структуре мира, а не лишь слегка реагировали на неё.

Что делается:

- обновить `SurfaceTerrainResolver`, чтобы он использовал:
- `river_width`
- `river_distance`
- `floodplain_strength`
- `ridge_strength`
- `mountain_mass`
- `slope`
- отделить:
- water core logic
- bank / floodplain logic
- mountain core logic
- foothill / carve logic
- оставить spawn safety guarantees без изменений;
- оставить polar modifiers как overlay над новой структурной правдой, а не как отдельную "конкурирующую генерацию";
- при необходимости добавить минимальные новые balance knobs только там, где без них нельзя выразить новую логику.

Видимый результат:

- после этой итерации мир уже обязан выглядеть заметно лучше даже без новых биомов;
- реки получают ширину и береговую зону;
- горы читаются как массивы, связанные хребтами;
- долины лучше режут горные зоны.

Acceptance tests:

- [ ] `SurfaceTerrainResolver` использует pre-pass-derived `river_width` / `river_distance` / `floodplain_strength`.
- [ ] river tiles визуально расширяются вниз по течению, а не имеют почти постоянную ширину.
- [ ] bank / floodplain tiles держатся возле river corridors, а не образуют широкие параллельные noise-полосы.
- [ ] mountain placement зависит от ridge families и slope-aware carving, а не только от старых threshold mix'ов.
- [ ] fixed-seed screenshots показывают заметное отличие between pre-Iteration-3 and post-Iteration-3 terrain.

Файлы, которые будут затронуты:

- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/tile_gen_data.gd` при необходимости
- `core/systems/world/chunk_content_builder.gd` при необходимости
- `data/world/world_gen_balance.gd` при необходимости
- `scenes/ui/world_lab.gd`

Файлы, которые не должны быть затронуты:

- `core/systems/world/biome_resolver.gd`
- `data/biomes/*.tres`
- `gdextension/src/chunk_generator.cpp`

Required updates:

- `DATA_CONTRACTS.md`: только если меняется surface payload contract или read semantics.
- `PUBLIC_API.md`: только если добавляется новый caller-facing safe entrypoint.

### Iteration 4 - Biome Schema Expansion

Цель: подготовить данные биомов к причинной схеме без немедленного ломания существующего мира.

Что делается:

- расширить `BiomeData` новыми ranges и weights:
- `drainage`
- `slope`
- `rain_shadow`
- `continentalness`
- добавить backward-compatible defaults:
- ranges `0..1`
- weights `0.0`
- обновить все `data/biomes/*.tres`;
- обновить любой debug/native/world-lab export биомных полей, который сериализует `BiomeData`;
- сохранить старое поведение при нулевых новых weight.

Видимый результат:

- на карте почти ничего не меняется, но появляется безопасный фундамент для causal biome iteration;
- в tooling и debug видно, что у всех биомов теперь есть новая схема.

Acceptance tests:

- [ ] Все biome resources загружаются с новыми полями без ошибок.
- [ ] При `*_weight = 0.0` новый канал не влияет на итоговый score.
- [ ] `WorldLab` и любые biome debug dumps не теряют новые поля при сериализации.
- [ ] fixed seed set до и после Iteration 4 даёт те же biome winners при нулевых новых weight.

Файлы, которые будут затронуты:

- `data/biomes/biome_data.gd`
- `data/biomes/*.tres`
- `scenes/ui/world_lab.gd`
- файлы serialisation bridge, если они экспортируют biome defs в native/tooling

Файлы, которые не должны быть затронуты:

- `core/systems/world/biome_resolver.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/local_variation_resolver.gd`

Required updates:

- `DATA_CONTRACTS.md`: нет, если меняются только biome resource fields и не меняется world layer ownership.
- `PUBLIC_API.md`: нет, если это не caller-facing public API.

### Iteration 5 - Causal `BiomeResolver`

Цель: перевести выбор биома с "старых шумовых диапазонов" на "следствие физики и pre-pass каналов".

Что делается:

- добавить `prepass_channels` во вход `BiomeResolver`;
- вычислять `effective_moisture` как функцию:
- base moisture
- rain shadow
- continentalness drying
- drainage bonus
- использовать `drainage`, `slope`, `rain_shadow`, `continentalness` в scoring;
- сохранить deterministic tie-break;
- оставить fallback path, но сделать его совместимым с новым input contract;
- сделать debug summary у `BiomeResult` достаточно подробным, чтобы видеть, почему биом победил.

Рекомендуемая формула MVP:

`effective_moisture = base_moisture * rain_shadow * (1.0 - continentalness * continental_drying_factor) + drainage * drainage_moisture_bonus`

Видимый результат:

- вдоль рек биомы становятся влажнее;
- за горными хребтами становится суше;
- внутренние части континента перестают быть просто "та же влага, что и у берега";
- biome map начинает объясняться географией.

Acceptance tests:

- [ ] `BiomeResolver` получает pre-pass input без прямого чтения внутренних массивов `WorldPrePass`.
- [ ] `effective_moisture` вычисляется один раз и попадает в debug summary.
- [ ] fixed-seed `Biome` preview показывает wetter river corridors и drier lee-side regions.
- [ ] При нулевых новых weights ranking биомов совпадает со старой схемой.
- [ ] `BiomeResolver` остаётся deterministic для одинакового seed и world_pos.

Файлы, которые будут затронуты:

- `core/systems/world/biome_resolver.gd`
- `core/systems/world/world_compute_context.gd`
- `core/systems/world/world_pre_pass_channels.gd`
- `scenes/ui/world_lab.gd`
- `data/world/world_gen_balance.gd` при необходимости для drying/moisture knobs

Файлы, которые не должны быть затронуты:

- `core/systems/world/chunk_flora_builder.gd`
- `core/systems/world/local_variation_resolver.gd`
- `gdextension/src/chunk_generator.cpp`

Required updates:

- `DATA_CONTRACTS.md`: только если меняется documented read chain между world pre-pass и biome resolution.
- `PUBLIC_API.md`: только если сигнатура promoted в sanctioned caller-facing API.

### Iteration 6 - `BiomeResult` Top-2 And `Ecotone`

Цель: уйти от winner-takes-all и начать считать переходную полосу как first-class result.

Что делается:

- расширить `BiomeResult` полями primary / secondary / dominance / `ecotone_factor`;
- обновить `BiomeResolver`, чтобы он хранил top-2 кандидата, а не только одного победителя;
- сделать `ecotone_factor` функцией разницы score;
- добавить в `WorldLab` отдельный `Ecotone` mode;
- сохранить совместимость потребителей там, где им пока нужен только primary biome.

Видимый результат:

- появляется явная карта переходов;
- на biome preview и ecotone preview видно, где мир должен смешивать соседние биомы, а не рубить границу ножом.

Acceptance tests:

- [ ] `BiomeResult` хранит `primary_biome`, `secondary_biome`, `primary_score`, `secondary_score`, `dominance`, `ecotone_factor`.
- [ ] `ecotone_factor` близок к `0` в уверенных core areas и растёт в спорных пограничных зонах.
- [ ] `WorldLab` умеет рисовать `Ecotone` map.
- [ ] existing consumers, которым нужен только primary biome, не ломаются.

Файлы, которые будут затронуты:

- `core/systems/world/biome_result.gd`
- `core/systems/world/biome_resolver.gd`
- `core/systems/world/world_compute_context.gd`
- `scenes/ui/world_lab.gd`

Файлы, которые не должны быть затронуты:

- `core/systems/world/chunk_flora_builder.gd`
- `core/systems/world/local_variation_resolver.gd`
- `gdextension/src/chunk_generator.cpp`

Required updates:

- `DATA_CONTRACTS.md`: нет, если меняется только derived biome result object.
- `PUBLIC_API.md`: да, если `BiomeResult` или resolver signature описаны как sanctioned public surface.

### Iteration 7 - Ecotone Consumers

Цель: сделать так, чтобы экотоны были не только debug-числом, а реальным видимым слоем мира.

Что делается:

- научить `LocalVariationResolver` учитывать `ecotone_factor`;
- научить `ChunkFloraBuilder` смешивать flora/decor sets primary и secondary biome;
- при необходимости добавить ecotone-aware terrain tint / variation selection;
- оставить feature hooks вне обязательного scope, кроме безопасного read-only использования, если оно понадобится для edge-of-biome content позже.

Видимый результат:

- на границе двух биомов игрок видит смешанную флору;
- локальные вариации сменяются мягче;
- переходы становятся читаемыми как регион, а не как ошибка палитры.

Acceptance tests:

- [ ] `LocalVariationResolver` использует `ecotone_factor` при расчёте modulation.
- [ ] `ChunkFloraBuilder` умеет смешивать primary/secondary biome flora sets.
- [ ] На fixed seed set есть наблюдаемые mixed-border regions, которые отсутствовали до этой итерации.
- [ ] Один-тайлный резкий flip vegetation на biome boundary заметно уменьшается.

Файлы, которые будут затронуты:

- `core/systems/world/local_variation_resolver.gd`
- `core/systems/world/chunk_flora_builder.gd`
- `core/systems/world/surface_terrain_resolver.gd` при необходимости
- `scenes/ui/world_lab.gd`

Файлы, которые не должны быть затронуты:

- `gdextension/src/chunk_generator.cpp`
- `core/autoloads/world_generator.gd` кроме тонкой plumbing при крайней необходимости

Required updates:

- `DATA_CONTRACTS.md`: нет, если это derived/presentation-поведение без смены ownership.
- `PUBLIC_API.md`: нет, если не меняется public caller surface.

### Iteration 8 - Native Path Parity

Цель: убрать ситуацию, где script path уже красивый и причинный, а native path всё ещё живёт на старом band/noise мире.

Что делается:

- передать native path всё, что нужно для новой structural truth и новой biome schema;
- либо сделать native path thin consumer готовой script-side truth, если это проще и дешевле;
- убрать старую независимую band-derived structure sampling внутри native chunk generator;
- поддержать новые biome fields и новый `BiomeResult` contract на native bridge уровне.

Видимый результат:

- игрок видит один и тот же мир независимо от того, каким build path строится chunk data.

Acceptance tests:

- [ ] script path и native path на одинаковом seed и одинаковых координатах дают одинаковый terrain class в agreed tolerance.
- [ ] script path и native path дают одинаковый primary biome id.
- [ ] В native path больше нет независимой directed band logic для rivers/ridges.
- [ ] fixed-seed screenshots native/script не расходятся по крупным river/ridge shapes.

Файлы, которые будут затронуты:

- `gdextension/src/chunk_generator.cpp`
- связанные header/bridge файлы native generator
- файлы параметризации world/native build path
- `scenes/ui/world_lab.gd`, если он умеет проверять parity
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Файлы, которые не должны быть затронуты:

- unrelated chunk streaming / topology / save-load systems

Required updates:

- `DATA_CONTRACTS.md`: да, если меняется ownership/read semantics между script и native path.
- `PUBLIC_API.md`: да, если меняется sanctioned bridge API.

### Iteration 9 - Legacy Band Cleanup And Balance Closure

Цель: удалить вторую, уже ненужную модель мира и оставить только одну конструктивную схему.

Что делается:

- удалить любой оставшийся legacy directed-band sampler/accessor, если authoritative path уже полностью живёт на `WorldPrePass`;
- удалить legacy band params из `WorldGenBalance`, когда больше нет runtime/native consumers;
- выпилить мёртвые helper'ы и debug serialization, завязанные на старую band logic;
- синхронизировать `DATA_CONTRACTS.md` и `PUBLIC_API.md` с финальной схемой;
- обновить `WorldLab`, чтобы он отражал только актуальные world inputs.

Видимый результат:

- tuning knobs наконец совпадают с тем, что реально влияет на мир;
- исчезает путаница "почему меняю pre-pass, а визуал всё ещё определяется чем-то ещё".

Acceptance tests:

- [ ] grep по runtime path не находит активных чтений legacy band params для rivers/ridges после миграции.
- [ ] В репозитории больше нет legacy directed-band sampler script, а authoritative runtime path идёт только через `WorldPrePass`.
- [ ] fixed-seed world result не меняется при удалении legacy band params, если новая система уже authoritative.
- [ ] `DATA_CONTRACTS.md` и `PUBLIC_API.md` описывают только актуальную схему без dual truth.

Файлы, которые будут затронуты:

- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `scenes/ui/world_lab.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Файлы, которые не должны быть затронуты:

- unrelated gameplay systems

Required updates:

- `DATA_CONTRACTS.md`: да
- `PUBLIC_API.md`: да

## Required Documentation Updates By Iteration

- Iteration 1: update both canonical docs
- Iteration 2: update both canonical docs
- Iteration 3: docs only if payload/read semantics changed
- Iteration 4: canonical docs not required by default
- Iteration 5: docs only if resolver/pre-pass read chain becomes documented contract
- Iteration 6: update `PUBLIC_API.md` only if `BiomeResult` public surface is documented there
- Iteration 7: canonical docs not required by default
- Iteration 8: update both canonical docs
- Iteration 9: update both canonical docs

## Out Of Scope

Эта спека специально не делает следующее:

- не вводит новый macro-skeleton generator beyond current Phase 1 pre-pass;
- не меняет save/load semantics;
- не трогает chunk streaming architecture;
- не расширяет canonical terrain types beyond текущие surface classes, если это не станет абсолютно необходимо;
- не делает automated scenic scoring gate для игрока;
- не возвращает landmark grammar в каком бы то ни было disguise.

## Risks

### R1. Half-migration trap

Опасность: переключить часть consumers на pre-pass, но оставить native или biome path на старой модели.

Снижение риска:

- не считать итерацию завершённой без fixed-seed visual proof;
- явно держать separate acceptance для script path и native parity.

### R2. Debug invisibility

Опасность: код меняется, но невозможно быстро понять, стало ли красивее.

Снижение риска:

- `WorldLab` обязателен как proof harness уже с Iteration 1.

### R3. Over-tuning avalanche

Опасность: начать "лечить" красоту десятью новыми thresholds вместо правильного source of truth.

Снижение риска:

- сначала смена world truth;
- только потом минимальный retune;
- каждый новый balance knob должен быть оправдан конкретным visible failure mode.

### R4. Native divergence

Опасность: GDScript мир и native мир расходятся и любая настройка начинает давать два разных результата.

Снижение риска:

- native parity выделена в отдельную обязательную итерацию, а не оставлена "на потом".

## Definition Of Done

Эта спека считается выполненной только когда одновременно выполнено всё ниже:

- `WorldPrePass` является источником правды для крупных структур мира;
- `SurfaceTerrainResolver` реально использует pre-pass-derived structure truth;
- `BiomeResolver` использует `drainage`, `slope`, `rain_shadow`, `continentalness`;
- `BiomeData` и все biome resources расширены и настроены;
- `BiomeResult` отдаёт top-2 + `ecotone_factor`;
- flora/local variation/terrain consumers реально используют экотоны;
- native path не расходится со script path;
- legacy band path удалён физически, без compatibility accessor и dual-path runtime;
- fixed-seed screenshots через `WorldLab` показывают видимый прогресс по Terrain, Biome, Climate и Ecotone без reroll.

## Transition Note

Эта спека является конструктивной заменой rejected runtime-landmark phase из [natural_world_generation_overhaul.md](./natural_world_generation_overhaul.md).

Старую overhaul-спеку нужно читать так:

- Phase 0-1: полезная база, сохраняется;
- Rejected Phase 2: не возвращается;
- Phase 3 идеи про causal channels и ecotones: переоформлены здесь в исполнимый итерационный план;
- дальнейшая работа по красивому миру должна идти по этому документу, а не по bootstrap validation logic.
