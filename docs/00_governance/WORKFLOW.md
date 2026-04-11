---
title: Workflow — Порядок работы над задачей
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 1.0
last_updated: 2026-04-11
depends_on:
  - DOCUMENT_PRECEDENCE.md
related_docs:
  - ENGINEERING_STANDARDS.md
  - PUBLIC_API.md
  - ../02_system_specs/world/DATA_CONTRACTS.md
---

# WORKFLOW — Порядок работы над любой задачей

> **Этот документ обязателен для любого агента и разработчика.**
> Нарушение порядка = откат работы.

---

## Правило #0: Документация — источник правды, не код

Агент НЕ строит понимание архитектуры из кода. Архитектура описана в документации.

Порядок чтения перед любой задачей:

1. `DATA_CONTRACTS.md` — слои данных, владельцы, инварианты
2. `PUBLIC_API.md` — какие функции вызывать, какие не трогать
3. Feature spec текущей задачи (если есть)
4. Только после этого — конкретные файлы, указанные в задаче или контракте

Если задача добавляет или меняет runtime-sensitive, loading-sensitive, streaming,
world, AI, building, flora, pathfinding, simulation, или другую потенциально
масштабируемую систему, до открытия кода также обязательно прочитай:
- `docs/00_governance/PERFORMANCE_CONTRACTS.md`
- `docs/00_governance/ENGINEERING_STANDARDS.md`

Запрещено оправдывать синхронное решение формулировками вроде
"сейчас объектов мало", "пока это только одно дерево" или
"многопоточность пока не нужна, потому что контента мало".

**Код используется ТОЛЬКО для:**
- нахождения конкретной строки, которую надо изменить
- проверки точного синтаксиса / сигнатуры функции
- выполнения acceptance tests

**Код НЕ используется для:**
- "понимания контекста" или "исследования архитектуры"
- сканирования файлов, не указанных в задаче
- поиска "а что ещё можно улучшить"
- построения собственной модели системы, отличной от описанной в контрактах

Если `DATA_CONTRACTS.md` говорит "проблема в `_is_open_exterior()`" — иди в `_is_open_exterior()` и чини. Не сканируй весь `chunk.gd` "чтобы понять контекст". Контекст — в контракте.

Если ты обнаружил в коде что-то, что противоречит `DATA_CONTRACTS.md` — **не чини это молча**. Запиши наблюдение в closure report и сообщи человеку. Контракт может быть устаревшим, а может быть правильным — решает человек, не агент.

---

## Правило #1: Не запускай параллельное исследование

Запрещено запускать explore-агентов, параллельные сканирования, или grep/search по всему проекту "для понимания". Это пустая трата токенов и источник ложных выводов.

Если задача говорит "измени файл X, функцию Y" — открой файл X, найди функцию Y, измени.

Если задача не указывает конкретный файл — посмотри в `PUBLIC_API.md` (какую функцию вызывать) и в `DATA_CONTRACTS.md` (какие файлы отвечают за слой данных).

Если ни задача, ни контракт не указывают файл — спроси человека, а не сканируй проект.

---

## Перед ЛЮБОЙ работой с кодом

1. Прочитай `DATA_CONTRACTS.md` — пойми, какие слои данных существуют, кто их владелец, какие инварианты действуют.
2. Прочитай `PUBLIC_API.md` — пойми, какие функции вызывать, какие запрещено.
3. Если задача runtime-sensitive или потенциально масштабируемая — прочитай `PERFORMANCE_CONTRACTS.md` и `ENGINEERING_STANDARDS.md`.
4. Прочитай spec текущей фичи (если есть) — пойми acceptance tests для своей итерации.
5. Определи, какие слои данных затрагивает твоя задача.
6. Для runtime-sensitive/extensible изменения зафиксируй до кода:
   - authoritative source of truth
   - single write owner
   - что является derived/cache state
   - local dirty unit
   - что остаётся в sync path, а что обязано уходить в queue/worker/native
7. Определи, какие конкретные файлы и функции указаны в задаче и контракте. Работай ТОЛЬКО с ними.

