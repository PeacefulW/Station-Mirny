class_name ChunkView
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

var chunk_coord: Vector2i = Vector2i.ZERO

var _tile_layer: TileMapLayer = null
var _pending_terrain_ids: PackedInt32Array = PackedInt32Array()
var _pending_terrain_atlas_indices: PackedInt32Array = PackedInt32Array()
var _apply_index: int = 0

func configure(new_chunk_coord: Vector2i) -> void:
	chunk_coord = new_chunk_coord
	position = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_ensure_tile_layer()

func begin_apply(terrain_ids: PackedInt32Array, terrain_atlas_indices: PackedInt32Array) -> void:
	_pending_terrain_ids = terrain_ids.duplicate()
	_pending_terrain_atlas_indices = terrain_atlas_indices.duplicate()
	_apply_index = 0
	visible = false
	_ensure_tile_layer()

func apply_next_batch(batch_size: int) -> bool:
	if _pending_terrain_ids.is_empty():
		visible = true
		return false
	var end_index: int = mini(_apply_index + batch_size, _pending_terrain_ids.size())
	for index: int in range(_apply_index, end_index):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var terrain_id: int = int(_pending_terrain_ids[index])
		var terrain_atlas_index: int = 0
		if index < _pending_terrain_atlas_indices.size():
			terrain_atlas_index = int(_pending_terrain_atlas_indices[index])
		_apply_cell(local_coord, terrain_id, terrain_atlas_index)
	_apply_index = end_index
	if _apply_index >= _pending_terrain_ids.size():
		visible = true
		return false
	return true

func apply_runtime_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	_ensure_tile_layer()
	_apply_cell(local_coord, terrain_id, terrain_atlas_index)

func _ensure_tile_layer() -> void:
	if _tile_layer != null and is_instance_valid(_tile_layer):
		return
	_tile_layer = TileMapLayer.new()
	_tile_layer.name = "TerrainLayer"
	_tile_layer.tile_set = WorldTileSetFactory.get_tile_set()
	add_child(_tile_layer)

func _apply_cell(local_coord: Vector2i, terrain_id: int, terrain_atlas_index: int) -> void:
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return
	_tile_layer.set_cell(
		local_coord,
		WorldTileSetFactory.get_source_id(terrain_id),
		WorldTileSetFactory.get_atlas_coords(terrain_id, terrain_atlas_index)
	)
