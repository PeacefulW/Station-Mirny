class_name ChunkView
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const ChunkDebugVisualLayer = preload("res://core/systems/world/chunk_debug_visual_layer.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")
const WorldLayeredObjectAssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")
const DepthLadderBandRoot = preload("res://core/systems/world/depth_ladder_band_root.gd")
const MOUNTAIN_COVER_SHADER = preload("res://assets/shaders/mountain_cover_overlay.gdshader")
const MOUNTAIN_TOP_MASK_UNDERLAY_SHADER = preload("res://assets/shaders/mountain_top_mask_underlay.gdshader")
const MOUNTAIN_FOOTHILL_OVERLAY_SHADER = preload("res://assets/shaders/mountain_foothill_overlay.gdshader")
const WATER_SURFACE_SHADER = preload("res://assets/shaders/water_surface_material.gdshader")
const GRASS_BLOB_OVERLAY_SHADER = preload("res://assets/shaders/grass_blob_overlay.gdshader")
const ROCK_PATCH_OVERLAY_SHADER = preload("res://assets/shaders/rock_patch_overlay.gdshader")

# Collision uses the same native mask plus a narrow lip for antialiased overhang.
const MOUNTAIN_FACADE_COLLISION_DEPTH_PX: float = 12.0
const MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD: int = 107
# Mountain mask presentation textures and dressing are authored data: the
# registry-resolved material set below owns them (sampling_params = слайдеры).
const MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID: StringName = &"mountain:mask_underlay_material"
const MOUNTAIN_ROCK_UNDERLAY_ENABLED: bool = true
const MOUNTAIN_ROCK_UNDERLAY_Z_INDEX: int = 3
const MOUNTAIN_ROCK_UNDERLAY_TEXTURE_SCALE: float = 0.60
const MOUNTAIN_ROCK_UNDERLAY_OUTER_WIDTH_PX: float = 18.0
const MOUNTAIN_ROCK_UNDERLAY_OUTER_WIDTH_VARIATION_PX: float = 8.0
const MOUNTAIN_ROCK_UNDERLAY_INNER_WIDTH_PX: float = 12.0
const MOUNTAIN_ROCK_UNDERLAY_ALPHA: float = 1.0
const MOUNTAIN_ROCK_UNDERLAY_FILL_STRENGTH: float = 1.0
const MOUNTAIN_ROCK_UNDERLAY_FILL_ALPHA: float = 3.0
const MOUNTAIN_ROCK_UNDERLAY_MAX_ALPHA: float = 1.0
const MOUNTAIN_FOOTHILL_OVERLAY_ENABLED: bool = true
const MOUNTAIN_FOOTHILL_TEXTURE_SCALE: float = 0.60
const MOUNTAIN_FOOTHILL_OUTER_WIDTH_PX: float = 154.0
const MOUNTAIN_FOOTHILL_OUTER_WIDTH_VARIATION_PX: float = 96.0
const MOUNTAIN_FOOTHILL_INNER_WIDTH_PX: float = 54.0
const MOUNTAIN_FOOTHILL_ALPHA: float = 0.68
const TERRAIN_EDGE_FACADE_HEIGHT_PX: float = 22.0
const TERRAIN_EDGE_TOP_TEXTURE_SCALE: float = 0.70
const TERRAIN_EDGE_FACE_TEXTURE_SCALE: float = 0.38
const TERRAIN_EDGE_TOP_ALPHA: float = 1.0
const TERRAIN_EDGE_CONTOUR_THRESHOLD_LOW: float = 0.16
const TERRAIN_EDGE_CONTOUR_THRESHOLD_HIGH: float = 0.34
const TERRAIN_EDGE_TOP_BAND_PX: float = 88.0
const TERRAIN_EDGE_TOP_BAND_FEATHER_PX: float = 56.0
# Grass/rock are composed in the ground material from pure world-space fields
# (see ground_hybrid_material.gdshader). Per-chunk overlay sprites are the
# proven source of ruler-straight cuts on chunk borders and stay disabled.
const GRASS_BLOB_OVERLAY_ENABLED: bool = false
const GRASS_BLOB_TEXTURE_SCALE: float = 1.0
const GRASS_BLOB_PATCH_CELL_PX: float = 2750.0
const GRASS_BLOB_PATCH_DENSITY: float = 0.72
const GRASS_BLOB_PATCH_ALPHA: float = 0.88
const GRASS_BLOB_EDGE_CLEARANCE_PX: float = 30.0
const GRASS_BLOB_EDGE_FEATHER_LOW: float = 0.10
const GRASS_BLOB_EDGE_FEATHER_HIGH: float = 0.68
const GRASS_BLOB_MAX_ALPHA: float = 0.94
const GRASS_BLOB_NORMAL_MIX: float = 0.18
const GRASS_BLOB_NORMAL_STRENGTH: float = 0.18
const ROCK_PATCH_OVERLAY_ENABLED: bool = false
const ROCK_PATCH_TEXTURE_SCALE: float = 0.66
const ROCK_PATCH_CELL_PX: float = 1280.0
const ROCK_PATCH_DENSITY: float = 0.54
const ROCK_PATCH_ALPHA: float = 0.48
const ROCK_PATCH_EDGE_CLEARANCE_PX: float = 28.0
const MASK_UNDERLAY_CHUNK_OVERLAP_PX: float = 3.0
const MASK_SHADOW_CHUNK_OVERLAP_PX: float = 48.0
# Scree debris numeric knobs (texture comes from the mountain material set's
# &"scree_albedo" extra slot; presentation-only).
const MOUNTAIN_SCREE_STRENGTH: float = 1.0
const MOUNTAIN_SCREE_TEXTURE_SCALE: float = 1.0
const MOUNTAIN_SCREE_PATCH_SCALE_PX: float = 760.0
const MOUNTAIN_SCREE_COVERAGE: float = 0.38

enum GrassScatterApplyPhase {
	IDLE,
	PREPARE,
	SHADOW_BLOB,
	SPORE_BLOB,
	DIRECTIONAL_SHADOW,
	STRIPES,
	COMMIT,
}

var chunk_coord: Vector2i = Vector2i.ZERO

var _base_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var _water_layer: TileMapLayer = null
var _water_fill_sprite: Sprite2D = null
var _water_fill_texture: ImageTexture = null
var _water_fill_material: ShaderMaterial = null
var _water_fill_sync_pending: bool = false
var _debug_layer: ChunkDebugVisualLayer = null
var roof_layers_by_mountain: Dictionary = { }
var _roof_mask_images_by_mountain: Dictionary = { }
var _roof_mask_textures_by_mountain: Dictionary = { }
var _pending_terrain_ids: PackedInt32Array = PackedInt32Array()
var _pending_terrain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _pending_walkable_flags: PackedByteArray = PackedByteArray()
var _pending_lake_flags: PackedByteArray = PackedByteArray()
var _pending_mountain_ids: PackedInt32Array = PackedInt32Array()
var _pending_mountain_flags: PackedByteArray = PackedByteArray()
var _pending_mountain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _pending_world_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var _pending_world_version: int = WorldRuntimeConstants.WORLD_VERSION
var _apply_index: int = 0
var _has_applied_cells: bool = false
var _bulk_apply_layers_pristine: bool = false
var _bulk_pattern_apply_active: bool = false
var _pending_base_pattern: TileMapPattern = null
var _pending_overlay_pattern: TileMapPattern = null
var _debug_grid_visible: bool = false
var _debug_solid_mask_visible: bool = false
var _debug_contour_visible: bool = false
var _mountain_tile_visuals_enabled: bool = true
var _skip_full_mountain_surface_apply: bool = false
var _mountain_page_sprite: Sprite2D = null
var _mountain_top_mask_sprite: Sprite2D = null
var _mountain_page_texture: ImageTexture = null
var _mountain_page_image: Image = null
var _mountain_page_normal_texture: ImageTexture = null
var _mountain_page_lit_texture: CanvasTexture = null
var _mountain_top_mask_texture: ImageTexture = null
var _mountain_top_mask_image: Image = null
var _mountain_top_mask_bytes: PackedByteArray = PackedByteArray()
var _mountain_top_mask_width: int = 0
var _mountain_top_mask_height: int = 0
var _mountain_top_mask_material: ShaderMaterial = null
var _mountain_top_mask_origin_world: Vector2 = Vector2.ZERO
var _mountain_top_mask_step_px: float = 0.0
var _mountain_top_mask_texture_scale: float = 0.70
var _mountain_top_mask_visual_dirty: bool = false
# The construction roof is a second, presentation-only copy of the immutable
# closed mountain silhouette (the mask as it was before any excavation).
# Collision and mining keep reading the live `_mountain_top_mask_bytes`
# BASE keeps rendering the live organic mask while ROOF renders CLOSED and
# fades its final contribution over the displayed connected component.
var _mountain_closed_roof_mask_sprite: Sprite2D = null
var _mountain_closed_roof_mask_texture: ImageTexture = null
var _mountain_closed_roof_mask_image: Image = null
var _mountain_closed_roof_mask_bytes: PackedByteArray = PackedByteArray()
var _mountain_closed_roof_mask_material: ShaderMaterial = null
var _mountain_closed_roof_mask_visual_dirty: bool = false
var _mountain_sky_exposure_texture: ImageTexture = null
var _mountain_sky_exposure_image: Image = null
var _mountain_sky_exposure_bytes: PackedByteArray = PackedByteArray()
var _mountain_sky_exposure_reach_samples: int = 0
var _mountain_sky_exposure_source_sample_count: int = 0
var _mountain_sky_exposure_visual_dirty: bool = false
var _mountain_roof_reveal_blend: float = 0.0
# CPU tile-halo fields share the native mask's UV extent (chunk 16x16 plus the
# 8-tile native halo). The displayed-component selector and the dug guard are
# presentation fields only: they never mutate remaining mass or collision.
var _mountain_active_floor_halo_bytes: PackedByteArray = PackedByteArray()
var _mountain_active_floor_halo_image: Image = null
var _mountain_active_floor_halo_texture: ImageTexture = null
var _mountain_active_floor_halo_side: int = 0
var _mountain_active_floor_halo_nonzero_count: int = 0
var _mountain_active_floor_halo_visual_dirty: bool = false
# A resolver refresh is uploaded into a texture that is deliberately not bound
# to the roof material. WorldStreamer commits every affected chunk together
# only after the complete selector generation is GPU-ready.
var _mountain_staged_floor_halo_bytes: PackedByteArray = PackedByteArray()
var _mountain_staged_floor_halo_image: Image = null
var _mountain_staged_floor_halo_texture: ImageTexture = null
var _mountain_staged_floor_halo_side: int = 0
var _mountain_staged_floor_halo_generation: int = 0
var _mountain_staged_floor_halo_nonzero_count: int = 0
var _mountain_staged_floor_halo_visual_dirty: bool = false
var _mountain_dug_halo_bytes: PackedByteArray = PackedByteArray()
var _mountain_dug_halo_image: Image = null
var _mountain_dug_halo_texture: ImageTexture = null
var _mountain_dug_halo_side: int = 0
var _mountain_dug_halo_nonzero_count: int = 0
var _mountain_dug_halo_visual_dirty: bool = false
var _mountain_rock_underlay_sprite: Sprite2D = null
var _mountain_rock_underlay_material: ShaderMaterial = null
var _mountain_rock_underlay_canvas_texture: ImageTexture = null
var _mountain_foothill_overlay_sprite: Sprite2D = null
var _mountain_foothill_overlay_material: ShaderMaterial = null
var _mountain_foothill_overlay_canvas_texture: ImageTexture = null
var _mountain_foothill_mask_texture: ImageTexture = null
var _mountain_foothill_mask_width: int = 0
var _mountain_foothill_mask_height: int = 0
var _mountain_foothill_mask_origin_world: Vector2 = Vector2.ZERO
var _mountain_foothill_mask_step_px: float = 0.0
var _mountain_interior_fill_active: bool = false
var _sun_light_angle_deg: float = WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG
var _sun_shadow_length_px: float = WorldVisualLightingProfile.DEFAULT_SHADOW_LENGTH_PX
var _sun_shadow_opacity: float = WorldVisualLightingProfile.DEFAULT_SHADOW_OPACITY
var _sun_shadow_softness_px: float = WorldVisualLightingProfile.DEFAULT_SHADOW_SOFTNESS_PX
var _terrain_edge_mask_sprite: Sprite2D = null
var _terrain_edge_mask_texture: ImageTexture = null
var _terrain_edge_mask_image: Image = null
var _terrain_edge_mask_bytes: PackedByteArray = PackedByteArray()
var _terrain_edge_mask_width: int = 0
var _terrain_edge_mask_height: int = 0
var _terrain_edge_mask_material: ShaderMaterial = null
var _terrain_edge_mask_origin_world: Vector2 = Vector2.ZERO
var _terrain_edge_mask_step_px: float = 0.0
var _terrain_edge_mask_visual_dirty: bool = false
var _grass_blob_overlay_sprite: Sprite2D = null
var _grass_blob_overlay_material: ShaderMaterial = null
var _grass_blob_overlay_canvas_texture: ImageTexture = null
var _rock_patch_overlay_sprite: Sprite2D = null
var _rock_patch_overlay_material: ShaderMaterial = null
var _rock_patch_overlay_canvas_texture: ImageTexture = null
var _living_flora_atlas: Texture2D = null
var _spiky_flora_atlases: Array[Texture2D] = []
var _tree_atlas: Texture2D = null
var _layered_tree_asset_dir: String = ""
var _layered_tree_asset_dirs: Array[String] = []
var _layered_small_rock_asset_dir: String = ""
var _layered_small_rock_asset_dirs: Array[String] = []
var _object_packet_layer: WorldObjectPacketLayer = null
var _object_packet_layer_uses_external_parent: bool = false
var _debug_object_collisions_visible: bool = false
var _object_packet_visual_dirty: bool = false
var _pending_object_packet_visual: Dictionary = { }
var _pending_object_presentation_result: Dictionary = { }
var _object_presentation_catalog: WorldLayeredObjectAssetCatalog = null
var _object_packet_visual_started: bool = false
var _object_presentation_apply_failure: String = ""
var _grass_scatter_layers: Array[MultiMeshInstance2D] = []
var _grass_shadow_atlas_layers: Array[MultiMeshInstance2D] = []
var _grass_directional_shadow_layer: MultiMeshInstance2D = null
var _grass_depth_ladder: DepthLadderBandRoot = null
var _grass_shadow_layer: MultiMeshInstance2D = null
var _grass_spore_layer: MultiMeshInstance2D = null
var _grass_scatter_visual_dirty: bool = false
var _pending_grass_scatter_result: Dictionary = { }
var _grass_scatter_apply_phase: int = GrassScatterApplyPhase.IDLE
var _grass_scatter_apply_stripe: int = 0
var _grass_scatter_apply_uses_shadow_atlas: bool = false
var _grass_scatter_apply_consolidates_directional_shadow: bool = false
var _grass_scatter_presentation_hidden: bool = false
const LADDER_ANCHOR_UNSET: int = 1 << 30
var _applied_ladder_anchor_stripe: int = LADDER_ANCHOR_UNSET
var _mountain_page_hit_mask: PackedByteArray = PackedByteArray()
var _mountain_page_hit_mask_width: int = 0
var _mountain_page_hit_mask_height: int = 0
var _mountain_page_hit_mask_origin_world: Vector2 = Vector2.ZERO
var _mountain_page_hit_mask_step_px: float = 0.0
var _mountain_page_render_origin_world: Vector2 = Vector2.ZERO
var _mountain_page_debug: Dictionary = {
	"ready": false,
}
var _debug_solid_mask: PackedByteArray = PackedByteArray()
var _debug_contour_vertices: PackedVector2Array = PackedVector2Array()
var _debug_contour_indices: PackedInt32Array = PackedInt32Array()


func _exit_tree() -> void:
	_roof_mask_images_by_mountain.clear()
	_roof_mask_textures_by_mountain.clear()


func configure(new_chunk_coord: Vector2i) -> void:
	chunk_coord = new_chunk_coord
	position = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	if _grass_depth_ladder != null and is_instance_valid(_grass_depth_ladder):
		_grass_depth_ladder.set_world_origin_y(position.y)
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_world_origin_y(position.y)
	_ensure_layers()


