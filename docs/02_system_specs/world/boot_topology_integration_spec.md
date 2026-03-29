---
title: Boot Topology Integration Spec
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
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
---

# Feature: Boot Topology Integration

## Design Intent

Boot topology must remain correct, but topology must not be optimized or scheduled in a way that reintroduces the same boot bottleneck from a different angle.

This spec defines when topology becomes mandatory relative to first-playable and boot-complete, and how it integrates with the staged boot pipeline.

## Public API impact

Current public APIs affected semantically:
- `ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`
- `ChunkManager.is_topology_ready() -> bool`
- `ChunkManager.get_mountain_key_at_tile(tile_pos: Vector2i) -> Vector2i`
- `ChunkManager.get_mountain_tiles(mountain_key: Vector2i) -> Dictionary`
- `ChunkManager.get_mountain_open_tiles(mountain_key: Vector2i) -> Dictionary`

Required API/documentation outcome after implementation:
- `PUBLIC_API.md` must document whether first-playable requires topology-ready or only boot-complete does.
- No caller outside `ChunkManager` may decide topology scheduling order.
- Any new read-only topology boot-state query must be documented in `PUBLIC_API.md`.

## Data Contracts — new and affected

### Affected layer: Topology
- What changes:
  - boot topology now has an explicit relation to `first_playable` and `boot_complete`.
- New invariants:
  - topology work must not begin before the minimum required chunk set exists for the chosen gate.
  - topology-ready semantics must be explicit, not inferred from legacy synchronous boot behavior.
  - native and scripted topology builders must respect the same boot gate contract.
- Who adapts:
  - `ChunkManager`
- What does NOT change:
  - topology remains derived state
  - topology ownership remains inside `ChunkManager`

### Affected layer: Chunk Lifecycle
- What changes:
  - lifecycle gains a topology integration phase after required chunk apply.
- New invariants:
  - `first_playable` and `boot_complete` may not silently collapse into one gate because of topology.
- Who adapts:
  - `ChunkManager`
- What does NOT change:
  - chunk registration order is still handled by lifecycle/apply specs

### Affected layer: Reveal
- What changes:
  - any system depending on topology must be aware of the chosen topology-ready gate.
- New invariants:
  - reveal-dependent systems must not assume topology is ready earlier than the spec says.
- Who adapts:
  - `ChunkManager`
  - only if needed later: `core/systems/world/mountain_roof_system.gd`
- What does NOT change:
  - reveal remains a derived layer

## Required topology gate policy

Initial required policy:
- `first_playable` does not require full startup-bubble topology by default
- required near-player gameplay must define explicitly whether ring-0/ring-1 topology is needed before first-playable
- `boot_complete` requires topology-ready for the startup bubble
- native and scripted topology backends must expose the same gate semantics

Default recommendation for iteration 1:
- near-player chunk apply first
- topology begins only after the required first-playable chunk set is applied
- full startup-bubble topology readiness remains part of boot-complete, not first-playable

## Iterations

### Iteration 1 — Separate topology gate from legacy full boot gate ✅
Goal: make topology timing explicit instead of inherited from the old synchronous boot path.

What is done:
- `first_playable` explicitly does NOT require topology: `_boot_first_playable = player_chunk_visual_complete and playable_ring_applied` — no `_boot_topology_ready` in formula
- `boot_complete` explicitly requires topology: `_boot_complete_flag = all_chunks_terminal and _boot_topology_ready`
- topology builds incrementally via `_tick_topology()` (FrameBudgetDispatcher, 2ms budget) after first_playable — no synchronous `ensure_built()` in post-first-playable path
- `_tick_boot_remaining()` polls `is_topology_ready()` to set `_boot_topology_ready` once FrameBudgetDispatcher finishes
- DATA_CONTRACTS.md contains explicit invariants: `first_playable does not require topology_ready`, `not boot_complete or topology_ready`

Acceptance tests:
- [x] `assert(first_playable_topology_requirement_is_explicit)` — `_boot_update_gates()` line comment: "Topology NOT required". Formula: `player_chunk_visual_complete and playable_ring_applied` — no topology term. DATA_CONTRACTS invariant documents this.
- [x] `assert(boot_complete_topology_requirement_is_explicit)` — `_boot_complete_flag = all_chunks_terminal and _boot_topology_ready`. DATA_CONTRACTS invariant: `not boot_complete or topology_ready`.
- [x] manual: topology does not block first-playable. After first_playable, topology processes incrementally via FrameBudgetDispatcher. `_tick_boot_remaining()` polls completion.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/systems/world/chunk.gd`
- `core/autoloads/world_generator.gd`
- `scenes/world/game_world.gd`

### Iteration 2 — Re-stage topology after required apply readiness ✅
Goal: ensure topology starts at the right point in the staged boot pipeline.

What is done:
- topology blocked during boot loop: `_tick_topology()` has `if _is_boot_in_progress: return false`
- after first_playable (ring 0..1 applied), boot loop exits → `_is_boot_in_progress = false`
- native topology: `_native_topology_dirty and _is_streaming_generation_idle()` — waits for streaming to finish before building
- scripted topology: `_is_topology_dirty and not _has_streaming_work()` — same idle gate
- each chunk load sets dirty flag (`_native_topology_dirty = true` / `_mark_topology_dirty()`) — topology rebuilds once streaming drains
- after pipeline drain (Patch B), outer chunks load via runtime streaming → topology waits for all streaming to complete before starting

Acceptance tests:
- [x] `assert(topology_does_not_start_before_required_chunks_are_applied)` — `_is_boot_in_progress` guard blocks during boot loop. After exit, streaming idle gate prevents premature build. Topology only fires when load queue empty + no staged chunk.
- [x] `assert(native_and_scripted_topology_follow_same_gate)` — native: `_is_boot_in_progress` + `_is_streaming_generation_idle()`. Scripted: `_is_boot_in_progress` + `not _has_streaming_work()`. Both blocked during boot, both wait for streaming idle.
- [x] manual: topology does not run during boot loop. After first_playable, topology waits for streaming to drain before building. No wasted topology work on incomplete chunk set.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/systems/world/chunk.gd`
- `core/autoloads/frame_budget_dispatcher.gd`
- `scenes/world/game_world.gd`

### Iteration 3 — Protect dependent systems from premature topology assumptions
Goal: make later systems safe when topology becomes staged during boot.

What is done:
- audit current topology-ready checks in world boot path
- update any boot-critical dependent system assumptions if required
- keep the surface reveal/roof path aligned with the new topology gate

Acceptance tests:
- [ ] `assert(boot_critical_dependents_do_not_assume_legacy_topology_timing)` — no hidden dependency remains.
- [ ] manual: reveal/roof behavior after first-playable remains stable even if full topology completes later.
- [ ] manual: topology-dependent reads remain guarded by `is_topology_ready()` or equivalent gate.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/mountain_roof_system.gd`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_content_builder.gd`

## Required contract and API updates after implementation

When this spec is implemented, update:
- `DATA_CONTRACTS.md`
  - topology readiness semantics during boot
  - any reveal dependency notes that rely on topology timing
- `PUBLIC_API.md`
  - `boot_load_initial_chunks()` semantics
  - `is_topology_ready()` semantics during staged boot

## Out-of-scope

- worker compute queue
- main-thread apply budget
- redraw phase deferral
- flora deferral policy
- performance log schema beyond topology-specific timings

Those belong to the adjacent boot specs.
