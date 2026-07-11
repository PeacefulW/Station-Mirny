class_name WorldStreamer
extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const HarvestQuery = preload("res://core/systems/world/harvest_query.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const PlainsTreePlacementSettings = preload("res://core/resources/plains_tree_placement_settings.gd")
const PlainsSmallRockPlacementSettings = preload("res://core/resources/plains_small_rock_placement_settings.gd")
const MountainCavityCache = preload("res://core/systems/world/mountain_cavity_cache.gd")
const MountainTorchComponentSelector = preload("res://core/systems/world/mountain_torch_component_selector.gd")
const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const MountainPlateau2DRasterLayer = preload("res://core/systems/world/mountain_plateau_2d_raster_layer.gd")
const MiningFeedbackLayer = preload("res://core/systems/world/mining_feedback_layer.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldDiffStore = preload("res://core/systems/world/world_diff_store.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const WorldVisualWindProfile = preload("res://core/systems/world/world_visual_wind_profile.gd")
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const GRASS_SHADOW_SHADER = preload("res://assets/shaders/grass_shadow_batch.gdshader")
const GRASS_SPORE_SHADER = preload("res://assets/shaders/grass_spore_batch.gdshader")
const WorldSpawnResolver = preload("res://core/systems/world/world_spawn_resolver.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const DefaultPlainsGroundMaterialSet = preload("res://data/terrain/material_sets/plains_ground_material_set.tres")
const DefaultPlainsTreePlacementSettings = preload("res://data/world_objects/placement_groups/plains_trees.tres")
const DefaultPlainsSmallRockPlacementSettings = preload("res://data/world_objects/placement_groups/plains_small_rocks.tres")

const INVALID_CHUNK_COORD: Vector2i = Vector2i(2147483647, 2147483647)
const LADDER_ANCHOR_UNSET: int = 1 << 30
const MAX_SPAWN_RESULTS_PER_TICK: int = 1
const PACKET_WORKER_COUNT: int = 3
const MOUNTAIN_MASK_WORKER_COUNT: int = 3
const MAX_PACKET_RESULTS_PER_TICK: int = 24
const MAX_MOUNTAIN_PAGE_RESULTS_PER_TICK: int = 1
const MAX_MOUNTAIN_NATIVE_MASK_RESULTS_PER_TICK: int = 8
# Publish pipeline pacing: scan a bounded queue prefix for a publishable chunk
# (a mask-stalled head must not block ready chunks behind it) and warm native
# mask requests for a bounded number of queued chunks per tick.
const PUBLISH_QUEUE_SCAN_LIMIT: int = 8
const PUBLISH_MASK_PREFETCH_PER_TICK: int = 2
const MOUNTAIN_PAGE_MAX_INFLIGHT: int = 18
const MOUNTAIN_MASK_SOURCE_RADIUS_CHUNKS: int = 1
const MOUNTAIN_PAGE_PREFETCH_RADIUS_CHUNKS: int = 1
const MOUNTAIN_PAGE_EVICT_MAX_PER_TICK: int = 8
const MOUNTAIN_PAGE_CLIP_MARGIN_PX: float = 128.0
const MOUNTAIN_VISUAL_CLIP_MARGIN_PX: float = 512.0
const MOUNTAIN_VISUAL_SOURCE_PADDING_PX: float = 320.0
const MOUNTAIN_PAGE_VISUAL_INFLUENCE_MARGIN_TILES: int = 6
const MOUNTAIN_INTERIOR_FILL_SAFETY_MARGIN_TILES: int = 2
# Halo must cover the longest cross-chunk sampling reach of the mask shader,
# or neighbour chunks cannot reproduce projected mountain shadows / aprons and
# they cut at chunk seams: shadow reach sqrt(360^2 + (78 * 1.38 * 1.85)^2)
# ~= 412 px + 48 px shadow draw overlap -> 460 px; foothill outer search is
# 154 + 96 = 250 px. ceil(460 / 64) = 8 tiles.
const MOUNTAIN_HALO_MASK_RADIUS_TILES: int = 8
const MOUNTAIN_HALO_MASK_PIXELS_PER_TILE: int = 8
const MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD: int = 107
const MOUNTAIN_MOUTH_NORTH_BIT: int = 1
const MOUNTAIN_MOUTH_EAST_BIT: int = 2
const MOUNTAIN_MOUTH_SOUTH_BIT: int = 4
const MOUNTAIN_MOUTH_WEST_BIT: int = 8
const MOUNTAIN_MOUTH_LATERAL_NEGATIVE_BIT: int = 16
const MOUNTAIN_MOUTH_LATERAL_POSITIVE_BIT: int = 32
const MOUNTAIN_TORCH_SHADOW_FIELD_WINDOW_SNAP_PX: float = 256.0
const MOUNTAIN_NATIVE_MASK_RUNTIME_ENABLED: bool = true
# The walkable plains surface is composed entirely by the world-space ground
# material (ground_hybrid_material.gdshader). The terrain-edge mask is a
# bounded SHORELINE enhancement only: it is built solely for chunks whose halo
# contains both dry land and visible water, and its shader paints only the
# organic contour band plus the bank facade, never the dry interior.
const TERRAIN_EDGE_MASK_RUNTIME_ENABLED: bool = true
# Same cross-chunk sampling-reach requirement as MOUNTAIN_HALO_MASK_RADIUS_TILES:
# the shoreline underlay projects the same WorldVisualLightingProfile shadows.
const TERRAIN_EDGE_HALO_MASK_RADIUS_TILES: int = 8
const TERRAIN_EDGE_HALO_MASK_PIXELS_PER_TILE: int = 4
const TERRAIN_EDGE_TOP_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/ground/dry_ground_top_albedo.png"
const TERRAIN_EDGE_FACE_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/ground/dry_ground_face_albedo.png"
const TERRAIN_EDGE_TOP_NORMAL_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/ground/dry_ground_top_normal.png"
const TERRAIN_EDGE_FACE_NORMAL_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/ground/dry_ground_face_normal.png"
const GRASS_BLOB_OVERLAY_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/ground/dry_grass_sparse_albedo.png"
const GRASS_BLOB_OVERLAY_TEXTURE_PATH_2: String = "res://assets/textures/world/biomes/plains/ground/dry_grass_medium_albedo.png"
const GRASS_BLOB_OVERLAY_TEXTURE_PATH_3: String = "res://assets/textures/world/biomes/plains/ground/dry_grass_dense_albedo.png"
const GRASS_BLOB_OVERLAY_NORMAL_TEXTURE_PATH: String = "res://assets/textures/world/biomes/plains/ground/orange_biofield_normal.png"
const PLAINS_TREE_ENABLED: bool = true
const PLAINS_TREE_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/plains_trees_atlas.png")
const PLAINS_LAYERED_TREE_ASSET_DIRS: Array[String] = [
	"res://assets/sprites/flora/layered_trees/tree_01",
	"res://assets/sprites/flora/layered_trees/tree_02",
	"res://assets/sprites/flora/layered_trees/tree_03",
	"res://assets/sprites/flora/layered_trees/tree_04",
	"res://assets/sprites/flora/layered_trees/tree_05",
]
const PLAINS_SMALL_ROCK_ENABLED: bool = true
const PLAINS_LAYERED_SMALL_ROCK_ASSET_DIRS: Array[String] = [
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_01",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_02",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_03",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_04",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_05",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_06",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_07",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_08",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_09",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_10",
]
const PLAINS_LIVING_FLORA_ENABLED: bool = false
const PLAINS_LIVING_FLORA_ATLAS_PATH: String = "res://assets/sprites/flora/atlases/brown_seaweed_living_4views_16frames_256.png"
# Спайки-колючки отключены по визуальному решению: идентичность биополя
# несёт густой травяной слой (grass scatter), а не точечные растения.
const PLAINS_SPIKY_FLORA_ENABLED: bool = false
const PLAINS_SPIKY_FLORA_ATLAS_PATH: String = "res://assets/sprites/flora/atlases/orange_spiky_plant_spritesheet_4x512.png"
const PLAINS_BROWN_SEAWEED_STATIC_FLORA_ATLAS_PATH: String = "res://assets/sprites/flora/atlases/brown_seaweed_static_biofield_4x512.png"
# Mountain mask presentation textures and dressing are authored data, resolved
# through the terrain presentation registry (see terrain_hybrid_presentation.md).
const MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID: StringName = &"mountain:mask_underlay_material"
const MOUNTAIN_NATIVE_MASK_VISUAL_UPLOAD_BUDGET_MS: float = 0.75
const MASK_MINING_SEARCH_RADIUS_TILES: int = 3
const MAX_VIEWPORT_STREAM_RADIUS_CHUNKS: int = 4
const MOUNTAIN_MASK_PRESET_PATH: String = "res://scenes/dev/mountain_2d_raster_preset.json"
const STREAMING_STEP_TIMING_DEBUG: bool = false

var world_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var world_version: int = WorldRuntimeConstants.WORLD_VERSION

var _diff_store: WorldDiffStore = WorldDiffStore.new()
var _chunk_packets: Dictionary = { }
var _chunk_views: Dictionary = { }
var _requested_chunks: Dictionary = { }
var _pending_publish_queue: Array[Vector2i] = []
var _active_publish_chunk: Vector2i = INVALID_CHUNK_COORD
var _player_chunk_coord: Vector2i = INVALID_CHUNK_COORD
var _current_stream_radius_chunks: int = WorldRuntimeConstants.STREAM_RADIUS_CHUNKS
var _desired_source_chunk_coords: Array[Vector2i] = []
var _desired_visible_chunk_coords: Array[Vector2i] = []
var _desired_mountain_mask_chunk_coords: Array[Vector2i] = []
var _desired_cache_center_chunk: Vector2i = INVALID_CHUNK_COORD
var _desired_cache_radius_chunks: int = -1
var _desired_cache_source_radius_chunks: int = -1
var _stream_job_id: StringName = &""
var _mountain_native_mask_visual_job_id: StringName = &""
var _generation_epoch: int = 0
var _worldgen_settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
var _world_bounds_settings: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
var _foundation_settings: FoundationGenSettings = FoundationGenSettings.hard_coded_defaults()
var _lake_settings: LakeGenSettings = LakeGenSettings.hard_coded_defaults()
var _plains_tree_settings: PlainsTreePlacementSettings = PlainsTreePlacementSettings.hard_coded_defaults()
var _plains_small_rock_settings: PlainsSmallRockPlacementSettings = PlainsSmallRockPlacementSettings.hard_coded_defaults()
var _worldgen_settings_packed: PackedFloat32Array = PackedFloat32Array()
var _pending_new_world_settings: MountainGenSettings = null
var _pending_new_world_bounds: WorldBoundsSettings = null
var _pending_new_foundation_settings: FoundationGenSettings = null
var _pending_new_lake_settings: LakeGenSettings = null
var _pending_new_plains_tree_settings: PlainsTreePlacementSettings = null
var _pending_new_plains_small_rock_settings: PlainsSmallRockPlacementSettings = null
var _packet_backend: WorldChunkPacketBackend = WorldChunkPacketBackend.new()
var _mountain_mask_backend: WorldChunkPacketBackend = WorldChunkPacketBackend.new()
var _awaiting_new_game_spawn_result: bool = false
var _new_game_spawn_failed: bool = false
var roof_layers_per_chunk_max: int = 0

var _mountain_cavity_cache: MountainCavityCache = MountainCavityCache.new()
var _active_cover_mountain_id: int = 0
var _active_cover_component_id: int = 0
var _did_warn_roof_layer_explosion: bool = false
var _debug_tile_grid_visible: bool = false
var _debug_mountain_solid_visible: bool = false
var _debug_mountain_contour_visible: bool = false
## Dev-оверлей коллизий деревьев (F11), presentation only.
var _debug_object_collisions_visible: bool = false
var _contour_world_core: Object = null
var _mountain_mask_preset: Dictionary = { }
var _mountain_top_fill_texture: Texture2D = null
var _mountain_face_fill_texture: Texture2D = null
var _mountain_top_normal_fill_texture: Texture2D = null
var _mountain_face_normal_fill_texture: Texture2D = null
var _mountain_foothill_texture: Texture2D = null
var _mountain_foothill_normal_texture: Texture2D = null
var _terrain_edge_top_texture: ImageTexture = null
var _terrain_edge_face_texture: ImageTexture = null
var _terrain_edge_top_normal_texture: ImageTexture = null
var _terrain_edge_face_normal_texture: ImageTexture = null
var _grass_blob_overlay_texture: ImageTexture = null
var _grass_blob_overlay_texture_2: ImageTexture = null
var _grass_blob_overlay_texture_3: ImageTexture = null
var _grass_blob_overlay_normal_texture: ImageTexture = null
var _plains_living_flora_atlas: Texture2D = null
var _plains_spiky_flora_atlases: Array[Texture2D] = []
var _mountain_mask_revision_by_chunk: Dictionary = { }
var _mountain_native_masks_by_chunk: Dictionary = { }
var _mountain_native_mask_inflight_chunks: Dictionary = { }
var _terrain_edge_mask_revision_by_chunk: Dictionary = { }
var _terrain_edge_masks_by_chunk: Dictionary = { }
var _terrain_edge_mask_inflight_chunks: Dictionary = { }
# Solid-halo build caches: a 32x32-tile halo costs ~1k packet lookups in
# GDScript, and the publish gate used to rebuild it every tick while waiting
# for a native mask. Keyed by chunk; validated by (epoch, revision).
var _mountain_solid_halo_cache: Dictionary = { }
var _terrain_edge_solid_halo_cache: Dictionary = { }
var _last_terrain_edge_mask_result: Dictionary = {
	"ready": false,
}
var _last_mountain_mask_result: Dictionary = {
	"ready": false,
}
var _mountain_native_mask_build_count_total: int = 0
var _mountain_native_mask_clear_count_total: int = 0
var _mountain_native_mask_build_count_tick: int = 0
var _mountain_native_mask_build_count_last_tick: int = 0
var _mountain_native_mask_build_count_max_tick: int = 0
var _mountain_native_mask_elapsed_ms_last: float = 0.0
var _mountain_native_mask_elapsed_ms_max_total: float = 0.0
var _mountain_native_mask_elapsed_ms_max_tick: float = 0.0
var _mountain_native_mask_elapsed_ms_last_tick_max: float = 0.0
var _mountain_native_mask_last_chunk: Vector2i = INVALID_CHUNK_COORD
var _mountain_native_mask_last_reason: StringName = &""
var _mountain_native_mask_last_refreshed_chunks: Array[Vector2i] = []
var _pending_mountain_native_mask_visual_upload_chunks: Array[Vector2i] = []
var _pending_mountain_native_mask_visual_upload_set: Dictionary = { }
# A chunk whose CPU cover selector is ready but whose GPU construction roof is
# still dirty stays hidden. This prevents one CLOSED frame when loading/restoring
# the player inside a cavity while visual work is budgeted.
var _pending_chunk_visibility_after_mountain_visual: Dictionary = { }
var _pending_terrain_edge_mask_visual_upload_chunks: Array[Vector2i] = []
var _pending_terrain_edge_mask_visual_upload_set: Dictionary = { }
var _pending_object_packet_visual_upload_chunks: Array[Vector2i] = []
var _pending_object_packet_visual_upload_set: Dictionary = { }
var _pending_grass_scatter_visual_upload_chunks: Array[Vector2i] = []
var _pending_grass_scatter_visual_upload_set: Dictionary = { }
var _grass_scatter_material: ShaderMaterial = null
var _grass_shadow_atlas_material: ShaderMaterial = null
var _grass_shadow_material: ShaderMaterial = null
var _grass_spore_material: ShaderMaterial = null
var _grass_scatter_atlas: Texture2D = null
var _grass_shadow_atlas: Texture2D = null
var _grass_scatter_params: PackedFloat32Array = PackedFloat32Array()
var _grass_lod_full_zoom: float = 0.8
var _grass_lod_min_zoom: float = 0.18
var _grass_lod_min_fraction: float = 0.35
var _grass_lod_fraction: float = 1.0
var _ladder_anchor_stripe: int = LADDER_ANCHOR_UNSET
var _mountain_native_mask_visual_upload_count_total: int = 0
var _mountain_native_mask_visual_upload_count_last_tick: int = 0
var _mountain_native_mask_visual_upload_elapsed_ms_last: float = 0.0
var _mountain_native_mask_visual_upload_elapsed_ms_max_total: float = 0.0
var _mountain_native_mask_visual_upload_last_chunk: Vector2i = INVALID_CHUNK_COORD
var _mountain_native_mask_visible_republish_skip_count_total: int = 0
var _mountain_native_mask_worker_elapsed_ms_last: float = 0.0
var _mountain_native_mask_worker_elapsed_ms_max_total: float = 0.0
var _mountain_native_mask_request_to_complete_ms_last: float = 0.0
var _mountain_native_mask_request_to_complete_ms_max_total: float = 0.0
var _mountain_surface_dig_visual_patch_skip_count_total: int = 0
var _mountain_torch_shadow_field_mask_cache: Dictionary = {}
var _mountain_torch_shadow_field_debug_state: Dictionary = {}
var _sun_light_angle_deg: float = WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG
var _sun_shadow_length_px: float = WorldVisualLightingProfile.DEFAULT_SHADOW_LENGTH_PX
var _sun_shadow_opacity: float = WorldVisualLightingProfile.DEFAULT_SHADOW_OPACITY
var _sun_shadow_softness_px: float = WorldVisualLightingProfile.DEFAULT_SHADOW_SOFTNESS_PX
# Daylight factor (1 day, 0 night) for the cosmetic ground shade's directional
# component. Same source as the shadows: WorldVisualLightingProfile.
var _sun_day_factor: float = 1.0
var _mining_feedback_layer: MiningFeedbackLayer = null


func _ready() -> void:
	add_to_group("chunk_manager")
	name = "WorldStreamer"
	_apply_worldgen_settings(
		MountainGenSettings.hard_coded_defaults(),
		WorldBoundsSettings.hard_coded_defaults(),
		FoundationGenSettings.hard_coded_defaults(),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
		_make_new_world_plains_tree_settings(),
		_make_new_world_plains_small_rock_settings(),
	)
	WorldTileSetFactory.bootstrap()
	_ensure_mountain_mask_sources()
	_ensure_terrain_edge_mask_sources()
	_ensure_grass_blob_overlay_source()
	_ensure_plains_living_flora_source()
	_ensure_plains_spiky_flora_source()
	_packet_backend.start(PACKET_WORKER_COUNT)
	_mountain_mask_backend.start(MOUNTAIN_MASK_WORKER_COUNT)
	_stream_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		1.5,
		_streaming_tick,
		&"world.streaming_v0",
		RuntimeWorkTypes.CadenceKind.NEAR_PLAYER,
		RuntimeWorkTypes.ThreadingRole.COMPUTE_THEN_APPLY,
		true,
		"World runtime V0 streaming",
	)
	_mountain_native_mask_visual_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_VISUAL,
		MOUNTAIN_NATIVE_MASK_VISUAL_UPLOAD_BUDGET_MS,
		_mountain_native_mask_visual_apply_tick,
		&"world.mountain_native_mask_visual_upload",
		RuntimeWorkTypes.CadenceKind.PRESENTATION,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"World native mountain mask visual upload",
	)
	if EventBus and not EventBus.time_tick.is_connected(_on_time_tick):
		EventBus.time_tick.connect(_on_time_tick)
	_sync_sun_lighting_from_time(true)
	_ensure_mining_feedback_layer()


func _exit_tree() -> void:
	if EventBus and EventBus.time_tick.is_connected(_on_time_tick):
		EventBus.time_tick.disconnect(_on_time_tick)
	if _stream_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_stream_job_id)
	if _mountain_native_mask_visual_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_mountain_native_mask_visual_job_id)
	_packet_backend.stop()
	_mountain_mask_backend.stop()


func initialize_new_world(
		seed_value: int,
		settings: MountainGenSettings,
		world_bounds: WorldBoundsSettings = null,
		foundation_settings: FoundationGenSettings = null,
		lake_settings: LakeGenSettings = null,
		plains_tree_settings: PlainsTreePlacementSettings = null,
		plains_small_rock_settings: PlainsSmallRockPlacementSettings = null,
) -> void:
	_pending_new_world_settings = _clone_worldgen_settings(settings)
	_pending_new_world_bounds = _clone_world_bounds(world_bounds)
	_pending_new_foundation_settings = _clone_foundation_settings(
		foundation_settings,
		_pending_new_world_bounds,
	)
	_pending_new_lake_settings = _clone_lake_settings(lake_settings)
	_pending_new_plains_tree_settings = _make_new_world_plains_tree_settings(plains_tree_settings)
	_pending_new_plains_small_rock_settings = _make_new_world_plains_small_rock_settings(plains_small_rock_settings)
	reset_for_new_game(seed_value, WorldRuntimeConstants.WORLD_VERSION)


func reset_for_new_game(
		seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		version: int = WorldRuntimeConstants.WORLD_VERSION,
) -> void:
	world_seed = seed
	world_version = version
	if _pending_new_world_settings != null:
		_apply_worldgen_settings(
			_pending_new_world_settings,
			_pending_new_world_bounds,
			_pending_new_foundation_settings,
			_pending_new_lake_settings,
			_pending_new_plains_tree_settings,
			_pending_new_plains_small_rock_settings,
		)
	else:
		var default_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
		_apply_worldgen_settings(
			MountainGenSettings.hard_coded_defaults(),
			default_bounds,
			FoundationGenSettings.for_bounds(default_bounds),
			LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
			_make_new_world_plains_tree_settings(),
			_make_new_world_plains_small_rock_settings(),
		)
	_pending_new_world_settings = null
	_pending_new_world_bounds = null
	_pending_new_foundation_settings = null
	_pending_new_lake_settings = null
	_pending_new_plains_tree_settings = null
	_pending_new_plains_small_rock_settings = null
	_diff_store.clear()
	_reset_runtime_state()
	_queue_new_game_spawn_resolution()
	EventBus.world_initialized.emit(world_seed)


func load_world_state(data: Dictionary) -> bool:
	var loaded_world_version: int = int(data.get("world_version", -1))
	if not WorldRuntimeConstants.is_current_world_version(loaded_world_version):
		_reject_world_save(
			"world.json world_version %d is incompatible with current world_version %d. Pre-alpha world saves are not migrated." % [
				loaded_world_version,
				WorldRuntimeConstants.WORLD_VERSION,
			],
		)
		return false
	if not _validate_current_world_save_shape(data):
		return false
	world_seed = int(data.get("world_seed", WorldRuntimeConstants.DEFAULT_WORLD_SEED))
	world_version = loaded_world_version
	_pending_new_world_settings = null
	_pending_new_world_bounds = null
	_pending_new_foundation_settings = null
	_pending_new_lake_settings = null
	_pending_new_plains_tree_settings = null
	_pending_new_plains_small_rock_settings = null
	var loaded_bounds: WorldBoundsSettings = _load_world_bounds_from_save(data)
	_apply_worldgen_settings(
		_load_worldgen_settings_from_save(data),
		loaded_bounds,
		_load_foundation_settings_from_save(data, loaded_bounds),
		_load_lake_settings_from_save(data),
		_load_plains_tree_settings_from_save(data),
		_load_plains_small_rock_settings_from_save(data),
	)
	_diff_store.clear()
	_reset_runtime_state()
	_awaiting_new_game_spawn_result = false
	_new_game_spawn_failed = false
	EventBus.world_initialized.emit(world_seed)
	return true


func save_world_state() -> Dictionary:
	var current_settings: MountainGenSettings = _worldgen_settings
	var worldgen_settings: Dictionary = {
		"mountains": current_settings.to_save_dict(),
	}
	if WorldRuntimeConstants.uses_world_foundation(world_version):
		worldgen_settings["world_bounds"] = _world_bounds_settings.to_save_dict()
		worldgen_settings["foundation"] = _foundation_settings.to_save_dict()
		worldgen_settings["lakes"] = _lake_settings.to_save_dict()
		worldgen_settings["plains_trees"] = _plains_tree_settings.to_save_dict()
		worldgen_settings["plains_small_rocks"] = _plains_small_rock_settings.to_save_dict()
	return {
		"world_rebuild_frozen": false,
		"world_scene_present": true,
		"world_seed": world_seed,
		"world_version": world_version,
		"worldgen_settings": worldgen_settings,
		"worldgen_signature": _compute_worldgen_signature(worldgen_settings),
	}


func collect_chunk_diffs() -> Array[Dictionary]:
	return _diff_store.serialize_dirty_chunks()


func load_chunk_diffs(entries: Array) -> void:
	_diff_store.load_serialized_chunks(entries)
	_refresh_loaded_packets_from_diffs()


func get_world_seed() -> int:
	return world_seed


func get_world_version() -> int:
	return world_version


func toggle_debug_tile_grid() -> bool:
	_debug_tile_grid_visible = not _debug_tile_grid_visible
	_apply_debug_overlay_visibility_to_loaded_chunks()
	return _debug_tile_grid_visible


func toggle_debug_mountain_solid_mask() -> bool:
	_debug_mountain_solid_visible = not _debug_mountain_solid_visible
	_refresh_debug_visuals_for_loaded_chunks()
	return _debug_mountain_solid_visible


func toggle_debug_mountain_contour() -> bool:
	_debug_mountain_contour_visible = not _debug_mountain_contour_visible
	_refresh_debug_visuals_for_loaded_chunks()
	return _debug_mountain_contour_visible


## F11: рамки коллайдеров камней/валунов/деревьев (Factorio-style), presentation only.
func toggle_debug_object_collisions() -> bool:
	_debug_object_collisions_visible = not _debug_object_collisions_visible
	_apply_object_collision_debug_visibility_to_loaded_chunks()
	return _debug_object_collisions_visible


func _apply_object_collision_debug_visibility_to_loaded_chunks() -> void:
	for chunk_coord_variant: Variant in _chunk_views.keys():
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord_variant) as ChunkView
		if chunk_view == null:
			continue
		chunk_view.set_debug_object_collisions_visible(_debug_object_collisions_visible)


