---
title: ADR-0001 Runtime Work and Dirty Update Foundation
doc_type: adr
status: approved
owner: engineering
source_of_truth: true
version: 2.4
last_updated: 2026-03-26
related_docs:
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../02_system_specs/base/building_and_rooms.md
  - ../02_system_specs/base/engineering_networks.md
  - ../04_execution/MASTER_ROADMAP.md
  - ../04_execution/runtime_integrity_gap_closure_plan.md
---

# ADR-0001 Runtime Work and Dirty Update Foundation

## Context

The current base/world foundation already contains:
- a shared `FrameBudgetDispatcher` path for streaming/topology/visual work
- boot/load full room recalculation plus runtime dirty-region room recompute for place/remove/destroy
- registry-global power recompute on explicit registration/dirty mark plus heartbeat safety net
- boot-time chunk loading under a loading screen

This refactor series needs one canonical contract for what work is allowed in the interactive path and what must move into dirty/budgeted processing.

## Decision

The series uses four runtime work classes.

### 1. Interactive work

Interactive work is the synchronous response to player input.

Allowed:
- mutate one local building/tile/object
- update immediate local state needed for feedback
- mark local dirty regions or dirty networks
- enqueue deferred work
- emit domain events

Forbidden:
- full room rebuild
- full power/network scan
- full loaded-world sweep
- full chunk redraw
- full topology rebuild
- mass scene-tree mutation

### 2. Background work

Background work runs during normal play only through shared budgeted processing.

Required shape:
- `event -> dirty mark -> queued work -> bounded per-frame processing -> completion`

This is the target class for:
- room recomputation beyond a small local patch
- power/network recomputation beyond a local partition
- topology/cache maintenance caused by runtime mutations

### 3. Compute/apply split

When derived work is too heavy for one local synchronous step, it must separate into:
- compute/prep of derived result
- bounded apply on the main thread

Apply remains main-thread-sensitive and must stay budgeted or tightly local.

### 4. Boot/load work

Boot/load work may be more expensive, but it is not interactive work.

Allowed here:
- initial chunk bubble load
- initial topology build
- restore and wider rebuilds needed after load

Rule:
- expensive rebuilds required for correctness on load must stay explicitly classified as boot/load work and must not leak into normal place/remove hot paths

## Local Dirty Update Contract

The following operations must use local dirty updates or dirty invalidation rather than full synchronous rebuilds:
- building placement
- building removal
- building destruction
- room closure/opening consequences
- room-scoped engineering link changes
- power source/power consumer placement or removal
- local terrain mutation hooks that affect derived caches

Dirty units for this series:
- `dirty region` for building/room effects
- `dirty network` or `dirty partition` for power/engineering effects

## Current Hot Paths

The current code paths that define scope for this series are:

1. Building placement/removal/destruction
- `core/systems/building/building_system.gd`
- `place_selected_building_at`
- `remove_building_at`
- `_on_building_destroyed`

2. Room recalculation
- `core/systems/building/building_system.gd`
- `_recalculate_indoor`
- `core/systems/building/building_indoor_solver.gd`
- `recalculate`

3. Power recalculation
- `core/systems/power/power_system.gd`
- `_power_recompute_tick`
- `register_source` / `register_consumer`
- `force_recalculate`
- `_recalculate_balance`

4. Boot chunk loading
- `scenes/world/game_world.gd`
- `_start_boot_sequence`
- `_run_boot_sequence`
- `core/systems/world/chunk_manager.gd`
- `boot_load_initial_chunks`

5. Local terrain mutation hooks
- `core/systems/world/chunk_manager.gd`
- `try_harvest_at_world`
- `_on_mountain_tile_changed`
- `scenes/world/game_world.gd`
- `_debug_toggle_rock`

## Current Main-Thread Hazards

The following hazards were present in the baseline code and still guide the remaining iterations. The status table below tracks what remains current versus resolved.

### Hazard A: runtime room recompute originally stayed a queued full flood-fill

