---
title: Seamless World Streaming - Active Task Brief
doc_type: active_task_brief
status: approved
owner: design+engineering
source_of_truth: false
version: 1.4
last_updated: 2026-09-05
code_baseline_revision: 121331d
active_subgoal: S4
active_subgoal_status: accepted
git_workflow: main_dirty_user_commits
related_docs:
  - ../README.md
  - WORKFLOW.md
  - ENGINEERING_STANDARDS.md
  - PROJECT_GLOSSARY.md
  - ../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../02_system_specs/world/world_runtime.md
  - ../02_system_specs/world/world_dynamic_lighting_2d.md
  - ../02_system_specs/ui/performance_flight_recorder.md
  - ../02_system_specs/meta/save_and_persistence.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../05_adrs/0002-wrap-world-is-cylindrical.md
  - ../05_adrs/0003-immutable-base-plus-runtime-diff.md
  - ../05_adrs/0005-light-is-gameplay-system.md
  - ../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
---

# Бесшовный стриминг мира — активная задача

## Роль документа

Это долговременный task brief и компактный tracker одной конкретной цели. Он
сохраняет общий замысел, порядок подцелей, правила остановки и доказательства
между чатами Codex.

Документ не заменяет canonical system specs или ADR. При конфликте побеждает
approved документ с `source_of_truth: true`. Статус здесь описывает выполнение
задачи, а не архитектурную истину проекта.

## Общая цель

Обеспечить бесшовное перемещение по процедурному миру: при обычной максимальной
скорости игрок не видит генерацию или подгрузку земли, гор, деревьев, камней,
декора, травы, теней, масок и других элементов окружения.

Зум не должен создавать запросы генерации, повторной загрузки или пересоздания
чанков. Область данных и presentation-residency заранее рассчитывается под
максимальный разрешенный zoom-out и сохраняет запас по направлению движения.

Текущий визуал и функционал сохраняются, включая пещеры, копание, коллизии,
факел, дневное/ночное освещение, погоду, сохранение и загрузку. На согласованной
целевой конфигурации итоговая реализация должна держать устойчивые 60 FPS и
иметь ограниченное, предсказуемое потребление RAM/VRAM при росте числа объектов
и биомов.

## Технически честные границы

- Бесконечный мир не хранится целиком. Постоянно готовой остается ограниченная
  область вокруг игрока: visible envelope, fully prepared reserve и background
  generation frontier.
- Обычное перемещение проверяется до максимальной разрешенной скорости игрока.
- Произвольный далекий teleport является отдельным сценарием и может требовать
  нового loading gate.
- Zoom может менять render culling уже готовых данных, но не residency demand,
  generation demand или lifetime чанков.
- Loading screen не является доказательством устойчивого streaming throughput.
  Время cold start и поведение при длительном движении измеряются отдельно.
- Средний FPS не является достаточным доказательством. Обязательны frame-time
  percentiles, GPU/CPU timings, queue pressure и отсутствие player-visible
  hitches.
- Масштабируемость означает bounded working set и bounded work per frame, а не
  обещание бесплатного неограниченного количества контента.

## Непереговорные ограничения

1. Нельзя ухудшать текущий утвержденный визуал ради FPS без прямого решения
   пользователя.
2. Нельзя ломать gameplay или environment behavior ради presentation speed.
3. Нельзя считать подцель принятой только по unit/contract/smoke tests.
4. Нельзя скрывать незагруженную область туманом, затемнением, crop или меньшим
   zoom-out, если это меняет текущий визуальный контракт.
5. Нельзя возвращать крупные части провалившейся rescue-реализации без новой
   локальной гипотезы и измеримого доказательства.
6. Нельзя вводить новый manager/framework/arena до доказательства, что текущая
   минимальная архитектура не закрывает измеренный bottleneck.
7. Main-thread apply должен быть bounded; тяжелый compute остается native/worker
   согласно governance.
8. Canonical world output, save shape и `world_version` нельзя менять в рамках
   чистой presentation/performance оптимизации.

## Git- и приемочный процесс

Эта задача намеренно не использует отдельные feature branches.

