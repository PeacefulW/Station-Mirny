---
title: World Rendering and Seamless Streaming — Completion Roadmap
doc_type: execution_plan
status: proposed
owner: engineering
source_of_truth: false
version: 1.1
last_updated: 2026-08-12
related_docs:
  - ../../02_system_specs/world/object_render_world.md
  - ../../02_system_specs/world/world_runtime.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# Доведение оптимизации мира до завершённой архитектуры

Этот документ — короткий план исполнения (execution plan), а не новый источник
архитектурной истины. По мере реализации каждой итерации фактические контракты
должны сразу переноситься в канонические system specs, API и packet schemas.

## Итоговая цель

На целевом профиле `1920x1080`, zoom `0.2`, Godot 4.7 и референсной GTX 1060
6 GB мир должен:

- держать 60 FPS без gameplay-кадров длиннее `16.67 ms` на максимальной
  разрешённой плотности контента;
- не показывать отсутствующие, старые или частично опубликованные чанки;
- готовить terrain, objects, shadows и collision до входа их пикселей в экран;
- сохранять текущий визуал, корректную сортировку по ногам и направление теней;
- масштабироваться на десятки видов деревьев/камней/флоры, более густой лес,
  фауну, emissive/glow и новые погодные проходы без нового renderer на каждое
  семейство;
- обновлять локальную грязную единицу (dirty unit), а не перестраивать весь
  видимый мир из-за одного чанка или одного изменения.

«60 FPS всегда» здесь означает все **незагрязнённые gameplay frames** на
референсном железе и в зафиксированном максимальном content profile. Захват
кадра, компиляция shader, внешний GPU contention и инструменты профилирования
должны помечаться отдельно и не маскировать реальные игровые просадки.

## Что уже доказано

Старый зафиксированный baseline на том же Godot 4.7 и `1920x1080`:

- average `50.561 FPS`;
- frame P95 `24.313 ms`;
- GPU P95 `23.183 ms`.

Последний честный 90-секундный проход на север с текущим renderer:

- frame P95 `8.949 ms`, P99 `9.634 ms`, max `11.608 ms`;
- `0` кадров выше `16.67 ms`;
- в кадре действительно были объекты: до 1188 деревьев, 4576 камней и
  926 кустов;
- framebuffer ablation объектов изменила 273681 пиксель.

Это подтверждает правильность общего направления: глобальный отсортированный
GPU snapshot намного дешевле per-chunk/per-stripe SceneTree. Но candidate-report
ещё не сохранён в репозитории, а текущая реализация имеет дефекты порядка,
масштаба, тестового контура и lifecycle. Поэтому результат пока нельзя считать
завершённой архитектурой.

## Непереговорные инварианты

1. Chunk остаётся единицей generation/save/streaming, но не единицей draw call.
2. Авторитетны gameplay/chunk/actor данные. GPU buffers и render pages — только
   производный кэш (derived cache) с одним владельцем записи — RenderWorld.
3. Painter order определяется ногами объекта и стабильным tie-breaker, а не
   индексом массива, порядком Node или названием семейства.
4. Игрок, враги и фауна участвуют в том же порядке, что и статические объекты.
5. Новый вид контента подключается данными (`render_class_id`, `sprite_id`,
   atlas metadata), а не новой веткой на семейство в C++ и shader.
6. Main-thread apply использует только bulk uploads и строго ограниченные фазы.
7. Обычное движение никогда не включает loading screen. Для дальнего teleport
   destination сначала предзагружается, и только затем переносится камера.
8. Проба невалидна, если она не доказала одновременно наличие terrain,
   объектов, теней и завершённой presentation.

---

## Итерация 1 — корректный общий порядок и надёжные контракты

> **Статус 2026-08-11: принято пользователем.** Реализация и обязательные
> автоматические proofs завершены; пользователь явно принял границу и открыл
> итерацию 2.

### Цель

Сделать текущий глобальный renderer визуально корректным до дальнейшего
ускорения. Устранить главный дефект: сейчас C++ возвращает абсолютный `page_y`,
а GDScript игнорирует его, назначает z по плотному индексу страницы и оставляет
игрока отдельным Sprite2D. Внутри 1024-пиксельной страницы игрок поэтому не
может корректно проходить перед и за объектами.

### Работа

- Ввести общий render-record/visual-proxy contract для статических объектов,
  игрока и будущих динамических актёров.
- Сортировать записи по `(feet_y, semantic_layer, stable_id)`; абсолютный
  `page_y` обязан участвовать в размещении, пустые Y-диапазоны не должны
  сдвигать порядок.
- Убрать отдельный body Sprite игрока после того, как его кадр, направление,
  tint и root transform публикуются тем же renderer. Gameplay Node и collision
  остаются самостоятельными.
