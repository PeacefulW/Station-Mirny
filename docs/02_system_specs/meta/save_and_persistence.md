---
title: Save and Persistence
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.2
last_updated: 2026-04-21
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
- world seed / `world_version`
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

Current V0 runtime implementation:
- `world.json` stores `world_seed` and `world_version` alongside the existing world flags
- changed terrain diffs are sharded as `chunks/<x>_<y>.json`
- load order is deterministic base restore first, then per-chunk diff apply

Current mountain extension:
- `world.json` now records `world_version: 5` for the current native mountain-field baseline
- `worldgen_settings.mountains` persistence is still deferred to Mountain Generation M4; M1 keeps hard-coded dev defaults in `WorldStreamer`
- legacy saves with `world_version < 2` keep `settings_packed = []`, so they
  stay on the V0 no-mountains path during load

Confirmed `world.json` shape in the current mountain code path:

```json
{
  "world_rebuild_frozen": false,
  "world_scene_present": true,
  "world_seed": 131071,
  "world_version": 5
}
```

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
