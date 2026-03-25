---
title: Subsurface and Verticality Foundation
doc_type: system_spec
status: draft
owner: design+engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
depends_on:
  - world_generation_foundation.md
  - environment_runtime_foundation.md
related_docs:
  - world_generation_foundation.md
  - environment_runtime_foundation.md
  - lighting_visibility_and_darkness.md
  - ../base/building_and_rooms.md
  - ../meta/save_and_persistence.md
  - ../meta/multiplayer_authority_and_replication.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Subsurface and Verticality Foundation

This document defines the architectural foundation for underground space, excavation, cellar creation, vertical traversal, and the relationship between surface and subsurface world layers in Station Mirny.

This is not just a mining note.
It exists to make sure that underground play is treated as a first-class world layer from the beginning rather than becoming a late workaround that breaks save/load, world identity, lighting, multiplayer, and streaming.

## Purpose

The purpose of this document is to define a stable foundation for:

- cellar and basement creation
- excavation into mountain or underground mass
- underground expansion as part of the base fantasy
- mining and digging into dangerous hidden spaces
- stairs and other vertical connectors
- stable identity for linked surface/subsurface spaces
- future compatibility with co-op, persistence, and world streaming

## Gameplay goal

Subsurface play must support two equally important fantasies:

- **refuge**: creating protected underground utility or living spaces such as a cellar, bunker extension, workshop, storage room, or deeper base module
- **risk**: digging into darkness, enclosed mass, hidden caverns, buried resources, and potentially dangerous unknowns

The player should be able to experience both of these truths:

- "I made a safer, more protected space under my base"
- "I went too deep into something dark and not fully understood"

That contrast is essential.

## Scope

This spec owns:

- the conceptual world model for surface and subsurface space
- the architectural role of vertical connectors
- the relationship between excavation, mining, cellar creation, and underground expansion
- stability requirements for underground identity and persistence
- underground-specific expectations for lighting, visibility, risk, and readability
- performance and multiplayer compatibility direction

This spec does not own:

- the final cave content catalog
- the exact final resource distribution tables
- the final AI/fauna behavior for underground threats
- low-level tile digging implementation details
- exact final UX of stairs or transitions

Those belong in future implementation or subsystem docs.

## Core architectural statement

Underground space in Station Mirny is a **real world layer**, not a fake visual effect and not a one-off feature.

It must be able to support:

- player-created underground rooms
- mining tunnels and excavated voids
- natural underground spaces where applicable
- meaningful vertical traversal between world layers
- independent darkness, readability, and danger identity

If underground is treated as just "surface with darker tiles," the architecture is wrong.

## Product-level truth

The emotional role of the underground is important.

Surface exterior pressure comes from:

- weather
- wind
- cold
- visibility
- distance from shelter
- exposure

Underground pressure comes from:

- darkness
- confinement
- uncertainty
- limited visibility radius
- structural enclosure
- hidden danger
- dependence on preparation and light

Underground refuge is powerful precisely because underground risk is also real.

## Core use cases

The foundation must support at least the following use cases.

### 1. Simple cellar under a base
The player places stairs or another connector, descends, and finds only a small initially open underground footprint.
Most surrounding space remains enclosed mass.
The player excavates outward to create:

- a food cellar
- storage space
- protected utility room
- hidden safe room
- a more insulated work area

### 2. Mining and excavation
The player digs into underground mass in search of:

- resources
- rare deposits
- expansion space
- hidden structures
- unusual underground features
- riskier or deeper opportunities

### 3. Mountain or enclosed terrain penetration
The player cuts into a mountain or similar terrain body and opens hidden interior spaces, tunnels, or chambers.

### 4. Dangerous discovery
The player may uncover:

- hazardous pockets
- underground fauna or threats later
- unstable spaces
- alien or precursor structures
- deeper systems that are not immediately safe or understood

### 5. Multi-room underground expansion
The player eventually builds deliberate underground infrastructure instead of treating the underground as one messy tunnel.

## Conceptual world model

The project must not assume that the world is only one flat surface forever.

The foundation direction is:

- the surface is one world layer
- the subsurface is another linked world layer
- traversal between them happens through explicit connectors
- the relationship between the two must be stable for persistence and co-op

This spec does **not** force the final implementation to be one exact technical representation.
But it does require that the project behave as if subsurface has stable world meaning.

## Surface and subsurface are separate but linked

Canonical rule:

- surface and subsurface are not the same space with a shader toggle
- they are linked spaces with different context and different gameplay identity

This means the architecture should allow differences in:

- readability
- lighting rules
- environmental pressure
- streaming needs
- room usage
- threat profile
- visibility and navigation feel

