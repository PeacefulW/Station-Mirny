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
  - ../../00_governance/SIMULATION_AND_THREADING_MODEL.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# Multiplayer Authority and Replication

This document defines the foundational multiplayer architecture constraints for future co-op play.

## Purpose

The purpose of this spec is to ensure that current single-player implementation choices do not silently block the intended future co-op model.

## Core statement

The target multiplayer model is small-scale host-authoritative co-op for 1-4 players.

This means the project must assume from now on that:
- more than one player can exist
- the host owns authoritative world/gameplay truth
- clients may present derived visuals locally
- systems must not be built around single-player-only identity or timing assumptions

## Scope

This spec owns:
- host-authoritative foundation
- replication classes
- authority-aware identity rules
- current implementation constraints for multiplayer-safe architecture

This spec does not own:
- final packet protocol
- final rollback/prediction details if ever needed
- low-level transport implementation

## Authority model

The intended model is:
- host-authoritative session
- host owns authoritative world state and gameplay mutations
- clients send intents/commands
- clients render presentation and receive authoritative results/state

## Architectural implications now

Even before full co-op implementation, systems should avoid assumptions such as:
- there is only one player actor
- world state may be mutated freely without a command boundary
- local machine state is automatically authoritative
- entity identity can be temporary or unstable

## Replication classes

The architecture should conceptually separate at least these classes:

### Authoritative gameplay state
Examples:
- player positions / core state
- entity life/health state
- placed structures
- inventory ownership
- world diffs
- machine state
- doors / interactables / connectors
- weather class if gameplay-relevant

### Derived reconstructible state
Examples:
- chunk presentation rebuild results
- cached topology products
- recomputable local masks
- deterministic local environment derivatives

### Client-local presentation state
Examples:
- particle placement
- grass sway phase
- exact shadow softness
- local interpolation state
- cosmetic camera presentation

## Command boundary rule

Player actions with gameplay effect should conceptually travel through command boundaries rather than arbitrary local mutation.

Examples:
- place building
- mine tile
- open connector
- interact with machine
- start crafting
- attack/use tool

This does not require fully networked commands immediately.
It does require architecture that can become authoritative later.

## Identity rules

The project must maintain stable identity for:
- players
- chunks / world locations where relevant
- placed entities
- connectors
- machines
- runtime diff entries

Identity must not depend on fragile scene-tree assumptions.

## World and chunk implications

The world model should support the idea that:
- multiple players may be far apart
- relevant world areas may differ by player proximity
- one player's local view must not become the sole truth of what exists

Streaming, loading and update policy must remain compatible with multi-presence.

## Environment implications

The architecture must allow separation between:
- authoritative environment truth
- reconstructible environmental derivatives
- client-local presentation effects

This matters for:
- weather
- lighting
- underground spaces
- environmental visibility

## Save/load relationship

Persistence should store authoritative world and player state, not client-local presentation state.

The save model should remain coherent whether the world was played solo or in host-authoritative co-op.

## Acceptance criteria

This foundation is successful when:
- current systems do not assume one unique local player as the only important actor
- important gameplay mutations can be reasoned about as commands/intents
- state classes are distinguishable as authoritative, reconstructible, or client-local
- future co-op remains feasible without rewriting the whole game from scratch

## Failure signs

This foundation is wrong if:
- gameplay systems directly mutate global truth from arbitrary local code paths
- entity identity is unstable or view-dependent
- presentation state and gameplay authority are inseparable
- streaming assumes one camera/one actor forever

## Open questions

- exact join-in-progress behavior
- exact chunk relevance model in co-op
- exact replication policy for environment and lighting-adjacent gameplay state
- exact future client prediction/interpolation scope