Если spec фичи не существует — **НЕ НАЧИНАЙ КОДИТЬ**. Сначала создай spec (см. "Порядок добавления новой фичи" ниже).

---

## Порядок добавления новой фичи

### Фаза A: Видение (делает человек)

Человек описывает что он хочет, в свободной форме. Это входные данные, не документ для кодера.

### Фаза B: Feature Spec (делает агент, код НЕ пишется)

Агент создаёт `docs/02_system_specs/<feature_name>.md` со следующей структурой:

```
# Feature: <название>

## Design Intent
Что фича делает для игрока. Краткое изложение видения.

## Performance / Scalability Contract
- Runtime class: (`boot`, `background`, `interactive`, или `not runtime-sensitive`)
- Target scale / density: (какой масштаб обязан выдерживать дизайн, а не только текущий sample size)
- Authoritative source of truth: (какой слой/структура является истиной)
- Write owner: (кто единственный пишет в authoritative state)
- Derived/cache state: (какие кэши/зеркала допустимы и как они инвалидируются)
- Dirty unit: (минимальная локальная единица синхронного обновления)
- Allowed synchronous work: (что разрешено сделать сразу)
- Escalation path: (что уходит в queue / worker / native cache / C++ и при каком trigger)
- Degraded mode: (что можно временно отложить или показать упрощённо)
- Forbidden shortcuts: (явно перечислить недопустимые "быстрые" решения)

## Data Contracts — новые и затронутые

### Новый слой: <название> (если фича создаёт новый слой данных)
- Что:
- Где: (конкретный файл, который будет создан)
- Владелец (WRITE): (один конкретный скрипт/система)
- Читатели (READ): (список)
- Инварианты: (assert-выражения)
- Событие после изменения: (сигнал)
- Запрещено: (что нельзя делать)

### Затронутый слой: <название из DATA_CONTRACTS.md>
- Что меняется:
- Новые инварианты (если есть):
- Кто адаптируется:
- Что НЕ меняется: (явно указать, чтобы агент-кодер не трогал лишнего)

## Required contract and API updates
- `DATA_CONTRACTS.md`: (что должно быть обновлено / `not required` с причиной)
- `PUBLIC_API.md`: (что должно быть обновлено / `not required` с причиной)
- Другие canonical docs: (если нужны)

## Iterations

### Iteration 1 — <название>
Цель: (одно предложение)

Что делается:
- (конкретный список)

Acceptance tests:
- [ ] assert(<конкретное условие>) — <пояснение>
- [ ] assert(<конкретное условие>) — <пояснение>
- [ ] <ручная проверка, если нужна> — <что именно проверить>

Файлы, которые будут затронуты:
- (список)

Файлы, которые НЕ ДОЛЖНЫ быть затронуты:
- (список, если важно)

### Iteration 2 — ...
(аналогично)
```

**Правила для spec:**
- Каждая итерация ≤ 1 день работы агента
- Acceptance tests — конкретные, проверяемые (assert или "запусти и увидишь X")
- Никаких субъективных критериев типа "should read as natural" без конкретного теста рядом
- Контракты данных пишутся ДО кода, привязаны к конкретной фиче
- Для каждой runtime-sensitive или extensible фичи spec обязан назвать target scale, source of truth, single writer, dirty unit и escalation path до кода
- "Сейчас объект один/редкий/маленький" — невалидное perf-обоснование для spec
- Если фича создаёт derived caches или mutable mirrors, spec обязан явно описать их owner и invalidation path

### Фаза C: Ревью spec (делает человек)

Человек читает spec и проверяет:
- Дизайн = то что хотел?
- Контракты не конфликтуют с DATA_CONTRACTS.md?
- Acceptance tests конкретные?
- Порядок итераций логичный?

Если spec не одобрен — кодить нельзя.

### Фаза D: Реализация (делает агент, по одной итерации)

Агент получает задачу: "Реализуй Iteration N из <feature>_spec.md"

