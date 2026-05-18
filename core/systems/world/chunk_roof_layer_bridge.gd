class_name ChunkRoofLayerBridge
extends RefCounted

const ChunkRoofVisualSupport = preload("res://core/systems/world/chunk_roof_visual_support.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

var layers_by_mountain: Dictionary = { }

var _owner: Node = null
var _chunk_coord: Vector2i = Vector2i.ZERO
var _mask_images_by_mountain: Dictionary = { }
var _mask_textures_by_mountain: Dictionary = { }


func configure(owner: Node, chunk_coord: Vector2i) -> void:
	_owner = owner
	_chunk_coord = chunk_coord


func clear() -> void:
	clear_layers()


func clear_layers() -> void:
	for terrain_layers_variant: Variant in layers_by_mountain.values():
		var terrain_layers: Dictionary = terrain_layers_variant as Dictionary
		for layer_variant: Variant in terrain_layers.values():
			var layer: TileMapLayer = layer_variant as TileMapLayer
			if layer != null and is_instance_valid(layer):
				layer.queue_free()
	layers_by_mountain.clear()
	_mask_images_by_mountain.clear()
	_mask_textures_by_mountain.clear()


func apply_cover_visibility(
		visible_mask: PackedByteArray,
		pending_mountain_ids: PackedInt32Array,
		pending_mountain_flags: PackedByteArray,
) -> void:
	var resolved_mask: PackedByteArray = visible_mask
	if resolved_mask.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		resolved_mask = PackedByteArray()
		resolved_mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var updated_mountains: Dictionary = { }
	for mountain_id_variant: Variant in layers_by_mountain.keys():
		var mountain_id: int = int(mountain_id_variant)
		var image: Image = _ensure_mask_image(mountain_id)
		image.fill(Color(1.0, 0.0, 0.0, 1.0))
	for index: int in range(mini(pending_mountain_ids.size(), pending_mountain_flags.size())):
		var mountain_id: int = int(pending_mountain_ids[index])
		var mountain_flags: int = int(pending_mountain_flags[index])
		if not is_roof_bearing_mountain_tile(mountain_id, mountain_flags):
			continue
		var image: Image = _ensure_mask_image(mountain_id)
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var hide_value: float = 0.0 if resolved_mask[index] != 0 else 1.0
		image.set_pixel(local_coord.x, local_coord.y, Color(hide_value, 0.0, 0.0, 1.0))
		updated_mountains[mountain_id] = true
	for mountain_id_variant: Variant in updated_mountains.keys():
		var mountain_id: int = int(mountain_id_variant)
		var texture: ImageTexture = (
			_mask_textures_by_mountain.get(mountain_id, null) as ImageTexture
		)
		var image: Image = _mask_images_by_mountain.get(mountain_id, null) as Image
		if texture != null and image != null:
			texture.update(image)


func ensure_roof_layer(mountain_id: int, terrain_id: int) -> TileMapLayer:
	var roof_terrain_id: int = resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = layers_by_mountain.get(mountain_id, { }) as Dictionary
	if terrain_layers.has(roof_terrain_id):
		return terrain_layers[roof_terrain_id] as TileMapLayer
	var layer := TileMapLayer.new()
	layer.name = "RoofLayer_%d_%s" % [mountain_id, get_roof_terrain_name(roof_terrain_id)]
	layer.tile_set = WorldTileSetFactory.get_roof_tile_set(roof_terrain_id)
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_index = 10
	layer.material = _build_roof_material(mountain_id, roof_terrain_id)
	if _owner != null and is_instance_valid(_owner):
		_owner.add_child(layer)
	terrain_layers[roof_terrain_id] = layer
	layers_by_mountain[mountain_id] = terrain_layers
	return layer


func clear_other_roof_surface_cell(
		mountain_id: int,
		terrain_id: int,
		local_coord: Vector2i,
) -> void:
	var roof_terrain_id: int = resolve_roof_terrain_id(terrain_id)
	var terrain_layers: Dictionary = layers_by_mountain.get(mountain_id, { }) as Dictionary
	for layer_terrain_id_variant: Variant in terrain_layers.keys():
		var layer_terrain_id: int = int(layer_terrain_id_variant)
		if layer_terrain_id == roof_terrain_id:
			continue
		_clear_cell(terrain_layers.get(layer_terrain_id, null) as TileMapLayer, local_coord)


func get_cover_render_debug(
		local_coord: Vector2i,
		mountain_id: int,
		expected_open_bit: int,
		pending_mountain_ids: PackedInt32Array,
		pending_mountain_flags: PackedByteArray,
) -> Dictionary:
	return ChunkRoofVisualSupport.get_cover_render_debug(
		local_coord,
		mountain_id,
		expected_open_bit,
		pending_mountain_ids,
		pending_mountain_flags,
		layers_by_mountain,
		_mask_images_by_mountain,
	)


func is_roof_bearing_mountain_tile(mountain_id: int, mountain_flags: int) -> bool:
	return mountain_id > 0 \
			and (
				mountain_flags
				& (
					WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
					| WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
				)
			) != 0


func resolve_roof_terrain_id_from_flags(mountain_flags: int) -> int:
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_WALL) != 0:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	if (mountain_flags & WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT) != 0:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL


func resolve_roof_terrain_id(terrain_id: int) -> int:
	if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	return WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL


func get_roof_terrain_name(terrain_id: int) -> String:
	if resolve_roof_terrain_id(terrain_id) == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
		return "foot"
	return "wall"


func _build_roof_material(mountain_id: int, terrain_id: int) -> ShaderMaterial:
	return ChunkRoofVisualSupport.build_roof_material(
		_chunk_coord,
		mountain_id,
		terrain_id,
		_ensure_mask_texture(mountain_id),
	)


func _ensure_mask_image(mountain_id: int) -> Image:
	if _mask_images_by_mountain.has(mountain_id):
		return _mask_images_by_mountain[mountain_id] as Image
	var image: Image = Image.create(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_L8,
	)
	image.fill(Color(1.0, 0.0, 0.0, 1.0))
	_mask_images_by_mountain[mountain_id] = image
	return image


func _ensure_mask_texture(mountain_id: int) -> ImageTexture:
	if _mask_textures_by_mountain.has(mountain_id):
		return _mask_textures_by_mountain[mountain_id] as ImageTexture
	var texture: ImageTexture = ImageTexture.create_from_image(_ensure_mask_image(mountain_id))
	_mask_textures_by_mountain[mountain_id] = texture
	return texture


func _clear_cell(layer: TileMapLayer, local_coord: Vector2i) -> void:
	if layer != null and is_instance_valid(layer):
		layer.set_cell(local_coord, -1, Vector2i(-1, -1))