At the same time, the two layers must remain linked by:

- connector identity
- shared base logistics where applicable
- stable save/load references
- coherent player traversal

## Vertical connectors

Vertical traversal must happen through explicit world connectors.

Examples:

- stairs
- ladders if ever introduced
- shafts
- mine access points
- elevator-like devices later if ever added

The important architectural rule is that these are not just decorative placements.
They are meaningful connection objects between world spaces.

A connector should be able to answer questions like:

- where does it lead?
- what surface location is it anchored to?
- what underground location is it connected to?
- does it still exist?
- is it traversable?
- is it powered, blocked, damaged, or restricted later if needed?

## First-step cellar expectation

One of the core intended player experiences is:

- the player builds or places a stair-like connector
- goes down into a very small initial underground opening
- sees that most of the surrounding underground is still enclosed material
- excavates further to shape the underground space manually

This use case is now explicitly part of the foundation.
It must not be treated later as an edge case.

## Excavation model direction

Underground space must support the distinction between:

- **solid enclosed mass** not yet opened
- **excavated traversable space** created by player digging or generation
- **built underground room space** where the player has started structuring the area intentionally
- **natural underground/open space** if such generated spaces exist

These may share a common tile/grid foundation.
But they must remain conceptually distinguishable.

## Cellar vs mine vs underground room

The project should not create three unrelated systems for:

- cellar creation
- mining tunnels
- underground rooms

They may differ in content, mood, and player purpose, but they should grow from a shared underground-space foundation.

That means the architecture should aim for one coherent model where:

- excavation opens space
- opened space may later be structured or built into rooms
- different underground areas may have different tags, functions, or support states

## Natural vs player-made underground space

The architecture should leave room for both:

- player-carved underground spaces
- naturally generated underground spaces

These should not be forced into the same content meaning, even if they share underlying representation.

Examples:

- a player-dug cellar should feel controlled and practical
- a natural cavern or buried anomaly should feel alien, uncontrolled, and risky

## Underground identity and coordinates

The project must maintain stable identity for underground locations.

Even before final implementation details are chosen, the following must be true:

- underground spaces need canonical identity
- connectors must reliably link surface and subsurface positions
- save/load must restore those links exactly
- multiplayer must not depend on brittle one-player-only assumptions

The final implementation may use:

- layered coordinates
- linked submaps
- canonical layer identifiers
- depth-aware world references

This spec does not lock one exact encoding.
It locks the requirement for stable identity.

## Traversal expectations

Vertical traversal should feel deliberate.

The architecture should support the idea that moving underground is a transition into a different context, not merely stepping onto a different colored tile.

Traversal should preserve or enable:

- stable spatial meaning
- correct loading/streaming of relevant areas
- correct lighting context
- correct environmental context
- consistent player and entity positioning

## Relationship with lighting and darkness

Underground play is one of the strongest arguments for meaningful lighting systems.

Underground should assume:

- darkness is the default
- local light sources are critical
- readability is fragile when unprepared
- the edge of light matters emotionally and practically
- carved safe pockets feel safer because the surrounding dark is real

Underground must integrate tightly with:

- `lighting_visibility_and_darkness.md`
- environment runtime
- future power/infrastructure systems

## Relationship with environment runtime

Subsurface spaces should be allowed to differ from surface spaces in:

- wind exposure
- weather exposure
- apparent temperature profile
- ambient sound character
- visibility pressure profile

At the same time, subsurface may still interact with broader systems such as:

- heat distribution later
- power later
- room support systems later
- logistics routes later

Canonical rule:
underground is not isolated from the rest of the game, but it should not simply inherit surface conditions blindly.

## Relationship with building and rooms

Underground should be compatible with the base-building fantasy.

The player should be able to create underground spaces that feel like:

- cellars
- storage rooms
- utility rooms
- protected base extensions
- deeper industrial or survival spaces later

This means underground space must remain compatible with:

- room logic
- infrastructure extension
- future power/heat/air systems
- player-authored structural layout

## Relationship with mining and resources

Mining is not a separate universe from subsurface play.

Mining should be able to use the same foundational world layer so that:

- digging for resources opens navigable or partially navigable spaces
- tunnels can become infrastructure later
- resource pursuit naturally produces underground geography
- underground geography can create new risk

Canonical rule:
resource extraction and underground world-shaping should reinforce each other rather than live in isolated systems.

## Relationship with threat and discovery

Underground space should be architecturally capable of hosting:

- hidden threats
- fauna encounters later
- buried structures
- anomalies
- environmental hazards
- deeper-tier resource areas

This does not mean all underground must always be combat-heavy.
It means the architecture must allow underground to be more than just storage plus ore.

