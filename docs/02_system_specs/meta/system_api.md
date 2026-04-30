---
title: System API
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 1.8
last_updated: 2026-04-30
related_docs:
  - ../README.md
  - commands.md
  - event_contracts.md
  - packet_schemas.md
  - save_and_persistence.md
  - multiplayer_authority_and_replication.md
  - ../world/river_generation_v1.md
---

# System API

## Purpose

This document lists a minimal set of code-confirmed external surfaces for core
systems.

Its job is to answer:

- which methods are currently exposed as callable entrypoints
- which state is currently exposed for read access
- which helpers are not documented as safe entrypoints

## Scope

This pass is intentionally narrow.

It covers only the minimal core set confirmed in code during this pass:

- `EventBus`
- `TimeManager`
- `ItemRegistry`
- `SaveManager`
- `PlayerAuthority`
- `CommandExecutor`
- `BuildingSystem`
- `WorldCore`
- `WorldStreamer`
- `EnvironmentOverlay`
- River Generation V1-R15 chunk packet / current-water overlay boundary and
  `RiverGenSettings`

## Out of Scope

- future API design outside approved inactive boundaries
- undocumented systems outside the minimal pass
- private helper methods and backing dictionaries
- any contract not directly confirmed in code

## Reading Rules

- Every entry below is backed by current code.
- Underscore-prefixed methods and fields are treated as internal by current
  code convention and are not documented here as safe entrypoints.
- If a system or method is absent here, it was not confirmed in this minimal
  pass.

## Confirmed Core Surfaces

### EventBus

Owner file: `core/autoloads/event_bus.gd`

Role:
- global signal hub for cross-system communication

Confirmed public surface:
- signal declarations on the autoload singleton

Read / subscribe path:
- other systems connect to `EventBus.<signal>`

Mutation path:
- signal emission ownership is documented per event in `event_contracts.md`

Not documented here as safe entrypoints:
- direct ownership of gameplay state
- any helper methods, because none are defined on the current singleton

### TimeManager

Owner file: `core/autoloads/time_manager.gd`

Role:
- authoritative runtime time state for hour, day, season, and day phase

Confirmed readable state:

| Surface | Kind | Notes |
|---|---|---|
| `balance` | variable | Loaded from `res://data/balance/time_balance.tres` |
| `current_hour` | variable | Current in-game hour as `float` |
| `current_day` | variable | Current in-game day as `int` |
| `current_season` | variable | Current season enum value |
| `current_time_of_day` | variable | Current day-phase enum value |
| `get_hour()` | method | Whole hour |
| `get_day_progress()` | method | `0.0..1.0` day progress |
| `get_sun_progress()` | method | Normalized sun progress |
| `get_sun_angle()` | method | Shadow angle in radians |
| `get_shadow_length_factor()` | method | Derived shadow-length factor |
| `is_time_paused()` | method | Pause query |
| `get_time_scale()` | method | Time scale query |

Confirmed mutation entrypoints:

| Surface | Kind | Notes |
|---|---|---|
| `reset_for_new_game()` | method | Resets to default start state |
| `restore_persisted_state(hour, day, season)` | method | Save/load restore path |
| `set_paused(paused)` | method | Pause toggle |
| `set_time_scale(scale)` | method | Runtime time scale |

Not documented here as safe entrypoints:
- `_calculate_speed()`
- `_apply_authoritative_time_state()`
- `_advance_time()`
- direct writes to the public `current_*` fields

Current code note:
- the code-confirmed state-transition paths that also emit sync events are the
  documented mutation methods above plus internal helpers

### ItemRegistry

Owner file: `core/autoloads/item_registry.gd`

Role:
- central registry for item, recipe, building, and resource-node data

Confirmed read entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `get_item(id: String)` | `ItemData` | Returns item or `null` |
| `get_recipe(id: String)` | `RecipeData` | Lazy-loads recipes |
| `get_all_recipes()` | `Array[RecipeData]` | Snapshot array |
| `get_building(id: StringName)` | `BuildingData` | Returns building or `null` |
| `get_all_buildings()` | `Array[BuildingData]` | Snapshot array |
| `get_resource_node(id: StringName)` | `ResourceNodeData` | Returns node or `null` |
| `get_resource_node_by_deposit(deposit_type: int)` | `ResourceNodeData` | Deposit lookup |
| `get_all_resource_nodes()` | `Array[ResourceNodeData]` | Snapshot array |

