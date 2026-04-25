---
title: Packet Schemas
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.7
last_updated: 2026-04-24
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
- `world_seed` is currently hardcoded to `0`

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
      "river_amount": float,
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
  },
  "worldgen_signature"?: String,
}
```

Current code notes:
- `world_seed` and `world_version` are present when a `chunk_manager` world runtime is active
- `world_version >= 9` writes `worldgen_settings.world_bounds` and
  `worldgen_settings.foundation`; loading version `>= 9` without
  `world_bounds` fails loudly, while missing `foundation` restores V1 defaults
- `world_version >= 10` uses `worldgen_settings.world_bounds.width_tiles` as
  the native mountain sample width; version `9` keeps the legacy `65536`-tile
  mountain sample-width compatibility path
- `world_version >= 11` uses `foundation_coarse_cell_size_tiles = 64` for
  `WorldPrePass`; versions `9..10` used `128`-tile substrate cells
- `world_version >= 14` adds native dry riverbed/lakebed realization to chunk
  packets. Riverbed/lakebed packet arrays are regenerated from seed/settings and
  are never written to save files.
- `worldgen_settings.mountains` is written once for new worlds and then loaded
  from `world.json`, not from the repository `.tres`
- missing `worldgen_settings.mountains` restores hard-coded loader defaults for
  backward-compatible saves
- `worldgen_signature` is diagnostic only and is never authoritative on load
- legacy/frozen-world callers may still emit only the older boolean fields

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
  "terrain_ids": PackedInt32Array,           # length 1024
  "terrain_atlas_indices": PackedInt32Array, # length 1024
  "walkable_flags": PackedByteArray,         # length 1024
}
```

Current code notes:
- V0 intentionally omits climate bytes, river data, placements, and decor
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
| `world_version` | `int` | — | Current foundation runtime value before river realization was `11` |
| `terrain_ids` | `PackedInt32Array` | 1024 | Base terrain ids for the gameplay layer |
| `terrain_atlas_indices` | `PackedInt32Array` | 1024 | Base-layer atlas indices; mountain tiles reuse the native mountain atlas solve |
| `walkable_flags` | `PackedByteArray` | 1024 | `1 = walkable`, `0 = blocked` |
| `mountain_id_per_tile` | `PackedInt32Array` | 1024 | `0 = no named mountain`; non-zero = deterministic `mountain_id` |
| `mountain_flags` | `PackedByteArray` | 1024 | Per-tile mountain bit layout documented below |
| `mountain_atlas_indices` | `PackedInt32Array` | 1024 | Roof-ready atlas indices derived from `mountain_id` adjacency via `autotile_47` |

`mountain_flags` bit layout:

| Bit | Name | Meaning |
|---|---|---|
| `1 << 0` | `is_interior` | Interior wall depth satisfies `interior_margin`; used later by M2 roof presentation |
| `1 << 1` | `is_wall` | `elevation >= t_wall` |
| `1 << 2` | `is_foot` | `t_edge <= elevation < t_wall` |
| `1 << 3` | `is_anchor` | Tile is the deterministic representative tile for its `mountain_id` |

For tiles with `mountain_id == 0`, current native contract is `mountain_flags = 0`
and `mountain_atlas_indices = 0`.

Current code notes:
- `ChunkPacketV1` keeps one hot-path packet per chunk; batch generation returns one packet per requested coord
- the current native boundary requires the full `settings_packed` payload:
  indices `0-8` are mountain settings, and for `world_version >= 9` indices
  `9-15` are `world_width_tiles`, `world_height_tiles`, `ocean_band_tiles`,
  `burning_band_tiles`, `pole_orientation`, `foundation_slope_bias`, and
  `river_amount`
- the current native boundary requires `world_version >= 6`
- `world_version >= 6` uses implicit-domain hierarchical labeling: aligned `1024 x 1024` macro solves recurse only through mixed cells, stop at versioned `min_label_cell_size = 8`, reuse a deterministic `1`-macro halo in native code, and hash `mountain_id` from the component representative leaf
- `mountain_id_per_tile`, `mountain_flags`, and `mountain_atlas_indices` are base packet fields only; they are not persisted in `ChunkDiffFile`
- only tiles with `mountain_id > 0` write canonical mountain terrain through `terrain_ids` as `TERRAIN_MOUNTAIN_WALL` or `TERRAIN_MOUNTAIN_FOOT`
- active packet output never uses a standalone plains-rock terrain class; elevated mountain terrain either resolves into named mountain output or stays on the ground path at the hierarchical scale cutoff
- `mountain_atlas_indices` is reserved for later roof presentation, but is already confirmed at the packet boundary in M1

### `ChunkPacketV2`

