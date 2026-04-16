---
title: Player-Hot Chunk Publication Recovery
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
  - frontier_streaming_optimization_spec.md
  - ../meta/ai_performance_observatory_spec.md
  - human_readable_runtime_logging_spec.md
---

# Feature: Player-Hot Chunk Publication Recovery

## Design Intent

This spec narrows streaming optimization to the failure profile proven by the
explicit observatory run from 2026-04-16.

Current proof source:

- `debug_exports/perf/streaming_scenarios_seed12345_20260416_151829.json`
- run command:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=12345 codex_perf_output=debug_exports/perf/streaming_scenarios_seed12345_20260416_151829.json codex_quit_on_perf_complete
```

The latest proof shows that route completion alone is not a sufficient green
condition:

- all three scenarios finish with `state=finished`
- `contract_violations[] = 128`
- `chunk_manager.streaming_load`: `42` overruns, average `20.247 ms`,
  peak `42.554 ms`
- `chunk_manager.streaming_redraw`: `41` overruns, average `3.731 ms`,
  peak `5.753 ms`
- `mountain_shadow.visual_rebuild`: `36` overruns, average `137.946 ms`,
  peak `309.3 ms`
- final visual queue depth = `221`, including `full_far=211` and
  `terrain_near=8`
- final forensics show the player chunk stalled for `11801.859 ms`, with
  `pending_tasks=["first_pass"]` and `is_visible=false`
- runtime native chunk generation remains expensive: average
  `119.562 ms`, peak `172.763 ms`

Player-facing problem:

- player-hot chunk publication can still starve even when the route harness
  reports success
- player-hot terminal convergence is competing with visual debt and shadow
  rebuild work
- runtime generation cost remains heavy, but it is secondary until player-hot
  publication no longer starves

This feature is not:

- a rewrite of all frontier planning
- permission to relax `full_ready`
- permission to publish terrain first and finish later
- permission to widen gameplay scope through debug camera visibility
- permission to change observatory JSON schema
- permission to fold `far_loop`, `seam_cross`, vehicles, or trains into the
  first recovery slice

## Performance / Scalability Contract

- `runtime class`:
  - `background` for validation proof evaluation, visual queue work, shadow
    rebuild work, runtime chunk generation, and streaming follow-up
  - `boot` only for collecting comparable artifacts; boot semantics are not
    redesigned here
  - `interactive`: none; no player-input path may gain new synchronous world
    rebuilds from this feature
- `target scale / density`:
  - fixed gameplay-owned `3x3` hot envelope
  - fixed gameplay-owned `5x5` warm preload envelope
  - sanctioned route matrix for this feature:
    `route`, `speed_traverse`, `chunk_revisit` with `seed=12345`
  - optional disambiguation routes `far_loop` and `seam_cross` are follow-up
    checks only; they do not widen the first implementation slice by default
- `authoritative source of truth`:
  - `ChunkStreamingService` owns runtime load queue relevance, staged install,
    and active generation handoff
  - `ChunkVisualScheduler` owns visual debt, queue ordering, and budgeted
    redraw completion
  - `MountainShadowSystem` owns shadow rebuild requests and shadow presentation
    follow-up
  - `Chunk` and `ChunkManager` own terminal publication, `full_ready`, and
    occupancy correctness
  - `RuntimeValidationDriver` and `PerfTelemetryCollector` own debug-only proof
    outcome and observatory artifact assembly
- `single write owner`:
  - no new mutable mirror may be introduced without naming one write owner and
    invalidation path in `DATA_CONTRACTS.md`
- `derived/cache state`:
  - observatory JSON remains debug-only derived proof
  - validation scenario results remain debug-only derived proof
  - visual queues, queue snapshots, suspicion flags, and shadow diagnostics
    remain transient
  - any visual/cache reuse must remain derived from the terminal
    `frontier_surface_final_packet`
- `dirty unit`:
  - one validation run outcome
  - one player-hot chunk visual task slice
  - one shadow rebuild slice
  - one runtime chunk generation request
  - one queue entry
- `allowed synchronous work`:
  - reclassify one player-hot visual task
  - emit one validation outcome from already-owned state
  - attach one already-prepared packet to one staged chunk shell
  - bounded publication bookkeeping for one chunk
  - enqueue or defer one shadow follow-up slice
- `escalation path`:
  - heavy visual follow-up stays inside `ChunkVisualScheduler`
  - heavy shadow follow-up stays budgeted/deferred behind player-hot publication
  - heavy generation stays in worker/native `ChunkGenerator`
  - proof hardening must reuse existing JSON sections and owner-owned reads
    instead of inventing a second schema
- `degraded mode`:
  - far/background visual debt may remain after route drain if it does not block
    player-hot publication
  - player chunk and adjacent hot-envelope chunks may remain hidden while not
    `full_ready`; they may not become visible or occupiable below `full_ready`
  - shadow correctness for far/background chunks may lag only if player-hot
    publication is already converged
- `forbidden shortcuts`:
  - publish-now/finish-later for player-hot chunks
  - marking validation green while final artifact still shows player-hot stall
  - widening gameplay load scope to hide debt
  - mass full redraw, `clear()`, `set_cell()`, `add_child()`, or `queue_free()`
    in response to one player-hot publication event
  - new mutable cache or mirror without declared owner/invalidation

## Observatory Proof Contract (No Schema Changes)

This feature must use existing observatory artifact fields directly. The first
iteration is allowed to tighten success/failure semantics, but it is not
allowed to require a new JSON schema to prove success.

Stable before/candidate commands for this feature:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=12345 codex_perf_output=debug_exports/perf/player_hot_publication_before_seed12345.json codex_quit_on_perf_complete
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=12345 codex_perf_output=debug_exports/perf/player_hot_publication_candidate_seed12345.json codex_quit_on_perf_complete
```

