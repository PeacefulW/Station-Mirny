---
title: Game Vision GDD
doc_type: product
status: approved
owner: design
source_of_truth: true
version: 1.1
last_updated: 2026-03-25
related_docs:
  - ../02_system_specs/README.md
  - ../03_content_bible/lore/canon.md
  - ../04_execution/MASTER_ROADMAP.md
---

# Game Vision GDD

This is the canonical product-layer document for Station Mirny.

## Product role

This file owns:
- core fantasy
- player fantasy
- product pillars
- unique selling points
- high-level gameplay loop
- high-level progression arc
- high-level path split
- high-level world and lore framing

This file does not own:
- low-level runtime architecture
- performance rules
- detailed system contracts
- exhaustive content catalogs
- milestone sequencing

Those belong in:
- [Engineering Standards](../00_governance/ENGINEERING_STANDARDS.md)
- [Performance Contracts](../00_governance/PERFORMANCE_CONTRACTS.md)
- `docs/02_system_specs/*`
- `docs/03_content_bible/*`
- [Master Roadmap](../04_execution/MASTER_ROADMAP.md)

## Project framing

- Genre: 2D top-down survival / base-builder with automation and RPG elements
- Engine: Godot 4
- Primary platform: PC
- Long-term target: a deep single-player survival/base-building game with future co-op potential
- Intended scope: long-form progression, multiple strategic arcs, strong atmosphere, meaningful home/base fantasy

## Core fantasy

**"Inside the base feels safe. Outside feels hostile."**

The player is an Engineer stranded on a hostile planet.

The planet is breathable only in the weakest sense, full of spores, cold nights, and constant environmental pressure. Safety does not exist by default. The player must build it.

The emotional loop is:
- go outside under pressure
- take risks to gather resources, scout, or survive
- return home to air, light, warmth, and order

The base is not just a crafting station cluster. It is the player's manually built island of safety in a world that is always trying to reclaim it.

## Player fantasy

The player fantasy combines:
- survivor
- field engineer
- base architect
- expedition operator
- late-game world shaper

The player should feel:
- vulnerable early
- competent in midgame
- strategically powerful late
- but always dependent on infrastructure, preparation, and environment control

## Product pillars

1. **Base as sanctuary**
   The strongest emotional contrast in the game is between exterior threat and interior safety.

2. **Hostile world, not just hostile enemies**
   The environment itself is a system of pressure: O2, spores, temperature, storms, terrain, darkness, and logistics.

3. **Infrastructure matters**
   Survival is not solved by stats alone. It is solved by rooms, air, power, water, heat, routing, and engineering choices.

4. **Expeditions have tension**
   Every trip outside the walls should involve planning, cost, risk, and relief on return.

5. **Two late-game identities**
   The player does not simply become stronger. They eventually commit to a worldview:
   - Terraformer
   - Adaptation

6. **Lore reinforces mechanics**
   The mystery of the planet should not feel detached from gameplay. The world's biological hostility, mutation pressure, ruins, and progression should all support the central reveal.

## Unique selling points

1. **Two divergent development paths with different fantasy and aesthetics**
   - Terraformer: industrial bunker, machinery, environmental domination
   - Adaptation: symbiosis, mutation, biological integration

2. **Save/load tied to fiction**
   Persistence is not just a menu feature; it has an in-world explanation and progression role.

3. **Decryption instead of traditional research**
   Technology is not invented from scratch. It is recovered from damaged human archives.

4. **Environment as living pressure**
   Spores, contamination, system clogging, breaches, and environmental decay give the world its own agency.

5. **Late lore twist with mechanical consequences**
   The planet is not merely alien; it is bound to humanity's origin and reshapes the meaning of both progression paths.

## High-level emotional references

Use these as feeling references, not as implementation law:

- Atmosphere: Stalker, Interstellar
- Base ownership and room-building tension: RimWorld
- Direct control and production clarity: Factorio
- Survival pressure and expedition mood: Subnautica, Don't Starve

## World framing

Humanity survived Earth's collapse by living on the Ark, a giant orbital city-ship. Engineers are sent to candidate worlds with knowledge archives, tools, and survival equipment.

The player is one such Engineer. The landing failed. The module crashed. The archives are damaged. Contact is gone. The player must survive and build alone.

The planet is beautiful, hostile, windswept, spore-ridden, and full of traces of an older civilization.

## High-level lore truth

The late reveal is:
- the planet is tied to humanity's origin
- the spores are not simply poison but a biological rollback pressure
- the two major progression paths become ideological as well as mechanical choices

Detailed canon and reveal sequencing should live in the content bible, not in this file.

## High-level gameplay loop

The intended repeated loop is:

1. Stabilize the base.
2. Prepare for an exterior trip.
3. Go outside to gather, scout, mine, fight, or reach a point of interest.
4. Return before logistics or survival systems fail.
5. Reprocess what was gained into stronger infrastructure.
6. Use stronger infrastructure to go farther, survive longer, and unlock new problems.

The key emotional rhythm is:
- preparation
- tension
- extraction
- return
- relief
- expansion

## High-level progression arc

### Early game
- survive the crash
- secure immediate shelter
- stabilize air, heat, and basic materials
- learn that the exterior is dangerous and costly

### Midgame
- expand infrastructure
- formalize production chains
- build safer expeditions
- explore ruins, underground areas, and rarer biomes
- start decryption and wider territorial presence

### Late game
- commit to Terraformer or Adaptation
- express that path through infrastructure and progression
- understand the truth of the planet
- reach an end-state that reflects the chosen philosophy

## The two paths

### Terraformer

Fantasy:
- impose order on a hostile world
- industrialize survival
- turn danger into controlled infrastructure

Expected aesthetic:
- bunker logic
- machinery
- hard surfaces
- environmental domination

### Adaptation

Fantasy:
- stop forcing the world to become Earth
- change the self instead
- survive through biological integration

Expected aesthetic:
- symbiosis
- organic structures
- mutation
- coexistence with hostile ecology

## Base fantasy

The base should feel like:
- shelter
- logistics hub
- emotional reset point
- player authorship made visible

Returning to the base should communicate:
- air
- warmth
- light
- organization
- control

Losing integrity in the base should feel serious because it attacks the game's core fantasy directly.

## Exterior fantasy

The outside should feel:
- costly
- exposed
- uncertain
- beautiful but unsafe

Threat does not need to come only from combat. It should come from:
- oxygen pressure
- contamination
- temperature
- distance
- visibility
- navigation
- noise
- time of day

## Day/night and seasons at product level

At the product level:
- day supports travel and planning
- night increases tension and vulnerability
- seasons shift the strategic value of infrastructure, exploration, and resource access

Detailed numerical balance and implementation rules belong elsewhere.

## Content boundaries for this document

This file should describe:
- why a system matters
- what experience it supports
- what role it plays in progression

It should not become:
- a wall of raw recipes
- an engineering architecture spec
- a performance manual
- a full lore encyclopedia
- a milestone checklist

## Current canonical product statement

Station Mirny is a survival/base-builder where the strongest fantasy is not simply "stay alive" but:

**build a real sanctuary in a world that is always trying to take it back.**

The player survives by engineering safety, then eventually chooses whether that safety means dominating the planet or changing to belong to it.