func get_mountain_contour_debug_state(chunk_coord: Vector2i) -> Dictionary:
	var chunk_view: ChunkView = _chunk_views.get(_canonicalize_chunk_coord(chunk_coord)) as ChunkView
	if chunk_view == null:
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
		}
	var debug_state: Dictionary = chunk_view.get_mountain_contour_debug_state()
	debug_state["ready"] = true
	return debug_state


func get_mountain_mask_runtime_debug_state() -> Dictionary:
	var visible_chunk_count: int = 0
	var ready_native_mask_chunk_count: int = 0
	var native_mask_visual_ready_count: int = 0
	var native_mask_visual_pending_count: int = 0
	var native_mask_pixels: int = 0
	var native_mask_solid_samples: int = 0
	var ready_terrain_edge_mask_chunk_count: int = 0
	var terrain_edge_mask_visual_ready_count: int = 0
	var terrain_edge_mask_visual_pending_count: int = 0
	var terrain_ground_visible_chunk_count: int = 0
	var terrain_ground_visible_without_mask_count: int = 0
	var terrain_ground_visible_without_visual_count: int = 0
	for chunk_view_variant: Variant in _chunk_views.values():
		var chunk_view: ChunkView = chunk_view_variant as ChunkView
		if chunk_view == null:
			continue
		visible_chunk_count += 1
		var chunk_coord: Vector2i = chunk_view.chunk_coord
		var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
		var native_debug: Dictionary = chunk_view.get_mountain_native_mask_debug_state()
		if bool(native_debug.get("native_mask_active", false)):
			ready_native_mask_chunk_count += 1
			native_mask_pixels += int(native_debug.get("mask_width", 0)) * int(native_debug.get("mask_height", 0))
			native_mask_solid_samples += int(native_debug.get("solid_sample_count", 0))
		if bool(native_debug.get("native_mask_visual_ready", false)):
			native_mask_visual_ready_count += 1
		if bool(native_debug.get("native_mask_visual_pending", false)):
			native_mask_visual_pending_count += 1
		var terrain_edge_debug: Dictionary = chunk_view.get_terrain_edge_mask_debug_state()
		if bool(terrain_edge_debug.get("terrain_edge_mask_active", false)):
			ready_terrain_edge_mask_chunk_count += 1
		if bool(terrain_edge_debug.get("visual_ready", false)):
			terrain_edge_mask_visual_ready_count += 1
		if bool(terrain_edge_debug.get("visual_pending", false)):
			terrain_edge_mask_visual_pending_count += 1
		if _packet_has_terrain_ground(packet):
			terrain_ground_visible_chunk_count += 1
			if not bool(terrain_edge_debug.get("terrain_edge_mask_active", false)):
				terrain_ground_visible_without_mask_count += 1
			if not bool(terrain_edge_debug.get("visual_ready", false)):
				terrain_ground_visible_without_visual_count += 1
	var snapshot: Dictionary = _last_mountain_mask_result.duplicate(true)
	snapshot["stream_radius_chunks"] = _current_stream_radius_chunks
	snapshot["page_source_radius_chunks"] = MOUNTAIN_MASK_SOURCE_RADIUS_CHUNKS
	snapshot["page_worker_count"] = MOUNTAIN_MASK_WORKER_COUNT
	snapshot["ready_page_count"] = ready_native_mask_chunk_count
	snapshot["ready_view_page_count"] = ready_native_mask_chunk_count
	snapshot["page_backend_pending"] = _mountain_mask_backend.has_pending_requests()
	snapshot["page_backend_completed"] = _mountain_mask_backend.has_completed_mountain_rasters() \
			or _mountain_mask_backend.has_completed_mountain_halo_masks()
	snapshot["native_mask_cached_count"] = _mountain_native_masks_by_chunk.size()
	snapshot["native_mask_inflight_count"] = _mountain_native_mask_inflight_chunks.size()
	snapshot["preset_path"] = MOUNTAIN_MASK_PRESET_PATH
	snapshot["desired_mountain_chunk_count"] = 0
	snapshot["missing_mountain_chunk_count"] = 0
	snapshot["packet_count"] = _chunk_packets.size()
	snapshot["source_packet_count"] = _chunk_packets.size()
	snapshot["display_packet_count"] = ready_native_mask_chunk_count
	snapshot["queued_source_chunks"] = snapshot.get("source_chunks", [])
	snapshot["hit_mask_ready"] = int(snapshot.get("hit_mask_width", 0)) > 0 \
			and int(snapshot.get("hit_mask_height", 0)) > 0
	snapshot["request_in_flight"] = bool(snapshot["page_backend_pending"]) \
			or bool(snapshot["page_backend_completed"]) \
			or not _mountain_native_mask_inflight_chunks.is_empty()
	snapshot["layer_count"] = ready_native_mask_chunk_count
	snapshot["applied_source_chunk_count"] = ready_native_mask_chunk_count
	snapshot["display_ready"] = true
	snapshot["display_layer"] = _last_mountain_mask_result.duplicate(true)
	snapshot["layer"] = snapshot.duplicate(true)
	snapshot["native_mask_runtime_enabled"] = MOUNTAIN_NATIVE_MASK_RUNTIME_ENABLED
	snapshot["legacy_page_runtime_enabled"] = false
	snapshot["visible_chunk_count"] = visible_chunk_count
	snapshot["ready_native_mask_chunk_count"] = ready_native_mask_chunk_count
	snapshot["native_mask_pixel_count"] = native_mask_pixels
	snapshot["native_mask_solid_sample_count"] = native_mask_solid_samples
	snapshot["native_mask_visual_ready_count"] = native_mask_visual_ready_count
	snapshot["native_mask_visual_pending_count"] = native_mask_visual_pending_count
	snapshot["native_mask_visual_upload_queue_count"] = _pending_mountain_native_mask_visual_upload_chunks.size()
	snapshot["chunk_visibility_waiting_for_roof_count"] = _pending_chunk_visibility_after_mountain_visual.size()
	snapshot["native_mask_visual_upload_count_total"] = _mountain_native_mask_visual_upload_count_total
	snapshot["native_mask_visual_upload_count_last_tick"] = _mountain_native_mask_visual_upload_count_last_tick
	snapshot["native_mask_visual_upload_elapsed_ms_last"] = _mountain_native_mask_visual_upload_elapsed_ms_last
	snapshot["native_mask_visual_upload_elapsed_ms_max_total"] = _mountain_native_mask_visual_upload_elapsed_ms_max_total
	snapshot["native_mask_visual_upload_last_chunk"] = _mountain_native_mask_visual_upload_last_chunk
	snapshot["native_mask_visible_republish_skip_count_total"] = _mountain_native_mask_visible_republish_skip_count_total
	snapshot["native_mask_worker_elapsed_ms_last"] = _mountain_native_mask_worker_elapsed_ms_last
	snapshot["native_mask_worker_elapsed_ms_max_total"] = _mountain_native_mask_worker_elapsed_ms_max_total
	snapshot["native_mask_request_to_complete_ms_last"] = _mountain_native_mask_request_to_complete_ms_last
	snapshot["native_mask_request_to_complete_ms_max_total"] = _mountain_native_mask_request_to_complete_ms_max_total
	snapshot["mountain_surface_dig_visual_patch_skip_count_total"] = _mountain_surface_dig_visual_patch_skip_count_total
	snapshot["native_mask_pixels_per_tile"] = MOUNTAIN_HALO_MASK_PIXELS_PER_TILE
	snapshot["native_mask_halo_radius_tiles"] = MOUNTAIN_HALO_MASK_RADIUS_TILES
	snapshot["native_mask_build_count_total"] = _mountain_native_mask_build_count_total
	snapshot["native_mask_clear_count_total"] = _mountain_native_mask_clear_count_total
	snapshot["native_mask_build_count_tick"] = _mountain_native_mask_build_count_tick
	snapshot["native_mask_build_count_last_tick"] = _mountain_native_mask_build_count_last_tick
	snapshot["native_mask_build_count_max_tick"] = _mountain_native_mask_build_count_max_tick
	snapshot["native_mask_elapsed_ms_last"] = _mountain_native_mask_elapsed_ms_last
	snapshot["native_mask_elapsed_ms_max_total"] = _mountain_native_mask_elapsed_ms_max_total
	snapshot["native_mask_elapsed_ms_max_tick"] = _mountain_native_mask_elapsed_ms_max_tick
	snapshot["native_mask_elapsed_ms_last_tick_max"] = _mountain_native_mask_elapsed_ms_last_tick_max
	snapshot["native_mask_last_chunk"] = _mountain_native_mask_last_chunk
	snapshot["native_mask_last_reason"] = _mountain_native_mask_last_reason
	snapshot["native_mask_last_refreshed_chunks"] = _mountain_native_mask_last_refreshed_chunks
	snapshot["terrain_edge_mask_runtime_enabled"] = TERRAIN_EDGE_MASK_RUNTIME_ENABLED
	snapshot["terrain_edge_mask_cached_count"] = _terrain_edge_masks_by_chunk.size()
	snapshot["terrain_edge_mask_inflight_count"] = _terrain_edge_mask_inflight_chunks.size()
	snapshot["terrain_edge_mask_visual_upload_queue_count"] = _pending_terrain_edge_mask_visual_upload_chunks.size()
	snapshot["grass_scatter_visual_upload_queue_count"] = _pending_grass_scatter_visual_upload_chunks.size()
	snapshot["ready_terrain_edge_mask_chunk_count"] = ready_terrain_edge_mask_chunk_count
	snapshot["terrain_edge_mask_visual_ready_count"] = terrain_edge_mask_visual_ready_count
	snapshot["terrain_edge_mask_visual_pending_count"] = terrain_edge_mask_visual_pending_count
	snapshot["terrain_ground_visible_chunk_count"] = terrain_ground_visible_chunk_count
	snapshot["terrain_ground_visible_without_mask_count"] = terrain_ground_visible_without_mask_count
	snapshot["terrain_ground_visible_without_visual_count"] = terrain_ground_visible_without_visual_count
	snapshot["terrain_edge_mask_last_result"] = _last_terrain_edge_mask_result.duplicate(true)
	return snapshot


func get_chunk_packet(chunk_coord: Vector2i) -> Dictionary:
	return _chunk_packets.get(chunk_coord, { }) as Dictionary


func get_mountain_cover_sample(world_tile: Vector2i) -> Dictionary:
	return _mountain_cavity_cache.get_sample(
		world_tile,
		Callable(self, "_sample_mountain_cover_tile"),
	)


## Resolve tile ownership first, then retain/enter a nearby cavity only inside
## the real organic excavation delta (C solid, S open). This prevents the roof
## from snapping shut when the player's centre stands in a walkable curved
## corner just outside the square DUG source cell.
func resolve_mountain_cover_at_world(
		world_pos: Vector2,
		preferred_component_id: int = 0,
) -> Dictionary:
	var player_tile: Vector2i = _canonicalize_tile_coord(
		WorldRuntimeConstants.world_to_tile(world_pos),
	)
	var exact_sample: Dictionary = get_mountain_cover_sample(player_tile)
	if not bool(exact_sample.get("ready", false)):
		return exact_sample
	var exact_component_id: int = int(exact_sample.get("component_id", 0))
	if _mountain_cavity_cache.has_component(exact_component_id):
		exact_sample["resolved_from_organic_cutout"] = false
		return exact_sample

	var remaining_hit: Dictionary = _sample_mountain_remaining_mass_hit(world_pos)
	var closed_hit: Dictionary = _sample_mountain_closed_roof_hit(world_pos)
	if not bool(remaining_hit.get("ready", false)) \
			or not bool(remaining_hit.get("in_bounds", false)) \
			or bool(remaining_hit.get("solid", false)) \
			or not bool(closed_hit.get("ready", false)) \
			or not bool(closed_hit.get("in_bounds", false)) \
			or not bool(closed_hit.get("solid", false)):
		exact_sample["resolved_from_organic_cutout"] = false
		return exact_sample

	var best_sample: Dictionary = { }
	var best_distance_sq: float = INF
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			if offset_x == 0 and offset_y == 0:
				continue
			var candidate_tile: Vector2i = _canonicalize_tile_coord(
				player_tile + Vector2i(offset_x, offset_y),
			)
			var candidate: Dictionary = get_mountain_cover_sample(candidate_tile)
			var candidate_component_id: int = int(candidate.get("component_id", 0))
			if not bool(candidate.get("ready", false)) \
					or not _mountain_cavity_cache.has_component(candidate_component_id):
				continue
			if candidate_component_id == preferred_component_id:
				candidate["resolved_from_organic_cutout"] = true
				candidate["organic_probe_tile"] = player_tile
				return candidate
			var distance_sq: float = _wrapped_distance_squared_to_tile_center(
				world_pos,
				candidate_tile,
			)
			if distance_sq < best_distance_sq:
				best_distance_sq = distance_sq
				best_sample = candidate
	if best_sample.is_empty():
		exact_sample["resolved_from_organic_cutout"] = false
		return exact_sample
	best_sample["resolved_from_organic_cutout"] = true
	best_sample["organic_probe_tile"] = player_tile
	return best_sample


func _wrapped_distance_squared_to_tile_center(
		world_pos: Vector2,
		candidate_tile: Vector2i,
) -> float:
	var candidate_world: Vector2 = WorldRuntimeConstants.tile_to_world_center(candidate_tile)
	var delta_x: float = absf(candidate_world.x - world_pos.x)
	if _uses_finite_world_bounds():
		var world_width_px: float = float(
			_world_bounds_settings.width_tiles * WorldRuntimeConstants.TILE_SIZE_PX,
		)
		if world_width_px > 0.0:
			delta_x = fposmod(delta_x, world_width_px)
			delta_x = minf(delta_x, world_width_px - delta_x)
	var delta_y: float = candidate_world.y - world_pos.y
	return delta_x * delta_x + delta_y * delta_y


func get_mountain_cover_debug_snapshot(world_tile: Vector2i) -> Dictionary:
	var debug_snapshot: Dictionary = _mountain_cavity_cache.get_debug_snapshot(
		world_tile,
		_active_cover_component_id,
		Callable(self, "_sample_mountain_cover_tile"),
	)
	debug_snapshot["active_mountain_id"] = _active_cover_mountain_id
	debug_snapshot["active_component_id"] = _active_cover_component_id
	debug_snapshot["roof_layers_per_chunk_max"] = roof_layers_per_chunk_max
	return debug_snapshot


func get_mountain_cover_render_debug_snapshot(world_tile: Vector2i) -> Dictionary:
	var probe_tile: Vector2i = _canonicalize_tile_coord(_resolve_cover_debug_probe_tile(world_tile))
	var probe_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(probe_tile)
	var probe_local: Vector2i = WorldRuntimeConstants.tile_to_local(probe_tile)
	var probe_sample: Dictionary = get_mountain_cover_sample(probe_tile)
	var expected_open_bit: int = -1
	var visible_mask: PackedByteArray = _mountain_cavity_cache.build_chunk_visibility_mask(
		probe_chunk,
		_active_cover_component_id,
	)
	var probe_index: int = WorldRuntimeConstants.local_to_index(probe_local)
	if probe_index >= 0 and probe_index < visible_mask.size():
		expected_open_bit = int(visible_mask[probe_index])
	var debug_snapshot := {
		"ready": true,
		"probe_tile": probe_tile,
		"probe_chunk": probe_chunk,
		"probe_local": probe_local,
		"probe_mountain_id": int(probe_sample.get("mountain_id", 0)),
		"probe_component_id": int(probe_sample.get("component_id", 0)),
		"probe_is_opening": bool(probe_sample.get("is_opening", false)),
		"expected_open_bit": expected_open_bit,
		"chunk_view_ready": false,
	}
	var chunk_view: ChunkView = _chunk_views.get(probe_chunk) as ChunkView
	if chunk_view == null:
		return debug_snapshot
	debug_snapshot["chunk_view_ready"] = true
	var render_debug: Dictionary = chunk_view.get_cover_render_debug(
		probe_local,
		int(probe_sample.get("mountain_id", 0)),
		expected_open_bit,
	)
	for key_variant: Variant in render_debug.keys():
		debug_snapshot[key_variant] = render_debug[key_variant]
	return debug_snapshot


func get_mountain_torch_shadow_field_mask(torch_world_pos: Vector2, radius_px: float) -> Dictionary:
	var debug_start_usec: int = Time.get_ticks_usec()
	var step_px: float = float(WorldRuntimeConstants.TILE_SIZE_PX) / float(MOUNTAIN_HALO_MASK_PIXELS_PER_TILE)
	var safe_radius: float = maxf(radius_px, float(WorldRuntimeConstants.TILE_SIZE_PX))
	var window_snap: float = maxf(MOUNTAIN_TORCH_SHADOW_FIELD_WINDOW_SNAP_PX, step_px)
	var origin := Vector2(
		floorf((torch_world_pos.x - safe_radius) / window_snap) * window_snap,
		floorf((torch_world_pos.y - safe_radius) / window_snap) * window_snap,
	)
	var width: int = ceili((safe_radius * 2.0 + window_snap) / step_px)
	var height: int = width
	var chunks: Array[Vector2i] = _build_chunk_coords_for_world_rect(
		origin,
		origin + Vector2(float(width), float(height)) * step_px,
	)
	var ready_results: Dictionary = {}
	var any_solid: bool = false
	var pending: bool = false
	var signature_parts: Array[String] = [
		"epoch=%d:%d,%d,%d,%d:component=%d" % [
			_generation_epoch,
			roundi(origin.x),
			roundi(origin.y),
			width,
			height,
			_active_cover_component_id,
		],
	]
	for chunk_coord: Vector2i in chunks:
		chunk_coord = _canonicalize_chunk_coord(chunk_coord)
		var revision: int = _get_mountain_mask_revision(chunk_coord)
		if not _has_loaded_mountain_halo_sources(chunk_coord):
			pending = true
			signature_parts.append("%s:%d:loading" % [str(chunk_coord), revision])
			continue
		var halo: Dictionary = _get_cached_mountain_solid_halo(chunk_coord)
		var has_any: bool = bool(halo.get("has_closed", false))
		signature_parts.append("%s:%d:%s" % [str(chunk_coord), revision, "solid" if has_any else "empty"])
		if not has_any:
			continue
		any_solid = true
		var result: Dictionary = _get_ready_mountain_native_mask_result(chunk_coord)
		if result.is_empty():
			_request_mountain_native_mask_for_chunk(
				chunk_coord,
				halo.get("closed_halo", PackedByteArray()) as PackedByteArray,
				halo.get("dug_halo", PackedByteArray()) as PackedByteArray,
				&"torch_shadow_field",
			)
			pending = true
			continue
		ready_results[chunk_coord] = result
	if not any_solid:
		_record_mountain_torch_shadow_field_debug(
			debug_start_usec,
			origin,
			width,
			height,
			chunks.size(),
			false,
			false,
			false,
			0,
			&"empty",
		)
		return {
			"ready": true,
			"mask": PackedByteArray(),
			"width": 0,
			"height": 0,
			"step_px": step_px,
			"origin_world": origin,
			"solid_sample_count": 0,
			"signature": "|".join(signature_parts),
		}
	if pending:
		_record_mountain_torch_shadow_field_debug(
			debug_start_usec,
			origin,
			width,
			height,
			chunks.size(),
			false,
			false,
			true,
			0,
			&"pending",
		)
		return {
			"ready": false,
			"pending": true,
			"signature": "|".join(signature_parts),
		}
	var signature: String = "|".join(signature_parts)
	var cached: Dictionary = _mountain_torch_shadow_field_mask_cache.get("last", {}) as Dictionary
	if not cached.is_empty() and str(cached.get("signature", "")) == signature:
		_record_mountain_torch_shadow_field_debug(
			debug_start_usec,
			origin,
			width,
			height,
			chunks.size(),
			true,
			false,
			false,
			int(cached.get("solid_sample_count", 0)),
			&"cache_hit",
		)
		return cached
	var bytes := PackedByteArray()
	bytes.resize(width * height)
	var solid_count: int = 0
	var chunk_size_px: float = float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
	var floor_masks_by_chunk: Dictionary = { }
	for chunk_variant: Variant in ready_results.keys():
		var chunk_coord: Vector2i = chunk_variant as Vector2i
		var result: Dictionary = ready_results.get(chunk_coord, {}) as Dictionary
		var chunk_origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
		solid_count += _blit_mountain_native_mask_result_to_shadow_field(
			result,
			origin,
			width,
			height,
			step_px,
			chunk_origin,
			chunk_origin + Vector2.ONE * chunk_size_px,
			bytes,
			_build_cover_floor_visibility_halo(chunk_coord, floor_masks_by_chunk),
		)
	cached = {
		"ready": true,
		"mask": bytes,
		"width": width,
		"height": height,
		"step_px": step_px,
		"origin_world": origin,
		"solid_sample_count": solid_count,
		"signature": signature,
	}
	_mountain_torch_shadow_field_mask_cache["last"] = cached
	_record_mountain_torch_shadow_field_debug(
		debug_start_usec,
		origin,
		width,
		height,
		chunks.size(),
		false,
		true,
		false,
		solid_count,
		&"composed",
	)
	return cached


func get_mountain_torch_shadow_field_debug_state() -> Dictionary:
	return _mountain_torch_shadow_field_debug_state.duplicate()


func _record_mountain_torch_shadow_field_debug(
		start_usec: int,
		origin: Vector2,
		width: int,
		height: int,
		chunk_count: int,
		cache_hit: bool,
		composed: bool,
		pending: bool,
		solid_sample_count: int,
		reason: StringName,
) -> void:
	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	var previous_max: float = float(_mountain_torch_shadow_field_debug_state.get("elapsed_ms_max", 0.0))
	var previous_compose_count: int = int(_mountain_torch_shadow_field_debug_state.get("compose_count", 0))
	var previous_cache_hit_count: int = int(_mountain_torch_shadow_field_debug_state.get("cache_hit_count", 0))
	_mountain_torch_shadow_field_debug_state = {
		"elapsed_ms_last": elapsed_ms,
		"elapsed_ms_max": maxf(previous_max, elapsed_ms),
		"origin": origin,
		"width": width,
		"height": height,
		"pixel_count": width * height,
		"chunk_count": chunk_count,
		"cache_hit": cache_hit,
		"cache_hit_count": previous_cache_hit_count + (1 if cache_hit else 0),
		"composed": composed,
		"compose_count": previous_compose_count + (1 if composed else 0),
		"pending": pending,
		"solid_sample_count": solid_sample_count,
		"reason": reason,
	}


func set_active_mountain_component(mountain_id: int, component_id: int) -> void:
	var resolved_component_id: int = component_id if _mountain_cavity_cache.has_component(component_id) else 0
	var resolved_mountain_id: int = mountain_id if resolved_component_id > 0 else 0
	if resolved_mountain_id == _active_cover_mountain_id \
			and resolved_component_id == _active_cover_component_id:
		return
	var previous_component_id: int = _active_cover_component_id
	var transition_chunks: Dictionary = { }
	_append_cover_component_chunks(transition_chunks, previous_component_id)
	_append_cover_component_chunks(transition_chunks, resolved_component_id)
	_active_cover_mountain_id = resolved_mountain_id
	_active_cover_component_id = resolved_component_id
	_mountain_torch_shadow_field_mask_cache.clear()
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(transition_chunks))


func is_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	# The diff store is authoritative for an excavated cell. Native contour
	# sampling adds organic collision around neighbouring rock, but it must
	# never resurrect an invisible threshold inside the DUG source tile.
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
		return true
	var world_tile: Vector2i = _canonicalize_tile_coord(
		WorldRuntimeConstants.world_to_tile(world_pos),
	)
	# The visual facade projects into the exterior ground. At a real physical
	# mouth that projection must not pinch the Player's nine-point footprint
	# before its centre reaches the DUG tile. This exemption is only the one
	# walkable apron cell touching an opening; retaining wall tiles still sample
	# their own non-walkable terrain/native mass and remain blocked.
	if bool(tile_data.get("walkable", false)) \
			and _is_mountain_mouth_apron_tile(world_tile):
		return true
	var hit_sample: Dictionary = _sample_mountain_mask_hit(world_pos)
	if _is_ready_mountain_mask_hit_sample(hit_sample):
		if bool(hit_sample.get("solid", false)):
			return false
		if _uses_mountain_surface_presentation(terrain_id):
			return true
	if _uses_mountain_surface_presentation(terrain_id):
		return false
	return bool(tile_data.get("walkable", false))


