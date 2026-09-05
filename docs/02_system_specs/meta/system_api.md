---
title: System API
doc_type: system_spec
status: draft
owner: engineering
source_of_truth: true
version: 0.22
last_updated: 2026-09-05
related_docs:
  - ../README.md
  - commands.md
  - event_contracts.md
  - packet_schemas.md
  - save_and_persistence.md
  - multiplayer_authority_and_replication.md
  - ../survival/player_wetness_and_cold_exposure.md
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
- `WeatherRuntime`
- `WindRuntime`
- `EnvironmentExposureResolver`
- `PlayerExposureComponent`
- `ItemRegistry`
- `SaveManager`
- `PlayerAuthority`
- `CommandExecutor`
- `BuildingSystem`
- `WorldCore`
- `WorldStreamer`
- `WorldRenderWorld`
- `WorldTileSetFactory`
- `WorldBoundsSettings`
- `FoundationGenSettings`
- `LakeGenSettings`

## Current Draft Blockers

This document remains draft after the 2026-06-29 pass because it now documents
both stable gameplay surfaces and dev/probe native surfaces. Before approval,
engineering must either promote those dev/probe surfaces as stable public API
or split them into a dedicated debug/probe API document.

Known blockers:
- `WorldCore.build_mountain_plateau_raster_image(...)` returns a broad
  preset-dependent debug/probe dictionary; only the stable consumed keys are
  documented in `packet_schemas.md`.
- This is a code-confirmed snapshot of listed surfaces, not a full repository
  API inventory.

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
- authoritative runtime time state for hour, day, season, season progress, and
  day phase; governing seasonal contract:
  `docs/02_system_specs/world/seasons_and_temperature_runtime.md`

Confirmed readable state:

| Surface | Kind | Notes |
|---|---|---|
| `balance` | variable | Loaded from `res://data/balance/time_balance.tres` |
| `current_hour` | variable | Current in-game hour as `float` |
| `current_day` | variable | Current in-game day as `int` |
| `current_season` | variable | Authoritative natural season enum value; consumers that must respect dev forcing use `get_effective_season()` |
| `current_time_of_day` | variable | Current day-phase enum value |
| `get_hour()` | method | Whole hour |
| `get_day_progress()` | method | `0.0..1.0` day progress |
| `get_sun_progress()` | method | Normalized time/elevation phase used by visual intensity and shadow length |
| `get_sun_angle()` | method | Fixed north-west visual sun angle in radians |
| `get_shadow_length_factor()` | method | Time-derived shadow-length factor; does not rotate the shadow |
| `is_time_paused()` | method | Pause query |
| `get_time_scale()` | method | Time scale query |
| `get_effective_season()` | method | Current effective `WARM/SPORE/COLD/STORM` phase, including developer-only forcing |
| `get_season_display_name_key()` | method | Localization key for the effective phase name, authored on `SeasonProfile`; UI resolves the text, never a literal |
| `get_day_in_season()` / `get_season_length_days()` | method | Phase-day readout `1..length` derived from the authoritative day, and the authored phase length; no separate calendar counter exists |
| `debug_cycle_time_scale()` | method | Developer-only time-scale ladder `x1 -> x10 -> x60 -> x300`, bound to `L` in debug builds. Never persisted; new-game and restore both reset to `x1` |
| `debug_cycle_season()` / `is_debug_season_forced()` | method | Developer-only phase forcing bound to `J` in debug builds. The cycle closes through the natural state (`natural -> next -> ... -> last -> natural`) so forcing is always exitable; the query exists so UI can mark a forced phase instead of it reading as a stuck calendar |
| `get_season_progress()` | method | Smooth normalized progress `0..1` through the effective phase; `0.0` and `1.0` are phase seams and `0.5` is the phase centre, where the authored profile is read exactly. Forced debug phases return the centre anchor `0.5` |
| `get_season_temperature_offset_c()` | method | Smooth data-driven seasonal Celsius offset; read by `WeatherRuntime` |
| `get_season_humidity_offset()` | method | Smooth additive seasonal humidity offset; read by `WeatherRuntime` |
| `get_weather_regime_weight_multiplier(regime_id)` | method | Smooth non-negative seasonal multiplier for an authored weather successor id; missing ids return neutral `1.0` |

