ЗАДАЧА ДЛЯ CODEX

Нужно дожать базовую архитектуру Station Mirny без расползания в новый контент.
Работай строго по канонической документации в docs/ и не предлагай решений, которые ей противоречат.

ОБЯЗАТЕЛЬНЫЕ ПРАВИЛА НА ВСЕ ИТЕРАЦИИ

1. Перед началом КАЖДОЙ итерации обязательно перечитай:
   - docs/README.md
   - docs/00_governance/AI_PLAYBOOK.md
   - docs/00_governance/DOCUMENT_PRECEDENCE.md
   - docs/00_governance/ENGINEERING_STANDARDS.md

2. Для всех задач этой серии дополнительно обязательно перечитай:
   - docs/00_governance/PERFORMANCE_CONTRACTS.md
   - docs/00_governance/SIMULATION_AND_THREADING_MODEL.md
   - docs/04_execution/MASTER_ROADMAP.md

3. Для конкретных подзадач обязательно подключай профильные спеки:
   - room/building work:
     docs/02_system_specs/base/building_and_rooms.md
   - power/network work:
     docs/02_system_specs/base/engineering_networks.md
   - persistence boundaries:
     docs/02_system_specs/meta/save_and_persistence.md
   - localization/UI messages:
     docs/02_system_specs/meta/localization_pipeline.md

4. Все решения делай только в соответствии с документацией.
   Если код и документация расходятся:
   - сначала считай docs/ каноном
   - не угадывай
   - если нужно, сначала обнови канонический doc, потом код
   - не используй legacy markdown в корне как равноправный источник

5. Нельзя:
   - добавлять новый контент, биомы, фауну, новые gameplay loops
   - плодить параллельные системы рядом с уже существующими
   - переносить heavy world/base work в interactive path
   - хардкодить user-facing text, balance, gameplay ids
   - делать full rebuild там, где должен быть local dirty update
   - ломать save/load совместимость без явного migration note

6. На выходе каждой итерации обязательно дай:
   - что изменено
   - какие файлы изменены
   - какие docs были источником решений
   - какие архитектурные риски сняты
   - какой smoke test пройти руками

ОБЩАЯ ЦЕЛЬ СЕРИИ

Нужно довести foundation base/world loop до состояния:
- local player actions остаются дешевыми
- тяжелые последствия уходят в dirty queue / background / bounded apply
- room/building/power обновляются локально и предсказуемо
- perf-инструментация реально показывает, где тратится бюджет
- GameWorld перестает быть местом, где бесконтрольно живет половина runtime orchestration

ITERATION 0 — FOUNDATION AUDIT + WORK CONTRACT

Цель:
Сначала зафиксировать целевую архитектурную рамку, чтобы дальше не чинить наугад.

Что сделать:
1. Прочитать обязательные governance docs.
2. Сделать короткий architecture note в docs/ или ADR:
   - какие runtime work classes используются в этой серии
   - что относится к interactive work
   - что относится к background work
   - что должно быть compute/apply
   - какие операции обязаны быть local dirty updates
3. Зафиксировать список существующих hot paths:
   - building placement/removal
   - room recalculation
   - power recalculation
   - boot chunk loading
   - local terrain mutation hooks, если затрагиваются
4. Зафиксировать текущие main-thread hazards в коде.
5. Если в docs этого еще нет в нужной форме — добавить канонический execution note для этой refactor-серии.

Результат итерации:
- есть один короткий canonical plan note / ADR
- есть согласованная терминология: interactive / background / apply / dirty region / dirty network
- следующие итерации не спорят о базовых правилах

Критерий готовности:
- можно показать конкретный список операций, которые запрещено выполнять синхронно
- можно показать список систем, которые будут переведены на dirty/budget model

ITERATION 1 — RUNTIME WORK MODEL + SHARED SEAMS

Цель:
Ввести единый практический runtime contract в код, а не только в docs.

Что сделать:
1. Создать или довести до usable-state общие seam-абстракции для runtime work:
   - classification of work
   - enqueue dirty work
   - bounded per-frame processing
   - compute/apply split where relevant
2. Не изобретай “job system ради job system”.
   Используй минимальный слой, совместимый с текущими autoloads и архитектурой.
3. Привести FrameBudgetDispatcher к роли реального shared runtime mechanism, а не декоративного autoload.
4. Явно определить:
   - какие категории бюджета уже поддерживаются
   - как новые background jobs регистрируются
   - как job сообщает “есть еще работа / работа закончена”
5. Подготовить простые helper APIs, чтобы building/power могли использовать один и тот же паттерн.