Confirmed mutation entrypoints:

| Surface | Input | Notes |
|---|---|---|
| `register_item(item: ItemData)` | `ItemData` | No-op on invalid item |
| `register_recipe(recipe: RecipeData)` | `RecipeData` | No-op on invalid recipe |
| `register_building(building_data: BuildingData)` | `BuildingData` | No-op on invalid building |
| `register_resource_node(resource_node: ResourceNodeData)` | `ResourceNodeData` | Also indexes by deposit type |

Not documented here as safe entrypoints:
- `_items`
- `_recipes`
- `_buildings`
- `_resource_nodes`
- `_resource_nodes_by_deposit`
- all `_load_*` helpers

### SaveManager

Owner file: `core/autoloads/save_manager.gd`

Role:
- orchestration facade for save/load scenarios

Confirmed readable state:

| Surface | Kind | Notes |
|---|---|---|
| `current_slot` | variable | Current save slot name |
| `is_busy` | variable | Save/load busy flag |
| `get_save_list()` | method | Returns `Array[Dictionary]` |
| `save_exists(slot_name: String)` | method | Checks `meta.json` presence |
| `consume_pending_load_slot()` | method | Returns and clears pending slot |

Confirmed mutation entrypoints:

| Surface | Kind | Notes |
|---|---|---|
| `save_game(slot_name: String = "")` | method | Writes save files |
| `load_game(slot_name: String)` | method | Reads and applies save files |
| `delete_save(slot_name: String)` | method | Deletes slot directory |
| `request_load_after_scene_change(slot_name: String)` | method | Stores pending slot |
| `clear_pending_load_request()` | method | Clears pending slot |

Not documented here as safe entrypoints:
- `_resolve_slot_name()`
- direct calls into `SaveCollectors`, `SaveAppliers`, or `SaveIO` when the
  orchestration surface is sufficient

### PlayerAuthority

Owner file: `core/autoloads/player_authority.gd`

Role:
- single lookup point for the local player and player list

Confirmed read entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `get_local_player()` | `Player` | May return `null` |
| `get_all_players()` | `Array[Player]` | Current code scans group `player` |
| `get_local_player_position()` | `Vector2` | Returns `Vector2.ZERO` if unavailable |

Confirmed mutation / maintenance entrypoints:

| Surface | Notes |
|---|---|
| `clear_cache()` | Clears cached local-player reference |

Not documented here as safe entrypoints:
- direct `get_tree().get_nodes_in_group("player")[0]` lookups in new code

### CommandExecutor

Owner file: `core/systems/commands/command_executor.gd`

Role:
- executes `GameCommand` instances and normalizes their dictionary results

Confirmed mutation entrypoint:

| Surface | Input | Return |
|---|---|---|
| `execute(command: GameCommand)` | `GameCommand` | Normalized `Dictionary` result |

Normalization confirmed in code:
- inserts `success: false` if missing
- inserts `message_key: ""` if missing
- inserts `message_args: {}` if missing

Not documented here as safe entrypoints:
- reliance on command result fields that are not documented in `commands.md`

### BuildingSystem

Owner file: `core/systems/building/building_system.gd`

Role:
- facade for building placement, removal, room recalculation, and persistence

Confirmed readable entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `world_to_grid(world_pos: Vector2)` | `Vector2i` | World to grid conversion |
| `grid_to_world(grid_pos: Vector2i)` | `Vector2` | Grid to world conversion |
| `is_cell_indoor(grid_pos: Vector2i)` | `bool` | Indoor query |
| `get_grid_size()` | `int` | Placement grid size |
| `has_pending_room_recompute()` | `bool` | Dirty-room work query |
| `has_building_at(grid_pos: Vector2i)` | `bool` | Occupancy query |
| `get_building_node_at(grid_pos: Vector2i)` | `Node2D` | Node lookup |
| `can_place_selected_building_at(world_pos: Vector2)` | `bool` | Placement validation |
| `save_state()` | `Dictionary` | Building persistence payload |

Confirmed mutation entrypoints:

