---
title: Packet Schemas
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 1.10
last_updated: 2026-07-15
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
- dev/probe native result dictionaries that are currently consumed by world
  runtime tooling

## Current Draft Blockers

This document remains draft after the 2026-06-29 pass because several confirmed
native result dictionaries are presentation/debug/probe surfaces rather than
stable gameplay packet contracts.

Known blockers:
- `MountainPlateauRasterImageResult` has a broad preset-dependent debug tail;
  only the stable consumed keys are documented below.
- Future network packet design remains out of scope.

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
| `weather.json` | `SaveCollectors.collect_weather()` | `SaveAppliers.apply_weather()` | `WeatherRuntime` |
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
    "plains_trees"?: {
      "id": String,
      "object_family": String,
      "biome_id": String,
      "placement_mask": String,
      "density": float,
      "scatter_grid_side": int,
      "max_per_chunk": int,
      "edge_padding_px": float,
      "min_distance_px": float,
      "grass_density_min": float,
      "visual_size_min_px": float,
      "visual_size_max_px": float,
      "small_chance": float,
      "small_visual_size_px": float,
      "hero_chance": float,
      "hero_visual_size_px": float,
      "grass_field_scale_px": float,
      "grass_coverage": float,
      "rock_field_scale_px": float,
      "rock_coverage": float,
      "macro_mass_scale_px": float,
      "macro_mass_strength": float,
      "path_scale_px": float,
      "path_width": float,
      "path_warp_px": float,
      "path_strength": float,
    },
    "plains_small_rocks"?: {
      "id": String,
      "object_family": String,
      "biome_id": String,
      "placement_mask": String,
      "density": float,
      "scatter_grid_side": int,
      "max_per_chunk": int,
      "edge_padding_px": float,
      "min_distance_px": float,
      "grass_density_min": float,
      "grass_density_max": float,
      "visual_size_min_px": float,
      "visual_size_max_px": float,
      "asset_variant_count": int,
      "grass_field_scale_px": float,
      "grass_coverage": float,
      "rock_field_scale_px": float,
      "rock_coverage": float,
      "macro_mass_scale_px": float,
      "macro_mass_strength": float,
      "path_scale_px": float,
      "path_width": float,
      "path_warp_px": float,
      "path_strength": float,
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
  `worldgen_settings.mountains`, `worldgen_settings.world_bounds`,
  `worldgen_settings.foundation`, `worldgen_settings.lakes`, and
  `worldgen_settings.plains_trees`; for `world_version >= 62` they also require
  `worldgen_settings.plains_small_rocks`; missing
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
- `world_version == 44` is the grid-contract boundary: one world tile
  is `64 px`, one chunk is `16 x 16` tiles, and chunk packet arrays contain
  `256` entries. This changes chunk coordinate sharding and therefore rejects
  previous `32 px` / `32 x 32` pre-alpha saves before chunk diffs are applied.
- `world_version == 45` is the historical first satellite-outcrop
  mountain-generation boundary: sparse `3..10`-tile mountain components may
  generate near large mountain masses. `ChunkPacketV1` shape is unchanged.
- `world_version == 46` is the historical clustered satellite-outcrop
  mountain-generation boundary: sparse groups of `2..6` separate `3..10`-tile
  mountain components may generate near large mountain masses. `ChunkPacketV1`
  shape is unchanged.
- `world_version == 47` is the historical strengthened satellite-outcrop
  mountain-generation boundary: sparse groups of `2..20` separate `3..18`-tile
  mountain components may generate near large mountain masses, biased toward
  `10..20` components with occasional larger footprints. `ChunkPacketV1` shape
  is unchanged.
- `world_version == 48` is the historical mountain passage/outcrop refinement
  boundary: satellite outcrop clusters become more frequent and spatially
  varied, and deterministic native carve masks create walkable passages,
  pockets, and gorges inside mountain masses. `ChunkPacketV1` shape is
  unchanged because carved openings are represented by existing terrain,
  walkability, and mountain fields.
- `world_version == 49` is the historical static biofield flora placement
  boundary: native object packets may emit spiky flora family atlas index `1`
  as a small static brown seaweed object only when its deterministic center
  passes the orange biofield mask. `ChunkPacketV1` shape is unchanged because
  the object uses existing visual object arrays and does not add collision,
  save identity, commands, or events.
- `world_version == 50` is the historical rare rocky-patch rock formation
  placement boundary: native object packets may emit rock family atlas index
  `3` as a sparse large object only when its deterministic center and clearance
  samples pass the rocky ground patch mask. `ChunkPacketV1` shape is unchanged
  because the object uses existing visual object arrays and the existing
  large-rock collision flag.
- `world_version == 51` is the historical rare rocky-patch rock pillar
  presentation boundary: native object packets keep rock family atlas index `3`
  but may choose eight `45 degree` atlas variants instead of four `90 degree`
  variants. `ChunkPacketV1` shape is unchanged because the object still uses the
  same `object_variant` byte field and existing large-rock collision flag.
- `world_version == 52` is the historical mountain-edge object clearance boundary:
  native object packets suppress rocks, living flora, and spiky flora when their
  deterministic placement center or local clearance samples overlap canonical
  mountain wall/foot terrain. `ChunkPacketV1` shape is unchanged because this
  only removes generated presentation records from existing object arrays.
- `world_version == 57` is the historical plains grass big rock placement boundary:
  native object packets may emit rare blocking `object_kind == 5` records only
  on the visual grass field and outside the orange biofield mask. `ChunkPacketV1`
  shape is unchanged because this uses the existing object arrays and collision
  flag.
- `world_version == 58` is the historical plains grass-edge small rock placement
  boundary: native object packets may emit visual-only `object_kind == 6`
  records concentrated on the procedural open-ground to grass transition. The
  family uses one atlas bank (`object_atlas_index == 0`), `object_variant`
  selects one of twelve atlas frames, and `object_flags == 0`; the cheap
  contact-shadow underlay is presentation-only. `ChunkPacketV1` shape is
  unchanged because this uses the existing object arrays.
- `world_version == 59` is the historical grass-edge small rock scree tuning
  boundary: `object_kind == 6` keeps the same packet family and atlas contract,
  but native placement is rebalanced toward sparser clusters on the true
  open-ground to grass seam and the atlas is rebaked with self-shadow/AO
  without baked ground projection. `ChunkPacketV1` shape is unchanged.
- `world_version == 60` is the historical plains tree placement profile boundary:
  native `object_kind == 4` placement reads the frozen
  `worldgen_settings.plains_trees` profile through `settings_packed[22..43]`.
  `ChunkPacketV1` shape is unchanged because this only changes how existing
  immutable tree records are generated.
- `world_version == 61` is the current object-placement cleanup boundary:
  native object packets no longer emit the previous generated stone/rock object
  families (`object_kind` values `1`, `5`, and `6`). `ChunkPacketV1` shape is
  unchanged; flora/tree records keep using the same `object_*` arrays.
- `world_version == 62` is the replacement small-rock placement boundary:
  native object packets may emit visual-only `object_kind == 7` records, using
  the frozen `worldgen_settings.plains_small_rocks` profile through
  `settings_packed[44..63]`. `ChunkPacketV1` shape is unchanged because the
  existing `object_*` arrays carry the new visual family.
- `world_version == 63` is the clustered small-rock placement boundary:
  `object_kind == 7` remains visual-only, but native placement uses edge,
  rocky-patch, and path-edge scores to accept cluster centers and emits several
  close rocks per accepted cluster. The profile is packed through
  `settings_packed[44..70]`. `ChunkPacketV1` shape is unchanged.
- `worldgen_settings.mountains` is written once for new worlds and then loaded
  from `world.json`, not from the repository `.tres`
- `worldgen_settings.lakes` is written once for new worlds and then loaded
  from `world.json`, not from the repository `.tres`
- `worldgen_settings.plains_trees` is written once for new worlds from
  `data/world_objects/placement_groups/plains_trees.tres` and then loaded from
  `world.json`, not from the repository `.tres`
- `worldgen_settings.plains_small_rocks` is written once for new worlds from
  `data/world_objects/placement_groups/plains_small_rocks.tres` and then loaded
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

### `WeatherSaveData`

Slow weather state only (ADR-0007); live axes (`cloud_cover`, wind targets,
reserved axes) are NOT saved — they reconstruct from the regime + clock on load.

```text
{
  "active_regime": String,      # e.g. "core:cloudy"; unknown id -> default "core:clear"
  "next_regime": String,        # regime being blended toward
  "in_transition": bool,
  "transition": float,          # 0..1 blend toward next_regime
  "remaining_hours": float,     # remaining duration of the active regime
  "weather_time_hours": float,  # accumulator for cloud breathing + heading meander continuity
  "transition_count": int,      # deterministic salt for successor / duration selection
}
```

Old saves without `weather.json` (or an empty dict) leave `WeatherRuntime` in
its boot default (`core:clear`, freshly rolled timers).

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
| `world_version` | `int` | — | Current foundation runtime value is `63` |
| `terrain_ids` | `PackedInt32Array` | 256 | Base terrain ids for the gameplay layer |
| `terrain_atlas_indices` | `PackedInt32Array` | 256 | Base-layer atlas indices; mountain tiles reuse the native mountain atlas solve, and plains ground opens `autotile_47` bank edges only against shallow/deep lake-bed neighbours |
| `walkable_flags` | `PackedByteArray` | 256 | `1 = walkable`, `0 = blocked` |
| `lake_flags` | `PackedByteArray` | 256 | Per-tile lake bit field; bit `0` is `is_water_present` |
| `mountain_id_per_tile` | `PackedInt32Array` | 256 | `0 = no named mountain`; non-zero = deterministic `mountain_id` |
| `mountain_flags` | `PackedByteArray` | 256 | Per-tile mountain bit layout documented below |
| `mountain_atlas_indices` | `PackedInt32Array` | 256 | Roof-ready atlas indices derived from `mountain_id` adjacency via `autotile_47` |
| `object_kind` | `PackedByteArray` | N | Visual object family id: `2` living flora, `3` spiky flora, `4` tree, `7` small rock; historical ids `1`, `5`, and `6` are not emitted in `world_version >= 61` |
| `object_local_x_px_q4` | `PackedByteArray` | N | Chunk-local pixel X quantized to `4 px` |
| `object_local_y_px_q4` | `PackedByteArray` | N | Chunk-local pixel Y quantized to `4 px` |
| `object_size_px` | `PackedByteArray` | N | Rendered sprite size in pixels |
| `object_atlas_index` | `PackedByteArray` | N | Prepared atlas bank index for the visual family |
| `object_variant` | `PackedByteArray` | N | Atlas frame / animation view variant |
| `object_flags` | `PackedByteArray` | N | Reserved; the current emitter writes `0`. It is not collision authority: tree collision is derived from `object_kind == 4` and `tree_collision_records`; small rocks have no collision. |
| `object_tint` | `PackedByteArray` | N | `0..255` presentation tint scalar |
| `object_phase` | `PackedByteArray` | N | `0..255` deterministic animation phase |

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
- all `object_*` arrays must have identical length; they are native-generated
  immutable visual object records, consumed by `WorldObjectPacketLayer`, and
  are not persisted as gameplay object state
- the current native boundary requires the full `settings_packed` payload:
  indices `0-8` are mountain settings, and for `world_version >= 9` indices
  `9-14` are `world_width_tiles`, `world_height_tiles`, `ocean_band_tiles`,
  `burning_band_tiles`, `pole_orientation`, and `foundation_slope_bias`;
  Lake Generation L1 extends the same payload additively with
  `LakeGenSettings` indices `15-20`; V2 / L5 adds
  `SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY = 21`; plains tree placement adds
  indices `22-43`; plains small rock placement adds indices `44-70`, so the
  current full field count is `71`
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
- `object_kind == 3` uses static biofield flora atlas bank index `0` for the
  orange spiky plant and index `1` for the small brown seaweed object. Both are
  immutable generated presentation records, not saved gameplay object state.
- `object_kind == 4` is the plains tree family (Iteration 2 of
  `world/plains_trees_presentation.md`): a single tree atlas, `object_variant`
  selects one of 16 frames (`4x4` grid), `object_atlas_index` is `0`, and
  `object_size_px` is the rendered frame box clamped to `<= 254` (byte quantum;
  larger landmark trees stay clamped rather than extending the packet). It is an
  immutable generated presentation record consumed by `WorldObjectPacketLayer`
  on the shared mid-layer depth ladder, not saved gameplay object state. From
  Iteration 3 tree trunks expose chunk-scoped static collision on the obstacle
  layer (shape owners on one body per chunk, not one body per tree).
- For `world_version >= 53`, the native object packet adds `object_kind == 4`
  (plains trees) with the same plains-ground placement and mountain-edge
  clearance as the other object families.
- For `world_version >= 55`, plains tree placement additionally requires the
  visual grass field (`grass_scatter::sample_grass_density >= 0.40` — the same
  `sample_fields` formula that paints the ground and scatters tufts), so trees
  grow only on visibly grassy ground, not bare dirt or rock patches. The grass
  field params in `world_core.cpp` tree constants mirror the single authored
  source `data/terrain/material_sets/plains_ground_material_set.tres` and must
  be kept in sync with it.
- For `world_version >= 60`, plains tree density, grid, spacing, size tiers,
  grass threshold, and mirrored grass-field sampling params are read from the
  saved `worldgen_settings.plains_trees` profile via native
  `settings_packed[22..43]`.
- For `world_version >= 61`, the native object packet no longer emits the
  historical stone/rock object families `1`, `5`, and `6`. This changes
  deterministic visual object placement only; packet fields and save payload
  shape stay unchanged.
- For `world_version >= 62`, the native object packet may emit visual-only
  `object_kind == 7` small rocks. `object_variant` selects a layered asset
  directory from `assets/sprites/decor/plains/layered_small_rocks`, and
  `object_size_px` is interpreted as visible rock width. The runtime creates no
  collision, no wind mask, and no save identity for these records.
- For `world_version >= 63`, those small rocks are generated as clustered
  edge/patch groups rather than independent scatter-grid singletons.
- For `world_version >= 61`, native object packet emission keeps local
  mountain-edge clearance for living flora, spiky flora, trees, and small rocks
  so batched decor does not spawn under the organic runtime mountain mask.
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

### `MountainContourDebugResult`

Returned by debug-only native
`WorldCore.build_mountain_contour_debug(solid_halo, chunk_size, tile_size_px)`.

```text
{
  "vertices": PackedVector2Array,
  "indices": PackedInt32Array,
  "solid_sample_count": int,
  "halo_side": int,
}
```

Current code notes:
- `solid_halo` is a compact `(chunk_size + 2)^2` `PackedByteArray` built from
  the loaded effective mountain solid state (`base + diff`) and includes a
  one-tile halo for loaded seam neighbours
- `vertices` and `indices` are derived debug mesh data only; they are not
  authoritative terrain, walkability, collision, navigation, or save data
- diagonal-only contact is resolved as separate filled pieces by the native
  marching-squares helper, so it does not create a face-connected solid
  component
- this result is not part of `ChunkPacketV1` and must not be persisted

### `MountainHaloMaskResult`

Returned by native
`WorldCore.build_mountain_halo_mask(solid_halo, chunk_size, tile_size_px, pixels_per_tile, origin_world_x, origin_world_y)`.

```text
{
  "mask": PackedByteArray,
  "width": int,
  "height": int,
  "step_px": float,
  "solid_sample_count": int,
  "halo_side": int,
  "halo_radius_tiles"?: int,
  "pixels_per_tile"?: int,
}
```

`WorldChunkPacketBackend` appends worker metadata to completed halo-mask
results. For `mask_purpose = "mountain"` requests that carry a non-empty
`closed_halo` (chunks with at least one excavated mountain-owned halo cell),
the worker performs a second `build_mountain_halo_mask` call over the
ownership-only halo and attaches the derived construction-roof fields:

```text
{
  ...MountainHaloMaskResult,
  "success": bool,
  "epoch": int,
  "revision": int,
  "reason": StringName,
  "mask_purpose": StringName,      # "mountain" or "terrain_edge"
  "target_chunk": Vector2i,
  "mask_origin_world": Vector2,
  "queued_msec": int,
  "worker_started_msec": int,
  "worker_elapsed_ms": int,
  "queue_wait_ms": int,
  "request_to_complete_ms": int,
  "closed_roof_mask"?: PackedByteArray,  # immutable pre-dig roof mask C; same
                                         # width/height/step as "mask"; present
                                         # only when the request carried a
                                         # closed_halo (dug mountain chunks)
  "dug_halo"?: PackedByteArray,          # 0/1 tile halo of excavated
                                         # mountain-owned cells, echoed from the
                                         # request for selector sizing
  "sky_exposure_mask"?: PackedByteArray, # L8 natural-light acceptance field;
                                         # same width/height/step as "mask"
  "sky_exposure_reach_samples"?: int,    # current tuning: 1 tile * pixels_per_tile
  "sky_exposure_source_sample_count"?: int,
  "sky_exposure_worker_elapsed_ms"?: float,
}
```

Current code notes:
- `mask.size()` must equal `width * height` for `success = true`
- when present, `closed_roof_mask.size()` must also equal `width * height`
  for `success = true`, and `dug_halo.size()` must equal
  `halo_side * halo_side`; `sky_exposure_mask.size()` must equal
  `width * height`
- `step_px = tile_size_px / pixels_per_tile`
- invalid input returns an empty mask with zero dimensions
- the mask, `closed_roof_mask`, `dug_halo`, and `sky_exposure_mask` are derived runtime
  presentation/cache data; they are not packet truth, terrain, walkability,
  navigation, or save data
- `mask_purpose = "terrain_edge"` reuses the same shape for dry-terrain edge
  presentation masks and never carries the construction-roof fields

### `MountainSkylightExposureResult`

Returned by native
`WorldCore.build_mountain_skylight_exposure(closed_roof_mask, live_mask, width, height, step_px, reach_samples)`.

```text
{
  "sky_exposure_mask": PackedByteArray, # width * height; 0 dark .. 255 open
  "width": int,
  "height": int,
  "step_px": float,
  "reach_samples": int,
  "source_sample_count": int,
}
```

Current code notes:
- input shapes must match `width * height`; invalid dimensions, shape, step, or
  reach return an empty `Dictionary`
- the traversable domain is derived from immutable closed roof `C` minus live
  remaining mass `V`; a real source requires cardinal contact with open `C`
- propagation is bounded to `reach_samples`; diagonal smoothing requires both
  adjacent cardinal samples to be traversable, so diagonal-only corners do not
  leak
- the result is deterministic derived presentation data, never part of
  `ChunkPacketV1` and never persisted

### `MountainPlateauRasterImageResult`

Returned by native
`WorldCore.build_mountain_plateau_raster_image(packets, target_chunk, preset, top_image, face_image)`.
This is an authoring/probe and legacy runtime raster helper. The result shape
has a broad preset-dependent debug tail; the stable consumed core is:

```text
{
  "ready": bool,
  "success"?: bool,
  "mountain_image"?: Image,
  "mountain_normal_image"?: Image,
  "image"?: Image,
  "normal_image"?: Image,
  "ground_image"?: Image,
  "ground_normal_image"?: Image,
  "hit_mask": PackedByteArray,
  "hit_mask_width": int,
  "hit_mask_height": int,
  "hit_mask_origin_world": Vector2,
  "hit_mask_step_px": float,
  "hit_mask_threshold": float,
  "hit_mask_solid_pixel_count": int,
  "top_mask"?: PackedByteArray,
  "top_mask_width"?: int,
  "top_mask_height"?: int,
  "top_mask_origin_world"?: Vector2,
  "top_mask_step_px"?: float,
  "render_origin_world": Vector2,
  "render_size_world": Vector2,
  "mountain_tile_count": int,
  "target_mountain_tile_count"?: int,
  "bounds_position": Vector2i,
  "bounds_size": Vector2i,
  "sample_step_px": float,
  "render_padding_tiles": int,
  "image_width": int,
  "image_height": int,
  "normal_ready": bool,
  "normal_image_width"?: int,
  "normal_image_height"?: int,
  "normal_pixel_count": int,
  "native": bool,
  "timing_total_ms": float,
}
```

`WorldChunkPacketBackend` appends worker metadata to completed raster results:

```text
{
  ...MountainPlateauRasterImageResult,
  "epoch": int,
  "revision": int,
  "raster_purpose": StringName,
  "target_chunk": Vector2i,
  "source_chunks": Array,
  "source_chunk_count": int,
  "queued_msec": int,
  "worker_started_msec": int,
  "worker_elapsed_ms": int,
  "queue_wait_ms": int,
  "request_to_complete_ms": int,
}
```

Current code notes:
- worker-side `success` is normalized from native `ready`
- image keys are optional and depend on preset flags (`runtime_mountain_only`,
  normal output, ground output, top-mask output)
- timing and tuning keys beyond `timing_total_ms` are debug/probe data; they
  are intentionally not part of the stable consumed core in this draft
- this result is derived presentation/probe data only; it is not
  `ChunkPacketV1`, save state, authoritative terrain, walkability, collision,
  or navigation data

### `ObjectPresentationBufferResult`

Returned by native
`WorldCore.build_object_presentation_buffers(object_kind, object_local_x_px_q4, object_local_y_px_q4, object_size_px, object_atlas_index, object_variant, object_flags, object_tint, object_phase, tree_metrics, rock_metrics, params)`.
Governing spec:
`docs/02_system_specs/world/world_object_placement_v0.md`.

```text
{
  "tree_atlas_bucket_buffers": Array,      # DEPTH_STRIPES_PER_CHUNK (64)
  "rock_atlas_bucket_buffers": Array,      # DEPTH_STRIPES_PER_CHUNK (64)
  "living_flora_bucket_buffers": Array,    # 64 stripes when count > 0;
                                             # empty Array when count == 0
  "living_flora_shadow_buffer": PackedFloat32Array,
                                             # one raw contact-shadow instance
                                             # per living-flora instance
  "spiky_flora_atlas_bucket_buffers": Array,
                                             # atlas-major Array[2][64] when
                                             # count > 0; empty when count == 0
  "spiky_flora_atlas_bank_count": int,     # 2 when present, otherwise 0
                                             # PackedFloat32Array entries; each
                                             # instance is 12 floats:
                                             # row0 = (x.x, y.x, 0, origin.x),
                                             # row1 = (x.y, y.y, 0, origin.y),
                                             # color = (atlas_variant/255,
                                             #          tint, phase, alpha)
  "tree_collision_records": PackedFloat32Array,
                                             # flat triples (local_x, local_y,
                                             # radius_px), one per tree
  "object_count": int,
  "tree_instance_count": int,
  "rock_instance_count": int,
  "living_flora_count": int,               # presented count after policy
  "spiky_flora_count": int,                # presented count after policy
  "living_flora_record_count": int,        # canonical packet count
  "spiky_flora_record_count": int,         # canonical packet count
  "suppressed_instance_count": int,        # known flora disabled by prepared
                                             # source policy; not an error
  "ignored_instance_count": int,
  "buffer_float_count": int,
  "payload_bytes": int,                    # buffer_float_count * 4, including
                                             # collision records; O(1) warm-cache
                                             # accounting
  "error": String,                          # present only on contract violation

  # Added by WorldChunkPacketBackend after native compute:
  "success"?: bool,
  "message"?: String,
  "epoch"?: int,
  "revision"?: int,
  "catalog_generation"?: int,
  "target_chunk"?: Vector2i,
  "queued_msec"?: int,
  "worker_started_msec"?: int,
  "worker_elapsed_ms"?: int,
  "queue_wait_ms"?: int,
  "request_to_complete_ms"?: int,
}
```

Current contract notes:

- the nine `object_*` inputs are the immutable canonical packet arrays and must
  have identical lengths; this result is derived presentation/loaded-collision
  data, never a new `ChunkPacketV1` field and never save data;
- native computes `buffer_float_count` and `payload_bytes` from its accepted
  family counters:
  `12 * (tree + rock + spiky + 2 * living) + 3 * tree`, with
  `payload_bytes == buffer_float_count * 4`. Warm-cache admission may use that
  trusted producer metadata in O(1). Before upload or commit,
  `WorldObjectPacketLayer` accumulates actual packed-array sizes in the existing
  phased structural validation and requires exact equality with both fields;
  ABI drift is rejected, not cached as a committed presentation;
- `tree_metrics` and `rock_metrics` are boot-prepared flat records with stride
  `5`: `(frame_width, frame_height, anchor_x, anchor_y,
  fixed_tree_scale_or_rock_visible_width)`. They reproduce the authored layered
  asset transforms without file/path/JSON/resource access in the worker;
- `params` is a 20-float layout owned by
  `object_presentation::ParamIndex`: local-pixel quantum, depth-stripe pixels,
  depth-stripe count, tree collision radius scale/min/max, then the authored
  classic-decor stripe anchor, spiky atlas-bank count, living/spiky alpha, and
  living contact-shadow scales/minima/alpha, followed by living/spiky prepared-
  source enable flags. The script-side catalog owns these values so native code
  does not carry a second drifting copy of visual tuning;
- quantized roots decode at the centre of their `q4` cell
  (`byte * quantum + quantum * 0.5`), matching the canonical packet consumer;
- tree and rock variants are mapped to the prepared atlas catalog modulo its
  declared metric count. `color.r` stores that mapped atlas frame, not an asset
  path and not an unbounded raw packet variant;
- living and spiky flora retain the exact legacy atlas transform/color contract:
  centred square quads, depth stripe from `root_y + size * 0.45`, living alpha
  `0.96`, spiky alpha `0.98`, and one living contact-shadow raw buffer using the
  authored `0.42/0.13/0.32` scale/offset recipe. Spiky atlas indices are checked
  against the prepared two-bank contract instead of silently dropping records;
- optional flora bucket tables are allocated lazily. A zero-count result carries
  empty flora arrays rather than 192 empty packed stripe arrays, so disabled
  families do not inflate every live/warm chunk payload;
- enable flags are derived from the actually prepared runtime sources, not just
  placement constants. A known flora record with no prepared source increments
  `suppressed_instance_count`, remains included in canonical `object_count`, but
  does not increment the presented family count or allocate buffers. Therefore
  current production policy (`living/spiky` sources disabled) preserves the
  existing visual output and cannot turn otherwise valid chunks into permanent
  object-presentation failures. `ignored_instance_count` remains reserved for
  unknown family ids and is rejected by the consumer;
- the native call runs on a worker-local `WorldCore`. Only after main-thread
  `epoch + revision + catalog_generation` and exact structural validation may
  `WorldObjectPacketLayer` stage reusable `MultiMesh` buffers and chunk-scoped
  tree collision shapes;
- main-thread flora apply consumes at most the configured number of non-empty
  raw buffers per scheduler slice, uses pooled stripe slots, and remains hidden
  in the same atomic object transaction until trees, collisions, both flora
  families, and small rocks are all staged;
- depth bucket is derived from the object's ground/root Y, so atlas anchor
  offsets do not change player-relative ordering;
- source channel atlases and shared materials are boot-prepared. The result
  contains no `Texture`, `Material`, `Mesh`, `Node`, or other scene/GPU object;
- an `error` key means the input/catalog contract was violated. Consumers must
  reject it explicitly rather than run a hidden GDScript packing fallback. The
  runtime retries the same current revision at most twice with a delay; malformed
  completed payloads follow the same bounded failure path instead of spinning
  the visual queue.

### `GrassScatterBufferResult`

Returned by native
`WorldCore.build_grass_scatter_buffer(seed, chunk_coord, terrain_ids, lake_flags, mountain_halo, mountain_halo_radius_tiles, params)`.
Governing spec:
`docs/02_system_specs/world/wind_and_grass_scatter_presentation.md`.

`WorldChunkPacketBackend.queue_grass_scatter_request(...)` preserves the
existing explicit-halo call shape and optionally accepts a final
`halo_packets_3x3` worker input. The two legal modes are:

- non-empty `mountain_halo`: use the explicit packed halo and ignore the
  optional packet window
- empty `mountain_halo` plus exactly nine row-major `(-1,-1)..(1,1)` packet
  envelopes: worker-local `WorldCore.build_chunk_halo_fields(...)` derives
  `remaining_halo`, then the same worker calls `build_grass_scatter_buffer`

Each present envelope is a shallow immutable packet snapshot containing
`terrain_ids`, `walkable_flags`, `mountain_id_per_tile`, `mountain_flags`, and
`lake_flags`; each packed channel has exactly `CHUNK_SIZE * CHUNK_SIZE` cells.
A finite north/south boundary occupies its fixed slot as
`{ "halo_source_present": false }`. The queue owns shallow copies of the outer
array and dictionaries but retains the packed channels by ref-counted handle;
producer mutation before completion violates the immutable-owner contract.
Malformed window count/type/channel shapes produce one failed completion and
never enter a script fallback or retry loop inside the backend.

```text
{
  "bucket_buffers": Array,                 # DEPTH_STRIPES_PER_CHUNK (64)
                                           # PackedFloat32Array entries, one per
                                           # chunk-local depth-ladder stripe;
                                           # 12 floats per instance:
                                           # row0 = (x.x, y.x, 0, origin.x),
                                           # row1 = (x.y, y.y, 0, origin.y),
                                           # color = (frame/255, tint, phase, alpha)
  "instance_count": int,                   # total across all buckets
  "directional_shadow_buffer": PackedFloat32Array,
                                           # exact tuft transforms flattened
                                           # from bucket_buffers by native;
                                           # 12 floats per instance, used as
                                           # one fixed-z shadow batch when the
                                           # authored profile is full LOD
  "shadow_buffer": PackedFloat32Array,     # contact-shadow blobs under larger
                                           # tufts (12-float MultiMesh layout),
                                           # one flat layer below the grass
                                           # ladder; color.a = blob opacity
  "spore_buffer": PackedFloat32Array,      # sparse glowing motes above strong
                                           # orange_region (12-float layout),
                                           # color = (phase, drift_seed, 0, 1)
  "truncated_count": int,                  # present only when the authored
                                           # instance cap dropped candidates
  "buffer_float_count": int,               # exact float count across bucket,
                                           # directional-shadow, contact-shadow,
                                           # and spore packed arrays
  "payload_bytes": int,                    # buffer_float_count * 4; O(1)
                                           # warm-cache byte accounting
  "non_empty_bucket_count": int,           # non-empty albedo depth stripes
  "error": String,                         # present only on contract violation

  # Added by WorldChunkPacketBackend after native compute:
  "success"?: bool,
  "message"?: String,
  "epoch"?: int,
  "revision"?: int,
  "target_chunk"?: Vector2i,
  "mountain_halo_source"?: StringName,    # `explicit` or `worker_3x3`
  "mountain_halo_derived"?: bool,         # true only after successful native
                                           # worker derivation
  "mountain_halo_derivation_ms"?: int,    # bounded worker-local halo phase;
                                           # included on success and failure
  "queued_msec"?: int,
  "worker_started_msec"?: int,
  "worker_elapsed_ms"?: int,
  "queue_wait_ms"?: int,
  "request_to_complete_ms"?: int,
}
```

Current code notes:
- `params` is a packed float layout owned by `grass_scatter::ParamIndex`
  (`gdextension/src/grass_scatter.h`, `PARAM_COUNT = 40`): chunk geometry, the
  shared ground field params (`grass/orange/rock` scale+coverage mirrored from
  the ground material `sampling_params`), grass-only authored knobs (grid, cap,
  sizes, density/tint/alpha curves), and the plains-ground-composition fields
  appended at the end (`PARAM_MACRO_MASS_SCALE_PX/STRENGTH`,
  `PARAM_PATH_SCALE_PX/WIDTH/WARP_PX/STRENGTH`). Macro-mass enters the gridded
  `sample_fields`; the path term is evaluated pointwise per-candidate
  (`grass_scatter::sample_path`), not through the field grid. New params are
  appended so existing indices stay stable. Governing spec:
  `docs/02_system_specs/world/plains_ground_field_composition.md`
- the buffer is presentation-only derived data. The legacy fractional-LOD path
  assigns it directly to chunk grass `MultiMesh` resources; the full-LOD path
  retains it as one immutable contributor to native page merge. It is never
  persisted and never enters `ChunkPacketV1`
- the native call executes on a worker-local `WorldCore`; scene objects and GPU
  resources are touched only after the main thread validates `epoch + revision`
- placement is deterministic for the same seed, chunk, inputs, and params;
  origins are chunk-local pixels. The legacy layer sits at the chunk origin;
  full-LOD page merge changes only transform `origin.x` by
  `slot * chunk_size_px`
- candidates reject mountain wall/foot terrain within the authored
  mountain-edge clearance (`GRASS_MOUNTAIN_CLEARANCE_PX`, `grass_scatter.cpp`)
  before instance emission, so presentation-only grass tufts cannot appear
  under the organic runtime mountain mask. The clearance check reads
  `mountain_halo` — a per-tile solid byte array, `halo_side x halo_side`
  (`halo_side = chunk_size_tiles + 2*mountain_halo_radius_tiles`), the SAME
  `remaining_halo` layout derived from the fixed 3x3 neighbouring packet
  window for mountain presentation — NOT the chunk's own `terrain_ids` alone.
  The backend may pass an existing explicit halo or derive it through
  worker-local `build_chunk_halo_fields` immediately before scatter packing.
  A chunk-local-only check (pre-2026-07-04) went blind for candidates near a
  chunk seam whose nearest mountain tile sat in the *neighbouring* chunk,
  regardless of clearance distance. The
  clearance test itself scans every halo tile within `clearance_px` (a filled
  disk at tile granularity), not a fixed ring of sample points at
  `clearance_px` — a ring can jump clean over a mountain feature thinner than
  the sampled radius, and does so more often at *larger* radii (verified by
  `tools/tmp_grass_mountain_overlap_probe.gd`, 2026-07-04, since deleted)
- buckets follow the shared mid-layer depth ladder
  (`WorldRuntimeConstants.DEPTH_STRIPE_PX` / `DEPTH_STRIPES_PER_CHUNK`,
  mirrored as `grass_scatter::DEPTH_STRIPE_PX/DEPTH_STRIPES_PER_CHUNK`): the
  bucket index is the chunk-local stripe of the tuft root; the consumer
  assigns stripe z relative to the player anchor (southern overdraws
  northern, no periodic wrap)
- inside each bucket instances are importance-ordered (large tufts first,
  small detail last): consumers may trim each bucket's tail via
  `MultiMesh.visible_instance_count` for zoom LOD without rebuilding;
  trimming order is part of this contract
- `directional_shadow_buffer` contains exactly `instance_count * 12` floats and
  is the concatenation of the finalized stripe buckets in stripe order. It is
  worker-produced derived data: the main thread performs one bounded raw
  `MultiMesh.buffer` assignment and never flattens instance arrays in GDScript.
  For the checked-in full-LOD profile this array is a page contributor; native
  page merge rebases/concatenates it into one fixed-z batch per page. A profile
  whose authored LOD envelope permits `visible_instance_count < instance_count`
  keeps the legacy per-stripe shadow path so hidden tufts cannot leave orphan
  shadows. The mode is selected from profile data before publication, not in
  response to zoom.
- tufts inside strong `orange_region` pick frames from the biofield atlas
  bank (`orange_frame_base..+orange_frame_count`), gated by the authored
  `orange_bank_low/high` response window
- `shadow_buffer` and `spore_buffer` are additional presentation-only
  MultiMesh layers (contact shadows below the ladder, biofield spores above
  the grass); both are derived, never persisted, and gated by authored
  params (`shadow_*`, `spore_*` in `grass_scatter::ParamIndex`)
- native `buffer_float_count` includes every returned float in
  `bucket_buffers`, `directional_shadow_buffer`, `shadow_buffer`, and
  `spore_buffer`; `payload_bytes == buffer_float_count * 4`. Warm-cache
  admission uses this O(1) producer metadata and must not rescan 64 arrays.
- an `error` key means the caller violated the input contract; consumers must
  fail explicitly instead of masking it

### `GrassRenderPageBufferResult`

Returned by native
`WorldCore.build_grass_render_page_buffer(contributors, page_width_chunks, chunk_size_px)`.
Governing spec:
`docs/02_system_specs/world/wind_and_grass_scatter_presentation.md`,
Iteration 7.

The pure worker input contains at most four shallow immutable contributor
envelopes. Each envelope references one already validated
`GrassScatterBufferResult` without copying or traversing its packed floats in
GDScript:

```text
{
  "slot": int,                              # unique 0..page_width_chunks-1
  "revision": int,                          # exact chunk scatter revision
  "bucket_buffers": Array[PackedFloat32Array; 64],
  "directional_shadow_buffer": PackedFloat32Array,
  "shadow_buffer": PackedFloat32Array,
  "spore_buffer": PackedFloat32Array,
}
```

Native output:

```text
{
  "bucket_buffers": Array[PackedFloat32Array; 64],
  "directional_shadow_buffer": PackedFloat32Array,
  "shadow_buffer": PackedFloat32Array,
  "spore_buffer": PackedFloat32Array,
  "contributor_revisions": PackedInt64Array, # page_width_chunks entries;
                                               # -1 for an absent slot
  "contributor_mask": int,
  "instance_count": int,
  "directional_shadow_count": int,
  "shadow_count": int,
  "spore_count": int,
  "non_empty_bucket_count": int,
  "buffer_float_count": int,
  "payload_bytes": int,
  "error": String,                           # contract violation only

  # Added by WorldChunkPacketBackend after native compute:
  "success"?: bool,
  "message"?: String,
  "epoch"?: int,
  "page_revision"?: int,
  "page_coord"?: Vector2i,
  "queued_msec"?: int,
  "worker_started_msec"?: int,
  "worker_elapsed_ms"?: int,
  "queue_wait_ms"?: int,
  "request_to_complete_ms"?: int,
}
```

Contract rules:

- the production full-LOD page is fixed at `4 x 1` chunks; the helper accepts
  widths `1..4` so partial/test envelopes remain structurally valid
- contributors are emitted in ascending slot order regardless of request order
- native changes only 2D transform `origin.x` (float index `3`) by
  `slot * chunk_size_px`; basis, Y, color, per-stripe importance order, and all
  other floats are copied exactly
- all contributors share the same chunk Y row, so the 64 local bucket indices
  remain the exact 64 global world-row stripes of the page
- `payload_bytes == buffer_float_count * 4`; the main thread must use this
  producer metadata instead of rescanning packed arrays
- this result is transient derived presentation, never canonical packet truth,
  gameplay state, collision, or save data
- queued requests coalesce by `(epoch, page_coord)`. Runtime accepts a result
  only when its `page_revision` and every required contributor revision still
  match; stale worker completions never reach GPU staging. Required contributors
  are `active | prestage` whenever that reveal mask is non-zero, otherwise the
  complete source-only mask. Already exact optional source contributors may join
  a reveal merge, but a later optional source arrival does not force a partial
  page rebuild
- malformed, duplicate-slot, or misaligned contributor payloads fail explicitly
  through `error`; no GDScript merge fallback is allowed

## Not Currently Confirmed

The current code still does not confirm packet fields for future biome,
placement, roof-runtime, entrance-runtime, drought, or environment layers.
The complete preset-specific debug tail of `MountainPlateauRasterImageResult`
is also intentionally not approved here; only the stable consumed core above is
documented.
