---
title: Boot Chunk Compute Pipeline Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-28
depends_on:
  - boot_chunk_readiness_spec.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
related_docs:
  - ../../04_execution/chunk_boot_streaming_rollout.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
---

# Feature: Boot Chunk Compute Pipeline

## Design Intent

The startup bubble must stop using repeated synchronous surface chunk generation on the main thread.

This spec defines the bounded-parallel compute side of boot loading:
- how startup chunk payloads are queued
- how many worker tasks may run at once
- what data is produced by worker threads
- how stale or failed compute results are handled
- how boot compute remains deterministic

This spec does not define scene-tree apply or redraw rules.

## Public API impact

Current public APIs affected semantically:
- `ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`
- `WorldGenerator.build_chunk_native_data(chunk_coord: Vector2i) -> Dictionary`
- `WorldGenerator.create_detached_chunk_content_builder() -> ChunkContentBuilder` (internal helper, not public gameplay API)

Required API/documentation outcome after implementation:
- `PUBLIC_API.md` must continue to forbid direct caller use of `_load_chunk()` and worker internals.
- No public gameplay API may be added for boot compute submission.
- If a read-only boot queue snapshot is introduced, it must be documented as read-only and owner-owned by `ChunkManager`.

## Data Contracts — new and affected

### New layer: Boot Compute Queue
- What: bounded queue of startup chunk compute requests and their worker-task state.
- Where: `core/systems/world/chunk_manager.gd` (`_boot_compute_*` state section).
- Owner (WRITE): `ChunkManager`.
- Readers (READ): instrumentation, boot progress, owner-side apply scheduler.
- Invariants:
  - a startup chunk may have at most one active compute task at a time.
  - a completed compute result contains native data only, never scene-tree objects.
  - `max_concurrent_boot_compute_tasks` must stay within `[1, 4]` in iteration 1.
  - stale compute results must be discarded, not applied.
- Event after change: none required in iteration 1.
- Forbidden:
  - creating `Chunk` nodes in worker threads
  - returning scene objects from worker compute
  - unbounded submission of all startup chunks without a concurrency cap

### Affected layer: Chunk Lifecycle
- What changes:
  - startup chunk generation becomes split into compute and apply stages.
- New invariants:
  - compute completion is not equivalent to chunk load completion.
  - chunk lifecycle state must be able to observe `computed but not yet applied`.
- Who adapts:
  - `ChunkManager`
- What does NOT change:
  - `ChunkManager` remains the sole lifecycle owner

### Affected layer: World
- What changes:
  - boot chunk generation must use native payload generation rather than legacy synchronous full build path.
- New invariants:
  - startup surface compute uses `build_chunk_native_data()` or detached-builder equivalent.
- Who adapts:
  - `ChunkManager`
  - only if required: `WorldGenerator`
- What does NOT change:
  - generated terrain semantics for a seed and coordinate pair

## Compute model

Bounded concurrency policy for iteration 1:
- minimum: `1`
- maximum: `4`
- recommended default: `3`

Per-chunk compute states:
- `requested`
- `queued`
- `computing`
- `computed`
- `discarded`
- `failed`

Worker output contract:
- `chunk_coord`
- `z_level`
- `native_data`
- optional `flora_payload` only if kept pure-data
- no `Node`, `TileMapLayer`, or `Chunk` instance references

## Iterations

### Iteration 1 — Replace synchronous boot compute path
Goal: eliminate repeated synchronous surface boot generation.

What is done:
- boot path stops calling legacy direct `_load_chunk()` for startup surface compute
- startup surface compute routes through `build_chunk_native_data()` or detached-builder native-data generation
- compute results remain pure dictionaries/packed arrays

Acceptance tests:
- [ ] manual: boot logs no longer show repeated synchronous `ChunkManager._load_chunk (...)` timings for every startup chunk.
- [ ] `assert(worker_output_has_no_scene_objects)` — compute results remain pure data.
- [ ] `assert(surface_boot_compute_uses_native_payload_path)` — startup surface generation no longer depends on `build_chunk_content()` in the critical path.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/autoloads/world_generator.gd`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/systems/world/chunk.gd`
- `scenes/world/game_world.gd`
- `core/autoloads/frame_budget_dispatcher.gd`

### Iteration 2 — Add bounded parallel compute queue
Goal: overlap startup chunk compute without unbounded task fan-out.

What is done:
- add owner-managed startup compute queue
- add strict `max_concurrent_boot_compute_tasks`
- add stale-result discard rules
- preserve deterministic priority order for request issuance

Acceptance tests:
- [ ] `assert(active_compute_tasks <= max_concurrent_boot_compute_tasks)` — bounded concurrency is enforced.
- [ ] `assert(no_chunk_has_more_than_one_active_compute_task)` — duplicate compute races are blocked.
- [ ] manual: increasing startup bubble size does not cause all chunks to launch at once.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/systems/world/chunk.gd`
- `scenes/world/game_world.gd`
- `core/autoloads/world_perf_monitor.gd`

### Iteration 3 — Add discard and failure handling
Goal: make the compute queue safe under boot state changes and partial failures.

What is done:
- discard computed results that no longer belong to the active boot request
- define retry policy or fail-fast policy for compute failure
- expose enough state for instrumentation without widening public mutation surface

Acceptance tests:
- [ ] `assert(stale_computed_result_is_not_applied)` — stale compute is discarded safely.
- [ ] `assert(failed_compute_does_not_deadlock_boot_state)` — one failure cannot leave boot permanently stuck.
- [ ] manual: a discarded or failed task leaves the queue in a recoverable state.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/world_perf_probe.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must NOT be touched:
- `core/systems/world/chunk.gd`
- `scenes/world/game_world.gd`

## Required contract and API updates after implementation

When this spec is implemented, update:
- `DATA_CONTRACTS.md`
  - chunk lifecycle section
  - world source-of-truth notes for startup compute path
  - any new boot compute queue invariants
- `PUBLIC_API.md`
  - semantics for `boot_load_initial_chunks()`
  - any new read-only boot queue snapshot API
  - explicit statement that boot compute submission remains internal

## Out-of-scope

- apply-frame budgeting
- redraw and visual completion policy
- topology scheduling
- loading screen UX
- performance summary formatting beyond minimal debug visibility

Those belong to the adjacent boot specs.
