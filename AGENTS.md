---
title: Контракт входа для агента
doc_type: agent_entrypoint
status: approved
owner: engineering
source_of_truth: false
version: 1.3
last_updated: 2026-04-09
related_docs:
  - docs/00_governance/DOCUMENT_PRECEDENCE.md
  - docs/00_governance/WORKFLOW.md
  - docs/00_governance/PUBLIC_API.md
  - docs/02_system_specs/world/DATA_CONTRACTS.md
  - docs/00_governance/ENGINEERING_STANDARDS.md
  - docs/00_governance/PERFORMANCE_CONTRACTS.md
---

# AGENTS.md

Этот файл является операционной точкой входа для агентов, работающих в этом репозитории.

Он **не** является архитектурным источником истины.
Если этот файл конфликтует с канонической документацией, следуй:
- `docs/00_governance/DOCUMENT_PRECEDENCE.md`

## Назначение

Этот файл нужен для того, чтобы агент:
- не расширял scope без одобрения
- не сканировал большие части репозитория "для контекста"
- не превращал маленькую задачу в переписывание подсистемы
- не менял контракты или API молча
- не продолжал работу после того, как запрошенный шаг уже завершен

## Каноническое правило

Этот файл говорит агенту, **как работать**.
Канонические документы говорят агенту, **что является истиной**.

Используй этот файл как направляющий и маршрутизирующий слой.
Не используй его как замену контрактам, API, спекам или ADR.

## Обязательный порядок чтения

### Для любой задачи
1. `AGENTS.md`
2. пользовательский промпт или task brief
3. `docs/00_governance/WORKFLOW.md`
4. `docs/00_governance/PUBLIC_API.md`
5. релевантная feature spec для задачи
6. релевантный контрактный документ для затронутой подсистемы
7. только после этого точные файлы кода, перечисленные в задаче или спеке

Если задача добавляет или меняет runtime-sensitive, loading-sensitive, streaming, world,
AI, building, flora или иное расширяемое игровое поведение, то перед открытием кода также прочитай:
- `docs/00_governance/PERFORMANCE_CONTRACTS.md`
- `docs/00_governance/ENGINEERING_STANDARDS.md`

Для таких задач фраза "сейчас это всего одно дерево/чанк/объект" не является допустимой причиной пропускать архитектуру, безопасную по масштабу.

### Skills — читать до начала и перед завершением

Этот проект использует три разные группы skills:
- project-specific skills Station Mirny в `.agents/skills/`
- compatibility mirrors в `.claude/skills/`
- global/system Codex skills в `$CODEX_HOME/skills/` или `~/.codex/skills/`, если `CODEX_HOME` не задан

**Не считай все три расположения одновременно обязательными.**
Выбирай релевантный источник skills по типу задачи и используй минимально достаточный набор.

**Для project-specific поведения Station Mirny в Codex:**
- используй релевантные skills из `.agents/skills/`
- не подгружай дополнительно `.claude/skills/` для той же цели, если задача явно не связана с синхронизацией зеркала или legacy compatibility

**Для Claude или legacy compatibility поведения:**
- `.claude/skills/` остается зеркалом для инструментов, которые его все еще ожидают
- это зеркало совместимости, а не второй источник истины

**Для global/system поведения:**
- используй релевантные skills из `$CODEX_HOME/skills/` только для cross-repository workflow, которые не принадлежат пакету project-specific skills Station Mirny
- не позволяй global skill переопределять repo-specific правила из `.agents/skills/`

**Маршрутизация project skills для этого репозитория:**
- `.agents/skills/mirny-task-router/SKILL.md` — широкая маршрутизация задач Station Mirny и композиция нескольких skills
- `.agents/skills/persistent-tasks/SKILL.md` — многоитерационная работа или работа, чувствительная к возобновлению
- `.agents/skills/verification-before-completion/SKILL.md` — доказательное завершение и проверки документации
- используй релевантный domain specialist skill в `.agents/skills/` для performance, lore, UI, content, balance, localization, playtest или prompt-shaping задач

**Маршрутизация global Codex skills, если они установлены в активной среде:**
- `$CODEX_HOME/skills/spec-first-feature-work/SKILL.md` — если задача является новой feature idea или структурным изменением без утвержденной спеки
- `$CODEX_HOME/skills/world-contract-discipline/SKILL.md` — для задач world / chunk / mining / topology / reveal / presentation
- `$CODEX_HOME/skills/save-load-change-check/SKILL.md` — для задач, влияющих на save/load и persistence
- `$CODEX_HOME/skills/docs-impact-check/SKILL.md` — перед написанием closure report для любой нетривиальной правки и всегда, когда могли измениться semantics или docs