func begin_apply(
		packet: Dictionary,
		defer_object_visual: bool = false,
		preserve_object_visual: bool = false,
		preserve_grass_visual: bool = false,
		preserve_terrain_cells: bool = false,
) -> void:
	var step_started: int = WorldPerfProbe.begin()
	var packet_world_seed: int = int(packet.get("world_seed", WorldRuntimeConstants.DEFAULT_WORLD_SEED))
	var packet_world_version: int = int(packet.get("world_version", WorldRuntimeConstants.WORLD_VERSION))
	_pending_world_seed = packet_world_seed
	_pending_world_version = packet_world_version
	_pending_terrain_ids = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_terrain_atlas_indices = (packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_walkable_flags = (packet.get("walkable_flags", PackedByteArray()) as PackedByteArray).duplicate()
	_pending_lake_flags = (packet.get("lake_flags", PackedByteArray()) as PackedByteArray).duplicate()
	if _pending_lake_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_pending_lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_pending_mountain_ids = (packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_mountain_flags = (packet.get("mountain_flags", PackedByteArray()) as PackedByteArray).duplicate()
	_pending_mountain_atlas_indices = (packet.get("mountain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	WorldPerfProbe.end("ChunkView.begin_apply.copy_packet", step_started)
	step_started = WorldPerfProbe.begin()
	# Even a chunk that is all mountain surface needs a foothill underlay,
	# because the native mountain mask has organic transparent edges.
	_skip_full_mountain_surface_apply = false
	var reuse_terrain_cells: bool = preserve_terrain_cells \
			and is_terrain_cell_presentation_committed()
	_apply_index = _pending_terrain_ids.size() if reuse_terrain_cells else 0
	_bulk_apply_layers_pristine = false if reuse_terrain_cells else not _has_applied_cells
	# Production mountains are the exact native organic mask, not square roof
	# tiles. Build base/overlay records into hidden patterns and commit each layer
	# once; the compatibility tile renderer keeps the legacy cell path below.
	_bulk_pattern_apply_active = not reuse_terrain_cells \
			and not _mountain_tile_visuals_enabled \
			and _pending_terrain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT
	_pending_base_pattern = TileMapPattern.new() if _bulk_pattern_apply_active else null
	_pending_overlay_pattern = TileMapPattern.new() if _bulk_pattern_apply_active else null
	visible = false
	set_object_collision_active(false)
	WorldPerfProbe.end("ChunkView.begin_apply.state", step_started)
	step_started = WorldPerfProbe.begin()
	_ensure_layers()
	WorldPerfProbe.end("ChunkView.begin_apply.ensure_layers", step_started)
	# Water-fill resource creation is a real GPU-side publish phase. Defer it to
	# the first terrain batch so a cold Sprite/Material/ImageTexture allocation
	# cannot stack on the same callback as ChunkView acquisition/configuration.
	# Exact terrain reuse already owns the matching committed water presentation.
	_water_fill_sync_pending = not reuse_terrain_cells
	step_started = WorldPerfProbe.begin()
	if preserve_object_visual:
		pass
	elif defer_object_visual:
		# Production presentation is staged from the worker result. Do not retain
		# the full packet while waiting; this field remains only for the legacy
		# synchronous path used by isolated compatibility tests.
		_pending_object_packet_visual.clear()
		# This Dictionary may still be owned by WorldStreamer's live/warm cache.
		# Drop our reference; mutating it with clear() would corrupt that cache.
		_pending_object_presentation_result = { }
		_object_packet_visual_dirty = true
		_object_packet_visual_started = false
		_object_presentation_apply_failure = ""
		if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
			_object_packet_layer.cancel_pending_presentation_apply()
	else:
		_sync_object_packet_visual(packet)
	if not preserve_grass_visual:
		_grass_scatter_visual_dirty = true
		# A pooled view may still own the previous coordinate's committed buffers.
		# Hide them while the view itself is behind the reveal gate so stale grass
		# can never flash if lower-priority upload work starts a frame later.
		_hide_grass_scatter_presentation()
		# A newer terrain revision cancels any hidden partial GPU transaction. Keep
		# already allocated slots for reuse, but release the immutable result owner.
		_pending_grass_scatter_result = { }
		_grass_scatter_apply_phase = GrassScatterApplyPhase.IDLE
		_grass_scatter_apply_stripe = 0
		_grass_scatter_apply_uses_shadow_atlas = false
		_grass_scatter_apply_consolidates_directional_shadow = false
	WorldPerfProbe.end("ChunkView.begin_apply.sync_objects", step_started)
	step_started = WorldPerfProbe.begin()
	if _debug_solid_mask_visible:
		_refresh_debug_solid_mask()
	WorldPerfProbe.end("ChunkView.begin_apply.refresh_debug", step_started)


func apply_pending_object_packet_visual() -> bool:
	if not _object_packet_visual_dirty:
		return false
	if not _object_packet_visual_started:
		if _pending_object_presentation_result.is_empty() \
				or _object_presentation_catalog == null:
			return false
		var layer: WorldObjectPacketLayer = _ensure_object_packet_layer()
		layer.set_world_origin_y(position.y)
		if not layer.begin_presentation_result(
			_pending_object_presentation_result,
			_object_presentation_catalog,
		):
			_pending_object_presentation_result = { }
			_object_presentation_apply_failure = \
					"native object presentation result failed main-thread contract validation"
			layer.cancel_pending_presentation_apply()
			return false
		_pending_object_packet_visual.clear()
		_pending_object_presentation_result = { }
		_object_packet_visual_started = true
		_apply_sun_lighting_to_object_packet_layer()
		# New stripe slots inherit the anchor stored by their batch layer. Seed it
		# once before the first slot is created; rewalking every already-created
		# grass/object stripe after every tiny upload slice was an accidental
		# O(loaded stripes) multiplier on this hot path.
		if _applied_ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
			layer.update_ladder_z(_applied_ladder_anchor_stripe)
		if layer.is_presentation_complete():
			_object_packet_visual_dirty = false
			_object_packet_visual_started = false
		# Catalog/batch-owner setup is a real main-thread operation. Keep it in a
		# separate scheduler slice instead of coupling it to the first GPU buffer
		# assignment; the priority upload job guarantees the extra slice cannot be
		# starved behind broad packet publication.
		return true
	var progressed: bool = _object_packet_layer.apply_next_presentation_slice(1, 4, 1)
	if _object_packet_layer.is_presentation_complete():
		_object_packet_visual_dirty = false
		_object_packet_visual_started = false
	return progressed


func stage_object_presentation_result(
		result: Dictionary,
		catalog: WorldLayeredObjectAssetCatalog,
) -> bool:
	if not _object_packet_visual_dirty \
			or _object_packet_visual_started \
			or not _pending_object_presentation_result.is_empty() \
			or catalog == null \
			or not catalog.is_ready():
		return false
	# Own the staging envelope without copying its immutable packed payloads.
	# This prevents local lifecycle resets from aliasing the streamer's cache.
	_pending_object_presentation_result = result.duplicate(false)
	_object_presentation_catalog = catalog
	_object_presentation_apply_failure = ""
	return true


func is_object_blocking_presentation_ready() -> bool:
	if not _object_packet_visual_dirty:
		return true
	return _object_packet_visual_started \
			and _object_packet_layer != null \
			and _object_packet_layer.is_blocking_presentation_ready()


func has_pending_object_presentation_apply() -> bool:
	return _object_packet_visual_dirty


func has_staged_object_presentation_result() -> bool:
	return _object_packet_visual_started or not _pending_object_presentation_result.is_empty()


func is_object_presentation_complete() -> bool:
	return not _object_packet_visual_dirty


## Transfers a fully committed native object layer to WorldStreamer's bounded
## hot cache without destroying its MultiMeshes/collision shapes. Terrain and
## mountain state remain owned by this ChunkView and are never cached here.
func detach_committed_object_layer_for_hot_cache() -> WorldObjectPacketLayer:
	if _object_packet_layer == null \
			or not is_instance_valid(_object_packet_layer) \
			or _object_packet_visual_dirty \
			or not _object_packet_layer.is_hot_cache_eligible():
		return null
	var layer: WorldObjectPacketLayer = _object_packet_layer
	layer.set_hot_cache_resident(true)
	if layer.get_parent() == self:
		remove_child(layer)
	_object_packet_layer = null
	_object_packet_layer_uses_external_parent = false
	return layer


## Restores a GPU-resident object layer into a fresh view. The caller validates
## generation/revision/catalog keys before adoption; this method restores only
## local ownership and reveal state, without scanning a packet or uploading a
## MultiMesh buffer again.
func adopt_committed_object_layer_from_hot_cache(layer: WorldObjectPacketLayer) -> bool:
	if layer == null \
			or not is_instance_valid(layer) \
			or not layer.is_hot_cache_eligible() \
		or (_object_packet_layer != null and is_instance_valid(_object_packet_layer)):
		return false
	var step_started: int = WorldPerfProbe.begin()
	var previous_parent: Node = layer.get_parent()
	_object_packet_layer_uses_external_parent = layer.is_streaming_world_parented() \
			and previous_parent != null \
			and previous_parent != self
	if previous_parent == null:
		add_child(layer)
		_object_packet_layer_uses_external_parent = false
	if not _object_packet_layer_uses_external_parent:
		if layer.get_parent() != self:
			if layer.get_parent() != null:
				layer.get_parent().remove_child(layer)
			add_child(layer)
		layer.set_streaming_world_parented(false)
	WorldPerfProbe.end("ChunkView.object_adopt.parent", step_started)
	step_started = WorldPerfProbe.begin()
	_object_packet_layer = layer
	if not _object_packet_layer_uses_external_parent:
		layer.position = Vector2.ZERO
		_sync_object_packet_layer_sources(layer)
	layer.set_world_origin_y(position.y)
	layer.set_debug_collisions_visible(_debug_object_collisions_visible)
	# Externally parented GPU layers do not inherit ChunkView.visible. Keep them
	# hidden until the same atomic reveal call that enables blocking collision.
	layer.set_hot_cache_resident(_object_packet_layer_uses_external_parent and not visible)
	WorldPerfProbe.end("ChunkView.object_adopt.state", step_started)
	step_started = WorldPerfProbe.begin()
	_pending_object_packet_visual = { }
	_pending_object_presentation_result = { }
	_object_presentation_catalog = null
	_object_packet_visual_dirty = false
	_object_packet_visual_started = false
	_object_presentation_apply_failure = ""
	WorldPerfProbe.end("ChunkView.object_adopt.clear_staging", step_started)
	step_started = WorldPerfProbe.begin()
	_apply_sun_lighting_to_object_packet_layer()
	WorldPerfProbe.end("ChunkView.object_adopt.lighting", step_started)
	step_started = WorldPerfProbe.begin()
	if _applied_ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
		layer.update_ladder_z(_applied_ladder_anchor_stripe)
	WorldPerfProbe.end("ChunkView.object_adopt.ladder", step_started)
	return true


## Last-resort recovery for a deterministic native-contract failure. It is
## intentionally outside the normal frame path: after bounded worker retries,
## preserving authored objects through the proven compatibility renderer is
## preferable to a permanently hidden chunk and an endless streaming poll.
func apply_terminal_object_presentation_fallback(packet: Dictionary) -> bool:
	if packet.is_empty():
		return false
	var layer: WorldObjectPacketLayer = _ensure_object_packet_layer()
	_sync_object_packet_layer_sources(layer)
	layer.set_world_origin_y(position.y)
	layer.configure_packet(packet)
	layer.mark_legacy_fallback_ready_for_reveal()
	layer.set_blocking_collision_active(false)
	_pending_object_packet_visual = { }
	_pending_object_presentation_result = { }
	_object_presentation_catalog = null
	_object_packet_visual_dirty = false
	_object_packet_visual_started = false
	_object_presentation_apply_failure = ""
	_apply_sun_lighting_to_object_packet_layer()
	if _applied_ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
		layer.update_ladder_z(_applied_ladder_anchor_stripe)
	return true


func set_object_collision_active(active: bool) -> void:
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		if _object_packet_layer_uses_external_parent:
			_object_packet_layer.set_hot_cache_resident(not active)
		_object_packet_layer.set_blocking_collision_active(active)


## Drops every coordinate-bound mask before this reusable view enters the pool.
## Grass buffers are deliberately excluded: an exact epoch+revision hit may
## retain them, while begin_apply() hides them immediately on generic reuse.
func prepare_for_chunk_view_cache() -> void:
	cancel_staged_mountain_roof_reveal_halo()
	# Retain only empty GPU allocations in the bounded hot pool. Coordinate-
	# bound bytes/state are cleared and every sprite is hidden; the next mask
	# fully overwrites these RIDs behind the normal reveal gate.
	clear_mountain_render_page(false, true)
	clear_terrain_edge_mask(true)
	if _grass_scatter_visual_dirty:
		# A partial transaction is neither reusable nor covered by the warm CPU
		# payload budget. Drop its immutable envelope and uploaded fragments while
		# preserving fully committed graphs for validated exact-coordinate hits.
		_pending_grass_scatter_result = { }
		_grass_scatter_apply_phase = GrassScatterApplyPhase.IDLE
		_grass_scatter_apply_stripe = 0
		_grass_scatter_apply_uses_shadow_atlas = false
		_grass_scatter_apply_consolidates_directional_shadow = false
		for layer: MultiMeshInstance2D in _grass_scatter_layers:
			if layer != null and is_instance_valid(layer):
				layer.visible = false
				layer.multimesh = null
				if _grass_depth_ladder != null and is_instance_valid(_grass_depth_ladder):
					_grass_depth_ladder.unregister_item(layer)
		for layer: MultiMeshInstance2D in _grass_shadow_atlas_layers:
			if layer != null and is_instance_valid(layer):
				layer.visible = false
				layer.multimesh = null
		if _grass_directional_shadow_layer != null \
				and is_instance_valid(_grass_directional_shadow_layer):
			_grass_directional_shadow_layer.visible = false
			_grass_directional_shadow_layer.multimesh = null
		if _grass_shadow_layer != null and is_instance_valid(_grass_shadow_layer):
			_grass_shadow_layer.visible = false
			_grass_shadow_layer.multimesh = null
		if _grass_spore_layer != null and is_instance_valid(_grass_spore_layer):
			_grass_spore_layer.visible = false
			_grass_spore_layer.multimesh = null
		_grass_scatter_presentation_hidden = true


func take_object_presentation_apply_failure() -> String:
	var failure: String = _object_presentation_apply_failure
	_object_presentation_apply_failure = ""
	return failure


func stage_grass_scatter_result(result: Dictionary) -> bool:
	if not _grass_scatter_visual_dirty \
			or not _pending_grass_scatter_result.is_empty() \
			or _grass_scatter_apply_phase != GrassScatterApplyPhase.IDLE:
		return false
	# Own only the small envelope. Packed arrays remain immutable worker output,
	# so a shallow duplicate avoids copying the grass payload on the main thread.
	_pending_grass_scatter_result = result.duplicate(false)
	return true


func has_pending_grass_scatter_visual() -> bool:
	return _grass_scatter_visual_dirty


func is_grass_scatter_presentation_committed() -> bool:
	return not _grass_scatter_visual_dirty \
			and _pending_grass_scatter_result.is_empty() \
			and _grass_scatter_apply_phase == GrassScatterApplyPhase.IDLE


func is_terrain_cell_presentation_committed() -> bool:
	return _has_applied_cells \
			and not _pending_terrain_ids.is_empty() \
			and _apply_index >= _pending_terrain_ids.size() \
			and not _bulk_pattern_apply_active


## Advances exactly one bounded grass GPU phase. The caller may execute several
## phases while its frame budget remains, but no callback can hide a 64-stripe
## allocation/upload loop behind one nominally cheap operation.
func apply_pending_grass_scatter_visual_phase(
		grass_atlas: Texture2D,
		grass_material: ShaderMaterial,
		grass_shadow_atlas: Texture2D,
		grass_shadow_atlas_material: ShaderMaterial,
		shadow_material: ShaderMaterial,
		spore_material: ShaderMaterial,
		consolidate_directional_shadow: bool = false,
) -> bool:
	if not _grass_scatter_visual_dirty or _pending_grass_scatter_result.is_empty():
		return false
	var result: Dictionary = _pending_grass_scatter_result
	match _grass_scatter_apply_phase:
		GrassScatterApplyPhase.IDLE:
			_grass_scatter_apply_phase = GrassScatterApplyPhase.PREPARE
			return true
		GrassScatterApplyPhase.PREPARE:
			var phase_started: int = WorldPerfProbe.begin()
			_ensure_grass_scatter_layer_slots()
			_grass_scatter_apply_stripe = 0
			_grass_scatter_apply_uses_shadow_atlas = \
					grass_shadow_atlas != null and grass_shadow_atlas_material != null
			_grass_scatter_apply_consolidates_directional_shadow = \
					_grass_scatter_apply_uses_shadow_atlas \
					and consolidate_directional_shadow
			_hide_grass_scatter_presentation()
			_grass_scatter_apply_phase = GrassScatterApplyPhase.SHADOW_BLOB
			WorldPerfProbe.end("ChunkView.grass.prepare", phase_started)
			return true
		GrassScatterApplyPhase.SHADOW_BLOB:
			var phase_started: int = WorldPerfProbe.begin()
			_stage_grass_blob_layer(
				PackedFloat32Array() if _grass_scatter_apply_uses_shadow_atlas \
				else result.get("shadow_buffer", PackedFloat32Array()) as PackedFloat32Array,
				shadow_material,
				WorldRuntimeConstants.Z_GRASS_SHADOW,
				true,
			)
			_grass_scatter_apply_phase = GrassScatterApplyPhase.SPORE_BLOB
			WorldPerfProbe.end("ChunkView.grass.shadow_blob", phase_started)
			return true
		GrassScatterApplyPhase.SPORE_BLOB:
			var phase_started: int = WorldPerfProbe.begin()
			_stage_grass_blob_layer(
				result.get("spore_buffer", PackedFloat32Array()) as PackedFloat32Array,
				spore_material,
				WorldRuntimeConstants.Z_GRASS_SPORE,
				false,
			)
			_grass_scatter_apply_phase = GrassScatterApplyPhase.DIRECTIONAL_SHADOW
			WorldPerfProbe.end("ChunkView.grass.spore_blob", phase_started)
			return true
		GrassScatterApplyPhase.DIRECTIONAL_SHADOW:
			var phase_started: int = WorldPerfProbe.begin()
			var directional_shadow_buffer := PackedFloat32Array()
			if _grass_scatter_apply_consolidates_directional_shadow:
				directional_shadow_buffer = result.get(
					"directional_shadow_buffer",
					PackedFloat32Array(),
				) as PackedFloat32Array
			_stage_grass_directional_shadow_layer(
				directional_shadow_buffer,
				grass_shadow_atlas,
				grass_shadow_atlas_material,
			)
			_grass_scatter_apply_phase = GrassScatterApplyPhase.STRIPES
			WorldPerfProbe.end("ChunkView.grass.directional_shadow", phase_started)
			return true
		GrassScatterApplyPhase.STRIPES:
			# Empty native buckets with no stale allocation require no RenderingServer
			# mutation. Skip them in this callback and stop after exactly one real
			# upload/clear, retaining a bounded GPU phase without paying 64 callbacks
			# for sparse chunks.
			while _grass_scatter_apply_stripe < WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK:
				var stripe_index: int = _grass_scatter_apply_stripe
				_grass_scatter_apply_stripe += 1
				if not _grass_scatter_stripe_requires_stage(stripe_index, result):
					continue
				var phase_started: int = WorldPerfProbe.begin()
				_stage_grass_scatter_stripe(
					stripe_index,
					result,
					grass_atlas,
					grass_material,
					grass_shadow_atlas,
					grass_shadow_atlas_material,
				)
				WorldPerfProbe.end("ChunkView.grass.stripe", phase_started)
				return true
			_grass_scatter_apply_phase = GrassScatterApplyPhase.COMMIT
			return true
		GrassScatterApplyPhase.COMMIT:
			var phase_started: int = WorldPerfProbe.begin()
			_commit_grass_scatter_presentation()
			_pending_grass_scatter_result = { }
			_grass_scatter_visual_dirty = false
			_grass_scatter_apply_phase = GrassScatterApplyPhase.IDLE
			_grass_scatter_apply_stripe = 0
			WorldPerfProbe.end("ChunkView.grass.commit", phase_started)
			return true
	return true


## Rebase mid-полос чанка on the player-relative depth ladder. Grass uses one
## linear-root z write plus at most two clamp-boundary migrations per 16 px;
## object batch owners use the same contract. No buffer rebuild is involved.
func update_mid_ladder_z(anchor_stripe: int) -> void:
	if anchor_stripe == _applied_ladder_anchor_stripe:
		return
	_applied_ladder_anchor_stripe = anchor_stripe
	var grass_depth_ladder: DepthLadderBandRoot = _ensure_grass_depth_ladder()
	grass_depth_ladder.set_world_origin_y(position.y)
	grass_depth_ladder.update_anchor(anchor_stripe)
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.update_ladder_z(anchor_stripe)


## Stores the current player-relative anchor before a recycled view adopts a
## hot object layer. Unlike the movement update, this does not allocate an empty
## grass ladder for a view whose grass transaction has not begun yet.
func seed_mid_ladder_z(anchor_stripe: int) -> void:
	_applied_ladder_anchor_stripe = anchor_stripe
	if _grass_depth_ladder != null and is_instance_valid(_grass_depth_ladder):
		_grass_depth_ladder.set_world_origin_y(position.y)
		_grass_depth_ladder.update_anchor(anchor_stripe)
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.update_ladder_z(anchor_stripe)


## Zoom-LOD: внутри каждой полосы native кладёт крупные пучки в голову,
## поэтому доля видимых инстансов режет только хвост мелкой детали.
func set_grass_scatter_lod_fraction(fraction: float) -> void:
	for layer: MultiMeshInstance2D in _grass_scatter_layers:
		if layer == null or not is_instance_valid(layer):
			continue
		var multimesh: MultiMesh = layer.multimesh
		if multimesh == null or multimesh.instance_count <= 0:
			continue
		multimesh.visible_instance_count = clampi(
			ceili(float(multimesh.instance_count) * clampf(fraction, 0.0, 1.0)),
			0,
			multimesh.instance_count,
		)


func get_grass_scatter_debug_state() -> Dictionary:
	var instance_count: int = 0
	var visible_instance_count: int = 0
	var layer_visible: bool = false
	var albedo_draw_layer_count: int = 0
	for layer: MultiMeshInstance2D in _grass_scatter_layers:
		if layer == null or not is_instance_valid(layer) or layer.multimesh == null:
			continue
		if layer.visible:
			layer_visible = true
			albedo_draw_layer_count += 1
		instance_count += layer.multimesh.instance_count
		var layer_visible_count: int = layer.multimesh.visible_instance_count
		if layer_visible_count < 0:
			layer_visible_count = layer.multimesh.instance_count
		visible_instance_count += layer_visible_count
	var legacy_shadow_draw_layer_count: int = 0
	for layer: MultiMeshInstance2D in _grass_shadow_atlas_layers:
		if layer != null \
				and is_instance_valid(layer) \
				and layer.visible \
				and layer.multimesh != null \
				and layer.multimesh.instance_count > 0:
			legacy_shadow_draw_layer_count += 1
	var consolidated_shadow_draw_layer_count: int = 0
	if _grass_directional_shadow_layer != null \
			and is_instance_valid(_grass_directional_shadow_layer) \
			and _grass_directional_shadow_layer.visible \
			and _grass_directional_shadow_layer.multimesh != null \
			and _grass_directional_shadow_layer.multimesh.instance_count > 0:
		consolidated_shadow_draw_layer_count = 1
	var depth_ladder_state: Dictionary = { }
	if _grass_depth_ladder != null and is_instance_valid(_grass_depth_ladder):
		depth_ladder_state = _grass_depth_ladder.get_debug_state()
	return {
		"instance_count": instance_count,
		"visible_instance_count": visible_instance_count,
		"visible": layer_visible,
		"albedo_draw_layer_count": albedo_draw_layer_count,
		"directional_shadow_draw_layer_count": \
				legacy_shadow_draw_layer_count + consolidated_shadow_draw_layer_count,
		"legacy_shadow_draw_layer_count": legacy_shadow_draw_layer_count,
		"consolidated_shadow_draw_layer_count": consolidated_shadow_draw_layer_count,
		"grass_and_directional_shadow_draw_layer_count": \
				albedo_draw_layer_count \
				+ legacy_shadow_draw_layer_count \
				+ consolidated_shadow_draw_layer_count,
		"directional_shadow_mode": \
				"consolidated" if _grass_scatter_apply_consolidates_directional_shadow \
				else "per_stripe",
		"pending": _grass_scatter_visual_dirty,
		"apply_phase": _grass_scatter_apply_phase,
		"apply_stripe": _grass_scatter_apply_stripe,
		"staged": not _pending_grass_scatter_result.is_empty(),
		"depth_ladder": depth_ladder_state,
	}


## Один MultiMesh-слой на чанк для теней (под лесенкой) или спор (над травой).
## Оба — простые interleaved 12-float буферы из native.
func _stage_grass_scatter_stripe(
		stripe_index: int,
		result: Dictionary,
		grass_atlas: Texture2D,
		grass_material: ShaderMaterial,
		grass_shadow_atlas: Texture2D,
		grass_shadow_atlas_material: ShaderMaterial,
) -> void:
	var layer: MultiMeshInstance2D = _grass_scatter_layers[stripe_index]
	var shadow_atlas_layer: MultiMeshInstance2D = _grass_shadow_atlas_layers[stripe_index]
	var bucket_buffers: Array = result.get("bucket_buffers", []) as Array
	var buffer := PackedFloat32Array()
	if int(result.get("instance_count", 0)) > 0 and stripe_index < bucket_buffers.size():
		buffer = bucket_buffers[stripe_index] as PackedFloat32Array
	var stripe_count: int = buffer.size() / 12
	if stripe_count <= 0:
		if layer != null and is_instance_valid(layer):
			layer.visible = false
			layer.multimesh = null
			if _grass_depth_ladder != null and is_instance_valid(_grass_depth_ladder):
				_grass_depth_ladder.unregister_item(layer)
		if shadow_atlas_layer != null and is_instance_valid(shadow_atlas_layer):
			shadow_atlas_layer.visible = false
			shadow_atlas_layer.multimesh = null
		return
	if layer == null or not is_instance_valid(layer):
		layer = _create_grass_scatter_layer(stripe_index, grass_atlas, grass_material)
		_grass_scatter_layers[stripe_index] = layer
	layer.visible = false
	_ensure_grass_depth_ladder().register_item(layer, stripe_index, 0)
	var multimesh: MultiMesh = _prepare_grass_multimesh(layer.multimesh, stripe_count)
	multimesh.buffer = buffer
	layer.multimesh = multimesh
	if _grass_scatter_apply_uses_shadow_atlas:
		if _grass_scatter_apply_consolidates_directional_shadow:
			if shadow_atlas_layer != null and is_instance_valid(shadow_atlas_layer):
				shadow_atlas_layer.visible = false
				shadow_atlas_layer.multimesh = null
		else:
			if shadow_atlas_layer == null or not is_instance_valid(shadow_atlas_layer):
				shadow_atlas_layer = _create_grass_shadow_atlas_layer(
					stripe_index,
					grass_shadow_atlas,
					grass_shadow_atlas_material,
				)
				_grass_shadow_atlas_layers[stripe_index] = shadow_atlas_layer
			shadow_atlas_layer.multimesh = multimesh
			shadow_atlas_layer.visible = false
	elif shadow_atlas_layer != null and is_instance_valid(shadow_atlas_layer):
		shadow_atlas_layer.visible = false
		shadow_atlas_layer.multimesh = null


func _grass_scatter_stripe_requires_stage(stripe_index: int, result: Dictionary) -> bool:
	var bucket_buffers: Array = result.get("bucket_buffers", []) as Array
	if int(result.get("instance_count", 0)) > 0 and stripe_index < bucket_buffers.size():
		var buffer: PackedFloat32Array = bucket_buffers[stripe_index] as PackedFloat32Array
		if not buffer.is_empty():
			return true
	var layer: MultiMeshInstance2D = _grass_scatter_layers[stripe_index]
	if layer != null and is_instance_valid(layer) and layer.multimesh != null:
		return true
	var shadow_layer: MultiMeshInstance2D = _grass_shadow_atlas_layers[stripe_index]
	return shadow_layer != null and is_instance_valid(shadow_layer) and shadow_layer.multimesh != null


## Stages one flat shadow/spore payload while keeping the draw item hidden.
func _stage_grass_blob_layer(
		buffer: PackedFloat32Array,
		material: ShaderMaterial,
		z: int,
		is_shadow: bool,
) -> void:
	var layer: MultiMeshInstance2D = _grass_shadow_layer if is_shadow else _grass_spore_layer
	var count: int = buffer.size() / 12
	if count <= 0 or material == null:
		if layer != null and is_instance_valid(layer):
			layer.visible = false
			layer.multimesh = null
		return
	if layer == null or not is_instance_valid(layer):
		layer = MultiMeshInstance2D.new()
		layer.name = "GrassShadowBatch" if is_shadow else "GrassSporeBatch"
		layer.z_index = z
		layer.material = material
		# Тень — текстурой не пользуется (форма в шейдере), но MultiMesh2D
		# требует текстуру для размера UV; единичный белый пиксель.
		layer.texture = _grass_blob_unit_texture()
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(layer)
		if is_shadow:
			_grass_shadow_layer = layer
		else:
			_grass_spore_layer = layer
	var multimesh: MultiMesh = _prepare_grass_multimesh(layer.multimesh, count)
	multimesh.buffer = buffer
	layer.multimesh = multimesh
	layer.visible = false


## Full-detail directional shadows are fixed below the whole depth ladder, so
## native flattens their transforms on the worker and this phase performs one
## bounded raw upload. Fractional-LOD profiles retain the per-stripe path above.
func _stage_grass_directional_shadow_layer(
		buffer: PackedFloat32Array,
		grass_shadow_atlas: Texture2D,
		grass_shadow_atlas_material: ShaderMaterial,
) -> void:
	var count: int = buffer.size() / 12
	if count <= 0 or grass_shadow_atlas == null or grass_shadow_atlas_material == null:
		if _grass_directional_shadow_layer != null \
				and is_instance_valid(_grass_directional_shadow_layer):
			_grass_directional_shadow_layer.visible = false
			_grass_directional_shadow_layer.multimesh = null
		return
	if _grass_directional_shadow_layer == null \
			or not is_instance_valid(_grass_directional_shadow_layer):
		_grass_directional_shadow_layer = MultiMeshInstance2D.new()
		_grass_directional_shadow_layer.name = "GrassDirectionalShadowBatch"
		_grass_directional_shadow_layer.z_index = WorldRuntimeConstants.Z_GRASS_SHADOW + 1
		_grass_directional_shadow_layer.texture_filter = \
				CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_grass_directional_shadow_layer.texture = grass_shadow_atlas
		_grass_directional_shadow_layer.material = grass_shadow_atlas_material
		add_child(_grass_directional_shadow_layer)
	var multimesh: MultiMesh = _prepare_grass_multimesh(
		_grass_directional_shadow_layer.multimesh,
		count,
	)
	multimesh.buffer = buffer
	_grass_directional_shadow_layer.multimesh = multimesh
	_grass_directional_shadow_layer.visible = false


func _hide_grass_scatter_presentation() -> void:
	if _grass_scatter_presentation_hidden:
		return
	for layer: MultiMeshInstance2D in _grass_scatter_layers:
		if layer != null and is_instance_valid(layer):
			layer.visible = false
	for layer: MultiMeshInstance2D in _grass_shadow_atlas_layers:
		if layer != null and is_instance_valid(layer):
			layer.visible = false
	if _grass_directional_shadow_layer != null \
			and is_instance_valid(_grass_directional_shadow_layer):
		_grass_directional_shadow_layer.visible = false
	if _grass_shadow_layer != null and is_instance_valid(_grass_shadow_layer):
		_grass_shadow_layer.visible = false
	if _grass_spore_layer != null and is_instance_valid(_grass_spore_layer):
		_grass_spore_layer.visible = false
	_grass_scatter_presentation_hidden = true


func _commit_grass_scatter_presentation() -> void:
	for stripe_index: int in range(_grass_scatter_layers.size()):
		var layer: MultiMeshInstance2D = _grass_scatter_layers[stripe_index]
		var has_instances: bool = layer != null \
				and is_instance_valid(layer) \
				and layer.multimesh != null \
				and layer.multimesh.instance_count > 0
		if layer != null and is_instance_valid(layer):
			layer.visible = has_instances
		var shadow_atlas_layer: MultiMeshInstance2D = _grass_shadow_atlas_layers[stripe_index]
		if shadow_atlas_layer != null and is_instance_valid(shadow_atlas_layer):
			shadow_atlas_layer.visible = _grass_scatter_apply_uses_shadow_atlas \
					and not _grass_scatter_apply_consolidates_directional_shadow \
					and has_instances
	if _grass_directional_shadow_layer != null \
			and is_instance_valid(_grass_directional_shadow_layer):
		_grass_directional_shadow_layer.visible = \
				_grass_scatter_apply_consolidates_directional_shadow \
				and _grass_directional_shadow_layer.multimesh != null \
				and _grass_directional_shadow_layer.multimesh.instance_count > 0
	if _grass_shadow_layer != null and is_instance_valid(_grass_shadow_layer):
		_grass_shadow_layer.visible = not _grass_scatter_apply_uses_shadow_atlas \
				and _grass_shadow_layer.multimesh != null \
				and _grass_shadow_layer.multimesh.instance_count > 0
	if _grass_spore_layer != null and is_instance_valid(_grass_spore_layer):
		_grass_spore_layer.visible = _grass_spore_layer.multimesh != null \
				and _grass_spore_layer.multimesh.instance_count > 0
	_grass_scatter_presentation_hidden = false


func _prepare_grass_multimesh(current: MultiMesh, count: int) -> MultiMesh:
	var multimesh: MultiMesh = current
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.mesh = _grass_unit_quad_mesh()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_colors = true
	# Reusing the resource avoids repeated RID/QuadMesh construction on reload.
	# visible_instance_count must be reset before a smaller backing allocation.
	multimesh.visible_instance_count = -1
	if multimesh.instance_count != count:
		multimesh.instance_count = count
	return multimesh


static var _shared_grass_blob_texture: ImageTexture = null
static var _shared_grass_unit_quad: QuadMesh = null
static var _shared_tile_pattern_record_by_key: Dictionary = { }


static func _grass_blob_unit_texture() -> Texture2D:
	if _shared_grass_blob_texture != null:
		return _shared_grass_blob_texture
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_shared_grass_blob_texture = ImageTexture.create_from_image(image)
	return _shared_grass_blob_texture


static func _grass_unit_quad_mesh() -> QuadMesh:
	if _shared_grass_unit_quad != null:
		return _shared_grass_unit_quad
	_shared_grass_unit_quad = QuadMesh.new()
	_shared_grass_unit_quad.size = Vector2.ONE
	return _shared_grass_unit_quad


static func _tile_pattern_record(terrain_id: int, atlas_index: int) -> Vector4i:
	var key := Vector2i(terrain_id, atlas_index)
	if _shared_tile_pattern_record_by_key.has(key):
		return _shared_tile_pattern_record_by_key[key] as Vector4i
	var atlas_coords: Vector2i = WorldTileSetFactory.get_atlas_coords(
		terrain_id,
		atlas_index,
	)
	var record := Vector4i(
		1 if WorldTileSetFactory.uses_overlay_layer(terrain_id) else 0,
		WorldTileSetFactory.get_source_id(terrain_id),
		atlas_coords.x,
		atlas_coords.y,
	)
	_shared_tile_pattern_record_by_key[key] = record
	return record


static func prewarm_tile_pattern_records() -> void:
	# Loading-boundary warmup: source/material construction is already paid by
	# WorldTileSetFactory; cache every authored autotile index so no new biome
	# variant can create a registry/bootstrap hitch during vehicle movement.
	for layer_id: StringName in [
		TerrainPresentationRegistry.RENDER_LAYER_BASE,
		TerrainPresentationRegistry.RENDER_LAYER_OVERLAY,
	]:
		for terrain_id: int in TerrainPresentationRegistry.get_terrain_ids_for_layer(layer_id):
			for atlas_index: int in range(47):
				_tile_pattern_record(terrain_id, atlas_index)


## Loading-boundary warmup for the render-node/material path used by native
## mountain masks. The dummy mask is never visible (the owner is hidden) and is
## cleared immediately, while shader/material/node initialization is paid once
## before movement and the correctly-sized texture allocations enter the hot
## pool for later update().
func prewarm_mountain_mask_visual_resources(
		mask_side_px: int,
		mask_step_px: float,
		top_texture: Texture2D,
		face_texture: Texture2D,
		top_normal_texture: Texture2D,
		face_normal_texture: Texture2D,
		foothill_texture: Texture2D,
		foothill_normal_texture: Texture2D,
) -> void:
	if mask_side_px <= 0 or mask_step_px <= 0.0 or top_texture == null:
		return
	var mask_image := Image.create(
		mask_side_px,
		mask_side_px,
		false,
		Image.FORMAT_L8,
	)
	mask_image.fill(Color.BLACK)
	_mountain_top_mask_width = mask_side_px
	_mountain_top_mask_height = mask_side_px
	_upload_mountain_mask_texture(
		mask_image,
		top_texture,
		face_texture,
		0.70,
		mask_step_px,
		Vector2.ZERO,
		top_normal_texture,
		face_normal_texture,
		foothill_texture,
		foothill_normal_texture,
	)
	clear_mountain_render_page(false, true)


func _ensure_grass_scatter_layer_slots() -> void:
	while _grass_scatter_layers.size() < WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK:
		_grass_scatter_layers.append(null)
	while _grass_shadow_atlas_layers.size() < WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK:
		_grass_shadow_atlas_layers.append(null)


func _create_grass_scatter_layer(
		stripe_index: int,
		grass_atlas: Texture2D,
		grass_material: ShaderMaterial,
) -> MultiMeshInstance2D:
	var layer := MultiMeshInstance2D.new()
	layer.name = "GrassScatterBatchB%d" % stripe_index
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.texture = grass_atlas
	layer.material = grass_material
	return layer


func _ensure_grass_depth_ladder() -> DepthLadderBandRoot:
	if _grass_depth_ladder != null and is_instance_valid(_grass_depth_ladder):
		return _grass_depth_ladder
	_grass_depth_ladder = DepthLadderBandRoot.new()
	_grass_depth_ladder.name = "GrassDepthLadder"
	add_child(_grass_depth_ladder)
	_grass_depth_ladder.set_world_origin_y(position.y)
	if _applied_ladder_anchor_stripe != LADDER_ANCHOR_UNSET:
		_grass_depth_ladder.update_anchor(_applied_ladder_anchor_stripe)
	return _grass_depth_ladder


func _create_grass_shadow_atlas_layer(
		stripe_index: int,
		grass_shadow_atlas: Texture2D,
		grass_shadow_atlas_material: ShaderMaterial,
) -> MultiMeshInstance2D:
	var layer := MultiMeshInstance2D.new()
	layer.name = "GrassShadowAtlasBatchB%d" % stripe_index
	layer.z_index = WorldRuntimeConstants.Z_GRASS_SHADOW + 1
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.texture = grass_shadow_atlas
	layer.material = grass_shadow_atlas_material
	layer.visible = false
	add_child(layer)
	return layer


func apply_next_batch(batch_size: int) -> bool:
	if _water_fill_sync_pending:
		var water_sync_started: int = WorldPerfProbe.begin()
		_sync_water_fill_visual()
		_water_fill_sync_pending = false
		WorldPerfProbe.end("ChunkView.publish.sync_water_fill", water_sync_started)
	if _pending_terrain_ids.is_empty():
		return false
	if _bulk_pattern_apply_active:
		return _apply_next_bulk_pattern_batch(batch_size)
	if _skip_full_mountain_surface_apply:
		_apply_index = _pending_terrain_ids.size()
		_skip_full_mountain_surface_apply = false
		return false
	var end_index: int = mini(_apply_index + batch_size, _pending_terrain_ids.size())
	for index: int in range(_apply_index, end_index):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var terrain_id: int = int(_pending_terrain_ids[index])
		var terrain_atlas_index: int = 0
		if index < _pending_terrain_atlas_indices.size():
			terrain_atlas_index = int(_pending_terrain_atlas_indices[index])
		if _should_suppress_mountain_visual(index, terrain_id):
			_clear_mountain_visual_cell(local_coord)
			continue
		if _should_render_as_organic_ground_underlay(index, terrain_id):
			# These states are gameplay/runtime truth, not a separate square
			# visual surface. To the eye they stay in the shared organic ground
			# material so mountain cuts and dry beds cannot reveal tile blocks.
			_apply_cell(local_coord, WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, 0)
		else:
			_apply_cell(local_coord, terrain_id, terrain_atlas_index)
		_apply_water_cell(local_coord, index)
		_apply_roof_cell(local_coord, index)
	_apply_index = end_index
	if _apply_index >= _pending_terrain_ids.size():
		_has_applied_cells = true
		_bulk_apply_layers_pristine = false
		return false
	return true


func _apply_next_bulk_pattern_batch(batch_size: int) -> bool:
	var phase_started: int = WorldPerfProbe.begin()
	var end_index: int = mini(
		_apply_index + maxi(1, batch_size),
		_pending_terrain_ids.size(),
	)
	for index: int in range(_apply_index, end_index):
		var terrain_id: int = int(_pending_terrain_ids[index])
		var terrain_atlas_index: int = 0
		if index < _pending_terrain_atlas_indices.size():
			terrain_atlas_index = int(_pending_terrain_atlas_indices[index])
		if _should_suppress_mountain_visual(index, terrain_id) \
				or _should_render_as_organic_ground_underlay(index, terrain_id):
			terrain_id = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
			terrain_atlas_index = 0
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var tile_record: Vector4i = _tile_pattern_record(terrain_id, terrain_atlas_index)
		var target_pattern: TileMapPattern = _pending_overlay_pattern \
				if tile_record.x != 0 \
				else _pending_base_pattern
		target_pattern.set_cell(
			local_coord,
			tile_record.y,
			Vector2i(tile_record.z, tile_record.w),
			0,
		)
	_apply_index = end_index
	WorldPerfProbe.end("ChunkView.publish.pattern_build_batch", phase_started)
	if _apply_index < _pending_terrain_ids.size():
		return true
	var commit_started: int = WorldPerfProbe.begin()
	_commit_bulk_patterns()
	WorldPerfProbe.end("ChunkView.publish.pattern_commit", commit_started)
	_has_applied_cells = true
	_bulk_apply_layers_pristine = false
	_bulk_pattern_apply_active = false
	_pending_base_pattern = null
	_pending_overlay_pattern = null
	return false


func _commit_bulk_patterns() -> void:
	# Omitted pattern cells must erase the previous revision, so clear once per
	# layer before the exact source/atlas records are adopted atomically while the
	# parent ChunkView is hidden.
	_base_layer.clear()
	_overlay_layer.clear()
	_base_layer.set_pattern(Vector2i.ZERO, _pending_base_pattern)
	_overlay_layer.set_pattern(Vector2i.ZERO, _pending_overlay_pattern)
	if _water_layer != null and is_instance_valid(_water_layer):
		_water_layer.clear()
	for terrain_layers_variant: Variant in roof_layers_by_mountain.values():
		var terrain_layers: Dictionary = terrain_layers_variant as Dictionary
		for layer_variant: Variant in terrain_layers.values():
			var layer: TileMapLayer = layer_variant as TileMapLayer
			if layer != null and is_instance_valid(layer):
				layer.clear()


func apply_runtime_cell(
		local_coord: Vector2i,
		terrain_id: int,
		terrain_atlas_index: int,
		walkable: bool = true,
		mountain_id: int = 0,
		mountain_flags: int = 0,
) -> void:
	_ensure_layers()
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index >= 0 and index < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		if _pending_terrain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_terrain_ids[index] = terrain_id
		if _pending_terrain_atlas_indices.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
		_pending_terrain_atlas_indices[index] = terrain_atlas_index
		if _pending_walkable_flags.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
		_pending_walkable_flags[index] = 1 if walkable else 0
		if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			if _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
				_pending_mountain_ids[index] = 0
			if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
				_pending_mountain_flags[index] = 0
		elif mountain_id > 0 and _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
			_pending_mountain_ids[index] = mountain_id
			if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
				_pending_mountain_flags[index] = mountain_flags
	if _should_suppress_mountain_visual(index, terrain_id):
		_clear_mountain_visual_cell(local_coord)
		if _debug_solid_mask_visible:
			_refresh_debug_solid_mask()
		return
	_sync_water_fill_visual()
	if _should_render_as_organic_ground_underlay(index, terrain_id):
		_apply_cell(local_coord, WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, 0)
	else:
		_apply_cell(local_coord, terrain_id, terrain_atlas_index)
	_apply_water_patch_around(local_coord)
	if _debug_solid_mask_visible:
		_refresh_debug_solid_mask()


func set_mountain_tile_visuals_enabled(enabled: bool) -> void:
	if _mountain_tile_visuals_enabled == enabled:
		return
	_mountain_tile_visuals_enabled = enabled
	if not _mountain_tile_visuals_enabled:
		_clear_loaded_mountain_visuals()


func set_debug_overlays(grid_visible: bool, solid_mask_visible: bool, contour_visible: bool) -> void:
	if grid_visible == _debug_grid_visible \
			and solid_mask_visible == _debug_solid_mask_visible \
			and contour_visible == _debug_contour_visible:
		return
	var solid_mask_just_enabled: bool = solid_mask_visible and not _debug_solid_mask_visible
	_debug_grid_visible = grid_visible
	_debug_solid_mask_visible = solid_mask_visible
	_debug_contour_visible = contour_visible
	if solid_mask_just_enabled:
		_refresh_debug_solid_mask()
	_sync_debug_layer()


## Дев-оверлей коллизий объектного пакета (камни/валуны/деревья, F11).
func set_debug_object_collisions_visible(enabled: bool) -> void:
	if enabled == _debug_object_collisions_visible:
		return
	_debug_object_collisions_visible = enabled
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_debug_collisions_visible(enabled)


func apply_sun_lighting(
		light_angle_deg: float,
		shadow_length_px: float,
		shadow_opacity: float,
		shadow_softness_px: float,
) -> void:
	if is_equal_approx(light_angle_deg, _sun_light_angle_deg) \
			and is_equal_approx(shadow_length_px, _sun_shadow_length_px) \
			and is_equal_approx(shadow_opacity, _sun_shadow_opacity) \
			and is_equal_approx(shadow_softness_px, _sun_shadow_softness_px):
		return
	_sun_light_angle_deg = light_angle_deg
	_sun_shadow_length_px = shadow_length_px
	_sun_shadow_opacity = shadow_opacity
	_sun_shadow_softness_px = shadow_softness_px
	_apply_sun_lighting_to_mask_material(_mountain_top_mask_material, 1.0)
	# The construction roof shares BASE's daylight grading but never draws a
	# second projected sun shadow (it would double-darken the massif).
	_apply_sun_lighting_to_mask_material(_mountain_closed_roof_mask_material, 1.0, false)
	_apply_sun_lighting_to_foothill_material(_mountain_rock_underlay_material)
	_apply_sun_lighting_to_foothill_material(_mountain_foothill_overlay_material)
	_apply_sun_lighting_to_rock_patch_material(_rock_patch_overlay_material)
	_apply_sun_lighting_to_grass_blob_material(_grass_blob_overlay_material)
	_apply_sun_lighting_to_object_packet_layer()
	_apply_sun_lighting_to_mask_material(
		_terrain_edge_mask_material,
		WorldVisualLightingProfile.TERRAIN_EDGE_SHADOW_OPACITY_SCALE,
	)


func set_living_flora_source(atlas: Texture2D) -> void:
	if atlas == _living_flora_atlas:
		return
	_living_flora_atlas = atlas
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_living_flora_atlas(_living_flora_atlas)


func set_spiky_flora_source(atlas: Texture2D) -> void:
	if atlas == null:
		set_spiky_flora_sources([])
	else:
		set_spiky_flora_sources([atlas])


func set_spiky_flora_sources(atlases: Array[Texture2D]) -> void:
	if atlases == _spiky_flora_atlases:
		return
	_spiky_flora_atlases = atlases.duplicate()
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_spiky_flora_atlases(_spiky_flora_atlases)


func set_tree_source(atlas: Texture2D) -> void:
	if atlas == _tree_atlas:
		return
	_tree_atlas = atlas
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_tree_atlas(_tree_atlas)


func set_layered_tree_asset_dir(asset_dir: String) -> void:
	set_layered_tree_asset_dirs([asset_dir] if not asset_dir.is_empty() else [])


func set_layered_tree_asset_dirs(asset_dirs: Array) -> void:
	if asset_dirs == _layered_tree_asset_dirs:
		return
	_layered_tree_asset_dirs = _normalize_layered_tree_asset_dirs(asset_dirs)
	_layered_tree_asset_dir = _layered_tree_asset_dirs[0] if not _layered_tree_asset_dirs.is_empty() else ""
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_layered_tree_asset_dirs(_layered_tree_asset_dirs)


func set_layered_small_rock_asset_dir(asset_dir: String) -> void:
	set_layered_small_rock_asset_dirs([asset_dir] if not asset_dir.is_empty() else [])


func set_layered_small_rock_asset_dirs(asset_dirs: Array) -> void:
	if asset_dirs == _layered_small_rock_asset_dirs:
		return
	_layered_small_rock_asset_dirs = _normalize_layered_tree_asset_dirs(asset_dirs)
	_layered_small_rock_asset_dir = _layered_small_rock_asset_dirs[0] if not _layered_small_rock_asset_dirs.is_empty() else ""
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_layered_small_rock_asset_dirs(_layered_small_rock_asset_dirs)


func apply_contour_debug_data(
		solid_mask: PackedByteArray,
		contour_vertices: PackedVector2Array,
		contour_indices: PackedInt32Array,
) -> void:
	_debug_solid_mask = solid_mask.duplicate()
	if _debug_solid_mask.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_debug_solid_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_debug_contour_vertices = contour_vertices.duplicate()
	_debug_contour_indices = contour_indices.duplicate()
	_sync_debug_layer()


func get_mountain_contour_debug_state() -> Dictionary:
	if _debug_layer != null and is_instance_valid(_debug_layer):
		return _debug_layer.get_debug_state()
	return {
		"chunk_coord": chunk_coord,
		"grid_visible": _debug_grid_visible,
		"solid_mask_visible": _debug_solid_mask_visible,
		"contour_visible": _debug_contour_visible,
		"solid_tile_count": _count_debug_solid_tiles(),
		"contour_vertex_count": _debug_contour_vertices.size(),
		"contour_index_count": _debug_contour_indices.size(),
		"contour_triangle_count": _debug_contour_indices.size() / 3,
	}


func apply_mountain_render_page(result: Dictionary, top_texture: Texture2D = null, face_texture: Texture2D = null) -> void:
	_ensure_mountain_page_sprite()
	var mountain_image: Image = result.get("mountain_image", null) as Image
	var top_mask: PackedByteArray = result.get("top_mask", PackedByteArray()) as PackedByteArray
	if (mountain_image == null or mountain_image.is_empty()) and top_mask.is_empty():
		clear_mountain_render_page()
		return
	_mountain_interior_fill_active = false
	_apply_mountain_top_mask(result, top_texture, face_texture)
	_mountain_page_image = (mountain_image.duplicate() as Image) if mountain_image != null and not mountain_image.is_empty() else null
	_mountain_page_texture = ImageTexture.create_from_image(_mountain_page_image) if _mountain_page_image != null else null
	_mountain_page_normal_texture = null
	_mountain_page_lit_texture = null
	_mountain_page_render_origin_world = result.get("render_origin_world", Vector2.ZERO) as Vector2
	_mountain_page_sprite.position = _mountain_page_render_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_mountain_page_sprite.scale = Vector2.ONE
	_mountain_page_sprite.texture = _mountain_page_lit_texture if _mountain_page_lit_texture != null else _mountain_page_texture
	_mountain_page_sprite.visible = _mountain_page_texture != null
	_mountain_page_hit_mask = result.get("hit_mask", PackedByteArray()) as PackedByteArray
	_mountain_page_hit_mask_width = int(result.get("hit_mask_width", 0))
	_mountain_page_hit_mask_height = int(result.get("hit_mask_height", 0))
	_mountain_page_hit_mask_origin_world = result.get("hit_mask_origin_world", Vector2.ZERO) as Vector2
	_mountain_page_hit_mask_step_px = float(result.get("hit_mask_step_px", 0.0))
	_mountain_page_debug = _compact_mountain_page_result(result)
	_mountain_page_debug["ready"] = true
	_mountain_page_debug["chunk_coord"] = chunk_coord


func apply_mountain_hit_page(result: Dictionary) -> void:
	_ensure_mountain_page_sprite()
	_mountain_interior_fill_active = false
	_mountain_page_texture = null
	_mountain_page_image = null
	_mountain_page_normal_texture = null
	_mountain_page_lit_texture = null
	_mountain_page_render_origin_world = result.get("render_origin_world", Vector2.ZERO) as Vector2
	_mountain_page_sprite.texture = null
	_mountain_page_sprite.visible = false
	_mountain_page_sprite.scale = Vector2.ONE
	_clear_mountain_top_mask()
	_mountain_page_hit_mask = result.get("hit_mask", PackedByteArray()) as PackedByteArray
	_mountain_page_hit_mask_width = int(result.get("hit_mask_width", 0))
	_mountain_page_hit_mask_height = int(result.get("hit_mask_height", 0))
	_mountain_page_hit_mask_origin_world = result.get("hit_mask_origin_world", Vector2.ZERO) as Vector2
	_mountain_page_hit_mask_step_px = float(result.get("hit_mask_step_px", 0.0))
	_mountain_page_debug = _compact_mountain_page_result(result)
	_mountain_page_debug["ready"] = true
	_mountain_page_debug["hit_only"] = true
	_mountain_page_debug["chunk_coord"] = chunk_coord


func apply_mountain_interior_fill(top_texture: Texture2D, face_texture: Texture2D = null, top_texture_scale: float = 0.70) -> void:
	if top_texture == null:
		clear_mountain_render_page()
		return
	_ensure_mountain_page_sprite()
	_mountain_interior_fill_active = true
	_mountain_page_texture = null
	_mountain_page_image = null
	_mountain_page_normal_texture = null
	_mountain_page_lit_texture = null
	_mountain_page_hit_mask = PackedByteArray()
	_mountain_page_hit_mask_width = 0
	_mountain_page_hit_mask_height = 0
	_mountain_page_hit_mask_origin_world = Vector2.ZERO
	_mountain_page_hit_mask_step_px = 0.0
	_mountain_page_render_origin_world = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_mountain_page_sprite.texture = null
	_mountain_page_sprite.visible = false
	_apply_mountain_full_top_fill(top_texture, face_texture, top_texture_scale)
	_mountain_page_debug = {
		"ready": true,
		"chunk_coord": chunk_coord,
		"interior_fill": true,
	}


func apply_mountain_mask_fill(packet: Dictionary, top_texture: Texture2D, face_texture: Texture2D = null, top_texture_scale: float = 0.70) -> void:
	if top_texture == null:
		clear_mountain_render_page()
		return
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		if index >= terrain_ids.size():
			continue
		var terrain_id: int = int(terrain_ids[index])
		if not _is_mountain_visual_terrain(terrain_id):
			continue
		if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
			continue
		if terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED and index < mountain_flags.size():
			var flags: int = int(mountain_flags[index])
			if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
				continue
		mask[index] = 255
	var mask_image: Image = Image.create_from_data(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_L8,
		mask,
	)
	mask_image.resize(
		WorldRuntimeConstants.CHUNK_SIZE * 8,
		WorldRuntimeConstants.CHUNK_SIZE * 8,
		Image.INTERPOLATE_CUBIC,
	)
	_apply_mountain_mask_image(
		mask_image,
		top_texture,
		face_texture,
		top_texture_scale,
		float(WorldRuntimeConstants.TILE_SIZE_PX) / 8.0,
		WorldRuntimeConstants.chunk_origin_px(chunk_coord),
	)
	_mountain_interior_fill_active = false
	_mountain_page_texture = null
	_mountain_page_image = null
	_mountain_page_normal_texture = null
	_mountain_page_lit_texture = null
	_mountain_page_hit_mask = PackedByteArray()
	_mountain_page_hit_mask_width = 0
	_mountain_page_hit_mask_height = 0
	_mountain_page_hit_mask_origin_world = Vector2.ZERO
	_mountain_page_hit_mask_step_px = 0.0
	_mountain_page_render_origin_world = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_mountain_page_debug = {
		"ready": true,
		"chunk_coord": chunk_coord,
		"mask_fill": true,
		"mask_size": mask_image.get_size(),
	}


func apply_mountain_halo_mask_fill(
		solid_halo: PackedByteArray,
		top_texture: Texture2D,
		face_texture: Texture2D = null,
		top_texture_scale: float = 0.70,
) -> void:
	if top_texture == null:
		clear_mountain_render_page()
		return
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	if solid_halo.size() != halo_side * halo_side:
		push_error(
			"ChunkView received invalid mountain halo mask: expected %d byte(s), got %d." % [
				halo_side * halo_side,
				solid_halo.size(),
			],
		)
		clear_mountain_render_page()
		return
	var mask_bytes := PackedByteArray()
	mask_bytes.resize(solid_halo.size())
	for index: int in range(solid_halo.size()):
		mask_bytes[index] = 255 if int(solid_halo[index]) != 0 else 0
	var mask_image: Image = Image.create_from_data(
		halo_side,
		halo_side,
		false,
		Image.FORMAT_L8,
		mask_bytes,
	)
	mask_image.resize(
		halo_side * 8,
		halo_side * 8,
		Image.INTERPOLATE_CUBIC,
	)
	_apply_mountain_mask_image(
		mask_image,
		top_texture,
		face_texture,
		top_texture_scale,
		float(WorldRuntimeConstants.TILE_SIZE_PX) / 8.0,
		WorldRuntimeConstants.chunk_origin_px(chunk_coord) - Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX),
	)
	_mountain_interior_fill_active = false
	_mountain_page_texture = null
	_mountain_page_image = null
	_mountain_page_normal_texture = null
	_mountain_page_lit_texture = null
	_mountain_page_hit_mask = PackedByteArray()
	_mountain_page_hit_mask_width = 0
	_mountain_page_hit_mask_height = 0
	_mountain_page_hit_mask_origin_world = Vector2.ZERO
	_mountain_page_hit_mask_step_px = 0.0
	_mountain_page_render_origin_world = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_mountain_page_debug = {
		"ready": true,
		"chunk_coord": chunk_coord,
		"halo_mask_fill": true,
		"mask_size": mask_image.get_size(),
	}


func apply_mountain_native_mask_fill(
		mask_result: Dictionary,
		mask_origin_world: Vector2,
		top_texture: Texture2D,
		face_texture: Texture2D = null,
		top_texture_scale: float = 0.70,
) -> void:
	if top_texture == null:
		clear_mountain_render_page()
		return
	if not apply_mountain_native_mask_data(mask_result, mask_origin_world, top_texture_scale):
		clear_mountain_render_page()
		return
	apply_pending_mountain_native_mask_visual(top_texture, face_texture)


func apply_mountain_native_mask_data(
		mask_result: Dictionary,
		mask_origin_world: Vector2,
		top_texture_scale: float = 0.70,
) -> bool:
	var mask_bytes: PackedByteArray = mask_result.get("mask", PackedByteArray()) as PackedByteArray
	var mask_width: int = int(mask_result.get("width", 0))
	var mask_height: int = int(mask_result.get("height", 0))
	var mask_step_px: float = float(mask_result.get("step_px", 0.0))
	var expected_mask_bytes: int = mask_width * mask_height
	if mask_width <= 0 \
			or mask_height <= 0 \
			or mask_step_px <= 0.0 \
			or mask_bytes.size() != expected_mask_bytes:
		return false

	var closed_mask_bytes: PackedByteArray = mask_result.get(
		"closed_roof_mask",
		PackedByteArray(),
	) as PackedByteArray
	var dug_halo: PackedByteArray = mask_result.get("dug_halo", PackedByteArray()) as PackedByteArray
	var sky_exposure: PackedByteArray = mask_result.get(
		"sky_exposure_mask",
		PackedByteArray(),
	) as PackedByteArray
	var has_construction_fields: bool = not closed_mask_bytes.is_empty() or not dug_halo.is_empty()
	var dug_halo_side: int = _square_l8_mask_side(dug_halo)
	if has_construction_fields \
			and (
				closed_mask_bytes.size() != expected_mask_bytes \
						or dug_halo_side <= 0 \
						or sky_exposure.size() != expected_mask_bytes
			):
		return false
	if not has_construction_fields and not sky_exposure.is_empty():
		return false

	var mask_geometry_changed: bool = _mountain_top_mask_width != mask_width \
			or _mountain_top_mask_height != mask_height \
			or not _mountain_top_mask_origin_world.is_equal_approx(mask_origin_world) \
			or not is_equal_approx(_mountain_top_mask_step_px, mask_step_px)
	_mountain_top_mask_image = null
	_mountain_top_mask_bytes = mask_bytes.duplicate()
	_mountain_top_mask_width = mask_width
	_mountain_top_mask_height = mask_height
	_mountain_top_mask_origin_world = mask_origin_world
	_mountain_top_mask_step_px = mask_step_px
	_mountain_top_mask_texture_scale = top_texture_scale
	_mountain_top_mask_visual_dirty = true

	if has_construction_fields:
		if mask_geometry_changed or _mountain_closed_roof_mask_bytes != closed_mask_bytes:
			_mountain_closed_roof_mask_bytes = closed_mask_bytes.duplicate()
			_mountain_closed_roof_mask_image = null
			_mountain_closed_roof_mask_visual_dirty = true
			# The permanent foothill footprint belongs to the immutable CLOSED
			# construction, not to the excavated live mask.
			# Keep the same-size L8 allocation alive across construction/dug-mask
			# refreshes. The immutable foothill footprint is recaptured below, so
			# dropping the GPU object here only creates avoidable driver churn.
			_clear_mountain_foothill_mask(true)
		if mask_geometry_changed or _mountain_sky_exposure_bytes != sky_exposure:
			_mountain_sky_exposure_bytes = sky_exposure.duplicate()
			_mountain_sky_exposure_image = null
			_mountain_sky_exposure_visual_dirty = true
		_mountain_sky_exposure_reach_samples = int(
			mask_result.get("sky_exposure_reach_samples", 0),
		)
		_mountain_sky_exposure_source_sample_count = int(
			mask_result.get("sky_exposure_source_sample_count", 0),
		)
		var normalized_dug_halo: PackedByteArray = _normalize_binary_l8_mask(dug_halo)
		if _mountain_dug_halo_side != dug_halo_side \
				or _mountain_dug_halo_bytes != normalized_dug_halo:
			_mountain_dug_halo_bytes = normalized_dug_halo
			_mountain_dug_halo_nonzero_count = _count_nonzero_mask_bytes(normalized_dug_halo)
			_mountain_dug_halo_side = dug_halo_side
			_mountain_dug_halo_visual_dirty = true
		# A freshly loaded/outside chunk still needs a valid zero-ownership
		# selector texture. Preserve an already published active component across
		# native mask refreshes as long as the halo extent is unchanged.
		if _mountain_active_floor_halo_side != dug_halo_side \
				or _mountain_active_floor_halo_bytes.size() != dug_halo.size():
			_mountain_active_floor_halo_bytes = PackedByteArray()
			_mountain_active_floor_halo_bytes.resize(dug_halo.size())
			_mountain_active_floor_halo_nonzero_count = 0
			_mountain_active_floor_halo_side = dug_halo_side
			_mountain_active_floor_halo_image = null
			_mountain_active_floor_halo_visual_dirty = true
			# A staged texture with another extent can never be committed safely.
			_clear_staged_mountain_roof_reveal_halo()
	elif not _mountain_closed_roof_mask_bytes.is_empty() \
			or _mountain_closed_roof_mask_texture != null:
		# A single-mask publication (no dug cells left in the halo) cannot drive
		# the construction roof. Drop the stale CLOSED state explicitly.
		_clear_mountain_closed_roof_state()
	_mountain_interior_fill_active = false
	_mountain_page_texture = null
	_mountain_page_image = null
	_mountain_page_normal_texture = null
	_mountain_page_lit_texture = null
	_mountain_page_hit_mask = PackedByteArray()
	_mountain_page_hit_mask_width = 0
	_mountain_page_hit_mask_height = 0
	_mountain_page_hit_mask_origin_world = Vector2.ZERO
	_mountain_page_hit_mask_step_px = 0.0
	_mountain_page_render_origin_world = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_mountain_page_debug = {
		"ready": true,
		"chunk_coord": chunk_coord,
		"native_mask_fill": true,
		"native_mask_visual_pending": true,
		# A retained texture is only an allocation target until the new bytes are
		# uploaded. Pending and ready must never be true at the same time.
		"native_mask_visual_ready": false,
		"mask_size": Vector2i(mask_width, mask_height),
		"solid_sample_count": int(mask_result.get("solid_sample_count", 0)),
		"construction_roof_mask": has_construction_fields,
		"pixels_per_tile": int(mask_result.get("pixels_per_tile", 0)),
	}
	return true


func set_mountain_roof_reveal_blend(value: float) -> void:
	var next_blend: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(next_blend, _mountain_roof_reveal_blend):
		return
	_mountain_roof_reveal_blend = next_blend
	if _mountain_closed_roof_mask_material != null:
		_mountain_closed_roof_mask_material.set_shader_parameter(
			"component_reveal_blend",
			_mountain_roof_reveal_blend,
		)
	_mountain_page_debug["roof_reveal_blend"] = _mountain_roof_reveal_blend


## Stage the resolver-selected connected cavity as a tile halo. This is a
## presentation field only: it never mutates remaining mass or collision. The
## staged texture is never bound by the upload path; WorldStreamer publishes a
## complete generation through `commit_staged_mountain_roof_reveal_halo()`.
func stage_mountain_roof_reveal_halo(
		reveal_halo: PackedByteArray,
		generation: int,
) -> bool:
	# Plain/shore chunks also participate in cover-cache refreshes, but they do
	# not own the construction roof state and must never enter the deferred
	# roof upload/first-visible gate.
	if generation <= 0 \
			or _mountain_closed_roof_mask_bytes.is_empty() \
			or _mountain_dug_halo_side <= 0:
		cancel_staged_mountain_roof_reveal_halo()
		return false
	var halo_side: int = _square_l8_mask_side(reveal_halo)
	if halo_side <= 0 or halo_side != _mountain_dug_halo_side:
		cancel_staged_mountain_roof_reveal_halo()
		return false
	var normalized_halo: PackedByteArray = _normalize_binary_l8_mask(reveal_halo)
	if _mountain_active_floor_halo_side == halo_side \
			and _mountain_active_floor_halo_bytes == normalized_halo:
		cancel_staged_mountain_roof_reveal_halo()
		return false
	if _mountain_staged_floor_halo_side == halo_side \
			and _mountain_staged_floor_halo_bytes == normalized_halo:
		# Re-staging the same selector under a newer generation can reuse the
		# private uploaded texture; it has never been exposed to the material.
		_mountain_staged_floor_halo_generation = generation
		_update_mountain_native_mask_pending_debug()
		return true
	_mountain_staged_floor_halo_bytes = normalized_halo
	_mountain_staged_floor_halo_nonzero_count = _count_nonzero_mask_bytes(normalized_halo)
	_mountain_staged_floor_halo_side = halo_side
	_mountain_staged_floor_halo_generation = generation
	_mountain_staged_floor_halo_image = null
	_mountain_staged_floor_halo_visual_dirty = true
	_update_mountain_native_mask_pending_debug()
	return true


func has_staged_mountain_roof_reveal_halo(generation: int) -> bool:
	return generation > 0 and _mountain_staged_floor_halo_generation == generation


func is_staged_mountain_roof_reveal_halo_ready(generation: int) -> bool:
	return has_staged_mountain_roof_reveal_halo(generation) \
			and not _mountain_staged_floor_halo_visual_dirty \
			and _mountain_staged_floor_halo_image != null \
			and not _mountain_staged_floor_halo_image.is_empty() \
			and _mountain_staged_floor_halo_texture != null


func commit_staged_mountain_roof_reveal_halo(generation: int) -> bool:
	if not is_staged_mountain_roof_reveal_halo_ready(generation):
		return false
	_mountain_active_floor_halo_bytes = _mountain_staged_floor_halo_bytes
	_mountain_active_floor_halo_nonzero_count = _mountain_staged_floor_halo_nonzero_count
	_mountain_active_floor_halo_image = _mountain_staged_floor_halo_image
	_mountain_active_floor_halo_texture = _mountain_staged_floor_halo_texture
	_mountain_active_floor_halo_side = _mountain_staged_floor_halo_side
	_mountain_active_floor_halo_visual_dirty = false
	_clear_staged_mountain_roof_reveal_halo()
	# This is the only point where a staged selector becomes observable. No GPU
	# upload happens here: every affected chunk only swaps material uniforms.
	if _mountain_closed_roof_mask_material != null:
		_mountain_closed_roof_mask_material.set_shader_parameter(
			"roof_component_reveal_enabled",
			1.0 if _mountain_active_floor_halo_nonzero_count > 0 else 0.0,
		)
		_mountain_closed_roof_mask_material.set_shader_parameter(
			"active_floor_halo_texture",
			_mountain_active_floor_halo_texture,
		)
	_update_mountain_native_mask_pending_debug()
	return true


func cancel_staged_mountain_roof_reveal_halo(generation: int = 0) -> bool:
	if generation > 0 and generation != _mountain_staged_floor_halo_generation:
		return false
	var had_staged_halo: bool = _mountain_staged_floor_halo_generation > 0
	_clear_staged_mountain_roof_reveal_halo()
	_update_mountain_native_mask_pending_debug()
	return had_staged_halo


func apply_pending_mountain_native_mask_visual(
		top_texture: Texture2D,
		face_texture: Texture2D = null,
		top_normal_texture: Texture2D = null,
		face_normal_texture: Texture2D = null,
		foothill_texture: Texture2D = null,
		foothill_normal_texture: Texture2D = null,
) -> bool:
	var any_visual_dirty: bool = _mountain_top_mask_visual_dirty \
			or _mountain_closed_roof_mask_visual_dirty \
			or _mountain_sky_exposure_visual_dirty \
			or _mountain_active_floor_halo_visual_dirty \
			or _mountain_staged_floor_halo_visual_dirty \
			or _mountain_dug_halo_visual_dirty
	if not any_visual_dirty:
		return false
	if top_texture == null \
			or _mountain_top_mask_width <= 0 \
			or _mountain_top_mask_height <= 0 \
			or _mountain_top_mask_step_px <= 0.0 \
			or _mountain_top_mask_bytes.size() != _mountain_top_mask_width * _mountain_top_mask_height:
		return false

	# Untouched chunks render exactly like the legacy single BASE pass. The
	# construction textures/sprite exist only once at least one halo source
	# tile was excavated, keeping the common exterior case at one draw.
	var construction_roof_needed: bool = _mountain_dug_halo_side > 0 \
			and _mountain_dug_halo_bytes.size() \
					== _mountain_dug_halo_side * _mountain_dug_halo_side \
			and _mountain_closed_roof_mask_bytes.size() \
					== _mountain_top_mask_width * _mountain_top_mask_height \
			and _mountain_sky_exposure_bytes.size() \
					== _mountain_top_mask_width * _mountain_top_mask_height \
			and _mountain_dug_halo_nonzero_count > 0
	if not construction_roof_needed:
		_mountain_closed_roof_mask_visual_dirty = false
		_mountain_dug_halo_visual_dirty = false
		_mountain_active_floor_halo_visual_dirty = false
		_hide_mountain_closed_roof_visual()

	if construction_roof_needed and (
		_mountain_sky_exposure_visual_dirty or _mountain_sky_exposure_texture == null
	):
		var skylight_image_started: int = WorldPerfProbe.begin()
		_mountain_sky_exposure_image = Image.create_from_data(
			_mountain_top_mask_width,
			_mountain_top_mask_height,
			false,
			Image.FORMAT_L8,
			_mountain_sky_exposure_bytes,
		)
		WorldPerfProbe.end(
			"ChunkView.mountain_skylight_visual.create_exposure_image",
			skylight_image_started,
		)
		var skylight_upload_started: int = WorldPerfProbe.begin()
		_mountain_sky_exposure_texture = _update_or_create_l8_texture(
			_mountain_sky_exposure_texture,
			_mountain_sky_exposure_image,
		)
		WorldPerfProbe.end(
			"ChunkView.mountain_skylight_visual.upload_exposure_texture",
			skylight_upload_started,
		)
		_mountain_sky_exposure_visual_dirty = false

	# CLOSED must seed the persistent foothill footprint before BASE has a
	# chance to capture its excavated silhouette.
	if construction_roof_needed and (
		_mountain_closed_roof_mask_visual_dirty or _mountain_closed_roof_mask_texture == null
	):
		var closed_image_started: int = WorldPerfProbe.begin()
		_mountain_closed_roof_mask_image = Image.create_from_data(
			_mountain_top_mask_width,
			_mountain_top_mask_height,
			false,
			Image.FORMAT_L8,
			_mountain_closed_roof_mask_bytes,
		)
		WorldPerfProbe.end("ChunkView.mountain_roof_visual.create_closed_image", closed_image_started)
		_capture_mountain_foothill_mask_if_needed(
			_mountain_closed_roof_mask_image,
			_mountain_top_mask_origin_world,
			_mountain_top_mask_step_px,
		)
		var closed_upload_started: int = WorldPerfProbe.begin()
		_mountain_closed_roof_mask_texture = _update_or_create_l8_texture(
			_mountain_closed_roof_mask_texture,
			_mountain_closed_roof_mask_image,
		)
		WorldPerfProbe.end("ChunkView.mountain_roof_visual.upload_closed_texture", closed_upload_started)
		_mountain_closed_roof_mask_visual_dirty = false
	elif construction_roof_needed \
			and _mountain_closed_roof_mask_image != null \
			and not _mountain_closed_roof_mask_image.is_empty():
		_capture_mountain_foothill_mask_if_needed(
			_mountain_closed_roof_mask_image,
			_mountain_top_mask_origin_world,
			_mountain_top_mask_step_px,
		)

	if construction_roof_needed and (
		_mountain_dug_halo_visual_dirty or _mountain_dug_halo_texture == null
	):
		_mountain_dug_halo_image = Image.create_from_data(
			_mountain_dug_halo_side,
			_mountain_dug_halo_side,
			false,
			Image.FORMAT_L8,
			_mountain_dug_halo_bytes,
		)
		_mountain_dug_halo_texture = _update_or_create_l8_texture(
			_mountain_dug_halo_texture,
			_mountain_dug_halo_image,
		)
		_mountain_dug_halo_visual_dirty = false

	if construction_roof_needed and (
		_mountain_active_floor_halo_visual_dirty \
				or _mountain_active_floor_halo_texture == null
	):
		if _mountain_active_floor_halo_bytes.size() \
				!= _mountain_active_floor_halo_side * _mountain_active_floor_halo_side:
			return false
		_mountain_active_floor_halo_image = Image.create_from_data(
			_mountain_active_floor_halo_side,
			_mountain_active_floor_halo_side,
			false,
			Image.FORMAT_L8,
			_mountain_active_floor_halo_bytes,
		)
		_mountain_active_floor_halo_texture = _update_or_create_l8_texture(
			_mountain_active_floor_halo_texture,
			_mountain_active_floor_halo_image,
		)
		_mountain_active_floor_halo_visual_dirty = false

	# The cavity cache can lead the asynchronous native dug-mask result by a
	# frame. Upload the private selector even while the roof pass is not needed
	# yet; otherwise its generation could remain publish-gated forever.
	if _mountain_staged_floor_halo_generation > 0 \
			and (
				_mountain_staged_floor_halo_visual_dirty \
						or _mountain_staged_floor_halo_texture == null
			):
		if _mountain_staged_floor_halo_bytes.size() \
				!= _mountain_staged_floor_halo_side * _mountain_staged_floor_halo_side:
			return false
		_mountain_staged_floor_halo_image = Image.create_from_data(
			_mountain_staged_floor_halo_side,
			_mountain_staged_floor_halo_side,
			false,
			Image.FORMAT_L8,
			_mountain_staged_floor_halo_bytes,
		)
		_mountain_staged_floor_halo_texture = _update_or_create_l8_texture(
			_mountain_staged_floor_halo_texture,
			_mountain_staged_floor_halo_image,
		)
		_mountain_staged_floor_halo_visual_dirty = false

	if _mountain_top_mask_visual_dirty:
		var create_image_started: int = WorldPerfProbe.begin()
		var mask_image: Image = Image.create_from_data(
			_mountain_top_mask_width,
			_mountain_top_mask_height,
			false,
			Image.FORMAT_L8,
			_mountain_top_mask_bytes,
		)
		WorldPerfProbe.end("ChunkView.mountain_visual.create_image", create_image_started)
		var upload_started: int = WorldPerfProbe.begin()
		_upload_mountain_mask_texture(
			mask_image,
			top_texture,
			face_texture,
			_mountain_top_mask_texture_scale,
			_mountain_top_mask_step_px,
			_mountain_top_mask_origin_world,
			top_normal_texture,
			face_normal_texture,
			foothill_texture,
			foothill_normal_texture,
		)
		WorldPerfProbe.end("ChunkView.mountain_visual.upload_texture", upload_started)
		_mountain_top_mask_image = mask_image
		_mountain_top_mask_visual_dirty = false

	_sync_mountain_closed_roof_visual(
		top_texture,
		face_texture,
		top_normal_texture,
		face_normal_texture,
	)
	_update_mountain_native_mask_pending_debug()
	return true


func apply_terrain_edge_mask_data(mask_result: Dictionary, mask_origin_world: Vector2) -> bool:
	var mask_bytes: PackedByteArray = mask_result.get("mask", PackedByteArray()) as PackedByteArray
	var mask_width: int = int(mask_result.get("width", 0))
	var mask_height: int = int(mask_result.get("height", 0))
	var mask_step_px: float = float(mask_result.get("step_px", 0.0))
	if mask_width <= 0 \
			or mask_height <= 0 \
			or mask_step_px <= 0.0 \
			or mask_bytes.size() != mask_width * mask_height:
		return false
	_terrain_edge_mask_image = null
	_terrain_edge_mask_bytes = mask_bytes.duplicate()
	_terrain_edge_mask_width = mask_width
	_terrain_edge_mask_height = mask_height
	_terrain_edge_mask_origin_world = mask_origin_world
	_terrain_edge_mask_step_px = mask_step_px
	_terrain_edge_mask_visual_dirty = true
	return true


func apply_pending_terrain_edge_mask_visual(
		top_texture: Texture2D,
		face_texture: Texture2D = null,
		top_normal_texture: Texture2D = null,
		face_normal_texture: Texture2D = null,
		grass_overlay_texture: Texture2D = null,
		grass_overlay_texture_2: Texture2D = null,
		grass_overlay_texture_3: Texture2D = null,
		grass_overlay_normal_texture: Texture2D = null,
		rock_patch_texture: Texture2D = null,
		rock_patch_normal_texture: Texture2D = null,
) -> bool:
	if not _terrain_edge_mask_visual_dirty:
		return false
	if top_texture == null \
			or _terrain_edge_mask_width <= 0 \
			or _terrain_edge_mask_height <= 0 \
			or _terrain_edge_mask_step_px <= 0.0 \
			or _terrain_edge_mask_bytes.size() != _terrain_edge_mask_width * _terrain_edge_mask_height:
		return false
	var create_image_started: int = WorldPerfProbe.begin()
	var mask_image: Image = Image.create_from_data(
		_terrain_edge_mask_width,
		_terrain_edge_mask_height,
		false,
		Image.FORMAT_L8,
		_terrain_edge_mask_bytes,
	)
	WorldPerfProbe.end("ChunkView.terrain_edge_visual.create_image", create_image_started)
	var upload_started: int = WorldPerfProbe.begin()
	_upload_terrain_edge_mask_texture(
		mask_image,
		top_texture,
		face_texture,
		top_normal_texture,
		face_normal_texture,
		grass_overlay_texture,
		grass_overlay_texture_2,
		grass_overlay_texture_3,
		grass_overlay_normal_texture,
		rock_patch_texture,
		rock_patch_normal_texture,
	)
	WorldPerfProbe.end("ChunkView.terrain_edge_visual.upload_texture", upload_started)
	_terrain_edge_mask_image = mask_image
	_terrain_edge_mask_visual_dirty = false
	return true


func invalidate_mountain_render_page_hit_mask_keep_visual() -> void:
	_mountain_page_hit_mask = PackedByteArray()
	_mountain_page_hit_mask_width = 0
	_mountain_page_hit_mask_height = 0
	_mountain_page_hit_mask_origin_world = Vector2.ZERO
	_mountain_page_hit_mask_step_px = 0.0
	_mountain_page_debug["ready"] = false
	_mountain_page_debug["visual_stale"] = true


func _apply_mountain_top_mask(
		result: Dictionary,
		top_texture: Texture2D,
		face_texture: Texture2D,
		top_normal_texture: Texture2D = null,
		face_normal_texture: Texture2D = null,
) -> void:
	var top_mask: PackedByteArray = result.get("top_mask", PackedByteArray()) as PackedByteArray
	var top_mask_width: int = int(result.get("top_mask_width", 0))
	var top_mask_height: int = int(result.get("top_mask_height", 0))
	if top_texture == null \
			or top_mask.is_empty() \
			or top_mask_width <= 0 \
			or top_mask_height <= 0 \
			or top_mask.size() != top_mask_width * top_mask_height:
		_clear_mountain_top_mask()
		return
	var top_mask_image: Image = Image.create_from_data(
		top_mask_width,
		top_mask_height,
		false,
		Image.FORMAT_L8,
		top_mask,
	)
	var top_mask_origin_world: Vector2 = result.get("top_mask_origin_world", Vector2.ZERO) as Vector2
	var top_mask_step_px: float = float(result.get("top_mask_step_px", 1.0))
	_apply_mountain_mask_image(
		top_mask_image,
		top_texture,
		face_texture,
		float(result.get("top_texture_scale", 0.70)),
		top_mask_step_px,
		top_mask_origin_world,
		top_normal_texture,
		face_normal_texture,
	)


func _apply_mountain_mask_image(
		mask_image: Image,
		top_texture: Texture2D,
		face_texture: Texture2D,
		top_texture_scale: float,
		mask_step_px: float,
		mask_origin_world: Vector2,
		top_normal_texture: Texture2D = null,
		face_normal_texture: Texture2D = null,
) -> void:
	# This path publishes a non-native/fallback mask that has no immutable CLOSED
	# companion. Keeping an older construction roof here would pair different
	# origins/revisions and leave a stale roof floating above the new BASE.
	_clear_mountain_closed_roof_state()
	_mountain_top_mask_image = mask_image
	_mountain_top_mask_bytes = mask_image.get_data()
	_mountain_top_mask_width = mask_image.get_width()
	_mountain_top_mask_height = mask_image.get_height()
	_mountain_top_mask_origin_world = mask_origin_world
	_mountain_top_mask_step_px = mask_step_px
	_mountain_top_mask_texture_scale = top_texture_scale
	_mountain_top_mask_visual_dirty = false
	_upload_mountain_mask_texture(
		mask_image,
		top_texture,
		face_texture,
		top_texture_scale,
		mask_step_px,
		mask_origin_world,
		top_normal_texture,
		face_normal_texture,
	)


func _upload_mountain_mask_texture(
		mask_image: Image,
		top_texture: Texture2D,
		face_texture: Texture2D,
		top_texture_scale: float,
		mask_step_px: float,
		mask_origin_world: Vector2,
		top_normal_texture: Texture2D = null,
		face_normal_texture: Texture2D = null,
		foothill_texture: Texture2D = null,
		foothill_normal_texture: Texture2D = null,
) -> void:
	var phase_started: int = WorldPerfProbe.begin()
	_capture_mountain_foothill_mask_if_needed(mask_image, mask_origin_world, mask_step_px)
	WorldPerfProbe.end("ChunkView.mountain_upload.capture_foothill", phase_started)
	phase_started = WorldPerfProbe.begin()
	if _mountain_top_mask_texture != null \
			and _mountain_top_mask_texture.get_width() == _mountain_top_mask_width \
			and _mountain_top_mask_texture.get_height() == _mountain_top_mask_height:
		_mountain_top_mask_texture.update(mask_image)
		WorldPerfProbe.end("ChunkView.mountain_upload.top_texture_update", phase_started)
	else:
		_mountain_top_mask_texture = ImageTexture.create_from_image(mask_image)
		WorldPerfProbe.end("ChunkView.mountain_upload.top_texture_create", phase_started)
	phase_started = WorldPerfProbe.begin()
	var sprite: Sprite2D = _ensure_mountain_top_mask_sprite()
	var material: ShaderMaterial = _ensure_mountain_top_mask_material()
	WorldPerfProbe.end("ChunkView.mountain_upload.ensure_nodes", phase_started)
	phase_started = WorldPerfProbe.begin()
	_mountain_top_mask_origin_world = mask_origin_world
	_mountain_top_mask_step_px = mask_step_px
	_mountain_top_mask_texture_scale = top_texture_scale
	material.set_shader_parameter("top_texture", top_texture)
	material.set_shader_parameter(
		"top_texture_size",
		Vector2(
			maxf(1.0, float(top_texture.get_width())),
			maxf(1.0, float(top_texture.get_height())),
		),
	)
	if face_texture == null:
		face_texture = top_texture
	if face_texture != null:
		material.set_shader_parameter("face_texture", face_texture)
		material.set_shader_parameter(
			"face_texture_size",
			Vector2(
				maxf(1.0, float(face_texture.get_width())),
				maxf(1.0, float(face_texture.get_height())),
			),
		)
	if face_normal_texture == null:
		face_normal_texture = top_normal_texture
	if top_normal_texture != null and face_normal_texture != null:
		material.set_shader_parameter("top_normal_texture", top_normal_texture)
		material.set_shader_parameter("face_normal_texture", face_normal_texture)
		material.set_shader_parameter("material_normal_mix", 1.0)
		material.set_shader_parameter("material_normal_strength", 1.45)
	else:
		material.set_shader_parameter("material_normal_mix", 0.0)
	material.set_shader_parameter("world_origin_px", mask_origin_world)
	material.set_shader_parameter("sample_step_px", mask_step_px)
	# All mountain dressing knobs are authored data on the material set; the
	# per-mask dynamic parameters (origin/step/top scale/clip/sun) stay code-set.
	_apply_mountain_material_sampling_params(material)
	material.set_shader_parameter("top_texture_scale", top_texture_scale)
	_set_mask_shader_chunk_clip(
		material,
		mask_origin_world,
		mask_image.get_width(),
		mask_image.get_height(),
		mask_step_px,
		MASK_UNDERLAY_CHUNK_OVERLAP_PX,
	)
	_apply_sun_lighting_to_mask_material(material, 1.0)
	sprite.material = material
	sprite.position = mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2.ONE * mask_step_px
	sprite.texture = _mountain_top_mask_texture
	sprite.visible = true
	WorldPerfProbe.end("ChunkView.mountain_upload.bind_base", phase_started)
	phase_started = WorldPerfProbe.begin()
	_sync_mountain_rock_underlay_visual(foothill_texture, foothill_normal_texture)
	WorldPerfProbe.end("ChunkView.mountain_upload.rock_underlay", phase_started)
	phase_started = WorldPerfProbe.begin()
	_sync_mountain_foothill_overlay_visual(foothill_texture, foothill_normal_texture)
	WorldPerfProbe.end("ChunkView.mountain_upload.foothill_overlay", phase_started)


func _sync_mountain_closed_roof_visual(
		top_texture: Texture2D,
		face_texture: Texture2D,
		top_normal_texture: Texture2D,
		face_normal_texture: Texture2D,
) -> void:
	var expected_mask_bytes: int = _mountain_top_mask_width * _mountain_top_mask_height
	var roof_ready: bool = top_texture != null \
			and expected_mask_bytes > 0 \
			and _mountain_closed_roof_mask_bytes.size() == expected_mask_bytes \
			and _mountain_closed_roof_mask_texture != null \
			and _mountain_top_mask_texture != null \
			and _mountain_active_floor_halo_texture != null \
			and _mountain_dug_halo_texture != null \
			and _mountain_active_floor_halo_side > 0 \
			and _mountain_active_floor_halo_side == _mountain_dug_halo_side \
			and _mountain_dug_halo_nonzero_count > 0
	if not roof_ready:
		_hide_mountain_closed_roof_visual()
		return

	var sprite: Sprite2D = _ensure_mountain_closed_roof_mask_sprite()
	var material: ShaderMaterial = _ensure_mountain_closed_roof_mask_material()
	material.set_shader_parameter("top_texture", top_texture)
	material.set_shader_parameter(
		"top_texture_size",
		Vector2(
			maxf(1.0, float(top_texture.get_width())),
			maxf(1.0, float(top_texture.get_height())),
		),
	)
	if face_texture == null:
		face_texture = top_texture
	material.set_shader_parameter("face_texture", face_texture)
	material.set_shader_parameter(
		"face_texture_size",
		Vector2(
			maxf(1.0, float(face_texture.get_width())),
			maxf(1.0, float(face_texture.get_height())),
		),
	)
	if face_normal_texture == null:
		face_normal_texture = top_normal_texture
	if top_normal_texture != null and face_normal_texture != null:
		material.set_shader_parameter("top_normal_texture", top_normal_texture)
		material.set_shader_parameter("face_normal_texture", face_normal_texture)
		material.set_shader_parameter("material_normal_mix", 1.0)
		material.set_shader_parameter("material_normal_strength", 1.45)
	else:
		material.set_shader_parameter("material_normal_mix", 0.0)
	material.set_shader_parameter("world_origin_px", _mountain_top_mask_origin_world)
	material.set_shader_parameter("sample_step_px", _mountain_top_mask_step_px)
	_apply_mountain_material_sampling_params(material)
	material.set_shader_parameter("top_texture_scale", _mountain_top_mask_texture_scale)
	material.set_shader_parameter("roof_overlay_mode", 1.0)
	material.set_shader_parameter("component_reveal_blend", _mountain_roof_reveal_blend)
	material.set_shader_parameter(
		"roof_component_reveal_enabled",
		1.0 if _mountain_active_floor_halo_nonzero_count > 0 else 0.0,
	)
	material.set_shader_parameter("base_visual_mask_texture", _mountain_top_mask_texture)
	material.set_shader_parameter("active_floor_halo_texture", _mountain_active_floor_halo_texture)
	material.set_shader_parameter("any_cutout_halo_texture", _mountain_dug_halo_texture)
	material.set_shader_parameter("any_cutout_broad_texture", _mountain_dug_halo_texture)
	_set_mask_shader_chunk_clip(
		material,
		_mountain_top_mask_origin_world,
		_mountain_top_mask_width,
		_mountain_top_mask_height,
		_mountain_top_mask_step_px,
		MASK_UNDERLAY_CHUNK_OVERLAP_PX,
	)
	# Keep the same daylight grading as BASE, but suppress the duplicate long
	# cast-shadow contribution from this second presentation-only pass.
	_apply_sun_lighting_to_mask_material(material, 1.0, false)
	sprite.material = material
	sprite.position = _mountain_top_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2.ONE * _mountain_top_mask_step_px
	sprite.z_as_relative = false
	sprite.z_index = WorldRuntimeConstants.Z_MOUNTAIN_ROOF
	sprite.texture = _mountain_closed_roof_mask_texture
	sprite.visible = true


func _hide_mountain_closed_roof_visual() -> void:
	if _mountain_closed_roof_mask_sprite != null \
			and is_instance_valid(_mountain_closed_roof_mask_sprite):
		_mountain_closed_roof_mask_sprite.texture = null
		_mountain_closed_roof_mask_sprite.visible = false
		_mountain_closed_roof_mask_sprite.scale = Vector2.ONE
		_mountain_closed_roof_mask_sprite.material = null


func _clear_mountain_closed_roof_state() -> void:
	_hide_mountain_closed_roof_visual()
	_mountain_closed_roof_mask_texture = null
	_mountain_closed_roof_mask_image = null
	_mountain_closed_roof_mask_bytes = PackedByteArray()
	_mountain_closed_roof_mask_material = null
	_mountain_closed_roof_mask_visual_dirty = false
	_mountain_sky_exposure_texture = null
	_mountain_sky_exposure_image = null
	_mountain_sky_exposure_bytes = PackedByteArray()
	_mountain_sky_exposure_reach_samples = 0
	_mountain_sky_exposure_source_sample_count = 0
	_mountain_sky_exposure_visual_dirty = false
	_mountain_active_floor_halo_bytes = PackedByteArray()
	_mountain_active_floor_halo_nonzero_count = 0
	_mountain_active_floor_halo_image = null
	_mountain_active_floor_halo_texture = null
	_mountain_active_floor_halo_side = 0
	_mountain_active_floor_halo_visual_dirty = false
	_clear_staged_mountain_roof_reveal_halo()
	_mountain_dug_halo_bytes = PackedByteArray()
	_mountain_dug_halo_nonzero_count = 0
	_mountain_dug_halo_image = null
	_mountain_dug_halo_texture = null
	_mountain_dug_halo_side = 0
	_mountain_dug_halo_visual_dirty = false


func _clear_staged_mountain_roof_reveal_halo() -> void:
	_mountain_staged_floor_halo_bytes = PackedByteArray()
	_mountain_staged_floor_halo_nonzero_count = 0
	_mountain_staged_floor_halo_image = null
	_mountain_staged_floor_halo_texture = null
	_mountain_staged_floor_halo_side = 0
	_mountain_staged_floor_halo_generation = 0
	_mountain_staged_floor_halo_visual_dirty = false


func _update_mountain_native_mask_pending_debug() -> void:
	var roof_visual_pending: bool = _mountain_closed_roof_mask_visual_dirty \
			or _mountain_sky_exposure_visual_dirty \
			or _mountain_active_floor_halo_visual_dirty \
			or _mountain_staged_floor_halo_generation > 0 \
			or _mountain_dug_halo_visual_dirty
	var native_visual_pending: bool = _mountain_top_mask_visual_dirty or roof_visual_pending
	_mountain_page_debug["roof_reveal_visual_pending"] = \
	_mountain_staged_floor_halo_generation > 0 \
			or _mountain_active_floor_halo_visual_dirty
	_mountain_page_debug["native_mask_visual_pending"] = native_visual_pending
	_mountain_page_debug["native_mask_visual_ready"] = \
	_is_mountain_native_mask_active() \
			and _mountain_top_mask_texture != null \
			and not native_visual_pending


func _is_mountain_native_mask_active() -> bool:
	return _mountain_top_mask_width > 0 \
			and _mountain_top_mask_height > 0 \
			and _mountain_top_mask_step_px > 0.0 \
			and _mountain_top_mask_bytes.size() \
					== _mountain_top_mask_width * _mountain_top_mask_height


func _square_l8_mask_side(mask_bytes: PackedByteArray) -> int:
	if mask_bytes.is_empty():
		return 0
	var side: int = floori(sqrt(float(mask_bytes.size())))
	return side if side > 0 and side * side == mask_bytes.size() else 0


func _normalize_binary_l8_mask(mask_bytes: PackedByteArray) -> PackedByteArray:
	var normalized := PackedByteArray()
	normalized.resize(mask_bytes.size())
	for index: int in range(mask_bytes.size()):
		normalized[index] = 255 if int(mask_bytes[index]) != 0 else 0
	return normalized


func _count_nonzero_mask_bytes(mask_bytes: PackedByteArray) -> int:
	var count: int = 0
	for value: int in mask_bytes:
		if value != 0:
			count += 1
	return count


func _update_or_create_l8_texture(texture: ImageTexture, image: Image) -> ImageTexture:
	if texture != null \
			and texture.get_width() == image.get_width() \
			and texture.get_height() == image.get_height():
		texture.update(image)
		return texture
	return ImageTexture.create_from_image(image)


func _upload_terrain_edge_mask_texture(
		mask_image: Image,
		top_texture: Texture2D,
		face_texture: Texture2D,
		top_normal_texture: Texture2D,
		face_normal_texture: Texture2D,
		grass_overlay_texture: Texture2D,
		grass_overlay_texture_2: Texture2D,
		grass_overlay_texture_3: Texture2D,
		grass_overlay_normal_texture: Texture2D,
		rock_patch_texture: Texture2D,
		rock_patch_normal_texture: Texture2D,
) -> void:
	if _terrain_edge_mask_texture != null \
			and _terrain_edge_mask_texture.get_width() == _terrain_edge_mask_width \
			and _terrain_edge_mask_texture.get_height() == _terrain_edge_mask_height:
		_terrain_edge_mask_texture.update(mask_image)
	else:
		_terrain_edge_mask_texture = ImageTexture.create_from_image(mask_image)
	var sprite: Sprite2D = _ensure_terrain_edge_mask_sprite()
	var material: ShaderMaterial = _ensure_terrain_edge_mask_material()
	if face_texture == null:
		face_texture = top_texture
	if face_normal_texture == null:
		face_normal_texture = top_normal_texture
	material.set_shader_parameter("top_texture", top_texture)
	material.set_shader_parameter(
		"top_texture_size",
		Vector2(
			maxf(1.0, float(top_texture.get_width())),
			maxf(1.0, float(top_texture.get_height())),
		),
	)
	material.set_shader_parameter("face_texture", face_texture)
	material.set_shader_parameter(
		"face_texture_size",
		Vector2(
			maxf(1.0, float(face_texture.get_width())),
			maxf(1.0, float(face_texture.get_height())),
		),
	)
	if top_normal_texture != null and face_normal_texture != null:
		material.set_shader_parameter("top_normal_texture", top_normal_texture)
		material.set_shader_parameter("face_normal_texture", face_normal_texture)
		material.set_shader_parameter("material_normal_mix", 1.0)
		material.set_shader_parameter("material_normal_strength", 1.45)
	else:
		material.set_shader_parameter("material_normal_mix", 0.0)
	material.set_shader_parameter("world_origin_px", _terrain_edge_mask_origin_world)
	material.set_shader_parameter("sample_step_px", _terrain_edge_mask_step_px)
	material.set_shader_parameter("top_texture_scale", TERRAIN_EDGE_TOP_TEXTURE_SCALE)
	material.set_shader_parameter("face_texture_scale", TERRAIN_EDGE_FACE_TEXTURE_SCALE)
	material.set_shader_parameter("facade_height_px", TERRAIN_EDGE_FACADE_HEIGHT_PX)
	material.set_shader_parameter("overhang_px", 3.0)
	# Shoreline band mode: the dry interior belongs to the ground material, so
	# the mask paints only a noisy packed-shore strip along the water contour.
	# Lower thresholds bulge the organic contour outward into the water tiles,
	# so it never undercuts square land tiles that the base layer painted.
	material.set_shader_parameter("top_threshold_low", TERRAIN_EDGE_CONTOUR_THRESHOLD_LOW)
	material.set_shader_parameter("top_threshold_high", TERRAIN_EDGE_CONTOUR_THRESHOLD_HIGH)
	material.set_shader_parameter("top_band_px", TERRAIN_EDGE_TOP_BAND_PX)
	material.set_shader_parameter("top_band_feather_px", TERRAIN_EDGE_TOP_BAND_FEATHER_PX)
	# No silhouette warp on shorelines: the water-fill clip samples the raw
	# mask, and both silhouettes must stay identical.
	material.set_shader_parameter("mask_warp_px", 0.0)
	_apply_land_mask_to_water_fill()
	material.set_shader_parameter("normal_strength", 0.48)
	material.set_shader_parameter("light_ambient", 0.58)
	material.set_shader_parameter("light_diffuse", 0.44)
	material.set_shader_parameter("top_surface_alpha", TERRAIN_EDGE_TOP_ALPHA)
	material.set_shader_parameter("wall_surface_alpha", 0.94)
	material.set_shader_parameter("top_dust_tint", Vector3(0.82, 0.87, 0.90))
	material.set_shader_parameter("cleft_color", Vector3(0.045, 0.052, 0.055))
	material.set_shader_parameter("crack_color", Vector3(0.018, 0.023, 0.026))
	material.set_shader_parameter("base_debris_color", Vector3(0.075, 0.082, 0.084))
	material.set_shader_parameter("eave_shadow_color", Vector3(0.040, 0.048, 0.050))
	material.set_shader_parameter("biofield_rim_strength", 0.0)
	_set_mask_shader_chunk_clip(
		material,
		_terrain_edge_mask_origin_world,
		mask_image.get_width(),
		mask_image.get_height(),
		_terrain_edge_mask_step_px,
		MASK_UNDERLAY_CHUNK_OVERLAP_PX,
	)
	_apply_sun_lighting_to_mask_material(
		material,
		WorldVisualLightingProfile.TERRAIN_EDGE_SHADOW_OPACITY_SCALE,
	)
	sprite.material = material
	sprite.position = _terrain_edge_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2.ONE * _terrain_edge_mask_step_px
	sprite.texture = _terrain_edge_mask_texture
	sprite.visible = true
	_sync_rock_patch_overlay_visual(
		rock_patch_texture,
		rock_patch_normal_texture,
	)
	_sync_grass_blob_overlay_visual(
		grass_overlay_texture,
		grass_overlay_texture_2,
		grass_overlay_texture_3,
		grass_overlay_normal_texture,
	)


func _clear_mountain_top_mask(
		preserve_foothill: bool = false,
		preserve_gpu_allocations: bool = false,
) -> void:
	if _mountain_top_mask_sprite != null and is_instance_valid(_mountain_top_mask_sprite):
		_mountain_top_mask_sprite.texture = null
		_mountain_top_mask_sprite.visible = false
		_mountain_top_mask_sprite.scale = Vector2.ONE
		_mountain_top_mask_sprite.material = null
	_clear_mountain_rock_underlay()
	if not preserve_foothill:
		_clear_mountain_foothill_mask(preserve_gpu_allocations)
		_clear_mountain_foothill_overlay()
	if not preserve_gpu_allocations:
		_mountain_top_mask_texture = null
	_mountain_top_mask_image = null
	_mountain_top_mask_bytes = PackedByteArray()
	_mountain_top_mask_width = 0
	_mountain_top_mask_height = 0
	_mountain_top_mask_origin_world = Vector2.ZERO
	_mountain_top_mask_step_px = 0.0
	_mountain_top_mask_texture_scale = 0.70
	_mountain_top_mask_visual_dirty = false
	_clear_mountain_closed_roof_state()


func clear_terrain_edge_mask(preserve_gpu_allocation: bool = false) -> void:
	if _terrain_edge_mask_sprite != null and is_instance_valid(_terrain_edge_mask_sprite):
		_terrain_edge_mask_sprite.texture = null
		_terrain_edge_mask_sprite.visible = false
		_terrain_edge_mask_sprite.scale = Vector2.ONE
		_terrain_edge_mask_sprite.material = null
	if not preserve_gpu_allocation:
		_terrain_edge_mask_texture = null
	_terrain_edge_mask_image = null
	_terrain_edge_mask_bytes = PackedByteArray()
	_terrain_edge_mask_width = 0
	_terrain_edge_mask_height = 0
	_terrain_edge_mask_origin_world = Vector2.ZERO
	_terrain_edge_mask_step_px = 0.0
	_terrain_edge_mask_visual_dirty = false
	if _water_fill_material != null:
		_water_fill_material.set_shader_parameter("land_mask_enabled", 0.0)
	_clear_rock_patch_overlay()
	_clear_grass_blob_overlay()


func _apply_sun_lighting_to_mask_material(
		material: ShaderMaterial,
		shadow_opacity_scale: float,
		draw_projected_shadow: bool = true,
) -> void:
	if material == null:
		return
	material.set_shader_parameter("light_angle_deg", _sun_light_angle_deg)
	material.set_shader_parameter("projected_shadow_angle_deg", _sun_light_angle_deg + 180.0)
	material.set_shader_parameter("projected_shadow_length_px", _sun_shadow_length_px)
	material.set_shader_parameter("projected_shadow_opacity", _sun_shadow_opacity * shadow_opacity_scale)
	material.set_shader_parameter("projected_shadow_softness_px", _sun_shadow_softness_px)
	material.set_shader_parameter("projected_shadow_draw_enabled", 1.0 if draw_projected_shadow else 0.0)


func _apply_sun_lighting_to_foothill_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("light_angle_deg", _sun_light_angle_deg)


func _apply_sun_lighting_to_rock_patch_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("light_angle_deg", _sun_light_angle_deg)


func _apply_sun_lighting_to_grass_blob_material(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("light_angle_deg", _sun_light_angle_deg)


func _apply_sun_lighting_to_object_packet_layer() -> void:
	if _object_packet_layer == null or not is_instance_valid(_object_packet_layer):
		return
	_object_packet_layer.set_sun_lighting(
		_sun_light_angle_deg,
		_sun_shadow_length_px,
		_sun_shadow_opacity,
		_sun_shadow_softness_px,
	)


func _apply_mountain_full_top_fill(top_texture: Texture2D, face_texture: Texture2D, top_texture_scale: float) -> void:
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mask.fill(255)
	_mountain_top_mask_image = Image.create_from_data(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_L8,
		mask,
	)
	var chunk_origin_world: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_apply_mountain_mask_image(
		_mountain_top_mask_image,
		top_texture,
		face_texture,
		top_texture_scale,
		float(WorldRuntimeConstants.TILE_SIZE_PX),
		chunk_origin_world,
	)


func clear_mountain_render_page(
		preserve_foothill: bool = false,
		preserve_gpu_allocations: bool = false,
) -> void:
	if _mountain_page_sprite != null and is_instance_valid(_mountain_page_sprite):
		_mountain_page_sprite.texture = null
		_mountain_page_sprite.visible = false
		_mountain_page_sprite.scale = Vector2.ONE
	_mountain_interior_fill_active = false
	_mountain_page_texture = null
	_mountain_page_image = null
	_mountain_page_normal_texture = null
	_mountain_page_lit_texture = null
	_clear_mountain_top_mask(preserve_foothill, preserve_gpu_allocations)
	_mountain_page_hit_mask = PackedByteArray()
	_mountain_page_hit_mask_width = 0
	_mountain_page_hit_mask_height = 0
	_mountain_page_hit_mask_origin_world = Vector2.ZERO
	_mountain_page_hit_mask_step_px = 0.0
	_mountain_page_render_origin_world = Vector2.ZERO
	_mountain_page_debug = {
		"ready": false,
		"chunk_coord": chunk_coord,
	}


func apply_mountain_local_dig_patch(local_coord: Vector2i, padding_px: int = 2) -> bool:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return false
	var patched: bool = false
	var tile_min_world: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord) \
			+ Vector2(float(local_coord.x), float(local_coord.y)) * float(WorldRuntimeConstants.TILE_SIZE_PX)
	var tile_max_world: Vector2 = tile_min_world + Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX)
	if _clear_mountain_top_mask_rect(tile_min_world, tile_max_world, padding_px):
		patched = true
	if _clear_mountain_page_hit_rect(tile_min_world, tile_max_world, padding_px):
		patched = true
	if patched:
		_mountain_page_debug["local_dig_patch_count"] = int(_mountain_page_debug.get("local_dig_patch_count", 0)) + 1
	return patched


func apply_mountain_world_dig_patch(world_tile: Vector2i, padding_px: int = 2) -> bool:
	var patched: bool = false
	var tile_min_world: Vector2 = Vector2(
		float(world_tile.x * WorldRuntimeConstants.TILE_SIZE_PX),
		float(world_tile.y * WorldRuntimeConstants.TILE_SIZE_PX),
	)
	var tile_max_world: Vector2 = tile_min_world + Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX)
	if _clear_mountain_top_mask_rect(tile_min_world, tile_max_world, padding_px):
		patched = true
	if _clear_mountain_page_hit_rect(tile_min_world, tile_max_world, padding_px):
		patched = true
	if patched:
		_mountain_page_debug["world_dig_patch_count"] = int(_mountain_page_debug.get("world_dig_patch_count", 0)) + 1
	return patched


func apply_mountain_world_dig_collision_patch(world_tile: Vector2i, padding_px: int = 2) -> bool:
	var patched: bool = false
	var tile_min_world: Vector2 = Vector2(
		float(world_tile.x * WorldRuntimeConstants.TILE_SIZE_PX),
		float(world_tile.y * WorldRuntimeConstants.TILE_SIZE_PX),
	)
	var tile_max_world: Vector2 = tile_min_world + Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX)
	if _clear_mountain_top_mask_rect(tile_min_world, tile_max_world, padding_px, false):
		patched = true
	if _clear_mountain_page_hit_rect(tile_min_world, tile_max_world, padding_px):
		patched = true
	if patched:
		_mountain_page_debug["world_dig_collision_patch_count"] = int(_mountain_page_debug.get("world_dig_collision_patch_count", 0)) + 1
	return patched