Правила реализации:
- Перед началом — прочитай DATA_CONTRACTS.md
- Для runtime-sensitive/extensible изменений — перечитай PERFORMANCE_CONTRACTS.md и ENGINEERING_STANDARDS.md
- Делай ТОЛЬКО свою итерацию, не забегай вперёд
- Открывай ТОЛЬКО файлы, перечисленные в "Файлы, которые будут затронуты"
- Если spec не объясняет source of truth, dirty unit и escalation path, остановись и сначала уточни spec
- После завершения — проверь ВСЕ acceptance tests своей итерации
- Если acceptance test не проходит — чини, не сдавай
- НЕ оптимизируй код, который не относится к задаче
- НЕ рефакторь код, который не относится к задаче
- НЕ трогай файлы из списка "НЕ ДОЛЖНЫ быть затронуты"
- НЕ запускай explore-агентов и параллельные сканирования
- НЕ оправдывай sync/main-thread решение тем, что текущая нагрузка пока маленькая
- НЕ добавляй mutable cache/mirror без явного owner и invalidation path

## Правила валидации и acceptance tests

Цель валидации — подтвердить acceptance tests текущей итерации, а не строить временную инфраструктуру проверки.

### Три режима верификации

`статическая проверка (static verification)`
- grep, file read, parse/syntax checks, bounded review changed path и обязательный contract/API grep
- обязательна для каждой задачи
- достаточна для acceptance tests, которые полностью проверяются статически

`ручная проверка пользователем (manual human verification)`
- проверки, требующие реального Godot runtime, headless scene, визуального осмотра, play session, runtime logs или perf route
- это default path для world / visible / perf / runtime acceptance tests, если человек, task spec или acceptance test явно не поручили агенту выполнить прогон самому
- в user-facing closure report агент обязан оформить `Ручная проверка пользователем (Manual human verification)`, `Рекомендованная проверка пользователем (Suggested human check)` и явно отметить, что `явный runtime-прогон агентом (explicit agent-run runtime verification)` не выполнялся, если такой proof не был поручен

`явный runtime-прогон агентом (explicit agent-run runtime verification)`
- Godot/headless/log/harness runs, которые агент выполняет только если это явно требует человек, task spec или acceptance test
- если агент реально запустил runtime proof, он обязан сослаться на фактическую команду, harness, лог и прочитанные строки/метрики

### Видимые world / presentation changes

Если итерация меняет видимый результат мира или player-facing presentation, одной только статической проверки недостаточно, чтобы честно писать `passed` для визуального acceptance test.

К таким изменениям относятся, например:
- биомы
- реки, ridges, drainage, climate
- terrain silhouette / terrain placement
- flora / decor placement
- ecotone transitions
- любые другие изменения, которые должны быть "видны на картинке", а не только в данных

По умолчанию для таких задач агент обязан:
- закончить `static verification` по изменённым code/data paths
- подготовить `manual human verification handoff` с fixed seed, сценой/harness и точным списком того, что человеку нужно проверить вручную
- пометить визуальный acceptance test как `требуется ручная проверка пользователем (manual human verification required)`, пока нет human feedback или явно запрошенного agent-run proof

Если человек, task spec или acceptance test явно требуют, чтобы runtime/visible proof выполнил сам агент, используй sanctioned proof harness из спеки или subsystem docs (`WorldLab`, `GameWorldDebug` exporter и т.п.) и укажи реальные артефакты.

Нельзя:
- писать `passed` для визуального результата без видимого доказательства или human confirmation
- заменять proof формулировками "визуально стало лучше", "должно рисоваться правильно" или "по коду видно, что биомы теперь появляются"

### Стандартный recipe для visible world verification

Чтобы не изобретать новый механизм под каждую итерацию, для world-visible задач используется один и тот же базовый pipeline, но по умолчанию он заканчивается `manual human verification handoff`, а не автоматическим Godot run.

1. Static verification:
   - подтвердить changed truth по коду/данным/документации
   - выбрать fixed seed из спеки или предложить один reproducible seed
   - назвать рекомендуемый harness/scene (`WorldLab`, `GameWorldDebug`)
