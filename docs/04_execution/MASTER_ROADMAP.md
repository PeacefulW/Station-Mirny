---
title: Master Roadmap
doc_type: execution
status: approved
owner: design+engineering
source_of_truth: true
version: 1.1
last_updated: 2026-03-25
related_docs:
  - ../01_product/GAME_VISION_GDD.md
  - ../00_governance/ENGINEERING_STANDARDS.md
  - ../00_governance/PERFORMANCE_CONTRACTS.md
---

# Master Roadmap

This is the canonical execution-layer roadmap for Station Mirny.

## Scope

This document owns:
- milestone ordering
- execution phases
- dependency ordering between workstreams
- readiness criteria for entering and leaving a phase
- delivery sequencing rules

This document does not own:
- core fantasy
- lore truth
- low-level runtime architecture
- detailed system contracts

Those belong in:
- [Game Vision GDD](M:\dev\Station Peaceful\Station Peaceful\docs\01_product\GAME_VISION_GDD.md)
- [Engineering Standards](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\ENGINEERING_STANDARDS.md)
- [Performance Contracts](M:\dev\Station Peaceful\Station Peaceful\docs\00_governance\PERFORMANCE_CONTRACTS.md)
- `docs/02_system_specs/*`
- `docs/03_content_bible/*`

## Execution philosophy

The roadmap follows four hard rules:

1. Mechanics without usable UI are not considered complete.
2. Content does not outrun systems.
3. Runtime-sensitive foundations must be stable before feature stacking.
4. Each phase should end in a playable and testable slice, not just a pile of partial code.

## Current strategic order

The long-range order remains:

**Engine/Foundation → UI → Building/Base Loop → World → Survival Pressure → Infrastructure → Fauna/Combat → Progression → Content/Depth → Release**

This order exists to protect the core fantasy:
- first make the world and interaction stable
- then make the base meaningful
- then make the outside dangerous
- then scale the game outward

## Phase model

### Phase A — Engine and Runtime Foundation

Goal:
- stable world interaction foundation
- stable chunk/tile/runtime architecture
- movement/camera/world switching basics

Typical work:
- world streaming
- foundational rendering
- chunk/runtime architecture
- essential interaction primitives

Readiness to leave Phase A:
- core movement and world interaction are playable
- runtime spikes are under control for the basic loop
- major world systems no longer require architectural churn every task

### Phase B — UI and Player-Facing Control Layer

Goal:
- all major loops have player-visible control surfaces

Typical work:
- HUD
- inventory shell
- construction shell
- crafting shell
- overlay modes
- feedback/UI scaffolding

Readiness to leave Phase B:
- player can understand and operate the current systems without debug knowledge
- building, interaction, and state feedback are visible enough for real testing

### Phase C — Building and Base Integrity

Goal:
- the player can create, damage, repair, and reason about a real shelter

Typical work:
- walls, doors, rooms, airlocks, floors
- indoor/outdoor logic
- vertical transitions if retained in scope
- shelter readability and breach consequences

Readiness to leave Phase C:
- building a functioning shelter is a real gameplay action, not a mockup
- breaches and safe interior space matter in practice

### Phase D — World Presence and Exploration Value

Goal:
- the world becomes worth traversing and reading

Typical work:
- biome expansion
- POIs
- flora/resource identity
- atmosphere, weather, time-of-day feel
- underground/secondary layers if in scope

Readiness to leave Phase D:
- walking outward produces differentiated play and visual interest
- the map contains reasons to leave base and return to it

### Phase E — Survival Pressure

Goal:
- being outside is mechanically expensive and emotionally tense

Typical work:
- oxygen
- temperature
- spores/toxicity
- hunger/thirst
- death/recovery loop

Readiness to leave Phase E:
- survival pressure meaningfully shapes route planning and return timing
- the base materially reduces exterior pressure

### Phase F — Infrastructure and Automation Foundations

Goal:
- the player solves pressure through engineering rather than only manual repetition

Typical work:
- power
- air distribution
- water/heat infrastructure
- basic automation helpers

Readiness to leave Phase F:
- infrastructure creates new capability, not just extra maintenance
- base layout and engineering choices matter to performance and safety

### Phase G — Fauna and Combat Pressure

Goal:
- the world actively pushes back and forces defense planning

Typical work:
- hostile fauna
- passive/ecological fauna
- attacks and responses
- combat loop
- base defense

Readiness to leave Phase G:
- the player must defend, route around, or strategically react to creatures
- combat and defense are integrated into the survival/base loop

### Phase H — Progression Systems

Goal:
- the player has a real long-term arc

Typical work:
- tools
- equipment
- decryption/research
- skill progression
- path differentiation setup

Readiness to leave Phase H:
- the player clearly moves from fragile to capable through structured progression
- unlocked capability changes how the player uses the world and the base

### Phase I — Content Expansion and Depth

Goal:
- broaden the game without replacing the core loop

Typical work:
- more recipes
- more stations
- more building classes
- more events
- more biomes/resources/fauna
- deeper exploration spaces

Readiness to leave Phase I:
- content breadth sits on working systems instead of exposing missing foundations

### Phase J — Release Readiness

Goal:
- convert the vertical slice and midgame systems into a shippable product path

Typical work:
- balancing
- sound
- art polish
- optimization hardening
- localization rollout
- mod API hardening
- future co-op planning boundaries

Readiness to leave Phase J:
- no major architectural blocker remains in the critical gameplay loop
- onboarding, progression, and performance meet release targets

## Delivery gates

Every major phase should pass these gates before the next one dominates development:

1. **Gameplay gate**
   The feature set is actually playable, not only technically present.

2. **UI gate**
   The player can operate and read the system without internal project knowledge.

3. **Performance gate**
   The phase does not violate runtime contracts for the core loop it introduces.

4. **Save/load gate**
   Persistent systems do not remain in a purely temporary state.

5. **Documentation gate**
   Canonical docs for the changed area are updated in `docs/`.

## Current tactical interpretation

Given the current state of the project, the near-term execution priority should remain:

1. stabilize foundations and runtime-sensitive world/base loops
2. keep documentation architecture canonical and layered
3. expand only the mechanics that reinforce the sanctuary-vs-hostility fantasy
4. avoid broad content expansion until the governing systems stop shifting

## Dependency order

The high-level dependency chain is:

1. Engine/Foundation
2. UI visibility
3. Building/Base integrity
4. World exploration value
5. Survival pressure
6. Infrastructure
7. Fauna/Combat
8. Progression
9. Content breadth
10. Release/polish

Some workstreams can overlap, but the dependency rule is:
- later layers may start exploration work early
- they should not become the main production focus before the earlier layer is truly stable

## Rules for phase discussions

Before starting a major phase or sub-phase:
- define what is in scope
- define what is out of scope
- define the smoke test
- define the performance-sensitive parts
- define the doc layer that must be updated

This prevents roadmap items from turning into vague endless workstreams.

## Smoke-test principle

Each phase should end with a player-facing smoke test, for example:
- "build a shelter and survive a full loop"
- "leave base, gather, return, and recover"
- "power and air actually make the base safer"
- "a hostile event forces defense, not confusion"

If a phase cannot be demonstrated through a short gameplay scenario, it is not done.