func _is_mountain_mouth_apron_tile(world_tile: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor_tile: Vector2i = _canonicalize_tile_coord(world_tile + offset)
		var sample: Dictionary = get_mountain_cover_sample(neighbor_tile)
		if bool(sample.get("ready", false)) \
				and bool(sample.get("walkable", false)) \
				and bool(sample.get("is_opening", false)):
			return true
	return false


func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var hit_sample: Dictionary = _sample_mountain_mask_hit(world_pos)
	if _is_ready_mountain_mask_hit_sample(hit_sample):
		if not bool(hit_sample.get("solid", false)):
			return false
		return not _resolve_mask_mining_tile(world_pos).is_empty()
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
		return false
	if not _is_diggable_surface_terrain(terrain_id):
		return false
	return HarvestQuery.is_tile_orthogonally_exposed(
		_chunk_local_to_tile(
			tile_data.get("chunk_coord", Vector2i.ZERO) as Vector2i,
			tile_data.get("local_coord", Vector2i.ZERO) as Vector2i,
		),
		Callable(self, "_sample_harvest_gate_tile"),
	)


## DEBUG (F8): describe the terrain + tilemap cell rendered under a world position.
func describe_tile_under_debug(world_pos: Vector2) -> String:
	var probe: Dictionary = _get_tile_data(world_pos)
	if not bool(probe.get("ready", false)):
		return "[G] tile not ready at %s" % str(WorldRuntimeConstants.world_to_tile(world_pos))
	var terrain_id: int = int(probe.get("terrain_id", -1))
	var chunk: Vector2i = probe.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var local: Vector2i = probe.get("local_coord", Vector2i.ZERO) as Vector2i
	var line: String = "[G] tile=%s terrain_id=%d chunk=%s" % [
		str(WorldRuntimeConstants.world_to_tile(world_pos)),
		terrain_id,
		str(chunk),
	]
	var cv: ChunkView = _chunk_views.get(chunk, null) as ChunkView
	if cv != null:
		if cv._base_layer != null:
			line += " base_src=%d base_atlas=%s" % [
				int(cv._base_layer.get_cell_source_id(local)),
				str(cv._base_layer.get_cell_atlas_coords(local)),
			]
		if cv._overlay_layer != null:
			line += " overlay_src=%d" % int(cv._overlay_layer.get_cell_source_id(local))
		line += " mountain_sprite=%s" % str(cv._mountain_top_mask_sprite != null and cv._mountain_top_mask_sprite.visible)
	else:
		line += " (no chunk view loaded)"
	return line


func try_harvest_at_world(world_pos: Vector2) -> Dictionary:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return {
			"success": false,
			"message_key": "SYSTEM_WORLD_CHUNK_NOT_READY",
		}
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var hit_sample: Dictionary = _sample_mountain_mask_hit(world_pos)
	if _is_ready_mountain_mask_hit_sample(hit_sample):
		if not bool(hit_sample.get("solid", false)):
			return {
				"success": false,
				"message_key": "SYSTEM_WORLD_TILE_NOT_DIGGABLE",
			}
		var mining_tile_data: Dictionary = _resolve_mask_mining_tile(world_pos)
		if mining_tile_data.is_empty():
			return {
				"success": false,
				"message_key": "SYSTEM_WORLD_TILE_NOT_DIGGABLE",
			}
		return _commit_harvest_tile(mining_tile_data, world_pos)
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
		return {
			"success": false,
			"message_key": "SYSTEM_WORLD_TILE_NOT_DIGGABLE",
		}
	if not _is_diggable_surface_terrain(terrain_id):
		return {
			"success": false,
			"message_key": "SYSTEM_WORLD_TILE_NOT_DIGGABLE",
		}
	var world_tile: Vector2i = _chunk_local_to_tile(
		tile_data.get("chunk_coord", Vector2i.ZERO) as Vector2i,
		tile_data.get("local_coord", Vector2i.ZERO) as Vector2i,
	)
	if not HarvestQuery.is_tile_orthogonally_exposed(world_tile, Callable(self, "_sample_harvest_gate_tile")):
		return {
			"success": false,
			"message_key": "SYSTEM_WORLD_TILE_NOT_DIGGABLE",
		}

	return _commit_harvest_tile(tile_data)


func _commit_harvest_tile(tile_data: Dictionary, impact_world_pos: Vector2 = Vector2(INF, INF)) -> Dictionary:
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var chunk_coord: Vector2i = tile_data.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var local_coord: Vector2i = tile_data.get("local_coord", Vector2i.ZERO) as Vector2i
	_diff_store.set_tile_override(
		chunk_coord,
		local_coord,
		WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		true,
	)
	_apply_loaded_override(chunk_coord, local_coord, WorldRuntimeConstants.TERRAIN_PLAINS_DUG, true)
	_handle_cover_tile_dug(_chunk_local_to_tile(chunk_coord, local_coord))
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		var mined_world_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_coord)
		_spawn_mountain_mining_feedback(mined_world_tile, impact_world_pos)
		EventBus.mountain_tile_mined.emit(mined_world_tile, terrain_id, WorldRuntimeConstants.TERRAIN_PLAINS_DUG)
	return {
		"success": true,
		"item_id": "base:scrap",
		"amount": 1,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
	}


func _sample_mountain_mask_hit(world_pos: Vector2) -> Dictionary:
	var tile_coord: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(world_pos))
	var owner_chunk: Vector2i = _canonicalize_chunk_coord(WorldRuntimeConstants.tile_to_chunk(tile_coord))
	var owner_view: ChunkView = _chunk_views.get(owner_chunk, null) as ChunkView
	if owner_view != null:
		var owner_sample: Dictionary = owner_view.sample_mountain_page_hit_at_world(world_pos)
		if bool(owner_sample.get("ready", false)) and bool(owner_sample.get("in_bounds", false)):
			return owner_sample
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var chunk_coord: Vector2i = _canonicalize_chunk_coord(owner_chunk + Vector2i(offset_x, offset_y))
			if chunk_coord == owner_chunk:
				continue
			var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
			if chunk_view == null:
				continue
			var sample: Dictionary = chunk_view.sample_mountain_page_hit_at_world(world_pos)
			if bool(sample.get("ready", false)) and bool(sample.get("in_bounds", false)):
				if bool(sample.get("solid", false)):
					return sample
	return {
		"ready": _chunk_views.has(owner_chunk),
		"in_bounds": false,
		"solid": false,
		"chunk_coord": owner_chunk,
	}


func _sample_mountain_closed_roof_hit(world_pos: Vector2) -> Dictionary:
	return _sample_mountain_raw_mask_hit(
		world_pos,
		&"sample_mountain_closed_roof_hit_at_world",
	)


func _sample_mountain_remaining_mass_hit(world_pos: Vector2) -> Dictionary:
	return _sample_mountain_raw_mask_hit(
		world_pos,
		&"sample_mountain_remaining_mass_hit_at_world",
	)


func _sample_mountain_raw_mask_hit(
		world_pos: Vector2,
		chunk_view_method: StringName,
) -> Dictionary:
	var tile_coord: Vector2i = _canonicalize_tile_coord(
		WorldRuntimeConstants.world_to_tile(world_pos),
	)
	var owner_chunk: Vector2i = _canonicalize_chunk_coord(
		WorldRuntimeConstants.tile_to_chunk(tile_coord),
	)
	var owner_view: ChunkView = _chunk_views.get(owner_chunk, null) as ChunkView
	if owner_view != null:
		var owner_sample: Dictionary = owner_view.call(chunk_view_method, world_pos) as Dictionary
		if bool(owner_sample.get("ready", false)) \
				and bool(owner_sample.get("in_bounds", false)):
			return owner_sample
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var chunk_coord: Vector2i = _canonicalize_chunk_coord(
				owner_chunk + Vector2i(offset_x, offset_y),
			)
			if chunk_coord == owner_chunk:
				continue
			var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
			if chunk_view == null:
				continue
			var sample: Dictionary = chunk_view.call(chunk_view_method, world_pos) as Dictionary
			if bool(sample.get("ready", false)) \
					and bool(sample.get("in_bounds", false)):
				return sample
	return {
		"ready": _chunk_views.has(owner_chunk),
		"in_bounds": false,
		"solid": false,
		"chunk_coord": owner_chunk,
	}


func _sample_mountain_raster_hit(world_pos: Vector2) -> Dictionary:
	return _sample_mountain_mask_hit(world_pos)


func _is_ready_mountain_mask_hit_sample(hit_sample: Dictionary) -> bool:
	return bool(hit_sample.get("ready", false)) and bool(hit_sample.get("in_bounds", false))


func _resolve_mask_mining_tile(world_pos: Vector2) -> Dictionary:
	var center_tile: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(world_pos))
	var best_tile_data: Dictionary = { }
	var best_distance_sq: float = INF
	for radius: int in range(MASK_MINING_SEARCH_RADIUS_TILES + 1):
		for y: int in range(center_tile.y - radius, center_tile.y + radius + 1):
			for x: int in range(center_tile.x - radius, center_tile.x + radius + 1):
				if maxi(absi(x - center_tile.x), absi(y - center_tile.y)) != radius:
					continue
				var candidate_tile: Vector2i = _canonicalize_tile_coord(Vector2i(x, y))
				var candidate_data: Dictionary = _get_tile_data(WorldRuntimeConstants.tile_to_world_center(candidate_tile))
				if not bool(candidate_data.get("ready", false)):
					continue
				var terrain_id: int = int(candidate_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
				if not _is_diggable_surface_terrain(terrain_id):
					continue
				if bool(candidate_data.get("walkable", true)):
					continue
				if not HarvestQuery.is_tile_orthogonally_exposed(candidate_tile, Callable(self, "_sample_harvest_gate_tile")):
					continue
				var candidate_center: Vector2 = WorldRuntimeConstants.tile_to_world_center(candidate_tile)
				var distance_sq: float = world_pos.distance_squared_to(candidate_center)
				if best_tile_data.is_empty() or distance_sq < best_distance_sq:
					best_tile_data = candidate_data
					best_tile_data["world_tile"] = candidate_tile
					best_distance_sq = distance_sq
		if not best_tile_data.is_empty():
			return best_tile_data
	return { }


func _streaming_tick() -> bool:
	var timing_records: Dictionary = { }
	var timing_started_usec: int = Time.get_ticks_usec()
	var timing_step_usec: int = timing_started_usec
	_drain_new_game_spawn_result()
	timing_step_usec = _record_streaming_step_timing(timing_records, "spawn", timing_step_usec)
	if _awaiting_new_game_spawn_result or _new_game_spawn_failed:
		return false
	_wrap_local_player_position_if_needed()
	timing_step_usec = _record_streaming_step_timing(timing_records, "wrap", timing_step_usec)
	_update_player_chunk_coord()
	timing_step_usec = _record_streaming_step_timing(timing_records, "player_chunk", timing_step_usec)
	timing_step_usec = _record_streaming_step_timing(timing_records, "object_depth", timing_step_usec)
	_begin_mountain_native_mask_tick_metrics()
	_enqueue_desired_chunks()
	timing_step_usec = _record_streaming_step_timing(timing_records, "enqueue", timing_step_usec)
	_prune_stale_pending_publish_chunks()
	timing_step_usec = _record_streaming_step_timing(timing_records, "prune", timing_step_usec)
	_drain_completed_packets(MAX_PACKET_RESULTS_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(timing_records, "drain_packets", timing_step_usec)
	_drain_completed_native_masks(MAX_MOUNTAIN_NATIVE_MASK_RESULTS_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(timing_records, "drain_native_masks", timing_step_usec)
	_publish_next_batch()
	timing_step_usec = _record_streaming_step_timing(timing_records, "publish", timing_step_usec)
	_evict_outside_ring(1)
	timing_step_usec = _record_streaming_step_timing(timing_records, "evict", timing_step_usec)
	_end_mountain_native_mask_tick_metrics()
	_report_streaming_step_timing(timing_records, timing_started_usec)
	return false


func _queue_mountain_native_mask_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _pending_mountain_native_mask_visual_upload_set.has(chunk_coord):
		return
	_pending_mountain_native_mask_visual_upload_set[chunk_coord] = true
	_pending_mountain_native_mask_visual_upload_chunks.append(chunk_coord)


func _drop_mountain_native_mask_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_pending_mountain_native_mask_visual_upload_set.erase(chunk_coord)
	if _pending_mountain_native_mask_visual_upload_chunks.is_empty():
		return
	var filtered: Array[Vector2i] = []
	for queued_coord: Vector2i in _pending_mountain_native_mask_visual_upload_chunks:
		if queued_coord == chunk_coord:
			continue
		filtered.append(queued_coord)
	_pending_mountain_native_mask_visual_upload_chunks = filtered


func _queue_terrain_edge_mask_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _pending_terrain_edge_mask_visual_upload_set.has(chunk_coord):
		return
	_pending_terrain_edge_mask_visual_upload_set[chunk_coord] = true
	_pending_terrain_edge_mask_visual_upload_chunks.append(chunk_coord)


func _drop_terrain_edge_mask_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_pending_terrain_edge_mask_visual_upload_set.erase(chunk_coord)
	if _pending_terrain_edge_mask_visual_upload_chunks.is_empty():
		return
	var filtered: Array[Vector2i] = []
	for queued_coord: Vector2i in _pending_terrain_edge_mask_visual_upload_chunks:
		if queued_coord == chunk_coord:
			continue
		filtered.append(queued_coord)
	_pending_terrain_edge_mask_visual_upload_chunks = filtered


func _queue_object_packet_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _pending_object_packet_visual_upload_set.has(chunk_coord):
		return
	_pending_object_packet_visual_upload_set[chunk_coord] = true
	_pending_object_packet_visual_upload_chunks.append(chunk_coord)


func _drop_object_packet_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_pending_object_packet_visual_upload_set.erase(chunk_coord)
	if _pending_object_packet_visual_upload_chunks.is_empty():
		return
	var filtered: Array[Vector2i] = []
	for queued_coord: Vector2i in _pending_object_packet_visual_upload_chunks:
		if queued_coord == chunk_coord:
			continue
		filtered.append(queued_coord)
	_pending_object_packet_visual_upload_chunks = filtered


func _queue_grass_scatter_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _pending_grass_scatter_visual_upload_set.has(chunk_coord):
		return
	_pending_grass_scatter_visual_upload_set[chunk_coord] = true
	_pending_grass_scatter_visual_upload_chunks.append(chunk_coord)


func _drop_grass_scatter_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_pending_grass_scatter_visual_upload_set.erase(chunk_coord)
	if _pending_grass_scatter_visual_upload_chunks.is_empty():
		return
	var filtered: Array[Vector2i] = []
	for queued_coord: Vector2i in _pending_grass_scatter_visual_upload_chunks:
		if queued_coord == chunk_coord:
			continue
		filtered.append(queued_coord)
	_pending_grass_scatter_visual_upload_chunks = filtered


# Источники травы готовятся один раз из registry-данных: один shared материал
# на все чанки, packed-параметры собираются из ground sampling_params (единый
# источник полей) плюс sampling_params травы.
func _ensure_grass_scatter_sources() -> void:
	if _grass_scatter_material != null:
		return
	var profile: TerrainPresentationProfile = TerrainPresentationRegistry.get_profile_by_id(
		&"plains:grass_scatter_profile",
	)
	var shader_family: TerrainShaderFamily = TerrainPresentationRegistry.get_shader_family(
		profile.shader_family_id,
	)
	var grass_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		profile.material_set_id,
	)
	var ground_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		&"base:plains_ground_material",
	)
	assert(shader_family != null and shader_family.shader != null, "grass scatter shader family missing")
	assert(grass_set != null and ground_set != null, "grass scatter material sets missing")
	_grass_scatter_atlas = grass_set.get_texture_slot(&"grass_tuft_atlas")
	assert(_grass_scatter_atlas != null, "grass_tuft_atlas missing in plains:grass_scatter_material")
	_grass_shadow_atlas = grass_set.get_texture_slot(&"grass_tuft_shadow_atlas")
	assert(_grass_shadow_atlas != null, "grass_tuft_shadow_atlas missing in plains:grass_scatter_material")
	var grass_params: Dictionary = grass_set.sampling_params
	var ground_params: Dictionary = ground_set.sampling_params
	var material := ShaderMaterial.new()
	material.shader = shader_family.shader
	material.set_shader_parameter("atlas_columns", float(grass_params.get("atlas_columns", 4.0)))
	material.set_shader_parameter("atlas_rows", float(grass_params.get("atlas_rows", 4.0)))
	material.set_shader_parameter("atlas_frame_count", float(grass_params.get("atlas_frame_count", 16.0)))
	material.set_shader_parameter("wind_sway_fraction", float(grass_params.get("wind_sway_fraction", 0.085)))
	material.set_shader_parameter("storm_lean_fraction", float(grass_params.get("storm_lean_fraction", 0.35)))
	material.set_shader_parameter("gust_field_scale_px", WorldVisualWindProfile.GUST_FIELD_SCALE_PX)
	material.set_shader_parameter("gust_field_anisotropy", WorldVisualWindProfile.GUST_FIELD_ANISOTROPY)
	material.set_shader_parameter("local_dir_min_deg", float(grass_params.get("local_dir_min_deg", 5.0)))
	material.set_shader_parameter("local_dir_max_deg", float(grass_params.get("local_dir_max_deg", 26.0)))
	material.set_shader_parameter(
		"local_dir_field_scale_px",
		float(grass_params.get("local_dir_field_scale_px", 1400.0)),
	)
	material.set_shader_parameter("local_dir_gust_gain", float(grass_params.get("local_dir_gust_gain", 0.9)))
	material.set_shader_parameter("intra_tuft_flutter", float(grass_params.get("intra_tuft_flutter", 0.05)))
	_grass_scatter_material = material
	_grass_shadow_atlas_material = ShaderMaterial.new()
	_grass_shadow_atlas_material.shader = shader_family.shader
	_grass_shadow_atlas_material.set_shader_parameter("atlas_columns", float(grass_params.get("atlas_columns", 4.0)))
	_grass_shadow_atlas_material.set_shader_parameter("atlas_rows", float(grass_params.get("atlas_rows", 4.0)))
	_grass_shadow_atlas_material.set_shader_parameter("atlas_frame_count", float(grass_params.get("atlas_frame_count", 16.0)))
	_grass_shadow_atlas_material.set_shader_parameter("wind_sway_fraction", 0.0)
	_grass_shadow_atlas_material.set_shader_parameter("storm_lean_fraction", 0.0)
	_grass_shadow_atlas_material.set_shader_parameter("intra_tuft_flutter", 0.0)
	_grass_shadow_atlas_material.set_shader_parameter("overlay_exact", 1.0)
	_grass_shadow_atlas_material.set_shader_parameter(
		"overlay_alpha",
		float(grass_params.get("directional_shadow_alpha", 0.88)),
	)
	_grass_shadow_material = ShaderMaterial.new()
	_grass_shadow_material.shader = GRASS_SHADOW_SHADER
	_grass_spore_material = ShaderMaterial.new()
	_grass_spore_material.shader = GRASS_SPORE_SHADER
	_grass_scatter_params = PackedFloat32Array(
		[
			float(WorldRuntimeConstants.CHUNK_SIZE),
			float(WorldRuntimeConstants.TILE_SIZE_PX),
			float(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
			float(grass_params.get("candidate_grid_side", 56.0)),
			float(grass_params.get("instance_cap", 4096.0)),
			float(ground_params.get("grass_field_scale_px", 1050.0)),
			float(ground_params.get("grass_coverage", 0.38)),
			float(ground_params.get("orange_field_scale_px", 820.0)),
			float(ground_params.get("orange_coverage", 0.16)),
			float(ground_params.get("rock_field_scale_px", 1900.0)),
			float(ground_params.get("rock_coverage", 0.26)),
			float(grass_params.get("tuft_min_width_px", 34.0)),
			float(grass_params.get("tuft_max_width_px", 58.0)),
			float(grass_params.get("tuft_min_height_px", 30.0)),
			float(grass_params.get("tuft_max_height_px", 52.0)),
			float(grass_params.get("height_scale", 0.7)),
			float(grass_params.get("density_scale", 1.0)),
			float(grass_params.get("orange_density_boost", 0.65)),
			float(grass_params.get("dry_frame_count", 16.0)),
			float(grass_params.get("base_tint_min", 0.8)),
			float(grass_params.get("base_tint_max", 1.16)),
			float(grass_params.get("orange_tint_boost", 0.18)),
			float(grass_params.get("alpha_min", 0.82)),
			float(grass_params.get("alpha_max", 0.97)),
			float(grass_params.get("orange_frame_base", 16.0)),
			float(grass_params.get("orange_frame_count", 16.0)),
			float(grass_params.get("orange_bank_low", 0.12)),
			float(grass_params.get("orange_bank_high", 0.45)),
			float(grass_params.get("shadow_size_scale", 0.9)),
			float(grass_params.get("shadow_alpha", 0.28)),
			float(grass_params.get("shadow_min_size_unit", 0.4)),
			float(grass_params.get("spore_orange_threshold", 0.28)),
			float(grass_params.get("spore_chance", 0.07)),
			float(grass_params.get("spore_size_px", 7.0)),
			float(ground_params.get("macro_mass_scale_px", 7000.0)),
			float(ground_params.get("macro_mass_strength", 0.34)),
			float(ground_params.get("path_scale_px", 2600.0)),
			float(ground_params.get("path_width", 0.06)),
			float(ground_params.get("path_warp_px", 700.0)),
			float(ground_params.get("path_strength", 0.85)),
		],
	)
	_grass_lod_full_zoom = float(grass_params.get("lod_full_zoom", 0.8))
	_grass_lod_min_zoom = float(grass_params.get("lod_min_zoom", 0.18))
	_grass_lod_min_fraction = float(grass_params.get("lod_min_fraction", 0.35))


func _mountain_native_mask_visual_apply_tick() -> bool:
	# Process as many queued visual uploads as fit in the time budget. The old
	# one-upload-per-tick pacing turned a sprint (dozens of queued chunks) into
	# seconds of pop-in tail while each frame did ~0.1 ms of work.
	_mountain_native_mask_visual_upload_count_last_tick = 0
	var budget_usec: int = int(MOUNTAIN_NATIVE_MASK_VISUAL_UPLOAD_BUDGET_MS * 1000.0)
	var tick_started_usec: int = Time.get_ticks_usec()
	while not _pending_mountain_native_mask_visual_upload_chunks.is_empty():
		var chunk_coord: Vector2i = _pending_mountain_native_mask_visual_upload_chunks.pop_front()
		_pending_mountain_native_mask_visual_upload_set.erase(chunk_coord)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view == null:
			continue
		var step_started: int = WorldPerfProbe.begin()
		_ensure_mountain_mask_sources()
		WorldPerfProbe.end("WorldStreamer.visual_upload.ensure_mountain_sources", step_started)
		var started_usec: int = Time.get_ticks_usec()
		var applied: bool = chunk_view.apply_pending_mountain_native_mask_visual(
			_mountain_top_fill_texture,
			_mountain_face_fill_texture,
			_mountain_top_normal_fill_texture,
			_mountain_face_normal_fill_texture,
			_mountain_foothill_texture,
			_mountain_foothill_normal_texture,
		)
		if not applied:
			_finalize_pending_chunk_visibility(chunk_coord)
			continue
		var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
		_mountain_native_mask_visual_upload_count_total += 1
		_mountain_native_mask_visual_upload_count_last_tick += 1
		_mountain_native_mask_visual_upload_elapsed_ms_last = elapsed_ms
		_mountain_native_mask_visual_upload_elapsed_ms_max_total = maxf(
			_mountain_native_mask_visual_upload_elapsed_ms_max_total,
			elapsed_ms,
		)
		_mountain_native_mask_visual_upload_last_chunk = chunk_coord
		_finalize_pending_chunk_visibility(chunk_coord)
		if Time.get_ticks_usec() - tick_started_usec >= budget_usec:
			return false
	while not _pending_terrain_edge_mask_visual_upload_chunks.is_empty():
		var chunk_coord: Vector2i = _pending_terrain_edge_mask_visual_upload_chunks.pop_front()
		_pending_terrain_edge_mask_visual_upload_set.erase(chunk_coord)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view == null:
			continue
		var step_started: int = WorldPerfProbe.begin()
		_ensure_terrain_edge_mask_sources()
		WorldPerfProbe.end("WorldStreamer.visual_upload.ensure_terrain_sources", step_started)
		if chunk_view.apply_pending_terrain_edge_mask_visual(
			_terrain_edge_top_texture,
			_terrain_edge_face_texture,
			_terrain_edge_top_normal_texture,
			_terrain_edge_face_normal_texture,
			_grass_blob_overlay_texture,
			_grass_blob_overlay_texture_2,
			_grass_blob_overlay_texture_3,
			_grass_blob_overlay_normal_texture,
			_mountain_foothill_texture,
			_mountain_foothill_normal_texture,
		):
			if Time.get_ticks_usec() - tick_started_usec >= budget_usec:
				return false
	while not _pending_object_packet_visual_upload_chunks.is_empty():
		var chunk_coord: Vector2i = _pending_object_packet_visual_upload_chunks.pop_front()
		_pending_object_packet_visual_upload_set.erase(chunk_coord)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view == null:
			continue
		var object_started: int = WorldPerfProbe.begin()
		var object_applied: bool = chunk_view.apply_pending_object_packet_visual()
		if object_applied and _ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
			chunk_view.update_mid_ladder_z(_ladder_anchor_stripe)
		WorldPerfProbe.end("WorldStreamer.visual_upload.object_packet", object_started)
		if object_applied and Time.get_ticks_usec() - tick_started_usec >= budget_usec:
			return false
	while not _pending_grass_scatter_visual_upload_chunks.is_empty():
		var chunk_coord: Vector2i = _pending_grass_scatter_visual_upload_chunks.pop_front()
		_pending_grass_scatter_visual_upload_set.erase(chunk_coord)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view == null:
			continue
		_ensure_grass_scatter_sources()
		var grass_started: int = WorldPerfProbe.begin()
		var grass_applied: bool = chunk_view.apply_pending_grass_scatter_visual(
			_get_contour_world_core(),
			_grass_scatter_params,
			_grass_scatter_atlas,
			_grass_scatter_material,
			_grass_shadow_atlas,
			_grass_shadow_atlas_material,
			_grass_shadow_material,
			_grass_spore_material,
			_get_cached_mountain_solid_halo(chunk_coord).get("halo", PackedByteArray()) as PackedByteArray,
			MOUNTAIN_HALO_MASK_RADIUS_TILES,
		)
		if grass_applied:
			chunk_view.set_grass_scatter_lod_fraction(_grass_lod_fraction)
			if _ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
				chunk_view.update_mid_ladder_z(_ladder_anchor_stripe)
		WorldPerfProbe.end("WorldStreamer.visual_upload.grass_scatter", grass_started)
		if grass_applied and Time.get_ticks_usec() - tick_started_usec >= budget_usec:
			return false
	return false


func _begin_mountain_native_mask_tick_metrics() -> void:
	_mountain_native_mask_build_count_tick = 0
	_mountain_native_mask_elapsed_ms_max_tick = 0.0


func _end_mountain_native_mask_tick_metrics() -> void:
	_mountain_native_mask_build_count_last_tick = _mountain_native_mask_build_count_tick
	_mountain_native_mask_build_count_max_tick = maxi(
		_mountain_native_mask_build_count_max_tick,
		_mountain_native_mask_build_count_tick,
	)
	_mountain_native_mask_elapsed_ms_last_tick_max = _mountain_native_mask_elapsed_ms_max_tick


func _update_player_chunk_coord() -> void:
	var player_pos: Vector2 = PlayerAuthority.get_local_player_position()
	var tile_coord: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(player_pos))
	var next_player_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var next_radius: int = _resolve_stream_radius_chunks()
	if next_player_chunk != _player_chunk_coord or next_radius != _current_stream_radius_chunks:
		_player_chunk_coord = next_player_chunk
		_current_stream_radius_chunks = next_radius
		_rebuild_desired_chunk_cache()
	_update_grass_scatter_lod()
	_update_mid_ladder_anchor()


## Zoom-LOD травы: буфер чанка отсортирован native-кодом по важности (крупные
## пучки в голове), поэтому дальний зум режет хвост мелочи одним числом —
## visible_instance_count — без пересборки буфера.
## Якорь player-relative depth-лесенки: полоса ног игрока. При смене полосы
## (раз в DEPTH_STRIPE_PX пути по Y) все чанки переставляют z своих mid-полос
## — это только присваивания z существующим нодам, без пересборки буферов.
func _update_mid_ladder_anchor() -> void:
	var player: Player = PlayerAuthority.get_local_player()
	if player == null:
		return
	var anchor_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(
		player.global_position.y + Player.PLAYER_FEET_OFFSET_PX,
	)
	if anchor_stripe == _ladder_anchor_stripe:
		return
	_ladder_anchor_stripe = anchor_stripe
	for chunk_view_variant: Variant in _chunk_views.values():
		var chunk_view: ChunkView = chunk_view_variant as ChunkView
		if chunk_view != null:
			chunk_view.update_mid_ladder_z(anchor_stripe)


func _update_grass_scatter_lod() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null or not is_instance_valid(camera):
		return
	var zoom: float = maxf(camera.zoom.x, 0.01)
	var lod_t: float = clampf(
		(zoom - _grass_lod_min_zoom) / maxf(_grass_lod_full_zoom - _grass_lod_min_zoom, 0.001),
		0.0,
		1.0,
	)
	var next_fraction: float = lerpf(_grass_lod_min_fraction, 1.0, lod_t)
	if absf(next_fraction - _grass_lod_fraction) < 0.04:
		return
	_grass_lod_fraction = next_fraction
	for chunk_view_variant: Variant in _chunk_views.values():
		var chunk_view: ChunkView = chunk_view_variant as ChunkView
		if chunk_view != null:
			chunk_view.set_grass_scatter_lod_fraction(_grass_lod_fraction)


func _enqueue_desired_chunks() -> void:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		return
	for desired_coord: Vector2i in _desired_source_chunk_coords:
		if _chunk_packets.has(desired_coord):
			if _is_chunk_desired(desired_coord) \
					and not _pending_publish_queue.has(desired_coord) \
					and not _chunk_views.has(desired_coord):
				_pending_publish_queue.append(desired_coord)
			continue
		if _requested_chunks.has(desired_coord):
			continue
		_requested_chunks[desired_coord] = true
		_packet_backend.queue_packet_request(
			desired_coord,
			world_seed,
			world_version,
			_worldgen_settings_packed,
			_generation_epoch,
		)


func _drain_completed_packets(max_count: int) -> void:
	var drained: Array[Dictionary] = _packet_backend.drain_completed_packets(max_count)
	for packet: Dictionary in drained:
		if int(packet.get("epoch", -1)) != _generation_epoch:
			continue
		var chunk_coord: Vector2i = _canonicalize_chunk_coord(packet.get("chunk_coord", Vector2i.ZERO) as Vector2i)
		_requested_chunks.erase(chunk_coord)
		if packet.has("success") and not bool(packet.get("success", true)):
			push_error(
				"WorldStreamer chunk packet generation failed for chunk %s: %s" % [
					str(chunk_coord),
					str(packet.get("message", "unknown native packet error")),
				],
			)
			continue
		var merged_packet: Dictionary = _diff_store.apply_to_packet(packet)
		_chunk_packets[chunk_coord] = merged_packet
		_refresh_loaded_visuals_around_chunk_overrides(chunk_coord)
		_forget_mountain_mask(chunk_coord, true, true)
		_forget_terrain_edge_mask(chunk_coord, true, true)
		if _is_chunk_desired(chunk_coord) and not _pending_publish_queue.has(chunk_coord) and chunk_coord != _active_publish_chunk:
			_pending_publish_queue.append(chunk_coord)


func _publish_next_batch() -> void:
	_prune_stale_pending_publish_chunks()
	if _active_publish_chunk == INVALID_CHUNK_COORD:
		if _pending_publish_queue.is_empty():
			return
		var publish_begin_started: int = WorldPerfProbe.begin()
		_prefetch_queued_chunk_masks(PUBLISH_MASK_PREFETCH_PER_TICK)
		# Bounded scan instead of strict FIFO: a head chunk waiting for its
		# native mountain mask must not stall every ready chunk behind it.
		var step_started: int = WorldPerfProbe.begin()
		var picked_index: int = -1
		var scan_limit: int = mini(_pending_publish_queue.size(), PUBLISH_QUEUE_SCAN_LIMIT)
		for index: int in range(scan_limit):
			var candidate: Vector2i = _pending_publish_queue[index]
			var candidate_packet: Dictionary = _chunk_packets.get(candidate, { }) as Dictionary
			if candidate_packet.is_empty():
				continue
			if _can_publish_chunk_with_mountain_mask(candidate, candidate_packet):
				picked_index = index
				break
		WorldPerfProbe.end("WorldStreamer.publish.begin.mountain_ready", step_started)
		if picked_index < 0:
			WorldPerfProbe.end("WorldStreamer.publish.begin", publish_begin_started)
			return
		var next_publish_chunk: Vector2i = _pending_publish_queue[picked_index]
		_pending_publish_queue.remove_at(picked_index)
		var packet: Dictionary = _chunk_packets.get(next_publish_chunk, { }) as Dictionary
		step_started = WorldPerfProbe.begin()
		_prepare_terrain_edge_mask_for_publish(next_publish_chunk, packet)
		WorldPerfProbe.end("WorldStreamer.publish.begin.terrain_edge_prepare", step_started)
		_active_publish_chunk = next_publish_chunk
		step_started = WorldPerfProbe.begin()
		_track_roof_layer_metric(_active_publish_chunk, packet)
		WorldPerfProbe.end("WorldStreamer.publish.begin.track_roof", step_started)
		step_started = WorldPerfProbe.begin()
		var chunk_view: ChunkView = _ensure_chunk_view(_active_publish_chunk)
		WorldPerfProbe.end("WorldStreamer.publish.begin.ensure_view", step_started)
		step_started = WorldPerfProbe.begin()
		_apply_mountain_mask_to_chunk_view(_active_publish_chunk, chunk_view, packet)
		WorldPerfProbe.end("WorldStreamer.publish.begin.apply_mountain_mask", step_started)
		step_started = WorldPerfProbe.begin()
		_apply_terrain_edge_mask_to_chunk_view(_active_publish_chunk, chunk_view, packet)
		WorldPerfProbe.end("WorldStreamer.publish.begin.apply_terrain_edge_mask", step_started)
		step_started = WorldPerfProbe.begin()
		chunk_view.begin_apply(packet, true)
		_queue_object_packet_visual_upload(_active_publish_chunk)
		_queue_grass_scatter_visual_upload(_active_publish_chunk)
		WorldPerfProbe.end("WorldStreamer.publish.begin.chunk_begin_apply", step_started)
		WorldPerfProbe.end("WorldStreamer.publish.begin", publish_begin_started)
		return

	var active_view: ChunkView = _chunk_views.get(_active_publish_chunk) as ChunkView
	if active_view == null:
		_active_publish_chunk = INVALID_CHUNK_COORD
		return
	var publish_apply_started: int = WorldPerfProbe.begin()
	var has_more: bool = active_view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE)
	WorldPerfProbe.end("WorldStreamer.publish.apply_batch", publish_apply_started)
	if not has_more:
		var publish_finalize_started: int = WorldPerfProbe.begin()
		var finalized_chunk: Vector2i = _active_publish_chunk
		_handle_cover_chunk_published(finalized_chunk)
		_refresh_debug_visuals_for_chunk(finalized_chunk)
		var native_debug: Dictionary = active_view.get_mountain_native_mask_debug_state()
		if bool(native_debug.get("native_mask_visual_pending", false)):
			_pending_chunk_visibility_after_mountain_visual[finalized_chunk] = true
		else:
			active_view.visible = true
			EventBus.chunk_loaded.emit(finalized_chunk)
		WorldPerfProbe.end("WorldStreamer.publish.finalize", publish_finalize_started)
		_active_publish_chunk = INVALID_CHUNK_COORD


