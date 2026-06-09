class_name ChunkView
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const TerrainPresentationRegistry = preload("res://core/systems/world/terrain_presentation_registry.gd")
const ChunkDebugVisualLayer = preload("res://core/systems/world/chunk_debug_visual_layer.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")
const MOUNTAIN_COVER_SHADER = preload("res://assets/shaders/mountain_cover_overlay.gdshader")
const MOUNTAIN_TOP_MASK_UNDERLAY_SHADER = preload("res://assets/shaders/mountain_top_mask_underlay.gdshader")
const MOUNTAIN_FOOTHILL_OVERLAY_SHADER = preload("res://assets/shaders/mountain_foothill_overlay.gdshader")
const WATER_SURFACE_SHADER = preload("res://assets/shaders/water_surface_material.gdshader")
const GRASS_BLOB_OVERLAY_SHADER = preload("res://assets/shaders/grass_blob_overlay.gdshader")
const ROCK_PATCH_OVERLAY_SHADER = preload("res://assets/shaders/rock_patch_overlay.gdshader")

# Visual south facade height for the mask underlay shader ("wall with roof").
# Collision uses the same native mask plus a narrow lip for antialiased overhang.
const MOUNTAIN_FACADE_HEIGHT_PX: float = 72.0
const MOUNTAIN_FACADE_COLLISION_DEPTH_PX: float = 12.0
const MOUNTAIN_FACE_TEXTURE_SCALE: float = 0.46
const MOUNTAIN_NATIVE_MASK_SOLID_THRESHOLD: int = 107
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
const GRASS_BLOB_OVERLAY_ENABLED: bool = true
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
const ROCK_PATCH_OVERLAY_ENABLED: bool = true
const ROCK_PATCH_TEXTURE_SCALE: float = 0.66
const ROCK_PATCH_CELL_PX: float = 1280.0
const ROCK_PATCH_DENSITY: float = 0.54
const ROCK_PATCH_ALPHA: float = 0.48
const ROCK_PATCH_EDGE_CLEARANCE_PX: float = 28.0
const MASK_UNDERLAY_CHUNK_OVERLAP_PX: float = 3.0
const MASK_SHADOW_CHUNK_OVERLAP_PX: float = 48.0

var chunk_coord: Vector2i = Vector2i.ZERO

var _base_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var _water_layer: TileMapLayer = null
var _water_fill_sprite: Sprite2D = null
var _water_fill_texture: ImageTexture = null
var _water_fill_material: ShaderMaterial = null
var _debug_layer: ChunkDebugVisualLayer = null
var roof_layers_by_mountain: Dictionary = {}
var _roof_mask_images_by_mountain: Dictionary = {}
var _roof_mask_textures_by_mountain: Dictionary = {}
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
var _rock_scatter_atlases: Array[Texture2D] = []
var _living_flora_atlas: Texture2D = null
var _spiky_flora_atlases: Array[Texture2D] = []
var _object_packet_layer: WorldObjectPacketLayer = null
var _object_depth_reference_enabled: bool = false
var _object_depth_reference_world_y: float = 0.0
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
	_ensure_layers()

func begin_apply(packet: Dictionary) -> void:
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
	_skip_full_mountain_surface_apply = not _mountain_tile_visuals_enabled and _is_pending_full_mountain_surface()
	_apply_index = 0
	visible = false
	_ensure_layers()
	_sync_water_fill_visual()
	_sync_object_packet_visual(packet)
	_refresh_debug_solid_mask()

func apply_next_batch(batch_size: int) -> bool:
	if _pending_terrain_ids.is_empty():
		return false
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
		if _should_suppress_terrain_ground_visual(index, terrain_id):
			_clear_terrain_base_visual_cell(local_coord)
		else:
			_apply_cell(local_coord, terrain_id, terrain_atlas_index)
		_apply_water_cell(local_coord, index)
		_apply_roof_cell(local_coord, index)
	_apply_index = end_index
	if _apply_index >= _pending_terrain_ids.size():
		return false
	return true

