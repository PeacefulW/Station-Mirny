---
title: Контракт входа для агента
doc_type: agent_entrypoint
status: approved
owner: engineering
source_of_truth: false
version: 1.4
last_updated: 2026-04-17
related_docs:
  - docs/README.md
  - docs/00_governance/WORKFLOW.md
  - docs/00_governance/ENGINEERING_STANDARDS.md
  - docs/00_governance/PROJECT_GLOSSARY.md
  - docs/02_system_specs/README.md
  - docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# AGENTS.md

Этот файл является операционной точкой входа для агентов, работающих в этом
репозитории.

Он **не** является архитектурным источником истины.
Если этот файл конфликтует с канонической документацией, следуй одобренным
документам внутри `docs/` с `source_of_truth: true`, а для навигации используй
`docs/README.md`.

## Назначение

Этот файл нужен для того, чтобы агент:
- не расширял scope без одобрения
- не сканировал большие части репозитория "для контекста"
- не превращал маленькую задачу в переписывание подсистемы
- не менял контракты или семантику молча
- не продолжал работу после того, как запрошенный шаг уже завершен

## Каноническое правило

Этот файл говорит агенту, **как работать**.
Канонические документы говорят агенту, **что является истиной**.

Используй этот файл как направляющий и маршрутизирующий слой.
Не используй его как замену approved system specs, ADR или product docs.

## Обязательный порядок чтения

### Для любой задачи
1. `AGENTS.md`
2. пользовательский промпт или task brief
3. `docs/README.md`
4. `docs/00_governance/WORKFLOW.md`
5. `docs/00_governance/ENGINEERING_STANDARDS.md`
6. `docs/00_governance/PROJECT_GLOSSARY.md`
7. релевантная approved spec или ADR для затронутой подсистемы
8. только после этого точные файлы кода, перечисленные в задаче или спеке

### Для runtime-sensitive / loading-sensitive / extensible задач

Если задача затрагивает runtime work, loading, streaming, world, simulation,
building, save/load, extension seams или иное масштабируемое поведение, перед
открытием кода также прочитай:
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- релевантные world/runtime ADR из `docs/05_adrs/`, если задача касается
  topology, wrap-world, immutable base + runtime diff, light/visibility,
  surface/subsurface или environment runtime

Для таких задач фраза "сейчас это всего один объект/один чанк" не является
допустимой причиной пропускать архитектуру, безопасную по масштабу.

## Skills

Проект использует три семейства skills:
- project-specific skills Station Mirny в `.agents/skills/`
- compatibility mirrors в `.claude/skills/`, если они вообще присутствуют
- global/system Codex skills в `$CODEX_HOME/skills/` или `~/.codex/skills/`

Правила:
- для project-specific поведения Station Mirny используй `.agents/skills/`
- не подгружай `.claude/skills/` для той же цели без явной необходимости legacy compatibility
- global/system skills допустимы только как дополнение к repo-specific правилам, а не как их замена

### Маршрутизация project skills

- `.agents/skills/mirny-task-router/SKILL.md` — широкая маршрутизация задач
- `.agents/skills/persistent-tasks/SKILL.md` — многоитерационная работа или аккуратное возобновление
- `.agents/skills/verification-before-completion/SKILL.md` — доказательное завершение
- используй релевантный domain specialist skill из `.agents/skills/` для performance, lore, UI, content, balance, localization и playtest-задач

### Общая память проекта

Shared tracker `\.claude/agent-memory/active-epic.md` больше не является
репозиторным источником истины и не должен считаться обязательным.

Если задача чувствительна к возобновлению:
- используй актуальный task brief, spec или пользовательский контекст
- обновляй task-local summary только там, где это явно согласовано задачей
- не рассчитывай на удаленные legacy memory files как на обязательную часть workflow

## World / runtime задачи

Для задач world / chunk / mining / topology / reveal / presentation обязательный
минимум — relevant ADR stack:
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- `docs/05_adrs/0002-wrap-world-is-cylindrical.md`
- `docs/05_adrs/0003-immutable-base-plus-runtime-diff.md`
- `docs/05_adrs/0005-light-is-gameplay-system.md`
- `docs/05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md`
- `docs/05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md`

Используй только те ADR, которые реально относятся к задаче.

## Непереговорные правила работы

### 1. Документация до кода

Не строй понимание архитектуры по коду.
Сначала читай governing docs, relevant specs и ADR.
Открывай код только после того, как тебе известны релевантные правила и границы.

### 2. Без широкого исследования по умолчанию

Не запускай широкие аудиты репозитория, многосессионные поисковые экспедиции по
файлам или параллельное исследование, если задача явно этого не требует.

Если задача называет spec, ADR, API surface или список файлов, оставайся в этих границах.

### 3. Одна задача, один шаг

Делай только запрошенный шаг.
Если spec говорит "Iteration 1", не реализуй Iteration 2 или 3.
Если пользователь просит bug fix, не переделывай подсистему заново.

### 4. Побеждает минимально достаточное изменение