2. Manual human verification handoff:
   - для macro proof предложить `res://scenes/ui/world_lab.tscn` с fixed seed и нужными слоями (`Terrain`, `Biome`, `Drainage`, `Ridges`, `Climate`, `Ecotone`)
   - для runtime consumer proof, если это важно, предложить `res://scenes/world/game_world.tscn` с существующим `GameWorldDebug` preview/export path (`F6`, `F7`, `F8`)
   - в closure report указать seed, harness/scene и конкретный `Suggested human check`
3. Explicit agent-run runtime verification:
   - только по явному запросу использовать существующий exporter/driver, а не придумывать новый proof tool
   - если proof реально был снят, сохранять артефакты в репозиторий или в agreed debug export path внутри проекта
4. Artifact path:
   - если runtime proof реально запускался, сохранять proof в `debug_exports/world_previews/`, если subsystem spec не требует другой путь
5. Closure report:
   - если runtime proof был запущен, указать seed, harness и пути к PNG/screenshot artifacts
   - иначе написать, что `явный runtime-прогон агентом (explicit agent-run runtime verification)` не выполнялся в этой задаче по policy, и указать `Ручная проверка пользователем (Manual human verification)` и `Рекомендованная проверка пользователем (Suggested human check): ...`

### Правило расширения harness

Если человек или spec явно поручили агенту runtime proof, и существующие `WorldLab` или `GameWorldDebug` уже близки к нужной проверке:
- расширяй их
- добавляй новый mode / export layer / stat line
- переиспользуй `debug_exports/world_previews/`

Без явного поручения на agent-run runtime verification не расширяй harness только ради того, чтобы избежать manual handoff.

### Performance / loading / streaming verification

Если задача про boot time, loading-screen drag, streaming catch-up, недогруженные чанки, runtime hitch или world traversal validation, агент не имеет права писать `passed` только по рассуждению о коде. Но по умолчанию это не означает автоматический запуск Godot/headless/log tooling.

По умолчанию для таких задач агент обязан:
- выполнить bounded `static verification` hot path, dirty unit, owner boundary и отсутствие скрытых full rebuild / loaded-world fan-out в interactive path
- подготовить `manual human verification handoff` с одним конкретным сценарием, seed/route и списком того, что человеку нужно проверить вручную
- пометить runtime/perf acceptance tests как `требуется ручная проверка пользователем (manual human verification required)`, если человек, task spec или acceptance test явно не поручили агентский runtime run

Если человек, task spec или acceptance test явно требуют agent-run runtime verification, используй approved harnesses и укажи фактически собранные доказательства.

Нельзя закрывать perf-задачу формулировками:
- "стало быстрее"
- "вроде не лагает"
- "по коду видно, что теперь incremental"
- "лог где-то был, но я его не читал"

Если задача обещает:
- более быстрый boot
- лучший first-playable
- отсутствие недогруженных чанков при route traversal
- корректный streaming/topology catch-up
- меньше hitch при интерактивном действии

то в closure report должен быть либо явный runtime proof, либо честный `manual human verification handoff`. Подменять это на `passed` запрещено.

### Стандартный recipe для performance verification

1. Static verification:
   - прочитать изменённый hot path
   - подтвердить, что sync path ограничен заявленной dirty unit
   - подтвердить отсутствие скрытого полного rebuild / loop over loaded chunks в interactive path
2. Manual human verification handoff:
   - указать один concrete scenario (`boot`, `route traversal`, `interactive action`)
   - указать reproducible fixed seed или sanctioned route preset, если они релевантны
   - указать, что именно человек должен увидеть/не увидеть, и какие log markers/metrics стоит проверить при ручном прогоне
3. Explicit agent-run runtime verification:
   - `Boot / load proof`: запускать реальную world scene через console binary только по явному запросу
   - `Runtime / streaming proof`: использовать существующий `RuntimeValidationDriver` только по явному запросу
   - `Hot-path proof`: использовать `WorldPerfProbe` / `WorldPerfMonitor` только по явному запросу
   - `Summary extraction`: прогонять `tools/perf_log_summary.gd` только если runtime proof реально был запущен и summary нужен
4. Artifact path:
   - если runtime proof реально запускался, по умолчанию сохранять perf-артефакты в `debug_exports/perf/`
   - fallback/manual log path остаётся Godot `app_userdata` logs для человека или для явно порученного runtime run