Confirmed mutation entrypoints:

| Surface | Kind | Notes |
|---|---|---|
| `reset_for_new_game()` | method | Resets to default start state |
| `restore_persisted_state(hour, day, season)` | method | Save/load restore path |
| `set_paused(paused)` | method | Pause toggle |
| `set_time_scale(scale)` | method | Runtime time scale |

Developer-only (not for gameplay code):

| Surface | Kind | Notes |
|---|---|---|
| `set_debug_season(season)` / `clear_debug_season()` | method | Pin/release the effective season without changing persisted natural phase |
| `debug_cycle_season()` | method | Cycle forced `WARM -> SPORE -> COLD -> STORM`; TimeManager dev hotkey `J` |

Not documented here as safe entrypoints:
- `_calculate_speed()`
- `_apply_authoritative_time_state()`
- `_advance_time()`
- direct writes to the public `current_*` fields

Current code note:
- the code-confirmed state-transition paths that also emit sync events are the
  documented mutation methods above plus internal helpers

### WeatherRuntime

Owner file: `core/autoloads/weather_runtime.gd`

Role:
- single owner of weather state (ADR-0007 layers 2 slow + 3 local); evolves a
  data-driven weather regime over game time and drives the wind target that
  `WindRuntime` publishes
- governing specs:
  `docs/02_system_specs/world/weather_runtime.md`,
  `docs/02_system_specs/world/humidity_and_rain_runtime.md`,
  `docs/02_system_specs/world/cloud_occlusion_lighting.md`

Confirmed readable state (live axes; smooth values are pull-model getters):

| Surface | Kind | Notes |
|---|---|---|
| `get_active_regime_id()` | method | Active regime id (`core:clear/cloudy/overcast` in V0) |
| `get_active_display_name_key()` | method | Localization key for the active regime; used by HUD weather UI |
| `get_cloud_cover()` | method | `0` clear .. `1` overcast |
| `get_cloud_occlusion()` | method | `0` direct sun open .. `1` direct sun blocked; derived from `cloud_cover`, no new save state |
| `get_target_wind_strength()` | method | `0..1` wind target consumed by `WindRuntime` |
| `get_target_wind_gustiness()` | method | `0..1` gust character target |
| `get_target_wind_heading_deg()` | method | Wind heading target in degrees |
| `get_humidity()` | method | Authoritative global live humidity `0..1`; deterministic from regime bands, transition, and weather clock |
| `get_precipitation_kind()` / `get_precipitation_intensity()` | method | Authoritative live precipitation read. Intensity `0..1` derives from humidity + cloud cover + regime tuning; kind is then resolved by authoritative temperature against the authored freezing threshold, publishing `NONE`/`RAIN`/`SNOW`. Stateless: no hysteresis, no save field |
| `get_snow_presentation_weight()` | method | Presentation-only cross-fade weight around the freezing threshold (`1` snow .. `0` rain). Read by the rain/snow layers so a kind change is not a visual pop; it never influences the published kind |
| `get_temperature_c()` | method | Authoritative global outside-air Celsius read: authored weather band plus smooth seasonal offset; consumed as the baseline for player cold load, but still not biome/altitude/body temperature or a snow resolver |

Emits `weather_changed` on regime change (see `event_contracts.md`).

Developer-only (not for gameplay code):
| `set_debug_regime(id)` / `clear_debug_regime()` | method | Freeze on / release a forced regime |
| `debug_cycle_regime()` | method | Smooth ping-pong through clear→cloudy→overcast; bound to player hotkey `K` for in-game presentation checks |
| `set_debug_cloud_cover(v)` / `nudge_debug_cloud_cover(delta)` / `clear_debug_cloud_cover()` | method | Pin/ramp/release `cloud_cover` in real time; player holds `+`/`-` to watch clouds grow, drift, merge (cloud occlusion tuning) |
| `set_debug_humidity(v)` / `clear_debug_humidity()` | method | Pin/release humidity for causal rain probes; not a gameplay mutation path |

Confirmed persistence entrypoints:

| Surface | Kind | Notes |
|---|---|---|
| `export_save_dict()` | method | SaveCollectors-only slow weather save shape |
| `restore_persisted_state(data)` | method | SaveAppliers-only restore path; unknown regimes fall back to `core:clear` |

