class_name ChunkManager
extends Node2D

## Менеджер чанков v12. Чистый: только terrain GROUND.

var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(99999, 99999)
var _player: Node2D = null
var _chunk_container: Node2D = null
var _load_queue: Array[Vector2i] = []
var _saved_chunk_data: Dictionary = {}
var _shared_tileset: TileSet = null
var _initialized: bool = false
var _active_z: int = 0
var _z_containers: Dictionary = {}
var _z_chunks: Dictionary = {}

const VARIANT_COUNT: int = 3

func _ready() -> void:
	add_to_group("chunk_manager")
	_chunk_container = Node2D.new()
	_chunk_container.name = "Chunks"
	add_child(_chunk_container)
	_setup_z_containers()
	call_deferred("_deferred_init")

func _process(_delta: float) -> void:
	if not _initialized or not _player:
		return
	_check_player_chunk()
	_process_load_queue()

func set_saved_data(data: Dictionary) -> void:
	_saved_chunk_data = data

func get_save_data() -> Dictionary:
	var result: Dictionary = _saved_chunk_data.duplicate()
	for coord: Vector2i in _loaded_chunks:
		var chunk: Chunk = _loaded_chunks[coord]
		if chunk.is_dirty:
			result[coord] = chunk.get_modifications()
	return result

func is_tile_loaded(gt: Vector2i) -> bool:
	return _loaded_chunks.has(WorldGenerator.tile_to_chunk(gt))

func get_chunk_at_tile(gt: Vector2i) -> Chunk:
	return _loaded_chunks.get(WorldGenerator.tile_to_chunk(gt))

func get_chunk(cc: Vector2i) -> Chunk:
	return _loaded_chunks.get(cc)

func get_loaded_chunks() -> Dictionary:
	return _loaded_chunks

func try_harvest_at_world(_world_pos: Vector2) -> Dictionary:
	return {}

func has_resource_at_world(_world_pos: Vector2) -> bool:
	return false

# --- Инициализация ---

func _deferred_init() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node2D
	_build_terrain_tileset()
	_initialized = _shared_tileset != null

## Цветные квадраты для terrain (только GROUND × 3 варианта).
func _build_terrain_tileset() -> void:
	if not WorldGenerator or not WorldGenerator.balance:
		return
	var ts: int = WorldGenerator.balance.tile_size
	var biome: BiomeData = WorldGenerator.current_biome
	if not biome:
		return
	var img := Image.create(ts, VARIANT_COUNT * ts, false, Image.FORMAT_RGBA8)
	var base_color: Color = biome.ground_color
	for vi: int in range(VARIANT_COUNT):
		var c: Color = base_color
		if vi == 0: c = c.darkened(0.12)
		elif vi == 2: c = c.lightened(0.10)
		for py: int in range(ts):
			for px: int in range(ts):
				img.set_pixel(px, vi * ts + py, c)
	var tex := ImageTexture.create_from_image(img)
	_shared_tileset = TileSet.new()
	_shared_tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	for y: int in range(VARIANT_COUNT):
		src.create_tile(Vector2i(0, y))
	_shared_tileset.add_source(src, 0)

# --- Обновление ---

func _check_player_chunk() -> void:
	var cur: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	if cur != _player_chunk:
		_player_chunk = cur
		_update_chunks(cur)

func _update_chunks(center: Vector2i) -> void:
	var lr: int = WorldGenerator.balance.load_radius
	var ur: int = WorldGenerator.balance.unload_radius
	var needed: Dictionary = {}
	for dx: int in range(-lr, lr + 1):
		for dy: int in range(-lr, lr + 1):
			needed[Vector2i(center.x + dx, center.y + dy)] = true
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks:
		if absi(coord.x - center.x) > ur or absi(coord.y - center.y) > ur:
			to_unload.append(coord)
	for coord: Vector2i in to_unload:
		_unload_chunk(coord)
	var to_load: Array[Vector2i] = []
	for coord: Vector2i in needed:
		if not _loaded_chunks.has(coord) and coord not in _load_queue:
			to_load.append(coord)
	to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absi(a.x - center.x) + absi(a.y - center.y) < absi(b.x - center.x) + absi(b.y - center.y)
	)
	_load_queue.append_array(to_load)

func _process_load_queue() -> void:
	var loaded: int = 0
	while not _load_queue.is_empty() and loaded < 3:
		var coord: Vector2i = _load_queue.pop_front()
		var lr: int = WorldGenerator.balance.load_radius
		if absi(coord.x - _player_chunk.x) > lr or absi(coord.y - _player_chunk.y) > lr:
			continue
		_load_chunk(coord)
		loaded += 1

func _load_chunk(coord: Vector2i) -> void:
	if _loaded_chunks.has(coord) or not _shared_tileset:
		return
	var native_data: Dictionary = WorldGenerator.get_chunk_data(coord)
	var chunk := Chunk.new()
	chunk.setup(coord, WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		WorldGenerator.current_biome, _shared_tileset)
	var saved_mods: Dictionary = _saved_chunk_data.get(coord, {})
	chunk.populate_native(native_data, saved_mods)
	var z_container: Node2D = _z_containers.get(_active_z) as Node2D
	if z_container:
		z_container.add_child(chunk)
	else:
		_chunk_container.add_child(chunk)
	_loaded_chunks[coord] = chunk
	EventBus.chunk_loaded.emit(coord)

func _unload_chunk(coord: Vector2i) -> void:
	if not _loaded_chunks.has(coord):
		return
	var chunk: Chunk = _loaded_chunks[coord]
	if chunk.is_dirty:
		_saved_chunk_data[coord] = chunk.get_modifications()
	chunk.cleanup()
	chunk.queue_free()
	_loaded_chunks.erase(coord)
	EventBus.chunk_unloaded.emit(coord)

# --- Z-уровни ---

func _setup_z_containers() -> void:
	for z: int in [ZLevelManager.Z_MIN, 0, ZLevelManager.Z_MAX]:
		var container := Node2D.new()
		container.name = "ZLayer_%d" % z
		container.visible = (z == 0)
		_chunk_container.add_child(container)
		_z_containers[z] = container
		_z_chunks[z] = {}
	_loaded_chunks = _z_chunks[0]

func set_active_z_level(z: int) -> void:
	_active_z = z
	for layer_z: int in _z_containers:
		(_z_containers[layer_z] as Node2D).visible = (layer_z == z)
	_loaded_chunks = _z_chunks.get(z, {})
	_player_chunk = Vector2i(99999, 99999)
