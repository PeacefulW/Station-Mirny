class_name MountainRoofSystem
extends Node

## Координирует player-local mountain shell reveal state.
## R1: canonical exterior shell is `cover_layer`; legacy roof cache is no longer reveal authority.

const WorldRuntimeDiagnosticLog = preload("res://core/debug/world_runtime_diagnostic_log.gd")
const INVALID_MOUNTAIN_KEY: Vector2i = Vector2i(999999, 999999)
const _CARDINAL_ZONE_OFFSETS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]
const _ZONE_REVEAL_TILE_OFFSETS := [
	Vector2i.ZERO,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1),
]
const _COVER_APPLY_TIME_BUDGET_USEC: int = 1200
const _COVER_APPLY_MAX_CHUNKS_PER_FRAME: int = 4
const _COVER_APPLY_MAX_REVEAL_TILES_PER_STEP: int = 2

var _chunk_manager: ChunkManager = null
var _player: Player = null
var _last_tile: Vector2i = INVALID_MOUNTAIN_KEY
var _is_player_on_mined_floor: bool = false
var _needs_zone_refresh: bool = false
var _active_local_zone_seed: Vector2i = INVALID_MOUNTAIN_KEY
var _active_local_zone_kind: StringName = &""
var _active_local_zone_tiles: Dictionary = {}
var _active_local_cover_tiles_by_chunk: Dictionary = {}
var _active_local_reveal_chunk_coords: Dictionary = {}
var _active_local_zone_truncated: bool = false
var _cached_zone_seed: Vector2i = INVALID_MOUNTAIN_KEY
var _cached_zone_kind: StringName = &""
var _cached_zone_tiles: Dictionary = {}
var _cached_cover_tiles_by_chunk: Dictionary = {}
var _cached_zone_truncated: bool = false
var _cached_zone_valid: bool = false
var _pending_incremental_mined_tile: Vector2i = INVALID_MOUNTAIN_KEY
var _pending_incremental_affected_chunks: Array[Vector2i] = []
var _pending_incremental_changed_cover_tiles_by_chunk: Dictionary = {}
var _pending_cover_apply_coords: Array[Vector2i] = []
var _pending_cover_apply_lookup: Dictionary = {}
var _pending_cover_apply_payloads: Dictionary = {}

func _ready() -> void:
	EventBus.mountain_tile_mined.connect(_on_mountain_tile_mined)
	EventBus.chunk_loaded.connect(_on_chunk_loaded)
	EventBus.chunk_unloaded.connect(_on_chunk_unloaded)
	call_deferred("_resolve_dependencies")

func _exit_tree() -> void:
	if EventBus.mountain_tile_mined.is_connected(_on_mountain_tile_mined):
		EventBus.mountain_tile_mined.disconnect(_on_mountain_tile_mined)
	if EventBus.chunk_loaded.is_connected(_on_chunk_loaded):
		EventBus.chunk_loaded.disconnect(_on_chunk_loaded)
	if EventBus.chunk_unloaded.is_connected(_on_chunk_unloaded):
		EventBus.chunk_unloaded.disconnect(_on_chunk_unloaded)
	_pending_cover_apply_coords.clear()
	_pending_cover_apply_lookup.clear()
	_pending_cover_apply_payloads.clear()
	_pending_incremental_changed_cover_tiles_by_chunk.clear()
	_chunk_manager = null
	_player = null

func _process(_delta: float) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	if _needs_zone_refresh:
		_needs_zone_refresh = false
		_request_refresh(true)
	_check_player_mountain_state()
	_drain_cover_apply_queue()

func _resolve_dependencies() -> void:
	var chunks: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if not chunks.is_empty():
		_chunk_manager = chunks[0] as ChunkManager
	_player = PlayerAuthority.get_local_player()
	_request_refresh()

func _check_player_mountain_state() -> void:
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	if player_tile == _last_tile:
		return
	_last_tile = player_tile
	var is_on_mined_floor: bool = _is_player_on_opened_mountain_tile(player_tile)
	if is_on_mined_floor == _is_player_on_mined_floor and (not is_on_mined_floor or _has_active_local_zone()):
		if is_on_mined_floor and not _active_local_zone_tiles.has(player_tile):
			_request_refresh(true)
		return
	_is_player_on_mined_floor = is_on_mined_floor
	_request_refresh()

func _request_refresh(force_refresh: bool = false) -> void:
	var started_usec: int = WorldPerfProbe.begin()
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	# Surface-only system. Skip underground (ADR-0006).
	if _chunk_manager.get_active_z_level() != 0:
		return
	var previous_cover_tiles_by_chunk: Dictionary = _active_local_cover_tiles_by_chunk
	_pending_incremental_changed_cover_tiles_by_chunk = {}
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var start_tile: Vector2i = _find_reveal_start(player_tile)
	if start_tile == INVALID_MOUNTAIN_KEY:
		_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
		_pending_incremental_affected_chunks = []
		_clear_active_local_zone()
	else:
		if not _try_apply_incremental_zone_refresh(start_tile) \
			and not _try_bootstrap_single_tile_zone(start_tile) \
			and not _try_restore_cached_zone(start_tile):
			_refresh_active_local_zone(start_tile)
	WorldPerfProbe.end("MountainRoofSystem._request_refresh", started_usec)
	var affected_chunks: Array[Vector2i] = _pending_incremental_affected_chunks
	var changed_cover_tiles_by_chunk: Dictionary = _pending_incremental_changed_cover_tiles_by_chunk
	if changed_cover_tiles_by_chunk.is_empty():
		var diff_usec: int = WorldPerfProbe.begin()
		changed_cover_tiles_by_chunk = _collect_changed_cover_tiles_by_chunk(
			previous_cover_tiles_by_chunk,
			_active_local_cover_tiles_by_chunk
		)
		WorldPerfProbe.end("MountainRoofSystem._collect_changed_cover_tiles_by_chunk", diff_usec)
	if affected_chunks.is_empty():
		if not changed_cover_tiles_by_chunk.is_empty():
			affected_chunks = _collect_chunk_coords_from_changed_cover_tiles(changed_cover_tiles_by_chunk)
		else:
			var affected_usec: int = WorldPerfProbe.begin()
			affected_chunks = _collect_affected_chunk_coords(previous_cover_tiles_by_chunk)
			WorldPerfProbe.end("MountainRoofSystem._collect_affected_chunk_coords", affected_usec)
	_pending_incremental_affected_chunks = []
	_pending_incremental_changed_cover_tiles_by_chunk = {}
	if affected_chunks.is_empty():
		return
	_queue_reveal_state_apply(affected_chunks, changed_cover_tiles_by_chunk)