- Работа выполняется в текущем `main`.
- Codex не создает ветки и не выполняет Git-коммиты.
- Codex не stage-ит файлы и не выполняет destructive Git cleanup.
- Пользователь сам просматривает dirty-tree и создает один commit после приемки
  каждой подцели.
- До начала подцели Codex записывает исходный `git status` и отделяет
  существующие изменения от своих.
- Технически готовый candidate не равен принятому этапу.
- После candidate closure Codex останавливается. Следующая подцель остается
  locked до явного `принимаю` или эквивалентного решения пользователя.
- Если пользователь не принимает результат, работа продолжается только внутри
  той же подцели. Следующий этап не начинается.

## Состояния подцели

- `locked` — предыдущая подцель не принята.
- `pending_user_start` — может быть запущена новой `/goal`.
- `in_progress` — разрешена работа только этой подцели.
- `candidate_ready` — автоматическая проверка завершена; требуется ручная
  приемка.
- `accepted` — пользователь явно принял результат и может создать commit.
- `rejected` — пользователь показал регрессию; этап остается текущим.

## Текущий статус

| Поле | Значение |
|---|---|
| Общий статус | S4_accepted |
| Code baseline | `121331d runtie debugger` |
| Текущая подцель | S4 — бесшовный terrain при движении; принято |
| Принятый baseline | S1, S2, S3 и S4 |
| Следующий разрешающий шаг | отдельное решение пользователя о запуске S5; S5 доступен, не начат; S6-S8 остаются locked |
| Последняя ручная приемка | S4 принято пользователем, 2026-09-05 |
| Последний closure report | `S04_CLOSURE_REPORT_2026-07-23.md` |

## Карта подцелей

| ID | Подцель | Статус | Обязательный результат |
|---|---|---|---|
| S1 | Baseline и воспроизводимая приемка | accepted | эталонные captures, маршрут и бюджеты без оптимизации runtime |
| S2 | Наблюдаемый readiness contract | accepted | точная причина неготовности каждого чанка без нового presentation framework |
| S3 | Honest loading screen и initial bubble | accepted | первый игровой кадр и резерв полностью готовы по измеримому gate |
| S4 | Бесшовный terrain при движении | accepted | ни одного видимого отсутствующего terrain/mountain чанка на маршруте |
| S5 | Zoom-independent residency и hysteresis | pending_user_start | zoom не создает generation/load/unload demand |
| S6 | Бесшовные деревья, камни и декор | locked | объекты готовы до входа в viewport без visual pop |
| S7 | Трава, тени, пещеры и lighting parity | locked | полный visual/gameplay parity, включая факел |
| S8 | 60 FPS, bounded memory и scale proof | locked | принятый performance envelope и 10x content stress evidence |

## S1 — Baseline и воспроизводимая приемка

### Цель

Зафиксировать честное состояние `121331d` до новой оптимизации и создать один
повторяемый visual/runtime/performance маршрут.

### Не входит

- изменение streaming behavior
- loading screen
- новые counters без доказанной необходимости
- исправление найденных проблем

### Результат

- target hardware, renderer, resolution, VSync и build type
- фиксированный seed и сохраненный стартовый сценарий
- точная максимальная обычная скорость игрока и разрешенный zoom range
- cold-start duration
- F4 trace обычного старта и непрерывного движения
- эталонные скриншоты day/night, plains, dense objects, mountain, cave/torch
- baseline FPS/frame-time/GPU/CPU/RAM/VRAM/queue metrics
- предложенные числовые P95/P99/max-frame acceptance thresholds для S8

### Зафиксированный измерительный стенд

По решению пользователя все S1/S8-сравнения выполняются на
`res://scenes/dev/mountain_runtime_dig_dev_scene.tscn`. Сцена инстанцирует
настоящий `world_runtime_v0`, но имеет dev-only scan и телепорт к горе, поэтому
ее `scene-ready` нельзя выдавать за время загрузки обычной новой игры.

Probe `s1_mountain_runtime_baseline_v1` принудительно создает новый мир с seed
`131071`, default worldgen resources, world version `63`, временем day 1 09:00
на паузе и ясной погодой. Последний save не участвует. Два независимых запуска
обязаны получать одинаковые worldgen signature и runtime mountain/stand tiles.

