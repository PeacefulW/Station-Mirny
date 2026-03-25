---
title: Lighting, Visibility and Darkness
doc_type: system_spec
status: draft
owner: design+engineering
source_of_truth: true
version: 0.1
last_updated: 2026-03-25
related_docs:
  - environment_runtime_foundation.md
  - subsurface_and_verticality_foundation.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
---

# Lighting, Visibility and Darkness

This document defines the gameplay-support role of lighting, darkness and visibility in Station Mirny.

## Purpose

The purpose of this spec is to ensure that lighting is treated as a foundational gameplay-support system rather than a disposable visual effect.

## Core statement

In Station Mirny:
- light means safety, orientation and human presence
- darkness means uncertainty, vulnerability and pressure

The rendering technology may evolve.
The gameplay role of lighting and darkness must remain stable.

## Scope

This spec owns:
- the gameplay/support role of light and darkness
- visibility categories
- indoor/outdoor/underground readability goals
- relationships with time, weather, power and shelter
- architecture-level boundaries between rendering and gameplay truth

This spec does not own:
- low-level shadow engine implementation details
- exact shader or renderer choices
- exact final numerical balance of visibility penalties if those exist

## Pillar-level expectations

Lighting must help create the contrast between:
- cozy base interior
- hostile outside world
- open travel vs unknown darkness
- prepared expedition vs unprepared exposure

If lighting stops serving that contrast, the system is failing the product fantasy.

## Lighting roles

### 1. Readability
Light helps the player read:
- walkable space
- entrances/exits
- danger silhouettes
- interactable objects
- room occupancy and safety

### 2. Emotional safety
Interior light sources should communicate:
- habitation
- warmth
- protection
- functional infrastructure

### 3. Pressure escalation
Darkness should intensify pressure during:
- night
- storms
- power failure
- wilderness travel
- underground exploration

### 4. Recovery and relief
Returning to a lit space should create emotional relief.
This is one of the core loop payoffs.

## Visibility contexts

The system should support at least these contexts conceptually:

### Base interior
Expected qualities:
- highest readability
- strongest sense of safety
- clear artificial light identity

### Surface daytime
Expected qualities:
- broader natural visibility
- weather and biome modulation still possible
- exploration is readable but not risk-free

### Surface night
Expected qualities:
- significantly increased uncertainty
- dependence on carried or placed light
- stronger threat atmosphere

### Severe weather surface
Expected qualities:
- degraded readability
- stronger contrast between lit and unlit areas
- increased pressure without necessarily making play unreadable

### Underground
Expected qualities:
- darkness as default
- local light sources matter heavily
- claustrophobic but information-rich if prepared correctly

## Light source classes

The architecture should distinguish between conceptually different light sources.

Examples:
- structural base lighting
- portable lights
- fire / torch-like lights
- emergency or low-power lighting
- environmental or alien light sources

Different classes may differ in:
- stability
- warmth/comfort identity
- power dependency
- gameplay expectation

## Darkness classes

Darkness should not be treated as one flat thing.
Different darkness contexts should be allowed to feel different:
- ordinary nighttime darkness
- storm-muted darkness
- underground darkness
- power-loss darkness inside a base
- ominous biome-specific darkness later

## System boundaries

### Rendering layer
Owns:
- visual shadow rendering
- occlusion and shading implementation
- particle/light composition
- presentation quality scaling

### Gameplay-support layer
Owns:
- whether an area counts as lit enough for intended readability/safety semantics
- interaction hooks with power, weather, shelter and time of day
- state flags or queries other systems may consume

### Design rule
Do not force gameplay logic to infer critical light state by scraping renderer internals.
Provide clean queries or states when other systems need to know whether an area is effectively lit.

## Dependencies and hooks

Lighting and visibility should be able to react to:
- time of day
- weather severity
- season mood/state where relevant
- indoor/outdoor context
- underground context
- power network state
- local placed light sources

Other systems that may consume visibility/light information include:
- survival/exposure presentation
- threat behavior hooks
- player guidance/tutorial systems
- ambience/audio
- stealth or fear mechanics later if introduced

## Multiplayer direction

The architecture must allow the difference between:
- authoritative light-relevant gameplay state
- client-local visual rendering details

Example direction:
- whether a powered lamp is on may be authoritative
- exact shadow softness or local animation may remain client-side

## Performance direction

Lighting is important enough that the project may have custom shadow/rendering tech.
That does not remove performance law.

The system must still avoid:
- giant synchronous world relight passes in interactive paths
- unnecessary coupling between gameplay mutation and expensive full redraw
- brute-force reprocessing of all loaded space for local light changes

## Acceptance criteria

This foundation is successful when:
- lit interiors feel safe and inhabited
- darkness outside and underground increases tension clearly
- lighting meaningfully supports navigation and threat readability
- weather/time/power changes can influence visibility without architecture collapse
- the system can remain compatible with performance constraints and future co-op

## Failure signs

This foundation is wrong if:
- light is treated as a pure cosmetic layer with no system role
- darkness is visually present but emotionally or mechanically irrelevant
- every gameplay system directly pokes renderer internals for light knowledge
- local light changes require brute-force world-scale updates

## Open questions

- exact gameplay consequences of insufficient light, if any
- exact relation between visibility state and fauna behavior later
- exact interaction between emergency power, lighting tiers and base safety feeling
- exact boundary between readability support and hard gameplay penalties