Not documented here as safe entrypoints:
- direct writes to weather state by any other system
- the internal regime-evolution helpers (`_advance`, `_begin_transition`,
  `_commit_transition`, `_select_next_regime`)

### WindRuntime

Owner file: `core/autoloads/wind_runtime.gd`

Role:
- low-level wind engine (ADR-0007 layer 3) and the single writer of the
  `wind_*` global shader uniforms. The wind **target** (strength, heading,
  gustiness) now comes from `WeatherRuntime`; `WindRuntime` smooths toward it
  and publishes globals. `WorldVisualWindProfile` keeps only gust shape.
- governing specs:
  `docs/02_system_specs/world/weather_runtime.md`,
  `docs/02_system_specs/world/wind_and_grass_scatter_presentation.md`

Confirmed readable state (environment-runtime read surface; presentation and
player exposure may consume it):

| Surface | Kind | Notes |
|---|---|---|
| `get_wind_time()` | method | Accumulated pause-aware wind seconds |
| `get_wind_strength()` | method | Current normalized strength `0..1` |
| `get_wind_direction()` | method | Current normalized direction vector |
| `get_wind_direction_deg()` | method | Current direction in degrees |
| `get_wind_gustiness()` | method | Current gust character `0..1` (also published as the `wind_gustiness` global) |
| `has_debug_wind_override()` | method | Whether a dev override is active |

Confirmed mutation entrypoints (dev-only: probes and dev scenes, never a
gameplay path):

| Surface | Kind | Notes |
|---|---|---|
| `set_debug_strength_override(strength)` | method | Clamped `0..1` dev override |
| `set_debug_direction_override_deg(deg)` | method | Dev direction override |
| `set_debug_gustiness_override(gustiness)` | method | Clamped `0..1` dev gustiness override |
| `clear_debug_wind_override()` | method | Returns to profile-driven wind |

Not documented here as safe entrypoints:
- direct writes to `wind_*` global shader uniforms by any other system
- `_current_strength()`, `_current_direction()`, `_publish_globals()`

### EnvironmentExposureResolver

Owner file: `core/systems/world/environment_exposure_resolver.gd`

Role:
- shared derived open-sky context for rain presentation and player wetting;
  owns no weather, terrain, room, or player survival truth

Confirmed read entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `get_active_z_level()` | `int` | Resolver-local z context; defaults to surface because the current shipping scene has no z-level owner |
| `is_open_sky_at(world_position)` | `bool` | True only at z0, outside a building indoor cell, with a ready non-interior mountain sample |
| `is_open_sky_at_z(world_position, z_level)` | `bool` | Explicit-z form used by probes/integration; unknown mountain cover fails closed |
| `is_building_indoor_at(world_position)` | `bool` | Derived read through the cached `BuildingSystem`; missing system means exterior, never false sanctuary |

Confirmed context update:

| Surface | Notes |
|---|---|
| `set_active_z_level(new_z)` | Explicit probe/future-integration bridge; the current shipping scene has no `ZLevelManager` and no `z_level_changed` emitter |

The resolver performs one deferred boot lookup for stable services, refreshes a
late-added `BuildingSystem` only when `rooms_recalculated` publishes, and never
scans the scene tree per exposure tick. `world_runtime_v0.tscn` currently ships
without `BuildingSystem`, `BaseLifeSupport`, or a z-level owner: mountain cover
is the reachable shelter authority there, while built/powered shelter and
subsurface branches remain integration-ready but are not reachable gameplay in
that scene.

### PlayerExposureComponent

Owner file: `core/entities/components/player_exposure_component.gd`

Role:
- sole per-player writer of normalized `wetness` and `cold_load`; V0 is
  warning-only and has no health, oxygen, movement, fatigue, or death mutation

Confirmed signal:

```text
exposure_changed(wetness: float, cold_load: float)
```

Confirmed read/persistence entrypoints:

| Surface | Return / notes |
|---|---|
| `from_player(player)` | Static typed lookup of the direct `ExposureComponent` child |
| `get_wetness()` / `get_cold_load()` | Authoritative normalized player reads |
| `get_*_visible_threshold()` | Data-authored HUD reveal thresholds |
| `get_*_warning_threshold()` / `get_*_critical_threshold()` | Data-authored palette-tier thresholds |
| `is_wetness_visible()` / `is_wetness_warning()` | Convenience wetness reads |
| `is_cold_visible()` / `is_cold_warning()` | Convenience cold-load reads |
| `save_state()` | Returns `{wetness, cold_load}` |
| `load_state(data)` | SaveAppliers restore path; missing/malformed values reset to zero and finite numeric values clamp to `0..1` |
| `calculate_next_state(...)` | Pure deterministic transition helper used by the component and contract probes; it does not write component state |

No public gameplay setter exists. Normal mutations occur only inside the
bounded component tick or through the documented save-restore entrypoint.

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
- `gdextension/src/world_render_buffer.cpp`

Role:
- native deterministic world-generation boundary and owner of the RAM-only
  `WorldPrePass` substrate;
- pure native construction/composition boundary for derived global world-render
  snapshots

Confirmed public native surface:

| Surface | Return | Notes |
|---|---|---|
| `generate_chunk_packets_batch(seed: int, coords: PackedVector2Array, world_version: int, settings_packed: PackedFloat32Array)` | `Array` | Returns one canonical chunk packet per requested coordinate; current chunk generation emits ground, mountain, and Lake Generation L2 bed terrain classes and reads the `WorldPrePass` substrate for lake fields. |
| `make_world_preview_patch_image(packet: Dictionary, render_mode: StringName)` | `Image` | Builds a lightweight preview patch image from an existing `ChunkPacketV1`; current modes are terrain, mountain id, and mountain classification. Terrain mode reads ground, mountain, and lake-bed packet terrain ids; it does not generate chunks. |
| `build_mountain_contour_debug(solid_halo: PackedByteArray, chunk_size: int, tile_size_px: int)` | `Dictionary` | Debug-only native marching-squares helper for Mountain Contour Mesh L1. Input is a compact `(chunk_size + 2)^2` solid mask with a one-tile halo; output contains derived `vertices: PackedVector2Array` and `indices: PackedInt32Array`. This is visual/debug data only, not packet truth, save state, collision, or walkability. |
| `build_mountain_halo_mask(solid_halo: PackedByteArray, chunk_size: int, tile_size_px: int, pixels_per_tile: int, origin_world_x: float, origin_world_y: float)` | `Dictionary` | Derived native mask helper for runtime mountain and terrain-edge presentation. Returns `MountainHaloMaskResult` from `packet_schemas.md`; not packet truth, save state, collision, or terrain ownership. |
| `build_mountain_skylight_exposure(closed_roof_mask: PackedByteArray, live_mask: PackedByteArray, width: int, height: int, step_px: float, reach_samples: int)` | `Dictionary` | Deterministic derived native helper for M8 mountain-cavity natural-light exposure. Returns `MountainSkylightExposureResult` from `packet_schemas.md`; runs only inside the existing mountain-mask worker request for excavated roof-bearing chunks and adds no gameplay read or save surface. |
| `build_mountain_plateau_raster_image(packets: Array, target_chunk: Vector2i, preset: Dictionary, top_image: Image, face_image: Image)` | `Dictionary` | Authoring/probe raster helper still used by the worker backend. Returns `MountainPlateauRasterImageResult` from `packet_schemas.md`; broad debug/probe output, not the normal chunk packet or save shape. |
| `resolve_world_foundation_spawn_tile(seed: int, world_version: int, settings_packed: PackedFloat32Array)` | `Dictionary` | Resolves the V1 foundation spawn tile from the substrate and returns the shape documented as `WorldFoundationSpawnResult` in `packet_schemas.md` |
| `build_grass_scatter_buffer(seed: int, chunk_coord: Vector2i, terrain_ids: PackedInt32Array, lake_flags: PackedByteArray, mountain_halo: PackedByteArray, mountain_halo_radius_tiles: int, params: PackedFloat32Array)` | `Dictionary` | Presentation-only deterministic grass tuft placement for one chunk; returns the `GrassScatterBufferResult` shape from `packet_schemas.md` (ready `MultiMesh` buffer). `mountain_halo` is the same cross-chunk solid halo `WorldStreamer` builds for the mountain mask, reused so mountain-edge clearance sees neighbouring-chunk mountains too (added 2026-07-04). Density mirrors the ground material's aperiodic world fields; never packet truth, save state, collision, or walkability. |
| `build_object_presentation_buffers(object_kind: PackedByteArray, object_local_x_px_q4: PackedByteArray, object_local_y_px_q4: PackedByteArray, object_size_px: PackedByteArray, object_atlas_index: PackedByteArray, object_variant: PackedByteArray, object_flags: PackedByteArray, object_tint: PackedByteArray, object_phase: PackedByteArray, tree_metrics: PackedFloat32Array, rock_metrics: PackedFloat32Array, bush_metrics: PackedFloat32Array, params: PackedFloat32Array)` | `Dictionary` | Pure worker packing for one already-generated object packet. Returns generic raw family buffers consumed by `WorldRenderWorld` through registry source bindings plus compact tree collision rectangles consumed by `WorldObjectCollisionOwner`. The collision owner creates chunk-owned `RectangleShape2D` owners only; it owns no visual asset or GPU buffer. Optional disabled flora outputs stay lazy-empty. The call loads no assets, touches no scene tree, alters no canonical placement and enters no save data. |
| `build_world_render_snapshot(chunk_origins: PackedVector2Array, object_results: Array, grass_results: Array, source_bindings: Array, grass_lod_fraction: float)` | `Dictionary` | Pure background/native construction of the static `WorldRenderSnapshot` documented in `packet_schemas.md`. `source_bindings` is validated data from `WorldRenderClassRegistry`, so family ids and worker keys are not compiled into the packer. The result preserves absolute 1024-pixel pages, emits only the five fixed pass streams plus shared object shadow/spore streams, reports descriptor counts and bounded CPU capacities, and owns no scene/resource/save state. |
| `compose_world_render_actors(static_snapshot: Dictionary, actor_records: Array)` | `Dictionary` | Validates `WorldRenderActorRecord` entries and returns a composed `WorldRenderSnapshot`. Runtime calls it as bounded interactive native work: immutable static packed arrays are shallow-reused by copy-on-write, only actor-touched body pages are repacked, and all visible actor shadows share one bulk buffer. It touches no scene tree and creates no GPU resources. |

