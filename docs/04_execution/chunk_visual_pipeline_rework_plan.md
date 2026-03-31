---
title: Chunk Visual Pipeline Rework Plan
doc_type: execution_plan
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-03-31
related_docs:
  - MASTER_ROADMAP.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../02_system_specs/world/lighting_visibility_and_darkness.md
  - ../02_system_specs/world/subsurface_and_verticality_foundation.md
  - mountain_roof_system_refactor_plan.md
---

# Chunk Visual Pipeline Rework Plan

This document is the execution-layer plan for replacing the current chunk visual activation and redraw model.

It does not override:
- governance rules
- ADRs
- system specs
- threading and performance contracts

Those higher-precedence docs remain the source of truth.

This plan exists to solve the current practical failure mode:
- boot is too slow
- the first visible chunk can stall for more than a second on cold start
- runtime streaming can leave near chunks in a partially drawn state for too long
- the player can outrun visual readiness and catch green/unrendered chunks
- the redraw scheduler is throughput-starved even when compute is already done

---

# 1. Executive Decision

## 1.1 Direct answer to the key question

Yes: **full redraw should return as the canonical final chunk visual path**.

No: **full redraw must not return as a blocking synchronous requirement in the first-playable path or ordinary near-chunk activation path**.

The project should not continue with the current strategy of trying to rescue the problem only by replacing `full redraw` with `terrain-only redraw` and tuning small budgets around it.

That strategy does not remove the architectural bottleneck.

## 1.2 Final model in one sentence

The new model is:
- a **cheap, non-blocking first-pass** that makes near chunks visibly valid immediately
- followed by a **deferred canonical full redraw** that converges each chunk to final visual correctness
- all driven by a **budget-based priority scheduler**, not by a round-robin single-queue redraw loop

---

# 2. Problem Statement

## 2.1 Current failure

The current chunk pipeline does detached compute reasonably well, but still performs too much expensive visual work at the wrong time and under the wrong scheduler policy.

The result is not just “insufficient budget”.
The result is an architectural mismatch:
- compute and apply are partially staged
- visual commit is still too expensive on the main thread
- redraw throughput is artificially limited
- urgent near-player work competes too fairly with far work
- the runtime can technically be alive while user-visible chunk readiness still lags behind movement

## 2.2 Why the recent terrain-only change was not enough

Replacing the old boot `full redraw` with `complete_terrain_phase_now()` for the center chunk did not solve the root issue.

Reasons:
- the center chunk still performs a full `64 x 64 = 4096` terrain walk on the main thread
- terrain redraw is still neighbor-aware and still writes many `TileMapLayer.set_cell()` calls
- the runtime redraw queue still advances too little useful work per tick
- `chunk_redraw_tiles_per_step` remains a hard ceiling on throughput
- near-visible chunks are still queued into a model that can starve them for too long

## 2.3 Core diagnosis

The root problem is:

**The game does not primarily fail because chunk generation is too slow. It fails because chunk visual publication is too expensive, too synchronous in the wrong places, and scheduled with the wrong fairness model.**

---

# 3. Goals

The rework must achieve all of the following:

1. The player must not see green or placeholder chunks near the camera.
2. The player must not be able to outrun near-chunk visual readiness.
3. First-playable must no longer depend on a blocking synchronous full visual bake.
4. Full redraw must remain available as the canonical final visual convergence path.
5. Near-visible chunk work must always outrank far/background chunk work.
6. Border/seam correctness must be restored quickly for visible chunks.
7. Runtime visual work must stay bounded, observable, and preemptible.
8. The final architecture must be compatible with future worker-side precomputation of visual descriptors.

---

# 4. Non-Goals

This plan does not aim to:
- redesign world generation itself
- rewrite the whole TileMap rendering system in one pass
- redesign chunk topology logic from scratch
- redesign underground fog/roof systems in this document
- replace all rendering with a custom renderer immediately
- require a one-shot mega-refactor with no intermediate shippable states

---

# 5. Hard Architectural Rules

The following rules are mandatory.

## 5.1 Full redraw rule

`full redraw` is the canonical final visual assembly path.

It is allowed to be:
- deferred
- progressive
- priority-scheduled
- resumed across frames

It is **not allowed** to be:
- the default blocking first-playable gate
- a required sync step before showing every new chunk
- the only way a near-visible chunk becomes minimally readable

