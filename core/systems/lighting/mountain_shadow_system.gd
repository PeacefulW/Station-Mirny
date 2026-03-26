class_name MountainShadowSystem
extends Node

## Система теней от гор. Строит shadow_mask по чанкам на основе
## внешней кромки горы и угла солнца. Рендер через Sprite2D + ImageTexture.
## Edge-тайлы кешируются при загрузке чанка. Rebuild бюджетирован.

const RuntimeWorkTypes = preload("res://core/runtime/runtime_work_types.gd")
const JOB_SHADOWS: StringName = &"mountain_shadow.visual_rebuild"
const INVALID_COORD: Vector2i = Vector2i(999999, 999999)
const EDGE_NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1),
]

var _chunk_manager: ChunkManager = null
var _shadow_sprites: Dictionary = {}
var _shadow_container: Node2D = null
var _last_built_angle: float = -999.0
var _edge_cache: Dictionary = {}
var _dirty_queue: Array[Vector2i] = []
var _edge_build_queue: Array[Vector2i] = []
var _active_edge_cache_build: Dictionary = {}
var _active_build: Dictionary = {}  ## Progressive shadow build state
var _prefer_shadow_step: bool = true

func _ready() -> void:
	_shadow_container = Node2D.new()
	_shadow_container.name = "ShadowContainer"
	_shadow_container.z_index = -5
	add_child(_shadow_container)
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	EventBus.mountain_tile_mined.connect(_on_mountain_tile_mined)
	call_deferred("_resolve_dependencies")

func _exit_tree() -> void:
	if FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(JOB_SHADOWS)

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
	FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_VISUAL,
		1.0,
		_tick_shadows,
		JOB_SHADOWS,
		RuntimeWorkTypes.CadenceKind.PRESENTATION,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"Mountain shadows"
	)

func _on_chunk_loaded(coord: Vector2i) -> void:
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	if chunk and chunk.has_any_mountain():
		_enqueue_edge_cache_build(coord)
	_mark_dirty(coord)
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		_mark_dirty(coord + dir)

func _on_chunk_unloaded(coord: Vector2i) -> void:
	var active_edge_coord: Vector2i = _active_edge_cache_build.get("coord", Vector2i(999999, 999999))
	if not _active_edge_cache_build.is_empty() \
		and active_edge_coord == coord:
		_active_edge_cache_build.clear()
	var active_shadow_coord: Vector2i = _active_build.get("coord", Vector2i(999999, 999999))
	if not _active_build.is_empty() \
		and active_shadow_coord == coord:
		_active_build.clear()
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
	if not _chunk_manager:
		return
	for coord: Vector2i in _chunk_manager.get_loaded_chunks():
		if _chunk_or_neighbors_have_mountain(coord):
			_mark_dirty(coord)

## Tick для FrameBudgetDispatcher. Edge build → progressive shadow build.
func _tick_shadows() -> bool:
	if not _active_build.is_empty():
		var phase: String = str(_active_build.get("phase", "build"))
		match phase:
			"build":
				_advance_shadow_build()
			"finalize_texture":
				_finalize_shadow_texture()
			"finalize_apply":
				_finalize_shadow_apply()
			_:
				_active_build.clear()
		return true
	var has_dirty: bool = not _dirty_queue.is_empty()
	var has_edge_work: bool = not _active_edge_cache_build.is_empty() or not _edge_build_queue.is_empty()
	if has_dirty and has_edge_work:
		if _prefer_shadow_step and _try_shadow_step():
			_prefer_shadow_step = false
			return true
		if _try_edge_step():
			_prefer_shadow_step = true
			return true
		if _try_shadow_step():
			_prefer_shadow_step = false
			return true
		return false
	if has_dirty:
		return _try_shadow_step()
	if has_edge_work:
		return _try_edge_step()
	return false