| Surface | Notes |
|---|---|
| `set_selected_building(building: BuildingData)` | Selects active building type |
| `load_state(data: Dictionary)` | Restores persisted buildings and recomputes rooms |
| `place_selected_building_at(world_pos: Vector2)` | Attempts placement and returns a result dictionary |
| `remove_building_at(world_pos: Vector2)` | Attempts removal and returns a result dictionary |

Current code note:
- `_execute_place_command()` and `_execute_remove_command()` prefer
  `CommandExecutor.execute(...)` when a `command_executor` group member exists,
  and fall back to direct method calls when it does not

Not documented here as safe entrypoints:
- `_execute_place_command()`
- `_execute_remove_command()`
- `_create_building_from_persistence()`
- `_clear_buildings_for_persistence()`
- `_walls`
- direct mutation of `indoor_cells`

### WorldCore

Owner files:
- `gdextension/src/world_core.cpp`
- `gdextension/src/world_prepass.cpp`
- `gdextension/src/world_hydrology_prepass.cpp`

Role:
- native deterministic world-generation boundary and owner of the RAM-only
  `WorldPrePass` substrate

Confirmed public native surface:

| Surface | Return | Notes |
|---|---|---|
| `generate_chunk_packets_batch(seed: int, coords: PackedVector2Array, world_version: int, settings_packed: PackedFloat32Array)` | `Array` | Returns one canonical chunk packet per requested coordinate. For `world_version >= 17`, builds/reuses `WorldHydrologyPrePass` internally and emits the hydrology packet fields documented in `packet_schemas.md`; for `world_version >= 18`, it also rasterizes native lakebed / lake shoreline output from `lake_id`; for `world_version >= 19`, it emits delta / estuary widening and controlled split flags; for `world_version >= 20`, lake shorelines, river centerlines, and river widths use organic native rasterization; for `world_version >= 21`, ocean edges may emit native walkable `TERRAIN_SHORE` band output instead of only ocean-floor-adjacent ground edges; for `world_version >= 22`, river rasterization reads native refined whole-path centerline edges through a bounded spatial-index query instead of scanning all river features per chunk; for `world_version >= 23`, river width/depth classification uses refined-edge curvature and post-confluence context, and post-confluence reaches may emit `HYDROLOGY_FLAG_CONFLUENCE`; for `world_version >= 24`, qualifying confluences produce native Y-shaped zones that mark upstream arms and the downstream reach with the existing confluence flag; for `world_version >= 25`, eligible controlled braid splits use native rejoining island-loop geometry while keeping the existing braid split flag; for `world_version >= 26`, lake rasterization uses native basin-contour depth/spill data for shallow rim and deep basin classification; for `world_version >= 27`, ocean rasterization uses native coast distance, shelf depth, and river-mouth influence fields to classify shore, shallow shelf, and deep ocean. |
| `resolve_world_foundation_spawn_tile(seed: int, world_version: int, settings_packed: PackedFloat32Array)` | `Dictionary` | Resolves the V1 foundation spawn tile from the substrate and returns the shape documented as `WorldFoundationSpawnResult` in `packet_schemas.md` |
| `build_world_hydrology_prepass(seed: int, world_version: int, settings_packed: PackedFloat32Array)` | `Dictionary` | Builds or reuses a RAM-only `WorldHydrologyPrePass` snapshot and returns `WorldHydrologyPrePassBuildResult`. Requires extended settings payload with river fields. Does not emit gameplay river terrain. |

Dev-only native surface:

| Surface | Return | Notes |
|---|---|---|
| `get_world_foundation_snapshot(layer_mask: int, downscale_factor: int)` | `Dictionary` | Debug build only; returns the current `WorldPrePass` channel snapshot |
| `get_world_foundation_overview(layer_mask: int, pixels_per_cell: int)` | `Image` | Debug build only; returns a pre-coloured high-resolution overview image. `layer_mask = 0` renders the current realised terrain classes: ground, mountain foot, and mountain wall. The hydro-height layer mask renders the raw `hydro_height` substrate channel as a diagnostic height map. |
| `get_world_hydrology_snapshot(layer_mask: int, downscale_factor: int)` | `Dictionary` | Debug build only; returns the current `WorldHydrologyPrePass` diagnostic snapshot |
| `get_world_hydrology_overview(layer_mask: int, pixels_per_cell: int)` | `Image` | Debug build only; returns a pre-coloured hydrology overview image. The default layer includes river, lake, and ocean overlay pixels over hydrology backing colours; `layer_mask` bit `1 << 6` returns a transparent water-only overlay for the new-game composite overview; for `world_version >= 20`, lake overview pixels use organic shoreline boundaries and river overview pixels use organic meander/width/branch rasterization; for `world_version >= 22`, overview river pixels use the same refined whole-path centerline substrate as chunk rasterization; for `world_version >= 25`, overview river pixels can show the native braid island loop edges from that same substrate; for `world_version >= 26`, lake overview pixels use the same basin-contour threshold as chunk lake rasterization; for `world_version >= 27`, ocean overview pixels may distinguish shallow shelf from deep ocean using native shelf depth. |

