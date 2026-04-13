---
title: Zero-Tolerance Chunk Readiness
Doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-13
depends_on:
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
related_docs:
  - chunk_visual_pipeline_rework_spec.md
---

# Feature: Zero-Tolerance Chunk Readiness

## Design Intent

This spec replaces all soft, progressive, or debt-based interpretations of chunk readiness for player-reachable world space.

Target player experience:

- the world must feel seamless, endless, and load-free
- the player must never step onto a chunk that is not fully ready
- no visible catch-up, no "later redraw", no pop-in, no missing flora, no delayed cliffs, no delayed seams, no hidden second pass
- no blocking walls, stop-gates, fake collisions, slowdowns, or explicit waits to hide preparation
- if the player can physically enter a chunk, that chunk is already finished in the final shipped sense of the word

This is a zero-tolerance contract. Any runtime state where the player enters a chunk that is not fully ready is a correctness bug, not a performance tradeoff.

This spec explicitly rejects the previous model where near/player chunks could become first-pass ready first and converge later. That model may be acceptable for some games; it is not acceptable for this project.

## Non-Negotiable Product Contract

### Core invariant

For every frame of active gameplay:

- the chunk currently occupied by the player must be `full_ready`
- the player must never cross a chunk boundary into a chunk that is not `full_ready`
- this applies on surface and underground z-levels
- this applies during walking, sprinting, vehicle driving, and train travel

### `full_ready` means fully generated, not "good enough"

`full_ready` includes all final player-visible and gameplay-relevant state for the chunk, with no exceptions:

- terrain
- water
- cliffs
- cover / roof
- flora / grass / decorative vegetation
- POI / props / world features
- collisions
- navigation / pathing data
- seams with neighbors
- fog / visibility state required for the chunk to render correctly
- shadows / lighting data required for the final intended presentation
- visual overlays and any other chunk-owned presentation layers

`full_ready` does **not** mean:

- first pass ready
- terrain-only ready
- visually acceptable for now
- ready except for cosmetics
- ready except for flora
- ready except for cliff overlays
- ready except for seam repair

If any of the above are still pending, the chunk is not `full_ready`.

## Explicit Rejections

The following patterns are forbidden for player-reachable chunks:

- progressive catch-up after player entry
- "first pass now, full redraw later"
- main-thread or worker fallback implementations for critical chunk generation and critical visual phases
- GDScript fallback for native generation, native visual payload build, or any critical visual convergence step
- entering a chunk and then repairing it behind or around the player
- hidden correctness debt re-labeled as background convergence
- compatibility logic that preserves old soft-readiness behavior

This feature intentionally permits breaking internal APIs, deleting compatibility helpers, and removing old runtime paths.

## Hardware and Performance Target

Baseline target machine:

- CPU: Ryzen 5 2600
- GPU: GTX 1060 6 GB
- RAM: 32 GB
- target framerate: 60 FPS minimum during ordinary gameplay movement on the baseline machine

Experience target:

- movement through the world should feel comparable to a high-quality seamless factory / sandbox game where chunk loading is not perceptible during normal play
- walking, sprinting, vehicles, and trains must not expose chunk streaming debt to the player

This target is a design constraint. It is not optional and must shape architecture, not merely tuning.

## Scope of the Contract

### In scope

- surface z-levels
- underground z-levels
- player walking and sprinting
- future vehicles
- future trains
- runtime chunk generation
- runtime chunk installation
- runtime final visual publication
- readiness gating and observability
- destruction of fallback paths

### Out of scope

- preserving backward compatibility with the old chunk runtime
- preserving current internal file boundaries
- preserving save compatibility solely to protect the old runtime design
- debug freecam / noclip behavior as a product constraint

## Architectural Consequence

The current concept of "player chunk can be first-pass ready and converge later" must be removed from the player-reachable runtime contract.

A valid future runtime must satisfy the following:

1. critical frontier chunks are completed before player entry, not after
2. critical chunk preparation is native-only for generation and critical visual readiness
3. far/background work must never consume the capacity required to keep the frontier fully ready
4. readiness must be defined in terms of final shipped content, not phased approximation
5. any runtime path that can produce player-visible catch-up is architecturally incorrect and must be removed