Optional disambiguation routes after the primary matrix passes or if the
primary matrix stays ambiguous:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_validate_route=far_loop codex_world_seed=12345 codex_perf_output=debug_exports/perf/player_hot_publication_far_loop_seed12345.json codex_quit_on_perf_complete
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_validate_route=seam_cross codex_world_seed=12345 codex_perf_output=debug_exports/perf/player_hot_publication_seam_cross_seed12345.json codex_quit_on_perf_complete
```

Required proof fields already available today:

- `meta.validation_completion.outcome`
- `meta.validation_completion.blocker`
- `contract_violations[]`
- `scenarios[].name`
- `scenarios[].state`
- `scenarios[].blocker`
- `scenarios[].readiness_outcome` when present
- `streaming.debug_diagnostics.forensics.chunk_causality_rows`
- `streaming.debug_diagnostics.forensics.incident_summary.shadow_ms`
- `frame_summary.session_observations["Scheduler.urgent_visual_wait_ms"]`
- `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.full_near"]`
- `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.terrain_near"]`
- `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.full_far"]`
- `native_profiling.chunk_generator.phase_avg_ms.*`
- `native_profiling.chunk_generator.phase_peak_ms.*`

Fail conditions for implementation:

- any run still ends with `meta.validation_completion.outcome == "finished"`
  while final `chunk_causality_rows` contains a player chunk with
  `state == "stalled"`
- any run still ends with `meta.validation_completion.outcome == "finished"`
  while final `full_near > 0` or `terrain_near > 0`
- any change weakens `full_ready`, visibility, or occupancy correctness to
  manufacture lower timings
- any change requires new top-level observatory JSON fields to prove success

## Data Contracts - new and affected

### New layer: none required initially

- This spec does not authorize a new gameplay truth layer by default.
- Recovery work must first adapt existing runtime and debug owners.
- If implementation introduces a new cache/service/queue owner, that ownership
  must be added to `DATA_CONTRACTS.md` in the same task.

### Affected layer: Runtime Validation Scenario Orchestration

- What changes:
  - validation outcome semantics may tighten so that player-hot publication debt
    becomes a non-green result even when waypoints were reached
- Who adapts:
  - `RuntimeValidationDriver`
  - `RouteValidationScenario`
  - `ValidationContext`
- Invariants:
  - scenario selection remains explicit and CLI-driven
  - proof stays debug-only and never becomes gameplay truth
  - JSON schema remains unchanged
- What does NOT change:
  - save/load semantics
  - route preset ownership
  - gameplay writer ownership

### Affected layer: Chunk Lifecycle

- What changes:
  - player-hot publication follow-up may be reprioritized or isolated from
    competing background work
- Who adapts:
  - `ChunkManager`
  - `ChunkStreamingService`
  - `Chunk`
- Invariants:
  - terminal `frontier_surface_final_packet` proof remains mandatory
  - fresh chunks remain hidden until `Chunk.is_full_redraw_ready()`
  - player-occupied chunks must remain `full_ready`
  - no optimization may reintroduce publish-now/finish-later semantics

### Affected layer: Visual Task Scheduling / Presentation