Предпочитай самое маленькое изменение, которое удовлетворяет spec, contract и
acceptance tests.
Не вводи новый manager, service, pipeline или архитектурный слой, если задача
этого явно не требует.

Минимально достаточное изменение **не** означает "самый маленький кусок кода,
который работает при сегодняшнем крошечном количестве контента".
Это означает минимальное изменение, которое остается корректным при целевом
масштабе и не перекладывает большую будущую цену в interactive path.

### 5. Закон производительности важнее локального удобства

Для любого runtime-sensitive или extensible изменения до начала кодинга явно
определи:
- runtime work class: `boot`, `background` или `interactive`
- сценарий целевого роста, а не только текущий sample size
- authoritative source of truth и single write owner
- какие данные являются derived/cache, а какие authoritative
- локальную dirty unit, которую разрешено обновлять синхронно
- escalation path для более крупной работы: `queue`, `worker`, `native cache`,
  `C++` или другой одобренный путь

Если ты не можешь объяснить, почему sync path остается ограниченным при росте
контента, дизайн еще не готов к реализации.

### 6. Никакого тихого drift канонической документации

Если реализация меняет:
- ownership слоев
- invariants
- mutation paths
- lifecycle semantics
- safe entry points
- save/load semantics
- public read semantics
- boot/readiness semantics
- extension seams

то обнови релевантные living canonical docs в рамках той же задачи.

### 7. Остановись, когда закончил

Если запрошенный шаг завершен, acceptance tests проходят и blocker'ов не
осталось, остановись.
Не продолжай только потому, что рядом есть улучшения, рефакторинг или идеи
архитектурной чистки.

## Запрещенное поведение по умолчанию

Если задача явно этого не просит, **не**:
- чини соседние проблемы
- делай opportunistic refactor'ы
- запускай широкий повторный аудит архитектуры
- открывай или меняй файлы вне разрешенного task/spec scope
- небрежно меняй public boundaries
- реализуй будущие итерации заранее
- подменяй запрошенный шаг более крупным "идеальным" решением
- оправдывай синхронную runtime-работу фразой "сейчас экземпляров мало"
- добавляй новый mutable mirror/cache без явного authoritative owner и invalidation path

Все, что замечено вне scope, идет в:
- `Out-of-scope observations`

## Допустимая модель чтения кода

Читай только то, что нужно для завершения текущего шага:
- файлы, названные в задаче
- файлы, названные в feature spec
- файлы, названные в relevant specs / ADR

**Не** читай половину репозитория "для контекста".
Контекст должна давать документация.

## Правило spec-first

Если задача является новой фичей или структурным изменением, а утвержденной
feature spec еще нет:
- не начинай кодить
- сначала создай или уточни spec

Feature work должно реализовываться по spec, где есть:
- design intent
- затронутые canonical docs
- разрешенные файлы
- запрещенные файлы
- acceptance tests
- явные границы итераций

## Что считается blocker'ом

Считай задачу незавершенной, если выполняется хотя бы одно из условий:
- acceptance test падает
- в затронутом пути появляется crash, assert или очевидная регрессия
- нарушена документированная owner boundary
- сломан safe entry point или согласованная семантика
- save/load behavior ломается в затронутом пути
- задача требует performance-ограничения, а результат явно его нарушает
- runtime-sensitive изменение не имеет правдоподобного scale path
- введен новый mutable cache/mirror без явного source of truth и write owner

## Минимально ожидаемый результат задачи

Каждая завершенная задача должна заканчиваться user-facing closure report.
`User-facing reports are written in Russian with canonical English terms in parentheses.`

Ключевые секции оформляй как `Русский текст (English term)`, а при первом
упоминании важного технического термина используй формат
`русский термин (english term)`.

Для runtime / visual / perf acceptance tests, которые человек или spec не
поручили агенту прогонять самостоятельно, допустим честный статус
`требуется ручная проверка пользователем (manual human verification required)`
с конкретным human handoff.

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

### Проверка канонической документации (Canonical documentation check)
- Grep `<doc path>` для `<changed_name или keyword>`: [результат]
- Секция "Required updates" в spec/ADR: [есть/нет] — [статус]

### Наблюдения вне задачи (Out-of-scope observations)
- ...

### Оставшиеся блокеры (Remaining blockers)
- ...

### Обновление канонических документов (Canonical docs updated)
- `<doc path>` — updated / not required (с grep-доказательством)
```

**Правило**: `not required` без grep-доказательства = невалидный closure report.

## Практическая дисциплина промптов

Хороший implementation prompt должен задавать:
- что прочитать сначала
- точный scope задачи
- что нельзя делать
- разрешенные файлы
- запрещенные файлы
- acceptance tests
- обязательный closure report
- нужно ли обновлять relevant living canonical docs

Если этих ограничений не хватает, выбирай более узкую интерпретацию, а не более широкую.

## Финальный принцип

Задача агента не в том, чтобы улучшить все вокруг.
Задача агента в том, чтобы аккуратно завершить текущий шаг, обновить канонические
docs при необходимости и остановиться.
