---
name: bugfix-prompt-smith
description: >
  Turn a vague Station Mirny bug report into a narrow, contract-aware
  implementation prompt that follows `docs/00_governance/WORKFLOW.md`. Use when
  the user says "составь промпт для фикса", "преврати это в задачу для агента",
  "оформи баг в нормальный промпт", or when a bug report is too fuzzy to safely
  implement without first tightening scope, files, acceptance tests, and doc checks.
disable-model-invocation: true
---

# Bugfix Prompt Smith

Use this skill when the next useful deliverable is a good implementation prompt,
not code yet.

This skill converts a bug symptom into the smallest valid task definition that a
Station Mirny coding agent can execute without wandering outside the contract,
API, and iteration boundaries defined by project governance.

## Read first

- `docs/00_governance/WORKFLOW.md`
- `docs/00_governance/PUBLIC_API.md`
- `docs/00_governance/AI_PLAYBOOK.md`
- the relevant contract or system spec for the affected subsystem

## What this skill does

1. Finds the contract, invariant, or safe-entrypoint framing behind the bug.
2. Narrows the request to one step, one boundary, and one acceptance-test set.
3. Produces a prompt structure that matches `WORKFLOW.md` instead of freeform
   "please fix this somehow" instructions.
4. Makes documentation and closure-report requirements explicit up front so the
   implementation agent does not improvise them later.

## Prompt shape to output

Use this structure unless the user asks for a different format:

```md
## Обязательно прочитай перед началом
- [governing docs]

## Задача
- [one concrete fix]

## Контекст
- [what is broken and which contract or symptom matters]

## Scope — что делать
- [allowed change 1]
- [allowed change 2]

## Scope — чего НЕ делать
- [explicit fences]

## Файлы, которые можно трогать
- [path] — [why]

## Файлы, которые НЕЛЬЗЯ трогать
- [path or subsystem]

## Acceptance tests
- [ ] [concrete verification]

## Формат результата
- Closure report по формату из WORKFLOW.md
- grep-check для DATA_CONTRACTS.md и PUBLIC_API.md
```

## Default workflow

1. Restate the bug as an observable failure, not a guessed fix.
2. Find the relevant contract doc and safe entry point before naming files.
3. Reduce the task to one requested step or one spec iteration.
4. Name allowed files and forbidden files explicitly.
5. Write concrete acceptance tests and documentation-check requirements that the
   implementation agent can actually verify.
6. If key facts are missing, surface the blocker instead of fabricating scope.

## Typical smells

- the prompt says "fix the subsystem" instead of naming one bug
- no file boundaries are given, so the next agent will scan the repo
- acceptance tests are subjective or impossible to verify
- documentation updates are omitted even though contracts or APIs may drift
- the requested "fix" is really a feature or redesign and needs a spec first

## Compose with other skills

- Load the domain specialist for the affected area, such as
  `world-perf-doctor`, `loading-lag-hunter`, `save-load-regression-guard`,
  `ui-experience-composer`, or `content-pipeline-author`.
- Load `playtest-triage` when the bug prompt must be extracted from noisy player
  notes or a mixed feedback bundle.

## Boundaries

- Do not use this as a license to implement the fix before the prompt is agreed.
- Do not widen a bugfix prompt into a refactor or future-iteration roadmap.
- Do not skip `WORKFLOW.md` structure just because the bug sounds obvious.
