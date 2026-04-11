---
title: In-Game Chunk Debug Overlay
doc_type: feature_spec
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-10
related_docs:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - DATA_CONTRACTS.md
  - human_readable_runtime_logging_spec.md
---

# Feature: In-Game Chunk Debug Overlay

## Design Intent

The feature adds a single in-game F11 debug overlay for the chunk-based procedural world.

The overlay is not cosmetic debug text. It is a practical runtime diagnostic tool for walking through the world and visually understanding:

- what chunk work is requested, queued, generating, building visuals, ready, visible, simulating, unloading, stalled, or errored
- where the actual load bubble around the player is
- which stage of the chunk pipeline is lagging
- which queue backlog matters to the player now and which backlog is background debt
- the recent causal sequence of world/chunk events in human-readable Russian
- the structured technical details an engineer or agent needs to debug the same incident precisely

The overlay must observe world state and diagnostic events. It must not own gameplay state, create chunk lifecycle logic, request chunks, unload chunks, or become a new authoritative world layer.

## Performance / Scalability Contract

- Runtime class: `interactive` presentation with `background` diagnostics observation.
- Target scale / density: the implementation must remain safe when the loaded bubble contains dozens of chunks and internal queues contain hundreds or thousands of pending tasks.
- Authoritative source of truth: `ChunkManager`, `Chunk`, `WorldPerfMonitor`, and `WorldRuntimeDiagnosticLog` remain the owners of the state they already own.
- Write owner: `ChunkManager` owns chunk lifecycle and queue diagnostic metadata; `WorldRuntimeDiagnosticLog` owns transient timeline buffering; `WorldPerfMonitor` owns frame/perf snapshot data; `WorldChunkDebugOverlay` owns only UI controls and draw state.
- Derived/cache state: the overlay snapshot is transient, read-only, not persisted, and rebuilt from bounded owner snapshots. Timeline ring-buffer entries are diagnostic history only and do not feed gameplay.
- Dirty unit: one diagnostic event, one queue row/group, or one chunk entry inside the bounded debug bubble.
- Allowed synchronous work: bounded snapshot assembly around the player, bounded queue sampling/grouping, bounded timeline copy, and UI string composition on a throttled cadence.
- Escalation path: heavy generation, visual building, topology, and chunk apply work stay in existing queues/workers. The overlay only reports their state.
- Degraded mode: if queues are too large, show the active top rows plus grouped hidden counts. If the bubble would be too large, clamp to the debug radius and explicitly report the clamp.
- Forbidden shortcuts: no full-world scan per frame, no gameplay mutation from overlay, no raw `print()`-only architecture, no per-frame duplicate timeline spam, no thousands of queue text rows, no private method names as the primary human UI.

## Data Contracts - New And Affected

### New layer: Chunk Debug Overlay Snapshot

- What: transient structured snapshot for the F11 overlay.
- Where: `core/systems/world/chunk_manager.gd` exposes the snapshot; `core/debug/world_chunk_debug_overlay.gd` renders it.
- Owner (WRITE): `ChunkManager` assembles chunk/queue snapshot fields from its own runtime state.
- Readers (READ): `WorldChunkDebugOverlay`.
- Invariants:
  - `assert(snapshot_is_read_only, "chunk debug overlay snapshot must not mutate chunk lifecycle")`
  - `assert(snapshot_radius_is_clamped, "chunk debug overlay snapshot must stay bounded around player")`
  - `assert(queue_rows_are_bounded_or_grouped, "chunk debug overlay queue output must not expose unbounded task walls")`
- Event after change: none; the overlay polls a throttled read snapshot.
- Forbidden: using the overlay snapshot as gameplay truth, save data, or a mutation API.

### New layer: Runtime Diagnostic Timeline Buffer

- What: transient ring buffer of structured human-readable diagnostic events.
- Where: `core/debug/world_runtime_diagnostic_log.gd`.
- Owner (WRITE): `WorldRuntimeDiagnosticLog`.
- Readers (READ): `WorldChunkDebugOverlay`, debugging/validation tools.
- Invariants:
  - `assert(event_has_human_summary_and_structured_fields, "timeline events must preserve both Russian summary and technical fields")`
  - `assert(dedupe_key_prevents_per_frame_spam, "unchanged diagnostic events must update an existing timeline entry or wait for cooldown")`
  - `assert(timeline_is_bounded, "diagnostic timeline must keep a fixed-size history")`