**Общая память проекта для многоитерационной работы:**
- используй `.claude/agent-memory/active-epic.md` как persistent task tracker независимо от runtime
- tracker-файл является общим состоянием проекта; это не причина загружать оба семейства skills

Если ты пропускаешь skill, который был релевантен внутри активного семейства skills для текущего runtime, closure report считается неполным.

### Для задач world / chunk / mining / topology / reveal / presentation
Обязательный контрактный документ:
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

### Для архитектурных конфликтов
Обязательный документ принятия решения:
- `docs/00_governance/DOCUMENT_PRECEDENCE.md`

## Непереговорные правила работы

### 1. Документация до кода
Не строй понимание архитектуры по коду.
Сначала читай governing docs.
Открывай код только после того, как тебе известны релевантные contract, API и spec.

### 2. Без широкого исследования по умолчанию
Не запускай широкие аудиты репозитория, многосессионные поисковые экспедиции по файлам или параллельное исследование, если задача явно этого не требует.

Если задача называет spec, contract, API surface или список файлов, оставайся в этих границах.

### 3. Одна задача, один шаг
Делай только запрошенный шаг.
Если spec говорит "Iteration 1", не реализуй Iteration 2 или 3.
Если пользователь просит bug fix, не переделывай подсистему заново.

### 4. Побеждает минимально достаточное изменение
Предпочитай самое маленькое изменение, которое удовлетворяет spec, contract и acceptance tests.
Не вводи новый manager, service, pipeline или архитектурный слой, если задача этого явно не требует.

Минимально достаточное изменение **не** означает "самый маленький кусок кода, который работает при сегодняшнем крошечном количестве контента".
Это означает минимальное изменение, которое остается корректным при целевом масштабе фичи и осознанно не перекладывает большую будущую цену в interactive path.

### 5. Закон производительности важнее локального удобства
Для любого runtime-sensitive или extensible изменения до начала кодинга явно определи:
- runtime work class: `boot`, `background` или `interactive`
- сценарий целевого роста, а не только текущий sample size
- authoritative source of truth и единственного write owner
- какие данные являются derived/cache, а какие authoritative
- локальную dirty unit, которую разрешено обновлять синхронно
- escalation path для более крупной работы: `queue`, `worker`, `native cache`, `C++` или другой утвержденный путь

Если ты не можешь объяснить, почему синхронный путь остается ограниченным при росте плотности контента, значит дизайн еще не готов к реализации.

### 6. Никакого тихого drift контракта или API
Если реализация меняет data contract, owner boundary, invariant, safe entry point или API semantics, обнови канонические docs в рамках той же задачи.

Как минимум проверь, требует ли задача обновления:
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

### 7. Остановись, когда закончил
Если запрошенный шаг завершен, acceptance tests проходят и blocker'ов не осталось, остановись.
Не продолжай только потому, что рядом есть улучшения, возможные refactor'ы или идеи архитектурной чистки.

## Запрещенное поведение по умолчанию

Если задача явно этого не просит, **не**:
- чини соседние проблемы
- делай opportunistic refactor'ы
- запускай широкий повторный аудит архитектуры
- делай perf audit только потому, что участок выглядит горячим
- открывай или меняй файлы вне разрешенного task/spec scope
- небрежно меняй public boundaries
- реализуй будущие итерации заранее
- подменяй запрошенный шаг более крупным "идеальным" решением
- оправдывай синхронную runtime-работу фразой "сейчас экземпляров все равно мало"
- добавляй новый mutable mirror/cache без явного authoritative owner и invalidation path

Все, что замечено вне scope, идет в:
- `Out-of-scope observations`

## Дисциплина контрактов и API

Перед изменением кода определи:
- какие data layers затронуты
- кто владеет правом записи в эти слои
- какие safe entry points разрешены
- меняет ли текущая задача API semantics или только детали реализации
- к какому runtime work class относится изменение
- что является authoritative source of truth, а что только derived/cache state
- какая dirty unit может исполняться синхронно
- какая работа обязана эскалироваться в queue/worker/native, а не оставаться в interactive path

Если задача меняет что-либо из следующего, обнови канонические docs до того, как считать задачу завершенной:
- ownership слоев
- invariants
- mutation paths
- lifecycle semantics
- safe entry points
- public read semantics
- boot/readiness semantics

## Допустимая модель чтения кода

Читай только то, что нужно для завершения текущего шага:
- файлы, названные в задаче
- файлы, названные в feature spec
- файлы, названные в релевантных contracts или API docs

**Не** читай половину репозитория для контекста.
Контекст должна давать документация.

## Правило spec-first для feature work

Если задача является новой фичей или структурным изменением, а утвержденной feature spec еще нет:
- не начинай кодить
- сначала создай или уточни spec

