class_name ChunkManager
extends Node2D

## Менеджер чанков v7. Текстуры земли из атласа PNG.

var _loaded_chunks: Dictionary = {}
var _player_chunk: Vector2i = Vector2i(99999, 99999)
var _player: Node2D = null
var _chunk_container: Node2D = null
var _load_queue: Array[Vector2i] = []
var _resource_defs: Dictionary = {}
var _saved_chunk_data: Dictionary = {}
var _shared_tileset: TileSet = null
var _resource_tileset: TileSet = null
var _initialized: bool = false

const TERRAIN_COUNT: int = 5
const VARIANT_COUNT: int = 3
const RESOURCE_COUNT: int = 5
const TERRAIN_ATLAS_PATH: String = "res://assets/textures/terrain_atlas.png"
const RESOURCE_ATLAS_PATH: String = "res://assets/textures/resource_atlas.png"

func _ready() -> void:
	add_to_group("chunk_manager")
	_chunk_container = Node2D.new()
	_chunk_container.name = "Chunks"
	add_child(_chunk_container)
	_load_resource_defs()
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

func try_harvest_at_world(world_pos: Vector2) -> Dictionary:
	var tile: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var cc: Vector2i = WorldGenerator.tile_to_chunk(tile)
	var chunk: Chunk = _loaded_chunks.get(cc)
	if not chunk:
		return {}
	var local: Vector2i = chunk.global_to_local(tile)
	return chunk.try_harvest_at(local)

func has_resource_at_world(world_pos: Vector2) -> bool:
	var tile: Vector2i = WorldGenerator.world_to_tile(world_pos)
	var cc: Vector2i = WorldGenerator.tile_to_chunk(tile)
	var chunk: Chunk = _loaded_chunks.get(cc)
	if not chunk:
		return false
	return chunk.has_resource_at(chunk.global_to_local(tile))

# --- Инициализация ---

func _deferred_init() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node2D
	_build_terrain_tileset()
	_build_resource_tileset()
	_initialized = _shared_tileset != null and _resource_tileset != null

## Загружает атлас земли из PNG. Если файла нет — fallback на цветные квадраты.
func _build_terrain_tileset() -> void:
	if not WorldGenerator or not WorldGenerator.balance:
		return
	var ts: int = WorldGenerator.balance.tile_size

	# Пытаемся загрузить PNG атлас
	var atlas_tex: Texture2D = null
	if ResourceLoader.exists(TERRAIN_ATLAS_PATH):
		atlas_tex = load(TERRAIN_ATLAS_PATH) as Texture2D

	if atlas_tex:
		# Атлас найден — используем текстуры
		_shared_tileset = TileSet.new()
		_shared_tileset.tile_size = Vector2i(ts, ts)
		var source := TileSetAtlasSource.new()
		source.texture = atlas_tex
		source.texture_region_size = Vector2i(ts, ts)
		for x: int in range(TERRAIN_COUNT):
			for y: int in range(VARIANT_COUNT):
				source.create_tile(Vector2i(x, y))
		_shared_tileset.add_source(source, 0)
	else:
		# Fallback — цветные квадраты (как раньше)
		push_warning("ChunkManager: Атлас %s не найден, используем цвета" % TERRAIN_ATLAS_PATH)
		_build_terrain_tileset_fallback()

## Fallback: генерация цветных квадратов если атлас не найден.
func _build_terrain_tileset_fallback() -> void:
	var ts: int = WorldGenerator.balance.tile_size
	var biome: BiomeData = WorldGenerator.current_biome
	if not biome:
		return
	var img := Image.create(TERRAIN_COUNT * ts, VARIANT_COUNT * ts, false, Image.FORMAT_RGBA8)
	var colors: Array[Color] = [
		biome.ground_color, biome.rock_color, biome.water_color,
		biome.sand_color, biome.grass_color,
	]
	for ti: int in range(TERRAIN_COUNT):
		for vi: int in range(VARIANT_COUNT):
			var c: Color = colors[ti]
			if vi == 0: c = c.darkened(0.12)
			elif vi == 2: c = c.lightened(0.10)
			for py: int in range(ts):
				for px: int in range(ts):
					img.set_pixel(ti * ts + px, vi * ts + py, c)
	var tex := ImageTexture.create_from_image(img)
	_shared_tileset = TileSet.new()
	_shared_tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	for x: int in range(TERRAIN_COUNT):
		for y: int in range(VARIANT_COUNT):
			src.create_tile(Vector2i(x, y))
	_shared_tileset.add_source(src, 0)

func _build_resource_tileset() -> void:
	if not WorldGenerator or not WorldGenerator.balance:
		return
	var ts: int = WorldGenerator.balance.tile_size
	# Пытаемся загрузить PNG атлас ресурсов
	var atlas_tex: Texture2D = null
	if ResourceLoader.exists(RESOURCE_ATLAS_PATH):
		atlas_tex = load(RESOURCE_ATLAS_PATH) as Texture2D
	if atlas_tex:
		_resource_tileset = TileSet.new()
		_resource_tileset.tile_size = Vector2i(ts, ts)
		var src := TileSetAtlasSource.new()
		src.texture = atlas_tex
		src.texture_region_size = Vector2i(ts, ts)
		for x: int in range(RESOURCE_COUNT):
			src.create_tile(Vector2i(x, 0))
		_resource_tileset.add_source(src, 0)
	else:
		push_warning("ChunkManager: Атлас ресурсов не найден, используем квадраты")
		_build_resource_tileset_fallback()

## Fallback: цветные квадраты если атлас ресурсов не найден.
func _build_resource_tileset_fallback() -> void:
	var ts: int = WorldGenerator.balance.tile_size
	var res_colors: Array[Color] = [
		Color(0.55, 0.35, 0.25), Color(0.65, 0.45, 0.20),
		Color(0.45, 0.43, 0.40), Color(0.20, 0.35, 0.55),
		Color(0.30, 0.22, 0.15),
	]
	var img := Image.create(RESOURCE_COUNT * ts, ts, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half: int = ts / 2
	var dot_r: int = ts / 4
	for ri: int in range(RESOURCE_COUNT):
		var c: Color = res_colors[ri]
		var ox: int = ri * ts
		for py: int in range(half - dot_r, half + dot_r):
			for px: int in range(half - dot_r, half + dot_r):
				img.set_pixel(ox + px, py, c)
	var tex := ImageTexture.create_from_image(img)
	_resource_tileset = TileSet.new()
	_resource_tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	for x: int in range(RESOURCE_COUNT):
		src.create_tile(Vector2i(x, 0))
	_resource_tileset.add_source(src, 0)

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
	if _loaded_chunks.has(coord) or not _shared_tileset or not _resource_tileset:
		return
	var native_data: Dictionary = WorldGenerator.get_chunk_data(coord)
	var chunk := Chunk.new()
	chunk.setup(coord, WorldGenerator.balance.tile_size,
		WorldGenerator.balance.chunk_size_tiles,
		WorldGenerator.current_biome, _shared_tileset, _resource_tileset)
	var saved_mods: Dictionary = _saved_chunk_data.get(coord, {})
	chunk.populate_native(native_data, saved_mods, _resource_defs)
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

func _load_resource_defs() -> void:
	_resource_defs[1] = {"id": &"iron_ore", "harvest_count": 8}
	_resource_defs[2] = {"id": &"copper_ore", "harvest_count": 6}
	_resource_defs[3] = {"id": &"stone", "harvest_count": 10}
	_resource_defs[4] = {"id": &"water_source", "harvest_count": 0}
	_resource_defs[-1] = {"id": &"dead_tree", "harvest_count": 3}