- Event after change: none; the buffer is diagnostic-only.
- Forbidden: treating timeline records as authoritative gameplay state.

### Affected layer: Visual Task Scheduling

- What changes: the overlay reads queue lengths, active visual tasks, recent completions, and stage ages as diagnostic metadata.
- New invariants:
  - `assert(visual_debug_reads_do_not_enqueue_work, "visual scheduler debug reads must not change scheduler state")`
  - `assert(stalled_is_diagnostic_observation, "stalled state must be presented as an observed delay, not a proven root cause unless owner evidence exists")`
- Who adapts: `ChunkManager` exposes bounded diagnostics; `WorldChunkDebugOverlay` renders them.
- What does not change: task ordering, scheduling priorities, chunk publication gates, and worker/apply boundaries.

### Affected layer: Presentation

- What changes: a new debug-only presentation node draws chunk grid, state colors, radii, queue, timeline, and metrics.
- New invariants:
  - `assert(debug_overlay_draws_existing_state_only, "debug overlay must be presentation-only")`
  - `assert(f11_toggle_does_not_change_world_state, "debug overlay visibility toggle must not affect chunk lifecycle")`
- Who adapts: `GameWorldDebug` owns the F11 input hook and creates the overlay node.
- What does not change: world rendering, chunk tilemaps, shadow systems, and existing gameplay HUD ownership.

## Required contract and API updates

- `DATA_CONTRACTS.md`: add `Chunk Debug Overlay Snapshot` and `Runtime Diagnostic Timeline Buffer`; document read-only, bounded, non-persistent invariants.
- `PUBLIC_API.md`: add read-only diagnostic entrypoints `ChunkManager.get_chunk_debug_overlay_snapshot()` and `WorldPerfMonitor.get_debug_snapshot()`.
- `DATA_CONTRACTS.md` / `PUBLIC_API.md`: document the debug-only F11 overlay log artifact at `user://debug/f11_chunk_overlay.log`; the file is derived from the overlay snapshot, overwritten on the first F11 open in a new game process, and must not become gameplay/save truth.
- Localization files: add fixed overlay chrome keys for Russian and English. Dynamic runtime diagnostic summaries remain debug-only Russian summaries produced by `WorldRuntimeDiagnosticLog`, with structured technical fields preserved under the hood.

## Iterations

### Iteration 1 - Operational F11 chunk debug overlay

Goal: ship a working in-game overlay that can be toggled with F11 and used while walking through the world to diagnose chunk pipeline state.

What is done:

- Add bounded chunk debug snapshot read API on `ChunkManager`.
- Extend `WorldRuntimeDiagnosticLog` with a structured, deduped, bounded timeline ring buffer.
- Add `WorldPerfMonitor.get_debug_snapshot()` for top HUD metrics.
- Add `WorldChunkDebugOverlay` presentation node with world grid/radii, right queue, bottom timeline, and top metrics HUD.
- Wire F11 toggle through `GameWorldDebug`.
- Add static localization keys for overlay chrome.
- Update `DATA_CONTRACTS.md` and `PUBLIC_API.md`.

Acceptance tests:

- [ ] `assert(GameWorldDebug handles KEY_F11 and toggles WorldChunkDebugOverlay)` - F11 entrypoint is wired without changing gameplay state.
- [ ] `assert(ChunkManager.get_chunk_debug_overlay_snapshot() exists and returns chunks, queue_rows, metrics, radii, player_chunk, active_z)` - snapshot contract exists.
- [ ] `assert(WorldRuntimeDiagnosticLog.get_timeline_snapshot() exists and returns bounded structured events with Russian summary and technical record)` - timeline contract exists.
- [ ] `assert(WorldPerfMonitor.get_debug_snapshot() exists and exposes fps/frame/world/chunk/visual metrics)` - perf summary contract exists.
- [ ] `assert(WorldChunkDebugOverlay draws only bounded snapshot data and does not call chunk mutation APIs)` - overlay stays read-only.
- [ ] `assert(queue output is grouped or capped and reports hidden_count)` - queue anti-spam exists.
- [ ] `assert(timeline dedupe updates repeat_count instead of appending identical entries inside cooldown)` - timeline anti-spam exists.
- [ ] Manual human verification: run `res://scenes/world/game_world.tscn`, press F11, walk across chunk borders, and confirm the overlay shows chunk grid, factual load/unload radii, chunk states, queue, timeline, and top metrics without becoming a wall of text.

