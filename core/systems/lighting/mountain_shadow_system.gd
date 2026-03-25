class_name MountainShadowSystem
extends Node

## Система теней от гор. Строит shadow_mask по чанкам на основе
## внешней кромки горы и угла солнца. Рендер через Sprite2D + ImageTexture.
## Edge-тайлы кешируются при загрузке чанка. Rebuild бюджетирован.

var _chunk_manager: ChunkManager = null
var _shadow_sprites: Dictionary = {}
var _shadow_container: Node2D = null
var _last_built_angle: float = -999.0
var _edge_cache: Dictionary = {}
var _dirty_queue: Array[Vector2i] = []
var _edge_build_queue: Array[Vector2i] = []
var _active_build: Dictionary = {}  ## Progressive shadow build state

func _ready() -> void:
	_shadow_container = Node2D.new()
	_shadow_container.name = "ShadowContainer"
	_shadow_container.z_index = -5
	add_child(_shadow_container)
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	EventBus.mountain_tile_mined.connect(_on_mountain_tile_mined)
	call_deferred("_resolve_dependencies")

func _process(_delta: float) -> void:
	if not _chunk_manager or not TimeManager or not WorldGenerator or not WorldGenerator.balance:
		return
	var sun_angle: float = TimeManager.get_sun_angle()
	var threshold: float = WorldGenerator.balance.shadow_angle_threshold
	if absf(sun_angle - _last_built_angle) > threshold:
		_last_built_angle = sun_angle
		_mark_all_dirty()

func _resolve_dependencies() -> void:
	var chunks: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunks.is_empty():
		_chunk_manager = chunks[0] as ChunkManager
	FrameBudgetDispatcher.register_job(&"visual", 1.0, _tick_shadows)

func _on_chunk_loaded(coord: Vector2i) -> void:
	if coord not in _edge_build_queue:
		_edge_build_queue.append(coord)

func _on_chunk_unloaded(coord: Vector2i) -> void:
	_edge_cache.erase(coord)
	_remove_shadow(coord)

func _on_mountain_tile_mined(tile_pos: Vector2i, _old_type: int, _new_type: int) -> void:
	_update_edges_at(tile_pos)
	var coord: Vector2i = WorldGenerator.tile_to_chunk(tile_pos)
	_mark_dirty(coord)
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Vector2i = coord + dir
		if _chunk_manager and _chunk_manager.get_chunk(neighbor):
			_mark_dirty(neighbor)

func _mark_dirty(coord: Vector2i) -> void:
	if coord not in _dirty_queue:
		_dirty_queue.append(coord)

func _mark_all_dirty() -> void:
	_dirty_queue.clear()
	if not _chunk_manager:
		return
	for coord: Vector2i in _chunk_manager.get_loaded_chunks():
		_dirty_queue.append(coord)

## Tick для FrameBudgetDispatcher. Edge build → progressive shadow build.
func _tick_shadows() -> bool:
	if not _edge_build_queue.is_empty():
		var coord: Vector2i = _edge_build_queue.pop_front()
		_cache_edges(coord)
		_mark_dirty(coord)
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			_mark_dirty(coord + dir)
		return true
	if not _active_build.is_empty():
		_advance_shadow_build()
		return true
	if _dirty_queue.is_empty():
		return false
	var coord: Vector2i = _dirty_queue.pop_front()
	if not _chunk_manager or not _chunk_manager.get_chunk(coord):
		return not _dirty_queue.is_empty()
	_start_shadow_build(coord)
	return true


