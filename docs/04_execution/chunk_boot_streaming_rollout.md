---
title: Chunk Boot Streaming Rollout
doc_type: execution
status: proposed
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-28
related_docs:
  - ../00_governance/PERFORMANCE_CONTRACTS.md
  - ../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../02_system_specs/world/world_generation_foundation.md
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../04_execution/MASTER_ROADMAP.md
---

# Chunk Boot Streaming Rollout

This document defines the rollout for fixing slow world boot caused by synchronous chunk loading and heavy main-thread chunk materialization.

It is an execution document.
It does not replace architectural truth for world generation or runtime ownership.

## Purpose

This file exists to answer:
- what exactly is wrong with current world boot loading
- what must change first versus later
- what can be parallelized safely
- what must stay on the main thread
- how to convert the current boot path into a staged, budgeted, low-hitch startup pipeline
- what follow-up specs agents should derive next

## Problem statement

Current world boot loads the initial chunk bubble through a synchronous path.

Observed behavior from runtime review:
- boot calls direct `_load_chunk()` for each startup chunk
- boot bypasses the staged async streaming pipeline already present in `ChunkManager`
- chunk generation on surface uses a heavy per-tile build path on the main thread
- boot forces full redraw with `complete_redraw_now()` for each chunk
- chunk topology rebuild runs after the boot bubble is loaded

Observed performance symptoms from the reviewed log:
- `ChunkManager._load_chunk (...)` is repeatedly around `1340-1435 ms` per chunk
- `Chunk._redraw_all (...)` ranges from roughly `24 ms` to `311 ms`
- `_rebuild_loaded_mountain_topology.boot` is around `258 ms`
- runtime frame budget logs remain near zero during boot because the boot path is not using the normal streaming dispatcher path

This means the startup world bubble is effectively serialized and fully blocking.

## Root cause summary

The primary bottleneck is not GPU rendering.
The primary bottleneck is synchronous boot-time chunk generation and boot-time forced redraw.

The current boot path has three architectural problems:

1. Boot does not use the staged compute/apply pipeline.
2. Boot performs expensive chunk content generation on the main thread.
3. Boot forces immediate full visual completion for too many chunks.

## Rollout philosophy

The fix must follow this rule:

**parallelize pure data generation, serialize scene-tree apply, and strictly budget visual completion.**

Do not try to make every chunk fully ready at once.
Do not move scene-tree work into worker threads.
Do not optimize topology first while boot still blocks on synchronous chunk generation.
Do not hide the issue behind a loading screen while keeping the same serialized architecture.

## Hard rules

1. Pure chunk compute may run in worker threads.
2. Scene-tree mutation must remain on the main thread.
3. Boot must stop calling the legacy fully synchronous surface load path for the startup bubble.
4. Full redraw at boot must be limited to near-player chunks only.
5. Flora must not remain in the critical path unless profiling proves it is negligible.
6. Boot topology work must never be optimized before boot generation/apply are staged correctly.
7. Any rollout step must preserve deterministic output for the same seed and coordinates.

## Threading boundary

### Allowed off-main-thread
- generation of chunk `native_data`
- detached chunk content builder work
- optional flora placement compute if it remains pure data
- optional cache warmup of surface payloads

### Must stay on main thread
- `Chunk.new()`
- `TileMapLayer` mutation
- `add_child()`
- scene-tree ownership changes
- final chunk apply into visible runtime world
- any redraw step that touches Godot nodes/layers

## Non-goals

This rollout does not attempt to:
- redesign world generation algorithms
- redesign mountain topology semantics
- change biome logic
- change save format
- fully solve streaming for all later runtime scenarios in one pass

The immediate target is startup boot for the initial loaded chunk bubble.

## Current reviewed code hotspots

Primary reviewed files:
- `core/systems/world/chunk_manager.gd`
- `core/systems/world/chunk.gd`
- `core/systems/world/chunk_content_builder.gd`
- `core/systems/world/surface_terrain_resolver.gd`
- `core/systems/world/chunk_flora_builder.gd`
- `core/autoloads/world_generator.gd`

Specific reviewed findings:
- `boot_load_initial_chunks()` currently loops startup coords and calls direct `_load_chunk()`
- `_tick_loading()` and related staged runtime jobs are disabled during boot via `_is_boot_in_progress`
- `_load_chunk_for_z()` uses the heavy `build_chunk_content()` path for surface chunks in the synchronous flow
- `Chunk.populate_native(..., instant=true)` plus `complete_redraw_now()` drives immediate expensive visual work
- flora calculation is still part of the synchronous load path for surface chunks