5. Closure report:
   - если runtime proof был запущен, указать seed, harness, команду, лог, summary artifact, проверенные строки/метрики и статус `ERROR` / `WARNING`
   - иначе написать, что `явный runtime-прогон агентом (explicit agent-run runtime verification)` не выполнялся в этой задаче по policy, и указать `Ручная проверка пользователем (Manual human verification)` и `Рекомендованная проверка пользователем (Suggested human check): ...`

### Разрешено
- Использовать штатные acceptance tests из spec
- Делать `static verification` для каждой задачи
- Сделать 1 простую runtime-проверку, только если она прямо названа человеком, acceptance test или task spec
- Сделать 1 простой smoke startup, только если это прямо названо человеком, acceptance test или task spec
- Возвращать задачу с `manual human verification handoff` вместо борьбы с runtime-инфраструктурой

### Запрещено без явного разрешения человека
- Автоматически запускать Godot, headless scene, `RuntimeValidationDriver`, log review или parsing только потому, что задача касается world/perf/visible path
- Создавать временные validation scripts / harnesses вне репозитория
- Делать несколько обходных запусков ради одной и той же проверки
- Эскалировать проверку, если она упёрлась в sandbox, log-path, autoload, script-mode, headless quirks или другие проблемы окружения
- Тратить основное время задачи на борьбу с инфраструктурой проверки, а не на саму итерацию

### Если acceptance test не воспроизводится статически
Агент обязан:
1. Сначала определить, относится ли он к `static verification`, `manual human verification` или `explicit agent-run runtime verification`
2. Если runtime proof явно не поручен — остановить автоматическую эскалацию запусков и перейти к manual handoff
3. Если explicit agent-run runtime verification был явно запрошен, но окружение его блокирует — зафиксировать blocker
4. Чётко указать:
   - что удалось проверить
   - что не удалось проверить
   - что остаётся на `manual human verification`
   - почему runtime proof не был запущен или почему он заблокирован
   - относится ли проблема к коду итерации или к окружению
5. Не придумывать новые обходные validation-механизмы без явного разрешения человека

### Лимит
- Без явного запроса на runtime proof: `0` обязательных agent-run runtime-проверок
- По явному запросу: не более 1 дополнительной специализированной runtime-проверки на итерацию
- По явному запросу: не более 1 smoke-проверки запуска на итерацию

Если runtime proof не был явно поручен, задача возвращается человеку с `manual human verification handoff`, а не разрастается в исследование инфраструктуры. Если runtime proof был явно поручен и всё ещё не подтверждён из-за среды, задача возвращается человеку с blocker.

### Фаза E: Проверка + обновление контрактов (после каждой итерации)

После завершения итерации:

1. Человек проверяет: работает? acceptance tests проходят?
2. Агент обновляет DATA_CONTRACTS.md:
   - Новые слои данных → добавить
   - Новые инварианты → добавить
   - Новые владельцы / читатели → добавить
   - Новые postconditions → добавить
3. Только после этого — следующая итерация

---

## Порядок исправления бага

1. Прочитай DATA_CONTRACTS.md и PUBLIC_API.md
2. Определи: какой контракт/инвариант нарушен?
3. Найди в PUBLIC_API: через какую безопасную точку входа должна проходить операция?
4. Найди в контракте: какой файл и функция отвечают за этот инвариант?
5. Открой ТОЛЬКО этот файл. Исправь ТОЛЬКО эту функцию.
5. Если нарушенный контракт НЕ описан — сначала добавь контракт в DATA_CONTRACTS.md, потом исправь код
6. После исправления — проверь ВСЕ инварианты затронутых слоёв (не только тот, который чинил)
7. Напиши closure report (формат ниже)

---

## Порядок оптимизации

