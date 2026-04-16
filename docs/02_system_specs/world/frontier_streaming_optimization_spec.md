---
title: Frontier Streaming Optimization
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-16
depends_on:
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - DATA_CONTRACTS.md
  - zero_tolerance_chunk_readiness_spec.md
  - frontier_native_runtime_architecture_spec.md
related_docs:
  - ../meta/ai_performance_observatory_spec.md
  - ../../04_execution/world_startup_and_runtime_perf_investigation.md
  - ../../04_execution/boot_streaming_perf_analysis.md
  - ../../04_execution/frontier_native_runtime_execution_plan.md
---

# Feature: Frontier Streaming Optimization

## Design Intent

This spec defines the first dedicated optimization feature that uses the
observatory as proof infrastructure without changing observatory schema or
ownership.

Player-facing problem:

- the player can still outrun runtime streaming/catch-up in sanctioned movement
  scenarios
- the remaining cost is concentrated in staged install, visual apply, and
  queue/frontier timing rather than in observatory itself

This feature is not:

- a replacement for `ai_performance_observatory_spec.md`
- permission to relax `full_ready`
- permission to publish terrain first and finish later
- permission to widen runtime scope through debug camera visibility

This feature is the implementation handoff for future streaming work. The
observatory remains proof/diagnosis infrastructure; this spec owns the runtime
optimization slices that future work must follow.

## Performance / Scalability Contract

- `runtime class`:
  - `background` for runtime streaming queue selection, async/native compute,
    staged install, visual apply, cache reuse, and publication follow-up
  - `boot` only for collecting comparable proof artifacts; boot semantics are
    not redesigned here
  - `interactive`: none; no player-input path may gain a new synchronous world
    rebuild from this feature
- `target scale / density`:
  - fixed gameplay-owned `3x3` hot envelope
  - fixed gameplay-owned `5x5` warm preload envelope
  - motion frontier sized for at least sanctioned on-foot sprint validation on
    the baseline machine
  - vehicle/train expansion remains a later iteration and must not silently
    weaken the walking/sprint contract while in progress
- `authoritative source of truth`:
  - `ChunkStreamingService` owns runtime load queue relevance, staged install
    orchestration, and active generation lanes
  - `TravelStateResolver`, `ViewEnvelopeResolver`, `FrontierPlanner`, and
    `FrontierScheduler` own derived planning and reserved-capacity policy
  - `ChunkVisualScheduler` owns runtime visual debt, queue ordering, and budgeted
    redraw completion
  - `Chunk` and `ChunkManager` own terminal publication/full-ready state
  - `ChunkSurfacePayloadCache` owns duplicated cache copies only, never gameplay
    truth
- `single write owner`:
  - no new mutable mirror may be introduced without naming one write owner and
    invalidation path in `DATA_CONTRACTS.md`
- `derived/cache state`:
  - observatory JSON remains debug-only derived proof
  - any visual/cache reuse must remain derived from the terminal
    `frontier_surface_final_packet`
  - queue snapshots, frontier plans, and scenario records remain transient
- `dirty unit`:
  - one queue entry
  - one staged chunk install entry
  - one chunk-local visual task slice
  - one cached terminal surface packet
- `allowed synchronous work`:
  - enqueue/reclassify one runtime request
  - attach one already-prepared payload to one staged chunk shell
  - bounded publication bookkeeping for one chunk
  - enqueue background follow-up work
- `escalation path`:
  - heavy compute stays in worker/native packet preparation
  - heavy visual completion stays in scheduler-owned budgeted slices or native
    batch-friendly payloads
  - reuse stays in cache/path-local derived buffers, not in gameplay truth
- `forbidden shortcuts`:
  - direct sync `load -> build -> finalize -> publish` player-path shortcuts
  - camera-visible or debug-visible chunks widening runtime load scope
  - visible or occupiable terrain-only fast pass
  - GDScript fallback for critical player-reachable readiness
  - mass full redraw, `clear()`, `set_cell()`, `add_child()`, or `queue_free()`
    in response to one frontier update

