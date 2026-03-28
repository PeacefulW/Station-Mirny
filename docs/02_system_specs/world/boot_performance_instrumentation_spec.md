---
title: Boot Performance Instrumentation Spec
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-28
depends_on:
  - boot_chunk_readiness_spec.md
  - boot_chunk_compute_pipeline_spec.md
  - boot_chunk_apply_budget_spec.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/WORKFLOW.md
related_docs:
  - ../../04_execution/chunk_boot_streaming_rollout.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
---

# Feature: Boot Performance Instrumentation

## Design Intent

Boot optimization work is not valid if the project cannot prove where time is going.

This spec defines the instrumentation required to measure staged boot loading after the architecture changes:
- compute queue wait
- worker compute time
- apply/finalize time
- redraw time by phase
- flora time
- topology time
- first-playable timestamp
- boot-complete timestamp

The point is attribution, not just more logs.

## Public API impact

Current public APIs affected semantically:
- `ChunkManager.boot_load_initial_chunks(progress_callback: Callable) -> void`
- `WorldPerfProbe.record(...)`
- `WorldPerfProbe.begin()` / `WorldPerfProbe.end(...)`

Required API/documentation outcome after implementation:
- `PUBLIC_API.md` does not need to expose internal instrumentation writers.
- If a read-only boot metrics snapshot becomes publicly readable to `GameWorld` or UI, it must be documented.
- No gameplay system may gain write access to performance counters.

## Data Contracts — new and affected

### New layer: Boot Performance Metrics
- What: owner-managed metrics for staged startup loading.
- Where: `core/systems/world/chunk_manager.gd`, `core/systems/world/world_perf_probe.gd`, and if needed `core/autoloads/world_perf_monitor.gd`.
- Owner (WRITE): `ChunkManager` for boot metric emission, `WorldPerfProbe` for aggregation.
- Readers (READ): debugging, profiling, boot progress diagnostics.
- Invariants:
  - compute, apply, redraw, flora, and topology timings must be distinguishable.
  - first-playable and boot-complete timestamps must be emitted separately.
  - instrumentation must not mutate gameplay state.
- Event after change: none required.
- Forbidden:
  - reporting one blended boot number without phase attribution
  - logging timings under misleading legacy labels
  - using UI as the source of truth for performance state

### Affected layer: Chunk Lifecycle
- What changes:
  - boot lifecycle now emits attributed timings for compute and apply.
- New invariants:
  - each startup chunk may emit separate timing records for compute and apply.
- Who adapts:
  - `ChunkManager`
- What does NOT change:
  - lifecycle ownership stays inside `ChunkManager`

### Affected layer: Presentation
- What changes:
  - redraw cost during boot is tracked by phase.
- New invariants:
  - boot redraw metrics must not merge terrain, cover, cliff, flora, and debug into one opaque total.
- Who adapts:
  - `ChunkManager`
  - `Chunk`
- What does NOT change:
  - redraw execution ownership stays inside `Chunk`

## Required boot metrics

Minimum required metrics:
- per-chunk compute queue wait time
- per-chunk worker compute duration
- per-chunk apply/finalize duration
- per-step redraw duration by redraw phase name
- per-chunk flora compute duration if flora is still computed during boot
- topology duration during boot
- timestamp or relative elapsed time for:
  - first-playable reached
  - boot-complete reached

Required boot summary must answer:
- how long until first-playable
- how long until boot-complete
- where the dominant time went

## Iterations

### Iteration 1 — Split boot timings into compute/apply/redraw/topology buckets
Goal: stop using a single blended boot timing that hides the real bottleneck.

What is done:
- add separate metric labels for compute, apply, redraw, flora, topology
- ensure boot paths emit these labels consistently
- keep legacy labels only if clearly marked deprecated

Acceptance tests:
- [ ] `assert(boot_metrics_have_distinct_compute_apply_redraw_topology_labels)` — attribution exists.
- [ ] manual: boot log can answer whether time is spent in compute or apply without reading code.
- [ ] `assert(no_single_blended_boot_metric_is_the_only_signal)` — one opaque total is not the only output.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/world_perf_probe.gd`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `docs/00_governance/PUBLIC_API.md`

### Iteration 2 — Emit first-playable and boot-complete milestones
Goal: make the player-facing boot gate measurable.

What is done:
- emit timing for `first_playable`
- emit timing for `boot_complete`
- ensure these are reported separately

Acceptance tests:
- [ ] `assert(first_playable_metric_exists)` — first playable has its own metric.
- [ ] `assert(boot_complete_metric_exists)` — boot complete has its own metric.
- [ ] `assert(first_playable_time <= boot_complete_time)` — milestone ordering is sane.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `scenes/world/game_world.gd`
- `core/systems/world/world_perf_probe.gd`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_content_builder.gd`

### Iteration 3 — Add chunk-level queue and apply pressure diagnostics
Goal: make staged boot regressions attributable to queue pressure, not just total duration.

What is done:
- record queue wait time for computed chunks
- record number of active compute tasks and queued apply items in boot summaries
- log warnings when apply-step budget is exceeded

Acceptance tests:
- [ ] `assert(queue_wait_metric_exists_for_computed_chunks)` — queue pressure is measurable.
- [ ] `assert(apply_budget_warning_is_visible)` — oversized finalize work is diagnosable.
- [ ] manual: a slow boot can be classified as compute-bound, apply-bound, redraw-bound, or topology-bound from the logs.

Files that may be touched:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/world_perf_probe.gd`
- `core/autoloads/world_perf_monitor.gd`

Files that must NOT be touched:
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk.gd`
- `docs/00_governance/PUBLIC_API.md`

## Required contract and API updates after implementation

When this spec is implemented, update:
- `DATA_CONTRACTS.md`
  - boot metric ownership if any contract section describes debug/probe ownership
- `PUBLIC_API.md`
  - only if a read-only boot metrics snapshot becomes public

## Out-of-scope

- changing boot compute architecture
- changing apply queue behavior
- changing redraw policy
- changing topology gates

This spec measures those systems; it does not redesign them.
