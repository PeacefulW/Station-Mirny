---
title: Building and Rooms
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - engineering_networks.md
  - ../world/transport_and_outposts.md
---

# Building and Rooms

This document defines the construction grammar of the player's base.

## Purpose

Building should create a compact, functional, defensible habitat rather than a decorative sandbox alone.

## Core statement

Construction is tile-based, room-based and systems-aware.

The player is not drawing abstract zones. The player is assembling a living machine:
- walls
- doors
- floors
- roofed spaces
- engineered rooms
- outposts

## Scope

This spec owns:
- tile-based placement foundations
- room closure and hermeticity intent
- room scale and role expectations
- outpost concept
- building-side dependency on engineering overlays

## Building grammar

### Placement model

Construction is grid-based in the RimWorld tradition:
- walls
- doors
- floors
- furniture
- modules

### Vertical intent

The long-term design allows:
- limited upward construction for towers / observation / antennas
- several downward bunker levels
- separate precursor underground complexes that are not player-built floors

## Hermetic rooms

### Rule

Closed walls plus roof create a sealed space.

### Consequences

- a sealed room can support controlled atmosphere
- any breach causes decompression / contamination risk
- entry should normally pass through an airlock logic

## Base scale target

The endgame fantasy is not a megacity.

The target is a compact bunker-like base of roughly 10-15 meaningful rooms, for example:
- airlock
- living quarters
- workshop
- compressor room
- water treatment
- server / decryption room
- greenhouse
- laboratory
- storage
- arsenal
- medbay

Branch-specific rooms may extend this:
- adaptation biolab / incubator
- terraformer heavy workshop / generator hall

## Outposts

Outposts exist to support remote extraction and logistics.

Expected qualities:
- smaller than the main base
- reduced comfort and reduced resilience
- enough infrastructure for shelter and resource export
- connected to the main base through logistics

## Dependencies

- engineering networks define whether a room is actually livable
- transport/logistics define whether outposts are worth maintaining
- defense systems define how a base survives pressure

## Runtime expectations

- placing one structure must update only local dirty regions
- room recalculation must be incremental
- large-scale room rebuild is not allowed in interactive path

## Acceptance criteria

- the player understands what counts as a room
- a compact, efficient bunker is viable and desirable
- outposts feel like infrastructure, not cosmetic duplicates
- airlock logic supports the fantasy of crossing between safe and hostile worlds

## Failure signs

- building becomes visually freeform but mechanically unreadable
- room logic feels arbitrary
- too many enormous empty halls are optimal
- outposts feel pointless compared to one central megabase
