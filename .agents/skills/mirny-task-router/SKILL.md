---
name: mirny-task-router
description: >
  Broad routing skill for Station Mirny requests. Use when the user asks about
  Station Mirny implementation, long loading, slow boot, "долгая загрузка",
  "долго стартует", hitches, "лагает", "фризит", lore expansion, "как
  расширить лор", "переписать лор", UI polish, "сделай интерфейс красивее",
  "улучши HUD", balance, content workflows, "придумай POI", "составь промпт
  для фикса", or any broad project question where one specialist skill would
  miss adjacent needs. Use this skill to classify the request and load all
  relevant companion skills, not just one.
---

# Mirny Task Router

Use this skill as the broad Station Mirny router.

Its job is not to solve every domain itself. Its job is to decide which project
skills must be active together so the response is grounded in the right gameplay,
lore, UI, workflow, and verification context.

## Routing rules

1. Classify the request into one or more task families before answering.
2. Load every relevant companion skill, not just the first matching one.
3. Prefer multi-skill composition for mixed requests.
4. If a future specialist skill is referenced here but is not implemented yet,
   do not block. Fall back to the closest existing project skill and the
   relevant canonical docs.

## Current companion skills

Use these skills immediately when their conditions apply:

- `brainstorming`
  Use for vague feature ideas, pre-spec design discussion, "как лучше сделать",
  "хочу добавить", "давай обсудим", or any request that should stop at design
  clarification instead of coding.

- `persistent-tasks`
  Use for multi-iteration work, resumed work, "продолжи", "где мы остановились",
  "что осталось", "continue", "resume", or any task that will likely span
  multiple sessions.

- `verification-before-completion`
  Use before any closure report, before claiming a task is done, before marking
  acceptance tests as passed, and before any final implementation handoff.

## Specialist stacks to compose

Use these target stacks as the default routing map:

- Long load, boot drag, streaming hitch
  Load `loading-lag-hunter` and `frame-budget-guardian`.
  Add `save-load-regression-guard` if persistence or restore behavior is involved.

- Interactive world hitch, mining hitch, placement hitch
  Load `world-perf-doctor` and `frame-budget-guardian`.

- Lore expansion, rewrite, or deeper canon work
  Load `lore-bible-architect`.
  Add `faction-voice-keeper` or `poi-story-seeder` when the request needs a
  specific voice, archive text, ruin history, or place-based storytelling.

- UI polish, atmosphere, readability, menu/HUD feel
  Load `ui-experience-composer` and `sanctuary-contrast-guardian`.
  Add `ui-copy-tone-keeper` or `localization-pipeline-keeper` if wording,
  tooltips, menus, or player-facing text are affected.

- New content, content wiring, registry/data work
  Load `content-pipeline-author`.
  Add `balance-simulator`, `localization-pipeline-keeper`, or
  `save-load-regression-guard` when scope touches pacing, player-facing text,
  or persistence boundaries.

- Bugfix prompt shaping or task handoff
  Load `bugfix-prompt-smith`.
  Add the relevant domain specialist for the affected subsystem.

## Mixed-request rule

Do not collapse mixed requests into a single domain.

Examples:

- "Долгая загрузка и еще интерфейс кажется ватным"
  Treat as both performance and UI.

- "Хочу расширить лор и чтобы это потом ложилось в POI"
  Treat as both lore-architecture and place-based storytelling.

- "Сделай промпт для фикса лагающей загрузки"
  Treat as both bugfix-prompt shaping and performance routing.

## Boundaries

- Do not replace specialist skills with generic advice.
- Do not skip project governance just because the routing feels obvious.
- Do not force coding when the request is still in design territory.
- Do not pretend a missing future specialist skill already exists.