- Не вводить переходный «разрез буфера на каждого актёра»: он не масштабируется
  на фауну и врагов.
- Явно зафиксировать порядок world shadow, mountain, player shadow, body,
  emissive и overhead; одинаковый `z_index` без проверенного tie-contract
  запрещён.
- Переписать `multimesh_instance_order_contract_test` так, чтобы он проверял не
  только порядок двух instances внутри MultiMesh, но и actor/static overlap,
  пустую render page, переход границы page и одинаковый Y.
- Мигрировать `world_streaming_queue_cache_smoke_test` на новый renderer/collision
  contract: никаких freed-object обращений, terminal poison или потерянного
  токена публикации.
- Исправить brittle mountain static test: считать все допустимые sync call sites,
  а не точное имя локальной переменной.
- Устранить teardown error `disconnect a nonexistent connection` и все RID /
  ObjectDB/resource leaks в затронутых runtime tests.

### Граница runtime work

- actor transform/frame update: `interactive`, O(visible actors), без Node scan;
- chunk render-record build: `background/native`;
- GPU publication: bounded `interactive apply`, bulk buffer upload.

### Готово, когда

- все затронутые headless contracts зелёные и Godot завершает их без engine
  errors и leaks;
- игрок корректно перекрывается одним и тем же деревом с северной и южной
  стороны на zoom `1.0` и `0.2`;
- page gaps и page crossing не меняют визуальный порядок;
- shadows относительно mountain/player имеют framebuffer regression proof;
- визуальное сравнение не показывает потерю authored pixels.

### Closure evidence (2026-08-11)

- native debug/release targets собраны; editor headless parse scan завершён без
  parse/engine errors;
- headless contracts подтверждают actor/static north/south, same-Y tie,
  абсолютную пустую page, crossing `1024 px`, уникальные pass z, очередь без
  terminal poison/потери токена, допустимые mountain sync sites и чистый
  production teardown;
- production actor runtime публикует один body и одну actor shadow, скрывает
  legacy Sprite2D только после успешного snapshot и пересекает ближайшую
  абсолютную page без дубликата;
- D3D12 framebuffer proof на NVIDIA GeForce GTX 1060 6GB подтверждает порядок
  world shadow → mountain → actor shadow → body → emissive → overhead;
- Player pixel proof на zoom `1.0` и `0.2`: `diff = 0`, `count_delta = 0`,
  `bounds_delta = 0`;
- один и тот же authored tree atlas корректно перекрывает Player севернее и
  южнее на zoom `1.0` и `0.2`; expected-composition error остаётся ниже reverse
  ordering во всех четырёх framebuffer cases;
- затронутые runtime tests завершаются без teardown disconnect, ObjectDB/RID
  leaks или resource leaks.

---

## Итерация 2 — масштабируемые render classes и удаление старого груза

> **Статус 2026-08-11: implementation complete, manual acceptance pending.**
> Итерация 3 остаётся закрытой до отдельной ручной приёмки. Все функциональные,
> визуальные, content-correctness и hard-frame-budget проверки пройдены;
> сравнительный P95 с итерацией 1 вынесен как явная оговорка ниже.

### Цель

Сделать стоимость renderer зависимой от небольшого числа реально разных
проходов, а не от количества семейств контента. Сейчас native enum и shader
жёстко знают grass/tree/rock/bush, а body shader держит 22 sampler2D. Такой путь
не переживёт десятки видов, glow и фауну.

### Работа

- Ввести data-driven RenderClassRegistry. Render class означает несовместимый
  GPU pass/material, а не «дерево» или «камень».
- Упаковать sprite layers в atlas/texture arrays и metadata tables. Instance
  выбирает `sprite_id` и descriptor; добавление нового семейства не меняет
  C++, GDScript и shader source.
- Оставить небольшой фиксированный набор проходов, например body, shadow,
  foliage/wind, emissive/glow и overhead. Новый проход допускается только для
  реально иной blend/light семантики и с измеренным бюджетом.
- Не делать один гигантский shader всё тяжелее. Дешёвые массовые записи не
  должны платить register/sampler cost самой дорогой ветки без измеренного
  выигрыша.
- Удалить dormant tall-caster полностью: nodes, MultiMeshes, material, native
  buffer, Variant payload и вводящий в заблуждение debug accounting.
- Удалить старый visual compatibility path из WorldObjectPacketLayer после
  переноса нужной collision логики в узкий collision owner.
- Разделить WorldStreamer, ChunkView, WorldObjectPacketLayer и RenderWorld по
  ответственности. 10k/5k/2.4k/923-строчные runtime scripts не являются
  устойчивой extension seam.