## 5.2 First-pass rule

A near-visible chunk must be able to become visually acceptable before canonical full redraw finishes.

The first-pass may be simpler and visually poorer than final quality.
It may omit:
- flora
- debug layers
- non-critical visual polish
- expensive seam-perfect variants

It may **not** be:
- green placeholder state
- blank chunk state
- invisible terrain where gameplay expects readable world space

## 5.3 Scheduler rule

Near-visible work must not be queued into the same fairness model as far background work.

Round-robin fairness across all chunks is forbidden as the primary visual scheduling strategy.

## 5.4 Throughput rule

No single artificial throttle is allowed to collapse total throughput.

The new model must avoid stacking all of the following at once on the same path:
- dispatcher budget
- per-phase halving
- tiny tile ceilings
- one-chunk-per-tick early return
- hidden queue starvation behind “fairness”

## 5.5 Main-thread rule

The main thread should increasingly become a **visual committer**, not a **visual thinker**.

Long-term direction:
- worker/native code computes more visual descriptors
- main thread publishes precomputed results
- expensive neighbor classification should move out of interactive main-thread work as much as possible

---

# 6. Current Architecture Defects To Replace

## 6.1 Defect A: blocking visual cold start in boot

The current boot path still special-cases the center chunk with main-thread terrain completion and layer warmup.

This means the first visible chunk still pays a large one-time publication cost.

## 6.2 Defect B: one-queue redraw model

The current runtime uses one general redraw queue for all chunk visual continuation.

This causes:
- urgent and non-urgent work to mix
- fairness where latency priority is required
- visible starvation for chunks near the player

## 6.3 Defect C: one-chunk-per-tick behavior

The redraw tick effectively advances one chunk step and exits.

That creates terrible worst-case latency when many chunks are in flight.
A near chunk may wait a long time between tiny slices of progress.

## 6.4 Defect D: terrain ceiling is too low relative to chunk size

With a chunk size of 64x64 and a small `chunk_redraw_tiles_per_step`, terrain readiness can require too many scheduling rounds.

## 6.5 Defect E: no strict separation between “visible enough now” and “fully correct later”

The current model still conflates “chunk can be shown” with “chunk must complete a heavy terrain pass”.

---

# 7. Target Model Overview

## 7.1 Core idea

Each chunk moves through two distinct visual contracts:

1. **First-pass visual readiness**
   - the player can safely see the chunk
   - no green placeholder
   - near chunks become readable fast

2. **Canonical full visual readiness**
   - the chunk has fully converged to the final visual state
   - terrain, cover, cliff, seam repair, flora, and optional debug are in their final intended form

## 7.2 Why both are needed

If only full redraw exists, user-visible latency is too high.
If only first-pass exists, visual correctness never converges.

The game needs both.

---

# 8. New Chunk Visual State Machine

The runtime must introduce a dedicated visual state machine.

```gdscript
enum ChunkVisualState {
    VISUAL_UNINITIALIZED,
    VISUAL_NATIVE_READY,
    VISUAL_PROXY_READY,
    VISUAL_TERRAIN_READY,
    VISUAL_FULL_PENDING,
    VISUAL_FULL_READY,
}
```

## 8.1 State meanings

### `VISUAL_UNINITIALIZED`
The chunk node may not exist yet, or no visual data has been published.

### `VISUAL_NATIVE_READY`
Worker/native data is available and safe to apply.
Gameplay bytes may already exist.

### `VISUAL_PROXY_READY`
A cheap first-pass has been published.
The player will not see a green/blank placeholder.

### `VISUAL_TERRAIN_READY`
Base terrain publication is complete enough for practical world readability.

### `VISUAL_FULL_PENDING`
The chunk is visible enough but still owes canonical full redraw.

### `VISUAL_FULL_READY`
The chunk has converged to final visual correctness.

## 8.2 Required invariants

1. A chunk may become visible at `VISUAL_PROXY_READY` or `VISUAL_TERRAIN_READY`, depending on the chosen first-pass implementation.
2. `VISUAL_FULL_READY` is the only state that means the chunk no longer needs canonical visual convergence work.
3. A visible chunk near the player must not remain below `VISUAL_PROXY_READY` longer than the acceptance thresholds in this spec.

