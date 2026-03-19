class_name ChunkManager
extends Node2D

## Менеджер чанков v5. Использует C++ генерацию через WorldGenerator.

var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(99999, 99999)
var _player: Node2D = null
var _chunk_container: Node2D = null
var _load_queue: Array[Vector2i] = []
var _resource_defs: Dictionary = {}
var _saved_chunk_data: Dictionary = {}
var _shared_tileset: TileSet = null
var _initialized: bool = false

const TERRAIN_COUNT: int = 5
const VARIANT_COUNT: int = 3

func _ready() -> void:
	_chunk_container = Node2D.new()
	_chunk_container.name = "Chunks"
	add_child(_chunk_container)
	_load_resource_definitions()
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

func _deferred_init() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node2D
	_build_tileset()
	_initialized = _shared_tileset != null

func _build_tileset() -> void:
	if not WorldGenerator or not WorldGenerator.balance or not WorldGenerator.current_biome:
		push_warning("ChunkManager: WorldGenerator не готов")
		return
	var ts: int = WorldGenerator.balance.tile_size
	var biome: BiomeData = WorldGenerator.current_biome
	var img_w: int = TERRAIN_COUNT * ts
	var img_h: int = VARIANT_COUNT * ts
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	var base_colors: Array[Color] = [
		biome.ground_color, biome.rock_color, biome.water_color,
		biome.sand_color, biome.grass_color,
	]
	for ti: int in range(TERRAIN_COUNT):
		for vi: int in range(VARIANT_COUNT):
			var c: Color = base_colors[ti]
			if vi == 0: c = c.darkened(0.12)
			elif vi == 2: c = c.lightened(0.10)
			var sx: int = ti * ts
			var sy: int = vi * ts
			for px: int in range(ts):
				for py: int in range(ts):
					img.set_pixel(sx + px, sy + py, c)
	var texture := ImageTexture.create_from_image(img)
	_shared_tileset = TileSet.new()
	_shared_tileset.tile_size = Vector2i(ts, ts)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(ts, ts)
	for x: int in range(TERRAIN_COUNT):
		for y: int in range(VARIANT_COUNT):
			source.create_tile(Vector2i(x, y))
	_shared_tileset.add_source(source, 0)

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

## С C++ — можно грузить 3-4 чанка за кадр без фризов.
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
	# Генерация через C++ — мгновенно
	var native_data: Dictionary = WorldGenerator.get_chunk_data(coord)
	var chunk := Chunk.new()
	chunk.setup(coord, WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		WorldGenerator.current_biome, _shared_tileset)
	var saved_mods: Dictionary = _saved_chunk_data.get(coord, {})
	# Используем native формат если есть packed arrays
	if native_data.has("terrain"):
		chunk.populate_native(native_data, saved_mods, _resource_defs)
	else:
		chunk.populate(native_data, saved_mods, _resource_defs)
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

func _load_resource_definitions() -> void:
	var iron := ResourceNodeData.new()
	iron.id = &"iron_ore"; iron.display_name = "Железная руда"
	iron.drop_item_id = &"iron_ore"; iron.drop_amount_min = 1; iron.drop_amount_max = 3
	iron.harvest_count = 8; iron.harvest_time = 2.0
	iron.placeholder_color = Color(0.55, 0.35, 0.25); iron.placeholder_size = Vector2(28, 28)
	iron.deposit_type = TileGenData.DepositType.IRON_ORE
	_resource_defs[TileGenData.DepositType.IRON_ORE] = iron
	_resource_defs[1] = iron  # C++ deposit type

	var copper := ResourceNodeData.new()
	copper.id = &"copper_ore"; copper.display_name = "Медная руда"
	copper.drop_item_id = &"copper_ore"; copper.drop_amount_min = 1; copper.drop_amount_max = 2
	copper.harvest_count = 6; copper.harvest_time = 2.5
	copper.placeholder_color = Color(0.65, 0.45, 0.20); copper.placeholder_size = Vector2(26, 26)
	copper.deposit_type = TileGenData.DepositType.COPPER_ORE
	_resource_defs[TileGenData.DepositType.COPPER_ORE] = copper
	_resource_defs[2] = copper

	var stone := ResourceNodeData.new()
	stone.id = &"stone"; stone.display_name = "Камень"
	stone.drop_item_id = &"stone"; stone.drop_amount_min = 2; stone.drop_amount_max = 4
	stone.harvest_count = 10; stone.harvest_time = 1.5
	stone.placeholder_color = Color(0.45, 0.43, 0.40); stone.placeholder_size = Vector2(30, 30)
	stone.deposit_type = TileGenData.DepositType.STONE
	_resource_defs[TileGenData.DepositType.STONE] = stone
	_resource_defs[3] = stone

	var water := ResourceNodeData.new()
	water.id = &"water_source"; water.display_name = "Водный источник"
	water.drop_item_id = &"water_dirty"; water.drop_amount_min = 1; water.drop_amount_max = 1
	water.harvest_count = 0; water.harvest_time = 3.0; water.is_solid = false
	water.placeholder_color = Color(0.20, 0.35, 0.55); water.placeholder_size = Vector2(24, 24)
	water.regenerates = true; water.regen_time = 60.0
	water.deposit_type = TileGenData.DepositType.WATER_SOURCE
	_resource_defs[TileGenData.DepositType.WATER_SOURCE] = water
	_resource_defs[4] = water

	var tree := ResourceNodeData.new()
	tree.id = &"dead_tree"; tree.display_name = "Мёртвое дерево"
	tree.drop_item_id = &"wood"; tree.drop_amount_min = 2; tree.drop_amount_max = 5
	tree.harvest_count = 3; tree.harvest_time = 2.0
	tree.placeholder_color = Color(0.30, 0.22, 0.15); tree.placeholder_size = Vector2(20, 32)
	tree.collision_radius = 10.0
	_resource_defs["tree"] = tree
