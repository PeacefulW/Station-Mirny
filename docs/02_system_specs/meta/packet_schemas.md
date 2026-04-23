---
title: Packet Schemas
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.4
last_updated: 2026-04-21
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

Returned by native `WorldCore.generate_chunk_packet(seed, coord, world_version)`.

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

### `ChunkPacketV1`

Returned by native
`WorldCore.generate_chunk_packet(seed, coord, world_version, settings_packed)`.

`ChunkPacketV1` extends `ChunkPacketV0` additively. Current confirmed shape:

| Field | Type | Length | Notes |
|---|---|---|---|
| `chunk_coord` | `Vector2i` | — | Canonical chunk coordinate |
| `world_seed` | `int` | — | Copied into the packet for validation/debug |
| `world_version` | `int` | — | Current mountain runtime value is `6` |
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
| `1 << 3` | `is_anchor` | Tile is the deterministic representative tile for its `mountain_id`; in legacy worlds (`world_version < 6`) this remains the jittered anchor tile |

For tiles with `mountain_id == 0`, current native contract is `mountain_flags = 0`
and `mountain_atlas_indices = 0`.

Current code notes:
- `ChunkPacketV1` keeps one hot-path packet per chunk; no per-tile callbacks were added
- `settings_packed.size() == 0` yields V0-compatible generation with all three mountain arrays zero-filled
- `world_version == 2` keeps the original anonymous-shoulder mountain output
- `world_version == 3` applies the named-mountain ownership fix while still allowing the scattered legacy blocked fallback
- `world_version >= 4` removes the active plains-rock path for new worlds and widens owner-anchor resolution so elevated mountain terrain resolves to named mountain output instead of anonymous fallback
- `world_version >= 5` keeps the named-mountain output and also carves out the initial `12..20 x 12..20` spawn-safe patch so `mountain_id_per_tile`, `mountain_flags`, and `mountain_atlas_indices` stay zero under the starting area
- `world_version >= 6` switches new worlds to implicit-domain hierarchical labeling: aligned `1024 x 1024` macro solves recurse only through mixed cells, stop at versioned `min_label_cell_size = 8`, reuse a deterministic `1`-macro halo in native code, and hash `mountain_id` from the component representative leaf instead of the legacy raw anchor
- `mountain_id_per_tile`, `mountain_flags`, and `mountain_atlas_indices` are base packet fields only; they are not persisted in `ChunkDiffFile`
- only tiles with `mountain_id > 0` write canonical mountain terrain through `terrain_ids` as `TERRAIN_MOUNTAIN_WALL` or `TERRAIN_MOUNTAIN_FOOT`
- for `world_version >= 4`, active packet output never uses a standalone plains-rock terrain class; elevated mountain terrain is expected to resolve into named mountain output
- `mountain_atlas_indices` is reserved for later roof presentation, but is already confirmed at the packet boundary in M1

## Not Currently Confirmed

The current code still does not confirm any packet fields beyond `ChunkPacketV1`
for future biome, river, placement, roof-runtime, entrance-runtime, or
environment layers.