`BuildingSystem` interactive path now marks dirty regions for:
- place
- remove
- destroy

Runtime room recompute now uses staged local proof regions and bounded `IndoorSolver.solve_local_patch()` expansion.

Boot/load still uses full `IndoorSolver.recalculate(walls)` behind the loading screen, and runtime keeps an explicit oversized fallback if local proof bounds are exhausted.

Implication:
- ordinary runtime building no longer defaults to queued full flood-fill across all wall extents
- live telemetry now shows the oversized path as staged/bounded rather than a recurring runtime spike source
- Hazard A is resolved for ordinary runtime contract closure; boot/load broad rebuild remains separately classified

### Hazard B: global power scan in interactive and periodic paths

`PowerSystem` currently:
- reacts to `building_placed` and `building_removed` with `force_recalculate()`
- scans all `power_sources`
- scans all `power_consumers`
- applies brownout decisions synchronously

Implication:
- the baseline strategy is still a full-tree/group scan, not dirty partition invalidation

### Hazard C: load path must stay conceptually separate from runtime room patching

`BuildingSystem.load_state()` now owns the room rebuild on restore and keeps it explicitly in boot/load classification.

Implication:
- load correctness no longer reuses the ordinary runtime dirty-region path
- sync rebuild remains acceptable only behind the loading screen or equivalent boot/load boundary

### Hazard D: `GameWorld` still owns broad orchestration

`GameWorld` currently mixes:
- boot orchestration
- runtime system setup
- debug terrain mutation hook
- UI composition
- spawn orchestration

Implication:
- ownership of runtime-sensitive work remains diffuse, making hot-path reasoning harder

### Hazard E: main-thread-heavy operations already exist and must stay out of local build/power actions

The codebase contains known expensive operations such as:
- `TileMapLayer.clear()`
- repeated `set_cell()`
- `add_child()`
- `queue_free()`

These are acceptable only when tightly local or explicitly classified as boot/background/apply work.

## Series Contract

For the remainder of this refactor series:

1. Building mutations must stay interactive only for local immediate result.
2. Room consequences must move to dirty-region or bounded recomputation.
3. Power consequences must move to dirty-network or dirty-partition recomputation.
4. Shared deferred work must go through `FrameBudgetDispatcher` rather than per-system ad-hoc loops.
5. Boot/load rebuilds may stay broader, but they must remain classified as boot/load work.
6. Performance instrumentation must distinguish interactive cost from deferred/background cost.

## Accepted Shared Runtime Seam

The accepted minimal shared seam for this series is:
- `FrameBudgetDispatcher` as the single autoload entry point for budgeted per-frame work
- `RuntimeBudgetJob` as the explicit registration contract for deferred jobs
- `RuntimeWorkTypes` as the shared work classification vocabulary
- `RuntimeDirtyQueue` as the shared enqueue/de-dupe helper for dirty-driven systems

Rules:
- systems may keep their own internal dirty state, but registration and budget consumption should go through the shared dispatcher
- jobs must declare category, budget, cadence class, and threading/apply role explicitly
- the seam is intentionally small and must not grow into a large generic job framework without real consumers
- dispatcher budgeting only happens between `tick()` calls, so each consumer must expose a genuinely small bounded internal step
- a monolithic runtime path is not acceptable as the default consumer for this seam, even if it has instrumentation around it

## Consequences

Expected code direction for the next iterations:
- add shared runtime work seams without inventing a large framework
- convert room work first to dirty/bounded processing
- convert power work next to dirty/bounded processing
- preserve save/load truth while keeping derived caches and queues transient
- keep boot-only heavy paths explicitly separate from runtime background paths
- keep native or optimized rebuild paths opt-in for runtime only after they obey the same bounded-step contract

## Implementation Status

Tracks which hazards and contract items have been addressed by completed iterations.

### Hazard Resolution

