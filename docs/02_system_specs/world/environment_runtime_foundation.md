---
title: Environment Runtime Foundation
doc_type: system_spec
status: draft
owner: design+engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
depends_on:
  - world_generation_foundation.md
related_docs:
  - world_generation_foundation.md
  - lighting_visibility_and_darkness.md
  - subsurface_and_verticality_foundation.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../meta/save_and_persistence.md
  - ../meta/multiplayer_authority_and_replication.md
---

# Environment Runtime Foundation

This document defines how the world behaves after it has been generated.

`world_generation_foundation.md` defines the stable generated shape of the world.
This document defines the runtime environmental layer that changes how the same place feels, looks, and plays over time.

## Purpose

The purpose of this document is to define a coherent runtime environment model for:

- time of day
- seasons
- weather
- wind
- temperature and exposure pressure
- environmental visual modulation
- runtime environmental hooks consumed by other systems

This file exists so that the project does not treat weather, seasons, wind, and environmental pressure as disconnected features.

## Gameplay goal

The runtime environment must support the product fantasy that:

- the same world location can feel radically different at day, at night, in calm weather, in storms, or during the harsh season
- the outside world feels alive, readable, hostile, and beautiful
- the base feels comparatively safer, clearer, more controlled, and more habitable
- environmental pressure matters even when nothing is directly attacking the player

## Scope

This spec owns:

- the conceptual runtime environment model
- separation between generated world truth and runtime environmental state
- the major environment dimensions
- the responsibilities and boundaries of environment runtime systems
- system hooks for flora, fauna, lighting, survival, audio, and presentation
- performance and authority direction for environmental systems

This spec does not own:

- low-level shadow rendering implementation
- exact final formulas for temperature, exposure, or precipitation
- exact art implementation of particles, shaders, or overlays
- exact biome generation logic
- exact balancing of all seasons and weather types

Those belong in:

- `world_generation_foundation.md`
- `lighting_visibility_and_darkness.md`
- governance/performance docs
- future detailed subsystem specs

## Core architectural statement

The world must not stop at generation.

In Station Mirny, the player should experience not only a generated planet, but a living runtime environment layered over that planet.

That runtime layer must be:

- coherent
- systemically useful
- performance-safe
- compatible with persistence
- compatible with future co-op
- rich enough to carry atmosphere and pressure

## Relationship to world generation

World generation provides stable base truth such as:

- terrain
- altitude
- biome tendency
- moisture tendency
- temperature tendency
- large structures
- subzone tendency

Environment runtime provides changing state layered on top of that base such as:

- current time-of-day phase
- current seasonal phase
- current weather state
- current wind state
- current local environmental severity
- current visual surface response

Canonical rule:

- world generation answers **what this place fundamentally is**
- environment runtime answers **what this place currently feels like**

## Core environment dimensions

The project should think in terms of several major runtime environment dimensions.

### 1. Time of day

Time of day is a foundational runtime signal.

It must be able to affect:

- ambient light level
- mood and tension
- visibility
- travel safety
- expedition planning
- behavior hooks for fauna
- psychological pressure on the player

At the product level:
- day supports travel and planning
- night increases vulnerability and tension

### 2. Seasonal phase

Seasonal change is mandatory.

The game must support major seasonal states analogous to:

- winter-like severe phase
- spring-like recovery / transition phase
- summer-like relatively open phase
- autumn-like decline / preparation phase

These do not need to be literal Earth seasons.
But they must be systemic, visible, and strategically meaningful.

Seasonal phase should be able to affect:

- broad environmental severity
- travel risk
- flora appearance state
- available surface comfort
- weather profiles
- resource and expedition pressure
- habitat pressure for fauna later

### 3. Weather state

Weather is not just particles.

Weather must be a real runtime state with gameplay-support meaning.

Weather should be able to include or influence:

- precipitation
- visibility degradation
- wind escalation
- surface response
- soundscape
- perceived exposure
- pressure on travel and preparation

The project should support the idea that weather can be calm, moderate, severe, or extreme depending on region/season/state.

### 4. Wind

Wind is one of the signature environmental carriers of atmosphere in Station Mirny.

Wind must matter because it makes the outside world feel alive and exposed.

Wind should influence:

- flora motion
- environmental ambience
- storm feel
- directional atmosphere
- surface particles
- visual readability of exposure
- optional later hooks for fauna, projectiles, or systems if needed

Canonical rule:
wind is not a disposable cosmetic effect.
It is a first-class environmental signal.

### 5. Temperature and exposure pressure

The game must support environmental thermal pressure.

The player should be able to feel that:

- some seasons are harsher
- night can be more dangerous than day
- storms can increase pressure
- shelter matters
- heat and interior protection matter

Temperature/exposure may depend on:

- season
- time of day
- weather
- biome tendency
- altitude
- wind severity
- shelter status
- local heat sources
- later clothing/gear systems

This document does not lock exact formulas.
It locks the architectural importance of the dimension.

### 6. Visibility pressure

Environment runtime should be allowed to change readability and visibility through things like:

- darkness
- fog-like states
- snowfall / rain-like events
- storms
- wind-driven visual noise
- underground context

Detailed visibility/light interaction belongs in `lighting_visibility_and_darkness.md`,
but the environment layer must be able to drive it.

## Environment runtime layers

The environment model should be layered rather than monolithic.

### Layer 1: Stable generated base

Examples:

- terrain
- biome tendency
- altitude
- base climate tendency
- large structures

This is deterministic from seed and canonical world coordinates.

### Layer 2: Slow world/regional environmental state

Examples:

- current season phase
- broad weather regime
- large environmental severity trend
- regional cold/harshness drift if used

This changes slowly and affects wide areas.