func apply_runtime_cell(
	local_coord: Vector2i,
	terrain_id: int,
	terrain_atlas_index: int,
	walkable: bool = true,
	mountain_id: int = 0,
	mountain_flags: int = 0
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
		_refresh_debug_solid_mask()
		return
	_sync_water_fill_visual()
	if _should_suppress_terrain_ground_visual(index, terrain_id):
		_clear_terrain_base_visual_cell(local_coord)
	else:
		_apply_cell(local_coord, terrain_id, terrain_atlas_index)
	_apply_water_patch_around(local_coord)
	_refresh_debug_solid_mask()

func set_mountain_tile_visuals_enabled(enabled: bool) -> void:
	if _mountain_tile_visuals_enabled == enabled:
		return
	_mountain_tile_visuals_enabled = enabled
	if not _mountain_tile_visuals_enabled:
		_clear_loaded_mountain_visuals()

func set_debug_overlays(grid_visible: bool, solid_mask_visible: bool, contour_visible: bool) -> void:
	_debug_grid_visible = grid_visible
	_debug_solid_mask_visible = solid_mask_visible
	_debug_contour_visible = contour_visible
	_sync_debug_layer()

func apply_sun_lighting(
	light_angle_deg: float,
	shadow_length_px: float,
	shadow_opacity: float,
	shadow_softness_px: float
) -> void:
	_sun_light_angle_deg = light_angle_deg
	_sun_shadow_length_px = shadow_length_px
	_sun_shadow_opacity = shadow_opacity
	_sun_shadow_softness_px = shadow_softness_px
	_apply_sun_lighting_to_mask_material(_mountain_top_mask_material, 1.0)
	_apply_sun_lighting_to_foothill_material(_mountain_foothill_overlay_material)
	_apply_sun_lighting_to_rock_patch_material(_rock_patch_overlay_material)
	_apply_sun_lighting_to_grass_blob_material(_grass_blob_overlay_material)
	_apply_sun_lighting_to_object_packet_layer()
	_apply_sun_lighting_to_mask_material(
		_terrain_edge_mask_material,
		WorldVisualLightingProfile.TERRAIN_EDGE_SHADOW_OPACITY_SCALE
	)

func set_plains_rock_scatter_sources(atlases: Array[Texture2D]) -> void:
	_rock_scatter_atlases = atlases.duplicate()
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_rock_atlases(_rock_scatter_atlases)

func set_living_flora_source(atlas: Texture2D) -> void:
	_living_flora_atlas = atlas
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_living_flora_atlas(_living_flora_atlas)

func set_spiky_flora_source(atlas: Texture2D) -> void:
	if atlas == null:
		set_spiky_flora_sources([])
	else:
		set_spiky_flora_sources([atlas])

func set_spiky_flora_sources(atlases: Array[Texture2D]) -> void:
	_spiky_flora_atlases = atlases.duplicate()
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.set_spiky_flora_atlases(_spiky_flora_atlases)

func apply_object_depth_sort_reference(reference_world_y: float) -> void:
	_object_depth_reference_enabled = true
	_object_depth_reference_world_y = reference_world_y
	_apply_object_depth_sort_reference_to_layer()

func apply_contour_debug_data(
	solid_mask: PackedByteArray,
	contour_vertices: PackedVector2Array,
	contour_indices: PackedInt32Array
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
		mask
	)
	mask_image.resize(
		WorldRuntimeConstants.CHUNK_SIZE * 8,
		WorldRuntimeConstants.CHUNK_SIZE * 8,
		Image.INTERPOLATE_CUBIC
	)
	_apply_mountain_mask_image(
		mask_image,
		top_texture,
		face_texture,
		top_texture_scale,
		float(WorldRuntimeConstants.TILE_SIZE_PX) / 8.0,
		WorldRuntimeConstants.chunk_origin_px(chunk_coord)
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
	top_texture_scale: float = 0.70
) -> void:
	if top_texture == null:
		clear_mountain_render_page()
		return
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	if solid_halo.size() != halo_side * halo_side:
		push_error("ChunkView received invalid mountain halo mask: expected %d byte(s), got %d." % [
			halo_side * halo_side,
			solid_halo.size(),
		])
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
		mask_bytes
	)
	mask_image.resize(
		halo_side * 8,
		halo_side * 8,
		Image.INTERPOLATE_CUBIC
	)
	_apply_mountain_mask_image(
		mask_image,
		top_texture,
		face_texture,
		top_texture_scale,
		float(WorldRuntimeConstants.TILE_SIZE_PX) / 8.0,
		WorldRuntimeConstants.chunk_origin_px(chunk_coord) - Vector2.ONE * float(WorldRuntimeConstants.TILE_SIZE_PX)
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
	top_texture_scale: float = 0.70
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
	top_texture_scale: float = 0.70
) -> bool:
	var mask_bytes: PackedByteArray = mask_result.get("mask", PackedByteArray()) as PackedByteArray
	var mask_width: int = int(mask_result.get("width", 0))
	var mask_height: int = int(mask_result.get("height", 0))
	var mask_step_px: float = float(mask_result.get("step_px", 0.0))
	if mask_width <= 0 \
			or mask_height <= 0 \
			or mask_step_px <= 0.0 \
			or mask_bytes.size() != mask_width * mask_height:
		return false
	_mountain_top_mask_image = null
	_mountain_top_mask_bytes = mask_bytes.duplicate()
	_mountain_top_mask_width = mask_width
	_mountain_top_mask_height = mask_height
	_mountain_top_mask_origin_world = mask_origin_world
	_mountain_top_mask_step_px = mask_step_px
	_mountain_top_mask_texture_scale = top_texture_scale
	_mountain_top_mask_visual_dirty = true
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
		"native_mask_visual_ready": _mountain_top_mask_texture != null,
		"mask_size": Vector2i(mask_width, mask_height),
		"solid_sample_count": int(mask_result.get("solid_sample_count", 0)),
		"pixels_per_tile": int(mask_result.get("pixels_per_tile", 0)),
	}
	return true

