---
title: World Startup and Runtime Perf Investigation
doc_type: execution
status: draft
owner: engineering
source_of_truth: false
version: 0.1
last_updated: 2026-04-04
related_docs:
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/PUBLIC_API.md
  - ../02_system_specs/world/DATA_CONTRACTS.md
  - ../04_execution/boot_streaming_perf_analysis.md
  - ../04_execution/chunk_boot_streaming_rollout.md
---

# World Startup and Runtime Perf Investigation

This document records the focused investigation performed on 2026-04-04 for the following player-facing complaints:

- after pressing `высадиться`, the loading screen appears immediately but actual loading/logs do not start for minutes
- startup feels weak or blocked before the world becomes truly playable
- some world work does not seem to converge after movement
- movement, mining, and redraw still produce visible hitches

This is an execution report based on bounded code-path review and measured perf artifacts.
It does not replace canonical API or contract documents.

## Purpose

This file exists to answer:

- what exactly blocks startup after the loading screen becomes visible
- whether the current stall is still caused by `reroll` / seed search
- which measured stage currently dominates total world initialization
- where runtime world convergence is incomplete after traversal
- which runtime hitch classes remain during movement, mining, and redraw
- what should be fixed first versus later

## Scope and method

Investigation stayed inside the documented startup and world-runtime boundaries.

Reviewed code paths:

- `scenes/ui/world_creation_screen.gd`
- `scenes/world/game_world.gd`
- `core/autoloads/world_generator.gd`
- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/chunk_manager.gd`

Artifacts reviewed or produced:

- `debug_exports/perf/boot_seed12345.log`
- `debug_exports/perf/boot_seed12345_summary.md`
- `debug_exports/perf/boot_init_breakdown_seed12345.log`
- `debug_exports/perf/boot_init_breakdown_seed12345_summary.md`
- `debug_exports/perf/runtime_far_loop_init_breakdown_seed12345.log`
- `debug_exports/perf/runtime_far_loop_init_breakdown_seed12345_summary.md`

Commands used for proof:

```powershell
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_quit_on_boot_complete codex_world_seed=12345
.\Godot_v4.6.1-stable_win64_console.exe --headless --path . --scene res://scenes/world/game_world.tscn -- codex_validate_runtime codex_validate_route=far_loop codex_world_seed=12345
```

Investigation-only timing markers were added locally to:

- `core/autoloads/world_generator.gd`
- `core/systems/world/world_pre_pass.gd`

These markers were used only to attribute the stall more precisely.
They are not themselves a gameplay fix.

## Executive summary

The current startup stall is no longer explained by `reroll`.

The loading screen becomes visible almost immediately, but world startup then blocks inside a synchronous `WorldGenerator.initialize_world(seed)` call that runs before the scene switch into `GameWorld`.
That is why the user sees the loading screen but does not see `GameWorld` boot logs for a long time: the boot scene has not been entered yet.

The dominant cost inside that hidden stall is now `WorldPrePass.compute()`.
Measured breakdown shows that the largest offenders are:

- `ridge_strength_grid`
- `river_extraction`

Runtime traversal no longer points to chunk load starvation as the main "world is not loading" symptom.
The measured route completes, the load queue drains to zero, and redraw queue reaches idle, but catch-up still reports `blocker=topology`.
So the current incomplete-convergence symptom after movement is primarily topology convergence, not missing chunk truth.

Movement and redraw still hitch under runtime load because visual redraw and topology work both exceed their budget envelope in hot windows.
Mining does exceed its contract in some samples, but it is secondary compared with startup pre-pass cost and traversal redraw/topology debt.

## Confirmed startup chain for `высадиться`

The button path currently behaves like this:

1. `world_creation_screen.gd` creates and shows the loading screen.
2. The code waits for `screen_presented`.
3. The code waits one frame.
4. The code calls `WorldGenerator.initialize_world(seed_val)` synchronously.
5. Only after that call returns does the code switch to `res://scenes/world/game_world.tscn`.

The practical consequence is critical:

- the loading screen is honest about "we are busy"
- but the heavy work is still happening before `GameWorld` owns the boot flow
- therefore `GameWorld` boot logs do not appear until the hidden pre-scene initialization finishes

This is the direct explanation for the user report:

- loading screen appears immediately
- logs do not move for a long time
- loading only seems to "start later"

It is not starting later.
It is already blocked inside synchronous world initialization before the scene change.

## Why this is not `reroll` anymore

Current canonical docs explicitly describe runtime initialization as a single deterministic publication of the requested seed.
The relevant contract/API text says runtime initialization does not perform:

- landmark validation during boot
- neighboring-seed search
- threshold remediation

That matters because the old mental model was:

- world stalls because the runtime keeps searching for a better seed or rerolling constraints

The current model is:

- runtime boot computes one deterministic pre-pass snapshot for the requested seed
- the stall is the cost of that compute itself, not seed search

So the right question is no longer "what reintroduced reroll?"
The right question is "why is synchronous pre-pass compute this expensive in the startup path?"

## Measured startup timings

### Existing older boot artifact

The older boot artifact already showed that the loading screen itself was not the bottleneck:

| Metric | Value |
|---|---:|
| `Startup.start_to_loading_screen_visible_ms` | `16.21 ms` |
| `_init_world_generator` | `134136.57 ms` |
| `Startup.loading_screen_visible_to_startup_bubble_ready_ms` | `168914.07 ms` |
| `Startup.startup_bubble_ready_to_boot_complete_ms` | `29586.29 ms` |

This was the first strong sign that the issue lived inside initialization, not in screen presentation.

### New boot breakdown artifact

After adding stage timings, the same startup path was re-run and attributed more precisely:

| Metric | Value |
|---|---:|
| `Startup.start_to_loading_screen_visible_ms` | `18.36 ms` |
| `WorldGenerator._setup_world_pre_pass.compute` | `113276.91 ms` |
| `WorldGenerator.initialize_world.setup_world_pre_pass` | `113277.07 ms` |
| `WorldGenerator.initialize_world` | `113279.59 ms` |
| `Startup.loading_screen_visible_to_startup_bubble_ready_ms` | `138226.07 ms` |
| `Startup.startup_bubble_ready_to_boot_complete_ms` | `22470.29 ms` |

Interpretation:

- showing the loading screen is effectively free relative to the stall
- the long hidden wait is dominated by pre-pass setup/compute
- the remainder of boot after startup bubble ready is much smaller than the pre-pass stall

### Runtime validation run with deeper pre-pass attribution

The far-loop validation run confirmed the same structure under a runtime scenario:

| Metric | Value |
|---|---:|
| `Startup.start_to_loading_screen_visible_ms` | `19.76 ms` |
| `WorldGenerator._setup_world_pre_pass.compute` | `130844.67 ms` |
| `WorldGenerator.initialize_world.setup_world_pre_pass` | `130844.83 ms` |
| `WorldGenerator.initialize_world` | `130847.38 ms` |
| `Startup.loading_screen_visible_to_startup_bubble_ready_ms` | `160479.87 ms` |
| `Startup.startup_bubble_ready_to_boot_complete_ms` | `27844.65 ms` |

Again, the same pattern holds:

- the loading screen is visible almost immediately
- the user-facing wait is dominated by synchronous pre-pass compute
- total startup pain is now explained primarily by world generation pre-pass cost

## Dominant startup bottleneck inside `WorldPrePass.compute()`

The runtime breakdown identified the current top offenders:

| Stage | Time |
|---|---:|
| `WorldPrePass.compute.ridge_strength_grid` | `91720.32 ms` |
| `WorldPrePass.compute.river_extraction` | `23960.23 ms` |
| `WorldPrePass.compute.continentalness` | `3844.52 ms` |
| `WorldPrePass.compute.lake_aware_fill` | `3150.45 ms` |
| `WorldPrePass.compute.rain_shadow` | `2017.07 ms` |
| `WorldPrePass.compute.flow_directions` | `1844.51 ms` |
| `WorldPrePass.compute.flow_accumulation` | `1506.03 ms` |

This means the current startup stall is not a broad "everything is slow" problem.
It is heavily concentrated in two specific pre-pass stages:

1. `ridge_strength_grid`
2. `river_extraction`

Those two stages alone account for the overwhelming majority of measured pre-pass time.

## Comparison with the earlier boot analysis

This report does not invalidate `boot_streaming_perf_analysis.md`.
Instead, it shows that the bottleneck has shifted.

The earlier analysis identified a boot path where:

- chunk boot had already entered the scene boot loop
- redraw scheduling and first-playable gates dominated the wait

The current investigation found an earlier bottleneck:

- world creation stalls before `GameWorld` scene ownership
- the heavy work is synchronous generator pre-pass compute
- `GameWorld` logs are delayed because the scene is not active yet

So the current user-visible "nothing happens after loading screen" complaint is a different class of bottleneck from the older redraw-focused first-playable delay.

Both classes may exist in the project.
But for this complaint, the pre-scene pre-pass stall is the first-order cause.

## Runtime movement / redraw weak spots

The far-loop validation route completed successfully:

- route completed: `yes`
- validation failed: `no`
- catch-up timeout: `no`

So the world does keep functioning under traversal.
However, the logs still show several concrete runtime weak spots.

