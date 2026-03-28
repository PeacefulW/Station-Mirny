---
title: Temp World Public API Boundary Note
doc_type: temp_system_boundary
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-03-27
related_docs:
  - AGENTS.md
  - TASK_BRIEF.md
  - ../docs/02_system_specs/world/DATA_CONTRACTS.md
  - ../docs/00_governance/ENGINEERING_STANDARDS.md
  - ../docs/00_governance/PERFORMANCE_CONTRACTS.md
---

# WORLD_PUBLIC_API.md

Этот файл — не полный контракт мира.

Его цель проще:
- быстро показать агенту, **через какие точки входа можно работать**
- показать, **что считается owner boundary**
- показать, **куда нельзя лезть напрямую**

Если нужен полный слой инвариантов и gaps — см. `docs/02_system_specs/world/DATA_CONTRACTS.md`.

## 1. Слои и владельцы

### Canonical truth

#### World truth
- `WorldGenerator` — generated surface base для unloaded fallback
- `Chunk` — loaded chunk terrain storage
- `ChunkManager` — runtime arbitration между loaded, saved overlay и generator fallback

#### Mining truth
- canonical orchestration point: `ChunkManager.try_harvest_at_world()`
- low-level mutation helper: `Chunk.try_mine_at()`

### Derived state
- topology caches — под `ChunkManager`
- local reveal / fog derived state — под `MountainRoofSystem`, `UndergroundFogState`, `ChunkManager`

### Presentation-only state
- TileMap redraw и визуальные слои — под `Chunk`
- surface mountain shadows — под `MountainShadowSystem`

## 2. Публичные entrypoints, которые можно использовать

### Разрешённые read entrypoints

Использовать как публичные world-read API:
- `ChunkManager.get_terrain_type_at_global()`
- `ChunkManager.is_walkable_at_world()`
- `ChunkManager.has_resource_at_world()`

Правило:
- gameplay code и внешние systems читают world truth через `ChunkManager`
- не через TileMap, не через reveal state, не через topology cache

### Разрешённый mutation entrypoint

Для mining / harvest использовать как canonical mutation API:
- `ChunkManager.try_harvest_at_world()`

Если нужен command path:
- command должен входить именно в этот orchestration point, а не обходить его

## 3. Что нельзя вызывать как безопасный public API

Следующие функции/данные **не считать безопасными публичными entrypoints**:
- `Chunk.try_mine_at()` как самостоятельный gameplay entrypoint
- прямые записи в `Chunk._terrain_bytes`
- прямые записи в `Chunk._modified_tiles`
- прямые записи в `ChunkManager._saved_chunk_data`
- прямые вызовы `Chunk._redraw_*()` из gameplay logic
- чтение TileMap/cover/fog/shadow state как источника world truth

Причина:
- эти точки не гарантируют полный orchestration chain
- их использование легко ломает topology / reveal / presentation invalidation

## 4. События, на которые можно опираться

Допустимые runtime signals в этом stack:
- `EventBus.chunk_loaded`
- `EventBus.chunk_unloaded`
- `EventBus.mountain_tile_mined`
- `EventBus.z_level_changed`

Правило:
- cross-system reaction должна строиться через event path или через явный owner boundary
- не через скрытую прямую мутацию соседней подсистемы

## 5. Минимальные boundary rules

### Rule A — one authoritative mutation path

Если действие меняет canonical world state, у него должен быть один понятный orchestration point.

Для mining сейчас это:
- `HarvestTileCommand -> ChunkManager.try_harvest_at_world() -> Chunk.try_mine_at()`

### Rule B — no presentation truth

Ни один из этих слоёв не является authoritative source of truth:
- TileMap cells
- cover erase state
- fog cells
- shadow sprites

Они могут отставать визуально.
Это не делает их world truth.

### Rule C — no direct bypass of owner

Если код не является owner слоя, он не пишет в этот слой напрямую.

Пример:
- reveal code не пишет terrain truth
- presentation code не пишет mining truth
- gameplay code не пишет `Chunk` внутренности напрямую

### Rule D — local interactive work only

Interactive path должен делать только локальную работу:
- одна canonical mutation
- маленькая локальная invalidation
- enqueue/re-signal дальнейших последствий

Interactive path не должен:
- делать full rebuild всего чанка
- сканировать все loaded chunks
- превращаться в широкую cleanup-операцию

## 6. Как агент должен принимать решение перед правкой

Перед любым изменением в world stack агент обязан ответить на 5 вопросов:

1. Какой слой я трогаю: canonical, derived, presentation?
2. Кто owner этого слоя?
3. Я иду через public entrypoint или обхожу его?
4. Какой event / invalidation chain должен случиться после изменения?
5. Не делаю ли я соседний рефактор вне текущего scope?

Если на любой вопрос нет чёткого ответа — надо остановиться и свериться с `DATA_CONTRACTS.md`, а не импровизировать.

## 7. Когда этот temp-doc надо повышать в канон

Этот файл стоит переносить в `docs/` только если он реально окажется полезнее, чем текущая смесь из:
- большого `DATA_CONTRACTS.md`
- execution notes
- task-specific prompts

Критерий полезности простой:
- новый агент может быстро понять границы world stack
- и после этого не уходит в бесконечный audit/refactor loop

## 8. Краткая версия для агента

Если времени мало, запомни только это:
- читать world truth через `ChunkManager`
- писать mining truth через `ChunkManager.try_harvest_at_world()`
- не считать `Chunk.try_mine_at()` safe public API
- не использовать presentation как истину
- не чинить соседние gaps без прямого разрешения в task brief
