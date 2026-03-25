---
title: Subsurface and Verticality Foundation
doc_type: system_spec
status: draft
owner: design+engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - world_generation_foundation.md
  - environment_runtime_foundation.md
  - lighting_visibility_and_darkness.md
  - ../meta/save_and_persistence.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Subsurface and Verticality Foundation

This document defines the foundational direction for underground space and vertical traversal.

## Purpose

The purpose of this spec is to prevent the project from improvising underground and vertical play as an afterthought.

Subsurface play affects:
- world topology
- mining
- shelter
- readability
- streaming
- save structure
- danger
- co-op coordination

## Core statement

Underground space is a first-class world layer, not a fake visual trick and not a minor extra room type.

It must support both:
- protected player-created utility space such as cellars or underground rooms
- risky excavation, mining and discovery space

## Scope

This spec owns:
- conceptual model for subsurface/vertical play
- architectural constraints for connected surface and underground spaces
- separation between surface truth and subsurface truth
- traversal expectations for stairs/entries/exits
- integration expectations with lighting, mining, persistence and multiplayer

This spec does not own:
- final cave content catalog
- final vertical pathfinding implementation details
- final exact cave generation algorithm

## Pillar role

Subsurface play exists to support the game fantasy by adding:
- refuge from external weather and exposure
- expansion space under player control
- mining and extraction pressure
- darkness-driven exploration tension
- hidden dangers and discoveries

It should feel distinct from both:
- a normal built room on the surface
- open wilderness travel

## Conceptual world model

The project must not assume that the world is only one flat surface plane forever.

The foundational direction is:
- surface and subsurface are separate but linked world layers
- traversal between them happens through explicit connection points
- those connections must be stable for persistence and multiplayer

## Vertical traversal entities

The architecture must support explicit vertical connectors such as:
- stairs
- shafts
- mine entries
- later elevators or equivalents if ever added

These connectors are not just visuals.
They are world links with persistence and traversal implications.

## Subsurface use cases

### 1. Utility cellar / underground room
The player creates a small controlled underground space attached to a base.
Uses may include:
- storage
- protected work area
- thermal shelter fantasy
- expansion when surface footprint is limited

### 2. Excavation and mining
The player digs into enclosed underground mass for:
- resources
- expansion
- route making
- discovery

### 3. Hazard and encounter space
The player may encounter:
- unstable spaces
- dangerous fauna or entities later
- hidden structures
- environmental threats

## Required distinctions

The system should distinguish conceptually between:
- carved player-made underground space
- naturally generated underground space
- connected built underground rooms
- raw enclosed rock/mass not yet opened

Those may share mechanics, but the architecture should not flatten them into one undifferentiated blob.

## Architectural direction

### Surface truth and subsurface truth
Surface and subsurface should not be treated as the same space with a visual toggle.

The system should support:
- separate location identity
- linked traversal
- independent lighting context
- independent environmental context where applicable
- saveable diffs

### Coordinate identity
The project must choose a stable identity model for underground locations.
Even before final implementation details, the architectural rule is:
- underground locations need stable canonical identity
- entries and destinations must survive save/load
- the model must remain multiplayer-safe

### Streaming direction
Subsurface spaces must be streamable like other world spaces.
The system should not assume that the entire underground is always loaded.

## Environment relationship

Subsurface spaces should be allowed to differ from surface in:
- light availability
- weather exposure
- temperature feel
- audio feel
- danger profile

At the same time, they may remain connected to surface systems through:
- entry points
- ventilation or oxygen systems later
- heat/power infrastructure later
- player logistics routes

## Lighting relationship

Underground darkness should be one of the strongest arguments for meaningful lighting.
Underground play must be designed with the expectation that:
- darkness matters
- local light sources matter heavily
- visibility and fear are central to the experience underground

## Mining relationship

Subsurface and mining must share a coherent foundation.
The architecture should not create one unrelated system for mining and a second unrelated system for underground rooms if both operate on the same excavated space model.

## Persistence direction

Save/persistence must support:
- stable identity of underground spaces and connectors
- diff-based modification storage
- exact reloading of player-created excavations and underground rooms

The save model must not depend on dumping an entire giant underground world indiscriminately.

## Multiplayer direction

Co-op introduces additional requirements:
- more than one player may occupy different layers/areas
- traversal through connectors must be authoritative and stable
- visibility/light/loaded-space assumptions must not rely on one-player-only camera logic

## Performance direction

Underground must respect the same performance law as the surface world:
- no giant synchronous rebuild when opening one tile or connector
- no full relight/full redraw of every connected underground space in the interactive path
- local excavation should stay local and queue heavier consequences

## Acceptance criteria

This foundation is successful when:
- underground can serve both as refuge and risk space
- surface and subsurface can remain linked without becoming the same mushy system
- stairs/entries/connectors have stable architectural meaning
- mining, excavation and underground expansion can grow from the same foundation
- persistence and co-op remain feasible

## Failure signs

This foundation is wrong if:
- underground is treated as a fake overlay with no world identity
- cellar/base excavation and mining become unrelated systems with duplicated logic
- traversal links have unstable identity or save/load ambiguity
- one local excavation action implies world-scale synchronous rebuild work

## Open questions

- exact final layer model: one subsurface layer vs multiple depth layers vs local submaps
- exact connector implementation and traversal UX
- exact relation between underground environment and oxygen/ventilation systems
- exact separation between generated caves and purely player-carved space