func _finalize_pending_chunk_visibility(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _pending_chunk_visibility_after_mountain_visual.has(chunk_coord):
		return
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if chunk_view == null:
		_pending_chunk_visibility_after_mountain_visual.erase(chunk_coord)
		return
	var native_debug: Dictionary = chunk_view.get_mountain_native_mask_debug_state()
	if bool(native_debug.get("native_mask_visual_pending", false)):
		return
	_pending_chunk_visibility_after_mountain_visual.erase(chunk_coord)
	chunk_view.visible = true
	EventBus.chunk_loaded.emit(chunk_coord)


func _prune_stale_pending_publish_chunks() -> void:
	if _pending_publish_queue.is_empty():
		return
	var filtered_queue: Array[Vector2i] = []
	var seen: Dictionary = { }
	for chunk_coord: Vector2i in _pending_publish_queue:
		if not _is_chunk_desired(chunk_coord):
			continue
		if seen.has(chunk_coord):
			continue
		seen[chunk_coord] = true
		filtered_queue.append(chunk_coord)
	_pending_publish_queue = filtered_queue


func _prefetch_queued_chunk_masks(max_builds: int) -> void:
	# Warm the native mask pipeline for chunks waiting in the publish queue.
	# Cache misses (fresh halo builds) are the bounded cost; chunks whose halos
	# are already cached only pay cheap dictionary checks.
	var builds: int = 0
	for chunk_coord: Vector2i in _pending_publish_queue:
		if builds >= max_builds:
			return
		if _prefetch_chunk_masks(chunk_coord):
			builds += 1


func _prefetch_chunk_masks(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var built_halo: bool = false
	if MOUNTAIN_NATIVE_MASK_RUNTIME_ENABLED and _has_loaded_mountain_halo_sources(chunk_coord):
		if not _mountain_solid_halo_cache.has(chunk_coord):
			built_halo = true
		var mountain_halo: Dictionary = _get_cached_mountain_solid_halo(chunk_coord)
		if bool(mountain_halo.get("has_closed", false)) \
				and _get_ready_mountain_native_mask_result(chunk_coord).is_empty():
			_request_mountain_native_mask_for_chunk(
				chunk_coord,
				mountain_halo.get("closed_halo", PackedByteArray()) as PackedByteArray,
				mountain_halo.get("dug_halo", PackedByteArray()) as PackedByteArray,
				&"prefetch",
			)
	if TERRAIN_EDGE_MASK_RUNTIME_ENABLED and _has_loaded_terrain_edge_halo_sources(chunk_coord):
		if not _terrain_edge_solid_halo_cache.has(chunk_coord):
			built_halo = true
		var edge_halo: Dictionary = _get_cached_terrain_edge_solid_halo(chunk_coord)
		if bool(edge_halo.get("has_shoreline", false)) \
				and _get_ready_terrain_edge_mask_result(chunk_coord).is_empty():
			_request_terrain_edge_mask_for_chunk(
				chunk_coord,
				edge_halo.get("halo", PackedByteArray()) as PackedByteArray,
				&"prefetch",
			)
	return built_halo


func _evict_outside_ring(max_count: int) -> void:
	var evicted: int = 0
	var loaded_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _chunk_views.keys():
		loaded_coords.append(chunk_coord_variant as Vector2i)
	loaded_coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x if a.x != b.x else a.y < b.y
	)
	for chunk_coord: Vector2i in loaded_coords:
		if evicted >= max_count:
			break
		if chunk_coord == _active_publish_chunk or _is_chunk_desired(chunk_coord):
			continue
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view:
			chunk_view.queue_free()
		_chunk_views.erase(chunk_coord)
		_chunk_packets.erase(chunk_coord)
		_requested_chunks.erase(chunk_coord)
		_pending_publish_queue.erase(chunk_coord)
		_pending_chunk_visibility_after_mountain_visual.erase(chunk_coord)
		_drop_object_packet_visual_upload(chunk_coord)
		_drop_grass_scatter_visual_upload(chunk_coord)
		_handle_cover_chunk_unloaded(chunk_coord)
		_forget_mountain_mask(chunk_coord, true, true)
		_forget_terrain_edge_mask(chunk_coord, true, true)
		EventBus.chunk_unloaded.emit(chunk_coord)
		evicted += 1


func _has_pending_streaming_work() -> bool:
	if _awaiting_new_game_spawn_result:
		return true
	if not _pending_publish_queue.is_empty():
		return true
	if _active_publish_chunk != INVALID_CHUNK_COORD:
		return true
	if not _pending_chunk_visibility_after_mountain_visual.is_empty():
		return true
	if _packet_backend.has_pending_requests():
		return true
	if _packet_backend.has_completed_packets():
		return true
	if _mountain_mask_backend.has_pending_requests():
		return true
	if _mountain_mask_backend.has_completed_mountain_halo_masks():
		return true
	if not _mountain_native_mask_inflight_chunks.is_empty():
		return true
	if not _pending_mountain_native_mask_visual_upload_chunks.is_empty():
		return true
	if not _terrain_edge_mask_inflight_chunks.is_empty():
		return true
	if not _pending_terrain_edge_mask_visual_upload_chunks.is_empty():
		return true
	if not _pending_object_packet_visual_upload_chunks.is_empty():
		return true
	if not _pending_grass_scatter_visual_upload_chunks.is_empty():
		return true
	for chunk_coord_variant: Variant in _chunk_views.keys():
		if not _is_chunk_desired(chunk_coord_variant as Vector2i):
			return true
	return false


func _get_tile_data(world_pos: Vector2) -> Dictionary:
	var tile_coord: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(world_pos))
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_tile_y_in_bounds(tile_coord.y):
		return {
			"ready": false,
			"chunk_coord": WorldRuntimeConstants.tile_to_chunk(tile_coord),
			"local_coord": WorldRuntimeConstants.tile_to_local(tile_coord),
		}
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)

	var override_data: Dictionary = _diff_store.get_tile_override(chunk_coord, local_coord)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty():
		_enqueue_chunk_if_needed(chunk_coord)
		if not override_data.is_empty():
			return {
				"ready": true,
				"chunk_coord": chunk_coord,
				"local_coord": local_coord,
				"terrain_id": int(override_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
				"walkable": bool(override_data.get("walkable", true)),
			}
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}

	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": int(terrain_ids[index]),
		"walkable": int(walkable_flags[index]) != 0,
	}


func _sample_harvest_gate_tile(world_tile: Vector2i) -> Dictionary:
	return _get_tile_data(WorldRuntimeConstants.tile_to_world_center(world_tile))


func _sample_mountain_cover_tile(world_tile: Vector2i) -> Dictionary:
	var canonical_tile: Vector2i = _canonicalize_tile_coord(world_tile)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var packet: Dictionary = get_chunk_packet(chunk_coord)
	if packet.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": WorldRuntimeConstants.tile_to_local(canonical_tile),
		}
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	if index < 0 \
			or index >= mountain_ids.size() \
			or index >= mountain_flags.size() \
			or index >= walkable_flags.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"mountain_id": int(mountain_ids[index]),
		"mountain_flags": int(mountain_flags[index]),
		"walkable": int(walkable_flags[index]) != 0,
	}


func _resolve_cover_debug_probe_tile(world_tile: Vector2i) -> Vector2i:
	for offset: Vector2i in [
		Vector2i.ZERO,
		Vector2i.UP,
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i(1, -1),
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]:
		var candidate_tile: Vector2i = world_tile + offset
		var candidate_sample: Dictionary = _sample_mountain_cover_tile(candidate_tile)
		if int(candidate_sample.get("mountain_id", 0)) > 0:
			return candidate_tile
	return world_tile


func _enqueue_chunk_if_needed(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
		return
	if _requested_chunks.has(chunk_coord) or _chunk_packets.has(chunk_coord):
		return
	_requested_chunks[chunk_coord] = true
	_packet_backend.queue_packet_request(
		chunk_coord,
		world_seed,
		world_version,
		_worldgen_settings_packed,
		_generation_epoch,
	)


func _apply_loaded_override(chunk_coord: Vector2i, local_coord: Vector2i, terrain_id: int, walkable: bool) -> void:
	if not _chunk_packets.has(chunk_coord):
		return
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	var terrain_ids: PackedInt32Array = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
	var terrain_atlas_indices: PackedInt32Array = (packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	var walkable_flags: PackedByteArray = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return
	var previous_terrain_id: int = int(terrain_ids[index])
	var is_mountain_surface_dig: bool = _uses_mountain_surface_presentation(previous_terrain_id) \
			and terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG
	if terrain_atlas_indices.size() < terrain_ids.size():
		terrain_atlas_indices.resize(terrain_ids.size())
	terrain_ids[index] = terrain_id
	walkable_flags[index] = 1 if walkable else 0
	terrain_atlas_indices[index] = 0
	packet["terrain_ids"] = terrain_ids
	packet["terrain_atlas_indices"] = terrain_atlas_indices
	packet["walkable_flags"] = walkable_flags
	_chunk_packets[chunk_coord] = packet
	var world_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_coord)
	if not is_mountain_surface_dig:
		_refresh_loaded_visual_patch_for_tiles(
			[
				world_tile,
			],
		)
	else:
		_mountain_surface_dig_visual_patch_skip_count_total += 1
		# Mountain walls don't paint a base cell, so a dug mountain tile leaves the
		# base layer empty -- the viewport clear_color then bleeds (green) through
		# the mountain-shader hole. Paint just this dug floor cell (DUG = dirt) so
		# the cavity shows ground, without the heavy 3x3 square visual patch.
		var dug_floor_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if dug_floor_view != null:
			dug_floor_view.apply_runtime_cell(local_coord, terrain_id, 0, walkable)
	_refresh_debug_visuals_around_tile(world_tile)
	_apply_mountain_surface_local_dig_patch(chunk_coord, local_coord, terrain_id)


func _refresh_loaded_packets_from_diffs() -> void:
	_mountain_cavity_cache.clear()
	_active_cover_mountain_id = 0
	_active_cover_component_id = 0
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _chunk_packets.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	for chunk_coord: Vector2i in chunk_coords:
		var base_packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
		var refreshed_packet: Dictionary = _diff_store.apply_to_packet(base_packet)
		_chunk_packets[chunk_coord] = refreshed_packet
		_refresh_loaded_visuals_around_chunk_overrides(chunk_coord)
		_forget_mountain_mask(chunk_coord, true, true)
		_forget_terrain_edge_mask(chunk_coord, true, true)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view:
			_track_roof_layer_metric(chunk_coord, _chunk_packets[chunk_coord] as Dictionary)
			chunk_view.begin_apply(_chunk_packets[chunk_coord] as Dictionary, true)
			_queue_object_packet_visual_upload(chunk_coord)
			_queue_grass_scatter_visual_upload(chunk_coord)
			_refresh_debug_visuals_for_chunk(chunk_coord)
			if not _pending_publish_queue.has(chunk_coord):
				_pending_publish_queue.append(chunk_coord)


func _refresh_loaded_visuals_around_chunk_overrides(center_chunk_coord: Vector2i) -> void:
	var origin_tiles: Array[Vector2i] = []
	for y: int in range(center_chunk_coord.y - 1, center_chunk_coord.y + 2):
		for x: int in range(center_chunk_coord.x - 1, center_chunk_coord.x + 2):
			var sample_chunk_coord := Vector2i(x, y)
			for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(sample_chunk_coord):
				origin_tiles.append(_chunk_local_to_tile(sample_chunk_coord, local_coord))
	if origin_tiles.is_empty():
		return
	_refresh_loaded_visual_patch_for_tiles(origin_tiles)


func _refresh_loaded_visual_patch_for_tiles(origin_tiles: Array[Vector2i]) -> void:
	var seen_tiles: Dictionary = { }
	var updates_by_chunk: Dictionary = { }
	for origin_tile: Vector2i in origin_tiles:
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var tile_coord: Vector2i = origin_tile + Vector2i(offset_x, offset_y)
				if seen_tiles.has(tile_coord):
					continue
				seen_tiles[tile_coord] = true
				var update: Dictionary = _build_loaded_visual_update(tile_coord)
				if update.is_empty():
					continue
				var chunk_coord: Vector2i = update.get("chunk_coord", INVALID_CHUNK_COORD) as Vector2i
				if chunk_coord == INVALID_CHUNK_COORD:
					continue
				if not updates_by_chunk.has(chunk_coord):
					updates_by_chunk[chunk_coord] = { }
				var local_coord: Vector2i = update.get("local_coord", Vector2i.ZERO) as Vector2i
				var chunk_updates: Dictionary = updates_by_chunk[chunk_coord] as Dictionary
				chunk_updates[local_coord] = update
	for chunk_coord_variant: Variant in updates_by_chunk.keys():
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
		if packet.is_empty():
			continue
		var terrain_ids: PackedInt32Array = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
		var terrain_atlas_indices: PackedInt32Array = (packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
		var walkable_flags: PackedByteArray = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
		if terrain_atlas_indices.size() < terrain_ids.size():
			terrain_atlas_indices.resize(terrain_ids.size())
		var chunk_updates: Dictionary = updates_by_chunk[chunk_coord] as Dictionary
		for local_coord_variant: Variant in chunk_updates.keys():
			var local_coord: Vector2i = local_coord_variant as Vector2i
			var update: Dictionary = chunk_updates.get(local_coord, { }) as Dictionary
			var index: int = WorldRuntimeConstants.local_to_index(local_coord)
			if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
				continue
			terrain_ids[index] = int(update.get("terrain_id", terrain_ids[index]))
			walkable_flags[index] = 1 if bool(update.get("walkable", int(walkable_flags[index]) != 0)) else 0
			terrain_atlas_indices[index] = int(update.get("terrain_atlas_index", terrain_atlas_indices[index]))
		packet["terrain_ids"] = terrain_ids
		packet["terrain_atlas_indices"] = terrain_atlas_indices
		packet["walkable_flags"] = walkable_flags
		_chunk_packets[chunk_coord] = packet
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view:
			for local_coord_variant: Variant in chunk_updates.keys():
				var local_coord: Vector2i = local_coord_variant as Vector2i
				var update: Dictionary = chunk_updates.get(local_coord, { }) as Dictionary
				chunk_view.apply_runtime_cell(
					local_coord,
					int(update.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
					int(update.get("terrain_atlas_index", 0)),
					bool(update.get("walkable", true)),
					int(update.get("mountain_id", 0)),
					int(update.get("mountain_flags", 0)),
				)


func _build_loaded_visual_update(tile_coord: Vector2i) -> Dictionary:
	var tile_data: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord)
	if not bool(tile_data.get("ready", false)):
		return { }
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var terrain_atlas_index: int = 0
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
		terrain_atlas_index = _resolve_loaded_ground_atlas_index(tile_coord)
	elif _uses_mountain_surface_presentation(terrain_id):
		var mountain_atlas_data: Dictionary = _try_resolve_loaded_mountain_atlas_index(tile_coord)
		if not bool(mountain_atlas_data.get("ready", false)):
			return { }
		terrain_atlas_index = int(mountain_atlas_data.get("terrain_atlas_index", 0))
	return {
		"chunk_coord": tile_data.get("chunk_coord", INVALID_CHUNK_COORD) as Vector2i,
		"local_coord": tile_data.get("local_coord", Vector2i.ZERO) as Vector2i,
		"terrain_id": terrain_id,
		"terrain_atlas_index": terrain_atlas_index,
		"walkable": bool(tile_data.get("walkable", true)),
		"mountain_id": int(tile_data.get("mountain_id", 0)),
		"mountain_flags": int(tile_data.get("mountain_flags", 0)),
	}


func _resolve_loaded_ground_atlas_index(tile_coord: Vector2i) -> int:
	var north_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(0, -1))
	var east_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(1, 0))
	var south_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(0, 1))
	var west_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(-1, 0))
	var north_east_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(1, -1))
	var south_east_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(1, 1))
	var south_west_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(-1, 1))
	var north_west_is_water: bool = _is_loaded_water_surface_at(tile_coord + Vector2i(-1, -1))
	var signature_code: int = Autotile47.build_signature_code(
		not north_is_water,
		not north_east_is_water,
		not east_is_water,
		not south_east_is_water,
		not south_is_water,
		not south_west_is_water,
		not west_is_water,
		not north_west_is_water,
	)
	var variant_index: int = Autotile47.pick_variant(tile_coord, world_seed)
	return Autotile47.build_atlas_index(signature_code, variant_index)


func _is_loaded_water_surface_at(tile_coord: Vector2i) -> bool:
	var sample: Dictionary = _get_loaded_tile_data_no_enqueue(tile_coord)
	if not bool(sample.get("ready", false)):
		return false
	return _is_loaded_water_surface_terrain(
		int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
	)


func _is_loaded_water_surface_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
			or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP


func _try_resolve_loaded_mountain_atlas_index(tile_coord: Vector2i) -> Dictionary:
	var north: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(0, -1))
	var east: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(1, 0))
	var south: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(0, 1))
	var west: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(-1, 0))
	if not bool(north.get("ready", false)) \
			or not bool(east.get("ready", false)) \
			or not bool(south.get("ready", false)) \
			or not bool(west.get("ready", false)):
		return { "ready": false }
	var is_north_mountain: bool = _is_loaded_mountain_geometry_surface(north)
	var is_east_mountain: bool = _is_loaded_mountain_geometry_surface(east)
	var is_south_mountain: bool = _is_loaded_mountain_geometry_surface(south)
	var is_west_mountain: bool = _is_loaded_mountain_geometry_surface(west)
	var is_north_east_mountain: bool = false
	var is_south_east_mountain: bool = false
	var is_south_west_mountain: bool = false
	var is_north_west_mountain: bool = false
	if is_north_mountain and is_east_mountain:
		var north_east: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(1, -1))
		if not bool(north_east.get("ready", false)):
			return { "ready": false }
		is_north_east_mountain = _is_loaded_mountain_geometry_surface(north_east)
	if is_south_mountain and is_east_mountain:
		var south_east: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(1, 1))
		if not bool(south_east.get("ready", false)):
			return { "ready": false }
		is_south_east_mountain = _is_loaded_mountain_geometry_surface(south_east)
	if is_south_mountain and is_west_mountain:
		var south_west: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(-1, 1))
		if not bool(south_west.get("ready", false)):
			return { "ready": false }
		is_south_west_mountain = _is_loaded_mountain_geometry_surface(south_west)
	if is_north_mountain and is_west_mountain:
		var north_west: Dictionary = _get_loaded_mountain_geometry_no_enqueue(tile_coord + Vector2i(-1, -1))
		if not bool(north_west.get("ready", false)):
			return { "ready": false }
		is_north_west_mountain = _is_loaded_mountain_geometry_surface(north_west)
	var signature_code: int = Autotile47.build_signature_code(
		is_north_mountain,
		is_north_east_mountain,
		is_east_mountain,
		is_south_east_mountain,
		is_south_mountain,
		is_south_west_mountain,
		is_west_mountain,
		is_north_west_mountain,
	)
	var variant_index: int = Autotile47.pick_variant(tile_coord, world_seed)
	return {
		"ready": true,
		"terrain_atlas_index": Autotile47.build_atlas_index(signature_code, variant_index),
	}


func _get_loaded_mountain_geometry_no_enqueue(tile_coord: Vector2i) -> Dictionary:
	tile_coord = _canonicalize_tile_coord(tile_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_tile_y_in_bounds(tile_coord.y):
		return { "ready": false }
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	if index < 0 or index >= terrain_ids.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	var has_mountain_geometry: bool = index < mountain_ids.size() and index < mountain_flags.size()
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": int(terrain_ids[index]),
		"mountain_id": int(mountain_ids[index]) if has_mountain_geometry else 0,
		"mountain_flags": int(mountain_flags[index]) if has_mountain_geometry else 0,
	}


func _is_loaded_mountain_geometry_surface(sample: Dictionary) -> bool:
	return _uses_mountain_surface_presentation(
		int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
	)


func _get_loaded_tile_data_no_enqueue(tile_coord: Vector2i) -> Dictionary:
	tile_coord = _canonicalize_tile_coord(tile_coord)
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_tile_y_in_bounds(tile_coord.y):
		return {
			"ready": false,
			"chunk_coord": WorldRuntimeConstants.tile_to_chunk(tile_coord),
			"local_coord": WorldRuntimeConstants.tile_to_local(tile_coord),
		}
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_coord)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_coord)
	var override_data: Dictionary = _diff_store.get_tile_override(chunk_coord, local_coord)
	if not override_data.is_empty():
		return {
			"ready": true,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
			"terrain_id": int(override_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)),
			"walkable": bool(override_data.get("walkable", true)),
			"mountain_id": 0,
			"mountain_flags": 0,
		}
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
			"local_coord": local_coord,
		}
	var has_mountain_geometry: bool = index < mountain_ids.size() and index < mountain_flags.size()
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"local_coord": local_coord,
		"terrain_id": int(terrain_ids[index]),
		"walkable": int(walkable_flags[index]) != 0,
		"mountain_id": int(mountain_ids[index]) if has_mountain_geometry else 0,
		"mountain_flags": int(mountain_flags[index]) if has_mountain_geometry else 0,
	}


func _chunk_local_to_tile(chunk_coord: Vector2i, local_coord: Vector2i) -> Vector2i:
	var canonical_chunk: Vector2i = _canonicalize_chunk_coord(chunk_coord)
	return Vector2i(
		canonical_chunk.x * WorldRuntimeConstants.CHUNK_SIZE + local_coord.x,
		canonical_chunk.y * WorldRuntimeConstants.CHUNK_SIZE + local_coord.y,
	)


func _ensure_chunk_view(chunk_coord: Vector2i) -> ChunkView:
	var existing: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if existing != null:
		return existing
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	chunk_view.set_mountain_tile_visuals_enabled(false)
	chunk_view.set_debug_overlays(
		_debug_tile_grid_visible,
		_debug_mountain_solid_visible,
		_debug_mountain_contour_visible,
	)
	chunk_view.set_debug_object_collisions_visible(_debug_object_collisions_visible)
	chunk_view.set_living_flora_source(_plains_living_flora_atlas)
	chunk_view.set_spiky_flora_sources(_plains_spiky_flora_atlases)
	chunk_view.set_tree_source(PLAINS_TREE_ATLAS if PLAINS_TREE_ENABLED else null)
	chunk_view.set_layered_tree_asset_dirs(PLAINS_LAYERED_TREE_ASSET_DIRS if PLAINS_TREE_ENABLED else [])
	chunk_view.set_layered_small_rock_asset_dirs(PLAINS_LAYERED_SMALL_ROCK_ASSET_DIRS if PLAINS_SMALL_ROCK_ENABLED else [])
	chunk_view.apply_sun_lighting(
		_sun_light_angle_deg,
		_sun_shadow_length_px,
		_sun_shadow_opacity,
		_sun_shadow_softness_px,
	)
	add_child(chunk_view)
	_chunk_views[chunk_coord] = chunk_view
	return chunk_view


func _ensure_mining_feedback_layer() -> MiningFeedbackLayer:
	if _mining_feedback_layer != null and is_instance_valid(_mining_feedback_layer):
		return _mining_feedback_layer
	_mining_feedback_layer = MiningFeedbackLayer.new()
	_mining_feedback_layer.name = "MiningFeedbackLayer"
	_mining_feedback_layer.z_as_relative = false
	_mining_feedback_layer.z_index = WorldRuntimeConstants.Z_MINING_FEEDBACK
	add_child(_mining_feedback_layer)
	return _mining_feedback_layer


func _spawn_mountain_mining_feedback(world_tile: Vector2i, impact_world_pos: Vector2) -> void:
	var feedback_layer: MiningFeedbackLayer = _ensure_mining_feedback_layer()
	feedback_layer.spawn_mountain_mining_feedback(world_tile, impact_world_pos)


func _on_time_tick(_current_hour: float, _day_progress: float) -> void:
	_sync_sun_lighting_from_time(false)


func _sync_sun_lighting_from_time(force: bool = false) -> void:
	if not TimeManager \
			or not TimeManager.has_method("get_sun_angle") \
			or not TimeManager.has_method("get_sun_progress"):
		return
	var angle_deg: float = rad_to_deg(float(TimeManager.get_sun_angle()))
	var sun_progress: float = float(TimeManager.get_sun_progress())
	var low_sun: float = WorldVisualLightingProfile.low_sun_for_progress(sun_progress)
	var current_hour: float = float(TimeManager.current_hour)
	var shadow_length_px: float = WorldVisualLightingProfile.shadow_length_px_for_low_sun(low_sun)
	var shadow_opacity: float = WorldVisualLightingProfile.shadow_opacity_for_low_sun_and_hour(low_sun, current_hour)
	var shadow_softness_px: float = WorldVisualLightingProfile.shadow_softness_px_for_low_sun(low_sun)
	if not force \
			and absf(angle_deg - _sun_light_angle_deg) < WorldVisualLightingProfile.LIGHT_ANGLE_EPSILON_DEG \
			and absf(shadow_length_px - _sun_shadow_length_px) < WorldVisualLightingProfile.SHADOW_LENGTH_EPSILON_PX \
			and absf(shadow_opacity - _sun_shadow_opacity) < WorldVisualLightingProfile.SHADOW_OPACITY_EPSILON \
			and absf(shadow_softness_px - _sun_shadow_softness_px) < WorldVisualLightingProfile.SHADOW_SOFTNESS_EPSILON_PX:
		return
	_sun_light_angle_deg = angle_deg
	_sun_shadow_length_px = shadow_length_px
	_sun_shadow_opacity = shadow_opacity
	_sun_shadow_softness_px = shadow_softness_px
	_sun_day_factor = WorldVisualLightingProfile.shadow_visibility_for_hour(current_hour)
	_apply_sun_lighting_to_loaded_chunks()
	_apply_sun_lighting_to_ground_material()


func _apply_sun_lighting_to_loaded_chunks() -> void:
	for chunk_view_variant: Variant in _chunk_views.values():
		var chunk_view: ChunkView = chunk_view_variant as ChunkView
		if chunk_view == null:
			continue
		chunk_view.apply_sun_lighting(
			_sun_light_angle_deg,
			_sun_shadow_length_px,
			_sun_shadow_opacity,
			_sun_shadow_softness_px,
		)


func _apply_sun_lighting_to_ground_material() -> void:
	# Cosmetic only (ADR-0005): feeds the shared plains ground material the same
	# sun model used by the shadows, for the large-scale ground shade. One shared
	# material -> set once per sun change; null until a chunk built it (the shader
	# has correct daytime defaults until then). See plains_ground_cosmetic_shading.md.
	var ground_material: ShaderMaterial = WorldTileSetFactory.get_built_material_for_terrain(
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
	)
	if ground_material == null:
		return
	ground_material.set_shader_parameter("ground_sun_angle_deg", _sun_light_angle_deg)
	ground_material.set_shader_parameter("ground_sun_day", _sun_day_factor)


func _drain_completed_native_masks(max_count: int) -> void:
	var drained: Array[Dictionary] = _mountain_mask_backend.drain_completed_mountain_halo_masks(max_count)
	for result: Dictionary in drained:
		var mask_purpose: StringName = result.get("mask_purpose", &"mountain") as StringName
		if mask_purpose == &"terrain_edge":
			_handle_completed_terrain_edge_mask(result)
		else:
			_handle_completed_mountain_native_mask(result)


func _handle_completed_mountain_native_mask(result: Dictionary) -> void:
	if int(result.get("epoch", -1)) != _generation_epoch:
		return
	var target_chunk: Vector2i = _canonicalize_chunk_coord(
		result.get("target_chunk", INVALID_CHUNK_COORD) as Vector2i,
	)
	if target_chunk == INVALID_CHUNK_COORD:
		return
	var expected_revision: int = _get_mountain_mask_revision(target_chunk)
	var result_revision: int = int(result.get("revision", -1))
	var inflight: Dictionary = _mountain_native_mask_inflight_chunks.get(
		target_chunk,
		{},
	) as Dictionary
	if int(inflight.get("revision", -1)) == result_revision:
		_mountain_native_mask_inflight_chunks.erase(target_chunk)
	if result_revision != expected_revision:
		return
	if not bool(result.get("success", false)):
		push_warning(
			"Mountain native mask failed for chunk %s: %s" % [
				str(target_chunk),
				str(result.get("message", "")),
			],
		)
		return
	var apply_started_usec: int = Time.get_ticks_usec()
	_mountain_native_masks_by_chunk[target_chunk] = result
	var chunk_view: ChunkView = _chunk_views.get(target_chunk, null) as ChunkView
	if chunk_view != null:
		_apply_ready_mountain_native_mask_to_chunk_view(target_chunk, chunk_view, result)
	var chunk_needs_publish_after_mask: bool = chunk_view == null or not chunk_view.visible
	if not chunk_needs_publish_after_mask:
		_mountain_native_mask_visible_republish_skip_count_total += 1
	_record_mountain_native_mask_build(
		target_chunk,
		result.get("reason", &"worker") as StringName,
		Time.get_ticks_usec() - apply_started_usec,
		result,
	)
	if chunk_needs_publish_after_mask \
			and _is_chunk_desired(target_chunk) \
			and not _pending_publish_queue.has(target_chunk) \
			and target_chunk != _active_publish_chunk:
		_pending_publish_queue.append(target_chunk)


func _handle_completed_terrain_edge_mask(result: Dictionary) -> void:
	if int(result.get("epoch", -1)) != _generation_epoch:
		return
	var target_chunk: Vector2i = _canonicalize_chunk_coord(
		result.get("target_chunk", INVALID_CHUNK_COORD) as Vector2i,
	)
	if target_chunk == INVALID_CHUNK_COORD:
		return
	var expected_revision: int = _get_terrain_edge_mask_revision(target_chunk)
	_terrain_edge_mask_inflight_chunks.erase(target_chunk)
	if int(result.get("revision", -1)) != expected_revision:
		return
	if not bool(result.get("success", false)):
		push_warning(
			"Terrain edge native mask failed for chunk %s: %s" % [
				str(target_chunk),
				str(result.get("message", "")),
			],
		)
		return
	_terrain_edge_masks_by_chunk[target_chunk] = result
	_last_terrain_edge_mask_result = {
		"ready": true,
		"chunk_coord": target_chunk,
		"reason": result.get("reason", &"worker") as StringName,
		"mask_width": int(result.get("width", 0)),
		"mask_height": int(result.get("height", 0)),
		"pixels_per_tile": int(result.get("pixels_per_tile", 0)),
		"solid_sample_count": int(result.get("solid_sample_count", 0)),
		"queue_wait_ms": int(result.get("queue_wait_ms", 0)),
		"worker_elapsed_ms": int(result.get("worker_elapsed_ms", 0)),
		"request_to_complete_ms": int(result.get("request_to_complete_ms", 0)),
		"visual_pending": _pending_terrain_edge_mask_visual_upload_set.has(target_chunk),
	}
	var chunk_view: ChunkView = _chunk_views.get(target_chunk, null) as ChunkView
	if chunk_view != null:
		_apply_ready_terrain_edge_mask_to_chunk_view(target_chunk, chunk_view, result)
	# Terrain-edge masks are decorative shoreline presentation. They may attach
	# to an existing view, but must not republish or block chunk visibility.


func _build_mountain_native_mask_origin(chunk_coord: Vector2i) -> Vector2:
	return WorldRuntimeConstants.chunk_origin_px(chunk_coord) \
			- Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX * MOUNTAIN_HALO_MASK_RADIUS_TILES)


func _get_ready_mountain_native_mask_result(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var result: Dictionary = _mountain_native_masks_by_chunk.get(chunk_coord, { }) as Dictionary
	if result.is_empty():
		return { }
	if int(result.get("epoch", -1)) != _generation_epoch \
			or int(result.get("revision", -1)) != _get_mountain_mask_revision(chunk_coord) \
			or not bool(result.get("success", false)):
		_mountain_native_masks_by_chunk.erase(chunk_coord)
		return { }
	return result


func _build_terrain_edge_mask_origin(chunk_coord: Vector2i) -> Vector2:
	return WorldRuntimeConstants.chunk_origin_px(chunk_coord) \
			- Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX * TERRAIN_EDGE_HALO_MASK_RADIUS_TILES)


func _get_ready_terrain_edge_mask_result(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var result: Dictionary = _terrain_edge_masks_by_chunk.get(chunk_coord, { }) as Dictionary
	if result.is_empty():
		return { }
	if int(result.get("epoch", -1)) != _generation_epoch \
			or int(result.get("revision", -1)) != _get_terrain_edge_mask_revision(chunk_coord) \
			or not bool(result.get("success", false)):
		_terrain_edge_masks_by_chunk.erase(chunk_coord)
		return { }
	return result


func _has_loaded_mountain_halo_sources(chunk_coord: Vector2i) -> bool:
	for source_chunk: Vector2i in _build_chunk_coords_for_radius(chunk_coord, 1):
		if not _chunk_packets.has(source_chunk):
			_enqueue_chunk_if_needed(source_chunk)
			return false
	return true


func _has_loaded_terrain_edge_halo_sources(chunk_coord: Vector2i) -> bool:
	for source_chunk: Vector2i in _build_chunk_coords_for_radius(chunk_coord, 1):
		if not _chunk_packets.has(source_chunk):
			_enqueue_chunk_if_needed(source_chunk)
			return false
	return true


func _request_mountain_native_mask_for_chunk(
		chunk_coord: Vector2i,
		closed_halo: PackedByteArray,
		dug_halo: PackedByteArray,
		reason: StringName,
) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _get_ready_mountain_native_mask_result(chunk_coord).is_empty():
		return
	var revision: int = _get_mountain_mask_revision(chunk_coord)
	var inflight: Dictionary = _mountain_native_mask_inflight_chunks.get(chunk_coord, { }) as Dictionary
	if not inflight.is_empty() and int(inflight.get("revision", -1)) == revision:
		return
	_mountain_native_mask_inflight_chunks[chunk_coord] = {
		"revision": revision,
		"reason": reason,
	}
	_mountain_mask_backend.queue_mountain_halo_mask_request(
		closed_halo,
		chunk_coord,
		_build_mountain_native_mask_origin(chunk_coord),
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		MOUNTAIN_HALO_MASK_PIXELS_PER_TILE,
		_generation_epoch,
		revision,
		reason,
		&"mountain",
		dug_halo,
	)


func _request_terrain_edge_mask_for_chunk(
		chunk_coord: Vector2i,
		solid_halo: PackedByteArray,
		reason: StringName,
) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _get_ready_terrain_edge_mask_result(chunk_coord).is_empty():
		return
	var revision: int = _get_terrain_edge_mask_revision(chunk_coord)
	var inflight: Dictionary = _terrain_edge_mask_inflight_chunks.get(chunk_coord, { }) as Dictionary
	if not inflight.is_empty() and int(inflight.get("revision", -1)) == revision:
		return
	_terrain_edge_mask_inflight_chunks[chunk_coord] = {
		"revision": revision,
		"reason": reason,
	}
	_mountain_mask_backend.queue_mountain_halo_mask_request(
		solid_halo,
		chunk_coord,
		_build_terrain_edge_mask_origin(chunk_coord),
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		TERRAIN_EDGE_HALO_MASK_PIXELS_PER_TILE,
		_generation_epoch,
		revision,
		reason,
		&"terrain_edge",
	)


func _apply_ready_mountain_native_mask_to_chunk_view(
		chunk_coord: Vector2i,
		chunk_view: ChunkView,
		mask_result: Dictionary,
) -> bool:
	if chunk_view == null or mask_result.is_empty():
		return false
	var mask_origin_world: Vector2 = mask_result.get(
		"mask_origin_world",
		_build_mountain_native_mask_origin(chunk_coord),
	) as Vector2
	var applied_data: bool = chunk_view.apply_mountain_native_mask_data(
		mask_result,
		mask_origin_world,
	)
	if applied_data:
		_queue_mountain_native_mask_visual_upload(chunk_coord)
	else:
		_drop_mountain_native_mask_visual_upload(chunk_coord)
		chunk_view.clear_mountain_render_page()
	return applied_data


func _apply_ready_terrain_edge_mask_to_chunk_view(
		chunk_coord: Vector2i,
		chunk_view: ChunkView,
		mask_result: Dictionary,
) -> bool:
	if chunk_view == null or mask_result.is_empty():
		return false
	var mask_origin_world: Vector2 = mask_result.get(
		"mask_origin_world",
		_build_terrain_edge_mask_origin(chunk_coord),
	) as Vector2
	var applied_data: bool = chunk_view.apply_terrain_edge_mask_data(
		mask_result,
		mask_origin_world,
	)
	if applied_data:
		_queue_terrain_edge_mask_visual_upload(chunk_coord)
	else:
		_drop_terrain_edge_mask_visual_upload(chunk_coord)
		chunk_view.clear_terrain_edge_mask()
	return applied_data


func _apply_mountain_mask_to_chunk_view(
		chunk_coord: Vector2i,
		chunk_view: ChunkView,
		_packet: Dictionary,
		reason: StringName = &"publish",
) -> void:
	var ready_mask_result: Dictionary = _get_ready_mountain_native_mask_result(chunk_coord)
	if not ready_mask_result.is_empty():
		_apply_ready_mountain_native_mask_to_chunk_view(chunk_coord, chunk_view, ready_mask_result)


func _apply_terrain_edge_mask_to_chunk_view(
		chunk_coord: Vector2i,
		chunk_view: ChunkView,
		_packet: Dictionary,
		reason: StringName = &"publish",
) -> void:
	if not TERRAIN_EDGE_MASK_RUNTIME_ENABLED:
		_forget_terrain_edge_mask(chunk_coord, true, false)
		return
	var ready_mask_result: Dictionary = _get_ready_terrain_edge_mask_result(chunk_coord)
	if not ready_mask_result.is_empty():
		_apply_ready_terrain_edge_mask_to_chunk_view(chunk_coord, chunk_view, ready_mask_result)


func _record_mountain_native_mask_build(
		chunk_coord: Vector2i,
		reason: StringName,
		elapsed_usec: int,
		mask_result: Dictionary,
) -> void:
	var elapsed_ms: float = float(elapsed_usec) / 1000.0
	_mountain_native_mask_build_count_total += 1
	_mountain_native_mask_build_count_tick += 1
	_mountain_native_mask_elapsed_ms_last = elapsed_ms
	_mountain_native_mask_elapsed_ms_max_total = maxf(_mountain_native_mask_elapsed_ms_max_total, elapsed_ms)
	_mountain_native_mask_elapsed_ms_max_tick = maxf(_mountain_native_mask_elapsed_ms_max_tick, elapsed_ms)
	_mountain_native_mask_worker_elapsed_ms_last = float(mask_result.get("worker_elapsed_ms", elapsed_ms))
	_mountain_native_mask_worker_elapsed_ms_max_total = maxf(
		_mountain_native_mask_worker_elapsed_ms_max_total,
		_mountain_native_mask_worker_elapsed_ms_last,
	)
	_mountain_native_mask_request_to_complete_ms_last = float(mask_result.get("request_to_complete_ms", elapsed_ms))
	_mountain_native_mask_request_to_complete_ms_max_total = maxf(
		_mountain_native_mask_request_to_complete_ms_max_total,
		_mountain_native_mask_request_to_complete_ms_last,
	)
	_mountain_native_mask_last_chunk = chunk_coord
	_mountain_native_mask_last_reason = reason
	_last_mountain_mask_result = {
		"ready": true,
		"native_mask_runtime": true,
		"chunk_coord": chunk_coord,
		"reason": reason,
		"mask_width": int(mask_result.get("width", 0)),
		"mask_height": int(mask_result.get("height", 0)),
		"pixels_per_tile": int(mask_result.get("pixels_per_tile", 0)),
		"solid_sample_count": int(mask_result.get("solid_sample_count", 0)),
		"closed_sample_count": int(mask_result.get("closed_sample_count", 0)),
		"dug_sample_count": int(mask_result.get("dug_sample_count", 0)),
		"paired_construction_masks": not (
			mask_result.get("closed_roof_mask", PackedByteArray()) as PackedByteArray
		).is_empty(),
		"native_mask_elapsed_ms": elapsed_ms,
		"native_mask_worker_elapsed_ms": _mountain_native_mask_worker_elapsed_ms_last,
		"native_mask_request_to_complete_ms": _mountain_native_mask_request_to_complete_ms_last,
		"queue_wait_ms": int(mask_result.get("queue_wait_ms", 0)),
		"worker_elapsed_ms": int(mask_result.get("worker_elapsed_ms", elapsed_ms)),
		"request_to_complete_ms": int(mask_result.get("request_to_complete_ms", elapsed_ms)),
		"native_mask_visual_pending": _pending_mountain_native_mask_visual_upload_set.has(chunk_coord),
	}


func _record_mountain_native_mask_clear(chunk_coord: Vector2i, reason: StringName) -> void:
	_mountain_native_mask_clear_count_total += 1
	_mountain_native_mask_last_chunk = chunk_coord
	_mountain_native_mask_last_reason = reason


func _apply_mountain_surface_local_dig_patch(chunk_coord: Vector2i, local_coord: Vector2i, terrain_id: int) -> void:
	if _uses_mountain_surface_presentation(terrain_id):
		return
	_refresh_mountain_native_masks_around_tile(_chunk_local_to_tile(chunk_coord, local_coord))


func _refresh_mountain_native_masks_around_tile(world_tile: Vector2i) -> void:
	# Mining gives an instant gameplay response via a world-space collision-only
	# mask byte clear, then re-flows the organic contour through native worker
	# reconciliation. Visible textures are not uploaded from this interactive path.
	var affected: Array[Vector2i] = _build_mountain_native_mask_dirty_chunks_for_tile(world_tile)
	_mountain_native_mask_last_refreshed_chunks = []
	for affected_chunk: Vector2i in affected:
		_mountain_native_mask_last_refreshed_chunks.append(affected_chunk)
		var chunk_view: ChunkView = _chunk_views.get(affected_chunk, null) as ChunkView
		if chunk_view != null:
			chunk_view.apply_mountain_world_dig_collision_patch(world_tile, 2)
		var dig_packet: Dictionary = _chunk_packets.get(affected_chunk, { }) as Dictionary
		if dig_packet.is_empty():
			continue
		_bump_mountain_mask_revision(affected_chunk)
		_mountain_torch_shadow_field_mask_cache.clear()
		_mountain_solid_halo_cache.erase(affected_chunk)
		_mountain_native_masks_by_chunk.erase(affected_chunk)
		_mountain_native_mask_inflight_chunks.erase(affected_chunk)
		# A target mask is valid only when its complete 3x3 packet source ring is
		# resident. Missing sources must never be interpreted/cached as open air.
		if not _has_loaded_mountain_halo_sources(affected_chunk):
			continue
		var dig_halo: Dictionary = _get_cached_mountain_solid_halo(affected_chunk)
		if bool(dig_halo.get("has_closed", false)):
			_request_mountain_native_mask_for_chunk(
				affected_chunk,
				dig_halo.get("closed_halo", PackedByteArray()) as PackedByteArray,
				dig_halo.get("dug_halo", PackedByteArray()) as PackedByteArray,
				&"mining",
			)


func _build_mountain_native_mask_dirty_chunks_for_tile(world_tile: Vector2i) -> Array[Vector2i]:
	var canonical_tile: Vector2i = _canonicalize_tile_coord(world_tile)
	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	var affected: Array[Vector2i] = [center_chunk]
	var halo_radius: int = MOUNTAIN_HALO_MASK_RADIUS_TILES
	if local_coord.x < halo_radius:
		affected.append(center_chunk + Vector2i.LEFT)
	if local_coord.x >= WorldRuntimeConstants.CHUNK_SIZE - halo_radius:
		affected.append(center_chunk + Vector2i.RIGHT)
	if local_coord.y < halo_radius:
		affected.append(center_chunk + Vector2i.UP)
	if local_coord.y >= WorldRuntimeConstants.CHUNK_SIZE - halo_radius:
		affected.append(center_chunk + Vector2i.DOWN)
	if local_coord.x < halo_radius and local_coord.y < halo_radius:
		affected.append(center_chunk + Vector2i.LEFT + Vector2i.UP)
	if local_coord.x >= WorldRuntimeConstants.CHUNK_SIZE - halo_radius and local_coord.y < halo_radius:
		affected.append(center_chunk + Vector2i.RIGHT + Vector2i.UP)
	if local_coord.x < halo_radius and local_coord.y >= WorldRuntimeConstants.CHUNK_SIZE - halo_radius:
		affected.append(center_chunk + Vector2i.LEFT + Vector2i.DOWN)
	if local_coord.x >= WorldRuntimeConstants.CHUNK_SIZE - halo_radius and local_coord.y >= WorldRuntimeConstants.CHUNK_SIZE - halo_radius:
		affected.append(center_chunk + Vector2i.RIGHT + Vector2i.DOWN)
	var refreshed: Dictionary = { }
	var dirty_chunks: Array[Vector2i] = []
	for affected_chunk: Vector2i in affected:
		affected_chunk = _canonicalize_chunk_coord(affected_chunk)
		if refreshed.has(affected_chunk):
			continue
		refreshed[affected_chunk] = true
		dirty_chunks.append(affected_chunk)
	return dirty_chunks


func _build_chunk_coords_for_world_rect(world_min: Vector2, world_max: Vector2) -> Array[Vector2i]:
	var min_tile: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(world_min))
	var max_tile: Vector2i = _canonicalize_tile_coord(WorldRuntimeConstants.world_to_tile(world_max))
	var min_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(min_tile)
	var max_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(max_tile)
	var coords: Array[Vector2i] = []
	for cy: int in range(min_chunk.y, max_chunk.y + 1):
		for cx: int in range(min_chunk.x, max_chunk.x + 1):
			coords.append(_canonicalize_chunk_coord(Vector2i(cx, cy)))
	return coords