func apply_pending_mountain_native_mask_visual(
	top_texture: Texture2D,
	face_texture: Texture2D = null,
	top_normal_texture: Texture2D = null,
	face_normal_texture: Texture2D = null,
	foothill_texture: Texture2D = null,
	foothill_normal_texture: Texture2D = null
) -> bool:
	if not _mountain_top_mask_visual_dirty:
		return false
	if top_texture == null \
			or _mountain_top_mask_width <= 0 \
			or _mountain_top_mask_height <= 0 \
			or _mountain_top_mask_step_px <= 0.0 \
			or _mountain_top_mask_bytes.size() != _mountain_top_mask_width * _mountain_top_mask_height:
		return false
	var mask_image: Image = Image.create_from_data(
		_mountain_top_mask_width,
		_mountain_top_mask_height,
		false,
		Image.FORMAT_L8,
		_mountain_top_mask_bytes
	)
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
		foothill_normal_texture
	)
	_mountain_top_mask_image = mask_image
	_mountain_top_mask_visual_dirty = false
	_mountain_page_debug["native_mask_visual_pending"] = false
	_mountain_page_debug["native_mask_visual_ready"] = true
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
	rock_patch_normal_texture: Texture2D = null
) -> bool:
	if not _terrain_edge_mask_visual_dirty:
		return false
	if top_texture == null \
			or _terrain_edge_mask_width <= 0 \
			or _terrain_edge_mask_height <= 0 \
			or _terrain_edge_mask_step_px <= 0.0 \
			or _terrain_edge_mask_bytes.size() != _terrain_edge_mask_width * _terrain_edge_mask_height:
		return false
	var mask_image: Image = Image.create_from_data(
		_terrain_edge_mask_width,
		_terrain_edge_mask_height,
		false,
		Image.FORMAT_L8,
		_terrain_edge_mask_bytes
	)
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
		rock_patch_normal_texture
	)
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
	face_normal_texture: Texture2D = null
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
		top_mask
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
		face_normal_texture
	)

