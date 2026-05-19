---
title: System API
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.6
last_updated: 2026-05-03
related_docs:
  - ../README.md
  - commands.md
  - event_contracts.md
  - packet_schemas.md
  - save_and_persistence.md
  - multiplayer_authority_and_replication.md
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

## Out of Scope

- future API design
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

Role:
- native deterministic world-generation boundary and owner of the RAM-only
  `WorldPrePass` substrate

Confirmed public native surface:

| Surface | Return | Notes |
|---|---|---|
| `generate_chunk_packets_batch(seed: int, coords: PackedVector2Array, world_version: int, settings_packed: PackedFloat32Array)` | `Array` | Returns one canonical chunk packet per requested coordinate; current chunk generation emits ground, mountain, and Lake Generation L2 bed terrain classes and reads the `WorldPrePass` substrate for lake fields. |
| `make_world_preview_patch_image(packet: Dictionary, render_mode: StringName)` | `Image` | Builds a lightweight preview patch image from an existing `ChunkPacketV1`; current modes are terrain, mountain id, and mountain classification. Terrain mode reads ground, mountain, and lake-bed packet terrain ids; it does not generate chunks. |
| `build_mountain_contour_debug(solid_halo: PackedByteArray, chunk_size: int, tile_size_px: int)` | `Dictionary` | Debug-only native marching-squares helper for Mountain Contour Mesh L1. Input is a compact `(chunk_size + 2)^2` solid mask with a one-tile halo; output contains derived `vertices: PackedVector2Array` and `indices: PackedInt32Array`. This is visual/debug data only, not packet truth, save state, collision, or walkability. |
| `resolve_world_foundation_spawn_tile(seed: int, world_version: int, settings_packed: PackedFloat32Array)` | `Dictionary` | Resolves the V1 foundation spawn tile from the substrate and returns the shape documented as `WorldFoundationSpawnResult` in `packet_schemas.md` |

Dev-only native surface:

| Surface | Return | Notes |
|---|---|---|
| `get_world_foundation_snapshot(layer_mask: int, downscale_factor: int)` | `Dictionary` | Debug build only; returns the current `WorldPrePass` channel snapshot |
| `get_world_foundation_overview(layer_mask: int, pixels_per_cell: int)` | `Image` | Debug build only; returns a pre-coloured high-resolution overview image. `layer_mask = 0` renders the current realised terrain classes: ground, mountain foot, mountain wall, shallow lake bed, and deep lake bed. The foundation-height layer mask renders the raw `foundation_height` substrate channel as a diagnostic height map. |

Current code notes:
- `settings_packed` for `world_version >= 9` must include the mountain fields
  plus V1 foundation indices `9-14`, Lake Generation L1/L2 indices `15-20`,
  and Lake Generation V2+ `connectivity` at index `21` (`22` fields total).
- the active pre-alpha save/load policy accepts only the current
  `WorldRuntimeConstants.WORLD_VERSION`; older generator versions may remain
  in native code for deterministic debug surfaces, but are not load-compatible
  through `WorldStreamer`.
- The substrate snapshot is a derived cache owned by `WorldCore`; it is not
  persisted and must not be mutated by script code.
- Preview spawn resolution uses the shared worker wrapper, not a main-thread
  GDScript fallback.

Not documented here as safe entrypoints:
- direct calls to `world_prepass::*` helpers from script, because they are native
  implementation details behind `WorldCore`
- using dev-only substrate snapshot dictionaries as save data or gameplay state

### WorldStreamer

Owner file: `core/systems/world/world_streamer.gd`

Role:
- V0 world runtime orchestrator and current `chunk_manager` compatibility surface

Confirmed readable entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `get_world_seed()` | `int` | Current deterministic world seed |
| `get_world_version()` | `int` | Current canonical world version |
| `save_world_state()` | `Dictionary` | World save payload for `world.json`, including embedded `worldgen_settings.world_bounds`, `worldgen_settings.foundation`, `worldgen_settings.mountains`, `worldgen_settings.lakes`, and optional `worldgen_signature` |
| `collect_chunk_diffs()` | `Array[Dictionary]` | Serialized dirty chunk entries |
| `get_chunk_packet(chunk_coord: Vector2i)` | `Dictionary` | Loaded chunk packet or `{}`; read-only world-domain lookup for `MountainResolver` |
| `get_mountain_cover_sample(world_tile: Vector2i)` | `Dictionary` | Read-only cover sample for one tile: `mountain_id`, `mountain_flags`, `component_id`, `is_opening`, `walkable` |
| `get_mountain_cover_debug_snapshot(world_tile: Vector2i)` | `Dictionary` | Debug-only snapshot including `inside_outside_state`, active component ids, and `roof_layers_per_chunk_max` |
| `is_walkable_at_world(world_pos: Vector2)` | `bool` | Reads `base + diff`; returns `false` while a chunk is not ready |
| `has_resource_at_world(world_pos: Vector2)` | `bool` | Diggable surface query for the current harvest path (`TERRAIN_MOUNTAIN_WALL` and `TERRAIN_MOUNTAIN_FOOT`); returns `true` only when the tile also has an orthogonally exposed walkable face |
| `get_mountain_contour_debug_state(chunk_coord: Vector2i)` | `Dictionary` | Debug-only readback for the loaded chunk's L1 grid/mask/contour overlay state. Returns `ready: false` if the chunk view is not loaded. |

Confirmed mutation entrypoints:

| Surface | Notes |
|---|---|
| `initialize_new_world(seed_value: int, settings: MountainGenSettings, world_bounds: WorldBoundsSettings = null, foundation_settings: FoundationGenSettings = null, lake_settings: LakeGenSettings = null)` | New-game entrypoint; freezes mountain, finite-bounds, foundation, and lake settings into packed/native form and then delegates to `reset_for_new_game(...)` |
| `reset_for_new_game(seed, version)` | Clears runtime state, queues native foundation spawn resolution for `world_version >= 9`, applies the resolved new-game spawn tile to the local player before streaming chunks, and emits `world_initialized` |
| `load_world_state(data: Dictionary) -> bool` | Restores only current-version `world.json` payloads. Returns `false` before mutating runtime state when `world_version` is missing/non-current or the current `worldgen_settings` shape is incomplete; on success restores `world_seed` / `world_version`, rebuilds `worldgen_settings.world_bounds`, `worldgen_settings.foundation`, `worldgen_settings.mountains`, and `worldgen_settings.lakes` from `world.json`, and clears runtime state |
| `load_chunk_diffs(entries: Array)` | Loads serialized chunk diffs into `WorldDiffStore` |
| `try_harvest_at_world(world_pos: Vector2)` | Single-tile harvest path; converts one nearest qualifying diggable surface tile into its dug state and rejects diagonal-only sealed rock |
| `set_active_mountain_component(mountain_id: int, component_id: int)` | World-domain cover selection surface used by `MountainResolver` to switch between outside state and one active cavity |
| `toggle_debug_tile_grid()` | Toggles the developer-only `F6` 64 px grid overlay for loaded chunks |
| `toggle_debug_mountain_solid_mask()` | Toggles the developer-only `F7` current solid mountain mask overlay for loaded chunks |
| `toggle_debug_mountain_contour()` | Toggles the developer-only `F10` native contour mesh overlay for loaded chunks; does not bind or use `F8` |

Not documented here as safe entrypoints:
- `_streaming_tick()`
- `_worker_loop()`
- direct access to `_chunk_packets`, `_chunk_views`, or `_diff_store`
- direct mutation of native packet dictionaries outside the documented methods
- mutation of dictionaries returned by `get_chunk_packet()`

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
