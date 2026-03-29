---
title: Boot Visual Completion Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.2
last_updated: 2026-03-29
depends_on:
  - boot_chunk_readiness_spec.md
  - boot_chunk_apply_budget_spec.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
related_docs:
  - ../../04_execution/chunk_boot_streaming_rollout.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
---

# Feature: Boot Visual Completion

## Design Intent

Boot must stop forcing full visual completion for the whole startup bubble before the player can begin.

This spec defines which visual phases are required immediately and which are allowed to complete later:
- terrain
- cover
- cliff
- flora
- debug-only phases

The goal is to preserve readability near the player while removing unnecessary full-bubble redraw cost from the critical boot path.

## Public API impact

Current public APIs affected semantically:
- `Chunk.complete_redraw_now() -> void`
- `Chunk.is_redraw_complete() -> bool`
- `ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`

Required API/documentation outcome after implementation:
- `PUBLIC_API.md` must stop implying that boot always forces immediate full redraw of all startup chunks.
- `Chunk.complete_redraw_now()` remains owner-only and must not become a generic boot-wide hammer.
- If a new read-only visual-readiness query is added, it must be documented explicitly.

## Data Contracts — new and affected

### New layer: Boot Visual Readiness Policy
- What: startup policy mapping chunk rings to required visual completion phases.
- Where: `core/systems/world/chunk_manager.gd` and `core/systems/world/chunk.gd`.
- Owner (WRITE): `ChunkManager` for policy, `Chunk` for phase execution.
- Readers (READ): boot gate logic, instrumentation, scene boot orchestrator.
- Invariants:
  - ring-0 requires full terrain readability before first-playable.
  - outer rings may remain on progressive redraw after first-playable.
  - debug visual phases must never be part of first-playable.
  - flora is deferred by default unless explicitly enabled by this spec.
- Event after change: none required in iteration 1.
- Forbidden:
  - calling `complete_redraw_now()` on the entire startup bubble
  - letting debug phases hold first-playable
  - requiring flora for first-playable by accident

### Affected layer: Presentation
- What changes:
  - startup redraw policy becomes ring-aware and phase-aware.
- New invariants:
  - `visual_complete` for first-playable means "required phases complete for required rings", not "all redraw phases complete for every startup chunk".
- Who adapts:
  - `ChunkManager`
  - `Chunk`
- What does NOT change:
  - redraw implementation ownership stays inside `Chunk`

### Affected layer: Chunk Lifecycle
- What changes:
  - lifecycle must distinguish `applied` from `required_visual_ready`.
- New invariants:
  - a chunk may be applied and present while still progressing through deferred visual phases.
- Who adapts:
  - `ChunkManager`
- What does NOT change:
  - chunk registration order is defined elsewhere

## Required boot visual policy

Initial required policy:
- ring 0: terrain, cover, cliff required before first-playable. Enforced via `complete_redraw_now()` at apply time.
- ring 1: terrain required before first-playable. Enforced via `Chunk.complete_terrain_phase_now()` at apply time — draws terrain layer for all tiles, then advances progressive redraw to COVER phase. Cover/cliff complete via `FrameBudgetDispatcher` after first-playable. This eliminates green placeholder zones visible near spawn.
- outer startup rings: progressive redraw after first-playable
- flora: deferred by default for all rings except if later explicitly approved
- debug phases: never part of first-playable or boot-complete gates in shipping runtime

## Iterations

### Iteration 1 — Remove forced full-bubble immediate redraw ✅
Goal: stop boot from calling full redraw for every startup chunk.

What is done:
- boot path no longer runs `complete_redraw_now()` across the whole startup bubble
- immediate redraw is limited to policy-approved rings only (ring 0: full, ring 1: terrain-only, outer: progressive)
- farther chunks enter the existing progressive redraw path
- outer chunks set `visible = false` at apply time, become visible when `is_terrain_phase_done()` — no green placeholder zones
- after `first_playable`, boot pipeline drains; outer chunks load via budgeted runtime streaming

