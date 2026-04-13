class_name ChunkFloraPresenter
extends Node2D

const ChunkFloraResultScript = preload("res://core/systems/world/chunk_flora_result.gd")

const FLORA_PUBLISH_LOG_ARG: String = "codex_flora_publish_log"

static var _shared_texture_cache: Dictionary = {}
static var _pending_texture_loads: Dictionary = {}
static var _failed_texture_loads: Dictionary = {}

var _tile_size: int = 0
var _layers: Array = []
var _flora_result: ChunkFloraResultScript = null
var _flora_payload: Dictionary = {}
var _local_pending_texture_paths: Dictionary = {}

func setup(tile_size: int) -> void:
	_tile_size = tile_size
	visible = false
	set_process(false)

func reset_runtime_state() -> void:
	_flora_result = null
	_flora_payload = {}
	clear_render_packet()

func set_flora_result(result: ChunkFloraResultScript) -> void:
	_flora_result = result
	_flora_payload = result.to_serialized_payload(_tile_size) if result != null else {}

func set_flora_payload(payload: Dictionary) -> void:
	_flora_payload = payload if not payload.is_empty() else {}
	_flora_result = null

func ensure_payload() -> Dictionary:
	if _flora_payload.is_empty() and _flora_result != null:
		_flora_payload = _flora_result.to_serialized_payload(_tile_size)
	return _flora_payload

func build_render_packet() -> Dictionary:
	var flora_payload: Dictionary = ensure_payload()
	if not flora_payload.is_empty():
		return ChunkFloraResultScript.build_render_packet_from_payload(flora_payload, _tile_size)
	if _flora_result == null:
		return {}
	return _flora_result.build_render_packet(_tile_size)

func get_prebuilt_render_packet(payload: Dictionary) -> Dictionary:
	if payload.is_empty():
		return {}
	var tile_size: int = int(payload.get("render_packet_tile_size", 0))
	if tile_size > 0 and tile_size != _tile_size:
		return {}
	return payload.get("render_packet", {}) as Dictionary

func clear_render_packet() -> void:
	_layers.clear()
	_local_pending_texture_paths.clear()
	visible = false
	set_process(false)
	queue_redraw()

func apply_render_packet(packet: Dictionary, mode: StringName, chunk_coord: Vector2i) -> void:
	if packet.is_empty():
		clear_render_packet()
	else:
		_layers = (packet.get("layers", []) as Array).duplicate(true)
		_local_pending_texture_paths.clear()
		_prime_packet_textures()
		visible = not _layers.is_empty()
		set_process(not _local_pending_texture_paths.is_empty())
		queue_redraw()
	_log_flora_publish_summary(mode, 1 if not packet.is_empty() else 0, chunk_coord)

func _process(_delta: float) -> void:
	if _local_pending_texture_paths.is_empty():
		set_process(false)
		return
	var should_redraw: bool = false
	for texture_path_variant: Variant in _local_pending_texture_paths.keys():
		var texture_path: String = String(texture_path_variant)
		var texture: Texture2D = _get_shared_texture(texture_path, false)
		if texture != null:
			_local_pending_texture_paths.erase(texture_path)
			should_redraw = true
		elif _failed_texture_loads.has(texture_path):
			_local_pending_texture_paths.erase(texture_path)
	if should_redraw:
		queue_redraw()
	if _local_pending_texture_paths.is_empty():
		set_process(false)

func _draw() -> void:
	for layer_variant: Variant in _layers:
		var layer: Dictionary = layer_variant as Dictionary
		for item_variant: Variant in layer.get("items", []):
			var item: Dictionary = item_variant as Dictionary
			var draw_rect_data := Rect2(
				item.get("position", Vector2.ZERO) as Vector2,
				item.get("size", Vector2.ZERO) as Vector2
			)
			var texture_path: String = String(item.get("texture_path", ""))
			var texture: Texture2D = _get_shared_texture(texture_path, false)
			if texture != null:
				draw_texture_rect(texture, draw_rect_data, false, Color.WHITE)
				continue
			draw_rect(draw_rect_data, item.get("color", Color.WHITE) as Color, true)

func _prime_packet_textures() -> void:
	for layer_variant: Variant in _layers:
		var layer: Dictionary = layer_variant as Dictionary
		for item_variant: Variant in layer.get("items", []):
			var item: Dictionary = item_variant as Dictionary
			var texture_path: String = String(item.get("texture_path", ""))
			if texture_path.is_empty():
				continue
			var texture: Texture2D = _get_shared_texture(texture_path, true)
			if texture == null and _pending_texture_loads.has(texture_path):
				_local_pending_texture_paths[texture_path] = true

static func _get_shared_texture(texture_path: String, allow_load: bool = true) -> Texture2D:
	if texture_path.is_empty():
		return null
	var cached_texture: Texture2D = _shared_texture_cache.get(texture_path, null) as Texture2D
	if cached_texture != null:
		return cached_texture
	if _pending_texture_loads.has(texture_path):
		var status: int = ResourceLoader.load_threaded_get_status(texture_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var loaded_resource: Resource = ResourceLoader.load_threaded_get(texture_path)
			_pending_texture_loads.erase(texture_path)
			if loaded_resource is Texture2D:
				_shared_texture_cache[texture_path] = loaded_resource
				_failed_texture_loads.erase(texture_path)
				return loaded_resource as Texture2D
			_failed_texture_loads[texture_path] = true
			return null
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending_texture_loads.erase(texture_path)
			_failed_texture_loads[texture_path] = true
			return null
		return null
	if not allow_load or _failed_texture_loads.has(texture_path):
		return null
	var load_error: int = ResourceLoader.load_threaded_request(texture_path, "Texture2D")
	if load_error == OK or load_error == ERR_BUSY:
		_pending_texture_loads[texture_path] = true
	else:
		_failed_texture_loads[texture_path] = true
	return null

func _flora_publish_logging_enabled() -> bool:
	return OS.is_debug_build() and FLORA_PUBLISH_LOG_ARG in OS.get_cmdline_user_args()

func _log_flora_publish_summary(mode: StringName, renderer_nodes: int, chunk_coord: Vector2i) -> void:
	if not _flora_publish_logging_enabled():
		return
	var flora_payload: Dictionary = ensure_payload()
	var placement_count: int = int(flora_payload.get(
		"placement_count",
		_flora_result.get_placement_count() if _flora_result != null else 0
	))
	var group_count: int = int(flora_payload.get(
		"group_count",
		_flora_result.get_render_group_count() if _flora_result != null else 0
	))
	var layer_count: int = int(flora_payload.get(
		"layer_count",
		_flora_result.get_render_layer_count() if _flora_result != null else 0
	))
	var textured_placement_count: int = 0
	var placements: Array = flora_payload.get("placements", []) as Array
	for placement_variant: Variant in placements:
		var placement: Dictionary = placement_variant as Dictionary
		if not String(placement.get("texture_path", "")).is_empty():
			textured_placement_count += 1
	print("[FloraPublish] chunk=%s mode=%s placements=%d textured=%d groups=%d layers=%d renderer_nodes=%d" % [
		chunk_coord,
		String(mode),
		placement_count,
		textured_placement_count,
		group_count,
		layer_count,
		renderer_nodes,
	])
