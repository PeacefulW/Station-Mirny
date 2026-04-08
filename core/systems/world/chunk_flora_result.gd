class_name ChunkFloraResult
extends RefCounted

## Результат compute-фазы размещения флоры/декора для одного чанка.

const RENDER_KIND_FLORA: StringName = &"flora"
const RENDER_KIND_DECOR: StringName = &"decor"

var chunk_coord: Vector2i = Vector2i.ZERO
var chunk_size: int = 0
var placements: Array[Dictionary] = []
var _placements_by_local_pos: Dictionary = {}
var _render_groups_by_key: Dictionary = {}
var _render_groups_cache: Array[Dictionary] = []
var _render_packet_cache_by_tile_size: Dictionary = {}

func add_placement(
	local_pos: Vector2i,
	entry_id: StringName,
	is_flora: bool,
	color: Color,
	size: Vector2i,
	z_offset: int,
	texture_path: String = ""
) -> void:
	var placement: Dictionary = {
		"local_pos": local_pos,
		"entry_id": entry_id,
		"is_flora": is_flora,
		"color": color,
		"size": size,
		"z_offset": z_offset,
		"texture_path": texture_path,
	}
	placements.append(placement)
	var placements_for_tile: Array = _placements_by_local_pos.get(local_pos, [])
	placements_for_tile.append(placement)
	_placements_by_local_pos[local_pos] = placements_for_tile
	_append_render_group(placement)

func get_placement_count() -> int:
	return placements.size()

func is_empty() -> bool:
	return placements.is_empty()

func get_placements_for_local_pos(local_pos: Vector2i) -> Array:
	return _placements_by_local_pos.get(local_pos, [])

func finalize_render_groups() -> void:
	if _render_groups_by_key.is_empty():
		_render_groups_cache.clear()
		return
	var group_keys: Array = _render_groups_by_key.keys()
	group_keys.sort()
	_render_groups_cache.clear()
	for key_variant: Variant in group_keys:
		var cached_group: Dictionary = (_render_groups_by_key.get(key_variant, {}) as Dictionary).duplicate(true)
		var local_tiles: Array = cached_group.get("local_tiles", []) as Array
		local_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		)
		cached_group["local_tiles"] = local_tiles
		cached_group["placement_count"] = local_tiles.size()
		_render_groups_cache.append(cached_group)

func get_render_group_count() -> int:
	if _render_groups_cache.is_empty() and not _render_groups_by_key.is_empty():
		finalize_render_groups()
	return _render_groups_cache.size()

func get_render_layer_count() -> int:
	if _render_groups_cache.is_empty() and not _render_groups_by_key.is_empty():
		finalize_render_groups()
	var layers: Dictionary = {}
	for group_variant: Variant in _render_groups_cache:
		var group: Dictionary = group_variant as Dictionary
		layers[int(group.get("layer", 0))] = true
	return layers.size()

func build_render_packet(tile_size: int) -> Dictionary:
	finalize_render_groups()
	if tile_size <= 0:
		return {}
	var cached_packet: Dictionary = _render_packet_cache_by_tile_size.get(tile_size, {}) as Dictionary
	if cached_packet.is_empty():
		cached_packet = _build_render_packet_from_groups(_render_groups_cache, tile_size, placements.size())
		if not cached_packet.is_empty():
			_render_packet_cache_by_tile_size[tile_size] = cached_packet
	return cached_packet

func to_serialized_payload(tile_size: int = 0) -> Dictionary:
	finalize_render_groups()
	var payload: Dictionary = {
		"chunk_coord": chunk_coord,
		"chunk_size": chunk_size,
		"placements": placements.duplicate(true),
		"render_groups": _render_groups_cache.duplicate(true),
		"placement_count": placements.size(),
		"group_count": _render_groups_cache.size(),
		"layer_count": get_render_layer_count(),
	}
	if tile_size > 0:
		payload["render_packet"] = build_render_packet(tile_size)
		payload["render_packet_tile_size"] = tile_size
	return payload

static func from_serialized_payload(payload: Dictionary) -> ChunkFloraResult:
	var result := ChunkFloraResult.new()
	result.chunk_coord = payload.get("chunk_coord", Vector2i.ZERO) as Vector2i
	result.chunk_size = int(payload.get("chunk_size", 0))
	var serialized_placements: Array = payload.get("placements", []) as Array
	for placement_variant: Variant in serialized_placements:
		var placement: Dictionary = placement_variant as Dictionary
		var local_pos: Vector2i = placement.get("local_pos", Vector2i.ZERO) as Vector2i
		result.add_placement(
			local_pos,
			placement.get("entry_id", &"") as StringName,
			bool(placement.get("is_flora", true)),
			placement.get("color", Color.WHITE) as Color,
			placement.get("size", Vector2i.ZERO) as Vector2i,
			int(placement.get("z_offset", 0)),
			String(placement.get("texture_path", ""))
		)
	result.finalize_render_groups()
	var render_packet: Dictionary = payload.get("render_packet", {}) as Dictionary
	var render_packet_tile_size: int = int(payload.get("render_packet_tile_size", 0))
	if render_packet_tile_size > 0 and not render_packet.is_empty():
		result._render_packet_cache_by_tile_size[render_packet_tile_size] = render_packet
	return result

