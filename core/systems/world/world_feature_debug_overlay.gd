class_name WorldFeatureDebugOverlay
extends Node2D

const PLACEMENTS_KEY: String = "placements"
const KIND_KEY: String = "kind"
const ID_KEY: String = "id"
const ANCHOR_TILE_KEY: String = "anchor_tile"
const DEBUG_MARKER_KIND_KEY: String = "debug_marker_kind"
const FEATURE_KIND: StringName = &"feature"
const POI_KIND: StringName = &"poi"
const MARKER_RADIUS: float = 7.0
const MARKER_CROSS_HALF_SIZE: float = 10.0
const FEATURE_MARKER_COLOR: Color = Color(0.20, 0.90, 0.95, 0.92)
const POI_MARKER_COLOR: Color = Color(1.00, 0.68, 0.20, 0.92)
const OUTLINE_COLOR: Color = Color(0.02, 0.03, 0.04, 0.95)

var _payload_reader: Callable = Callable()
var _tile_to_world: Callable = Callable()
var _markers_by_chunk: Dictionary = {}

func setup(payload_reader: Callable, tile_to_world: Callable) -> void:
	_disconnect_chunk_lifecycle()
	_payload_reader = payload_reader
	_tile_to_world = tile_to_world
	z_index = 250
	_connect_chunk_lifecycle()

func get_anchor_marker_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for chunk_coord: Vector2i in _sorted_chunk_coords():
		for marker: Dictionary in _markers_by_chunk.get(chunk_coord, []):
			snapshot.append(marker.duplicate(true))
	return snapshot

func _exit_tree() -> void:
	_disconnect_chunk_lifecycle()

func _draw() -> void:
	for chunk_coord: Vector2i in _sorted_chunk_coords():
		for marker: Dictionary in _markers_by_chunk.get(chunk_coord, []):
			var world_pos: Vector2 = marker.get("world_pos", Vector2.ZERO) as Vector2
			var color: Color = marker.get("color", FEATURE_MARKER_COLOR)
			draw_circle(world_pos, MARKER_RADIUS, color)
			draw_arc(world_pos, MARKER_RADIUS, 0.0, TAU, 20, OUTLINE_COLOR, 2.0)
			draw_line(
				world_pos + Vector2(-MARKER_CROSS_HALF_SIZE, 0.0),
				world_pos + Vector2(MARKER_CROSS_HALF_SIZE, 0.0),
				OUTLINE_COLOR,
				2.0
			)
			draw_line(
				world_pos + Vector2(0.0, -MARKER_CROSS_HALF_SIZE),
				world_pos + Vector2(0.0, MARKER_CROSS_HALF_SIZE),
				OUTLINE_COLOR,
				2.0
			)

func _connect_chunk_lifecycle() -> void:
	if EventBus == null:
		return
	if not EventBus.chunk_loaded.is_connected(_on_chunk_loaded):
		EventBus.chunk_loaded.connect(_on_chunk_loaded)
	if not EventBus.chunk_unloaded.is_connected(_on_chunk_unloaded):
		EventBus.chunk_unloaded.connect(_on_chunk_unloaded)

func _disconnect_chunk_lifecycle() -> void:
	if EventBus == null:
		return
	if EventBus.chunk_loaded.is_connected(_on_chunk_loaded):
		EventBus.chunk_loaded.disconnect(_on_chunk_loaded)
	if EventBus.chunk_unloaded.is_connected(_on_chunk_unloaded):
		EventBus.chunk_unloaded.disconnect(_on_chunk_unloaded)

func _on_chunk_loaded(chunk_coord: Vector2i) -> void:
	if not _payload_reader.is_valid():
		return
	var payload: Dictionary = _payload_reader.call(chunk_coord) as Dictionary
	var markers: Array[Dictionary] = _build_markers_for_payload(payload)
	if markers.is_empty():
		_markers_by_chunk.erase(chunk_coord)
	else:
		_markers_by_chunk[chunk_coord] = markers
	queue_redraw()

func _on_chunk_unloaded(chunk_coord: Vector2i) -> void:
	if _markers_by_chunk.erase(chunk_coord):
		queue_redraw()

func _build_markers_for_payload(payload: Dictionary) -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if payload.is_empty() or not _tile_to_world.is_valid():
		return markers
	for placement_value: Variant in payload.get(PLACEMENTS_KEY, []):
		if not (placement_value is Dictionary):
			continue
		var placement: Dictionary = placement_value as Dictionary
		var debug_marker_kind: StringName = placement.get(DEBUG_MARKER_KIND_KEY, &"") as StringName
		if debug_marker_kind == &"":
			continue
		var anchor_tile: Vector2i = placement.get(ANCHOR_TILE_KEY, Vector2i.ZERO) as Vector2i
		markers.append({
			"kind": placement.get(KIND_KEY, &"") as StringName,
			"id": placement.get(ID_KEY, &"") as StringName,
			"anchor_tile": anchor_tile,
			"debug_marker_kind": debug_marker_kind,
			"world_pos": _tile_to_world.call(anchor_tile) as Vector2,
			"color": _resolve_marker_color(placement.get(KIND_KEY, &"") as StringName),
		})
	markers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_anchor: Vector2i = left.get("anchor_tile", Vector2i.ZERO) as Vector2i
		var right_anchor: Vector2i = right.get("anchor_tile", Vector2i.ZERO) as Vector2i
		if left_anchor.y != right_anchor.y:
			return left_anchor.y < right_anchor.y
		if left_anchor.x != right_anchor.x:
			return left_anchor.x < right_anchor.x
		var left_kind: String = str(left.get("kind", &""))
		var right_kind: String = str(right.get("kind", &""))
		if left_kind != right_kind:
			return left_kind < right_kind
		return str(left.get("id", &"")) < str(right.get("id", &""))
	)
	return markers

func _resolve_marker_color(kind: StringName) -> Color:
	if kind == POI_KIND:
		return POI_MARKER_COLOR
	return FEATURE_MARKER_COLOR

func _sorted_chunk_coords() -> Array[Vector2i]:
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _markers_by_chunk.keys():
		if chunk_coord_variant is Vector2i:
			chunk_coords.append(chunk_coord_variant)
	chunk_coords.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		if left.y != right.y:
			return left.y < right.y
		return left.x < right.x
	)
	return chunk_coords