### 1. Visual redraw queue pressure remains high

The summary repeatedly reports:

- `scheduler.visual_queue_depth.full_far: 355`
- `scheduler.visual_queue_depth.terrain_near: 23`
- `FrameBudgetDispatcher.visual.chunk_manager.streaming_redraw: ~9-10+ ms`

This means traversal continues to carry a large visual backlog, especially in far/full redraw work.

### 2. Redraw work still spikes beyond healthy frame-budget envelopes

Typical redraw-step times often sit around `2.5-3.2 ms`, but the runtime log also contains significantly larger bursts such as:

- `20.95 ms`
- `11.70 ms`
- `8.36 ms`
- `7.84 ms`
- multiple `7-8+ ms` redraw steps inside hot windows

That is enough to create visible hitch windows even when average frame time later recovers.

### 3. Topology work contributes meaningful runtime pressure

The same summary shows:

- `Topology.runtime.scan: 4.66 ms`
- `FrameBudgetDispatcher.topology.chunk_manager.topology_rebuild: 6.12 ms`

These numbers are large enough to matter in the same frames where redraw work is already expensive.

### 4. Some hot windows are substantially worse than the final frame summary

The final summary is relatively mild:

- average frame time around `15.3 ms`
- `p99` around `25.0 ms`
- `hitches=6`

But intermediate runtime windows in the raw log show much worse temporary states, including:

- `avg=19.0 ms, p99=79.6 ms, hitches=32`
- `avg=18.9 ms, p99=51.5 ms, hitches=32`
- `avg=18.4 ms, p99=51.0 ms, hitches=38`

So the runtime path is not uniformly bad, but it is still capable of producing obvious player-facing hitch bursts during traversal.

## Mining weak spots

Mining does exceed contract in measured samples, but it is not the primary cause of the long startup complaint.

Observed warnings:

- `ChunkManager.try_harvest_at_world took 2.03 ms (contract: 2.0 ms)`
- `ChunkManager.try_harvest_at_world took 3.37 ms (contract: 2.0 ms)`
- `ChunkManager.try_harvest_at_world took 3.51 ms (contract: 2.0 ms)`

Interpretation:

- mining hitch exists
- the harvest path is still worth tightening
- but this is a secondary issue compared with startup pre-pass cost and runtime redraw/topology backlog

## Boot apply weak spots that still remain

The new instrumentation run also shows boot apply steps still exceeding their per-step budget:

- `(0, -1)` took `13.7 ms` with an `8.0 ms` budget
- `(0, 0)` took `13.6 ms`
- `(1, 0)` took `13.8 ms`
- `(63, 0)` took `13.4 ms`
- `(63, -1)` took `14.8 ms`

So even after the dominant pre-pass stall is isolated, boot apply still needs attention.
It is simply not the largest problem in the measured startup path right now.

## Where the world currently "does not finish loading"

The user-facing symptom "world does not fully load" is currently better described as "runtime catch-up does not fully converge".

The far-loop validation reached all intended waypoints and ended with:

- `streaming_truth_idle=true`
- `redraw_idle=true`
- `load_queue=0`
- `topology_ready=false`
- `native_topology=false`
- `native_dirty=false`
- `dirty=true`
- `build_in_progress=true`
- `blocker=topology`

This is important because it rules out the simplest explanation.

The problem is not:

- chunks still waiting in the streaming load queue
- redraw still obviously backed up at the end
- route failure due to missing world data

The problem is:

- topology remains not-ready even after streaming truth and redraw both report idle

So the present "world did not finish loading" symptom is primarily topology convergence debt.

## Interpretation of the topology blocker

Based on the current code review, the relevant script-topology path behaves like this:

- `is_topology_ready()` returns false while `_is_topology_dirty` or `_is_topology_build_in_progress` remain active
- `_tick_topology()` refuses to start or finish the rebuild while other required conditions are not satisfied
- `_mark_topology_dirty()` resets the state back to dirty/not-started

The validation artifact proves the runtime ends in:

- `dirty=true`
- `build_in_progress=true`
- `topology_ready=false`

This strongly suggests that topology is staying in a non-converged state after traversal churn.

What is not yet proven from this investigation:

- the exact mutation site or event sequence that keeps topology dirty or restarts build progress

So topology has been localized as the current blocker class, but not yet reduced to a single definitive root-cause method.

## What currently lags by category

### Startup

Primary bottleneck:

- synchronous `WorldGenerator.initialize_world()` before scene switch
- dominated by `WorldPrePass.compute()`
- especially `ridge_strength_grid` and `river_extraction`

### Movement / traversal

Primary bottlenecks:

- visual redraw queue debt
- redraw bursts larger than a healthy per-frame budget
- topology rebuild/scan cost overlapping with redraw

### Mining

Primary bottleneck:

- `try_harvest_at_world()` over contract in some samples

Secondary compared with:

- startup pre-pass stall
- runtime redraw/topology pressure

### Rendering / visual completion

Primary bottlenecks:

- `streaming_redraw` regularly above ideal budget in hot windows
- large `full_far` queue depth
- redraw-step bursts into the `7-20 ms` range

## Recommended fix order

The current evidence supports the following order of operations.

### 1. Fix the startup critical path first

Do not treat the delayed logs as a logging problem.
The real issue is the synchronous compute on the startup critical path.

Priority actions:

- stop paying the full `WorldGenerator.initialize_world()` stall before scene switch, or at minimum make that staged ownership explicit
- if startup must still block there temporarily, keep progress reporting honest and instrumented

Important caution:

- moving the scene switch earlier may improve observability
- but it does not solve total wait unless the pre-pass cost itself is also reduced or staged

### 2. Optimize or split `WorldPrePass.compute()`

This is the highest-value pure performance target now.

Start with:

1. `ridge_strength_grid`
2. `river_extraction`

Those are the two stages most likely to unlock a large startup improvement.

### 3. Investigate topology convergence separately from chunk loading

Do not misclassify the current end-of-traversal blocker as a streaming load issue.

The next topology investigation should answer:

- what keeps `_is_topology_dirty` true late in the route
- what keeps `_is_topology_build_in_progress` true after other queues are idle
- whether topology is being retriggered by mining/redraw/chunk lifecycle churn

### 4. Reduce runtime redraw bursts after topology is understood

After startup pre-pass and topology convergence are addressed, the next visible runtime gain is likely to come from:

- lowering redraw-step spikes
- reducing far/full visual queue debt
- keeping redraw/topology/shadow work from colliding in the same frames

### 5. Triage mining overages as a smaller follow-up

Mining is still worth tightening, but it should not be treated as the primary explanation for the user's startup complaint.

## Concrete conclusions

The investigation answers the original player-facing questions directly.

### Why does the loading screen appear but logs do not start for minutes?

Because the code currently blocks inside synchronous `WorldGenerator.initialize_world(seed)` before switching to `GameWorld`.
The scene that would emit the later boot logs has not taken over yet.

### Was this previously caused by `reroll`, and is it still that?

No.
Current contracts and API docs describe deterministic single-seed initialization with no runtime seed search/reroll in this path.
The measured stall is now the cost of pre-pass computation itself.

### Where is the world not fully loading?

Not primarily in the chunk load queue.
The measured route drains streaming truth and redraw, but ends with `blocker=topology`.

### What currently lags during movement / mining / rendering?

Movement and rendering:

- redraw queue debt
- redraw bursts
- topology work overlap

Mining:

- harvest path over contract in some samples

Startup:

- overwhelmingly dominated by synchronous pre-pass compute

## Open questions for the next pass

- Can `WorldPrePass` be cached, staged, or partially published without violating deterministic world contracts?
- Why does topology remain `dirty=true` and `build_in_progress=true` after far-loop catch-up reaches idle for load/redraw?
- Is the best short-term startup fix to change ownership flow, reduce pre-pass cost, or do both in one bounded iteration?
- Which portion of redraw burst cost is terrain publication itself versus shadow/border/topology follow-up work in the same frame?

## Evidence index

Primary startup evidence:

- `debug_exports/perf/boot_seed12345.log`
- `debug_exports/perf/boot_seed12345_summary.md`
- `debug_exports/perf/boot_init_breakdown_seed12345.log`
- `debug_exports/perf/boot_init_breakdown_seed12345_summary.md`

Primary runtime evidence:

- `debug_exports/perf/runtime_far_loop_init_breakdown_seed12345.log`
- `debug_exports/perf/runtime_far_loop_init_breakdown_seed12345_summary.md`

Primary code-path evidence:

- `scenes/ui/world_creation_screen.gd`
- `scenes/world/game_world.gd`
- `core/autoloads/world_generator.gd`
- `core/systems/world/world_pre_pass.gd`
- `core/systems/world/chunk_manager.gd`

## Final judgment

The current startup complaint is real and well-explained by measured data.

The loading screen is not the slow part.
The hidden synchronous world initialization behind it is the slow part.

The current root cause is no longer `reroll`.
The current root cause is the cost of deterministic pre-pass world computation on the startup critical path, with `ridge_strength_grid` and `river_extraction` dominating that cost.

The current runtime "world did not finish loading" symptom is not best explained by chunk streaming backlog.
It is better explained by topology convergence failing to settle after traversal.