func has_mountain_render_page() -> bool:
	return (_mountain_page_hit_mask_width > 0 \
				and _mountain_page_hit_mask_height > 0 \
				and not _mountain_page_hit_mask.is_empty() ) \
			or (_mountain_top_mask_width > 0 \
						and _mountain_top_mask_height > 0 \
						and not _mountain_top_mask_bytes.is_empty() \
						and _mountain_top_mask_step_px > 0.0 )


func sample_mountain_page_hit_at_world(world_pos: Vector2) -> Dictionary:
	if _mountain_page_hit_mask_width > 0 \
			and _mountain_page_hit_mask_height > 0 \
			and not _mountain_page_hit_mask.is_empty() \
			and _mountain_page_hit_mask_step_px > 0.0:
		var mask_position: Vector2 = (world_pos - _mountain_page_hit_mask_origin_world) / _mountain_page_hit_mask_step_px
		var x: int = floori(mask_position.x)
		var y: int = floori(mask_position.y)
		if x < 0 or y < 0 or x >= _mountain_page_hit_mask_width or y >= _mountain_page_hit_mask_height:
			return {
				"ready": true,
				"in_bounds": false,
				"solid": false,
				"chunk_coord": chunk_coord,
			}
		var index: int = y * _mountain_page_hit_mask_width + x
		return {
			"ready": true,
			"in_bounds": true,
			"solid": int(_mountain_page_hit_mask[index]) != 0,
			"chunk_coord": chunk_coord,
		}
	if _mountain_top_mask_width <= 0 \
			or _mountain_top_mask_height <= 0 \
			or _mountain_top_mask_bytes.is_empty() \
			or _mountain_top_mask_step_px <= 0.0:
		return {
			"ready": false,
			"in_bounds": false,
			"solid": false,
			"chunk_coord": chunk_coord,
		}
	var mask_position: Vector2 = (world_pos - _mountain_top_mask_origin_world) / _mountain_top_mask_step_px
	var x: int = floori(mask_position.x)
	var y: int = floori(mask_position.y)
	if x < 0 or y < 0 or x >= _mountain_top_mask_width or y >= _mountain_top_mask_height:
		return {
			"ready": true,
			"in_bounds": false,
			"solid": false,
			"chunk_coord": chunk_coord,
		}
	var index: int = y * _mountain_top_mask_width + x
	var mask: int = int(_mountain_top_mask_bytes[index]) if index >= 0 and index < _mountain_top_mask_bytes.size() else 0
	var solid: bool = mask > MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD \
			or _is_mountain_facade_band_solid(x, y)
	return {
		"ready": true,
		"in_bounds": true,
		"solid": solid,
		"chunk_coord": chunk_coord,
	}


