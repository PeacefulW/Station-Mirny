---
title: Simulation and Threading Model
doc_type: governance
status: draft
owner: engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - ENGINEERING_STANDARDS.md
  - PERFORMANCE_CONTRACTS.md
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../02_system_specs/world/lighting_visibility_and_darkness.md
  - ../02_system_specs/world/subsurface_and_verticality_foundation.md
  - ../02_system_specs/meta/multiplayer_authority_and_replication.md
---

# Simulation and Threading Model

This document defines the high-level simulation classes, cadence rules, and thread-boundary expectations for Station Mirny.

It exists to stop the project from drifting into ad-hoc update logic where every new system gets its own `_process()` loop, every heavy feature competes for the main thread, and gameplay truth becomes mixed with presentation updates.

This file is one of the core runtime governance documents for the project.

## Purpose

The purpose of this document is to define a stable foundation for:

- simulation cadence classes
- main-thread vs worker-thread expectations
- gameplay-truth vs derived-state vs presentation-state update boundaries
- apply-phase rules for heavy world/runtime systems
- degradation rules when performance is under pressure
- early architectural constraints that protect the project from hitching and update-loop chaos

## Why this document exists

Station Mirny is not a static game.
It will contain systems such as:

- world generation and chunk streaming
- excavation and underground space
- weather, wind, seasons, and runtime environment
- lighting, darkness, and visibility
- flora motion and environmental response
- machinery and infrastructure
- fauna and threat simulation later
- multiplayer-safe shared gameplay state

These systems do not all belong on the same update cadence.
They do not all belong on the same thread.
They do not all deserve the same authority level.

Without a project-wide model, performance and architecture quality will degrade over time.

## Scope

This document owns:

- simulation cadence classes
- main-thread restrictions and worker-eligible direction
- the distinction between authoritative, derived, and presentation simulation
- apply-phase expectations for heavy jobs
- degradation hierarchy under load
- architectural rules for where systems should live in runtime

This document does not own:

- exact low-level implementation details of each subsystem
- exact engine-specific thread API usage for every feature
- exact networking packet design
- exact profiling numbers and budgets for every target machine

Those belong in subsystem specs, implementation documents, and profiling notes.

## Core architectural statement

Not every system should update every frame.
Not every system should live on the main thread.
Not every visual effect should be authoritative gameplay state.
Not every expensive derived product should be rebuilt synchronously.

The project must classify runtime work intentionally.

That classification should influence:

- cadence
- thread eligibility
- authority level
- persistence needs
- degradation strategy
- apply behavior

## Foundational principles

### 1. Main thread is precious
The main thread should be protected aggressively.

Anything that directly affects:

- player input responsiveness
- scene-tree mutation
- renderer-sensitive state
- engine APIs that require main-thread access
- immediate gameplay feedback

must be handled with care.

Heavy world-scale processing should never default to the main thread just because it was easy to write.

### 2. Immediate feedback may be local; heavy consequences may be deferred
The player may need instant feedback for an action such as:

- placing a block
- mining a tile
- toggling a door
- opening a connector
- switching a machine

That does not mean every consequence of that action must be resolved synchronously in the same hot path.

Small immediate feedback is allowed.
Heavy derived consequences should be queued, staged, or rebuilt incrementally.

### 3. Gameplay truth, derived state, and presentation must not be collapsed together
The project must distinguish between:

- **authoritative gameplay truth**
- **derived reconstructible runtime state**
- **client/local presentation state**

These categories may update at different cadences and use different threading models.

### 4. Degradation is acceptable; hitching is not
When under load, the project should prefer:

- slower visual catch-up
- reduced update frequency for non-critical systems
- lower presentation fidelity
- delayed non-critical rebuild completion

rather than:

- blocking input
- large frame spikes
- full synchronous world sweeps
- catastrophic main-thread hitching

### 5. Expensive world work should be spatially and architecturally bounded
Heavy work should be limited by:

- locality
- dirty queues
- region/chunk scope
- relevance
- cadence class
- thread eligibility

Global full sweeps should be rare and deliberate, not the default response to local events.

## Simulation classes

The project should reason about runtime work in explicit classes.

## Class A — Immediate interactive gameplay
Examples:

- direct player action confirmation
- a local tile changing because of a player action
- opening a door
- starting or stopping a machine
- picking up an item
- placing a structure

Characteristics:

- must feel immediate
- usually local in scope
- often main-thread-visible
- should avoid hidden heavy follow-up work in the same hot path

Rule:

Small local response is allowed synchronously.
Heavier follow-up must be deferred if necessary.

## Class B — Near-player gameplay simulation
Examples:

- nearby entity logic
- immediate local hazards
- active interaction checks
- nearby machine updates
- local room/state checks needed for active play

Characteristics:

- high priority
- bounded by relevance and locality
- gameplay-facing
- should remain predictable under load

