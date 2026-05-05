---
title: Packet Schemas
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 1.1
last_updated: 2026-05-05
related_docs:
  - ../README.md
  - system_api.md
  - commands.md
  - save_and_persistence.md
---

# Packet Schemas

## Purpose

This document records the current data shapes that are confirmed at code
boundaries.

## Scope

This pass covers only shapes confirmed in current code:

- save-slot file layout
- save payload dictionaries
- command result dictionaries
- runtime native packet/result dictionaries

## Out of Scope

- future network packet design
- future native chunk packets
- shapes that are only implied by comments

## Save Slot Layout

Current code writes one directory per slot under `user://saves/<slot_name>/`.

Confirmed files:

| File | Writer | Reader / applier | Current shape owner |
|---|---|---|---|
| `meta.json` | `SaveCollectors.collect_meta()` | `SaveManager.get_save_list()` | `SaveCollectors` |
| `player.json` | `SaveCollectors.collect_player()` | `SaveAppliers.apply_player()` | `SaveCollectors` + component `save_state()` methods |
| `world.json` | `SaveCollectors.collect_world()` | `SaveAppliers.apply_world()` | `SaveCollectors` |
| `time.json` | `SaveCollectors.collect_time()` | `SaveAppliers.apply_time()` | `TimeManager` |
| `buildings.json` | `SaveCollectors.collect_buildings()` | `SaveAppliers.apply_buildings()` | `BuildingPersistence` |
| `chunks/<x>_<y>.json` | `SaveCollectors.collect_chunk_data()` via `SaveManager._write_chunk_data()` | `SaveManager._read_chunk_data()` -> `SaveAppliers.apply_chunk_data()` | `WorldDiffStore` |

## Confirmed Save Payload Shapes

### `SaveMeta`

```text
{
  "save_version": int,
  "save_format_version": int,
  "save_time": String,
  "world_seed": int,
  "game_day": int,
}
```

Current code notes:
- `save_format_version` is currently hardcoded to `4`
- `world_seed` is collected from the active `chunk_manager` when present

### `SaveListEntry`

Returned by `SaveManager.get_save_list()`.

```text
{
  ...SaveMeta,
  "slot_name": String,
  "date": String,     # alias backfilled from save_time when needed
  "day": int,         # alias backfilled from game_day when needed
}
```

Current code note:
- `get_save_list()` also backfills the reverse aliases if older metadata uses
  `date` / `day`

### `PlayerSaveData`

```text
{
  "position": {
    "x": float,
    "y": float,
  },
  "z_level"?: int,
  "health"?: {
    "current": float,
    "max": float,
  },
  "inventory"?: InventoryState,
  "equipment"?: EquipmentState,
  "oxygen"?: OxygenState,
}
```

Presence rules confirmed in code:
- `position` is written when a player node is found
- `z_level` is written only if a `ZLevelManager` with `get_current_z()` exists
- `health`, `inventory`, `equipment`, and `oxygen` are written only if the
  corresponding component exists and exposes `save_state()`

### `InventoryState`

```text
{
  "capacity": int,
  "slots": Array[
    {} |
    {
      "item_id": String,
      "amount": int,
    }
  ],
}
```

### `EquipmentState`

Saved by `EquipmentComponent.save_state()`.

```text
{
  <slot_id>: item_id,
  ...
}
```

Current code note:
- `load_state()` accepts keys convertible to `int`

### `OxygenState`

```text
{
  "current_oxygen": float,
  "is_indoor": bool,
  "is_base_powered": bool,
}
```

### `WorldSaveData`

```text
{
  "world_rebuild_frozen": bool,
  "world_scene_present": bool,
  "world_seed"?: int,
  "world_version"?: int,
  "worldgen_settings"?: {
    "world_bounds"?: {
      "width_tiles": int,
      "height_tiles": int,
    },
    "foundation"?: {
      "ocean_band_tiles": int,
      "burning_band_tiles": int,
      "pole_orientation": int,
      "slope_bias": float,
    },
    "mountains"?: {
      "density": float,
      "scale": float,
      "continuity": float,
      "ruggedness": float,
      "anchor_cell_size": int,
      "gravity_radius": int,
      "foot_band": float,
      "interior_margin": int,
      "latitude_influence": float,
    },
    "lakes"?: {
      "density": float,
      "scale": float,
      "shore_warp_amplitude": float,
      "shore_warp_scale": float,
      "deep_threshold": float,
      "mountain_clearance": float,
      "connectivity": float,
    },
  },
  "worldgen_signature"?: String,
}
```