---

# 9. New Visual Task Model

The scheduler must stop treating redraw as “a chunk is in one queue”.

Instead, the scheduler must operate on explicit visual tasks.

```gdscript
enum VisualTaskKind {
    TASK_FIRST_PASS,
    TASK_TERRAIN_CONTINUE,
    TASK_FULL_REDRAW,
    TASK_BORDER_FIX,
    TASK_FLORA,
    TASK_DEBUG,
}
```

Each task should be represented by data similar to:

```gdscript
{
    "chunk_coord": coord,
    "z": z_level,
    "kind": VisualTaskKind.TASK_FIRST_PASS,
    "priority_band": 0,
    "camera_score": 0.0,
    "movement_score": 0.0,
    "eta_score": 0.0,
    "invalidation_version": 0,
}
```

## 9.1 Why explicit tasks are required

A single chunk can simultaneously require:
- urgent first-pass publication
- border/seam repair
- deferred full redraw
- later cosmetic follow-up

One queue entry per chunk is too coarse and prevents correct prioritization.

---

# 10. New Visual Queue Topology

The runtime must replace the single `_redrawing_chunks` queue with explicit priority queues.

Recommended first version:

```gdscript
var _visual_q_terrain_urgent: Array
var _visual_q_terrain_near: Array
var _visual_q_full_near: Array
var _visual_q_border_fix: Array
var _visual_q_full_far: Array
var _visual_q_cosmetic: Array
```

## 10.1 Priority order

Strict priority order:

1. `terrain_urgent`
   - player chunk
   - immediate neighbors
   - currently visible or immediately imminent chunks

2. `terrain_near`
   - ring 2 chunks
   - chunks ahead of the movement vector

3. `full_near`
   - canonical full redraw for near-visible chunks

4. `border_fix`
   - seam correction tasks for visible chunks and newly loaded neighbors

5. `full_far`
   - background canonical convergence for far chunks

6. `cosmetic`
   - flora, debug, optional polish

## 10.2 Fairness policy

Fairness is not symmetric across all queues.

The scheduler must prefer:
- low latency for urgent work
- reasonable throughput for background work

It must not prefer “equal turns” for all loaded chunks.

---

# 11. New Budget Model

The new system must stop relying on one tiny general redraw ceiling.

## 11.1 New balance fields

The project must add explicit visual scheduler controls to `WorldGenBalance`.

Recommended new exported fields:

```gdscript
@export_group("Chunk Visual Scheduler")
@export_range(0.5, 16.0) var visual_scheduler_budget_ms: float = 4.0
@export_range(16, 4096) var visual_first_pass_tiles_per_step: int = 256
@export_range(16, 4096) var visual_full_redraw_tiles_per_step: int = 192
@export_range(16, 4096) var visual_border_fix_tiles_per_step: int = 128
@export_range(16, 4096) var visual_cosmetic_tiles_per_step: int = 64
@export_range(1, 8) var visual_first_pass_max_tasks_per_tick: int = 4
@export_range(1, 16) var visual_full_redraw_max_tasks_per_tick: int = 6
```

## 11.2 Rules for budget usage

1. First-pass and full redraw must not share the same tiny tile ceiling.
2. Terrain budget must not be blindly halved just because the phase is terrain.
3. Border fixes must have their own explicit budget.
4. Cosmetic work must be separately throttled.

## 11.3 Config migration direction

The old knobs:
- `chunk_redraw_rows_per_frame`
- `chunk_redraw_tiles_per_step`

may remain temporarily for migration compatibility, but they must stop being the sole throughput bottleneck.

---

# 12. New First-Pass Contract

## 12.1 Purpose

The first-pass exists to eliminate visible bad states.

It must guarantee:
- no green chunks near the player
- no prolonged blank chunk areas
- minimal readable terrain publication

## 12.2 Allowed simplifications

The first-pass may omit or simplify:
- flora
- cliff polish
- expensive cover nuance
- full border perfection
- optional debug layers

## 12.3 Recommended implementation path

The first implementation should be a **cheap terrain publish**, not a perfect terrain publish.

This means:
- publish enough terrain to be visually readable
- postpone expensive canonical neighbor-sensitive refinement to full redraw

## 12.4 Alternative future option