Важно:
- не делай огромный framework
- не делай абстракции без первого реального потребителя
- первый реальный потребитель появится уже в следующих итерациях

Результат итерации:
- есть один shared runtime path для budgeted background work
- есть понятная точка регистрации dirty-processing jobs
- есть минимальные типы/соглашения, которые потом используют building и power

Smoke test:
- background job можно зарегистрировать, он ест бюджет по кадрам и завершается
- dispatcher логирует/метрит свою работу

ITERATION 2 — BUILDING/ROOMS: LOCAL DIRTY UPDATE

Цель:
Убрать full room recalculation из hot path build/remove/destroy/load там, где это возможно.

Что сделать:
1. Прочитать:
   - docs/02_system_specs/base/building_and_rooms.md
   - docs/00_governance/PERFORMANCE_CONTRACTS.md
   - docs/00_governance/SIMULATION_AND_THREADING_MODEL.md
2. Разделить в BuildingSystem:
   - immediate local action result
   - room/indoor dirty marking
   - deferred or bounded recalculation
3. Ввести понятие local dirty region для building mutation:
   - placement/removal/destruction не должны триггерить полный world-scale or full-grid rebuild по умолчанию
4. Indoor/room solver перевести на один из вариантов:
   - локальный пересчет затронутой области
   - staged recomputation
   - region invalidation + bounded rebuild
5. Сохранить текущий gameplay contract:
   - игрок ставит/ломает постройку сразу
   - визуальный/системный отклик приходит сразу на локальный результат
   - тяжелая вторичка дорабатывается bounded way
6. Если для load нужен более широкий rebuild:
   - классифицируй это как boot/load work, а не interactive work

Важно:
- не ломай existing command boundary
- не ломай save/load
- не теряй EventBus-события
- не уводи truth в UI

Результат итерации:
- BuildingSystem больше не зависит от полного sync recalculation после каждой локальной мутации
- indoor update живет в dirty/bounded model
- build/remove hot path остается коротким

Критерий готовности:
- place/remove wall не запускает полный пересчет всего room state синхронно
- load path отдельно классифицирован как boot-time or staged rebuild
- локальный smoke test проходит без заметного hitch

Smoke test:
- поставить стену
- снести стену
- разрушить стену через damage path
- проверить, что room/indoor state обновляется корректно
- проверить, что нет полного sync rebuild на каждый клик

ITERATION 3 — POWER/ENGINEERING: DIRTY NETWORK RECALC

Цель:
Убрать naïve full scan по всем sources/consumers как основной путь пересчета.

Что сделать:
1. Прочитать:
   - docs/02_system_specs/base/engineering_networks.md
   - docs/00_governance/PERFORMANCE_CONTRACTS.md
   - docs/00_governance/SIMULATION_AND_THREADING_MODEL.md
2. Зафиксировать network truth:
   - что является authoritative state
   - что является derived network/cache state
3. Ввести dirty network / dirty partition model:
   - при изменении building/power node отмечается только затронутая сеть или локальная компонента
4. Убрать из основного цикла зависимость от регулярного полного get_nodes_in_group scan как базовой стратегии.
5. Пересчет перевести на:
   - explicit invalidation
   - bounded recompute
   - incremental apply
6. Сохранить gameplay contract:
   - immediate local interaction возможна
   - тяжелый network recompute не должен съедать интерактивный кадр

Важно:
- не изобретай “идеальную финальную энергосеть”, если для foundation достаточно dirty partitions
- не ломай brownout/priority semantics
- если временно нужен fallback full recompute, он должен быть явно помечен как fallback/debug, а не основная архитектура

Результат итерации:
- power system опирается на dirty invalidation, а не только на full scan
- recalculation scope становится bounded
- foundation готова к дальнейшему росту инженерных сетей

Smoke test:
- поставить/снести генератор
- поставить/снести потребитель
- проверить, что пересчитывается затронутая часть сети
- проверить, что brownout semantics не сломаны

ITERATION 4 — PERF INSTRUMENTATION THAT ACTUALLY EXPLAINS THE SYSTEM

Цель:
Сделать perf layer полезным для архитектурных решений, а не только для логов.

Что сделать:
1. Прочитать:
   - docs/00_governance/PERFORMANCE_CONTRACTS.md
   - docs/00_governance/SIMULATION_AND_THREADING_MODEL.md
2. Довести связку:
   - WorldPerfProbe
   - FrameBudgetDispatcher
   - WorldPerfMonitor
   до одного согласованного perf-observability слоя.
3. Явно измерять:
   - interactive build path
   - deferred room work
   - deferred power work
   - dispatcher total
   - boot rebuild paths