func _try_apply_immediate_mining_reveal_patch() -> bool:
	var started_usec: int = WorldPerfProbe.begin()
	var applied: bool = false
	if _pending_incremental_mined_tile != INVALID_MOUNTAIN_KEY:
		var start_tile: Vector2i = _find_mining_refresh_start()
		if start_tile != INVALID_MOUNTAIN_KEY:
			_pending_incremental_affected_chunks = []
			_pending_incremental_changed_cover_tiles_by_chunk = {}
			if _try_apply_incremental_zone_refresh(start_tile) \
				or _try_bootstrap_single_tile_zone(start_tile):
				var affected_chunks: Array[Vector2i] = _pending_incremental_affected_chunks
				var changed_cover_tiles_by_chunk: Dictionary = _pending_incremental_changed_cover_tiles_by_chunk
				_pending_incremental_affected_chunks = []
				_pending_incremental_changed_cover_tiles_by_chunk = {}
				if affected_chunks.is_empty() and not changed_cover_tiles_by_chunk.is_empty():
					affected_chunks = _collect_chunk_coords_from_changed_cover_tiles(
						changed_cover_tiles_by_chunk
					)
				_apply_cover_state_immediately(affected_chunks, changed_cover_tiles_by_chunk)
				if _active_local_zone_truncated:
					_emit_roof_local_patch_diag(start_tile, affected_chunks, changed_cover_tiles_by_chunk)
				applied = true
	WorldPerfProbe.end("MountainRoofSystem._try_apply_immediate_mining_reveal_patch", started_usec)
	return applied

func _apply_cover_state_immediately(
	affected_chunks: Array[Vector2i],
	changed_cover_tiles_by_chunk: Dictionary
) -> void:
	for coord: Vector2i in affected_chunks:
		var chunk: Chunk = _chunk_manager.get_chunk(coord)
		if not chunk:
			_remove_pending_cover_apply_coord(coord)
			continue
		var next_cover_tiles: Dictionary = _active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		var changed_tiles: Dictionary = changed_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		if not chunk.is_first_pass_ready():
			chunk.prime_revealed_local_cover_tiles(next_cover_tiles)
		elif not changed_tiles.is_empty():
			var apply_usec: int = WorldPerfProbe.begin()
			chunk.apply_revealed_local_cover_tiles_batch(next_cover_tiles, changed_tiles)
			WorldPerfProbe.end("MountainRoofSystem._apply_immediate_cover_patch %s" % [coord], apply_usec)
		_enqueue_cover_apply_coord(coord, next_cover_tiles)

func _queue_reveal_state_apply(
	affected_chunks: Array[Vector2i],
	changed_cover_tiles_by_chunk: Dictionary = {}
) -> void:
	for coord: Vector2i in affected_chunks:
		_enqueue_cover_apply_coord(
			coord,
			_active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary,
			changed_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		)

func _enqueue_cover_apply_coord(
	coord: Vector2i,
	next_cover_tiles: Dictionary = {},
	changed_tiles: Dictionary = {}
) -> void:
	if coord == INVALID_MOUNTAIN_KEY:
		return
	var existing_payload: Dictionary = _pending_cover_apply_payloads.get(coord, {}) as Dictionary
	var target_cover_tiles: Dictionary = _duplicate_tile_set(next_cover_tiles)
	var effective_changed_tiles: Dictionary = _duplicate_tile_set(changed_tiles)
	if effective_changed_tiles.is_empty() or not existing_payload.is_empty():
		var chunk: Chunk = _chunk_manager.get_chunk(coord) if _chunk_manager else null
		var live_cover_tiles: Dictionary = chunk.get_revealed_local_cover_tiles() if chunk else {}
		effective_changed_tiles = _collect_changed_cover_tiles(live_cover_tiles, target_cover_tiles)
	if effective_changed_tiles.is_empty():
		_remove_pending_cover_apply_coord(coord)
		return
	var payload: Dictionary = {
		"chunk_coord": coord,
		"next_cover_tiles": target_cover_tiles,
		"changed_tiles": effective_changed_tiles,
		"is_full_apply": false,
	}
	_initialize_cover_apply_tile_queue(payload)
	_pending_cover_apply_payloads[coord] = payload
	if _pending_cover_apply_lookup.has(coord):
		return
	_pending_cover_apply_lookup[coord] = true
	_pending_cover_apply_coords.append(coord)

func _remove_pending_cover_apply_coord(coord: Vector2i) -> void:
	if not _pending_cover_apply_lookup.has(coord):
		return
	_pending_cover_apply_lookup.erase(coord)
	_pending_cover_apply_payloads.erase(coord)
	var idx: int = _pending_cover_apply_coords.find(coord)
	if idx != -1:
		_pending_cover_apply_coords.remove_at(idx)

func _drain_cover_apply_queue() -> void:
	if _pending_cover_apply_coords.is_empty() or _chunk_manager.get_active_z_level() != 0:
		return
	var started_usec: int = Time.get_ticks_usec()
	var processed_chunks: int = 0
	while processed_chunks < _COVER_APPLY_MAX_CHUNKS_PER_FRAME \
		and not _pending_cover_apply_coords.is_empty():
		if Time.get_ticks_usec() - started_usec >= _COVER_APPLY_TIME_BUDGET_USEC:
			return
		var coord: Vector2i = _pop_next_cover_apply_coord()
		if coord == INVALID_MOUNTAIN_KEY:
			return
		_apply_cover_state_to_chunk(coord)
		processed_chunks += 1

func _pop_next_cover_apply_coord() -> Vector2i:
	if _pending_cover_apply_coords.is_empty():
		return INVALID_MOUNTAIN_KEY
	var best_idx: int = 0
	var best_score: int = _cover_apply_priority_score(_pending_cover_apply_coords[0])
	for idx: int in range(1, _pending_cover_apply_coords.size()):
		var score: int = _cover_apply_priority_score(_pending_cover_apply_coords[idx])
		if score < best_score:
			best_idx = idx
			best_score = score
	var coord: Vector2i = _pending_cover_apply_coords[best_idx]
	_pending_cover_apply_coords.remove_at(best_idx)
	_pending_cover_apply_lookup.erase(coord)
	return coord

func _cover_apply_priority_score(coord: Vector2i) -> int:
	if not _player or not WorldGenerator:
		return 0
	var player_chunk: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	return absi(coord.x - player_chunk.x) + absi(coord.y - player_chunk.y)

