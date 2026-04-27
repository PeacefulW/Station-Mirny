---
title: World Generation Preview Architecture
doc_type: design_proposal
status: draft
owner: engineering
source_of_truth: false
version: 0.2
last_updated: 2026-04-24
related_docs:
  - ../../README.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../05_adrs/0001-runtime-work-and-dirty-update-foundation.md
  - ../meta/system_api.md
  - ../meta/packet_schemas.md
  - ../meta/save_and_persistence.md
  - world_grid_rebuild_foundation.md
  - world_runtime.md
  - mountain_generation.md
---

# World Generation Preview Architecture

> This file is a design proposal, not source of truth.
> Before implementation, land an approved spec update or implementation brief.

## Goal

Add a live new-game preview that shows the actual worldgen result around the
start area while the player edits seed and mountain settings.

The UX target is a progressive chunk-by-chunk fill from the spawn area outward.
The engineering target is zero architectural divergence from runtime worldgen.

## Core rule

Use the same canonical chunk packet as runtime, but a different render path.

In short:

`same packet generation, separate preview renderer`

Preview must not become:
- a second generator
- a hidden gameplay world running inside the menu
- a save-producing or diff-producing path

## Existing foundations in the repo

Current code already gives the needed base:

- `scenes/ui/new_game_panel.gd` owns seed text and `MountainGenSettings`
- `core/systems/world/world_streamer.gd` already owns
  worker thread, request queue, result queue, packed settings, and `epoch`
- `WorldCore.generate_chunk_packet(...)` already generates runtime chunk packets
- `ChunkPacketV1` already carries mountain fields
- `world.json` already persists `worldgen_settings.world_bounds`,
  `worldgen_settings.foundation`, and `worldgen_settings.mountains`

Because of this, preview should consume the same packet contract instead of
inventing preview-only generation math.

## Architectural shape

Recommended split:

- `NewGamePanel`
  - UI owner only
  - emits normalized seed + settings snapshot for preview and start

- `WorldChunkPacketBackend`
  - shared request/result worker wrapper
  - accepts `seed`, `coord`, `world_version`, `settings_packed`, `epoch`
  - returns full chunk packet
  - also accepts a `spawn` request that resolves
    `WorldCore.resolve_world_foundation_spawn_tile(...)` on the worker before
    chunk staging begins
  - knows nothing about `ChunkView`, save/load, or menu UI
  - for `world_version >= 9`, receives the same bounds/foundation indices
    (`settings_packed[9..15]`) as the gameplay runtime

- `WorldPreviewController`
  - preview orchestrator
  - debounce
  - epoch bump
  - native spawn-result drain before spiral order build
  - spiral order build
  - packet cache
  - stale-result drop

- `WorldPreviewCanvas`
  - lightweight draw surface
  - draws ready preview patches by chunk coordinate
  - draws spawn marker and optional chunk grid

- `WorldPreviewPalette`
  - packet-to-image mapping
  - builds one small preview patch per chunk

- `WorldSpawnResolver`
  - authoritative start-tile seam for both runtime and preview

## What must stay true

### 1. Seed normalization must be shared

Preview must use the same seed resolution path as `Start`:
empty seed fallback, integer parse, and hashed text path must never diverge.

### 2. Packet boundary must stay the same

Do not add preview-only per-tile native calls.
Do not create a second packet format if `ChunkPacketV1` is sufficient.

### 3. Preview is transient only

Preview must never:
- write `world.json`
- write chunk diff files
- mutate `WorldDiffStore`
- emit world runtime lifecycle events as if the game already started

## Scheduling and fill order

Preview should not request the full outer radius as one monolithic pass.

If the window is about `spawn ±500 tiles`, then with `32 x 32` chunks it is
roughly `33 x 33 = 1089` chunks. That is acceptable only as progressive fill.

Use two stages:

1. fast pass
- small inner radius around spawn
- gives immediate visual feedback

2. full pass
- keeps filling outer rings afterward

Chunk order should be a deterministic square spiral around the spawn chunk.

## Render strategy

Do not render real gameplay chunks in the menu.

One preview chunk should become one lightweight patch:
- `Image`
- `ImageTexture`
- one patch per chunk
- nearest-neighbor scale

This keeps the main thread bounded:
- one packet result arrives
- one patch is built
- one patch is published
- no whole-image rebuild

The preview may be stylized.
It must be shape-true, not necessarily tileset-perfect.

