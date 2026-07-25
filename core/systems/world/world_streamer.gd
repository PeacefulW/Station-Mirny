class_name WorldStreamer
extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")
const HarvestQuery = preload("res://core/systems/world/harvest_query.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const PlainsTreePlacementSettings = preload("res://core/resources/plains_tree_placement_settings.gd")
const PlainsSmallRockPlacementSettings = preload("res://core/resources/plains_small_rock_placement_settings.gd")
const MountainCavityCache = preload("res://core/systems/world/mountain_cavity_cache.gd")
const MountainCavitySkylightField = preload("res://core/systems/world/mountain_cavity_skylight_field.gd")
const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const MountainPlateau2DRasterLayer = preload("res://core/systems/world/mountain_plateau_2d_raster_layer.gd")
const MiningFeedbackLayer = preload("res://core/systems/world/mining_feedback_layer.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldStreamingReadinessTracker = preload(
	"res://core/systems/world/world_streaming_readiness_tracker.gd"
)
const WorldInitialLoadingGate = preload(
	"res://core/systems/world/world_initial_loading_gate.gd"
)
const WorldDiffStore = preload("res://core/systems/world/world_diff_store.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const WorldVisualWindProfile = preload("res://core/systems/world/world_visual_wind_profile.gd")
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const WorldLayeredObjectAssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")
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
## All world compute kinds share one priority pool. Reserving logical cores for
## the main/render lanes prevents packet+mask+grass+object workers from
## oversubscribing low-core machines; the cap also avoids scaling background
## generation until it competes with frame delivery on large CPUs.
const WORLD_COMPUTE_RESERVED_LOGICAL_CORES: int = 2
const WORLD_COMPUTE_MAX_WORKERS: int = 6
const WORLD_COMPUTE_PACKET_BATCH_MAX: int = 12
# Six workers complete in clusters. Eight integrations keep a new source ring
# moving at vehicle speed (at most two frames for the max-radius edge) without
# turning one clustered completion into a multi-millisecond main-thread burst.
const MAX_PACKET_RESULTS_PER_TICK: int = 8
# When a queued chunk is waiting to start publication, leave deterministic main-
# thread headroom for that start. Active four-slice terrain uploads still drain
# the full worker burst, so result throughput remains high over a publish cycle.
const MAX_PACKET_RESULTS_WHILE_PUBLISH_WAITING: int = 2
## Initial readiness is sampled incrementally. Eight O(1) chunk probes keep the
## loading gate bounded while revisiting the current 121-chunk target quickly.
const INITIAL_LOADING_READINESS_CHECKS_PER_TICK: int = 8
const MAX_GRASS_SCATTER_RESULTS_PER_TICK: int = 12
const MAX_GRASS_SCATTER_RETRIES_PER_TICK: int = 2
const GRASS_SCATTER_MAX_BACKGROUND_INFLIGHT: int = WORLD_COMPUTE_MAX_WORKERS * 2
const GRASS_SCATTER_RETRY_BASE_DELAY_MSEC: int = 125
const GRASS_SCATTER_RETRY_MAX_DELAY_MSEC: int = 2000
const MAX_OBJECT_PRESENTATION_RESULTS_PER_TICK: int = 24
const MAX_OBJECT_PRESENTATION_RETRIES_PER_TICK: int = 2
const OBJECT_PRESENTATION_MAX_RETRY_ATTEMPTS: int = 2
const OBJECT_PRESENTATION_RETRY_DELAY_MSEC: int = 125
const MAX_MOUNTAIN_PAGE_RESULTS_PER_TICK: int = 1
const MAX_MOUNTAIN_NATIVE_MASK_RESULTS_PER_TICK: int = 8
const MAX_MOUNTAIN_NATIVE_MASK_RETRIES_PER_TICK: int = 2
# Publish pipeline pacing: scan a bounded queue prefix for a publishable chunk
# (a mask-stalled head must not block ready chunks behind it) and warm native
# mask requests for a bounded number of queued chunks per tick.
const PUBLISH_QUEUE_SCAN_LIMIT: int = 8
const PUBLISH_MASK_PREFETCH_PER_TICK: int = 1
# Active terrain batches may opportunistically warm the next halo only when the
# preceding worker-result integration was cheap. A cold idle publisher ignores
# this threshold after at most one deferred tick, guaranteeing forward progress
# even on a slow CPU.
const PUBLISH_PREFETCH_PACKET_HEADROOM_USEC: int = 1000
const COMBINED_HALO_FAILURE_RETRY_BASE_DELAY_MSEC: int = 125
const COMBINED_HALO_FAILURE_RETRY_MAX_DELAY_MSEC: int = 2000
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
const MOUNTAIN_NATIVE_MASK_MAX_RETRY_ATTEMPTS: int = 2
const MOUNTAIN_NATIVE_MASK_RETRY_DELAY_MSEC: int = 125
const MOUNTAIN_NATIVE_MASK_EXHAUSTED_RETRY_DELAY_MSEC: int = 2000
const MOUNTAIN_ROOF_REVEAL_ENTER_DURATION_SEC: float = 0.150
const MOUNTAIN_ROOF_REVEAL_EXIT_DELAY_SEC: float = 0.060
const MOUNTAIN_ROOF_REVEAL_EXIT_DURATION_SEC: float = 0.180
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
const OBJECT_PRESENTATION_VISUAL_UPLOAD_BUDGET_MS: float = 0.75
# Grass payloads are already computed by WorldChunkPacketBackend workers, but
# RenderingServer/MultiMesh mutation must stay on the main thread. Give that
# upload its own lane after authoritative streaming so a 64-stripe graph can be
# advanced in small predicted phases without hiding a multi-millisecond loop in
# chunk publication.
# Two predicted stripe phases normally fit here. Authoritative packet/object
# work is registered first and the global 6 ms dispatcher cap still wins, so a
# cold zoom drains faster without stealing a reveal or creating a frame spike.
const GRASS_SCATTER_VISUAL_UPLOAD_BUDGET_MS: float = 1.5
const MASK_MINING_SEARCH_RADIUS_TILES: int = 3
const MAX_VIEWPORT_STREAM_RADIUS_CHUNKS: int = 4
const WARM_PACKET_CACHE_SIDE_CHUNKS: int = MAX_VIEWPORT_STREAM_RADIUS_CHUNKS * 2 + 3
const WARM_PACKET_CACHE_MAX_CHUNKS: int = WARM_PACKET_CACHE_SIDE_CHUNKS * WARM_PACKET_CACHE_SIDE_CHUNKS
# At most the current source window plus one outgoing window may retain visual
# tokens during reconciliation/teleport. This hard cap makes the priority-scan
# snapshot allocation itself bounded; hidden overflow keeps its lightweight
# prestage token and retries when a slot opens, while live urgency may evict a
# lower-class token.
const OBJECT_PRESENTATION_VISUAL_QUEUE_MAX_TOKENS: int = WARM_PACKET_CACHE_MAX_CHUNKS * 2
const WARM_OBJECT_PRESENTATION_CACHE_MAX_BYTES: int = 32 * 1024 * 1024
# Native grass output is immutable packed CPU data. Retaining it across a short
# zoom/movement round trip avoids recompute while this byte cap prevents the
# infinite world from turning the cache into unbounded residency.
const WARM_GRASS_SCATTER_CACHE_MAX_BYTES: int = 64 * 1024 * 1024
# ChunkView owns expensive TileMap/grass RenderingServer objects. Radius 4 has
# 56 chunks outside the minimum radius-2 view, so 64 entries cover a complete
# zoom-out -> zoom-in -> zoom-out round trip while remaining strictly bounded.
const HOT_CHUNK_VIEW_CACHE_MAX_ENTRIES: int = 64
const HOT_CHUNK_VIEW_PREWARM_COUNT: int = 1
# GPU-resident object presentation is a separate cache from the CPU packed
# result cache. Count, CanvasItem/collider pressure, and raw buffer bytes are
# all bounded independently so repeated zoom never implies unbounded residency.
# Live incomplete reveal transactions are a separately bounded visible-ring
# working set and are never recursively evicted/restaged to satisfy these caps.
const HOT_OBJECT_PRESENTATION_CACHE_MAX_CHUNKS: int = WARM_PACKET_CACHE_MAX_CHUNKS
const HOT_OBJECT_PRESENTATION_CACHE_MAX_BYTES: int = 32 * 1024 * 1024
const HOT_OBJECT_PRESENTATION_CACHE_MAX_CANVAS_ITEMS: int = \
		WARM_PACKET_CACHE_MAX_CHUNKS * WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK
const HOT_OBJECT_PRESENTATION_CACHE_MAX_COLLIDERS: int = \
		WARM_PACKET_CACHE_MAX_CHUNKS * WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK
# A tiny boot/recycle pool moves script/CanvasItem/MultiMesh first-use out of
# the moving-player deadline. It is deliberately independent from the hot
# residency budget and remains strictly bounded.
const OBJECT_PRESENTATION_LAYER_POOL_TARGET_SIZE: int = 2
const OBJECT_PRESENTATION_LAYER_POOL_MAX_SIZE: int = 4
const OBJECT_PRESENTATION_POOL_INITIAL_SLOTS_PER_FAMILY: int = 4
const OBJECT_PRESENTATION_SLICE_SOFT_BUDGET_USEC: int = 350
const OBJECT_PRESENTATION_MAX_APPLY_SUBSLICES_PER_CALLBACK: int = 8
const OBJECT_PRESENTATION_PRIORITY_SCAN_SOFT_BUDGET_USEC: int = 150
const OBJECT_PRESENTATION_PRIORITY_SCAN_MAX_ITEMS_PER_PHASE: int = 16
# The dispatcher may immediately call a job again while it returns true. Keep a
# second local guard because object phases have different costs: the previous
# dispatcher sample cannot predict a transition from a cheap control phase to a
# GPU allocation. This cap also prevents a zero-microsecond timer resolution
# from producing an unbounded callback loop.
const OBJECT_PRESENTATION_MAX_DISPATCH_CALLBACKS_PER_FRAME: int = 8
const OBJECT_PRESENTATION_VISUAL_UPLOAD_BUDGET_USEC: int = \
		int(OBJECT_PRESENTATION_VISUAL_UPLOAD_BUDGET_MS * 1000.0)
# Slot graphs are allocation-only callbacks. They use a tighter local ceiling
# than the registered lane and never spend its final 0.10 ms safety reserve.
const OBJECT_PRESENTATION_ALLOCATION_SOFT_BUDGET_USEC: int = 650
const OBJECT_PRESENTATION_MAX_ALLOCATION_CALLBACKS_PER_FRAME: int = 2
const OBJECT_PRESENTATION_ALLOCATION_LOOKAHEAD_NUMERATOR: int = 5
const OBJECT_PRESENTATION_ALLOCATION_LOOKAHEAD_DENOMINATOR: int = 4
const OBJECT_PRESENTATION_ALLOCATION_LOOKAHEAD_FIXED_MARGIN_USEC: int = 25
const OBJECT_PRESENTATION_RETIRE_BUDGET_MS: float = 0.35
const OBJECT_PRESENTATION_RETIRE_VISUAL_SLOTS_PER_PHASE: int = 1
const OBJECT_PRESENTATION_RETIRE_COLLIDERS_PER_PHASE: int = 4
const MOUNTAIN_MASK_PRESET_PATH: String = "res://scenes/dev/mountain_2d_raster_preset.json"
const STREAMING_STEP_TIMING_DEBUG: bool = false

var world_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var world_version: int = WorldRuntimeConstants.WORLD_VERSION

var _diff_store: WorldDiffStore = WorldDiffStore.new()
var _readiness_tracker: WorldStreamingReadinessTracker = WorldStreamingReadinessTracker.new()
var _initial_loading_gate: WorldInitialLoadingGate = WorldInitialLoadingGate.new()
var _initial_loading_readiness_cursor: int = 0
var _chunk_packets: Dictionary = { }
## Immutable native packets are kept separately from diff-applied runtime
## packets so a warm-cache hit can always reapply the current WorldDiffStore.
var _base_chunk_packets: Dictionary = { }
var _warm_base_chunk_packet_cache: Dictionary = { }
var _warm_base_chunk_packet_cache_stamps: Dictionary = { }
var _warm_base_chunk_packet_cache_next_stamp: int = 0
var _warm_packet_cache_hit_count_total: int = 0
var _chunk_views: Dictionary = { }
var _hot_chunk_view_cache: Dictionary = { }
var _hot_chunk_view_cache_next_stamp: int = 0
var _hot_chunk_view_reuse_metadata_by_chunk: Dictionary = { }
var _hot_chunk_view_cache_hit_count_total: int = 0
var _hot_chunk_view_pool_reuse_count_total: int = 0
var _hot_chunk_view_grass_preserve_hit_count_total: int = 0
var _hot_chunk_view_terrain_preserve_hit_count_total: int = 0
var _requested_chunks: Dictionary = { }
var _pending_publish_queue: Array[Vector2i] = []
var _active_publish_chunk: Vector2i = INVALID_CHUNK_COORD
var _player_chunk_coord: Vector2i = INVALID_CHUNK_COORD
## Camera-independent residency radius. See _resolve_stream_radius_chunks().
var _current_stream_radius_chunks: int = MAX_VIEWPORT_STREAM_RADIUS_CHUNKS
var _desired_source_chunk_coords: Array[Vector2i] = []
var _desired_visible_chunk_coords: Array[Vector2i] = []
var _desired_mountain_mask_chunk_coords: Array[Vector2i] = []
var _terrain_packet_support_chunk_coords: Array[Vector2i] = []
var _terrain_packet_support_chunk_set: Dictionary = { }
var _desired_cache_center_chunk: Vector2i = INVALID_CHUNK_COORD
var _desired_cache_radius_chunks: int = -1
var _desired_cache_source_radius_chunks: int = -1
var _sorted_chunk_offsets_by_radius: Dictionary = { }
var _streaming_worker_demand_dirty: bool = true
var _stream_job_id: StringName = &""
var _grass_scatter_visual_job_id: StringName = &""
var _mountain_native_mask_visual_job_id: StringName = &""
var _object_presentation_visual_job_id: StringName = &""
var _object_presentation_retire_job_id: StringName = &""
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
var _world_compute_backend: WorldChunkPacketBackend = WorldChunkPacketBackend.new()
# Compatibility role names share the same multiplexed backend. Result queues
# remain typed inside WorldChunkPacketBackend; start/stop/clear are owned only
# by _world_compute_backend below.
var _packet_backend: WorldChunkPacketBackend = _world_compute_backend
var _mountain_mask_backend: WorldChunkPacketBackend = _world_compute_backend
var _grass_scatter_backend: WorldChunkPacketBackend = _world_compute_backend
var _object_presentation_backend: WorldChunkPacketBackend = _world_compute_backend
var _world_compute_worker_count: int = 0
var _layered_object_asset_catalog: WorldLayeredObjectAssetCatalog = WorldLayeredObjectAssetCatalog.new()
var _awaiting_new_game_spawn_result: bool = false
var _new_game_spawn_failed: bool = false
var roof_layers_per_chunk_max: int = 0

var _mountain_cavity_cache: MountainCavityCache = MountainCavityCache.new()
var _active_cover_mountain_id: int = 0
var _active_cover_component_id: int = 0
enum MountainRoofRevealTransitionState {
	CLOSED,
	OPENING_WAIT_SELECTOR,
	OPENING,
	OPEN,
	CLOSING_DELAY,
	CLOSING,
}
# Gameplay/torch target ownership (_active_cover_*) changes immediately.
# The displayed selector is retained independently until the presentation
# state machine has finished fading the old roof back in.
var _displayed_cover_mountain_id: int = 0
var _displayed_cover_component_id: int = 0
var _displayed_cover_visual_chunks: Dictionary = { }
var _mountain_roof_reveal_selector_wait_chunks: Dictionary = { }
var _mountain_roof_reveal_selector_generation: int = 0
var _mountain_roof_reveal_blend: float = 0.0
var _mountain_roof_reveal_transition_state: MountainRoofRevealTransitionState = \
		MountainRoofRevealTransitionState.CLOSED
var _mountain_roof_reveal_transition_elapsed_sec: float = 0.0
var _mountain_roof_reveal_transition_start_blend: float = 0.0
var _mountain_roof_reveal_transition_duration_sec: float = 0.0
var _mountain_cavity_skylight_field: MountainCavitySkylightField = null
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
# Failed current-revision worker requests retry on a short bounded cooldown.
# Repeated failures enter a longer parked cooldown but never poison that chunk
# permanently; publish fairness rotates parked entries behind healthy work.
var _mountain_native_mask_retry_by_chunk: Dictionary = { }
var _terrain_edge_mask_revision_by_chunk: Dictionary = { }
var _terrain_edge_masks_by_chunk: Dictionary = { }
var _terrain_edge_mask_inflight_chunks: Dictionary = { }
# Solid-halo build caches: a 32x32-tile halo costs ~1k packet lookups in
# GDScript, and the publish gate used to rebuild it every tick while waiting
# for a native mask. Keyed by chunk; validated by (epoch, revision).
var _mountain_solid_halo_cache: Dictionary = { }
var _terrain_edge_solid_halo_cache: Dictionary = { }
var _combined_halo_build_retry_by_chunk: Dictionary = { }
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
# A published chunk whose GPU construction-roof/selector state is still dirty
# stays hidden. This prevents one CLOSED frame when loading/restoring the
# player inside a cavity while visual work is budgeted.
var _pending_chunk_visibility_after_mountain_visual: Dictionary = { }
var _pending_terrain_edge_mask_visual_upload_chunks: Array[Vector2i] = []
var _pending_terrain_edge_mask_visual_upload_set: Dictionary = { }
var _pending_object_packet_visual_upload_chunks: Array[Vector2i] = []
var _pending_object_packet_visual_upload_set: Dictionary = { }
var _pending_object_packet_visual_upload_index_by_chunk: Dictionary = { }
var _object_packet_visual_queue_repair_needed: bool = false
var _object_packet_visual_queue_repair_cursor: int = 0
var _object_packet_visual_enqueued_turn_by_chunk: Dictionary = { }
var _object_packet_visual_dispatch_turn: int = 0
var _focused_object_packet_visual_upload_chunk: Vector2i = INVALID_CHUNK_COORD
var _object_packet_visual_priority_dirty: bool = true
var _object_packet_visual_urgent_priority_dirty: bool = false
# A dirty O(queue) priority refresh is its own dispatcher phase. This token lets
# exactly one already-selected phase run next even if streaming appended more
# equal/lower-urgency source tokens meanwhile, preventing refresh starvation.
var _object_packet_visual_selection_phase_prepared: bool = false
var _object_packet_visual_priority_scan_active: bool = false
var _object_packet_visual_priority_scan_candidates: Array[Vector2i] = []
var _object_packet_visual_priority_scan_cursor: int = 0
var _object_packet_visual_priority_scan_best: Vector2i = INVALID_CHUNK_COORD
var _object_packet_visual_priority_scan_best_class: int = 2147483647
var _object_packet_visual_priority_scan_best_priority: int = 0
var _object_packet_visual_priority_scan_best_turn: int = 0
# Safe phases may keep the dispatcher lane active in the current process frame.
# The lane timer is independent from the dispatcher's last-step predictor so a
# heterogeneous next phase can reserve its own conservative lookahead.
var _object_presentation_visual_lane_frame: int = -1
var _object_presentation_visual_lane_started_usec: int = 0
var _object_presentation_visual_lane_callback_count: int = 0
var _object_presentation_allocation_callback_count: int = 0
# Per-family maxima are intentionally monotonic for the session. A rare slow
# RenderingServer allocation must make future lookahead more conservative, not
# be averaged away by many cheap decor slots.
var _object_presentation_allocation_high_water_usec_by_family: Dictionary = { }
# COMPLETE is produced by an upload callback; adopt plus the atomic visual /
# collision reveal run together in a later FINALIZE callback. The guard also
# blocks the lower-priority mountain visual job from revealing a chunk later in
# the same frame in which object presentation performed its last upload.
var _object_presentation_reveal_not_before_frame_by_chunk: Dictionary = { }
var _pending_hot_object_prestage_chunks: Array[Vector2i] = []
var _pending_hot_object_prestage_set: Dictionary = { }
var _object_presentation_next_revision: int = 0
var _object_presentation_revision_by_chunk: Dictionary = { }
var _object_presentation_inflight_chunks: Dictionary = { }
var _object_presentation_results_by_chunk: Dictionary = { }
var _warm_object_presentation_cache: Dictionary = { }
var _warm_object_presentation_cache_bytes_by_chunk: Dictionary = { }
var _warm_object_presentation_cache_bytes: int = 0
var _object_presentation_cache_hit_count_total: int = 0
var _hot_object_presentation_layers: Dictionary = { }
var _hot_object_presentation_cache_next_stamp: int = 0
var _hot_object_presentation_cache_bytes: int = 0
var _hot_object_presentation_cache_canvas_items: int = 0
var _hot_object_presentation_cache_colliders: int = 0
var _hot_object_presentation_cache_hit_count_total: int = 0
var _hot_object_presentation_cache_eviction_count_total: int = 0
var _hot_object_presentation_root: Node2D = null
var _object_presentation_layer_pool: Array[WorldObjectPacketLayer] = []
var _object_presentation_retire_queue: Array[Dictionary] = []
var _object_presentation_retire_layer_ids: Dictionary = { }
var _object_presentation_retire_gpu_bytes: int = 0
var _object_presentation_retire_canvas_items: int = 0
var _object_presentation_retire_colliders: int = 0
var _object_presentation_retire_phase_count_total: int = 0
var _object_presentation_retire_phase_usec_max_total: int = 0
var _object_presentation_pool_gpu_bytes: int = 0
var _object_presentation_pool_canvas_items: int = 0
var _object_presentation_pool_colliders: int = 0
var _object_presentation_pool_weight_by_layer_id: Dictionary = { }
var _object_presentation_worker_elapsed_ms_last: float = 0.0
var _object_presentation_worker_elapsed_ms_max_total: float = 0.0
var _object_presentation_request_to_complete_ms_last: float = 0.0
var _object_presentation_request_to_complete_ms_max_total: float = 0.0
var _object_presentation_retry_by_chunk: Dictionary = { }
var _object_presentation_terminal_fallback_by_chunk: Dictionary = { }
var _object_presentation_failure_count_total: int = 0
var _object_presentation_terminal_failure_count: int = 0
var _pending_grass_scatter_visual_upload_chunks: Array[Vector2i] = []
var _pending_grass_scatter_visual_upload_set: Dictionary = { }
var _pending_grass_scatter_visual_upload_index_by_chunk: Dictionary = { }
var _focused_grass_scatter_visual_upload_chunk: Vector2i = INVALID_CHUNK_COORD
var _grass_scatter_revision_by_chunk: Dictionary = { }
var _grass_scatter_next_revision: int = 0
var _grass_scatter_inflight_chunks: Dictionary = { }
var _grass_scatter_results_by_chunk: Dictionary = { }
var _grass_scatter_retry_by_chunk: Dictionary = { }
var _warm_grass_scatter_cache: Dictionary = { }
var _warm_grass_scatter_cache_bytes_by_chunk: Dictionary = { }
var _warm_grass_scatter_cache_bytes: int = 0
var _grass_scatter_cache_hit_count_total: int = 0
var _grass_scatter_worker_elapsed_ms_last: float = 0.0
var _grass_scatter_worker_elapsed_ms_max_total: float = 0.0
var _grass_scatter_request_to_complete_ms_last: float = 0.0
var _grass_scatter_request_to_complete_ms_max_total: float = 0.0
var _chunk_reveal_with_pending_grass_count_total: int = 0
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
var _grass_directional_shadow_consolidation_enabled: bool = false
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
var _mountain_torch_shadow_field_mask_cache: Dictionary = { }
var _mountain_torch_shadow_field_debug_state: Dictionary = { }
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
	# _process runs only while a roof reveal transition is animating.
	set_process(false)
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
	# Resolve textures/materials before the first streamed publish. Lazy source
	# creation here used to charge shader/material setup to publish.begin.
	_ensure_grass_scatter_sources()
	ChunkView.prewarm_tile_pattern_records()
	_prewarm_chunk_view_cache()
	assert(
		_layered_object_asset_catalog.is_ready(),
		"Layered object channel atlases/catalog must be prepared before streaming starts",
	)
	_world_compute_worker_count = _resolve_world_compute_worker_count()
	_world_compute_backend.set_max_batch_size(
		mini(WORLD_COMPUTE_PACKET_BATCH_MAX, maxi(2, _world_compute_worker_count * 2)),
	)
	_world_compute_backend.start(_world_compute_worker_count)
	# Required object visuals gate chunk reveal, so their small bounded apply job
	# must run before the broader streaming job. Otherwise one legacy streaming
	# step that overruns the global budget can starve this queue for many frames
	# and let a moving player catch hidden/unready chunks.
	_object_presentation_visual_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		OBJECT_PRESENTATION_VISUAL_UPLOAD_BUDGET_MS,
		_object_presentation_visual_apply_tick,
		&"world.object_presentation_visual_upload",
		RuntimeWorkTypes.CadenceKind.NEAR_PLAYER,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		true,
		"World object presentation bounded upload",
	)
	_object_presentation_retire_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		OBJECT_PRESENTATION_RETIRE_BUDGET_MS,
		_object_presentation_retire_tick,
		&"world.object_presentation_retire",
		RuntimeWorkTypes.CadenceKind.BACKGROUND,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		true,
		"World object presentation bounded retire",
	)
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
	# Registration order is deliberate: packet/publish progress owns the first
	# streaming slice; cosmetic grass consumes only the remaining frame budget.
	_grass_scatter_visual_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_STREAMING,
		GRASS_SCATTER_VISUAL_UPLOAD_BUDGET_MS,
		_grass_scatter_visual_apply_tick,
		&"world.grass_scatter_visual_upload",
		RuntimeWorkTypes.CadenceKind.PRESENTATION,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"World grass scatter bounded GPU upload",
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


func _process(delta: float) -> void:
	_advance_mountain_roof_reveal_transition(delta)


func _exit_tree() -> void:
	if EventBus and EventBus.time_tick.is_connected(_on_time_tick):
		EventBus.time_tick.disconnect(_on_time_tick)
	if _stream_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_stream_job_id)
	if _grass_scatter_visual_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_grass_scatter_visual_job_id)
	if _mountain_native_mask_visual_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_mountain_native_mask_visual_job_id)
	if _object_presentation_visual_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_object_presentation_visual_job_id)
	if _object_presentation_retire_job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_object_presentation_retire_job_id)
	_clear_hot_object_presentation_cache()
	_world_compute_backend.stop()


func _resolve_world_compute_worker_count() -> int:
	return clampi(
		OS.get_processor_count() - WORLD_COMPUTE_RESERVED_LOGICAL_CORES,
		1,
		WORLD_COMPUTE_MAX_WORKERS,
	)


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


func get_initial_loading_state() -> Dictionary:
	return _initial_loading_gate.get_state()


func acknowledge_initial_world_presented() -> bool:
	if not _initial_loading_gate.acknowledge_presented():
		return false
	var next_radius: int = _resolve_stream_radius_chunks()
	if next_radius != _current_stream_radius_chunks:
		_current_stream_radius_chunks = next_radius
		_object_packet_visual_priority_dirty = true
		_rebuild_desired_chunk_cache()
	_streaming_worker_demand_dirty = true
	return true


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


## HUD-safe O(1) snapshot. Keep this separate from the forensic mountain state
## below: that diagnostic intentionally walks every ChunkView and takes backend
## locks, which would make the profiler itself a source of frame-time noise.
func get_perf_hud_snapshot() -> Dictionary:
	var mountain_uploads: int = _pending_mountain_native_mask_visual_upload_chunks.size()
	var terrain_uploads: int = _pending_terrain_edge_mask_visual_upload_chunks.size()
	var mask_retries: int = (
		_mountain_native_mask_retry_by_chunk.size()
		+ _combined_halo_build_retry_by_chunk.size()
	)
	return {
		"resident_views": _chunk_views.size(),
		"desired_visible_chunks": _desired_visible_chunk_coords.size(),
		"desired_source_chunks": _desired_source_chunk_coords.size(),
		"packet_count": _chunk_packets.size(),
		"requested_packets": _requested_chunks.size(),
		"publish_queue": _pending_publish_queue.size(),
		"publish_active": _active_publish_chunk != INVALID_CHUNK_COORD,
		"visibility_wait": _pending_chunk_visibility_after_mountain_visual.size(),
		"object_inflight": _object_presentation_inflight_chunks.size(),
		"object_ready_cpu": _object_presentation_results_by_chunk.size(),
		"object_upload_queue": _pending_object_packet_visual_upload_chunks.size(),
		"object_prestage_queue": _pending_hot_object_prestage_chunks.size(),
		"object_retire_queue": _object_presentation_retire_queue.size(),
		"object_worker_ms": _object_presentation_worker_elapsed_ms_last,
		"object_latency_ms": _object_presentation_request_to_complete_ms_last,
		"object_warm_cache": _warm_object_presentation_cache.size(),
		"object_warm_cache_bytes": _warm_object_presentation_cache_bytes,
		"object_hot_cache": _hot_object_presentation_layers.size(),
		"object_hot_cache_bytes": _hot_object_presentation_cache_bytes,
		"object_pool": _object_presentation_layer_pool.size(),
		"grass_inflight": _grass_scatter_inflight_chunks.size(),
		"grass_ready_cpu": _grass_scatter_results_by_chunk.size(),
		"grass_upload_queue": _pending_grass_scatter_visual_upload_chunks.size(),
		"grass_worker_ms": _grass_scatter_worker_elapsed_ms_last,
		"grass_latency_ms": _grass_scatter_request_to_complete_ms_last,
		"grass_warm_cache": _warm_grass_scatter_cache.size(),
		"grass_warm_cache_bytes": _warm_grass_scatter_cache_bytes,
		"mountain_mask_inflight": _mountain_native_mask_inflight_chunks.size(),
		"terrain_mask_inflight": _terrain_edge_mask_inflight_chunks.size(),
		"mountain_mask_upload_queue": mountain_uploads,
		"terrain_mask_upload_queue": terrain_uploads,
		"mask_retry_queue": mask_retries,
		"warm_packet_cache": _warm_base_chunk_packet_cache.size(),
		"warm_packet_cache_capacity": WARM_PACKET_CACHE_MAX_CHUNKS,
		"hot_view_cache": _hot_chunk_view_cache.size(),
		"hot_view_cache_capacity": HOT_CHUNK_VIEW_CACHE_MAX_ENTRIES,
		"worker_count": _world_compute_worker_count,
		"stream_radius": _current_stream_radius_chunks,
		"player_chunk": _player_chunk_coord,
	}


func get_streaming_readiness_debug_snapshot() -> Dictionary:
	var sampled_at_msec: int = Time.get_ticks_msec()
	var coords: Array[Vector2i] = []
	var seen: Dictionary = { }
	for chunk_coord: Vector2i in _desired_source_chunk_coords:
		_readiness_append_coord(coords, seen, chunk_coord)
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var distance_a: int = _chunk_request_priority(a)
			var distance_b: int = _chunk_request_priority(b)
			return distance_a < distance_b \
					if distance_a != distance_b \
					else (a.x < b.x if a.x != b.x else a.y < b.y)
	)
	var entries: Array[Dictionary] = []
	var stage_counts: Dictionary = { }
	var reason_counts: Dictionary = { }
	var missing_chunk_count: int = 0
	for chunk_coord: Vector2i in coords:
		var entry: Dictionary = _build_streaming_readiness_entry(
			chunk_coord,
			sampled_at_msec,
		)
		entries.append(entry)
		var stage: String = String(entry.get("lifecycle_stage", ""))
		stage_counts[stage] = int(stage_counts.get(stage, 0)) + 1
		if not bool(entry.get("ready", false)):
			missing_chunk_count += 1
			var reason: String = String(entry.get("blocking_reason", ""))
			reason_counts[reason] = int(reason_counts.get(reason, 0)) + 1
	return {
		"schema_version": 1,
		"sampled_at_msec": sampled_at_msec,
		"generation_epoch": _generation_epoch,
		"player_chunk": _player_chunk_coord,
		"desired_visible_count": _desired_visible_chunk_coords.size(),
		"desired_source_count": _desired_source_chunk_coords.size(),
		"missing_chunk_count": missing_chunk_count,
		"stage_counts": stage_counts,
		"reason_counts": reason_counts,
		"entries": entries,
		"terminal_history": _readiness_tracker.get_terminal_history(),
	}


func _readiness_append_coord(
		coords: Array[Vector2i],
		seen: Dictionary,
		chunk_coord: Vector2i,
) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if chunk_coord == INVALID_CHUNK_COORD or seen.has(chunk_coord):
		return
	seen[chunk_coord] = true
	coords.append(chunk_coord)


func _readiness_layer(state: StringName, reason: StringName = &"") -> Dictionary:
	return {"state": state, "reason": reason}