Current code notes:
- `world_seed` and `world_version` are present when a `chunk_manager` world runtime is active
- active pre-alpha load accepts only saves whose `world_version` equals the
  current `WorldRuntimeConstants.WORLD_VERSION`; missing, older, or newer
  values are incompatible
- current-version `WorldStreamer` loads require `world_seed`,
  `worldgen_settings.mountains`, `worldgen_settings.world_bounds`, and
  `worldgen_settings.foundation`, and `worldgen_settings.lakes`; missing
  fields fail the world apply step before chunk diffs or player/base state are
  applied
- `world_version == 38` is the Lake Generation L2 historical boundary: base
  terrain is regenerated from seed/version/settings, lake bed terrain ids are
  canonical packet output, and `lake_flags` is derived packet data rather than
  save data.
- `world_version == 39` is the lake-generation correction boundary:
  per-tile lake classification samples bilinear `foundation_height` in the
  same units as `lake_water_level_q16`, and basin BFS uses a dynamic observed
  rim rather than a fixed `center_height + fill_depth` ceiling.
- `world_version == 40` is the V2 / L5 lake-generation algorithm
  boundary: `settings_packed[21]` carries `LakeGenSettings.connectivity`, basin
  size mapping allows larger basins, and the native substrate merge pass can
  fuse adjacent similar-rim basins into one `lake_id`. `ChunkPacketV1` shape is
  unchanged.
- `world_version == 41` is the V2 / L6 lake-generation algorithm
  boundary: per-tile lake classification and spawn rejection read the
  `3×3 neighbourhood` of coarse lake cells before applying the existing
  effective-elevation water test. `ChunkPacketV1` shape is unchanged.
- `world_version == 42` is the V2 / L7 lake-generation algorithm
  boundary: `shore_warp_amplitude` is applied as a fraction of chosen basin
  depth, and `worldgen_settings.lakes.connectivity` is mandatory in
  current-version saves. `ChunkPacketV1` shape is unchanged.
- `world_version == 43` is the V3 / L8 lake-generation algorithm
  boundary: lake substrate fields are produced by an elevation-threshold mask
  plus face-connected-component labeling; `LakeGenSettings.connectivity`
  remains in `settings_packed[21]` but is a no-op for canonical output.
  `ChunkPacketV1` shape is unchanged.
- `world_version == 44` is the current grid-contract boundary: one world tile
  is `64 px`, one chunk is `16 x 16` tiles, and chunk packet arrays contain
  `256` entries. This changes chunk coordinate sharding and therefore rejects
  previous `32 px` / `32 x 32` pre-alpha saves before chunk diffs are applied.
- `worldgen_settings.mountains` is written once for new worlds and then loaded
  from `world.json`, not from the repository `.tres`
- `worldgen_settings.lakes` is written once for new worlds and then loaded
  from `world.json`, not from the repository `.tres`
- `worldgen_signature` is diagnostic only and is never authoritative on load
- legacy/frozen-world payloads with only the older boolean fields are not
  load-compatible with the active `WorldStreamer` runtime

### `ChunkDiffFile`

One JSON file per dirty chunk under `user://saves/<slot>/chunks/`.

```text
{
  "chunk_coord": {
    "x": int,
    "y": int,
  },
  "tiles": Array[ChunkDiffTile],
}
```

### `ChunkDiffTile`

```text
{
  "local_x": int,
  "local_y": int,
  "terrain_id": int,
  "walkable": bool,
}
```

Current code note:
- `ChunkDiffTile` intentionally does not persist any presentation-only atlas or
  autotile metadata; runtime derives those values from `base + diff`

### `TimeSaveData`

```text
{
  "current_hour": float,
  "current_day": int,
  "current_season": int,
}
```

### `BuildingsSaveData`

```text
{
  "walls": Array[BuildingEntry],
}
```

### `BuildingEntry`

```text
{
  "x": int,
  "y": int,
  "building_id": String,
  "health"?: float,
  "state"?: Dictionary,
}
```

Current code notes:
- multi-tile buildings are serialized once per node, keyed by `grid_origin`
- if `building_id` is unknown on load, `BuildingPersistence` falls back to
  `"wall"`