## Streaming direction

Subsurface spaces must be streamable.

The architecture must not assume that the entire underground world is always loaded.

Streaming must be compatible with:

- explicit connectors
- more than one player later
- linked but separate world contexts
- local excavation events that only affect nearby space

Canonical rule:
opening one underground area must not imply loading or rebuilding the entire underground layer.

## Persistence direction

Save/persistence must support:

- stable connector identity
- excavated space restoration
- underground built-space restoration
- exact recovery of player-created cellar/tunnel layouts
- exact recovery of linked surface/subsurface traversal points

The persistence model should remain compatible with immutable generated base + runtime diff where possible.

Likely direction:

- stable base world rules remain deterministic
- excavation/build changes are stored as runtime diff or equivalent persistent modification records

This document does not define the full persistence format.
It defines the required persistence behavior.

## Multiplayer direction

The underground foundation must remain compatible with future 1-4 player co-op.

This means:

- more than one player may occupy different world layers or different underground areas simultaneously
- connector traversal cannot assume a single local focus point forever
- world loading and state meaning must remain authoritative and stable
- underground changes cannot be encoded in ways that break host-authoritative world truth

Canonical rule:
subsurface architecture must be multiplayer-safe from the beginning, even before multiplayer is fully implemented.

## Performance direction

Underground systems must obey the same performance laws as the surface world.

The architecture must avoid:

- giant synchronous rebuilds when opening one tile
- full relight or full topology rebuild of all underground space after local digging
- global rescans triggered directly by local excavation in the interactive path
- forcing the entire underground layer to update at one cadence

Preferred direction:

- local excavation stays local
- heavy derived consequences are queued, budgeted, or rebuilt incrementally
- presentation richness degrades before interaction responsiveness does
- underground rebuild behavior follows the same runtime law as the rest of the world

## Simulation direction

Subsurface systems should not be treated as one monolithic always-loaded simulation.

The intended direction is layered:

- immediate local tile/opening response for player feedback
- local neighbor/zone updates where required
- heavier derived products rebuilt incrementally or on demand
- streamed loading of relevant underground spaces only

## Visibility and readability expectations underground

Underground readability should support the following emotional states:

### Controlled underground pocket
A small excavated lit area under the base should feel:

- protective
- useful
- intentional
- player-authored

### Expanding work frontier
A partially excavated area should feel:

- functional but incomplete
- near safety but not fully safe
- dependent on additional light and planning

### Raw dark underground
An unlit or weakly lit underground area should feel:

- uncertain
- risky
- not fully under control
- capable of hiding threat or discovery

These distinctions matter a lot for the identity of the underground.

## Minimal architectural seams

These are illustrative, not final APIs.

### Underground world service

```gdscript
class_name SubsurfaceService
extends RefCounted

func get_subsurface_context(world_ref: WorldRef) -> SubsurfaceContext:
    pass
```

### Connector service

```gdscript
class_name VerticalConnectorService
extends RefCounted

func get_linked_destination(connector_id: StringName) -> WorldRef:
    pass

func is_connector_traversable(connector_id: StringName) -> bool:
    pass
```

### Excavation query direction

```gdscript
class_name ExcavationService
extends RefCounted

func can_excavate(cell_ref: CellRef) -> bool:
    pass

func excavate(cell_ref: CellRef) -> ExcavationResult:
    pass
```

These examples are not binding APIs.
They illustrate the required architectural seams:

- underground context is queryable
- connectors have stable identity
- excavation is a real system operation, not a random visual hack

## Success conditions

This foundation is successful when:

- a player can create a cellar or bunker-like underground extension naturally
- the first underground descent feels like entry into a distinct world context
- mining, excavation, and underground rooms can grow from one coherent system foundation
- surface and subsurface remain linked without collapsing into one indistinct mush
- underground darkness and local light feel meaningful
- save/load and future co-op remain feasible
- local digging does not force catastrophic rebuild behavior

## Failure signs

This foundation is wrong if:

- underground is treated as a simple darker copy of the surface
- cellar creation, mining, and underground rooms become unrelated feature silos
- connectors have unstable identity or unreliable save/load behavior
- underground logic silently assumes one player forever
- local excavation triggers world-scale rebuilds
- underground spaces have no strong lighting/readability identity of their own

## Open questions

The following remain intentionally open:

- exact technical representation: layered coordinates vs linked submaps vs another stable model
- exact depth model: one underground layer vs multiple layers later
- exact UX of vertical traversal
- exact interaction between underground space and future heat/air/support systems
- exact representation of natural caves vs player-excavated spaces
- exact underground hazard taxonomy

These may evolve without changing the foundation above.
