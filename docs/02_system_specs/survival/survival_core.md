---
title: Survival Core
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - ../../01_product/GAME_VISION_GDD.md
  - ../base/engineering_networks.md
  - ../progression/character_progression.md
---

# Survival Core

This document defines the runtime survival contract for the engineer on hostile planets.

## Purpose

Survival systems create pressure that makes the base feel necessary, expeditions risky, and preparation meaningful.

## Gameplay goal

The player should constantly feel:
- outside is expensive and dangerous
- the base is relief, safety and recovery
- every expedition is a calculation of oxygen, toxicity, temperature, stamina and return path

## Scope

This spec owns:
- personal survival meters
- atmosphere and spore exposure
- food and water pressure
- fatigue pressure
- death and save logic as part of survival progression

## Out of scope

This spec does not own:
- room engineering distribution
- resource identities
- fauna content catalog
- event content

## Core survival variables

### Required meters

| Meter | Meaning | Failure behavior |
|---|---|---|
| `oxygen` | suit oxygen reserve | hypoxia chain, loss of performance, death |
| `toxicity` | internal spore burden | coughing, hallucination, sickness, death |
| `body_temperature` | thermal stress | freezing / overheating penalties |
| `hunger` | long-term caloric pressure | weaker recovery, eventual death |
| `thirst` | short-term hydration pressure | faster collapse than hunger |
| `fatigue` | accumulated exhaustion | lower speed, accuracy and reliability |

## Oxygen and hypoxia

### Design rule

Oxygen failure must be dramatic and readable, not instant.

### Expected progression

1. oxygen becomes low
2. stamina collapses
3. movement becomes heavy
4. screen readability worsens
5. the player scrambles back toward safety
6. collapse and death only happen after visible warning stages

The intended emotion is tension, not arbitrary punishment.

## Spores and toxicity

Spores are a dual threat:
- biological threat to the engineer
- contamination threat to machines and base systems

### Player-side effects

Toxicity can produce:
- coughing that compromises stealth
- hallucination-like peripheral noise
- long-term sickness pressure
- demand for medicine / antidotes

### Base-side implication

Spores clog compressors and contaminate interior space if the perimeter fails.

That means survival and engineering are intentionally coupled.

## Food and water

### Food sources

Stable food should come primarily from:
- greenhouse / hydroponics
- processed fauna products
- processed local flora
- later synthetic food chains

### Water rule

Raw water is not assumed safe.
The survival loop expects:
- extraction
- filtering / purification
- distribution into base systems

## Fatigue

Fatigue exists to make extended activity and long expeditions meaningfully different from short local tasks.

Desired effects:
- lower movement efficiency
- worse combat handling
- stronger need to return to base and sleep

## Death and save logic

### Early-game policy

Difficulty mode determines baseline save harshness:
- hardcore = permadeath
- standard = save on quit
- easy = daily autosave

### Lore-integrated save progression

Later, survival/save becomes partially diegetic:
- special blood discovery introduces a lore checkpoint mechanic
- later laboratory progression allows cleaner manual checkpoint creation

The important design rule is:
- saving is not only a menu feature
- it becomes part of survival/biological progression

## Dependencies

- engineering networks for interior safe air and water
- character progression for suit and metabolism upgrades
- crafting/decryption for antidotes, filters and survival modules
- events/weather for global survival pressure

## Runtime and performance class

This is an interactive-path system.

Rules:
- changing one meter must be O(1)
- no world-scale rebuilds may happen from survival ticks
- visual effects must degrade gracefully rather than hitch the frame

## Acceptance criteria

- the player can read why they are failing
- oxygen shortage is recoverable if the player planned well
- spore toxicity matters outside but does not make early play impossible
- food/water matter, but do not drown the player in chores
- death/save logic feels fair and readable on each difficulty

## Failure signs

- meters become pure annoyance rather than expedition planning
- oxygen death feels instant
- toxicity is either ignorable or oppressive
- food and water create repetitive busywork
- death rules feel disconnected from lore progression

## Open questions

- exact early-game harshness targets by difficulty
- how much of fatigue should be simulated vs abstracted
- final implementation of interior contamination spread after breaches