### Confirmed `BuildingEntry.state` Variants

`ThermoBurner.save_state()`:

```text
{
  "type": "thermo_burner",
  "grid_x": int,
  "grid_y": int,
  "fuel": float,
  "running": bool,
}
```

`ArkBattery.save_state()`:

```text
{
  "type": "ark_battery",
  "grid_x": int,
  "grid_y": int,
  "charge": float,
  "depleted": bool,
}
```

## Confirmed Command Result Shapes

### `CommandResultBase`

`GameCommand.execute()` establishes the base contract, and
`CommandExecutor.execute()` normalizes missing keys.

```text
{
  "success": bool,
  "message_key": String,
  "message_args": Dictionary,
  ...command-specific keys
}
```

Normalization confirmed in code:
- `success` is backfilled with `false`
- `message_key` is backfilled with `""`
- `message_args` is backfilled with `{}`

### `PlaceBuildingResult`

Success shape:

```text
{
  "success": true,
  "message_key": "SYSTEM_BUILD_PLACED",
  "message_args": {
    "building": String,
  },
  "grid_pos": Vector2i,
  "building_id": String,
}
```

Failure shape:

```text
{
  "success": false,
  "message_key": String,
}
```

### `RemoveBuildingResult`

Success shape:

```text
{
  "success": true,
  "message_key": "SYSTEM_BUILD_REMOVED",
  "message_args": {
    "amount": int,
  },
  "grid_pos": Vector2i,
  "refund_amount": int,
}
```

Failure shape:

```text
{
  "success": false,
  "message_key": String,
}
```

### `PickupItemResult`

Success shape:

```text
{
  "success": true,
  "message_key": "SYSTEM_ITEM_PICKED_UP",
  "message_args": {
    "amount": int,
  },
  "collected_amount": int,
}
```

Failure shape:

```text
{
  "success": false,
  "message_key": String,
}
```

### `CraftRecipeResult`

Success shape:

```text
{
  "success": true,
  "message_key": "SYSTEM_CRAFT_SUCCESS",
  "message_args": {
    "item": String,
    "amount": int,
  },
}
```

Failure shape:

```text
{
  "success": false,
  "message_key": String,
}
```

## Confirmed Runtime Packet Shapes

### `ChunkPacketV0`

Historical base packet shape. In the current runtime, these fields are the
subset carried by each element of `WorldCore.generate_chunk_packets_batch(...)`.

```text
{
  "chunk_coord": Vector2i,
  "world_seed": int,
  "world_version": int,
  "terrain_ids": PackedInt32Array,           # length 256
  "terrain_atlas_indices": PackedInt32Array, # length 256
  "walkable_flags": PackedByteArray,         # length 256
}
```

Current code notes:
- V0 intentionally omits climate bytes, placements, and decor
- `terrain_atlas_indices` is derived presentation metadata consumed by `ChunkView`
- runtime mutations are not written back into `ChunkPacketV0`; they are persisted separately as `ChunkDiffFile`
- `terrain_atlas_indices` is not part of `ChunkDiffFile` and is recomputed from
  `base + diff` for loaded visual patches
- `WorldChunkPacketBackend` may add `request_chunk_coord` to drained worker
  results as preview-only request identity; native `chunk_coord` remains the
  canonical chunk coordinate

### `ChunkPacketV1`

Returned one-per-input-coord by native
`WorldCore.generate_chunk_packets_batch(seed, coords, world_version, settings_packed)`.

`ChunkPacketV1` extends `ChunkPacketV0` additively. Current confirmed shape:

| Field | Type | Length | Notes |
|---|---|---|---|
| `chunk_coord` | `Vector2i` | — | Canonical chunk coordinate |
| `world_seed` | `int` | — | Copied into the packet for validation/debug |
| `world_version` | `int` | — | Current foundation runtime value is `44` |
| `terrain_ids` | `PackedInt32Array` | 256 | Base terrain ids for the gameplay layer |
| `terrain_atlas_indices` | `PackedInt32Array` | 256 | Base-layer atlas indices; mountain tiles reuse the native mountain atlas solve, and plains ground opens `autotile_47` bank edges only against shallow/deep lake-bed neighbours |
| `walkable_flags` | `PackedByteArray` | 256 | `1 = walkable`, `0 = blocked` |
| `lake_flags` | `PackedByteArray` | 256 | Per-tile lake bit field; bit `0` is `is_water_present` |
| `mountain_id_per_tile` | `PackedInt32Array` | 256 | `0 = no named mountain`; non-zero = deterministic `mountain_id` |
| `mountain_flags` | `PackedByteArray` | 256 | Per-tile mountain bit layout documented below |
| `mountain_atlas_indices` | `PackedInt32Array` | 256 | Roof-ready atlas indices derived from `mountain_id` adjacency via `autotile_47` |