## Performance guardrails

Interactive path may do only:

- slider or seed input change
- debounce reset
- epoch increment
- queue rebuild
- bounded patch publish

Forbidden on the menu hot path:

- full preview redraw on every ready chunk
- per-tile native queries
- hidden `WorldRuntimeV0` scene boot
- real `ChunkView` / `TileMapLayer` generation
- main-thread whole-world prepass

Cancellation is mandatory:
old results whose `epoch` does not match the current preview epoch are dropped.

Current V1-R1B note:
- preview spawn resolution queues one worker-side `WorldPrePass` substrate read
  or build first, then starts the existing progressive chunk preview around the
  returned spawn chunk
- this does not ship the full-world overview canvas; that remains the
  `world_foundation_v1.md` V1-R1C task

Current V1-R1C note:
- the new-game panel shows a full-world overview canvas alongside the existing
  progressive detail canvas
- `WorldPreviewController` uses the same debounce and epoch as the detail
  preview, then queues one overview request through `WorldChunkPacketBackend`
- `WorldChunkPacketBackend` calls the native `WorldCore` foundation snapshot
  / overview surface on the worker path and returns one native overview image
  for main-thread texture publication
- the default player overview uses the current `64`-tile substrate grid with
  `pixels_per_cell = 4`, roughly one overview pixel per `16 x 16` world tiles,
  without generating chunk packets for the full world
- the default native overview image renders only currently realised gameplay
  terrain classes: ground, mountain foot, and mountain wall; ocean/burning
  bands, continent/open-water masks, rivers, and lakes stay out of the default
  player overview until matching terrain exists
- mountain pixels are sampled at overview-pixel resolution through the same
  mountain elevation threshold plus hierarchical `mountain_id` cutoff used by
  `ChunkPacketV1`; `hydro_height` is only subtle neutral-ground shading in
  the default terrain overview
- `WorldFoundationPalette` keeps the current player-truthful canonical palette
  contract for the default mode and may expose raw `hydro_height` as a
  diagnostic height-map mode; future river skeleton fields remain available
  for dev/debug diagnostics but are not rendered as rivers in the default
  player overview until river rasterization exists
- `WorldOverviewCanvas` draws a single texture snapshot with X-wrap edge hints;
  it never boots `WorldRuntimeV0`, never creates `ChunkView`, and never writes
  save data
- the overview canvas also draws presentation-only navigation overlays: the
  resolved spawn marker and the current `33 x 33` detail-preview window, so the
  player can see where the lower region preview sits inside the whole world

## File scope for the first implementation task

### New files

- `core/systems/world/world_chunk_packet_backend.gd`
- `core/systems/world/world_spawn_resolver.gd`
- `core/systems/world/world_preview_palette.gd`
- `core/systems/world/world_preview_controller.gd`
- `scenes/ui/world_preview_canvas.gd`

### Modified files

- `core/systems/world/world_streamer.gd`
- `scenes/ui/new_game_panel.gd`

### Files that should stay out of scope

- save payload shape
- building and power systems
- combat systems
- z-level runtime
- mountain generation math itself, unless a separate versioned worldgen task is approved

## Acceptance criteria

- [ ] changing seed or mountain settings rebuilds preview without freezing the menu
- [ ] preview uses the same normalized seed and packed settings layout as the start path
- [ ] preview fills by chunk patches, not by hidden gameplay chunks
- [ ] preview begins from the spawn chunk and expands outward in stable spiral order
- [ ] fast pass gives early feedback; outer rings continue progressively
- [ ] stale results from old settings are never published
- [ ] preview writes nothing to save files before `Start`

## Follow-ups when code lands

If implementation introduces a new public runtime boundary, update in the same task:

- `system_api.md`
- `packet_schemas.md`
- `event_contracts.md`
- `commands.md`

Preferred MVP outcome:
no new canonical packet schema and no new global event surface are needed.
Главная мысль такая:

превью должно использовать тот же канонический worldgen, что и игра, но другой apply/render path.

Не “мини-генератор для меню”, не скриншот из реальной сцены, не отдельная упрощённая математика.
Именно тот же seed + world_version + worldgen_settings -> chunk packet, только вместо игровых ChunkView/TileMap ты рисуешь лёгкое UI-превью. Это очень хорошо ложится на твой текущий стек, потому что:

new_game_panel.gd уже живёт на копии MountainGenSettings и на старте просто эмитит seed + settings, то есть UI-шов уже есть
WorldStreamer уже умеет инициализировать новый мир из seed + settings, хранит world_version, пакует worldgen-настройки и пишет их в world.json
approved spec прямо требует детерминированный output от world_seed + world_version + worldgen_settings.mountains, плюс фиксированный 32x32 chunk contract и pure native generation через WorldCore

То есть база уже почти готова.

Как я бы сделал это архитектурно
1. Не через WorldStreamer целиком, а через общий низкоуровневый compute-backend

Сейчас в WorldStreamer уже сидят нужные кирпичи: WorldCore, worker thread, request/result queue, epoch, packed settings, sliced streaming job .
Но сам WorldStreamer тащит за собой лишнее для меню:

diff store
cavity/cover runtime
ChunkView
roof presentation
active cover state
куски игрового runtime, которые в меню не нужны

Поэтому правильно не “запускать реальный мир в меню”, а вытащить из WorldStreamer отдельный общий сервис, условно:

WorldChunkPacketWorker
или WorldChunkComputeService

Его задача одна:
по запросу seed + version + settings_packed + chunk_coord вернуть канонический ChunkPacket.

Тогда:

WorldStreamer использует его для игры
WorldPreviewGenerator использует его для экрана новой игры

Это лучший вариант, потому что логика compute будет одна, а apply-path разный.

2. В меню нужен отдельный WorldPreviewController, а не жирный new_game_panel.gd

new_game_panel.gd у тебя уже отвечает за seed, sliders, advanced settings и кнопку старта . Не надо превращать его в комбайн.

Сделай рядом отдельный контрол, например:

scenes/ui/world_preview_panel.gd
scenes/ui/world_preview_canvas.gd

Роли такие:

NewGamePanel

хранит editable settings
шлёт сигнал “параметры изменились”

WorldPreviewController

дебаунсит изменения
создаёт новый preview epoch
отменяет старые задачи
строит очередь чанков по спирали
получает готовые preview patches
отдаёт их в canvas

WorldPreviewCanvas

только рисует
chunk grid
spawn marker
optional overlays/debug modes
3. Рендер не через реальные TileMapLayer, а через лёгкие preview patches

Вот тут очень важный момент.

Для меню не надо создавать реальные игровые чанки, ChunkView, TileMapLayer, коллизии и т.д.
Это будет жирно, шумно и со временем начнёт ломать UX.

Правильнее так:

worker генерит тот же ChunkPacket
main thread превращает packet в маленький bitmap/texture patch
canvas рисует patch в нужной позиции

То есть один preview chunk = не игровой chunk view, а просто маленькая картинка.

Например:

игровой чанк = 32x32 тайла
preview chunk можно рисовать как:
32x32 px для 1 тайл = 1 px
или 16x16 px для 2 тайла = 1 px

Для меню это намного выгоднее.

И ещё плюс: chunk-by-chunk отрисовка даст именно тот факторио-вайб, который ты хочешь — карта дорисовывается квадратиками от центра наружу.

4. Спиральная очередь вокруг spawn, а не просто “все чанки разом”

Тут прям надо делать так, как ты описал:
центр -> кольца вокруг -> змейка/спираль.

Алгоритм:

Сначала вычисляешь точный spawn tile
Преобразуешь его в spawn_chunk
Строишь квадратную спираль chunk coords вокруг него
Отправляешь их в worker queue в этом порядке
Preview canvas дорисовывает патчи по мере готовности

Это даст сразу три вещи:

визуально приятно
пользователь быстро видит центр и стартовую область
не надо ждать весь радиус, чтобы получить пользу
5. Spawn в превью должен быть не “центр картинки”, а реальный spawn resolver

Это важно заложить сейчас, пока ещё не добавил реки/температуру.

Сейчас approved mountain spec уже говорит, что новый мир должен стартовать на spawn-safe patch вокруг initial player tile, чтобы первый кадр не ставил игрока в гору/крышу .
Значит превью уже должно уважать реальную логику старта, а не рисовать крестик “примерно в центре”.

Я бы сразу выделил отдельную чистую функцию:

WorldSpawnResolver.resolve(seed, version, settings) -> Vector2i

Пока она может вернуть фиксированный стартовый тайл/центр safe patch.
Позже, когда появятся реки, температура, биомы, ты просто усложнишь resolver — а превью останется тем же.

Это очень важный архитектурный шов.

