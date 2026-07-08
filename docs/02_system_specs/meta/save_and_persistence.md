---
title: Save and Persistence
doc_type: system_spec
status: approved
owner: engineering+design
source_of_truth: true
version: 1.9
last_updated: 2026-06-24
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

### Weather slow-state persistence

Weather follows the same diff-not-scene rule (ADR-0007: only slow world state is
saved). See `WeatherSaveData` in `packet_schemas.md`.

- **What persists** (`weather.json`): the active/next regime ids, the transition
  flag + progress, the active regime's remaining duration, the weather-time
  accumulator, and the transition count.
- **What is regenerated**: all live axes (`cloud_cover`, wind strength/heading/
  gustiness targets, reserved precipitation/temperature/humidity) — they
  reconstruct from the restored regime + the world clock via `WeatherRuntime`
  getters; they are never written to the save.
- **Who collects / applies**: `SaveCollectors.collect_weather()` →
  `WeatherRuntime.export_save_dict()`; `SaveAppliers.apply_weather()` →
  `WeatherRuntime.restore_persisted_state()`.
- **Old-save defaults**: a save without `weather.json` (or an empty section)
  leaves `WeatherRuntime` in its boot default (`core:clear`, freshly rolled
  timers); an unknown regime id in the section also falls back to `core:clear`.
  This is an additive section — it does **not** change `world_version` or the
  chunk-diff shape, so old saves stay load-compatible.

Current world generation extension:
- `world.json` now records `world_version: 59` for the current finite-world
  foundation baseline with `64`-tile substrate cells, native high-resolution
  overview, Lake Generation L2 packet output (`TERRAIN_LAKE_BED_SHALLOW`,
  `TERRAIN_LAKE_BED_DEEP`, and `lake_flags`), and the 2026-05-03
  deterministic lake classification / basin-rim correction plus the 2026-05-04
  V2 / L5 basin-size mapping and connectivity merge boundary plus the
  2026-05-04 V2 / L6 cross-cell shoreline boundary plus the 2026-05-04
  V2 / L7 shore-warp normalisation and mandatory connectivity persistence
  boundary plus the 2026-05-04 V3 / L8 threshold-mask and connected-component
  lake substrate boundary plus the 2026-05-05 grid-contract boundary
  (`64 px` tile, `16 x 16` chunk, `256`-entry chunk packet arrays), plus the
  2026-06-03 mountain satellite-outcrop boundary, plus the 2026-06-03
  clustered satellite-outcrop refinement boundary, plus the strengthened
  satellite-outcrop refinement boundary, plus the mountain passage/outcrop
  refinement boundary, plus the native visual object placement boundaries for
  static biofield flora, rare rocky-patch rock formations, rare rocky-patch rock
  pillar presentation, mountain-edge object clearance, rare grass-only big
  rocks, grass-edge small rocks, and the plains tree placement profile boundary
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
- current-version saves also require `worldgen_settings.plains_trees`
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
- `world_version == 43` is the V3 / L8 boundary for
  threshold-mask and connected-component lake substrate output.
  `worldgen_settings.lakes.connectivity` remains mandatory in the save shape
  but is a no-op for canonical lake output.
- `world_version == 44` is the grid-contract boundary for the `64 px` /
  `16 x 16` grid contract. It changes chunk packet length and chunk-diff
  sharding, so previous `32 px` / `32 x 32` pre-alpha saves are rejected before
  chunk diffs are applied.
- `world_version == 45` is the historical first satellite-outcrop
  mountain-generation boundary. It changes canonical mountain output but does
  not change save payload or chunk-diff shape.
- `world_version == 46` is the historical clustered satellite-outcrop
  mountain-generation boundary. It changes canonical mountain output so
  outcrops appear as sparse groups of `2..6` separate `3..10`-tile components,
  but does not change save payload or chunk-diff shape.
- `world_version == 47` is the historical strengthened satellite-outcrop
  mountain-generation boundary. It changes canonical mountain output so
  outcrops appear as larger clusters of `2..20` separate `3..18`-tile
  components, biased toward `10..20` components, but does not change save
  payload or chunk-diff shape.
- `world_version == 48` is the historical mountain passage/outcrop refinement
  boundary. It changes canonical mountain output so outcrop clusters are more
  frequent and spatially varied, and deterministic native carve masks create
  walkable passages, pockets, and gorges inside mountain masses. It does not
  change save payload or chunk-diff shape.
- `world_version == 49` is the historical static biofield flora placement
  boundary. It changes deterministic native visual object placement by allowing
  spiky flora atlas index `1` on the same orange biofield mask used by the
  static spiky flora proof. It does not change save payload or chunk-diff shape.
- `world_version == 50` is the historical rare rocky-patch rock formation
  boundary. It changes deterministic native visual object placement by allowing
  rock atlas index `3` on the same rocky ground patch mask used by presentation.
  It does not change save payload or chunk-diff shape.
- `world_version == 51` is the historical rare rocky-patch rock pillar presentation
  boundary. It keeps the same rock atlas index `3` placement mask, but native
  packets may now choose among eight `45 degree` deterministic atlas variants.
  Presentation scales that atlas taller than the compact byte-packed
  `object_size_px`, keeps collision narrow at the base, and depth-sorts object
  batches against the player reference. It does not change save payload or
  chunk-diff shape.