## Target state

The target boot pipeline is:

1. Identify startup chunk bubble and priority order.
2. Launch a bounded number of worker compute tasks for chunk `native_data`.
3. Collect completed compute results into a ready queue.
4. Apply chunk nodes on the main thread under a strict per-frame or per-step budget.
5. Visually complete only the minimum near-player set immediately.
6. Let farther chunks finish progressive redraw after control is nearly ready.
7. Run topology and secondary visual work only after the critical boot slice is complete.

## Rollout phases

### Phase 1 — Freeze the boot contract

Goal:
- define exactly what boot must deliver before player control begins

Deliverables:
- explicit definition of the startup chunk bubble
- explicit definition of near-player visual readiness versus deferred readiness
- explicit definition of boot completion gates
- explicit definition of which chunk rings must be instant-complete and which may remain staged

Success criteria:
- the project has a written boot readiness contract
- boot no longer means "all startup chunks fully complete in the old synchronous sense"

### Phase 2 — Remove synchronous surface boot generation from the critical path

Goal:
- stop using the old direct heavy surface chunk load path during boot

Deliverables:
- boot path no longer calls the legacy direct `_load_chunk()` surface generation path for the startup bubble
- boot generation uses `build_chunk_native_data()` or an equivalent detached-builder native-data path
- compute path remains deterministic and pure-data only

Success criteria:
- startup chunk generation can proceed without blocking the main thread on per-chunk full world build work
- profiling shows boot chunk generation no longer appears as repeated ~1.3-1.4s synchronous `_load_chunk()` calls

### Phase 3 — Add bounded parallel compute for boot chunk payloads

Goal:
- compute multiple startup chunks in parallel without saturating runtime incorrectly

Deliverables:
- bounded boot compute queue
- bounded concurrency cap, expected initial range: `2-4` workers, not `25`
- deterministic ordering policy for completed results
- cancellation or discard of stale results if boot state changes

Success criteria:
- startup compute throughput increases materially
- CPU saturation remains bounded and intentional
- results remain deterministic

### Phase 4 — Separate compute-ready from scene-ready

Goal:
- make it impossible for compute completion to force immediate visual completion for every chunk

Deliverables:
- explicit ready queue for computed `native_data`
- explicit main-thread apply stage
- explicit distinction between:
  - computed
  - applied to runtime structures
  - visually complete

Success criteria:
- the code has separate states for chunk compute and chunk visual readiness
- boot progress reporting reflects these states honestly

### Phase 5 — Budget main-thread apply

Goal:
- prevent the boot fix from simply moving the hitch from compute to finalize/apply

Deliverables:
- per-frame or per-step budget for chunk apply/finalize on main thread
- apply ordering by distance to player
- guardrails so boot does not attach too many chunks in one frame

Success criteria:
- main-thread hitches during apply are controlled and measurable
- central chunk and immediate neighbors appear first

### Phase 6 — Limit instant redraw to the critical ring only

Goal:
- stop paying full redraw cost for the entire startup bubble before gameplay can start

Deliverables:
- immediate full visual completion only for player chunk and selected near ring
- progressive redraw for farther chunks
- explicit policy for cover/cliff/flora completion order

Recommended first policy:
- ring 0: immediate
- ring 1: immediate only if profiling proves acceptable
- outer startup ring(s): progressive after near-ready boot

Success criteria:
- boot no longer performs forced full redraw for every startup chunk
- far chunk visuals may still complete shortly after spawn without hurting startup readiness

### Phase 7 — Remove flora from the critical boot path unless proven cheap

Goal:
- stop flora compute from delaying first playable state

Deliverables:
- flora marked as deferred or optional during critical boot slice
- flora can compute in worker phase or in post-ready follow-up phase
- central chunk policy documented if some minimum flora is needed instantly

Success criteria:
- first-playable boot no longer waits on nonessential flora for the full bubble

### Phase 8 — Re-stage topology after critical boot readiness

Goal:
- keep topology correct without forcing it ahead of more important boot work

Deliverables:
- topology rebuild or ensure step triggered after critical boot slice is present
- topology work does not block near-player first-playable readiness more than necessary
- if native topology builder is active, boot integrates with it without reintroducing sync stalls

Success criteria:
- topology correctness is preserved
- topology is no longer the first optimization target or first blocking step

### Phase 9 — Instrumentation and acceptance profiling

