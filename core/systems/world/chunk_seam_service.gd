class_name ChunkSeamService
extends RefCounted

var _owner: Node = null
var _max_tiles_per_step: int = 4
var _pending_refresh_tiles: Array[Vector2i] = []
var _pending_refresh_lookup: Dictionary = {}

func setup(owner: Node, max_tiles_per_step: int) -> void:
	_owner = owner
	_max_tiles_per_step = maxi(1, max_tiles_per_step)

func _active_z() -> int:
	return _owner.get_active_z_level()

func _make_border_fix_reason_key(source_coord: Vector2i, z_level: int, tag: StringName) -> String:
	return _owner._make_border_fix_reason_key(source_coord, z_level, tag)

func _offset_chunk_coord(coord: Vector2i, offset: Vector2i) -> Vector2i:
	return _owner._offset_chunk_coord(coord, offset)

func _border_dirty_tiles_for_edge(chunk_size: int, edge_dir: Vector2i) -> Dictionary:
	return _owner._border_dirty_tiles_for_edge(chunk_size, edge_dir)

func _ensure_chunk_border_fix_task(chunk: Chunk, z_level: int, invalidate: bool = false) -> void:
	_owner._ensure_chunk_border_fix_task(chunk, z_level, invalidate)

func _append_unique_chunk_coord(coords: Array[Vector2i], coord: Vector2i) -> void:
	_owner._append_unique_chunk_coord(coords, coord)

func _emit_border_fix_queue_diag(
	actor_key: StringName,
	source_coord: Vector2i,
	queued_coords: Array[Vector2i],
	reason_human: String,
	follow_up_terms: Array[String],
	source_tile: Vector2i = Vector2i(999999, 999999)
) -> void:
	_owner._emit_border_fix_queue_diag(actor_key, source_coord, queued_coords, reason_human, follow_up_terms, source_tile)

func _offset_tile(tile_pos: Vector2i, offset: Vector2i) -> Vector2i:
	return _owner._offset_tile(tile_pos, offset)

func _canonical_tile(tile_pos: Vector2i) -> Vector2i:
	return _owner._canonical_tile(tile_pos)

func clear() -> void:
	_pending_refresh_tiles.clear()
	_pending_refresh_lookup.clear()

func pending_count() -> int:
	return _pending_refresh_tiles.size()

func enqueue_neighbor_border_redraws(coord: Vector2i) -> void:
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles
	var active_z: int = _active_z()
	var source_chunk: Chunk = _owner.get_chunk(coord)
	if source_chunk == null:
		return
	var source_version: int = source_chunk.get_visual_invalidation_version()
	var reason_key: String = _make_border_fix_reason_key(coord, active_z, &"stream_load")
	var queued_coords: Array[Vector2i] = []
	var source_dirty_tiles: Dictionary = {}
	for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor_coord: Vector2i = _offset_chunk_coord(coord, dir)
		var neighbor_chunk: Chunk = _owner.get_chunk(neighbor_coord)
		if not neighbor_chunk:
			continue
		source_dirty_tiles.merge(_border_dirty_tiles_for_edge(chunk_size, dir), true)
		var neighbor_dirty_tiles: Dictionary = _border_dirty_tiles_for_edge(chunk_size, -dir)
		neighbor_chunk._mark_cover_edge_set_dirty_tiles(neighbor_dirty_tiles)
		if not neighbor_chunk.is_first_pass_ready():
			continue
		if neighbor_chunk.enqueue_dirty_border_redraw(neighbor_dirty_tiles, reason_key, source_version):
			_ensure_chunk_border_fix_task(neighbor_chunk, active_z, true)
			_append_unique_chunk_coord(queued_coords, neighbor_coord)
	source_chunk._mark_cover_edge_set_dirty_tiles(source_dirty_tiles)
	if source_chunk.is_first_pass_ready() \
		and source_chunk.enqueue_dirty_border_redraw(source_dirty_tiles, reason_key, source_version):
		_ensure_chunk_border_fix_task(source_chunk, active_z, true)
		_append_unique_chunk_coord(queued_coords, coord)
	if not queued_coords.is_empty():
		var follow_up_terms: Array[String] = ["border_fix"]
		_emit_border_fix_queue_diag(
			&"stream_load",
			coord,
			queued_coords,
			"после появления нового чанка нужно выровнять seam-границу и сбросить cover edge cache по обе стороны",
			follow_up_terms
		)

