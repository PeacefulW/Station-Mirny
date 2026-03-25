---
title: ADR-0001 Runtime Work and Dirty Update Foundation
doc_type: adr
status: approved
owner: engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../02_system_specs/base/building_and_rooms.md
  - ../02_system_specs/base/engineering_networks.md
  - ../04_execution/MASTER_ROADMAP.md
---

# ADR-0001 Runtime Work and Dirty Update Foundation

## Context

The current base/world foundation already contains:
- a shared `FrameBudgetDispatcher` path for streaming/topology/visual work
- synchronous building room recalculation on every place/remove/destroy/load
- synchronous full power balance recalculation on building mutations and timer ticks
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

The following hazards are present in the current code and must guide the next iterations.

### Hazard A: full room recomputation in interactive building path

`BuildingSystem` currently calls `_recalculate_indoor()` after:
- load
- place
- remove
- destroy

`IndoorSolver.recalculate()` performs a full bounded flood-fill across the current wall extents, not a local dirty patch.

Implication:
- building hot paths already violate the runtime direction in `building_and_rooms.md` and `PERFORMANCE_CONTRACTS.md`

### Hazard B: global power scan in interactive and periodic paths

`PowerSystem` currently:
- reacts to `building_placed` and `building_removed` with `force_recalculate()`
- scans all `power_sources`
- scans all `power_consumers`
- applies brownout decisions synchronously

Implication:
- the baseline strategy is still a full-tree/group scan, not dirty partition invalidation

### Hazard C: load path still reuses runtime sync room rebuild

`SaveAppliers.apply_buildings()` may still call `_recalculate_indoor()` directly after restore.

Implication:
- load correctness currently depends on the same synchronous room rebuild path that is used for interactive mutations
- this must be separated conceptually into boot/load work vs interactive work

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

## Consequences

Expected code direction for the next iterations:
- add shared runtime work seams without inventing a large framework
- convert room work first to dirty/bounded processing
- convert power work next to dirty/bounded processing
- preserve save/load truth while keeping derived caches and queues transient

## Status Rationale

This ADR is approved because it does not invent new gameplay behavior.
It records the runtime law already implied by governance docs and applies it explicitly to the current base/world refactor series.