Current code notes:
- `settings_packed` for `world_version >= 9` must include the mountain fields
  plus V1 foundation indices `9-14`.
- `build_world_hydrology_prepass(...)` requires the extended V1-R2 settings
  payload with river indices `15-26`.
- `generate_chunk_packets_batch(...)` requires the same extended payload for
  `world_version >= 17`; versions `9..16` keep the foundation-only payload.
- for `world_version >= 10`, native mountain sampling uses
  `worldgen_settings.world_bounds.width_tiles` as its cylindrical X width;
  `world_version == 9` keeps the legacy `65536`-tile mountain sample-width
  compatibility path.
- for `world_version >= 11`, the native `WorldPrePass` substrate uses
  `foundation_coarse_cell_size_tiles = 64`; earlier finite-foundation versions
  used `128`.
- The substrate snapshot is a derived cache owned by `WorldCore`; it is not
  persisted and must not be mutated by script code.
- Preview spawn resolution uses the shared worker wrapper, not a main-thread
  GDScript fallback.
- New-game overview water/composite modes use the same worker wrapper. They
  build/reuse `WorldHydrologyPrePass` in native code and publish
  `get_world_hydrology_overview(...)` as an image or transparent overlay; script
  code must not read the hydrology snapshot arrays to rasterize rivers, lakes,
  or oceans. Composite overview composition uses image operations on the worker
  and publishes one final `Image`.
- `WorldHydrologyPrePass` is a derived cache owned by `WorldCore`; it is not
  persisted. V1-R3B chunk generation reads it internally for riverbed,
  shore/bank/floodplain, ocean sink, and default water-class rasterization.
  V1-R4 also reads `lake_id` for lakebed, lake shoreline / bank, and default
  shallow/deep lake water-class rasterization. V1-R5 uses the existing river
  graph and `RiverGenSettings` values for native delta / estuary widening and
  controlled split packet flags. V1-R8 uses the same snapshot and settings for
  native organic lake shorelines, meandered river raster edges, hydrology
  overview river lines, and dynamic river width modulation. V1-R9 uses the
  same ocean sink mask for native walkable ocean shore band packet output.
  V1-R10 keeps the existing hydrology graph as the skeleton but adds native
  refined centerline edges and a native spatial index inside the RAM-only
  snapshot; neither is persisted or exposed to script as per-tile arrays.
  V1-R11 adds signed curvature and post-confluence classification to those
  native refined edges for chunk width/depth rasterization and diagnostic
  aggregate counts; these remain derived RAM-only data. V1-R12 adds native
  Y-shaped confluence influence weights and aggregate diagnostics to the same
  refined-edge cache. V1-R13 adds native braid island loop edges and aggregate
  diagnostics to that same refined-edge cache; these also remain derived
  RAM-only data. V1-R14 adds native basin-contour lake depth/spill diagnostics
  and oxbow candidate counts; these also remain derived RAM-only data and are
  not packet or save arrays. V1-R15 adds native coast distance, shelf depth, and
  river-mouth influence fields plus aggregate diagnostics; these remain derived
  RAM-only data and are not packet or save arrays.

Not documented here as safe entrypoints:
- direct calls to `world_prepass::*` helpers from script, because they are native
  implementation details behind `WorldCore`
- using dev-only substrate or hydrology snapshot dictionaries as save data or
  gameplay state

River-enabled chunk generation must keep
`generate_chunk_packets_batch(...)` as the hot-path packet boundary. It may read
the native hydrology snapshot/spatial index internally, but script code must not
derive river centerlines, SDFs, water classes, or atlas transitions.

### WorldStreamer

Owner file: `core/systems/world/world_streamer.gd`