func _try_shadow_step() -> bool:
	while not _dirty_queue.is_empty():
		var coord: Vector2i = _pop_best_queue_coord(_dirty_queue)
		if not _chunk_manager or not _chunk_manager.get_chunk(coord):
			continue
		_start_shadow_build(coord)
		return true
	return false

func _try_edge_step() -> bool:
	if not _active_edge_cache_build.is_empty():
		_advance_edge_cache_build()
		return true
	if not _edge_build_queue.is_empty():
		var coord: Vector2i = _pop_best_queue_coord(_edge_build_queue)
		_start_edge_cache_build(coord)
		return true
	return false


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
			var terrain_bytes: PackedByteArray = chunk.get_terrain_bytes()
			var local_index: int = local_tile.y * chunk_size + local_tile.x
			var is_edge: bool = terrain_bytes[local_index] == TileGenData.TerrainType.ROCK \
				and _is_external_edge_at(coord, terrain_bytes, local_tile.x, local_tile.y, chunk_size)
			if not _edge_cache.has(coord):
				_edge_cache[coord] = [] as Array[Vector2i]
			var edges: Array = _edge_cache[coord] as Array
			var edge_idx: int = edges.find(check_tile)
			if is_edge and edge_idx < 0:
				edges.append(check_tile)
			elif not is_edge and edge_idx >= 0:
				edges.remove_at(edge_idx)

func _enqueue_edge_cache_build(coord: Vector2i) -> void:
	if _active_edge_cache_build.get("coord", INVALID_COORD) == coord:
		return
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	if not chunk or not chunk.has_any_mountain():
		return
	if coord not in _edge_build_queue:
		_edge_build_queue.append(coord)

func _pop_best_queue_coord(queue: Array[Vector2i]) -> Vector2i:
	if queue.is_empty():
		return INVALID_COORD
	var player_chunk: Vector2i = _get_player_chunk_coord()
	if player_chunk == INVALID_COORD:
		var first_coord: Vector2i = queue[0]
		queue.remove_at(0)
		return first_coord
	var best_idx: int = 0
	var best_score: int = _chunk_priority_score(queue[0], player_chunk)
	for i: int in range(1, queue.size()):
		var score: int = _chunk_priority_score(queue[i], player_chunk)
		if score < best_score:
			best_idx = i
			best_score = score
	var coord: Vector2i = queue[best_idx]
	queue.remove_at(best_idx)
	return coord

func _get_player_chunk_coord() -> Vector2i:
	if not WorldGenerator or not PlayerAuthority:
		return INVALID_COORD
	var player_pos: Vector2 = PlayerAuthority.get_local_player_position()
	var player_tile: Vector2i = WorldGenerator.world_to_tile(player_pos)
	return WorldGenerator.tile_to_chunk(player_tile)

func _chunk_priority_score(coord: Vector2i, player_chunk: Vector2i) -> int:
	var dx: int = coord.x - player_chunk.x
	var dy: int = coord.y - player_chunk.y
	return dx * dx + dy * dy

func _chunk_or_neighbors_have_mountain(coord: Vector2i) -> bool:
	if not _chunk_manager:
		return false
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if chunk and chunk.has_any_mountain():
		return true
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor: Chunk = _chunk_manager.get_chunk(coord + dir)
		if neighbor and neighbor.has_any_mountain():
			return true
	return false

func _start_edge_cache_build(coord: Vector2i) -> void:
	if not _chunk_manager:
		return
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if not chunk or not chunk.has_any_mountain():
		_edge_cache[coord] = [] as Array[Vector2i]
		_complete_edge_cache_build(coord)
		return
	var chunk_size: int = chunk.get_chunk_size()
	_active_edge_cache_build = {
		"coord": coord,
		"chunk_size": chunk_size,
		"base_x": coord.x * chunk_size,
		"base_y": coord.y * chunk_size,
		"tile_index": 0,
		"edges": [] as Array[Vector2i],
	}

