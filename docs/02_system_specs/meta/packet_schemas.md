---
title: Packet Schemas
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 1.11
last_updated: 2026-04-30
related_docs:
  - ../README.md
  - system_api.md
  - commands.md
  - save_and_persistence.md
  - ../world/river_generation_v1.md
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

It also records the River Generation V1 fields that became current in
`world_version = 17`, the V1-R4 lakebed semantics that became current in
`world_version = 18`, the V1-R5 delta / controlled-split semantics that became
current in `world_version = 19`, the V1-R8 organic water raster semantics that
became current in `world_version = 20`, the V1-R9 ocean shore band semantics
that became current in `world_version = 21`, the V1-R10 refined river
centerline semantics that became current in `world_version = 22`, the V1-R11
curvature-aware river width/depth semantics that became current in
`world_version = 23`, the V1-R12 Y-shaped confluence semantics that became
current in `world_version = 24`, the V1-R13 braid island loop semantics that
became current in `world_version = 25`, the V1-R14 basin-contour lake semantics
that became current in `world_version = 26`, the V1-R15 organic coastline/shelf
semantics that became current in `world_version = 27`, the V1-R16 hydrology
shape-quality correction semantics that became current in `world_version = 28`,
the V1-R17 multi-scale headland/bay coastline semantics that became current in
`world_version = 29`, and the V1-R6 runtime water-overlay override shape. Broad
drought simulation remains a future approved shape.

## Out of Scope

- future network packet design
- future native chunk packets outside an approved source-of-truth spec
- shapes that are only implied by comments

## Save Slot Layout

Current code writes one directory per slot under `user://saves/<slot_name>/`.

Confirmed files:

| File | Writer | Reader / applier | Current shape owner |
|---|---|---|---|
| `meta.json` | `SaveCollectors.collect_meta()` | `SaveManager.get_save_list()` | `SaveCollectors` |
| `player.json` | `SaveCollectors.collect_player()` | `SaveAppliers.apply_player()` | `SaveCollectors` + component `save_state()` methods |
| `world.json` | `SaveCollectors.collect_world()` | `SaveAppliers.apply_world()` | `WorldStreamer` + `EnvironmentOverlay` |
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
    "rivers"?: {
      "enabled": bool,
      "target_trunk_count": int,
      "density": float,
      "width_scale": float,
      "lake_chance": float,
      "meander_strength": float,
      "braid_chance": float,
      "shallow_crossing_frequency": float,
      "mountain_clearance_tiles": int,
      "delta_scale": float,
      "north_drainage_bias": float,
      "hydrology_cell_size_tiles": int,
    },
  },
  "water_overlay"?: WaterOverlayState,
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
- `world_version == 16` removes the failed dry river/lake settings and packet
  fields. Base terrain is regenerated from seed/version/settings; river/lake
  arrays are not part of the current packet boundary.
- `world_version >= 17` is the first River Generation V1 runtime boundary:
  `worldgen_settings.rivers` is saved, river settings indices `15-26` are
  required for native chunk generation, and `ChunkPacketV1` emits the current
  hydrology fields listed below.
- `world_version >= 18` enables V1-R4 natural lake basin selection and lakebed /
  lake shoreline packet rasterization. Existing `world_version = 17` saves keep
  `lake_id = 0` and the pre-R4 river/ocean packet output.
- `world_version >= 19` enables V1-R5 river-mouth delta / estuary widening and
  controlled braid/distributary split packet flags. Existing
  `world_version = 18` saves keep pre-R5 river/lake packet output.
- `world_version >= 20` enables V1-R8 organic water raster output: natural lake
  shorelines use deterministic noise, river raster edges may meander, and river
  widths vary dynamically. Existing `world_version = 19` saves keep pre-R8
  river/lake/delta packet output.
- `world_version >= 21` enables V1-R9 ocean shore band output: ocean edge
  chunks may emit walkable `TERRAIN_SHORE` with `HYDROLOGY_FLAG_SHORE` /
  `HYDROLOGY_FLAG_BANK` and no current water on the shore tile. Existing
  `world_version = 20` saves keep pre-R9 ocean-floor-only coast output.