- What changes:
  - player-hot terminal publication work may outrank far `full_far` backlog
  - shadow rebuild may be throttled, deferred, or reshaped while player-hot
    publication debt exists
- Who adapts:
  - `ChunkVisualScheduler`
  - `ChunkManager`
  - `MountainShadowSystem`
  - native `chunk_visual_kernels` only if later iterations need batch-friendly
    visual apply
- Invariants:
  - player-hot publication outranks far background debt
  - shadow work must not starve player-hot `full_ready`
  - cache or batching work remains derived from terminal packet truth

### Affected layer: Surface Final Packet / Runtime Generation

- What changes:
  - later iterations may reduce runtime generation cost in
    `terrain_resolve` and `feature_and_poi`
- Who adapts:
  - native `ChunkGenerator`
  - `ChunkContentBuilder`
  - `WorldGenerator`
  - `ChunkStreamingService` only if request packaging must change
- Invariants:
  - terminal packet shape stays authoritative for publication boundaries
  - player-reachable runtime must not reintroduce GDScript fallback for
    critical generation
  - optimization may reduce cost, but not weaken packet validation

## Required contract and API updates

- `DATA_CONTRACTS.md`
  - required if validation outcome invariants change
  - required if visual scheduler or shadow/publication ownership changes
  - required if runtime generation ownership or packet/cache ownership changes
- `PUBLIC_API.md`
  - `not required` by default; update only if a new sanctioned read-only
    runtime/proof accessor is added
- `Other canonical docs`
  - `ai_performance_observatory_spec.md`: update only if sanctioned proof
    command shape, default scenario set, or no-schema guarantee changes
  - `human_readable_runtime_logging_spec.md`: update only if new validation
    outcome wording or severity becomes canonical
  - `zero_tolerance_chunk_readiness_spec.md`: must be updated first if an
    implementation tries to reinterpret `full_ready`, `visible`, or occupancy

## Iterations

### Iteration 1 - Player-Hot Proof Hardening

Goal:
Make the explicit proof fail for the exact bad state seen in the fresh
2026-04-16 run, without changing gameplay runtime or observatory schema.

What is done:

- capture a stable before-state artifact for `seed=12345` and the current
  scenario matrix
- tighten validation completion so player-hot stalled state or final near-queue
  debt cannot still report green
- keep top-level observatory JSON shape unchanged
- keep runtime world/scheduler/generation code untouched in this iteration

Acceptance tests:

- [ ] `before` and `candidate` artifacts use `seed=12345` and scenarios `route,speed_traverse,chunk_revisit`
- [ ] `assert(meta.validation_completion.outcome != "finished")` whenever final `streaming.debug_diagnostics.forensics.chunk_causality_rows` still contains an entry with `is_player_chunk == true` and `state == "stalled"`
- [ ] `assert(meta.validation_completion.outcome != "finished")` whenever final `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.full_near"] > 0` or `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.terrain_near"] > 0`
- [ ] `assert(meta.schema_version == before.meta.schema_version)` and top-level JSON sections remain unchanged

Files that may be touched:

- `core/debug/runtime_validation_driver.gd`
- `core/debug/scenarios/validation_context.gd`
- `core/debug/scenarios/route_validation_scenario.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if debug-proof invariants become normative
- `docs/02_system_specs/meta/ai_performance_observatory_spec.md` only if sanctioned proof semantics change

Files that must NOT be touched:

- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk_visual_scheduler.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `gdextension/src/chunk_generator.cpp`
- observatory JSON schema or new top-level fields

### Iteration 2 - Player-Hot Publication Priority And Shadow Isolation

Goal:
Remove player-hot publication starvation without relaxing `full_ready`.

What is done:

- prioritize player chunk and hot-envelope terminal publication tasks over far
  `full_far` backlog
- bound, defer, or isolate `mountain_shadow.visual_rebuild` while player-hot
  publication debt exists
- preserve final-packet-only visibility and occupancy rules
- keep gameplay load scope and debug-camera behavior unchanged

Acceptance tests:

- [ ] `assert(meta.validation_completion.outcome == "finished")` on the primary proof
- [ ] final `streaming.debug_diagnostics.forensics.chunk_causality_rows` contains no entry with `is_player_chunk == true` and `state == "stalled"`
- [ ] final `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.full_near"] == 0`
- [ ] final `frame_summary.latest_debug_snapshot.ops["scheduler.visual_queue_depth.terrain_near"] == 0`
- [ ] `frame_summary.session_observations["Scheduler.urgent_visual_wait_ms"]` improves versus the dedicated before-state
- [ ] contract violations filtered by `category=visual` and `job_id in {"chunk_manager.streaming_redraw","mountain_shadow.visual_rebuild"}` improve, or at minimum one improves while the other does not regress by more than `20%`

