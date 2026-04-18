---
title: Workflow — Порядок работы над задачей
doc_type: governance
status: approved
owner: engineering
source_of_truth: true
version: 1.1
last_updated: 2026-04-17
related_docs:
  - ENGINEERING_STANDARDS.md
  - PROJECT_GLOSSARY.md
  - ../README.md
  - ../02_system_specs/README.md
  - ../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
---

# WORKFLOW — Порядок работы над любой задачей

> Этот документ обязателен для любого агента и разработчика.
> Нарушение порядка = работа считается недисциплинированной.

## Правило #0: документация — источник правды, не код

Агент не строит понимание архитектуры по коду.
Сначала читаются living canonical docs, потом открывается код.

### Базовый порядок чтения

1. `AGENTS.md`
2. пользовательский промпт или task brief
3. `docs/README.md`
4. `docs/00_governance/WORKFLOW.md`
5. `docs/00_governance/ENGINEERING_STANDARDS.md`
6. `docs/00_governance/PROJECT_GLOSSARY.md`
7. relevant approved spec или ADR
8. только после этого — конкретные файлы кода из задачи

### Дополнительное чтение для runtime-sensitive задач

Если задача затрагивает runtime, loading, streaming, save/load, world,
simulation или другое масштабируемое поведение, до кода также прочитай:
- `docs/05_adrs/0001-runtime-work-and-dirty-update-foundation.md`
- relevant ADR из world/runtime стека, если он реально относится к задаче

## Правило #1: не запускай широкое исследование по умолчанию

Запрещено сканировать репозиторий "для понимания контекста", если задача уже
называет spec, ADR, subsystem surface или список файлов.

Если задача не указывает файл:
- найди relevant spec/ADR
- определи owner boundary и safe path из живых canonical docs
- только потом открывай минимально достаточный код

Если ни задача, ни docs не позволяют локализовать файл без широкого сканирования,
остановись и уточни задачу у человека.

## Перед любой работой с кодом

1. Прочитай relevant docs и зафиксируй:
   - authoritative source of truth
   - single write owner
   - derived/cache state
   - dirty unit
   - runtime work class: `boot`, `background`, `interactive`
2. Прочитай spec текущей фичи или bug brief, если он существует.
3. Определи разрешенные файлы и запрещенные файлы.
4. Только потом открывай код.

Если approved feature spec не существует для новой фичи или структурного
изменения — кодить нельзя. Сначала создается spec.

## Правила реализации

### 1. Одна задача, один шаг

Не делай будущие итерации заранее.
Не превращай bug fix в refactor всей подсистемы.

### 2. Минимально достаточное изменение

Предпочитай самое маленькое изменение, которое:
- удовлетворяет spec
- сохраняет owner boundaries
- не ломает scale path
- закрывает acceptance tests

### 3. Закон производительности

Для runtime-sensitive и extensible изменений заранее определи:
- target scale / density
- почему sync path остается ограниченным
- что обязано уйти в queue / worker / native path

Фраза "пока объектов мало" никогда не считается допустимым perf-обоснованием.

### 4. Никакого тихого drift документации

Если изменились:
- ownership
- invariants
- mutation paths
- lifecycle semantics
- save/load semantics
- safe entry points
- public read semantics
- extension seams

то relevant canonical docs обновляются в рамках этой же задачи.

## Допустимая модель чтения кода

Читай только то, что нужно для текущего шага:
- файлы, названные в задаче
- файлы, названные в spec
- файлы, названные или логически выведенные из relevant spec / ADR

Не открывай половину репозитория "на всякий случай".

## Acceptance tests и верификация

### Главный принцип

`passed` можно писать только после реального verification command в этой сессии.

Подходящие способы:
- grep/search
- file read final state
- parse/syntax/static check
- validation script
- explicit runtime run, если он был явно поручен