- `world_version >= 22` enables V1-R10 refined river centerline output: rivers
  use a native whole-path refined centerline substrate, direction-memory
  meanders, slope/floodplain/mountain-clearance width modulation, and bounded
  spatial-index candidate queries. Existing `world_version = 21` saves keep
  pre-R10 per-edge organic river raster output.
- `world_version >= 23` enables V1-R11 curvature-aware river width/depth:
  refined river edges contribute signed curvature and post-confluence context
  to native chunk rasterization, which widens curved/confluence reaches and
  shifts deep riverbed classification toward the outer bank of bends. Existing
  `world_version = 22` saves keep pre-R11 refined-centerline river output.
- `world_version >= 24` enables V1-R12 Y-shaped confluence zones: native
  refined river edges around qualifying confluence nodes mark two or more
  upstream arms and the downstream reach as one softened confluence join.
  Existing `world_version = 23` saves keep pre-R12 curvature-aware river output.
- `world_version >= 25` enables V1-R13 braid island loops: controlled split
  output uses native multi-edge branches that rejoin the same downstream reach
  and keep the existing `HYDROLOGY_FLAG_BRAID_SPLIT` packet flag. Existing
  `world_version = 24` saves keep pre-R13 simple controlled-split output.
- `world_version >= 26` enables V1-R14 basin-contour lakes and oxbow
  preparation: selected lakes use native filled-basin depth/spill data for
  shallow/deep rim rasterization, and refined river bends expose aggregate
  oxbow candidate diagnostics. Existing `world_version = 25` saves keep
  pre-R14 lake raster output.
- `world_version >= 27` enables V1-R15 organic coastline/shelf output: native
  coast distance, shelf depth, and river-mouth influence fields classify shore,
  shallow ocean shelf, and deep ocean while preserving the existing packet
  arrays. Existing `world_version = 26` saves keep pre-R15 ocean shelf output.
- `world_version >= 28` enables V1-R16 hydrology shape-quality corrections:
  refined river width modulation is continuous along centerline distance, braid
  island loops are more strictly validated, and coast distance is sampled as
  tile-level coastline geometry while preserving the existing packet arrays.
  Existing `world_version = 27` saves keep pre-R16 shape output.
- `world_version >= 29` enables V1-R17 multi-scale headland/bay coastline
  output: the native tile-sampled coast distance uses an expanded near-coast
  band plus a low-frequency deterministic octave for larger bays and capes,
  while preserving the existing packet arrays. Existing `world_version = 28`
  saves keep pre-R17 coastline output.
- `water_overlay` is optional and appears only when explicit local current-water
  overrides exist. It does not change `world_version` because it is runtime
  overlay state, not canonical worldgen output.
- `worldgen_settings.mountains` is written once for new worlds and then loaded
  from `world.json`, not from the repository `.tres`
- missing `worldgen_settings.mountains` restores hard-coded loader defaults for
  backward-compatible saves
- `worldgen_signature` is diagnostic only and is never authoritative on load
- legacy/frozen-world callers may still emit only the older boolean fields

Current River Generation V1 save extension for `world_version >= 17`:

```text
"worldgen_settings": {
  ...current fields,
  "rivers": {
    "enabled": bool,
    "target_trunk_count": int,
    "density": float,
    "width_scale": float,
    "lake_chance": float,
    "meander_strength": float,
    "braid_chance": float,
    "shallow_crossing_frequency": float,
    "mountain_clearance_tiles": int,
    "delta_scale": float,
    "north_drainage_bias": float,
    "hydrology_cell_size_tiles": int,
  }
}
```

### `WaterOverlayState`

Optional field under `world.json`, owned by `EnvironmentOverlay`.

```text
{
  "format": 1,
  "dirty_block_size": 16,
  "overrides": Array[WaterOverlayOverride],
}
```