## Observatory Proof Contract (No Schema Changes)

This feature must use existing observatory artifact fields directly. Future
implementation is forbidden from requiring a new JSON schema merely to prove the
optimization worked.

Required fixed-seed proof commands:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=12345 codex_perf_output=debug_exports/perf/streaming_opt_before_seed12345.json codex_quit_on_perf_complete
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=12345 codex_perf_output=debug_exports/perf/streaming_opt_after_seed12345.json codex_quit_on_perf_complete
```

Optional cross-check after the primary seed passes:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=99999 codex_perf_output=debug_exports/perf/streaming_opt_after_seed99999.json codex_quit_on_perf_complete
```

Required before/after proof fields already available today:

- `contract_violations[]`
  - filter by `type`, `category`, and `job_id`
  - streaming-targeted regressions are tracked here without schema changes
- `frame_summary.latest_frame_ms`
- `frame_summary.hitch_count`
- `frame_summary.category_peaks.visual`
- `frame_summary.category_peaks.dispatcher`
- `frame_summary.latest_debug_snapshot.visual_build_ms`
- `frame_summary.latest_debug_snapshot.dispatcher_ms`
- `streaming.overlay_snapshot.metrics.average_chunk_processing_time_ms`
- `streaming.overlay_snapshot.metrics.worst_chunk_stage_time_ms`
- `streaming.overlay_snapshot.metrics.queue_sizes.load`
- `streaming.overlay_snapshot.metrics.queue_sizes.visual`
- `streaming.overlay_snapshot.metrics.queue_sizes.frontier_capacity.queue_frontier_critical`
- `streaming.overlay_snapshot.metrics.queue_sizes.frontier_plan.speed_class`
- `streaming.overlay_snapshot.metrics.queue_sizes.frontier_plan.travel_mode`
- `scenarios[].name`
- `scenarios[].state`
- `scenarios[].blocker`
- `scenarios[].readiness_outcome` when present
- `scenarios[].reached_waypoints`

Diff workflow:

- use `tools/perf_baseline_diff.gd` for existing numeric regression heuristics on
  `frame_summary`, `boot`, and `native_profiling`
- read the candidate JSON directly for `scenarios[]` and
  `streaming.overlay_snapshot.metrics.queue_sizes.*`, because those fields
  already exist but are not all summarized by the helper

Fail conditions for future implementation:

- any new streaming-targeted contract violation appears in the candidate artifact
- `route`, `speed_traverse`, or `chunk_revisit` fails to finish with
  `blocker=none`
- a visible/publication correctness contract is weakened to manufacture lower
  timings
- the optimization requires observatory schema changes to prove its own result

## Data Contracts - new and affected

### New layer: none required initially

- This handoff spec does not authorize a new canonical gameplay layer by
  default.
- Optimization work must first adapt existing runtime owners.
- If implementation introduces a new cache/service/queue owner, that ownership
  must be added to `DATA_CONTRACTS.md` in the same task that lands the code.

### Affected layer: Frontier Planning / Reserved Scheduling

- What changes:
  - planning horizon, enqueue timing, queue pruning, and lane pressure may be
    retuned for sanctioned movement scenarios
- Who adapts:
  - `TravelStateResolver`
  - `ViewEnvelopeResolver`
  - `FrontierPlanner`
  - `FrontierScheduler`
  - `ChunkStreamingService`
- What does NOT change:
  - fixed gameplay `3x3` hot and `5x5` warm envelope policy
  - debug camera remains observability-only
  - `full_ready` does not move into frontier-planning truth

### Affected layer: Chunk Lifecycle

- What changes:
  - staged install sequencing and bounded publish preparation may be optimized
- Who adapts:
  - `ChunkStreamingService`
  - `ChunkManager`
  - `Chunk`