func _apply_mountain_mask_image(
	mask_image: Image,
	top_texture: Texture2D,
	face_texture: Texture2D,
	top_texture_scale: float,
	mask_step_px: float,
	mask_origin_world: Vector2,
	top_normal_texture: Texture2D = null,
	face_normal_texture: Texture2D = null
) -> void:
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
		face_normal_texture
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
	foothill_normal_texture: Texture2D = null
) -> void:
	_capture_mountain_foothill_mask_if_needed(mask_image, mask_origin_world, mask_step_px)
	if _mountain_top_mask_texture != null \
			and _mountain_top_mask_texture.get_width() == _mountain_top_mask_width \
			and _mountain_top_mask_texture.get_height() == _mountain_top_mask_height:
		_mountain_top_mask_texture.update(mask_image)
	else:
		_mountain_top_mask_texture = ImageTexture.create_from_image(mask_image)
	var sprite: Sprite2D = _ensure_mountain_top_mask_sprite()
	var material: ShaderMaterial = _ensure_mountain_top_mask_material()
	_mountain_top_mask_origin_world = mask_origin_world
	_mountain_top_mask_step_px = mask_step_px
	_mountain_top_mask_texture_scale = top_texture_scale
	material.set_shader_parameter("top_texture", top_texture)
	material.set_shader_parameter("top_texture_size", Vector2(
		maxf(1.0, float(top_texture.get_width())),
		maxf(1.0, float(top_texture.get_height()))
	))
	if face_texture == null:
		face_texture = top_texture
	if face_texture != null:
		material.set_shader_parameter("face_texture", face_texture)
		material.set_shader_parameter("face_texture_size", Vector2(
			maxf(1.0, float(face_texture.get_width())),
			maxf(1.0, float(face_texture.get_height()))
		))
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
	material.set_shader_parameter("top_texture_scale", top_texture_scale)
	material.set_shader_parameter("face_texture_scale", MOUNTAIN_FACE_TEXTURE_SCALE)
	material.set_shader_parameter("facade_height_px", MOUNTAIN_FACADE_HEIGHT_PX)
	material.set_shader_parameter("normal_strength", 0.48)
	material.set_shader_parameter("light_ambient", 0.58)
	material.set_shader_parameter("light_diffuse", 0.44)
	_set_mask_shader_chunk_clip(
		material,
		mask_origin_world,
		mask_image.get_width(),
		mask_image.get_height(),
		mask_step_px,
		MASK_UNDERLAY_CHUNK_OVERLAP_PX
	)
	_apply_sun_lighting_to_mask_material(material, 1.0)
	sprite.material = material
	sprite.position = mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2.ONE * mask_step_px
	sprite.texture = _mountain_top_mask_texture
	sprite.visible = true
	_sync_mountain_foothill_overlay_visual(foothill_texture, foothill_normal_texture)

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
	rock_patch_normal_texture: Texture2D
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
	material.set_shader_parameter("top_texture_size", Vector2(
		maxf(1.0, float(top_texture.get_width())),
		maxf(1.0, float(top_texture.get_height()))
	))
	material.set_shader_parameter("face_texture", face_texture)
	material.set_shader_parameter("face_texture_size", Vector2(
		maxf(1.0, float(face_texture.get_width())),
		maxf(1.0, float(face_texture.get_height()))
	))
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
	material.set_shader_parameter("normal_strength", 0.48)
	material.set_shader_parameter("light_ambient", 0.58)
	material.set_shader_parameter("light_diffuse", 0.44)
	material.set_shader_parameter("top_surface_alpha", TERRAIN_EDGE_TOP_ALPHA)
	material.set_shader_parameter("wall_surface_alpha", 0.94)
	material.set_shader_parameter("top_dust_tint", Vector3(0.82, 0.87, 0.90))
	material.set_shader_parameter("rim_highlight_color", Vector3(0.42, 0.48, 0.50))
	material.set_shader_parameter("cut_highlight_color", Vector3(0.34, 0.39, 0.41))
	material.set_shader_parameter("cleft_color", Vector3(0.045, 0.052, 0.055))
	material.set_shader_parameter("crack_color", Vector3(0.018, 0.023, 0.026))
	material.set_shader_parameter("base_debris_color", Vector3(0.075, 0.082, 0.084))
	material.set_shader_parameter("eave_shadow_color", Vector3(0.040, 0.048, 0.050))
	material.set_shader_parameter("inner_rim_color", Vector3(0.32, 0.38, 0.40))
	_set_mask_shader_chunk_clip(
		material,
		_terrain_edge_mask_origin_world,
		mask_image.get_width(),
		mask_image.get_height(),
		_terrain_edge_mask_step_px,
		MASK_UNDERLAY_CHUNK_OVERLAP_PX
	)
	_apply_sun_lighting_to_mask_material(
		material,
		WorldVisualLightingProfile.TERRAIN_EDGE_SHADOW_OPACITY_SCALE
	)
	sprite.material = material
	sprite.position = _terrain_edge_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2.ONE * _terrain_edge_mask_step_px
	sprite.texture = _terrain_edge_mask_texture
	sprite.visible = true
	_sync_rock_patch_overlay_visual(
		rock_patch_texture,
		rock_patch_normal_texture
	)
	_sync_grass_blob_overlay_visual(
		grass_overlay_texture,
		grass_overlay_texture_2,
		grass_overlay_texture_3,
		grass_overlay_normal_texture
	)

func _clear_mountain_top_mask(preserve_foothill: bool = false) -> void:
	if _mountain_top_mask_sprite != null and is_instance_valid(_mountain_top_mask_sprite):
		_mountain_top_mask_sprite.texture = null
		_mountain_top_mask_sprite.visible = false
		_mountain_top_mask_sprite.scale = Vector2.ONE
		_mountain_top_mask_sprite.material = null
	if not preserve_foothill:
		_clear_mountain_foothill_mask()
		_clear_mountain_foothill_overlay()
	_mountain_top_mask_texture = null
	_mountain_top_mask_image = null
	_mountain_top_mask_bytes = PackedByteArray()
	_mountain_top_mask_width = 0
	_mountain_top_mask_height = 0
	_mountain_top_mask_origin_world = Vector2.ZERO
	_mountain_top_mask_step_px = 0.0
	_mountain_top_mask_texture_scale = 0.70
	_mountain_top_mask_visual_dirty = false