Returned one-per-input-coord by native
`WorldCore.generate_chunk_packets_batch(seed, coords, world_version, settings_packed)`
for `world_version >= 14`.

`ChunkPacketV2` extends `ChunkPacketV1` additively. No V1 field is removed or
reshaped.

| Field | Type | Length | Notes |
|---|---|---:|---|
| `chunk_coord` | `Vector2i` | — | Canonical chunk coordinate |
| `world_seed` | `int` | — | Copied into the packet for validation/debug |
| `world_version` | `int` | — | Current dry-river runtime value is `14` |
| `terrain_ids` | `PackedInt32Array` | 1024 | Base terrain ids, now including dry river/lake bed ids where not blocked by mountain terrain |
| `terrain_atlas_indices` | `PackedInt32Array` | 1024 | Base-layer atlas indices; ordinary ground solves `47`-tile banks against river/lake bed footprints natively |
| `walkable_flags` | `PackedByteArray` | 1024 | `1 = walkable`, `0 = blocked`; dry river/lake bed terrain remains walkable in R1B |
| `mountain_id_per_tile` | `PackedInt32Array` | 1024 | Same semantics as `ChunkPacketV1` |
| `mountain_flags` | `PackedByteArray` | 1024 | Same bit layout as `ChunkPacketV1` |
| `mountain_atlas_indices` | `PackedInt32Array` | 1024 | Same semantics as `ChunkPacketV1` |
| `riverbed_flags` | `PackedByteArray` | 1024 | Dry river/lake footprint flags; zero for non-bed tiles or older world versions |
| `riverbed_depth` | `PackedByteArray` | 1024 | `0 none`, `1 shallow`, `2 deep` |

`riverbed_flags` bit layout:

| Bit | Name | Meaning |
|---:|---|---|
| `1 << 0` | `is_riverbed` | Tile belongs to a realized dry river channel footprint |
| `1 << 1` | `is_lakebed` | Tile belongs to a dry terminal-lake scar footprint |
| `1 << 2` | `is_ocean_directed` | River path drains into the top-Y ocean band |
| `1 << 3` | `is_side_channel` | Reserved for R1D split/rejoin side channels; R1B writes `0` |
| `1 << 4` | `is_mouth_or_delta` | Tile belongs to ocean mouth/delta widening |
| `1 << 5` | `is_debug_orphan` | Reserved for dev-only rejected drainage debug; R1B release packets write `0` |

Current code notes:
- R1B does not add `riverbed_atlas_indices` or `river_flow_q8`; dry bed
  terrain uses normal `terrain_ids` and `terrain_atlas_indices`.
- R1B realizes only ocean-directed primary river trunks from `WorldPrePass`.
  Split/rejoin side channels remain deferred to R1D.
- Lakebed scars are dry terrain footprints. They are regenerated from
  `WorldPrePass`; they are not persisted per tile.
- `TERRAIN_RIVERBED_SHALLOW`, `TERRAIN_RIVERBED_DEEP`,
  `TERRAIN_LAKEBED_SHALLOW`, and `TERRAIN_LAKEBED_DEEP` are dry base terrain
  ids and remain walkable until a future water overlay changes movement.

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
  "hydro_height": float,
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
- success candidates reject ocean band, burning band, open-water continent mask,
  high wall density, visible river trunk nodes, and terminal lake centres
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
  "hydro_height": PackedFloat32Array,
  "coarse_wall_density": PackedFloat32Array,
  "coarse_foot_density": PackedFloat32Array,
  "coarse_valley_score": PackedFloat32Array,
  "source_score": PackedFloat32Array,
  "biome_region_id": PackedInt32Array,
  "downstream_index": PackedInt32Array,
  "flow_accumulation": PackedFloat32Array,
  "visible_trunk_mask": PackedByteArray,
  "strahler_order": PackedInt32Array,
  "is_terminal_lake_center": PackedByteArray,
  "terminal_lake_polygons": Array[PackedVector2Array],
}
```

Current code notes:
- every array is indexed by coarse node index `y * grid_width + x`
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
- `pixels_per_cell` is clamped to `>= 1` on the native side
- the default new-game overview requests `pixels_per_cell = 4`, which maps the
  current `64`-tile substrate grid to roughly one image pixel per `16 x 16`
  world tiles
- the native pass re-samples player-facing ocean/burning bands and continent
  mask at overview pixel centres, directly samples the mountain field for
  `wall_density`, and bilinearly interpolates `hydro_height` from the built
  substrate
- this image is presentation-only and must not be persisted

## Not Currently Confirmed

The current code still does not confirm packet fields for future biome,
placement, roof-runtime, entrance-runtime, water overlay, drought, or
environment layers.