func _resolve_roof_diag_scope(coord: Vector2i) -> StringName:
	if not _player or not WorldGenerator:
		return &"far_runtime_backlog"
	var player_chunk: Vector2i = WorldGenerator.world_to_chunk(_player.global_position)
	if coord == player_chunk:
		return &"player_chunk"
	var dx: int = coord.x - player_chunk.x
	if WorldGenerator.has_method("chunk_wrap_delta_x"):
		dx = WorldGenerator.chunk_wrap_delta_x(coord.x, player_chunk.x)
	var dy: int = coord.y - player_chunk.y
	if maxi(absi(dx), absi(dy)) <= 1:
		return &"adjacent_loaded_chunk"
	return &"far_runtime_backlog"

func _resolve_roof_diag_impact(scope: StringName) -> StringName:
	if scope == &"far_runtime_backlog":
		return WorldRuntimeDiagnosticLog.IMPACT_BACKGROUND_DEBT
	return WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE

func _pick_roof_diag_target_coord(coords: Array[Vector2i]) -> Vector2i:
	if coords.is_empty():
		return WorldGenerator.world_to_chunk(_player.global_position) if _player and WorldGenerator else Vector2i.ZERO
	var best_coord: Vector2i = coords[0]
	var best_score: int = 1_000_000
	for coord: Vector2i in coords:
		var score: int = _cover_apply_priority_score(coord)
		if score < best_score:
			best_score = score
			best_coord = coord
	return best_coord

func _count_cover_tiles_by_chunk(tile_map: Dictionary) -> int:
	var tile_count: int = 0
	for coord_variant: Variant in tile_map.keys():
		tile_count += (tile_map.get(coord_variant, {}) as Dictionary).size()
	return tile_count

func _emit_roof_local_patch_diag(
	start_tile: Vector2i,
	affected_chunks: Array[Vector2i],
	changed_cover_tiles_by_chunk: Dictionary
) -> void:
	var target_coord: Vector2i = _pick_roof_diag_target_coord(affected_chunks)
	var scope: StringName = _resolve_roof_diag_scope(target_coord)
	var impact_key: StringName = _resolve_roof_diag_impact(scope)
	var severity_key: StringName = WorldRuntimeDiagnosticLog.SEVERITY_FOLLOW_UP
	if impact_key == WorldRuntimeDiagnosticLog.IMPACT_PLAYER_VISIBLE:
		severity_key = WorldRuntimeDiagnosticLog.SEVERITY_ROOT_CAUSE
	var record: Dictionary = {
		"actor": "local_patch",
		"actor_human": "Локальная правка после изменения тайла",
		"action": "recalculate_roof_state",
		"action_human": "пересчитала крышу вокруг изменённого тайла",
		"target": String(scope),
		"target_human": WorldRuntimeDiagnosticLog.describe_chunk_scope(scope, target_coord),
		"reason": "wrong_state_calculated",
		"reason_human": "зона уткнулась в незагруженную границу, поэтому часть состояния пока может быть неполной",
		"impact": String(impact_key),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact_key),
		"state": "applied",
		"state_human": "локальный патч уже применён, но итог ещё может измениться",
		"severity": String(severity_key),
		"severity_human": WorldRuntimeDiagnosticLog.humanize_severity(severity_key),
		"code": "local_patch",
	}
	var detail_fields: Dictionary = {
		"affected_chunks": WorldRuntimeDiagnosticLog.format_coord_list(affected_chunks),
		"affected_count": affected_chunks.size(),
		"changed_cover_tiles": _count_cover_tiles_by_chunk(changed_cover_tiles_by_chunk),
		"start_tile": str(start_tile),
		"target_chunk": str(target_coord),
		"truncated": _active_local_zone_truncated,
		"zone_kind": String(_active_local_zone_kind),
		"zone_seed": str(_active_local_zone_seed),
	}
	WorldRuntimeDiagnosticLog.emit_record(record, detail_fields)

func _emit_roof_restore_overwrite_diag(
	coord: Vector2i,
	restore_tile_count: int,
	next_cover_tiles: Dictionary
) -> void:
	var scope: StringName = _resolve_roof_diag_scope(coord)
	var impact_key: StringName = _resolve_roof_diag_impact(scope)
	var record: Dictionary = {
		"actor": "roof_restore",
		"actor_human": "Восстановление крыши",
		"action": "queue_follow_up",
		"action_human": "передало восстановление в очередь правки границы",
		"target": String(scope),
		"target_human": WorldRuntimeDiagnosticLog.describe_chunk_scope(scope, coord),
		"reason": "later_overwrite",
		"reason_human": "сначала вернулось промежуточное состояние восстановления, а финальную картинку позже перезапишет owner чанка",
		"impact": String(impact_key),
		"impact_human": WorldRuntimeDiagnosticLog.humanize_impact(impact_key),
		"state": "queued",
		"state_human": "ожидает позднее переопределение owner-путём",
		"severity": String(WorldRuntimeDiagnosticLog.SEVERITY_FOLLOW_UP),
		"severity_human": WorldRuntimeDiagnosticLog.humanize_severity(WorldRuntimeDiagnosticLog.SEVERITY_FOLLOW_UP),
		"code": "border_fix",
	}
	var detail_fields: Dictionary = {
		"chunk": str(coord),
		"follow_up": "border_fix",
		"next_cover_tiles": next_cover_tiles.size(),
		"restore_tiles": restore_tile_count,
		"target_scope": String(scope),
	}
	WorldRuntimeDiagnosticLog.emit_record(record, detail_fields)