Files that will be touched:

- `.claude/agent-memory/active-epic.md`
- `docs/02_system_specs/world/chunk_debug_overlay_spec.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`
- `core/debug/world_runtime_diagnostic_log.gd`
- `core/debug/world_chunk_debug_overlay.gd`
- `core/autoloads/world_perf_monitor.gd`
- `core/systems/world/chunk_manager.gd`
- `scenes/world/game_world_debug.gd`
- `locale/ru/messages.po`
- `locale/en/messages.po`

Files that must not be touched:

- gameplay content registries
- save/load formats
- chunk generation algorithms
- mining/topology/reveal mutation semantics
- worker thread compute ownership

### Iteration 2 - F11 overlay session log

Goal: write the full F11 debug summary into a `.log` file while the overlay is open, without adding new world reads or gameplay ownership.

What is done:

- Add `WorldChunkDebugOverlay` session log writing to `user://debug/f11_chunk_overlay.log`.
- Truncate the log on the first F11 open in a new game process.
- Append subsequent snapshots only while F11 overlay is visible.
- Serialize the same bounded snapshot used by the overlay: metrics, player/radii, queue rows, error/stalled summary, timeline events, and bounded chunk entries.
- Keep the file debug-only and derived from snapshot data; no save/load format change.

Acceptance tests:

- [ ] `assert(WorldChunkDebugOverlay.LOG_PATH == "user://debug/f11_chunk_overlay.log")` - log path is stable and easy to find.
- [ ] `assert(set_overlay_visible(true) opens/resets the log once per game process and set_overlay_visible(false) closes it)` - logging is tied to F11 visibility.
- [ ] `assert(_write_log_snapshot() serializes metrics, queue_rows, timeline_events, and chunks from the existing snapshot)` - no second world scan is introduced for the file.
- [ ] `assert(log writing is throttled and uses the bounded snapshot)` - file output stays debug-safe while walking.
- [ ] Manual human verification: start the game, press F11, walk across chunk borders, close F11, and confirm the file contains snapshots only for the visible interval and is overwritten after a fresh game process starts.

Files that will be touched:

- `docs/02_system_specs/world/chunk_debug_overlay_spec.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`
- `core/debug/world_chunk_debug_overlay.gd`
- `.claude/agent-memory/active-epic.md`

Files that must not be touched:

- save/load formats
- `ChunkManager` lifecycle mutation paths
- `WorldRuntimeDiagnosticLog` timeline ownership
- chunk generation algorithms

## Summary

The debug overlay is a read-only operational cockpit for chunk streaming. It shows the real working bubble around the player, pipeline state by chunk, bounded queue pressure, recent causal timeline, and concise performance metrics.

## User-visible behavior

- Pressing F11 toggles a unified debug overlay.
- The world view shows chunk grid cells, chunk coordinates, the current player chunk, factual square load/unload/visual bands, and state colors.
- The right panel shows active tasks first, waiting/grouped tasks below, recent completions briefly, and hidden counts when the queue is too large.
- The bottom panel shows a bounded Russian timeline of recent events.
- The top panel shows compact metrics: FPS, frame time, world update, chunk generation, visual build, queue sizes, loaded/visible/simulating/unloading/stalled counts, worst stage age, average stage age, load/sec, and unload/sec.

## Overlay layout

- Zone A, world/chunk visualization: drawn in world space over the map.
- Zone B, live queue: right-side fixed panel.
- Zone C, timeline: bottom fixed panel.
- Zone D, metrics: top fixed HUD line.