Rule:

Near-player gameplay simulation may be frequent, but it must remain bounded and avoid silent world-scale growth.

## Class C — Low-frequency world/runtime simulation
Examples:

- environmental progression
- weather phase stepping
- season progression
- broad ecological pressure updates later
- low-frequency resource or habitat simulation later

Characteristics:

- slower cadence than frame-rate
- often region-based or event-driven
- can be authoritative or shared gameplay truth depending on the system

Rule:

These systems should not default to per-frame updates unless there is a strong reason.

## Class D — Background maintenance and rebuild
Examples:

- chunk preparation
- derived cache rebuilds
- visibility mask regeneration
- topology recomputation
- streaming prep
- progressive redraw
- worldgen prep

Characteristics:

- budgeted
- incremental
- often worker-eligible or split into compute/apply stages
- not directly tied to every input frame

Rule:

This class should absorb heavy consequences of local mutations whenever possible.

## Class E — Client/local presentation simulation
Examples:

- grass sway phase
- light flicker phase
- particles
- interpolation
- camera-local ambience motion
- some local storm motion details
- cosmetic procedural animation

Characteristics:

- non-authoritative when possible
- may vary across clients/machines
- should degrade before gameplay truth does

Rule:

Rich presentation is desirable, but it must not secretly become required authoritative gameplay state.

## Authority-aware simulation classes

Simulation class is not only about cadence.
It is also about authority.

The project should ask for each system:

- is this authoritative gameplay truth?
- is this reconstructible derived state?
- is this local-only presentation?

Examples:

- season phase may be authoritative/shared truth
- local wetness overlay mask may be derived state
- grass sway phase may be client-local presentation
- machine on/off may be authoritative gameplay state
- a rebuild cache for room connectivity may be derived state

This distinction matters for:

- multiplayer
- persistence
- thread eligibility
- update cadence
- performance strategy

## Main-thread expectations

The following kinds of work should generally be treated as main-thread-sensitive.

### Main-thread-sensitive categories
Examples:

- scene-tree mutation
- Node creation/removal where engine restrictions apply
- direct visual/renderer-bound state application
- immediate player-facing state changes
- some TileMap or renderer-visible operations
- final commit/apply phases for prepared results

Canonical rule:

Do not treat main-thread access as free.
Use it for final application and immediate feedback, not for giant compute loops by default.

## Worker-eligible direction

The following classes of work are often good candidates for worker/background execution or detached preparation:

- deterministic analysis on immutable data
- world sampling prep
- chunk preparation
- classification over native-backed or detached buffers
- expensive rebuild planning
- local topology preprocessing
- environment-region analysis
- path or metadata prep where engine restrictions allow

Canonical rule:

Worker threads should prepare or compute what can safely be computed off the main thread.
The result should then be applied in a bounded main-thread phase if needed.

## Compute phase vs apply phase

Many systems should conceptually separate into:

- **compute/prep phase**
- **ready/queued result**
- **bounded apply phase**

This is especially important for:

- chunk rebuilds
- visibility products
- environmental overlays
- worldgen/build outputs
- underground topology changes
- heavy derived caches

Canonical rule:

Even if compute is parallel or deferred, apply must still be controlled and bounded.

## Cadence rules by system family

These are governance-level expectations, not exact implementation law.

### World generation and chunk preparation
Expected class:

- Class D primarily
- some local Class A feedback for immediate action results

Guideline:

Base world generation and chunk preparation should not run as uncontrolled frame-time work.
Use staged streaming and background prep.

### Environment runtime
Expected classes:

- Class C for broad environment progression
- Class E for visual response
- Class D for heavier derived rebuilds when required

Guideline:

Do not simulate all environment details globally every frame.
Separate authoritative state from local visual response.

### Lighting / darkness / visibility
Expected classes:

- Class A or B for immediate gameplay-facing local changes when necessary
- Class D for heavier derived visibility products
- Class E for visual richness such as flicker or some local effects

Guideline:

Keep renderer richness decoupled from gameplay truth where possible.

### Underground / excavation
Expected classes:

- Class A for immediate local excavation feedback
- Class D for heavier rebuild consequences
- Class B for near-player underground logic

Guideline:

A local dig should feel immediate, but must not trigger unbounded full-layer rebuilds.

### Fauna / threat simulation later
Expected classes:

- Class B for nearby active behavior
- Class C for low-frequency ecology/migration pressure
- Class E for visual-only motion nuance

Guideline:

Do not simulate all entities at full fidelity at all times.

### Building / infrastructure / machines
Expected classes:

- Class A for immediate toggles and interactions
- Class B for nearby active systems
- Class D for larger recomputation or derived network rebuilds when needed

Guideline:

Network or room recalculation should be incremental and relevance-aware where possible.

## Threading and determinism

When worker/background execution is used, systems should preserve deterministic rules where deterministic outcomes matter.