func _advance_edge_cache_build() -> void:
	var started_usec: int = WorldPerfProbe.begin()
	var build: Dictionary = _active_edge_cache_build
	var coord: Vector2i = build.get("coord", Vector2i(999999, 999999))
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	if not chunk or not chunk.has_any_mountain():
		_edge_cache[coord] = [] as Array[Vector2i]
		_active_edge_cache_build.clear()
		_complete_edge_cache_build(coord)
		WorldPerfProbe.end("Shadow.edge_cache_slice", started_usec)
		return
	var chunk_size: int = build["chunk_size"] as int
	var base_x: int = build["base_x"] as int
	var base_y: int = build["base_y"] as int
	var tile_index: int = build["tile_index"] as int
	var tile_budget: int = _resolve_shadow_edge_cache_tile_budget()
	var total_tiles: int = chunk_size * chunk_size
	var end_index: int = mini(tile_index + tile_budget, total_tiles)
	var edges: Array = build["edges"] as Array
	var terrain_bytes: PackedByteArray = chunk.get_terrain_bytes()
	for current_index: int in range(tile_index, end_index):
		if terrain_bytes[current_index] != TileGenData.TerrainType.ROCK:
			continue
		var local_x: int = current_index % chunk_size
		var local_y: int = current_index / chunk_size
		if _is_external_edge_at(coord, terrain_bytes, local_x, local_y, chunk_size):
			edges.append(Vector2i(base_x + local_x, base_y + local_y))
	build["tile_index"] = end_index
	if end_index >= total_tiles:
		_edge_cache[coord] = edges
		_active_edge_cache_build.clear()
		_complete_edge_cache_build(coord)
	WorldPerfProbe.end("Shadow.edge_cache_slice", started_usec)

func _complete_edge_cache_build(coord: Vector2i) -> void:
	_mark_dirty(coord)
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		_mark_dirty(coord + dir)

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
	if all_edges.is_empty():
		_remove_shadow(coord)
		return
	var shadow_points: Array[Vector2i] = _bresenham(0, 0, roundi(shadow_dir.x * float(shadow_length)), roundi(shadow_dir.y * float(shadow_length)))
	if shadow_points.is_empty():
		_remove_shadow(coord)
		return
	_active_build = {
		"phase": "build",
		"coord": coord,
		"chunk_size": chunk_size,
		"tile_size": balance.tile_size,
		"base_x": coord.x * chunk_size,
		"base_y": coord.y * chunk_size,
		"shadow_color": balance.shadow_color,
		"max_intensity": balance.shadow_intensity,
		"edges": all_edges,
		"edge_idx": 0,
		"shadow_points": shadow_points,
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
	var shadow_color: Color = b["shadow_color"] as Color
	var max_intensity: float = b["max_intensity"] as float
	var has_pixels: bool = b["has_pixels"] as bool
	var shadow_points: Array = b["shadow_points"] as Array
	var coord: Vector2i = b.get("coord", Vector2i(999999, 999999))
	var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
	if not chunk:
		_remove_shadow(coord)
		_active_build.clear()
		return
	var end_idx: int = mini(edge_idx + _resolve_shadow_edges_per_step(), edges.size())
	for i: int in range(edge_idx, end_idx):
		var edge_global: Vector2i = edges[i] as Vector2i
		for point_idx: int in range(shadow_points.size()):
			var pt: Vector2i = shadow_points[point_idx] as Vector2i
			var px: int = edge_global.x + pt.x - base_x
			var py: int = edge_global.y + pt.y - base_y
			if px < 0 or py < 0 or px >= chunk_size or py >= chunk_size:
				continue
			var terrain: int = chunk.get_terrain_type_at(Vector2i(px, py))
			if terrain == TileGenData.TerrainType.ROCK:
				continue
			var fade: float = 1.0 - (float(point_idx + 1) / float(shadow_points.size() + 1))
			var alpha: float = max_intensity * fade
			var current: Color = img.get_pixel(px, py)
			if alpha > current.a:
				img.set_pixel(px, py, Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha))
				has_pixels = true
	b["edge_idx"] = end_idx
	b["has_pixels"] = has_pixels
	if end_idx >= edges.size():
		WorldPerfProbe.end("Shadow.advance_slice", started_usec)
		b["phase"] = "finalize_texture"
		return
	WorldPerfProbe.end("Shadow.advance_slice", started_usec)