Dev-only native surface:

| Surface | Return | Notes |
|---|---|---|
| `get_world_foundation_snapshot(layer_mask: int, downscale_factor: int)` | `Dictionary` | Debug build only; returns the current `WorldPrePass` channel snapshot |
| `get_world_foundation_overview(layer_mask: int, pixels_per_cell: int)` | `Image` | Debug build only; returns a pre-coloured high-resolution overview image. `layer_mask = 0` renders the current realised terrain classes: ground, mountain foot, mountain wall, shallow lake bed, and deep lake bed. The foundation-height layer mask renders the raw `foundation_height` substrate channel as a diagnostic height map. |

Current code notes:
- `settings_packed` for `world_version >= 9` must include the mountain fields
  plus V1 foundation indices `9-14`, Lake Generation L1/L2 indices `15-20`,
  Lake Generation V2+ `connectivity` at index `21`, plains tree indices
  `22-43`, and plains small rock indices `44-70` (`71` total fields) in the
  current `WorldStreamer` path.
- the active pre-alpha save/load policy accepts only the current
  `WorldRuntimeConstants.WORLD_VERSION`; older generator versions may remain
  in native code for deterministic debug surfaces, but are not load-compatible
  through `WorldStreamer`.
- The substrate snapshot is a derived cache owned by `WorldCore`; it is not
  persisted and must not be mutated by script code.
- Preview spawn resolution uses the shared worker wrapper, not a main-thread
  GDScript fallback.
- Mountain halo, skylight-exposure, and plateau raster outputs are derived native presentation or
  debug/probe results. They must not be persisted or treated as authoritative
  terrain, walkability, navigation, or chunk packet data.
- World-render snapshots and actor records are derived presentation boundaries.
  They carry no authoritative placement, collision, navigation, command, event,
  save, or replication ownership.
- `compose_world_render_actors` requires worker-sorted static body painter
  metadata. It validates actor-touched pages and linearly merges their immutable
  static records with sorted actors; it does not re-sort static bodies. A static
  bank staged across multiple frames receives the current actor set at atomic
  publication, including any intervening proxy registration or removal.