- Перенести grass crop scan из 614400 `Image.get_pixel()` на boot main thread в
  запечённую metadata.
- Удалить неиспользуемые instance поля; C++ sorting/packing должен резервировать
  память и не двигать тяжёлые записи там, где достаточно indices/compact atoms.
- Решить production contract compositor: при scale `1.0` либо обходить лишний
  SubViewport/blit, либо доказать, что единый pass нужен всегда. Render-time
  measurement включать только в instrumentation/debug режиме.

### Масштабный proof

Добавить synthetic content pack:

- 10 семейств статических объектов;
- минимум 10 вариантов в каждом;
- часть foliage/wind, часть emissive, часть обычных opaque/cutout;
- подключение десятого семейства только data/assets изменениями.

### Готово, когда

- число shader samplers и материалов не растёт линейно с семействами;
- draw calls ограничены render passes/pages, а не `chunks × stripes × families`;
- synthetic десятое семейство добавляется без изменений renderer source;
- dormant/legacy production resources отсутствуют;
- память GPU/CPU имеет явный hard bound для authored maximum;
- текущая сцена не становится медленнее результатов итерации 1.

### Closure evidence (2026-08-11)

- `WorldRenderClassRegistry`: 5 fixed passes, 9 production descriptors,
  4 generic static source bindings, 6 fixed materials. Sampler budgets не
  зависят от числа семейств: ground/body/shadow/emissive/overhead =
  `5/9/4/3/3`.
- Synthetic `9 -> 10` families: append-only data/assets; native выдаёт
  100 body, 100 shadow, 30 emissive и 20 overhead instances, а id десятого
  семейства отсутствует в renderer source.
- Tall-caster/height-shadow production path удалён; visual compatibility
  `WorldObjectPacketLayer` заменён узким `WorldObjectCollisionOwner` без GPU
  ресурсов. Grass crops запечены offline; compositor при scale `1.0` обходит
  auxiliary SubViewport/blit.
- Hard bounds: 1,048,576 static instances, 4,096 actors, 1,048,576 spores,
  320 MiB GPU payload, 160 MiB RenderAtom envelope, 8 MiB sort indices,
  1 GiB native snapshot working-set ceiling. Реальный `RenderAtom` = 136 bytes.
- Debug/Release native build, architecture contract, painter/shadow/queue/cache/
  teardown/actor runtime tests и D3D12 pixel contracts: PASS.
- Валидный 90 s north, GTX 1060, D3D12, 1920×1080, zoom `0.2`: 10,780 samples,
  `0` missing/hidden/stale/incomplete viewport chunks, `0` frames over
  `16.67 ms`, average `7.261 ms`, P95 `9.630 ms`, P99 `10.470 ms`, max
  `14.096 ms`, GPU P95 `9.481 ms`; object ablation = 303,689 pixels, maxima =
  1,188 trees / 4,576 rocks / 926 bushes.
- Оговорка для ручной приёмки: P95 итерации 1 был `8.949 ms`; текущий валидный
  контрольный прогон хуже на `0.681 ms` (`7.6%`). Поэтому последний критерий
  «не медленнее итерации 1» формально не закрыт, хотя hard 60 FPS gate и полный
  content-correctness gate пройдены.

---

## Итерация 3 — локальный streaming, dirty pages и предзагрузка до экрана

> **Статус: отклонена и полностью откачена 2026-08-12.** Принятой рабочей
> базой остаётся результат итераций 1–2. Описанный ниже объём сохранён только
> как исходный замысел; его прежняя реализация и точечные исправления не входят
> в текущий код.

### Цель

Убрать оставшуюся работу, которая масштабируется размером всей 165-chunk source
области. Один новый чанк, excavation patch или revision не должен пересобирать
весь global snapshot и четыре полных ground-field textures.

### Работа

- Worker/native backend выдаёт immutable ChunkRenderBlob с revision и
  contributions по render pages/classes.
- RenderWorld хранит persistent page residency. Dirty unit — один заменяемый
  chunk contribution и только затронутые pages; публикация — active/staging
  page swap после полного bulk upload.
- Один stale worker result не может удалить новую revision. Замена сохраняет
  старую видимую page до готовности новой, затем публикуется атомарно.
- Dynamic actors обновляются отдельным малым bounded buffer, не заставляя
  пересортировывать все 165 chunk blobs каждый кадр.
- Ground presentation fields получают tile/page dirty regions и halo, а не
  синхронный full-window rebuild. Существующий mountain `patch_halo_mask`
  остаётся локальным эталоном.
- Убрать линейные hot predicates вроде scan всех `_chunk_views.keys()` для
  ответа «есть ли работа»; состояние очередей ведётся счётчиками/sets владельца.