Goal:
- make the rollout measurable and resistant to regressions

Deliverables:
- separate metrics for:
  - compute queue wait
  - worker compute time per chunk
  - apply/finalize time per chunk
  - redraw step cost by phase
  - flora compute cost
  - topology cost during boot
- boot summary logging for first-playable readiness and full-startup completion

Success criteria:
- logs can answer where time is spent without ambiguous blended timings
- performance regressions are locally attributable

## Recommended implementation order

1. Write the boot readiness contract.
2. Replace synchronous boot surface generation path.
3. Introduce bounded parallel compute queue.
4. Separate compute-ready from applied-ready.
5. Budget main-thread apply.
6. Reduce instant redraw scope.
7. Defer flora.
8. Re-stage topology.
9. Tighten instrumentation and iterate.

## Explicit anti-patterns

Do not:
- spawn `25` full chunk jobs and treat that as the final design
- mutate scene-tree content from worker threads
- preserve `complete_redraw_now()` for the whole startup bubble
- keep using old synchronous `_load_chunk()` for boot and just add more awaits around it
- declare boot solved because the loading screen hides stalls
- optimize mountain topology first while the boot path still serializes chunk generation

## Acceptance checkpoints

The rollout is successful only if the following become true in order:

1. Boot no longer serially blocks on repeated synchronous surface chunk loads.
2. Startup chunk compute can overlap across a bounded worker set.
3. Main-thread apply is budgeted and prioritized near the player.
4. Full visual completion is no longer required for the entire startup bubble before first playable state.
5. Flora is no longer on the critical path by default.
6. Topology correctness is preserved after boot staging changes.
7. Logs clearly separate compute cost, apply cost, redraw cost, flora cost, and topology cost.

## First playable contract

Recommended first playable state:
- player chunk is loaded and visually complete
- immediate movement/readability ring is present
- collision/navigation-critical terrain is ready in the near ring
- farther startup chunks may still be finalizing progressively
- topology may complete immediately after first playable if required by dependent systems

This should be treated as the default target unless a stricter player-facing requirement is later approved.

## Risks

### Risk 1 — Hidden thread-unsafety in world compute chain

Mitigation:
- keep initial worker rollout bounded
- use detached builders only
- profile and validate deterministic output across repeated seeds

### Risk 2 — Hitch migration from compute to apply

Mitigation:
- main-thread apply budget from the start
- distinct apply metrics
- explicit limit on chunks finalized per frame

### Risk 3 — Visual pop-in becomes too aggressive

Mitigation:
- prioritize ring-based readiness
- allow ring-0 or ring-1 immediate completion based on profiling
- separate gameplay-critical readiness from cosmetic completion

### Risk 4 — Boot progress becomes misleading

Mitigation:
- progress must reflect compute-ready versus scene-ready versus visually-ready states

## Derived specs that should be written next

After this rollout is accepted, agents should derive at least the following specs:

1. `boot_chunk_readiness_spec`
   - exact readiness rings
   - first-playable gate
   - deferred completion rules

2. `boot_chunk_compute_pipeline_spec`
   - worker concurrency model
   - queue semantics
   - cancellation/discard rules
   - deterministic guarantees

3. `boot_chunk_apply_budget_spec`
   - main-thread apply budget
   - per-frame limits
   - priority policy by distance

4. `boot_visual_completion_spec`
   - which redraw phases are immediate
   - which phases are deferred
   - flora treatment during boot

5. `boot_topology_integration_spec`
   - when topology becomes mandatory
   - native versus scripted topology behavior after staged boot

6. `boot_performance_instrumentation_spec`
   - required metrics
   - log format
   - acceptance thresholds

## Suggested task slicing for implementation

A practical implementation breakdown is:
- instrumentation patch first
- boot-path compute refactor second
- bounded worker queue third
- main-thread apply budget fourth
- redraw/flora deferral fifth
- topology restaging sixth
- polish and threshold tuning last

## Definition of done

This rollout is done when:
- the startup world bubble no longer depends on repeated synchronous `_load_chunk()` calls
- boot compute is bounded-parallel and deterministic
- main-thread apply is budgeted
- far startup chunks no longer force immediate full redraw
- flora is not part of the critical path by default
- instrumentation can prove the new cost distribution
- follow-up specs exist for the steady-state architecture

## Status note

As of 2026-03-28, this rollout is proposed from direct review of the current boot loading path and startup performance logs.
It should be treated as the execution source of truth for fixing boot chunk loading before deeper optimization work branches into narrower specs.