func seam_normalize_and_redraw(tile_pos: Vector2i, local_tile: Vector2i, source_chunk: Chunk) -> void:
	var chunk_size: int = WorldGenerator.balance.chunk_size_tiles
	var on_left: bool = local_tile.x == 0
	var on_right: bool = local_tile.x == chunk_size - 1
	var on_top: bool = local_tile.y == 0
	var on_bottom: bool = local_tile.y == chunk_size - 1
	if not (on_left or on_right or on_top or on_bottom):
		return
	var cross_dirs: Array[Vector2i] = []
	if on_left:
		cross_dirs.append(Vector2i.LEFT)
	if on_right:
		cross_dirs.append(Vector2i.RIGHT)
	if on_top:
		cross_dirs.append(Vector2i.UP)
	if on_bottom:
		cross_dirs.append(Vector2i.DOWN)
	for dir: Vector2i in cross_dirs:
		var neighbor_global: Vector2i = _offset_tile(tile_pos, dir)
		var neighbor_chunk: Chunk = _owner.get_chunk_at_tile(neighbor_global)
		if not neighbor_chunk or neighbor_chunk == source_chunk:
			continue
		_enqueue_refresh_tile(neighbor_global)

func process_queue_step() -> bool:
	if _pending_refresh_tiles.is_empty():
		return false
	var processed_tiles: int = 0
	while processed_tiles < _max_tiles_per_step and not _pending_refresh_tiles.is_empty():
		var tile_pos: Vector2i = _pending_refresh_tiles.pop_front()
		_pending_refresh_lookup.erase(tile_pos)
		_apply_refresh_tile(tile_pos)
		processed_tiles += 1
	return not _pending_refresh_tiles.is_empty()

func _enqueue_refresh_tile(tile_pos: Vector2i) -> void:
	var canonical_tile: Vector2i = _canonical_tile(tile_pos)
	if _pending_refresh_lookup.has(canonical_tile):
		return
	_pending_refresh_lookup[canonical_tile] = true
	_pending_refresh_tiles.append(canonical_tile)

func _apply_refresh_tile(tile_pos: Vector2i) -> void:
	var neighbor_chunk: Chunk = _owner.get_chunk_at_tile(tile_pos)
	if not neighbor_chunk:
		return
	var active_z: int = _active_z()
	var n_local: Vector2i = neighbor_chunk.global_to_local(tile_pos)
	neighbor_chunk.refresh_open_tile_with_operation_cache(n_local)
	neighbor_chunk.is_dirty = true
	if not neighbor_chunk.is_first_pass_ready():
		return
	var chunk_size: int = neighbor_chunk.get_chunk_size()
	var reason_key: String = _make_border_fix_reason_key(neighbor_chunk.chunk_coord, active_z, &"seam_mining_async")
	var reason_version: int = neighbor_chunk.get_visual_invalidation_version()
	var cross_dirty: Dictionary = {n_local: true}
	if n_local.x == 0 or n_local.x == chunk_size - 1:
		for offset_y: int in range(-1, 2):
			var seam_tile: Vector2i = n_local + Vector2i(0, offset_y)
			if neighbor_chunk._is_inside(seam_tile):
				cross_dirty[seam_tile] = true
	if n_local.y == 0 or n_local.y == chunk_size - 1:
		for offset_x: int in range(-1, 2):
			var seam_tile: Vector2i = n_local + Vector2i(offset_x, 0)
			if neighbor_chunk._is_inside(seam_tile):
				cross_dirty[seam_tile] = true
	if not cross_dirty.is_empty() \
		and neighbor_chunk.enqueue_dirty_border_redraw(cross_dirty, reason_key, reason_version):
		_ensure_chunk_border_fix_task(neighbor_chunk, active_z, true)
		var queued_coords: Array[Vector2i] = [neighbor_chunk.chunk_coord]
		var follow_up_terms: Array[String] = ["local_patch", "border_fix"]
		_emit_border_fix_queue_diag(
				&"seam_mining_async",
				neighbor_chunk.chunk_coord,
				queued_coords,
				"добыча на шве изменила открытую границу, поэтому соседнему чанку нужна последующая перерисовка",
			follow_up_terms,
			tile_pos
		)
