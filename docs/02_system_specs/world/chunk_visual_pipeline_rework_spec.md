---
title: Chunk Visual Pipeline Rework
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-13
depends_on:
  - DATA_CONTRACTS.md
  - boot_fast_first_playable_spec.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
related_docs:
  - ../../04_execution/chunk_visual_pipeline_rework_plan.md
  - ../../04_execution/mountain_roof_system_refactor_plan.md
---

# Feature: Chunk Visual Pipeline Rework

## Legacy Status

This spec documents a legacy interim rollout for the hybrid chunk runtime.

It is no longer the active architecture target for player-reachable chunk readiness or seamless traversal. Active target selection now lives in:

- `zero_tolerance_chunk_readiness_spec.md`
- `frontier_native_runtime_architecture_spec.md`
- `../../04_execution/frontier_native_runtime_execution_plan.md`

New work must not extend `first_pass`, publish-now / finish-later, or other hybrid progressive-convergence semantics as acceptable player behavior.

## Design Intent

Current boot/runtime work already includes the `boot_fast_first_playable_spec.md` fixes:

- ring 0-1 can get immediate terrain publication
- `_redrawing_chunks` still remains the active redraw authority
- `_tick_redraws()` still advances one chunk step and returns
- boot/runtime still rely on the progressive redraw phase machine to "eventually catch up"

That baseline removed the worst startup stall, but it did not solve the architectural problem described in `docs/04_execution/chunk_visual_pipeline_rework_plan.md`:

- near-visible chunks still compete with far/background redraw work
- visual readiness still depends on a chunk-local progressive pipeline that has no explicit first-pass contract
- final correctness and initial visibility are still conflated
- the main thread still does too much visual thinking in the wrong place

This feature introduces an explicit chunk visual pipeline with:

1. a priority budget scheduler owned by `ChunkManager`
2. a distinct first-pass readiness contract for near-visible chunks
3. canonical deferred full redraw convergence
4. explicit border/seam repair work
5. telemetry that proves urgent work is not starved

The first shipped version covers rollout phases V0-V3 from the execution plan. Worker-side descriptor migration (V4) and an optional proxy renderer (V5) are deferred to follow-up specs because they expand beyond the currently approved file boundary and require new payload/renderer contracts.

## Architectural Mapping

Closest existing systems:

- `ChunkManager` boot/runtime chunk orchestration
- `Chunk` progressive redraw phase machine
- `WorldGenBalance` redraw/streaming tuning resource
- `GameWorld` first-playable handoff and loading UI

Pattern fit:

- background, budgeted, locality-bounded work (`PERFORMANCE_CONTRACTS.md`)
- compute/apply separation with explicit main-thread apply boundary (`SIMULATION_AND_THREADING_MODEL.md`)
- derived/presentation state must not redefine canonical world truth (`DATA_CONTRACTS.md`)

Performance classification:

- boot-time: first-pass publication for startup slice
- background: scheduler-driven first-pass/full/border/cosmetic tasks
- interactive: unchanged; mining/building must still enqueue consequences instead of triggering full visual rebuilds synchronously

## Data Contracts - new and affected

### New layer: Visual Task Scheduling

- What:
  - Scheduler-owned task queues for chunk visual work kinds (`first_pass`, `terrain_continue`, `full_redraw`, `border_fix`, `cosmetic`)
  - Queue membership, task priority, invalidation version, and latency telemetry for visual work
- Where:
  - `core/systems/world/chunk_manager.gd`
  - chunk-level readiness/version fields in `core/systems/world/chunk.gd`
- Owner (WRITE):
  - `ChunkManager`
- Readers (READ):
  - `ChunkManager` boot/runtime loops
  - `GameWorld` boot progress and handoff
  - telemetry/profiling readers only
- Invariants:
  - `assert(only_chunk_manager_mutates_visual_task_queues, "visual task queues are owner-only scheduler state")`
  - `assert(urgent_near_work_outranks_far_work, "terrain_urgent and terrain_near must outrank full_far and cosmetic")`
  - `assert(task_registration_is_deduped_by_chunk_kind_and_version, "visual scheduling must not accumulate duplicate stale tasks for one chunk/kind/version")`
  - `assert(queue_latency_for_near_visible_chunks_is_observable, "scheduler must expose urgent wait / first-pass latency metrics")`
  - `assert(background_visual_work_is_budgeted, "visual scheduler work must stay inside an explicit per-tick budget")`
- Event after change:
  - none required in Iteration 1; telemetry is mandatory
- Forbidden:
  - direct queue mutation outside `ChunkManager`
  - direct chunk visibility flips that bypass first-pass/full-ready state
  - treating scheduler state as canonical world truth or save data

### Affected layer: Presentation

