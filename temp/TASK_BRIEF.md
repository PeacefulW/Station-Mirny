---
title: Temp Task Brief — World Runtime Tail Closure
doc_type: temp_task_brief
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-03-27
related_docs:
  - AGENTS.md
  - WORLD_PUBLIC_API.md
  - ../docs/02_system_specs/world/DATA_CONTRACTS.md
  - ../docs/04_execution/world_generation_gap_closure_plan.md
  - ../docs/00_governance/PERFORMANCE_CONTRACTS.md
---

# TASK_BRIEF.md

## Название шага

**Закрыть текущий runtime tail вокруг mining hot path, не открывая новый фронт worldgen-рефакторов.**

## Зачем этот шаг нужен

Сейчас по world stack одновременно открыто слишком много направлений.
Из-за этого любая правка быстро разрастается в новый аудит.

Этот brief намеренно сужает следующий шаг до одного участка:
- mining entrypoint
- seam redraw
- честность hot path

Без попытки параллельно чинить:
- readability geography
- wrap seams генератора
- biome explainability
- local variation downstream
- полную очистку всей world architecture

## In scope

Разрешено делать только следующее:

1. Проверить production path:
   - `HarvestTileCommand`
   - `ChunkManager.try_harvest_at_world()`
   - `Chunk.try_mine_at()`

2. Закрыть **локальную** проблему на пути mining, если она относится к одному из пунктов:
   - seam mining не обновляет соседний loaded chunk визуально
   - interactive path внутри `try_harvest_at_world()` нарушает заявленный контракт задачи
   - отсутствует минимальная локальная invalidation после mining на границе чанка

3. Если для проверки нужен замер, разрешено добавить **минимальную** instrumentation только вокруг затронутого hot path.

4. Если для закрытия задачи нужен минимальный contract note, разрешено обновить только `temp/WORLD_PUBLIC_API.md`.

## Out of scope

Запрещено в рамках этого шага:
- трогать ridge/river wrap continuity
- трогать readability больших структур
- переделывать resolver explainability
- переделывать local variation consumption
- переносить world truth между sampler / resolver / builder
- переписывать topology subsystem
- переписывать reveal subsystem
- делать большой cleanup `ChunkManager`
- делать новый execution plan
- обновлять канонические `docs/` ради всего мира целиком

Если по пути обнаружены эти проблемы — их надо перечислить в `Out-of-scope observations`, но не чинить.

## Allowed files

Агент может открывать и менять только эти файлы:
- `core/systems/commands/harvest_tile_command.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/world_perf_probe.gd` — только если реально нужен локальный замер
- `temp/WORLD_PUBLIC_API.md` — только если нужно уточнить boundary note после правки

## Forbidden files

Эти файлы в этой задаче трогать нельзя:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/planet_sampler.gd`
- любой файл под `data/biomes/`
- любой файл под `data/flora/`
- любой файл под `data/decor/`
- любой файл под `docs/04_execution/`, кроме чтения
- любой другой файл вне allowlist

## Acceptance checks

Задача считается закрытой только если одновременно выполнено следующее:

- [ ] Успешный mining path по-прежнему проходит через canonical orchestration point, а не через новый обходной mutation path.
- [ ] Mining на границе чанка обновляет не только исходный loaded chunk, но и затронутый соседний loaded chunk, если он уже загружен.
- [ ] В задаче не появился full chunk redraw или full loaded-world scan как часть interactive path.
- [ ] Возвращаемый gameplay result mining path не сломан.
- [ ] Surface smoke test: выкопать тайл на seam и визуально увидеть корректное обновление границы с обеих сторон.

## Stop condition

Если acceptance checks проходят, задача должна быть остановлена.

Не продолжать работу ради:
- «ещё одной маленькой оптимизации»
- «ещё одного соседнего gap»
- «перекладывания этого же кода в более красивую архитектуру»

## Expected result format

После выполнения нужен короткий отчёт:

### In scope completed
- что сделано

### Files changed
- список файлов

### Acceptance checks
- passed / failed по каждому пункту

### Out-of-scope observations
- что найдено, но специально не трогалось

### Smallest next step
- один следующий шаг, не больше

## Предпочтительный следующий шаг после закрытия этого brief

Если этот шаг закрыт чисто, следующий отдельный brief должен быть уже **другим документом** и касаться только одного из вариантов:
1. `ChunkManager.try_harvest_at_world()` perf overrun
2. `Iteration 5` truth boundary cleanup
3. `Iteration 3` structure wrap seam

Но не всех трёх сразу.