Not documented here as safe entrypoints:
- direct calls to `world_prepass::*` helpers from script, because they are native
  implementation details behind `WorldCore`
- using dev-only substrate snapshot dictionaries as save data or gameplay state

### WorldStreamer

Owner file: `core/systems/world/world_streamer.gd`

Role:
- V0 world runtime orchestrator, current `chunk_manager` compatibility surface,
  and the safe registration boundary for streamer-owned global visual proxies

Confirmed readable entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `get_world_seed()` | `int` | Current deterministic world seed |
| `get_world_version()` | `int` | Current canonical world version |
| `save_world_state()` | `Dictionary` | World save payload for `world.json`, including embedded `worldgen_settings.world_bounds`, `worldgen_settings.foundation`, `worldgen_settings.mountains`, `worldgen_settings.lakes`, `worldgen_settings.plains_trees`, `worldgen_settings.plains_small_rocks`, `worldgen_settings.plains_bare_ground_stones`, and optional `worldgen_signature` |
| `collect_chunk_diffs()` | `Array[Dictionary]` | Serialized dirty chunk entries |
| `get_chunk_packet(chunk_coord: Vector2i)` | `Dictionary` | Loaded chunk packet or `{}`; read-only world-domain lookup for `MountainResolver` |
| `get_mountain_cover_sample(world_tile: Vector2i)` | `Dictionary` | Read-only cover sample for one tile: `mountain_id`, `mountain_flags`, `component_id`, `is_opening`, `walkable` |
| `resolve_mountain_cover_at_world(world_pos: Vector2, preferred_component_id: int = 0)` | `Dictionary` | Read-only cover resolution used by `MountainResolver`: exact-tile cover sample, extended by a bounded `3 x 3` neighbour fallback only inside the real organic excavation fringe (closed roof mask solid, live remaining mask open); prefers `preferred_component_id`. Adds `resolved_from_organic_cutout: bool` |
| `get_mountain_cover_debug_snapshot(world_tile: Vector2i)` | `Dictionary` | Debug-only snapshot including `inside_outside_state`, active component ids, and `roof_layers_per_chunk_max` |
| `is_walkable_at_world(world_pos: Vector2)` | `bool` | Reads `base + diff`; returns `false` while a chunk is not ready |
| `has_resource_at_world(world_pos: Vector2)` | `bool` | Diggable surface query for the current harvest path (`TERRAIN_MOUNTAIN_WALL` and `TERRAIN_MOUNTAIN_FOOT`); returns `true` only when the tile also has an orthogonally exposed walkable face |
| `get_mountain_contour_debug_state(chunk_coord: Vector2i)` | `Dictionary` | Debug-only readback for the loaded chunk's L1 grid/mask/contour overlay state. Returns `ready: false` if the chunk view is not loaded. |
| `get_streaming_readiness_debug_snapshot()` | `Dictionary` | Developer-only bounded read of the existing streaming working set. Returns `StreamingReadinessDiagnosticSnapshot`; it may inspect only resident/demand dictionaries, never schedules work, and is called only by explicit captures/probes/finalization rather than the four-Hz HUD context path. |
| `get_initial_loading_state()` | `Dictionary` | O(1) read of the transient `InitialWorldLoadingState` owned by `WorldStreamer`. Used by the loading UI and deterministic probes; it never scans chunks or schedules work. |

Confirmed mutation entrypoints:

| Surface | Notes |
|---|---|
| `initialize_new_world(seed_value: int, settings: MountainGenSettings, world_bounds: WorldBoundsSettings = null, foundation_settings: FoundationGenSettings = null, lake_settings: LakeGenSettings = null, plains_tree_settings: PlainsTreePlacementSettings = null, plains_small_rock_settings: PlainsSmallRockPlacementSettings = null, plains_bare_ground_stone_settings: PlainsSmallRockPlacementSettings = null)` | New-game entrypoint; freezes mountain, finite-bounds, foundation, lake, plains tree placement, and both plains small-rock placement profiles into packed/native form and then delegates to `reset_for_new_game(...)` |
| `enable_debug_visible_only_initial_loading()` | Developer-scene boot option; before target establishment, makes the initial loading gate wait for the complete production visible envelope while the outer movement-reserve ring continues through the normal background streamer. Returns `false` after a target exists. |
| `reset_for_new_game(seed, version)` | Clears runtime state, queues native foundation spawn resolution for `world_version >= 9`, applies the resolved new-game spawn tile to the local player before streaming chunks, and emits `world_initialized` |
| `load_world_state(data: Dictionary) -> bool` | Restores only current-version `world.json` payloads. Returns `false` before mutating runtime state when `world_version` is missing/non-current or the current `worldgen_settings` shape is incomplete; on success restores `world_seed` / `world_version`, rebuilds `worldgen_settings.world_bounds`, `worldgen_settings.foundation`, `worldgen_settings.mountains`, `worldgen_settings.lakes`, `worldgen_settings.plains_trees`, `worldgen_settings.plains_small_rocks`, and `worldgen_settings.plains_bare_ground_stones` from `world.json`, and clears runtime state |
| `load_chunk_diffs(entries: Array)` | Loads serialized chunk diffs into `WorldDiffStore` |
| `acknowledge_initial_world_presented()` | Called only by `WorldRuntimeV0Scene` after the first unobscured world frame. Records presentation timing and releases the startup-only maximum-zoom plus movement-reserve materialization pin. It cannot close an unready gate. |
| `register_visual_proxy(proxy: Node) -> bool` | Registers one visible interactive presentation owner with `WorldRenderWorld`. Returns `false` unless the renderer is configured and the proxy implements the complete protocol below. Actor atlases/descriptors are boot-owned by `WorldRenderClassRegistry`; a proxy supplies records, not textures. Registration triggers a composed publication but does not change gameplay/collision authority. |
| `unregister_visual_proxy(proxy: Node) -> void` | Removes the proxy, republishes the remaining actor set, and requests that the proxy restore its legacy fallback presentation. Safe to call during owner teardown. |
| `try_harvest_at_world(world_pos: Vector2)` | Single-tile harvest path; converts one nearest qualifying diggable surface tile into its dug state and rejects diagonal-only sealed rock |
| `set_active_mountain_component(mountain_id: int, component_id: int)` | World-domain cover selection surface used by `MountainResolver`. Updates the immediate gameplay target selection; the construction-roof presentation independently retains a displayed component and fades its reveal blend (`150 ms` enter; `60 + 180 ms` exit), see `mountain_generation.md` M7 |
| `toggle_debug_tile_grid()` | Toggles the developer-only `F6` 64 px grid overlay for loaded chunks |
| `toggle_debug_mountain_solid_mask()` | Toggles the developer-only `F7` current solid mountain mask overlay for loaded chunks |
| `toggle_debug_mountain_contour()` | Toggles the developer-only `F10` native contour mesh overlay for loaded chunks; does not bind or use `F8` |

Visual proxy protocol consumed by `WorldRenderWorld`:

| Required surface | Contract |
|---|---|
| `get_world_render_record() -> Dictionary` | Returns the current `WorldRenderActorRecord` from `packet_schemas.md`; one call per explicitly registered visible proxy when the renderer evaluates actor state. |
| `set_world_render_proxy_active(active: bool) -> void` | Hides fallback body/shadow CanvasItems only after successful composed publication and restores them on unregister/renderer teardown. It must not disable gameplay, collision, or animation-state updates. |

`WorldRenderWorld` owns weak references to registered proxies and iterates only
that bounded registry. Direct group/scene-tree scans for actor presentation and
per-actor GPU/CanvasItem allocation are outside the contract. Callers should use
the `WorldStreamer` forwarding methods rather than retaining or mutating the
streamer-owned renderer node.

The retired `bind_height_shadow_field`/`WorldHeightShadowField`/
`get_height_shadow_debug_state` API has no production replacement. Its script,
profile resource, shader include and debug counter were removed; directional
shadows are ordinary fixed-pass records in the render-class registry and
snapshot schema.

Not documented here as safe entrypoints:
- `_streaming_tick()`
- `_worker_loop()`
- direct access to `_chunk_packets`, `_chunk_views`, or `_diff_store`
- direct access to `_world_render_world` or its active/staging GPU banks
- direct mutation of native packet dictionaries outside the documented methods
- mutation of dictionaries returned by `get_chunk_packet()`

