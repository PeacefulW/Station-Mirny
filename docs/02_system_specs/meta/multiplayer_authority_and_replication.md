---
title: Multiplayer Authority and Replication
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - multiplayer_and_modding.md
  - save_and_persistence.md
  - ../world/environment_runtime_foundation.md
  - ../world/lighting_visibility_and_darkness.md
  - ../world/subsurface_and_verticality_foundation.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Multiplayer Authority and Replication

This document defines the foundational multiplayer architecture constraints for future 1-4 player co-op in Station Mirny.

This file exists to make sure that current implementation choices do not silently destroy future co-op viability.

The goal is not to fully implement networking now.
The goal is to ensure that world systems, environment systems, building systems, underground systems, AI systems, and persistence systems are designed in a way that can survive the transition to host-authoritative co-op.

## Purpose

The purpose of this document is to define a stable architectural foundation for:

- future small-scale co-op
- authority boundaries
- replicated vs derived vs local-only state
- multiplayer-safe world mutation rules
- multiplayer-safe assumptions for chunks, environment, lighting, underground traversal, and persistence
- design constraints that should apply even before networking is fully implemented

## Gameplay goal

Multiplayer must strengthen the core fantasy rather than dilute it.

Co-op should amplify:

- shared preparation inside the base
- coordinated expeditions
- rescue and recovery moments
- group logistics and infrastructure planning
- shared fear outside
- shared relief on return to shelter

It must not flatten the game into a noisy sandbox where:

- the world loses tension
- authority is ambiguous
- systems become impossible to reason about
- every local visual trick becomes accidental gameplay truth

## Scope

This spec owns:

- the authoritative multiplayer direction
- high-level replication classes
- command/intention boundaries for gameplay mutations
- multiplayer-safe assumptions for world and runtime systems
- the distinction between authoritative truth and local presentation

This spec does not own:

- low-level transport details
- final packet schema
- final prediction or interpolation implementation
- low-level online services integration
- platform-specific networking APIs

Those belong in later implementation or tech notes.

## Core architectural statement

The intended multiplayer model is:

- **small-scale co-op**
- **1-4 players**
- **host-authoritative gameplay truth**
- **clients send intentions/commands**
- **clients may render local presentation details**
- **authoritative results come from the host**

This is the non-negotiable networking foundation unless a future ADR explicitly changes it.

## Canonical model

### Host-authoritative truth
The host owns authoritative gameplay truth for things like:

- world modifications
- placed buildings
- machine state
- inventories and item transfers
- player life state
- entity state
- doors / interactables / connectors
- excavated underground changes
- power-relevant state
- weather/environment state where gameplay-relevant

### Client role
Clients are expected to:

- send player intentions or commands
- receive authoritative world/gameplay updates
- present local visuals and interpolation
- maintain local caches or derived state where allowed

### Important rule
The local client should not be allowed to become hidden gameplay authority just because "it felt easier" in a subsystem.

## Why this matters now

Even before co-op exists in shipping form, the codebase must stop making these assumptions:

- there is only one meaningful player
- the local machine is automatically authoritative
- any script can mutate global world truth directly
- chunk loading is only ever based on one player camera
- local presentation values can safely double as shared gameplay state
- underground traversal only needs to make sense for one local actor

If those assumptions become widespread, multiplayer becomes a rewrite instead of an extension.

## High-level replication classes

The project should separate state into at least three broad classes.

## 1. Authoritative gameplay state
This is shared truth that affects play and must be consistent.

Examples:

- player positions and gameplay state
- health / status / damage
- inventories, item stacks, item transfers
- world diff changes
- mining / excavation results
- building placement / removal
- machine and infrastructure state
- connector state (stairs, underground access, doors, etc.)
- room-related state if gameplay-relevant
- weather or environmental phase if gameplay-relevant
- fauna or hostile entity gameplay state

## 2. Derived reconstructible state
This is state that can be rebuilt from authoritative inputs and stable rules.