func clear_terrain_edge_mask() -> void:
	if _terrain_edge_mask_sprite != null and is_instance_valid(_terrain_edge_mask_sprite):
		_terrain_edge_mask_sprite.texture = null
		_terrain_edge_mask_sprite.visible = false
		_terrain_edge_mask_sprite.scale = Vector2.ONE
		_terrain_edge_mask_sprite.material = null
	_terrain_edge_mask_texture = null
	_terrain_edge_mask_image = null
	_terrain_edge_mask_bytes = PackedByteArray()
	_terrain_edge_mask_width = 0
	_terrain_edge_mask_height = 0
	_terrain_edge_mask_origin_world = Vector2.ZERO
	_terrain_edge_mask_step_px = 0.0
	_terrain_edge_mask_visual_dirty = false
	_clear_rock_patch_overlay()
	_clear_grass_blob_overlay()

func _apply_sun_lighting_to_mask_material(material: ShaderMaterial, shadow_opacity_scale: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("light_angle_deg", _sun_light_angle_deg)
	material.set_shader_parameter("projected_shadow_angle_deg", _sun_light_angle_deg + 180.0)
	material.set_shader_parameter("projected_shadow_length_px", _sun_shadow_length_px)
	material.set_shader_parameter("projected_shadow_opacity", _sun_shadow_opacity * shadow_opacity_scale)
	material.set_shader_parameter("projected_shadow_softness_px", _sun_shadow_softness_px)

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
		_sun_shadow_softness_px
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
		mask
	)
	var chunk_origin_world: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_apply_mountain_mask_image(
		_mountain_top_mask_image,
		top_texture,
		face_texture,
		top_texture_scale,
		float(WorldRuntimeConstants.TILE_SIZE_PX),
		chunk_origin_world
	)

func clear_mountain_render_page(preserve_foothill: bool = false) -> void:
	if _mountain_page_sprite != null and is_instance_valid(_mountain_page_sprite):
		_mountain_page_sprite.texture = null
		_mountain_page_sprite.visible = false
		_mountain_page_sprite.scale = Vector2.ONE
	_mountain_interior_fill_active = false
	_mountain_page_texture = null
	_mountain_page_image = null
	_mountain_page_normal_texture = null
	_mountain_page_lit_texture = null
	_clear_mountain_top_mask(preserve_foothill)
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
		float(world_tile.y * WorldRuntimeConstants.TILE_SIZE_PX)
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
		float(world_tile.y * WorldRuntimeConstants.TILE_SIZE_PX)
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
		and not _mountain_page_hit_mask.is_empty()) \
		or (_mountain_top_mask_width > 0 \
		and _mountain_top_mask_height > 0 \
		and not _mountain_top_mask_bytes.is_empty() \
		and _mountain_top_mask_step_px > 0.0)

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
	return _mountain_page_debug.duplicate(true)

func get_mountain_native_mask_debug_state() -> Dictionary:
	var debug := _mountain_page_debug.duplicate(true)
	var active: bool = _mountain_top_mask_width > 0 \
		and _mountain_top_mask_height > 0 \
		and _mountain_top_mask_step_px > 0.0 \
		and not _mountain_top_mask_bytes.is_empty()
	debug["native_mask_active"] = active
	debug["mask_width"] = _mountain_top_mask_width
	debug["mask_height"] = _mountain_top_mask_height
	debug["mask_step_px"] = _mountain_top_mask_step_px
	debug["mask_byte_count"] = _mountain_top_mask_bytes.size()
	debug["has_visual_texture"] = _mountain_top_mask_texture != null
	debug["native_mask_visual_pending"] = _mountain_top_mask_visual_dirty
	debug["native_mask_visual_ready"] = _mountain_top_mask_texture != null and not _mountain_top_mask_visual_dirty
	debug["foothill_mask_active"] = _mountain_foothill_mask_texture != null \
		and _mountain_foothill_mask_width > 0 \
		and _mountain_foothill_mask_height > 0 \
		and _mountain_foothill_mask_step_px > 0.0
	debug["foothill_overlay_visible"] = _mountain_foothill_overlay_sprite != null \
		and is_instance_valid(_mountain_foothill_overlay_sprite) \
		and _mountain_foothill_overlay_sprite.visible
	debug["chunk_coord"] = chunk_coord
	return debug

