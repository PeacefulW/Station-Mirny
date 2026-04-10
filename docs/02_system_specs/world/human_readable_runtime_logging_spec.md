---
title: Human Readable Runtime Logging Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-10
depends_on:
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/WORKFLOW.md
related_docs:
  - boot_performance_instrumentation_spec.md
  - mountain_reveal_and_world_perf_recovery_spec.md
---

# Feature: Human-Readable Runtime Logging For World Diagnostics

## Design Intent

World/runtime/perf/debug logs must stop assuming the reader already knows private function names, queue names, and internal ownership boundaries.

This spec defines a human-readable diagnostic logging policy for the world/runtime stack so one log stream can answer three different needs at the same time:
- a non-developer must be able to understand what happened and whether it matters to the player
- an agent/developer must still keep internal terminology, queue state, and ownership clues needed for root-cause analysis
- future runtime validation and proof flows must be able to classify outcomes without reverse-engineering ad-hoc strings

The goal is not "more logs". The goal is attributed, layered logs:
- one human summary line
- one technical detail line when needed
- perf timings that stay precise
- validation outcomes that say whether the world converged, why, and where it did not

Human-readable logging is a translation and attribution layer on top of owner-known runtime facts. It does not replace raw instrumentation, and it must not become a new gameplay state system.

## Logging Goals

### For a human reader

Human-readable runtime logging must answer:
- who initiated the work
- what happened
- where it happened
- why it matters
- whether this is the actual cause of the player-facing problem or only background follow-up work
- what is important right now versus what is diagnostic detail

### For an agent or developer

Human-readable runtime logging must still answer:
- which owner system emitted the statement
- whether the event is a root cause, an observed effect, or a follow-up task
- which chunk, region, route segment, or queue band is involved
- whether state was wrong when calculated, overwritten later, still queued, or already applied but not converged
- which internal term, queue name, or blocker keyword should be grepped next

### Human-readable logging versus raw instrumentation

Human-readable logging:
- explains meaning in Russian first
- keeps the canonical English/internal term only where it helps debugging
- prioritizes the dominant cause or outcome
- distinguishes player-visible issue from background debt

Raw instrumentation:
- keeps exact timings, counters, budgets, queue depths, and internal identifiers
- remains allowed in technical detail and perf telemetry
- must not be the only layer a human has to read

## Public API Impact

Current observability/proof surfaces affected semantically:
- `WorldPerfProbe.record(...)`
- `WorldPerfProbe.report_budget_overrun(...)`
- `core/debug/runtime_validation_driver.gd` console output
- owner-local runtime diagnostics in `ChunkManager`, `MountainRoofSystem`, and `MountainShadowSystem`

Required API/documentation outcome after implementation:
- no new gameplay safe entrypoint is required for this feature
- `PUBLIC_API.md` does not need to expose internal logging writers
- if implementation adds a read-only diagnostic snapshot or helper that other systems are expected to call directly, that read API must be documented in `PUBLIC_API.md`
- no system may gain a public mutation API whose only purpose is to push logging state from outside the authoritative owner

## Performance / Scalability Contract

- Runtime class: `interactive + background observability`
- Target scale / density:
  - large streaming/load/redraw queues
  - repeated seam-mining and follow-up invalidation chains
  - many loaded chunks around the player
  - long runtime validation routes with repeated catch-up waits
- Authoritative source of truth:
  - world state remains authoritative in existing owners such as `ChunkManager`, `MountainRoofSystem`, and `MountainShadowSystem`
  - perf timings remain authoritative in `WorldPerfProbe`
  - route/proof progression remains authoritative in `RuntimeValidationDriver`
  - human-readable diagnostic lines are derived from those owners; the log itself is never source of truth
- Write owner:
  - each owner system is the only system allowed to claim the root cause for its own transition
  - a shared formatting helper may format, dedupe, and emit, but must not invent ownership or rewrite another system's causal claim
- Derived/cache state:
  - transient summary strings
  - transient technical detail strings
  - dedupe/cooldown metadata
  - optional per-run summary accumulators
  - all of the above are log-only and non-persistent
- Dirty unit:
  - one semantic transition keyed by `actor + action + target + reason + impact + state`
  - not one line per tile
  - not one line per frame