## Инкрементальное обновление edge-кеша для 1 тайла и 8 соседей. O(9) вместо O(4096).
func _update_edges_at(tile_pos: Vector2i) -> void:
	if not _chunk_manager:
		return
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var check_tile: Vector2i = tile_pos + Vector2i(offset_x, offset_y)
			var coord: Vector2i = WorldGenerator.tile_to_chunk(check_tile)
			var chunk: Chunk = _chunk_manager.get_chunk(coord)
			if not chunk:
				continue
			var chunk_size: int = chunk.get_chunk_size()
			var local_tile: Vector2i = chunk.global_to_local(check_tile)
			if local_tile.x < 0 or local_tile.y < 0 or local_tile.x >= chunk_size or local_tile.y >= chunk_size:
				continue
			var is_edge: bool = chunk.get_terrain_type_at(local_tile) == TileGenData.TerrainType.ROCK and _is_external_edge(chunk, local_tile, chunk_size)
			if not _edge_cache.has(coord):
				_edge_cache[coord] = [] as Array[Vector2i]
			var edges: Array = _edge_cache[coord] as Array
			var edge_idx: int = edges.find(check_tile)
			if is_edge and edge_idx < 0:
				edges.append(check_tile)
			elif not is_edge and edge_idx >= 0:
				edges.remove_at(edge_idx)

func _cache_edges(coord: Vector2i) -> void:
	if not _chunk_manager:
		return
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if not chunk or not chunk.has_any_mountain():
		_edge_cache[coord] = [] as Array[Vector2i]
		return
	var chunk_size: int = chunk.get_chunk_size()
	var base_x: int = coord.x * chunk_size
	var base_y: int = coord.y * chunk_size
	var edges: Array[Vector2i] = []
	for local_y: int in range(chunk_size):
		for local_x: int in range(chunk_size):
			var local_tile: Vector2i = Vector2i(local_x, local_y)
			if chunk.get_terrain_type_at(local_tile) != TileGenData.TerrainType.ROCK:
				continue
			if _is_external_edge(chunk, local_tile, chunk_size):
				edges.append(Vector2i(base_x + local_x, base_y + local_y))
	_edge_cache[coord] = edges

const EDGES_PER_TICK: int = 30

## Начинает progressive shadow build для чанка.
func _start_shadow_build(coord: Vector2i) -> void:
	var balance: WorldGenBalance = WorldGenerator.balance
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if not chunk:
		_remove_shadow(coord)
		return
	var length_factor: float = TimeManager.get_shadow_length_factor()
	if length_factor <= 0.0:
		_remove_shadow(coord)
		return
	var chunk_size: int = chunk.get_chunk_size()
	var shadow_length: int = clampi(
		int(float(balance.shadow_mountain_height) * length_factor),
		1, balance.shadow_max_length
	)
	var sun_angle: float = TimeManager.get_sun_angle()
	var shadow_dir: Vector2 = Vector2(cos(sun_angle + PI), sin(sun_angle + PI))
	var all_edges: Array[Vector2i] = []
	var source_chunks: Array[Vector2i] = [coord]
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		source_chunks.append(coord + dir)
	for source_coord: Vector2i in source_chunks:
		var edges: Array = _edge_cache.get(source_coord, []) as Array
		for e: Vector2i in edges:
			all_edges.append(e)
	_active_build = {
		"coord": coord,
		"chunk_size": chunk_size,
		"tile_size": balance.tile_size,
		"base_x": coord.x * chunk_size,
		"base_y": coord.y * chunk_size,
		"shadow_color": balance.shadow_color,
		"max_intensity": balance.shadow_intensity,
		"end_dx": roundi(shadow_dir.x * float(shadow_length)),
		"end_dy": roundi(shadow_dir.y * float(shadow_length)),
		"edges": all_edges,
		"edge_idx": 0,
		"img": Image.create(chunk_size, chunk_size, false, Image.FORMAT_RGBA8),
		"has_pixels": false,
	}