## Raw immutable construction-roof sample used only for organic cave ownership
## hysteresis. Unlike gameplay collision it does not add the facade band.
func sample_mountain_closed_roof_hit_at_world(world_pos: Vector2) -> Dictionary:
	return _sample_mountain_raw_mask_bytes_at_world(world_pos, _mountain_closed_roof_mask_bytes)


## Raw live remaining-mass sample for cover ownership. Gameplay collision uses
## `sample_mountain_page_hit_at_world()` and deliberately adds the facade band
## the resolver must compare CLOSED against the raw live mask or the projected
## facade lip can falsely look solid and close the roof.
func sample_mountain_remaining_mass_hit_at_world(world_pos: Vector2) -> Dictionary:
	return _sample_mountain_raw_mask_bytes_at_world(world_pos, _mountain_top_mask_bytes)


func _sample_mountain_raw_mask_bytes_at_world(
		world_pos: Vector2,
		mask_bytes: PackedByteArray,
) -> Dictionary:
	if _mountain_top_mask_width <= 0 \
			or _mountain_top_mask_height <= 0 \
			or mask_bytes.size() != _mountain_top_mask_width * _mountain_top_mask_height \
			or _mountain_top_mask_step_px <= 0.0:
		return {
			"ready": false,
			"in_bounds": false,
			"solid": false,
			"chunk_coord": chunk_coord,
		}
	var mask_position: Vector2 = (
		world_pos - _mountain_top_mask_origin_world
	) / _mountain_top_mask_step_px
	var x: int = floori(mask_position.x)
	var y: int = floori(mask_position.y)
	if x < 0 or y < 0 or x >= _mountain_top_mask_width or y >= _mountain_top_mask_height:
		return {
			"ready": true,
			"in_bounds": false,
			"solid": false,
			"chunk_coord": chunk_coord,
		}
	var index: int = y * _mountain_top_mask_width + x
	return {
		"ready": true,
		"in_bounds": true,
		"solid": int(mask_bytes[index]) > MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD,
		"chunk_coord": chunk_coord,
	}


