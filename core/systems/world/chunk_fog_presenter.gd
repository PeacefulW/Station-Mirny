class_name ChunkFogPresenter
extends RefCounted

const FOG_LAYER_Z_INDEX: int = 7

var _owner: Node = null
var _chunk_size: int = 0
var _layer: TileMapLayer = null

func setup(owner: Node, chunk_size: int) -> void:
	_owner = owner
	_chunk_size = chunk_size

func has_layer() -> bool:
	return _layer != null

func ensure_layer(fog_tileset: TileSet) -> void:
	if _layer != null:
		return
	_layer = TileMapLayer.new()
	_layer.name = "FogLayer"
	_layer.tile_set = fog_tileset
	_layer.z_index = FOG_LAYER_Z_INDEX
	_owner.add_child(_layer)
	for y: int in range(_chunk_size):
		for x: int in range(_chunk_size):
			_layer.set_cell(
				Vector2i(x, y),
				ChunkTilesetFactory.FOG_SOURCE_ID,
				ChunkTilesetFactory.TILE_FOG_UNSEEN
			)

func apply_visible(
	visible_locals: Dictionary,
	is_inside: Callable,
	on_tile_revealed: Callable = Callable()
) -> void:
	if _layer == null:
		return
	for local: Vector2i in visible_locals:
		if not _is_valid_local(local, is_inside):
			continue
		_layer.erase_cell(local)
		if on_tile_revealed.is_valid():
			on_tile_revealed.call(local)

func apply_discovered(discovered_locals: Dictionary, is_inside: Callable) -> void:
	if _layer == null:
		return
	for local: Vector2i in discovered_locals:
		if not _is_valid_local(local, is_inside):
			continue
		_layer.set_cell(
			local,
			ChunkTilesetFactory.FOG_SOURCE_ID,
			ChunkTilesetFactory.TILE_FOG_DISCOVERED
		)

func reset_runtime_state() -> void:
	if _layer != null:
		_layer.queue_free()
		_layer = null

func _is_valid_local(local: Vector2i, is_inside: Callable) -> bool:
	return not is_inside.is_valid() or bool(is_inside.call(local))
