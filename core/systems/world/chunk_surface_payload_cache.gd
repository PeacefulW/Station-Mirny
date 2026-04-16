class_name ChunkSurfacePayloadCache
extends RefCounted

const ChunkFinalPacketScript = preload("res://core/systems/world/chunk_final_packet.gd")
const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")

var _limit: int = 192
var _entries: Dictionary = {}
var _lru_prev: Dictionary = {}  ## Vector3i -> previous key in LRU list
var _lru_next: Dictionary = {}  ## Vector3i -> next key in LRU list
var _lru_head_key: Vector3i = Vector3i.ZERO
var _lru_tail_key: Vector3i = Vector3i.ZERO
var _lru_has_head: bool = false
var _canonicalize_chunk_coord: Callable
var _duplicate_native_data_fn: Callable
var _resolve_flora_tile_size_fn: Callable
var _hydrate_flora_payload_fn: Callable
var _flora_result_from_payload_fn: Callable

func setup(owner: Node, limit: int) -> void:
	_limit = maxi(1, limit)
	_canonicalize_chunk_coord = owner._canonical_chunk_coord
	_duplicate_native_data_fn = owner._duplicate_native_data
	_resolve_flora_tile_size_fn = owner._resolve_flora_tile_size
	_hydrate_flora_payload_fn = owner._hydrate_flora_payload_texture_paths
	_flora_result_from_payload_fn = owner._flora_result_from_payload

func clear() -> void:
	_entries.clear()
	_lru_prev.clear()
	_lru_next.clear()
	_lru_head_key = Vector3i.ZERO
	_lru_tail_key = Vector3i.ZERO
	_lru_has_head = false

func make_key(coord: Vector2i, z_level: int) -> Vector3i:
	var canonical_coord: Vector2i = _canonicalize_chunk_coord.call(coord) as Vector2i
	return Vector3i(canonical_coord.x, canonical_coord.y, z_level)

func has_chunk(coord: Vector2i, z_level: int) -> bool:
	if z_level != 0:
		return false
	return _entries.has(make_key(coord, z_level))

func cache_native_payload(coord: Vector2i, z_level: int, native_data: Dictionary) -> void:
	if z_level != 0 or native_data.is_empty():
		return
	if not ChunkFinalPacketScript.validate_terminal_surface_packet(
		native_data,
		"ChunkSurfacePayloadCache.cache_native_payload(%s)" % [coord]
	):
		return
	var cache_key: Vector3i = make_key(coord, z_level)
	var entry: Dictionary = _entries.get(cache_key, {}) as Dictionary
	entry["native_data"] = native_data
	_entries[cache_key] = entry
	_touch_key(cache_key)
	_trim()

func cache_flora_result(coord: Vector2i, z_level: int, flora_result: ChunkFloraResultScript) -> void:
	if z_level != 0 or flora_result == null:
		return
	var cache_key: Vector3i = make_key(coord, z_level)
	var entry: Dictionary = _entries.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return
	entry["flora_result"] = flora_result
	if not entry.has("flora_payload"):
		entry["flora_payload"] = flora_result.to_serialized_payload(int(_resolve_flora_tile_size_fn.call()))
	_entries[cache_key] = entry
	_touch_key(cache_key)

func cache_flora_payload(coord: Vector2i, z_level: int, flora_payload: Dictionary) -> void:
	if z_level != 0 or flora_payload.is_empty():
		return
	var cache_key: Vector3i = make_key(coord, z_level)
	var entry: Dictionary = _entries.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return
	var hydrated_payload: Dictionary = _hydrate_flora_payload_fn.call(flora_payload) as Dictionary
	entry["flora_payload"] = hydrated_payload if not hydrated_payload.is_empty() else flora_payload
	_entries[cache_key] = entry
	_touch_key(cache_key)

func get_flora_payload(coord: Vector2i, z_level: int) -> Dictionary:
	if z_level != 0:
		return {}
	var cache_key: Vector3i = make_key(coord, z_level)
	var entry: Dictionary = _entries.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return {}
	var flora_payload: Dictionary = entry.get("flora_payload", {}) as Dictionary
	if flora_payload.is_empty():
		return {}
	var hydrated_payload: Dictionary = _hydrate_flora_payload_fn.call(flora_payload) as Dictionary
	if hydrated_payload != flora_payload and not hydrated_payload.is_empty():
		entry["flora_payload"] = hydrated_payload
		_entries[cache_key] = entry
		_touch_key(cache_key)
		return hydrated_payload
	return flora_payload