func _is_mountain_facade_band_solid(mask_x: int, mask_y: int) -> bool:
	if mask_x < 0 \
			or mask_y < 0 \
			or mask_x >= _mountain_top_mask_width \
			or mask_y >= _mountain_top_mask_height \
			or _mountain_top_mask_step_px <= 0.0:
		return false
	var facade_texels: int = maxi(1, ceili(MOUNTAIN_FACADE_COLLISION_DEPTH_PX / _mountain_top_mask_step_px))
	for distance: int in range(1, facade_texels + 1):
		var north_y: int = mask_y - distance
		if north_y < 0:
			return false
		var north_index: int = north_y * _mountain_top_mask_width + mask_x
		if north_index < 0 or north_index >= _mountain_top_mask_bytes.size():
			continue
		if int(_mountain_top_mask_bytes[north_index]) > MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD:
			return true
	return false


func get_mountain_render_page_debug_state() -> Dictionary:
	var debug := _mountain_page_debug.duplicate(true)
	var active: bool = _is_mountain_native_mask_active()
	var pending: bool = is_mountain_native_mask_visual_pending()
	debug["native_mask_visual_pending"] = pending
	debug["native_mask_visual_ready"] = \
			active and _mountain_top_mask_texture != null and not pending
	debug["native_mask_gpu_allocation_retained"] = \
			not active and _mountain_top_mask_texture != null
	return debug