`mountain_flags` bit layout:

| Bit | Name | Meaning |
|---|---|---|
| `1 << 0` | `is_interior` | Interior wall depth satisfies `interior_margin`; used later by M2 roof presentation |
| `1 << 1` | `is_wall` | `elevation >= t_wall` |
| `1 << 2` | `is_foot` | `t_edge <= elevation < t_wall` |
| `1 << 3` | `is_anchor` | Tile is the deterministic representative tile for its `mountain_id` |

For tiles with `mountain_id == 0`, current native contract is `mountain_flags = 0`
and `mountain_atlas_indices = 0`.

`lake_flags` bit layout:

| Bit | Name | Meaning |
|---|---|---|
| `1 << 0` | `is_water_present` | Water surface is present over this generated lake-bed tile. Set only when `terrain_ids[index]` is `TERRAIN_LAKE_BED_SHALLOW` or `TERRAIN_LAKE_BED_DEEP`; always `0` on mountain, plains, and shore-land tiles. |
| `1 << 1..7` | reserved | Must remain `0` in the current L2 packet. |

Current code notes:
- `ChunkPacketV1` keeps one hot-path packet per chunk; batch generation returns one packet per requested coord
- the current native boundary requires the full `settings_packed` payload:
  indices `0-8` are mountain settings, and for `world_version >= 9` indices
  `9-14` are `world_width_tiles`, `world_height_tiles`, `ocean_band_tiles`,
  `burning_band_tiles`, `pole_orientation`, and `foundation_slope_bias`;
  Lake Generation L1 extends the same payload additively with
  `LakeGenSettings` indices `15-20`; V2 / L5 adds
  `SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY = 21`, so the current field count
  is `22`
- the current native boundary requires `world_version >= 6`
- `world_version >= 6` uses implicit-domain hierarchical labeling: aligned `1024 x 1024` macro solves recurse only through mixed cells, stop at versioned `min_label_cell_size = 8`, reuse a deterministic `1`-macro halo in native code, and hash `mountain_id` from the component representative leaf
- `mountain_id_per_tile`, `mountain_flags`, and `mountain_atlas_indices` are base packet fields only; they are not persisted in `ChunkDiffFile`
- only tiles with `mountain_id > 0` write canonical mountain terrain through `terrain_ids` as `TERRAIN_MOUNTAIN_WALL` or `TERRAIN_MOUNTAIN_FOOT`
- Lake Generation L2 adds `TERRAIN_LAKE_BED_SHALLOW = 5`,
  `TERRAIN_LAKE_BED_DEEP = 6`, and `lake_flags` to `ChunkPacketV1`
  at the `WORLD_VERSION = 38` boundary. Shallow lake bed is walkable (`1`); deep lake
  bed is blocked (`0`). Mountain terrain wins before lake classification.
- Lake Generation L6 keeps the `ChunkPacketV1` field shape unchanged but
  changes canonical lake-bed contents at the `WORLD_VERSION = 41` boundary:
  eligible plains tiles choose a lake from the `3×3 neighbourhood` of coarse
  substrate cells before `lake_flags` is set.
- Lake Generation L7 keeps the `ChunkPacketV1` field shape unchanged but
  changes canonical lake-bed contents at the `WORLD_VERSION = 42` boundary:
  shoreline FBM is applied as a fraction of the chosen basin depth before
  `lake_flags` is set.
- Lake Generation L8 keeps the `ChunkPacketV1` field shape unchanged but
  changes canonical lake substrate and bed contents at the `WORLD_VERSION = 43`
  boundary: lake identity comes from an elevation-threshold mask plus
  face-connected components, and `connectivity` no longer affects canonical
  output.
- `lake_flags` is base packet output only; it is not persisted in
  `ChunkDiffFile` and must not be written into chunk diff JSON.