## Required Runtime Model

### 1. Native-only critical path

For player-reachable chunk readiness, the critical path must be native-only.

Required:

- native-only chunk generation
- native-only critical visual payload generation
- native-only critical visual phase computation
- native-only or equivalently final-prepared data for any step that determines `full_ready`

Forbidden:

- GDScript fallback for `generate_chunk`
- GDScript fallback for prebaked visual payload generation
- GDScript fallback for critical near/player visual convergence
- hybrid runtime designs where correctness depends on a "temporary" script path

If a native path is not implemented yet, the correct action is to implement it or temporarily remove the dependent feature from the readiness contract. The correct action is not to silently route through a fallback.

### 2. Frontier-first scheduling

The world runtime must treat player-entry frontier work as sacred.

Required:

- dedicated reserved capacity for player/frontier chunk preparation
- hard preemption of far/background work when frontier readiness is threatened
- no starvation of player/frontier work by far full redraw, background convergence, cosmetic tasks, or long-running auxiliary generation

Forbidden:

- a shared worker pool policy where far work can occupy all compute slots while player-entry work waits
- queue fairness models that allow player-frontier readiness to lose to backlog depth
- any scheduler policy where the player chunk or immediate entry target can repeatedly requeue because worker capacity is saturated by unrelated work

### 3. Predictive readiness

The runtime must prepare chunks before the player reaches them.

Required:

- predictive precomputation based on player motion vector and reachable speed envelope
- readiness planning that accounts for walking, sprinting, vehicles, and trains
- explicit frontier budget sized for worst allowed ordinary travel speed on the target hardware

Forbidden:

- relying on current walking speed assumptions only
- relying on a human player's casual behavior to hide latency
- assuming later vehicles or trains can be solved with the same soft runtime model

### 4. Final-publication semantics

Chunk publication into player-reachable space must mean final publication.

Required:

- the chunk presented to the player is the final intended chunk state for that moment
- seams with already-reachable neighbors are already correct at publication time
- no delayed flora, cliff, or roof completion after the player steps into the chunk

Forbidden:

- publishing a partial chunk and planning to finish it later
- publishing a chunk whose final visual state still depends on deferred convergence
- a readiness state machine where player entry is allowed before terminal state

## Data Contracts - new and affected

### Affected layer: Chunk Readiness

- What:
  - a strict readiness contract for player-reachable chunks
- Owner (WRITE):
  - chunk runtime owner system
- Readers (READ):
  - movement, world runtime, diagnostics, tests
- Invariants:
  - `assert(player_chunk_is_full_ready, "player may not occupy a non-full-ready chunk")`
  - `assert(player_boundary_crossing_target_is_full_ready, "player may not enter a non-full-ready target chunk")`
  - `assert(full_ready_means_all_final_layers_present, "full_ready must include all final gameplay and visual layers")`
  - `assert(no_first_pass_semantics_in_player_contract, "first-pass readiness is not sufficient for player entry")`
- Forbidden:
  - using `first_pass_ready` or equivalent approximation as permission for player occupancy

### Affected layer: Streaming / Scheduling

- What:
  - frontier-first scheduling and reserved compute capacity
- Invariants:
  - `assert(frontier_work_has_reserved_capacity, "player/frontier preparation must have reserved compute capacity")`
  - `assert(far_work_cannot_starve_frontier, "far/background work must not starve player/frontier readiness")`
  - `assert(frontier_prediction_accounts_for_supported_travel_speeds, "frontier sizing must be based on supported movement speeds")`
- Forbidden:
  - one-pool fairness that can starve frontier work
  - processing far convergence while entry-critical chunks are threatened

### Affected layer: Native Runtime Ownership

- What:
  - removal of fallback implementations
- Invariants:
  - `assert(critical_chunk_generation_path_is_native_only, "critical chunk generation must be native-only")`
  - `assert(critical_visual_payload_path_is_native_only, "critical visual payload generation must be native-only")`
  - `assert(critical_visual_convergence_path_is_native_only, "critical visual convergence must be native-only")`
- Forbidden:
  - script fallback for critical readiness paths
  - compatibility adapters that preserve old hybrid behavior