## Returns only already-uploaded presentation textures. MountainCavitySkylightField
## binds these references directly and never creates a second mask copy.
func get_mountain_cavity_skylight_field_source() -> Dictionary:
	var mask_byte_count: int = _mountain_top_mask_width * _mountain_top_mask_height
	var selector_byte_count: int = _mountain_active_floor_halo_side \
			* _mountain_active_floor_halo_side
	var facade_height_px: float = 0.0
	if _mountain_closed_roof_mask_material != null:
		facade_height_px = float(
			_mountain_closed_roof_mask_material.get_shader_parameter("facade_height_px"),
		)
	var ready: bool = mask_byte_count > 0 \
			and selector_byte_count > 0 \
			and _mountain_top_mask_step_px > 0.0 \
			and _mountain_top_mask_bytes.size() == mask_byte_count \
			and _mountain_closed_roof_mask_bytes.size() == mask_byte_count \
			and _mountain_sky_exposure_bytes.size() == mask_byte_count \
			and _mountain_active_floor_halo_bytes.size() == selector_byte_count \
			and _mountain_top_mask_texture != null \
			and _mountain_closed_roof_mask_texture != null \
			and _mountain_sky_exposure_texture != null \
			and _mountain_active_floor_halo_texture != null \
			and _mountain_dug_halo_texture != null \
			and facade_height_px > 0.0 \
			and not _mountain_top_mask_visual_dirty \
			and not _mountain_closed_roof_mask_visual_dirty \
			and not _mountain_sky_exposure_visual_dirty \
			and not _mountain_active_floor_halo_visual_dirty
	if not ready:
		return {
			"ready": false,
			"chunk_coord": chunk_coord,
		}

	var chunk_size_px: float = float(
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX,
	)
	var mask_size_world := Vector2(
		float(_mountain_top_mask_width) * _mountain_top_mask_step_px,
		float(_mountain_top_mask_height) * _mountain_top_mask_step_px,
	)
	var selector_size_px: float = float(
		_mountain_active_floor_halo_side * WorldRuntimeConstants.TILE_SIZE_PX,
	)
	return {
		"ready": true,
		"chunk_coord": chunk_coord,
		"live_mask_texture": _mountain_top_mask_texture,
		"closed_roof_mask_texture": _mountain_closed_roof_mask_texture,
		"sky_exposure_texture": _mountain_sky_exposure_texture,
		"reveal_selector_texture": _mountain_active_floor_halo_texture,
		"any_cutout_texture": _mountain_dug_halo_texture,
		"chunk_origin_world": WorldRuntimeConstants.chunk_origin_px(chunk_coord),
		"chunk_size_world": Vector2.ONE * chunk_size_px,
		"mask_origin_world": _mountain_top_mask_origin_world,
		"mask_size_world": mask_size_world,
		"selector_origin_world": _mountain_top_mask_origin_world,
		"selector_size_world": Vector2.ONE * selector_size_px,
		"mask_sample_step_px": _mountain_top_mask_step_px,
		"facade_height_px": facade_height_px,
	}


func get_mountain_native_mask_debug_state() -> Dictionary:
	var debug := _mountain_page_debug.duplicate(true)
	var active: bool = _is_mountain_native_mask_active()
	debug["native_mask_active"] = active
	debug["mask_width"] = _mountain_top_mask_width
	debug["mask_height"] = _mountain_top_mask_height
	debug["mask_step_px"] = _mountain_top_mask_step_px
	debug["mask_byte_count"] = _mountain_top_mask_bytes.size()
	debug["closed_roof_mask_byte_count"] = _mountain_closed_roof_mask_bytes.size()
	debug["closed_roof_texture_ready"] = _mountain_closed_roof_mask_texture != null
	debug["sky_exposure_mask_byte_count"] = _mountain_sky_exposure_bytes.size()
	debug["sky_exposure_texture_ready"] = _mountain_sky_exposure_texture != null
	debug["sky_exposure_reach_samples"] = _mountain_sky_exposure_reach_samples
	debug["sky_exposure_source_sample_count"] = _mountain_sky_exposure_source_sample_count
	debug["dug_halo_tile_count"] = _mountain_dug_halo_nonzero_count
	debug["active_floor_halo_tile_count"] = _mountain_active_floor_halo_nonzero_count
	debug["staged_floor_halo_tile_count"] = _mountain_staged_floor_halo_nonzero_count
	debug["staged_floor_halo_generation"] = _mountain_staged_floor_halo_generation
	debug["staged_floor_halo_ready"] = is_staged_mountain_roof_reveal_halo_ready(
		_mountain_staged_floor_halo_generation,
	)
	debug["roof_reveal_blend"] = _mountain_roof_reveal_blend
	debug["roof_overlay_visible"] = _mountain_closed_roof_mask_sprite != null \
			and is_instance_valid(_mountain_closed_roof_mask_sprite) \
			and _mountain_closed_roof_mask_sprite.visible
	var roof_visual_pending: bool = _mountain_closed_roof_mask_visual_dirty \
			or _mountain_sky_exposure_visual_dirty \
			or _mountain_active_floor_halo_visual_dirty \
			or _mountain_staged_floor_halo_generation > 0 \
			or _mountain_dug_halo_visual_dirty
	debug["roof_overlay_visual_pending"] = roof_visual_pending
	debug["has_visual_texture"] = active and _mountain_top_mask_texture != null
	debug["gpu_allocation_retained"] = not active and _mountain_top_mask_texture != null
	debug["native_mask_visual_pending"] = _mountain_top_mask_visual_dirty or roof_visual_pending
	debug["native_mask_visual_ready"] = active \
			and _mountain_top_mask_texture != null \
			and not _mountain_top_mask_visual_dirty \
			and not roof_visual_pending
	debug["foothill_mask_active"] = _mountain_foothill_mask_texture != null \
			and _mountain_foothill_mask_width > 0 \
			and _mountain_foothill_mask_height > 0 \
			and _mountain_foothill_mask_step_px > 0.0
	debug["foothill_overlay_visible"] = _mountain_foothill_overlay_sprite != null \
			and is_instance_valid(_mountain_foothill_overlay_sprite) \
			and _mountain_foothill_overlay_sprite.visible
	debug["rock_underlay_visible"] = _mountain_rock_underlay_sprite != null \
			and is_instance_valid(_mountain_rock_underlay_sprite) \
			and _mountain_rock_underlay_sprite.visible
	debug["chunk_coord"] = chunk_coord
	return debug


## Hot-path readiness probe. Unlike get_mountain_native_mask_debug_state(), it
## never scans diagnostic halo buffers.
func is_mountain_native_mask_visual_pending() -> bool:
	return _mountain_top_mask_visual_dirty \
			or _mountain_closed_roof_mask_visual_dirty \
			or _mountain_sky_exposure_visual_dirty \
			or _mountain_active_floor_halo_visual_dirty \
			or _mountain_staged_floor_halo_generation > 0 \
			or _mountain_dug_halo_visual_dirty


func get_terrain_edge_mask_debug_state() -> Dictionary:
	var active: bool = _terrain_edge_mask_width > 0 \
			and _terrain_edge_mask_height > 0 \
			and _terrain_edge_mask_step_px > 0.0 \
			and _terrain_edge_mask_bytes.size() \
					== _terrain_edge_mask_width * _terrain_edge_mask_height
	return {
		"terrain_edge_mask_active": active,
		"mask_width": _terrain_edge_mask_width,
		"mask_height": _terrain_edge_mask_height,
		"mask_step_px": _terrain_edge_mask_step_px,
		"mask_byte_count": _terrain_edge_mask_bytes.size(),
		"has_visual_texture": active and _terrain_edge_mask_texture != null,
		"gpu_allocation_retained": not active and _terrain_edge_mask_texture != null,
		"visual_pending": _terrain_edge_mask_visual_dirty,
		"visual_ready": active \
				and _terrain_edge_mask_texture != null \
				and not _terrain_edge_mask_visual_dirty,
		"grass_overlay_visible": _grass_blob_overlay_sprite != null \
				and is_instance_valid(_grass_blob_overlay_sprite) \
				and _grass_blob_overlay_sprite.visible,
		"chunk_coord": chunk_coord,
	}


func apply_cover_visibility(visible_mask: PackedByteArray) -> void:
	_ensure_layers()
	var resolved_mask: PackedByteArray = visible_mask
	if resolved_mask.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		resolved_mask = PackedByteArray()
		resolved_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var updated_mountains: Dictionary = { }
	for mountain_id_variant: Variant in roof_layers_by_mountain.keys():
		var mountain_id: int = int(mountain_id_variant)
		var image: Image = _ensure_roof_mask_image(mountain_id)
		image.fill(Color(1.0, 0.0, 0.0, 1.0))
	for index: int in range(mini(_pending_mountain_ids.size(), _pending_mountain_flags.size())):
		var mountain_id: int = int(_pending_mountain_ids[index])
		var mountain_flags: int = int(_pending_mountain_flags[index])
		if not _is_roof_bearing_mountain_tile(mountain_id, mountain_flags):
			continue
		var image: Image = _ensure_roof_mask_image(mountain_id)
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var hide_value: float = 0.0 if resolved_mask[index] != 0 else 1.0
		image.set_pixel(local_coord.x, local_coord.y, Color(hide_value, 0.0, 0.0, 1.0))
		updated_mountains[mountain_id] = true
	for mountain_id_variant: Variant in updated_mountains.keys():
		var mountain_id: int = int(mountain_id_variant)
		var texture: ImageTexture = _roof_mask_textures_by_mountain.get(mountain_id, null) as ImageTexture
		var image: Image = _roof_mask_images_by_mountain.get(mountain_id, null) as Image
		if texture != null and image != null:
			texture.update(image)


func _ensure_layers() -> void:
	if _base_layer != null \
			and is_instance_valid(_base_layer) \
			and _overlay_layer != null \
			and is_instance_valid(_overlay_layer):
		return
	if _base_layer == null or not is_instance_valid(_base_layer):
		_base_layer = TileMapLayer.new()
		_base_layer.name = "TerrainBaseLayer"
		_base_layer.tile_set = WorldTileSetFactory.get_base_tile_set()
		_base_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_base_layer)
	if _overlay_layer == null or not is_instance_valid(_overlay_layer):
		_overlay_layer = TileMapLayer.new()
		_overlay_layer.name = "TerrainOverlayLayer"
		_overlay_layer.tile_set = WorldTileSetFactory.get_overlay_tile_set()
		_overlay_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_overlay_layer.z_index = 1
		add_child(_overlay_layer)


func _ensure_water_layer() -> TileMapLayer:
	if _water_layer != null and is_instance_valid(_water_layer):
		return _water_layer
	_water_layer = TileMapLayer.new()
	_water_layer.name = "WaterSurfaceLayer"
	_water_layer.tile_set = WorldTileSetFactory.get_water_tile_set()
	_water_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_water_layer.z_index = 1
	add_child(_water_layer)
	return _water_layer


func _ensure_water_fill_sprite() -> Sprite2D:
	if _water_fill_sprite != null and is_instance_valid(_water_fill_sprite):
		return _water_fill_sprite
	_water_fill_sprite = Sprite2D.new()
	_water_fill_sprite.name = "WaterFillUnderlay"
	_water_fill_sprite.centered = false
	_water_fill_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_water_fill_sprite.z_as_relative = false
	_water_fill_sprite.z_index = 1
	add_child(_water_fill_sprite)
	return _water_fill_sprite


func _ensure_water_fill_texture() -> ImageTexture:
	if _water_fill_texture != null:
		return _water_fill_texture
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color(1.0, 1.0, 1.0, 1.0))
	_water_fill_texture = ImageTexture.create_from_image(image)
	return _water_fill_texture


func _ensure_water_fill_material() -> ShaderMaterial:
	if _water_fill_material != null:
		return _water_fill_material
	_water_fill_material = ShaderMaterial.new()
	_water_fill_material.shader = WATER_SURFACE_SHADER
	_water_fill_material.set_shader_parameter("water_world_scale_px", 1024.0)
	_water_fill_material.set_shader_parameter("land_mask_enabled", 0.0)
	return _water_fill_material


func _apply_land_mask_to_water_fill() -> void:
	# Clip the chunk water fill by the shoreline mask so the visible water
	# contour and the shore band share one organic silhouette.
	var material: ShaderMaterial = _ensure_water_fill_material()
	if _terrain_edge_mask_texture == null \
			or _terrain_edge_mask_width <= 0 \
			or _terrain_edge_mask_height <= 0 \
			or _terrain_edge_mask_step_px <= 0.0:
		material.set_shader_parameter("land_mask_enabled", 0.0)
		return
	var chunk_origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	var chunk_size_px: float = float(
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX,
	)
	var mask_world_size := Vector2(
		float(_terrain_edge_mask_width) * _terrain_edge_mask_step_px,
		float(_terrain_edge_mask_height) * _terrain_edge_mask_step_px,
	)
	material.set_shader_parameter("land_mask", _terrain_edge_mask_texture)
	material.set_shader_parameter("land_mask_enabled", 1.0)
	material.set_shader_parameter(
		"land_mask_uv_scale",
		Vector2(
			chunk_size_px / mask_world_size.x,
			chunk_size_px / mask_world_size.y,
		),
	)
	material.set_shader_parameter(
		"land_mask_uv_offset",
		Vector2(
			(chunk_origin.x - _terrain_edge_mask_origin_world.x) / mask_world_size.x,
			(chunk_origin.y - _terrain_edge_mask_origin_world.y) / mask_world_size.y,
		),
	)
	material.set_shader_parameter("land_threshold_low", TERRAIN_EDGE_CONTOUR_THRESHOLD_LOW)
	material.set_shader_parameter("land_threshold_high", TERRAIN_EDGE_CONTOUR_THRESHOLD_HIGH)


func _ensure_debug_layer() -> ChunkDebugVisualLayer:
	if _debug_layer != null and is_instance_valid(_debug_layer):
		return _debug_layer
	_debug_layer = ChunkDebugVisualLayer.new()
	_debug_layer.name = "ChunkDebugVisualLayer"
	_debug_layer.configure(chunk_coord)
	add_child(_debug_layer)
	return _debug_layer


func _ensure_mountain_page_sprite() -> Sprite2D:
	if _mountain_page_sprite != null and is_instance_valid(_mountain_page_sprite):
		return _mountain_page_sprite
	_mountain_page_sprite = Sprite2D.new()
	_mountain_page_sprite.name = "MountainRenderPage"
	_mountain_page_sprite.centered = false
	_mountain_page_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mountain_page_sprite.z_as_relative = false
	_mountain_page_sprite.z_index = WorldRuntimeConstants.Z_MOUNTAIN_PAGE
	add_child(_mountain_page_sprite)
	return _mountain_page_sprite


func _clear_mountain_page_hit_rect(tile_min_world: Vector2, tile_max_world: Vector2, padding_px: int) -> bool:
	if _mountain_page_hit_mask.is_empty() \
			or _mountain_page_hit_mask_width <= 0 \
			or _mountain_page_hit_mask_height <= 0 \
			or _mountain_page_hit_mask_step_px <= 0.0:
		return false
	var step_px: float = _mountain_page_hit_mask_step_px
	var min_x: int = maxi(0, floori((tile_min_world.x - _mountain_page_hit_mask_origin_world.x) / step_px) - padding_px)
	var min_y: int = maxi(0, floori((tile_min_world.y - _mountain_page_hit_mask_origin_world.y) / step_px) - padding_px)
	var max_x: int = mini(_mountain_page_hit_mask_width - 1, ceili((tile_max_world.x - _mountain_page_hit_mask_origin_world.x) / step_px) + padding_px)
	var max_y: int = mini(_mountain_page_hit_mask_height - 1, ceili((tile_max_world.y - _mountain_page_hit_mask_origin_world.y) / step_px) + padding_px)
	if min_x > max_x or min_y > max_y:
		return false
	for y: int in range(min_y, max_y + 1):
		var row_start: int = y * _mountain_page_hit_mask_width
		for x: int in range(min_x, max_x + 1):
			_mountain_page_hit_mask[row_start + x] = 0
	return true


func _clear_mountain_top_mask_rect(
		tile_min_world: Vector2,
		tile_max_world: Vector2,
		padding_px: int,
		mark_visual_dirty: bool = true,
) -> bool:
	if _mountain_top_mask_width <= 0 \
			or _mountain_top_mask_height <= 0 \
			or _mountain_top_mask_bytes.is_empty() \
			or _mountain_top_mask_step_px <= 0.0:
		return false
	var step_px: float = _mountain_top_mask_step_px
	var scaled_padding: int = ceili(float(padding_px) / step_px)
	var min_x: int = maxi(0, floori((tile_min_world.x - _mountain_top_mask_origin_world.x) / step_px) - scaled_padding)
	var min_y: int = maxi(0, floori((tile_min_world.y - _mountain_top_mask_origin_world.y) / step_px) - scaled_padding)
	var max_x: int = mini(_mountain_top_mask_width - 1, ceili((tile_max_world.x - _mountain_top_mask_origin_world.x) / step_px) + scaled_padding)
	var max_y: int = mini(_mountain_top_mask_height - 1, ceili((tile_max_world.y - _mountain_top_mask_origin_world.y) / step_px) + scaled_padding)
	if min_x > max_x or min_y > max_y:
		return false
	var feather_px: float = maxf(step_px * 2.0, float(padding_px) * 2.0 + 6.0)
	var image_changed: bool = mark_visual_dirty \
			and _mountain_top_mask_image != null \
			and not _mountain_top_mask_image.is_empty()
	var changed: bool = false
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var index: int = y * _mountain_top_mask_width + x
			if index < 0 or index >= _mountain_top_mask_bytes.size():
				continue
			var pixel_world: Vector2 = _mountain_top_mask_origin_world \
					+ Vector2(float(x) + 0.5, float(y) + 0.5) * step_px
			var clear_strength: float = _organic_dig_clear_strength(
				pixel_world,
				tile_min_world,
				tile_max_world,
				feather_px,
			)
			if clear_strength <= 0.0:
				continue
			var next_mask: int = int(roundf(float(_mountain_top_mask_bytes[index]) * (1.0 - clear_strength)))
			next_mask = clampi(next_mask, 0, 255)
			if next_mask == int(_mountain_top_mask_bytes[index]):
				continue
			_mountain_top_mask_bytes[index] = next_mask
			changed = true
			if image_changed:
				_mountain_top_mask_image.set_pixel(x, y, Color8(next_mask, next_mask, next_mask))
	if changed and mark_visual_dirty:
		_mountain_top_mask_visual_dirty = true
		_mountain_page_debug["native_mask_visual_pending"] = true
	return changed