| Hazard | Description                                    | Status   | Iteration |
|--------|------------------------------------------------|----------|-----------|
| A      | Full room recomputation in interactive path    | RESOLVED | G5        |
| B      | Global power scan in interactive/periodic path | PARTIAL  | 3         |
| C      | Load path reuses runtime sync room rebuild     | RESOLVED | 2         |
| D      | GameWorld broad orchestration                  | RESOLVED | 5         |
| E      | Main-thread-heavy ops in local actions         | ACCEPTED | —         |

### Iteration 6 — Save/Load Audit + Series Closure (2026-03-26)

**Save/load audit result: UPDATED, not full series closure.** No transient runtime state leaks into serialized save payload:
- `BuildingSystem._dirty_queue`, `_room_job_id` — not serialized, not referenced by save_state()
- `PowerSystem._is_dirty`, `_power_job_id`, `_heartbeat_timer`, `_was_deficit` — not serialized
- `BuildingPersistence` serializes only: grid position, building_id, health, node state
- `PowerSystem.save_state()` serializes only: supply, demand, deficit
- In-game load entry now routes through scene reload / boot path instead of in-place live-world mutation
- Chunk diff save sync now reconciles stale `chunks/*.json` files, including the empty-diff case
- Dirty queues and dispatcher jobs re-initialize in `_ready()` after load

Remaining gaps:
- `BuildingSystem` runtime room recompute now uses local proof regions, and the oversized fallback has been converted to staged bounded slices; it remains a safety net, not a live closure blocker
- `PowerSystem` now uses explicit registries, but still remains registry-global instead of a real dirty-network/partition model
- direct combat damage still bypasses a formal command boundary

**Hazard E status: ACCEPTED.** Main-thread-heavy operations (TileMapLayer.clear(), mass set_cell(), add_child(), queue_free()) are architectural constraints of Godot's scene tree. The refactor series keeps them out of local interactive building/power actions, but this does not by itself close Hazards A or B.

**Series not complete.** Building/power contract closure remains open and is now tracked by `docs/04_execution/runtime_integrity_gap_closure_plan.md`.

### Gap Closure G3 - Local Room Patch (2026-03-26)

- `BuildingSystem` runtime path no longer clears dirty state and wholesale-replaces `indoor_cells` on every room job tick
- room invalidation now queues merged `dirty region` entries carrying footprint, proof bounds, and reason metadata
- `IndoorSolver.solve_local_patch()` computes bounded local add/remove diffs inside a proof region instead of defaulting to full flood-fill
- proof regions expand in staged background steps until the local patch is proven or an explicit oversized fallback is reached
- boot/load remains on sync `recalculate()` behind the loading screen
- headless validation now includes a scripted room case: build closed room -> breach wall -> reclose -> destroy wall
### Iteration 5 Changes (2026-03-26)

- `GameWorld` decomposed: debug overlay extracted to `GameWorldDebug` (FPS, tile highlight, rock toggle, validation driver), spawn logic extracted to `SpawnOrchestrator` (enemy spawning, item drops, pickup collection)
- `GameWorld._process()` now only calls `_update_player_indoor_status()` — no debug or spawn updates
- `GameWorld` no longer owns enemy count, spawn timer, pickup factory, or debug visualization
- New files: `scenes/world/game_world_debug.gd`, `scenes/world/spawn_orchestrator.gd`
- Debug code can be disabled for release by not creating `GameWorldDebug` node

### Iteration 4 Changes (2026-03-26)

- `BuildingSystem` interactive path (place/remove/destroy) instrumented with `WorldPerfProbe.begin()/end()` and contract checks (< 2ms)
- `WorldPerfProbe._CONTRACTS` extended with `BuildingSystem.place_building`, `remove_building`, `destroy_building` at 2.0ms limit
- `WorldPerfMonitor._categorize()` now splits "building" and "power" from generic "topology" — labels from `FrameBudgetDispatcher.topology.building.*` and `BuildingSystem.*` go to "building"; `FrameBudgetDispatcher.topology.power.*` goes to "power"
- 300-frame summary now shows `building=X.Xms power=X.Xms` alongside streaming/topology/visual/spawn
- Interactive vs deferred cost now distinguishable: interactive building ops appear in WorldPerfProbe immediate logs; deferred room/power recompute appears in FrameBudgetDispatcher per-job stats