Rules:
- present only when explicit local current-water overrides exist;
- absent means "use seed-derived packet `water_class` defaults";
- dirty regions / queues are runtime-only and are not saved;
- this state is applied after regenerated base chunks and `WorldDiffStore`
  terrain diffs.

### `WaterOverlayOverride`

```text
{
  "x": int,
  "y": int,
  "water_class": int,
}
```

Current code note:
- `water_class` uses the same numeric values as `ChunkPacketV1.water_class`
  (`0 = none`, `1 = shallow`, `2 = deep`, `3 = ocean`);
- the override changes effective current water and derived walkability only. It
  does not rewrite `terrain_ids` or the seed-derived packet `water_class` array.

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
| `world_version` | `int` | — | Current river/lake/delta/organic-water/ocean-shore/refined-river/curvature-river/Y-confluence/braid-loop/basin-contour-lake/organic-coastline/headland-coast runtime value is `29`; `17` remains the first river-enabled compatibility boundary |
| `terrain_ids` | `PackedInt32Array` | 1024 | Base terrain ids for the gameplay layer |
| `terrain_atlas_indices` | `PackedInt32Array` | 1024 | Base-layer atlas indices; mountain tiles reuse the native mountain atlas solve, and plains ground may use native riverbed / river-bank / lakebed / ocean-floor adjacency for 47-tile edge variants |
| `walkable_flags` | `PackedByteArray` | 1024 | `1 = walkable`, `0 = blocked` |
| `mountain_id_per_tile` | `PackedInt32Array` | 1024 | `0 = no named mountain`; non-zero = deterministic `mountain_id` |
| `mountain_flags` | `PackedByteArray` | 1024 | Per-tile mountain bit layout documented below |
| `mountain_atlas_indices` | `PackedInt32Array` | 1024 | Roof-ready atlas indices derived from `mountain_id` adjacency via `autotile_47` |
| `hydrology_id_per_tile` | `PackedInt32Array` | 1024 | `0 = no hydrology`; otherwise stable river/lake/ocean feature id for `world_version >= 17` |
| `hydrology_flags` | `PackedInt32Array` | 1024 | River/lake/shore/bank/floodplain bitfield for `world_version >= 17` |
| `floodplain_strength` | `PackedByteArray` | 1024 | `0..255` bank/floodplain strength for `world_version >= 17` |
| `water_class` | `PackedByteArray` | 1024 | Default water class for `world_version >= 17`: none, shallow, deep, ocean |
| `flow_dir_quantized` | `PackedByteArray` | 1024 | Compact hydrology flow direction for `world_version >= 17`; `255` is terminal/none |
| `stream_order` | `PackedByteArray` | 1024 | Compact stream order / discharge bucket for `world_version >= 17` |
| `water_atlas_indices` | `PackedInt32Array` | 1024 | Derived water/shore presentation atlas index for `world_version >= 17` |

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
  `9-14` are `world_width_tiles`, `world_height_tiles`, `ocean_band_tiles`,
  `burning_band_tiles`, `pole_orientation`, and `foundation_slope_bias`
- for `world_version >= 17`, `generate_chunk_packets_batch(...)` also requires
  river settings indices `15-26` and builds/reuses `WorldHydrologyPrePass`
  before packet rasterization
- `WorldCore.build_world_hydrology_prepass(...)` uses an extended
  `settings_packed` payload for diagnostics: river settings indices `15-26`
  are `enabled`, `target_trunk_count`, `density`, `width_scale`,
  `lake_chance`, `meander_strength`, `braid_chance`,
  `shallow_crossing_frequency`, `mountain_clearance_tiles`, `delta_scale`,
  `north_drainage_bias`, and `hydrology_cell_size_tiles`