### WorldTileSetFactory

Owner file: `core/systems/world/world_tile_set_factory.gd`

Role:
- boot-built shared `TileSet` and `ShaderMaterial` cache for production terrain
  presentation

Confirmed developer-only mutation entrypoint:

| Surface | Notes |
|---|---|
| `reset_debug_authoring_cache()` | Clears boot-built terrain, roof, and water presentation caches for a complete embedded dev-runtime rebuild. It is valid only after the previous world and all of its `ChunkView` nodes have left the scene tree; gameplay/runtime code must never call it on a live world. |

Not documented here as safe entrypoints:
- clearing any backing cache dictionary directly
- calling `reset_debug_authoring_cache()` while a live world owns built tile
  sets or materials

### World Bounds, Foundation, Lake, Tree, and Small Rock Settings

Owner files:
- `core/resources/world_bounds_settings.gd`
- `core/resources/foundation_gen_settings.gd`
- `core/resources/lake_gen_settings.gd`
- `core/resources/plains_tree_placement_settings.gd`
- `core/resources/plains_small_rock_placement_settings.gd`

Role:
- data resources for finite cylindrical bounds, V1 foundation settings, current
  lake-generation settings, plains tree placement tuning, and plains small rock
  placement tuning

Confirmed readable entrypoints:

| Surface | Return | Notes |
|---|---|---|
| `WorldBoundsSettings.to_save_dict()` | `Dictionary` | Writes bounds into `world.json` |
| `WorldBoundsSettings.for_preset(preset: StringName)` | `WorldBoundsSettings` | Returns `small`, `medium`, or `large` V1 bounds |
| `WorldBoundsSettings.from_save_dict(data: Dictionary)` | `WorldBoundsSettings` | Rebuilds bounds from `world.json` |
| `FoundationGenSettings.to_save_dict()` | `Dictionary` | Writes foundation settings into `world.json` |
| `FoundationGenSettings.for_bounds(world_bounds: WorldBoundsSettings)` | `FoundationGenSettings` | Builds default band settings from saved bounds |
| `FoundationGenSettings.from_save_dict(data: Dictionary, world_bounds: WorldBoundsSettings)` | `FoundationGenSettings` | Rebuilds foundation settings from `world.json` |
| `FoundationGenSettings.write_to_settings_packed(settings_packed: PackedFloat32Array, world_bounds: WorldBoundsSettings)` | `PackedFloat32Array` | Appends V1 foundation indices `9-14` to the native settings packet |
| `LakeGenSettings.to_save_dict()` | `Dictionary` | Writes lake settings into `world.json` |
| `LakeGenSettings.from_save_dict(data: Dictionary)` | `LakeGenSettings` | Rebuilds lake settings from `world.json` |
| `LakeGenSettings.write_to_settings_packed(settings_packed: PackedFloat32Array)` | `PackedFloat32Array` | Appends Lake Generation indices `15-21` to the native settings packet |
| `PlainsTreePlacementSettings.to_save_dict()` | `Dictionary` | Writes plains tree placement settings into `world.json` |
| `PlainsTreePlacementSettings.from_save_dict(data: Dictionary)` | `PlainsTreePlacementSettings` | Rebuilds plains tree placement settings from `world.json` |
| `PlainsTreePlacementSettings.write_to_settings_packed(settings_packed: PackedFloat32Array)` | `PackedFloat32Array` | Appends plains tree placement indices `22-43` to the native settings packet |
| `PlainsSmallRockPlacementSettings.to_save_dict()` | `Dictionary` | Writes plains small rock placement settings into `world.json` |
| `PlainsSmallRockPlacementSettings.from_save_dict(data: Dictionary)` | `PlainsSmallRockPlacementSettings` | Rebuilds plains small rock placement settings from `world.json` |
| `PlainsSmallRockPlacementSettings.write_to_settings_packed(settings_packed: PackedFloat32Array)` | `PackedFloat32Array` | Appends plains small rock placement indices `44-70` to the native settings packet |

Not documented here as safe entrypoints:
- direct mutation of settings resources after `WorldStreamer` has frozen them
  into its current packed native settings
