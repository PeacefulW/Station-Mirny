---
title: Non-Negotiable Experience
doc_type: product_foundation
status: draft
owner: design+engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - GAME_VISION_GDD.md
  - ../02_system_specs/world/environment_runtime_foundation.md
  - ../02_system_specs/world/lighting_visibility_and_darkness.md
  - ../02_system_specs/world/subsurface_and_verticality_foundation.md
---

# Non-Negotiable Experience

This document captures the experience-level truths that must survive all system, content and implementation decisions.

If a proposed mechanic, optimization, content pack, or rendering shortcut breaks these pillars, the change should be redesigned.

## Purpose

The purpose of this document is to define the irreducible player experience of Station Mirny.

This file is not a detailed implementation spec.
It is the product foundation that all system specs must protect.

## Core fantasy

Station Mirny is a survival base-builder where:
- inside the base feels warm, lit, controlled and human
- outside feels vast, cold, dark, unstable and frightening
- the world is beautiful enough to tempt exploration
- the same world is hostile enough to make every expedition feel risky

The game must preserve the contrast between:
- shelter and exposure
- light and darkness
- order and wildness
- known routes and the unknown
- temporary safety and planetary indifference

## Non-negotiable pillars

### 1. Cozy inside, hostile outside
The emotional spine of the game is the contrast between a safe interior and a dangerous exterior.

Base interiors should communicate:
- warmth
- visibility
- habitability
- managed resources
- human presence

The exterior should communicate:
- exposure
- vulnerability
- uncertainty
- environmental pressure
- ecological or atmospheric hostility

### 2. Light is safety, darkness is pressure
Light is not cosmetic dressing.
It is one of the primary emotional and readability systems in the game.

Lighting must support:
- navigation
- comfort
- threat readability
- indoor/outdoor contrast
- fear escalation at night, during storms, underground, or during failures

Darkness must support:
- uncertainty
- incomplete information
- tension
- environmental dread

### 3. Wind, weather and seasonal change are part of the fantasy
The world should feel alive through:
- wind passing through flora
- precipitation
- atmospheric motion
- changing seasonal states
- visible environmental response

These are not optional flavor-only effects.
They are part of the identity of the world.

### 4. The world must be beautiful and frightening at the same time
The player should want to go outside because the world is visually compelling.
The player should hesitate because it is dangerous.

Beauty and dread must coexist.
A sterile or visually dead outside world would fail the fantasy.
A purely pretty, non-threatening outside world would also fail the fantasy.

### 5. The outside gets worse with distance, night and season
Pressure should increase under conditions such as:
- long travel away from shelter
- darkness
- winter-like severe seasonal phases
- bad weather
- biome or region hostility

The player should feel that preparation matters.

### 6. Underground space is both refuge and danger
Subsurface play is not a gimmick.
It must support:
- cellars / storage / protected expansion
- excavation and mining
- hidden danger
- discovery
- resource pursuit under risk

Underground space should feel distinct from both the open surface and the built base interior.

### 7. The world should feel inhabited, not empty
The player should sense life and motion through:
- flora reacting to wind
- visible environmental motion
- fauna presence
- ambient movement in the sky or distance
- changes in atmosphere and soundscape

Not every creature needs to be hostile.
The planet should feel ecologically present.

### 8. Co-op must preserve the same fantasy, not dilute it
Multiplayer should strengthen:
- shared fear outside
- shared work inside
- rescue / logistics / planning moments
- group expeditions and retreats

Co-op must not flatten the game into a noise-heavy sandbox with no tension.

### 9. Readability matters more than simulation vanity
The game may be systemic and deep, but the player must be able to read:
- where safety is
- what the weather is doing
- whether they are exposed
- whether light is sufficient
- whether shelter is near
- whether the environment is worsening

### 10. Every foundational system must reinforce the emotional loop
World generation, lighting, environment runtime, underground, fauna, sound, seasons, and base engineering should all reinforce the same loop:
- prepare inside
- go outside with intent
- feel pressure and uncertainty
- return to safety with relief
- expand human control a little further

## Usage rule

When a system spec or implementation is created, it should be checked against these questions:
- does this strengthen the inside/outside contrast?
- does this protect the role of light and darkness?
- does this preserve environmental pressure?
- does this support beauty plus dread?
- does this keep outside travel meaningful?

If the answer is no, the system is drifting away from the intended game.

## Open questions to resolve later

These remain open without weakening the pillars above:
- exact lore framing of local flora and tree-like forms
- exact severity and cadence of seasonal transitions
- exact temperature model and exposure penalties
- exact underground threat families
- exact final balance between cozy simulation and survival pressure

Those may evolve.
The pillars above should not.