- the current native boundary requires `world_version >= 6`
- `world_version >= 6` uses implicit-domain hierarchical labeling: aligned `1024 x 1024` macro solves recurse only through mixed cells, stop at versioned `min_label_cell_size = 8`, reuse a deterministic `1`-macro halo in native code, and hash `mountain_id` from the component representative leaf
- `mountain_id_per_tile`, `mountain_flags`, and `mountain_atlas_indices` are base packet fields only; they are not persisted in `ChunkDiffFile`
- only tiles with `mountain_id > 0` write canonical mountain terrain through `terrain_ids` as `TERRAIN_MOUNTAIN_WALL` or `TERRAIN_MOUNTAIN_FOOT`
- active packet output never uses a standalone plains-rock terrain class; elevated mountain terrain either resolves into named mountain output or stays on the ground path at the hierarchical scale cutoff
- `mountain_atlas_indices` is reserved for later roof presentation, but is already confirmed at the packet boundary in M1

### River Generation V1 Terrain, Water, and Packet Shape

The following fields are current for `world_version >= 17`. V1-R4 makes
lakebed and lake shoreline semantics current for `world_version >= 18`; V1-R5
makes delta / estuary and controlled braid/distributary split flag semantics
current for `world_version >= 19`; V1-R8 makes organic lake shoreline noise,
meandered river raster edges, and dynamic river width current for
`world_version >= 20`; V1-R9 makes ocean shore band output current for
`world_version >= 21`; V1-R10 makes refined whole-river centerlines and bounded
spatial-index river candidate queries current for `world_version >= 22`;
V1-R11 makes curvature-aware width/depth and post-confluence reach flags current
for `world_version >= 23`; V1-R12 makes native Y-shaped confluence zones current
for `world_version >= 24`; V1-R13 makes native rejoining braid island loops
current for `world_version >= 25`; V1-R14 makes basin-contour lake rim/depth
rasterization current for `world_version >= 26`; V1-R15 makes organic
coastline/shelf rasterization current for `world_version >= 27`; V1-R16 makes
continuous river width, stricter braid island loops, and tile-sampled coastline
rasterization current for `world_version >= 28`; V1-R17 makes multi-scale
headland/bay coastline carving current for `world_version >= 29`. Broad drought
semantics remain reserved for a future iteration.

| Constant | Numeric id | Meaning | Default traversal |
|---|---:|---|---|
| `TERRAIN_RIVERBED_SHALLOW` | 5 | Canonical shallow riverbed under water-capable channel | Walkable when dry or under shallow water |
| `TERRAIN_RIVERBED_DEEP` | 6 | Canonical deep riverbed under main channel | Walkability comes from current water class |
| `TERRAIN_LAKEBED` | 7 | Canonical natural lake floor | Walkability comes from current water class |
| `TERRAIN_OCEAN_FLOOR` | 8 | Canonical ocean / estuary floor connected to the north ocean | Blocking by default through ocean water class |
| `TERRAIN_SHORE` | 9 | Land/water transition band around ocean, lakes, and wider rivers | Walkable unless current water class blocks |
| `TERRAIN_FLOODPLAIN` | 10 | Canonical low river-adjacent flood-shaped land | Walkable by default |

Water classes are overlay classes, not immutable terrain ids:

| Constant | Numeric id | Meaning | Traversal |
|---|---:|---|---|
| `WATER_CLASS_NONE` | 0 | No current water | Uses base terrain walkability |
| `WATER_CLASS_SHALLOW` | 1 | Shallow current water | Walkable; future tuning may add movement penalty |
| `WATER_CLASS_DEEP` | 2 | Deep current water | Blocking |
| `WATER_CLASS_OCEAN` | 3 | Ocean / impassable sea water | Blocking |

The first river-enabled `ChunkPacketV1` must extend the current packet
additively. Existing fields are not removed or reshaped.

| Field | Type | Length | Meaning |
|---|---|---:|---|
| `terrain_ids` | `PackedInt32Array` | 1024 | Existing field may include riverbed, lakebed, ocean floor, shore, and floodplain terrain ids |
| `walkable_flags` | `PackedByteArray` | 1024 | Derived from base terrain plus current/default water class for that packet |
| `hydrology_id_per_tile` | `PackedInt32Array` | 1024 | `0 = no hydrology`; otherwise stable river/lake/ocean feature id |
| `hydrology_flags` | `PackedInt32Array` | 1024 | Bitfield documented below |
| `floodplain_strength` | `PackedByteArray` | 1024 | `0..255` presentation/future-wetting strength |
| `water_class` | `PackedByteArray` | 1024 | Current/default water class: none, shallow, deep, ocean |
| `flow_dir_quantized` | `PackedByteArray` | 1024 | Optional compact flow direction for animation/debug, not pathfinding authority |
| `stream_order` | `PackedByteArray` | 1024 | Compact stream order / discharge bucket |
| `water_atlas_indices` | `PackedInt32Array` | 1024 | Derived water/shore presentation atlas index |