func get_terrain_edge_mask_debug_state() -> Dictionary:
	var active: bool = _terrain_edge_mask_width > 0 \
		and _terrain_edge_mask_height > 0 \
		and _terrain_edge_mask_step_px > 0.0 \
		and not _terrain_edge_mask_bytes.is_empty()
	return {
		"terrain_edge_mask_active": active,
		"mask_width": _terrain_edge_mask_width,
		"mask_height": _terrain_edge_mask_height,
		"mask_step_px": _terrain_edge_mask_step_px,
		"mask_byte_count": _terrain_edge_mask_bytes.size(),
		"has_visual_texture": _terrain_edge_mask_texture != null,
		"visual_pending": _terrain_edge_mask_visual_dirty,
		"visual_ready": _terrain_edge_mask_texture != null and not _terrain_edge_mask_visual_dirty,
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
	var updated_mountains: Dictionary = {}
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
	return _water_fill_material

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
	_mountain_page_sprite.z_index = 8
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
	mark_visual_dirty: bool = true
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
				feather_px
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
	_mountain_top_mask_sprite.z_index = 7
	add_child(_mountain_top_mask_sprite)
	return _mountain_top_mask_sprite

func _ensure_mountain_top_mask_material() -> ShaderMaterial:
	if _mountain_top_mask_material != null:
		return _mountain_top_mask_material
	_mountain_top_mask_material = ShaderMaterial.new()
	_mountain_top_mask_material.shader = MOUNTAIN_TOP_MASK_UNDERLAY_SHADER
	return _mountain_top_mask_material

func _capture_mountain_foothill_mask_if_needed(
	mask_image: Image,
	mask_origin_world: Vector2,
	mask_step_px: float
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
	_mountain_foothill_mask_texture = ImageTexture.create_from_image(mask_image)
	_mountain_foothill_mask_width = width
	_mountain_foothill_mask_height = height
	_mountain_foothill_mask_origin_world = mask_origin_world
	_mountain_foothill_mask_step_px = mask_step_px

func _clear_mountain_foothill_mask() -> void:
	_mountain_foothill_mask_texture = null
	_mountain_foothill_mask_width = 0
	_mountain_foothill_mask_height = 0
	_mountain_foothill_mask_origin_world = Vector2.ZERO
	_mountain_foothill_mask_step_px = 0.0

func _sync_mountain_foothill_overlay_visual(
	foothill_texture: Texture2D,
	foothill_normal_texture: Texture2D
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
	material.set_shader_parameter("foothill_texture_size", Vector2(
		maxf(1.0, float(foothill_texture.get_width())),
		maxf(1.0, float(foothill_texture.get_height()))
	))
	material.set_shader_parameter("mask_texture_size", Vector2(
		maxf(1.0, float(_mountain_foothill_mask_width)),
		maxf(1.0, float(_mountain_foothill_mask_height))
	))
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
	_set_mask_shader_chunk_clip(
		material,
		_mountain_foothill_mask_origin_world,
		_mountain_foothill_mask_width,
		_mountain_foothill_mask_height,
		_mountain_foothill_mask_step_px,
		0.0
	)
	_apply_sun_lighting_to_foothill_material(material)
	sprite.material = material
	sprite.position = _mountain_foothill_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2(
		float(_mountain_foothill_mask_width) * _mountain_foothill_mask_step_px,
		float(_mountain_foothill_mask_height) * _mountain_foothill_mask_step_px
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
	rock_patch_normal_texture: Texture2D
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
	material.set_shader_parameter("rock_texture_size", Vector2(
		maxf(1.0, float(rock_patch_texture.get_width())),
		maxf(1.0, float(rock_patch_texture.get_height()))
	))
	material.set_shader_parameter("mask_texture_size", Vector2(
		maxf(1.0, float(_terrain_edge_mask_width)),
		maxf(1.0, float(_terrain_edge_mask_height))
	))
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
		0.0
	)
	_apply_sun_lighting_to_rock_patch_material(material)
	sprite.material = material
	sprite.position = _terrain_edge_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2(
		float(_terrain_edge_mask_width) * _terrain_edge_mask_step_px,
		float(_terrain_edge_mask_height) * _terrain_edge_mask_step_px
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
	grass_overlay_normal_texture: Texture2D
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
	material.set_shader_parameter("grass_texture_size", Vector2(
		maxf(1.0, float(grass_overlay_texture.get_width())),
		maxf(1.0, float(grass_overlay_texture.get_height()))
	))
	material.set_shader_parameter("grass_texture_size_2", Vector2(
		maxf(1.0, float(grass_overlay_texture_2.get_width())),
		maxf(1.0, float(grass_overlay_texture_2.get_height()))
	))
	material.set_shader_parameter("grass_texture_size_3", Vector2(
		maxf(1.0, float(grass_overlay_texture_3.get_width())),
		maxf(1.0, float(grass_overlay_texture_3.get_height()))
	))
	material.set_shader_parameter("mask_texture_size", Vector2(
		maxf(1.0, float(_terrain_edge_mask_width)),
		maxf(1.0, float(_terrain_edge_mask_height))
	))
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
		0.0
	)
	sprite.material = material
	sprite.position = _terrain_edge_mask_origin_world - WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	sprite.scale = Vector2(
		float(_terrain_edge_mask_width) * _terrain_edge_mask_step_px,
		float(_terrain_edge_mask_height) * _terrain_edge_mask_step_px
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
	if _rock_scatter_atlases.is_empty() \
			and _living_flora_atlas == null \
			and _spiky_flora_atlases.is_empty():
		_clear_object_packet_visual()
		return
	var layer: WorldObjectPacketLayer = _ensure_object_packet_layer()
	layer.set_rock_atlases(_rock_scatter_atlases)
	layer.set_living_flora_atlas(_living_flora_atlas)
	layer.set_spiky_flora_atlases(_spiky_flora_atlases)
	_apply_object_depth_sort_reference_to_layer()
	layer.configure_packet(packet)
	_apply_sun_lighting_to_object_packet_layer()

func _ensure_object_packet_layer() -> WorldObjectPacketLayer:
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		return _object_packet_layer
	_object_packet_layer = WorldObjectPacketLayer.new()
	_object_packet_layer.name = "WorldObjectPacketLayer"
	_object_packet_layer.z_as_relative = false
	_object_packet_layer.z_index = 0
	_object_packet_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_object_packet_layer)
	_apply_object_depth_sort_reference_to_layer()
	return _object_packet_layer

func _clear_object_packet_visual() -> void:
	if _object_packet_layer != null and is_instance_valid(_object_packet_layer):
		_object_packet_layer.visible = false

func _apply_object_depth_sort_reference_to_layer() -> void:
	if not _object_depth_reference_enabled \
			or _object_packet_layer == null \
			or not is_instance_valid(_object_packet_layer):
		return
	_object_packet_layer.set_depth_sort_reference(
		WorldRuntimeConstants.chunk_origin_px(chunk_coord).y,
		_object_depth_reference_world_y
	)

func _ensure_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {}) as Dictionary
	if terrain_layers.has(roof_terrain_id):
		return terrain_layers[roof_terrain_id] as TileMapLayer
	var layer := TileMapLayer.new()
	layer.name = "RoofLayer_%d_%s" % [mountain_id, _get_roof_terrain_name(roof_terrain_id)]
	layer.tile_set = WorldTileSetFactory.get_roof_tile_set(roof_terrain_id)
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_index = 10
	layer.material = _build_roof_material(mountain_id, roof_terrain_id)
	add_child(layer)
	terrain_layers[roof_terrain_id] = layer
	roof_layers_by_mountain[mountain_id] = terrain_layers
	return layer

func _apply_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if WorldTileSetFactory.uses_overlay_layer(terrain_id):
		_clear_cell(_base_layer, local_coord)
		_overlay_layer.set_cell(
			local_coord,
			WorldTileSetFactory.get_source_id(terrain_id),
			WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index)
		)
		return
	_clear_cell(_overlay_layer, local_coord)
	_base_layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_source_id(terrain_id),
		WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index)
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
		WorldTileSetFactory.get_atlas_coords(roof_terrain_id, terrain_atlas_index)
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
	_clear_cell(_water_layer, local_coord)