1. Прочитай `DATA_CONTRACTS.md`, а для runtime-sensitive задач ещё и `PERFORMANCE_CONTRACTS.md` + `ENGINEERING_STANDARDS.md`
2. Определи: какие инварианты и owner boundaries затрагивает оптимизация?
3. Классифицируй работу: `boot`, `background`, `interactive`
4. Зафиксируй target scale / density, на котором решение обязано оставаться валидным
5. Назови authoritative source of truth, single write owner и все derived/cache layers
6. Определи local dirty unit и что именно разрешено выполнить синхронно
7. Определи escalation path: что уходит в queue / worker / native cache / C++ вместо интерактивного пути
8. Реализуй оптимизацию
9. Проверь ВСЕ инварианты затронутых слоёв и perf contract
10. Если хоть один инвариант нарушен — откати оптимизацию, она невалидна
11. Оптимизация, нарушающая контракт или живущая только на аргументе "сейчас объектов мало", не является оптимизацией

---

## Формат closure report (обязателен после каждой задачи)

Каждая завершённая задача ОБЯЗАНА заканчиваться closure report. Без closure report задача считается несданной.
Closure report является user-facing отчётом для человека.
User-facing reports are written in Russian with canonical English terms in parentheses.
Ключевые секции оформляй как `Русский текст (English term)`, а при первом упоминании важного технического термина используй формат `русский термин (english term)`, чтобы отчёт был понятен человеку без глубокого технического бэкграунда.
Если упоминается внутренний debug-name, job-name или jargon вроде `border_fix`, `stream_load`, `seam_mining_async` или `roof_restore`, рядом дай простое русское пояснение для новичка.
Например: `основной поток (main thread)`, `нативный код (native code)`, `очередь задач (queue)`, `рабочий поток (worker thread)`, `статическая проверка (static verification)`, `ручная проверка пользователем (manual human verification)`, `правка границы чанка (border_fix)`, `фоновая догрузка чанков рядом с игроком (stream_load)`.

```md
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- (что конкретно сделано, по пунктам)

### Корневая причина (Root cause)
- (для багфиксов — почему было сломано, со ссылкой на нарушение из DATA_CONTRACTS.md)

### Изменённые файлы (Files changed)
- (список файлов и что в каждом изменено, кратко)

### Проверки приёмки (Acceptance tests)
- [ ] (тест 1) — прошло (passed) / не прошло (failed) / требуется ручная проверка пользователем (manual human verification required) (метод верификации)
- [ ] (тест 2) — прошло (passed) / не прошло (failed) / требуется ручная проверка пользователем (manual human verification required) (метод верификации)

### Артефакты доказательства (Proof artifacts)
- (для видимых world / rendering / presentation изменений)
- Статическая проверка (Static verification): ...
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): Seed: ... / Harness / mode: ... / Артефакты: [пути]
- Если явный runtime-прогон агентом (explicit agent-run runtime verification) не запускался: указать это прямо и пояснить, что proof не запускался в этой задаче по policy
- Ручная проверка пользователем (Manual human verification): [требуется / не требуется]
- Рекомендованная проверка пользователем (Suggested human check): ...
- Если секция не применима — написать `не применимо (not applicable)`

### Артефакты производительности (Performance artifacts)
- (для perf / loading / streaming / hitch задач)
- Статическая проверка (Static verification): ...
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): Seed: ... / Harness / mode: ... / Команда: ... / Лог: [путь]
- Сводка (Summary): [путь] / `не применимо (not applicable)`
- Проверенные метрики / строки: ...
- `ERROR` / `WARNING`: [нет / есть, статус]
- Если явный runtime-прогон агентом (explicit agent-run runtime verification) не запускался: указать это прямо и пояснить, что proof не запускался в этой задаче по policy
- Ручная проверка пользователем (Manual human verification): [требуется / не требуется]
- Рекомендованная проверка пользователем (Suggested human check): ...
- Если секция не применима — написать `не применимо (not applicable)`

### Проверка документации контрактов и API (Contract/API documentation check) (ОБЯЗАТЕЛЬНО)

Перед написанием closure report агент ОБЯЗАН:
1. Собрать список изменённых функций, констант, сигналов
2. Запустить grep по DATA_CONTRACTS.md и PUBLIC_API.md для каждого имени
3. Проверить секцию "Required contract and API updates" в спеке (если есть)
4. Если это последняя итерация спеки — выполнить все отложенные обновления документов

Формат записи:
- Grep DATA_CONTRACTS.md для `имя_функции`: [N совпадений, строки X, Y — обновлено / актуально / 0 совпадений]
- Grep PUBLIC_API.md для `имя_функции`: [N совпадений, строки X, Y — обновлено / актуально / 0 совпадений]
- Секция "Required updates" в спеке: [есть / нет] — [выполнено / не применимо / отложено до итерации N]

ЗАПРЕЩЕНО писать "не требовалось" без результата grep. Это та же ошибка,
что и "passed" без верификации. Доказательство обязательно.

### Наблюдения вне задачи (Out-of-scope observations)
- (что заметил в коде, но НЕ стал трогать, потому что не входит в задачу)
- (если ничего — написать "нет")

### Оставшиеся блокеры (Remaining blockers)
- (что ещё нужно сделать, если задача не полностью закрыта)
- (если всё закрыто — написать "нет")

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- (какие секции обновлены — со ссылкой на grep-доказательство выше)
- (или `не требовалось (not required)` — grep подтвердил 0 совпадений)

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- (какие секции обновлены — со ссылкой на grep-доказательство выше)
- (или `не требовалось (not required)` — grep подтвердил 0 совпадений)
```

