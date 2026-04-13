---
title: Boot Chunk Readiness Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.3
last_updated: 2026-04-13
depends_on:
  - chunk_boot_streaming_rollout.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
related_docs:
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../../04_execution/chunk_boot_streaming_rollout.md
---

# Feature: Boot Chunk Readiness

## Legacy Status

This spec documents a legacy boot-readiness rollout for the hybrid chunk runtime.

It is not the active architecture target for player-reachable chunk readiness. Active target selection now lives in:

- `zero_tolerance_chunk_readiness_spec.md`
- `frontier_native_runtime_architecture_spec.md`
- `../../04_execution/frontier_native_runtime_execution_plan.md`

Any rule below that permits player handoff before final seamless `full_ready` traversal must be treated as superseded by the frontier-native runtime stack.

## Design Intent

Boot must stop meaning "every startup chunk is fully finished the old synchronous way".

Boot must instead define a strict, player-facing readiness contract:
- what must be ready before control is allowed
- what may still be computing or drawing
- which startup chunk rings are critical
- what counts as first playable versus full startup completion

This spec exists so implementation work does not optimize blindly or reintroduce hidden full-bubble completion requirements.

`first_playable` is not just an internal `ChunkManager` flag — it is the product moment when `GameWorld` hands control to the player: input and physics are enabled, the blocking loading screen is dismissed, and time is unpaused. All remaining boot work (outer chunks, topology, shadows) completes in background via `_tick_boot_remaining()` and `GameWorld._tick_boot_finalization()` without re-blocking the player.

## Public API impact

Current public APIs that are affected semantically:
- `ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`
- `ChunkManager.is_topology_ready() -> bool`
- `Chunk.is_redraw_complete() -> bool`

Required API/documentation outcome after implementation:
- `PUBLIC_API.md` must update the semantics of `ChunkManager.boot_load_initial_chunks()` to reflect first-playable readiness instead of legacy full synchronous completion.
- If a new read-only boot snapshot API is added, it must be documented in `PUBLIC_API.md` before agents use it.
- No direct new write API may be added for chunk readiness outside `ChunkManager` ownership.

## Data Contracts — new and affected

### New layer: Boot Readiness State
- What: explicit startup-readiness state for the initial boot bubble.
- Where: `core/systems/world/chunk_manager.gd` (`_boot_*` state section).
- Owner (WRITE): `ChunkManager`.
- Readers (READ): `scenes/world/game_world.gd`, boot progress UI, instrumentation.
- Invariants:
  - `first_playable == true` implies player chunk is applied and visually complete.
  - `first_playable == true` implies the defined near-player gameplay ring is applied.
  - `boot_complete == true` implies all startup chunks reached the terminal boot state defined by this spec.
  - No chunk may be marked `visual_complete` before it is `applied`.
- Event after change: none required in iteration 1; polling via owner is acceptable.
- Forbidden:
  - writing readiness state from UI or scene code
  - inferring readiness from `_load_queue.is_empty()` alone
  - treating topology-ready as identical to first-playable by default

### Affected layer: Chunk Lifecycle
- What changes:
  - boot lifecycle gains explicit readiness states separate from raw load completion.
  - `GameWorld` uses `first_playable` as the product handoff point: enables player input/physics, dismisses blocking loading screen, unpauses time. Shadows and remaining boot work complete in background via `_tick_boot_finalization()`.
  - Ring distance uses Chebyshev metric so diagonal chunks are ring 1, not ring 2.
- New invariants:
  - startup chunk state must distinguish at least `computed`, `applied`, and `visual_complete`.
  - `first_playable` implies player can move and interact; no re-blocking after this point.
  - diagonal chunks visible from a 4-chunk junction must be ready at `first_playable`.
- Who adapts:
  - `ChunkManager`
  - `scenes/world/game_world.gd`
- What does NOT change:
  - chunk ownership remains with `ChunkManager`
  - runtime streaming ownership does not move into UI

### Affected layer: Presentation
- What changes:
  - first-playable no longer implies full visual completion for the whole startup bubble.