static func build_render_packet_from_payload(payload: Dictionary, tile_size: int) -> Dictionary:
	if payload.is_empty():
		return {}
	var cached_packet: Dictionary = payload.get("render_packet", {}) as Dictionary
	var cached_tile_size: int = int(payload.get("render_packet_tile_size", 0))
	if not cached_packet.is_empty() and (cached_tile_size <= 0 or cached_tile_size == tile_size):
		return cached_packet
	var render_groups: Array = payload.get("render_groups", []) as Array
	if render_groups.is_empty():
		return ChunkFloraResult.from_serialized_payload(payload).build_render_packet(tile_size)
	var placement_count: int = 0
	for group_variant: Variant in render_groups:
		var group: Dictionary = group_variant as Dictionary
		var local_tiles: Array = group.get("local_tiles", []) as Array
		placement_count += int(group.get("placement_count", local_tiles.size()))
	return _build_render_packet_from_groups(render_groups, tile_size, placement_count)

static func build_serialized_payload_from_placements(
	chunk_coord: Vector2i,
	chunk_size: int,
	serialized_placements: Array,
	tile_size: int
) -> Dictionary:
	if serialized_placements.is_empty() or chunk_size <= 0:
		return {}
	return ChunkFloraResult.from_serialized_payload({
		"chunk_coord": chunk_coord,
		"chunk_size": chunk_size,
		"placements": serialized_placements,
	}).to_serialized_payload(tile_size)

func _append_render_group(placement: Dictionary) -> void:
	_render_groups_cache.clear()
	_render_packet_cache_by_tile_size.clear()
	var kind: StringName = RENDER_KIND_FLORA if bool(placement.get("is_flora", true)) else RENDER_KIND_DECOR
	var entry_id: StringName = placement.get("entry_id", &"") as StringName
	var color: Color = placement.get("color", Color.WHITE) as Color
	var size: Vector2i = placement.get("size", Vector2i.ZERO) as Vector2i
	var layer: int = int(placement.get("z_offset", 0))
	var texture_path: String = String(placement.get("texture_path", ""))
	var group_key: String = "%d|%s|%s|%d|%d|%s|%s" % [
		layer,
		String(kind),
		String(entry_id),
		size.x,
		size.y,
		texture_path,
		color.to_html(),
	]
	var render_group: Dictionary = _render_groups_by_key.get(group_key, {
		"layer": layer,
		"kind": kind,
		"entry_id": entry_id,
		"color": color,
		"size": size,
		"texture_path": texture_path,
		"local_tiles": [],
	})
	var local_tiles: Array = render_group.get("local_tiles", []) as Array
	local_tiles.append(placement.get("local_pos", Vector2i.ZERO) as Vector2i)
	render_group["local_tiles"] = local_tiles
	_render_groups_by_key[group_key] = render_group

static func _build_render_packet_from_groups(render_groups: Array, tile_size: int, placement_count: int) -> Dictionary:
	if render_groups.is_empty() or tile_size <= 0 or placement_count <= 0:
		return {}
	var items_by_layer: Dictionary = {}
	var group_summaries: Array[Dictionary] = []
	for group_variant: Variant in render_groups:
		var group: Dictionary = group_variant as Dictionary
		var layer: int = int(group.get("layer", 0))
		var color: Color = group.get("color", Color.WHITE) as Color
		var size_pixels_i: Vector2i = group.get("size", Vector2i.ZERO) as Vector2i
		var size_pixels: Vector2 = Vector2(size_pixels_i.x, size_pixels_i.y)
		var texture_path: String = String(group.get("texture_path", ""))
		var local_tiles: Array = group.get("local_tiles", []) as Array
		var items: Array = items_by_layer.get(layer, []) as Array
		for tile_variant: Variant in local_tiles:
			var local_pos: Vector2i = tile_variant as Vector2i
			items.append({
				"sort_y": local_pos.y,
				"sort_x": local_pos.x,
				"position": Vector2(
					local_pos.x * tile_size + (tile_size - size_pixels_i.x) * 0.5,
					local_pos.y * tile_size + (tile_size - size_pixels_i.y)
				),
				"size": size_pixels,
				"color": color,
				"texture_path": texture_path,
			})
		items_by_layer[layer] = items
		group_summaries.append({
			"layer": layer,
			"kind": group.get("kind", RENDER_KIND_FLORA),
			"entry_id": group.get("entry_id", &""),
			"texture_path": texture_path,
			"placement_count": int(group.get("placement_count", local_tiles.size())),
		})
	var layer_keys: Array = items_by_layer.keys()
	layer_keys.sort()
	var layers: Array[Dictionary] = []
	for layer_key_variant: Variant in layer_keys:
		var layer: int = int(layer_key_variant)
		var items: Array = items_by_layer.get(layer, []) as Array
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ay: int = int(a.get("sort_y", 0))
			var by: int = int(b.get("sort_y", 0))
			if ay == by:
				return int(a.get("sort_x", 0)) < int(b.get("sort_x", 0))
			return ay < by
		)
		for item_variant: Variant in items:
			var item: Dictionary = item_variant as Dictionary
			item.erase("sort_y")
			item.erase("sort_x")
		layers.append({
			"z_index": layer,
			"items": items,
			"item_count": items.size(),
		})
	return {
		"mode": &"batched_renderer",
		"placement_count": placement_count,
		"group_count": group_summaries.size(),
		"layer_count": layer_keys.size(),
		"groups": group_summaries,
		"layers": layers,
	}