`hydrology_flags` bit layout:

| Bit | Constant | Meaning |
|---:|---|---|
| `1 << 0` | `HYDROLOGY_FLAG_RIVERBED` | Tile belongs to river channel bed |
| `1 << 1` | `HYDROLOGY_FLAG_LAKEBED` | Tile belongs to a natural lake basin |
| `1 << 2` | `HYDROLOGY_FLAG_SHORE` | Tile is shoreline / transition band |
| `1 << 3` | `HYDROLOGY_FLAG_BANK` | Tile is bank-adjacent terrain |
| `1 << 4` | `HYDROLOGY_FLAG_FLOODPLAIN` | Tile is floodplain-capable land |
| `1 << 5` | `HYDROLOGY_FLAG_DELTA` | Tile belongs to delta or estuary widening |
| `1 << 6` | `HYDROLOGY_FLAG_BRAID_SPLIT` | Tile belongs to a controlled braid/distributary split |
| `1 << 7` | `HYDROLOGY_FLAG_CONFLUENCE` | Tile marks a confluence or its widened reach |
| `1 << 8` | `HYDROLOGY_FLAG_SOURCE` | Tile marks a river source/headwater reach |

Rules:
- `riverbed`, `lakebed`, `shore`, and `ocean_floor` terrain are canonical base
  terrain. Drying removes or changes `water_class`; it does not rewrite bed
  terrain.
- for `world_version >= 21`, ocean-edge shore tiles use `TERRAIN_SHORE`,
  `HYDROLOGY_FLAG_SHORE | HYDROLOGY_FLAG_BANK`, `WATER_CLASS_NONE`, and a
  stable ocean hydrology id (`2000000`). Ocean-floor tiles use the same ocean
  hydrology id and `WATER_CLASS_OCEAN`. River-mouth delta tiles may keep their
  river segment id instead.
- for `world_version >= 27`, ocean-floor tiles within the native shelf band may
  use `WATER_CLASS_SHALLOW` and walkable flags while farther ocean-floor tiles
  keep `WATER_CLASS_OCEAN` and remain blocking. No new packet arrays are added.
- for `world_version >= 28`, ocean floor and shore classification samples the
  native coast distance field as tile-level coastline geometry, preserving the
  same terrain/water arrays.
- for `world_version >= 29`, that tile-level coastline geometry adds
  deterministic multi-scale headland/bay carving while preserving the same
  terrain/water arrays.
- `water_class` is the initial/default overlay state for packet publication.
  Future drought/refill systems must own runtime overlay mutation separately.
- deep and ocean water produce blocking `walkable_flags`; shallow water remains
  walkable.
- `HYDROLOGY_FLAG_DELTA` marks widened river-mouth estuary/delta output on
  riverbed, shore, or ocean-floor tiles.
- `HYDROLOGY_FLAG_BRAID_SPLIT` marks controlled braid/distributary split output;
  split riverbed tiles keep a stable river `hydrology_id_per_tile`.
- for `world_version >= 25`, non-delta braid split output is generated from
  native rejoining island-loop geometry instead of a simple parallel split
  edge; it still uses the same `HYDROLOGY_FLAG_BRAID_SPLIT` bit.
- for `world_version >= 23`, `HYDROLOGY_FLAG_CONFLUENCE` may also mark the
  widened post-confluence reach on riverbed, shore, or bank tiles; it does not
  add a new packet array.