func _apply_cover_state_to_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = _chunk_manager.get_chunk(coord)
	if not chunk:
		return
	var payload: Dictionary = _pending_cover_apply_payloads.get(coord, {}) as Dictionary
	var next_cover_tiles: Dictionary = _active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary
	if not payload.is_empty():
		next_cover_tiles = payload.get("next_cover_tiles", next_cover_tiles) as Dictionary
	if not chunk.is_first_pass_ready():
		chunk.prime_revealed_local_cover_tiles(next_cover_tiles)
		_pending_cover_apply_payloads.erase(coord)
		return
	if _payload_is_restore_only(payload):
		var restore_tiles: Dictionary = payload.get("changed_tiles", {}) as Dictionary
		if chunk.defer_revealed_local_cover_tiles_restore(restore_tiles):
			_chunk_manager._ensure_chunk_border_fix_task(
				chunk,
				_chunk_manager.get_active_z_level()
			)
			_emit_roof_restore_overwrite_diag(coord, restore_tiles.size(), next_cover_tiles)
		elif not restore_tiles.is_empty():
			chunk.apply_revealed_local_cover_tiles_batch(next_cover_tiles, restore_tiles)
		_pending_cover_apply_payloads.erase(coord)
		return
	var apply_tiles: Dictionary = _consume_cover_apply_step_tiles(payload)
	if apply_tiles.is_empty():
		_pending_cover_apply_payloads.erase(coord)
		return
	var reveal_step_tiles: Dictionary = {}
	var restore_step_tiles: Dictionary = {}
	for local_tile: Vector2i in apply_tiles:
		if next_cover_tiles.has(local_tile):
			reveal_step_tiles[local_tile] = true
		else:
			restore_step_tiles[local_tile] = true
	if not restore_step_tiles.is_empty():
		if chunk.defer_revealed_local_cover_tiles_restore(restore_step_tiles):
			_chunk_manager._ensure_chunk_border_fix_task(
				chunk,
				_chunk_manager.get_active_z_level()
			)
			_emit_roof_restore_overwrite_diag(coord, restore_step_tiles.size(), next_cover_tiles)
		else:
			chunk.apply_revealed_local_cover_tiles_batch(next_cover_tiles, restore_step_tiles)
	if not reveal_step_tiles.is_empty():
		var cover_step_usec: int = WorldPerfProbe.begin()
		chunk.apply_revealed_local_cover_tiles_batch(next_cover_tiles, reveal_step_tiles)
		WorldPerfProbe.end("MountainRoofSystem._process_cover_step %s" % [coord], cover_step_usec)
	if (payload.get("changed_tiles", {}) as Dictionary).is_empty():
		_pending_cover_apply_payloads.erase(coord)
		return
	_pending_cover_apply_payloads[coord] = payload
	_requeue_cover_apply_coord(coord)

func _consume_cover_apply_step_tiles(payload: Dictionary) -> Dictionary:
	var remaining_changed_tiles: Dictionary = payload.get("changed_tiles", {}) as Dictionary
	if remaining_changed_tiles.is_empty():
		return {}
	var step_tiles: Dictionary = {}
	_consume_cover_apply_tile_queue(
		payload,
		"reveal_tiles",
		"reveal_index",
		_COVER_APPLY_MAX_REVEAL_TILES_PER_STEP,
		step_tiles,
		remaining_changed_tiles
	)
	# Restore tiles are intentionally excluded from the synchronous cover step.
	# Once reveal tiles drain, the next pass hits _payload_is_restore_only() and
	# hands the remaining restore payload to the chunk-local queued redraw path.
	payload["changed_tiles"] = remaining_changed_tiles
	return step_tiles

func _initialize_cover_apply_tile_queue(payload: Dictionary) -> void:
	var target_cover_tiles: Dictionary = payload.get("next_cover_tiles", {}) as Dictionary
	var changed_tiles: Dictionary = payload.get("changed_tiles", {}) as Dictionary
	var reveal_tiles: Array[Vector2i] = []
	var restore_tiles: Array[Vector2i] = []
	for tile_variant: Variant in changed_tiles.keys():
		var local_tile: Vector2i = tile_variant as Vector2i
		if target_cover_tiles.has(local_tile):
			reveal_tiles.append(local_tile)
		else:
			restore_tiles.append(local_tile)
	if reveal_tiles.size() <= 32:
		reveal_tiles.sort_custom(_sort_cover_apply_tiles.bind(payload))
	if restore_tiles.size() <= 32:
		restore_tiles.sort_custom(_sort_cover_apply_tiles.bind(payload))
	payload["reveal_tiles"] = reveal_tiles
	payload["restore_tiles"] = restore_tiles
	payload["reveal_index"] = 0
	payload["restore_index"] = 0

func _payload_is_restore_only(payload: Dictionary) -> bool:
	var remaining_changed_tiles: Dictionary = payload.get("changed_tiles", {}) as Dictionary
	if remaining_changed_tiles.is_empty():
		return false
	var reveal_tiles: Array[Vector2i] = payload.get("reveal_tiles", []) as Array[Vector2i]
	var reveal_index: int = int(payload.get("reveal_index", 0))
	return reveal_index >= reveal_tiles.size()

func _consume_cover_apply_tile_queue(
	payload: Dictionary,
	queue_key: String,
	index_key: String,
	budget: int,
	step_tiles: Dictionary,
	remaining_changed_tiles: Dictionary
) -> void:
	if budget <= 0:
		return
	var queue: Array[Vector2i] = payload.get(queue_key, []) as Array[Vector2i]
	var queue_index: int = int(payload.get(index_key, 0))
	while budget > 0 and queue_index < queue.size():
		var local_tile: Vector2i = queue[queue_index]
		queue_index += 1
		if not remaining_changed_tiles.has(local_tile):
			continue
		step_tiles[local_tile] = true
		remaining_changed_tiles.erase(local_tile)
		budget -= 1
	payload[index_key] = queue_index

func _sort_cover_apply_tiles(a: Vector2i, b: Vector2i, payload: Dictionary) -> bool:
	var coord: Vector2i = payload.get("chunk_coord", INVALID_MOUNTAIN_KEY) as Vector2i
	var target_cover_tiles: Dictionary = payload.get("next_cover_tiles", {}) as Dictionary
	var a_reveal: bool = target_cover_tiles.has(a)
	var b_reveal: bool = target_cover_tiles.has(b)
	if a_reveal != b_reveal:
		return a_reveal and not b_reveal
	var a_score: int = _cover_apply_tile_priority_score(coord, a)
	var b_score: int = _cover_apply_tile_priority_score(coord, b)
	if a_score != b_score:
		return a_score < b_score
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x

func _cover_apply_tile_priority_score(chunk_coord: Vector2i, local_tile: Vector2i) -> int:
	if not _player or not WorldGenerator:
		return local_tile.x + local_tile.y * 1024
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	var global_tile: Vector2i = WorldGenerator.chunk_to_tile_origin(chunk_coord) + local_tile
	return absi(global_tile.x - player_tile.x) + absi(global_tile.y - player_tile.y)

func _requeue_cover_apply_coord(coord: Vector2i) -> void:
	if _pending_cover_apply_lookup.has(coord):
		return
	_pending_cover_apply_lookup[coord] = true
	_pending_cover_apply_coords.insert(0, coord)