Самое важное по производительности
500 тайлов радиуса — можно, но не как первый обязательный pass

Если чанк 32x32, то радиус 500 тайлов — это примерно 16 чанков в каждую сторону.
То есть примерно 33 x 33 = 1089 чанков в окне превью.

Это нормально как background progressive fill, но не как синхронный интерактивный rebuild на каждый чих ползунка.

Я бы сделал двухступенчатую схему:

Stage A — быстрый отклик

сразу после изменения параметров показываешь центр
генеришь первые 7x7 или 9x9 чанков
пользователь почти мгновенно видит “куда всё идёт”

Stage B — добивка дальнего радиуса

потом докрашиваешь внешний ring до целевого окна
хоть до ±500 тайлов, хоть дальше

И ещё одно:
пока пользователь тащит слайдер, не надо пытаться успеть дорисовать всё.
Нужны:

debounce примерно 100–150 ms
preview epoch / cancellation
отбрасывание результатов старых epoch

Иначе ты гарантированно утонешь в просроченных задачах.

Не перерисовывать всё заново на каждый чанк

Нельзя делать так:

получил 1 чанк
пересобрал всю большую texture целиком
загрузил заново весь preview image

Это будет глупо и дорого.

Лучше:

либо один texture per preview chunk
либо patch-based drawing в canvas
либо чанковая сетка маленьких ImageTexture

Для Godot-меню я бы реально выбрал чанковые текстуры.
Это просто, наглядно и хорошо подходит под “рисуется по квадратикам”.

Сохраняй packet cache отдельно от render mode

Это прям очень сильный ход на будущее.

Approved spec уже определяет, что в ChunkPacketV1 есть не только базовый terrain, но и mountain_id_per_tile, mountain_flags, mountain_atlas_indices .
Это значит:

packet можно сгенерить один раз
а потом показывать его по-разному без регена

Например режимы:

обычный красивый terrain preview
только mountains mask
mountain_id debug color
wall/foot/interior debug
spawn-safe patch overlay
позже rivers overlay
позже climate/temperature heatmap
позже biome overlay

Вот это уже будет не просто “красивый экран”, а реальный worldgen-lab.

Что я бы рекомендовал как конкретную структуру файлов

Прямо так:

core/systems/world/world_chunk_packet_worker.gd
общий compute backend, вынесенный из WorldStreamer
core/systems/world/worldgen_settings_packer.gd
один канонический pack/unpack для settings_packed
core/systems/world/world_spawn_resolver.gd
единый расчёт стартовой точки
scenes/ui/world_preview_controller.gd
дебаунс, epoch, очередь, отмена, прогресс
scenes/ui/world_preview_canvas.gd
draw чанков, spawn marker, grid, overlays
core/systems/world/world_preview_palette.gd
packet -> colors/mini-bitmap

Если делать ещё аккуратнее, WorldStreamer после этого должен перестать сам владеть низкоуровневой chunk compute логикой и просто использовать WorldChunkPacketWorker.

Как должен выглядеть pipeline

Очень коротко:

slider change
→ snapshot current settings
→ debounce
→ epoch += 1
→ spawn = WorldSpawnResolver.resolve(...)
→ build spiral chunk list around spawn
→ worker generates ChunkPacket
→ preview palette converts packet to tiny image
→ main thread applies patch
→ canvas redraw

Это и есть твой “как в игре формируется”, но без тяжёлого игрового хвоста.

Что нельзя делать

Вот это прям запрещёнка, если не хочешь потом ненавидеть систему:

Отдельная preview-математика, которая не совпадает с runtime worldgen.
Иначе превью врёт.
Инстанцировать реальный World scene в меню.
Это будет жирно и грязно.
Полностью пересобирать 500-тайловое окно синхронно на каждый шаг слайдера.
Будут лаги.
Писать preview state в save/world runtime до нажатия Start.
Preview должен быть чисто временным.
Смешивать compute и render.
У тебя проект уже идёт по compute-then-apply логике, и preview должен жить так же
Как я бы сделал MVP

Если без расползания, то порядок такой:

Вынести из WorldStreamer общий chunk worker.
Подключить WorldPreviewCanvas в new_game_panel.
Сделать preview только для surface/mountains.
Сделать spiral queue + cancellation by epoch.
Нарисовать spawn marker + chunk grid.
Добавить debug mode mountain_id и interior/wall/foot.
Потом уже расширять под rivers/climate.