Оконный ввод и F4 выполняет пользователь; Codex не управляет компьютером.
Подробный маршрут и результаты хранятся в
`artifacts/codex_perf/seamless_world_streaming/S01_BASELINE_MANIFEST_2026-07-22.md`.

### Exit gate

Пользователь подтверждает, что маршрут воспроизводим, скриншоты отражают
правильный текущий визуал, а baseline не содержит случайно включенных dev
подмен.

## S2 — Наблюдаемый readiness contract

### Цель

Сделать существующий lifecycle доказуемым: `requested -> generated -> gameplay
ready -> presentation ready -> reserve ready -> visible -> retained/evicted`.

### Ограничение

Это instrumentation/contract шаг. Он не разрешает новую GPU arena, второй
streamer или переписывание object presentation.

### Exit gate

Для любого отсутствующего чанка или слоя diagnostics дает одну конкретную
причину и длительность стадии; наблюдение само не создает значимого frame cost.

### Candidate evidence

Автоматический deterministic mountain probe прошел: 49 source-demand entries,
48 честно отмечены missing, у каждой есть конкретный blocker; detailed snapshot
занял `6593 us` и не изменил streaming queues. Smoke/regression/determinism
набор прошел. Отчет:
`artifacts/codex_perf/seamless_world_streaming/S02_CLOSURE_REPORT_2026-07-22.md`.
Оконный F4/F2-маршрут принят пользователем 2026-07-23. Пользователь отдельно
подтвердил, что cave/torch parity не является содержательным риском
instrumentation-only S2 и не должен блокировать переход к S3.

## S3 — Honest loading screen и initial bubble

### Цель

Не показывать игровой viewport, пока область под максимальный zoom-out плюс
movement reserve фактически не готова.

### Readiness gate

Gate считается закрытым только после готовности требуемых terrain, gameplay
masks/collisions и всех визуальных слоев, которые по общей цели не могут
появляться перед игроком. Fixed timeout или декоративный progress запрещены.

### Измерения

- cold start wall time
- время каждой readiness stage
- prepared chunks/second
- первый показанный frame
- memory after initial bubble

### Exit gate

Первый кадр на максимальном zoom-out полный, запас готов, progress честный,
функционал new game/load сохранен. Допустимое время экрана утверждает
пользователь после измерений, а не до них.

## S4 — Бесшовный terrain при движении

### Цель

Гарантировать готовую землю, воду и горную presentation/mask область впереди
игрока при максимальной обычной скорости.

### Ограничение

На этом шаге нельзя переписывать деревья, декор и траву. Гипотеза должна быть
минимальной и проверяться на настоящем маршруте.

### Контракт реализации S4

- Runtime work class: `background streaming`; player movement остается
  `interactive` и только меняет bounded demand.
- `WorldCore` сохраняет ownership канонического terrain packet;
  `WorldStreamer` остается единственным scheduling/presentation owner;
  `ChunkView` владеет только derived presentation.
- При текущем visible radius streamer держит симметричное materialized terrain
  reserve на один chunk дальше. Земля, вода, mountain mask и shoreline mask
  этого кольца готовятся скрыто и не получают collision до visible demand.
- Еще одно packet-only support кольцо дает reserve-чанкам полный halo source.
  При radius `4` это bounded envelope `81 visible + 40 reserve + 48 packet
  support = 169` chunk packets; это не whole-world prepass.
- Новый центр demand появляется только при пересечении chunk boundary.
  Вошедший reserve frontier должен быть готов раньше, чем за `3.2 s`, которые
  требуются игроку со скоростью `320 px/s` для пересечения следующего
  `1024 px` chunk.
- S4 не меняет readiness, визуал, placement или batching деревьев, декора и
  травы. Эти слои не могут использоваться как доказательство terrain readiness.
- После принятого S3 startup gate незавершенный object presentation не держит
  готовый terrain скрытым: terrain/mask view открывается по собственному guard,
  а внешний object layer и его blocking collision остаются выключены до
  завершения существующего object reveal guard. На самом S3 startup атомарность
  полной стартовой presentation сохраняется.
- Envelope пока следует текущему stream radius. Независимость residency от zoom,
  hysteresis и long-route retention остаются S5.