- active packet output never uses a standalone plains-rock terrain class; elevated mountain terrain either resolves into named mountain output or stays on the ground path at the hierarchical scale cutoff
- `mountain_atlas_indices` is reserved for later roof presentation, but is already confirmed at the packet boundary in M1

### `WorldFoundationSpawnResult`

Returned by native
`WorldCore.resolve_world_foundation_spawn_tile(seed, world_version, settings_packed)`
and drained by `WorldChunkPacketBackend.drain_completed_spawn_results(...)`.

Success shape:

```text
{
  "success": true,
  "spawn_tile": Vector2i,
  "spawn_safe_patch_rect": Rect2i,
  "node_coord": Vector2i,
  "score": float,
  "coarse_valley_score": float,
  "foundation_height": float,
  "coarse_wall_density": float,
  "grid_width": int,
  "grid_height": int,
  "coarse_cell_size_tiles": int,
  "compute_time_ms": float,
  "epoch"?: int, # added by the worker wrapper, not by native code
}
```

Failure shape:

```text
{
  "success": false,
  "message": String,
  "epoch"?: int,
}
```

Current code notes:
- success candidates reject ocean band, burning band, reserved non-land mask,
  high wall density, and L6 lake candidates whose `3×3 neighbourhood` lookup
  yields water at the candidate tile's effective elevation
- the result is transient worker output, not save data

### `WorldFoundationSnapshotDebug`

Returned by dev-only native
`WorldCore.get_world_foundation_snapshot(layer_mask, downscale_factor)` after a
matching substrate has been built.

```text
{
  "grid_width": int,
  "grid_height": int,
  "coarse_cell_size_tiles": int,
  "world_width_tiles": int,
  "world_height_tiles": int,
  "ocean_band_tiles": int,
  "burning_band_tiles": int,
  "seed": int,
  "world_version": int,
  "signature": int,
  "compute_time_ms": float,
  "cycle_free": bool,
  "layer_mask": int,
  "downscale_factor": int,
  "latitude_t": PackedFloat32Array,
  "ocean_band_mask": PackedByteArray,
  "burning_band_mask": PackedByteArray,
  "continent_mask": PackedByteArray,
  "foundation_height": PackedFloat32Array,
  "coarse_wall_density": PackedFloat32Array,
  "coarse_foot_density": PackedFloat32Array,
  "coarse_valley_score": PackedFloat32Array,
  "biome_region_id": PackedInt32Array,
  "lake_id": PackedInt32Array,
  "lake_water_level_q16": PackedInt32Array,
}
```

Current code notes:
- every array is indexed by coarse node index `y * grid_width + x`
- `lake_id` and `lake_water_level_q16` are Lake Generation L1 substrate fields;
  they are debug/dev arrays only in L1 and are not part of `ChunkPacketV1`
- this dictionary is debug/dev tooling only and must not be persisted

### `WorldFoundationOverviewImage`

Returned by dev-only native
`WorldCore.get_world_foundation_overview(layer_mask, pixels_per_cell)` after a
matching substrate has been built.

```text
Image {
  width: grid_width * pixels_per_cell,
  height: grid_height * pixels_per_cell,
  format: FORMAT_RGBA8,
}
```

Current code notes:
- `layer_mask = 0` returns the default terrain overview. The foundation-height layer
  mask returns a diagnostic height-map image from the raw `foundation_height`
  substrate channel; it is presentation/debug output and is not save data.
- `pixels_per_cell` is clamped to `>= 1` on the native side
- the default new-game overview requests `pixels_per_cell = 4`, which maps the
  current `64`-tile substrate grid to roughly one image pixel per `16 x 16`
  world tiles
- the default native pass renders currently realised gameplay terrain
  classes: ground, mountain foot, mountain wall, shallow lake bed, and deep
  lake bed
- mountain pixels sample the mountain field at overview-pixel resolution and
  apply the same hierarchical `mountain_id` cutoff used by `ChunkPacketV1`;
  `foundation_height` is used only as subtle neutral-ground shading in the default
  terrain overview
- ocean/burning bands and reserved non-land masks are not
  player-facing overview colours until matching terrain exists
- this image is presentation-only and must not be persisted

## Not Currently Confirmed

The current code still does not confirm packet fields for future biome,
placement, roof-runtime, entrance-runtime, drought, or
environment layers.