Examples:

- local cached topology products
- chunk-local rebuild products
- derived visibility zone classifications
- combined local environmental samples
- rebuildable masks or metadata
- deterministic local caches that do not need to be individually replicated

## 3. Client-local presentation state
This is allowed to vary per client when it does not change gameplay truth.

Examples:

- grass sway phase
- exact particle placement
- shadow softness
- light flicker phase
- interpolation state
- cosmetic camera effects
- some local ambience details

Canonical rule:

**shared gameplay meaning must not depend on client-local presentation state.**

## Command and intention boundaries

Gameplay-changing actions should conceptually flow through commands or intentions rather than arbitrary local mutation.

Examples:

- place building
- remove structure
- excavate tile
- traverse connector
- open/close door
- start or stop machine
- move item between inventories
- pick up item
- use tool
- attack or trigger a hostile action
- place light source
- toggle power-dependent object

This does not require a full final command framework immediately.
It does require architecture that can later route these actions through a host-authoritative path.

## Canonical design rules

### Rule 1: No hidden local authority
If a system mutates meaningful gameplay state, that mutation must be conceptually attributable to an authoritative path.

### Rule 2: Presentation is not truth
A client may render something beautifully and locally, but that does not make it shared gameplay truth.

### Rule 3: Identity must be stable
Players, entities, world references, connectors, placed structures, and persistent world modifications need stable identity.

### Rule 4: More than one player must be imaginable in every major system
Even before networking is finished, system architecture should avoid one-player-only assumptions.

### Rule 5: Streaming and world logic must not collapse into one-camera logic forever
Loaded-space policy may start simple, but the architecture must allow multiple relevant player locations later.

## Entity and object identity

The project must maintain stable identity for gameplay-relevant objects.

This includes at minimum:

- player identities
- network-relevant entities
- placed structures
- underground connectors
- machine instances
- world diff records
- item containers where needed
- fauna instances or persistent groups where needed later

Identity must not depend on fragile scene-tree order or temporary local-only references.

## World mutation rules

World changes must remain multiplayer-safe.

Examples of multiplayer-sensitive world mutations:

- terrain excavation
- wall/floor placement
- underground expansion
- opening access paths
- machine placement
- door toggles
- container inventory changes
- activating environmental controls

Canonical direction:

- world truth changes should be attributable to authoritative actions
- derived chunk or presentation rebuilds may happen locally after authoritative truth changes
- local convenience must not replace a coherent mutation model

## Chunk and world streaming implications

The world model must support the fact that:

- multiple players may be far apart
- more than one area may matter at once
- one player's camera must not become the sole definition of relevant world existence

This does not mean the shipping implementation must immediately support worst-case fully independent world-scale streaming for all players.
It does mean the architecture should not hardcode one-player-only assumptions into core services.

## Underground implications

Subsurface architecture must remain multiplayer-safe.

This means:

- multiple players may occupy different world layers simultaneously
- connectors must have stable shared identity
- traversal cannot rely on one local camera or one local scene assumption forever
- excavation results must belong to authoritative world truth
- underground loading/state meaning must remain stable under co-op

## Environment implications

Environment runtime must distinguish between:

- authoritative or shared gameplay-relevant environment state
- derived reconstructible environmental state
- client-local visual response

Examples:

- current season phase may be shared truth
- weather class may be shared truth if gameplay-relevant
- local grass motion can remain client-local
- some local environmental caches can be reconstructible rather than replicated directly

This is especially important for:

- wind
- storms
- visibility pressure
- lighting context
- temperature/exposure-relevant state

## Lighting implications

Lighting must also follow the same separation.

Examples:

- whether a lamp is powered/on may be authoritative
- whether a zone is considered functionally lit for gameplay semantics may be derived/shared as needed
- exact shadow animation and flicker phase can remain client-local

The project must avoid letting renderer-only state accidentally become authoritative gameplay truth.

## AI / fauna implications