---

## Как составлять промпт для агента

Качество результата на 80% определяется качеством промпта. Плохой промпт → агент сканирует проект, выдумывает scope, оптимизирует не то. Хороший промпт → агент делает ровно то, что нужно.

### Шаблон промпта (копируй и заполняй)

```
## Обязательно прочитай перед началом
- DATA_CONTRACTS.md
- [другие релевантные документы, если есть]
- WORKFLOW.md

## Задача
[Одно-два предложения: что конкретно сделать]

## Контекст
[Почему это нужно. Какая проблема решается. Ссылка на нарушение из DATA_CONTRACTS.md, если это багфикс]

## Performance / scalability guardrails
- Runtime class: [interactive / background / boot / not runtime-sensitive]
- Target scale / density: [какой реальный масштаб обязан выдерживать дизайн]
- Source of truth + write owner: [кто хранит истину и кто один имеет право писать]
- Dirty unit: [какая минимальная локальная единица обновляется синхронно]
- Escalation path: [что уходит в queue / worker / native cache / C++]
- Why sync path stays bounded: [короткое объяснение]

## Scope — что делать
- [Конкретный пункт 1]
- [Конкретный пункт 2]
- [Конкретный пункт 3]

## Scope — чего НЕ делать
- Не оптимизировать
- Не рефакторить код за пределами задачи
- Не трогать [конкретные файлы/системы]
- Не запускать explore-агентов и параллельные сканирования
- Не оправдывать sync/main-thread решение тем, что сейчас объектов мало
- [Другие ограничения]

## Файлы, которые можно трогать
- [файл 1] — [что в нём менять]
- [файл 2] — [что в нём менять]

## Файлы, которые НЕЛЬЗЯ трогать
- [файл / система]

## Acceptance tests
- [ ] [Конкретная проверка 1]
- [ ] [Конкретная проверка 2]
- [ ] [Конкретная проверка 3]

## Формат результата
- Closure report по формату из WORKFLOW.md
- Обновить DATA_CONTRACTS.md если затронуты слои данных
```

### Правила хорошего промпта

**Конкретность важнее полноты:**
- ❌ "Почини визуал горы"
- ✅ "В `chunk.gd`, функция `_is_open_exterior()`: добавь `MINED_FLOOR` и `MOUNTAIN_ENTRANCE` в список открытых типов"

**Всегда указывай файлы:**
- ❌ "Исправь cross-chunk redraw"
- ✅ "В `ChunkManager.try_harvest_at_world()`: после mining, если тайл на краю чанка, пометь граничные тайлы соседнего чанка как dirty. Файл: `core/systems/world/chunk_manager.gd`"

**"Чего не делать" важнее чем "что делать":**
Агент по умолчанию расширяет scope. Без явных ограничений он найдёт в коде "ещё вот это надо бы починить" и потратит 70% токенов на то, о чём ты не просил. Секция "чего НЕ делать" — это забор, без которого агент разбредается.