- Уменьшить 34-фазный полный upload: лимитировать не искусственным числом фаз,
  а реальными bytes/usec и количеством dirty pages в кадре.
- Demand считать от физического camera viewport, zoom и скорости. Source lead
  обязан покрывать максимальный authored overhang теней/крон плюс worst-case
  movement до следующего publish.
- Обычное движение north/east не использует loading gate. Дальний teleport
  становится двухфазной операцией: destination prefetch -> readiness proof ->
  перенос игрока/камеры одним commit.
- Очереди обязаны иметь cancellation, retry с новым состоянием и self-healing;
  exhausted request не может навечно занять bounded scan window.

### Готово, когда

- 90 секунд north и 90 секунд east: `0` viewport holes, stale revisions,
  incomplete object layers и pop frames;
- zoom `1.0 -> 0.2 -> 1.0` не создаёт дыр и не перезагружает уже готовые chunks;
- подготовленный teleport на 20 chunks показывает готовый destination первым
  отображённым кадром и укладывается в `< 3 s`;
- один chunk revision не строит и не загружает незатронутые pages/fields;
- streaming/main-thread apply P95 `<= 2 ms`, а полный frame остаётся
  `<= 16.67 ms`;
- queue stress с отменами, повторными revision и backpressure полностью
  восстанавливается без ручного события вроде F4/F12/F.

---

## Итерация 4 — GPU, визуальная и release-приёмка

### Цель

Закрыть не отдельную цифру, а всю систему доказательствами на реальном контенте
и максимальном authored scale. После этой итерации оптимизация может считаться
завершённой и разбиваться на чистые commits.

### Обязательная GPU matrix

На одном build/seed/route выполнить независимые ablations:

- world scale `1.0 / 0.75 / 0.5`;
- normal blend и alpha/blend cost;
- ground shader groups;
- direct shadows по семействам;
- body-only / shadow-only / emissive-only;
- current density / 10x static density;
- current actors / authored maximum actors;
- clear day / dense forest / storm / night torch / mountain cave.

Результат matrix определяет production scale и GPU remedies. Нельзя оставлять
full-resolution compositor «на будущее» и платить за него без решения.

### Честный acceptance harness

Каждый sampled frame обязан независимо проверить:

- физически пересекающиеся viewport chunks существуют и видимы;
- terrain revision, ChunkRenderBlob revision и GPU snapshot generation совпали;
- ожидаемые counts `<=` фактическим resident counts и они ненулевые;
- framebuffer с объектами отличается от framebuffer без объектов;
- shadows и emissive также имеют отдельную pixel-difference проверку;
- capture/observer frames исключены из frame-time выборки, но не из content
  correctness.

### Финальные thresholds

- `1920x1080`, zoom `0.2`, 90 s north + 90 s east;
- average, P95, P99 и каждый чистый frame `<= 16.67 ms`;
- `0` missing/hidden/stale/incomplete viewport chunks;
- `0` queue deadlocks и terminal poison;
- визуальная матрица: plains, dense forest, shoreline, mountain exterior,
  cave, day/night, torch on/off, storm, zoom `1.0/0.2`;
- current content, 10 families, 10x density и authored maximum actors;
- debug и release GDExtension собраны из тех же sources; release run повторяет
  correctness и не содержит engine errors/leaks;
- before/after JSON, commands, build id, adapter, screenshots и raw trace
  сохранены в `artifacts/codex_perf`;
- canonical `world_runtime.md`, family specs, `system_api.md` и
  `packet_schemas.md` описывают фактическую систему;
- dirty tree очищено от `.sconsign`, временных DLL, случайных `.obj` и
  неотобранных probe PNG. Нужные `.png.import` с mipmaps остаются tracked для
  воспроизводимости.

### Разбиение commits

Не складывать всё текущее дерево в один commit. Минимальное логичное разбиение:

1. render-order + actor contract + regression tests;
2. scalable render classes + native/shader cleanup;
3. incremental streaming/pages/fields;
4. compositor/GPU decisions + instrumentation + canonical docs + evidence;
5. отдельно — curated generated binaries, только если политика репозитория
   действительно требует их хранить.

## Когда работа останавливается

Работа завершена только после итерации 4, когда все thresholds подтверждены
сохранёнными артефактами и визуальной проверкой. Хороший average FPS, пустой мир,
маршрут через гору, короткий 10-секундный прогон или headless counters без
framebuffer proof не являются основанием остановиться.

Если итерация не проходит собственный Definition of Done, следующая не
начинается: исправление остаётся внутри текущей архитектурной границы, а не
маскируется снижением визуала, отключением объектов или дополнительным loading
screen при обычном движении.
