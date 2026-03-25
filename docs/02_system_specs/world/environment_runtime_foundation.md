---
title: Environment Runtime Foundation
doc_type: system_spec
status: draft
owner: design+engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - world_generation_foundation.md
  - lighting_visibility_and_darkness.md
  - subsurface_and_verticality_foundation.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Environment Runtime Foundation

This document defines how the world behaves after it has been generated.

World generation defines the stable large-scale shape of the world.
This document defines the runtime environmental state layered over that world.

## Purpose

The purpose of this spec is to define the foundational runtime model for:
- time of day
- seasonal state
- weather state
- wind
- temperature and exposure pressure
- environmental visual modulation
- hooks that other systems consume

## Core statement

The generated world is not enough.
Station Mirny also needs a living runtime environment that changes how the same place feels over time.

The environmental runtime layer must support:
- atmosphere
- readability
- survival pressure
- beauty and dread
- stable integration with world, flora, fauna, lighting and multiplayer

## Scope

This spec owns:
- environment runtime state categories
- layer boundaries between generated truth and runtime environmental truth
- environmental hooks consumed by other systems
- cadence class and update responsibility direction
- authoritative vs visual-only environment state direction

This spec does not own:
- exact art implementation
- exact shadow rendering implementation
- exact final weather balance values
- exact final temperature formulas

## Environmental runtime layers

The intended environment model is layered.

### Layer 1: Stable world base
Provided by world generation.
Examples:
- terrain
- altitude
- biome tendency
- moisture tendency
- climate tendency
- world-position context

This layer is deterministic from seed and coordinates.

### Layer 2: Slow global/regional runtime state
Examples:
- season phase
- large weather fronts or broad weather state
- long-form temperature shifts

This layer changes slowly and affects wide areas.

### Layer 3: Local runtime environment state
Examples:
- current precipitation at location
- wind intensity and gusts
- local fog or storm intensity
- local surface wetness / snow cover tendency
- perceived temperature / exposure state

This layer creates local moment-to-moment atmosphere.

### Layer 4: Visual response layer
Examples:
- flora motion
- particle intensity
- overlay masks
- wet/snow/dust visual response
- local ambient color grading hooks

This layer should often degrade gracefully before gameplay state does.

## Core environmental dimensions

### Time of day
Time of day is a foundational runtime signal.

It must be able to influence:
- light availability
- threat pressure
- atmosphere
- readability
- fauna behavior hooks
- player planning

### Seasonal state
The game requires major seasonal phases analogous to:
- winter-like severe phase
- spring-like recovery/growth phase
- summer-like more open phase
- autumn-like decline/transition phase

These do not need to mirror Earth literally.
But they must be systemic, visible and meaningful.

Seasonal state must be able to affect:
- broad temperature pressure
- precipitation profile
- flora appearance state
- movement/expedition risk
- available environmental comfort outside
- migration/habitat hooks for fauna

### Weather state
Weather should be a runtime state, not just particles.

Weather must be able to include or influence:
- wind
- rain-like events
- snow-like events
- fog / visibility pressure
- storm escalation
- surface visual response
- soundscape shifts

### Wind
Wind is one of the signature identity systems of the game.

Wind should influence:
- flora motion
- ambient movement readability
- storm feel
- soundscape
- atmosphere
- optional creature or projectile interactions later

Wind must remain readable and directionally coherent enough to be felt by the player.

### Temperature and exposure
The environment must be able to exert thermal pressure.

Temperature/exposure should be allowed to depend on:
- season
- time of day
- weather
- biome tendency
- altitude
- shelter status
- heat/light sources
- clothing/gear later

## Environment hooks for other systems

The runtime environment must expose clean hooks rather than force every system to recalculate its own environment model.

Consumers include:

### Lighting / visibility
Consumes:
- time of day
- weather visibility modifiers
- underground/outdoor context

### Surface visuals
Consumes:
- seasonal appearance state
- wet/dry/snow-like response state
- wind motion parameters

### Flora
Consumes:
- wind profile
- season profile
- biome/environment compatibility
- severe weather suppression or reaction hooks

### Fauna
Consumes:
- habitat comfort signals
- migration pressure signals
- day/night behavior hooks
- severe weather or seasonal pressure hooks

### Survival systems
Consumes:
- exposure
- shelter bonus
- environmental severity

### Audio
Consumes:
- wind class
- precipitation class
- storm state
- season mood hooks

## Runtime class expectations

Environment runtime is not one giant always-per-frame simulation.
It should be split by cadence:
- very cheap per-frame local presentation values
- low-frequency regional state updates
- budgeted background updates for heavier derived work
- event-driven recalculation when state transitions meaningfully change

## Authoritative vs presentation distinction

Important distinction:
- not every environmental signal must be network-authoritative or saved at high fidelity
- not every visual response must be part of gameplay truth

The architecture should distinguish between:
- authoritative gameplay-facing environment state
- derived presentation state

Example direction:
- weather class may be authoritative
- exact grass sway may remain client-local visual simulation

## Save and persistence direction

Environment persistence should not naïvely serialize all presentation details.

Likely persistence classes:
- current season phase
- broad world/regional weather seed/state
- long-form environment progression state if needed

Likely non-persistent or cheaply reconstructible:
- exact local gust shape
- exact particle placement
- exact grass animation phase

## Multiplayer direction

For multiplayer, the environment model must support a host-authoritative gameplay truth with room for client-local presentation.

The exact replication contract belongs in multiplayer specs, but this document establishes the requirement that environment state be separable into:
- authoritative state
- reconstructible derived state
- client-local visual response

## Performance direction

The environment runtime must respect performance law:
- no giant per-frame world sweep
- no synchronous full map season swap in gameplay path
- no mass tile mutation on one state change
- visual and surface transitions should prefer incremental, masked, cached, or region-aware approaches

## Acceptance criteria

This foundation is successful when:
- time, season, weather and wind feel like one coherent runtime layer
- the same biome can feel different at night, in winter, in a storm, or in calm weather
- environment systems can influence flora, fauna, lighting and survival without direct spaghetti coupling
- presentation richness does not require forbidden full-world rebuild behavior

## Failure signs

This foundation is wrong if:
- weather is just particles with no systemic hooks
- seasons require brute-force world replacement
- wind is purely cosmetic with no architecture-level place in the simulation
- every system invents its own local climate logic independently
- presentation and authoritative state are mixed so tightly that multiplayer or optimization becomes painful

## Open questions

- exact world/regional weather partitioning
- exact severity model for the coldest seasonal phase
- exact visual surface modulation model for snow/wetness/dust
- exact exposure formula and shelter/heat interaction
- exact migration/environment hooks for fauna