func _sync_water_fill_visual() -> void:
	var water_texture: Texture2D = _resolve_water_fill_texture()
	if water_texture == null:
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
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX
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
		WorldTileSetFactory.WATER_SURFACE_DARK_MATERIAL_ID
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
	_apply_ground_underlay_cell(local_coord)
	_clear_cell(_overlay_layer, local_coord)
	_clear_cell(_water_layer, local_coord)
	_clear_roof_surface_cell(local_coord)

func _apply_ground_underlay_cell(local_coord: Vector2i) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	if _has_terrain_ground_mask_data():
		_clear_terrain_base_visual_cell(local_coord)
		return
	_base_layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_source_id(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND),
		WorldTileSetFactory.get_atlas_coords(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND, 0)
	)

func _clear_terrain_base_visual_cell(local_coord: Vector2i) -> void:
	_clear_cell(_base_layer, local_coord)
	_clear_cell(_overlay_layer, local_coord)

func _should_suppress_terrain_ground_visual(index: int, terrain_id: int) -> bool:
	if not _has_terrain_ground_mask_data():
		return false
	if _is_mountain_visual_terrain(terrain_id):
		return false
	return index >= 0 and index < WorldRuntimeConstants.CHUNK_CELL_COUNT

func _has_terrain_ground_mask_data() -> bool:
	return _terrain_edge_mask_width > 0 \
		and _terrain_edge_mask_height > 0 \
		and _terrain_edge_mask_step_px > 0.0 \
		and not _terrain_edge_mask_bytes.is_empty()

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
	overlap_px: float
) -> void:
	var mask_world_size := Vector2(
		maxf(1.0, float(mask_width) * mask_step_px),
		maxf(1.0, float(mask_height) * mask_step_px)
	)
	var mask_chunk_origin: Vector2 = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	var mask_chunk_size_world: float = float(
		WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX
	)
	var chunk_min: Vector2 = mask_chunk_origin - Vector2.ONE * overlap_px
	var chunk_max: Vector2 = mask_chunk_origin + Vector2.ONE * (mask_chunk_size_world + overlap_px)
	var shadow_chunk_min: Vector2 = mask_chunk_origin
	var shadow_chunk_max: Vector2 = mask_chunk_origin + Vector2.ONE * mask_chunk_size_world
	var shadow_draw_chunk_min: Vector2 = mask_chunk_origin - Vector2.ONE * MASK_SHADOW_CHUNK_OVERLAP_PX
	var shadow_draw_chunk_max: Vector2 = mask_chunk_origin + Vector2.ONE * (
		mask_chunk_size_world + MASK_SHADOW_CHUNK_OVERLAP_PX
	)
	material.set_shader_parameter("chunk_uv_min", Vector2(
		(chunk_min.x - mask_origin_world.x) / mask_world_size.x,
		(chunk_min.y - mask_origin_world.y) / mask_world_size.y
	))
	material.set_shader_parameter("chunk_uv_max", Vector2(
		(chunk_max.x - mask_origin_world.x) / mask_world_size.x,
		(chunk_max.y - mask_origin_world.y) / mask_world_size.y
	))
	material.set_shader_parameter("shadow_uv_min", Vector2(
		(shadow_chunk_min.x - mask_origin_world.x) / mask_world_size.x,
		(shadow_chunk_min.y - mask_origin_world.y) / mask_world_size.y
	))
	material.set_shader_parameter("shadow_uv_max", Vector2(
		(shadow_chunk_max.x - mask_origin_world.x) / mask_world_size.x,
		(shadow_chunk_max.y - mask_origin_world.y) / mask_world_size.y
	))
	material.set_shader_parameter("shadow_draw_uv_min", Vector2(
		(shadow_draw_chunk_min.x - mask_origin_world.x) / mask_world_size.x,
		(shadow_draw_chunk_min.y - mask_origin_world.y) / mask_world_size.y
	))
	material.set_shader_parameter("shadow_draw_uv_max", Vector2(
		(shadow_draw_chunk_max.x - mask_origin_world.x) / mask_world_size.x,
		(shadow_draw_chunk_max.y - mask_origin_world.y) / mask_world_size.y
	))
	material.set_shader_parameter(
		"shadow_blend_texels",
		maxf(1.0, MASK_SHADOW_CHUNK_OVERLAP_PX / maxf(mask_step_px, 0.001))
	)