**Для runtime-sensitive задач пиши scale guardrails явно:**
Если промпт не называет target scale, source of truth, dirty unit и escalation path, агент слишком легко скатится в решение, которое "нормально пока объектов мало", а потом разнесёт производительность при росте контента.

**Один промпт = одна задача:**
- ❌ "Почини wall atlas, neighbor normalization, cross-chunk redraw и debug paths"
- ✅ Четыре отдельных промпта, каждый с closure report между ними

Исключение: если задачи зависимые и мелкие (каждая < 30 минут работы), можно объединить, но тогда **пронумеруй порядок выполнения** и укажи "после каждого фикса проверь, что предыдущие не сломались".

**Ссылайся на контракт, не описывай проблему своими словами:**
- ❌ "Копание ломается когда копаешь на границе чанка, визуал не обновляется у соседнего чанка, надо чтобы обновлялся"
- ✅ "Нарушение #8 из DATA_CONTRACTS.md: cross-chunk mining redraw отсутствует. Исправить согласно postconditions `mine tile`."

Когда ты ссылаешься на контракт, агент получает: точный файл, точную функцию, точный инвариант, точное определение "готово". Когда ты описываешь своими словами — агент интерпретирует, и его интерпретация может не совпасть с твоей.

### Пример: как превратить "хотелку" в промпт

**Ты думаешь:** "хочу чтобы стены в горе нормально рисовались"

**Ты пишешь агенту или Claude:**
"В DATA_CONTRACTS.md нарушение #21: surface wall atlas не считает MINED_FLOOR и MOUNTAIN_ENTRANCE открытыми. Составь промпт для агента-кодера по шаблону из WORKFLOW.md."

**Claude/агент составляет готовый промпт** с файлами, функциями, acceptance tests, ограничениями.

**Ты проверяешь промпт** (30 секунд) и даёшь агенту-кодеру.

Это три шага вместо одного, но результат — агент делает ровно то, что нужно, с первого раза. А не три explore-агента по 25k токенов каждый.

---

## Чеклист "можно ли начинать кодить?"

- [ ] DATA_CONTRACTS.md прочитан?
- [ ] PUBLIC_API.md прочитан?
- [ ] Feature spec существует и одобрен?
- [ ] Acceptance tests конкретные и проверяемые?
- [ ] Понятно, какие слои данных затрагиваются?
- [ ] Для runtime-sensitive/extensible задачи названы target scale, source of truth, dirty unit и escalation path?
- [ ] Понятно, какие файлы можно трогать, а какие нет?
- [ ] Конкретные файлы и функции определены из контракта / задачи (НЕ из сканирования)?

Если хоть один пункт — нет, **кодить нельзя**.

---

## Антипаттерны (что запрещено)

- ❌ Сканировать проект "для понимания контекста" вместо чтения документации
- ❌ Запускать explore-агентов или параллельные поиски по кодовой базе
- ❌ Открывать файлы, не указанные в задаче или контракте
- ❌ Начинать кодить без spec
- ❌ Делать несколько итераций подряд без проверки каждой
- ❌ Писать субъективные acceptance criteria ("should feel natural")
- ❌ Оптимизировать попутно, "раз уж я тут"
- ❌ Рефакторить то, что не относится к текущей задаче
- ❌ Менять слой данных без обновления DATA_CONTRACTS.md
- ❌ Добавлять нового writer в слой данных без обновления DATA_CONTRACTS.md
- ❌ Оправдывать sync/main-thread путь тем, что "пока это только один объект / одно дерево / один чанк"
- ❌ Добавлять mutable cache/mirror без явного source of truth, owner и invalidation path
- ❌ Сдавать итерацию с непройденными acceptance tests
- ❌ Забегать на следующую итерацию, не закрыв текущую
- ❌ Молча чинить то, что обнаружил в коде, но что не входит в задачу
- ❌ Игнорировать DATA_CONTRACTS.md и строить своё понимание из кода
- ❌ Сдавать задачу без closure report