func _build_streaming_readiness_entry(
		chunk_coord: Vector2i,
		now_msec: int,
) -> Dictionary:
	var visible_demand: bool = _is_chunk_desired(chunk_coord)
	var source_demand: bool = _is_chunk_source_desired(chunk_coord)
	var demand: StringName = &"visible" if visible_demand else (&"reserve" if source_demand else &"none")
	var packet_resident: bool = _chunk_packets.has(chunk_coord)
	var view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if not source_demand:
		return _build_retained_streaming_readiness_entry(chunk_coord, now_msec)
	var layers: Dictionary = { }
	if packet_resident:
		layers[&"packet"] = _readiness_layer(&"ready", &"packet_resident")
	elif _requested_chunks.has(chunk_coord):
		layers[&"packet"] = _readiness_layer(&"waiting", &"packet_generation_inflight")
	elif _warm_base_chunk_packet_cache.has(chunk_coord):
		layers[&"packet"] = _readiness_layer(
			&"waiting" if source_demand else &"retained",
			&"packet_warm_cache_restore_pending" if source_demand else &"packet_warm_cache_retained",
		)
	elif source_demand:
		layers[&"packet"] = _readiness_layer(&"waiting", &"packet_request_not_enqueued")
	else:
		layers[&"packet"] = _readiness_layer(&"evicted", &"packet_evicted")

	if not packet_resident:
		layers[&"terrain"] = _readiness_layer(&"waiting", &"terrain_waiting_for_packet")
	elif view != null and view.is_terrain_cell_presentation_committed():
		layers[&"terrain"] = _readiness_layer(&"ready", &"terrain_cells_committed")
	elif chunk_coord == _active_publish_chunk:
		layers[&"terrain"] = _readiness_layer(&"waiting", &"terrain_publish_applying")
	elif _pending_publish_queue.has(chunk_coord):
		layers[&"terrain"] = _readiness_layer(&"waiting", &"terrain_publish_queued")
	elif source_demand and not visible_demand:
		layers[&"terrain"] = _readiness_layer(&"waiting", &"terrain_reserve_not_materialized")
	elif visible_demand:
		layers[&"terrain"] = _readiness_layer(&"waiting", &"terrain_publish_not_queued")
	else:
		layers[&"terrain"] = _readiness_layer(&"retained", &"terrain_view_cache_retained") \
				if _hot_chunk_view_cache.has(chunk_coord) \
				else _readiness_layer(&"evicted", &"terrain_view_evicted")

	var mountain_halo: Dictionary = _mountain_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	var mountain_result: Dictionary = _mountain_native_masks_by_chunk.get(chunk_coord, { }) as Dictionary
	if not packet_resident:
		layers[&"mountain_mask"] = _readiness_layer(&"waiting", &"mountain_mask_waiting_for_packet")
	elif mountain_halo.is_empty():
		layers[&"mountain_mask"] = _readiness_layer(&"waiting", &"mountain_halo_not_prepared")
	elif not bool(mountain_halo.get("has_closed", false)):
		layers[&"mountain_mask"] = _readiness_layer(&"not_applicable", &"no_mountain_surface")
	elif _mountain_native_mask_retry_by_chunk.has(chunk_coord):
		layers[&"mountain_mask"] = _readiness_layer(&"waiting", &"mountain_mask_retry_backoff")
	elif _mountain_native_mask_inflight_chunks.has(chunk_coord):
		layers[&"mountain_mask"] = _readiness_layer(&"waiting", &"mountain_mask_worker_inflight")
	elif mountain_result.is_empty():
		layers[&"mountain_mask"] = _readiness_layer(&"waiting", &"mountain_mask_request_not_enqueued")
	elif view == null:
		layers[&"mountain_mask"] = _readiness_layer(&"waiting", &"mountain_mask_reserve_visual_not_materialized")
	elif view.is_mountain_native_mask_visual_pending():
		layers[&"mountain_mask"] = _readiness_layer(&"waiting", &"mountain_mask_visual_upload")
	else:
		layers[&"mountain_mask"] = _readiness_layer(&"ready", &"mountain_mask_visual_ready")

	var terrain_halo: Dictionary = _terrain_edge_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	var terrain_result: Dictionary = _terrain_edge_masks_by_chunk.get(chunk_coord, { }) as Dictionary
	if not packet_resident:
		layers[&"terrain_edge_mask"] = _readiness_layer(&"waiting", &"terrain_edge_waiting_for_packet")
	elif terrain_halo.is_empty():
		layers[&"terrain_edge_mask"] = _readiness_layer(&"waiting", &"terrain_edge_halo_not_prepared")
	elif not bool(terrain_halo.get("has_shoreline", false)):
		layers[&"terrain_edge_mask"] = _readiness_layer(&"not_applicable", &"no_shoreline")
	elif _terrain_edge_mask_inflight_chunks.has(chunk_coord):
		layers[&"terrain_edge_mask"] = _readiness_layer(&"waiting", &"terrain_edge_mask_worker_inflight")
	elif terrain_result.is_empty():
		layers[&"terrain_edge_mask"] = _readiness_layer(&"waiting", &"terrain_edge_mask_request_not_enqueued")
	elif view == null:
		layers[&"terrain_edge_mask"] = _readiness_layer(&"waiting", &"terrain_edge_reserve_visual_not_materialized")
	else:
		var edge_debug: Dictionary = view.get_terrain_edge_mask_debug_state()
		layers[&"terrain_edge_mask"] = _readiness_layer(
			&"waiting" if bool(edge_debug.get("visual_pending", false)) else &"ready",
			&"terrain_edge_mask_visual_upload" \
					if bool(edge_debug.get("visual_pending", false)) \
					else &"terrain_edge_mask_visual_ready",
		)

	var hot_object_entry: Dictionary = _hot_object_presentation_layers.get(chunk_coord, { }) as Dictionary
	if not packet_resident:
		layers[&"objects"] = _readiness_layer(&"waiting", &"objects_waiting_for_packet")
	elif _object_presentation_terminal_fallback_by_chunk.has(chunk_coord):
		layers[&"objects"] = _readiness_layer(&"waiting", &"object_presentation_terminal_fallback")
	elif _object_presentation_retry_by_chunk.has(chunk_coord):
		layers[&"objects"] = _readiness_layer(&"waiting", &"object_presentation_retry_backoff")
	elif view != null and view.is_object_presentation_complete():
		layers[&"objects"] = _readiness_layer(&"ready", &"object_presentation_committed")
	elif bool(hot_object_entry.get("ready", false)):
		layers[&"objects"] = _readiness_layer(&"ready", &"object_hot_presentation_ready")
	elif _pending_object_packet_visual_upload_set.has(chunk_coord) \
			or not hot_object_entry.is_empty():
		layers[&"objects"] = _readiness_layer(&"waiting", &"object_presentation_gpu_upload")
	elif _object_presentation_results_by_chunk.has(chunk_coord):
		layers[&"objects"] = _readiness_layer(&"waiting", &"object_presentation_cpu_ready_not_staged")
	elif _object_presentation_inflight_chunks.has(chunk_coord):
		layers[&"objects"] = _readiness_layer(&"waiting", &"object_presentation_worker_inflight")
	else:
		layers[&"objects"] = _readiness_layer(&"waiting", &"object_presentation_request_not_enqueued")

	if not packet_resident:
		layers[&"grass"] = _readiness_layer(&"waiting", &"grass_waiting_for_packet")
	elif view != null and view.is_grass_scatter_presentation_committed():
		layers[&"grass"] = _readiness_layer(&"ready", &"grass_presentation_committed")
	elif _pending_grass_scatter_visual_upload_set.has(chunk_coord):
		layers[&"grass"] = _readiness_layer(&"waiting", &"grass_gpu_upload")
	elif _grass_scatter_results_by_chunk.has(chunk_coord):
		layers[&"grass"] = _readiness_layer(&"waiting", &"grass_cpu_ready_not_staged")
	elif _grass_scatter_retry_by_chunk.has(chunk_coord):
		layers[&"grass"] = _readiness_layer(&"waiting", &"grass_retry_backoff")
	elif _grass_scatter_inflight_chunks.has(chunk_coord):
		layers[&"grass"] = _readiness_layer(&"waiting", &"grass_worker_inflight")
	elif not source_demand and _warm_grass_scatter_cache.has(chunk_coord):
		layers[&"grass"] = _readiness_layer(&"retained", &"grass_warm_cache_retained")
	else:
		layers[&"grass"] = _readiness_layer(&"waiting", &"grass_request_not_enqueued")

	if view == null:
		layers[&"roof_cavity"] = _readiness_layer(
			&"waiting" if source_demand else &"evicted",
			&"roof_cavity_reserve_not_materialized" if source_demand else &"roof_cavity_evicted",
		)
	elif view.is_mountain_native_mask_visual_pending():
		layers[&"roof_cavity"] = _readiness_layer(&"waiting", &"roof_cavity_visual_upload")
	else:
		layers[&"roof_cavity"] = _readiness_layer(&"ready", &"roof_cavity_visual_ready")

	if not visible_demand:
		layers[&"visibility"] = _readiness_layer(&"not_applicable", &"outside_visible_demand")
	elif view != null and view.visible:
		layers[&"visibility"] = _readiness_layer(&"ready", &"chunk_visible")
	elif _pending_chunk_visibility_after_mountain_visual.has(chunk_coord):
		var visibility_reason: StringName = &"visibility_reveal_guard"
		if view != null and view.is_mountain_native_mask_visual_pending():
			visibility_reason = &"visibility_waiting_for_mountain_visual"
		elif view != null and not view.is_object_blocking_presentation_ready():
			visibility_reason = &"visibility_waiting_for_object_presentation"
		elif int(Engine.get_process_frames()) < int(
			_object_presentation_reveal_not_before_frame_by_chunk.get(chunk_coord, 0),
		):
			visibility_reason = &"visibility_waiting_for_next_frame_finalize"
		layers[&"visibility"] = _readiness_layer(&"waiting", visibility_reason)
	elif chunk_coord == _active_publish_chunk:
		layers[&"visibility"] = _readiness_layer(&"waiting", &"visibility_waiting_for_terrain_publish")
	elif _pending_publish_queue.has(chunk_coord):
		layers[&"visibility"] = _readiness_layer(&"waiting", &"visibility_waiting_in_publish_queue")
	else:
		layers[&"visibility"] = _readiness_layer(&"waiting", &"visibility_view_not_created")

	var terrain_ready: bool = _readiness_state_is_ready(layers.get(&"terrain", { }) as Dictionary)
	var mountain_ready: bool = _readiness_state_is_ready(layers.get(&"mountain_mask", { }) as Dictionary)
	var objects_ready: bool = _readiness_state_is_ready(layers.get(&"objects", { }) as Dictionary)
	var gameplay_ready: bool = terrain_ready and mountain_ready and objects_ready
	layers[&"gameplay"] = _readiness_layer(
		&"ready" if gameplay_ready else &"waiting",
		&"gameplay_layers_ready" if gameplay_ready else &"gameplay_dependency_pending",
	)

	var presentation_ready: bool = gameplay_ready
	for layer_name: StringName in [
		&"terrain_edge_mask", &"grass", &"roof_cavity",
	]:
		presentation_ready = presentation_ready \
				and _readiness_state_is_ready(layers.get(layer_name, { }) as Dictionary)
	var lifecycle_stage: StringName = &"requested"
	if not source_demand:
		lifecycle_stage = &"retained" if _readiness_has_retained_data(chunk_coord) else &"evicted"
	elif packet_resident:
		lifecycle_stage = &"generated"
		if gameplay_ready:
			lifecycle_stage = &"gameplay_ready"
		if presentation_ready:
			lifecycle_stage = &"reserve_ready" if not visible_demand else &"presentation_ready"
		if visible_demand and view != null and view.visible:
			lifecycle_stage = &"visible"
	var timing: Dictionary = _readiness_tracker.observe(
		chunk_coord,
		lifecycle_stage,
		layers,
		now_msec,
	)
	var timed_layers: Dictionary = timing.get("layers", { }) as Dictionary
	var blocking_layer: String = ""
	var blocking_reason: String = ""
	var blocking_elapsed_ms: int = 0
	for layer_name: StringName in [
		&"packet", &"terrain", &"mountain_mask", &"objects",
		&"terrain_edge_mask", &"grass", &"roof_cavity", &"visibility",
	]:
		var layer: Dictionary = timed_layers.get(String(layer_name), { }) as Dictionary
		if String(layer.get("state", "")) != "waiting":
			continue
		blocking_layer = String(layer_name)
		blocking_reason = String(layer.get("reason", ""))
		blocking_elapsed_ms = int(layer.get("elapsed_ms", 0))
		break
	var ready: bool = blocking_reason.is_empty() \
			and lifecycle_stage in [&"reserve_ready", &"visible", &"retained"]
	return {
		"chunk_coord": chunk_coord,
		"demand": String(demand),
		"lifecycle_stage": String(lifecycle_stage),
		"stage_elapsed_ms": int(timing.get("stage_elapsed_ms", 0)),
		"ready": ready,
		"blocking_layer": blocking_layer,
		"blocking_reason": blocking_reason,
		"blocking_elapsed_ms": blocking_elapsed_ms,
		"layers": timed_layers,
	}


func _build_retained_streaming_readiness_entry(
		chunk_coord: Vector2i,
		now_msec: int,
) -> Dictionary:
	var layers: Dictionary = {
		&"packet": _readiness_layer(
			&"retained" if _warm_base_chunk_packet_cache.has(chunk_coord) else &"evicted",
			&"packet_warm_cache_retained" \
					if _warm_base_chunk_packet_cache.has(chunk_coord) else &"packet_evicted",
		),
		&"terrain": _readiness_layer(
			&"retained" if _hot_chunk_view_cache.has(chunk_coord) else &"evicted",
			&"terrain_view_cache_retained" \
					if _hot_chunk_view_cache.has(chunk_coord) else &"terrain_view_evicted",
		),
		&"mountain_mask": _readiness_layer(&"evicted", &"mountain_mask_evicted"),
		&"terrain_edge_mask": _readiness_layer(&"evicted", &"terrain_edge_mask_evicted"),
		&"objects": _readiness_layer(
			&"retained" if _hot_object_presentation_layers.has(chunk_coord) \
					or _warm_object_presentation_cache.has(chunk_coord) else &"evicted",
			&"object_presentation_retained" \
					if _hot_object_presentation_layers.has(chunk_coord) \
							or _warm_object_presentation_cache.has(chunk_coord) \
					else &"object_presentation_evicted",
		),
		&"grass": _readiness_layer(
			&"retained" if _warm_grass_scatter_cache.has(chunk_coord) \
					or _hot_chunk_view_cache.has(chunk_coord) else &"evicted",
			&"grass_presentation_retained" \
					if _warm_grass_scatter_cache.has(chunk_coord) \
							or _hot_chunk_view_cache.has(chunk_coord) \
					else &"grass_presentation_evicted",
		),
		&"roof_cavity": _readiness_layer(&"evicted", &"roof_cavity_evicted"),
		&"visibility": _readiness_layer(&"not_applicable", &"outside_visible_demand"),
		&"gameplay": _readiness_layer(&"retained", &"outside_source_demand"),
	}
	var timing: Dictionary = _readiness_tracker.observe(
		chunk_coord,
		&"retained",
		layers,
		now_msec,
	)
	return {
		"chunk_coord": chunk_coord,
		"demand": "none",
		"lifecycle_stage": "retained",
		"stage_elapsed_ms": int(timing.get("stage_elapsed_ms", 0)),
		"ready": true,
		"blocking_layer": "",
		"blocking_reason": "",
		"blocking_elapsed_ms": 0,
		"layers": timing.get("layers", { }),
	}


func _readiness_state_is_ready(layer: Dictionary) -> bool:
	var state: String = String(layer.get("state", "waiting"))
	return state == "ready" or state == "not_applicable" or state == "retained"


func _readiness_has_retained_data(chunk_coord: Vector2i) -> bool:
	return _warm_base_chunk_packet_cache.has(chunk_coord) \
			or _hot_chunk_view_cache.has(chunk_coord) \
			or _hot_object_presentation_layers.has(chunk_coord) \
			or _warm_object_presentation_cache.has(chunk_coord) \
			or _warm_grass_scatter_cache.has(chunk_coord)


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
	var hot_object_ready_count: int = 0
	for entry_variant: Variant in _hot_object_presentation_layers.values():
		var hot_entry: Dictionary = entry_variant as Dictionary
		if bool(hot_entry.get("ready", false)):
			hot_object_ready_count += 1
	var snapshot: Dictionary = _last_mountain_mask_result.duplicate(true)
	snapshot["stream_radius_chunks"] = _current_stream_radius_chunks
	snapshot["page_source_radius_chunks"] = MOUNTAIN_MASK_SOURCE_RADIUS_CHUNKS
	snapshot["page_worker_count"] = _world_compute_worker_count
	snapshot["world_compute_pool_shared"] = true
	snapshot["world_compute_worker_count"] = _world_compute_worker_count
	snapshot["world_compute_logical_processor_count"] = OS.get_processor_count()
	snapshot["ready_page_count"] = ready_native_mask_chunk_count
	snapshot["ready_view_page_count"] = ready_native_mask_chunk_count
	snapshot["page_backend_pending"] = \
		_world_compute_backend.has_pending_request_kind(&"mountain_raster") \
		or _world_compute_backend.has_pending_request_kind(&"mountain_halo_mask")
	snapshot["page_backend_completed"] = _mountain_mask_backend.has_completed_mountain_rasters() \
			or _mountain_mask_backend.has_completed_mountain_halo_masks()
	snapshot["native_mask_cached_count"] = _mountain_native_masks_by_chunk.size()
	snapshot["native_mask_inflight_count"] = _mountain_native_mask_inflight_chunks.size()
	snapshot["preset_path"] = MOUNTAIN_MASK_PRESET_PATH
	snapshot["desired_mountain_chunk_count"] = 0
	snapshot["missing_mountain_chunk_count"] = 0
	snapshot["packet_count"] = _chunk_packets.size()
	snapshot["source_packet_count"] = _chunk_packets.size()
	snapshot["base_packet_count"] = _base_chunk_packets.size()
	snapshot["warm_packet_cache_count"] = _warm_base_chunk_packet_cache.size()
	snapshot["warm_packet_cache_capacity"] = WARM_PACKET_CACHE_MAX_CHUNKS
	snapshot["warm_packet_cache_hit_count_total"] = _warm_packet_cache_hit_count_total
	snapshot["object_presentation_worker_count"] = _world_compute_worker_count
	snapshot["object_presentation_inflight_count"] = _object_presentation_inflight_chunks.size()
	snapshot["object_presentation_ready_count"] = _object_presentation_results_by_chunk.size()
	snapshot["object_presentation_warm_cache_count"] = _warm_object_presentation_cache.size()
	snapshot["object_presentation_warm_cache_bytes"] = _warm_object_presentation_cache_bytes
	snapshot["object_presentation_warm_cache_max_bytes"] = WARM_OBJECT_PRESENTATION_CACHE_MAX_BYTES
	snapshot["object_presentation_cache_hit_count_total"] = _object_presentation_cache_hit_count_total
	snapshot["object_presentation_hot_cache_count"] = _hot_object_presentation_layers.size()
	snapshot["object_presentation_hot_cache_ready_count"] = hot_object_ready_count
	snapshot["object_presentation_hot_cache_staging_count"] = \
		_hot_object_presentation_layers.size() - hot_object_ready_count
	snapshot["object_presentation_hot_cache_gpu_bytes"] = _hot_object_presentation_cache_bytes
	snapshot["object_presentation_hot_cache_gpu_max_bytes"] = \
		HOT_OBJECT_PRESENTATION_CACHE_MAX_BYTES
	snapshot["object_presentation_hot_cache_canvas_items"] = \
		_hot_object_presentation_cache_canvas_items
	snapshot["object_presentation_hot_cache_colliders"] = \
		_hot_object_presentation_cache_colliders
	snapshot["object_presentation_hot_cache_hit_count_total"] = \
		_hot_object_presentation_cache_hit_count_total
	snapshot["object_presentation_hot_cache_eviction_count_total"] = \
		_hot_object_presentation_cache_eviction_count_total
	snapshot["object_presentation_layer_pool_count"] = \
		_object_presentation_layer_pool.size()
	snapshot["object_presentation_retire_queue_count"] = \
		_object_presentation_retire_queue.size()
	snapshot["object_presentation_retire_gpu_bytes"] = \
		_object_presentation_retire_gpu_bytes
	snapshot["object_presentation_retire_canvas_items"] = \
		_object_presentation_retire_canvas_items
	snapshot["object_presentation_retire_colliders"] = \
		_object_presentation_retire_colliders
	snapshot["object_presentation_retire_phase_count_total"] = \
		_object_presentation_retire_phase_count_total
	snapshot["object_presentation_retire_phase_usec_max_total"] = \
		_object_presentation_retire_phase_usec_max_total
	snapshot["object_presentation_pool_canvas_items"] = \
		_object_presentation_pool_canvas_items
	snapshot["object_presentation_total_resident_gpu_bytes"] = \
		_object_presentation_total_gpu_bytes()
	snapshot["object_presentation_total_resident_canvas_items"] = \
		_object_presentation_total_canvas_items()
	snapshot["object_presentation_total_resident_colliders"] = \
		_object_presentation_total_colliders()
	snapshot["object_presentation_deferred_reveal_count"] = \
		_object_presentation_reveal_not_before_frame_by_chunk.size()
	snapshot["object_presentation_worker_pending"] = \
		_world_compute_backend.has_pending_request_kind(&"object_presentation")
	snapshot["object_presentation_worker_completed"] = \
		_object_presentation_backend.has_completed_object_presentation_buffers()
	snapshot["object_presentation_worker_elapsed_ms_last"] = \
		_object_presentation_worker_elapsed_ms_last
	snapshot["object_presentation_worker_elapsed_ms_max_total"] = \
		_object_presentation_worker_elapsed_ms_max_total
	snapshot["object_presentation_request_to_complete_ms_last"] = \
		_object_presentation_request_to_complete_ms_last
	snapshot["object_presentation_request_to_complete_ms_max_total"] = \
		_object_presentation_request_to_complete_ms_max_total
	snapshot["object_presentation_retry_count"] = _object_presentation_retry_by_chunk.size()
	snapshot["object_presentation_failure_count_total"] = \
		_object_presentation_failure_count_total
	snapshot["object_presentation_terminal_failure_count"] = \
		_object_presentation_terminal_failure_count
	snapshot["object_presentation_terminal_fallback_pending_count"] = \
		_object_presentation_terminal_fallback_by_chunk.size()
	snapshot["object_presentation_visual_upload_queue_count"] = \
		_pending_object_packet_visual_upload_chunks.size()
	snapshot["object_presentation_prestage_queue_count"] = \
		_pending_hot_object_prestage_chunks.size()
	snapshot["object_presentation_focused_upload_chunk"] = \
		_focused_object_packet_visual_upload_chunk
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
	snapshot["chunk_visibility_waiting_for_roof_count"] = \
	_pending_chunk_visibility_after_mountain_visual.size()
	# Compatibility key above remains for existing diagnostics. The visibility
	# gate now covers every required blocking visual, including tree collisions.
	snapshot["chunk_visibility_waiting_for_blocking_visual_count"] = \
		_pending_chunk_visibility_after_mountain_visual.size()
	snapshot["mountain_roof_target_mountain_id"] = _active_cover_mountain_id
	snapshot["mountain_roof_target_component_id"] = _active_cover_component_id
	snapshot["mountain_roof_displayed_mountain_id"] = _displayed_cover_mountain_id
	snapshot["mountain_roof_displayed_component_id"] = _displayed_cover_component_id
	snapshot["mountain_roof_displayed_visual_chunk_count"] = \
	_displayed_cover_visual_chunks.size()
	snapshot["mountain_roof_reveal_transition_state"] = \
	_get_mountain_roof_reveal_transition_state_name()
	snapshot["mountain_roof_reveal_blend"] = _mountain_roof_reveal_blend
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
	snapshot["grass_scatter_visual_upload_focus"] = \
		_focused_grass_scatter_visual_upload_chunk
	snapshot["grass_scatter_inflight_count"] = _grass_scatter_inflight_chunks.size()
	snapshot["grass_scatter_ready_cpu_count"] = _grass_scatter_results_by_chunk.size()
	snapshot["grass_scatter_warm_cache_count"] = _warm_grass_scatter_cache.size()
	snapshot["grass_scatter_warm_cache_bytes"] = _warm_grass_scatter_cache_bytes
	snapshot["grass_scatter_cache_hit_count_total"] = _grass_scatter_cache_hit_count_total
	snapshot["hot_chunk_view_cache_count"] = _hot_chunk_view_cache.size()
	snapshot["hot_chunk_view_cache_capacity"] = HOT_CHUNK_VIEW_CACHE_MAX_ENTRIES
	snapshot["hot_chunk_view_cache_hit_count_total"] = _hot_chunk_view_cache_hit_count_total
	snapshot["hot_chunk_view_pool_reuse_count_total"] = _hot_chunk_view_pool_reuse_count_total
	snapshot["hot_chunk_view_grass_preserve_hit_count_total"] = \
			_hot_chunk_view_grass_preserve_hit_count_total
	snapshot["hot_chunk_view_terrain_preserve_hit_count_total"] = \
			_hot_chunk_view_terrain_preserve_hit_count_total
	snapshot["grass_scatter_worker_pending"] = \
		_world_compute_backend.has_pending_request_kind(&"grass_scatter")
	snapshot["grass_scatter_worker_completed"] = \
		_grass_scatter_backend.has_completed_grass_scatter_buffers()
	snapshot["grass_scatter_worker_elapsed_ms_last"] = _grass_scatter_worker_elapsed_ms_last
	snapshot["grass_scatter_worker_elapsed_ms_max_total"] = _grass_scatter_worker_elapsed_ms_max_total
	snapshot["grass_scatter_request_to_complete_ms_last"] = \
		_grass_scatter_request_to_complete_ms_last
	snapshot["grass_scatter_request_to_complete_ms_max_total"] = \
		_grass_scatter_request_to_complete_ms_max_total
	snapshot["chunk_reveal_with_pending_grass_count_total"] = \
		_chunk_reveal_with_pending_grass_count_total
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
## the real organic excavation delta (CLOSED solid, live mask open). This
## prevents the roof from snapping shut when the player's centre stands in a
## walkable curved corner just outside the square DUG source cell.
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