func _count_debug_solid_tiles() -> int:
	var count: int = 0
	for value: int in _debug_solid_mask:
		if value != 0:
			count += 1
	return count

func _compact_mountain_page_result(result: Dictionary) -> Dictionary:
	var compact: Dictionary = {}
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
		Vector2(float(WorldRuntimeConstants.CHUNK_SIZE), float(WorldRuntimeConstants.CHUNK_SIZE))
	)
	material.set_shader_parameter("tile_size_px", float(WorldRuntimeConstants.TILE_SIZE_PX))
	material.set_shader_parameter("chunk_origin_px", WorldRuntimeConstants.chunk_origin_px(chunk_coord))
	_apply_roof_presentation_params(material, terrain_id)
	return material

func _apply_roof_presentation_params(material: ShaderMaterial, terrain_id: int) -> void:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var shape_set: TerrainShapeSet = TerrainPresentationRegistry.get_shape_set_for_terrain(
		roof_terrain_id
	)
	var material_set: TerrainMaterialSet = TerrainPresentationRegistry.get_material_set_for_terrain(
		roof_terrain_id
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
			material_set.sampling_params[parameter_name_variant]
		)

func _get_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {}) as Dictionary
	return terrain_layers.get(roof_terrain_id, null) as TileMapLayer

func _clear_other_roof_surface_cell(mountain_id: int, terrain_id: int, local_coord: Vector2i) -> void:
	var roof_terrain_id: int = _resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = roof_layers_by_mountain.get(mountain_id, {}) as Dictionary
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
		Image.FORMAT_L8
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

func _is_roof_bearing_mountain_tile(mountain_id: int, mountain_flags: int) -> bool:
	return mountain_id > 0 \
		and (mountain_flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0