func get_flora_result(coord: Vector2i, z_level: int) -> ChunkFloraResultScript:
	if z_level != 0:
		return null
	var cache_key: Vector3i = make_key(coord, z_level)
	var entry: Dictionary = _entries.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return null
	var flora_result: ChunkFloraResultScript = entry.get("flora_result", null) as ChunkFloraResultScript
	if flora_result != null:
		return flora_result
	var flora_payload: Dictionary = entry.get("flora_payload", {}) as Dictionary
	if flora_payload.is_empty():
		return null
	flora_result = _flora_result_from_payload_fn.call(flora_payload) as ChunkFloraResultScript
	if flora_result == null:
		return null
	entry["flora_result"] = flora_result
	_entries[cache_key] = entry
	_touch_key(cache_key)
	return flora_result

func try_get_native_data(coord: Vector2i, z_level: int, out_native_data: Dictionary) -> bool:
	if z_level != 0:
		return false
	var cache_key: Vector3i = make_key(coord, z_level)
	var entry: Dictionary = _entries.get(cache_key, {}) as Dictionary
	if entry.is_empty():
		return false
	var cached_native_data: Dictionary = entry.get("native_data", {}) as Dictionary
	if cached_native_data.is_empty():
		return false
	var duplicated_native_data: Dictionary = _duplicate_native_data_fn.call(cached_native_data) as Dictionary
	if not ChunkFinalPacketScript.validate_terminal_surface_packet(
		duplicated_native_data,
		"ChunkSurfacePayloadCache.try_get_native_data(%s)" % [coord]
	):
		_entries.erase(cache_key)
		_unlink_lru_key(cache_key)
		return false
	out_native_data.assign(duplicated_native_data)
	_touch_key(cache_key)
	return true

func _touch_key(cache_key: Vector3i) -> void:
	if _is_lru_tail(cache_key):
		return
	if _is_lru_linked(cache_key):
		_unlink_lru_key(cache_key)
	_append_lru_key(cache_key)

func _trim() -> void:
	while _entries.size() > _limit:
		if not _lru_has_head:
			break
		var oldest_key: Vector3i = _lru_head_key
		_unlink_lru_key(oldest_key)
		_entries.erase(oldest_key)

func _is_lru_linked(cache_key: Vector3i) -> bool:
	return _lru_has_head and (
		cache_key == _lru_head_key
		or _lru_prev.has(cache_key)
		or _lru_next.has(cache_key)
	)

func _is_lru_tail(cache_key: Vector3i) -> bool:
	return _lru_has_head and cache_key == _lru_tail_key

func _append_lru_key(cache_key: Vector3i) -> void:
	if not _lru_has_head:
		_lru_head_key = cache_key
		_lru_tail_key = cache_key
		_lru_has_head = true
		_lru_prev.erase(cache_key)
		_lru_next.erase(cache_key)
		return
	_lru_prev[cache_key] = _lru_tail_key
	_lru_next.erase(cache_key)
	_lru_next[_lru_tail_key] = cache_key
	_lru_tail_key = cache_key

func _unlink_lru_key(cache_key: Vector3i) -> void:
	if not _is_lru_linked(cache_key):
		return
	var has_prev: bool = _lru_prev.has(cache_key)
	var has_next: bool = _lru_next.has(cache_key)
	var prev_key: Vector3i = _lru_prev.get(cache_key, Vector3i.ZERO) as Vector3i
	var next_key: Vector3i = _lru_next.get(cache_key, Vector3i.ZERO) as Vector3i
	if has_prev:
		if has_next:
			_lru_next[prev_key] = next_key
		else:
			_lru_next.erase(prev_key)
	if has_next:
		if has_prev:
			_lru_prev[next_key] = prev_key
		else:
			_lru_prev.erase(next_key)
	if _lru_head_key == cache_key:
		if has_next:
			_lru_head_key = next_key
		else:
			_lru_head_key = Vector3i.ZERO
			_lru_tail_key = Vector3i.ZERO
			_lru_has_head = false
	if _lru_has_head and _lru_tail_key == cache_key:
		_lru_tail_key = prev_key if has_prev else _lru_head_key
	_lru_prev.erase(cache_key)
	_lru_next.erase(cache_key)