Feature work должно реализовываться по spec, в которой есть:
- design intent
- затронутые contracts
- разрешенные файлы
- запрещенные файлы
- acceptance tests
- явные границы итераций

## Что считается blocker'ом

Считай задачу незавершенной, если выполняется хотя бы одно из следующих условий:
- acceptance test падает
- в затронутом пути появляется crash, assert или очевидная регрессия
- нарушена документированная owner boundary
- сломан public contract или safe entry point
- save/load behavior ломается в затронутом пути
- задача требует performance-ограничения, а результат явно его нарушает
- runtime-sensitive изменение не имеет правдоподобного scale path за пределами сегодняшнего крошечного количества контента
- введен новый mutable cache/mirror без явного source of truth и write owner

## Что не оправдывает бесконечное продолжение работы

Это **не** является достаточной причиной продолжать после завершения запрошенного шага:
- "API могло бы быть красивее"
- "окружающий код можно было бы сделать чище"
- "рядом напрашивается еще один refactor"
- "я нашел еще один contract gap"
- "я могу представить более идеальную архитектуру"

Запиши это в out-of-scope observations и остановись.

## Минимально ожидаемый результат задачи

Каждая завершенная задача должна заканчиваться user-facing closure report.
`User-facing reports are written in Russian with canonical English terms in parentheses.`
Ключевые секции оформляй как `Русский текст (English term)`, а при первом упоминании важного технического термина используй формат `русский термин (english term)`, чтобы отчёт был понятен человеку без глубокого технического бэкграунда.
Если упоминается внутренний debug-name, job-name или jargon вроде `border_fix` или `stream_load`, рядом дай простое русское пояснение, например `правка границы чанка (border_fix)` или `фоновая догрузка чанков рядом с игроком (stream_load)`.

Для runtime / visual / perf acceptance tests, которые человек или spec не поручили агенту прогонять самостоятельно, допустим честный статус `требуется ручная проверка пользователем (manual human verification required)` / `ожидается подтверждение пользователем (pending human validation)` с конкретным human handoff по правилам `docs/00_governance/WORKFLOW.md`.
Запрещено подменять такой случай на `passed`.

Используй такую структуру:

```md
## Отчёт о выполнении (Closure Report)

### Что сделано (Implemented)
- ...

### Корневая причина (Root cause)
- ...

### Изменённые файлы (Files changed)
- ...

### Проверки приёмки (Acceptance tests)
- [ ] ... прошло (passed) / не прошло (failed) / требуется ручная проверка пользователем (manual human verification required) (метод верификации)

### Артефакты доказательства (Proof artifacts)
- Статическая проверка (Static verification): ...
- Ручная проверка пользователем (Manual human verification): [требуется / не требуется]
- Рекомендованная проверка пользователем (Suggested human check): ...

### Артефакты производительности (Performance artifacts)
- Статическая проверка (Static verification): ...
- Явный runtime-прогон агентом (Explicit agent-run runtime verification): ... / не запускался в этой задаче по policy
- Ручная проверка пользователем (Manual human verification): [требуется / не требуется]
- Рекомендованная проверка пользователем (Suggested human check): ...

### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md для `changed_name`: [результат]
- Grep PUBLIC_API.md для `changed_name`: [результат]
- Секция "Required updates" в спеке: [есть/нет] — [статус]

### Наблюдения вне задачи (Out-of-scope observations)
- ...

### Оставшиеся блокеры (Remaining blockers)
- ...

### Обновление DATA_CONTRACTS.md (DATA_CONTRACTS.md updated)
- ... / не требовалось (not required) (с grep-доказательством)

### Обновление PUBLIC_API.md (PUBLIC_API.md updated)
- ... / не требовалось (not required) (с grep-доказательством)
```

**Правило**: `not required` без grep-доказательства = невалидный closure report.
См. полный формат и процедуру в `docs/00_governance/WORKFLOW.md`.

## Практическая дисциплина промптов

Хороший implementation prompt должен задавать:
- что прочитать сначала
- точный scope задачи
- что нельзя делать
- разрешенные файлы
- запрещенные файлы
- acceptance tests
- обязательный closure report
- нужно ли обновлять `DATA_CONTRACTS.md` и `PUBLIC_API.md`

Если этих ограничений не хватает, выбирай более узкую интерпретацию, а не более широкую.

## Финальный принцип

В этом репозитории уже достаточно governance, чтобы поддерживать дисциплинированное исполнение.

Задача агента не в том, чтобы улучшить все вокруг.
Задача агента в том, чтобы аккуратно завершить текущий шаг, обновить канонические docs при необходимости и остановиться.