Role:
- V0 world runtime orchestrator and current `chunk_manager` compatibility surface

Confirmed readable entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `get_world_seed()` | `int` | Current deterministic world seed |
| `get_world_version()` | `int` | Current canonical world version |
| `save_world_state()` | `Dictionary` | World save payload for `world.json`, including embedded `worldgen_settings.world_bounds`, `worldgen_settings.foundation`, `worldgen_settings.mountains`, `worldgen_settings.rivers` for `world_version >= 17`, optional `water_overlay` explicit overrides, and optional `worldgen_signature` |
| `collect_chunk_diffs()` | `Array[Dictionary]` | Serialized dirty chunk entries |
| `get_chunk_packet(chunk_coord: Vector2i)` | `Dictionary` | Loaded chunk packet or `{}`; read-only world-domain lookup for `MountainResolver` |
| `get_current_water_class_at_tile(tile_coord: Vector2i)` | `int` | Effective current water class for a tile, combining loaded packet default with explicit `EnvironmentOverlay` override when present |
| `get_mountain_cover_sample(world_tile: Vector2i)` | `Dictionary` | Read-only cover sample for one tile: `mountain_id`, `mountain_flags`, `component_id`, `is_opening`, `walkable` |
| `get_mountain_cover_debug_snapshot(world_tile: Vector2i)` | `Dictionary` | Debug-only snapshot including `inside_outside_state`, active component ids, and `roof_layers_per_chunk_max` |
| `is_walkable_at_world(world_pos: Vector2)` | `bool` | Reads `base + diff`; returns `false` while a chunk is not ready |
| `has_resource_at_world(world_pos: Vector2)` | `bool` | Diggable surface query for the current harvest path (`TERRAIN_MOUNTAIN_WALL` and `TERRAIN_MOUNTAIN_FOOT`); returns `true` only when the tile also has an orthogonally exposed walkable face |

Confirmed mutation entrypoints:

| Surface | Notes |
|---|---|
| `initialize_new_world(seed_value: int, settings: MountainGenSettings, world_bounds: WorldBoundsSettings = null, foundation_settings: FoundationGenSettings = null, river_settings: RiverGenSettings = null)` | New-game entrypoint; freezes mountain, finite-bounds, foundation, and river settings into packed/native form and then delegates to `reset_for_new_game(...)` |
| `reset_for_new_game(seed, version)` | Clears runtime state, queues native foundation spawn resolution for `world_version >= 9`, applies the resolved new-game spawn tile to the local player before streaming chunks, and emits `world_initialized` |
| `load_world_state(data: Dictionary)` | Restores `world_seed` / `world_version`, rebuilds `worldgen_settings.world_bounds`, `worldgen_settings.foundation`, `worldgen_settings.mountains`, and `worldgen_settings.rivers` for river-enabled versions from `world.json` (or documented defaults where allowed), and clears runtime state |
| `load_chunk_diffs(entries: Array)` | Loads serialized chunk diffs into `WorldDiffStore` |
| `set_current_water_class_at_tile(tile_coord: Vector2i, water_class: int, reason: StringName = &"manual")` | Sets one explicit local current-water override through `EnvironmentOverlay`; emits `water_overlay_changed` and updates only the bounded loaded packet walkability block |
| `clear_current_water_class_at_tile(tile_coord: Vector2i, reason: StringName = &"manual")` | Clears one explicit local current-water override and restores packet-default water behavior for the bounded loaded packet walkability block |
| `try_harvest_at_world(world_pos: Vector2)` | Single-tile harvest path; converts one nearest qualifying diggable surface tile into its dug state and rejects diagonal-only sealed rock |
| `set_active_mountain_component(mountain_id: int, component_id: int)` | World-domain cover selection surface used by `MountainResolver` to switch between outside state and one active cavity |

Not documented here as safe entrypoints:
- `_streaming_tick()`
- `_worker_loop()`
- direct access to `_chunk_packets`, `_chunk_views`, or `_diff_store`
- direct access to `_water_overlay`
- direct mutation of native packet dictionaries outside the documented methods
- mutation of dictionaries returned by `get_chunk_packet()`

### EnvironmentOverlay

Owner file: `core/systems/world/environment_overlay.gd`

Role:
- authoritative runtime owner for explicit local current-water overrides