func _organic_dig_clear_strength(pixel_world: Vector2, tile_min_world: Vector2, tile_max_world: Vector2, feather_px: float) -> float:
	var center: Vector2 = (tile_min_world + tile_max_world) * 0.5
	var half_extent: Vector2 = (tile_max_world - tile_min_world) * 0.5 + Vector2.ONE * (feather_px * 0.45)
	var radius: float = minf(half_extent.x, half_extent.y) * 0.46
	var q: Vector2 = (pixel_world - center).abs() - (half_extent - Vector2.ONE * radius)
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0))
	var sdf: float = outside.length() + minf(maxf(q.x, q.y), 0.0) - radius
	if sdf <= -feather_px:
		return 1.0
	if sdf >= feather_px:
		return 0.0
	return 1.0 - smoothstep(-feather_px, feather_px, sdf)


func _ensure_mountain_top_mask_sprite() -> Sprite2D:
	if _mountain_top_mask_sprite != null and is_instance_valid(_mountain_top_mask_sprite):
		return _mountain_top_mask_sprite
	_mountain_top_mask_sprite = Sprite2D.new()
	_mountain_top_mask_sprite.name = "MountainTopMaskUnderlay"
	_mountain_top_mask_sprite.centered = false
	_mountain_top_mask_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_mountain_top_mask_sprite.z_as_relative = false
	_mountain_top_mask_sprite.z_index = WorldRuntimeConstants.Z_MOUNTAIN_TOP
	add_child(_mountain_top_mask_sprite)
	return _mountain_top_mask_sprite


func _resolve_mountain_material_set() -> TerrainMaterialSet:
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID,
	)
	assert(material_set != null, "Missing TerrainMaterialSet %s for mountain mask presentation." % MOUNTAIN_MASK_UNDERLAY_MATERIAL_SET_ID)
	return material_set


func _apply_mountain_material_sampling_params(material: ShaderMaterial) -> void:
	var material_set: TerrainMaterialSet = _resolve_mountain_material_set()
	if material_set == null:
		return
	for parameter_name_variant: Variant in material_set.sampling_params.keys():
		material.set_shader_parameter(
			parameter_name_variant,
			material_set.sampling_params[parameter_name_variant],
		)


func _ensure_mountain_top_mask_material() -> ShaderMaterial:
	if _mountain_top_mask_material != null:
		return _mountain_top_mask_material
	_mountain_top_mask_material = ShaderMaterial.new()
	_mountain_top_mask_material.shader = MOUNTAIN_TOP_MASK_UNDERLAY_SHADER
	return _mountain_top_mask_material


func _ensure_mountain_closed_roof_mask_sprite() -> Sprite2D:
	if _mountain_closed_roof_mask_sprite != null \
			and is_instance_valid(_mountain_closed_roof_mask_sprite):
		return _mountain_closed_roof_mask_sprite
	_mountain_closed_roof_mask_sprite = Sprite2D.new()
	_mountain_closed_roof_mask_sprite.name = "MountainClosedRoofOverlay"
	_mountain_closed_roof_mask_sprite.centered = false
	_mountain_closed_roof_mask_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_mountain_closed_roof_mask_sprite.z_as_relative = false
	_mountain_closed_roof_mask_sprite.z_index = WorldRuntimeConstants.Z_MOUNTAIN_ROOF
	add_child(_mountain_closed_roof_mask_sprite)
	return _mountain_closed_roof_mask_sprite


func _ensure_mountain_closed_roof_mask_material() -> ShaderMaterial:
	if _mountain_closed_roof_mask_material != null:
		return _mountain_closed_roof_mask_material
	_mountain_closed_roof_mask_material = ShaderMaterial.new()
	_mountain_closed_roof_mask_material.shader = MOUNTAIN_TOP_MASK_UNDERLAY_SHADER
	return _mountain_closed_roof_mask_material


func _sync_mountain_rock_underlay_visual(
		foothill_texture: Texture2D,
		foothill_normal_texture: Texture2D,
) -> void:
	if not MOUNTAIN_ROCK_UNDERLAY_ENABLED \
			or foothill_texture == null \
			or _mountain_top_mask_texture == null \
			or _mountain_top_mask_width <= 0 \
			or _mountain_top_mask_height <= 0 \
			or _mountain_top_mask_step_px <= 0.0:
		_clear_mountain_rock_underlay()
		return
	var sprite: Sprite2D = _ensure_mountain_rock_underlay_sprite()
	var material: ShaderMaterial = _ensure_mountain_rock_underlay_material()
	material.set_shader_parameter("foothill_texture", foothill_texture)
	material.set_shader_parameter("mask_texture", _mountain_top_mask_texture)
	material.set_shader_parameter(
		"foothill_texture_size",
		Vector2(
			maxf(1.0, float(foothill_texture.get_width())),
			maxf(1.0, float(foothill_texture.get_height())),
		),
	)
	material.set_shader_parameter(
		"mask_texture_size",
		Vector2(
			maxf(1.0, float(_mountain_top_mask_width)),
			maxf(1.0, float(_mountain_top_mask_height)),
		),
	)
	if foothill_normal_texture != null:
		material.set_shader_parameter("foothill_normal_texture", foothill_normal_texture)
		material.set_shader_parameter("normal_mix", 1.0)
	else:
		material.set_shader_parameter("normal_mix", 0.0)
	material.set_shader_parameter("world_origin_px", _mountain_top_mask_origin_world)
	material.set_shader_parameter("sample_step_px", _mountain_top_mask_step_px)
	material.set_shader_parameter("texture_scale", MOUNTAIN_ROCK_UNDERLAY_TEXTURE_SCALE)
	material.set_shader_parameter("outer_width_px", MOUNTAIN_ROCK_UNDERLAY_OUTER_WIDTH_PX)
	material.set_shader_parameter("outer_width_variation_px", MOUNTAIN_ROCK_UNDERLAY_OUTER_WIDTH_VARIATION_PX)
	material.set_shader_parameter("inner_width_px", MOUNTAIN_ROCK_UNDERLAY_INNER_WIDTH_PX)
	material.set_shader_parameter("foothill_alpha", MOUNTAIN_ROCK_UNDERLAY_ALPHA)
	material.set_shader_parameter("footprint_fill_strength", MOUNTAIN_ROCK_UNDERLAY_FILL_STRENGTH)
	material.set_shader_parameter("footprint_fill_alpha", MOUNTAIN_ROCK_UNDERLAY_FILL_ALPHA)
	material.set_shader_parameter("max_alpha", MOUNTAIN_ROCK_UNDERLAY_MAX_ALPHA)
	material.set_shader_parameter("scree_strength", 0.0)
	_set_mask_shader_chunk_clip(
		material,
		_mountain_top_mask_origin_world,
		_mountain_top_mask_width,
		_mountain_top_mask_height,
		_mountain_top_mask_step_px,
		MASK_UNDERLAY_CHUNK_OVERLAP_PX,
	)
	_apply_sun_lighting_to_foothill_material(material)
	sprite.material = material
	sprite.position = _mountain_top_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2(
		float(_mountain_top_mask_width) * _mountain_top_mask_step_px,
		float(_mountain_top_mask_height) * _mountain_top_mask_step_px,
	)
	sprite.texture = _ensure_mountain_rock_underlay_canvas_texture()
	sprite.visible = true


func _clear_mountain_rock_underlay() -> void:
	if _mountain_rock_underlay_sprite != null and is_instance_valid(_mountain_rock_underlay_sprite):
		_mountain_rock_underlay_sprite.texture = null
		_mountain_rock_underlay_sprite.visible = false
		_mountain_rock_underlay_sprite.scale = Vector2.ONE
		_mountain_rock_underlay_sprite.material = null


func _ensure_mountain_rock_underlay_sprite() -> Sprite2D:
	if _mountain_rock_underlay_sprite != null and is_instance_valid(_mountain_rock_underlay_sprite):
		return _mountain_rock_underlay_sprite
	_mountain_rock_underlay_sprite = Sprite2D.new()
	_mountain_rock_underlay_sprite.name = "MountainRockUnderlay"
	_mountain_rock_underlay_sprite.centered = false
	_mountain_rock_underlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mountain_rock_underlay_sprite.z_as_relative = false
	_mountain_rock_underlay_sprite.z_index = MOUNTAIN_ROCK_UNDERLAY_Z_INDEX
	add_child(_mountain_rock_underlay_sprite)
	return _mountain_rock_underlay_sprite


func _ensure_mountain_rock_underlay_material() -> ShaderMaterial:
	if _mountain_rock_underlay_material != null:
		return _mountain_rock_underlay_material
	_mountain_rock_underlay_material = ShaderMaterial.new()
	_mountain_rock_underlay_material.shader = MOUNTAIN_FOOTHILL_OVERLAY_SHADER
	return _mountain_rock_underlay_material


func _ensure_mountain_rock_underlay_canvas_texture() -> ImageTexture:
	if _mountain_rock_underlay_canvas_texture != null:
		return _mountain_rock_underlay_canvas_texture
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	_mountain_rock_underlay_canvas_texture = ImageTexture.create_from_image(image)
	return _mountain_rock_underlay_canvas_texture


func _capture_mountain_foothill_mask_if_needed(
		mask_image: Image,
		mask_origin_world: Vector2,
		mask_step_px: float,
) -> void:
	if not MOUNTAIN_FOOTHILL_OVERLAY_ENABLED \
			or mask_image == null \
			or mask_image.is_empty() \
			or mask_step_px <= 0.0:
		return
	var width: int = mask_image.get_width()
	var height: int = mask_image.get_height()
	if width <= 0 or height <= 0:
		return
	var needs_capture: bool = _mountain_foothill_mask_texture == null \
			or _mountain_foothill_mask_width != width \
			or _mountain_foothill_mask_height != height \
			or not _mountain_foothill_mask_origin_world.is_equal_approx(mask_origin_world) \
			or not is_equal_approx(_mountain_foothill_mask_step_px, mask_step_px)
	if not needs_capture:
		return
	var reuses_texture: bool = _mountain_foothill_mask_texture != null \
			and _mountain_foothill_mask_texture.get_width() == width \
			and _mountain_foothill_mask_texture.get_height() == height
	var texture_started: int = WorldPerfProbe.begin()
	_mountain_foothill_mask_texture = _update_or_create_l8_texture(
		_mountain_foothill_mask_texture,
		mask_image,
	)
	WorldPerfProbe.end(
		"ChunkView.mountain_upload.foothill_texture_update" \
				if reuses_texture \
				else "ChunkView.mountain_upload.foothill_texture_create",
		texture_started,
	)
	_mountain_foothill_mask_width = width
	_mountain_foothill_mask_height = height
	_mountain_foothill_mask_origin_world = mask_origin_world
	_mountain_foothill_mask_step_px = mask_step_px


func _clear_mountain_foothill_mask(preserve_gpu_allocation: bool = false) -> void:
	if not preserve_gpu_allocation:
		_mountain_foothill_mask_texture = null
	_mountain_foothill_mask_width = 0
	_mountain_foothill_mask_height = 0
	_mountain_foothill_mask_origin_world = Vector2.ZERO
	_mountain_foothill_mask_step_px = 0.0


func _sync_mountain_foothill_overlay_visual(
		foothill_texture: Texture2D,
		foothill_normal_texture: Texture2D,
) -> void:
	if not MOUNTAIN_FOOTHILL_OVERLAY_ENABLED \
			or foothill_texture == null \
			or _mountain_foothill_mask_texture == null \
			or _mountain_foothill_mask_width <= 0 \
			or _mountain_foothill_mask_height <= 0 \
			or _mountain_foothill_mask_step_px <= 0.0:
		_clear_mountain_foothill_overlay()
		return
	var sprite: Sprite2D = _ensure_mountain_foothill_overlay_sprite()
	var material: ShaderMaterial = _ensure_mountain_foothill_overlay_material()
	material.set_shader_parameter("foothill_texture", foothill_texture)
	material.set_shader_parameter("mask_texture", _mountain_foothill_mask_texture)
	material.set_shader_parameter(
		"foothill_texture_size",
		Vector2(
			maxf(1.0, float(foothill_texture.get_width())),
			maxf(1.0, float(foothill_texture.get_height())),
		),
	)
	material.set_shader_parameter(
		"mask_texture_size",
		Vector2(
			maxf(1.0, float(_mountain_foothill_mask_width)),
			maxf(1.0, float(_mountain_foothill_mask_height)),
		),
	)
	if foothill_normal_texture != null:
		material.set_shader_parameter("foothill_normal_texture", foothill_normal_texture)
		material.set_shader_parameter("normal_mix", 1.0)
	else:
		material.set_shader_parameter("normal_mix", 0.0)
	material.set_shader_parameter("world_origin_px", _mountain_foothill_mask_origin_world)
	material.set_shader_parameter("sample_step_px", _mountain_foothill_mask_step_px)
	material.set_shader_parameter("texture_scale", MOUNTAIN_FOOTHILL_TEXTURE_SCALE)
	material.set_shader_parameter("outer_width_px", MOUNTAIN_FOOTHILL_OUTER_WIDTH_PX)
	material.set_shader_parameter("outer_width_variation_px", MOUNTAIN_FOOTHILL_OUTER_WIDTH_VARIATION_PX)
	material.set_shader_parameter("inner_width_px", MOUNTAIN_FOOTHILL_INNER_WIDTH_PX)
	material.set_shader_parameter("foothill_alpha", MOUNTAIN_FOOTHILL_ALPHA)
	material.set_shader_parameter("footprint_fill_strength", 0.0)
	material.set_shader_parameter("footprint_fill_alpha", 0.78)
	material.set_shader_parameter("max_alpha", 0.78)
	var scree_texture: Texture2D = _resolve_mountain_material_set().get_texture_slot(&"scree_albedo")
	assert(scree_texture != null, "Mountain material set requires extra texture scree_albedo.")
	material.set_shader_parameter("scree_texture", scree_texture)
	material.set_shader_parameter(
		"scree_texture_size",
		Vector2(
			maxf(1.0, float(scree_texture.get_width())),
			maxf(1.0, float(scree_texture.get_height())),
		),
	)
	material.set_shader_parameter("scree_strength", MOUNTAIN_SCREE_STRENGTH)
	material.set_shader_parameter("scree_texture_scale", MOUNTAIN_SCREE_TEXTURE_SCALE)
	material.set_shader_parameter("scree_patch_scale_px", MOUNTAIN_SCREE_PATCH_SCALE_PX)
	material.set_shader_parameter("scree_coverage", MOUNTAIN_SCREE_COVERAGE)
	_set_mask_shader_chunk_clip(
		material,
		_mountain_foothill_mask_origin_world,
		_mountain_foothill_mask_width,
		_mountain_foothill_mask_height,
		_mountain_foothill_mask_step_px,
		0.0,
	)
	_apply_sun_lighting_to_foothill_material(material)
	sprite.material = material
	sprite.position = _mountain_foothill_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2(
		float(_mountain_foothill_mask_width) * _mountain_foothill_mask_step_px,
		float(_mountain_foothill_mask_height) * _mountain_foothill_mask_step_px,
	)
	sprite.texture = _ensure_mountain_foothill_overlay_canvas_texture()
	sprite.visible = true


func _clear_mountain_foothill_overlay() -> void:
	if _mountain_foothill_overlay_sprite != null and is_instance_valid(_mountain_foothill_overlay_sprite):
		_mountain_foothill_overlay_sprite.texture = null
		_mountain_foothill_overlay_sprite.visible = false
		_mountain_foothill_overlay_sprite.scale = Vector2.ONE
		_mountain_foothill_overlay_sprite.material = null


func _ensure_mountain_foothill_overlay_sprite() -> Sprite2D:
	if _mountain_foothill_overlay_sprite != null and is_instance_valid(_mountain_foothill_overlay_sprite):
		return _mountain_foothill_overlay_sprite
	_mountain_foothill_overlay_sprite = Sprite2D.new()
	_mountain_foothill_overlay_sprite.name = "MountainFoothillOverlay"
	_mountain_foothill_overlay_sprite.centered = false
	_mountain_foothill_overlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mountain_foothill_overlay_sprite.z_as_relative = false
	_mountain_foothill_overlay_sprite.z_index = 4
	add_child(_mountain_foothill_overlay_sprite)
	return _mountain_foothill_overlay_sprite


func _ensure_mountain_foothill_overlay_material() -> ShaderMaterial:
	if _mountain_foothill_overlay_material != null:
		return _mountain_foothill_overlay_material
	_mountain_foothill_overlay_material = ShaderMaterial.new()
	_mountain_foothill_overlay_material.shader = MOUNTAIN_FOOTHILL_OVERLAY_SHADER
	return _mountain_foothill_overlay_material


func _ensure_mountain_foothill_overlay_canvas_texture() -> ImageTexture:
	if _mountain_foothill_overlay_canvas_texture != null:
		return _mountain_foothill_overlay_canvas_texture
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	_mountain_foothill_overlay_canvas_texture = ImageTexture.create_from_image(image)
	return _mountain_foothill_overlay_canvas_texture


func _ensure_terrain_edge_mask_sprite() -> Sprite2D:
	if _terrain_edge_mask_sprite != null and is_instance_valid(_terrain_edge_mask_sprite):
		return _terrain_edge_mask_sprite
	_terrain_edge_mask_sprite = Sprite2D.new()
	_terrain_edge_mask_sprite.name = "TerrainEdgeMaskUnderlay"
	_terrain_edge_mask_sprite.centered = false
	_terrain_edge_mask_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_terrain_edge_mask_sprite.z_as_relative = false
	_terrain_edge_mask_sprite.z_index = 2
	add_child(_terrain_edge_mask_sprite)
	return _terrain_edge_mask_sprite


func _ensure_terrain_edge_mask_material() -> ShaderMaterial:
	if _terrain_edge_mask_material != null:
		return _terrain_edge_mask_material
	_terrain_edge_mask_material = ShaderMaterial.new()
	_terrain_edge_mask_material.shader = MOUNTAIN_TOP_MASK_UNDERLAY_SHADER
	return _terrain_edge_mask_material


func _sync_rock_patch_overlay_visual(
		rock_patch_texture: Texture2D,
		rock_patch_normal_texture: Texture2D,
) -> void:
	if not ROCK_PATCH_OVERLAY_ENABLED \
			or rock_patch_texture == null \
			or _terrain_edge_mask_texture == null \
			or _terrain_edge_mask_width <= 0 \
			or _terrain_edge_mask_height <= 0 \
			or _terrain_edge_mask_step_px <= 0.0:
		_clear_rock_patch_overlay()
		return
	var sprite: Sprite2D = _ensure_rock_patch_overlay_sprite()
	var material: ShaderMaterial = _ensure_rock_patch_overlay_material()
	material.set_shader_parameter("rock_texture", rock_patch_texture)
	material.set_shader_parameter("mask_texture", _terrain_edge_mask_texture)
	material.set_shader_parameter(
		"rock_texture_size",
		Vector2(
			maxf(1.0, float(rock_patch_texture.get_width())),
			maxf(1.0, float(rock_patch_texture.get_height())),
		),
	)
	material.set_shader_parameter(
		"mask_texture_size",
		Vector2(
			maxf(1.0, float(_terrain_edge_mask_width)),
			maxf(1.0, float(_terrain_edge_mask_height)),
		),
	)
	if rock_patch_normal_texture != null:
		material.set_shader_parameter("rock_normal_texture", rock_patch_normal_texture)
		material.set_shader_parameter("normal_mix", 1.0)
	else:
		material.set_shader_parameter("normal_mix", 0.0)
	material.set_shader_parameter("world_origin_px", _terrain_edge_mask_origin_world)
	material.set_shader_parameter("sample_step_px", _terrain_edge_mask_step_px)
	material.set_shader_parameter("rock_texture_scale", ROCK_PATCH_TEXTURE_SCALE)
	material.set_shader_parameter("patch_cell_px", ROCK_PATCH_CELL_PX)
	material.set_shader_parameter("patch_density", ROCK_PATCH_DENSITY)
	material.set_shader_parameter("patch_alpha", ROCK_PATCH_ALPHA)
	material.set_shader_parameter("edge_clearance_px", ROCK_PATCH_EDGE_CLEARANCE_PX)
	_set_mask_shader_chunk_clip(
		material,
		_terrain_edge_mask_origin_world,
		_terrain_edge_mask_width,
		_terrain_edge_mask_height,
		_terrain_edge_mask_step_px,
		0.0,
	)
	_apply_sun_lighting_to_rock_patch_material(material)
	sprite.material = material
	sprite.position = _terrain_edge_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2(
		float(_terrain_edge_mask_width) * _terrain_edge_mask_step_px,
		float(_terrain_edge_mask_height) * _terrain_edge_mask_step_px,
	)
	sprite.texture = _ensure_rock_patch_overlay_canvas_texture()
	sprite.visible = true


func _clear_rock_patch_overlay() -> void:
	if _rock_patch_overlay_sprite != null and is_instance_valid(_rock_patch_overlay_sprite):
		_rock_patch_overlay_sprite.texture = null
		_rock_patch_overlay_sprite.visible = false
		_rock_patch_overlay_sprite.scale = Vector2.ONE
		_rock_patch_overlay_sprite.material = null


func _ensure_rock_patch_overlay_sprite() -> Sprite2D:
	if _rock_patch_overlay_sprite != null and is_instance_valid(_rock_patch_overlay_sprite):
		return _rock_patch_overlay_sprite
	_rock_patch_overlay_sprite = Sprite2D.new()
	_rock_patch_overlay_sprite.name = "RockPatchOverlay"
	_rock_patch_overlay_sprite.centered = false
	_rock_patch_overlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rock_patch_overlay_sprite.z_as_relative = false
	_rock_patch_overlay_sprite.z_index = 2
	add_child(_rock_patch_overlay_sprite)
	return _rock_patch_overlay_sprite


func _ensure_rock_patch_overlay_material() -> ShaderMaterial:
	if _rock_patch_overlay_material != null:
		return _rock_patch_overlay_material
	_rock_patch_overlay_material = ShaderMaterial.new()
	_rock_patch_overlay_material.shader = ROCK_PATCH_OVERLAY_SHADER
	return _rock_patch_overlay_material


func _ensure_rock_patch_overlay_canvas_texture() -> ImageTexture:
	if _rock_patch_overlay_canvas_texture != null:
		return _rock_patch_overlay_canvas_texture
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	_rock_patch_overlay_canvas_texture = ImageTexture.create_from_image(image)
	return _rock_patch_overlay_canvas_texture


