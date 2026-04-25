---
title: Save and Persistence
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.3
last_updated: 2026-04-24
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
- `world.json` now records `world_version: 11` for the current finite-world
  foundation baseline with `64`-tile substrate cells and the native
  high-resolution overview pass
- `world_version` remains a plain integer algorithm boundary; it is not a hash
  of `worldgen_settings` and does not incorporate `worldgen_signature`
- `world_version >= 6` keeps the same save shape but changes canonical new-world
  mountain identity to implicit-domain hierarchical labeling; save/load still
  regenerates that base data from seed + `world_version` instead of persisting
  `mountain_id_per_tile`
- `world_version >= 9` adds explicit finite-world state:
  - `worldgen_settings.world_bounds.width_tiles`
  - `worldgen_settings.world_bounds.height_tiles`
  - `worldgen_settings.foundation.ocean_band_tiles`
  - `worldgen_settings.foundation.burning_band_tiles`
  - `worldgen_settings.foundation.pole_orientation`
  - `worldgen_settings.foundation.slope_bias`
  - `worldgen_settings.foundation.river_amount`
- `world_version == 9` finite-foundation saves keep the legacy `65536`-tile
  mountain sample-width compatibility path; `world_version >= 10` uses
  `worldgen_settings.world_bounds.width_tiles` for mountain sampling
- `world_version >= 11` uses `foundation_coarse_cell_size_tiles = 64` for
  `WorldPrePass`; versions `9..10` used `128`-tile substrate cells
- loading `world_version <= 8` preserves the legacy pre-foundation path without
  injecting synthetic bounds into the save
- loading `world_version >= 9` without `worldgen_settings.world_bounds` fails
  loudly; missing `worldgen_settings.foundation` restores hard-coded V1 defaults
- `worldgen_settings.mountains` stores the embedded per-save mountain input copy
  with these fields:
  - `density: float` (`0.0..1.0`)
  - `scale: float` (`32.0..2048.0`)
  - `continuity: float` (`0.0..1.0`)
  - `ruggedness: float` (`0.0..1.0`)
  - `anchor_cell_size: int` (`32..512`)
  - `gravity_radius: int` (`32..256`)
  - `foot_band: float` (`0.02..0.3`)
  - `interior_margin: int` (`0..4`)
  - `latitude_influence: float` (`-1.0..1.0`)
- new worlds read defaults from `data/balance/mountain_gen_settings.tres` only
  once during `new game`
- load never re-reads the repository `.tres`; if
  `worldgen_settings.mountains` is missing, the loader injects hard-coded
  defaults in code for backward-compatible restore
- optional `worldgen_signature: String` may be written for diagnostics only; it
  is non-authoritative and load must ignore its absence

Confirmed `world.json` shape in the current mountain code path:

```json
{
  "world_rebuild_frozen": false,
  "world_scene_present": true,
  "world_seed": 131071,
  "world_version": 11,
  "worldgen_settings": {
    "world_bounds": {
      "width_tiles": 4096,
      "height_tiles": 2048
    },
    "foundation": {
      "ocean_band_tiles": 128,
      "burning_band_tiles": 128,
      "pole_orientation": 0,
      "slope_bias": 0.0,
      "river_amount": 0.35
    },
    "mountains": {
      "density": 0.3,
      "scale": 512.0,
      "continuity": 0.65,
      "ruggedness": 0.55,
      "anchor_cell_size": 128,
      "gravity_radius": 96,
      "foot_band": 0.08,
      "interior_margin": 1,
      "latitude_influence": 0.0
    }
  },
  "worldgen_signature": "debug-only"
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