func _sample_mountain_native_mask_result(mask_result: Dictionary, chunk_coord: Vector2i, world_pos: Vector2) -> int:
	var mask_bytes: PackedByteArray = mask_result.get("mask", PackedByteArray()) as PackedByteArray
	var width: int = int(mask_result.get("width", 0))
	var height: int = int(mask_result.get("height", 0))
	var step_px: float = float(mask_result.get("step_px", 0.0))
	if width <= 0 or height <= 0 or step_px <= 0.0 or mask_bytes.size() != width * height:
		return 0
	var origin: Vector2 = mask_result.get(
		"mask_origin_world",
		_build_mountain_native_mask_origin(chunk_coord),
	) as Vector2
	var mask_pos: Vector2 = (world_pos - origin) / step_px
	var x: int = floori(mask_pos.x)
	var y: int = floori(mask_pos.y)
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return int(mask_bytes[y * width + x])


func _blit_mountain_native_mask_result_to_shadow_field(
		mask_result: Dictionary,
		window_origin: Vector2,
		window_width: int,
		window_height: int,
		window_step_px: float,
		copy_min: Vector2,
		copy_max: Vector2,
		target_bytes: PackedByteArray,
		active_floor_halo: PackedByteArray = PackedByteArray(),
) -> int:
	var mask_bytes: PackedByteArray = mask_result.get("mask", PackedByteArray()) as PackedByteArray
	var visual_mask_bytes: PackedByteArray = mask_result.get(
		"visual_remaining_mass_mask",
		mask_bytes,
	) as PackedByteArray
	var closed_mask_bytes: PackedByteArray = mask_result.get(
		"closed_roof_mask",
		mask_bytes,
	) as PackedByteArray
	var dug_halo: PackedByteArray = mask_result.get("dug_halo", PackedByteArray()) as PackedByteArray
	var source_width: int = int(mask_result.get("width", 0))
	var source_height: int = int(mask_result.get("height", 0))
	var source_step_px: float = float(mask_result.get("step_px", 0.0))
	if source_width <= 0 \
			or source_height <= 0 \
			or source_step_px <= 0.0 \
			or window_width <= 0 \
			or window_height <= 0 \
			or window_step_px <= 0.0 \
			or mask_bytes.size() != source_width * source_height \
			or visual_mask_bytes.size() != source_width * source_height \
			or closed_mask_bytes.size() != source_width * source_height \
			or target_bytes.size() != window_width * window_height:
		return 0
	var pixels_per_tile: int = int(mask_result.get("pixels_per_tile", 0))
	var halo_side: int = int(mask_result.get("halo_side", 0))
	# This is the raw cavity-cache halo (0/1), not ChunkView's normalized GPU
	# selector (0/255). Testing specifically for 255 silently restores CLOSED C
	# inside every real cave: mouths stop passing light and retaining islands no
	# longer cast as isolated blockers.
	var has_floor_selector: bool = pixels_per_tile > 0 \
			and halo_side > 0 \
			and active_floor_halo.size() == halo_side * halo_side \
			and dug_halo.size() == halo_side * halo_side \
			and source_width == halo_side * pixels_per_tile \
			and source_height == halo_side * pixels_per_tile \
			and _solid_halo_has_any(active_floor_halo)
	var component_reveal_halo: PackedByteArray = _build_mountain_torch_component_support_halo(
		active_floor_halo,
		dug_halo,
		halo_side,
	) if has_floor_selector else PackedByteArray()
	var source_origin: Vector2 = mask_result.get("mask_origin_world", Vector2.ZERO) as Vector2
	var source_max: Vector2 = source_origin + Vector2(float(source_width), float(source_height)) * source_step_px
	var window_max: Vector2 = window_origin + Vector2(float(window_width), float(window_height)) * window_step_px
	var blit_min := Vector2(
		maxf(source_origin.x, maxf(window_origin.x, copy_min.x)),
		maxf(source_origin.y, maxf(window_origin.y, copy_min.y)),
	)
	var blit_max := Vector2(
		minf(source_max.x, minf(window_max.x, copy_max.x)),
		minf(source_max.y, minf(window_max.y, copy_max.y)),
	)
	if blit_min.x >= blit_max.x or blit_min.y >= blit_max.y:
		return 0

	var dst_x0: int = clampi(ceili((blit_min.x - window_origin.x) / window_step_px - 0.5), 0, window_width)
	var dst_y0: int = clampi(ceili((blit_min.y - window_origin.y) / window_step_px - 0.5), 0, window_height)
	var dst_x1: int = clampi(floori((blit_max.x - window_origin.x) / window_step_px - 0.5) + 1, 0, window_width)
	var dst_y1: int = clampi(floori((blit_max.y - window_origin.y) / window_step_px - 0.5) + 1, 0, window_height)
	if dst_x0 >= dst_x1 or dst_y0 >= dst_y1:
		return 0

	var added_solid: int = 0
	if absf(source_step_px - window_step_px) <= 0.001:
		var copy_width: int = dst_x1 - dst_x0
		var first_sample_x: float = window_origin.x + (float(dst_x0) + 0.5) * window_step_px
		var src_x0: int = floori((first_sample_x - source_origin.x) / source_step_px)
		if src_x0 < 0 or src_x0 + copy_width > source_width:
			return 0
		for dst_y: int in range(dst_y0, dst_y1):
			var sample_y: float = window_origin.y + (float(dst_y) + 0.5) * window_step_px
			var src_y: int = floori((sample_y - source_origin.y) / source_step_px)
			if src_y < 0 or src_y >= source_height:
				continue
			var dst_index: int = dst_y * window_width + dst_x0
			var src_index: int = src_y * source_width + src_x0
			for _i: int in range(copy_width):
				var previous: int = int(target_bytes[dst_index])
				var value: int = int(closed_mask_bytes[src_index])
				if has_floor_selector:
					var selector_index: int = floori(float(src_y) / float(pixels_per_tile)) * halo_side \
							+ floori(float(src_index % source_width) / float(pixels_per_tile))
					if int(component_reveal_halo[selector_index]) \
							>= MountainTorchComponentSelector.SUPPORT_CODE:
						value = int(visual_mask_bytes[src_index])
				if value > previous:
					target_bytes[dst_index] = value
					if previous <= MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD \
							and value > MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD:
						added_solid += 1
				dst_index += 1
				src_index += 1
		return added_solid

	for dst_y: int in range(dst_y0, dst_y1):
		var sample_y: float = window_origin.y + (float(dst_y) + 0.5) * window_step_px
		var src_y: int = floori((sample_y - source_origin.y) / source_step_px)
		if src_y < 0 or src_y >= source_height:
			continue
		var dst_row: int = dst_y * window_width
		var src_row: int = src_y * source_width
		for dst_x: int in range(dst_x0, dst_x1):
			var sample_x: float = window_origin.x + (float(dst_x) + 0.5) * window_step_px
			var src_x: int = floori((sample_x - source_origin.x) / source_step_px)
			if src_x < 0 or src_x >= source_width:
				continue
			var dst_index: int = dst_row + dst_x
			var previous: int = int(target_bytes[dst_index])
			var source_index: int = src_row + src_x
			var value: int = int(closed_mask_bytes[source_index])
			if has_floor_selector:
				var selector_index: int = floori(float(src_y) / float(pixels_per_tile)) * halo_side \
						+ floori(float(src_x) / float(pixels_per_tile))
				if int(component_reveal_halo[selector_index]) \
						>= MountainTorchComponentSelector.SUPPORT_CODE:
					value = int(visual_mask_bytes[source_index])
			if value <= previous:
				continue
			target_bytes[dst_index] = value
			if previous <= MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD \
					and value > MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD:
				added_solid += 1
	return added_solid


func _build_mountain_torch_component_support_halo(
		active_floor_halo: PackedByteArray,
		dug_halo: PackedByteArray,
		halo_side: int,
) -> PackedByteArray:
	if halo_side <= 0 \
			or active_floor_halo.size() != halo_side * halo_side \
			or dug_halo.size() != halo_side * halo_side:
		return PackedByteArray()
	return MountainTorchComponentSelector.build_component_support_halo(
		active_floor_halo,
		dug_halo,
	)


func _forget_mountain_mask(
		chunk_coord: Vector2i,
		clear_view: bool,
		bump_revision: bool = false,
		preserve_visual: bool = false,
) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_drop_mountain_native_mask_visual_upload(chunk_coord)
	if bump_revision:
		_bump_mountain_mask_revision(chunk_coord)
		_mountain_torch_shadow_field_mask_cache.clear()
	_mountain_solid_halo_cache.erase(chunk_coord)
	_mountain_native_masks_by_chunk.erase(chunk_coord)
	_mountain_native_mask_inflight_chunks.erase(chunk_coord)
	if clear_view:
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view != null:
			if preserve_visual:
				chunk_view.invalidate_mountain_render_page_hit_mask_keep_visual()
			else:
				chunk_view.clear_mountain_render_page()


func _forget_terrain_edge_mask(
		chunk_coord: Vector2i,
		clear_view: bool,
		bump_revision: bool = false,
) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_drop_terrain_edge_mask_visual_upload(chunk_coord)
	if bump_revision:
		_bump_terrain_edge_mask_revision(chunk_coord)
	_terrain_edge_solid_halo_cache.erase(chunk_coord)
	_terrain_edge_masks_by_chunk.erase(chunk_coord)
	_terrain_edge_mask_inflight_chunks.erase(chunk_coord)
	if clear_view:
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view != null:
			chunk_view.clear_terrain_edge_mask()


func _get_mountain_mask_revision(chunk_coord: Vector2i) -> int:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	return int(_mountain_mask_revision_by_chunk.get(chunk_coord, 0))


func _bump_mountain_mask_revision(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_mountain_mask_revision_by_chunk[chunk_coord] = _get_mountain_mask_revision(chunk_coord) + 1


func _get_terrain_edge_mask_revision(chunk_coord: Vector2i) -> int:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	return int(_terrain_edge_mask_revision_by_chunk.get(chunk_coord, 0))


func _bump_terrain_edge_mask_revision(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_terrain_edge_mask_revision_by_chunk[chunk_coord] = _get_terrain_edge_mask_revision(chunk_coord) + 1


func _ensure_mountain_mask_sources() -> void:
	# Mountain presentation textures are authored data: the registry-resolved
	# material set owns them (mipmapped at import). The raster preset JSON and
	# the old hardcoded paths remain dev-raster-probe inputs only.
	if _mountain_mask_preset.is_empty():
		_mountain_mask_preset = _load_mountain_mask_preset()
	if _mountain_top_fill_texture != null \
			and _mountain_face_fill_texture != null \
			and _mountain_top_normal_fill_texture != null \
			and _mountain_face_normal_fill_texture != null \
			and _mountain_foothill_texture != null \
			and _mountain_foothill_normal_texture != null:
		return
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID,
	)
	assert(material_set != null, "Missing TerrainMaterialSet %s for mountain mask presentation." % MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID)
	_mountain_top_fill_texture = material_set.top_albedo
	_mountain_face_fill_texture = material_set.face_albedo
	_mountain_top_normal_fill_texture = material_set.top_normal
	_mountain_face_normal_fill_texture = material_set.face_normal
	_mountain_foothill_texture = material_set.get_texture_slot(&"foothill_albedo")
	_mountain_foothill_normal_texture = material_set.get_texture_slot(&"foothill_normal")
	assert(_mountain_top_fill_texture != null, "Mountain material set %s requires top_albedo." % MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID)
	assert(_mountain_face_fill_texture != null, "Mountain material set %s requires face_albedo." % MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID)
	assert(_mountain_top_normal_fill_texture != null, "Mountain material set %s requires top_normal." % MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID)
	assert(_mountain_face_normal_fill_texture != null, "Mountain material set %s requires face_normal." % MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID)
	assert(_mountain_foothill_texture != null, "Mountain material set %s requires extra texture foothill_albedo." % MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID)
	assert(_mountain_foothill_normal_texture != null, "Mountain material set %s requires extra texture foothill_normal." % MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID)


func _ensure_terrain_edge_mask_sources() -> void:
	if _terrain_edge_top_texture != null \
			and _terrain_edge_face_texture != null \
			and _terrain_edge_top_normal_texture != null \
			and _terrain_edge_face_normal_texture != null:
		return
	var top_image: Image = _load_mountain_mask_source_image(TERRAIN_EDGE_TOP_TEXTURE_PATH, "terrain edge top")
	var face_image: Image = _load_mountain_mask_source_image(TERRAIN_EDGE_FACE_TEXTURE_PATH, "terrain edge face")
	var top_normal_image: Image = _load_mountain_mask_source_image(TERRAIN_EDGE_TOP_NORMAL_TEXTURE_PATH, "terrain edge top normal")
	var face_normal_image: Image = _load_mountain_mask_source_image(TERRAIN_EDGE_FACE_NORMAL_TEXTURE_PATH, "terrain edge face normal")
	assert(top_image != null, "Terrain edge top source image is required: %s" % TERRAIN_EDGE_TOP_TEXTURE_PATH)
	assert(face_image != null, "Terrain edge face source image is required: %s" % TERRAIN_EDGE_FACE_TEXTURE_PATH)
	assert(top_normal_image != null, "Terrain edge top normal source image is required: %s" % TERRAIN_EDGE_TOP_NORMAL_TEXTURE_PATH)
	assert(face_normal_image != null, "Terrain edge face normal source image is required: %s" % TERRAIN_EDGE_FACE_NORMAL_TEXTURE_PATH)
	if top_image != null and _terrain_edge_top_texture == null:
		top_image.generate_mipmaps()
		_terrain_edge_top_texture = ImageTexture.create_from_image(top_image)
	if face_image != null and _terrain_edge_face_texture == null:
		face_image.generate_mipmaps()
		_terrain_edge_face_texture = ImageTexture.create_from_image(face_image)
	if top_normal_image != null and _terrain_edge_top_normal_texture == null:
		top_normal_image.generate_mipmaps()
		_terrain_edge_top_normal_texture = ImageTexture.create_from_image(top_normal_image)
	if face_normal_image != null and _terrain_edge_face_normal_texture == null:
		face_normal_image.generate_mipmaps()
		_terrain_edge_face_normal_texture = ImageTexture.create_from_image(face_normal_image)


func _ensure_grass_blob_overlay_source() -> void:
	if _grass_blob_overlay_texture != null \
			and _grass_blob_overlay_texture_2 != null \
			and _grass_blob_overlay_texture_3 != null \
			and _grass_blob_overlay_normal_texture != null:
		return
	var grass_image: Image = _load_mountain_mask_source_image(
		GRASS_BLOB_OVERLAY_TEXTURE_PATH,
		"dry grass overlay sparse",
	)
	var grass_image_2: Image = _load_mountain_mask_source_image(
		GRASS_BLOB_OVERLAY_TEXTURE_PATH_2,
		"dry grass overlay medium",
	)
	var grass_image_3: Image = _load_mountain_mask_source_image(
		GRASS_BLOB_OVERLAY_TEXTURE_PATH_3,
		"dry grass overlay dense",
	)
	var grass_normal_image: Image = _load_mountain_mask_source_image(
		GRASS_BLOB_OVERLAY_NORMAL_TEXTURE_PATH,
		"grass overlay normal",
	)
	assert(grass_image != null, "Grass overlay source image is required: %s" % GRASS_BLOB_OVERLAY_TEXTURE_PATH)
	assert(grass_image_2 != null, "Grass overlay source image is required: %s" % GRASS_BLOB_OVERLAY_TEXTURE_PATH_2)
	assert(grass_image_3 != null, "Grass overlay source image is required: %s" % GRASS_BLOB_OVERLAY_TEXTURE_PATH_3)
	assert(grass_normal_image != null, "Grass overlay normal source image is required: %s" % GRASS_BLOB_OVERLAY_NORMAL_TEXTURE_PATH)
	if grass_image == null or grass_image_2 == null or grass_image_3 == null or grass_normal_image == null:
		return
	grass_image.generate_mipmaps()
	grass_image_2.generate_mipmaps()
	grass_image_3.generate_mipmaps()
	grass_normal_image.generate_mipmaps()
	_grass_blob_overlay_texture = ImageTexture.create_from_image(grass_image)
	_grass_blob_overlay_texture_2 = ImageTexture.create_from_image(grass_image_2)
	_grass_blob_overlay_texture_3 = ImageTexture.create_from_image(grass_image_3)
	_grass_blob_overlay_normal_texture = ImageTexture.create_from_image(grass_normal_image)


func _ensure_plains_living_flora_source() -> void:
	if not PLAINS_LIVING_FLORA_ENABLED:
		_plains_living_flora_atlas = null
		return
	if _plains_living_flora_atlas != null:
		return
	_plains_living_flora_atlas = load(PLAINS_LIVING_FLORA_ATLAS_PATH) as Texture2D
	assert(
		_plains_living_flora_atlas != null,
		"WorldStreamer cannot load living flora atlas: %s" % PLAINS_LIVING_FLORA_ATLAS_PATH,
	)


func _ensure_plains_spiky_flora_source() -> void:
	if not PLAINS_SPIKY_FLORA_ENABLED:
		_plains_spiky_flora_atlases.clear()
		return
	if _plains_spiky_flora_atlases.size() == 2:
		return
	_plains_spiky_flora_atlases.clear()
	var spiky_atlas := load(PLAINS_SPIKY_FLORA_ATLAS_PATH) as Texture2D
	var brown_seaweed_atlas := load(PLAINS_BROWN_SEAWEED_STATIC_FLORA_ATLAS_PATH) as Texture2D
	if spiky_atlas != null:
		_plains_spiky_flora_atlases.append(spiky_atlas)
	if brown_seaweed_atlas != null:
		_plains_spiky_flora_atlases.append(brown_seaweed_atlas)
	assert(
		_plains_spiky_flora_atlases.size() == 2,
		"WorldStreamer cannot load static biofield flora atlases: %s, %s" % [
			PLAINS_SPIKY_FLORA_ATLAS_PATH,
			PLAINS_BROWN_SEAWEED_STATIC_FLORA_ATLAS_PATH,
		],
	)


func _load_mountain_mask_source_image(path: String, label: String) -> Image:
	var texture: Texture2D = load(path) as Texture2D
	assert(texture != null, "WorldStreamer cannot load %s texture: %s" % [label, path])
	if texture == null:
		return null
	var image: Image = texture.get_image()
	assert(image != null, "WorldStreamer %s texture has no readable image: %s" % [label, path])
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _load_mountain_mask_preset() -> Dictionary:
	var file: FileAccess = FileAccess.open(MOUNTAIN_MASK_PRESET_PATH, FileAccess.READ)
	assert(file != null, "Runtime mountain page preset is required: %s" % MOUNTAIN_MASK_PRESET_PATH)
	if file == null:
		return MountainPlateau2DRasterLayer.default_preset()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Runtime mountain page preset must be a Dictionary: %s" % MOUNTAIN_MASK_PRESET_PATH)
	if parsed is Dictionary:
		return parsed as Dictionary
	return MountainPlateau2DRasterLayer.default_preset()


func _can_publish_chunk_with_mountain_mask(chunk_coord: Vector2i, packet: Dictionary) -> bool:
	if not MOUNTAIN_NATIVE_MASK_RUNTIME_ENABLED:
		return true
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _has_loaded_mountain_halo_sources(chunk_coord):
		return false
	var cached_halo: Dictionary = _get_cached_mountain_solid_halo(chunk_coord)
	if not bool(cached_halo.get("has_closed", false)):
		_mountain_native_masks_by_chunk.erase(chunk_coord)
		_mountain_native_mask_inflight_chunks.erase(chunk_coord)
		return true
	if not _get_ready_mountain_native_mask_result(chunk_coord).is_empty():
		return true
	_request_mountain_native_mask_for_chunk(
		chunk_coord,
		cached_halo.get("closed_halo", PackedByteArray()) as PackedByteArray,
		cached_halo.get("dug_halo", PackedByteArray()) as PackedByteArray,
		&"publish",
	)
	if _packet_has_roof_bearing_mountain_metadata(packet):
		return false
	return true


func _prepare_terrain_edge_mask_for_publish(chunk_coord: Vector2i, _packet: Dictionary) -> void:
	if not TERRAIN_EDGE_MASK_RUNTIME_ENABLED:
		return
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _has_loaded_terrain_edge_halo_sources(chunk_coord):
		return
	var cached_halo: Dictionary = _get_cached_terrain_edge_solid_halo(chunk_coord)
	if not bool(cached_halo.get("has_shoreline", false)):
		_terrain_edge_masks_by_chunk.erase(chunk_coord)
		_terrain_edge_mask_inflight_chunks.erase(chunk_coord)
		return
	if not _get_ready_terrain_edge_mask_result(chunk_coord).is_empty():
		return
	_request_terrain_edge_mask_for_chunk(
		chunk_coord,
		cached_halo.get("halo", PackedByteArray()) as PackedByteArray,
		&"publish",
	)


func _reset_runtime_state() -> void:
	_generation_epoch += 1
	_packet_backend.clear_queued_work()
	_mountain_mask_backend.clear_queued_work()
	_awaiting_new_game_spawn_result = false
	_new_game_spawn_failed = false
	_requested_chunks.clear()
	_pending_publish_queue.clear()
	_mountain_solid_halo_cache.clear()
	_terrain_edge_solid_halo_cache.clear()
	_mountain_torch_shadow_field_mask_cache.clear()
	_active_publish_chunk = INVALID_CHUNK_COORD
	_player_chunk_coord = INVALID_CHUNK_COORD
	_current_stream_radius_chunks = WorldRuntimeConstants.STREAM_RADIUS_CHUNKS
	_desired_source_chunk_coords.clear()
	_desired_visible_chunk_coords.clear()
	_desired_mountain_mask_chunk_coords.clear()
	_desired_cache_center_chunk = INVALID_CHUNK_COORD
	_desired_cache_radius_chunks = -1
	_desired_cache_source_radius_chunks = -1
	_mountain_mask_revision_by_chunk.clear()
	_mountain_native_masks_by_chunk.clear()
	_mountain_native_mask_inflight_chunks.clear()
	_terrain_edge_mask_revision_by_chunk.clear()
	_terrain_edge_masks_by_chunk.clear()
	_terrain_edge_mask_inflight_chunks.clear()
	_pending_mountain_native_mask_visual_upload_chunks.clear()
	_pending_mountain_native_mask_visual_upload_set.clear()
	_pending_chunk_visibility_after_mountain_visual.clear()
	_pending_terrain_edge_mask_visual_upload_chunks.clear()
	_pending_terrain_edge_mask_visual_upload_set.clear()
	_pending_object_packet_visual_upload_chunks.clear()
	_pending_object_packet_visual_upload_set.clear()
	_pending_grass_scatter_visual_upload_chunks.clear()
	_pending_grass_scatter_visual_upload_set.clear()
	_mountain_native_mask_visual_upload_count_last_tick = 0
	_mountain_native_mask_visible_republish_skip_count_total = 0
	_mountain_surface_dig_visual_patch_skip_count_total = 0
	_last_mountain_mask_result = {
		"ready": false,
	}
	_last_terrain_edge_mask_result = {
		"ready": false,
	}
	for chunk_view_variant: Variant in _chunk_views.values():
		var chunk_view: ChunkView = chunk_view_variant as ChunkView
		if chunk_view:
			chunk_view.queue_free()
	_chunk_views.clear()
	_chunk_packets.clear()
	if _mining_feedback_layer != null and is_instance_valid(_mining_feedback_layer):
		_mining_feedback_layer.clear_feedback()
	roof_layers_per_chunk_max = 0
	_mountain_cavity_cache.clear()
	_active_cover_mountain_id = 0
	_active_cover_component_id = 0
	_did_warn_roof_layer_explosion = false


func _queue_new_game_spawn_resolution() -> void:
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		var legacy_spawn_tile: Vector2i = WorldSpawnResolver.resolve_preview_spawn_tile(
			world_seed,
			world_version,
			_worldgen_settings,
			_world_bounds_settings,
			_foundation_settings,
		)
		_position_local_player_at_spawn_tile(legacy_spawn_tile)
		return
	_awaiting_new_game_spawn_result = true
	_new_game_spawn_failed = false
	_packet_backend.queue_spawn_request(
		world_seed,
		world_version,
		_worldgen_settings_packed,
		_generation_epoch,
	)


func _drain_new_game_spawn_result() -> void:
	if not _awaiting_new_game_spawn_result:
		return
	var ready_results: Array[Dictionary] = _packet_backend.drain_completed_spawn_results(MAX_SPAWN_RESULTS_PER_TICK)
	for spawn_result: Dictionary in ready_results:
		if int(spawn_result.get("epoch", -1)) != _generation_epoch:
			continue
		if not bool(spawn_result.get("success", false)):
			var message: String = "WorldStreamer native spawn resolution failed: %s" \
					% str(spawn_result.get("message", "unknown error"))
			_fail_new_game_spawn_resolution(message)
			return
		var spawn_tile_variant: Variant = spawn_result.get("spawn_tile", null)
		if spawn_tile_variant is not Vector2i:
			_fail_new_game_spawn_resolution(
				"WorldStreamer native spawn resolution returned no Vector2i spawn_tile.",
			)
			return
		_awaiting_new_game_spawn_result = false
		_position_local_player_at_spawn_tile(spawn_tile_variant as Vector2i)
		return


func _fail_new_game_spawn_resolution(message: String) -> void:
	push_error(message)
	assert(false, message)
	_awaiting_new_game_spawn_result = false
	_new_game_spawn_failed = true


func _position_local_player_at_spawn_tile(spawn_tile: Vector2i) -> void:
	var player: Node2D = PlayerAuthority.get_local_player()
	if player == null:
		_fail_new_game_spawn_resolution(
			"WorldStreamer could not apply new-game spawn because local player is missing.",
		)
		return
	var canonical_spawn_tile: Vector2i = _canonicalize_tile_coord(spawn_tile)
	player.global_position = WorldRuntimeConstants.tile_to_world_center(canonical_spawn_tile)
	_player_chunk_coord = WorldRuntimeConstants.tile_to_chunk(canonical_spawn_tile)
	_current_stream_radius_chunks = _resolve_stream_radius_chunks()
	_rebuild_desired_chunk_cache()
	_new_game_spawn_failed = false


func _build_desired_chunk_coords(center_chunk: Vector2i) -> Array[Vector2i]:
	var source_radius: int = _resolve_source_cache_radius_chunks()
	return _build_chunk_coords_for_radius(center_chunk, source_radius)


func _rebuild_desired_chunk_cache() -> void:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		_desired_source_chunk_coords.clear()
		_desired_visible_chunk_coords.clear()
		_desired_mountain_mask_chunk_coords.clear()
		_desired_cache_center_chunk = INVALID_CHUNK_COORD
		_desired_cache_radius_chunks = -1
		_desired_cache_source_radius_chunks = -1
		return
	var source_radius: int = _resolve_source_cache_radius_chunks()
	if _desired_cache_center_chunk == _player_chunk_coord \
			and _desired_cache_radius_chunks == _current_stream_radius_chunks \
			and _desired_cache_source_radius_chunks == source_radius:
		return
	_desired_cache_center_chunk = _player_chunk_coord
	_desired_cache_radius_chunks = _current_stream_radius_chunks
	_desired_cache_source_radius_chunks = source_radius
	_desired_visible_chunk_coords = _build_chunk_coords_for_radius(
		_player_chunk_coord,
		_current_stream_radius_chunks,
	)
	_desired_mountain_mask_chunk_coords.clear()
	_desired_source_chunk_coords = _build_chunk_coords_for_radius(_player_chunk_coord, source_radius)


func _build_chunk_coords_for_radius(center_chunk: Vector2i, radius_chunks: int) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var seen: Dictionary = { }
	for y: int in range(center_chunk.y - radius_chunks, center_chunk.y + radius_chunks + 1):
		for x: int in range(center_chunk.x - radius_chunks, center_chunk.x + radius_chunks + 1):
			var coord: Vector2i = _canonicalize_chunk_coord(Vector2i(x, y))
			if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(coord.y):
				continue
			if seen.has(coord):
				continue
			seen[coord] = true
			coords.append(coord)
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var dist_a: int = _chunk_distance_sq(center_chunk, a)
			var dist_b: int = _chunk_distance_sq(center_chunk, b)
			return dist_a < dist_b if dist_a != dist_b else (a.x < b.x if a.x != b.x else a.y < b.y)
	)
	return coords