Files that may be touched:

- `core/systems/world/chunk_visual_scheduler.gd`
- `core/systems/world/chunk_manager.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if priority or ownership invariants change
- `docs/00_governance/PUBLIC_API.md` only if a new read-only proof accessor is added

Files that must NOT be touched:

- `core/debug/perf_telemetry_collector.gd`
- `core/debug/runtime_validation_driver.gd`
- `core/debug/scenarios/*.gd`
- `gdextension/src/chunk_generator.cpp`
- `core/systems/world/travel_state_resolver.gd`
- `core/systems/world/frontier_planner.gd`

### Iteration 3 - Runtime Chunk Generation Cost Recovery

Goal:
Lower runtime generation debt only after player-hot publication no longer
starves.

What is done:

- reduce runtime `ChunkGenerator.generate_chunk()` cost in
  `terrain_resolve` and `feature_and_poi`
- keep terminal packet contract and native-only player-reachable path
- touch request/build plumbing only if needed to avoid redundant work

Acceptance tests:

- [ ] `native_profiling.chunk_generator.phase_avg_ms.total_ms` improves by more than `15%` versus the dedicated before-state
- [ ] at least one of `native_profiling.chunk_generator.phase_avg_ms.terrain_resolve_ms` or `native_profiling.chunk_generator.phase_avg_ms.feature_and_poi_ms` improves by more than `10%`
- [ ] contract violations filtered by `category=streaming` and `job_id=chunk_manager.streaming_load` improve versus the dedicated before-state
- [ ] `route`, `speed_traverse`, and `chunk_revisit` still finish with `blocker=none`
- [ ] no new visible/publication correctness regression appears

Files that may be touched:

- `gdextension/src/chunk_generator.h`
- `gdextension/src/chunk_generator.cpp`
- `core/systems/world/chunk_content_builder.gd`
- `core/autoloads/world_generator.gd`
- `core/systems/world/chunk_streaming_service.gd` only if worker request packaging must change
- `docs/02_system_specs/world/DATA_CONTRACTS.md` only if build ownership or packet invariants change

Files that must NOT be touched:

- `core/debug/perf_telemetry_collector.gd`
- `core/debug/runtime_validation_driver.gd`
- `core/systems/world/chunk_visual_scheduler.gd`
- `core/systems/lighting/mountain_shadow_system.gd`
- `core/systems/world/travel_state_resolver.gd`
- `core/systems/world/frontier_planner.gd`

## Verification recipe for implementation

Primary proof run:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_perf_test codex_validate_runtime codex_validate_scenarios=route,speed_traverse,chunk_revisit codex_world_seed=12345 codex_perf_output=debug_exports/perf/player_hot_publication_candidate_seed12345.json codex_quit_on_perf_complete
```

Numeric diff summary:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tools/perf_baseline_diff.gd -- codex_perf_baseline=debug_exports/perf/player_hot_publication_before_seed12345.json codex_perf_candidate=debug_exports/perf/player_hot_publication_candidate_seed12345.json codex_perf_output_prefix=player_hot_publication_seed12345
```

Mandatory direct JSON review after the helper:

- `meta.validation_completion`
- `contract_violations[]`
- `streaming.debug_diagnostics.forensics.chunk_causality_rows`
- `streaming.debug_diagnostics.forensics.incident_summary`
- `frame_summary.session_observations`
- `frame_summary.latest_debug_snapshot.ops`
- `native_profiling.chunk_generator.*`

If the primary matrix passes but player reports still describe long-travel or
seam-specific pain, run the same scenario set with `codex_validate_route=far_loop`
and `codex_validate_route=seam_cross`. If one of those routes reveals a new
dominant blocker, create a follow-up spec amendment instead of widening this
spec mid-implementation.

## Out-of-scope

- broad frontier-planning retune before player-hot publication is fixed
- vehicle/train runtime
- observatory JSON schema changes
- new always-on diagnostics or a second perf subsystem
- relaxing `full_ready`, `visible`, or occupancy correctness
- debug-camera-driven widening of runtime streaming scope
- save/load redesign
- visible `terrain-only` publish-first behavior
- generic staged-install rewrite unless later proof shows player-hot publication
  is already fixed and staged install is still dominant