- Allowed synchronous work:
  - assemble a bounded message from already-known local facts
  - sample already-available queue counts, chunk coordinates, versions, and timing values
  - emit at state-transition boundaries such as `queued`, `blocked`, `applied`, `restored`, `stale`, `converged`, `failed`
- Escalation path:
  - human summary log: when dominant cause or user-relevant state changes
  - technical detail log: when a summary is emitted, when explicit debug/proof context is active, or when internal attribution is needed
  - perf timing log: timings, budgets, backlog counts, and overrun diagnostics only
  - validation outcome log: route/proof milestones, blocker changes, timeout/failure, and final convergence result
- Degraded mode:
  - if exact cause is not yet owner-confirmed, emit an observed-effect summary that explicitly says cause is not yet confirmed
  - suppress repeated summaries and keep only perf telemetry when the same background debt continues without a meaningful state change
- Forbidden shortcuts:
  - scanning all loaded chunks only to phrase a nicer message
  - adding a new persistent mirror of runtime state for logging convenience
  - emitting human summary lines every frame
  - claiming root cause from timing alone
  - letting logs become a new source of lag in the interactive path

## Data Contracts — New And Affected

### New layer: World runtime diagnostic records
- What:
  - immutable, non-persistent diagnostic payloads that translate owner-known runtime events into human summary, technical detail, perf attribution, or validation outcome logs
- Where:
  - new helper `core/debug/world_runtime_diagnostic_log.gd`
  - owner call sites in `core/systems/world/world_perf_probe.gd`
  - `core/debug/runtime_validation_driver.gd`
  - `core/systems/world/chunk_manager.gd`
  - `core/systems/world/mountain_roof_system.gd`
  - `core/systems/lighting/mountain_shadow_system.gd`
- Owner (WRITE):
  - source owner system prepares the payload for its own event class
  - shared helper owns formatting, severity selection, and dedupe metadata only
- Readers (READ):
  - console log review
  - future summary/parser tooling
  - runtime proof review
  - closure-report evidence gathering
- Invariants:
  - every important runtime diagnostic record includes `actor`, `action`, `target`, `reason`, `impact`, and `state`
  - human summary text is Russian-first and understandable without private function names
  - optional English/internal term appears only with human gloss when useful
  - records are derived from already-available owner state and never drive gameplay logic
  - records are immutable after emission; later systems may emit follow-up records, not mutate old ones
- Event after change:
  - console emission only; no gameplay signal required
- Forbidden:
  - persisting records in save data
  - treating records as a readiness or state API
  - letting one subsystem silently rewrite another subsystem's causal statement

### Affected layer: Runtime validation proof output
- What changes:
  - route/proof logs become outcome-oriented and explicitly state whether the world finished, did not converge, or was blocked
- New invariants:
  - validation logs must classify blocker, impacted target, and impact band
  - final outcome must distinguish `finished`, `not_converged`, and `blocked`
  - raw blocker terms such as `streaming_truth` may remain in technical detail only
- Who adapts:
  - `RuntimeValidationDriver`
  - `ChunkManager` as blocker-state provider where needed
- What does NOT change:
  - runtime validation route ownership
  - runtime proof policy from `PERFORMANCE_CONTRACTS.md`

### Affected layer: World presentation and convergence observability
- What changes:
  - queue/apply/convergence diagnostics now distinguish initiator, target scope, cause class, and follow-up work
- New invariants:
  - only the authoritative owner may claim that an event is the root cause
  - `wrong_state_calculated` and `later_overwrite` are separate cause classes
  - repeated status uses transition-based dedupe rather than per-frame spam
- Who adapts:
  - `ChunkManager`
  - `MountainRoofSystem`
  - `MountainShadowSystem`
- What does NOT change:
  - terrain ownership
  - topology ownership
  - roof state ownership
  - shadow cache/build ownership

### Affected layer: Perf telemetry
- What changes:
  - timing logs may gain a human-readable summary form, but only when owner-provided causal context exists
- New invariants:
  - raw timing, queue, and budget values remain available
  - timing logs must not claim root cause from elapsed milliseconds alone
  - "not the cause" phrasing is allowed only when another owner-supplied blocker is known in the same diagnostic context
- Who adapts:
  - `WorldPerfProbe`
  - owner callers that attach causal context
- What does NOT change:
  - frame-budget enforcement ownership
  - sanctioned perf proof policy

## Logging Layers

### Human summary logs