- What changes:
  - Presentation gains an explicit split between first-pass readiness and canonical full convergence.
  - Border/seam repair becomes explicit scheduled work instead of an implicit side-effect of a general redraw queue.
  - `complete_terrain_phase_now()` and `warmup_tile_layers()` are demoted from production boot assumptions to compatibility/debug/fallback helpers.
- New invariants:
  - `assert(visible_near_chunk_implies_first_pass_ready, "a near-visible chunk must not be shown below first-pass readiness")`
  - `assert(full_redraw_remains_canonical_final_builder, "first-pass may be approximate, but full redraw owns final visual correctness")`
  - `assert(border_fix_work_is_not_starved_behind_far_convergence, "visible seam repair outranks far full redraw")`
- What does NOT change:
  - canonical terrain/world truth ownership
  - mining/topology/reveal source-of-truth semantics
  - current TileMap-based renderer as the canonical output target for V0-V3

### Affected layer: Boot Readiness

- What changes:
  - `first_playable` is redefined in terms of first-pass readiness for the near startup slice, not synchronous terrain helpers or legacy redraw phase assumptions.
  - `boot_complete` remains stricter and depends on full convergence plus required support systems.
- New invariants:
  - `assert(first_playable_requires_first_pass_ready_for_ring_0_1, "boot handoff depends on near-slice first-pass readiness, not full convergence")`
  - `assert(boot_complete_requires_full_ready_for_tracked_startup_chunks, "boot_complete stays a terminal full-convergence gate")`
  - `assert(runtime_handoff_preserves_pending_full_redraw_and_border_fix_work, "boot handoff must not discard owed visual work")`
- What does NOT change:
  - `GameWorld` remains the owner of player-control handoff
  - topology/shadow boot completion remains a separate support-system gate

### Affected layer: Chunk Lifecycle

- What changes:
  - staged loading finalization schedules explicit first-pass/full/border work instead of assuming one progressive redraw queue is sufficient
  - chunk visibility is gated by first-pass readiness, not by raw apply completion
- New invariants:
  - `assert(newly_loaded_near_chunk_schedules_first_pass_immediately, "runtime streaming must enqueue first-pass work for near-visible chunks as soon as apply completes")`
  - `assert(newly_loaded_chunk_that_owes_convergence_enters_full_pending_state, "approximate publication must explicitly schedule canonical follow-up work")`
- What does NOT change:
  - chunk node creation/apply remains main-thread work
  - unloaded world read rules stay unchanged

## Iterations

### Iteration 1 - Scheduler Surgery + Telemetry Baseline

Goal: replace `_redrawing_chunks` as the active authority with a budgeted priority scheduler, while keeping the current chunk-local redraw implementation as a temporary compatibility path.

What is done:

- add explicit visual scheduler queues and dedupe/version helpers in `ChunkManager`
- add `WorldGenBalance` knobs for visual scheduler budgets and per-task throughput
- replace `_tick_redraws()` ownership with `_tick_visuals()` that can process multiple tasks while budget remains
- preserve current `Chunk.continue_redraw()` and terrain-only compatibility helpers for now, but schedule them through explicit task kinds
- add telemetry/warnings for urgent wait, queue depth, tasks processed per tick, budget exhaustion, first-pass latency placeholder hooks, and starvation incidents

Acceptance tests:

- [ ] `WorldGenBalance` exports exist for `visual_scheduler_budget_ms`, `visual_first_pass_tiles_per_step`, `visual_full_redraw_tiles_per_step`, `visual_border_fix_tiles_per_step`, `visual_cosmetic_tiles_per_step`, `visual_first_pass_max_tasks_per_tick`, `visual_full_redraw_max_tasks_per_tick`
- [ ] `world_gen_balance.tres` provides concrete defaults for the new `visual_*` fields
- [ ] `chunk_manager.gd` contains explicit queues for urgent/near/full/border/far/cosmetic visual work
- [ ] `_tick_visuals()` loops while budget remains and is able to process more than one task per tick
- [ ] `_tick_redraws()` is removed or reduced to a compatibility adapter; queue selection authority lives in `_tick_visuals()`
- [ ] scheduler telemetry records processed count, queue depths, budget exhaustion, and urgent wait
- [ ] no new public API surface is introduced in Iteration 1
- [ ] runtime validation: urgent queue does not starve behind far work during sprinting across chunk boundaries

Files that may be touched:

- `core/systems/world/chunk_manager.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:

- `core/systems/world/chunk.gd`
- `scenes/world/game_world.gd`
- `core/autoloads/world_generator.gd`
- mining/topology/reveal/shadow systems
- any new external validation harness outside the repository

### Iteration 2 - First-Pass Readiness State Machine

Goal: introduce explicit chunk visual readiness state and boot/runtime visibility rules that depend on first-pass, not on legacy redraw phase assumptions.

What is done:

- add `ChunkVisualState` and chunk-local readiness/query methods
- split chunk-local first-pass continuation from canonical full redraw continuation
- update staged loading finalize and boot handoff to schedule first-pass explicitly for near chunks
- update `GameWorld` loading semantics so first-playable vs boot-complete are distinct user-facing milestones
- update docs for the new readiness contract and public read APIs

Acceptance tests:

- [ ] `ChunkVisualState` exists with explicit states for uninitialized/native/proxy/terrain/full-pending/full-ready
- [ ] `Chunk.is_first_pass_ready()`, `Chunk.is_full_redraw_ready()`, and `Chunk.needs_full_redraw()` exist
- [ ] `ChunkManager.boot_load_initial_chunks()` first-playable gate depends on first-pass readiness for ring 0-1, not on `complete_terrain_phase_now()` or flora completion
- [ ] runtime staged finalize schedules separate first-pass and full-redraw tasks
- [ ] near-visible chunks become visible only after first-pass readiness is true
- [ ] `GameWorld` preserves the distinction between first-playable handoff and boot-complete background convergence
- [ ] `DATA_CONTRACTS.md` is updated for `Visual Task Scheduling`, `Presentation`, `Boot Readiness`, and `Chunk Lifecycle`
- [ ] `PUBLIC_API.md` is updated for any new readiness query methods and for changed `boot_load_initial_chunks()` / `is_boot_first_playable()` semantics

Files that may be touched:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `scenes/world/game_world.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must NOT be touched:

- `core/autoloads/world_generator.gd`
- `core/systems/world/world_feature_debug_overlay.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- unrelated gameplay systems

### Iteration 3 - Full Redraw as Canonical Convergence + Explicit Border Fix

Goal: restore full redraw as the canonical final visual path without putting it back on the blocking startup/near-activation path.

What is done:

- add explicit `TASK_FULL_REDRAW` and `TASK_BORDER_FIX` task kinds with near/far priority bands
- add versioned invalidation rules so mining/neighbor-load/approximate first-pass can re-enter `VISUAL_FULL_PENDING`
- move visible seam repair to explicit scheduled border-fix work
- demote `complete_terrain_phase_now()` and `warmup_tile_layers()` from production boot assumptions to diagnostics/fallback paths only
- define terminal full-ready observability and boot-complete wiring around full convergence

Acceptance tests:

- [ ] `TASK_FULL_REDRAW` and `TASK_BORDER_FIX` exist and are enqueued through version-aware helpers
- [ ] chunks re-enter full-pending when seam/mutation/approximation invalidates final correctness
- [ ] visible seam defects enqueue border-fix work that outranks far full redraw
- [ ] the normal boot critical path no longer depends on `Chunk.complete_terrain_phase_now()` or `Chunk.warmup_tile_layers()`
- [ ] `VISUAL_FULL_READY` is the only terminal visual state
- [ ] boot-complete depends on full-ready startup chunks plus required support systems
- [ ] `DATA_CONTRACTS.md` and `PUBLIC_API.md` reflect the canonical/full-ready semantics and helper demotion
- [ ] runtime validation: near-visible seam defects converge quickly and near chunks reach full-ready in bounded background time

Files that may be touched:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `scenes/world/game_world.gd`
- `data/world/world_gen_balance.gd`
- `data/world/world_gen_balance.tres`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must NOT be touched:

- `core/autoloads/world_generator.gd`
- `core/systems/world/world_feature_debug_overlay.gd`
- `core/systems/world/mountain_roof_system.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- unrelated save/load, inventory, AI, or building systems

## Required contract and API updates

Documentation debt for this feature is not optional.

- `DATA_CONTRACTS.md`
  - add the `Visual Task Scheduling` layer when Iteration 1 lands
  - rewrite `Presentation`, `Boot Readiness`, and `Chunk Lifecycle` invariants when Iteration 2 lands
  - update terminal/full-convergence semantics and sync-helper demotion when Iteration 3 lands
- `PUBLIC_API.md`
  - Iteration 1: likely not required if no public surface changes; must still be verified by grep
  - Iteration 2: required for any new chunk readiness query methods and for revised first-playable semantics
  - Iteration 3: required if `complete_terrain_phase_now()` / `warmup_tile_layers()` move to diagnostics/fallback status or if public read semantics change

## Explicitly Out of Scope for This Spec

- worker/native visual descriptor payload changes in generator/build result files
- renderer/proxy layer replacement
- mountain roof/visibility redesign outside the existing chunk visual pipeline
- mining/topology contract redesign outside visual invalidation wiring
- broad world generation or chunk compute refactors

Those belong to follow-up specs after V0-V3 are shipped and measured.