func _is_chunk_desired(chunk_coord: Vector2i) -> bool:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		return false
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
		return false
	return maxi(
		_wrapped_chunk_delta_abs(chunk_coord.x, _player_chunk_coord.x),
		absi(chunk_coord.y - _player_chunk_coord.y),
	) <= _current_stream_radius_chunks


func _resolve_source_cache_radius_chunks() -> int:
	return _current_stream_radius_chunks + 1


func _resolve_stream_radius_chunks() -> int:
	var radius: int = WorldRuntimeConstants.STREAM_RADIUS_CHUNKS
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null and is_instance_valid(camera):
		var zoom_x: float = maxf(camera.zoom.x, 0.05)
		var zoom_y: float = maxf(camera.zoom.y, 0.05)
		var viewport_size: Vector2 = get_viewport_rect().size
		var visible_world_size := Vector2(viewport_size.x / zoom_x, viewport_size.y / zoom_y)
		var chunk_size_px: float = float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
		var visible_radius_chunks: int = ceili(maxf(visible_world_size.x, visible_world_size.y) * 0.5 / chunk_size_px) + 1
		radius = maxi(radius, visible_radius_chunks)
	return mini(radius, MAX_VIEWPORT_STREAM_RADIUS_CHUNKS)


func _chunk_has_diff(chunk_coord: Vector2i) -> bool:
	return not _diff_store.get_chunk_override_local_coords(chunk_coord).is_empty()


func _handle_cover_chunk_published(published_chunk_coord: Vector2i) -> void:
	var previous_active_chunks: Array[Vector2i] = _mountain_cavity_cache.get_component_chunks(
		_active_cover_component_id,
	)
	var cover_result: Dictionary = _mountain_cavity_cache.on_chunk_loaded(
		published_chunk_coord,
		_collect_cover_candidate_tiles_for_chunk(published_chunk_coord),
		Callable(self, "_sample_mountain_cover_tile"),
	)
	_repair_active_cover_component_from_player_position()
	var affected_chunks: Dictionary = {published_chunk_coord: true}
	for previous_chunk: Vector2i in previous_active_chunks:
		affected_chunks[previous_chunk] = true
	var published_chunks: Array[Vector2i] = _variant_to_vector2i_array(cover_result.get("affected_chunks", []))
	for chunk_coord: Vector2i in published_chunks:
		affected_chunks[chunk_coord] = true
	_append_cover_component_chunks(affected_chunks, _active_cover_component_id)
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func _handle_cover_chunk_unloaded(chunk_coord: Vector2i) -> void:
	var previous_active_chunks: Array[Vector2i] = _mountain_cavity_cache.get_component_chunks(
		_active_cover_component_id,
	)
	var cover_result: Dictionary = _mountain_cavity_cache.on_chunk_unloaded(
		chunk_coord,
		_collect_diff_world_tiles_for_chunk(chunk_coord),
		Callable(self, "_sample_mountain_cover_tile"),
	)
	_repair_active_cover_component_from_player_position()
	var affected_chunks: Dictionary = {chunk_coord: true}
	for previous_chunk: Vector2i in previous_active_chunks:
		affected_chunks[previous_chunk] = true
	var unloaded_chunks: Array[Vector2i] = _variant_to_vector2i_array(cover_result.get("affected_chunks", []))
	for affected_chunk: Vector2i in unloaded_chunks:
		affected_chunks[affected_chunk] = true
	_append_cover_component_chunks(affected_chunks, _active_cover_component_id)
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func _handle_cover_tile_dug(world_tile: Vector2i) -> void:
	var previous_active_component_id: int = _active_cover_component_id
	var previous_active_chunks: Array[Vector2i] = _mountain_cavity_cache.get_component_chunks(
		previous_active_component_id,
	)
	var cover_result: Dictionary = _mountain_cavity_cache.on_tile_dug(
		world_tile,
		Callable(self, "_sample_mountain_cover_tile"),
	)
	var active_change: Dictionary = _repair_active_cover_component_from_player_position()
	var affected_chunks: Dictionary = { }
	var dug_chunks: Array[Vector2i] = _variant_to_vector2i_array(cover_result.get("affected_chunks", []))
	for chunk_coord: Vector2i in dug_chunks:
		affected_chunks[chunk_coord] = true
	if bool(active_change.get("state_changed", false)) \
			or previous_active_component_id != _active_cover_component_id:
		for previous_chunk: Vector2i in previous_active_chunks:
			affected_chunks[previous_chunk] = true
		_append_cover_component_chunks(affected_chunks, _active_cover_component_id)
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func _collect_cover_candidate_tiles_for_chunk(published_chunk_coord: Vector2i) -> Array[Vector2i]:
	published_chunk_coord = _canonicalize_chunk_coord(published_chunk_coord)
	var candidate_tiles: Dictionary = { }
	for sample_chunk_y: int in range(published_chunk_coord.y - 1, published_chunk_coord.y + 2):
		for sample_chunk_x: int in range(published_chunk_coord.x - 1, published_chunk_coord.x + 2):
			# Foundation topology wraps X only. DiffStore keys are canonical chunks,
			# so the x=-1/max+1 source ring must be normalized before lookup.
			var sample_chunk_coord: Vector2i = _canonicalize_chunk_coord(
				Vector2i(sample_chunk_x, sample_chunk_y),
			)
			for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(sample_chunk_coord):
				candidate_tiles[_chunk_local_to_tile(sample_chunk_coord, local_coord)] = true
	return _dictionary_vector2i_keys(candidate_tiles)


func _collect_diff_world_tiles_for_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var world_tiles: Array[Vector2i] = []
	for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(chunk_coord):
		world_tiles.append(_chunk_local_to_tile(chunk_coord, local_coord))
	return world_tiles


func _repair_active_cover_component_from_player_position() -> Dictionary:
	var previous_mountain_id: int = _active_cover_mountain_id
	var previous_component_id: int = _active_cover_component_id
	if PlayerAuthority.get_local_player() == null:
		_active_cover_mountain_id = 0
		_active_cover_component_id = 0
		if previous_mountain_id != 0 or previous_component_id != 0:
			_mountain_torch_shadow_field_mask_cache.clear()
		return {
			"state_changed": previous_mountain_id != 0 or previous_component_id != 0,
			"previous_mountain_id": previous_mountain_id,
			"previous_component_id": previous_component_id,
			"mountain_id": 0,
			"component_id": 0,
		}
	var current_sample: Dictionary = resolve_mountain_cover_at_world(
		PlayerAuthority.get_local_player_position(),
		previous_component_id,
	)
	var next_component_id: int = int(current_sample.get("component_id", 0))
	if not _mountain_cavity_cache.has_component(next_component_id):
		next_component_id = 0
	var next_mountain_id: int = int(current_sample.get("mountain_id", 0)) if next_component_id > 0 else 0
	_active_cover_mountain_id = next_mountain_id
	_active_cover_component_id = next_component_id
	if previous_mountain_id != next_mountain_id \
			or previous_component_id != next_component_id:
		_mountain_torch_shadow_field_mask_cache.clear()
	return {
		"state_changed": previous_mountain_id != next_mountain_id
		or previous_component_id != next_component_id,
		"previous_mountain_id": previous_mountain_id,
		"previous_component_id": previous_component_id,
		"mountain_id": next_mountain_id,
		"component_id": next_component_id,
	}


func _refresh_cover_visibility_for_loaded_chunks(target_chunks: Array[Vector2i] = []) -> void:
	var refresh_chunks: Array[Vector2i] = _expand_cover_visual_chunks(target_chunks)
	if refresh_chunks.is_empty():
		return
	var seen_chunks: Dictionary = { }
	var floor_masks_by_chunk: Dictionary = { }
	var opening_masks_by_chunk: Dictionary = { }
	for chunk_coord: Vector2i in refresh_chunks:
		if seen_chunks.has(chunk_coord):
			continue
		seen_chunks[chunk_coord] = true
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view == null:
			continue
		var visual_dirty: bool = chunk_view.apply_mountain_roof_reveal_halo(
			_build_cover_floor_visibility_halo(chunk_coord, floor_masks_by_chunk),
			_build_cover_opening_visibility_halo(chunk_coord, opening_masks_by_chunk),
		)
		if visual_dirty:
			_queue_mountain_native_mask_visual_upload(chunk_coord)


func _expand_cover_visual_chunks(target_chunks: Array[Vector2i]) -> Array[Vector2i]:
	var expanded: Dictionary = { }
	for target_chunk: Vector2i in target_chunks:
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var chunk_coord: Vector2i = _canonicalize_chunk_coord(
					target_chunk + Vector2i(offset_x, offset_y),
				)
				if _chunk_views.has(chunk_coord):
					expanded[chunk_coord] = true
	return _dictionary_vector2i_keys(expanded)


func _get_cached_cover_floor_mask(chunk_coord: Vector2i, cache: Dictionary) -> PackedByteArray:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not cache.has(chunk_coord):
		cache[chunk_coord] = _mountain_cavity_cache.build_chunk_component_floor_mask(
			chunk_coord,
			_active_cover_component_id,
		)
	return cache[chunk_coord] as PackedByteArray


func _get_cached_cover_opening_mask(chunk_coord: Vector2i, cache: Dictionary) -> PackedByteArray:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not cache.has(chunk_coord):
		cache[chunk_coord] = _mountain_cavity_cache.build_chunk_opening_floor_mask(
			chunk_coord,
		)
	return cache[chunk_coord] as PackedByteArray


func _build_cover_floor_visibility_halo(
		chunk_coord: Vector2i,
		floor_masks_by_chunk: Dictionary,
) -> PackedByteArray:
	return _build_cover_tile_visibility_halo(
		chunk_coord,
		floor_masks_by_chunk,
		false,
	)


func _build_cover_opening_visibility_halo(
		chunk_coord: Vector2i,
		opening_masks_by_chunk: Dictionary,
) -> PackedByteArray:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var opening_halo: PackedByteArray = _build_cover_tile_visibility_halo(
		chunk_coord,
		opening_masks_by_chunk,
		true,
	)
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE \
			+ MOUNTAIN_HALO_MASK_RADIUS_TILES * 2
	var halo_origin_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE \
			- Vector2i.ONE * MOUNTAIN_HALO_MASK_RADIUS_TILES
	for halo_y: int in range(halo_side):
		var row: int = halo_y * halo_side
		for halo_x: int in range(halo_side):
			var index: int = row + halo_x
			if int(opening_halo[index]) == 0:
				continue
			opening_halo[index] = _get_mountain_mouth_direction_bits(
				_canonicalize_tile_coord(halo_origin_tile + Vector2i(halo_x, halo_y)),
			)
	return _encode_mountain_mouth_lateral_continuations(opening_halo, halo_side)


## Wide single-direction mouths keep full depth across internal seams and
## round only their two outer ends. Multi-direction corner cells deliberately
## carry no shared continuation bits: a SOUTH neighbour must never deepen the
## EAST aperture of the same corner cell.
func _encode_mountain_mouth_lateral_continuations(
		direction_halo: PackedByteArray,
		halo_side: int,
) -> PackedByteArray:
	if halo_side <= 0 or direction_halo.size() != halo_side * halo_side:
		return PackedByteArray()
	var encoded_halo: PackedByteArray = direction_halo.duplicate()
	for halo_y: int in range(halo_side):
		var row: int = halo_y * halo_side
		for halo_x: int in range(halo_side):
			var index: int = row + halo_x
			var direction_bits: int = int(direction_halo[index]) & 15
			if direction_bits != MOUNTAIN_MOUTH_NORTH_BIT \
					and direction_bits != MOUNTAIN_MOUTH_EAST_BIT \
					and direction_bits != MOUNTAIN_MOUTH_SOUTH_BIT \
					and direction_bits != MOUNTAIN_MOUTH_WEST_BIT:
				continue
			var negative_continues: bool = false
			var positive_continues: bool = false
			var vertical_mouth_bits: int = direction_bits & (
				MOUNTAIN_MOUTH_NORTH_BIT | MOUNTAIN_MOUTH_SOUTH_BIT
			)
			if vertical_mouth_bits != 0:
				negative_continues = halo_x > 0 \
						and (int(direction_halo[index - 1]) & vertical_mouth_bits) != 0
				positive_continues = halo_x + 1 < halo_side \
						and (int(direction_halo[index + 1]) & vertical_mouth_bits) != 0
			var horizontal_mouth_bits: int = direction_bits & (
				MOUNTAIN_MOUTH_EAST_BIT | MOUNTAIN_MOUTH_WEST_BIT
			)
			if horizontal_mouth_bits != 0:
				negative_continues = negative_continues or (
					halo_y > 0 \
							and (int(direction_halo[index - halo_side]) \
									& horizontal_mouth_bits) != 0
				)
				positive_continues = positive_continues or (
					halo_y + 1 < halo_side \
							and (int(direction_halo[index + halo_side]) \
									& horizontal_mouth_bits) != 0
				)
			if negative_continues:
				encoded_halo[index] |= MOUNTAIN_MOUTH_LATERAL_NEGATIVE_BIT
			if positive_continues:
				encoded_halo[index] |= MOUNTAIN_MOUTH_LATERAL_POSITIVE_BIT
	return encoded_halo


func _get_mountain_mouth_direction_bits(world_tile: Vector2i) -> int:
	var source: Dictionary = _sample_mountain_cover_tile(world_tile)
	if not bool(source.get("ready", false)):
		return 0
	var source_mountain_id: int = int(source.get("mountain_id", 0))
	if source_mountain_id <= 0 or not bool(source.get("walkable", false)):
		return 0
	var direction_bits: int = 0
	var offsets: Array[Vector2i] = [
		Vector2i.UP,
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
	]
	var bits: Array[int] = [
		MOUNTAIN_MOUTH_NORTH_BIT,
		MOUNTAIN_MOUTH_EAST_BIT,
		MOUNTAIN_MOUTH_SOUTH_BIT,
		MOUNTAIN_MOUTH_WEST_BIT,
	]
	for index: int in range(offsets.size()):
		var neighbor: Dictionary = _sample_mountain_cover_tile(
			_canonicalize_tile_coord(world_tile + offsets[index]),
		)
		if not bool(neighbor.get("ready", false)) \
				or not bool(neighbor.get("walkable", false)):
			continue
		var neighbor_flags: int = int(neighbor.get("mountain_flags", 0))
		var neighbor_is_roof: bool = int(neighbor.get("mountain_id", 0)) > 0 \
				and (neighbor_flags & (
					WorldRuntimeConstants.MOUNTAIN_FLAG_WALL \
							| WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
				)) != 0
		if int(neighbor.get("mountain_id", 0)) != source_mountain_id \
				or not neighbor_is_roof:
			direction_bits |= bits[index]
	return direction_bits


func _build_cover_tile_visibility_halo(
		chunk_coord: Vector2i,
		visibility_masks_by_chunk: Dictionary,
		opening_only: bool,
) -> PackedByteArray:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var halo_radius: int = MOUNTAIN_HALO_MASK_RADIUS_TILES
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius * 2
	var visibility_halo := PackedByteArray()
	visibility_halo.resize(halo_side * halo_side)
	var local_min: int = -halo_radius
	var local_max: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius
	for source_offset_y: int in range(-1, 2):
		var source_base_y: int = source_offset_y * WorldRuntimeConstants.CHUNK_SIZE
		var from_local_y: int = maxi(local_min, source_base_y)
		var to_local_y: int = mini(local_max, source_base_y + WorldRuntimeConstants.CHUNK_SIZE)
		for source_offset_x: int in range(-1, 2):
			var source_base_x: int = source_offset_x * WorldRuntimeConstants.CHUNK_SIZE
			var from_local_x: int = maxi(local_min, source_base_x)
			var to_local_x: int = mini(local_max, source_base_x + WorldRuntimeConstants.CHUNK_SIZE)
			var source_chunk: Vector2i = _canonicalize_chunk_coord(
				chunk_coord + Vector2i(source_offset_x, source_offset_y),
			)
			var source_mask: PackedByteArray
			if opening_only:
				source_mask = _get_cached_cover_opening_mask(
					source_chunk,
					visibility_masks_by_chunk,
				)
			else:
				source_mask = _get_cached_cover_floor_mask(
					source_chunk,
					visibility_masks_by_chunk,
				)
			for local_y: int in range(from_local_y, to_local_y):
				var source_y: int = local_y - source_base_y
				var target_row: int = (local_y + halo_radius) * halo_side
				var source_row: int = source_y * WorldRuntimeConstants.CHUNK_SIZE
				for local_x: int in range(from_local_x, to_local_x):
					var source_x: int = local_x - source_base_x
					visibility_halo[target_row + local_x + halo_radius] = source_mask[
						source_row + source_x
					]
	return visibility_halo


func _append_cover_component_chunks(target: Dictionary, component_id: int) -> void:
	if component_id <= 0:
		return
	for chunk_coord: Vector2i in _mountain_cavity_cache.get_component_chunks(component_id):
		target[chunk_coord] = true


func _apply_debug_overlay_visibility_to_loaded_chunks() -> void:
	for chunk_coord_variant: Variant in _chunk_views.keys():
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord_variant) as ChunkView
		if chunk_view == null:
			continue
		chunk_view.set_debug_overlays(
			_debug_tile_grid_visible,
			_debug_mountain_solid_visible,
			_debug_mountain_contour_visible,
		)


func _refresh_debug_visuals_for_loaded_chunks() -> void:
	_apply_debug_overlay_visibility_to_loaded_chunks()
	if not _debug_mountain_solid_visible and not _debug_mountain_contour_visible:
		return
	for chunk_coord: Vector2i in _dictionary_vector2i_keys(_chunk_views):
		_refresh_debug_visuals_for_chunk(chunk_coord)


func _refresh_debug_visuals_for_chunk(chunk_coord: Vector2i) -> void:
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if chunk_view == null:
		return
	chunk_view.set_debug_overlays(
		_debug_tile_grid_visible,
		_debug_mountain_solid_visible,
		_debug_mountain_contour_visible,
	)
	if not _debug_mountain_solid_visible and not _debug_mountain_contour_visible:
		return
	var solid_mask: PackedByteArray = _build_local_mountain_solid_mask(chunk_coord)
	var contour_vertices := PackedVector2Array()
	var contour_indices := PackedInt32Array()
	if _debug_mountain_contour_visible:
		var contour_result: Dictionary = _build_native_mountain_contour_for_chunk(chunk_coord)
		contour_vertices = contour_result.get("vertices", PackedVector2Array()) as PackedVector2Array
		contour_indices = contour_result.get("indices", PackedInt32Array()) as PackedInt32Array
	chunk_view.apply_contour_debug_data(solid_mask, contour_vertices, contour_indices)


func _refresh_debug_visuals_around_tile(world_tile: Vector2i) -> void:
	if not _debug_mountain_solid_visible and not _debug_mountain_contour_visible:
		return
	var affected_chunks: Dictionary = { }
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(
				_canonicalize_tile_coord(world_tile + Vector2i(offset_x, offset_y)),
			)
			affected_chunks[chunk_coord] = true
	for chunk_coord: Vector2i in _dictionary_vector2i_keys(affected_chunks):
		_refresh_debug_visuals_for_chunk(chunk_coord)


func _build_local_mountain_solid_mask(chunk_coord: Vector2i) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty():
		return mask
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var world_tile: Vector2i = _chunk_local_to_tile(chunk_coord, local_coord)
		if _is_mountain_contour_solid_sample(_get_loaded_tile_data_no_enqueue(world_tile)):
			mask[index] = 1
	return mask


func _build_native_mountain_contour_for_chunk(chunk_coord: Vector2i) -> Dictionary:
	var world_core: Object = _get_contour_world_core()
	if world_core == null:
		return {
			"vertices": PackedVector2Array(),
			"indices": PackedInt32Array(),
		}
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_debug",
		_build_mountain_solid_halo(chunk_coord, 1),
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
	)
	if result_variant is Dictionary:
		return result_variant as Dictionary
	push_error("WorldCore.build_mountain_contour_debug returned non-dictionary result.")
	return {
		"vertices": PackedVector2Array(),
		"indices": PackedInt32Array(),
	}


func _build_native_mountain_halo_mask(
		closed_halo: PackedByteArray,
		mask_origin_world: Vector2,
		dug_halo: PackedByteArray = PackedByteArray(),
) -> Dictionary:
	var world_core: Object = _get_contour_world_core()
	if world_core == null:
		return { }
	var result_variant: Variant = world_core.call(
		"build_mountain_halo_mask",
		closed_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		MOUNTAIN_HALO_MASK_PIXELS_PER_TILE,
		mask_origin_world.x,
		mask_origin_world.y,
		dug_halo,
	)
	if result_variant is Dictionary:
		return result_variant as Dictionary
	push_error("WorldCore.build_mountain_halo_mask returned non-dictionary result.")
	return { }


func _solid_halo_has_any(solid_halo: PackedByteArray) -> bool:
	for value: int in solid_halo:
		if value != 0:
			return true
	return false


