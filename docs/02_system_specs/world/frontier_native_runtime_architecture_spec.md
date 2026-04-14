---
title: Frontier Native Runtime Architecture
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-04-13
depends_on:
  - zero_tolerance_chunk_readiness_spec.md
  - zero_tolerance_chunk_readiness_legacy_delete_list.md
  - DATA_CONTRACTS.md
  - ../../00_governance/PUBLIC_API.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
related_docs:
  - chunk_visual_pipeline_rework_spec.md
---

# Feature: Frontier Native Runtime Architecture

## Design Intent

This spec defines the target architecture that replaces the current chunk runtime.

The parent contract is already fixed by `zero_tolerance_chunk_readiness_spec.md`:

- the player must never occupy a non-`full_ready` chunk
- all player-visible world space must appear seamless and fully finished
- `full_ready` includes all final layers, including flora and cosmetics
- critical runtime correctness may not depend on fallback paths

This document answers the next question:

- how the new runtime must be built so the contract is actually achievable on the target machine

This is not a tuning spec. This is a replacement architecture spec.

## Decision: Current runtime is legacy

Effective immediately:

- the current chunk runtime is legacy
- the current hybrid progressive convergence model is deprecated
- the target architecture is a new frontier-native runtime

The implementation is not required to preserve the current runtime's structure, internal APIs, or intermediate semantics.

## Product Experience Target

The world must feel like seamless continuous space.

For the player:

- no visible chunk loading
- no visible chunk catch-up
- no terrain-first / flora-later publication
- no seam repair after reveal
- no cliff completion after reveal
- no delayed cosmetics after reveal
- no fake stop-gates or hidden waiting walls
- no special-case ugliness when moving fast

Movement modes covered by this runtime contract:

- walking
- sprinting
- vehicles
- trains
- underground staircase transition with fade

Debug freecam and dev noclip are out of scope.

## Baseline and Optimization Priority

Baseline target machine:

- CPU: Ryzen 5 2600
- GPU: GTX 1060 6 GB
- RAM: 32 GB
- target: 60 FPS class gameplay with seamless traversal feel

Optimization priority order:

1. correctness of the seamless contract
2. architectural simplicity and determinism
3. predictable latency for frontier preparation
4. measured memory efficiency
5. secondary throughput tuning

Memory may be spent to preserve the seamless contract, but only after the runtime is architecturally correct. Blind cache growth is forbidden as a substitute for a bad design.

## World Visibility Contract

The runtime contract is stricter than just "player chunk must be ready".

### Required visible-world invariant

Every chunk intersecting the active camera-visible world envelope must be `full_ready`.

This means the runtime must guarantee not only occupancy correctness but also visible-world correctness.

### Envelope components

The runtime must compute and maintain three distinct sets:

1. `occupancy_chunk`
   - the chunk currently occupied by the player

2. `camera_visible_set`
   - all chunks intersecting the camera rectangle plus a small safety margin against sub-frame camera movement and screen-edge exposure

3. `motion_frontier_set`
   - all chunks that can become visible or occupiable within the prediction horizon for the current movement mode

The runtime must guarantee:

- `occupancy_chunk` is `full_ready`
- every chunk in `camera_visible_set` is `full_ready`
- every chunk in `motion_frontier_set` is scheduled and protected by frontier capacity before it becomes visible or occupiable

## New High-Level Architecture

The new runtime is composed of the following subsystems.

### 1. Travel State Resolver

Responsibility:

- determine the current travel mode and speed class
- expose worst-case movement envelope for planning

Inputs:

- player velocity
- vehicle state
- train state
- underground transition state

Outputs:

- `travel_mode`
- `speed_class`
- `prediction_horizon_ms`
- `max_forward_distance`
- `max_lateral_deviation`
- `braking_window`

Notes:

- planning must be based on worst allowed ordinary movement, not current leisurely movement
- train mode must be treated as a first-class planning mode, not an afterthought

### 2. View Envelope Resolver

Responsibility:

- resolve which chunks are currently visible or imminently visible

Inputs:

- camera transform
- viewport size
- zoom
- display margin policy

Outputs:

- `camera_visible_set`
- `camera_margin_set`

Notes:

- visible-world correctness depends on this set, not only on player chunk position

### 3. Frontier Planner

Responsibility:

- build the set of chunks that must be prepared ahead of reveal and ahead of occupancy

Inputs:

- `travel_mode`
- movement vector
- braking window
- `camera_visible_set`
- current z-level or transition target

Outputs:

- `frontier_critical_set`
- `frontier_high_set`
- `background_set`

Rules:

- `frontier_critical_set` includes all chunks that can become visible or occupiable before the next safe planning update
- `frontier_high_set` includes near-follow-up work that soon becomes visible after the critical slice
- `background_set` includes all other preparation and retention work

Hard rule:

- no chunk may enter `camera_visible_set` or become occupiable unless it already graduated through the critical frontier path to `full_ready`

### 4. Native Chunk Packet Builder

Responsibility:

- produce the final authoritative chunk packet in native code

This builder replaces the old hybrid model where chunk generation, visual payload generation, and late convergence were split across fallback paths.

The native chunk packet must include everything required for terminal publication of the chunk:

- terrain
- water
- cliffs
- cover / roof data required for final presentation
- flora and decorative placement data
- POI / feature / prop placement data
- collision data
- navigation / pathing data
- seam-complete edge data
- fog / reveal presentation state required at publication time
- lighting / shadow data required for final intended presentation
- final overlay payloads

Hard rule:

- `full_ready` must be representable as "final chunk packet exists and has been published", not as "some packet exists and later systems will finish it"

### 5. Chunk Residency and Packet Cache

Responsibility:

- retain ready-to-publish and already-published chunk packets across motion
- manage memory intentionally

Cache classes:

- `hot_frontier`
  - packets required immediately for current visible and frontier-critical world
- `warm_predicted`
  - packets likely needed soon for continued motion
- `cold_retained`
  - packets kept temporarily to reduce rebuild churn when direction changes

Rules:

- caches store final packets, not half-finished convergence debt
- cache retention must be guided by motion prediction and measured residency value
- the runtime may use more memory to protect seamlessness, but cache growth must remain policy-driven and observable

### 6. Publication Coordinator

Responsibility:

- publish only final chunk packets to live world representation on the main thread

Publication must be minimal and mechanical:

- instantiate or reuse chunk node container
- apply final packet
- expose chunk as visible / occupiable only after successful publication

Forbidden:

- publish-then-finish-later
- publish terrain now and vegetation later
- publish seams before edge correctness is known
- publish partial packet subsets as a temporary state for visible chunks

### 7. Frontier Scheduler

Responsibility:

- assign compute and publication capacity in strict priority order

Scheduling lanes:

- `lane_frontier_critical`
- `lane_camera_visible_support`
- `lane_transition_target`
- `lane_background`

Hard rules:

- `lane_frontier_critical` capacity is reserved and cannot be stolen by background work
- `lane_transition_target` for underground staircase target preparation is treated as critical
- background tasks may not consume the last capacity required to preserve visible-world correctness
- fairness is subordinate to frontier correctness

Implementation note:

- whether this is one worker pool with strict reservation or multiple pools is an implementation choice
- the invariant is what matters: frontier-critical work cannot be starved

### 8. Underground Transition Coordinator

Responsibility:

- handle staircase descent / ascent as an explicit controlled transition

Rules:

- fade-out may begin before target reveal
- fade-in is forbidden until the target visible envelope is `full_ready`
- underground target preparation must obey the same full-ready contract as surface runtime
- a fade is allowed to hide the controlled layer transition; it is not allowed to hide incomplete chunks after reveal

## Chunk Size Policy

Chunk size is reopened as an architecture variable.

Allowed:

- keep current chunk size
- reduce chunk size
- increase chunk size
- redesign chunk sizing entirely

Required process:

- run a measured bake-off across multiple candidate chunk sizes on the baseline machine
- measure visible-world guarantee cost, publication overhead, cache locality, seam complexity, and train-speed frontier pressure

Decision rule:

- choose the chunk size that best satisfies the seamless contract on target hardware
- do not preserve the current size merely because the code already exists

## Determinism Policy

The new runtime is allowed to change world generation.

Not required:

- matching the old runtime's world output
- matching the old river layout
- preserving old generator quirks

Required:

- determinism within the new runtime for the same seed, world config, generator version, and runtime version
- explicit generator versioning so world outputs remain stable within a versioned generation model

This means:

- the new world generator may and should improve terrain, rivers, and structure quality
- but once the new generator version is chosen, it must be deterministic

## Startup and Handoff Policy

Startup may be slower than the current startup if that is required to preserve the seamless runtime contract.

### Required startup handoff rule

Player control may be handed off only when:

- the startup/player spawn position is anchored to the center tile of the ring-0 chunk, so handoff does not begin on a seam or 4-chunk junction
- all chunks intersecting the startup camera-visible envelope are `full_ready`
- the startup near envelope is the centered ring-0 spawn chunk plus all eight Chebyshev ring-1 neighbors, and all nine chunks are `full_ready`
- immediate motion frontier slices for initial movement are protected by frontier preparation
- all required publication for the startup slice is complete

Forbidden:

- first-playable semantics based on a partial first pass
- giving player control while visible chunks still owe final convergence
- startup handoff based on the hope that runtime catch-up will finish before the player notices

## Full Ready State Definition in the New Runtime

The new runtime reduces readiness ambiguity to a simpler truth model.

### Allowed terminal states

For player-reachable space, only these high-level states matter:

- `absent`
- `building_final_packet`
- `final_packet_ready_not_published`
- `full_ready`

### Forbidden player-reachable states

The following are forbidden as enterable or visible runtime outcomes:

- first-pass-only
- terrain-ready-but-not-final
- full-redraw-pending
- seam-fix-pending
- flora-pending
- cosmetics-pending
- cliff-pending

These may exist as internal build phases inside native packet production, but they may not exist as published visible-world states.

## Required Data Contracts

### Native chunk packet

A new authoritative packet contract is required.

Owner:

- native world runtime

Readers:

- publication coordinator
- diagnostics
- test harnesses

Invariants:

- `assert(final_packet_is_self_sufficient_for_publication, "publication may not depend on later convergence work")`
- `assert(final_packet_contains_all_final_layers, "final packet must contain all full_ready layers")`
- `assert(final_packet_is_versioned, "native packet schema must be versioned")`
- `assert(final_packet_is_deterministic_for_same_inputs, "packet output must be deterministic for same generator version and inputs")`

R2 schema lock:

- surface packet contract name: `frontier_surface_final_packet`
- `packet_version = 1`
- `generator_version = 1`
- `z_level = 0`
- required provenance field: `generation_source`

Field groups owned by `frontier_surface_final_packet v1`:

1. Authoritative chunk base fields:
   - `chunk_coord`
   - `canonical_chunk_coord`
   - `base_tile`
   - `chunk_size`
   - `terrain`
   - `height`
   - `variation`
   - `biome`
   - `secondary_biome`
   - `ecotone_values`
   - `flora_density_values`
   - `flora_modulation_values`
2. Deterministic placement fields:
   - `flora_placements`
   - `feature_and_poi_payload`
3. Terminal publication payloads:
   - `flora_payload` when `flora_placements` is non-empty; it must match the packet canonical chunk coord/chunk size, match placement count, and carry a prebuilt pure-data render packet.
4. Publication-local derived buffers:
   - `rock_visual_class`
   - `ground_face_atlas`
   - `cover_mask`
   - `cliff_overlay`
   - `variant_id`
   - `alt_id`
5. Final-publication ownership groups that may not remain undocumented outside the contract during migration:
   - seam-complete edge correctness
   - collision / navigation ownership
   - roof / cover / fog visibility ownership
   - lighting / shadow ownership
   - overlay ownership

Migration note:

- `R2` locks the packet header, versioning, and ownership vocabulary so runtime code can stop passing anonymous `native_data` dictionaries.
- `R3` makes surface packet production terminal for native flora placement/render payloads, real feature/POI payloads, native visual packet buffers from `ChunkVisualKernels`, and install/cache validation through `ChunkFinalPacket.validate_terminal_surface_packet()`.
- `R4` introduces explicit GDScript ownership for `TravelStateResolver`, `ViewEnvelopeResolver`, `FrontierPlanner`, and `FrontierScheduler`, then routes `ChunkStreamingService` runtime queues through frontier-critical, camera-visible-support, and background lanes. Vehicle/train and underground transition inputs remain scaffold-only until their dedicated iterations; R4's enforceable invariant is reserved frontier capacity for current surface runtime streaming.
- `R5` is responsible for switching live publication to consume only that final packet.
- Until `R5` lands, any live publication layer still outside final-packet-only apply must be named explicitly in the contracts; it must not reappear as hidden "later convergence" debt after reveal.

### Frontier planning state

Owner:

- `TravelStateResolver` for travel-mode/speed-class planning inputs
- `ViewEnvelopeResolver` for camera-visible and margin envelopes
- `FrontierPlanner` for active-z `frontier_critical_set`, `frontier_high_set`, `background_set`, and `needed_set`
- `FrontierScheduler` for lane classification and reserved-capacity policy
- `ChunkStreamingService` for lane queue execution, active generation lane metadata, and diagnostics

Readers:

- scheduler
- diagnostics
- traversal tests

Invariants:

- `assert(visible_chunks_subset_of_full_ready_or_transition_hidden, "visible chunks must be full_ready unless hidden by controlled fade transition")`
- `assert(frontier_critical_capacity_is_reserved, "critical frontier work must have protected capacity")`
- `assert(background_work_never_blocks_visible_world_correctness, "background work must not block visible correctness")`
- `assert(lane_metadata_tracks_active_runtime_generation, "active and ready runtime work must keep its frontier lane for diagnostics and strict ordering")`

