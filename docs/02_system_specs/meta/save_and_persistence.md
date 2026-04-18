---
title: Save and Persistence
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - multiplayer_and_modding.md
  - ../../05_adrs/0003-immutable-base-plus-runtime-diff.md
---

# Save and Persistence

## Purpose

Persistence must preserve a large procedural world without serializing everything naively.

## Core statement

The save model is:
- deterministic base world from seed
- persisted runtime diffs for changed state
- structured player/base/progression/event state

## Scope

This spec owns:
- save decomposition
- relationship between seed and world diffs
- persistence expectations for player, base, progression and events

## Save structure direction

The intended save layout is conceptually:
- meta
- player state
- base state
- world seed / generation parameters
- changed chunks only
- tech/decryption state
- event state
- lore discovery state

## World persistence rule

The world should not serialize every untouched chunk.

Instead:
- base terrain generation remains deterministic from seed
- only modified chunk state is persisted as runtime diff

## Dependencies

- world generation foundation
- building and rooms
- engineering networks
- progression systems
- events

## Acceptance criteria

- large worlds remain saveable without full-world dumps
- modified chunks reload exactly as changed
- player/base/progression state survives versioned migration safely

## Failure signs

- save size scales with total explored world rather than changed state
- unchanged chunks are stored redundantly
- persistence rules differ arbitrarily by subsystem
