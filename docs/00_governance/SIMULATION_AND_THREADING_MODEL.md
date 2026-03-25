---
title: Simulation and Threading Model
doc_type: governance
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - PERFORMANCE_CONTRACTS.md
  - ENGINEERING_STANDARDS.md
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../02_system_specs/meta/multiplayer_authority_and_replication.md
---

# Simulation and Threading Model

This document defines the high-level simulation classes and thread-boundary expectations for Station Mirny.

## Purpose

The purpose of this document is to stop the project from drifting into ad-hoc update loops where everything ticks everywhere at once.

## Core statement

Not every system should update at the same cadence.
Not every job belongs on the main thread.
Not every presentation effect belongs in authoritative gameplay state.

The project needs explicit simulation classes and threading expectations.

## Scope

This document owns:
- simulation cadence classes
- main-thread vs worker-eligible direction
- authoritativeness-aware update boundaries
- degradation expectations for expensive systems

This document does not own:
- precise micro-optimization strategy for each implementation
- low-level native implementation details
- exact networking protocol details

## Foundational principles

### 1. Main thread is precious
Anything that touches player-facing immediacy, scene-tree mutation, renderer-sensitive operations, or engine-only APIs should be treated with extreme care.

### 2. Heavy deterministic work should prefer precompute, caching, or worker-eligible pipelines
Grid-heavy, expensive and locality-friendly work should not default to giant main-thread loops.

### 3. Gameplay truth and presentation should not be forced into the same update cadence
The player does not need every visual effect to be authoritative.
The project should distinguish:
- authoritative gameplay state
- derived reconstructible state
- local presentation state

### 4. Degradation is acceptable; hitching is not
A system may present temporary lower-fidelity visual response while catching up.
It should not block interactive play.

## Simulation cadence classes

The project should reason about systems through classes like these.

### Class A: Interactive immediate
Examples:
- player local action response
- single tile mine/place/remove mutation
- door toggle
- item use confirmation

Rules:
- synchronous
- small/local only
- heavy consequences must enqueue background work

### Class B: Near-player gameplay simulation
Examples:
- nearby entities
- active machine logic
- local hazards
- immediate interaction checks

Rules:
- high priority
- bounded scope
- must not silently expand to world-scale sweeps

### Class C: Low-frequency world/runtime simulation
Examples:
- broad environmental progression
- fauna ecology pressure updates
- migration tendency updates
- long-form seasonal progression

Rules:
- lower cadence than per-frame
- may use partitioning or region-based stepping
- should remain deterministic where needed

### Class D: Background maintenance and rebuild
Examples:
- chunk streaming
- cache rebuilds
- derived masks
- progressive redraw
- warmup/prep jobs

Rules:
- budgeted
- incremental
- often worker-eligible or staged where engine constraints allow

### Class E: Client-local presentation
Examples:
- grass sway phase
- particles
- interpolation
- cosmetic local ambience motion
- some shadow or animation details

Rules:
- may vary per client
- should not own gameplay truth
- should degrade first when performance is under pressure

## Threading direction

### Main-thread only candidates
Common examples include:
- scene-tree mutation
- direct Node creation/destruction where engine restrictions apply
- direct TileMap/renderer-sensitive mutation
- player input response chain
- final apply phase for many visual changes

### Worker-eligible candidates
Common examples include:
- deterministic analysis on immutable/native-backed data
- chunk preparation
- generation sampling prep
- expensive classification over detached data buffers
- precomputation of local masks/metadata before main-thread apply

### Native-side cache candidates
Common examples include:
- dense world grids
- topology metadata
- classification products
- immutable/generated base data
- large frequently-queried runtime data where bridge cost matters

## Apply-phase rule

Even when heavy work is worker-eligible, many engine-visible results still need a controlled apply phase.
The architecture should separate:
- compute/prep
- queue/ready state
- bounded apply on the main thread

## Authority-aware simulation rule

When multiplayer matters, systems should ask:
- is this authoritative gameplay truth?
- is this reconstructible derived state?
- is this client-local presentation only?

The answer should affect cadence and replication expectations.

## Environmental simulation guidance

Environment systems are a common trap.
Do not make:
- all weather logic fully per-frame and global
- all seasonal visuals world-synchronous on one tick
- every wind response authoritative

Prefer:
- slower authoritative environment state
- local derived presentation response
- budgeted visual transitions

## Acceptance criteria

This foundation is successful when:
- systems can be classified by cadence and authority instead of guessing ad hoc
- worker eligibility and main-thread apply boundaries are understood early
- local visual richness does not force global synchronous updates
- future co-op remains compatible with the simulation model

## Failure signs

This foundation is wrong if:
- every new system defaults to `_process()` with no cadence reasoning
- world/runtime systems do large main-thread loops because "it was simpler"
- presentation effects are mixed into authoritative gameplay state without need
- thread usage is improvised without stable ownership/apply boundaries

## Open questions

- exact fixed-step policy for gameplay systems
- exact worker model for generation/runtime prep jobs in the shipping architecture
- exact native/GDScript boundary for large world caches
- exact degraded-mode policy per major subsystem