## Обрабатывает порцию edge-тайлов. Финализирует когда все обработаны.
func _advance_shadow_build() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	var b: Dictionary = _active_build
	var edges: Array = b["edges"] as Array
	var edge_idx: int = b["edge_idx"] as int
	var img: Image = b["img"] as Image
	var chunk_size: int = b["chunk_size"] as int
	var base_x: int = b["base_x"] as int
	var base_y: int = b["base_y"] as int
	var end_dx: int = b["end_dx"] as int
	var end_dy: int = b["end_dy"] as int
	var shadow_color: Color = b["shadow_color"] as Color
	var max_intensity: float = b["max_intensity"] as float
	var has_pixels: bool = b["has_pixels"] as bool
	var coord: Vector2i = b["coord"] as Vector2i
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	if not chunk:
		_remove_shadow(coord)
		_active_build.clear()
		return
	var end_idx: int = mini(edge_idx + EDGES_PER_TICK, edges.size())
	for i: int in range(edge_idx, end_idx):
		var edge_global: Vector2i = edges[i] as Vector2i
		var points: Array[Vector2i] = _bresenham(0, 0, end_dx, end_dy)
		for point_idx: int in range(points.size()):
			var pt: Vector2i = points[point_idx]
			var px: int = edge_global.x + pt.x - base_x
			var py: int = edge_global.y + pt.y - base_y
			if px < 0 or py < 0 or px >= chunk_size or py >= chunk_size:
				continue
			var terrain: int = chunk.get_terrain_type_at(Vector2i(px, py))
			if terrain == TileGenData.TerrainType.ROCK:
				continue
			var fade: float = 1.0 - (float(point_idx + 1) / float(points.size() + 1))
			var alpha: float = max_intensity * fade
			var current: Color = img.get_pixel(px, py)
			if alpha > current.a:
				img.set_pixel(px, py, Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha))
				has_pixels = true
	b["edge_idx"] = end_idx
	b["has_pixels"] = has_pixels
	if end_idx >= edges.size():
		WorldPerfProbe.end("Shadow.advance_slice", started_usec)
		_finalize_shadow_build()
		return
	WorldPerfProbe.end("Shadow.advance_slice", started_usec)

## Финализация: создать текстуру и sprite.
func _finalize_shadow_build() -> void:
	var finalize_usec: int = WorldPerfProbe.begin()
	var b: Dictionary = _active_build
	var coord: Vector2i = b["coord"] as Vector2i
	var has_pixels: bool = b["has_pixels"] as bool
	var img: Image = b["img"] as Image
	var tile_size: int = b["tile_size"] as int
	var base_x: int = b["base_x"] as int
	var base_y: int = b["base_y"] as int
	_active_build.clear()
	if not has_pixels:
		_remove_shadow(coord)
		WorldPerfProbe.end("Shadow.finalize %s" % [coord], finalize_usec)
		return
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var sprite: Sprite2D
	if _shadow_sprites.has(coord):
		sprite = _shadow_sprites[coord]
	else:
		sprite = Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_shadow_container.add_child(sprite)
		_shadow_sprites[coord] = sprite
	sprite.texture = tex
	sprite.scale = Vector2(tile_size, tile_size)
	sprite.position = Vector2(base_x * tile_size, base_y * tile_size)
	WorldPerfProbe.end("Shadow.finalize %s" % [coord], finalize_usec)

func _is_external_edge(chunk: Chunk, local: Vector2i, chunk_size: int) -> bool:
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var neighbor: Vector2i = local + dir
		if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= chunk_size or neighbor.y >= chunk_size:
			continue
		var terrain: int = chunk.get_terrain_type_at(neighbor)
		if terrain == TileGenData.TerrainType.GROUND \
			or terrain == TileGenData.TerrainType.WATER \
			or terrain == TileGenData.TerrainType.SAND \
			or terrain == TileGenData.TerrainType.GRASS:
			return true
	return false

func _remove_shadow(coord: Vector2i) -> void:
	if _shadow_sprites.has(coord):
		(_shadow_sprites[coord] as Sprite2D).queue_free()
		_shadow_sprites.erase(coord)

func _bresenham(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	var cx: int = x0
	var cy: int = y0
	while true:
		if cx != x0 or cy != y0:
			result.append(Vector2i(cx, cy))
		if cx == x1 and cy == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
	return result
