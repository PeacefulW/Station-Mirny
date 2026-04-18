---
title: Non-Negotiable Experience (Legacy Mirror Path)
doc_type: product_foundation
status: draft
owner: design
source_of_truth: false
legacy_mirror_of: NON_NEGOTIABLE_EXPERIENCE.md
language: en
version: 0.1
last_updated: 2026-04-18
depends_on:
  - GAME_VISION_GDD.md
related_docs:
  - NON_NEGOTIABLE_EXPERIENCE.md
  - GAME_VISION_GDD.md
  - ../05_adrs/0005-light-is-gameplay-system.md
  - ../05_adrs/0006-surface-and-subsurface-are-separate-but-linked.md
  - ../05_adrs/0007-environment-runtime-is-layered-and-distinct-from-worldgen.md
  - ../02_system_specs/meta/multiplayer_authority_and_replication.md
---

# Non-Negotiable Experience (Legacy Mirror Path)

> This file is retained for legacy path compatibility. The canonical source
> remains [NON_NEGOTIABLE_EXPERIENCE.md](./NON_NEGOTIABLE_EXPERIENCE.md).

This document defines the experience-level truths of Station Mirny that must remain intact across all future design, technical, content, and implementation decisions.

If a proposed feature, optimization, content pack, or system refactor weakens these pillars, that proposal should be reconsidered.

This file is intentionally short, sharp, and product-level.
It is not a low-level mechanics spec and not a technical architecture document.

## Purpose

This document exists to protect the emotional and experiential identity of the game.

It answers:

- what the game must *feel like*
- what the player must consistently experience
- what must never be lost, even if details evolve

## This document owns

This file owns:

- the irreducible emotional core of the game
- the highest-priority product pillars
- the non-negotiable player experience
- the experiential filter used to judge future systems and content

## This document does not own

This file does not own:

- low-level runtime architecture
- performance rules
- save/load contracts
- exact formulas
- exact implementation of lighting, weather, seasons, fauna, or world generation
- full lore canon
- milestone sequencing

Those belong in:

- governance docs
- system specs
- content bible
- roadmap / execution docs

## Core experience statement

**Inside feels safe. Outside feels hostile.**

Station Mirny is a survival/base-builder about building real safety in a world that is beautiful, alive, and deeply threatening.

The emotional heart of the game is not simply "survive."

It is:

**create warmth, light, order, and shelter in a world of darkness, wind, cold, uncertainty, and exposure.**

## The primary contrast

The single most important contrast in the entire game is:

- inside vs outside
- light vs darkness
- warmth vs exposure
- shelter vs wilderness
- control vs indifference
- return vs risk

If this contrast becomes weak, the game loses its identity.

## Non-negotiable pillars

### 1. The base must feel like a true sanctuary

The base is not just a container for crafting stations.

It must feel like:

- warmth
- light
- structure
- breathable safety
- emotional reset
- visible player authorship
- human order against planetary hostility

Returning home should feel relieving.

Improving the base should feel meaningful not only mechanically, but emotionally.

### 2. The outside must feel dangerous even when nothing is attacking you

The outside world must be threatening through environment, not only combat.

Threat should come from things like:

- darkness
- wind
- cold
- distance from shelter
- weather
- low visibility
- terrain
- seasonal severity
- environmental uncertainty
- being unprepared

The player should never feel fully casual outside for long.

### 3. Light is safety

Lighting is a core pillar, not decoration.

Light must support:

- readability
- navigation
- emotional comfort
- contrast between interior and exterior
- preparation for expeditions
- underground tension
- fear of failure when light is absent

A lit interior should feel inhabited and safe.
A dark exterior or underground area should feel uncertain and stressful.

### 4. Darkness must be frightening, not merely dim

Darkness should create:

- incomplete information
- hesitation
- vulnerability
- reliance on carried or placed light
- emotional pressure

Night should materially change how the world feels.

Underground darkness should feel even more intimate and dangerous.