Что не считается доказательством:
- "логика выглядит правильной"
- пересказ собственного diff без команды
- память о прошлой сессии

### Режимы верификации

1. `статическая проверка (static verification)`
   - обязательна для каждой задачи
2. `ручная проверка пользователем (manual human verification)`
   - честный default для visual/runtime/perf результатов без явного поручения на runtime run
3. `явный runtime-прогон агентом (explicit agent-run runtime verification)`
   - только если это явно требуется задачей, человеком или acceptance test

## Closure report

Каждая завершенная задача заканчивается user-facing closure report на русском
языке с canonical English terms в скобках.

Используй этот формат:

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
- Grep `<doc path>` для `<changed_name или keyword>`: [N совпадений, строки X, Y — updated / still accurate / 0 matches]
- Секция "Required updates" в spec/ADR: [есть / нет] — [выполнено / не применимо / отложено]

### Наблюдения вне задачи (Out-of-scope observations)
- ...

### Оставшиеся блокеры (Remaining blockers)
- ...

### Обновление канонических документов (Canonical docs updated)
- `<doc path>` — updated / not required (с grep-доказательством)
```

`not required` без grep-доказательства запрещено.

## Порядок исправления бага

1. Прочитай relevant spec/ADR и определи, какой invariant или safe path нарушен.
2. Найди минимальный owner-boundary файл, который отвечает за проблему.
3. Исправь только текущий шаг.
4. Запусти acceptance checks.
5. Обнови relevant canonical docs, если изменилась документированная семантика.
6. Напиши closure report.

## Порядок оптимизации

1. Прочитай relevant spec/ADR и ADR-0001.
2. Классифицируй работу: `boot`, `background`, `interactive`.
3. Зафиксируй target scale, dirty unit и escalation path.
4. Докажи, что hot path остается ограниченным.
5. Не подменяй отсутствие архитектурной границы профайлерным "сейчас быстро".

## Порядок подготовки implementation prompt

Хороший prompt должен содержать:
- что прочитать сначала
- что именно сделать
- чего не делать
- разрешенные файлы
- запрещенные файлы
- acceptance tests
- требование closure report
- требование doc-check для relevant canonical docs

Шаблон:

```md
## Обязательно прочитай перед началом
- [governing docs]

## Задача
- [один конкретный шаг]

## Контекст
- [какая проблема решается]

## Performance / scalability guardrails
- Runtime class: [...]
- Target scale / density: [...]
- Source of truth + write owner: [...]
- Dirty unit: [...]
- Escalation path: [...]

## Scope — что делать
- [...]

## Scope — чего НЕ делать
- [...]

## Файлы, которые можно трогать
- [...]

## Файлы, которые НЕЛЬЗЯ трогать
- [...]

## Acceptance tests
- [ ] [...]

## Формат результата
- Closure report по формату из WORKFLOW.md
- Проверить и обновить relevant canonical docs при необходимости
```

## Антипаттерны

По умолчанию запрещено:
- сканировать репозиторий вместо чтения docs
- кодить без approved spec для новой фичи
- делать несколько итераций подряд без закрытия текущей
- писать субъективные acceptance criteria
- чинить соседние проблемы
- менять documented semantics без обновления docs
- писать `passed` без доказательства
- писать `not required` по документации без grep-подтверждения

## Чеклист "можно ли начинать кодить?"

- [ ] `AGENTS.md` прочитан?
- [ ] `docs/README.md` прочитан?
- [ ] `WORKFLOW.md` прочитан?
- [ ] `ENGINEERING_STANDARDS.md` и `PROJECT_GLOSSARY.md` прочитаны?
- [ ] relevant spec/ADR прочитан?
- [ ] acceptance tests конкретные и проверяемые?
- [ ] target scale / dirty unit / escalation path определены для runtime-sensitive задачи?
- [ ] разрешенные и запрещенные файлы названы?

Если хотя бы один пункт — нет, кодить нельзя.