### Layer 3: Local runtime environment state

Examples:

- local wind intensity
- local gust profile
- local precipitation state
- local fog/storm intensity
- local perceived exposure
- local surface response tendency

This is what makes one expedition feel different from another.

### Layer 4: Presentation response layer

Examples:

- grass sway
- tree/flora response
- snow/rain/wet overlays
- particles
- screen-space / ambient modulation
- local atmosphere richness

This layer is important, but should degrade before gameplay truth does.

## What the environment layer must provide to other systems

The runtime environment should expose clean consumable signals rather than force every system to invent its own environmental logic.

### Lighting / visibility systems consume:

- time of day
- weather visibility modifiers
- underground/outdoor context
- storm severity
- seasonal mood if needed

### Flora systems consume:

- wind profile
- season profile
- weather stress profile
- environmental animation context
- surface state modulation hooks

### Fauna systems consume:

- habitat pressure
- migration pressure
- day/night behavior hooks
- weather avoidance hooks
- seasonal behavior hooks

### Survival systems consume:

- temperature/exposure state
- shelter bonus
- outdoor severity
- weather penalty
- environmental comfort or danger modifiers

### Surface/tile presentation systems consume:

- wetness / snow-like / dust-like response
- season appearance state
- environmental overlay state
- wind motion parameters

### Audio systems consume:

- wind class
- precipitation class
- storm intensity
- seasonal atmosphere cues
- indoor/outdoor dampening context

## Authoritative vs derived vs presentation state

This distinction is mandatory.

Not every environmental signal should be equally authoritative or persisted.

### Authoritative gameplay-facing environment state

Examples may include:

- current season phase
- broad weather class
- gameplay-relevant exposure severity
- current day/night state
- major environmental hazard phase if introduced later

### Derived reconstructible state

Examples may include:

- local surface state masks
- region-specific weather derivatives
- local severity sampling from stable runtime seeds and current world state

### Client-local presentation state

Examples may include:

- grass sway phase
- exact gust motion shape
- exact particle placement
- cosmetic local turbulence
- minor presentation-only ambient variation

Canonical rule:
presentation richness must not force unnecessary authoritative complexity.

## Persistence direction

Environment persistence must be selective.

The game should not try to save every presentation detail.

Likely persistent or reconstructibly stable classes:

- season phase
- broad environmental progression state
- major weather regime seed/state if needed
- current time-of-day state

Likely cheap to reconstruct:

- exact local gust pattern
- exact particle positions
- exact frame-level flora animation phase
- many local visual-only overlay details

The exact save model belongs in persistence docs.
This document establishes the separation principle.

## Multiplayer direction

The environment model must be compatible with future host-authoritative co-op.

This means the project should distinguish between:

- host-authoritative gameplay-relevant environment truth
- deterministic/reconstructible derived state
- client-local visual response

Example direction:
- weather class may be authoritative
- exact grass sway phase may remain client-local

Environment architecture must not assume one local player and one camera forever.

## Performance direction

Environment runtime must comply with performance law.

That means:

- no giant per-frame world sweep
- no full synchronous seasonal world rebuild
- no brute-force update of all loaded tiles because weather changed
- no heavy environment recomputation in the interactive path

Preferred direction:

- layered state
- local sampling
- region-aware updates
- background/budgeted rebuilds where needed
- presentation degradation before gameplay hitching

## Simulation direction

Environment systems should not all run at the same cadence.

The intended model is something like:

- very cheap per-frame local presentation response
- slower gameplay-relevant environment stepping
- even slower broad seasonal/world state progression
- budgeted background recalculation for heavier derived products

Exact cadence belongs in simulation/threading governance.
This document establishes that cadence separation is required.

## Minimal architectural seams

These are not final APIs, but they show the intended shape.

### Environment state sampler

```gdscript
class_name EnvironmentRuntimeService
extends RefCounted

func sample_environment(world_pos: Vector2i) -> EnvironmentSample:
    pass
World/time state access
class_name WorldTimeService
extends RefCounted

func get_day_phase() -> DayPhase:
    pass

func get_season_phase() -> SeasonPhase:
    pass
Weather state access
class_name WeatherService
extends RefCounted

func get_regional_weather(world_pos: Vector2i) -> WeatherState:
    pass
Example environment sample direction
class_name EnvironmentSample
extends RefCounted

var day_phase: int
var season_phase: int
var weather_state: int
var wind_strength: float
var wind_direction: Vector2
var exposure_severity: float
var visibility_modifier: float
var shelter_modifier: float

These are illustrative, not final.

The important part is architectural:

one environment layer
explicit queries
shared signals for multiple systems
Acceptance criteria

This foundation is successful when:

the same location can feel different at day, night, during storms, and in different seasons
environment meaningfully influences player mood and planning
weather, wind, and seasons are not isolated gimmicks
the outside world feels alive and hostile even when combat is absent
flora, lighting, audio, survival, and later fauna can all consume the same coherent environment layer
environmental richness does not require forbidden full-world rebuild behavior
Failure signs

This foundation should be considered wrong if:

weather is just particles with no systemic role
seasons are just palette swaps with no strategic meaning
wind exists only as a shader trick with no architectural place in the simulation
every subsystem invents its own separate environment logic
environment changes require giant synchronous updates
authoritative gameplay state and client-local presentation are mixed together carelessly
Open questions

The following remain intentionally open:

exact weather taxonomy
exact final season structure and cadence
exact exposure formula
exact regional weather partitioning model
exact surface response implementation (masks, overlays, material swaps, etc.)
exact fauna migration/environment hooks
exact future interaction between environment state and engineering systems such as heating or ventilation

These may evolve without changing the foundation above.