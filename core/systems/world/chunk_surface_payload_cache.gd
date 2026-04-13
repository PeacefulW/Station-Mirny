class_name ChunkSurfacePayloadCache
extends RefCounted

const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")

var _limit: int = 192
var _entries: Dictionary = {}
var _touch_order: Dictionary = {}  ## Vector3i -> monotonic touch serial
var _touch_serial: int = 0
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
	_touch_order.clear()
	_touch_serial = 0

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
	var cache_key: Vector3i = make_key(coord, z_level)
	var entry: Dictionary = _entries.get(cache_key, {}) as Dictionary
	entry["native_data"] = _duplicate_native_data_fn.call(native_data) as Dictionary
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
	out_native_data.assign(_duplicate_native_data_fn.call(cached_native_data) as Dictionary)
	_touch_key(cache_key)
	return true

func _touch_key(cache_key: Vector3i) -> void:
	_touch_serial += 1
	_touch_order[cache_key] = _touch_serial

func _trim() -> void:
	while _entries.size() > _limit:
		var has_oldest: bool = false
		var oldest_key: Vector3i = Vector3i.ZERO
		var oldest_serial: int = 0
		for key_variant: Variant in _entries.keys():
			var cache_key: Vector3i = key_variant as Vector3i
			var access_serial: int = int(_touch_order.get(cache_key, 0))
			if not has_oldest or access_serial < oldest_serial:
				has_oldest = true
				oldest_key = cache_key
				oldest_serial = access_serial
		if not has_oldest:
			break
		_entries.erase(oldest_key)
		_touch_order.erase(oldest_key)