- Invariants:
  - terminal `frontier_surface_final_packet` proof remains mandatory
  - fresh chunks remain hidden until `Chunk.is_full_redraw_ready()`
  - no optimization may reintroduce publish-now/finish-later semantics

### Affected layer: Surface Payload Cache / Visual Scheduling

- What changes:
  - runtime may reuse packet-derived payloads or batch-friendly command buffers
    to reduce repeated visual apply cost
- Who adapts:
  - `ChunkSurfacePayloadCache`
  - `ChunkVisualScheduler`
  - `Chunk`
  - native `chunk_visual_kernels`
- Invariants:
  - cache entries remain derived from terminal packet truth
  - visual batching may reduce cost, but not weaken publication correctness
  - any hidden terrain-only prewarm must stay non-visible, non-occupiable, and
    non-authoritative; otherwise it requires a spec amendment

## Required contract and API updates after implementation

- `DATA_CONTRACTS.md`
  - required if staged install ownership changes
  - required if frontier lane ownership/invariants change
  - required if packet/cache ownership changes or a new runtime cache/service is
    introduced
- `PUBLIC_API.md`
  - update only if a new sanctioned read-only runtime/proof accessor is added
  - do not document internal writer hooks, queue internals, or observatory-only
    file writes as public API
- `Other canonical docs`
  - if implementation needs to reinterpret `full_ready`, `visible`, or hidden
    prewarm semantics, update the higher-precedence runtime spec first instead
    of burying the change here

## Iterations

### Iteration 1 - Dedicated Streaming Baseline + Staged Install Split

Goal:
Reduce staged install stall without changing player-visible publication rules.

What is done:

- capture a dedicated fixed-seed optimization baseline artifact for
  `route,speed_traverse,chunk_revisit`
- split runtime staged install into explicit prepared-data steps and bounded
  main-thread apply slices
- keep `Chunk.populate_native()` terminal proof and `Chunk.is_full_redraw_ready()`
  gating unchanged
- forbid reintroduction of a direct sync runtime surface load path

Acceptance tests:

- [ ] baseline and candidate artifacts use the same fixed seed and scenario set
- [ ] `streaming.overlay_snapshot.metrics.worst_chunk_stage_time_ms` improves by
  more than `20%` versus the dedicated baseline
- [ ] `frame_summary.category_peaks.dispatcher` does not regress by more than
  `20%`
- [ ] `route`, `speed_traverse`, and `chunk_revisit` finish with `blocker=none`
- [ ] no new streaming-targeted contract violation key appears in
  `contract_violations[]`

Files that may be touched:

- `core/systems/world/chunk_streaming_service.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if ownership/invariants
  change
- `docs/00_governance/PUBLIC_API.md` only if a new read-only accessor is added

Files that must NOT be touched:

- `core/debug/perf_telemetry_collector.gd`
- `core/debug/runtime_validation_driver.gd`
- `tools/perf_baseline_diff.gd`
- save/load semantics
- chunk publication correctness rules outside the explicit contract updates above

### Iteration 2 - Predictive Frontier Tuning For Sprint-Safe Traversal

Goal:
Prepare the motion frontier early enough that sanctioned sprint traversal does
not outrun queue readiness.

What is done:

- retune travel-speed inputs and prediction horizon for sanctioned sprint routes
- tighten enqueue/prune timing for movement-critical chunks
- preserve debug-camera non-driving behavior
- preserve reserved frontier capacity discipline

Acceptance tests:

- [ ] `speed_traverse` finishes with `state=finished`,
  `readiness_outcome=finished`, and `blocker=none`
- [ ] `chunk_revisit` finishes with `state=finished` and `blocker=none`
- [ ] final
  `streaming.overlay_snapshot.metrics.queue_sizes.frontier_capacity.queue_frontier_critical`
  equals `0`
- [ ] final `streaming.overlay_snapshot.metrics.queue_sizes.frontier_plan.speed_class`
  matches the active validation scenario
- [ ] no new frontier-starvation or camera-scope contract violation appears

Files that may be touched:

- `core/systems/world/travel_state_resolver.gd`
- `core/systems/world/view_envelope_resolver.gd`
- `core/systems/world/frontier_planner.gd`
- `core/systems/world/frontier_scheduler.gd`
- `core/systems/world/chunk_streaming_service.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if ownership/invariants
  change