If cheap terrain publish is still too expensive, the future extension is a true proxy layer:
- simplified chunk texture
- sprite-based coarse pass
- mesh-like coarse proxy

That is an optional later phase, not required for the first iteration of this rework.

---

# 13. New Full Redraw Contract

## 13.1 Definition

Full redraw is the canonical final visual convergence path.

It must be responsible for final correctness of:
- terrain variants
- rock/wall canonical classification
- cover state
- cliff state
- seam reconciliation
- flora publication
- optional debug markers

## 13.2 Scheduling rule

Full redraw may be progressive and deferred.

However:
- near-visible chunks must receive full redraw sooner than far chunks
- full redraw must eventually finish for all relevant loaded chunks
- completion must be observable in telemetry

## 13.3 Invalidation rule

A chunk re-enters `VISUAL_FULL_PENDING` whenever:
- a new neighbor invalidates seam correctness
- a mining/topology event invalidates canonical presentation
- a first-pass publish was deliberately approximate

---

# 14. Boot Redesign

## 14.1 New first-playable gate

The boot critical path must change.

### New `first_playable` depends on:
- compute complete for the required boot near-ring slice
- apply complete for the required boot near-ring slice
- `first_pass_ready` for the required boot near-ring slice
- gameplay-critical readiness

### New `first_playable` must not depend on:
- canonical full redraw for the center chunk
- synchronous terrain completion for the center chunk
- flora completion
- topology completion unless explicitly required by gameplay truth

## 14.2 New boot complete gate

`boot_complete` should mean:
- startup-required chunks reached `VISUAL_FULL_READY`
- required topology work is ready
- no pending urgent seam work remains

## 14.3 Mandatory removal from critical path

The following methods must be removed from the normal boot critical path:
- `Chunk.warmup_tile_layers()`
- `Chunk.complete_terrain_phase_now()`

They may remain only as:
- diagnostics
- debug profiling tools
- emergency forced fallback paths

They must not remain the primary boot optimization strategy.

---

# 15. Runtime Streaming Redesign

## 15.1 New runtime invariant

If a chunk becomes near-visible or imminently reachable by the player, the chunk must reach at least `first_pass_ready` before the player can physically outrun it under expected maximum movement speed.

## 15.2 New movement-aware priority

Runtime streaming priority must include:
- chunk ring distance
- screen-space relevance if available
- direction of player movement
- estimated time-to-arrival

### Example scoring idea

```text
priority = ring_weight + screen_weight + movement_weight + eta_weight + dirty_kind_weight
```

The exact formula may vary, but priority must be explicit and not implicit in insertion order alone.

## 15.3 Required behavior for near rings

### Ring 0
Player chunk.
Must get the highest priority always.

### Ring 1
Immediate neighbors.
Must receive first-pass publication before any far background convergence work.

### Ring 2
Near-visible extended bubble.
Must receive first-pass publication before far full redraw.

### Ring 3+
Background territory.
May wait for background convergence and must not starve ring 0–2.

---

# 16. Border / Seam Repair Redesign

## 16.1 Problem

Neighbor border updates currently exist but still compete with general redraw under starvation-prone conditions.

## 16.2 New task kind

Border and seam correction must become explicit `TASK_BORDER_FIX` work.

## 16.3 Priority rule

If a seam issue is visible or near-visible, border fix must outrank far full redraw.

## 16.4 Contract

A visible chunk may temporarily be in a first-pass approximate state, but visible seam defects caused by newly loaded neighbors must converge quickly.

---

# 17. New Scheduler Loop

The redraw system must be replaced by a time-budget loop that processes multiple tasks per tick.

Recommended shape:

```gdscript
func _tick_visuals() -> bool:
    var started_usec := Time.get_ticks_usec()
    var budget_usec := int(WorldGenerator.balance.visual_scheduler_budget_ms * 1000.0)

    while Time.get_ticks_usec() - started_usec < budget_usec:
        var task := _pop_next_visual_task()
        if task.is_empty():
            break

        var has_more := _process_visual_task(task, started_usec, budget_usec)
        if has_more:
            _requeue_visual_task(task)

    return _has_pending_visual_tasks()
```

And queue selection like:

```gdscript
func _pop_next_visual_task() -> Dictionary:
    if not _visual_q_terrain_urgent.is_empty():
        return _visual_q_terrain_urgent.pop_front()
    if not _visual_q_terrain_near.is_empty():
        return _visual_q_terrain_near.pop_front()
    if not _visual_q_full_near.is_empty():
        return _visual_q_full_near.pop_front()
    if not _visual_q_border_fix.is_empty():
        return _visual_q_border_fix.pop_front()
    if not _visual_q_full_far.is_empty():
        return _visual_q_full_far.pop_front()
    if not _visual_q_cosmetic.is_empty():
        return _visual_q_cosmetic.pop_front()
    return {}
```

## 17.1 Required behavior

The loop must not process one task and exit immediately while budget remains.

## 17.2 Required observability

Each tick must record:
- tasks processed
- budget exhaustion
- queue depths by class
- longest pending urgent task wait

---

# 18. File-By-File Implementation Plan

## 18.1 `core/systems/world/chunk_manager.gd`

This file is the primary orchestration target.

### Current responsibilities that must be reworked
- `_redrawing_chunks` as a single general redraw queue
- `_tick_redraws()` as the runtime visual scheduler
- boot special-case synchronous terrain completion
- staged chunk finalization behavior that immediately assumes progressive redraw will catch up in time

### Required structural changes

#### A. Replace `_redrawing_chunks`
Replace:
- `var _redrawing_chunks: Array[Chunk] = []`

With:
- explicit visual task queues
- explicit dedupe or task registration maps
- explicit invalidation/versioning for scheduled work

#### B. Add visual task registry helpers
Add helpers such as:
- `_enqueue_first_pass_task(...)`
- `_enqueue_full_redraw_task(...)`
- `_enqueue_border_fix_task(...)`
- `_enqueue_cosmetic_task(...)`
- `_has_pending_visual_tasks()`
- `_pop_next_visual_task()`
- `_requeue_visual_task(...)`
- `_compute_visual_priority(...)`

#### C. Replace `_tick_redraws()` with `_tick_visuals()`
`_tick_redraws()` should either:
- be removed and replaced
- or become a thin adapter that calls the new scheduler during migration

The new loop must:
- consume time budget, not just one task
- process multiple tasks while budget remains
- prefer urgent near work over far work
- expose telemetry

#### D. Boot path changes
In `boot_load_initial_chunks(...)` and boot helpers:
- remove dependence on `complete_terrain_phase_now()` from the critical path
- remove dependence on `warmup_tile_layers()` from the critical path
- redefine `first_playable` in terms of first-pass readiness
- hand off full redraw to runtime visual scheduling

#### E. Staged loading changes
In `_staged_loading_create()` and `_staged_loading_finalize()`:
- do not assume ordinary progressive redraw queueing is sufficient for near-visible correctness
- schedule explicit first-pass work for near chunks
- schedule deferred full redraw separately
- schedule border repair explicitly after finalization if neighbors require it

#### F. Add movement-aware prioritization
Use current player chunk and movement direction to score tasks.
A first version may use only:
- ring distance
- whether the chunk is ahead of motion

#### G. Add explicit near/far policies
Near visible chunks must move into urgent queues.
Far chunks must move into deferred queues.

#### H. Telemetry
Add metrics around:
- first-pass latency
- full redraw latency
- urgent queue wait
- per-tick task count
- starvation incidents

### Functions that must be revisited explicitly
- `_tick_redraws()`
- `_staged_loading_finalize()`
- `_boot_apply_from_queue()`
- `_boot_is_first_playable_slice_ready()`
- `_boot_process_redraw_budget()`
- `_boot_on_chunk_redraw_progress()`
- `_enqueue_neighbor_border_redraws()`
- `_process_chunk_redraws()`

### Migration note
The first implementation may temporarily keep legacy helpers around, but the single-queue redraw model must stop being the active authority.

---

## 18.2 `core/systems/world/chunk.gd`

This file is the primary chunk-local visual behavior target.

### Current responsibilities that must be reworked
- `complete_terrain_phase_now()` as a production boot tool
- `warmup_tile_layers()` as a production boot optimization strategy
- one progressive redraw state machine that assumes all visual work belongs to one pipeline

### Required structural changes

#### A. Add explicit visual state
Introduce `ChunkVisualState` and supporting query methods:
- `is_first_pass_ready()`
- `is_full_redraw_ready()`
- `needs_full_redraw()`