func _find_reveal_start(player_tile: Vector2i) -> Vector2i:
	var mined_tile_start: Vector2i = _find_mining_refresh_start()
	if mined_tile_start != INVALID_MOUNTAIN_KEY:
		return mined_tile_start
	if _is_player_on_opened_mountain_tile(player_tile):
		return player_tile
	return INVALID_MOUNTAIN_KEY

func _find_mining_refresh_start() -> Vector2i:
	if _pending_incremental_mined_tile == INVALID_MOUNTAIN_KEY:
		return INVALID_MOUNTAIN_KEY
	var mined_tile: Vector2i = _pending_incremental_mined_tile
	if _should_reuse_active_zone_seed(mined_tile):
		if _active_local_zone_seed != INVALID_MOUNTAIN_KEY:
			return _active_local_zone_seed
		return mined_tile
	if _is_open_mountain_tile(mined_tile):
		return mined_tile
	return INVALID_MOUNTAIN_KEY

func _should_reuse_active_zone_seed(tile_pos: Vector2i) -> bool:
	if not _has_active_local_zone():
		return false
	if _active_local_zone_tiles.has(tile_pos):
		return true
	for offset: Vector2i in _CARDINAL_ZONE_OFFSETS:
		if _active_local_zone_tiles.has(WorldGenerator.offset_tile(tile_pos, offset)):
			return true
	return false