Purpose:
- one concise line a non-developer can read without prior code knowledge

Rules:
- Russian first
- one dominant cause or outcome per line
- say whether this matters to the player now
- optional internal term only in parentheses and only with human gloss
- prefer `[WorldDiag]` prefix for owner-side diagnostic summaries

### Technical detail logs

Purpose:
- preserve grep-friendly internal detail for agents and developers

Rules:
- may be emitted as a second line next to the human summary
- keep stable key fields for future tooling
- include queue band, versions, follow-up jobs, route preset, timings, or backlog numbers when relevant
- may use internal terms such as `border_fix`, `streaming_truth`, or `roof_restore`, but never without a human summary companion when the line is user-relevant

### Perf timing logs

Purpose:
- keep exact timings, budgets, queue depths, and backlog pressure

Rules:
- stay under `[WorldPerf]`
- timings remain machine-precise
- human-readable timing summary is optional and secondary
- a perf line may say "this was not the dominant cause" only with owner-provided causal context

### Validation outcome logs

Purpose:
- report route/proof progress and final outcome in language that is understandable during manual review

Rules:
- stay under `[CodexValidation]` unless a future canonical prefix is approved
- must say `finished`, `not converged`, or `blocked`
- must name exact blocker and affected target
- must classify `player_visible_issue`, `background_debt_only`, or `informational_only`

## Canonical Log Shape

Every important runtime log entry must carry these semantic fields:
- `actor` / кто инициировал событие
- `action` / что произошло
- `target` / где это произошло
- `reason` / почему это произошло
- `impact` / насколько это важно игроку
- `state` / queued, applied, blocked, rebuilt, stale, restored, converged, overwritten_later, wrong_state_calculated, etc.
- `code_term` / optional internal or English term in parentheses

Recommended human summary order:
1. actor + action
2. target
3. reason
4. impact
5. state
6. optional code term in parentheses

Recommended technical detail order:
- `actor=<...> action=<...> target=<...> reason=<...> impact=<...> state=<...> code=<...>`

Recommended optional detail fields:
- `follow_up=<...>`
- `chunk=<x,y>`
- `region=<...>`
- `scope=<player_chunk|adjacent_loaded_chunk|far_runtime_backlog>`
- `route=<...>`
- `duration_ms=<...>`
- `budget_ms=<...>`
- `queue_depth=<...>`
- `source_version=<...>`
- `current_version=<...>`

Example summary lines:
- `Игрок закончил маршрут, но мир ещё не сошёлся: причина — перестройка топологии не завершена (topology rebuild not complete).`
- `Добыча на границе чанка поставила в очередь обновление: перерисовка 2 чанков, правка топологии 1 региона, обновление теней 1 региона.`
- `Обновление крыши заняло 1.4 ms и уложилось в лимит; задержку игрока сейчас создаёт очередь фоновой перерисовки (streaming redraw backlog).`

Example technical detail lines:
- `actor=manual_validation_route action=await_convergence target=player_chunk reason=topology_rebuild_not_complete impact=background_debt_only state=blocked code=topology chunk=(4,-1) route=local_ring`
- `actor=seam_mining_async action=queue_follow_up target=adjacent_loaded_chunk reason=queued_after_mining impact=player_visible_issue state=queued code=border_fix follow_up=streaming_redraw,topology_patch,shadow_refresh chunk=(12,-3)`

## Required Distinctions

### Initiator vocabulary

Human-readable logging must distinguish at minimum:
- `потоковая догрузка мира (stream_load)`
- `добыча на границе чанка (seam_mining_async)`
- `восстановление крыши (roof_restore)`
- `локальная правка после изменения тайла (local_patch)`
- `обновление теней горы (shadow_refresh)`
- `маршрут ручной проверки (manual_validation_route)`

### Target scope vocabulary

Human-readable logging must distinguish at minimum:
- `текущий чанк игрока (player_chunk)`
- `соседний загруженный чанк (adjacent_loaded_chunk)`
- `дальний runtime backlog (far_runtime_backlog)`

### Cause-class vocabulary

Human-readable logging must distinguish at minimum:
- `неверное состояние посчитано (wrong_state_calculated)`
- `корректное состояние позже перезаписано (later_overwrite)`
- `работа поставлена в очередь, но ещё не применена (queued_not_applied)`
- `работа применена, но мир ещё не сошёлся (applied_not_converged)`