- for `world_version >= 24`, `HYDROLOGY_FLAG_CONFLUENCE` may mark the softened
  Y-shaped confluence zone across upstream arms and the downstream reach; it
  still does not add a new packet array.
- these fields must be produced in native chunk generation from the
  `WorldHydrologyPrePass` snapshot. GDScript must not rasterize rivers or loop
  through chunk tiles to derive them.

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
  and high wall density
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
  "biome_region_id": PackedInt32Array,
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
- `layer_mask = 0` returns the default terrain overview. The hydro-height layer
  mask returns a diagnostic height-map image from the raw `hydro_height`
  substrate channel; it is presentation/debug output and is not save data.
- `pixels_per_cell` is clamped to `>= 1` on the native side
- the foundation overview source requests `pixels_per_cell = 4`, which maps the
  current `64`-tile substrate grid to roughly one image pixel per `16 x 16`
  world tiles
- the foundation native pass renders only currently realised gameplay terrain
  classes: ground, mountain foot, and mountain wall
- mountain pixels sample the mountain field at overview-pixel resolution and
  apply the same hierarchical `mountain_id` cutoff used by `ChunkPacketV1`;
  `hydro_height` is used only as subtle neutral-ground shading in the default
  terrain overview
- the foundation overview remains a foundation/mountain view; the default
  new-game composite overview uses this image plus a transparent
  `WorldHydrologyOverviewImage`, while the standalone water-only diagnostic
  mode uses `WorldHydrologyOverviewImage` directly
- this image is presentation-only and must not be persisted

### `WorldHydrologyPrePassBuildResult`

Returned by native
`WorldCore.build_world_hydrology_prepass(seed, world_version, settings_packed)`.

Success shape:

```text
{
  "success": true,
  "cache_hit": bool,
  "grid_width": int,
  "grid_height": int,
  "cell_size_tiles": int,
  "signature": int,
  "compute_time_ms": float,
  "river_segment_count": int,
  "river_source_count": int,
  "refined_river_edge_count": int,
  "curvature_refined_river_edge_count": int,
  "confluence_refined_river_edge_count": int,
  "y_confluence_zone_count": int,
  "y_confluence_refined_river_edge_count": int,
  "braid_loop_candidate_count": int,
  "braid_loop_refined_river_edge_count": int,
  "basin_contour_lake_node_count": int,
  "lake_spill_point_count": int,
  "lake_outlet_connection_count": int,
  "oxbow_candidate_count": int,
  "ocean_coastline_node_count": int,
  "ocean_shallow_shelf_node_count": int,
  "ocean_river_mouth_node_count": int,
  "river_spatial_index_cell_count": int,
}
```

Failure shape:

```text
{
  "success": false,
  "message": String,
}
```

Current code notes:
- this result is worker/debug orchestration data, not save data
- a matching second call returns `cache_hit: true`
- the method requires river settings fields in `settings_packed`; current
  `world_version >= 17` chunk packet generation requires the same extended
  settings payload
- for `world_version >= 23`, the curvature/confluence refined-edge counts are
  aggregate smoke-test diagnostics; they are not authoritative gameplay state
  and must not be persisted
- for `world_version >= 24`, the Y-confluence counts are aggregate smoke-test
  diagnostics; they are not authoritative gameplay state and must not be
  persisted
- for `world_version >= 25`, the braid-loop candidate/edge counts are aggregate
  smoke-test diagnostics; they are not authoritative gameplay state and must
  not be persisted
- for `world_version >= 26`, the basin-contour lake, lake spill/outlet, and
  oxbow candidate counts are aggregate smoke-test diagnostics; they are not
  authoritative gameplay state and must not be persisted
- for `world_version >= 27`, the coastline, shallow-shelf, and river-mouth
  influence counts are aggregate smoke-test diagnostics; they are not
  authoritative gameplay state and must not be persisted
- for `world_version >= 28`, shape-quality corrections reuse the same aggregate
  diagnostics and add no debug arrays that can become save state
- for `world_version >= 29`, multi-scale headland/bay coastline carving reuses
  the same aggregate diagnostics and adds no debug arrays that can become save
  state