Default mode is compact. Expanded/focused modes may refine density later, but Iteration 1 must be useful immediately with one F11 toggle.

## Data model

Chunk entry fields:

- `coord`
- `z`
- `state`
- `state_human`
- `stage_age_ms`
- `priority`
- `distance`
- `requested_frame`
- `requested_timestamp_usec`
- `reason`
- `impact`
- `is_player_chunk`
- `is_visible`
- `is_simulating`
- `is_stalled`
- `source_system`
- `technical_code`

Queue row fields:

- `task_id`
- `group_key`
- `task_type`
- `task_type_human`
- `chunk_coord`
- `scope`
- `stage`
- `stage_human`
- `age_ms`
- `priority`
- `reason`
- `impact`
- `state`
- `queue_depth`
- `hidden_count`
- `completed_recently`
- `correlation_id`
- `predecessor_id`

Timeline event fields:

- `event_id`
- `timestamp_usec`
- `timestamp_label`
- `summary`
- `actor`
- `action`
- `target`
- `chunk_coord`
- `region`
- `reason`
- `impact`
- `state`
- `duration_ms`
- `queue_depth`
- `priority`
- `source_system`
- `technical_code`
- `correlation_id`
- `predecessor_id`
- `repeat_count`
- `dedupe_key`

Snapshot fields:

- `timestamp_usec`
- `active_z`
- `player_chunk`
- `player_motion`
- `radii`
- `chunks`
- `queue_rows`
- `queue_hidden_count`
- `timeline_events`
- `metrics`
- `mode_hint`

## Event pipeline

Chunk lifecycle owners emit structured diagnostics at state boundaries:

1. request
2. queue
3. generate
4. data ready
5. apply wait
6. build visual
7. ready
8. visible
9. unload
10. error or stalled observation

`WorldRuntimeDiagnosticLog` formats Russian summaries, keeps stable technical detail fields, dedupes repeated summaries, and exposes a bounded timeline snapshot.

## Queue visualization rules

- Active tasks come first.
- Waiting tasks come second.
- Recently completed tasks are shown briefly and then disappear.
- Rows are capped.
- Similar waiting work is grouped by task type, stage, priority band, and reason.
- Hidden work is reported as `+N скрыто`.
- Internal code terms may appear only as secondary technical detail after a Russian explanation.

## Timeline rules

- Bounded ring buffer.
- Old entries are dropped.
- Identical events inside cooldown update `repeat_count` and `last_timestamp_usec` instead of appending.
- Errors and stalled observations use higher visual emphasis.
- Unconfirmed root cause is phrased as observation, not proof.

## Russian human-readable log policy

Human summaries are in Russian and should answer:

- who initiated it
- what happened
- where it happened
- why it matters
- what impact level it has

Good message shape:

- `Игрок приблизился к границе области загрузки: запрошены 3 новых чанка впереди по движению.`
- `Подготовка визуала чанка (14, 6) задерживается: очередь построения перегружена.`
- `Чанк (15, 6) готов, но ещё не показан: ожидается применение результата на основном потоке.`

Bad message shape:

- `request_refresh chunk=14,6`
- `streaming_truth mismatch`
- `enqueue border_fix task`

## Technical detail layer for developers/agents

Every diagnostic event keeps structured fields for agents and engineers:

- `actor`
- `action`
- `target`
- `chunk_coord`
- `region`
- `reason`
- `impact`
- `state`
- `timestamp`
- `duration_ms`
- `queue_depth`
- `priority`
- `source_system`
- `technical_code`
- `correlation_id`
- `predecessor_id`

The overlay displays concise human text. The structured record remains available in the snapshot for precise debugging and grep-friendly log correlation.

## Performance and safety constraints

- No gameplay mutation from overlay.
- No full-world scan per frame.
- Snapshot radius is clamped.
- Queue rows are capped/grouped.
- UI refresh is throttled.
- Timeline is bounded and deduped.
- Diagnostic metadata is transient and not persisted.
- Existing worker and apply boundaries remain unchanged.