### Разрешенные файлы S4

- `core/systems/world/world_streamer.gd`
- новый узкий policy/accounting helper под `core/systems/world/`, только если
  он уменьшает ответственность существующего orchestrator
- S4 probe/test под `tools/`
- этот task brief, `world_runtime.md` и boundary docs только при фактическом
  изменении documented surface
- S4 evidence/closure artifacts

### Запрещенные файлы и изменения S4

- object/flora/decor/grass generation, batching, shaders и assets
- camera zoom policy, zoom-driven residency contract и hysteresis
- canonical worldgen output, `world_version`, save shape, commands и events
- новый streamer, GPU arena или параллельный presentation framework

### Exit gate

В непрерывной F4-записи отсутствуют black/empty terrain chunks, seams и terrain
pop. Проверка выполняется во время движения и сразу после остановки, без
ожидания catch-up.

Автоматический candidate probe на
`mountain_runtime_dig_dev_scene.tscn` после S3 handoff двигает игрока на юг со
скоростью `320 px/s` при максимальном zoom-out и на каждом кадре проверяет, что
весь visible terrain envelope уже materialized, terrain cells committed, а
применимые mountain/shore masks готовы без catch-up. Поскольку S3 уже принят
пользователем, probe имеет явно логируемый terrain-only handoff для известной
headless-задержки object staging; он разрешается только после полной готовности
всех S4 terrain/mask targets и не меняет runtime/UI gate. F4-видео и визуальная
оценка seams/pop остаются ручной приемкой пользователя.

## S5 — Zoom-independent residency и hysteresis

### Цель

Рассчитывать resident/prepared envelope по максимальному zoom-out и обеспечить
выгрузку только по distance+hysteresis, а не по текущей камере.

### Exit gate

Повторные zoom-in/zoom-out во время движения и стоянки не увеличивают generation
requests, не пересоздают чанки и не вызывают visible pop. Working set остается
bounded после длинного пути и возврата.

## S6 — Бесшовные деревья, камни и декор

### Цель

Подключать object families по одной через существующий packet/batch путь и
готовить их до входа чанка в viewport.

### Порядок

1. Деревья и их collision/shadow contract.
2. Камни.
3. Живая/статическая flora и остальной текущий decor.

### Exit gate

На фиксированном маршруте и максимальном zoom-out отсутствуют missing objects,
late reveal и повторный upload после короткого возврата. Visual identity
совпадает с S1 reference screenshots.

## S7 — Трава, тени, пещеры и lighting parity

### Цель

Включить все оставшиеся presentation layers в readiness/performance contract,
не меняя gameplay meaning света и темноты.

### Обязательные проверки

- grass and ground overlays
- projected/contact shadows
- mountain/cavity/skylight masks
- surface day/night
- cave darkness
- player torch в пещере и на поверхности
- weather/cloud/postprocess
- mining visual update

### Exit gate

Пользователь подтверждает visual parity по эталонным кадрам и отсутствие
регрессий факела, копания, коллизий и environment behavior.

## S8 — 60 FPS, bounded memory и scale proof

### Цель

Оптимизировать только измеренные bottlenecks после достижения корректности.

### Правила

- одна performance hypothesis за раз
- before/after capture на одном маршруте
- average FPS не заменяет P95/P99/max и visual acceptance
- resident data может быть больше visible render set; render cost обязан быть
  bounded
- 10x content-density probe не должен менять complexity class interactive path
- рост числа биомов должен идти через общий data/packet/batch contract, а не
  через новые per-biome hot paths

### Exit gate

Profile/release build на утвержденной S1 target configuration держит принятый
60 FPS frame-time contract, не имеет streaming-caused hitch, остается в
утвержденном RAM/VRAM envelope и проходит полный visual/gameplay маршрут.

## Общий приемочный маршрут

Точные значения фиксируются в S1. До этого обязательна следующая форма:

1. Запуск обычной игры через main menu, а не только dev scene.
2. Cold start с фиксированным seed.
3. Screenshot первого игрового кадра на максимальном zoom-out.
4. Непрерывная F4-запись до начала движения.
5. Длинный пробег на максимальной обычной скорости без teleport.
6. Контрольные screenshots во время движения через фиксированные интервалы.
7. Screenshot сразу после дальней остановки, без ожидания загрузки.
8. Zoom sweep во время движения и после остановки.
9. Возврат по пройденному пути.
10. Dense-object area, mountain edge, excavation/cave и torch.
11. Отдельный `mountain_runtime_dig_dev_scene.tscn` run как mountain stress и
    functional probe; его startup teleport не смешивается с steady-state
    ordinary-walk numbers.

Один финальный screenshot не является достаточным: остановка может скрыть
streaming deficit. Непрерывный trace и промежуточные screenshots обязательны.

## Performance contract — поля S1

| Поле | Значение |
|---|---|
| Target GPU/CPU | TBD in S1 |
| Resolution / renderer | TBD in S1 |
| Build type for final acceptance | profile/release, exact mode TBD in S1 |
| Allowed zoom range | TBD in S1 |
| Max ordinary player speed | TBD in S1 |
| Cold-start target | measure first, approve after S1/S3 evidence |
| Frame P95 | TBD in S1; target is 60 FPS budget |
| Frame P99 | TBD in S1 |
| Max streaming-caused frame | TBD in S1 |
| RAM/VRAM envelope | TBD in S1 |

## Доказательства и артефакты

- Raw F4 captures остаются в `user://performance_captures/`.
- В `artifacts/codex_perf/seamless_world_streaming/` хранятся только небольшие
  tracked summaries, manifests и явно выбранные reference images.
- Большие raw traces, PNG-серии и бинарные профили нельзя копировать в Git без
  прямого решения пользователя.
- Для каждого candidate closure записываются capture id/path, revision,
  configuration, route id и результат manual acceptance.

## Журнал решений

| Дата | Решение |
|---|---|
| 2026-07-22 | Провалившийся незакоммиченный эксперимент сохранен в `rescue/failed-streaming-2026-07-22` (`cf2995b`). |
| 2026-07-22 | `main` возвращен к `121331d runtie debugger`; два более поздних optimization commits остаются в rescue history. |
| 2026-07-22 | Новая попытка идет по отдельным подцелям с обязательной ручной приемкой между ними. |
| 2026-07-22 | Пользователь отказался от feature branches: Codex работает в `main`, не stage-ит и не коммитит; commit выполняет пользователь. |
| 2026-07-22 | Loading screen принят как hypothesis для honest initial readiness, но не как доказательство steady-state throughput. |
| 2026-07-22 | S2 readiness instrumentation достиг candidate_ready: автоматические проверки пройдены, S3 остается locked до ручного F4/F2-прогона и явной приемки пользователя. |
| 2026-07-23 | Пользователь принял S2 по capture `20260723_132327_539`: readiness contract прошел, причины неготовности доказаны; недобор формальных S1 route thresholds явно принят как несущественный для instrumentation-only результата. S3 разблокирован, но не начат. |
| 2026-09-05 | Пользователь явно принял ручную приемку S4 в чате. S4 отмечен accepted; S5 доступен к отдельному запуску (pending_user_start), но не начат. Следующая цель разработки обсуждается и пока не согласована. Новые runtime/performance-измерения агентом не выполнялись. |

## Как возобновить работу в новом чате

Минимальный prompt:

```text
Продолжаем docs/00_governance/SEAMLESS_WORLD_STREAMING_TASK.md.
Прочитай AGENTS.md и task brief. Выполняй только текущую подцель.
Не создавай ветки, не stage и не commit. После candidate closure остановись
для моей ручной приемки и не переходи к следующей подцели.
```

Для запуска первой подцели:

```text
/goal Выполни только S1 из
docs/00_governance/SEAMLESS_WORLD_STREAMING_TASK.md. Зафиксируй baseline и
приемочный маршрут без оптимизации игрового runtime. Не переходи к S2.
```

## Обновление tracker

При каждом переходе обновляются только:

- frontmatter `active_subgoal` и `active_subgoal_status`
- таблица `Текущий статус`
- строка соответствующей подцели в `Карта подцелей`
- поля S1/performance contract, если появились доказанные значения
- журнал решений
- ссылки на latest proof и closure report

Не переписывай весь документ при обычном обновлении статуса.