func _is_player_on_opened_mountain_tile(player_tile: Vector2i) -> bool:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(player_tile)
	if not chunk:
		return false
	var local_tile: Vector2i = chunk.global_to_local(player_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	return terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _on_mountain_tile_mined(tile_pos: Vector2i, _old_type: int, new_type: int) -> void:
	if not _chunk_manager or not _player or not WorldGenerator:
		return
	_invalidate_cached_zone()
	if new_type == TileGenData.TerrainType.MINED_FLOOR \
		or new_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
		_pending_incremental_mined_tile = WorldGenerator.canonicalize_tile(tile_pos)
	else:
		_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	var applied_immediate_patch: bool = _try_apply_immediate_mining_reveal_patch()
	var player_tile: Vector2i = WorldGenerator.world_to_tile(_player.global_position)
	_needs_zone_refresh = not applied_immediate_patch and (
		_pending_incremental_mined_tile != INVALID_MOUNTAIN_KEY \
		or _is_player_on_opened_mountain_tile(player_tile)
	)

func _on_chunk_loaded(coord: Vector2i) -> void:
	if coord == Vector2i(999999, 999999):
		return
	if _cached_zone_valid and _cached_zone_truncated:
		_invalidate_cached_zone()
	if _has_active_local_zone():
		if _active_local_reveal_chunk_coords.has(coord):
			var chunk: Chunk = _chunk_manager.get_chunk(coord)
			var next_cover_tiles: Dictionary = _active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary
			if chunk and not chunk.is_first_pass_ready():
				chunk.prime_revealed_local_cover_tiles(next_cover_tiles)
			else:
				_enqueue_cover_apply_coord(coord, next_cover_tiles)
		if _active_local_zone_truncated:
			_needs_zone_refresh = true

func _on_chunk_unloaded(coord: Vector2i) -> void:
	if coord == Vector2i(999999, 999999):
		return
	_remove_pending_cover_apply_coord(coord)
	if _cached_zone_valid and _cached_cover_tiles_by_chunk.has(coord):
		_invalidate_cached_zone()
	if _has_active_local_zone():
		if _active_local_reveal_chunk_coords.has(coord) or _active_local_zone_truncated:
			_needs_zone_refresh = true

func _refresh_active_local_zone(seed_tile: Vector2i) -> void:
	if not _chunk_manager:
		_clear_active_local_zone()
		return
	var started_usec: int = WorldPerfProbe.begin()
	var zone: Dictionary = _query_surface_reveal_zone(seed_tile)
	if zone.is_empty():
		_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
		_clear_active_local_zone()
		WorldPerfProbe.end("MountainRoofSystem._refresh_local_zone", started_usec)
		return
	_active_local_zone_seed = zone.get("seed_tile", INVALID_MOUNTAIN_KEY)
	_active_local_zone_kind = zone.get("zone_kind", &"") as StringName
	_active_local_zone_tiles = zone.get("tiles", {}) as Dictionary
	var cover_build_usec: int = WorldPerfProbe.begin()
	_active_local_cover_tiles_by_chunk = _build_local_cover_tiles_by_chunk(_active_local_zone_tiles)
	_active_local_reveal_chunk_coords = _active_local_cover_tiles_by_chunk
	WorldPerfProbe.end("MountainRoofSystem._build_cover_tiles_by_chunk", cover_build_usec)
	_active_local_zone_truncated = bool(zone.get("truncated", false))
	_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	_cache_active_zone_state()
	WorldPerfProbe.end("MountainRoofSystem._refresh_local_zone", started_usec)

func _query_surface_reveal_zone(seed_tile: Vector2i) -> Dictionary:
	var topology_zone: Dictionary = _query_topology_local_open_zone(seed_tile)
	if not topology_zone.is_empty():
		return topology_zone
	return _chunk_manager.query_local_underground_zone(seed_tile)

func _query_topology_local_open_zone(seed_tile: Vector2i) -> Dictionary:
	if not _chunk_manager or not WorldGenerator:
		return {}
	seed_tile = WorldGenerator.canonicalize_tile(seed_tile)
	if not _chunk_manager.is_tile_loaded(seed_tile):
		return {}
	if not _is_open_mountain_tile(seed_tile):
		return {}
	var mountain_key: Vector2i = _chunk_manager.get_mountain_key_at_tile(seed_tile)
	if mountain_key == INVALID_MOUNTAIN_KEY:
		return {}
	var open_tiles: Dictionary = _chunk_manager.get_mountain_open_tiles(mountain_key)
	if open_tiles.is_empty() or not open_tiles.has(seed_tile):
		return {}
	var visited: Dictionary = {seed_tile: true}
	var queue: Array[Vector2i] = [seed_tile]
	var queue_index: int = 0
	var zone_tiles: Dictionary = {}
	var chunk_coords: Dictionary = {}
	var truncated: bool = false
	while queue_index < queue.size():
		var current_tile: Vector2i = queue[queue_index]
		queue_index += 1
		zone_tiles[current_tile] = true
		chunk_coords[WorldGenerator.tile_to_chunk(current_tile)] = true
		for offset: Vector2i in _CARDINAL_ZONE_OFFSETS:
			var next_tile: Vector2i = WorldGenerator.offset_tile(current_tile, offset)
			if visited.has(next_tile):
				continue
			if not _chunk_manager.is_tile_loaded(next_tile):
				truncated = true
				continue
			if not open_tiles.has(next_tile):
				continue
			visited[next_tile] = true
			queue.append(next_tile)
	var chunk_coord_list: Array[Vector2i] = []
	for coord: Vector2i in chunk_coords:
		chunk_coord_list.append(coord)
	return {
		"zone_kind": &"topology_open_pocket",
		"seed_tile": seed_tile,
		"tiles": zone_tiles,
		"chunk_coords": chunk_coord_list,
		"truncated": truncated,
	}

func _clear_active_local_zone() -> void:
	_active_local_zone_seed = INVALID_MOUNTAIN_KEY
	_active_local_zone_kind = &""
	_active_local_zone_tiles = {}
	_active_local_cover_tiles_by_chunk = {}
	_active_local_reveal_chunk_coords = {}
	_active_local_zone_truncated = false

func _collect_affected_chunk_coords(previous_cover_tiles_by_chunk: Dictionary) -> Array[Vector2i]:
	var affected_chunks: Array[Vector2i] = []
	var seen_coords: Dictionary = {}
	for coord: Vector2i in previous_cover_tiles_by_chunk:
		seen_coords[coord] = true
	for coord: Vector2i in _active_local_cover_tiles_by_chunk:
		seen_coords[coord] = true
	for coord: Vector2i in seen_coords:
		var previous_cover_tiles: Dictionary = previous_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		var next_cover_tiles: Dictionary = _active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		if previous_cover_tiles != next_cover_tiles:
			affected_chunks.append(coord)
	return affected_chunks

func _collect_chunk_coords_from_changed_cover_tiles(changed_cover_tiles_by_chunk: Dictionary) -> Array[Vector2i]:
	var affected_chunks: Array[Vector2i] = []
	for coord: Vector2i in changed_cover_tiles_by_chunk:
		var changed_tiles: Dictionary = changed_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		if changed_tiles.is_empty():
			continue
		affected_chunks.append(coord)
	return affected_chunks

func _collect_changed_cover_tiles_by_chunk(
	previous_cover_tiles_by_chunk: Dictionary,
	next_cover_tiles_by_chunk: Dictionary
) -> Dictionary:
	var changed_tiles_by_chunk: Dictionary = {}
	var seen_coords: Dictionary = {}
	for coord: Vector2i in previous_cover_tiles_by_chunk:
		seen_coords[coord] = true
	for coord: Vector2i in next_cover_tiles_by_chunk:
		seen_coords[coord] = true
	for coord: Vector2i in seen_coords:
		var previous_cover_tiles: Dictionary = previous_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		var next_cover_tiles: Dictionary = next_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		var chunk_changed_tiles: Dictionary = _collect_changed_cover_tiles(
			previous_cover_tiles,
			next_cover_tiles
		)
		if not chunk_changed_tiles.is_empty():
			changed_tiles_by_chunk[coord] = chunk_changed_tiles
	return changed_tiles_by_chunk

func _collect_changed_cover_tiles(
	previous_cover_tiles: Dictionary,
	next_cover_tiles: Dictionary
) -> Dictionary:
	if previous_cover_tiles.is_empty():
		return next_cover_tiles.duplicate()
	if next_cover_tiles.is_empty():
		return previous_cover_tiles.duplicate()
	var changed_tiles: Dictionary = {}
	for local_tile: Vector2i in previous_cover_tiles:
		if next_cover_tiles.has(local_tile):
			continue
		changed_tiles[local_tile] = true
	for local_tile: Vector2i in next_cover_tiles:
		if previous_cover_tiles.has(local_tile):
			continue
		changed_tiles[local_tile] = true
	return changed_tiles

func _collect_changed_chunk_coords(
	previous_cover_tiles_by_chunk: Dictionary,
	chunk_coords: Dictionary
) -> Array[Vector2i]:
	var affected_chunks: Array[Vector2i] = []
	for coord: Vector2i in chunk_coords:
		var previous_cover_tiles: Dictionary = previous_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		var next_cover_tiles: Dictionary = _active_local_cover_tiles_by_chunk.get(coord, {}) as Dictionary
		if previous_cover_tiles != next_cover_tiles:
			affected_chunks.append(coord)
	return affected_chunks

func _has_active_local_zone() -> bool:
	return _active_local_zone_seed != INVALID_MOUNTAIN_KEY and not _active_local_zone_tiles.is_empty()

func _try_apply_incremental_zone_refresh(start_tile: Vector2i) -> bool:
	if _pending_incremental_mined_tile == INVALID_MOUNTAIN_KEY:
		return false
	if not _has_active_local_zone():
		return false
	if not _active_local_zone_tiles.has(start_tile):
		return false
	var mined_tile: Vector2i = _pending_incremental_mined_tile
	if not _can_incrementally_extend_active_zone(mined_tile):
		return false
	var zone_was_truncated: bool = _active_local_zone_truncated
	var next_zone_tiles: Dictionary = _active_local_zone_tiles.duplicate()
	var previous_cover_tiles_by_chunk: Dictionary = _active_local_cover_tiles_by_chunk
	next_zone_tiles[mined_tile] = true
	_active_local_zone_tiles = next_zone_tiles
	var incremental_result: Dictionary = _build_incremental_cover_tiles_by_chunk(
		previous_cover_tiles_by_chunk,
		mined_tile
	)
	_active_local_cover_tiles_by_chunk = incremental_result.get("cover_tiles_by_chunk", {}) as Dictionary
	_active_local_reveal_chunk_coords = _active_local_cover_tiles_by_chunk
	_pending_incremental_changed_cover_tiles_by_chunk = incremental_result.get(
		"changed_tiles_by_chunk",
		{}
	) as Dictionary
	_pending_incremental_affected_chunks = _collect_chunk_coords_from_changed_cover_tiles(
		_pending_incremental_changed_cover_tiles_by_chunk
	)
	_active_local_zone_truncated = zone_was_truncated or _zone_tile_touches_unloaded_boundary(mined_tile)
	_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	_cache_active_zone_state()
	return true

func _try_bootstrap_single_tile_zone(start_tile: Vector2i) -> bool:
	if _pending_incremental_mined_tile == INVALID_MOUNTAIN_KEY:
		return false
	if _has_active_local_zone():
		return false
	if start_tile != _pending_incremental_mined_tile:
		return false
	if not _is_open_mountain_tile(start_tile):
		return false
	for offset: Vector2i in _CARDINAL_ZONE_OFFSETS:
		var neighbor_tile: Vector2i = WorldGenerator.offset_tile(start_tile, offset)
		if not _chunk_manager.is_tile_loaded(neighbor_tile):
			continue
		if _is_open_mountain_tile(neighbor_tile):
			return false
	_active_local_zone_seed = start_tile
	_active_local_zone_kind = &"mined_tile_bootstrap"
	_active_local_zone_tiles = {start_tile: true}
	var bootstrap_result: Dictionary = _build_incremental_cover_tiles_by_chunk({}, start_tile)
	_active_local_cover_tiles_by_chunk = bootstrap_result.get("cover_tiles_by_chunk", {}) as Dictionary
	_active_local_reveal_chunk_coords = _active_local_cover_tiles_by_chunk
	_pending_incremental_changed_cover_tiles_by_chunk = bootstrap_result.get(
		"changed_tiles_by_chunk",
		{}
	) as Dictionary
	_pending_incremental_affected_chunks = _collect_chunk_coords_from_changed_cover_tiles(
		_pending_incremental_changed_cover_tiles_by_chunk
	)
	_active_local_zone_truncated = _zone_tile_touches_unloaded_boundary(start_tile)
	_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	_cache_active_zone_state()
	return true

func _try_restore_cached_zone(start_tile: Vector2i) -> bool:
	if not _cached_zone_valid or not _cached_zone_tiles.has(start_tile):
		return false
	_active_local_zone_seed = _cached_zone_seed
	_active_local_zone_kind = _cached_zone_kind
	_active_local_zone_tiles = _cached_zone_tiles
	_active_local_cover_tiles_by_chunk = _cached_cover_tiles_by_chunk
	_active_local_reveal_chunk_coords = _active_local_cover_tiles_by_chunk
	_active_local_zone_truncated = _cached_zone_truncated
	_pending_incremental_mined_tile = INVALID_MOUNTAIN_KEY
	return true

func _can_incrementally_extend_active_zone(tile_pos: Vector2i) -> bool:
	if _active_local_zone_tiles.has(tile_pos):
		return false
	if not _is_open_mountain_tile(tile_pos):
		return false
	var has_active_neighbor: bool = false
	for offset: Vector2i in _CARDINAL_ZONE_OFFSETS:
		var neighbor_tile: Vector2i = WorldGenerator.offset_tile(tile_pos, offset)
		if _active_local_zone_tiles.has(neighbor_tile):
			has_active_neighbor = true
			continue
		if _is_open_mountain_tile(neighbor_tile):
			return false
	return has_active_neighbor

func _zone_tile_touches_unloaded_boundary(tile_pos: Vector2i) -> bool:
	if not _chunk_manager:
		return false
	for offset: Vector2i in _CARDINAL_ZONE_OFFSETS:
		var neighbor_tile: Vector2i = WorldGenerator.offset_tile(tile_pos, offset)
		if not _chunk_manager.is_tile_loaded(neighbor_tile):
			return true
	return false

func _is_open_mountain_tile(global_tile: Vector2i) -> bool:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(global_tile)
	if not chunk:
		return false
	var local_tile: Vector2i = chunk.global_to_local(global_tile)
	var terrain_type: int = chunk.get_terrain_type_at(local_tile)
	return terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

func _cache_active_zone_state() -> void:
	_cached_zone_seed = _active_local_zone_seed
	_cached_zone_kind = _active_local_zone_kind
	_cached_zone_tiles = _active_local_zone_tiles
	_cached_cover_tiles_by_chunk = _active_local_cover_tiles_by_chunk
	_cached_zone_truncated = _active_local_zone_truncated
	_cached_zone_valid = _has_active_local_zone()

func _invalidate_cached_zone() -> void:
	_cached_zone_seed = INVALID_MOUNTAIN_KEY
	_cached_zone_kind = &""
	_cached_zone_tiles = {}
	_cached_cover_tiles_by_chunk = {}
	_cached_zone_truncated = false
	_cached_zone_valid = false

func _build_incremental_cover_tiles_by_chunk(
	previous_cover_tiles_by_chunk: Dictionary,
	mined_tile: Vector2i
) -> Dictionary:
	var next_cover_tiles_by_chunk: Dictionary = previous_cover_tiles_by_chunk.duplicate()
	var touched_chunks: Dictionary = {}
	var changed_tiles_by_chunk: Dictionary = {}
	_refresh_incremental_cover_tile(
		next_cover_tiles_by_chunk,
		touched_chunks,
		changed_tiles_by_chunk,
		mined_tile
	)
	for offset: Vector2i in _ZONE_REVEAL_TILE_OFFSETS:
		if offset == Vector2i.ZERO:
			continue
		_refresh_incremental_cover_tile(
			next_cover_tiles_by_chunk,
			touched_chunks,
			changed_tiles_by_chunk,
			WorldGenerator.offset_tile(mined_tile, offset)
		)
	for coord: Vector2i in touched_chunks:
		if not next_cover_tiles_by_chunk.has(coord):
			continue
		if (next_cover_tiles_by_chunk[coord] as Dictionary).is_empty():
			next_cover_tiles_by_chunk.erase(coord)
	return {
		"cover_tiles_by_chunk": next_cover_tiles_by_chunk,
		"changed_tiles_by_chunk": changed_tiles_by_chunk,
		"touched_chunks": touched_chunks,
	}

func _refresh_incremental_cover_tile(
	cover_tiles_by_chunk: Dictionary,
	touched_chunks: Dictionary,
	changed_tiles_by_chunk: Dictionary,
	global_tile: Vector2i
) -> void:
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(global_tile)
	if not chunk:
		return
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
	var local_tile: Vector2i = chunk.global_to_local(global_tile)
	var should_reveal: bool = _active_local_zone_tiles.has(global_tile)
	if not should_reveal and _has_active_zone_neighbor(global_tile):
		should_reveal = chunk.is_revealable_cover_edge(local_tile)
	var current_cover_tiles: Dictionary = cover_tiles_by_chunk.get(chunk_coord, {}) as Dictionary
	var is_currently_revealed: bool = current_cover_tiles.has(local_tile)
	if is_currently_revealed == should_reveal:
		return
	if not should_reveal and not cover_tiles_by_chunk.has(chunk_coord):
		return
	var chunk_cover_tiles: Dictionary = _get_mutable_chunk_cover_tiles(
		cover_tiles_by_chunk,
		touched_chunks,
		chunk_coord
	)
	_mark_changed_cover_tile(changed_tiles_by_chunk, chunk_coord, local_tile)
	if should_reveal:
		chunk_cover_tiles[local_tile] = true
	else:
		chunk_cover_tiles.erase(local_tile)

func _get_mutable_chunk_cover_tiles(
	cover_tiles_by_chunk: Dictionary,
	touched_chunks: Dictionary,
	chunk_coord: Vector2i
) -> Dictionary:
	if touched_chunks.has(chunk_coord):
		return cover_tiles_by_chunk.get(chunk_coord, {}) as Dictionary
	var chunk_cover_tiles: Dictionary = {}
	if cover_tiles_by_chunk.has(chunk_coord):
		chunk_cover_tiles = (cover_tiles_by_chunk[chunk_coord] as Dictionary).duplicate()
	cover_tiles_by_chunk[chunk_coord] = chunk_cover_tiles
	touched_chunks[chunk_coord] = true
	return chunk_cover_tiles

func _mark_changed_cover_tile(
	changed_tiles_by_chunk: Dictionary,
	chunk_coord: Vector2i,
	local_tile: Vector2i
) -> void:
	var chunk_changed_tiles: Dictionary = changed_tiles_by_chunk.get(chunk_coord, {}) as Dictionary
	if chunk_changed_tiles.is_empty():
		changed_tiles_by_chunk[chunk_coord] = chunk_changed_tiles
	chunk_changed_tiles[local_tile] = true

func _has_active_zone_neighbor(global_tile: Vector2i) -> bool:
	for offset: Vector2i in _ZONE_REVEAL_TILE_OFFSETS:
		if offset == Vector2i.ZERO:
			continue
		if _active_local_zone_tiles.has(WorldGenerator.offset_tile(global_tile, offset)):
			return true
	return false

func _build_local_cover_tiles_by_chunk(zone_tiles: Dictionary) -> Dictionary:
	var cover_tiles_by_chunk: Dictionary = {}
	if zone_tiles.is_empty() or not _chunk_manager:
		return cover_tiles_by_chunk
	var chunk_cache: Dictionary = {}
	## cover_set_cache: chunk_coord → chunk.get_cover_edge_set()
	## Кешируем per-chunk set чтобы не пересчитывать is_revealable_cover_edge для каждого тайла.
	## get_cover_edge_set() стоит O(chunk²) только при первом вызове (или после майнинга),
	## последующие обращения — O(1). Это заменяет O(n×9×8) вызовы is_revealable_cover_edge.
	var cover_set_cache: Dictionary = {}
	var chunk_size: int = 0
	for global_tile: Vector2i in zone_tiles:
		var zone_chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(global_tile)
		var zone_chunk: Chunk = _resolve_cached_chunk(zone_chunk_coord, chunk_cache)
		if zone_chunk == null:
			continue
		if chunk_size <= 0:
			chunk_size = zone_chunk.get_chunk_size()
		var zone_local: Vector2i = _chunk_local_from_global(global_tile, zone_chunk_coord, chunk_size)
		var zone_cover_tiles: Dictionary
		if cover_tiles_by_chunk.has(zone_chunk_coord):
			zone_cover_tiles = cover_tiles_by_chunk[zone_chunk_coord] as Dictionary
		else:
			zone_cover_tiles = {}
			cover_tiles_by_chunk[zone_chunk_coord] = zone_cover_tiles
		zone_cover_tiles[zone_local] = true
		for offset: Vector2i in _ZONE_REVEAL_TILE_OFFSETS:
			if offset == Vector2i.ZERO:
				continue
			var candidate_local: Vector2i = zone_local + offset
			var candidate_tile: Vector2i = global_tile + offset
			var candidate_chunk_coord: Vector2i = zone_chunk_coord
			var candidate_chunk: Chunk = zone_chunk
			if candidate_local.x < 0 \
				or candidate_local.y < 0 \
				or candidate_local.x >= chunk_size \
				or candidate_local.y >= chunk_size:
				candidate_tile = WorldGenerator.offset_tile(global_tile, offset)
				candidate_chunk_coord = WorldGenerator.tile_to_chunk(candidate_tile)
				candidate_chunk = _resolve_cached_chunk(candidate_chunk_coord, chunk_cache)
				if candidate_chunk != null:
					candidate_local = _chunk_local_from_global(candidate_tile, candidate_chunk_coord, chunk_size)
			if not candidate_chunk:
				continue
			## Получаем cover_edge_set для чанка (O(1) если уже кешировано в чанке)
			var cover_edge_set: Dictionary
			if cover_set_cache.has(candidate_chunk_coord):
				cover_edge_set = cover_set_cache[candidate_chunk_coord] as Dictionary
			else:
				cover_edge_set = candidate_chunk.get_cover_edge_set()
				cover_set_cache[candidate_chunk_coord] = cover_edge_set
			if cover_edge_set.has(candidate_local):
				var candidate_cover_tiles: Dictionary
				if cover_tiles_by_chunk.has(candidate_chunk_coord):
					candidate_cover_tiles = cover_tiles_by_chunk[candidate_chunk_coord] as Dictionary
				else:
					candidate_cover_tiles = {}
					cover_tiles_by_chunk[candidate_chunk_coord] = candidate_cover_tiles
				candidate_cover_tiles[candidate_local] = true
	return cover_tiles_by_chunk

func _resolve_cached_chunk(chunk_coord: Vector2i, chunk_cache: Dictionary) -> Chunk:
	if chunk_cache.has(chunk_coord):
		return chunk_cache[chunk_coord] as Chunk
	var chunk: Chunk = _chunk_manager.get_chunk(chunk_coord)
	chunk_cache[chunk_coord] = chunk
	return chunk

func _chunk_local_from_global(global_tile: Vector2i, chunk_coord: Vector2i, chunk_size: int) -> Vector2i:
	return Vector2i(
		global_tile.x - chunk_coord.x * chunk_size,
		global_tile.y - chunk_coord.y * chunk_size
	)

func _duplicate_tile_set(tile_map: Dictionary) -> Dictionary:
	return tile_map.duplicate()

func _duplicate_cover_tiles_by_chunk(cover_tiles_by_chunk: Dictionary) -> Dictionary:
	var duplicate_map: Dictionary = {}
	for coord: Vector2i in cover_tiles_by_chunk:
		duplicate_map[coord] = (cover_tiles_by_chunk[coord] as Dictionary).duplicate()
	return duplicate_map

func has_active_local_zone() -> bool:
	return _has_active_local_zone()

func get_active_local_zone_tile_count() -> int:
	return _active_local_zone_tiles.size()

func is_active_local_zone_truncated() -> bool:
	return _active_local_zone_truncated
