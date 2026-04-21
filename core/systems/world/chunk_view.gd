class_name ChunkView
extends Node2D

const MountainRevealRegistry = preload("res://core/systems/world/mountain_reveal_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

var chunk_coord: Vector2i = Vector2i.ZERO

var _base_layer: TileMapLayer = null
var _overlay_layer: TileMapLayer = null
var roof_layers_by_mountain: Dictionary = {}
var _mountain_reveal_registry: MountainRevealRegistry = null
var _entrance_cache: PackedByteArray = PackedByteArray()
var _cover_mask_bytes_by_mountain: Dictionary = {}
var _cover_mask_textures_by_mountain: Dictionary = {}
var _roof_materials_by_mountain: Dictionary = {}
var _roof_source_ids_by_mountain: Dictionary = {}
var _pending_terrain_ids: PackedInt32Array = PackedInt32Array()
var _pending_terrain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _pending_mountain_ids: PackedInt32Array = PackedInt32Array()
var _pending_mountain_flags: PackedByteArray = PackedByteArray()
var _pending_mountain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _apply_index: int = 0

func _ready() -> void:
	_connect_reveal_registry()
	if not EventBus.mountain_revealed.is_connected(_on_mountain_visibility_changed):
		EventBus.mountain_revealed.connect(_on_mountain_visibility_changed)
	if not EventBus.mountain_concealed.is_connected(_on_mountain_visibility_changed):
		EventBus.mountain_concealed.connect(_on_mountain_visibility_changed)

func _exit_tree() -> void:
	if _mountain_reveal_registry != null \
			and is_instance_valid(_mountain_reveal_registry) \
			and _mountain_reveal_registry.alpha_changed.is_connected(_on_alpha_changed):
		_mountain_reveal_registry.alpha_changed.disconnect(_on_alpha_changed)
	if EventBus.mountain_revealed.is_connected(_on_mountain_visibility_changed):
		EventBus.mountain_revealed.disconnect(_on_mountain_visibility_changed)
	if EventBus.mountain_concealed.is_connected(_on_mountain_visibility_changed):
		EventBus.mountain_concealed.disconnect(_on_mountain_visibility_changed)

func configure(new_chunk_coord: Vector2i) -> void:
	chunk_coord = new_chunk_coord
	position = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_ensure_layers()

func begin_apply(packet: Dictionary) -> void:
	_pending_terrain_ids = (packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_terrain_atlas_indices = (packet.get("terrain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_mountain_ids = (packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array).duplicate()
	_pending_mountain_flags = (packet.get("mountain_flags", PackedByteArray()) as PackedByteArray).duplicate()
	_pending_mountain_atlas_indices = (packet.get("mountain_atlas_indices", PackedInt32Array()) as PackedInt32Array).duplicate()
	_apply_index = 0
	visible = false
	_ensure_layers()
	_clear_roof_layers()
	_entrance_cache = PackedByteArray()
	_entrance_cache.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)

func apply_next_batch(batch_size: int) -> bool:
	if _pending_terrain_ids.is_empty():
		return false
	var end_index: int = mini(_apply_index + batch_size, _pending_terrain_ids.size())
	for index: int in range(_apply_index, end_index):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var terrain_id: int = int(_pending_terrain_ids[index])
		var terrain_atlas_index: int = 0
		if index < _pending_terrain_atlas_indices.size():
			terrain_atlas_index = int(_pending_terrain_atlas_indices[index])
		_apply_cell(local_coord, terrain_id, terrain_atlas_index)
		_apply_roof_cell(local_coord, index)
	_apply_index = end_index
	if _apply_index >= _pending_terrain_ids.size():
		return false
	return true

func apply_runtime_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	_ensure_layers()
	_apply_cell(local_coord, terrain_id, terrain_atlas_index)

func set_entrance_flag(local: Vector2i, is_entrance: bool) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local):
		return
	_ensure_layers()
	var index: int = WorldRuntimeConstants.local_to_index(local)
	if index < 0 or index >= _entrance_cache.size():
		return
	var was_entrance: bool = _entrance_cache[index] != 0
	if was_entrance == is_entrance:
		return
	_entrance_cache[index] = 1 if is_entrance else 0
	if index >= _pending_mountain_ids.size() or index >= _pending_mountain_flags.size():
		return
	var mountain_id: int = int(_pending_mountain_ids[index])
	if mountain_id <= 0:
		return
	if is_entrance:
		var layer: TileMapLayer = roof_layers_by_mountain.get(mountain_id, null) as TileMapLayer
		_clear_cell(layer, local)
	_apply_roof_cell(local, index)

func get_entrance_flag(local: Vector2i) -> bool:
	if not WorldRuntimeConstants.is_local_coord_valid(local):
		return false
	var index: int = WorldRuntimeConstants.local_to_index(local)
	return index >= 0 and index < _entrance_cache.size() and _entrance_cache[index] != 0

func sync_cover_masks(open_masks_by_mountain: Dictionary) -> void:
	var all_mountain_ids: Dictionary = {}
	for mountain_id_variant: Variant in roof_layers_by_mountain.keys():
		all_mountain_ids[int(mountain_id_variant)] = true
	for mountain_id_variant: Variant in open_masks_by_mountain.keys():
		all_mountain_ids[int(mountain_id_variant)] = true
	for mountain_id_variant: Variant in all_mountain_ids.keys():
		var mountain_id: int = int(mountain_id_variant)
		var open_mask: PackedByteArray = open_masks_by_mountain.get(mountain_id, PackedByteArray()) as PackedByteArray
		_apply_cover_mask(mountain_id, open_mask)

func _ensure_layers() -> void:
	if _base_layer != null \
			and is_instance_valid(_base_layer) \
			and _overlay_layer != null \
			and is_instance_valid(_overlay_layer) \
			and _entrance_cache.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT:
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
	if _entrance_cache.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_entrance_cache = PackedByteArray()
		_entrance_cache.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)

func _ensure_roof_layer(mountain_id: int) -> TileMapLayer:
	if roof_layers_by_mountain.has(mountain_id):
		return roof_layers_by_mountain[mountain_id] as TileMapLayer
	var roof_bundle: Dictionary = WorldTileSetFactory.create_roof_tile_set_bundle()
	var roof_tile_set: TileSet = roof_bundle.get("tile_set", null) as TileSet
	var roof_material: ShaderMaterial = roof_bundle.get("material", null) as ShaderMaterial
	var layer := TileMapLayer.new()
	layer.name = "RoofLayer_%d" % mountain_id
	layer.tile_set = roof_tile_set
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.z_index = 10
	if roof_material != null:
		roof_material.set_shader_parameter("chunk_origin_px", WorldRuntimeConstants.chunk_origin_px(chunk_coord))
		roof_material.set_shader_parameter("open_mask", _build_cover_mask_texture(_zero_cover_mask()))
		roof_material.set_shader_parameter("open_alpha", _get_reveal_alpha(mountain_id))
	add_child(layer)
	roof_layers_by_mountain[mountain_id] = layer
	_roof_materials_by_mountain[mountain_id] = roof_material
	_roof_source_ids_by_mountain[mountain_id] = int(roof_bundle.get("source_id", 0))
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
	if index < 0 or index >= _pending_mountain_ids.size() or index >= _pending_mountain_flags.size():
		return
	if get_entrance_flag(local_coord):
		return
	var mountain_id: int = int(_pending_mountain_ids[index])
	if mountain_id <= 0:
		return
	var terrain_atlas_index: int = 0
	if index < _pending_mountain_atlas_indices.size():
		terrain_atlas_index = int(_pending_mountain_atlas_indices[index])
	var layer: TileMapLayer = _ensure_roof_layer(mountain_id)
	var source_id: int = int(_roof_source_ids_by_mountain.get(mountain_id, 0))
	layer.set_cell(
		local_coord,
		source_id,
		WorldTileSetFactory.get_atlas_coords(WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL, terrain_atlas_index)
	)

func _clear_cell(layer: TileMapLayer, local_coord: Vector2i) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.set_cell(local_coord, -1, Vector2i(-1, -1))

func _clear_roof_layers() -> void:
	for layer_variant: Variant in roof_layers_by_mountain.values():
		var layer: TileMapLayer = layer_variant as TileMapLayer
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
	roof_layers_by_mountain.clear()
	_cover_mask_bytes_by_mountain.clear()
	_cover_mask_textures_by_mountain.clear()
	_roof_materials_by_mountain.clear()
	_roof_source_ids_by_mountain.clear()

func _connect_reveal_registry() -> void:
	var registry: MountainRevealRegistry = _get_reveal_registry()
	if registry == null:
		return
	if not registry.alpha_changed.is_connected(_on_alpha_changed):
		registry.alpha_changed.connect(_on_alpha_changed)

func _get_reveal_registry() -> MountainRevealRegistry:
	if _mountain_reveal_registry != null and is_instance_valid(_mountain_reveal_registry):
		return _mountain_reveal_registry
	if get_tree() == null:
		return null
	var chunk_manager: Node = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager == null or not chunk_manager.has_method("get_mountain_reveal_registry"):
		return null
	_mountain_reveal_registry = chunk_manager.call("get_mountain_reveal_registry") as MountainRevealRegistry
	return _mountain_reveal_registry

func _get_reveal_alpha(mountain_id: int) -> float:
	var registry: MountainRevealRegistry = _get_reveal_registry()
	if registry == null:
		return 1.0
	return registry.get_alpha(mountain_id)

func _on_alpha_changed(mountain_id: int, alpha: float) -> void:
	var material: ShaderMaterial = _roof_materials_by_mountain.get(mountain_id, null) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("open_alpha", alpha)

func _on_mountain_visibility_changed(mountain_id: int) -> void:
	_on_alpha_changed(mountain_id, _get_reveal_alpha(mountain_id))

func _apply_cover_mask(mountain_id: int, open_mask: PackedByteArray) -> void:
	if not roof_layers_by_mountain.has(mountain_id) and open_mask.is_empty():
		return
	var layer: TileMapLayer = _ensure_roof_layer(mountain_id)
	if layer == null or not is_instance_valid(layer):
		return
	var resolved_mask: PackedByteArray = open_mask.duplicate()
	if resolved_mask.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		resolved_mask = _zero_cover_mask()
	var previous_mask: PackedByteArray = _cover_mask_bytes_by_mountain.get(mountain_id, PackedByteArray()) as PackedByteArray
	if previous_mask == resolved_mask:
		return
	var texture: ImageTexture = _build_cover_mask_texture(resolved_mask)
	_cover_mask_bytes_by_mountain[mountain_id] = resolved_mask
	_cover_mask_textures_by_mountain[mountain_id] = texture
	var material: ShaderMaterial = _roof_materials_by_mountain.get(mountain_id, null) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("open_mask", texture)
		material.set_shader_parameter("open_alpha", _get_reveal_alpha(mountain_id))

func _build_cover_mask_texture(open_mask: PackedByteArray) -> ImageTexture:
	var resolved_mask: PackedByteArray = open_mask
	if resolved_mask.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		resolved_mask = _zero_cover_mask()
	var image_bytes := PackedByteArray()
	image_bytes.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT * 4)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var byte_index: int = index * 4
		var mask_value: int = int(resolved_mask[index])
		image_bytes[byte_index] = mask_value
		image_bytes[byte_index + 1] = 0
		image_bytes[byte_index + 2] = 0
		image_bytes[byte_index + 3] = 255
	var image: Image = Image.create_from_data(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_RGBA8,
		image_bytes
	)
	return ImageTexture.create_from_image(image)

func _zero_cover_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	return mask