4. Убедиться, что метрики отражают:
   - sync hot path cost
   - background cost
   - queue lag / backlog, если применимо
5. Если текущая категоризация логов слишком хрупкая — замени на более явную и архитектурно осмысленную.

Важно:
- не делай метрики только “по имени строк”
- instrumentation должна помогать отличать interactive spikes от background budget usage

Результат итерации:
- есть понятная картина по building/power hot paths
- можно увидеть, не съедает ли background budget слишком много
- можно подтвердить, что refactor реально улучшил архитектуру, а не только переставил код

Smoke test:
- серия place/remove действий
- серия power mutations
- сравнение sync path vs deferred path по логам/метрикам

ITERATION 5 — GAMEWORLD DECOMPOSITION OF ORCHESTRATION HOTSPOTS

Цель:
Подрезать GameWorld как god-orchestrator там, где он мешает foundation.

Что сделать:
1. Прочитать:
   - docs/00_governance/ENGINEERING_STANDARDS.md
   - docs/00_governance/SIMULATION_AND_THREADING_MODEL.md
   - docs/04_execution/MASTER_ROADMAP.md
2. Разобрать GameWorld на более узкие orchestration boundaries:
   - boot orchestration
   - runtime overlays/debug
   - spawn orchestration
   - world runtime glue
3. Не делай большой rewrite всей сцены.
   Вынеси только то, что:
   - мешает наблюдаемости
   - мешает testability
   - смешивает boot/runtime/debug/UI responsibilities
4. Особенно отдели:
   - boot sequence orchestration
   - debug-only presentation helpers
   - runtime update ownership
5. Сохрани текущий playable flow.

Важно:
- это не “переписать GameWorld с нуля”
- это cleanup only where it reduces architectural risk for runtime foundation

Результат итерации:
- GameWorld заметно тоньше
- ownership основных runtime участков понятнее
- foundation легче расширять без нового god script growth

Smoke test:
- новая игра
- загрузка сейва
- boot flow
- world scene still playable
- no regressions in UI/world startup

ITERATION 6 — SAVE/LOAD + DOC HARDENING

Цель:
Закрепить foundation и закрыть архитектурную серию корректно.

Что сделать:
1. Прочитать:
   - docs/02_system_specs/meta/save_and_persistence.md
   - docs/00_governance/AI_PLAYBOOK.md
   - docs/00_governance/ENGINEERING_STANDARDS.md
2. Проверить, что новые dirty caches / deferred queues / derived network state:
   - либо не сериализуются вообще
   - либо сериализуются только если действительно принадлежат durable truth
3. Явно разделить:
   - authoritative saved state
   - reconstructible derived state
   - transient runtime queues
4. Обновить канонические docs в docs/ по итогам серии:
   - что теперь является accepted runtime pattern для base/world loop
   - какие full rebuild paths остались только как boot/load/fallback
   - какие next risks still open
5. Если появились важные решения — оформить ADR.

Результат итерации:
- foundation закрыта не только кодом, но и документацией
- save/load contract не загрязнен transient derived state
- следующая серия задач уже не будет заново спорить о базовой архитектуре

ФИНАЛЬНЫЙ ACCEPTANCE CHECK ДЛЯ ВСЕЙ СЕРИИ

Серия считается успешной только если одновременно верно следующее:

1. Build/remove actions больше не тянут тяжелый sync rebuild в обычном hot path.
2. Room/indoor updates живут по dirty/bounded модели.
3. Power/network recalculation живет по dirty-partition или bounded invalidation модели.
4. Background work реально идет через shared dispatcher/budget path.
5. Perf instrumentation показывает разницу между interactive и background cost.
6. Save/load не сериализует transient runtime noise как durable truth.
7. GameWorld стал архитектурно чище хотя бы в критичных местах.
8. Все изменения соответствуют docs/ и сами docs/ обновлены там, где это требуется.

ФОРМАТ РАБОТЫ ПО КАЖДОЙ ИТЕРАЦИИ

Для каждой итерации работай так:
1. Сначала перечисли, какие docs ты прочитал.
2. Потом коротко напиши:
   - in scope
   - out of scope
   - architectural decisions
3. Затем внеси изменения.
4. После изменений дай:
   - список файлов
   - что именно изменилось
   - почему это соответствует docs
   - smoke tests
   - оставшиеся риски

ГЛАВНЫЙ ПРИОРИТЕТ

Не “сделать больше фич”.
А привести base/world runtime foundation в состояние,
в котором дальнейшее развитие проекта не будет строиться на скрытых full rebuilds,
god scripts и размытых thread/update boundaries.