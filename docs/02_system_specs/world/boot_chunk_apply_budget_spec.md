---
title: Boot Chunk Apply Budget Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-28
depends_on:
  - boot_chunk_readiness_spec.md
  - boot_chunk_compute_pipeline_spec.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
related_docs:
  - ../../04_execution/chunk_boot_streaming_rollout.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
---

# Feature: Boot Chunk Apply Budget

## Design Intent

Fixing boot compute is not enough.
If computed startup chunks are applied to the scene tree in an unbounded burst, the hitch simply moves from compute to finalize/apply.

This spec defines how startup chunks are applied on the main thread:
- in what order
- under what budget
- how many may finalize per frame/step
- how first-playable prioritization beats far-ring completeness

## Public API impact

Current public APIs affected semantically:
- `ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`
- `Chunk.complete_redraw_now() -> void` (owner-only safe entrypoint)

Required API/documentation outcome after implementation:
- `PUBLIC_API.md` must document that boot load is a staged apply path, not a single synchronous full-install loop.
- No public API may expose arbitrary external chunk apply or finalize control.
- Any read-only boot apply snapshot API must be documented as owner-owned and non-mutating.

## Data Contracts — new and affected

### New layer: Boot Apply Queue
- What: owner-managed ready-to-apply startup chunk queue.
- Where: `core/systems/world/chunk_manager.gd` (`_boot_apply_*` state section).
- Owner (WRITE): `ChunkManager`.
- Readers (READ): instrumentation, boot progress, scene boot orchestrator.
- Invariants:
  - only computed startup chunks may enter the apply queue.
  - scene-tree apply happens on the main thread only.
  - apply priority is distance-first: nearer chunks must beat farther chunks.
  - `first_playable` must never wait behind a farther-ring apply item.
- Event after change: none required in iteration 1.
- Forbidden:
  - applying more chunks in one frame than allowed by the explicit budget
  - bypassing apply order by directly attaching far chunks first
  - equating apply completion with visual completion

### Affected layer: Chunk Lifecycle
- What changes:
  - chunk install becomes explicitly split into compute result availability and main-thread apply.
- New invariants:
  - `applied` means registered, attached, and visible to runtime ownership.
  - `applied` does not imply `visual_complete`.
- Who adapts:
  - `ChunkManager`
- What does NOT change:
  - chunk registration ownership remains with `ChunkManager`

### Affected layer: Presentation
- What changes:
  - apply order may precede full visual completion order.
- New invariants:
  - apply queue controls ownership and presence; redraw policy is separate.
- Who adapts:
  - `ChunkManager`
  - `Chunk`
- What does NOT change:
  - `Chunk` still owns redraw phase progression

## Apply budget model

Required initial policy:
- boot apply must run on the main thread only
- apply priority must be by startup ring distance from player
- before `first_playable`, apply budget may prioritize ring-0 and ring-1 work even if outer rings are already computed

Initial concrete limits for iteration 1:
- maximum one chunk finalize per frame or per boot step
- log a warning if single apply/finalize step exceeds `8.0 ms`
- do not apply outer-ring startup chunks while a required near-ring chunk is still pending

## Iterations

### Iteration 1 — Introduce apply queue and distance priority
Goal: prevent computed results from finalizing in arbitrary order.

What is done:
- add owner-managed boot apply queue
- sort or maintain queue by distance to player chunk
- split `computed` from `applied`
- ensure near-player chunks always finalize first

Acceptance tests:
- [ ] `assert(only_computed_chunks_enter_apply_queue)` — no raw requests skip compute.
- [ ] `assert(no_outer_ring_chunk_applied_before_required_near_ring_chunk)` — priority is enforced.
- [ ] manual: when multiple startup chunks are ready together, player chunk and ring-1 chunks appear before farther chunks.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`
- `docs/00_governance/PUBLIC_API.md`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `scenes/world/game_world.gd`

### Iteration 2 — Add explicit apply budget enforcement
Goal: stop boot from finalizing too much scene-tree work in one frame.

What is done:
- enforce maximum finalize operations per frame/boot step
- record apply-step timings
- add guardrails so budget pressure cannot be bypassed by direct helper calls

Acceptance tests:
- [ ] `assert(applied_chunks_this_step <= configured_apply_limit)` — hard cap enforced.
- [ ] `assert(apply_step_warning_emitted_when_over_8ms)` — oversized finalize is visible in logs.
- [ ] manual: large startup bubbles no longer cause a single massive attach/finalize burst after compute completes.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/world_perf_probe.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk.gd`
- `scenes/world/game_world.gd`

### Iteration 3 — Tie first-playable to apply budget, not full startup completion
Goal: ensure boot gate logic benefits from apply budgeting instead of waiting for outer rings.

What is done:
- connect apply queue status to `first_playable`
- ensure first-playable becomes true once required near rings are applied and meet readiness contract
- keep outer rings in the queue for later completion without blocking control

Acceptance tests:
- [ ] `assert(first_playable_not_blocked_by_outer_ring_apply_work)` — outer rings do not hold the gate.
- [ ] `assert(first_playable_requires_near_ring_apply_complete)` — near-ring apply is still mandatory.
- [ ] manual: gameplay can begin while farther startup chunks continue applying later.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `scenes/world/game_world.gd`
- `docs/00_governance/PUBLIC_API.md`
- `docs/02_system_specs/world/DATA_CONTRACTS.md`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_content_builder.gd`

## Required contract and API updates after implementation

When this spec is implemented, update:
- `DATA_CONTRACTS.md`
  - chunk lifecycle states
  - main-thread apply ownership
  - any new apply budget invariants
- `PUBLIC_API.md`
  - `boot_load_initial_chunks()` semantics
  - any read-only boot apply status read API

## Out-of-scope

- worker compute concurrency
- visual redraw phase ordering
- flora deferral policy
- topology scheduling
- UI polish of loading screen text

Those belong to the adjacent boot specs.