Future fauna and hostile systems must also be multiplayer-safe.

That means:

- authoritative threat behavior cannot depend on one client's presentation state
- perception, target choice, and movement must remain attributable to shared truth
- local visual smoothing or animation can remain client-local

## Save and persistence relationship

Persistence should store authoritative world and player state, not client-local visual presentation state.

The save system should remain coherent for both:

- solo play
- host-authoritative co-op sessions

Canonical rule:

if a thing matters to shared gameplay truth, it must be representable in shared persistent state.

## Failure modes to avoid early

The following are early anti-patterns that make co-op much harder later.

### 1. Global singleton logic that assumes one player forever
For example:

- `PlayerManager.get_player()` as the only meaningful actor path for everything
- environment/AI/streaming systems that assume exactly one actor matters

### 2. Direct local mutation of global truth from arbitrary scripts
For example:

- any interactable directly editing canonical world state with no conceptual command boundary

### 3. Using presentation state as gameplay state
For example:

- reading renderer state to decide whether something is visible, safe, or interactable in shared gameplay logic

### 4. Identity based on scene order or local object lifetime
For example:

- temporary node order implying canonical identity

### 5. One-camera-only chunk assumptions in foundational world services
For example:

- core world logic permanently tied to one local viewport as if future co-op does not exist

## Performance direction

Multiplayer safety does not remove performance law.

The architecture must still avoid:

- world-scale synchronous updates in interactive paths
- unnecessary replication of reconstructible state
- forcing all clients to share identical cosmetic presentation details
- coupling every local presentation update to authoritative net state

Preferred direction:

- replicate authoritative meaning
- rebuild or derive what can be rebuilt locally
- allow client-local visual richness where safe
- keep hot paths bounded and explicit

## Simulation direction

Different simulation classes may need different multiplayer handling.

Typical direction:

- authoritative gameplay simulation: shared/host-driven
- reconstructible local caches: rebuildable per machine
- client-local presentation: non-authoritative

The exact cadence model belongs in `SIMULATION_AND_THREADING_MODEL.md`, but this document establishes the multiplayer relevance of that distinction.

## Minimal architectural seams

These are illustrative, not final APIs.

### Command submission direction

```gdscript
class_name GameplayCommandService
extends RefCounted

func submit_command(command: GameplayCommand) -> void:
    pass
```

### Authority query direction

```gdscript
class_name MultiplayerAuthorityService
extends RefCounted

func is_host() -> bool:
    pass

func is_authoritative_for_world_mutation() -> bool:
    pass
```

### Replication-class thinking example

```gdscript
class_name ReplicationClass
extends RefCounted

enum Kind {
    AUTHORITATIVE,
    DERIVED,
    CLIENT_LOCAL,
}
```

These examples are not final APIs.
They illustrate the required architectural mindset:

- actions should be attributable to commands or intentions
- authority should be explicit
- replication class should be a real design concern

## Success conditions

This foundation is successful when:

- current single-player implementation choices do not silently hard-lock the project against co-op
- world, environment, lighting, underground, and building systems can all be reasoned about in authoritative vs derived vs client-local terms
- major gameplay mutations can be conceptually routed through a host-authoritative path
- stable identity exists for the main classes of persistent/shared objects
- future co-op can extend the architecture instead of rewriting it from scratch

## Failure signs

This foundation is wrong if:

- systems routinely assume a single player forever
- world truth is mutated directly from arbitrary local scripts with no conceptual authority boundary
- client-local visuals are used as if they were shared truth
- stable identity is missing for critical world objects
- chunk/world services are architecturally bound to one local camera as the only future model

## Open questions

The following remain intentionally open:

- exact future join-in-progress behavior
- exact replication strategy for chunk-relevance and remote players far apart
- exact prediction/interpolation policy
- exact authoritative treatment of certain environment and visibility states
- exact long-term entity ownership and handoff details if ever needed

These may evolve without changing the foundation above.