#### B. Split first-pass from full redraw
Add chunk-local methods such as:
- `apply_first_pass(payload: Dictionary) -> void`
- `continue_first_pass(tile_budget: int, time_budget_usec: int) -> bool`
- `continue_full_redraw(tile_budget: int, time_budget_usec: int) -> bool`
- `schedule_full_redraw(reason: StringName) -> void`

#### C. Keep full redraw as canonical convergence
The current `_redraw_all()` or a renamed equivalent should remain the canonical final visual builder.

It may be decomposed internally, but the semantic contract remains:
- this is the final correctness path

#### D. Demote current sync helpers
`complete_terrain_phase_now()` and `warmup_tile_layers()` must be demoted to:
- diagnostics
- forced fallback
- profiling support

They must not remain core production-path assumptions.

#### E. Reduce main-thread thinking over time
Prepare the chunk API to consume worker-side visual descriptors later.

That means the chunk should eventually support input like:
- precomputed terrain classes
- precomputed wall forms
- precomputed cheap first-pass descriptors

without needing to derive all of them interactively on the main thread.

#### F. Separate approximation from convergence
The first-pass implementation may be intentionally approximate.
The chunk must remember that approximation and schedule canonical convergence afterward.

### Functions that must be revisited explicitly
- `populate_native(...)`
- `_begin_progressive_redraw()`
- `continue_redraw(...)`
- `_process_redraw_phase_tiles(...)`
- `_advance_redraw_phase()`
- `complete_terrain_phase_now()`
- `warmup_tile_layers()`
- `_redraw_dirty_tiles(...)`
- `enqueue_dirty_border_redraw(...)`

### Migration note
A temporary compatibility layer is acceptable, but the long-term target is:
- first-pass path
- canonical full redraw path
- explicit invalidation model

---

## 18.3 `data/world/world_gen_balance.gd`

This script must be extended so the new visual scheduler has real exported knobs.

### Required additions
Add a new export group for chunk visual scheduling and convergence budgets.

Minimum first-pass fields:
- `visual_scheduler_budget_ms`
- `visual_first_pass_tiles_per_step`
- `visual_full_redraw_tiles_per_step`
- `visual_border_fix_tiles_per_step`
- `visual_cosmetic_tiles_per_step`
- `visual_first_pass_max_tasks_per_tick`
- `visual_full_redraw_max_tasks_per_tick`

### Required migration policy
Do not delete old redraw fields immediately.
Keep them temporarily if needed for compatibility during rollout.
But the new scheduler must stop being bottlenecked by the legacy fields alone.

---

## 18.4 `data/world/world_gen_balance.tres`

This resource must be updated with concrete defaults that favor urgent near chunk visibility.

### Recommended starting defaults
These are starting points, not final truth:

```text
visual_scheduler_budget_ms = 4.0
visual_first_pass_tiles_per_step = 256
visual_full_redraw_tiles_per_step = 192
visual_border_fix_tiles_per_step = 128
visual_cosmetic_tiles_per_step = 64
visual_first_pass_max_tasks_per_tick = 4
visual_full_redraw_max_tasks_per_tick = 6
```

### Required config intent
The configuration must clearly express:
- urgent terrain visibility gets more throughput than far cosmetic convergence
- border fixes are not starved behind general redraw
- the scheduler has enough per-tick room to process multiple tasks

---

## 18.5 `scenes/world/game_world.gd` or the boot/loading owner

The boot/loading orchestration layer must be updated to reflect the new gate semantics.

### Required changes
- progress display must distinguish `first playable` from `full convergence`
- loading screens must stop assuming final visual completeness before gameplay starts
- handoff to runtime must preserve pending full redraw tasks

### Required contract
The loading owner must understand:
- first-playable is achieved at first-pass readiness
- boot-complete is achieved at full convergence plus required support systems

---

## 18.6 Runtime validation / perf harness files

Any existing validation route or perf harness should be updated to test the new contracts explicitly.

Required validation scenarios:
- boot cold start
- sprinting across chunk boundaries
- oscillating movement near a boundary to stress urgent queue reuse
- mining or neighbor invalidation that creates border fix work
- save/load while full redraw work is pending

---

# 19. Detailed Boot Pipeline Specification

## 19.1 New boot sequence