## Forbidden Architecture Patterns

The following architecture patterns are banned in the new runtime:

- progressive redraw as a visible-world correctness mechanism
- publish-now-finish-later pipelines
- script fallback in any critical full-ready path
- non-versioned hidden packet shape changes
- visible chunk states that still owe flora, seams, cliff, roof, or overlay completion
- scheduler designs that allow far backlog to occupy all compute while frontier correctness is threatened
- startup handoff before startup visible envelope is fully ready

## Recommended File Direction

The exact file layout may change, but the target architecture should converge toward explicit owners such as:

- `travel_state_resolver.*`
- `view_envelope_resolver.*`
- `frontier_planner.*`
- `native_chunk_packet_builder.*`
- `chunk_packet_cache.*`
- `frontier_scheduler.*`
- `publication_coordinator.*`
- `underground_transition_coordinator.*`

The old monolithic or hybrid ownership model must not be preserved out of convenience.

## Migration Plan

### Iteration 1 - Freeze and Deprecate Legacy Runtime

Goal:

- stop extending the old runtime
- isolate it as deprecated implementation debt

What is done:

- explicitly mark current chunk runtime as legacy in docs and execution artifacts
- stop adding new fallback paths
- inventory all critical fallback, phased-publication, and starvation-prone logic
- define native chunk packet schema

Acceptance tests:

- [ ] legacy runtime is named deprecated in execution artifacts
- [ ] no new feature work lands on the old hybrid model except deletion/isolation
- [ ] native final packet schema exists and is versioned

### Iteration 2 - Native Final Packet Pipeline

Goal:

- make final packet production the core truth of the runtime

What is done:

- implement native-only final packet generation for surface chunks
- remove critical GDScript fallback from surface full-ready path
- make publication consume final packet only

Acceptance tests:

- [ ] surface visible chunks publish from final native packet only
- [ ] no surface visible chunk can owe later flora/cliff/seam completion
- [ ] no critical surface full-ready path uses GDScript fallback

### Iteration 3 - Frontier Planning and Reserved Scheduling

Goal:

- guarantee that visible and imminent chunks are prepared before reveal/entry

What is done:

- implement travel state resolver
- implement view envelope resolver
- implement frontier planner
- implement frontier-critical reserved scheduling

Acceptance tests:

- [ ] far/background work cannot starve frontier-critical work
- [ ] visible-world traversal on foot and sprint exposes no catch-up
- [ ] diagnostics prove frontier-critical lane always has protected capacity

### Iteration 4 - Underground Controlled Transition

Goal:

- bring underground staircase transitions under the same final-ready contract

What is done:

- implement target-envelope preparation before fade-in
- use fade only for controlled layer switch, not for hiding incomplete reveal

Acceptance tests:

- [ ] underground entry never reveals non-full-ready chunks
- [ ] fade-in occurs only after target visible envelope is ready

### Iteration 5 - Vehicles and Trains

Goal:

- extend the same runtime to high-speed travel

What is done:

- tune prediction horizon and frontier width for vehicle motion
- tune prediction horizon and frontier width for trains
- validate cache/residency policy under sustained fast travel

Acceptance tests:

- [ ] vehicle travel shows no visible chunk catch-up
- [ ] train travel shows no visible chunk catch-up
- [ ] runtime stays within acceptable frame behavior on the baseline machine

## Observability and Test Harness Requirements

The runtime must expose the following telemetry:

- current travel mode and speed class
- current camera-visible set size
- current frontier-critical set size
- current hot/warm/cold cache residency
- native final packet build latency
- publication latency
- frontier-critical queue depth
- background queue depth
- any breach attempt where visibility or occupancy would have happened before `full_ready`

Required automated scenarios:

- long straight walking traversal
- long straight sprint traversal
- rapid zig-zag movement across chunk boundaries
- vehicle traversal
- train traversal
- staircase descent/ascent into underground
- long-distance traversal with reversals to stress cache behavior

Failure rule:

- the scenario fails if any chunk becomes visible or occupiable before `full_ready`

## Definition of Done

The frontier-native runtime architecture is considered delivered only when:

- current runtime is no longer the active architectural target
- visible-world correctness is guaranteed, not approximate
- player occupancy correctness is guaranteed, not approximate
- full-ready publication is terminal and all-inclusive
- surface, underground, vehicles, and trains all obey the same runtime contract
- the baseline machine sustains seamless-feeling 60 FPS class traversal under supported movement modes
- no critical player-reachable path depends on GDScript fallback

If the player can still see or enter a chunk that is not fully finished, the architecture is not done.