Acceptance tests:
- [x] manual: startup logs no longer show immediate full redraw for every startup chunk. Only ring 0 emits `Chunk._redraw_all`. Ring 1 uses `complete_terrain_phase_now()`. Outer uses progressive.
- [x] `assert(outer_ring_chunks_do_not_call_complete_redraw_now_by_default)` — enforced in `_boot_apply_from_queue()`: only `ring == 0` calls `complete_redraw_now()`.
- [x] `assert(ring0_chunks_reach_required_visual_state_before_first_playable)` — ring 0 gets full redraw at apply → `VISUAL_COMPLETE` before `first_playable` gate check.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/surface_terrain_resolver.gd`

### Iteration 2 — Make visual completion ring-aware and phase-aware ✅
Goal: define exactly which redraw phases matter for each required startup ring.

What is done:
- codify ring-based redraw requirements: ring 0 = full (terrain+cover+cliff), ring 1 = terrain-only, outer = progressive
- codify which phases are required for boot gates: `is_gameplay_redraw_complete()` = terrain+cover+cliff (phase >= FLORA). Flora and debug phases excluded.
- codify that debug phases are excluded from boot gates: `_boot_promote_redrawn_chunks()` uses `is_gameplay_redraw_complete()`, not `is_redraw_complete()`
- `Chunk.is_gameplay_redraw_complete()` — new read-only query: true when terrain+cover+cliff done

Acceptance tests:
- [x] `assert(debug_phases_not_in_boot_gate)` — `is_gameplay_redraw_complete()` returns true at FLORA phase, before DEBUG_INTERIOR/DEBUG_COLLISION. Debug never blocks boot_complete.
- [x] `assert(first_playable_visual_gate_uses_policy_not_full_redraw_done)` — gate uses ring-aware logic: ring 0 VISUAL_COMPLETE (via gameplay redraw), ring 1 APPLIED (with terrain drawn). Not full `is_redraw_complete()`.
- [x] manual: far chunks visibly continue finishing cover/cliff/flora/debug after control begins. Outer chunks appear when terrain phase completes (`is_terrain_phase_done`).

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `scenes/world/game_world.gd`

### Iteration 3 — Defer flora by default ✅
Goal: remove flora from the critical visual boot path unless later profiling proves otherwise.

What is done:
- `_redraw_all()` now sets `_redraw_phase = REDRAW_PHASE_FLORA` instead of `DONE` — terrain+cover+cliff are drawn immediately, flora deferred to progressive redraw
- boot gates use `is_gameplay_redraw_complete()` (phase >= FLORA) — flora NOT required for VISUAL_COMPLETE or first_playable
- chunks with pending flora stay in `_redrawing_chunks` after `complete_redraw_now()` — flora draws progressively via FrameBudgetDispatcher
- both runtime streaming and boot apply paths: `_redrawing_chunks.append(chunk)` when `not chunk.is_redraw_complete()` (replaces `not is_player_chunk` guard)

Acceptance tests:
- [x] `assert(first_playable_does_not_require_flora_phase)` — `is_gameplay_redraw_complete()` = true at FLORA phase. VISUAL_COMPLETE promotion does not wait for flora. `first_playable` gate checks ring 0 VISUAL_COMPLETE which is reached before flora.
- [x] manual: player can begin while nearby flora finishes shortly after spawn — ring 0 chunk stays in `_redrawing_chunks` for progressive flora after `_redraw_all()`.
- [x] manual: no terrain/readability regression — `_redraw_all()` still draws terrain+cover+cliff synchronously. Only flora is deferred.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_flora_builder.gd`

## Required contract and API updates after implementation

When this spec is implemented, update:
- `DATA_CONTRACTS.md`
  - presentation layer boot-readiness semantics
  - redraw phase requirements for boot gates
- `PUBLIC_API.md`
  - semantics of `boot_load_initial_chunks()`
  - owner-only meaning of `complete_redraw_now()` in boot contexts

## Out-of-scope

- worker compute design
- main-thread apply queue design
- topology timing
- flora compute algorithm changes
- lighting shadow system boot policy

Those belong to adjacent specs.