### Gap Closure G4 - Power Registry De-globalization (2026-03-26)

- `PowerSystem` no longer pulls authoritative sources/consumers through `get_nodes_in_group(...)` during runtime recompute
- `PowerSourceComponent` and `PowerConsumerComponent` now register/unregister explicitly with `PowerSystem`
- source output changes and consumer configuration changes now dirty the power job through registry-connected signals
- runtime balance recompute uses registry snapshots only; scene-tree groups remain only for UI/debug compatibility
- headless validation now includes a scripted power case: place battery -> verify source registration and life-support power -> remove battery -> verify baseline restore

### Gap Closure G5 - Revalidation and Truthful Closure (2026-03-26)

- current headless `codex_validate_runtime` passes room, power, and mining+persistence validation without new parse/runtime errors
- a fresh post-fix live gameplay log no longer shows standalone `building.room_recompute` offenders; summaries keep `building.room_recompute=0.0ms`, and late-session dispatcher summaries settle around `total=3.4ms/6.0ms`
- Hazard A is therefore promoted to `RESOLVED` for ordinary runtime contract closure
- `power.balance_recompute` no longer appears as a meaningful runtime offender, but Hazard B remains `PARTIAL` because power is still registry-global rather than dirty-network or partition-local
- save/load integrity holes fixed in `G0/G1` remain code-closed, but a fresh manual GUI save/load session on the current build remains explicit residual backlog
- direct combat damage and headless `topology catch-up timeout` remain outside closure and stay documented as backlog, not hidden under optimistic wording

### Iteration 3 Changes (2026-03-26)

- `PowerSystem` interactive path (`building_placed`/`building_removed` signals) now calls `_mark_power_dirty()` instead of `force_recalculate()`
- Power recomputation runs as a TOPOLOGY budget job (`power.balance_recompute`, 1.0ms) through `FrameBudgetDispatcher`
- Removed 1s periodic timer full scan; replaced with 5s heartbeat safety net (marks dirty, actual work done by dispatcher)
- `force_recalculate()` retained as public boot/load entry point
- Brownout priority sort stays in deferred tick (cheap at current scale)
- `_is_dirty` flag initialized to `true` so first tick after boot computes initial state
- Note: this iteration introduced deferred scheduling; the explicit registry lifecycle later arrived in gap-closure iteration `G4`, while partition-local power work still remains open

### Iteration 2 Changes (2026-03-26)

- `BuildingSystem` interactive path (place/remove/destroy) now marks dirty region via `RuntimeDirtyQueue` instead of calling `IndoorSolver.recalculate()` synchronously
- Room recomputation runs as a TOPOLOGY budget job (`building.room_recompute`, 1.5ms) through `FrameBudgetDispatcher`
- Load path explicitly classified as boot work — direct sync `recalculate()` behind loading screen
- `SaveAppliers` legacy fallback `_recalculate_indoor()` call removed (dead code; primary path uses `BuildingSystem.load_state()`)
- Note: this iteration removed interactive sync rebuild; the genuinely local bounded room patch arrived later in gap-closure iteration `G3`

## Status Rationale

This ADR is approved because it does not invent new gameplay behavior.
It records the runtime law already implied by governance docs and applies it explicitly to the current base/world refactor series.

**v2.5**: Save/load integrity, excavation command closure, staged room patching, and explicit power registration are in place. A fresh live gameplay log no longer shows standalone `building.room_recompute` spikes, so Hazard A is now resolved for ordinary runtime contract closure. Hazard B remains PARTIAL because power is still registry-global rather than dirty-network or partition-local. Save/load code holes are closed, but fresh GUI save/load revalidation remains explicit backlog. Follow-up execution is tracked in `docs/04_execution/runtime_integrity_gap_closure_plan.md`.