- `world_version == 52` is the historical mountain-edge object clearance boundary.
  It changes deterministic native visual object placement by suppressing rocks,
  living flora, and spiky flora when their placement center or local clearance
  samples overlap canonical mountain wall/foot terrain. It does not change save
  payload or chunk-diff shape.
- `world_version == 57` is the historical plains grass big rock placement
  boundary. It changes deterministic native visual object placement by allowing
  rare blocking `object_kind == 5` big rocks only on the visual grass field and
  outside the orange biofield mask. It does not change save payload or
  chunk-diff shape.
- `world_version == 58` is the historical plains grass-edge small rock placement
  boundary. It changes deterministic native visual object placement by allowing
  visual-only `object_kind == 6` dense pebble scree on the procedural
  open-ground to grass transition, with runtime contact-shadow presentation
  only. It does not change save payload or chunk-diff shape.
- `world_version == 59` is the historical grass-edge small rock scree tuning
  boundary. It keeps the same `object_kind == 6` packet family but rebalances
  deterministic placement toward sparser clustered seam groups and uses the
  self-shadowed/AO atlas rebake without baked ground projection. It does not
  change save payload or chunk-diff shape.
- `world_version == 60` is the current plains tree placement profile boundary.
  It keeps the same `object_kind == 4` packet family but moves density, scatter
  grid, spacing, size tiers, grass threshold, and mirrored grass-field sampling
  params into `worldgen_settings.plains_trees`. It changes the current
  `world.json` shape, not per-chunk diff shape.
- Current native visual object packet fields for rocks, flora, trees, big
  grass rocks, and grass-edge small rocks are immutable generated presentation
  records plus loaded base-collision proofs where `object_flags` requests them.
  They are regenerated from `world_seed + chunk_coord + world_version` plus the
  frozen `worldgen_settings` profile data. Object records themselves are not
  stored in `world.json` or per-chunk diff files.
- `WorldRuntimeConstants.WORLD_VERSION` is therefore `60` for current saves;
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
- `worldgen_settings.plains_trees` stores the embedded per-save tree placement
  input copy with these fields:
  - `id: String`
  - `object_family: String`
  - `biome_id: String`
  - `placement_mask: String`
  - `density: float` (`0.0..1.0`)
  - `scatter_grid_side: int` (`1..16`)
  - `max_per_chunk: int` (`0..128`; `0` means uncapped beyond the grid)
  - `edge_padding_px: float` (`>= 0.0`)
  - `min_distance_px: float` (`>= 0.0`)
  - `grass_density_min: float` (`0.0..1.0`)
  - `visual_size_min_px: float` (`1.0..254.0`)
  - `visual_size_max_px: float` (`1.0..254.0`)
  - `small_chance: float` (`0.0..1.0`)
  - `small_visual_size_px: float` (`1.0..254.0`)
  - `hero_chance: float` (`0.0..1.0`)
  - `hero_visual_size_px: float` (`1.0..254.0`)
  - `grass_field_scale_px: float` (`>= 1.0`)
  - `grass_coverage: float` (`0.0..1.0`)
  - `rock_field_scale_px: float` (`>= 1.0`)
  - `rock_coverage: float` (`0.0..1.0`)
  - `macro_mass_scale_px: float` (`>= 1.0`)
  - `macro_mass_strength: float` (`0.0..1.0`)
  - `path_scale_px: float` (`>= 1.0`)
  - `path_width: float` (`0.0..1.0`)
  - `path_warp_px: float` (`>= 0.0`)
  - `path_strength: float` (`0.0..1.0`)
- new worlds read defaults from `data/balance/mountain_gen_settings.tres` and
  `data/world_objects/placement_groups/plains_trees.tres` only once during
  `new game`
- load never re-reads the repository `.tres`; if
  `worldgen_settings.mountains`, `worldgen_settings.lakes`, or
  `worldgen_settings.plains_trees` is missing from a current-version save, load
  fails instead of injecting compatibility defaults
- optional `worldgen_signature: String` may be written for diagnostics only; it
  is non-authoritative and load must ignore its absence

Confirmed `world.json` shape in the current worldgen code path:

```json
{
  "world_rebuild_frozen": false,
  "world_scene_present": true,
  "world_seed": 131071,
  "world_version": 60,
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
    },
    "plains_trees": {
      "id": "core:plains_trees",
      "object_family": "tree",
      "biome_id": "core:plains",
      "placement_mask": "grass_field",
      "density": 0.62,
      "scatter_grid_side": 6,
      "max_per_chunk": 0,
      "edge_padding_px": 40.0,
      "min_distance_px": 88.0,
      "grass_density_min": 0.40,
      "visual_size_min_px": 150.0,
      "visual_size_max_px": 244.0,
      "small_chance": 0.20,
      "small_visual_size_px": 120.0,
      "hero_chance": 0.10,
      "hero_visual_size_px": 252.0,
      "grass_field_scale_px": 720.0,
      "grass_coverage": 0.80,
      "rock_field_scale_px": 1200.0,
      "rock_coverage": 0.22,
      "macro_mass_scale_px": 7000.0,
      "macro_mass_strength": 0.34,
      "path_scale_px": 2600.0,
      "path_width": 0.06,
      "path_warp_px": 700.0,
      "path_strength": 0.85
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