### Impact bands

Human-readable logging must distinguish at minimum:
- `заметно игроку сейчас (player_visible_issue)`
- `только фоновый долг сходимости (background_debt_only)`
- `информационно, без текущего риска игроку (informational_only)`

## System Responsibilities

| System | Human summary | Technical detail | Perf telemetry | Validation outcome |
|---|---|---|---|---|
| `WorldPerfProbe` | timing/budget summary only; never sole root-cause owner | yes | primary owner | no |
| `RuntimeValidationDriver` | yes | yes | no direct ownership | primary owner |
| `ChunkManager` | yes for streaming/redraw/topology/border-fix/player-chunk blockage | yes | via `WorldPerfProbe` | blocker detail provider only |
| `MountainRoofSystem` | yes for roof refresh/restore/local-zone causality | yes | via `WorldPerfProbe` | no |
| `MountainShadowSystem` | yes when shadow refresh or stale/discarded work is diagnostically relevant | yes | via `WorldPerfProbe` | no |

Additional ownership rules:
- `ChunkManager` is the authoritative owner for `border_fix`, streaming redraw queue placement, topology dirty/build status, and player-chunk convergence blockage.
- `MountainRoofSystem` may claim roof refresh/restore/local-zone causality, but must not claim that queue-owned redraw debt belongs to it if the queue owner is `ChunkManager`.
- `MountainShadowSystem` may report shadow refresh, edge-cache rebuild, stale supersede/discard, and deferred work, but only as shadow-owner facts.
- `RuntimeValidationDriver` owns the final statement about proof outcome, not the underlying world-state ownership.
- `WorldPerfProbe` may report time and budget, but must not guess causal ownership.

## Anti-Goals

This spec explicitly forbids:
- adding more `push_warning()` calls without canonical structure
- logging only with private/internal names and no human meaning
- printing the same human summary every frame
- mixing root cause and incidental noise as if they were equivalent
- writing logs that are only understandable if the reader already knows the whole codebase
- turning one event into a multi-screen wall of text with no severity or priority
- inferring cause from time alone
- introducing a new laggy observability path in the name of debugging

## Required Contract And API Updates

- `DATA_CONTRACTS.md`:
  - `not required` for the preferred implementation path, because this feature does not change authoritative gameplay truth, safe entrypoints, persistence, or owner boundaries of world data
  - update only if implementation introduces a shared read-visible diagnostic snapshot beyond transient log emission
- `PUBLIC_API.md`:
  - `not required` for the preferred implementation path, because no gameplay/public safe entrypoint changes are required
  - update only if a read-only diagnostic helper becomes an approved external API
- `PERFORMANCE_CONTRACTS.md`:
  - required after Iteration 4 if the canonical vocabulary, severity, dedupe, and sanctioned harness wording from this spec become active project policy
- `WORKFLOW.md`:
  - `not required` for this feature by default, because closure-report rules already describe human-readable task reporting
  - revisit only if project governance later decides every new spec must declare a logging vocabulary section up front

## Iterations

### Iteration 1 — Logging vocabulary and canonical message shape
Goal: introduce one shared human-readable diagnostic style without sweeping every world system at once.

What is done:
- add a shared world-runtime diagnostic formatting/policy helper
- define canonical fields, impact bands, cause classes, and summary/detail message shapes
- pilot the new shape in one owner-side runtime diagnostic surface and one perf warning/timing surface
- preserve raw/internal terms in technical detail or perf logs

Acceptance tests:
- [ ] A captured human summary line includes actor, action, target, reason, impact, and state in human wording.
- [ ] A captured human summary line does not expose bare private names such as `_request_refresh`, `streaming_truth`, or `border_fix` without a human gloss.
- [ ] A captured technical detail line still contains stable key fields and useful internal terminology for grep/debug.
- [ ] Static review confirms no runtime behavior, queue ownership, or mutation semantics changed outside logging call sites.

Files that may be touched:
- `core/debug/world_runtime_diagnostic_log.gd`
- `core/systems/world/world_perf_probe.gd`
- `core/systems/world/chunk_manager.gd`

Files that must NOT be touched:
- `core/systems/world/chunk.gd`
- `core/autoloads/world_generator.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`