1. Boot compute fills worker/native results.
2. Boot apply creates chunk nodes and publishes minimal state.
3. Near ring chunks schedule **first-pass tasks** immediately.
4. `first_playable` becomes true as soon as near ring chunks are first-pass ready.
5. Gameplay starts.
6. Runtime visual scheduler continues with:
   - remaining near first-pass debt
   - near full redraw
   - border fixes
   - far full redraw
   - cosmetics

## 19.2 Explicitly forbidden boot behavior

The boot loop must not stall waiting for:
- center chunk synchronous full redraw
- center chunk synchronous terrain completion as the default strategy
- full flora publication
- full canonical seam perfection on all startup chunks

## 19.3 Boot telemetry requirements

Log milestones for:
- first native ready
- first apply complete
- first-pass ready for ring 0
- first-playable reached
- all near startup chunks full-ready
- boot complete reached

---

# 20. Detailed Runtime Streaming Specification

## 20.1 Runtime chunk activation sequence

When a streaming result becomes ready:

1. Promote native result to staged state.
2. Create chunk node and populate gameplay/native bytes.
3. Publish minimal visibility-safe state.
4. Schedule `TASK_FIRST_PASS` for the chunk using near/far priority rules.
5. Schedule `TASK_FULL_REDRAW` separately.
6. Schedule `TASK_BORDER_FIX` if newly loaded neighbors need reconciliation.
7. Reveal the chunk as soon as the first-pass contract allows it.

## 20.2 Runtime movement guarantee

If the player is moving into unloaded/unfinished territory, the scheduler must prioritize chunks ahead of motion so the player does not catch placeholders.

## 20.3 Runtime convergence guarantee

Even after first-pass success, the scheduler must continue to converge nearby chunks to `VISUAL_FULL_READY` in a bounded amount of time.

---

# 21. Telemetry and Observability Specification

This rework must be observable or it will regress invisibly.

## 21.1 Boot metrics

Add metrics for:
- `boot.time_to_native_ready_ring0_ms`
- `boot.time_to_apply_ring0_ms`
- `boot.time_to_first_pass_ring0_ms`
- `boot.time_to_first_playable_ms`
- `boot.time_to_full_ready_ring0_ms`
- `boot.time_to_full_ready_ring1_ms`
- `boot.time_to_boot_complete_ms`

## 21.2 Runtime metrics

Add metrics for:
- `stream.chunk_compute_ms`
- `stream.chunk_apply_ms`
- `stream.chunk_first_pass_ms`
- `stream.chunk_full_redraw_ms`
- `stream.chunk_border_fix_ms`
- `stream.chunk_latency_to_visible_ms`
- `stream.chunk_latency_to_full_ready_ms`

## 21.3 Scheduler metrics

Add metrics for:
- `scheduler.visual_tasks_processed_per_tick`
- `scheduler.visual_budget_exhausted_count`
- `scheduler.urgent_queue_depth`
- `scheduler.near_queue_depth`
- `scheduler.full_far_queue_depth`
- `scheduler.max_urgent_wait_ms`
- `scheduler.starvation_incident_count`

## 21.4 Warning thresholds

Emit warnings when:
- an urgent first-pass task waits more than 100 ms before first execution
- a near-visible chunk waits more than 250 ms to become first-pass ready
- a near-visible chunk waits more than 1000 ms to become full-ready
- urgent queue depth remains above threshold across multiple frames

---

# 22. Acceptance Criteria

The plan is only successful when all of the following are true.

## 22.1 Functional criteria

1. The player no longer sees green or placeholder chunks in the near-visible bubble under normal movement.
2. The player cannot reliably outrun near-chunk visual readiness.
3. Boot no longer depends on a synchronous center-chunk terrain/full redraw to become playable.
4. Full redraw still exists and still converges chunks to final canonical state.
5. Visible seam issues caused by newly loaded neighbors resolve quickly.

## 22.2 Performance targets

Initial targets:
- `boot first_playable < 2.5s`
- `center chunk first_pass < 120ms`
- `ring0-1 first_pass all ready < 300ms after apply`
- `visible chunk placeholder lifetime <= 1 frame in ordinary streaming`
- `near chunk full convergence < 1.5s background`
- `ordinary streaming path produces no single visual spike > 16ms`