func get_mountain_cover_debug_snapshot(world_tile: Vector2i) -> Dictionary:
	var debug_snapshot: Dictionary = _mountain_cavity_cache.get_debug_snapshot(
		world_tile,
		_active_cover_component_id,
		Callable(self, "_sample_mountain_cover_tile"),
	)
	debug_snapshot["active_mountain_id"] = _active_cover_mountain_id
	debug_snapshot["active_component_id"] = _active_cover_component_id
	debug_snapshot["target_mountain_id"] = _active_cover_mountain_id
	debug_snapshot["target_component_id"] = _active_cover_component_id
	debug_snapshot["displayed_mountain_id"] = _displayed_cover_mountain_id
	debug_snapshot["displayed_component_id"] = _displayed_cover_component_id
	debug_snapshot["roof_reveal_transition_state"] = \
	_get_mountain_roof_reveal_transition_state_name()
	debug_snapshot["component_reveal_blend"] = _mountain_roof_reveal_blend
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
	var ready_results: Dictionary = { }
	var any_solid: bool = false
	var pending: bool = false
	var signature_parts: Array[String] = [
		"%d,%d,%d,%d" % [roundi(origin.x), roundi(origin.y), width, height],
	]
	for chunk_coord: Vector2i in chunks:
		chunk_coord = _canonicalize_chunk_coord(chunk_coord)
		var revision: int = _get_mountain_mask_revision(chunk_coord)
		if not _has_loaded_mountain_halo_sources(chunk_coord):
			pending = true
			signature_parts.append("%s:%d:loading" % [str(chunk_coord), revision])
			continue
		var halo: Dictionary = _get_cached_mountain_solid_halo(chunk_coord)
		var has_any: bool = bool(halo.get("has_any", false))
		signature_parts.append("%s:%d:%s" % [str(chunk_coord), revision, "solid" if has_any else "empty"])
		if not has_any:
			continue
		any_solid = true
		var result: Dictionary = _get_ready_mountain_native_mask_result(chunk_coord)
		if result.is_empty():
			_request_mountain_native_mask_for_chunk(
				chunk_coord,
				halo,
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
	var cached: Dictionary = _mountain_torch_shadow_field_mask_cache.get("last", { }) as Dictionary
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
	for chunk_variant: Variant in ready_results.keys():
		var chunk_coord: Vector2i = chunk_variant as Vector2i
		var result: Dictionary = ready_results.get(chunk_coord, { }) as Dictionary
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
	_active_cover_mountain_id = resolved_mountain_id
	_active_cover_component_id = resolved_component_id
	_sync_mountain_roof_reveal_target()


## Gameplay target ownership changes immediately through _active_cover_*. The
## displayed selector is retained independently until this presentation state
## machine has finished closing it. Keeping the two states separate prevents
## an exit from deleting the only mask that can still fade the old roof in.
func _sync_mountain_roof_reveal_target() -> void:
	if _active_cover_component_id <= 0:
		_begin_mountain_roof_reveal_close()
		return
	if _displayed_cover_component_id <= 0:
		_replace_displayed_cover_component(
			_active_cover_mountain_id,
			_active_cover_component_id,
		)
		_begin_mountain_roof_reveal_open()
		return
	if _displayed_cover_mountain_id == _active_cover_mountain_id:
		if _displayed_cover_component_id == _active_cover_component_id:
			_begin_mountain_roof_reveal_open()
			return
		# Component ids are derived cache handles and can be replaced after a
		# merge/chunk reload while the player never left this mountain. Only an
		# ID that actually disappeared is a repair: two still-live components of
		# the same mountain are distinct cavities and must transition through a
		# fully closed roof instead of snapping the selector at the current blend.
		if not _mountain_cavity_cache.has_component(_displayed_cover_component_id):
			_replace_displayed_cover_component(
				_active_cover_mountain_id,
				_active_cover_component_id,
			)
			_begin_mountain_roof_reveal_open()
			return
		_begin_mountain_roof_reveal_close()
		return
	# A different mountain must not replace a still-visible selector. The most
	# recent _active_cover_* values act as the pending target after close.
	_begin_mountain_roof_reveal_close()


func _begin_mountain_roof_reveal_open() -> void:
	if _displayed_cover_component_id <= 0:
		return
	# Selector images are uploaded through the bounded visual queue. Do not
	# advance alpha (or report OPEN after an id repair) while either the old
	# selector cleanup or the new displayed selector still lives only on CPU.
	if not _is_displayed_cover_selector_upload_ready():
		_mountain_roof_reveal_transition_state = \
		MountainRoofRevealTransitionState.OPENING_WAIT_SELECTOR
		_mountain_roof_reveal_transition_elapsed_sec = 0.0
		set_process(true)
		return
	if _mountain_roof_reveal_blend >= 1.0 - 0.0001:
		# A same-mountain id repair at full reveal never blinks the roof closed
		# the upload barrier above merely keeps transition/debug state honest
		# until every affected chunk has received the replacement selector.
		_set_mountain_roof_reveal_blend(1.0)
		_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.OPEN
		_mountain_roof_reveal_transition_elapsed_sec = 0.0
		_mountain_roof_reveal_transition_start_blend = 1.0
		_mountain_roof_reveal_transition_duration_sec = 0.0
		set_process(false)
		return
	if _mountain_roof_reveal_transition_state == MountainRoofRevealTransitionState.OPENING:
		return
	_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.OPENING
	_mountain_roof_reveal_transition_elapsed_sec = 0.0
	_mountain_roof_reveal_transition_start_blend = _mountain_roof_reveal_blend
	_mountain_roof_reveal_transition_duration_sec = maxf(
		0.001,
		MOUNTAIN_ROOF_REVEAL_ENTER_DURATION_SEC * (1.0 - _mountain_roof_reveal_blend),
	)
	set_process(true)


func _begin_mountain_roof_reveal_close() -> void:
	if _displayed_cover_component_id <= 0:
		_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.CLOSED
		_set_mountain_roof_reveal_blend(0.0)
		set_process(false)
		return
	if _mountain_roof_reveal_blend <= 0.0001:
		_complete_mountain_roof_reveal_close()
		return
	if _mountain_roof_reveal_transition_state == MountainRoofRevealTransitionState.CLOSING_DELAY \
			or _mountain_roof_reveal_transition_state == MountainRoofRevealTransitionState.CLOSING:
		return
	_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.CLOSING_DELAY
	_mountain_roof_reveal_transition_elapsed_sec = 0.0
	_mountain_roof_reveal_transition_start_blend = _mountain_roof_reveal_blend
	_mountain_roof_reveal_transition_duration_sec = 0.0
	set_process(true)


func _advance_mountain_roof_reveal_transition(delta: float) -> void:
	var remaining_delta: float = maxf(0.0, delta)
	if _mountain_roof_reveal_transition_state \
			== MountainRoofRevealTransitionState.OPENING_WAIT_SELECTOR:
		if not _is_displayed_cover_selector_upload_ready():
			return
		# Start with a fresh 150 ms clock; queue latency is not part of the fade.
		_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.CLOSED
		_begin_mountain_roof_reveal_open()
		return
	if _mountain_roof_reveal_transition_state == MountainRoofRevealTransitionState.CLOSING_DELAY:
		_mountain_roof_reveal_transition_elapsed_sec += remaining_delta
		if _mountain_roof_reveal_transition_elapsed_sec < MOUNTAIN_ROOF_REVEAL_EXIT_DELAY_SEC:
			return
		remaining_delta = _mountain_roof_reveal_transition_elapsed_sec \
				- MOUNTAIN_ROOF_REVEAL_EXIT_DELAY_SEC
		_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.CLOSING
		_mountain_roof_reveal_transition_elapsed_sec = 0.0
		_mountain_roof_reveal_transition_start_blend = _mountain_roof_reveal_blend
		_mountain_roof_reveal_transition_duration_sec = maxf(
			0.001,
			MOUNTAIN_ROOF_REVEAL_EXIT_DURATION_SEC * _mountain_roof_reveal_blend,
		)
	if _mountain_roof_reveal_transition_state == MountainRoofRevealTransitionState.OPENING:
		if not _is_displayed_cover_selector_upload_ready():
			_mountain_roof_reveal_transition_state = \
			MountainRoofRevealTransitionState.OPENING_WAIT_SELECTOR
			_mountain_roof_reveal_transition_elapsed_sec = 0.0
			return
		_mountain_roof_reveal_transition_elapsed_sec += remaining_delta
		var opening_progress: float = clampf(
			_mountain_roof_reveal_transition_elapsed_sec \
					/ _mountain_roof_reveal_transition_duration_sec,
			0.0,
			1.0,
		)
		var opening_eased: float = 1.0 - pow(1.0 - opening_progress, 3.0)
		_set_mountain_roof_reveal_blend(
			lerpf(
				_mountain_roof_reveal_transition_start_blend,
				1.0,
				opening_eased,
			),
		)
		if opening_progress >= 1.0:
			_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.OPEN
			_mountain_roof_reveal_transition_elapsed_sec = 0.0
			_mountain_roof_reveal_transition_start_blend = 1.0
			_mountain_roof_reveal_transition_duration_sec = 0.0
			set_process(false)
		return
	if _mountain_roof_reveal_transition_state != MountainRoofRevealTransitionState.CLOSING:
		return
	_mountain_roof_reveal_transition_elapsed_sec += remaining_delta
	var closing_progress: float = clampf(
		_mountain_roof_reveal_transition_elapsed_sec \
				/ _mountain_roof_reveal_transition_duration_sec,
		0.0,
		1.0,
	)
	var closing_eased: float = _ease_mountain_roof_reveal_cubic_in_out(closing_progress)
	_set_mountain_roof_reveal_blend(
		lerpf(
			_mountain_roof_reveal_transition_start_blend,
			0.0,
			closing_eased,
		),
	)
	if closing_progress >= 1.0:
		_complete_mountain_roof_reveal_close()


func _complete_mountain_roof_reveal_close() -> void:
	_set_mountain_roof_reveal_blend(0.0)
	_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.CLOSED
	_mountain_roof_reveal_transition_elapsed_sec = 0.0
	_mountain_roof_reveal_transition_start_blend = 0.0
	_mountain_roof_reveal_transition_duration_sec = 0.0
	var next_mountain_id: int = _active_cover_mountain_id \
	if _active_cover_component_id > 0 else 0
	var next_component_id: int = _active_cover_component_id \
	if _active_cover_component_id > 0 else 0
	_replace_displayed_cover_component(next_mountain_id, next_component_id)
	if next_component_id > 0:
		_begin_mountain_roof_reveal_open()
	else:
		set_process(false)


func _replace_displayed_cover_component(mountain_id: int, component_id: int) -> void:
	var resolved_component_id: int = component_id if component_id > 0 else 0
	var resolved_mountain_id: int = mountain_id if resolved_component_id > 0 else 0
	if resolved_mountain_id == _displayed_cover_mountain_id \
			and resolved_component_id == _displayed_cover_component_id:
		return
	var affected_chunks: Dictionary = _displayed_cover_visual_chunks.duplicate()
	_append_cover_component_chunks(affected_chunks, _displayed_cover_component_id)
	_displayed_cover_mountain_id = resolved_mountain_id
	_displayed_cover_component_id = resolved_component_id
	_displayed_cover_visual_chunks.clear()
	var next_component_chunks: Dictionary = { }
	_append_cover_component_chunks(next_component_chunks, _displayed_cover_component_id)
	for visual_chunk: Vector2i in _expand_cover_visual_chunks(
		_dictionary_vector2i_keys(next_component_chunks),
	):
		_displayed_cover_visual_chunks[visual_chunk] = true
		affected_chunks[visual_chunk] = true
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func _set_mountain_roof_reveal_blend(value: float) -> void:
	var resolved_blend: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(resolved_blend, _mountain_roof_reveal_blend):
		return
	_mountain_roof_reveal_blend = resolved_blend
	_apply_mountain_roof_reveal_blend_to_displayed_chunks()
	var skylight_field: MountainCavitySkylightField = _get_mountain_cavity_skylight_field()
	if skylight_field != null:
		skylight_field.set_reveal_blend(_mountain_roof_reveal_blend)


func _apply_mountain_roof_reveal_blend_to_displayed_chunks() -> void:
	for chunk_coord: Vector2i in _dictionary_vector2i_keys(_displayed_cover_visual_chunks):
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view != null:
			chunk_view.set_mountain_roof_reveal_blend(_mountain_roof_reveal_blend)


func _get_mountain_cavity_skylight_field() -> MountainCavitySkylightField:
	if _mountain_cavity_skylight_field != null \
			and is_instance_valid(_mountain_cavity_skylight_field):
		return _mountain_cavity_skylight_field
	var parent: Node = get_parent()
	if parent == null:
		return null
	_mountain_cavity_skylight_field = parent.get_node_or_null(
		"MountainCavitySkylightField",
	) as MountainCavitySkylightField
	return _mountain_cavity_skylight_field


func _sync_mountain_cavity_skylight_field_chunk(
		chunk_coord: Vector2i,
		chunk_view: ChunkView,
) -> void:
	var skylight_field: MountainCavitySkylightField = _get_mountain_cavity_skylight_field()
	if skylight_field == null or chunk_view == null or not is_instance_valid(chunk_view):
		return
	skylight_field.apply_chunk_source(
		chunk_coord,
		chunk_view.get_mountain_cavity_skylight_field_source(),
	)


func _remove_mountain_cavity_skylight_field_chunk(chunk_coord: Vector2i) -> void:
	var skylight_field: MountainCavitySkylightField = _get_mountain_cavity_skylight_field()
	if skylight_field != null:
		skylight_field.remove_chunk(chunk_coord)


func _clear_mountain_cavity_skylight_field() -> void:
	var skylight_field: MountainCavitySkylightField = _get_mountain_cavity_skylight_field()
	if skylight_field != null:
		skylight_field.clear()
		skylight_field.set_reveal_blend(0.0)


func _is_displayed_cover_selector_upload_ready() -> bool:
	if not _try_commit_mountain_roof_reveal_selector_generation():
		return false
	# Keep the opening barrier compatible with the chunk publish gate: a newly
	# loaded displayed chunk may still be uploading its initial zero selector or
	# native mask even when it did not need a staged selector transition.
	for chunk_coord: Vector2i in _dictionary_vector2i_keys(_displayed_cover_visual_chunks):
		if _pending_mountain_native_mask_visual_upload_set.has(chunk_coord):
			return false
	return true


func _try_commit_mountain_roof_reveal_selector_generation() -> bool:
	if _mountain_roof_reveal_selector_wait_chunks.is_empty():
		return true
	var generation: int = _mountain_roof_reveal_selector_generation
	var commit_chunks: Array[Vector2i] = []
	var released_chunks: Array[Vector2i] = []
	for chunk_coord: Vector2i in _dictionary_vector2i_keys(
		_mountain_roof_reveal_selector_wait_chunks,
	):
		var waiting_generation: int = int(
			_mountain_roof_reveal_selector_wait_chunks.get(chunk_coord, 0),
		)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view != null \
				and is_instance_valid(chunk_view) \
				and chunk_view.has_staged_mountain_roof_reveal_halo(generation):
			_mountain_roof_reveal_selector_wait_chunks[chunk_coord] = generation
			commit_chunks.append(chunk_coord)
			continue
		if chunk_view != null and is_instance_valid(chunk_view):
			chunk_view.cancel_staged_mountain_roof_reveal_halo(waiting_generation)
		_mountain_roof_reveal_selector_wait_chunks.erase(chunk_coord)
		released_chunks.append(chunk_coord)
	for chunk_coord: Vector2i in released_chunks:
		_finalize_pending_chunk_visibility(chunk_coord)

	# Preflight the complete generation before changing a single material. Since
	# this runs synchronously on the main thread, the following commit loop is an
	# atomic publication from the renderer's point of view.
	for chunk_coord: Vector2i in commit_chunks:
		if _pending_mountain_native_mask_visual_upload_set.has(chunk_coord):
			return false
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view == null \
				or not chunk_view.is_staged_mountain_roof_reveal_halo_ready(generation):
			return false
	for chunk_coord: Vector2i in commit_chunks:
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		chunk_view.commit_staged_mountain_roof_reveal_halo(generation)
		_sync_mountain_cavity_skylight_field_chunk(chunk_coord, chunk_view)
		_mountain_roof_reveal_selector_wait_chunks.erase(chunk_coord)
	for chunk_coord: Vector2i in commit_chunks:
		_finalize_pending_chunk_visibility(chunk_coord)
	return _mountain_roof_reveal_selector_wait_chunks.is_empty()


func _ease_mountain_roof_reveal_cubic_in_out(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5


func _get_mountain_roof_reveal_transition_state_name() -> StringName:
	match _mountain_roof_reveal_transition_state:
		MountainRoofRevealTransitionState.OPENING_WAIT_SELECTOR:
			return &"OPENING_WAIT_SELECTOR"
		MountainRoofRevealTransitionState.OPENING:
			return &"OPENING"
		MountainRoofRevealTransitionState.OPEN:
			return &"OPEN"
		MountainRoofRevealTransitionState.CLOSING_DELAY:
			return &"CLOSING_DELAY"
		MountainRoofRevealTransitionState.CLOSING:
			return &"CLOSING"
		_:
			return &"CLOSED"


func _reset_mountain_roof_reveal_presentation() -> void:
	# Presentation progress is intentionally derived and never persisted.
	_set_mountain_roof_reveal_blend(0.0)
	for chunk_view_variant: Variant in _chunk_views.values():
		var chunk_view: ChunkView = chunk_view_variant as ChunkView
		if chunk_view != null:
			chunk_view.set_mountain_roof_reveal_blend(0.0)
			chunk_view.cancel_staged_mountain_roof_reveal_halo()
	_displayed_cover_mountain_id = 0
	_displayed_cover_component_id = 0
	_displayed_cover_visual_chunks.clear()
	_mountain_roof_reveal_selector_wait_chunks.clear()
	_mountain_roof_reveal_selector_generation = 0
	_mountain_roof_reveal_transition_state = MountainRoofRevealTransitionState.CLOSED
	_mountain_roof_reveal_transition_elapsed_sec = 0.0
	_mountain_roof_reveal_transition_start_blend = 0.0
	_mountain_roof_reveal_transition_duration_sec = 0.0
	set_process(false)


func is_walkable_at_world(world_pos: Vector2) -> bool:
	var tile_data: Dictionary = _get_tile_data(world_pos)
	if not bool(tile_data.get("ready", false)):
		return false
	var terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	var hit_sample: Dictionary = _sample_mountain_mask_hit(world_pos)
	if _is_ready_mountain_mask_hit_sample(hit_sample):
		if bool(hit_sample.get("solid", false)):
			return false
		if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
			return true
		if _uses_mountain_surface_presentation(terrain_id):
			return true
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
		return true
	if _uses_mountain_surface_presentation(terrain_id):
		return false
	return bool(tile_data.get("walkable", false))


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
	var publish_queue_was_waiting: bool = not _pending_publish_queue.is_empty()
	var idle_publish_was_waiting: bool = \
			_active_publish_chunk == INVALID_CHUNK_COORD and publish_queue_was_waiting
	var packet_result_limit: int = MAX_PACKET_RESULTS_PER_TICK
	if idle_publish_was_waiting:
		packet_result_limit = MAX_PACKET_RESULTS_WHILE_PUBLISH_WAITING
	var packet_integrate_started: int = WorldPerfProbe.begin()
	var packet_integrate_started_usec: int = Time.get_ticks_usec()
	_drain_completed_packets(packet_result_limit)
	var packet_integrate_elapsed_usec: int = \
			Time.get_ticks_usec() - packet_integrate_started_usec
	WorldPerfProbe.end("WorldStreamer.packet_results.integrate_batch", packet_integrate_started)
	timing_step_usec = _record_streaming_step_timing(timing_records, "drain_packets", timing_step_usec)
	_drain_completed_object_presentation_buffers(MAX_OBJECT_PRESENTATION_RESULTS_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(timing_records, "drain_objects", timing_step_usec)
	_retry_failed_object_presentation_builds(MAX_OBJECT_PRESENTATION_RETRIES_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(timing_records, "retry_objects", timing_step_usec)
	_drain_completed_grass_scatter_buffers(MAX_GRASS_SCATTER_RESULTS_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(timing_records, "drain_grass", timing_step_usec)
	_retry_failed_grass_scatter_builds(MAX_GRASS_SCATTER_RETRIES_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(timing_records, "retry_grass", timing_step_usec)
	_drain_completed_native_masks(MAX_MOUNTAIN_NATIVE_MASK_RESULTS_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(timing_records, "drain_native_masks", timing_step_usec)
	_retry_failed_mountain_native_masks(MAX_MOUNTAIN_NATIVE_MASK_RETRIES_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(timing_records, "retry_native_masks", timing_step_usec)
	_publish_next_batch(
		publish_queue_was_waiting,
		idle_publish_was_waiting \
				or packet_integrate_elapsed_usec <= PUBLISH_PREFETCH_PACKET_HEADROOM_USEC,
	)
	timing_step_usec = _record_streaming_step_timing(timing_records, "publish", timing_step_usec)
	_evict_outside_ring(1)
	timing_step_usec = _record_streaming_step_timing(timing_records, "evict", timing_step_usec)
	_advance_initial_loading_readiness(INITIAL_LOADING_READINESS_CHECKS_PER_TICK)
	timing_step_usec = _record_streaming_step_timing(
		timing_records,
		"initial_loading",
		timing_step_usec,
	)
	_end_mountain_native_mask_tick_metrics()
	_report_streaming_step_timing(timing_records, timing_started_usec)
	return false


func _queue_mountain_native_mask_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"mountain_mask",
		&"waiting",
		&"mountain_mask_visual_upload",
	)
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
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"terrain_edge_mask",
		&"waiting",
		&"terrain_edge_mask_visual_upload",
	)
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
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"objects",
		&"waiting",
		&"object_presentation_gpu_upload",
	)
	if _pending_object_packet_visual_upload_set.has(chunk_coord):
		_mark_object_packet_visual_urgent_preemption(chunk_coord)
		return
	if _pending_object_packet_visual_upload_set.size() \
			>= OBJECT_PRESENTATION_VISUAL_QUEUE_MAX_TOKENS \
			and not _make_object_packet_visual_queue_room_for(chunk_coord):
		# Source-only overflow remains represented by its prestage token and is
		# retried after normal queue progress; no GPU work or result is discarded.
		_object_packet_visual_queue_repair_needed = true
		return
	_pending_object_packet_visual_upload_set[chunk_coord] = true
	_object_packet_visual_enqueued_turn_by_chunk[chunk_coord] = \
			_object_packet_visual_dispatch_turn
	_pending_object_packet_visual_upload_index_by_chunk[chunk_coord] = \
			_pending_object_packet_visual_upload_chunks.size()
	_pending_object_packet_visual_upload_chunks.append(chunk_coord)
	_object_packet_visual_priority_dirty = true
	_mark_object_packet_visual_urgent_preemption(chunk_coord)


func _make_object_packet_visual_queue_room_for(chunk_coord: Vector2i) -> bool:
	var candidate_class: int = _object_packet_visual_upload_class(chunk_coord)
	if candidate_class >= 2:
		return false
	var victim: Vector2i = INVALID_CHUNK_COORD
	var victim_class: int = candidate_class
	var victim_priority: int = -1
	for queued_coord: Vector2i in _pending_object_packet_visual_upload_chunks:
		var queued_class: int = _object_packet_visual_upload_class(queued_coord)
		var queued_priority: int = _chunk_request_priority(queued_coord)
		if queued_class > victim_class \
				or (queued_class == victim_class and queued_priority > victim_priority):
			victim = queued_coord
			victim_class = queued_class
			victim_priority = queued_priority
	if victim == INVALID_CHUNK_COORD:
		return false
	_drop_object_packet_visual_upload(victim)
	if _pending_hot_object_prestage_set.has(victim):
		_object_packet_visual_queue_repair_needed = true
		_object_packet_visual_queue_repair_cursor = 0
	return true


func _mark_object_packet_visual_urgent_preemption(chunk_coord: Vector2i) -> void:
	if _focused_object_packet_visual_upload_chunk == INVALID_CHUNK_COORD \
			or chunk_coord == _focused_object_packet_visual_upload_chunk \
			or not _pending_object_packet_visual_upload_set.has(
				_focused_object_packet_visual_upload_chunk,
			):
		return
	var candidate_class: int = _object_packet_visual_upload_class(chunk_coord)
	var focused_class: int = _object_packet_visual_upload_class(
		_focused_object_packet_visual_upload_chunk,
	)
	if candidate_class < focused_class \
			or (candidate_class == focused_class \
					and _chunk_request_priority(chunk_coord) \
							< _chunk_request_priority(
								_focused_object_packet_visual_upload_chunk,
							)):
		_object_packet_visual_urgent_priority_dirty = true


func _drop_object_packet_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _pending_object_packet_visual_upload_set.has(chunk_coord):
		return
	_pending_object_packet_visual_upload_set.erase(chunk_coord)
	_object_packet_visual_enqueued_turn_by_chunk.erase(chunk_coord)
	var removed_index: int = int(
		_pending_object_packet_visual_upload_index_by_chunk.get(chunk_coord, -1)
	)
	_pending_object_packet_visual_upload_index_by_chunk.erase(chunk_coord)
	if removed_index >= 0 and removed_index < _pending_object_packet_visual_upload_chunks.size():
		var last_index: int = _pending_object_packet_visual_upload_chunks.size() - 1
		if removed_index != last_index:
			var moved_coord: Vector2i = _pending_object_packet_visual_upload_chunks[last_index]
			_pending_object_packet_visual_upload_chunks[removed_index] = moved_coord
			_pending_object_packet_visual_upload_index_by_chunk[moved_coord] = removed_index
		_pending_object_packet_visual_upload_chunks.pop_back()
	if _focused_object_packet_visual_upload_chunk == chunk_coord:
		_focused_object_packet_visual_upload_chunk = INVALID_CHUNK_COORD
		_object_packet_visual_urgent_priority_dirty = false
	_object_packet_visual_priority_dirty = true


## Completion-biased priority pick. A live/reveal transaction always beats a
## hidden source-ring prestage, and the selected transaction keeps the lane
## until complete. Atomic reveal cannot benefit from dozens of half-uploaded
## chunks; completing one frontier chunk is what turns pixels/collision on.
func _take_next_object_packet_visual_upload() -> Vector2i:
	if _pending_object_packet_visual_upload_chunks.is_empty():
		return INVALID_CHUNK_COORD
	if not _object_packet_visual_priority_dirty \
			and _focused_object_packet_visual_upload_chunk != INVALID_CHUNK_COORD \
			and _pending_object_packet_visual_upload_set.has(
				_focused_object_packet_visual_upload_chunk,
			):
		_object_packet_visual_dispatch_turn += 1
		return _focused_object_packet_visual_upload_chunk
	var best_index: int = -1
	var best_class: int = 2147483647
	var best_priority: int = 0
	var best_enqueued_turn: int = 0
	var focused_index: int = -1
	for index: int in range(_pending_object_packet_visual_upload_chunks.size()):
		var candidate: Vector2i = _pending_object_packet_visual_upload_chunks[index]
		if candidate == _focused_object_packet_visual_upload_chunk:
			focused_index = index
		var enqueued_turn: int = int(
			_object_packet_visual_enqueued_turn_by_chunk.get(
				candidate,
				_object_packet_visual_dispatch_turn,
			)
		)
		var urgency_class: int = _object_packet_visual_upload_class(candidate)
		var priority: int = _chunk_request_priority(candidate)
		if best_index < 0 \
				or urgency_class < best_class \
				or (urgency_class == best_class and priority < best_priority) \
				or (urgency_class == best_class and priority == best_priority \
						and enqueued_turn < best_enqueued_turn):
			best_index = index
			best_class = urgency_class
			best_priority = priority
			best_enqueued_turn = enqueued_turn
	# Keep the current atomic transaction unless a genuinely more urgent class
	# or a closer deadline arrived. Equal-priority work waits for completion.
	if focused_index >= 0:
		var focused: Vector2i = _pending_object_packet_visual_upload_chunks[focused_index]
		var focused_class: int = _object_packet_visual_upload_class(focused)
		var focused_priority: int = _chunk_request_priority(focused)
		if best_class > focused_class \
				or (best_class == focused_class and best_priority >= focused_priority):
			best_index = focused_index
	var selected: Vector2i = _pending_object_packet_visual_upload_chunks[best_index]
	_focused_object_packet_visual_upload_chunk = selected
	_object_packet_visual_priority_dirty = false
	_object_packet_visual_urgent_priority_dirty = false
	_object_packet_visual_dispatch_turn += 1
	return selected


func _begin_object_packet_visual_priority_scan() -> void:
	# Snapshotting coordinates is cheap and keeps cursor semantics stable while
	# streaming appends or filters the live queue between dispatcher callbacks.
	# Mutations set priority_dirty again and are considered by the next scan.
	_object_packet_visual_priority_scan_candidates = \
			_pending_object_packet_visual_upload_chunks.duplicate()
	_object_packet_visual_priority_scan_cursor = 0
	_object_packet_visual_priority_scan_best = INVALID_CHUNK_COORD
	_object_packet_visual_priority_scan_best_class = 2147483647
	_object_packet_visual_priority_scan_best_priority = 0
	_object_packet_visual_priority_scan_best_turn = 0
	_object_packet_visual_priority_scan_active = true
	_object_packet_visual_priority_dirty = false
	_object_packet_visual_urgent_priority_dirty = false


## Advances a stable priority snapshot under both a time guard and an item cap.
## Returns true only when selection has completed; raw upload/envelope work is
## always deferred to a later dispatcher callback.
func _advance_object_packet_visual_priority_scan() -> bool:
	if not _object_packet_visual_priority_scan_active:
		_begin_object_packet_visual_priority_scan()
	var phase_started_usec: int = Time.get_ticks_usec()
	var processed_items: int = 0
	while _object_packet_visual_priority_scan_cursor \
			< _object_packet_visual_priority_scan_candidates.size():
		var candidate: Vector2i = _object_packet_visual_priority_scan_candidates[
			_object_packet_visual_priority_scan_cursor
		]
		_object_packet_visual_priority_scan_cursor += 1
		processed_items += 1
		if _pending_object_packet_visual_upload_set.has(candidate):
			var enqueued_turn: int = int(
				_object_packet_visual_enqueued_turn_by_chunk.get(
					candidate,
					_object_packet_visual_dispatch_turn,
				)
			)
			var urgency_class: int = _object_packet_visual_upload_class(candidate)
			var priority: int = _chunk_request_priority(candidate)
			if _object_packet_visual_priority_scan_best == INVALID_CHUNK_COORD \
					or urgency_class < _object_packet_visual_priority_scan_best_class \
					or (urgency_class == _object_packet_visual_priority_scan_best_class \
							and priority < _object_packet_visual_priority_scan_best_priority) \
					or (urgency_class == _object_packet_visual_priority_scan_best_class \
							and priority == _object_packet_visual_priority_scan_best_priority \
							and enqueued_turn < _object_packet_visual_priority_scan_best_turn):
				_object_packet_visual_priority_scan_best = candidate
				_object_packet_visual_priority_scan_best_class = urgency_class
				_object_packet_visual_priority_scan_best_priority = priority
				_object_packet_visual_priority_scan_best_turn = enqueued_turn
		if processed_items >= OBJECT_PRESENTATION_PRIORITY_SCAN_MAX_ITEMS_PER_PHASE \
				or Time.get_ticks_usec() - phase_started_usec \
						>= OBJECT_PRESENTATION_PRIORITY_SCAN_SOFT_BUDGET_USEC:
			break
	if _object_packet_visual_priority_scan_cursor \
			< _object_packet_visual_priority_scan_candidates.size():
		return false

	var selected: Vector2i = _object_packet_visual_priority_scan_best
	# Completion bias is evaluated at commit time against the current queue, not
	# the snapshot, so a focused transaction removed mid-scan is never resurrected.
	if _focused_object_packet_visual_upload_chunk != INVALID_CHUNK_COORD \
			and _pending_object_packet_visual_upload_set.has(
				_focused_object_packet_visual_upload_chunk,
			):
		var focused_class: int = _object_packet_visual_upload_class(
			_focused_object_packet_visual_upload_chunk,
		)
		var focused_priority: int = _chunk_request_priority(
			_focused_object_packet_visual_upload_chunk,
		)
		if selected == INVALID_CHUNK_COORD \
				or _object_packet_visual_priority_scan_best_class > focused_class \
				or (_object_packet_visual_priority_scan_best_class == focused_class \
						and _object_packet_visual_priority_scan_best_priority \
								>= focused_priority):
			selected = _focused_object_packet_visual_upload_chunk
	_focused_object_packet_visual_upload_chunk = selected
	_object_packet_visual_priority_scan_active = false
	_object_packet_visual_priority_scan_candidates.clear()
	_object_packet_visual_priority_scan_cursor = 0
	_object_packet_visual_priority_scan_best = INVALID_CHUNK_COORD
	_object_packet_visual_dispatch_turn += 1
	# A token appended after snapshot creation is intentionally left dirty. If no
	# snapshot candidate survived, it must trigger the next scan immediately.
	if selected == INVALID_CHUNK_COORD \
			and not _pending_object_packet_visual_upload_chunks.is_empty():
		_object_packet_visual_priority_dirty = true
	return true


func _object_packet_visual_upload_class(chunk_coord: Vector2i) -> int:
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if chunk_view == null:
		return 2 # Hidden source-ring prestage.
	if chunk_coord == _active_publish_chunk \
			or _pending_chunk_visibility_after_mountain_visual.has(chunk_coord) \
			or not chunk_view.visible:
		return 0 # Atomic reveal frontier.
	return 1 # Already visible live refresh.


func _queue_hot_object_prestage(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _pending_hot_object_prestage_set.has(chunk_coord):
		_pending_hot_object_prestage_set[chunk_coord] = true
		_pending_hot_object_prestage_chunks.append(chunk_coord)
	# The coordinate itself is the lightweight envelope token. Putting it in the
	# normal visual queue lets a newly-live reveal frontier preempt hidden GPU
	# work without acquiring a layer or touching RenderingServer in streaming tick.
	_queue_object_packet_visual_upload(chunk_coord)


func _drop_hot_object_prestage(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_pending_hot_object_prestage_set.erase(chunk_coord)
	# Repair cursors address the live prestage array. Filtering can shift every
	# later index, so restart a pending bounded scan instead of skipping an orphan.
	if _object_packet_visual_queue_repair_needed:
		_object_packet_visual_queue_repair_cursor = 0
	if _pending_hot_object_prestage_chunks.is_empty():
		return
	var filtered: Array[Vector2i] = []
	for queued_coord: Vector2i in _pending_hot_object_prestage_chunks:
		if queued_coord != chunk_coord:
			filtered.append(queued_coord)
	_pending_hot_object_prestage_chunks = filtered


## Creates one transaction envelope at a time. Keeping packed CPU results in
## this queue is cheap; Node/RenderingServer objects are only allocated by the
## separately budgeted presentation job. The matching visual-queue token keeps
## live/reveal urgency ordering identical before and after the envelope exists.
func _stage_next_pending_hot_object_presentation() -> bool:
	if _pending_hot_object_prestage_chunks.is_empty():
		return false
	var best_index: int = 0
	var best_class: int = _object_packet_visual_upload_class(
		_pending_hot_object_prestage_chunks[0],
	)
	var best_priority: int = _chunk_request_priority(
		_pending_hot_object_prestage_chunks[0],
	)
	for index: int in range(1, _pending_hot_object_prestage_chunks.size()):
		var urgency_class: int = _object_packet_visual_upload_class(
			_pending_hot_object_prestage_chunks[index],
		)
		var priority: int = _chunk_request_priority(
			_pending_hot_object_prestage_chunks[index],
		)
		if urgency_class < best_class \
				or (urgency_class == best_class and priority < best_priority):
			best_index = index
			best_class = urgency_class
			best_priority = priority
	var chunk_coord: Vector2i = _pending_hot_object_prestage_chunks[best_index]
	return _stage_pending_hot_object_presentation(chunk_coord)


func _repair_one_object_packet_visual_queue_token() -> void:
	if _pending_hot_object_prestage_chunks.is_empty():
		_object_packet_visual_queue_repair_needed = false
		_object_packet_visual_queue_repair_cursor = 0
		return
	_object_packet_visual_queue_repair_cursor = clampi(
		_object_packet_visual_queue_repair_cursor,
		0,
		_pending_hot_object_prestage_chunks.size(),
	)
	var phase_started_usec: int = Time.get_ticks_usec()
	var processed_items: int = 0
	while _object_packet_visual_queue_repair_cursor \
			< _pending_hot_object_prestage_chunks.size():
		var coord: Vector2i = _pending_hot_object_prestage_chunks[
			_object_packet_visual_queue_repair_cursor
		]
		_object_packet_visual_queue_repair_cursor += 1
		processed_items += 1
		if _pending_hot_object_prestage_set.has(coord) \
				and not _pending_object_packet_visual_upload_set.has(coord):
			_queue_object_packet_visual_upload(coord)
			if _pending_object_packet_visual_upload_set.has(coord):
				return
		if processed_items >= OBJECT_PRESENTATION_PRIORITY_SCAN_MAX_ITEMS_PER_PHASE \
				or Time.get_ticks_usec() - phase_started_usec \
						>= OBJECT_PRESENTATION_PRIORITY_SCAN_SOFT_BUDGET_USEC:
			return
	_object_packet_visual_queue_repair_needed = false
	_object_packet_visual_queue_repair_cursor = 0


## Consumes one already-selected envelope token. This function is called only
## from the object presentation FrameBudgetDispatcher job; acquire/begin and
## recycled-layer cleanup therefore cannot leak back into streaming drain.
func _stage_pending_hot_object_presentation(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _pending_hot_object_prestage_set.has(chunk_coord):
		return false
	if not _object_presentation_results_by_chunk.has(chunk_coord):
		_drop_hot_object_prestage(chunk_coord)
		_drop_object_packet_visual_upload(chunk_coord)
		return false
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if chunk_view != null:
		_drop_hot_object_prestage(chunk_coord)
		var staged: bool = _stage_ready_object_presentation(chunk_coord, chunk_view)
		if not staged:
			_drop_object_packet_visual_upload(chunk_coord)
		return staged
	if not _is_chunk_source_desired(chunk_coord):
		_drop_hot_object_prestage(chunk_coord)
		_drop_object_packet_visual_upload(chunk_coord)
		return false
	if not _get_current_hot_object_entry(chunk_coord).is_empty():
		_drop_hot_object_prestage(chunk_coord)
		return true
	# Retiring resources remain part of exact residency. Do not let source-ring
	# prewarming acquire fresh GPU graphs faster than the one-phase retire lane can
	# release them. The token deliberately remains in both queues: a live view can
	# preempt it immediately, and the same hidden token retries automatically once
	# retirement/budget pressure clears without requiring another streaming event.
	if _hidden_object_prestage_is_backpressured():
		return false
	# Consume at most one envelope/obsolete queue entry per dispatcher frame.
	# A long stale tail must not turn one nominally bounded callback into a scan
	# plus several Node/RenderingServer allocations.
	_drop_hot_object_prestage(chunk_coord)
	var result: Dictionary = _object_presentation_results_by_chunk.get(
		chunk_coord,
		{ },
	) as Dictionary
	var staged: bool = _stage_hot_object_presentation(chunk_coord, result)
	if not staged:
		# Empty/suppressed hidden packets retain CPU truth and will be queued again
		# if they later acquire a live ChunkView; they need no idle upload token.
		_drop_object_packet_visual_upload(chunk_coord)
	return staged


func _hidden_object_prestage_is_backpressured() -> bool:
	return not _object_presentation_retire_queue.is_empty() \
			or _hot_object_presentation_cache_is_over_budget()


func _queue_grass_scatter_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"grass",
		&"waiting",
		&"grass_gpu_upload",
	)
	if _pending_grass_scatter_visual_upload_set.has(chunk_coord):
		return
	_pending_grass_scatter_visual_upload_set[chunk_coord] = true
	_pending_grass_scatter_visual_upload_index_by_chunk[chunk_coord] = \
			_pending_grass_scatter_visual_upload_chunks.size()
	_pending_grass_scatter_visual_upload_chunks.append(chunk_coord)


func _request_object_presentation_build(
		chunk_coord: Vector2i,
		packet: Dictionary,
		new_base_packet: bool,
) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if packet.is_empty() or not _is_chunk_source_desired(chunk_coord):
		return
	if not _layered_object_asset_catalog.is_ready():
		push_error("WorldStreamer: layered object asset catalog is not boot-ready")
		return
	if new_base_packet:
		_drop_hot_object_prestage(chunk_coord)
		_evict_hot_object_presentation(chunk_coord)
		_object_presentation_reveal_not_before_frame_by_chunk.erase(chunk_coord)
		_object_presentation_next_revision += 1
		_object_presentation_revision_by_chunk[chunk_coord] = _object_presentation_next_revision
		_object_presentation_results_by_chunk.erase(chunk_coord)
		_erase_warm_object_presentation(chunk_coord)
		_object_presentation_retry_by_chunk.erase(chunk_coord)
		_object_presentation_terminal_fallback_by_chunk.erase(chunk_coord)
	elif _object_presentation_results_by_chunk.has(chunk_coord) \
			or _object_presentation_inflight_chunks.has(chunk_coord):
		return
	elif not _object_presentation_revision_by_chunk.has(chunk_coord):
		_object_presentation_next_revision += 1
		_object_presentation_revision_by_chunk[chunk_coord] = _object_presentation_next_revision
	var revision: int = int(_object_presentation_revision_by_chunk.get(chunk_coord, -1))
	if revision < 0:
		return
	var living_flora_enabled: bool = _plains_living_flora_atlas != null
	var spiky_flora_enabled: bool = \
			_plains_spiky_flora_atlases.size() == WorldLayeredObjectAssetCatalog.SPIKY_ATLAS_BANK_COUNT
	if spiky_flora_enabled:
		for atlas: Texture2D in _plains_spiky_flora_atlases:
			if atlas == null:
				spiky_flora_enabled = false
				break
	_object_presentation_inflight_chunks[chunk_coord] = revision
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"objects",
		&"waiting",
		&"object_presentation_worker_inflight",
	)
	_streaming_worker_demand_dirty = true
	_object_presentation_backend.queue_object_presentation_request(
		chunk_coord,
		packet,
		_layered_object_asset_catalog.get_tree_native_metrics(),
		_layered_object_asset_catalog.get_rock_native_metrics(),
		_layered_object_asset_catalog.get_native_params(
			living_flora_enabled,
			spiky_flora_enabled,
		),
		_layered_object_asset_catalog.get_catalog_generation(),
		_generation_epoch,
		revision,
		_chunk_request_priority(chunk_coord),
		_object_presentation_compute_priority_class(chunk_coord),
	)


func _object_presentation_compute_priority_class(chunk_coord: Vector2i) -> int:
	if _is_chunk_desired(chunk_coord) \
			or _chunk_views.has(chunk_coord) \
			or _pending_publish_queue.has(chunk_coord) \
			or chunk_coord == _active_publish_chunk:
		return WorldChunkPacketBackend.PRIORITY_CLASS_REVEAL
	return WorldChunkPacketBackend.PRIORITY_CLASS_STREAMING


func _drain_completed_object_presentation_buffers(max_count: int) -> void:
	var drained: Array[Dictionary] = \
		_object_presentation_backend.drain_completed_object_presentation_buffers(max_count)
	for result: Dictionary in drained:
		if int(result.get("epoch", -1)) != _generation_epoch:
			continue
		var chunk_coord: Vector2i = _canonicalize_chunk_coord(
			result.get("target_chunk", Vector2i.ZERO) as Vector2i,
		)
		var revision: int = int(result.get("revision", -1))
		if revision != int(_object_presentation_revision_by_chunk.get(chunk_coord, -2)):
			continue
		if revision == int(_object_presentation_inflight_chunks.get(chunk_coord, -3)):
			_object_presentation_inflight_chunks.erase(chunk_coord)
		if int(result.get("catalog_generation", -1)) \
				!= _layered_object_asset_catalog.get_catalog_generation():
			# A completed old-catalog payload is stale, but it must also release
			# inflight ownership and schedule current-catalog work. Silently dropping
			# it would leave this revision permanently waiting.
			_object_presentation_retry_by_chunk[chunk_coord] = {
				"revision": revision,
				"attempts": 0,
				"next_retry_msec": Time.get_ticks_msec(),
				"message": "object presentation catalog generation changed",
				"terminal": false,
			}
			continue
		_object_presentation_worker_elapsed_ms_last = float(result.get("worker_elapsed_ms", 0.0))
		_object_presentation_worker_elapsed_ms_max_total = maxf(
			_object_presentation_worker_elapsed_ms_max_total,
			_object_presentation_worker_elapsed_ms_last,
		)
		_object_presentation_request_to_complete_ms_last = float(
			result.get("request_to_complete_ms", 0.0),
		)
		_object_presentation_request_to_complete_ms_max_total = maxf(
			_object_presentation_request_to_complete_ms_max_total,
			_object_presentation_request_to_complete_ms_last,
		)
		if not bool(result.get("success", false)):
			_record_object_presentation_failure(
				chunk_coord,
				revision,
				str(result.get("message", "unknown native object presentation error")),
			)
			continue
		_object_presentation_retry_by_chunk.erase(chunk_coord)
		_object_presentation_terminal_fallback_by_chunk.erase(chunk_coord)
		if _base_chunk_packets.has(chunk_coord):
			_object_presentation_results_by_chunk[chunk_coord] = result
			_readiness_tracker.mark_layer(
				chunk_coord,
				&"objects",
				&"waiting",
				&"object_presentation_cpu_ready_not_staged",
			)
			if _chunk_views.has(chunk_coord) or _is_chunk_source_desired(chunk_coord):
				# Drain owns immutable CPU truth only. The coordinate is a lightweight
				# priority token; acquire/begin/recycled-owner cleanup happens in the
				# object FrameBudgetDispatcher, never in this up-to-24-result loop.
				_queue_hot_object_prestage(chunk_coord)
		elif _warm_base_chunk_packet_cache.has(chunk_coord):
			_store_warm_object_presentation(chunk_coord, result)


func _record_object_presentation_failure(
		chunk_coord: Vector2i,
		revision: int,
		message: String,
) -> void:
	if revision != int(_object_presentation_revision_by_chunk.get(chunk_coord, -2)):
		return
	_object_presentation_results_by_chunk.erase(chunk_coord)
	_erase_warm_object_presentation(chunk_coord)
	_object_presentation_failure_count_total += 1
	var previous: Dictionary = _object_presentation_retry_by_chunk.get(chunk_coord, { }) as Dictionary
	var attempts: int = 1
	if int(previous.get("revision", -1)) == revision:
		attempts = int(previous.get("attempts", 0)) + 1
	var terminal: bool = attempts > OBJECT_PRESENTATION_MAX_RETRY_ATTEMPTS
	_object_presentation_retry_by_chunk[chunk_coord] = {
		"revision": revision,
		"attempts": attempts,
		"next_retry_msec": Time.get_ticks_msec() + OBJECT_PRESENTATION_RETRY_DELAY_MSEC,
		"message": message,
		"terminal": terminal,
	}
	if terminal:
		_object_presentation_terminal_failure_count += 1
		_object_presentation_retry_by_chunk.erase(chunk_coord)
		_object_presentation_terminal_fallback_by_chunk[chunk_coord] = revision
		_evict_hot_object_presentation(chunk_coord)
		push_error(
			"WorldStreamer native object presentation failed for chunk %s revision %d after %d attempts; using the compatibility recovery path: %s" % [
				str(chunk_coord),
				revision,
				attempts,
				message,
			],
		)
		# Compatibility recovery may allocate its complete legacy object graph.
		# Queue it as one exceptional dispatcher phase instead of doing that work
		# from result drain / streaming tick.
		if _chunk_views.has(chunk_coord):
			_queue_object_packet_visual_upload(chunk_coord)
	else:
		push_warning(
			"WorldStreamer object presentation retry %d/%d for chunk %s revision %d: %s" % [
				attempts,
				OBJECT_PRESENTATION_MAX_RETRY_ATTEMPTS,
				str(chunk_coord),
				revision,
				message,
			],
		)


func _try_apply_terminal_object_presentation_fallback(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var revision: int = int(
		_object_presentation_terminal_fallback_by_chunk.get(chunk_coord, -1),
	)
	if revision < 0:
		return false
	if revision != int(_object_presentation_revision_by_chunk.get(chunk_coord, -2)):
		_object_presentation_terminal_fallback_by_chunk.erase(chunk_coord)
		return false
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if chunk_view == null:
		return false
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty() and _warm_base_chunk_packet_cache.has(chunk_coord):
		packet = _diff_store.apply_to_packet(
			_warm_base_chunk_packet_cache.get(chunk_coord, { }) as Dictionary,
		)
	if packet.is_empty() or not chunk_view.apply_terminal_object_presentation_fallback(packet):
		return false
	_object_presentation_terminal_fallback_by_chunk.erase(chunk_coord)
	_object_presentation_retry_by_chunk.erase(chunk_coord)
	_object_presentation_results_by_chunk.erase(chunk_coord)
	_drop_object_packet_visual_upload(chunk_coord)
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"objects",
		&"ready",
		&"object_presentation_committed",
	)
	_finalize_pending_chunk_visibility(chunk_coord)
	return true


func _retry_failed_object_presentation_builds(max_count: int) -> void:
	if max_count <= 0 or _object_presentation_retry_by_chunk.is_empty():
		return
	var candidates: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _object_presentation_retry_by_chunk.keys():
		candidates.append(chunk_coord_variant as Vector2i)
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return _chunk_request_priority(a) < _chunk_request_priority(b)
	)
	var now_msec: int = Time.get_ticks_msec()
	var queued_count: int = 0
	for chunk_coord: Vector2i in candidates:
		if queued_count >= max_count:
			break
		var retry: Dictionary = _object_presentation_retry_by_chunk.get(chunk_coord, { }) as Dictionary
		var revision: int = int(retry.get("revision", -1))
		if revision != int(_object_presentation_revision_by_chunk.get(chunk_coord, -2)):
			_object_presentation_retry_by_chunk.erase(chunk_coord)
			continue
		if bool(retry.get("terminal", false)) \
				or now_msec < int(retry.get("next_retry_msec", 0)):
			continue
		if _object_presentation_results_by_chunk.has(chunk_coord):
			_object_presentation_retry_by_chunk.erase(chunk_coord)
			continue
		if _object_presentation_inflight_chunks.has(chunk_coord) \
				or not _is_chunk_source_desired(chunk_coord):
			continue
		var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
		if packet.is_empty() and _warm_base_chunk_packet_cache.has(chunk_coord):
			packet = _diff_store.apply_to_packet(
				_warm_base_chunk_packet_cache.get(chunk_coord, { }) as Dictionary,
			)
		if packet.is_empty():
			continue
		_request_object_presentation_build(chunk_coord, packet, false)
		if _object_presentation_inflight_chunks.has(chunk_coord):
			retry["next_retry_msec"] = 1 << 60
			_object_presentation_retry_by_chunk[chunk_coord] = retry
			queued_count += 1


func _stage_ready_object_presentation(chunk_coord: Vector2i, chunk_view: ChunkView) -> bool:
	if chunk_view == null or not _object_presentation_results_by_chunk.has(chunk_coord):
		return false
	var result: Dictionary = _object_presentation_results_by_chunk.get(chunk_coord, { }) as Dictionary
	# Production live chunks use the same world-parented transaction as hidden
	# prestage. Besides preserving hot-cache identity, this lets them acquire a
	# boot-prepared envelope instead of allocating a ChunkView-local graph on the
	# reveal-critical frame. Empty/suppressed packets fall through to the small
	# compatibility staging path because they need no GPU-resident layer.
	if not _get_current_hot_object_entry(chunk_coord).is_empty() \
			or _stage_hot_object_presentation(chunk_coord, result):
		_drop_hot_object_prestage(chunk_coord)
		_object_packet_visual_priority_dirty = true
		_queue_object_packet_visual_upload(chunk_coord)
		return true
	if not chunk_view.stage_object_presentation_result(result, _layered_object_asset_catalog):
		return false
	_drop_hot_object_prestage(chunk_coord)
	_object_packet_visual_priority_dirty = true
	_queue_object_packet_visual_upload(chunk_coord)
	return true


## Streaming/publish-side handoff for a view that just became a reveal frontier.
## This method is deliberately queue-only: it is also the re-entry point for a
## terminal fallback whose previous view disappeared before its dispatcher turn.
func _queue_object_presentation_for_live_view(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _chunk_views.has(chunk_coord):
		return false
	if not _get_current_hot_object_entry(chunk_coord).is_empty():
		_queue_object_packet_visual_upload(chunk_coord)
	elif _object_presentation_terminal_fallback_by_chunk.has(chunk_coord):
		_queue_object_packet_visual_upload(chunk_coord)
	elif _object_presentation_results_by_chunk.has(chunk_coord):
		_queue_hot_object_prestage(chunk_coord)
	else:
		return false
	# A hidden prestage token may already have been focused as class 2. Creating
	# its live ChunkView promotes it to class 0 without inserting a duplicate.
	_object_packet_visual_priority_dirty = true
	return true


func _invalidate_grass_scatter(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_drop_grass_scatter_visual_upload(chunk_coord)
	_grass_scatter_results_by_chunk.erase(chunk_coord)
	_erase_warm_grass_scatter(chunk_coord)
	_grass_scatter_retry_by_chunk.erase(chunk_coord)
	_grass_scatter_next_revision += 1
	_grass_scatter_revision_by_chunk[chunk_coord] = _grass_scatter_next_revision


func _current_grass_scatter_revision(chunk_coord: Vector2i) -> int:
	if not _grass_scatter_revision_by_chunk.has(chunk_coord):
		_grass_scatter_next_revision += 1
		_grass_scatter_revision_by_chunk[chunk_coord] = _grass_scatter_next_revision
	return int(_grass_scatter_revision_by_chunk.get(chunk_coord, -1))


func _stage_cached_grass_scatter(
		chunk_coord: Vector2i,
		chunk_view: ChunkView,
) -> bool:
	if chunk_view == null or not _grass_scatter_results_by_chunk.has(chunk_coord):
		return false
	var result: Dictionary = _grass_scatter_results_by_chunk.get(chunk_coord, { }) as Dictionary
	if result.is_empty() \
			or int(result.get("epoch", -1)) != _generation_epoch \
			or int(result.get("revision", -1)) \
					!= int(_grass_scatter_revision_by_chunk.get(chunk_coord, -2)):
		_grass_scatter_results_by_chunk.erase(chunk_coord)
		return false
	if chunk_view.stage_grass_scatter_result(result):
		_queue_grass_scatter_visual_upload(chunk_coord)
		return true
	return false


func _request_grass_scatter_build(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	var packet: Dictionary = _chunk_packets.get(chunk_coord, { }) as Dictionary
	if packet.is_empty() or not _is_chunk_source_desired(chunk_coord):
		return
	if chunk_view != null and _stage_cached_grass_scatter(chunk_coord, chunk_view):
		return
	if _grass_scatter_results_by_chunk.has(chunk_coord):
		return
	var retry_state: Dictionary = _grass_scatter_retry_by_chunk.get(chunk_coord, { }) as Dictionary
	if Time.get_ticks_msec() < int(retry_state.get("not_before_msec", 0)):
		return
	if chunk_view == null \
			and _grass_scatter_inflight_chunks.size() \
					>= GRASS_SCATTER_MAX_BACKGROUND_INFLIGHT:
		return
	var revision: int = _current_grass_scatter_revision(chunk_coord)
	if int(_grass_scatter_inflight_chunks.get(chunk_coord, -1)) == revision:
		return
	if not _has_loaded_mountain_halo_sources(chunk_coord):
		return
	_ensure_grass_scatter_sources()
	_grass_scatter_inflight_chunks[chunk_coord] = revision
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"grass",
		&"waiting",
		&"grass_worker_inflight",
	)
	_streaming_worker_demand_dirty = true
	var mountain_halo: Dictionary = _get_cached_mountain_solid_halo(chunk_coord)
	_grass_scatter_backend.queue_grass_scatter_request(
		chunk_coord,
		int(packet.get("world_seed", world_seed)),
		packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array,
		packet.get("lake_flags", PackedByteArray()) as PackedByteArray,
		mountain_halo.get("halo", PackedByteArray()) as PackedByteArray,
		MOUNTAIN_HALO_MASK_RADIUS_TILES,
		_grass_scatter_params,
		_generation_epoch,
		revision,
		_chunk_request_priority(chunk_coord),
	)


func _drop_grass_scatter_visual_upload(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if _pending_grass_scatter_visual_upload_set.has(chunk_coord):
		_pending_grass_scatter_visual_upload_set.erase(chunk_coord)
		var removed_index: int = int(
			_pending_grass_scatter_visual_upload_index_by_chunk.get(chunk_coord, -1)
		)
		_pending_grass_scatter_visual_upload_index_by_chunk.erase(chunk_coord)
		if removed_index >= 0 \
				and removed_index < _pending_grass_scatter_visual_upload_chunks.size():
			var last_index: int = _pending_grass_scatter_visual_upload_chunks.size() - 1
			if removed_index != last_index:
				var moved_coord: Vector2i = \
						_pending_grass_scatter_visual_upload_chunks[last_index]
				_pending_grass_scatter_visual_upload_chunks[removed_index] = moved_coord
				_pending_grass_scatter_visual_upload_index_by_chunk[moved_coord] = removed_index
			_pending_grass_scatter_visual_upload_chunks.pop_back()
	if _focused_grass_scatter_visual_upload_chunk == chunk_coord:
		_focused_grass_scatter_visual_upload_chunk = INVALID_CHUNK_COORD
	_grass_scatter_inflight_chunks.erase(chunk_coord)
	_streaming_worker_demand_dirty = true


## Completion-biased nearest-first selection. Once a chunk owns the lane it
## keeps it until COMMIT, avoiding a field of half-built invisible grass graphs.
func _take_next_grass_scatter_visual_upload() -> Vector2i:
	if _pending_grass_scatter_visual_upload_chunks.is_empty():
		_focused_grass_scatter_visual_upload_chunk = INVALID_CHUNK_COORD
		return INVALID_CHUNK_COORD
	if _focused_grass_scatter_visual_upload_chunk != INVALID_CHUNK_COORD \
			and _pending_grass_scatter_visual_upload_set.has(
				_focused_grass_scatter_visual_upload_chunk,
			):
		return _focused_grass_scatter_visual_upload_chunk
	var selected: Vector2i = _pending_grass_scatter_visual_upload_chunks[0]
	var best_priority: int = _chunk_request_priority(selected)
	for index: int in range(1, _pending_grass_scatter_visual_upload_chunks.size()):
		var candidate: Vector2i = _pending_grass_scatter_visual_upload_chunks[index]
		var priority: int = _chunk_request_priority(candidate)
		if priority < best_priority:
			selected = candidate
			best_priority = priority
	_focused_grass_scatter_visual_upload_chunk = selected
	return selected


func _drain_completed_grass_scatter_buffers(max_count: int) -> void:
	var drained: Array[Dictionary] = _grass_scatter_backend.drain_completed_grass_scatter_buffers(max_count)
	for result: Dictionary in drained:
		if int(result.get("epoch", -1)) != _generation_epoch:
			continue
		var chunk_coord: Vector2i = _canonicalize_chunk_coord(
			result.get("target_chunk", Vector2i.ZERO) as Vector2i,
		)
		var revision: int = int(result.get("revision", -1))
		if revision != int(_grass_scatter_revision_by_chunk.get(chunk_coord, -2)):
			continue
		_grass_scatter_worker_elapsed_ms_last = float(result.get("worker_elapsed_ms", 0.0))
		_grass_scatter_worker_elapsed_ms_max_total = maxf(
			_grass_scatter_worker_elapsed_ms_max_total,
			_grass_scatter_worker_elapsed_ms_last,
		)
		_grass_scatter_request_to_complete_ms_last = float(
			result.get("request_to_complete_ms", 0.0),
		)
		_grass_scatter_request_to_complete_ms_max_total = maxf(
			_grass_scatter_request_to_complete_ms_max_total,
			_grass_scatter_request_to_complete_ms_last,
		)
		if revision == int(_grass_scatter_inflight_chunks.get(chunk_coord, -3)):
			_grass_scatter_inflight_chunks.erase(chunk_coord)
		if not bool(result.get("success", false)):
			var previous_retry: Dictionary = _grass_scatter_retry_by_chunk.get(
				chunk_coord,
				{ },
			) as Dictionary
			var failure_count: int = int(previous_retry.get("failure_count", 0)) + 1
			var retry_delay_msec: int = mini(
				GRASS_SCATTER_RETRY_MAX_DELAY_MSEC,
				GRASS_SCATTER_RETRY_BASE_DELAY_MSEC * (1 << mini(failure_count - 1, 4)),
			)
			_grass_scatter_retry_by_chunk[chunk_coord] = {
				"failure_count": failure_count,
				"not_before_msec": Time.get_ticks_msec() + retry_delay_msec,
			}
			# Avoid a permanent poisoned cache and avoid an unbounded tight retry
			# loop. Transient native failures retry with capped exponential backoff.
			if failure_count <= 3 or failure_count % 16 == 0:
				push_warning(
					"WorldStreamer grass scatter build failed for chunk %s (attempt %d, retry in %d ms): %s" % [
						str(chunk_coord),
						failure_count,
						retry_delay_msec,
						str(result.get("message", "unknown native grass scatter error")),
					],
				)
			continue
		_grass_scatter_retry_by_chunk.erase(chunk_coord)
		# Keep immutable CPU output even when the view does not exist yet. Publish
		# can attach it immediately; warm packet residency decides whether a
		# completion racing source eviction is retained or discarded.
		if _is_chunk_source_desired(chunk_coord):
			_grass_scatter_results_by_chunk[chunk_coord] = result
			_readiness_tracker.mark_layer(
				chunk_coord,
				&"grass",
				&"waiting",
				&"grass_cpu_ready_not_staged",
			)
		elif _warm_base_chunk_packet_cache.has(chunk_coord):
			_store_warm_grass_scatter(chunk_coord, result)
		else:
			continue
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view == null or not _should_materialize_chunk(chunk_coord):
			continue
		_stage_cached_grass_scatter(chunk_coord, chunk_view)


func _retry_failed_grass_scatter_builds(max_count: int) -> void:
	if max_count <= 0 or _grass_scatter_retry_by_chunk.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	var queued_count: int = 0
	for chunk_coord_variant: Variant in _grass_scatter_retry_by_chunk.keys():
		if queued_count >= max_count:
			return
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		var retry_state: Dictionary = _grass_scatter_retry_by_chunk.get(
			chunk_coord,
			{ },
		) as Dictionary
		if now_msec < int(retry_state.get("not_before_msec", 0)):
			continue
		if not _is_chunk_source_desired(chunk_coord) or not _chunk_packets.has(chunk_coord):
			_grass_scatter_retry_by_chunk.erase(chunk_coord)
			continue
		if _grass_scatter_results_by_chunk.has(chunk_coord):
			_grass_scatter_retry_by_chunk.erase(chunk_coord)
			continue
		var revision: int = _current_grass_scatter_revision(chunk_coord)
		if int(_grass_scatter_inflight_chunks.get(chunk_coord, -1)) == revision:
			continue
		_request_grass_scatter_build(chunk_coord)
		if int(_grass_scatter_inflight_chunks.get(chunk_coord, -1)) == revision:
			queued_count += 1


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
	# The mode is authored-envelope static, never current-zoom dependent. A
	# fractional profile keeps per-stripe shadows for exact LOD identity; the
	# checked-in full-detail profile can use one fixed-z shadow batch per chunk.
	_grass_directional_shadow_consolidation_enabled = \
			_grass_lod_min_fraction >= 0.9999


## Exactly one bounded GPU phase per callback. FrameBudgetDispatcher may call
## this again while its measured/predicted lane still fits; every phase
## boundary remains visible to the budget instead of one 64-stripe black box.
func _grass_scatter_visual_apply_tick() -> bool:
	var chunk_coord: Vector2i = _take_next_grass_scatter_visual_upload()
	if chunk_coord == INVALID_CHUNK_COORD:
		return false
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if chunk_view == null or not _should_materialize_chunk(chunk_coord):
		_drop_grass_scatter_visual_upload(chunk_coord)
		return not _pending_grass_scatter_visual_upload_chunks.is_empty()
	_ensure_grass_scatter_sources()
	var grass_started: int = WorldPerfProbe.begin()
	var advanced: bool = chunk_view.apply_pending_grass_scatter_visual_phase(
		_grass_scatter_atlas,
		_grass_scatter_material,
		_grass_shadow_atlas,
		_grass_shadow_atlas_material,
		_grass_shadow_material,
		_grass_spore_material,
		_grass_directional_shadow_consolidation_enabled,
	)
	WorldPerfProbe.end("WorldStreamer.visual_upload.grass_scatter_phase", grass_started)
	if not advanced or not chunk_view.has_pending_grass_scatter_visual():
		if advanced:
			chunk_view.set_grass_scatter_lod_fraction(_grass_lod_fraction)
			if _ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
				chunk_view.update_mid_ladder_z(_ladder_anchor_stripe)
		_drop_grass_scatter_visual_upload(chunk_coord)
		if chunk_view.is_grass_scatter_presentation_committed():
			_readiness_tracker.mark_layer(
				chunk_coord,
				&"grass",
				&"ready",
				&"grass_presentation_committed",
			)
	return not _pending_grass_scatter_visual_upload_chunks.is_empty()


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
		_sync_mountain_cavity_skylight_field_chunk(chunk_coord, chunk_view)
		var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
		_mountain_native_mask_visual_upload_count_total += 1
		_mountain_native_mask_visual_upload_count_last_tick += 1
		_mountain_native_mask_visual_upload_elapsed_ms_last = elapsed_ms
		_mountain_native_mask_visual_upload_elapsed_ms_max_total = maxf(
			_mountain_native_mask_visual_upload_elapsed_ms_max_total,
			elapsed_ms,
		)
		_mountain_native_mask_visual_upload_last_chunk = chunk_coord
		_readiness_tracker.mark_layer(
			chunk_coord,
			&"mountain_mask",
			&"ready",
			&"mountain_mask_visual_ready",
		)
		_readiness_tracker.mark_layer(
			chunk_coord,
			&"roof_cavity",
			&"ready",
			&"roof_cavity_visual_ready",
		)
		_finalize_pending_chunk_visibility(chunk_coord)
		if Time.get_ticks_usec() - tick_started_usec >= budget_usec:
			_try_commit_mountain_roof_reveal_selector_generation()
			return false
	_try_commit_mountain_roof_reveal_selector_generation()
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
			_readiness_tracker.mark_layer(
				chunk_coord,
				&"terrain_edge_mask",
				&"ready",
				&"terrain_edge_mask_visual_ready",
			)
			_finalize_pending_chunk_visibility(chunk_coord)
			if Time.get_ticks_usec() - tick_started_usec >= budget_usec:
				return false
		else:
			_finalize_pending_chunk_visibility(chunk_coord)
	return false


func _defer_object_presentation_reveal(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_object_presentation_reveal_not_before_frame_by_chunk[chunk_coord] = maxi(
		int(_object_presentation_reveal_not_before_frame_by_chunk.get(chunk_coord, 0)),
		int(Engine.get_process_frames()) + 1,
	)


func _is_object_presentation_reveal_deferred(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _object_presentation_reveal_not_before_frame_by_chunk.has(chunk_coord):
		return false
	if int(Engine.get_process_frames()) < int(
		_object_presentation_reveal_not_before_frame_by_chunk.get(chunk_coord, 0),
	):
		return true
	_object_presentation_reveal_not_before_frame_by_chunk.erase(chunk_coord)
	return false


func _begin_object_presentation_visual_lane_callback() -> int:
	var now_usec: int = Time.get_ticks_usec()
	var process_frame: int = int(Engine.get_process_frames())
	if process_frame != _object_presentation_visual_lane_frame:
		_object_presentation_visual_lane_frame = process_frame
		_object_presentation_visual_lane_started_usec = now_usec
		_object_presentation_visual_lane_callback_count = 0
		_object_presentation_allocation_callback_count = 0
	_object_presentation_visual_lane_callback_count += 1
	return now_usec


## Returns true only for a known-safe next callback whose conservative
## lookahead still fits the lane's own per-frame budget. FrameBudgetDispatcher
## also enforces the registered 0.75 ms cap, but its previous-step estimate
## cannot safely predict a transition between heterogeneous object phases.
func _can_continue_object_presentation_visual_lane(
		callback_started_usec: int,
		next_phase_lookahead_usec: int,
		expected_focus: Vector2i = INVALID_CHUNK_COORD,
) -> bool:
	if _object_presentation_visual_lane_callback_count \
			>= OBJECT_PRESENTATION_MAX_DISPATCH_CALLBACKS_PER_FRAME:
		return false
	if expected_focus != INVALID_CHUNK_COORD \
			and (_object_packet_visual_urgent_priority_dirty \
					or _focused_object_packet_visual_upload_chunk != expected_focus \
					or not _pending_object_packet_visual_upload_set.has(expected_focus)):
		return false
	var now_usec: int = Time.get_ticks_usec()
	var callback_elapsed_usec: int = maxi(0, now_usec - callback_started_usec)
	var lane_elapsed_usec: int = maxi(
		0,
		now_usec - _object_presentation_visual_lane_started_usec,
	)
	var predicted_next_usec: int = maxi(
		1,
		maxi(callback_elapsed_usec, next_phase_lookahead_usec),
	)
	return lane_elapsed_usec + predicted_next_usec \
			<= OBJECT_PRESENTATION_VISUAL_UPLOAD_BUDGET_USEC


func _record_object_presentation_allocation_measurement(
		family: StringName,
		elapsed_usec: int,
) -> void:
	if family == WorldObjectPacketLayer.PRESENTATION_PHASE_NONE:
		return
	_object_presentation_allocation_high_water_usec_by_family[family] = maxi(
		maxi(1, elapsed_usec),
		int(_object_presentation_allocation_high_water_usec_by_family.get(family, 0)),
	)


func _object_presentation_allocation_lookahead_usec(family: StringName) -> int:
	var high_water_usec: int = maxi(
		1,
		int(_object_presentation_allocation_high_water_usec_by_family.get(family, 1)),
	)
	return ceili(
		float(high_water_usec * OBJECT_PRESENTATION_ALLOCATION_LOOKAHEAD_NUMERATOR) \
				/ float(OBJECT_PRESENTATION_ALLOCATION_LOOKAHEAD_DENOMINATOR)
	) + OBJECT_PRESENTATION_ALLOCATION_LOOKAHEAD_FIXED_MARGIN_USEC


## Pure budget predicate kept separate from focus/revision guards so scheduler
## tests can deterministically inject high-water samples without relying on
## wall-clock resolution.
func _object_presentation_allocation_lookahead_fits_lane(
		lane_elapsed_usec: int,
		family: StringName,
) -> bool:
	return maxi(0, lane_elapsed_usec) \
			+ _object_presentation_allocation_lookahead_usec(family) \
			<= OBJECT_PRESENTATION_ALLOCATION_SOFT_BUDGET_USEC


func _can_continue_object_presentation_allocation_lane(
		callback_started_usec: int,
		family: StringName,
		expected_focus: Vector2i,
) -> bool:
	if _object_presentation_allocation_callback_count \
			>= OBJECT_PRESENTATION_MAX_ALLOCATION_CALLBACKS_PER_FRAME:
		return false
	if _object_packet_visual_urgent_priority_dirty \
			or _focused_object_packet_visual_upload_chunk != expected_focus \
			or not _pending_object_packet_visual_upload_set.has(expected_focus):
		return false
	var now_usec: int = Time.get_ticks_usec()
	var callback_elapsed_usec: int = maxi(0, now_usec - callback_started_usec)
	var lane_elapsed_usec: int = maxi(
		0,
		now_usec - _object_presentation_visual_lane_started_usec,
	)
	# The current sample is already included in the high-water table, but retain
	# the direct comparison for defensive callers that invoke this helper alone.
	var predicted_next_usec: int = maxi(
		callback_elapsed_usec,
		_object_presentation_allocation_lookahead_usec(family),
	)
	return lane_elapsed_usec + predicted_next_usec \
			<= OBJECT_PRESENTATION_ALLOCATION_SOFT_BUDGET_USEC


## One main-thread phase per dispatcher callback. Only homogeneous bounded
## continuations return true: an incomplete priority scan, an incremental begin
## phase with no Node/GPU work, warmed sub-slices with one unchanged phase hint,
## or measured allocation-only reservations of one unchanged family. Cold fixed
## graphs, every family's first allocation, allocation-to-upload transitions,
## COMPLETE, cache commit, and FINALIZE always yield to the next process frame.
func _object_presentation_visual_apply_tick() -> bool:
	var lane_callback_started_usec: int = \
			_begin_object_presentation_visual_lane_callback()
	var repair_focus_is_valid: bool = \
			_focused_object_packet_visual_upload_chunk != INVALID_CHUNK_COORD \
			and _pending_object_packet_visual_upload_set.has(
				_focused_object_packet_visual_upload_chunk,
			)
	if _object_packet_visual_queue_repair_needed \
			and not repair_focus_is_valid \
			and _pending_object_packet_visual_upload_set.size() \
					< OBJECT_PRESENTATION_VISUAL_QUEUE_MAX_TOKENS:
		var repair_started: int = WorldPerfProbe.begin()
		_repair_one_object_packet_visual_queue_token()
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_priority_repair",
			repair_started,
		)
		return false
	if _pending_object_packet_visual_upload_chunks.is_empty():
		_object_packet_visual_selection_phase_prepared = false
		if _pending_hot_object_prestage_chunks.is_empty():
			return false
		# Queue-invariant repair only. Selection and envelope allocation are never
		# combined: the normal priority phase below owns the O(queue) scan later.
		var priority_repair_started: int = WorldPerfProbe.begin()
		_queue_object_packet_visual_upload(_pending_hot_object_prestage_chunks[0])
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_priority_repair",
			priority_repair_started,
		)
		return false

	var focused_selection_is_valid: bool = \
			_focused_object_packet_visual_upload_chunk != INVALID_CHUNK_COORD \
			and _pending_object_packet_visual_upload_set.has(
				_focused_object_packet_visual_upload_chunk,
			)
	if _object_packet_visual_selection_phase_prepared and not focused_selection_is_valid:
		_object_packet_visual_selection_phase_prepared = false
	if _object_packet_visual_selection_phase_prepared \
			and _object_packet_visual_urgent_priority_dirty:
		# A newly-live reveal frontier is the one exception to the prepared-work
		# guarantee: it invalidates a hidden selection before any heavy phase runs.
		_object_packet_visual_selection_phase_prepared = false
	# Priority refresh can scan dozens of tokens. It must not share a callback
	# with Node/RenderingServer allocation or raw upload. A token added after this
	# refresh may dirty priorities again, but one prepared phase is guaranteed to
	# run before another equal/lower-urgency refresh, so continuous streaming
	# cannot starve the focused transaction.
	if not _object_packet_visual_selection_phase_prepared \
			and (_object_packet_visual_priority_scan_active \
					or _object_packet_visual_urgent_priority_dirty \
					or not focused_selection_is_valid):
		var priority_started: int = WorldPerfProbe.begin()
		var selection_completed: bool = _advance_object_packet_visual_priority_scan()
		_object_packet_visual_selection_phase_prepared = selection_completed \
				and _focused_object_packet_visual_upload_chunk != INVALID_CHUNK_COORD \
				and _pending_object_packet_visual_upload_set.has(
					_focused_object_packet_visual_upload_chunk,
				)
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_priority_refresh",
			priority_started,
		)
		if not selection_completed:
			return _can_continue_object_presentation_visual_lane(
				lane_callback_started_usec,
				OBJECT_PRESENTATION_PRIORITY_SCAN_SOFT_BUDGET_USEC,
			)
		# Selection commit is the boundary before any Node/RenderingServer work.
		# Even a cheap final scan slice may not pull envelope allocation into the
		# same process frame.
		return false

	var chunk_coord: Vector2i = INVALID_CHUNK_COORD
	if _object_packet_visual_selection_phase_prepared:
		_object_packet_visual_selection_phase_prepared = false
		chunk_coord = _focused_object_packet_visual_upload_chunk
		_object_packet_visual_dispatch_turn += 1
	elif focused_selection_is_valid:
		# Same/lower urgency dirtiness (new source tokens or player-distance
		# changes) cannot interrupt an owned atomic transaction.
		chunk_coord = _focused_object_packet_visual_upload_chunk
		_object_packet_visual_dispatch_turn += 1
	if chunk_coord == INVALID_CHUNK_COORD:
		return false
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if _object_presentation_terminal_fallback_by_chunk.has(chunk_coord):
		# The compatibility renderer is exceptional but still owns an explicit
		# dispatcher phase: it may allocate Nodes and rebuild authored objects.
		if chunk_view == null:
			_drop_object_packet_visual_upload(chunk_coord)
			return false
		var fallback_started: int = WorldPerfProbe.begin()
		_try_apply_terminal_object_presentation_fallback(chunk_coord)
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_terminal_fallback",
			fallback_started,
		)
		return false
	if _pending_hot_object_prestage_set.has(chunk_coord):
		var envelope_started: int = WorldPerfProbe.begin()
		_stage_pending_hot_object_presentation(chunk_coord)
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_envelope",
			envelope_started,
		)
		return false
	var hot_entry: Dictionary = _get_current_hot_object_entry(chunk_coord)
	if not hot_entry.is_empty():
		var hot_layer: WorldObjectPacketLayer = hot_entry.get(
			"layer",
			null,
		) as WorldObjectPacketLayer
		if hot_layer == null or not is_instance_valid(hot_layer):
			_evict_hot_object_presentation(chunk_coord)
			return false
		if bool(hot_entry.get("envelope_pending", false)):
			# An acquired shell is already owned/accounted by this revision and must
			# finish even if source-only admission becomes backpressured meanwhile.
			# Live/reveal priority still comes from the shared focused queue.
			var envelope_started_usec: int = WorldPerfProbe.begin()
			if not hot_layer.is_presentation_envelope_ready():
				var fixed_phase_advanced: bool = \
						hot_layer.prepare_next_presentation_envelope_phase(
							_layered_object_asset_catalog,
						)
				if not fixed_phase_advanced \
						and not hot_layer.is_presentation_envelope_ready():
					_evict_hot_object_presentation(chunk_coord)
					_record_object_presentation_failure(
						chunk_coord,
						int(_object_presentation_revision_by_chunk.get(chunk_coord, -1)),
						"incremental presentation envelope could not advance",
					)
				WorldPerfProbe.end(
					"WorldStreamer.visual_upload.object_packet_envelope",
					envelope_started_usec,
				)
				return false
			var result: Dictionary = _object_presentation_results_by_chunk.get(
				chunk_coord,
				{ },
			) as Dictionary
			var begin_started_usec: int = WorldPerfProbe.begin()
			var began_or_advanced: bool = false
			if not bool(hot_entry.get("begin_started", false)):
				began_or_advanced = hot_layer.begin_incremental_presentation_result(
					result,
					_layered_object_asset_catalog,
				)
				if began_or_advanced:
					hot_entry["begin_started"] = true
					_hot_object_presentation_layers[chunk_coord] = hot_entry
			else:
				began_or_advanced = hot_layer.advance_incremental_presentation_begin_phase()
			WorldPerfProbe.end(
				"WorldStreamer.visual_upload.object_packet_envelope.begin",
				begin_started_usec,
			)
			if not began_or_advanced:
				_evict_hot_object_presentation(chunk_coord)
				_record_object_presentation_failure(
					chunk_coord,
					int(_object_presentation_revision_by_chunk.get(chunk_coord, -1)),
					"prepared presentation envelope rejected worker buffers",
				)
				WorldPerfProbe.end(
					"WorldStreamer.visual_upload.object_packet_envelope",
					envelope_started_usec,
				)
				return false
			if not hot_layer.is_incremental_presentation_begin_complete():
				WorldPerfProbe.end(
					"WorldStreamer.visual_upload.object_packet_envelope",
					envelope_started_usec,
				)
				# Header/family begin phases only validate metadata and retain COW
				# buffers. They perform no Node, GPU, collider, or reveal work, so
				# another same-kind callback may use otherwise-idle lane budget.
				return _can_continue_object_presentation_visual_lane(
					lane_callback_started_usec,
					OBJECT_PRESENTATION_PRIORITY_SCAN_SOFT_BUDGET_USEC,
					chunk_coord,
				)
			_take_hot_object_entry(chunk_coord)
			hot_entry["envelope_pending"] = false
			var begun_reservation: Dictionary = hot_layer.get_hot_cache_reservation_weight()
			hot_entry["gpu_buffer_bytes"] = maxi(
				0,
				int(begun_reservation.get("gpu_buffer_bytes", 0)),
			)
			hot_entry["canvas_item_count"] = maxi(
				0,
				int(begun_reservation.get("canvas_item_count", 0)),
			)
			hot_entry["collider_count"] = maxi(
				0,
				int(begun_reservation.get("collider_count", 0)),
			)
			_add_hot_object_entry(chunk_coord, hot_entry)
			WorldPerfProbe.end(
				"WorldStreamer.visual_upload.object_packet_envelope",
				envelope_started_usec,
			)
			return false
		var presentation_is_ready: bool = bool(hot_entry.get("ready", false)) \
				or hot_layer.is_presentation_complete()
		if presentation_is_ready \
				and _ladder_anchor_stripe != LADDER_ANCHOR_UNSET \
				and int(hot_entry.get("ladder_anchor_stripe", LADDER_ANCHOR_UNSET)) \
						!= _ladder_anchor_stripe:
			# A depth-root migration can touch several band roots. It owns a
			# standalone phase so an unpredictable boundary crossing never shares a
			# callback with raw MultiMesh upload, allocation, adopt, or reveal.
			var anchor_phase_started: int = WorldPerfProbe.begin()
			hot_layer.update_ladder_z(_ladder_anchor_stripe)
			hot_entry["ladder_anchor_stripe"] = _ladder_anchor_stripe
			_hot_object_presentation_layers[chunk_coord] = hot_entry
			WorldPerfProbe.end(
				"WorldStreamer.visual_upload.object_packet_anchor_rebase",
				anchor_phase_started,
			)
			return false
		if presentation_is_ready:
			if chunk_view != null:
				# COMPLETE was produced by an earlier callback/frame. Adoption and the
				# atomic visibility+collision release are one FINALIZE phase; neither
				# can ever follow a raw upload in this callback.
				if _is_object_presentation_reveal_deferred(chunk_coord):
					return false
				var finalize_started: int = WorldPerfProbe.begin()
				var adopt_started: int = WorldPerfProbe.begin()
				var promoted: bool = _promote_hot_object_presentation(chunk_coord, chunk_view)
				WorldPerfProbe.end(
					"WorldStreamer.visual_upload.object_packet_adopt",
					adopt_started,
				)
				_drop_object_packet_visual_upload(chunk_coord)
				if promoted:
					var reveal_started: int = WorldPerfProbe.begin()
					_finalize_pending_chunk_visibility(chunk_coord)
					WorldPerfProbe.end(
						"WorldStreamer.visual_upload.object_packet_reveal",
						reveal_started,
					)
				WorldPerfProbe.end(
					"WorldStreamer.visual_upload.object_packet_finalize",
					finalize_started,
				)
				return false
			var cache_commit_started: int = WorldPerfProbe.begin()
			if not bool(hot_entry.get("ready", false)):
				_mark_hot_object_presentation_ready(chunk_coord)
			_drop_object_packet_visual_upload(chunk_coord)
			WorldPerfProbe.end(
				"WorldStreamer.visual_upload.object_packet_cache_commit",
				cache_commit_started,
			)
			return false
		if chunk_view == null and not _is_chunk_source_desired(chunk_coord):
			_evict_hot_object_presentation(chunk_coord)
			return false
		var next_phase_hint: StringName = \
				hot_layer.get_next_presentation_apply_phase_hint()
		if hot_layer.next_presentation_slice_requires_visual_slot_allocation():
			# One callback grows one family slot and cannot advance a raw-buffer
			# cursor. The first allocation of every family always yields because no
			# prior sample for this transaction can prove its cold path is warmed.
			var started_families: Dictionary = hot_entry.get(
				"allocation_started_families",
				{ },
			) as Dictionary
			var is_first_family_allocation: bool = not started_families.has(next_phase_hint)
			var allocation_probe_started: int = WorldPerfProbe.begin()
			var allocation_started_usec: int = Time.get_ticks_usec()
			var allocated: bool = hot_layer.apply_next_presentation_allocation_only()
			var allocation_elapsed_usec: int = maxi(
				1,
				Time.get_ticks_usec() - allocation_started_usec,
			)
			_object_presentation_allocation_callback_count += 1
			_record_object_presentation_allocation_measurement(
				next_phase_hint,
				allocation_elapsed_usec,
			)
			WorldPerfProbe.end(
				"WorldStreamer.visual_upload.object_packet_slice.slot_allocation",
				allocation_probe_started,
			)
			if not allocated:
				return false
			started_families[next_phase_hint] = true
			hot_entry["allocation_started_families"] = started_families
			_hot_object_presentation_layers[chunk_coord] = hot_entry
			if is_first_family_allocation:
				return false
			# Allocation and upload are never adjacent in one process frame. A
			# changed hint means either the family is fully reserved or the next
			# family owns a fresh first-yield boundary.
			if hot_layer.get_next_presentation_apply_phase_hint() != next_phase_hint:
				return false
			return _can_continue_object_presentation_allocation_lane(
				lane_callback_started_usec,
				next_phase_hint,
				chunk_coord,
			)
		var hot_started: int = WorldPerfProbe.begin()
		var phase_started_usec: int = Time.get_ticks_usec()
		if Time.get_ticks_usec() - phase_started_usec >= OBJECT_PRESENTATION_SLICE_SOFT_BUDGET_USEC:
			WorldPerfProbe.end("WorldStreamer.visual_upload.object_packet_slice", hot_started)
			return false
		var previous_slice_usec: int = 0
		var subslice_count: int = 0
		var created_visual_slot: bool = false
		while subslice_count < OBJECT_PRESENTATION_MAX_APPLY_SUBSLICES_PER_CALLBACK:
			var elapsed_usec: int = Time.get_ticks_usec() - phase_started_usec
			if subslice_count > 0 \
					and (elapsed_usec >= OBJECT_PRESENTATION_SLICE_SOFT_BUDGET_USEC \
							or elapsed_usec + previous_slice_usec \
									> OBJECT_PRESENTATION_SLICE_SOFT_BUDGET_USEC):
				break
			# Heterogeneous transitions are process-frame boundaries. In particular,
			# upload -> collider/next family/retire/commit cannot reuse an estimate
			# sampled from the previous phase, even if that previous slice was cheap.
			if subslice_count > 0 \
					and hot_layer.get_next_presentation_apply_phase_hint() \
							!= next_phase_hint:
				break
			var subslice_started_usec: int = Time.get_ticks_usec()
			var advanced: bool = hot_layer.apply_next_presentation_slice(1, 4, 1)
			previous_slice_usec = Time.get_ticks_usec() - subslice_started_usec
			subslice_count += 1
			if hot_layer.did_last_presentation_slice_create_visual_slot():
				created_visual_slot = true
				break
			if not advanced or hot_layer.is_presentation_complete():
				break
		if hot_layer.is_presentation_complete():
			# COMMIT makes a standalone layer internally visible. World-parented
			# staging must immediately retain the outer reveal gate until the later
			# adopt/reveal phases; collision stays disabled as well.
			hot_layer.set_hot_cache_resident(true)
			if chunk_view != null:
				_defer_object_presentation_reveal(chunk_coord)
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_slice.slot_allocation" \
					if created_visual_slot \
					else "WorldStreamer.visual_upload.object_packet_slice.warmed_or_upload",
			hot_started,
		)
		WorldPerfProbe.end("WorldStreamer.visual_upload.object_packet_slice", hot_started)
		if hot_layer.is_presentation_complete() \
				or created_visual_slot \
				or hot_layer.get_next_presentation_apply_phase_hint() != next_phase_hint:
			# COMPLETE must reach FINALIZE in a later process frame. A freshly
			# allocated slot and every heterogeneous phase transition likewise yield.
			return false
		return _can_continue_object_presentation_visual_lane(
			lane_callback_started_usec,
			OBJECT_PRESENTATION_SLICE_SOFT_BUDGET_USEC,
			chunk_coord,
		)

	if chunk_view == null:
		_drop_object_packet_visual_upload(chunk_coord)
		return false
	if not chunk_view.has_pending_object_presentation_apply() \
			or not chunk_view.has_staged_object_presentation_result():
		if _is_object_presentation_reveal_deferred(chunk_coord):
			return false
		var finalize_started: int = WorldPerfProbe.begin()
		_drop_object_packet_visual_upload(chunk_coord)
		_finalize_pending_chunk_visibility(chunk_coord)
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_finalize",
			finalize_started,
		)
		return false

	var object_started: int = WorldPerfProbe.begin()
	chunk_view.apply_pending_object_packet_visual()
	var apply_failure: String = chunk_view.take_object_presentation_apply_failure()
	if not apply_failure.is_empty():
		_drop_object_packet_visual_upload(chunk_coord)
		_record_object_presentation_failure(
			chunk_coord,
			int(_object_presentation_revision_by_chunk.get(chunk_coord, -1)),
			apply_failure,
		)
	elif chunk_view.is_object_presentation_complete():
		_readiness_tracker.mark_layer(
			chunk_coord,
			&"objects",
			&"ready",
			&"object_presentation_committed",
		)
		_defer_object_presentation_reveal(chunk_coord)
	WorldPerfProbe.end("WorldStreamer.visual_upload.object_packet_slice", object_started)
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
		_object_packet_visual_priority_dirty = true
		_rebuild_desired_chunk_cache()
	_sync_initial_loading_target()
	_update_grass_scatter_lod()
	_update_mid_ladder_anchor()


func _sync_initial_loading_target() -> void:
	if not _initial_loading_gate.is_active() \
			or _player_chunk_coord == INVALID_CHUNK_COORD:
		return
	if _initial_loading_gate.establish_target(
		_player_chunk_coord,
		_desired_visible_chunk_coords,
		_desired_source_chunk_coords,
		_current_stream_radius_chunks,
		_resolve_source_cache_radius_chunks(),
	):
		_initial_loading_readiness_cursor = 0
		_streaming_worker_demand_dirty = true


func _advance_initial_loading_readiness(max_checks: int) -> void:
	if max_checks <= 0 \
			or not _initial_loading_gate.is_active() \
			or not _initial_loading_gate.has_target() \
			or _initial_loading_gate.is_ready():
		return
	var target_coords: Array[Vector2i] = _initial_loading_gate.get_target_coords()
	if target_coords.is_empty():
		return
	var was_ready: bool = _initial_loading_gate.is_ready()
	var checks: int = mini(max_checks, target_coords.size())
	for _check_index: int in range(checks):
		if _initial_loading_readiness_cursor >= target_coords.size():
			_initial_loading_readiness_cursor = 0
		var chunk_coord: Vector2i = target_coords[_initial_loading_readiness_cursor]
		_initial_loading_readiness_cursor += 1
		_initial_loading_gate.observe_chunk_stage(
			chunk_coord,
			_get_initial_loading_chunk_stage(chunk_coord),
		)
	if not was_ready and _initial_loading_gate.is_ready():
		_initial_loading_gate.capture_ready_memory(
			int(Performance.get_monitor(Performance.MEMORY_STATIC)),
			int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		)


func _get_initial_loading_chunk_stage(chunk_coord: Vector2i) -> int:
	if not _chunk_packets.has(chunk_coord):
		return WorldInitialLoadingGate.STAGE_REQUESTED
	var stage: int = WorldInitialLoadingGate.STAGE_GENERATED
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if chunk_view == null or not chunk_view.is_terrain_cell_presentation_committed():
		return stage
	var mountain_halo: Dictionary = _mountain_solid_halo_cache.get(
		chunk_coord,
		{ },
	) as Dictionary
	if mountain_halo.is_empty():
		return stage
	if bool(mountain_halo.get("has_closed", false)) \
			and _get_ready_mountain_native_mask_result(chunk_coord).is_empty():
		return stage
	if not chunk_view.is_object_blocking_presentation_ready():
		return stage
	stage = WorldInitialLoadingGate.STAGE_GAMEPLAY_READY
	if chunk_view.is_mountain_native_mask_visual_pending() \
			or not chunk_view.is_object_presentation_complete():
		return stage
	if TERRAIN_EDGE_MASK_RUNTIME_ENABLED:
		var terrain_edge_halo: Dictionary = _terrain_edge_solid_halo_cache.get(
			chunk_coord,
			{ },
		) as Dictionary
		if terrain_edge_halo.is_empty():
			return stage
		if bool(terrain_edge_halo.get("has_shoreline", false)) \
				and (
					_get_ready_terrain_edge_mask_result(chunk_coord).is_empty()
					or chunk_view.is_terrain_edge_mask_visual_pending()
				):
			return stage
	if not chunk_view.is_grass_scatter_presentation_committed():
		return stage
	stage = WorldInitialLoadingGate.STAGE_PRESENTATION_READY
	if _initial_loading_gate.is_visible_target(chunk_coord):
		if not chunk_view.visible:
			return stage
	elif chunk_view.visible:
		return stage
	return WorldInitialLoadingGate.STAGE_RESERVE_READY


## Zoom-LOD травы: буфер чанка отсортирован native-кодом по важности (крупные
## пучки в голове), поэтому дальний зум режет хвост мелочи одним числом —
## visible_instance_count — без пересборки буфера.
## Якорь player-relative depth-лесенки: полоса ног игрока. При смене полосы
## (раз в DEPTH_STRIPE_PX пути по Y) каждый chunk-owner сдвигает один linear
## band root и переносит только полосы, пересёкшие две clamp-границы. Полного
## O(chunks * stripes) переприсваивания z здесь больше нет.
func _update_mid_ladder_anchor() -> void:
	var player: Player = PlayerAuthority.get_local_player()
	if player == null:
		return
	var anchor_stripe: int = WorldRuntimeConstants.depth_stripe_for_world_y(
		player.global_position.y + Player.PLAYER_FEET_OFFSET_PX,
	)
	if anchor_stripe == _ladder_anchor_stripe:
		return
	var previous_anchor_stripe: int = _ladder_anchor_stripe
	_ladder_anchor_stripe = anchor_stripe
	for chunk_coord_variant: Variant in _chunk_views.keys():
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		if previous_anchor_stripe != LADDER_ANCHOR_UNSET \
				and not _chunk_depth_ladder_can_change(
					chunk_coord,
					previous_anchor_stripe,
					anchor_stripe,
				):
			continue
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
		if chunk_view != null:
			chunk_view.update_mid_ladder_z(anchor_stripe)


func _chunk_depth_ladder_can_change(
		chunk_coord: Vector2i,
		previous_anchor_stripe: int,
		next_anchor_stripe: int,
) -> bool:
	var chunk_first_stripe: int = chunk_coord.y * WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK
	var chunk_last_stripe: int = \
			chunk_first_stripe + WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK - 1
	var half_range: int = WorldRuntimeConstants.DEPTH_LADDER_HALF_RANGE_STRIPES
	var stayed_north_clamped: bool = \
			chunk_last_stripe <= previous_anchor_stripe - half_range \
			and chunk_last_stripe <= next_anchor_stripe - half_range
	if stayed_north_clamped:
		return false
	var stayed_south_clamped: bool = \
			chunk_first_stripe >= previous_anchor_stripe + half_range \
			and chunk_first_stripe >= next_anchor_stripe + half_range
	return not stayed_south_clamped


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
	_sync_streaming_worker_demand()
	_prune_resident_source_packets()
	for packet_coord: Vector2i in _terrain_packet_support_chunk_coords:
		if not _chunk_packets.has(packet_coord):
			_restore_warm_chunk_packet(
				packet_coord,
				_is_chunk_source_desired(packet_coord),
			)
		if _chunk_packets.has(packet_coord) or _requested_chunks.has(packet_coord):
			continue
		_requested_chunks[packet_coord] = true
		if _is_chunk_source_desired(packet_coord):
			_readiness_tracker.mark_stage(packet_coord, &"requested")
			_readiness_tracker.mark_layer(
				packet_coord,
				&"packet",
				&"waiting",
				&"packet_generation_inflight",
			)
		_packet_backend.queue_packet_request(
			packet_coord,
			world_seed,
			world_version,
			_worldgen_settings_packed,
			_generation_epoch,
			_chunk_request_priority(packet_coord),
		)
	for desired_coord: Vector2i in _desired_source_chunk_coords:
		if _chunk_packets.has(desired_coord):
			if not _chunk_views.has(desired_coord) \
					and not _pending_publish_queue.has(desired_coord) \
					and desired_coord != _active_publish_chunk:
				_request_object_presentation_build(
					desired_coord,
					_chunk_packets.get(desired_coord, { }) as Dictionary,
					false,
				)
			if _should_materialize_chunk(desired_coord) \
					and not _pending_publish_queue.has(desired_coord) \
					and not _chunk_views.has(desired_coord):
				_pending_publish_queue.append(desired_coord)
				_readiness_tracker.mark_layer(
					desired_coord,
					&"terrain",
					&"waiting",
					&"terrain_publish_queued",
				)
			_sync_materialized_chunk_demand(desired_coord)
			continue


func _sync_materialized_chunk_demand(chunk_coord: Vector2i) -> void:
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if chunk_view == null or not chunk_view.is_terrain_cell_presentation_committed():
		return
	if _is_chunk_desired(chunk_coord):
		if chunk_view.visible:
			return
		_pending_chunk_visibility_after_mountain_visual[chunk_coord] = true
		_finalize_pending_chunk_visibility(chunk_coord)
		return
	_pending_chunk_visibility_after_mountain_visual.erase(chunk_coord)
	chunk_view.set_object_collision_active(false)
	chunk_view.visible = false
	_readiness_tracker.mark_stage(chunk_coord, &"presentation_ready")
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"visibility",
		&"not_applicable",
		&"outside_visible_demand",
	)


func _chunk_request_priority(chunk_coord: Vector2i) -> int:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		return 0
	return _chunk_distance_sq(_player_chunk_coord, chunk_coord)


func _sync_streaming_worker_demand() -> void:
	if not _streaming_worker_demand_dirty:
		return
	_streaming_worker_demand_dirty = false
	var packet_priorities: Dictionary = { }
	for packet_coord: Vector2i in _terrain_packet_support_chunk_coords:
		packet_priorities[packet_coord] = _chunk_request_priority(packet_coord)
	for removed_coord: Vector2i in _packet_backend.sync_packet_requests(
		_generation_epoch,
		packet_priorities,
	):
		_requested_chunks.erase(removed_coord)

	var grass_demand: Dictionary = { }
	for chunk_coord_variant: Variant in _grass_scatter_inflight_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		if not _is_chunk_source_desired(chunk_coord):
			continue
		grass_demand[chunk_coord] = {
			"revision": int(_grass_scatter_inflight_chunks.get(chunk_coord, -1)),
			"priority": _chunk_request_priority(chunk_coord),
		}
	for removed_coord: Vector2i in _grass_scatter_backend.sync_grass_scatter_requests(
		_generation_epoch,
		grass_demand,
	):
		_grass_scatter_inflight_chunks.erase(removed_coord)

	var object_demand: Dictionary = { }
	for chunk_coord_variant: Variant in _object_presentation_inflight_chunks.keys():
		var chunk_coord: Vector2i = chunk_coord_variant as Vector2i
		if not _is_chunk_source_desired(chunk_coord):
			continue
		object_demand[chunk_coord] = {
			"revision": int(_object_presentation_inflight_chunks.get(chunk_coord, -1)),
			"catalog_generation": _layered_object_asset_catalog.get_catalog_generation(),
			"priority": _chunk_request_priority(chunk_coord),
			"priority_class": _object_presentation_compute_priority_class(chunk_coord),
		}
	for removed_coord: Vector2i in _object_presentation_backend.sync_object_presentation_requests(
		_generation_epoch,
		object_demand,
	):
		_object_presentation_inflight_chunks.erase(removed_coord)


func _restore_warm_chunk_packet(
		chunk_coord: Vector2i,
		prepare_presentation: bool = true,
) -> bool:
	if not _warm_base_chunk_packet_cache.has(chunk_coord):
		return false
	var base_packet: Dictionary = _warm_base_chunk_packet_cache.get(chunk_coord, { }) as Dictionary
	_warm_base_chunk_packet_cache.erase(chunk_coord)
	_warm_base_chunk_packet_cache_stamps.erase(chunk_coord)
	if base_packet.is_empty():
		return false
	_warm_packet_cache_hit_count_total += 1
	_restore_warm_object_presentation(chunk_coord)
	_restore_warm_grass_scatter(chunk_coord)
	_base_chunk_packets[chunk_coord] = base_packet
	_chunk_packets[chunk_coord] = _diff_store.apply_to_packet(base_packet)
	_readiness_tracker.mark_stage(chunk_coord, &"generated")
	_readiness_tracker.mark_layer(chunk_coord, &"packet", &"ready", &"packet_resident")
	_refresh_loaded_visuals_around_chunk_overrides(chunk_coord)
	if prepare_presentation:
		_request_object_presentation_build(
			chunk_coord,
			_chunk_packets.get(chunk_coord, { }) as Dictionary,
			false,
		)
	if not _chunk_views.has(chunk_coord) \
			and _is_chunk_source_desired(chunk_coord) \
			and _object_presentation_results_by_chunk.has(chunk_coord):
		_queue_hot_object_prestage(chunk_coord)
	return true


func _store_warm_chunk_packet(chunk_coord: Vector2i, base_packet: Dictionary) -> void:
	if base_packet.is_empty():
		return
	_warm_base_chunk_packet_cache_next_stamp += 1
	_warm_base_chunk_packet_cache[chunk_coord] = base_packet
	_warm_base_chunk_packet_cache_stamps[chunk_coord] = _warm_base_chunk_packet_cache_next_stamp
	_move_live_object_presentation_to_warm(chunk_coord)
	_move_live_grass_scatter_to_warm(chunk_coord)
	while _warm_base_chunk_packet_cache.size() > WARM_PACKET_CACHE_MAX_CHUNKS:
		var oldest_coord: Vector2i = INVALID_CHUNK_COORD
		var oldest_stamp: int = 2147483647
		for cached_coord_variant: Variant in _warm_base_chunk_packet_cache_stamps.keys():
			var cached_coord: Vector2i = cached_coord_variant as Vector2i
			var stamp: int = int(_warm_base_chunk_packet_cache_stamps.get(cached_coord, oldest_stamp))
			if stamp < oldest_stamp:
				oldest_coord = cached_coord
				oldest_stamp = stamp
		if oldest_coord == INVALID_CHUNK_COORD:
			break
		_evict_warm_chunk(oldest_coord)
	_trim_warm_object_presentation_cache_to_budget()
	_trim_warm_grass_scatter_cache_to_budget()


func _grass_scatter_result_byte_size(result: Dictionary) -> int:
	# Metadata is emitted by the native worker while it already owns every
	# buffer length. Never rescan the 64 packed arrays on the main thread.
	var payload_bytes: int = int(result.get("payload_bytes", -1))
	if payload_bytes >= 0:
		return payload_bytes
	return maxi(0, int(result.get("buffer_float_count", 0)) * 4)


func _move_live_grass_scatter_to_warm(chunk_coord: Vector2i) -> void:
	if not _grass_scatter_results_by_chunk.has(chunk_coord):
		return
	var result: Dictionary = _grass_scatter_results_by_chunk.get(chunk_coord, { }) as Dictionary
	_grass_scatter_results_by_chunk.erase(chunk_coord)
	_store_warm_grass_scatter(chunk_coord, result)


func _store_warm_grass_scatter(chunk_coord: Vector2i, result: Dictionary) -> void:
	if result.is_empty() or not _warm_base_chunk_packet_cache.has(chunk_coord):
		return
	_erase_warm_grass_scatter(chunk_coord)
	var byte_size: int = _grass_scatter_result_byte_size(result)
	_warm_grass_scatter_cache[chunk_coord] = result
	_warm_grass_scatter_cache_bytes_by_chunk[chunk_coord] = byte_size
	_warm_grass_scatter_cache_bytes += byte_size
	_trim_warm_grass_scatter_cache_to_budget()


func _restore_warm_grass_scatter(chunk_coord: Vector2i) -> void:
	if not _warm_grass_scatter_cache.has(chunk_coord):
		return
	var result: Dictionary = _warm_grass_scatter_cache.get(chunk_coord, { }) as Dictionary
	_erase_warm_grass_scatter(chunk_coord)
	if result.is_empty():
		return
	_grass_scatter_results_by_chunk[chunk_coord] = result
	_grass_scatter_cache_hit_count_total += 1


func _erase_warm_grass_scatter(chunk_coord: Vector2i) -> void:
	if _warm_grass_scatter_cache.has(chunk_coord):
		_warm_grass_scatter_cache.erase(chunk_coord)
		_warm_grass_scatter_cache_bytes = maxi(
			0,
			_warm_grass_scatter_cache_bytes \
					- int(_warm_grass_scatter_cache_bytes_by_chunk.get(chunk_coord, 0)),
		)
	_warm_grass_scatter_cache_bytes_by_chunk.erase(chunk_coord)


func _trim_warm_grass_scatter_cache_to_budget() -> void:
	while _warm_grass_scatter_cache_bytes > WARM_GRASS_SCATTER_CACHE_MAX_BYTES:
		var oldest_coord: Vector2i = INVALID_CHUNK_COORD
		var oldest_stamp: int = 2147483647
		for coord_variant: Variant in _warm_grass_scatter_cache.keys():
			var coord: Vector2i = coord_variant as Vector2i
			var stamp: int = int(_warm_base_chunk_packet_cache_stamps.get(coord, oldest_stamp))
			if stamp < oldest_stamp:
				oldest_coord = coord
				oldest_stamp = stamp
		if oldest_coord == INVALID_CHUNK_COORD:
			break
		_erase_warm_grass_scatter(oldest_coord)


func _move_live_object_presentation_to_warm(chunk_coord: Vector2i) -> void:
	if not _object_presentation_results_by_chunk.has(chunk_coord):
		return
	var result: Dictionary = _object_presentation_results_by_chunk.get(chunk_coord, { }) as Dictionary
	_object_presentation_results_by_chunk.erase(chunk_coord)
	_store_warm_object_presentation(chunk_coord, result)


func _store_warm_object_presentation(chunk_coord: Vector2i, result: Dictionary) -> void:
	if result.is_empty() or not _warm_base_chunk_packet_cache.has(chunk_coord):
		return
	_erase_warm_object_presentation(chunk_coord)
	var byte_size: int = _object_presentation_result_byte_size(result)
	_warm_object_presentation_cache[chunk_coord] = result
	_warm_object_presentation_cache_bytes_by_chunk[chunk_coord] = byte_size
	_warm_object_presentation_cache_bytes += byte_size
	_trim_warm_object_presentation_cache_to_budget()


func _restore_warm_object_presentation(chunk_coord: Vector2i) -> void:
	if not _warm_object_presentation_cache.has(chunk_coord):
		return
	var result: Dictionary = _warm_object_presentation_cache.get(chunk_coord, { }) as Dictionary
	_erase_warm_object_presentation(chunk_coord)
	if result.is_empty():
		return
	_object_presentation_results_by_chunk[chunk_coord] = result
	_object_presentation_cache_hit_count_total += 1


func _erase_warm_object_presentation(chunk_coord: Vector2i) -> void:
	if _warm_object_presentation_cache.has(chunk_coord):
		_warm_object_presentation_cache.erase(chunk_coord)
		_warm_object_presentation_cache_bytes = maxi(
			0,
			_warm_object_presentation_cache_bytes \
					- int(_warm_object_presentation_cache_bytes_by_chunk.get(chunk_coord, 0)),
		)
	_warm_object_presentation_cache_bytes_by_chunk.erase(chunk_coord)


func _evict_warm_chunk(chunk_coord: Vector2i) -> void:
	_warm_base_chunk_packet_cache.erase(chunk_coord)
	_warm_base_chunk_packet_cache_stamps.erase(chunk_coord)
	_erase_warm_object_presentation(chunk_coord)
	_erase_warm_grass_scatter(chunk_coord)
	_evict_hot_object_presentation(chunk_coord)
	_object_presentation_revision_by_chunk.erase(chunk_coord)
	_grass_scatter_revision_by_chunk.erase(chunk_coord)
	_object_presentation_inflight_chunks.erase(chunk_coord)
	_object_presentation_retry_by_chunk.erase(chunk_coord)
	_object_presentation_terminal_fallback_by_chunk.erase(chunk_coord)
	if not _is_chunk_source_desired(chunk_coord) \
			and not _chunk_packets.has(chunk_coord) \
			and not _readiness_has_retained_data(chunk_coord):
		_readiness_tracker.mark_terminal(chunk_coord, &"evicted")


func _trim_warm_object_presentation_cache_to_budget() -> void:
	while _warm_object_presentation_cache_bytes > WARM_OBJECT_PRESENTATION_CACHE_MAX_BYTES:
		var oldest_coord: Vector2i = INVALID_CHUNK_COORD
		var oldest_stamp: int = 2147483647
		for cached_coord_variant: Variant in _warm_object_presentation_cache.keys():
			var cached_coord: Vector2i = cached_coord_variant as Vector2i
			var stamp: int = int(_warm_base_chunk_packet_cache_stamps.get(cached_coord, oldest_stamp))
			if stamp < oldest_stamp:
				oldest_coord = cached_coord
				oldest_stamp = stamp
		if oldest_coord == INVALID_CHUNK_COORD:
			break
		_evict_warm_chunk(oldest_coord)


static func _object_presentation_result_byte_size(result: Dictionary) -> int:
	if result.has("payload_bytes"):
		return maxi(0, int(result.get("payload_bytes", 0)))
	var float_count: int = 0
	for key: StringName in [
		&"tree_atlas_bucket_buffers",
		&"rock_atlas_bucket_buffers",
		&"living_flora_bucket_buffers",
	]:
		var bucket_value: Variant = result.get(key, [])
		if not bucket_value is Array:
			continue
		for buffer_variant: Variant in (bucket_value as Array):
			if buffer_variant is PackedFloat32Array:
				float_count += (buffer_variant as PackedFloat32Array).size()
	var spiky_value: Variant = result.get("spiky_flora_atlas_bucket_buffers", [])
	if spiky_value is Array:
		for atlas_variant: Variant in (spiky_value as Array):
			if not atlas_variant is Array:
				continue
			for buffer_variant: Variant in (atlas_variant as Array):
				if buffer_variant is PackedFloat32Array:
					float_count += (buffer_variant as PackedFloat32Array).size()
	float_count += (
		result.get("living_flora_shadow_buffer", PackedFloat32Array()) as PackedFloat32Array
	).size()
	float_count += (result.get("tree_collision_records", PackedFloat32Array()) as PackedFloat32Array).size()
	return float_count * 4


func _ensure_hot_object_presentation_root() -> Node2D:
	if _hot_object_presentation_root != null \
			and is_instance_valid(_hot_object_presentation_root):
		return _hot_object_presentation_root
	_hot_object_presentation_root = Node2D.new()
	_hot_object_presentation_root.name = "HotObjectPresentationRoot"
	# Individual resident layers own their hidden/revealed state. Keeping this
	# root visible lets a promoted GPU layer remain world-parented, avoiding a
	# costly Node/CanvasItem reparent on the reveal-critical frame.
	_hot_object_presentation_root.visible = true
	add_child(_hot_object_presentation_root)
	return _hot_object_presentation_root


func _make_pooled_object_presentation_layer() -> WorldObjectPacketLayer:
	var layer := WorldObjectPacketLayer.new()
	_ensure_hot_object_presentation_root().add_child(layer)
	_configure_hot_object_layer(layer, Vector2i.ZERO)
	if not layer.prepare_presentation_envelope(
		_layered_object_asset_catalog,
		OBJECT_PRESENTATION_POOL_INITIAL_SLOTS_PER_FAMILY,
	):
		layer.queue_free()
		return null
	layer.set_hot_cache_resident(true)
	return layer


func _warm_object_presentation_layer_pool() -> void:
	while _object_presentation_layer_pool.size() < OBJECT_PRESENTATION_LAYER_POOL_TARGET_SIZE:
		var layer: WorldObjectPacketLayer = _make_pooled_object_presentation_layer()
		if layer == null:
			return
		_add_clean_object_presentation_layer_to_pool(layer)


func _acquire_object_presentation_layer() -> WorldObjectPacketLayer:
	while not _object_presentation_layer_pool.is_empty():
		var pooled: WorldObjectPacketLayer = _object_presentation_layer_pool.pop_back()
		_remove_object_presentation_pool_weight(pooled)
		if pooled != null and is_instance_valid(pooled):
			assert(
				not pooled.has_pending_pool_retire(),
				"Object presentation pool exposed a layer before retirement completed",
			)
			return pooled
	# Pool exhaustion creates only the shell in this explicit envelope phase.
	# Family fixed graphs and collision ownership are advanced one-at-a-time by
	# subsequent visual-dispatcher callbacks before begin() is allowed to run.
	var layer := WorldObjectPacketLayer.new()
	_ensure_hot_object_presentation_root().add_child(layer)
	layer.set_hot_cache_resident(true)
	return layer


func _release_object_presentation_layer(layer: WorldObjectPacketLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.set_blocking_collision_active(false)
	layer.begin_pool_retire()
	layer.set_hot_cache_resident(true)
	layer.set_streaming_world_parented(true)
	var hot_root: Node2D = _ensure_hot_object_presentation_root()
	if layer.get_parent() != hot_root:
		if layer.get_parent() != null:
			layer.get_parent().remove_child(layer)
		hot_root.add_child(layer)
	layer.position = Vector2.ZERO
	_queue_object_presentation_layer_retire(layer)


func _add_clean_object_presentation_layer_to_pool(layer: WorldObjectPacketLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	assert(not layer.has_pending_pool_retire(), "Only fully retired object layers are reusable")
	layer.name = "PooledObjectPresentation%d" % _object_presentation_layer_pool.size()
	var weight: Dictionary = layer.get_retained_residency_weight()
	var layer_id: int = layer.get_instance_id()
	_object_presentation_pool_weight_by_layer_id[layer_id] = weight
	_object_presentation_pool_gpu_bytes += maxi(0, int(weight.get("gpu_buffer_bytes", 0)))
	_object_presentation_pool_canvas_items += maxi(0, int(weight.get("canvas_item_count", 0)))
	_object_presentation_pool_colliders += maxi(0, int(weight.get("collider_count", 0)))
	_object_presentation_layer_pool.append(layer)


func _remove_object_presentation_pool_weight(layer: WorldObjectPacketLayer) -> void:
	if layer == null:
		return
	var layer_id: int = layer.get_instance_id()
	var weight: Dictionary = _object_presentation_pool_weight_by_layer_id.get(layer_id, { }) as Dictionary
	_object_presentation_pool_weight_by_layer_id.erase(layer_id)
	_object_presentation_pool_gpu_bytes = maxi(
		0,
		_object_presentation_pool_gpu_bytes - maxi(0, int(weight.get("gpu_buffer_bytes", 0))),
	)
	_object_presentation_pool_canvas_items = maxi(
		0,
		_object_presentation_pool_canvas_items - maxi(0, int(weight.get("canvas_item_count", 0))),
	)
	_object_presentation_pool_colliders = maxi(
		0,
		_object_presentation_pool_colliders - maxi(0, int(weight.get("collider_count", 0))),
	)


func _queue_object_presentation_layer_retire(layer: WorldObjectPacketLayer) -> void:
	var layer_id: int = layer.get_instance_id()
	if _object_presentation_retire_layer_ids.has(layer_id):
		return
	var weight: Dictionary = layer.get_retained_residency_weight()
	var entry: Dictionary = {
		"layer": layer,
		"layer_id": layer_id,
		"phase": &"retire",
		"gpu_buffer_bytes": maxi(0, int(weight.get("gpu_buffer_bytes", 0))),
		"canvas_item_count": maxi(0, int(weight.get("canvas_item_count", 0))),
		"collider_count": maxi(0, int(weight.get("collider_count", 0))),
	}
	_object_presentation_retire_layer_ids[layer_id] = true
	_object_presentation_retire_queue.append(entry)
	_add_object_presentation_retire_weight(entry)


func _add_object_presentation_retire_weight(entry: Dictionary) -> void:
	_object_presentation_retire_gpu_bytes += maxi(0, int(entry.get("gpu_buffer_bytes", 0)))
	_object_presentation_retire_canvas_items += maxi(0, int(entry.get("canvas_item_count", 0)))
	_object_presentation_retire_colliders += maxi(0, int(entry.get("collider_count", 0)))


func _remove_object_presentation_retire_weight(entry: Dictionary) -> void:
	_object_presentation_retire_gpu_bytes = maxi(
		0,
		_object_presentation_retire_gpu_bytes - maxi(0, int(entry.get("gpu_buffer_bytes", 0))),
	)
	_object_presentation_retire_canvas_items = maxi(
		0,
		_object_presentation_retire_canvas_items - maxi(0, int(entry.get("canvas_item_count", 0))),
	)
	_object_presentation_retire_colliders = maxi(
		0,
		_object_presentation_retire_colliders - maxi(0, int(entry.get("collider_count", 0))),
	)


func _refresh_object_presentation_retire_weight(entry_index: int) -> void:
	if entry_index < 0 or entry_index >= _object_presentation_retire_queue.size():
		return
	var entry: Dictionary = _object_presentation_retire_queue[entry_index]
	var layer: WorldObjectPacketLayer = entry.get("layer", null) as WorldObjectPacketLayer
	_remove_object_presentation_retire_weight(entry)
	var weight: Dictionary = layer.get_retained_residency_weight() \
			if layer != null and is_instance_valid(layer) else { }
	entry["gpu_buffer_bytes"] = maxi(0, int(weight.get("gpu_buffer_bytes", 0)))
	entry["canvas_item_count"] = maxi(0, int(weight.get("canvas_item_count", 0)))
	entry["collider_count"] = maxi(0, int(weight.get("collider_count", 0)))
	_object_presentation_retire_queue[entry_index] = entry
	_add_object_presentation_retire_weight(entry)


func _pop_object_presentation_retire_front() -> Dictionary:
	if _object_presentation_retire_queue.is_empty():
		return { }
	var entry: Dictionary = _object_presentation_retire_queue.pop_front()
	_remove_object_presentation_retire_weight(entry)
	_object_presentation_retire_layer_ids.erase(int(entry.get("layer_id", 0)))
	return entry


## Separate dispatcher lane: exactly one slot-group/collider slice, one pool
## transition/shrink, OR one trim victim per frame. Always returning false is
## intentional: FrameBudgetDispatcher must not consume a cheap chain of
## RenderingServer/PhysicsServer writes in one frame. A pending retirement also
## backpressures trim, so eviction cannot outrun cleanup.
func _object_presentation_retire_tick() -> bool:
	var phase_started_usec: int = Time.get_ticks_usec()
	if not _object_presentation_retire_queue.is_empty():
		var entry: Dictionary = _object_presentation_retire_queue[0]
		var layer: WorldObjectPacketLayer = entry.get("layer", null) as WorldObjectPacketLayer
		if layer == null or not is_instance_valid(layer):
			_pop_object_presentation_retire_front()
			_finish_object_presentation_retire_phase(phase_started_usec)
			return false
		var phase: StringName = entry.get("phase", &"retire") as StringName
		if phase == &"retire":
			var retired_resource: bool = layer.retire_next_pool_slice(
				OBJECT_PRESENTATION_RETIRE_VISUAL_SLOTS_PER_PHASE,
				OBJECT_PRESENTATION_RETIRE_COLLIDERS_PER_PHASE,
			)
			_refresh_object_presentation_retire_weight(0)
			if retired_resource:
				_finish_object_presentation_retire_phase(phase_started_usec)
				return false
			if _clean_retired_object_layer_can_enter_pool(layer):
				_pop_object_presentation_retire_front()
				_add_clean_object_presentation_layer_to_pool(layer)
				_finish_object_presentation_retire_phase(phase_started_usec)
				return false
			entry = _object_presentation_retire_queue[0]
			entry["phase"] = &"shrink"
			_object_presentation_retire_queue[0] = entry
		elif _clean_retired_object_layer_can_enter_pool(layer):
			# A prior bounded slot-group shrink may already have removed the canvas
			# overage. Re-evaluate every frame instead of destroying the rest of a
			# now-admissible reusable graph.
			_pop_object_presentation_retire_front()
			_add_clean_object_presentation_layer_to_pool(layer)
			_finish_object_presentation_retire_phase(phase_started_usec)
			return false
		if layer.shrink_pool_next_slot_group():
			_refresh_object_presentation_retire_weight(0)
		else:
			_pop_object_presentation_retire_front()
			layer.free()
		_finish_object_presentation_retire_phase(phase_started_usec)
		return false
	if _hot_object_presentation_cache_is_over_budget():
		var cache_count_before: int = _hot_object_presentation_layers.size()
		_trim_hot_object_presentation_cache_to_budget()
		if _hot_object_presentation_layers.size() < cache_count_before:
			_finish_object_presentation_retire_phase(phase_started_usec)
	return false


func _clean_retired_object_layer_can_enter_pool(layer: WorldObjectPacketLayer) -> bool:
	if layer == null \
			or _object_presentation_layer_pool.size() >= OBJECT_PRESENTATION_LAYER_POOL_MAX_SIZE:
		return false
	var weight: Dictionary = layer.get_retained_residency_weight()
	# Moving a clean graph from retire accounting into pool accounting does not
	# change totals. Shrink it only when that graph can actually reduce the
	# violated dimension; tearing down hundreds of CanvasItems cannot help a
	# GPU/collider-only overage and would postpone eviction of the real hot victim.
	if _object_presentation_total_gpu_bytes() > HOT_OBJECT_PRESENTATION_CACHE_MAX_BYTES \
			and int(weight.get("gpu_buffer_bytes", 0)) > 0:
		return false
	if _object_presentation_total_canvas_items() > HOT_OBJECT_PRESENTATION_CACHE_MAX_CANVAS_ITEMS \
			and int(weight.get("canvas_item_count", 0)) > 0:
		return false
	if _object_presentation_total_colliders() > HOT_OBJECT_PRESENTATION_CACHE_MAX_COLLIDERS \
			and int(weight.get("collider_count", 0)) > 0:
		return false
	return true


func _finish_object_presentation_retire_phase(started_usec: int) -> void:
	_object_presentation_retire_phase_count_total += 1
	_object_presentation_retire_phase_usec_max_total = maxi(
		_object_presentation_retire_phase_usec_max_total,
		Time.get_ticks_usec() - started_usec,
	)


func _configure_hot_object_layer(
		layer: WorldObjectPacketLayer,
		chunk_coord: Vector2i,
) -> void:
	layer.set_streaming_world_parented(true)
	layer.set_living_flora_atlas(_plains_living_flora_atlas)
	layer.set_spiky_flora_atlases(_plains_spiky_flora_atlases)
	layer.set_tree_atlas(PLAINS_TREE_ATLAS if PLAINS_TREE_ENABLED else null)
	layer.set_layered_tree_asset_dirs(
		PLAINS_LAYERED_TREE_ASSET_DIRS if PLAINS_TREE_ENABLED else [],
	)
	layer.set_layered_small_rock_asset_dirs(
		PLAINS_LAYERED_SMALL_ROCK_ASSET_DIRS if PLAINS_SMALL_ROCK_ENABLED else [],
	)
	layer.position = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	layer.set_world_origin_y(layer.position.y)
	layer.set_debug_collisions_visible(_debug_object_collisions_visible)
	if _ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
		layer.update_ladder_z(_ladder_anchor_stripe)


func _hot_object_entry_is_current(chunk_coord: Vector2i, entry: Dictionary) -> bool:
	return not entry.is_empty() \
			and int(entry.get("epoch", -1)) == _generation_epoch \
			and int(entry.get("revision", -1)) \
					== int(_object_presentation_revision_by_chunk.get(chunk_coord, -2)) \
			and int(entry.get("catalog_generation", -1)) \
					== _layered_object_asset_catalog.get_catalog_generation() \
			and is_instance_valid(entry.get("layer", null) as WorldObjectPacketLayer)


func _get_current_hot_object_entry(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var entry: Dictionary = _hot_object_presentation_layers.get(chunk_coord, { }) as Dictionary
	if entry.is_empty():
		return { }
	if not _hot_object_entry_is_current(chunk_coord, entry):
		_evict_hot_object_presentation(chunk_coord)
		return { }
	return entry


func _add_hot_object_entry(chunk_coord: Vector2i, entry: Dictionary) -> void:
	_hot_object_presentation_cache_next_stamp += 1
	entry["stamp"] = _hot_object_presentation_cache_next_stamp
	_hot_object_presentation_layers[chunk_coord] = entry
	_hot_object_presentation_cache_bytes += maxi(0, int(entry.get("gpu_buffer_bytes", 0)))
	_hot_object_presentation_cache_canvas_items += maxi(
		0,
		int(entry.get("canvas_item_count", 0)),
	)
	_hot_object_presentation_cache_colliders += maxi(0, int(entry.get("collider_count", 0)))


func _take_hot_object_entry(chunk_coord: Vector2i) -> Dictionary:
	var entry: Dictionary = _hot_object_presentation_layers.get(chunk_coord, { }) as Dictionary
	if entry.is_empty():
		return { }
	_hot_object_presentation_layers.erase(chunk_coord)
	_hot_object_presentation_cache_bytes = maxi(
		0,
		_hot_object_presentation_cache_bytes - maxi(0, int(entry.get("gpu_buffer_bytes", 0))),
	)
	_hot_object_presentation_cache_canvas_items = maxi(
		0,
		_hot_object_presentation_cache_canvas_items \
				- maxi(0, int(entry.get("canvas_item_count", 0))),
	)
	_hot_object_presentation_cache_colliders = maxi(
		0,
		_hot_object_presentation_cache_colliders \
				- maxi(0, int(entry.get("collider_count", 0))),
	)
	return entry


func _stage_hot_object_presentation(
		chunk_coord: Vector2i,
		result: Dictionary,
) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if result.is_empty() \
			or (not _is_chunk_source_desired(chunk_coord) and not _chunk_views.has(chunk_coord)):
		return false
	var current: Dictionary = _get_current_hot_object_entry(chunk_coord)
	if not current.is_empty():
		return true
	var presented_object_count: int = maxi(0, int(result.get("tree_instance_count", 0))) \
			+ maxi(0, int(result.get("rock_instance_count", 0))) \
			+ maxi(0, int(result.get("living_flora_count", 0))) \
			+ maxi(0, int(result.get("spiky_flora_count", 0)))
	if presented_object_count <= 0:
		return false
	var acquired_from_pool: bool = not _object_presentation_layer_pool.is_empty()
	var acquire_started_usec: int = WorldPerfProbe.begin()
	var layer: WorldObjectPacketLayer = _acquire_object_presentation_layer()
	WorldPerfProbe.end(
		"WorldStreamer.visual_upload.object_packet_envelope.acquire_pool" \
				if acquired_from_pool \
				else "WorldStreamer.visual_upload.object_packet_envelope.acquire_cold",
		acquire_started_usec,
	)
	if layer == null:
		return false
	layer.name = "HotObjectPacket_%d_%d" % [chunk_coord.x, chunk_coord.y]
	var configure_started_usec: int = WorldPerfProbe.begin()
	_configure_hot_object_layer(layer, chunk_coord)
	WorldPerfProbe.end(
		"WorldStreamer.visual_upload.object_packet_envelope.configure",
		configure_started_usec,
	)
	layer.set_blocking_collision_active(false)
	var reservation: Dictionary = layer.estimate_presentation_result_reservation_weight(result)
	_add_hot_object_entry(
		chunk_coord,
		{
			"layer": layer,
			"epoch": _generation_epoch,
			"revision": int(_object_presentation_revision_by_chunk.get(chunk_coord, -1)),
			"catalog_generation": _layered_object_asset_catalog.get_catalog_generation(),
			"ready": false,
			"envelope_pending": true,
			"begin_started": false,
			"allocation_started_families": { },
			"ladder_anchor_stripe": LADDER_ANCHOR_UNSET,
			"acquired_from_pool": acquired_from_pool,
			"gpu_buffer_bytes": maxi(0, int(reservation.get("gpu_buffer_bytes", 0))),
			"canvas_item_count": maxi(0, int(reservation.get("canvas_item_count", 0))),
			"collider_count": maxi(0, int(reservation.get("collider_count", 0))),
		},
	)
	_queue_object_packet_visual_upload(chunk_coord)
	_trim_hot_object_presentation_cache_to_budget()
	return _hot_object_presentation_layers.has(chunk_coord)


func _mark_hot_object_presentation_ready(chunk_coord: Vector2i) -> bool:
	var entry: Dictionary = _get_current_hot_object_entry(chunk_coord)
	if entry.is_empty():
		return false
	var layer: WorldObjectPacketLayer = entry.get("layer", null) as WorldObjectPacketLayer
	if layer == null or not layer.is_hot_cache_eligible():
		_evict_hot_object_presentation(chunk_coord)
		return false
	_take_hot_object_entry(chunk_coord)
	layer.set_hot_cache_resident(true)
	var weight: Dictionary = layer.get_hot_cache_weight()
	entry["ready"] = true
	entry["gpu_buffer_bytes"] = maxi(0, int(weight.get("gpu_buffer_bytes", 0)))
	entry["canvas_item_count"] = maxi(0, int(weight.get("canvas_item_count", 0)))
	entry["collider_count"] = maxi(0, int(weight.get("collider_count", 0)))
	_add_hot_object_entry(chunk_coord, entry)
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"objects",
		&"ready",
		&"object_hot_presentation_ready",
	)
	_trim_hot_object_presentation_cache_to_budget()
	return _hot_object_presentation_layers.has(chunk_coord)


func _cache_committed_object_layer(
		chunk_coord: Vector2i,
		layer: WorldObjectPacketLayer,
) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if layer == null or not is_instance_valid(layer) or not layer.is_hot_cache_eligible():
		return false
	_evict_hot_object_presentation(chunk_coord)
	var previous_parent: Node = layer.get_parent()
	var hot_root: Node2D = _ensure_hot_object_presentation_root()
	if previous_parent != null and previous_parent != hot_root:
		previous_parent.remove_child(layer)
	if layer.get_parent() == null:
		hot_root.add_child(layer)
	_configure_hot_object_layer(layer, chunk_coord)
	layer.set_hot_cache_resident(true)
	var weight: Dictionary = layer.get_hot_cache_weight()
	_add_hot_object_entry(
		chunk_coord,
		{
			"layer": layer,
			"epoch": _generation_epoch,
			"revision": int(_object_presentation_revision_by_chunk.get(chunk_coord, -1)),
			"catalog_generation": _layered_object_asset_catalog.get_catalog_generation(),
			"ready": true,
			"gpu_buffer_bytes": maxi(0, int(weight.get("gpu_buffer_bytes", 0))),
			"canvas_item_count": maxi(0, int(weight.get("canvas_item_count", 0))),
			"collider_count": maxi(0, int(weight.get("collider_count", 0))),
		},
	)
	_trim_hot_object_presentation_cache_to_budget()
	return _hot_object_presentation_layers.has(chunk_coord)


func _promote_hot_object_presentation(
		chunk_coord: Vector2i,
		chunk_view: ChunkView,
) -> bool:
	if chunk_view == null:
		return false
	var entry: Dictionary = _get_current_hot_object_entry(chunk_coord)
	if entry.is_empty():
		return false
	var layer: WorldObjectPacketLayer = entry.get("layer", null) as WorldObjectPacketLayer
	if not bool(entry.get("ready", false)) \
			and (layer == null or not layer.is_presentation_complete()):
		return false
	var cache_take_started: int = WorldPerfProbe.begin()
	_take_hot_object_entry(chunk_coord)
	WorldPerfProbe.end(
		"WorldStreamer.visual_upload.object_packet_adopt.cache_take",
		cache_take_started,
	)
	var view_adopt_started: int = WorldPerfProbe.begin()
	var adopted: bool = layer != null \
			and chunk_view.adopt_committed_object_layer_from_hot_cache(layer)
	WorldPerfProbe.end(
		"WorldStreamer.visual_upload.object_packet_adopt.view",
		view_adopt_started,
	)
	if adopted:
		_hot_object_presentation_cache_hit_count_total += 1
		return true
	if layer != null and is_instance_valid(layer):
		_release_object_presentation_layer(layer)
	return false


func _evict_hot_object_presentation(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_drop_hot_object_prestage(chunk_coord)
	# A prestage envelope now shares the visual-priority queue even before a hot
	# layer exists, so invalidation must retire both halves atomically.
	_drop_object_packet_visual_upload(chunk_coord)
	var entry: Dictionary = _take_hot_object_entry(chunk_coord)
	if entry.is_empty():
		return
	var layer: WorldObjectPacketLayer = entry.get("layer", null) as WorldObjectPacketLayer
	if layer != null and is_instance_valid(layer):
		_release_object_presentation_layer(layer)
	_hot_object_presentation_cache_eviction_count_total += 1


func _object_presentation_total_gpu_bytes() -> int:
	return _hot_object_presentation_cache_bytes \
			+ _object_presentation_retire_gpu_bytes \
			+ _object_presentation_pool_gpu_bytes


func _object_presentation_total_canvas_items() -> int:
	return _hot_object_presentation_cache_canvas_items \
			+ _object_presentation_retire_canvas_items \
			+ _object_presentation_pool_canvas_items


func _object_presentation_total_colliders() -> int:
	return _hot_object_presentation_cache_colliders \
			+ _object_presentation_retire_colliders \
			+ _object_presentation_pool_colliders


func _object_presentation_residency_over_resource_budget() -> bool:
	return _object_presentation_total_gpu_bytes() > HOT_OBJECT_PRESENTATION_CACHE_MAX_BYTES \
			or _object_presentation_total_canvas_items() \
					> HOT_OBJECT_PRESENTATION_CACHE_MAX_CANVAS_ITEMS \
			or _object_presentation_total_colliders() \
					> HOT_OBJECT_PRESENTATION_CACHE_MAX_COLLIDERS


func _hot_object_presentation_cache_is_over_budget() -> bool:
	return _hot_object_presentation_layers.size() > HOT_OBJECT_PRESENTATION_CACHE_MAX_CHUNKS \
			or _object_presentation_residency_over_resource_budget()


func _trim_hot_object_presentation_cache_to_budget() -> void:
	# One victim is one explicit dispatcher phase. Its retained resources move to
	# the retire counters, and no second victim is selected until that queue drains.
	if not _hot_object_presentation_cache_is_over_budget() \
			or not _object_presentation_retire_queue.is_empty():
		return
	var victim: Vector2i = INVALID_CHUNK_COORD
	var victim_has_live_view: bool = true
	var victim_is_source_desired: bool = true
	var victim_priority: int = -1
	var victim_stamp: int = 1 << 60
	for coord_variant: Variant in _hot_object_presentation_layers.keys():
		var coord: Vector2i = coord_variant as Vector2i
		var entry: Dictionary = _hot_object_presentation_layers.get(coord, { }) as Dictionary
		var live_view: ChunkView = _chunk_views.get(coord, null) as ChunkView
		var has_live_view: bool = live_view != null and is_instance_valid(live_view)
		var layer: WorldObjectPacketLayer = entry.get("layer", null) as WorldObjectPacketLayer
		if has_live_view and layer != null and is_instance_valid(layer) \
				and not bool(entry.get("ready", false)) \
				and not layer.is_presentation_complete():
			continue
		var source_desired: bool = _is_chunk_source_desired(coord)
		var priority: int = _chunk_request_priority(coord)
		var stamp: int = int(entry.get("stamp", 0))
		if victim == INVALID_CHUNK_COORD \
				or (victim_has_live_view and not has_live_view) \
				or (victim_has_live_view == has_live_view \
						and victim_is_source_desired and not source_desired) \
				or (victim_has_live_view == has_live_view \
						and victim_is_source_desired == source_desired \
						and priority > victim_priority) \
				or (victim_has_live_view == has_live_view \
						and victim_is_source_desired == source_desired \
						and priority == victim_priority and stamp < victim_stamp):
			victim = coord
			victim_has_live_view = has_live_view
			victim_is_source_desired = source_desired
			victim_priority = priority
			victim_stamp = stamp
	if victim != INVALID_CHUNK_COORD:
		_evict_hot_object_presentation_for_budget(victim)


## Cache limits may discard hidden residency, never the only transaction that
## a live hidden ChunkView is waiting on. If the live working set itself forces
## eviction, immediately transfer a completed layer or restage its retained CPU
## result into the view so atomic reveal cannot wait forever.
func _evict_hot_object_presentation_for_budget(chunk_coord: Vector2i) -> void:
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	var entry: Dictionary = _hot_object_presentation_layers.get(chunk_coord, { }) as Dictionary
	if chunk_view == null or entry.is_empty():
		_evict_hot_object_presentation(chunk_coord)
		return
	var layer: WorldObjectPacketLayer = entry.get("layer", null) as WorldObjectPacketLayer
	if layer != null and is_instance_valid(layer) \
			and not bool(entry.get("ready", false)) \
			and not layer.is_presentation_complete():
		# Defensive counterpart to the victim filter above. Never restart the only
		# in-flight presentation a hidden live view is waiting on.
		return
	if bool(entry.get("ready", false)) \
			or (layer != null and layer.is_presentation_complete()):
		if _promote_hot_object_presentation(chunk_coord, chunk_view):
			# Promotion remains hidden. Keep/restore the focused queue coordinate so
			# atomic reveal runs as its own dispatcher phase on a later frame.
			_defer_object_presentation_reveal(chunk_coord)
			_queue_object_packet_visual_upload(chunk_coord)
			return
	_evict_hot_object_presentation(chunk_coord)
	# Do not call _stage_ready_object_presentation() here: that method prefers
	# hot residency and would re-enter trim with the same over-budget reservation.
	# A broken/stale live entry falls back directly to its retained CPU result.
	var result: Dictionary = _object_presentation_results_by_chunk.get(
		chunk_coord,
		{ },
	) as Dictionary
	if result.is_empty() \
			or not chunk_view.stage_object_presentation_result(
				result,
				_layered_object_asset_catalog,
			):
		return
	_drop_hot_object_prestage(chunk_coord)
	_object_packet_visual_priority_dirty = true
	_queue_object_packet_visual_upload(chunk_coord)


func _clear_hot_object_presentation_cache() -> void:
	_pending_hot_object_prestage_chunks.clear()
	_pending_hot_object_prestage_set.clear()
	var coords: Array[Vector2i] = []
	for coord_variant: Variant in _hot_object_presentation_layers.keys():
		coords.append(coord_variant as Vector2i)
	for coord: Vector2i in coords:
		_evict_hot_object_presentation(coord)
	_hot_object_presentation_layers.clear()
	_hot_object_presentation_cache_bytes = 0
	_hot_object_presentation_cache_canvas_items = 0
	_hot_object_presentation_cache_colliders = 0
	_hot_object_presentation_cache_next_stamp = 0
	_object_presentation_layer_pool.clear()
	_object_presentation_pool_weight_by_layer_id.clear()
	_object_presentation_pool_gpu_bytes = 0
	_object_presentation_pool_canvas_items = 0
	_object_presentation_pool_colliders = 0
	_object_presentation_retire_queue.clear()
	_object_presentation_retire_layer_ids.clear()
	_object_presentation_retire_gpu_bytes = 0
	_object_presentation_retire_canvas_items = 0
	_object_presentation_retire_colliders = 0
	_object_presentation_retire_phase_count_total = 0
	_object_presentation_retire_phase_usec_max_total = 0
	if _hot_object_presentation_root != null \
			and is_instance_valid(_hot_object_presentation_root):
		_hot_object_presentation_root.queue_free()
	_hot_object_presentation_root = null


func _prune_resident_source_packets() -> void:
	var resident_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _base_chunk_packets.keys():
		resident_coords.append(chunk_coord_variant as Vector2i)
	for chunk_coord: Vector2i in resident_coords:
		if _is_chunk_packet_residency_desired(chunk_coord) \
				or _chunk_views.has(chunk_coord) \
				or chunk_coord == _active_publish_chunk:
			continue
		_store_warm_chunk_packet(
			chunk_coord,
			_base_chunk_packets.get(chunk_coord, { }) as Dictionary,
		)
		_base_chunk_packets.erase(chunk_coord)
		_chunk_packets.erase(chunk_coord)
		_forget_mountain_mask(chunk_coord, false, false)
		_forget_terrain_edge_mask(chunk_coord, false, false)
	_prune_stale_hot_object_presentation_work()


func _prune_stale_hot_object_presentation_work() -> void:
	var pending_coords: Array[Vector2i] = _pending_hot_object_prestage_chunks.duplicate()
	for chunk_coord: Vector2i in pending_coords:
		if _is_chunk_source_desired(chunk_coord) or _chunk_views.has(chunk_coord):
			continue
		_drop_hot_object_prestage(chunk_coord)
		_drop_object_packet_visual_upload(chunk_coord)
	var resident_coords: Array[Vector2i] = []
	for coord_variant: Variant in _hot_object_presentation_layers.keys():
		resident_coords.append(coord_variant as Vector2i)
	for chunk_coord: Vector2i in resident_coords:
		if _is_chunk_source_desired(chunk_coord) or _chunk_views.has(chunk_coord):
			continue
		var entry: Dictionary = _hot_object_presentation_layers.get(chunk_coord, { }) as Dictionary
		if bool(entry.get("ready", false)):
			continue
		_evict_hot_object_presentation(chunk_coord)


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
		if not _is_chunk_packet_residency_desired(chunk_coord):
			_store_warm_chunk_packet(chunk_coord, packet)
			continue
		_evict_warm_chunk(chunk_coord)
		_base_chunk_packets[chunk_coord] = packet
		var merged_packet: Dictionary = _diff_store.apply_to_packet(packet)
		_chunk_packets[chunk_coord] = merged_packet
		_readiness_tracker.mark_stage(chunk_coord, &"generated")
		_readiness_tracker.mark_layer(chunk_coord, &"packet", &"ready", &"packet_resident")
		_invalidate_grass_scatter(chunk_coord)
		_refresh_loaded_visuals_around_chunk_overrides(chunk_coord)
		_forget_mountain_mask(chunk_coord, true, true)
		_forget_terrain_edge_mask(chunk_coord, true, true)
		if _is_chunk_source_desired(chunk_coord):
			_request_object_presentation_build(chunk_coord, merged_packet, true)
		if _should_materialize_chunk(chunk_coord) \
				and not _pending_publish_queue.has(chunk_coord) \
				and chunk_coord != _active_publish_chunk:
			_pending_publish_queue.append(chunk_coord)
			_readiness_tracker.mark_layer(
				chunk_coord,
				&"terrain",
				&"waiting",
				&"terrain_publish_queued",
			)


func _publish_next_batch(
		allow_new_publish: bool = true,
		allow_mask_prefetch: bool = true,
) -> void:
	_prune_stale_pending_publish_chunks()
	if _active_publish_chunk != INVALID_CHUNK_COORD \
			and not _should_materialize_chunk(_active_publish_chunk):
		_hot_chunk_view_reuse_metadata_by_chunk.erase(_active_publish_chunk)
		_active_publish_chunk = INVALID_CHUNK_COORD
	if _active_publish_chunk == INVALID_CHUNK_COORD:
		if _pending_publish_queue.is_empty() or not allow_new_publish:
			return
		var publish_begin_started: int = WorldPerfProbe.begin()
		# Bounded scan instead of strict FIFO: a head chunk waiting for its
		# native mountain mask must not stall every ready chunk behind it. This
		# readiness pass is cache-only: a halo cache miss is prepared below and
		# never shares a frame with ChunkView acquisition/publication.
		var step_started: int = WorldPerfProbe.begin()
		var picked_index: int = -1
		var exhausted_mask_chunks: Array[Vector2i] = []
		var scan_limit: int = mini(_pending_publish_queue.size(), PUBLISH_QUEUE_SCAN_LIMIT)
		for index: int in range(scan_limit):
			var candidate: Vector2i = _pending_publish_queue[index]
			var candidate_packet: Dictionary = _chunk_packets.get(candidate, { }) as Dictionary
			if candidate_packet.is_empty():
				continue
			if _can_publish_chunk_with_mountain_mask(candidate, candidate_packet):
				picked_index = index
				break
			if _is_current_mountain_mask_retry_exhausted(candidate) \
					or _is_current_combined_halo_retry_parked(candidate):
				exhausted_mask_chunks.append(candidate)
		WorldPerfProbe.end("WorldStreamer.publish.begin.mountain_ready", step_started)
		if picked_index < 0:
			WorldPerfProbe.end("WorldStreamer.publish.begin", publish_begin_started)
			_rotate_parked_mask_chunks_to_publish_tail(exhausted_mask_chunks)
			if allow_mask_prefetch:
				var prefetch_started: int = WorldPerfProbe.begin()
				_prefetch_queued_chunk_masks(PUBLISH_MASK_PREFETCH_PER_TICK)
				WorldPerfProbe.end("WorldStreamer.publish.begin.prefetch", prefetch_started)
			return
		var next_publish_chunk: Vector2i = _pending_publish_queue[picked_index]
		_pending_publish_queue.remove_at(picked_index)
		var packet: Dictionary = _chunk_packets.get(next_publish_chunk, { }) as Dictionary
		step_started = WorldPerfProbe.begin()
		_prepare_terrain_edge_mask_for_publish(next_publish_chunk, packet)
		WorldPerfProbe.end("WorldStreamer.publish.begin.terrain_edge_prepare", step_started)
		_active_publish_chunk = next_publish_chunk
		_readiness_tracker.mark_layer(
			_active_publish_chunk,
			&"terrain",
			&"waiting",
			&"terrain_publish_applying",
		)
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
		# Terrain publication only establishes the hidden reveal gate. Adoption,
		# begin(), recycled-owner cleanup and terminal compatibility rendering all
		# remain distinct phases of the higher-priority object dispatcher.
		var reuse_metadata: Dictionary = _hot_chunk_view_reuse_metadata_by_chunk.get(
			_active_publish_chunk,
			{ },
		) as Dictionary
		chunk_view.begin_apply(
			packet,
			true,
			false,
			bool(reuse_metadata.get("preserve_grass", false)),
			bool(reuse_metadata.get("preserve_terrain", false)),
		)
		_hot_chunk_view_reuse_metadata_by_chunk.erase(_active_publish_chunk)
		_queue_object_presentation_for_live_view(_active_publish_chunk)
		_request_grass_scatter_build(_active_publish_chunk)
		WorldPerfProbe.end("WorldStreamer.publish.begin.chunk_begin_apply", step_started)
		WorldPerfProbe.end("WorldStreamer.publish.begin", publish_begin_started)
		return

	# Use the terrain upload frames to prepare the next queued chunk. One native
	# halo miss per tick keeps forward streaming warm without combining that miss
	# with the comparatively expensive ChunkView acquisition of the next publish.
	if allow_mask_prefetch and not _pending_publish_queue.is_empty():
		var prefetch_started: int = WorldPerfProbe.begin()
		_prefetch_queued_chunk_masks(PUBLISH_MASK_PREFETCH_PER_TICK)
		WorldPerfProbe.end("WorldStreamer.publish.begin.prefetch", prefetch_started)
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
		_readiness_tracker.mark_stage(finalized_chunk, &"gameplay_ready")
		_readiness_tracker.mark_layer(
			finalized_chunk,
			&"terrain",
			&"ready",
			&"terrain_cells_committed",
		)
		_handle_cover_chunk_published(finalized_chunk)
		_refresh_debug_visuals_for_chunk(finalized_chunk)
		# A chunk whose native terrain/mountain visual is still budget-queued
		# stays hidden: showing it now would flash a square shoreline or a closed
		# or stale-cavity roof for one or more frames on reload. Once the honest
		# startup gate is over, object presentation is allowed to finish behind
		# the already complete terrain; S6 owns making those objects pop-free.
		if not _is_chunk_desired(finalized_chunk):
			# S3 materializes the outer movement reserve through the same complete
			# pipeline, but that ring is not current viewport demand. Keep its
			# presentation and built colliders resident behind an explicit reveal
			# gate; activation remains a later visible-demand transition.
			active_view.set_object_collision_active(false)
			active_view.visible = false
			_readiness_tracker.mark_stage(finalized_chunk, &"presentation_ready")
			_readiness_tracker.mark_layer(
				finalized_chunk,
				&"visibility",
				&"not_applicable",
				&"outside_visible_demand",
			)
		else:
			_pending_chunk_visibility_after_mountain_visual[finalized_chunk] = true
			_readiness_tracker.mark_layer(
				finalized_chunk,
				&"visibility",
				&"waiting",
				&"visibility_reveal_guard",
			)
			_finalize_pending_chunk_visibility(finalized_chunk)
		WorldPerfProbe.end("WorldStreamer.publish.finalize", publish_finalize_started)
		_active_publish_chunk = INVALID_CHUNK_COORD


func _finalize_pending_chunk_visibility(chunk_coord: Vector2i) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _pending_chunk_visibility_after_mountain_visual.has(chunk_coord):
		# A presentation may complete before terrain batch publication has reached
		# its reveal gate. Expired guards have no remaining work to protect.
		_is_object_presentation_reveal_deferred(chunk_coord)
		return
	var chunk_view: ChunkView = _chunk_views.get(chunk_coord, null) as ChunkView
	if chunk_view == null:
		_pending_chunk_visibility_after_mountain_visual.erase(chunk_coord)
		_object_presentation_reveal_not_before_frame_by_chunk.erase(chunk_coord)
		return
	if not _is_chunk_desired(chunk_coord):
		_pending_chunk_visibility_after_mountain_visual.erase(chunk_coord)
		chunk_view.set_object_collision_active(false)
		chunk_view.visible = false
		return
	var terrain_visual_pending: bool = chunk_view.is_mountain_native_mask_visual_pending() \
			or chunk_view.is_terrain_edge_mask_visual_pending()
	var object_presentation_pending: bool = \
			not chunk_view.is_object_blocking_presentation_ready() \
					or _is_object_presentation_reveal_deferred(chunk_coord)
	if terrain_visual_pending \
			or (_initial_loading_gate.is_active() and object_presentation_pending):
		return
	if not chunk_view.visible:
		if chunk_view.has_pending_grass_scatter_visual():
			_chunk_reveal_with_pending_grass_count_total += 1
		chunk_view.visible = true
		_readiness_tracker.mark_stage(chunk_coord, &"visible")
		_readiness_tracker.mark_layer(
			chunk_coord,
			&"visibility",
			&"ready",
			&"terrain_visible",
		)
		EventBus.chunk_loaded.emit(chunk_coord)
	if object_presentation_pending:
		# The terrain/water/mountain owner is complete and may meet its S4
		# deadline independently. Keep the externally-parented object layer and
		# its blockers inactive until the existing object pipeline reaches its
		# own reveal guard; no object generation or batching policy changes here.
		chunk_view.set_object_collision_active(false)
		return
	_pending_chunk_visibility_after_mountain_visual.erase(chunk_coord)
	_object_presentation_reveal_not_before_frame_by_chunk.erase(chunk_coord)
	chunk_view.set_object_collision_active(true)


func _prune_stale_pending_publish_chunks() -> void:
	if _pending_publish_queue.is_empty():
		return
	var filtered_queue: Array[Vector2i] = []
	var seen: Dictionary = { }
	for chunk_coord: Vector2i in _pending_publish_queue:
		if not _should_materialize_chunk(chunk_coord):
			continue
		if seen.has(chunk_coord):
			continue
		seen[chunk_coord] = true
		filtered_queue.append(chunk_coord)
	_pending_publish_queue = filtered_queue


func _is_current_mountain_mask_retry_exhausted(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var retry_state: Dictionary = _mountain_native_mask_retry_by_chunk.get(
		chunk_coord,
		{ },
	) as Dictionary
	return not retry_state.is_empty() \
			and int(retry_state.get("epoch", -1)) == _generation_epoch \
			and int(retry_state.get("revision", -1)) \
					== _get_mountain_mask_revision(chunk_coord) \
			and bool(retry_state.get("exhausted", false))


func _is_current_combined_halo_retry_parked(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var retry_state: Dictionary = _combined_halo_build_retry_by_chunk.get(
		chunk_coord,
		{ },
	) as Dictionary
	return not retry_state.is_empty() \
			and int(retry_state.get("epoch", -1)) == _generation_epoch \
			and int(retry_state.get("mountain_revision", -1)) \
					== _get_mountain_mask_revision(chunk_coord) \
			and int(retry_state.get("terrain_revision", -1)) \
					== _get_terrain_edge_mask_revision(chunk_coord) \
			and Time.get_ticks_msec() < int(retry_state.get("not_before_msec", 0))


func _rotate_parked_mask_chunks_to_publish_tail(
		chunk_coords: Array[Vector2i],
) -> void:
	# Rare failure-only fairness path. Healthy/inflight chunks keep their stable
	# nearest-first order; long-cooldown failures cannot permanently occupy all
	# eight bounded readiness slots.
	for chunk_coord: Vector2i in chunk_coords:
		var index: int = _pending_publish_queue.find(chunk_coord)
		if index < 0:
			continue
		_pending_publish_queue.remove_at(index)
		_pending_publish_queue.append(chunk_coord)


func _prefetch_queued_chunk_masks(max_builds: int) -> void:
	# Warm the native mask pipeline for chunks waiting in the publish queue.
	# Cache misses (fresh halo builds) are the bounded cost; chunks whose halos
	# are already cached only pay cheap dictionary checks.
	var builds: int = 0
	var inspected: int = 0
	for chunk_coord: Vector2i in _pending_publish_queue:
		if builds >= max_builds or inspected >= PUBLISH_QUEUE_SCAN_LIMIT:
			return
		inspected += 1
		if _prefetch_chunk_masks(chunk_coord):
			builds += 1


func _prefetch_chunk_masks(chunk_coord: Vector2i) -> bool:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var halo_sources_ready: bool = _has_loaded_chunk_halo_sources(chunk_coord)
	if not halo_sources_ready:
		return false
	var mountain_halo: Dictionary = _mountain_solid_halo_cache.get(
		chunk_coord,
		{ },
	) as Dictionary
	var edge_halo: Dictionary = _terrain_edge_solid_halo_cache.get(
		chunk_coord,
		{ },
	) as Dictionary
	var mountain_halo_current: bool = _is_runtime_halo_cache_entry_current(
		mountain_halo,
		_get_mountain_mask_revision(chunk_coord),
	)
	var terrain_halo_current: bool = _is_runtime_halo_cache_entry_current(
		edge_halo,
		_get_terrain_edge_mask_revision(chunk_coord),
	)
	var needs_combined_halo: bool = not mountain_halo_current \
			or (TERRAIN_EDGE_MASK_RUNTIME_ENABLED and not terrain_halo_current)
	if needs_combined_halo:
		var mountain_revision: int = _get_mountain_mask_revision(chunk_coord)
		var terrain_revision: int = _get_terrain_edge_mask_revision(chunk_coord)
		var retry_state: Dictionary = _combined_halo_build_retry_by_chunk.get(
			chunk_coord,
			{ },
		) as Dictionary
		var retry_is_current: bool = not retry_state.is_empty() \
				and int(retry_state.get("epoch", -1)) == _generation_epoch \
				and int(retry_state.get("mountain_revision", -1)) == mountain_revision \
				and int(retry_state.get("terrain_revision", -1)) == terrain_revision
		if retry_is_current \
				and Time.get_ticks_msec() < int(retry_state.get("not_before_msec", 0)):
			return false
		if not retry_is_current:
			_combined_halo_build_retry_by_chunk.erase(chunk_coord)
		# Both masks and grass consume the same radius-8 source field. Build it
		# exactly once per prefetch attempt; a native contract failure must not
		# cascade through mountain, terrain and grass getters in the same frame.
		var phase_started: int = WorldPerfProbe.begin()
		var fields: Dictionary = _build_combined_chunk_halo_fields(
			chunk_coord,
			MOUNTAIN_HALO_MASK_RADIUS_TILES,
		)
		_cache_combined_chunk_halo_fields(chunk_coord, fields)
		WorldPerfProbe.end(
			"WorldStreamer.prefetch.mountain_halo" \
					if not mountain_halo_current \
					else "WorldStreamer.prefetch.terrain_halo",
			phase_started,
		)
		if not bool(fields.get("success", false)):
			var failure_count: int = 1
			if retry_is_current:
				failure_count = int(retry_state.get("failure_count", 0)) + 1
			var retry_delay_msec: int = mini(
				COMBINED_HALO_FAILURE_RETRY_MAX_DELAY_MSEC,
				COMBINED_HALO_FAILURE_RETRY_BASE_DELAY_MSEC \
						* (1 << mini(failure_count - 1, 4)),
			)
			_combined_halo_build_retry_by_chunk[chunk_coord] = {
				"epoch": _generation_epoch,
				"mountain_revision": mountain_revision,
				"terrain_revision": terrain_revision,
				"failure_count": failure_count,
				"not_before_msec": Time.get_ticks_msec() + retry_delay_msec,
			}
			return true
		mountain_halo = _mountain_solid_halo_cache.get(chunk_coord, { }) as Dictionary
		edge_halo = _terrain_edge_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	if MOUNTAIN_NATIVE_MASK_RUNTIME_ENABLED:
		if bool(mountain_halo.get("has_closed", false)) \
				and _get_ready_mountain_native_mask_result(chunk_coord).is_empty():
			var phase_started: int = WorldPerfProbe.begin()
			_request_mountain_native_mask_for_chunk(
				chunk_coord,
				mountain_halo,
				&"prefetch",
			)
			WorldPerfProbe.end("WorldStreamer.prefetch.mountain_request", phase_started)
	if TERRAIN_EDGE_MASK_RUNTIME_ENABLED:
		if bool(edge_halo.get("has_shoreline", false)) \
				and _get_ready_terrain_edge_mask_result(chunk_coord).is_empty():
			var phase_started: int = WorldPerfProbe.begin()
			_request_terrain_edge_mask_for_chunk(
				chunk_coord,
				edge_halo.get("halo", PackedByteArray()) as PackedByteArray,
				&"prefetch",
			)
			WorldPerfProbe.end("WorldStreamer.prefetch.terrain_request", phase_started)
	# Grass compute is data-only native work and does not wait for ChunkView
	# creation. Starting it from the already-valid 3x3 halo makes publication
	# consume a ready CPU result instead of beginning a ~0.2 s round trip.
	var phase_started: int = WorldPerfProbe.begin()
	_request_grass_scatter_build(chunk_coord)
	WorldPerfProbe.end("WorldStreamer.prefetch.grass_request", phase_started)
	return needs_combined_halo


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
		if chunk_coord == _active_publish_chunk \
				or _should_materialize_chunk(chunk_coord):
			continue
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		var cached_committed_objects: bool = false
		var committed_object_layer: WorldObjectPacketLayer = null
		if chunk_view:
			chunk_view.cancel_staged_mountain_roof_reveal_halo()
			_remove_mountain_cavity_skylight_field_chunk(chunk_coord)
			chunk_view.set_object_collision_active(false)
			committed_object_layer = chunk_view.detach_committed_object_layer_for_hot_cache()
		_chunk_views.erase(chunk_coord)
		if chunk_view:
			_cache_chunk_view(chunk_coord, chunk_view)
		_object_presentation_reveal_not_before_frame_by_chunk.erase(chunk_coord)
		if committed_object_layer != null:
			cached_committed_objects = _cache_committed_object_layer(
				chunk_coord,
				committed_object_layer,
			)
		_mountain_roof_reveal_selector_wait_chunks.erase(chunk_coord)
		if not _is_chunk_source_desired(chunk_coord):
			_store_warm_chunk_packet(
				chunk_coord,
				_base_chunk_packets.get(chunk_coord, { }) as Dictionary,
			)
			_base_chunk_packets.erase(chunk_coord)
			_chunk_packets.erase(chunk_coord)
		_requested_chunks.erase(chunk_coord)
		_pending_publish_queue.erase(chunk_coord)
		_pending_chunk_visibility_after_mountain_visual.erase(chunk_coord)
		_readiness_tracker.mark_terminal(chunk_coord, &"retained")
		_drop_object_packet_visual_upload(chunk_coord)
		var resident_entry: Dictionary = _get_current_hot_object_entry(chunk_coord)
		if not resident_entry.is_empty() and not bool(resident_entry.get("ready", false)):
			if _is_chunk_source_desired(chunk_coord):
				_queue_object_packet_visual_upload(chunk_coord)
			else:
				_evict_hot_object_presentation(chunk_coord)
		elif not cached_committed_objects \
				and resident_entry.is_empty() \
				and _is_chunk_source_desired(chunk_coord) \
				and _object_presentation_results_by_chunk.has(chunk_coord):
			_queue_hot_object_prestage(chunk_coord)
		_drop_grass_scatter_visual_upload(chunk_coord)
		_handle_cover_chunk_unloaded(chunk_coord)
		_try_commit_mountain_roof_reveal_selector_generation()
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
	if _world_compute_backend.has_pending_requests():
		return true
	if _packet_backend.has_completed_packets():
		return true
	if _mountain_mask_backend.has_completed_mountain_halo_masks():
		return true
	if _grass_scatter_backend.has_completed_grass_scatter_buffers():
		return true
	if _object_presentation_backend.has_completed_object_presentation_buffers():
		return true
	if not _object_presentation_inflight_chunks.is_empty():
		return true
	if not _grass_scatter_inflight_chunks.is_empty():
		return true
	if not _mountain_native_mask_inflight_chunks.is_empty():
		return true
	if not _requested_chunks.is_empty():
		return true
	if not _pending_mountain_native_mask_visual_upload_chunks.is_empty():
		return true
	if not _terrain_edge_mask_inflight_chunks.is_empty():
		return true
	if not _pending_terrain_edge_mask_visual_upload_chunks.is_empty():
		return true
	if not _pending_object_packet_visual_upload_chunks.is_empty():
		return true
	if not _pending_hot_object_prestage_chunks.is_empty():
		return true
	if not _pending_grass_scatter_visual_upload_chunks.is_empty():
		return true
	for chunk_coord_variant: Variant in _chunk_views.keys():
		if not _should_materialize_chunk(chunk_coord_variant as Vector2i):
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
	if _restore_warm_chunk_packet(chunk_coord):
		return
	_requested_chunks[chunk_coord] = true
	_packet_backend.queue_packet_request(
		chunk_coord,
		world_seed,
		world_version,
		_worldgen_settings_packed,
		_generation_epoch,
		_chunk_request_priority(chunk_coord),
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
	_reset_mountain_roof_reveal_presentation()
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _chunk_packets.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	for chunk_coord: Vector2i in chunk_coords:
		var base_packet: Dictionary = _base_chunk_packets.get(chunk_coord, { }) as Dictionary
		if base_packet.is_empty():
			base_packet = _chunk_packets.get(chunk_coord, { }) as Dictionary
		var refreshed_packet: Dictionary = _diff_store.apply_to_packet(base_packet)
		_chunk_packets[chunk_coord] = refreshed_packet
		_invalidate_grass_scatter(chunk_coord)
		_refresh_loaded_visuals_around_chunk_overrides(chunk_coord)
		_forget_mountain_mask(chunk_coord, true, true)
		_forget_terrain_edge_mask(chunk_coord, true, true)
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view:
			_track_roof_layer_metric(chunk_coord, _chunk_packets[chunk_coord] as Dictionary)
			# object_* arrays are immutable base output. Terrain-only diffs must
			# preserve the already committed batch buffers and tree collision.
			chunk_view.begin_apply(_chunk_packets[chunk_coord] as Dictionary, true, true)
			_request_grass_scatter_build(chunk_coord)
			_refresh_debug_visuals_for_chunk(chunk_coord)
			if not _pending_publish_queue.has(chunk_coord):
				_pending_publish_queue.append(chunk_coord)


func _refresh_loaded_visuals_around_chunk_overrides(center_chunk_coord: Vector2i) -> void:
	# The normal streaming path has no runtime diffs. Avoid nine key-array builds
	# and sorts for every completed packet in that overwhelmingly common case.
	if not _diff_store.has_any_diffs():
		return
	var origin_tiles: Array[Vector2i] = []
	for y: int in range(center_chunk_coord.y - 1, center_chunk_coord.y + 2):
		for x: int in range(center_chunk_coord.x - 1, center_chunk_coord.x + 2):
			var sample_chunk_coord: Vector2i = _canonicalize_chunk_coord(Vector2i(x, y))
			if not _diff_store.has_chunk_overrides(sample_chunk_coord):
				continue
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


func _configure_chunk_view(chunk_view: ChunkView, chunk_coord: Vector2i) -> void:
	chunk_view.configure(chunk_coord)
	# New/reloaded views must receive the current reveal blend before their
	# roof material exists, preventing a one-frame closed-roof flash.
	chunk_view.set_mountain_roof_reveal_blend(_mountain_roof_reveal_blend)
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
	if chunk_view.get_parent() == null:
		add_child(chunk_view)
	chunk_view.visible = false
	chunk_view.set_object_collision_active(false)


func _cache_chunk_view(chunk_coord: Vector2i, chunk_view: ChunkView) -> void:
	if chunk_view == null or not is_instance_valid(chunk_view):
		return
	if _hot_chunk_view_cache.has(chunk_coord):
		var replaced: Dictionary = _hot_chunk_view_cache.get(chunk_coord, { }) as Dictionary
		var replaced_view: ChunkView = replaced.get("view", null) as ChunkView
		if replaced_view != null and replaced_view != chunk_view:
			replaced_view.queue_free()
	_hot_chunk_view_cache_next_stamp += 1
	chunk_view.visible = false
	chunk_view.set_object_collision_active(false)
	chunk_view.prepare_for_chunk_view_cache()
	_hot_chunk_view_cache[chunk_coord] = {
		"view": chunk_view,
		"source_chunk": chunk_coord,
		"stamp": _hot_chunk_view_cache_next_stamp,
		"epoch": _generation_epoch,
		"grass_revision": int(_grass_scatter_revision_by_chunk.get(chunk_coord, -1)),
		"grass_committed": chunk_view.is_grass_scatter_presentation_committed(),
		"terrain_revision": int(_grass_scatter_revision_by_chunk.get(chunk_coord, -1)),
		"terrain_committed": chunk_view.is_terrain_cell_presentation_committed(),
	}
	_trim_hot_chunk_view_cache()


func _trim_hot_chunk_view_cache() -> void:
	while _hot_chunk_view_cache.size() > HOT_CHUNK_VIEW_CACHE_MAX_ENTRIES:
		var oldest_coord: Vector2i = INVALID_CHUNK_COORD
		var oldest_stamp: int = 9223372036854775807
		for coord_variant: Variant in _hot_chunk_view_cache.keys():
			var coord: Vector2i = coord_variant as Vector2i
			var entry: Dictionary = _hot_chunk_view_cache.get(coord, { }) as Dictionary
			var stamp: int = int(entry.get("stamp", oldest_stamp))
			if stamp < oldest_stamp:
				oldest_coord = coord
				oldest_stamp = stamp
		if oldest_coord == INVALID_CHUNK_COORD \
				and not _hot_chunk_view_cache.has(INVALID_CHUNK_COORD):
			break
		var entry: Dictionary = _hot_chunk_view_cache.get(oldest_coord, { }) as Dictionary
		_hot_chunk_view_cache.erase(oldest_coord)
		if oldest_coord != INVALID_CHUNK_COORD \
				and not _is_chunk_source_desired(oldest_coord) \
				and not _readiness_has_retained_data(oldest_coord):
			_readiness_tracker.mark_terminal(oldest_coord, &"evicted")
		var view: ChunkView = entry.get("view", null) as ChunkView
		if view != null and is_instance_valid(view):
			view.queue_free()


func _take_cached_chunk_view(chunk_coord: Vector2i) -> Dictionary:
	if _hot_chunk_view_cache.is_empty():
		return { }
	var selected_key: Vector2i = chunk_coord
	var exact: bool = _hot_chunk_view_cache.has(selected_key)
	if not exact:
		var oldest_stamp: int = 9223372036854775807
		for coord_variant: Variant in _hot_chunk_view_cache.keys():
			var coord: Vector2i = coord_variant as Vector2i
			var candidate: Dictionary = _hot_chunk_view_cache.get(coord, { }) as Dictionary
			var stamp: int = int(candidate.get("stamp", oldest_stamp))
			if stamp < oldest_stamp:
				selected_key = coord
				oldest_stamp = stamp
	var entry: Dictionary = _hot_chunk_view_cache.get(selected_key, { }) as Dictionary
	_hot_chunk_view_cache.erase(selected_key)
	if entry.is_empty():
		return { }
	entry["exact"] = exact
	if exact:
		_hot_chunk_view_cache_hit_count_total += 1
	else:
		_hot_chunk_view_pool_reuse_count_total += 1
	return entry


func _clear_hot_chunk_view_cache() -> void:
	for entry_variant: Variant in _hot_chunk_view_cache.values():
		var entry: Dictionary = entry_variant as Dictionary
		var view: ChunkView = entry.get("view", null) as ChunkView
		if view != null and is_instance_valid(view):
			view.queue_free()
	_hot_chunk_view_cache.clear()
	_hot_chunk_view_reuse_metadata_by_chunk.clear()


func _prewarm_chunk_view_cache() -> void:
	while _hot_chunk_view_cache.size() < HOT_CHUNK_VIEW_PREWARM_COUNT:
		var chunk_view := ChunkView.new()
		_configure_chunk_view(chunk_view, Vector2i.ZERO)
		chunk_view.prewarm_mountain_mask_visual_resources(
			(
				WorldRuntimeConstants.CHUNK_SIZE \
						+ MOUNTAIN_HALO_MASK_RADIUS_TILES * 2
			) * MOUNTAIN_HALO_MASK_PIXELS_PER_TILE,
			float(WorldRuntimeConstants.TILE_SIZE_PX) \
					/ float(MOUNTAIN_HALO_MASK_PIXELS_PER_TILE),
			_mountain_top_fill_texture,
			_mountain_face_fill_texture,
			_mountain_top_normal_fill_texture,
			_mountain_face_normal_fill_texture,
			_mountain_foothill_texture,
			_mountain_foothill_normal_texture,
		)
		_cache_chunk_view(INVALID_CHUNK_COORD, chunk_view)


func _can_preserve_cached_chunk_view_grass(
		cached: Dictionary,
		chunk_coord: Vector2i,
) -> bool:
	var preserve_grass: bool = bool(cached.get("exact", false)) \
			and bool(cached.get("grass_committed", false)) \
			and int(cached.get("epoch", -1)) == _generation_epoch \
			and int(cached.get("grass_revision", -1)) \
					== int(_grass_scatter_revision_by_chunk.get(chunk_coord, -2))
	if preserve_grass:
		_hot_chunk_view_grass_preserve_hit_count_total += 1
	return preserve_grass


func _can_preserve_cached_chunk_view_terrain(
		cached: Dictionary,
		chunk_coord: Vector2i,
) -> bool:
	var preserve_terrain: bool = bool(cached.get("exact", false)) \
			and bool(cached.get("terrain_committed", false)) \
			and int(cached.get("epoch", -1)) == _generation_epoch \
			and int(cached.get("terrain_revision", -1)) \
					== int(_grass_scatter_revision_by_chunk.get(chunk_coord, -2))
	if preserve_terrain:
		_hot_chunk_view_terrain_preserve_hit_count_total += 1
	return preserve_terrain


func _ensure_chunk_view(chunk_coord: Vector2i) -> ChunkView:
	var existing: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
	if existing != null:
		return existing
	var cached: Dictionary = _take_cached_chunk_view(chunk_coord)
	var chunk_view: ChunkView = cached.get("view", null) as ChunkView
	if chunk_view == null:
		chunk_view = ChunkView.new()
	_configure_chunk_view(chunk_view, chunk_coord)
	var preserve_grass: bool = _can_preserve_cached_chunk_view_grass(cached, chunk_coord)
	var preserve_terrain: bool = _can_preserve_cached_chunk_view_terrain(cached, chunk_coord)
	# Depth ownership is coordinate/player-relative, not a property of cached
	# grass. Seed it before a hot object layer can be adopted and revealed.
	if _ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
		chunk_view.seed_mid_ladder_z(_ladder_anchor_stripe)
	if preserve_grass:
		chunk_view.set_grass_scatter_lod_fraction(_grass_lod_fraction)
	_hot_chunk_view_reuse_metadata_by_chunk[chunk_coord] = {
		"preserve_grass": preserve_grass,
		"preserve_terrain": preserve_terrain,
	}
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
	# Tree/rock native batches share one catalog and the same ShaderMaterial
	# instances across every chunk. Update those uniforms once per accepted sun
	# change; per-chunk propagation below is only for chunk-owned legacy layers.
	_layered_object_asset_catalog.set_sun_lighting(
		_sun_shadow_length_px,
		_sun_shadow_opacity,
	)
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
		{ },
	) as Dictionary
	# Only the request that owns the current inflight marker may clear it. A
	# stale worker result must not cancel a newer in-flight rebuild.
	if int(inflight.get("revision", -1)) == result_revision:
		_mountain_native_mask_inflight_chunks.erase(target_chunk)
	if result_revision != expected_revision:
		return
	if not bool(result.get("success", false)):
		_schedule_mountain_native_mask_retry(
			target_chunk,
			result_revision,
			str(result.get("message", "")),
		)
		return
	_mountain_native_mask_retry_by_chunk.erase(target_chunk)
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
			and _should_materialize_chunk(target_chunk) \
			and not _pending_publish_queue.has(target_chunk) \
			and target_chunk != _active_publish_chunk:
		_pending_publish_queue.append(target_chunk)


func _schedule_mountain_native_mask_retry(
		target_chunk: Vector2i,
		revision: int,
		message: String,
) -> void:
	var previous: Dictionary = _mountain_native_mask_retry_by_chunk.get(
		target_chunk,
		{ },
	) as Dictionary
	var failure_count: int = 1
	if int(previous.get("epoch", -1)) == _generation_epoch \
			and int(previous.get("revision", -1)) == revision:
		failure_count = int(previous.get("failure_count", 0)) + 1
	var exhausted: bool = failure_count > MOUNTAIN_NATIVE_MASK_MAX_RETRY_ATTEMPTS
	var retry_delay_msec: int = MOUNTAIN_NATIVE_MASK_EXHAUSTED_RETRY_DELAY_MSEC \
			if exhausted else MOUNTAIN_NATIVE_MASK_RETRY_DELAY_MSEC
	_mountain_native_mask_retry_by_chunk[target_chunk] = {
		"epoch": _generation_epoch,
		"revision": revision,
		"failure_count": failure_count,
		"not_before_msec": Time.get_ticks_msec() + retry_delay_msec,
		"exhausted": exhausted,
	}
	if exhausted:
		# Exhaustion is a long cooldown, not a terminal poison pill. Keeping an
		# immutable failed state forever would let eight bad chunks occupy the
		# bounded publish scan window and freeze the rest of the world.
		if failure_count == MOUNTAIN_NATIVE_MASK_MAX_RETRY_ATTEMPTS + 1 \
				or failure_count % 16 == 0:
			push_warning(
				"Mountain native mask failed for chunk %s after %d attempts; retrying in %d ms: %s" % [
					str(target_chunk),
					failure_count,
					retry_delay_msec,
					message,
				],
			)
		return
	push_warning(
		"Mountain native mask failed for chunk %s; retry %d/%d in %d ms: %s" % [
			str(target_chunk),
			failure_count,
			MOUNTAIN_NATIVE_MASK_MAX_RETRY_ATTEMPTS,
			MOUNTAIN_NATIVE_MASK_RETRY_DELAY_MSEC,
			message,
		],
	)


func _retry_failed_mountain_native_masks(max_count: int) -> void:
	if max_count <= 0 or _mountain_native_mask_retry_by_chunk.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	var queued_count: int = 0
	for chunk_coord: Vector2i in _dictionary_vector2i_keys(
		_mountain_native_mask_retry_by_chunk,
	):
		if queued_count >= max_count:
			return
		var retry_state: Dictionary = _mountain_native_mask_retry_by_chunk.get(
			chunk_coord,
			{ },
		) as Dictionary
		if int(retry_state.get("epoch", -1)) != _generation_epoch \
				or int(retry_state.get("revision", -1)) != _get_mountain_mask_revision(chunk_coord):
			_mountain_native_mask_retry_by_chunk.erase(chunk_coord)
			continue
		if now_msec < int(retry_state.get("not_before_msec", 0)):
			continue
		if not _get_ready_mountain_native_mask_result(chunk_coord).is_empty():
			_mountain_native_mask_retry_by_chunk.erase(chunk_coord)
			continue
		var inflight: Dictionary = _mountain_native_mask_inflight_chunks.get(
			chunk_coord,
			{ },
		) as Dictionary
		if int(inflight.get("revision", -1)) == _get_mountain_mask_revision(chunk_coord):
			continue
		if not _chunk_packets.has(chunk_coord):
			_mountain_native_mask_retry_by_chunk.erase(chunk_coord)
			continue
		if not _has_loaded_mountain_halo_sources(chunk_coord):
			continue
		var halo_fields: Dictionary = _get_cached_mountain_solid_halo(chunk_coord)
		if not bool(halo_fields.get("has_closed", false)):
			_mountain_native_mask_retry_by_chunk.erase(chunk_coord)
			continue
		_request_mountain_native_mask_for_chunk(
			chunk_coord,
			halo_fields,
			&"retry",
		)
		inflight = _mountain_native_mask_inflight_chunks.get(chunk_coord, { }) as Dictionary
		if int(inflight.get("revision", -1)) == _get_mountain_mask_revision(chunk_coord):
			queued_count += 1


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
	return _has_loaded_chunk_halo_sources(chunk_coord)


func _has_loaded_terrain_edge_halo_sources(chunk_coord: Vector2i) -> bool:
	return _has_loaded_chunk_halo_sources(chunk_coord)


func _has_loaded_chunk_halo_sources(chunk_coord: Vector2i) -> bool:
	# Fixed 3x3 membership needs neither an allocated Array/Dictionary nor a
	# distance sort. This predicate runs repeatedly across the publish prefix.
	for source_offset_y: int in range(-1, 2):
		for source_offset_x: int in range(-1, 2):
			var source_chunk: Vector2i = chunk_coord + Vector2i(source_offset_x, source_offset_y)
			# Finite worlds have a real vertical edge. The former GDScript halo
			# builder omitted those cells; do not wait forever for a packet the
			# packet backend correctly refuses to generate.
			if _uses_finite_world_bounds() \
					and not _world_bounds_settings.is_chunk_y_in_bounds(source_chunk.y):
				continue
			source_chunk = _canonicalize_chunk_coord(source_chunk)
			if not _chunk_packets.has(source_chunk):
				_enqueue_chunk_if_needed(source_chunk)
				return false
	return true


func _request_mountain_native_mask_for_chunk(
		chunk_coord: Vector2i,
		halo_fields: Dictionary,
		reason: StringName,
) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _get_ready_mountain_native_mask_result(chunk_coord).is_empty():
		return
	var revision: int = _get_mountain_mask_revision(chunk_coord)
	var retry_state: Dictionary = _mountain_native_mask_retry_by_chunk.get(
		chunk_coord,
		{ },
	) as Dictionary
	if not retry_state.is_empty():
		if int(retry_state.get("epoch", -1)) != _generation_epoch \
				or int(retry_state.get("revision", -1)) != revision:
			_mountain_native_mask_retry_by_chunk.erase(chunk_coord)
		elif Time.get_ticks_msec() < int(retry_state.get("not_before_msec", 0)):
			return
		elif bool(retry_state.get("exhausted", false)):
			# Re-open the request after the long cooldown. failure_count remains in
			# the envelope for sparse diagnostics/backoff, but exhaustion can never
			# become a permanent queue blocker.
			retry_state["exhausted"] = false
			_mountain_native_mask_retry_by_chunk[chunk_coord] = retry_state
	var inflight: Dictionary = _mountain_native_mask_inflight_chunks.get(chunk_coord, { }) as Dictionary
	if not inflight.is_empty() and int(inflight.get("revision", -1)) == revision:
		return
	_mountain_native_mask_inflight_chunks[chunk_coord] = {
		"revision": revision,
		"reason": reason,
	}
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"mountain_mask",
		&"waiting",
		&"mountain_mask_worker_inflight",
	)
	# The live mask always builds from the post-diff remaining halo (pre-M7
	# behaviour, organic contour untouched). The closed/dug pair rides along
	# only for excavated chunks, where the worker derives the construction
	# roof C in the same request.
	var construction_roof_needed: bool = bool(halo_fields.get("has_dug", false))
	_mountain_mask_backend.queue_mountain_halo_mask_request(
		halo_fields.get("remaining_halo", halo_fields.get("halo", PackedByteArray())) as PackedByteArray,
		chunk_coord,
		_build_mountain_native_mask_origin(chunk_coord),
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		MOUNTAIN_HALO_MASK_PIXELS_PER_TILE,
		_generation_epoch,
		revision,
		reason,
		&"mountain",
		halo_fields.get("closed_halo", PackedByteArray()) as PackedByteArray \
		if construction_roof_needed else PackedByteArray(),
		halo_fields.get("dug_halo", PackedByteArray()) as PackedByteArray \
		if construction_roof_needed else PackedByteArray(),
		_chunk_request_priority(chunk_coord),
		_mask_compute_priority_class(reason),
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
	_readiness_tracker.mark_layer(
		chunk_coord,
		&"terrain_edge_mask",
		&"waiting",
		&"terrain_edge_mask_worker_inflight",
	)
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
		PackedByteArray(),
		PackedByteArray(),
		_chunk_request_priority(chunk_coord),
		_mask_compute_priority_class(reason),
	)


func _mask_compute_priority_class(reason: StringName) -> int:
	match reason:
		&"mining", &"torch_shadow_field":
			return WorldChunkPacketBackend.PRIORITY_CLASS_INTERACTIVE
		&"prefetch":
			return WorldChunkPacketBackend.PRIORITY_CLASS_BACKGROUND
		_:
			return WorldChunkPacketBackend.PRIORITY_CLASS_REVEAL


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
		"native_mask_elapsed_ms": elapsed_ms,
		"native_mask_worker_elapsed_ms": _mountain_native_mask_worker_elapsed_ms_last,
		"sky_exposure_worker_elapsed_ms": float(
			mask_result.get("sky_exposure_worker_elapsed_ms", 0.0),
		),
		"sky_exposure_reach_samples": int(
			mask_result.get("sky_exposure_reach_samples", 0),
		),
		"sky_exposure_source_sample_count": int(
			mask_result.get("sky_exposure_source_sample_count", 0),
		),
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
				dig_halo,
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
) -> int:
	var mask_bytes: PackedByteArray = mask_result.get("mask", PackedByteArray()) as PackedByteArray
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
			or target_bytes.size() != window_width * window_height:
		return 0
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
			for column_index: int in range(copy_width):
				var previous: int = int(target_bytes[dst_index])
				var value: int = int(mask_bytes[src_index])
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
			var value: int = int(mask_bytes[src_row + src_x])
			if value <= previous:
				continue
			target_bytes[dst_index] = value
			if previous <= MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD \
					and value > MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD:
				added_solid += 1
	return added_solid


func _forget_mountain_mask(
		chunk_coord: Vector2i,
		clear_view: bool,
		bump_revision: bool = false,
		preserve_visual: bool = false,
) -> void:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	_drop_mountain_native_mask_visual_upload(chunk_coord)
	_mountain_native_mask_retry_by_chunk.erase(chunk_coord)
	_combined_halo_build_retry_by_chunk.erase(chunk_coord)
	if bump_revision:
		_bump_mountain_mask_revision(chunk_coord)
		_mountain_torch_shadow_field_mask_cache.clear()
	_mountain_solid_halo_cache.erase(chunk_coord)
	_mountain_native_masks_by_chunk.erase(chunk_coord)
	_mountain_native_mask_inflight_chunks.erase(chunk_coord)
	if clear_view:
		if not preserve_visual:
			_remove_mountain_cavity_skylight_field_chunk(chunk_coord)
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
	_combined_halo_build_retry_by_chunk.erase(chunk_coord)
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
	_mountain_native_mask_retry_by_chunk.erase(chunk_coord)


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
	if not MOUNTAIN_NATIVE_MASK_RUNTIME_ENABLED and not TERRAIN_EDGE_MASK_RUNTIME_ENABLED:
		return true
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not _has_loaded_chunk_halo_sources(chunk_coord):
		return false
	if TERRAIN_EDGE_MASK_RUNTIME_ENABLED:
		var terrain_halo: Dictionary = _terrain_edge_solid_halo_cache.get(
			chunk_coord,
			{ },
		) as Dictionary
		if not _is_runtime_halo_cache_entry_current(
			terrain_halo,
			_get_terrain_edge_mask_revision(chunk_coord),
		):
			return false
	if not MOUNTAIN_NATIVE_MASK_RUNTIME_ENABLED:
		return true
	var cached_halo: Dictionary = _mountain_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	if not _is_runtime_halo_cache_entry_current(
		cached_halo,
		_get_mountain_mask_revision(chunk_coord),
	):
		return false
	if not bool(cached_halo.get("has_closed", false)):
		_mountain_native_masks_by_chunk.erase(chunk_coord)
		_mountain_native_mask_inflight_chunks.erase(chunk_coord)
		return true
	if not _get_ready_mountain_native_mask_result(chunk_coord).is_empty():
		return true
	_request_mountain_native_mask_for_chunk(
		chunk_coord,
		cached_halo,
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
	_readiness_tracker.reset(_generation_epoch)
	_initial_loading_gate.begin(_generation_epoch)
	_initial_loading_readiness_cursor = 0
	_world_compute_backend.clear_queued_work()
	_clear_hot_object_presentation_cache()
	_awaiting_new_game_spawn_result = false
	_new_game_spawn_failed = false
	_requested_chunks.clear()
	_pending_publish_queue.clear()
	_mountain_solid_halo_cache.clear()
	_terrain_edge_solid_halo_cache.clear()
	_combined_halo_build_retry_by_chunk.clear()
	_active_publish_chunk = INVALID_CHUNK_COORD
	_player_chunk_coord = INVALID_CHUNK_COORD
	_current_stream_radius_chunks = MAX_VIEWPORT_STREAM_RADIUS_CHUNKS
	_desired_source_chunk_coords.clear()
	_desired_visible_chunk_coords.clear()
	_desired_mountain_mask_chunk_coords.clear()
	_terrain_packet_support_chunk_coords.clear()
	_terrain_packet_support_chunk_set.clear()
	_desired_cache_center_chunk = INVALID_CHUNK_COORD
	_desired_cache_radius_chunks = -1
	_desired_cache_source_radius_chunks = -1
	_streaming_worker_demand_dirty = true
	_mountain_mask_revision_by_chunk.clear()
	_mountain_native_masks_by_chunk.clear()
	_mountain_native_mask_inflight_chunks.clear()
	_mountain_native_mask_retry_by_chunk.clear()
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
	_pending_object_packet_visual_upload_index_by_chunk.clear()
	_object_packet_visual_queue_repair_needed = false
	_object_packet_visual_queue_repair_cursor = 0
	_object_packet_visual_enqueued_turn_by_chunk.clear()
	_object_packet_visual_dispatch_turn = 0
	_focused_object_packet_visual_upload_chunk = INVALID_CHUNK_COORD
	_object_packet_visual_priority_dirty = true
	_object_packet_visual_urgent_priority_dirty = false
	_object_packet_visual_selection_phase_prepared = false
	_object_packet_visual_priority_scan_active = false
	_object_packet_visual_priority_scan_candidates.clear()
	_object_packet_visual_priority_scan_cursor = 0
	_object_packet_visual_priority_scan_best = INVALID_CHUNK_COORD
	_object_presentation_visual_lane_frame = -1
	_object_presentation_visual_lane_started_usec = 0
	_object_presentation_visual_lane_callback_count = 0
	_object_presentation_allocation_callback_count = 0
	_object_presentation_reveal_not_before_frame_by_chunk.clear()
	_pending_hot_object_prestage_chunks.clear()
	_pending_hot_object_prestage_set.clear()
	_object_presentation_revision_by_chunk.clear()
	_object_presentation_next_revision = 0
	_object_presentation_inflight_chunks.clear()
	_object_presentation_results_by_chunk.clear()
	_warm_object_presentation_cache.clear()
	_warm_object_presentation_cache_bytes_by_chunk.clear()
	_warm_object_presentation_cache_bytes = 0
	_object_presentation_cache_hit_count_total = 0
	_hot_object_presentation_cache_hit_count_total = 0
	_hot_object_presentation_cache_eviction_count_total = 0
	_object_presentation_worker_elapsed_ms_last = 0.0
	_object_presentation_worker_elapsed_ms_max_total = 0.0
	_object_presentation_request_to_complete_ms_last = 0.0
	_object_presentation_request_to_complete_ms_max_total = 0.0
	_object_presentation_retry_by_chunk.clear()
	_object_presentation_terminal_fallback_by_chunk.clear()
	_object_presentation_failure_count_total = 0
	_object_presentation_terminal_failure_count = 0
	_pending_grass_scatter_visual_upload_chunks.clear()
	_pending_grass_scatter_visual_upload_set.clear()
	_pending_grass_scatter_visual_upload_index_by_chunk.clear()
	_focused_grass_scatter_visual_upload_chunk = INVALID_CHUNK_COORD
	_grass_scatter_revision_by_chunk.clear()
	_grass_scatter_next_revision = 0
	_grass_scatter_inflight_chunks.clear()
	_grass_scatter_results_by_chunk.clear()
	_grass_scatter_retry_by_chunk.clear()
	_warm_grass_scatter_cache.clear()
	_warm_grass_scatter_cache_bytes_by_chunk.clear()
	_warm_grass_scatter_cache_bytes = 0
	_grass_scatter_cache_hit_count_total = 0
	_grass_scatter_worker_elapsed_ms_last = 0.0
	_grass_scatter_worker_elapsed_ms_max_total = 0.0
	_grass_scatter_request_to_complete_ms_last = 0.0
	_grass_scatter_request_to_complete_ms_max_total = 0.0
	_chunk_reveal_with_pending_grass_count_total = 0
	_mountain_native_mask_visual_upload_count_last_tick = 0
	_mountain_native_mask_visible_republish_skip_count_total = 0
	_mountain_surface_dig_visual_patch_skip_count_total = 0
	_last_mountain_mask_result = {
		"ready": false,
	}
	_last_terrain_edge_mask_result = {
		"ready": false,
	}
	_clear_mountain_cavity_skylight_field()
	_clear_hot_chunk_view_cache()
	_hot_chunk_view_cache_next_stamp = 0
	_hot_chunk_view_cache_hit_count_total = 0
	_hot_chunk_view_pool_reuse_count_total = 0
	_hot_chunk_view_grass_preserve_hit_count_total = 0
	_hot_chunk_view_terrain_preserve_hit_count_total = 0
	for chunk_view_variant: Variant in _chunk_views.values():
		var chunk_view: ChunkView = chunk_view_variant as ChunkView
		if chunk_view:
			chunk_view.set_object_collision_active(false)
			chunk_view.queue_free()
	_chunk_views.clear()
	_chunk_packets.clear()
	_base_chunk_packets.clear()
	_warm_base_chunk_packet_cache.clear()
	_warm_base_chunk_packet_cache_stamps.clear()
	_warm_base_chunk_packet_cache_next_stamp = 0
	_warm_packet_cache_hit_count_total = 0
	if _mining_feedback_layer != null and is_instance_valid(_mining_feedback_layer):
		_mining_feedback_layer.clear_feedback()
	roof_layers_per_chunk_max = 0
	_mountain_cavity_cache.clear()
	_active_cover_mountain_id = 0
	_active_cover_component_id = 0
	_reset_mountain_roof_reveal_presentation()
	_did_warn_roof_layer_explosion = false
	# New-world/reset startup is the loading boundary. Pay the bounded first-use
	# envelope cost here, before any moving-player reveal deadline exists.
	_warm_object_presentation_layer_pool()
	_prewarm_chunk_view_cache()


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
		_terrain_packet_support_chunk_coords.clear()
		_terrain_packet_support_chunk_set.clear()
		_desired_cache_center_chunk = INVALID_CHUNK_COORD
		_desired_cache_radius_chunks = -1
		_desired_cache_source_radius_chunks = -1
		_streaming_worker_demand_dirty = true
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
	_terrain_packet_support_chunk_coords = _build_chunk_coords_for_radius(
		_player_chunk_coord,
		source_radius + 1,
	)
	_terrain_packet_support_chunk_set.clear()
	for chunk_coord: Vector2i in _terrain_packet_support_chunk_coords:
		_terrain_packet_support_chunk_set[chunk_coord] = true
	_streaming_worker_demand_dirty = true


func _build_chunk_coords_for_radius(center_chunk: Vector2i, radius_chunks: int) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	var seen: Dictionary = { }
	for offset: Vector2i in _get_sorted_chunk_offsets(radius_chunks):
		var coord: Vector2i = _canonicalize_chunk_coord(center_chunk + offset)
		if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(coord.y):
			continue
		if seen.has(coord):
			continue
		seen[coord] = true
		coords.append(coord)
	return coords


func _get_sorted_chunk_offsets(radius_chunks: int) -> Array[Vector2i]:
	radius_chunks = maxi(0, radius_chunks)
	if _sorted_chunk_offsets_by_radius.has(radius_chunks):
		return _sorted_chunk_offsets_by_radius[radius_chunks] as Array[Vector2i]
	var offsets: Array[Vector2i] = []
	for y: int in range(-radius_chunks, radius_chunks + 1):
		for x: int in range(-radius_chunks, radius_chunks + 1):
			offsets.append(Vector2i(x, y))
	offsets.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var dist_a: int = a.length_squared()
			var dist_b: int = b.length_squared()
			return dist_a < dist_b \
					if dist_a != dist_b \
					else (a.x < b.x if a.x != b.x else a.y < b.y)
	)
	_sorted_chunk_offsets_by_radius[radius_chunks] = offsets
	return offsets


func _is_chunk_desired(chunk_coord: Vector2i) -> bool:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		return false
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
		return false
	return maxi(
		_wrapped_chunk_delta_abs(chunk_coord.x, _player_chunk_coord.x),
		absi(chunk_coord.y - _player_chunk_coord.y),
	) <= _current_stream_radius_chunks


func _should_materialize_chunk(chunk_coord: Vector2i) -> bool:
	return _is_chunk_source_desired(chunk_coord)


func _is_chunk_source_desired(chunk_coord: Vector2i) -> bool:
	if _player_chunk_coord == INVALID_CHUNK_COORD:
		return false
	if _uses_finite_world_bounds() and not _world_bounds_settings.is_chunk_y_in_bounds(chunk_coord.y):
		return false
	return maxi(
		_wrapped_chunk_delta_abs(chunk_coord.x, _player_chunk_coord.x),
		absi(chunk_coord.y - _player_chunk_coord.y),
	) <= _resolve_source_cache_radius_chunks()


func _is_terrain_packet_support_desired(chunk_coord: Vector2i) -> bool:
	return _terrain_packet_support_chunk_set.has(
		_canonicalize_chunk_coord(chunk_coord),
	)


func _is_chunk_packet_residency_desired(chunk_coord: Vector2i) -> bool:
	return _is_terrain_packet_support_desired(chunk_coord)


func _resolve_source_cache_radius_chunks() -> int:
	return _current_stream_radius_chunks + 1


## Residency is deliberately camera-independent. The envelope is sized once for
## the widest zoom the player may ever reach, so zooming can never create a
## generation request, a publish, an eviction or a chunk lifetime change; it
## only changes which already-resident chunks the renderer culls. Deriving the
## radius from the live camera made every zoom-out a streaming burst and every
## zoom-in an eviction burst, which is exactly the churn this system must not
## have.
func _resolve_stream_radius_chunks() -> int:
	return MAX_VIEWPORT_STREAM_RADIUS_CHUNKS


func _chunk_has_diff(chunk_coord: Vector2i) -> bool:
	return _diff_store.has_chunk_overrides(chunk_coord)


func _handle_cover_chunk_published(published_chunk_coord: Vector2i) -> void:
	var candidate_tiles: Array[Vector2i] = _collect_cover_candidate_tiles_for_chunk(
		published_chunk_coord,
	)
	# The cavity graph contains only runtime-excavated floor. Ordinary untouched
	# chunks have nothing to add and, while no component is displayed, require no
	# global component/visibility reconciliation at all.
	if candidate_tiles.is_empty() \
			and _active_cover_component_id <= 0 \
			and _displayed_cover_visual_chunks.is_empty():
		return
	var previous_displayed_chunks: Array[Vector2i] = \
			_dictionary_vector2i_keys(_displayed_cover_visual_chunks)
	var cover_result: Dictionary = _mountain_cavity_cache.on_chunk_loaded(
		published_chunk_coord,
		candidate_tiles,
		Callable(self, "_sample_mountain_cover_tile"),
	)
	_repair_active_cover_component_from_player_position()
	var affected_chunks: Dictionary = { published_chunk_coord: true }
	for previous_chunk: Vector2i in previous_displayed_chunks:
		affected_chunks[previous_chunk] = true
	var published_chunks: Array[Vector2i] = _variant_to_vector2i_array(cover_result.get("affected_chunks", []))
	for chunk_coord: Vector2i in published_chunks:
		affected_chunks[chunk_coord] = true
	_append_cover_component_chunks(affected_chunks, _displayed_cover_component_id)
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func _handle_cover_chunk_unloaded(chunk_coord: Vector2i) -> void:
	var dirty_world_tiles: Array[Vector2i] = _collect_diff_world_tiles_for_chunk(chunk_coord)
	if dirty_world_tiles.is_empty() \
			and _active_cover_component_id <= 0 \
			and _displayed_cover_visual_chunks.is_empty():
		return
	var previous_displayed_chunks: Array[Vector2i] = \
			_dictionary_vector2i_keys(_displayed_cover_visual_chunks)
	var cover_result: Dictionary = _mountain_cavity_cache.on_chunk_unloaded(
		chunk_coord,
		dirty_world_tiles,
		Callable(self, "_sample_mountain_cover_tile"),
	)
	_repair_active_cover_component_from_player_position()
	var affected_chunks: Dictionary = { chunk_coord: true }
	for previous_chunk: Vector2i in previous_displayed_chunks:
		affected_chunks[previous_chunk] = true
	var unloaded_chunks: Array[Vector2i] = _variant_to_vector2i_array(cover_result.get("affected_chunks", []))
	for affected_chunk: Vector2i in unloaded_chunks:
		affected_chunks[affected_chunk] = true
	_append_cover_component_chunks(affected_chunks, _displayed_cover_component_id)
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func _handle_cover_tile_dug(world_tile: Vector2i) -> void:
	var previous_active_component_id: int = _active_cover_component_id
	var previous_displayed_chunks: Array[Vector2i] = \
			_dictionary_vector2i_keys(_displayed_cover_visual_chunks)
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
		for previous_chunk: Vector2i in previous_displayed_chunks:
			affected_chunks[previous_chunk] = true
		_append_cover_component_chunks(affected_chunks, _displayed_cover_component_id)
	_refresh_cover_visibility_for_loaded_chunks(_dictionary_vector2i_keys(affected_chunks))


func _collect_cover_candidate_tiles_for_chunk(published_chunk_coord: Vector2i) -> Array[Vector2i]:
	var candidate_tiles: Dictionary = { }
	for sample_chunk_y: int in range(published_chunk_coord.y - 1, published_chunk_coord.y + 2):
		for sample_chunk_x: int in range(published_chunk_coord.x - 1, published_chunk_coord.x + 2):
			var sample_chunk_coord: Vector2i = _canonicalize_chunk_coord(
				Vector2i(sample_chunk_x, sample_chunk_y),
			)
			for local_coord: Vector2i in _diff_store.get_chunk_override_local_coords(sample_chunk_coord):
				candidate_tiles[_chunk_local_to_tile(sample_chunk_coord, local_coord)] = true
	return _dictionary_vector2i_keys(candidate_tiles)


func _collect_diff_world_tiles_for_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
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
		_sync_mountain_roof_reveal_target()
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
	_sync_mountain_roof_reveal_target()
	return {
		"state_changed": previous_mountain_id != next_mountain_id
		or previous_component_id != next_component_id,
		"previous_mountain_id": previous_mountain_id,
		"previous_component_id": previous_component_id,
		"mountain_id": next_mountain_id,
		"component_id": next_component_id,
	}


func _refresh_cover_visibility_for_loaded_chunks(target_chunks: Array[Vector2i] = []) -> void:
	if _displayed_cover_component_id > 0:
		var displayed_component_chunks: Dictionary = { }
		_append_cover_component_chunks(
			displayed_component_chunks,
			_displayed_cover_component_id,
		)
		for displayed_chunk: Vector2i in _expand_cover_visual_chunks(
			_dictionary_vector2i_keys(displayed_component_chunks),
		):
			_displayed_cover_visual_chunks[displayed_chunk] = true
	var refresh_chunks: Array[Vector2i] = _expand_cover_visual_chunks(target_chunks)
	# An empty target list must never mean "scan every loaded ChunkView"
	# callers name the dirty chunks explicitly (see mountain_generation.md M7).
	if refresh_chunks.is_empty():
		return
	# A refresh supersedes an in-flight selector generation. Re-stage every old
	# participant directly (without expanding it again, which would grow the
	# affected radius on every retry) so no uploaded stale texture can commit.
	var refresh_chunk_set: Dictionary = { }
	for chunk_coord: Vector2i in refresh_chunks:
		refresh_chunk_set[chunk_coord] = true
	for waiting_chunk: Vector2i in _dictionary_vector2i_keys(
		_mountain_roof_reveal_selector_wait_chunks,
	):
		if _chunk_views.has(waiting_chunk):
			refresh_chunk_set[waiting_chunk] = true
	refresh_chunks = _dictionary_vector2i_keys(refresh_chunk_set)
	_mountain_roof_reveal_selector_generation += 1
	if _mountain_roof_reveal_selector_generation <= 0:
		_mountain_roof_reveal_selector_generation = 1
	var selector_generation: int = _mountain_roof_reveal_selector_generation
	var next_wait_chunks: Dictionary = { }
	var floor_masks_by_chunk: Dictionary = { }
	for chunk_coord: Vector2i in refresh_chunks:
		var chunk_view: ChunkView = _chunk_views.get(chunk_coord) as ChunkView
		if chunk_view == null:
			continue
		chunk_view.set_mountain_roof_reveal_blend(_mountain_roof_reveal_blend)
		var selector_staged: bool = chunk_view.stage_mountain_roof_reveal_halo(
			_build_cover_floor_visibility_halo(
				chunk_coord,
				floor_masks_by_chunk,
				_displayed_cover_component_id,
			),
			selector_generation,
		)
		if not selector_staged:
			continue
		next_wait_chunks[chunk_coord] = selector_generation
		if not chunk_view.is_staged_mountain_roof_reveal_halo_ready(selector_generation):
			_queue_mountain_native_mask_visual_upload(chunk_coord)
	_mountain_roof_reveal_selector_wait_chunks = next_wait_chunks
	_try_commit_mountain_roof_reveal_selector_generation()


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


func _get_cached_cover_floor_mask(
		chunk_coord: Vector2i,
		cache: Dictionary,
		component_id: int,
) -> PackedByteArray:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	if not cache.has(chunk_coord):
		cache[chunk_coord] = _mountain_cavity_cache.build_chunk_component_floor_mask(
			chunk_coord,
			component_id,
		)
	return cache[chunk_coord] as PackedByteArray


func _build_cover_floor_visibility_halo(
		chunk_coord: Vector2i,
		floor_masks_by_chunk: Dictionary,
		component_id: int,
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
			var source_mask: PackedByteArray = _get_cached_cover_floor_mask(
				source_chunk,
				floor_masks_by_chunk,
				component_id,
			)
			for local_y: int in range(from_local_y, to_local_y):
				var source_y: int = local_y - source_base_y
				var target_row: int = (local_y + halo_radius) * halo_side
				var source_row: int = source_y * WorldRuntimeConstants.CHUNK_SIZE
				for local_x: int in range(from_local_x, to_local_x):
					var source_x: int = local_x - source_base_x
					visibility_halo[target_row + local_x + halo_radius] = source_mask[source_row + source_x]
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


func _build_native_mountain_halo_mask(solid_halo: PackedByteArray, mask_origin_world: Vector2) -> Dictionary:
	var world_core: Object = _get_contour_world_core()
	if world_core == null:
		return { }
	var result_variant: Variant = world_core.call(
		"build_mountain_halo_mask",
		solid_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		MOUNTAIN_HALO_MASK_PIXELS_PER_TILE,
		mask_origin_world.x,
		mask_origin_world.y,
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


func _build_combined_chunk_halo_fields(
		chunk_coord: Vector2i,
		halo_radius_tiles: int,
) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var packets_3x3: Array = []
	packets_3x3.resize(9)
	var packet_index: int = 0
	for source_offset_y: int in range(-1, 2):
		for source_offset_x: int in range(-1, 2):
			var source_chunk: Vector2i = chunk_coord + Vector2i(source_offset_x, source_offset_y)
			if _uses_finite_world_bounds() \
					and not _world_bounds_settings.is_chunk_y_in_bounds(source_chunk.y):
				# Explicit void slots preserve the old builder's zero-filled halo at
				# finite north/south borders while retaining the native fixed 3x3 ABI.
				packets_3x3[packet_index] = { "halo_source_present": false }
				packet_index += 1
				continue
			source_chunk = _canonicalize_chunk_coord(source_chunk)
			var packet: Dictionary = _chunk_packets.get(source_chunk, { }) as Dictionary
			if packet.is_empty():
				return {
					"success": false,
					"message": "missing halo source packet %s for %s" % [
						str(source_chunk),
						str(chunk_coord),
					],
				}
			packets_3x3[packet_index] = packet
			packet_index += 1
	var world_core: Object = _get_contour_world_core()
	if world_core == null:
		return {
			"success": false,
			"message": "WorldCore unavailable for combined chunk halo build",
		}
	var native_started: int = WorldPerfProbe.begin()
	var result_variant: Variant = world_core.call(
		"build_chunk_halo_fields",
		packets_3x3,
		halo_radius_tiles,
	)
	WorldPerfProbe.end("WorldStreamer.publish.combined_halo_native", native_started)
	if not result_variant is Dictionary:
		return {
			"success": false,
			"message": "WorldCore.build_chunk_halo_fields returned non-dictionary result",
		}
	var result: Dictionary = result_variant as Dictionary
	if not bool(result.get("success", false)):
		push_error(
			"WorldStreamer combined halo build failed for %s: %s" % [
				str(chunk_coord),
				str(result.get("message", "unknown native halo error")),
			],
		)
	return result


func _cache_combined_chunk_halo_fields(
		chunk_coord: Vector2i,
		fields: Dictionary,
) -> void:
	if not bool(fields.get("success", false)):
		return
	_combined_halo_build_retry_by_chunk.erase(chunk_coord)
	var remaining_halo: PackedByteArray = fields.get(
		"remaining_halo",
		PackedByteArray(),
	) as PackedByteArray
	var closed_halo: PackedByteArray = fields.get(
		"closed_halo",
		PackedByteArray(),
	) as PackedByteArray
	var dug_halo: PackedByteArray = fields.get("dug_halo", PackedByteArray()) as PackedByteArray
	_mountain_solid_halo_cache[chunk_coord] = {
		"revision": _get_mountain_mask_revision(chunk_coord),
		"epoch": _generation_epoch,
		"halo": remaining_halo,
		"remaining_halo": remaining_halo,
		"closed_halo": closed_halo,
		"dug_halo": dug_halo,
		"has_any": bool(fields.get("has_any", false)),
		"has_closed": bool(fields.get("has_closed", false)),
		"has_dug": bool(fields.get("has_dug", false)),
		"remaining_count": int(fields.get("remaining_count", 0)),
		"closed_count": int(fields.get("closed_count", 0)),
		"dug_count": int(fields.get("dug_count", 0)),
	}
	var terrain_edge_halo: PackedByteArray = fields.get(
		"terrain_edge_solid_halo",
		PackedByteArray(),
	) as PackedByteArray
	_terrain_edge_solid_halo_cache[chunk_coord] = {
		"revision": _get_terrain_edge_mask_revision(chunk_coord),
		"epoch": _generation_epoch,
		"halo": terrain_edge_halo,
		"has_shoreline": bool(fields.get("has_shoreline", false)),
		"solid_count": int(fields.get("terrain_edge_solid_count", 0)),
	}


func _is_runtime_halo_cache_entry_current(entry: Dictionary, revision: int) -> bool:
	return not entry.is_empty() \
			and int(entry.get("revision", -2)) == revision \
			and int(entry.get("epoch", -2)) == _generation_epoch


func _get_cached_mountain_solid_halo(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var revision: int = _get_mountain_mask_revision(chunk_coord)
	var cached: Dictionary = _mountain_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	if _is_runtime_halo_cache_entry_current(cached, revision):
		return cached
	var fields: Dictionary = _build_combined_chunk_halo_fields(
		chunk_coord,
		MOUNTAIN_HALO_MASK_RADIUS_TILES,
	)
	_cache_combined_chunk_halo_fields(chunk_coord, fields)
	var refreshed: Dictionary = _mountain_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	return refreshed if _is_runtime_halo_cache_entry_current(refreshed, revision) else { }


func _get_cached_terrain_edge_solid_halo(chunk_coord: Vector2i) -> Dictionary:
	chunk_coord = _canonicalize_chunk_coord(chunk_coord)
	var revision: int = _get_terrain_edge_mask_revision(chunk_coord)
	var cached: Dictionary = _terrain_edge_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	if _is_runtime_halo_cache_entry_current(cached, revision):
		return cached
	var fields: Dictionary = _build_combined_chunk_halo_fields(
		chunk_coord,
		TERRAIN_EDGE_HALO_MASK_RADIUS_TILES,
	)
	_cache_combined_chunk_halo_fields(chunk_coord, fields)
	var refreshed: Dictionary = _terrain_edge_solid_halo_cache.get(chunk_coord, { }) as Dictionary
	return refreshed if _is_runtime_halo_cache_entry_current(refreshed, revision) else { }


func _build_mountain_solid_halo(chunk_coord: Vector2i, halo_radius_tiles: int = 1) -> PackedByteArray:
	return _build_mountain_halo_fields(
		chunk_coord,
		halo_radius_tiles,
	).get("remaining_halo", PackedByteArray()) as PackedByteArray


func _build_mountain_halo_fields(chunk_coord: Vector2i, halo_radius_tiles: int = 1) -> Dictionary:
	var fields: Dictionary = _build_combined_chunk_halo_fields(
		chunk_coord,
		clampi(halo_radius_tiles, 1, WorldRuntimeConstants.CHUNK_SIZE),
	)
	return {
		"remaining_halo": fields.get("remaining_halo", PackedByteArray()),
		"closed_halo": fields.get("closed_halo", PackedByteArray()),
		"dug_halo": fields.get("dug_halo", PackedByteArray()),
		"has_any": bool(fields.get("has_any", false)),
		"has_closed": bool(fields.get("has_closed", false)),
		"has_dug": bool(fields.get("has_dug", false)),
	}


func _build_terrain_edge_solid_halo(chunk_coord: Vector2i, halo_radius_tiles: int = 1) -> PackedByteArray:
	var fields: Dictionary = _build_combined_chunk_halo_fields(
		chunk_coord,
		clampi(halo_radius_tiles, 1, WorldRuntimeConstants.CHUNK_SIZE),
	)
	return fields.get("terrain_edge_solid_halo", PackedByteArray()) as PackedByteArray


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
	if not _contour_world_core.has_method("build_chunk_halo_fields"):
		push_error("WorldCore missing build_chunk_halo_fields; combined halo runtime disabled.")
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


## Roof-bearing ownership survives excavation, unlike the raster check above:
## a fully dug local mountain no longer has non-walkable WALL/FOOT terrain but
## must still gate publish on its closed construction roof.
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