func _get_cached_mountain_solid_halo(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var revision: int = _get_mountain_mask_revision(chunk_coord)
	var cached: Dictionary = _mountain_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	if not cached.is_empty() \
			and int(cached.get("revision", -2)) == revision \
			and int(cached.get("epoch", -2)) == _generation_epoch:
		return cached
	var fields: Dictionary = _build_mountain_halo_fields(
		chunk_coord,
		MOUNTAIN_HALO_MASK_RADIUS_TILES,
	)
	var remaining_halo: PackedByteArray = fields.get(
		"remaining_halo",
		PackedByteArray(),
	) as PackedByteArray
	var closed_halo: PackedByteArray = fields.get(
		"closed_halo",
		PackedByteArray(),
	) as PackedByteArray
	cached = {
		"revision": revision,
		"epoch": _generation_epoch,
		# Compatibility field for grass, torch shadows and contour debug: those
		# systems consume the physical mass that remains after excavation.
		"halo": remaining_halo,
		"remaining_halo": remaining_halo,
		"closed_halo": closed_halo,
		"dug_halo": fields.get("dug_halo", PackedByteArray()) as PackedByteArray,
		"has_any": _solid_halo_has_any(remaining_halo),
		"has_closed": _solid_halo_has_any(closed_halo),
		"has_local_closed": bool(fields.get("has_local_closed", false)),
	}
	_mountain_solid_halo_cache[chunk_coord] = cached
	return cached


func _get_cached_terrain_edge_solid_halo(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var revision: int = _get_terrain_edge_mask_revision(chunk_coord)
	var cached: Dictionary = _terrain_edge_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	if not cached.is_empty() \
			and int(cached.get("revision", -2)) == revision \
			and int(cached.get("epoch", -2)) == _generation_epoch:
		return cached
	var halo: PackedByteArray = _build_terrain_edge_solid_halo(chunk_coord, TERRAIN_EDGE_HALO_MASK_RADIUS_TILES)
	cached = {
		"revision": revision,
		"epoch": _generation_epoch,
		"halo": halo,
		"has_shoreline": _terrain_edge_halo_has_shoreline(halo),
	}
	_terrain_edge_solid_halo_cache[chunk_coord] = cached
	return cached


func _build_mountain_solid_halo(chunk_coord: Vector2i, halo_radius_tiles: int = 1) -> PackedByteArray:
	return _build_mountain_halo_fields(
		chunk_coord,
		halo_radius_tiles,
	).get("remaining_halo", PackedByteArray()) as PackedByteArray


func _build_mountain_halo_fields(chunk_coord: Vector2i, halo_radius_tiles: int = 1) -> Dictionary:
	halo_radius_tiles = maxi(1, halo_radius_tiles)
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius_tiles * 2
	var remaining_halo := PackedByteArray()
	remaining_halo.resize(halo_side * halo_side)
	var closed_halo := PackedByteArray()
	closed_halo.resize(halo_side * halo_side)
	var dug_halo := PackedByteArray()
	dug_halo.resize(halo_side * halo_side)
	var has_local_closed: bool = false
	var local_min: int = -halo_radius_tiles
	var local_max: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius_tiles
	for source_offset_y: int in range(-1, 2):
		var source_local_min_y: int = source_offset_y * WorldRuntimeConstants.CHUNK_SIZE
		var from_local_y: int = maxi(local_min, source_local_min_y)
		var to_local_y: int = mini(local_max, source_local_min_y + WorldRuntimeConstants.CHUNK_SIZE)
		if from_local_y >= to_local_y:
			continue
		for source_offset_x: int in range(-1, 2):
			var source_local_min_x: int = source_offset_x * WorldRuntimeConstants.CHUNK_SIZE
			var from_local_x: int = maxi(local_min, source_local_min_x)
			var to_local_x: int = mini(local_max, source_local_min_x + WorldRuntimeConstants.CHUNK_SIZE)
			if from_local_x >= to_local_x:
				continue
			var source_chunk: Vector2i = _canonicalize_chunk_coord(
				chunk_coord + Vector2i(source_offset_x, source_offset_y),
			)
			var packet: Dictionary = _chunk_packets.get(source_chunk, { }) as Dictionary
			if packet.is_empty():
				continue
			var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
			var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
			var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
			var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
			var source_base_x: int = source_offset_x * WorldRuntimeConstants.CHUNK_SIZE
			var source_base_y: int = source_offset_y * WorldRuntimeConstants.CHUNK_SIZE
			for local_y: int in range(from_local_y, to_local_y):
				var source_y: int = local_y - source_base_y
				var halo_row: int = (local_y + halo_radius_tiles) * halo_side
				var source_row: int = source_y * WorldRuntimeConstants.CHUNK_SIZE
				for local_x: int in range(from_local_x, to_local_x):
					var index: int = source_row + local_x - source_base_x
					if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
						continue
					if index >= mountain_ids.size() or int(mountain_ids[index]) <= 0:
						continue
					if index >= mountain_flags.size():
						continue
					var flags: int = int(mountain_flags[index])
					if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
						continue
					var halo_index: int = halo_row + local_x + halo_radius_tiles
					closed_halo[halo_index] = 1
					if source_offset_x == 0 and source_offset_y == 0:
						has_local_closed = true
					var terrain_id: int = int(terrain_ids[index])
					var walkable: bool = int(walkable_flags[index]) != 0
					if walkable and terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
						dug_halo[halo_index] = 1
						continue
					# Unknown/non-dug overrides fail closed. Only the canonical public
					# excavation state is allowed to punch a hole in the construction.
					remaining_halo[halo_index] = 1
	return {
		"remaining_halo": remaining_halo,
		"closed_halo": closed_halo,
		"dug_halo": dug_halo,
		"has_local_closed": has_local_closed,
	}


func _build_terrain_edge_solid_halo(chunk_coord: Vector2i, halo_radius_tiles: int = 1) -> PackedByteArray:
	halo_radius_tiles = maxi(1, halo_radius_tiles)
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius_tiles * 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(halo_side * halo_side)
	var local_min: int = -halo_radius_tiles
	var local_max: int = WorldRuntimeConstants.CHUNK_SIZE + halo_radius_tiles
	for source_offset_y: int in range(-1, 2):
		var source_local_min_y: int = source_offset_y * WorldRuntimeConstants.CHUNK_SIZE
		var from_local_y: int = maxi(local_min, source_local_min_y)
		var to_local_y: int = mini(local_max, source_local_min_y + WorldRuntimeConstants.CHUNK_SIZE)
		if from_local_y >= to_local_y:
			continue
		for source_offset_x: int in range(-1, 2):
			var source_local_min_x: int = source_offset_x * WorldRuntimeConstants.CHUNK_SIZE
			var from_local_x: int = maxi(local_min, source_local_min_x)
			var to_local_x: int = mini(local_max, source_local_min_x + WorldRuntimeConstants.CHUNK_SIZE)
			if from_local_x >= to_local_x:
				continue
			var source_chunk: Vector2i = _canonicalize_chunk_coord(
				chunk_coord + Vector2i(source_offset_x, source_offset_y),
			)
			var packet: Dictionary = _chunk_packets.get(source_chunk, { }) as Dictionary
			if packet.is_empty():
				continue
			var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
			var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
			var source_base_x: int = source_offset_x * WorldRuntimeConstants.CHUNK_SIZE
			var source_base_y: int = source_offset_y * WorldRuntimeConstants.CHUNK_SIZE
			for local_y: int in range(from_local_y, to_local_y):
				var source_y: int = local_y - source_base_y
				var halo_row: int = (local_y + halo_radius_tiles) * halo_side
				var source_row: int = source_y * WorldRuntimeConstants.CHUNK_SIZE
				for local_x: int in range(from_local_x, to_local_x):
					var index: int = source_row + local_x - source_base_x
					if index < 0 or index >= terrain_ids.size():
						continue
					var terrain_id: int = int(terrain_ids[index])
					var water_present: bool = index < lake_flags.size() \
							and (int(lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0
					if water_present \
							and (
								terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
										or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP
							):
						continue
					solid_halo[halo_row + local_x + halo_radius_tiles] = 1
	return solid_halo


func _terrain_edge_halo_has_solid(solid_halo: PackedByteArray) -> bool:
	for value: int in solid_halo:
		if value != 0:
			return true
	return false


func _terrain_edge_halo_has_shoreline(solid_halo: PackedByteArray) -> bool:
	# The shoreline underlay is built only where dry land actually meets
	# visible water inside the halo. Pure-land and pure-water chunks render
	# without it: the ground material owns the dry interior.
	var has_solid: bool = false
	var has_open: bool = false
	for value: int in solid_halo:
		if value != 0:
			has_solid = true
		else:
			has_open = true
		if has_solid and has_open:
			return true
	return false


func _mountain_halo_has_solid(chunk_coord: Vector2i, halo_radius_tiles: int = MOUNTAIN_HALO_MASK_RADIUS_TILES) -> bool:
	return _solid_halo_has_any(_build_mountain_solid_halo(chunk_coord, halo_radius_tiles))


func _loaded_mountain_contour_tile_is_solid(world_tile: Vector2i) -> bool:
	var canonical_tile: Vector2i = _canonicalize_tile_coord(world_tile)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty():
		return false
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size() or index >= walkable_flags.size():
		return false
	var terrain_id: int = int(terrain_ids[index])
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if int(walkable_flags[index]) != 0:
		return false
	if index >= mountain_ids.size() or int(mountain_ids[index]) <= 0:
		return false
	if index >= mountain_flags.size():
		return false
	var flags: int = int(mountain_flags[index])
	return (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0


func _loaded_terrain_edge_tile_is_solid(world_tile: Vector2i) -> bool:
	var canonical_tile: Vector2i = _canonicalize_tile_coord(world_tile)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty():
		return false
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
	if index < 0 or index >= terrain_ids.size():
		return false
	var terrain_id: int = int(terrain_ids[index])
	if _is_water_surface_sample(terrain_id, lake_flags, index):
		return false
	return true


func _packet_has_terrain_ground(packet: Dictionary) -> bool:
	if packet.is_empty():
		return false
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		if not _is_water_surface_sample(int(terrain_ids[index]), lake_flags, index):
			return true
	return false


func _is_water_surface_sample(terrain_id: int, lake_flags: PackedByteArray, index: int) -> bool:
	if index < 0 or index >= lake_flags.size():
		return false
	if (int(lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) == 0:
		return false
	return terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
			or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP


func _is_mountain_contour_solid_sample(sample: Dictionary) -> bool:
	if not bool(sample.get("ready", false)):
		return false
	var terrain_id: int = int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if bool(sample.get("walkable", true)):
		return false
	var mountain_id: int = int(sample.get("mountain_id", 0))
	var mountain_flags: int = int(sample.get("mountain_flags", 0))
	return mountain_id > 0 \
			and (mountain_flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0


func _get_contour_world_core() -> Object:
	if _contour_world_core != null:
		return _contour_world_core
	_contour_world_core = ClassDB.instantiate("WorldCore")
	assert(_contour_world_core != null, "WorldCore required for mountain contour debug - build GDExtension first")
	if _contour_world_core == null:
		return null
	if not _contour_world_core.has_method("build_mountain_contour_debug"):
		push_error("WorldCore missing build_mountain_contour_debug; mountain contour debug disabled.")
		_contour_world_core = null
		return null
	if not _contour_world_core.has_method("build_mountain_halo_mask"):
		push_error("WorldCore missing build_mountain_halo_mask; mountain runtime mask disabled.")
		_contour_world_core = null
		return null
	return _contour_world_core


func _dictionary_vector2i_keys(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key_variant: Variant in source.keys():
		result.append(key_variant as Vector2i)
	result.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x if a.x != b.x else a.y < b.y
	)
	return result


func _variant_to_vector2i_array(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if value is Array:
		for entry: Variant in value:
			result.append(entry as Vector2i)
	return result


func _track_roof_layer_metric(chunk_coord: Vector2i, packet: Dictionary) -> void:
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	if mountain_ids.is_empty() or mountain_flags.is_empty():
		return
	var present_mountains: Dictionary = { }
	for index: int in range(mini(mountain_ids.size(), mountain_flags.size())):
		var mountain_id: int = int(mountain_ids[index])
		var flags: int = int(mountain_flags[index])
		if mountain_id <= 0 or (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
			continue
		present_mountains[mountain_id] = true
	var mountain_count: int = present_mountains.size()
	if mountain_count > roof_layers_per_chunk_max:
		roof_layers_per_chunk_max = mountain_count
	if mountain_count > 24 and not _did_warn_roof_layer_explosion:
		_did_warn_roof_layer_explosion = true
		push_warning("roof layer count above strengthened satellite-outcrop guardrail: chunk %s has %d mountains" % [chunk_coord, mountain_count])


func _chunk_distance_sq(a: Vector2i, b: Vector2i) -> int:
	var dx: int = _wrapped_chunk_delta_abs(a.x, b.x)
	var dy: int = a.y - b.y
	return dx * dx + dy * dy


func _is_diggable_surface_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT


func _uses_mountain_surface_presentation(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT


func _packet_has_raster_mountain(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if not _uses_mountain_surface_presentation(terrain_id):
			continue
		if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
			continue
		if terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED and index < mountain_flags.size():
			var flags: int = int(mountain_flags[index])
			if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
				continue
		return true
	return false


func _packet_has_roof_bearing_mountain_metadata(packet: Dictionary) -> bool:
	var mountain_ids: PackedInt32Array = packet.get(
		"mountain_id_per_tile",
		PackedInt32Array(),
	) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get(
		"mountain_flags",
		PackedByteArray(),
	) as PackedByteArray
	var sample_count: int = mini(
		WorldRuntimeConstants.CHUNK_CELL_COUNT,
		mini(mountain_ids.size(), mountain_flags.size()),
	)
	for index: int in range(sample_count):
		if int(mountain_ids[index]) <= 0:
			continue
		var flags: int = int(mountain_flags[index])
		if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
			return true
	return false


func _wrap_local_player_position_if_needed() -> void:
	if not _uses_finite_world_bounds():
		return
	var player: Node2D = PlayerAuthority.get_local_player()
	if player == null:
		return
	var width_px: float = float(_world_bounds_settings.width_tiles * WorldRuntimeConstants.TILE_SIZE_PX)
	if width_px <= 0.0:
		return
	var wrapped_x: float = fposmod(player.global_position.x, width_px)
	if is_equal_approx(wrapped_x, player.global_position.x):
		return
	player.global_position = Vector2(wrapped_x, player.global_position.y)


func _record_streaming_step_timing(records: Dictionary, key: String, previous_usec: int) -> int:
	if not STREAMING_STEP_TIMING_DEBUG:
		return previous_usec
	var now_usec: int = Time.get_ticks_usec()
	records[key] = float(now_usec - previous_usec) / 1000.0
	return now_usec


func _report_streaming_step_timing(records: Dictionary, started_usec: int) -> void:
	if not STREAMING_STEP_TIMING_DEBUG:
		return
	var total_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	if total_ms < 6.0:
		return
	print("STREAMING_STEP_TIMING total=%.2fms %s" % [total_ms, JSON.stringify(records)])


func _uses_finite_world_bounds() -> bool:
	return WorldRuntimeConstants.uses_world_foundation(world_version)


func _canonicalize_tile_coord(tile_coord: Vector2i) -> Vector2i:
	if not _uses_finite_world_bounds():
		return tile_coord
	return _world_bounds_settings.canonicalize_tile(tile_coord)


func _canonicalize_chunk_coord(chunk_coord: Vector2i) -> Vector2i:
	if not _uses_finite_world_bounds():
		return chunk_coord
	return _world_bounds_settings.canonicalize_chunk(chunk_coord)


func _wrapped_chunk_delta_abs(a: int, b: int) -> int:
	if not _uses_finite_world_bounds():
		return absi(a - b)
	var width_chunks: int = _world_bounds_settings.get_width_chunks()
	var direct_delta: int = absi(posmod(a, width_chunks) - posmod(b, width_chunks))
	return mini(direct_delta, width_chunks - direct_delta)


func _apply_worldgen_settings(
		settings: MountainGenSettings,
		world_bounds: WorldBoundsSettings,
		foundation_settings: FoundationGenSettings,
		lake_settings: LakeGenSettings = null,
		plains_tree_settings: PlainsTreePlacementSettings = null,
		plains_small_rock_settings: PlainsSmallRockPlacementSettings = null,
) -> void:
	_worldgen_settings = _clone_worldgen_settings(settings)
	_world_bounds_settings = _clone_world_bounds(world_bounds)
	_mountain_cavity_cache.configure_horizontal_wrap(
		_world_bounds_settings.width_tiles if _uses_finite_world_bounds() else 0,
	)
	_foundation_settings = _clone_foundation_settings(foundation_settings, _world_bounds_settings)
	_lake_settings = _clone_lake_settings(lake_settings)
	_plains_tree_settings = _clone_plains_tree_settings(plains_tree_settings)
	_plains_small_rock_settings = _clone_plains_small_rock_settings(plains_small_rock_settings)
	_worldgen_settings_packed = _build_worldgen_settings_packed()


func _clone_worldgen_settings(settings: MountainGenSettings) -> MountainGenSettings:
	if settings == null:
		return MountainGenSettings.hard_coded_defaults()
	return MountainGenSettings.from_save_dict(settings.to_save_dict())


func _clone_world_bounds(settings: WorldBoundsSettings) -> WorldBoundsSettings:
	if settings == null:
		return WorldBoundsSettings.hard_coded_defaults()
	return WorldBoundsSettings.from_save_dict(settings.to_save_dict())


func _clone_foundation_settings(
		settings: FoundationGenSettings,
		world_bounds: WorldBoundsSettings,
) -> FoundationGenSettings:
	if settings == null:
		return FoundationGenSettings.for_bounds(world_bounds)
	return FoundationGenSettings.from_save_dict(settings.to_save_dict(), world_bounds)


func _clone_lake_settings(settings: LakeGenSettings) -> LakeGenSettings:
	if settings == null:
		return LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	return LakeGenSettings.from_save_dict(settings.to_save_dict())


func _clone_plains_tree_settings(settings: PlainsTreePlacementSettings) -> PlainsTreePlacementSettings:
	if settings == null:
		return PlainsTreePlacementSettings.from_save_dict(DefaultPlainsTreePlacementSettings.to_save_dict())
	return PlainsTreePlacementSettings.from_save_dict(settings.to_save_dict())


func _clone_plains_small_rock_settings(settings: PlainsSmallRockPlacementSettings) -> PlainsSmallRockPlacementSettings:
	if settings == null:
		return PlainsSmallRockPlacementSettings.from_save_dict(DefaultPlainsSmallRockPlacementSettings.to_save_dict())
	return PlainsSmallRockPlacementSettings.from_save_dict(settings.to_save_dict())


func _make_new_world_plains_tree_settings(settings: PlainsTreePlacementSettings = null) -> PlainsTreePlacementSettings:
	var cloned: PlainsTreePlacementSettings = _clone_plains_tree_settings(settings)
	cloned.apply_ground_sampling_params(DefaultPlainsGroundMaterialSet.sampling_params)
	return cloned


func _make_new_world_plains_small_rock_settings(settings: PlainsSmallRockPlacementSettings = null) -> PlainsSmallRockPlacementSettings:
	var cloned: PlainsSmallRockPlacementSettings = _clone_plains_small_rock_settings(settings)
	cloned.apply_ground_sampling_params(DefaultPlainsGroundMaterialSet.sampling_params)
	return cloned


func _build_worldgen_settings_packed() -> PackedFloat32Array:
	var packed: PackedFloat32Array = _worldgen_settings.flatten_to_packed()
	if WorldRuntimeConstants.uses_world_foundation(world_version):
		packed = _foundation_settings.write_to_settings_packed(packed, _world_bounds_settings)
		packed = _lake_settings.write_to_settings_packed(packed)
		packed = _plains_tree_settings.write_to_settings_packed(packed)
		return _plains_small_rock_settings.write_to_settings_packed(packed)
	return packed


func _compute_worldgen_signature(worldgen_settings: Dictionary) -> String:
	var hashing_context: HashingContext = HashingContext.new()
	var start_error: Error = hashing_context.start(HashingContext.HASH_SHA1)
	if start_error != OK:
		return ""
	hashing_context.update(JSON.stringify(worldgen_settings).to_utf8_buffer())
	return hashing_context.finish().hex_encode()


func _validate_current_world_save_shape(data: Dictionary) -> bool:
	if not data.has("world_seed"):
		_reject_world_save("world.json is missing required field world_seed")
		return false
	if not data.has("worldgen_settings"):
		_reject_world_save("world.json is missing required field worldgen_settings")
		return false
	var worldgen_settings: Variant = data.get("worldgen_settings", { })
	if worldgen_settings is not Dictionary:
		_reject_world_save("worldgen_settings must be a Dictionary")
		return false
	var settings_dict: Dictionary = worldgen_settings as Dictionary
	if not settings_dict.has("mountains") or settings_dict.get("mountains") is not Dictionary:
		_reject_world_save("worldgen_settings.mountains must be a Dictionary")
		return false
	if WorldRuntimeConstants.uses_world_foundation(WorldRuntimeConstants.WORLD_VERSION):
		if not settings_dict.has("world_bounds") or settings_dict.get("world_bounds") is not Dictionary:
			_reject_world_save("worldgen_settings.world_bounds must be a Dictionary")
			return false
		if not settings_dict.has("foundation") or settings_dict.get("foundation") is not Dictionary:
			_reject_world_save("worldgen_settings.foundation must be a Dictionary")
			return false
		if not settings_dict.has("lakes") or settings_dict.get("lakes") is not Dictionary:
			_reject_world_save("worldgen_settings.lakes must be a Dictionary")
			return false
		var lake_settings: Dictionary = settings_dict.get("lakes") as Dictionary
		if WorldRuntimeConstants.WORLD_VERSION >= 42 and not lake_settings.has("connectivity"):
			_reject_world_save("worldgen_settings.lakes.connectivity is required for world_version >= 42")
			return false
		if WorldRuntimeConstants.WORLD_VERSION >= 60 \
				and (not settings_dict.has("plains_trees") or settings_dict.get("plains_trees") is not Dictionary):
			_reject_world_save("worldgen_settings.plains_trees must be a Dictionary for world_version >= 60")
			return false
		if WorldRuntimeConstants.WORLD_VERSION >= 62 \
				and (not settings_dict.has("plains_small_rocks") or settings_dict.get("plains_small_rocks") is not Dictionary):
			_reject_world_save("worldgen_settings.plains_small_rocks must be a Dictionary for world_version >= 62")
			return false
	return true


func _reject_world_save(message: String) -> void:
	push_error(message)


func _load_worldgen_settings_from_save(data: Dictionary) -> MountainGenSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", { })
	if worldgen_settings is not Dictionary:
		return MountainGenSettings.hard_coded_defaults()
	var mountains_settings: Variant = (worldgen_settings as Dictionary).get("mountains", { })
	if mountains_settings is not Dictionary:
		return MountainGenSettings.hard_coded_defaults()
	return MountainGenSettings.from_save_dict(mountains_settings as Dictionary)


func _load_world_bounds_from_save(data: Dictionary) -> WorldBoundsSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", { })
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		return WorldBoundsSettings.hard_coded_defaults()
	if worldgen_settings is not Dictionary or not (worldgen_settings as Dictionary).has("world_bounds"):
		var message: String = "world_version >= 9 requires worldgen_settings.world_bounds in world.json"
		push_error(message)
		assert(false, message)
		return WorldBoundsSettings.hard_coded_defaults()
	var world_bounds: Variant = (worldgen_settings as Dictionary).get("world_bounds", { })
	if world_bounds is not Dictionary:
		var message: String = "worldgen_settings.world_bounds must be a Dictionary"
		push_error(message)
		assert(false, message)
		return WorldBoundsSettings.hard_coded_defaults()
	return WorldBoundsSettings.from_save_dict(world_bounds as Dictionary)


func _load_foundation_settings_from_save(
		data: Dictionary,
		world_bounds: WorldBoundsSettings,
) -> FoundationGenSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", { })
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		return FoundationGenSettings.for_bounds(world_bounds)
	if worldgen_settings is not Dictionary:
		return FoundationGenSettings.for_bounds(world_bounds)
	var foundation_settings: Variant = (worldgen_settings as Dictionary).get("foundation", { })
	if foundation_settings is not Dictionary:
		return FoundationGenSettings.for_bounds(world_bounds)
	return FoundationGenSettings.from_save_dict(foundation_settings as Dictionary, world_bounds)


func _load_lake_settings_from_save(data: Dictionary) -> LakeGenSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", { })
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		return LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	if worldgen_settings is not Dictionary:
		return LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var lake_settings: Variant = (worldgen_settings as Dictionary).get("lakes", { })
	if lake_settings is not Dictionary:
		return LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	return LakeGenSettings.from_save_dict(lake_settings as Dictionary)


func _load_plains_tree_settings_from_save(data: Dictionary) -> PlainsTreePlacementSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", { })
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		return _make_new_world_plains_tree_settings()
	if worldgen_settings is not Dictionary:
		return _make_new_world_plains_tree_settings()
	var plains_tree_settings: Variant = (worldgen_settings as Dictionary).get("plains_trees", { })
	if plains_tree_settings is not Dictionary:
		return _make_new_world_plains_tree_settings()
	return PlainsTreePlacementSettings.from_save_dict(plains_tree_settings as Dictionary)


func _load_plains_small_rock_settings_from_save(data: Dictionary) -> PlainsSmallRockPlacementSettings:
	var worldgen_settings: Variant = data.get("worldgen_settings", { })
	if not WorldRuntimeConstants.uses_world_foundation(world_version):
		return _make_new_world_plains_small_rock_settings()
	if worldgen_settings is not Dictionary:
		return _make_new_world_plains_small_rock_settings()
	var plains_small_rock_settings: Variant = (worldgen_settings as Dictionary).get("plains_small_rocks", { })
	if plains_small_rock_settings is not Dictionary:
		return _make_new_world_plains_small_rock_settings()
	return PlainsSmallRockPlacementSettings.from_save_dict(plains_small_rock_settings as Dictionary)
