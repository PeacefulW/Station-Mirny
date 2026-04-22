class_name WorldPreviewPatchCache
extends RefCounted

const MAX_PACKET_ENTRY_COUNT: int = 1280
const MAX_PATCH_ENTRY_COUNT: int = 4096

var _packets_by_key: Dictionary = {}
var _packet_lru_keys: Array[String] = []
var _patches_by_key: Dictionary = {}
var _patch_lru_keys: Array[String] = []

func make_packet_key(
	seed: int,
	world_version: int,
	settings_signature: String,
	chunk_coord: Vector2i
) -> String:
	return "%d|%d|%s|%d|%d" % [
		seed,
		world_version,
		settings_signature,
		chunk_coord.x,
		chunk_coord.y,
	]

func make_patch_key(
	seed: int,
	world_version: int,
	settings_signature: String,
	chunk_coord: Vector2i,
	palette_id: StringName
) -> String:
	return "%s|%s" % [
		make_packet_key(seed, world_version, settings_signature, chunk_coord),
		String(palette_id),
	]

func get_packet(cache_key: String) -> Dictionary:
	var packet: Dictionary = _packets_by_key.get(cache_key, {}) as Dictionary
	if not packet.is_empty():
		_touch_packet_key(cache_key)
	return packet

func get_patch(cache_key: String) -> Texture2D:
	var patch_texture: Texture2D = _patches_by_key.get(cache_key, null) as Texture2D
	if patch_texture != null:
		_touch_patch_key(cache_key)
	return patch_texture

func store_packet(cache_key: String, packet: Dictionary) -> void:
	if cache_key.is_empty() or packet.is_empty():
		return
	_packets_by_key[cache_key] = packet.duplicate(true)
	_touch_packet_key(cache_key)
	_evict_packet_overflow()

func store_patch(cache_key: String, patch_texture: Texture2D) -> void:
	if cache_key.is_empty() or patch_texture == null:
		return
	_patches_by_key[cache_key] = patch_texture
	_touch_patch_key(cache_key)
	_evict_patch_overflow()

func clear() -> void:
	_packets_by_key.clear()
	_packet_lru_keys.clear()
	_patches_by_key.clear()
	_patch_lru_keys.clear()

func _touch_packet_key(cache_key: String) -> void:
	var existing_index: int = _packet_lru_keys.find(cache_key)
	if existing_index >= 0:
		_packet_lru_keys.remove_at(existing_index)
	_packet_lru_keys.append(cache_key)

func _touch_patch_key(cache_key: String) -> void:
	var existing_index: int = _patch_lru_keys.find(cache_key)
	if existing_index >= 0:
		_patch_lru_keys.remove_at(existing_index)
	_patch_lru_keys.append(cache_key)

func _evict_packet_overflow() -> void:
	while _packet_lru_keys.size() > MAX_PACKET_ENTRY_COUNT:
		var oldest_key: String = _packet_lru_keys.pop_front()
		_packets_by_key.erase(oldest_key)

func _evict_patch_overflow() -> void:
	while _patch_lru_keys.size() > MAX_PATCH_ENTRY_COUNT:
		var oldest_key: String = _patch_lru_keys.pop_front()
		_patches_by_key.erase(oldest_key)