Confirmed readable entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `has_water_class_override(tile_coord: Vector2i)` | `bool` | Whether a tile has explicit runtime current-water state |
| `get_effective_water_class(tile_coord: Vector2i, default_water_class: int)` | `int` | Returns explicit override when present, otherwise the packet default |
| `consume_dirty_regions(max_count: int)` | `Array[Rect2i]` | Drains transient aligned `16 x 16` water dirty blocks |
| `apply_to_packet(packet: Dictionary)` | `Dictionary` | Returns a packet copy with overlay-derived `walkable_flags`; does not rewrite `water_class` |
| `apply_dirty_region_to_packet(packet: Dictionary, region: Rect2i)` | `Dictionary` | Recomputes overlay-derived `walkable_flags` only inside the bounded dirty block |
| `save_state()` | `Dictionary` | Optional `world.json.water_overlay` payload with explicit overrides only |

Confirmed mutation entrypoints:

| Surface | Notes |
|---|---|
| `set_water_class_override(tile_coord: Vector2i, water_class: int, reason: StringName = &"manual")` | Sets one explicit override and emits `water_overlay_changed(region, reason)` |
| `clear_water_class_override(tile_coord: Vector2i, reason: StringName = &"manual")` | Clears one explicit override and emits `water_overlay_changed(region, reason)` |
| `load_state(data: Dictionary)` | Restores explicit overrides without enqueuing runtime dirty work |
| `clear_all()` | Clears overrides and transient dirty regions |

Not documented here as safe entrypoints:
- `_overrides_by_chunk`
- `_dirty_regions`
- `_mark_tile_dirty(...)`
- direct mutation of packet `water_class`; the packet array remains the
  seed-derived default current-water class

### World Bounds and Foundation Settings

Owner files:
- `core/resources/world_bounds_settings.gd`
- `core/resources/foundation_gen_settings.gd`

Role:
- data resources for finite cylindrical bounds and V1 foundation settings

Confirmed readable entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `WorldBoundsSettings.for_preset(preset: StringName)` | `WorldBoundsSettings` | Returns `small`, `medium`, or `large` V1 bounds |
| `WorldBoundsSettings.from_save_dict(data: Dictionary)` | `WorldBoundsSettings` | Rebuilds bounds from `world.json` |
| `FoundationGenSettings.for_bounds(world_bounds: WorldBoundsSettings)` | `FoundationGenSettings` | Builds default band settings from saved bounds |
| `FoundationGenSettings.from_save_dict(data: Dictionary, world_bounds: WorldBoundsSettings)` | `FoundationGenSettings` | Rebuilds foundation settings from `world.json` |
| `FoundationGenSettings.write_to_settings_packed(settings_packed: PackedFloat32Array, world_bounds: WorldBoundsSettings)` | `PackedFloat32Array` | Appends V1 foundation indices `9-14` to the native settings packet |

### River Generation Settings

Owner file:
- `core/resources/river_gen_settings.gd`

Role:
- data resource for River Generation V1 settings. V1-R8 uses the same resource
  in new-game setup, Water Sector UI, save/load, preview packing, and
  river-enabled native chunk packet generation.

Confirmed readable entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `RiverGenSettings.write_to_settings_packed(settings_packed: PackedFloat32Array)` | `PackedFloat32Array` | Appends river settings indices `15-26` for `build_world_hydrology_prepass(...)` and `generate_chunk_packets_batch(...)` when `world_version >= 17` |
| `RiverGenSettings.to_save_dict()` | `Dictionary` | Serializes the river settings shape for `worldgen_settings.rivers` |
| `RiverGenSettings.from_save_dict(data: Dictionary)` | `RiverGenSettings` | Rebuilds and clamps settings from a save dictionary |
| `RiverGenSettings.hard_coded_defaults()` | `RiverGenSettings` | Returns code defaults for controlled migrations/fallbacks |
| `RiverGenSettings.compute_signature()` | `String` | Diagnostic SHA1 signature of the settings dictionary |

Default data file:
- `data/balance/river_gen_settings.tres`

Current code note:
- this resource is current for `world_version >= 17`. Missing saved river
  settings on a river-enabled load use an explicit hard-coded default migration
  in code and do not reread the repository `.tres`.
- the new-game Water Sector edits the existing saved settings shape; it does
  not add new save fields or a second river settings owner.