## Финализация apply разбита на texture build и sprite apply, чтобы не склеивать её с последним compute-step.
func _finalize_shadow_texture() -> void:
	var finalize_usec: int = WorldPerfProbe.begin()
	var b: Dictionary = _active_build
	var coord: Vector2i = b.get("coord", Vector2i(999999, 999999))
	var has_pixels: bool = b["has_pixels"] as bool
	var img: Image = b["img"] as Image
	if not has_pixels:
		_active_build.clear()
		_remove_shadow(coord)
		WorldPerfProbe.end("Shadow.finalize_texture %s" % [coord], finalize_usec)
		return
	b["texture"] = ImageTexture.create_from_image(img)
	b["phase"] = "finalize_apply"
	WorldPerfProbe.end("Shadow.finalize_texture %s" % [coord], finalize_usec)

func _finalize_shadow_apply() -> void:
	var finalize_usec: int = WorldPerfProbe.begin()
	var b: Dictionary = _active_build
	var coord: Vector2i = b.get("coord", Vector2i(999999, 999999))
	var tile_size: int = b["tile_size"] as int
	var base_x: int = b["base_x"] as int
	var base_y: int = b["base_y"] as int
	var tex: ImageTexture = b.get("texture") as ImageTexture
	if not _chunk_manager or not _chunk_manager.get_chunk(coord) or tex == null:
		_active_build.clear()
		_remove_shadow(coord)
		WorldPerfProbe.end("Shadow.finalize_apply %s" % [coord], finalize_usec)
		return
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
	_active_build.clear()
	WorldPerfProbe.end("Shadow.finalize_apply %s" % [coord], finalize_usec)

func _is_external_edge(chunk: Chunk, local: Vector2i, chunk_size: int) -> bool:
	return _is_external_edge_at(chunk.chunk_coord, chunk.get_terrain_bytes(), local.x, local.y, chunk_size)

func _is_external_edge_at(
	chunk_coord: Vector2i,
	terrain_bytes: PackedByteArray,
	local_x: int,
	local_y: int,
	chunk_size: int
) -> bool:
	var global_tile: Vector2i = Vector2i(
		chunk_coord.x * chunk_size + local_x,
		chunk_coord.y * chunk_size + local_y
	)
	for dir: Vector2i in EDGE_NEIGHBOR_OFFSETS:
		var neighbor_x: int = local_x + dir.x
		var neighbor_y: int = local_y + dir.y
		var terrain: int = TileGenData.TerrainType.ROCK
		if neighbor_x >= 0 and neighbor_y >= 0 and neighbor_x < chunk_size and neighbor_y < chunk_size:
			terrain = terrain_bytes[neighbor_y * chunk_size + neighbor_x]
		elif _chunk_manager:
			terrain = _chunk_manager.get_terrain_type_at_global(global_tile + dir)
		if _is_shadow_open_terrain(terrain):
			return true
	return false

func _is_shadow_open_terrain(terrain: int) -> bool:
	return terrain == TileGenData.TerrainType.GROUND \
		or terrain == TileGenData.TerrainType.WATER \
		or terrain == TileGenData.TerrainType.SAND \
		or terrain == TileGenData.TerrainType.GRASS

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

func _resolve_shadow_edge_cache_tile_budget() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.mountain_shadow_edge_cache_tiles_per_step)
	return 128

func _resolve_shadow_edges_per_step() -> int:
	if WorldGenerator and WorldGenerator.balance:
		return maxi(1, WorldGenerator.balance.mountain_shadow_edges_per_step)
	return 4
