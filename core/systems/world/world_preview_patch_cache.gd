class_name WorldPreviewPatchCache
extends RefCounted

const MAX_ENTRY_COUNT: int = 2048

var _patches_by_key: Dictionary = {}
var _lru_keys: Array[String] = []

func make_key(
	seed: int,
	world_version: int,
	settings_signature: String,
	chunk_coord: Vector2i,
	palette_id: StringName
) -> String:
	return "%d|%d|%s|%s|%d|%d" % [
		seed,
		world_version,
		settings_signature,
		String(palette_id),
		chunk_coord.x,
		chunk_coord.y,
	]

func get_patch(cache_key: String) -> Texture2D:
	var patch_texture: Texture2D = _patches_by_key.get(cache_key, null) as Texture2D
	if patch_texture != null:
		_touch_key(cache_key)
	return patch_texture

func store_patch(cache_key: String, patch_texture: Texture2D) -> void:
	if cache_key.is_empty() or patch_texture == null:
		return
	_patches_by_key[cache_key] = patch_texture
	_touch_key(cache_key)
	_evict_overflow()

func clear() -> void:
	_patches_by_key.clear()
	_lru_keys.clear()

func _touch_key(cache_key: String) -> void:
	var existing_index: int = _lru_keys.find(cache_key)
	if existing_index >= 0:
		_lru_keys.remove_at(existing_index)
	_lru_keys.append(cache_key)

func _evict_overflow() -> void:
	while _lru_keys.size() > MAX_ENTRY_COUNT:
		var oldest_key: String = _lru_keys.pop_front()
		_patches_by_key.erase(oldest_key)