## Anti-noise / dedupe policy

- Dedupe key: `actor + action + target + reason + impact + state + technical_code`.
- Cooldown: identical events inside the cooldown update an existing timeline row.
- Queue anti-spam: cap visible rows and group low-priority waiting work.
- Dominant cause: show only confirmed owner cause as cause; otherwise label it as observed backlog or suspected delay.
- Repeated background debt: collapse into grouped rows and cooldown reminders.

## Implementation plan

1. Create this spec and persistent tracker entry.
2. Extend diagnostic log timeline buffer.
3. Add perf debug snapshot.
4. Add chunk manager debug snapshot and lifecycle event emission.
5. Build overlay node and F11 wiring.
6. Add localization keys.
7. Update contracts/API docs.
8. Run static verification and prepare manual human verification handoff.

## Acceptance criteria

The feature is accepted when a developer can walk around the world with F11 enabled and immediately see:

- how the load bubble expands around the player
- which chunks are absent/requested/queued/generating/data_ready/building_visual/ready/visible/simulating/unloading/error/stalled
- which tasks are active and which are waiting
- where queue backlog is forming
- the recent request to visible/unload event chain
- whether an issue is player-visible, background debt, or informational
- which detail is a root cause claim and which is only an observed state

## Example messages

- `[12:41:03.214] Запрошен чанк (13, 5): игрок приблизился к границе области загрузки, приоритет высокий.`
- `[12:41:03.221] Началась генерация данных чанка (13, 5): задача взята из очереди подготовки.`
- `[12:41:03.236] Данные чанка (13, 5) готовы за 15 мс: ожидается применение на основном потоке.`
- `[12:41:03.251] Визуал чанка (13, 5) готов за 12 мс: чанк можно публиковать.`
- `[12:41:03.255] Чанк (13, 5) стал видимым: игрок больше не должен видеть пустоту впереди.`
- `[12:41:04.020] Наблюдается задержка визуала чанка (14, 6): задача висит 910 мс в очереди построения, причина не подтверждена как корневая.`

## Example on-screen states

Top HUD:

```text
F11 Chunk Debug | FPS 60 | frame 16.4 ms | world 1.1 ms | gen 0.7 ms | visual 1.8 ms | Q load 3 gen 1 ready 2 visual 8 | chunks 25/16 visible/9 sim | stalled 1 | worst 910 ms | avg 43 ms | load/s 2 unload/s 1
```

Queue panel:

```text
Активные задачи
Генерация данных чанка (13, 5) - 18 мс - высокий - игрок движется к границе
Подготовка визуала чанка (12, 6) - 41 мс - средний - догоняет ближнее кольцо

Ожидают
Запрос чанка - 3 шт - высокий - впереди по движению
Подготовка визуала чанка - 8 шт - средний - ближние и дальние чанки
+17 скрыто

Недавно завершено
Визуал чанка (12, 5) готов - 12 мс
```

Timeline:

```text
[12:41:03.214] Запрошен чанк (13, 5), приоритет высокий.
[12:41:03.221] Началась генерация данных чанка (13, 5).
[12:41:03.236] Генерация чанка (13, 5) завершена за 15 мс.
[12:41:03.251] Визуал чанка (13, 5) готов за 12 мс.
[12:41:03.255] Чанк (13, 5) стал видимым.
```

## Risks and non-goals

Risks:

- Overlay overhead could grow if it scans all loaded/world state. Mitigation: bounded radius, capped queue rows, throttled UI refresh.
- Debug Russian text could drift from localization rules. Mitigation: static overlay chrome uses localization keys; runtime diagnostic summaries stay in the debug diagnostic layer and preserve structured fields.
- Stalled labels could be mistaken for proven root cause. Mitigation: stalled wording explicitly says observed delay unless owner evidence confirms cause.
- Queue panel could become unreadable under stress. Mitigation: grouping and hidden counts are mandatory.

Non-goals:

- No external telemetry platform.
- No web dashboard.
- No save/load format changes.
- No chunk scheduler redesign.
- No new gameplay state owner.
- No replacement of existing worker/generation/apply pipeline.
