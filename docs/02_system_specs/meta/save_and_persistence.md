---
title: Save and Persistence
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.7
last_updated: 2026-05-04
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

Current world generation extension:
- `world.json` now records `world_version: 43` for the current finite-world
  foundation baseline with `64`-tile substrate cells, native high-resolution
  overview, Lake Generation L2 packet output (`TERRAIN_LAKE_BED_SHALLOW`,
  `TERRAIN_LAKE_BED_DEEP`, and `lake_flags`), and the 2026-05-03
  deterministic lake classification / basin-rim correction plus the 2026-05-04
  V2 / L5 basin-size mapping and connectivity merge boundary plus the
  2026-05-04 V2 / L6 cross-cell shoreline boundary plus the 2026-05-04
  V2 / L7 shore-warp normalisation and mandatory connectivity persistence
  boundary plus the 2026-05-04 V3 / L8 threshold-mask and connected-component
  lake substrate boundary
- `world_version` remains a plain integer algorithm boundary; it is not a hash
  of `worldgen_settings` and does not incorporate `worldgen_signature`
- pre-alpha save compatibility policy: the active load path accepts only
  saves whose `world_version` equals `WorldRuntimeConstants.WORLD_VERSION`
  exactly; missing, older, or newer values are incompatible and must fail
  before chunk diffs, buildings, player state, or time state are applied
- current-version `world.json` must include the current worldgen settings shape:
  - `worldgen_settings.world_bounds.width_tiles`
  - `worldgen_settings.world_bounds.height_tiles`
  - `worldgen_settings.foundation.ocean_band_tiles`
  - `worldgen_settings.foundation.burning_band_tiles`
  - `worldgen_settings.foundation.pole_orientation`
  - `worldgen_settings.foundation.slope_bias`
- current-version saves also require `worldgen_settings.mountains`
- current-version saves also require `worldgen_settings.lakes`
- `world_version == 37` remains a historical boundary for the finite-world
  foundation baseline before Lake Generation L2 packet output.
- `world_version == 38` adds lake bed terrain ids and the additive
  `lake_flags` chunk packet field. Save shape remains unchanged in L2:
  `lake_flags` is derived base packet data and is not persisted in
  `chunks/*.json`.
- `world_version == 39` is the historical boundary for the corrected lake
  classifier and dynamic basin-rim solve.
- `world_version == 40` is the V2 / L5 boundary for basin-size
  mapping and deterministic basin merging by `worldgen_settings.lakes.connectivity`.
  Save shape is otherwise unchanged, and `connectivity` is optional in L5 loads
  because missing saves read the `LakeGenSettings` default `0.4`; L7 owns the
  final mandatory persistence/UI wiring.
- `world_version == 41` is the V2 / L6 boundary for cross-cell
  shoreline classification and spawn rejection. Save shape is otherwise
  unchanged.
- `world_version == 42` is the V2 / L7 boundary for shore-warp
  normalisation and final V2 lake persistence. Save shape now requires
  `worldgen_settings.lakes.connectivity` instead of treating it as optional.
- `world_version == 43` is the current active boundary for V3 / L8
  threshold-mask and connected-component lake substrate output.
  `worldgen_settings.lakes.connectivity` remains mandatory in the save shape
  but is a no-op for canonical lake output.
- `WorldRuntimeConstants.WORLD_VERSION` is therefore `43` for current saves;
  `38` remains the historical L2 packet boundary and `42` remains the
  historical L7 shore-warp boundary.
- `worldgen_settings.lakes` stores the embedded per-save lake input copy
  with these fields:
  - `density: float` (`0.0..1.0`)
  - `scale: float` (`64.0..2048.0`)
  - `shore_warp_amplitude: float` (`0.0..1.0`)
  - `shore_warp_scale: float` (`8.0..64.0`)
  - `deep_threshold: float` (`0.05..0.5`)
  - `mountain_clearance: float` (`0.0..0.5`)
  - `connectivity: float` (`0.0..1.0`, mandatory in current-version saves;
    canonical no-op for `world_version >= 43`)
- loading a same-version save without required current worldgen settings fails
  loudly; the active pre-alpha loader does not inject compatibility defaults
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
  `worldgen_settings.mountains` or `worldgen_settings.lakes` is missing from a
  current-version save, load fails instead of injecting compatibility defaults
- optional `worldgen_signature: String` may be written for diagnostics only; it
  is non-authoritative and load must ignore its absence

Confirmed `world.json` shape in the current mountain code path:

```json
{
  "world_rebuild_frozen": false,
  "world_scene_present": true,
  "world_seed": 131071,
  "world_version": 43,
  "worldgen_settings": {
    "world_bounds": {
      "width_tiles": 4096,
      "height_tiles": 2048
    },
    "foundation": {
      "ocean_band_tiles": 128,
      "burning_band_tiles": 128,
      "pole_orientation": 0,
      "slope_bias": 0.0
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
    },
    "lakes": {
      "density": 0.35,
      "scale": 512.0,
      "shore_warp_amplitude": 0.4,
      "shore_warp_scale": 16.0,
      "deep_threshold": 0.18,
      "mountain_clearance": 0.10,
      "connectivity": 0.4
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
- current-version player/base/progression state survives save/load
- non-current `world_version` saves are rejected before runtime diffs or other
  gameplay state are applied

## Failure signs

- save size scales with total explored world rather than changed state
- unchanged chunks are stored redundantly
- persistence rules differ arbitrarily by subsystem
- load silently accepts a missing or non-current `world_version`