### 5. The planet must feel alive

The world must not feel static or dead.

It should feel alive through:

- moving grass
- moving tree-like flora
- wind passing through vegetation
- storms and seasonal shifts
- fauna presence
- distant motion
- environmental response to weather and time

Even when the player is alone, the world should feel inhabited by processes, organisms, and forces.

### 6. Beauty and fear must coexist

The exterior should be beautiful enough that the player wants to explore it.

The same exterior should be hostile enough that exploration always carries tension.

The world must never become:

- visually dead
- mechanically sterile
- merely pretty
- merely ugly
- only punishing without wonder
- only beautiful without danger

### 7. Seasons matter

Seasonal change is mandatory.

The world must pass through major seasonal states analogous to:

- winter-like severity
- spring-like transition
- summer-like relative openness
- autumn-like decline

These do not need to mimic Earth literally.

But they must affect:

- mood
- planning
- visibility of safety
- travel pressure
- infrastructure value
- environmental identity

The player must feel that some times are harsher than others.

### 8. Wind matters

Wind is one of the signature carriers of atmosphere in the game.

Wind must be visible, readable, and emotionally important through:

- vegetation motion
- environmental ambience
- storm escalation
- sense of exposure
- exterior hostility

Wind helps make the outside feel alive and unsafe.

### 9. Underground space is both refuge and danger

Underground play must support both fantasies:

- protected expansion and shelter
- risky excavation and discovery

The player should be able to create:

- a cellar
- underground utility space
- deeper excavated structures

But underground should also remain tense because of:

- darkness
- confinement
- uncertainty
- hidden threats
- what lies deeper

### 10. Preparation must matter

The game loop must preserve the rhythm of:

- prepare
- go out
- endure pressure
- return
- recover
- expand control

Success should come from planning, infrastructure, light, logistics, and knowledge.

Not from careless brute force.

### 11. Co-op must strengthen the fantasy, not flatten it

Future multiplayer should amplify:

- shared preparation
- shared expeditions
- rescue moments
- return-to-base relief
- division of labor under pressure

It must not destroy the core inside/outside contrast.
It must not turn the world into noise-heavy chaos with no tension.

### 12. The player must always feel the world pushing back

No matter how strong the player becomes, the world should never become emotionally trivial.

The player may become more capable.
The player may build stronger infrastructure.
The player may push farther.

But the planet should still feel like something that must be respected, managed, and survived.

## Experience filters for future decisions

When evaluating any new feature, system, biome, content pack, or refactor, ask:

1. Does this strengthen the inside/outside contrast?
2. Does this help the base feel safer, warmer, clearer, or more authored?
3. Does this preserve the fear, uncertainty, or exposure of the outside?
4. Does this support light as safety and darkness as pressure?
5. Does this keep the world alive, beautiful, and threatening?
6. Does this preserve the prepare -> risk -> return -> relief loop?
7. Does this still work with future seasons, underground, and co-op?

If the answer is "no" to several of these, the addition is likely off-direction.

## Anti-goals

The game must not drift into:

- a generic farming sandbox with no dread
- a flat crafting game where the base is only utility
- a combat-first game where environmental hostility stops mattering
- a static world with no wind, no seasonal identity, and no environmental motion
- a permanently comfortable outside world
- a purely miserable game with no beauty, no relief, and no sanctuary
- a systems soup where the emotional loop is no longer readable

## What is allowed to evolve

The following may change without violating this document:

- exact lore details
- exact flora taxonomy
- exact fauna families
- exact weather formulas
- exact seasonal cadence
- exact numerical severity of cold or darkness
- exact underground structure rules
- exact progression pacing
- exact final implementation of the Terraformer late-game identity

These details may evolve.

The emotional truths above should not.

## Final product statement

Station Mirny must remain a game where the player builds a true sanctuary of light, warmth, and order in a living world of wind, darkness, cold, beauty, and fear.

That is the foundation.
Everything else is built on top of it.