### Iteration 2 — Route/validation outcome logging
Goal: after a route/validation run, the log must say in plain language whether the world finished, did not converge, or is blocked, and why.

What is done:
- extend `RuntimeValidationDriver` to emit human-readable route/proof outcome lines
- classify exact blocker and target scope
- classify whether the blocker is player-visible or background-only
- keep raw blocker terms and queue/topology detail in technical detail output

Acceptance tests:
- [ ] After route validation, the final summary line says in human language whether the route `finished`, `not converged`, or `blocked`, and names the blocker.
- [ ] The log distinguishes `player_visible_issue` from `background_debt_only`.
- [ ] The log names the impacted chunk, region, or scope for the blocker.
- [ ] The human summary line is understandable without knowing private field names such as `_is_topology_dirty` or `_redrawing_chunks`.

Files that may be touched:
- `core/debug/runtime_validation_driver.gd`
- `core/debug/world_runtime_diagnostic_log.gd`
- `core/systems/world/chunk_manager.gd`

Files that must NOT be touched:
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- save/load systems

### Iteration 3 — Mining / border-fix / roof causality logging
Goal: make seam-mining and roof-related follow-up work attributable by owner, target, and cause class.

What is done:
- add owner-attributed diagnostic emission for seam mining, border-fix queueing, roof refresh/restore, and relevant shadow follow-up work
- make `ChunkManager` state when and where `border_fix` or redraw follow-up was queued
- make `MountainRoofSystem` state whether roof state was recalculated, restored, or later overwritten by later owner work
- make `MountainShadowSystem` report shadow refresh/deferred/stale discard only when it is part of the same causality chain

Acceptance tests:
- [ ] The log distinguishes initiators `stream_load`, `seam_mining_async`, `roof_restore`, `local_patch`, `shadow_refresh`, and `manual_validation_route`.
- [ ] For the seam/mining case, the log names the affected chunk or region and whether it is the player chunk, an adjacent loaded chunk, or far backlog work.
- [ ] For the roof-related case, the log can distinguish `wrong_state_calculated` from `later_overwrite`.
- [ ] A seam-mining summary line states the queued follow-up work in human wording, while technical detail preserves internal terms such as `border_fix`.
- [ ] The human summary line does not require knowledge of private function names or queue symbols.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `core/debug/world_runtime_diagnostic_log.gd`
- `core/systems/world/world_perf_probe.gd`

Files that must NOT be touched:
- terrain generation code
- mining balance/data definitions
- save payload formats

### Iteration 4 — Noise control / dedupe / severity rules
Goal: keep the log useful under long routes, large queues, and repeated background debt.

What is done:
- add transition-based dedupe keyed by `actor + action + target + reason + impact + state`
- define severity rules so dominant cause wins and follow-up noise is downgraded
- collapse repeated backlog spam into state changes and cooldown-based reminders
- align sanctioned perf/proof harness wording in `PERFORMANCE_CONTRACTS.md` if this policy becomes canonical

Acceptance tests:
- [ ] An identical human summary line does not print every frame; it re-emits only when state, impact, target, dominant reason, or cooldown boundary changes.
- [ ] One blocked route or backlog state does not print root cause and every downstream follower as equal-priority warnings.
- [ ] Technical detail and perf logs still preserve queue depth, backlog, timing, and budget values for agent/developer analysis.
- [ ] The implementation remains inside logging/observability scope and does not require a broad runtime refactor.
- [ ] `PERFORMANCE_CONTRACTS.md` documents canonical log layers, root-cause rules, and anti-spam policy if Iteration 4 lands.

Files that may be touched:
- `core/debug/world_runtime_diagnostic_log.gd`
- `core/systems/world/world_perf_probe.gd`
- `core/debug/runtime_validation_driver.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `docs/00_governance/PERFORMANCE_CONTRACTS.md`

Files that must NOT be touched:
- UI overlay/debug panel code
- unrelated world simulation systems
- gameplay balance/content files

## Out-of-Scope

- implementation code in this task
- runtime behavior changes
- bug fixing on the way
- a full observability platform or external telemetry pipeline
- a new UI overlay unless a later spec asks for it explicitly
- rewriting all of `WorldPerfProbe`
- rewriting all of `ChunkManager`
- unrelated documentation changes

This spec defines message policy, ownership, and iteration boundaries. It must not be used as an excuse to smuggle in a wider architecture rewrite.