These are initial rollout targets and may be tuned after instrumentation exists.

## 22.3 Regression criteria

The rework is considered failed if any of the following remain true:
- a near-visible chunk can stay green/blank for many frames
- urgent tasks are starved by far tasks
- the project reintroduces sync full redraw into the first-playable gate
- full redraw is removed entirely and the game never reaches canonical visual correctness

---

# 23. Rollout Phases

This must be delivered as staged work, not one code dump.

## Phase V0: Instrumentation Baseline

Goal:
- capture current boot, streaming, and redraw latency clearly

Deliverables:
- metrics and warnings
- queue depth telemetry
- chunk latency telemetry

Definition of done:
- the team can measure current urgent wait and chunk readiness latency before changing architecture

## Phase V1: Scheduler Surgery

Goal:
- replace one-queue one-chunk-per-tick redraw with priority budget scheduling

Deliverables:
- explicit visual task queues
- `_tick_visuals()`
- urgent vs far separation
- border fix queue

Definition of done:
- multiple tasks are processed per tick while budget remains
- urgent queue no longer starves behind far work

## Phase V2: First-Pass Separation

Goal:
- introduce first-pass visual readiness as a distinct contract

Deliverables:
- `ChunkVisualState`
- first-pass task kind
- first-pass readiness queries
- boot first-playable based on first-pass

Definition of done:
- near chunks can become visibly valid before full convergence

## Phase V3: Full Redraw Return As Canonical Convergence

Goal:
- reintroduce full redraw as the final canonical visual path

Deliverables:
- full redraw task kind
- invalidation rules for full convergence
- near/far convergence policy

Definition of done:
- chunks converge to final correctness without blocking gameplay start

## Phase V4: Worker-Side Visual Descriptor Migration

Goal:
- reduce main-thread visual thinking

Deliverables:
- optional precomputed terrain/visual descriptors from worker/native side
- reduced main-thread neighbor classification cost

Definition of done:
- main thread increasingly commits rather than derives visual structure

## Phase V5: Optional Proxy Pass

Goal:
- add a true proxy representation only if cheap terrain publish remains too expensive

Deliverables:
- optional proxy layer or coarse chunk texture

Definition of done:
- project has a fallback path if even first-pass terrain is too costly

---

# 24. Risks

## 24.1 Risk: first-pass becomes too approximate

Mitigation:
- full redraw remains canonical and mandatory
- near-visible chunks still receive fast convergence after first-pass

## 24.2 Risk: too many queues make scheduling bug-prone

Mitigation:
- centralize task registration and dedupe
- add queue-depth telemetry and starvation warnings

## 24.3 Risk: compatibility break during migration

Mitigation:
- allow temporary compatibility adapters
- keep legacy redraw internals behind a new scheduler before deleting them

## 24.4 Risk: worker-side visual descriptor work is delayed

Mitigation:
- the scheduler and first-pass separation already provide value before worker precompute lands

---

# 25. Open Questions

1. Should the first-pass publish directly into the existing TileMap layers, or should a temporary proxy layer be introduced sooner?
2. Which terrain visual decisions can safely move to worker/native precomputation first?
3. Should border fix remain its own queue permanently, or later merge into full redraw once descriptor precompute exists?
4. Should chunk screen-space scoring be added immediately, or should ring + movement direction be the first shipped heuristic?

---

# 26. Definition Of Done

This rework is only done when:
- first-playable no longer relies on blocking sync chunk visual bake
- near-visible chunks become visibly valid fast enough that the player cannot catch placeholders
- the redraw scheduler is priority-based and budget-driven, not one-queue round-robin
- border/seam repair is explicit and not starved by far convergence work
- full redraw exists as the canonical final convergence path
- chunks reliably reach `VISUAL_FULL_READY`
- the system is instrumented well enough to catch future regressions immediately

---

# 27. Immediate Implementation Recommendation

The first implementation slice should be:

1. add telemetry
2. replace `_tick_redraws()` with a priority budget scheduler
3. introduce first-pass readiness for near chunks
4. remove `complete_terrain_phase_now()` and `warmup_tile_layers()` from the boot critical path
5. reintroduce full redraw as deferred canonical convergence

This order gives the highest chance of eliminating green chunk starvation quickly without losing the ability to converge to final visual quality.