- `docs/00_governance/PUBLIC_API.md` only if a new read-only accessor is added

Files that must NOT be touched:

- `core/debug/perf_telemetry_collector.gd`
- `core/debug/runtime_validation_driver.gd`
- `tools/perf_baseline_diff.gd`
- `scenes/world/game_world_debug.gd` unless the implementation prompt
  explicitly narrows a proof-only scene change with no schema/API change

### Iteration 3 - Visual Apply Batching + Packet/Cache Reuse

Goal:
Lower `streaming_redraw` cost without weakening final-packet-only visibility.

What is done:

- move critical visual apply preparation toward native/batch-friendly buffers
- reuse terminal packet-derived payloads where validity is already provable
- reduce repeated `streaming_redraw` debt in player-near routes
- keep chunks hidden until full-ready publication closes

Acceptance tests:

- [ ] candidate proof does not introduce any new visible/publication correctness
  contract violation
- [ ] `contract_violations[]` for
  `type=budget_overrun|category=visual|job_id=chunk_manager.streaming_redraw`
  improves relative to the dedicated streaming baseline
- [ ] `frame_summary.category_peaks.visual` improves by more than `10%` or
  holds steady while the streaming-redraw contract violation count falls
- [ ] `frame_summary.latest_debug_snapshot.visual_build_ms` improves by more
  than `10%` or holds steady while the streaming-redraw contract violation count
  falls
- [ ] `route` and `speed_traverse` still finish with `blocker=none`

Files that may be touched:

- `core/systems/world/chunk_visual_scheduler.gd`
- `core/systems/world/chunk_surface_payload_cache.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_manager.gd`
- `gdextension/src/chunk_visual_kernels.h`
- `gdextension/src/chunk_visual_kernels.cpp`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if ownership/invariants
  change
- `docs/00_governance/PUBLIC_API.md` only if a new read-only accessor is added

Files that must NOT be touched:

- `core/debug/perf_telemetry_collector.gd`
- `core/debug/runtime_validation_driver.gd`
- `tools/perf_baseline_diff.gd`
- save/load semantics
- any change that makes a chunk visible before terminal `full_ready`

## Verification recipe for implementation

Primary proof run:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=12345 codex_perf_output=debug_exports/perf/streaming_opt_candidate_seed12345.json codex_quit_on_perf_complete
```

Numeric diff summary:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tools/perf_baseline_diff.gd -- codex_perf_baseline=debug_exports/perf/streaming_opt_before_seed12345.json codex_perf_candidate=debug_exports/perf/streaming_opt_candidate_seed12345.json codex_perf_output_prefix=streaming_opt_seed12345
```

Mandatory direct JSON review after the helper:

- `contract_violations[]`
- `streaming.overlay_snapshot.metrics.average_chunk_processing_time_ms`
- `streaming.overlay_snapshot.metrics.worst_chunk_stage_time_ms`
- `streaming.overlay_snapshot.metrics.queue_sizes.*`
- `scenarios[]`

Secondary proof is optional until the primary fixed seed passes:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=99999 codex_perf_output=debug_exports/perf/streaming_opt_candidate_seed99999.json codex_quit_on_perf_complete
```

## Out-of-scope

- observatory JSON schema changes
- new always-on diagnostics or a second perf subsystem
- relaxing `full_ready`, `visible`, or occupancy correctness
- debug-camera-driven widening of runtime streaming scope
- save/load redesign
- streaming work that depends on hidden direct world mutations outside
  sanctioned owners
- visible `terrain-only` publish-first behavior; if a future hidden prewarm path
  is needed, it must remain non-visible and non-authoritative or be specified in
  a reviewed amendment