## Migration Policy

This feature is intentionally destructive.

Allowed and expected actions:

- delete fallback code
- delete hybrid code
- break internal APIs
- rename readiness states
- replace existing scheduler logic
- replace existing chunk publication semantics
- invalidate old technical assumptions
- remove helpers whose only purpose was to support phased catch-up

Not required:

- preserving old implementation strategies
- preserving old internal call chains
- preserving current split of responsibility if that split fights the contract

## Required Implementation Strategy

The implementation must be delivered in hard stages.

### Iteration 1 - Contract Lock and Runtime Purge

Goal: remove the possibility of silently continuing the old hybrid design.

What is done:

- define and document the new `full_ready` contract as terminal and all-inclusive
- remove or mark-for-deletion all GDScript fallback paths for critical generation and critical visual readiness
- add runtime assertions and diagnostics that flag any player occupancy of a non-`full_ready` chunk as a correctness failure
- mark old phased catch-up semantics as invalid for player-reachable chunks

Acceptance tests:

- [ ] repository contains this spec and references it from affected docs where needed
- [ ] all critical fallback paths are either deleted or explicitly blocked from use in player-reachable runtime
- [ ] runtime asserts or fatal diagnostics exist for player occupancy of a non-`full_ready` chunk
- [ ] `first_pass_ready` is no longer treated as sufficient for player entry anywhere in the runtime

### Iteration 2 - Frontier-First Native Runtime

Goal: build a runtime that can actually satisfy the contract.

What is done:

- introduce reserved frontier compute capacity
- hard-separate frontier-critical work from far/background work
- design predictive preparation using player motion and supported speed classes
- ensure the target chunk for player entry is already `full_ready` before boundary crossing occurs

Acceptance tests:

- [ ] frontier/player work has reserved capacity that far work cannot steal
- [ ] no reproducible case exists where far backlog prevents frontier completion
- [ ] entering a new chunk on foot and sprint does not expose visible catch-up on target hardware
- [ ] the player chunk is always `full_ready` in ordinary runtime traversal

### Iteration 3 - Vehicles, Trains, Underground

Goal: extend the same strict contract to faster travel and all z-levels.

What is done:

- size predictive readiness and frontier preparation for vehicle movement
- size predictive readiness and frontier preparation for train movement
- apply identical readiness semantics to underground chunks
- ensure chunk entry remains invisible and seamless under supported movement modes

Acceptance tests:

- [ ] vehicles do not expose chunk catch-up
- [ ] trains do not expose chunk catch-up
- [ ] underground traversal does not expose chunk catch-up
- [ ] no movement mode supported by the game allows player entry into a non-`full_ready` chunk

## Observability and Test Requirements

The runtime must expose proof, not hope.

Required diagnostics:

- current player chunk readiness state
- target chunk readiness state at attempted boundary crossing
- frontier backlog depth
- reserved frontier capacity utilization
- far/background backlog depth
- cause-of-failure diagnostics for any contract breach
- explicit signal whenever a player-visible chunk is not `full_ready`

Required automated checks:

- traversal tests for ordinary walking
- traversal tests for sprinting
- traversal tests for vehicles
- traversal tests for trains
- traversal tests for underground entry
- stress tests with sustained movement in one direction over long distance

A run is considered failed if the player ever occupies a non-`full_ready` chunk, even for one frame.

## Definition of Done

This feature is done only when all of the following are true:

- the player never enters a non-`full_ready` chunk
- `full_ready` includes every final layer listed in this spec, including flora and cosmetics
- the player experiences seamless world traversal with no visible chunk loading or catch-up
- the runtime no longer depends on critical GDScript fallback paths
- walking, sprinting, vehicles, trains, surface, and underground all obey the same contract
- the target baseline machine sustains the intended seamless feel at 60 FPS class gameplay

If any player-reachable chunk can still be entered before full completion, the feature is not done.

## Explicitly Out of Scope for This Spec

- saving the old chunk runtime architecture
- retaining temporary compatibility helpers that undermine the contract
- accepting visual debt as an unavoidable part of traversal
- redefining `full_ready` to avoid hard engineering work

This spec exists specifically to prevent those compromises.