### `WorldHydrologyPrePassSnapshotDebug`

Returned by dev-only native
`WorldCore.get_world_hydrology_snapshot(layer_mask, downscale_factor)` after a
matching hydrology snapshot has been built.

```text
{
  "grid_width": int,
  "grid_height": int,
  "cell_size_tiles": int,
  "world_width_tiles": int,
  "world_height_tiles": int,
  "ocean_band_tiles": int,
  "seed": int,
  "world_version": int,
  "signature": int,
  "compute_time_ms": float,
  "cycle_free": bool,
  "layer_mask": int,
  "downscale_factor": int,
  "hydro_elevation": PackedFloat32Array,
  "filled_elevation": PackedFloat32Array,
  "flow_dir": PackedByteArray,
  "flow_accumulation": PackedFloat32Array,
  "watershed_id": PackedInt32Array,
  "lake_id": PackedInt32Array,
  "ocean_sink_mask": PackedByteArray,
  "ocean_coast_distance_tiles": PackedFloat32Array,
  "ocean_shelf_depth_ratio": PackedFloat32Array,
  "ocean_river_mouth_influence": PackedFloat32Array,
  "mountain_exclusion_mask": PackedByteArray,
  "floodplain_potential": PackedFloat32Array,
  "river_segment_count": int,
  "river_source_count": int,
  "river_node_mask": PackedByteArray,
  "river_segment_id": PackedInt32Array,
  "river_stream_order": PackedByteArray,
  "river_discharge": PackedFloat32Array,
  "river_segment_ranges": PackedInt32Array,
  "river_path_node_indices": PackedInt32Array,
  "refined_river_edge_count": int,
  "curvature_refined_river_edge_count": int,
  "confluence_refined_river_edge_count": int,
  "y_confluence_zone_count": int,
  "y_confluence_refined_river_edge_count": int,
  "braid_loop_candidate_count": int,
  "braid_loop_refined_river_edge_count": int,
  "basin_contour_lake_node_count": int,
  "lake_spill_point_count": int,
  "lake_outlet_connection_count": int,
  "oxbow_candidate_count": int,
  "ocean_coastline_node_count": int,
  "ocean_shallow_shelf_node_count": int,
  "ocean_river_mouth_node_count": int,
  "river_spatial_index_cell_size_tiles": int,
  "river_spatial_index_width": int,
  "river_spatial_index_height": int,
}
```

Current code notes:
- every array is indexed by hydrology node index `y * grid_width + x`
- `flow_dir` uses compact direction buckets with `255` as terminal
- for `world_version >= 18`, `lake_id` records deterministic natural lake basin
  ids; for `world_version = 17`, it remains `0` to preserve the pre-R4
  compatibility boundary
- V1-R3A river graph fields remain debug/dev snapshot data and must not be
  saved; V1-R3B chunk generation reads the native snapshot internally and emits
  only compact per-tile hydrology packet fields; V1-R4 also reads `lake_id` for
  native lakebed and shoreline rasterization
- `river_segment_ranges` uses six-int records:
  `segment_id, path_offset, path_length, head_node, tail_node, max_stream_order`
- `river_path_node_indices` is the concatenated hydrology-node path storage
  referenced by `river_segment_ranges`
- for `world_version >= 22`, `refined_river_edge_count` reports the native
  RAM-only refined centerline edge count, and the `river_spatial_index_*`
  fields report the diagnostic shape of the bounded candidate index used by
  chunk rasterization. The refined edge coordinates and index contents are
  native-owned implementation data and are not exposed as packet or save arrays.
- for `world_version >= 23`, `curvature_refined_river_edge_count` reports
  refined edges with non-zero signed curvature used by chunk width/depth
  classification, and `confluence_refined_river_edge_count` reports refined
  edges classified as widened post-confluence reaches. These are aggregate
  diagnostics only and are not packet or save arrays.