func _sync_grass_blob_overlay_visual(
		grass_overlay_texture: Texture2D,
		grass_overlay_texture_2: Texture2D,
		grass_overlay_texture_3: Texture2D,
		grass_overlay_normal_texture: Texture2D,
) -> void:
	if not GRASS_BLOB_OVERLAY_ENABLED \
			or grass_overlay_texture == null \
			or grass_overlay_texture_2 == null \
			or grass_overlay_texture_3 == null \
			or _terrain_edge_mask_texture == null \
			or _terrain_edge_mask_width <= 0 \
			or _terrain_edge_mask_height <= 0 \
			or _terrain_edge_mask_step_px <= 0.0:
		_clear_grass_blob_overlay()
		return
	var sprite: Sprite2D = _ensure_grass_blob_overlay_sprite()
	var material: ShaderMaterial = _ensure_grass_blob_overlay_material()
	material.set_shader_parameter("grass_texture", grass_overlay_texture)
	material.set_shader_parameter("grass_texture_2", grass_overlay_texture_2)
	material.set_shader_parameter("grass_texture_3", grass_overlay_texture_3)
	material.set_shader_parameter("mask_texture", _terrain_edge_mask_texture)
	if grass_overlay_normal_texture != null:
		material.set_shader_parameter("grass_normal_texture", grass_overlay_normal_texture)
		material.set_shader_parameter("normal_mix", GRASS_BLOB_NORMAL_MIX)
	else:
		material.set_shader_parameter("normal_mix", 0.0)
	material.set_shader_parameter(
		"grass_texture_size",
		Vector2(
			maxf(1.0, float(grass_overlay_texture.get_width())),
			maxf(1.0, float(grass_overlay_texture.get_height())),
		),
	)
	material.set_shader_parameter(
		"grass_texture_size_2",
		Vector2(
			maxf(1.0, float(grass_overlay_texture_2.get_width())),
			maxf(1.0, float(grass_overlay_texture_2.get_height())),
		),
	)
	material.set_shader_parameter(
		"grass_texture_size_3",
		Vector2(
			maxf(1.0, float(grass_overlay_texture_3.get_width())),
			maxf(1.0, float(grass_overlay_texture_3.get_height())),
		),
	)
	material.set_shader_parameter(
		"mask_texture_size",
		Vector2(
			maxf(1.0, float(_terrain_edge_mask_width)),
			maxf(1.0, float(_terrain_edge_mask_height)),
		),
	)
	material.set_shader_parameter("world_origin_px", _terrain_edge_mask_origin_world)
	material.set_shader_parameter("sample_step_px", _terrain_edge_mask_step_px)
	material.set_shader_parameter("grass_texture_scale", GRASS_BLOB_TEXTURE_SCALE)
	material.set_shader_parameter("patch_cell_px", GRASS_BLOB_PATCH_CELL_PX)
	material.set_shader_parameter("patch_density", GRASS_BLOB_PATCH_DENSITY)
	material.set_shader_parameter("patch_alpha", GRASS_BLOB_PATCH_ALPHA)
	material.set_shader_parameter("edge_clearance_px", GRASS_BLOB_EDGE_CLEARANCE_PX)
	material.set_shader_parameter("edge_feather_low", GRASS_BLOB_EDGE_FEATHER_LOW)
	material.set_shader_parameter("edge_feather_high", GRASS_BLOB_EDGE_FEATHER_HIGH)
	material.set_shader_parameter("max_alpha", GRASS_BLOB_MAX_ALPHA)
	material.set_shader_parameter("normal_strength", GRASS_BLOB_NORMAL_STRENGTH)
	_apply_sun_lighting_to_grass_blob_material(material)
	_set_mask_shader_chunk_clip(
		material,
		_terrain_edge_mask_origin_world,
		_terrain_edge_mask_width,
		_terrain_edge_mask_height,
		_terrain_edge_mask_step_px,
		0.0,
	)
	sprite.material = material
	sprite.position = _terrain_edge_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2(
		float(_terrain_edge_mask_width) * _terrain_edge_mask_step_px,
		float(_terrain_edge_mask_height) * _terrain_edge_mask_step_px,
	)
	sprite.texture = _ensure_grass_blob_overlay_canvas_texture()
	sprite.visible = true


func _clear_grass_blob_overlay() -> void:
	if _grass_blob_overlay_sprite != null and is_instance_valid(_grass_blob_overlay_sprite):
		_grass_blob_overlay_sprite.texture = null
		_grass_blob_overlay_sprite.visible = false
		_grass_blob_overlay_sprite.scale = Vector2.ONE
		_grass_blob_overlay_sprite.material = null


func _ensure_grass_blob_overlay_sprite() -> Sprite2D:
	if _grass_blob_overlay_sprite != null and is_instance_valid(_grass_blob_overlay_sprite):
		return _grass_blob_overlay_sprite
	_grass_blob_overlay_sprite = Sprite2D.new()
	_grass_blob_overlay_sprite.name = "GrassBlobOverlay"
	_grass_blob_overlay_sprite.centered = false
	_grass_blob_overlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_grass_blob_overlay_sprite.z_as_relative = false
	_grass_blob_overlay_sprite.z_index = 3
	add_child(_grass_blob_overlay_sprite)
	return _grass_blob_overlay_sprite


func _ensure_grass_blob_overlay_material() -> ShaderMaterial:
	if _grass_blob_overlay_material != null:
		return _grass_blob_overlay_material
	_grass_blob_overlay_material = ShaderMaterial.new()
	_grass_blob_overlay_material.shader = GRASS_BLOB_OVERLAY_SHADER
	return _grass_blob_overlay_material


func _ensure_grass_blob_overlay_canvas_texture() -> ImageTexture:
	if _grass_blob_overlay_canvas_texture != null:
		return _grass_blob_overlay_canvas_texture
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	_grass_blob_overlay_canvas_texture = ImageTexture.create_from_image(image)
	return _grass_blob_overlay_canvas_texture


func _sync_object_packet_visual(packet: Dictionary) -> void:
	if _living_flora_atlas == null \
			and _spiky_flora_atlases.is_empty() \
			and _tree_atlas == null \
			and _layered_tree_asset_dirs.is_empty() \
			and _layered_small_rock_asset_dirs.is_empty():
		_clear_object_packet_visual()
		return
	var layer: WorldObjectPacketLayer = _ensure_object_packet_layer()
	_sync_object_packet_layer_sources(layer)
	_object_packet_layer.set_world_origin_y(position.y)
	layer.configure_packet(packet)
	_apply_sun_lighting_to_object_packet_layer()


func _ensure_object_packet_layer() -> WorldObjectPacketLayer:
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		return _object_packet_layer
	_object_packet_layer = WorldObjectPacketLayer.new()
	_object_packet_layer_uses_external_parent = false
	_object_packet_layer.set_streaming_world_parented(false)
	_object_packet_layer.name = "WorldObjectPacketLayer"
	_object_packet_layer.z_as_relative = false
	_object_packet_layer.z_index = 0
	_object_packet_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_object_packet_layer)
	# Source setters commonly run while the packet layer is still lazy. Native
	# presentation may create it much later, after worker buffers are staged, so
	# creation must replay every stored source before validating those buffers.
	# Otherwise enabling living/spiky flora would turn a valid worker result into
	# a terminal missing-atlas failure and leave the whole chunk reveal-gated.
	_sync_object_packet_layer_sources(_object_packet_layer)
	_object_packet_layer.set_world_origin_y(position.y)
	_object_packet_layer.set_debug_collisions_visible(_debug_object_collisions_visible)
	return _object_packet_layer


func _sync_object_packet_layer_sources(layer: WorldObjectPacketLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.set_living_flora_atlas(_living_flora_atlas)
	layer.set_spiky_flora_atlases(_spiky_flora_atlases)
	layer.set_tree_atlas(_tree_atlas)
	layer.set_layered_tree_asset_dirs(_layered_tree_asset_dirs)
	layer.set_layered_small_rock_asset_dirs(_layered_small_rock_asset_dirs)


func _clear_object_packet_visual() -> void:
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.visible = false


func _ensure_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, { }) as Dictionary
	if terrain_layers.has(roof_terrain_id):
		return terrain_layers[roof_terrain_id] as TileMapLayer
	var layer := TileMapLayer.new()
	layer.name = "RoofLayer_%d_%s" % [mountain_id, _get_roof_terrain_name(roof_terrain_id)]
	layer.tile_set = WorldTileSetFactory.get_roof_tile_set(roof_terrain_id)
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_index = WorldRuntimeConstants.Z_DEBUG_OVERLAY
	layer.material = _build_roof_material(mountain_id, roof_terrain_id)
	add_child(layer)
	terrain_layers[roof_terrain_id] = layer
	roof_layers_by_mountain[mountain_id] = terrain_layers
	return layer


func _is_dry_lake_bed_index(index: int, terrain_id: int) -> bool:
	if terrain_id != WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
			and terrain_id != WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP:
		return false
	if index < 0 or index >= _pending_lake_flags.size():
		return true
	return (int(_pending_lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) == 0


func _should_render_as_organic_ground_underlay(index: int, terrain_id: int) -> bool:
	if terrain_id == WorldRuntimeConstants.TERRAIN_PLAINS_DUG:
		return true
	return _is_dry_lake_bed_index(index, terrain_id)


func _apply_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if WorldTileSetFactory.uses_overlay_layer(terrain_id):
		if not _bulk_apply_layers_pristine:
			_clear_cell(_base_layer, local_coord)
		_overlay_layer.set_cell(
			local_coord,
			WorldTileSetFactory.get_source_id(terrain_id),
			WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index),
		)
		return
	if not _bulk_apply_layers_pristine:
		_clear_cell(_overlay_layer, local_coord)
	_base_layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_source_id(terrain_id),
		WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index),
	)


func _apply_roof_cell(local_coord: Vector2i, index: int) -> void:
	if not _mountain_tile_visuals_enabled:
		_clear_roof_surface_cell(local_coord)
		return
	if index < 0 or index >= _pending_mountain_ids.size() or index >= _pending_mountain_flags.size():
		return
	var mountain_id: int = int(_pending_mountain_ids[index])
	var mountain_flags: int = int(_pending_mountain_flags[index])
	if not _is_roof_bearing_mountain_tile(mountain_id, mountain_flags):
		return
	var terrain_atlas_index: int = 0
	if index < _pending_mountain_atlas_indices.size():
		terrain_atlas_index = int(_pending_mountain_atlas_indices[index])
	var roof_terrain_id: int = _resolve_roof_terrain_id_from_flags(mountain_flags)
	_clear_other_roof_surface_cell(mountain_id, roof_terrain_id, local_coord)
	var layer: TileMapLayer = _ensure_roof_layer(mountain_id, roof_terrain_id)
	layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_roof_source_id(roof_terrain_id),
		WorldTileSetFactory.get_atlas_coords(roof_terrain_id, terrain_atlas_index),
	)


func _apply_water_patch_around(local_coord: Vector2i) -> void:
	for offset: Vector2i in [
		Vector2i.ZERO,
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 0),
	]:
		var patch_coord: Vector2i = local_coord + offset
		if not WorldRuntimeConstants.is_local_coord_valid(patch_coord):
			continue
		_apply_water_cell(patch_coord, WorldRuntimeConstants.local_to_index(patch_coord))


func _apply_water_cell(local_coord: Vector2i, index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if _bulk_apply_layers_pristine:
		return
	_clear_cell(_water_layer, local_coord)


func _sync_water_fill_visual() -> void:
	var water_texture: Texture2D = _resolve_water_fill_texture()
	if water_texture == null:
		# The fill is the under-water backdrop only; over dry chunks it would
		# paint the whole chunk as a dark sea above the ground material.
		if _water_fill_sprite != null and is_instance_valid(_water_fill_sprite):
			_water_fill_sprite.texture = null
			_water_fill_sprite.visible = false
		return
	_ensure_water_layer()
	var sprite: Sprite2D = _ensure_water_fill_sprite()
	var material: ShaderMaterial = _ensure_water_fill_material()
	material.set_shader_parameter("water_albedo", water_texture)
	sprite.material = material
	sprite.texture = _ensure_water_fill_texture()
	var chunk_size_px: float = float(
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX,
	)
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2.ONE * chunk_size_px
	sprite.visible = true


func _resolve_water_fill_texture() -> Texture2D:
	if _pending_terrain_ids.is_empty() or _pending_lake_flags.is_empty():
		return null
	var has_water: bool = false
	for index: int in range(mini(_pending_terrain_ids.size(), _pending_lake_flags.size())):
		if not _should_render_water_at(index):
			continue
		has_water = true
		break
	if not has_water:
		return null
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set(
		WorldTileSetFactory.WATER_SURFACE_DARK_MATERIAL_ID,
	)
	if material_set == null:
		return null
	return material_set.get_texture_slot(&"top_albedo")


func _clear_cell(layer: TileMapLayer, local_coord: Vector2i) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.set_cell(local_coord, -1, Vector2i(-1, -1))


func _clear_loaded_mountain_visuals() -> void:
	_ensure_layers()
	for index: int in range(mini(_pending_terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(_pending_terrain_ids[index])
		if not _should_suppress_mountain_visual(index, terrain_id):
			continue
		_clear_mountain_visual_cell(WorldRuntimeConstants.index_to_local(index))


func _clear_mountain_visual_cell(local_coord: Vector2i) -> void:
	# Mountain renders via the native mask/silhouette. The fallback base cell is
	# the same organic ground material used outside the mountain; the mountain
	# shape is purely the overlay above it.
	_apply_ground_underlay_cell(local_coord)
	_clear_cell(_overlay_layer, local_coord)
	_clear_cell(_water_layer, local_coord)
	_clear_roof_surface_cell(local_coord)


func _apply_ground_underlay_cell(local_coord: Vector2i) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	_base_layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
		WorldTileSetFactory.get_atlas_coords(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, 0),
	)


func _clear_roof_surface_cell(local_coord: Vector2i) -> void:
	for terrain_layers_variant: Variant in roof_layers_by_mountain.values():
		var terrain_layers: Dictionary = terrain_layers_variant as Dictionary
		for layer_variant: Variant in terrain_layers.values():
			_clear_cell(layer_variant as TileMapLayer, local_coord)


func _should_suppress_mountain_visual(index: int, terrain_id: int) -> bool:
	if _mountain_tile_visuals_enabled:
		return false
	if not _is_mountain_visual_terrain(terrain_id):
		return false
	return true


func _is_mountain_visual_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
			or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED


func _is_pending_full_mountain_surface() -> bool:
	if _pending_terrain_ids.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return false
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		if not _is_mountain_visual_terrain(int(_pending_terrain_ids[index])):
			return false
		if index < _pending_walkable_flags.size() and int(_pending_walkable_flags[index]) != 0:
			return false
		if int(_pending_terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
				and index < _pending_mountain_flags.size():
			var flags: int = int(_pending_mountain_flags[index])
			if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
				return false
	return true


func _refresh_debug_solid_mask() -> void:
	_debug_solid_mask = _build_debug_solid_mask()
	_sync_debug_layer_data()


func _build_debug_solid_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		if _is_debug_solid_mountain_index(index):
			mask[index] = 1
	return mask


func _is_debug_solid_mountain_index(index: int) -> bool:
	if index < 0 or index >= _pending_terrain_ids.size():
		return false
	var terrain_id: int = int(_pending_terrain_ids[index])
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return false
	if index < _pending_walkable_flags.size() and int(_pending_walkable_flags[index]) != 0:
		return false
	if _pending_mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT \
			and int(_pending_mountain_ids[index]) <= 0:
		return false
	if _pending_mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
		var flags: int = int(_pending_mountain_flags[index])
		return (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0
	return true


func _sync_debug_layer() -> void:
	if not _debug_grid_visible and not _debug_solid_mask_visible and not _debug_contour_visible:
		if _debug_layer != null and is_instance_valid(_debug_layer):
			_debug_layer.set_debug_visibility(false, false, false)
		return
	var layer: ChunkDebugVisualLayer = _ensure_debug_layer()
	layer.set_debug_visibility(_debug_grid_visible, _debug_solid_mask_visible, _debug_contour_visible)
	_sync_debug_layer_data()


func _sync_debug_layer_data() -> void:
	if _debug_layer == null or not is_instance_valid(_debug_layer):
		return
	_debug_layer.set_debug_data(_debug_solid_mask, _debug_contour_vertices, _debug_contour_indices)


func _set_mask_shader_chunk_clip(
		material: ShaderMaterial,
		mask_origin_world: Vector2,
		mask_width: int,
		mask_height: int,
		mask_step_px: float,
		overlap_px: float,
) -> void:
	var mask_world_size := Vector2(
		maxf(1.0, float(mask_width) * mask_step_px),
		maxf(1.0, float(mask_height) * mask_step_px),
	)
	var mask_chunk_origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	var mask_chunk_size_world: float = float(
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX,
	)
	var chunk_min: Vector2 = mask_chunk_origin - Vector2.ONE * overlap_px
	var chunk_max: Vector2 = mask_chunk_origin + Vector2.ONE * (mask_chunk_size_world + overlap_px)
	var shadow_chunk_min: Vector2 = mask_chunk_origin
	var shadow_chunk_max: Vector2 = mask_chunk_origin + Vector2.ONE * mask_chunk_size_world
	var shadow_draw_chunk_min: Vector2 = mask_chunk_origin - Vector2.ONE * MASK_SHADOW_CHUNK_OVERLAP_PX
	var shadow_draw_chunk_max: Vector2 = mask_chunk_origin + Vector2.ONE * (
		mask_chunk_size_world + MASK_SHADOW_CHUNK_OVERLAP_PX
	)
	material.set_shader_parameter(
		"chunk_uv_min",
		Vector2(
			(chunk_min.x - mask_origin_world.x) / mask_world_size.x,
			(chunk_min.y - mask_origin_world.y) / mask_world_size.y,
		),
	)
	material.set_shader_parameter(
		"chunk_uv_max",
		Vector2(
			(chunk_max.x - mask_origin_world.x) / mask_world_size.x,
			(chunk_max.y - mask_origin_world.y) / mask_world_size.y,
		),
	)
	material.set_shader_parameter(
		"shadow_uv_min",
		Vector2(
			(shadow_chunk_min.x - mask_origin_world.x) / mask_world_size.x,
			(shadow_chunk_min.y - mask_origin_world.y) / mask_world_size.y,
		),
	)
	material.set_shader_parameter(
		"shadow_uv_max",
		Vector2(
			(shadow_chunk_max.x - mask_origin_world.x) / mask_world_size.x,
			(shadow_chunk_max.y - mask_origin_world.y) / mask_world_size.y,
		),
	)
	material.set_shader_parameter(
		"shadow_draw_uv_min",
		Vector2(
			(shadow_draw_chunk_min.x - mask_origin_world.x) / mask_world_size.x,
			(shadow_draw_chunk_min.y - mask_origin_world.y) / mask_world_size.y,
		),
	)
	material.set_shader_parameter(
		"shadow_draw_uv_max",
		Vector2(
			(shadow_draw_chunk_max.x - mask_origin_world.x) / mask_world_size.x,
			(shadow_draw_chunk_max.y - mask_origin_world.y) / mask_world_size.y,
		),
	)
	material.set_shader_parameter(
		"shadow_blend_texels",
		maxf(1.0, MASK_SHADOW_CHUNK_OVERLAP_PX / maxf(mask_step_px, 0.001)),
	)


func _count_debug_solid_tiles() -> int:
	var count: int = 0
	for value: int in _debug_solid_mask:
		if value != 0:
			count += 1
	return count


func _compact_mountain_page_result(result: Dictionary) -> Dictionary:
	var compact: Dictionary = { }
	for key_variant: Variant in result.keys():
		var key: Variant = key_variant
		if key in [
			"image",
			"normal_image",
			"ground_image",
			"ground_normal_image",
			"mountain_image",
			"mountain_normal_image",
			"light_occluder_polygon",
			"hit_mask",
			"top_mask",
		]:
			continue
		compact[key] = result[key]
	return compact


func _should_render_water_at(index: int) -> bool:
	if index < 0 \
			or index >= _pending_lake_flags.size() \
			or index >= _pending_terrain_ids.size():
		return false
	if (int(_pending_lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) == 0:
		return false
	return _is_lake_bed_terrain(int(_pending_terrain_ids[index]))


func _resolve_water_atlas_index(_local_coord: Vector2i) -> int:
	return 0


func _is_lake_bed_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
			or terrain_id == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP


func _build_roof_material(mountain_id: int, terrain_id: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = MOUNTAIN_COVER_SHADER
	material.set_shader_parameter("cover_mask", _ensure_roof_mask_texture(mountain_id))
	material.set_shader_parameter(
		"mask_tile_count",
		Vector2(float(WorldRuntimeConstants.CHUNK_SIZE), float(WorldRuntimeConstants.CHUNK_SIZE)),
	)
	material.set_shader_parameter("tile_size_px", float(WorldRuntimeConstants.TILE_SIZE_PX))
	material.set_shader_parameter("chunk_origin_px", WorldRuntimeConstants.chunk_origin_px(chunk_coord))
	_apply_roof_presentation_params(material, terrain_id)
	return material


func _apply_roof_presentation_params(material: ShaderMaterial, terrain_id: int) -> void:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var shape_set: TerrainShapeSet = TerrainPresentationRegistry.get_shape_set_for_terrain(
		roof_terrain_id,
	)
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(
		roof_terrain_id,
	)
	material.set_shader_parameter("shape_normal_atlas", shape_set.get_texture_slot(&"shape_normal_atlas"))
	material.set_shader_parameter("top_albedo_tex", material_set.get_texture_slot(&"top_albedo"))
	material.set_shader_parameter("face_albedo_tex", material_set.get_texture_slot(&"face_albedo"))
	material.set_shader_parameter("top_modulation", material_set.get_texture_slot(&"top_modulation"))
	material.set_shader_parameter("face_modulation", material_set.get_texture_slot(&"face_modulation"))
	material.set_shader_parameter("top_normal_tex", material_set.get_texture_slot(&"top_normal"))
	material.set_shader_parameter("face_normal_tex", material_set.get_texture_slot(&"face_normal"))
	for parameter_name_variant: Variant in material_set.sampling_params.keys():
		material.set_shader_parameter(
			parameter_name_variant,
			material_set.sampling_params[parameter_name_variant],
		)


func _get_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, { }) as Dictionary
	return terrain_layers.get(roof_terrain_id, null) as TileMapLayer


func _clear_other_roof_surface_cell(mountain_id: int, terrain_id: int, local_coord: Vector2i) -> void:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, { }) as Dictionary
	for layer_terrain_id_variant: Variant in terrain_layers.keys():
		var layer_terrain_id: int = int(layer_terrain_id_variant)
		if layer_terrain_id == roof_terrain_id:
			continue
		_clear_cell(terrain_layers.get(layer_terrain_id, null) as TileMapLayer, local_coord)


func _resolve_roof_terrain_id_from_flags(mountain_flags: int) -> int:
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_WALL) != 0:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT) != 0:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL


func _resolve_roof_terrain_id(terrain_id: int) -> int:
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL


func _get_roof_terrain_name(terrain_id: int) -> String:
	if _resolve_roof_terrain_id(terrain_id) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return "foot"
	return "wall"


func _ensure_roof_mask_image(mountain_id: int) -> Image:
	if _roof_mask_images_by_mountain.has(mountain_id):
		return _roof_mask_images_by_mountain[mountain_id] as Image
	var image: Image = Image.create(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_L8,
	)
	image.fill(Color(1.0, 0.0, 0.0, 1.0))
	_roof_mask_images_by_mountain[mountain_id] = image
	return image


func _ensure_roof_mask_texture(mountain_id: int) -> ImageTexture:
	if _roof_mask_textures_by_mountain.has(mountain_id):
		return _roof_mask_textures_by_mountain[mountain_id] as ImageTexture
	var texture: ImageTexture = ImageTexture.create_from_image(_ensure_roof_mask_image(mountain_id))
	_roof_mask_textures_by_mountain[mountain_id] = texture
	return texture


func get_cover_render_debug(local_coord: Vector2i, mountain_id: int = 0, expected_open_bit: int = -1) -> Dictionary:
	var result := {
		"ready": false,
		"local_coord": local_coord,
		"expected_open_bit": expected_open_bit,
		"pending_mountain_id": 0,
		"pending_flags": 0,
		"has_roof_layer": false,
		"layer_has_cover_material": false,
		"roof_terrain_id": WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
		"roof_cell_source_id": -1,
		"roof_cell_atlas_coords": Vector2i(-1, -1),
		"roof_tile_material_present": false,
		"mask_value": -1.0,
	}
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return result
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	var pending_mountain_id: int = 0
	var pending_flags: int = 0
	if index >= 0 and index < _pending_mountain_ids.size():
		pending_mountain_id = int(_pending_mountain_ids[index])
	if index >= 0 and index < _pending_mountain_flags.size():
		pending_flags = int(_pending_mountain_flags[index])
	result["pending_mountain_id"] = pending_mountain_id
	result["pending_flags"] = pending_flags
	var resolved_mountain_id: int = mountain_id if mountain_id > 0 else pending_mountain_id
	if resolved_mountain_id <= 0:
		result["ready"] = true
		return result
	var roof_terrain_id: int = _resolve_roof_terrain_id_from_flags(pending_flags)
	result["roof_terrain_id"] = roof_terrain_id
	var layer: TileMapLayer = _get_roof_layer(resolved_mountain_id, roof_terrain_id)
	result["has_roof_layer"] = layer != null and is_instance_valid(layer)
	if layer != null and is_instance_valid(layer):
		result["layer_has_cover_material"] = layer.material != null
		var roof_cell_source_id: int = layer.get_cell_source_id(local_coord)
		result["roof_cell_source_id"] = roof_cell_source_id
		var roof_cell_atlas_coords: Vector2i = layer.get_cell_atlas_coords(local_coord)
		result["roof_cell_atlas_coords"] = roof_cell_atlas_coords
		if roof_cell_source_id >= 0 and layer.tile_set != null:
			var source: TileSetAtlasSource = layer.tile_set.get_source(roof_cell_source_id) as TileSetAtlasSource
			if source != null:
				var tile_data: TileData = source.get_tile_data(roof_cell_atlas_coords, 0)
				result["roof_tile_material_present"] = tile_data != null and tile_data.material != null
	var image: Image = _roof_mask_images_by_mountain.get(resolved_mountain_id, null) as Image
	if image != null:
		result["mask_value"] = image.get_pixel(local_coord.x, local_coord.y).r
	result["ready"] = true
	return result


func _normalize_layered_tree_asset_dirs(asset_dirs: Array) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = { }
	for value: Variant in asset_dirs:
		var asset_dir: String = str(value).strip_edges()
		if asset_dir.is_empty() or seen.has(asset_dir):
			continue
		seen[asset_dir] = true
		result.append(asset_dir)
	return result


func _is_roof_bearing_mountain_tile(mountain_id: int, mountain_flags: int) -> bool:
	return mountain_id > 0 \
			and (mountain_flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0