- New invariants:
  - ring-0 visual completeness is mandatory before first-playable.
  - farther rings may remain progressive until post-playable completion.
- Who adapts:
  - `ChunkManager`
  - `Chunk`
- What does NOT change:
  - `Chunk` remains the owner of redraw phase progression

### Affected layer: Topology
- What changes:
  - topology readiness is explicitly decoupled from first-playable unless a dependent gameplay rule says otherwise.
- New invariants:
  - topology must not silently block first-playable unless this spec says it is part of the gate.
- Who adapts:
  - `ChunkManager`
- What does NOT change:
  - topology remains derived state owned by `ChunkManager`

## Readiness model

The startup bubble must use these boot states per chunk:
- `queued_compute`
- `computed`
- `queued_apply`
- `applied`
- `visual_complete`

The boot process must expose these aggregate gates:
- `first_playable`
- `boot_complete`

Ring distance metric: **Chebyshev** (`max(abs(dx), abs(dy))`), not Manhattan. This ensures diagonal chunks at offset (1,1) are ring 1, covering the case where the player/camera straddles a 4-chunk junction.

Recommended ring policy:
- ring 0: player chunk only, mandatory for first-playable. Full redraw (terrain + cover + cliff) at apply time.
- ring 1: immediate movement and readability ring (including diagonals), mandatory for first-playable. Terrain-only immediate redraw at apply time via `complete_terrain_phase_now()` — eliminates green placeholder zones. Cover/cliff/flora complete via progressive redraw.
- outer startup rings: mandatory for boot-complete, not mandatory for first-playable. Pure progressive redraw.

## Iterations

### Iteration 1 — Introduce explicit readiness state model
Goal: replace implicit boot assumptions with explicit state tracking.

What is done:
- add owner-managed boot chunk state tracking to `ChunkManager`
- define terminal state transitions for startup chunks
- define aggregate flags for `first_playable` and `boot_complete`
- expose a read-only boot snapshot API only if needed by `GameWorld`

Acceptance tests:
- [ ] `assert(chunk_state != visual_complete or chunk_state_was_applied_first)` — visual completion never precedes apply.
- [ ] `assert(not first_playable or player_chunk_visual_complete)` — player chunk visual readiness is part of the gate.
- [ ] `assert(not boot_complete or all_startup_chunks_terminal)` — boot complete only after full startup bubble reaches terminal state.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `scenes/world/game_world.gd`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/chunk.gd`

### Iteration 2 — Define first-playable and boot-complete gates
Goal: make boot completion criteria player-facing and enforceable.

What is done:
- codify ring-0 and ring-1 requirements
- codify what topology means for first-playable versus boot-complete
- update boot progress logic to report the correct gate

Acceptance tests:
- [ ] manual: boot does not wait for the whole startup bubble to become visually complete before reporting first-playable.
- [ ] `assert(first_playable_requires_ring0_and_ring1_only)` — no outer ring requirement leaks into first-playable.
- [ ] `assert(boot_complete_implies_outer_rings_finished)` — full startup completion still covers the whole requested startup bubble.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `scenes/world/game_world.gd`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/world_perf_probe.gd`

### Iteration 3 — Lock contract language in docs
Goal: ensure agents cannot reintroduce ambiguity in later specs.

What is done:
- update `PUBLIC_API.md` with the new boot semantics
- update `DATA_CONTRACTS.md` chunk lifecycle and presentation sections with the new readiness invariants
- align rollout terminology with spec terminology if needed

Acceptance tests:
- [ ] `PUBLIC_API.md` documents the semantic change to `boot_load_initial_chunks()`.
- [ ] `DATA_CONTRACTS.md` contains explicit readiness invariants.
- [ ] manual: all later boot specs refer to `first_playable` and `boot_complete` using the same definitions.

Files that may be touched:
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/04_execution/chunk_boot_streaming_rollout.md`

Files that must NOT be touched:
- runtime code

## Out-of-scope

- compute concurrency
- worker queue behavior
- apply-frame budgeting
- visual redraw deferral details
- topology scheduling details
- performance probe implementation

Those belong to the other boot specs and must not be smuggled into this task.