- for `world_version >= 24`, `y_confluence_zone_count` reports qualifying
  confluence nodes with native Y-shaped influence zones, and
  `y_confluence_refined_river_edge_count` reports refined edges affected by
  that tapering zone. These are aggregate diagnostics only and are not packet
  or save arrays.
- for `world_version >= 25`, `braid_loop_candidate_count` reports accepted
  native island-loop split candidates, and
  `braid_loop_refined_river_edge_count` reports emitted refined loop edges.
  These are aggregate diagnostics only and are not packet or save arrays.
- for `world_version >= 26`, `basin_contour_lake_node_count` reports selected
  lake nodes with native basin depth ratios, `lake_spill_point_count` reports
  selected spill points, `lake_outlet_connection_count` reports selected spill
  points with a downstream outlet, and `oxbow_candidate_count` reports prepared
  high-curvature lowland abandoned-meander candidates. These are aggregate
  diagnostics only and are not packet or save arrays.
- for `world_version >= 27`, `ocean_coast_distance_tiles` is the native signed
  coarse coast field, `ocean_shelf_depth_ratio` classifies shallow shelf versus
  deep ocean, and `ocean_river_mouth_influence` widens local coast/shelf
  behavior around valid river mouths. These arrays are debug snapshot data
  only; they are not packet or save arrays. `ocean_coastline_node_count`,
  `ocean_shallow_shelf_node_count`, and `ocean_river_mouth_node_count` are
  aggregate diagnostics for smoke coverage.
- for `world_version >= 28`, chunk and overview rasterization sample
  `ocean_coast_distance_tiles` as a tile-level signed coastline field; the
  stored debug arrays remain node-level and RAM-only.
- for `world_version >= 29`, that tile-level sampler adds deterministic
  multi-scale headland/bay carving; the stored debug arrays remain node-level
  and RAM-only.
- this dictionary is debug/dev tooling only and must not be persisted

### `WorldHydrologyOverviewImage`

Returned by dev-only native
`WorldCore.get_world_hydrology_overview(layer_mask, pixels_per_cell)` after a
matching hydrology snapshot has been built.

```text
Image {
  width: grid_width * pixels_per_cell,
  height: grid_height * pixels_per_cell,
  format: FORMAT_RGBA8,
}
```

Current code notes:
- default layer renders a hydrology water overview: ocean sink pixels, natural
  lake pixels, selected river graph pixels, mountain exclusion, and effective
  hydrology height backing colours
- for `world_version >= 22`, river overview pixels are sampled from the native
  refined whole-path centerline substrate instead of rebuilding independent
  overview-only river edges
- for `world_version >= 23`, post-confluence radius changes in the refined
  substrate may be visible in overview river pixels, while bend-side deep-water
  classification remains a chunk packet concern
- for `world_version >= 24`, Y-shaped confluence radius/taper changes in the
  refined substrate may be visible in overview river pixels
- for `world_version >= 25`, native braid island loop edges may be visible in
  overview river pixels through the same refined substrate
- for `world_version >= 26`, lake overview pixels use the same basin-contour
  edge threshold as chunk lake rasterization
- for `world_version >= 27`, ocean overview pixels may distinguish shallow
  shelf from deep ocean using the native shelf depth ratio
- for `world_version >= 28`, ocean overview pixels sample the same tile-level
  coastline geometry as chunk rasterization
- for `world_version >= 29`, ocean overview pixels include the same
  deterministic headland/bay coastline carving as chunk rasterization
- the new-game overview water/composite modes request this image through the
  packet worker; it is presentation/debug output, not gameplay state or save
  data
- layer mask `1 << 0` renders flow accumulation; `1 << 1` renders filled
  elevation; `1 << 6` renders a transparent water-only overlay for worker-side
  composition over the foundation terrain overview
- this image is presentation/debug output and must not be persisted

## Not Currently Confirmed

The current code still does not confirm live chunk packet fields for future
biome, placement, roof-runtime, entrance-runtime, broad drought, or environment
layers. Runtime water overlay mutation is confirmed only as sparse explicit
overrides in `world.json.water_overlay`; current packet `water_class` remains
seed-derived default state.