Important considerations:

- the order of visual presentation tasks may be flexible
- the order of authoritative gameplay truth resolution may need stronger guarantees
- derived results should not become nondeterministic gameplay truth by accident

Canonical rule:

Parallel compute is acceptable.
Unclear or unstable gameplay truth is not.

## Locality and relevance rules

Runtime systems should prefer locality and relevance over global naive iteration.

Useful limiting concepts include:

- near-player radius
- active loaded chunk set
- dirty region list
- explicit connector/zone neighborhood
- machine network partition
- region-based environment update scope

Canonical rule:

If a system can be updated locally or regionally, it should not default to a whole-world scan.

## Degradation hierarchy

When performance pressure rises, the project should prefer degrading in roughly this order:

1. cosmetic local presentation detail
2. non-critical visual frequency
3. delayed completion of heavier derived rebuilds
4. low-priority far-field simulation cadence
5. only as a last resort, important nearby gameplay-facing updates

This is not a strict numerical ladder.
It is a design principle.

The player should notice reduced richness before they notice input hitching or broken gameplay feedback.

## Anti-patterns

The following patterns should be treated as architectural warnings.

### 1. Every system gets its own `_process()` forever
This usually leads to update chaos, hidden cost growth, and no shared cadence logic.

### 2. Local action triggers full synchronous rebuild
For example:

- mining one tile causes world-scale topology work immediately
- toggling one light causes a giant relight sweep
- weather change forces synchronous full-world visual reapplication

### 3. Presentation state is treated as gameplay truth
For example:

- exact shadow visuals deciding shared gameplay state
- purely cosmetic motion becoming authoritative logic input

### 4. Worker thread does engine-forbidden mutation directly
For example:

- background threads mutating scene-tree or renderer-bound objects directly in unsafe ways

### 5. No apply boundary after parallel compute
This creates hidden race-like behavior and unstable frame cost.

### 6. One cadence for everything
A live game with world systems, environment, underground, lighting, and AI cannot remain healthy if everything is treated as equal-frequency update work.

## Relationship with multiplayer

This document is closely related to multiplayer authority rules.

The simulation model should support the separation between:

- authoritative shared gameplay simulation
- derived reconstructible runtime products
- client-local presentation simulation

Canonical rule:

Do not force all simulation into the authoritative lane.
Only gameplay-relevant truth needs to be authoritative.

## Relationship with persistence

Persistence should generally store:

- authoritative gameplay truth
- meaningful durable state
- durable world modifications

It should usually not store:

- cosmetic local presentation phases
- easily reconstructible caches
- transient rebuild products

This distinction should influence what systems bother to serialize.

## Profiling and instrumentation expectation

A healthy simulation model needs observability.

The project should eventually be able to inspect or reason about:

- how much work each simulation class is doing
- which systems are hitting the main thread
- which queues are growing too large
- which deferred products are lagging behind
- whether near-player responsiveness is being protected

This document does not define the exact profiler UI.
It defines the expectation that simulation classes should be observable enough to debug.

## Minimal architectural seams

These are illustrative, not final APIs.

### Simulation cadence example

```gdscript
class_name SimulationCadence
extends RefCounted

enum Kind {
    IMMEDIATE,
    NEAR_PLAYER,
    LOW_FREQUENCY,
    BACKGROUND,
    PRESENTATION,
}
```

### Threading role example

```gdscript
class_name ThreadingRole
extends RefCounted

enum Kind {
    MAIN_THREAD_ONLY,
    WORKER_ELIGIBLE,
    COMPUTE_THEN_APPLY,
}
```

### Work item direction example

```gdscript
class_name RuntimeWorkItem
extends RefCounted

var cadence_kind: int
var threading_role: int
var authoritative: bool
```

These are not final APIs.
They illustrate the mindset that work should be classified deliberately.

## Success conditions

This foundation is successful when:

- new systems are designed with explicit cadence and thread expectations
- the project avoids uncontrolled growth of per-frame main-thread work
- heavy world/runtime consequences are pushed into bounded deferred pipelines where appropriate
- gameplay truth remains distinct from presentation simulation
- environment, lighting, underground, and future fauna systems can all coexist without update chaos
- performance problems become easier to reason about because work classes are explicit

## Failure signs

This foundation is wrong if:

- every subsystem invents its own update loop style independently
- main-thread heavy loops grow across world/runtime systems with no shared discipline
- local visual richness is allowed to dominate authoritative gameplay update cost
- local mutations repeatedly trigger global rebuilds
- the codebase has no coherent answer to “what should run when, where, and with what authority?”

## Open questions

The following remain intentionally open:

- exact final job system and worker orchestration model
- exact engine-specific thread safety boundaries for some subsystems
- exact cadence values for individual systems
- exact profiling and debug tooling format
- exact far-field simulation policy for late-game large worlds

These may evolve without changing the foundational rules above.
