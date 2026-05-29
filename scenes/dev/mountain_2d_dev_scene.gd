extends Node2D

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const MountainPlateau2DLayer = preload("res://scenes/dev/mountain_plateau_2d_layer.gd")
const MountainPlateau2DRasterLayer = preload("res://core/systems/world/mountain_plateau_2d_raster_layer.gd")
const Mountain2DLightProbeScript = preload("res://scenes/dev/mountain_2d_light_probe.gd")
const Mountain2DDevInfoText = preload("res://scenes/dev/mountain_2d_dev_info_text.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const SEARCH_RADIUS_CHUNKS: int = 32
const DISPLAY_RADIUS_CHUNKS: int = 2
const GENERATION_BATCH_SIZE: int = 64
const MIN_TARGET_MOUNTAIN_CELLS: int = 24
const PAN_SPEED_PX_PER_SEC: float = 900.0
const ZOOM_STEP: float = 1.12
const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 2.25
const RASTER_PRESET_PATH: String = "res://scenes/dev/mountain_2d_raster_preset.json"
const TUNING_PANEL_WIDTH_PX: float = 620.0
const TUNING_UI_RU: Dictionary = {
	"facade_height_px": ["Фасад", "Высота фасада"],
	"face_texture_scale": ["Фасад", "Масштаб текстуры фасада"],
	"face_texture_blend": ["Фасад", "Сила текстуры фасада"],
	"face_darkening": ["Фасад", "Затемнение фасада"],
	"round_blur_radius_px": ["Форма", "Скругление силуэта"],
	"shape_blob_radius_px": ["Форма", "Полутайловый радиус"],
	"shape_domain_warp_px": ["Форма", "Сила природных волн"],
	"shape_domain_warp_scale_px": ["Форма", "Размер природных волн"],
	"shape_lobe_px": ["Форма", "Разброс выступов"],
	"shape_lobe_scale_px": ["Форма", "Размер выступов"],
	"normal_strength": ["Нормали", "Сила нормалей"],
	"normal_top_detail_strength": ["Нормали", "Деталь верхушки"],
	"normal_face_detail_strength": ["Нормали", "Деталь фасада"],
	"normal_detail_scale_px": ["Нормали", "Размер мелких вмятин"],
	"normal_macro_scale_px": ["Нормали", "Размер крупных неровностей"],
	"top_threshold_center": ["Форма", "Порог верхушки"],
	"top_threshold_width": ["Форма", "Мягкость края"],
	"edge_warp_px": ["Форма", "Мелкая дрожь края"],
	"edge_warp_scale_px": ["Форма", "Размер мелкой дрожи"],
	"top_texture_scale": ["Верхушка", "Масштаб текстуры верхушки"],
	"top_texture_blend": ["Верхушка", "Сила текстуры верхушки"],
	"top_macro_scale_px": ["Верхушка", "Размер крупных пятен"],
	"top_macro_strength": ["Верхушка", "Сила крупных пятен"],
	"rim_threshold_center": ["Кромка", "Положение кромки"],
	"rim_threshold_width": ["Кромка", "Мягкость кромки"],
	"rim_strength": ["Кромка", "Сила темной кромки"],
	"rim_light_strength": ["Кромка", "Светлая грань"],
	"outline_strength": ["Кромка", "Нижняя обводка"],
}

@export var probe_seed: int = 131071
@export var show_debug_grid: bool = false
@export var show_mountain_solid_mask: bool = false
@export var show_mountain_contour: bool = false
@export var show_plateau_layer: bool = false
@export var show_raster_layer: bool = true
@export var show_raster_normal_preview: bool = false
@export var show_raster_light_preview: bool = false
@export var show_tilemap_baseline: bool = false
@export var show_plateau_edge_debug: bool = false
@export_range(0.0, 1.0, 0.05) var tilemap_baseline_alpha: float = 0.38

@onready var _terrain_root: Node2D = $TerrainRoot as Node2D
@onready var _camera: Camera2D = $Camera2D as Camera2D
@onready var _info_label: Label = $Hud/InfoLabel as Label

var _world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
var _debug_snapshot: Dictionary = {}
var _last_mouse_position: Vector2 = Vector2.ZERO
var _is_mouse_panning: bool = false
var _plateau_layer: MountainPlateau2DLayer = null
var _raster_layer: MountainPlateau2DRasterLayer = null
var _light_probe: Node2D = null
var _display_packets: Array[Dictionary] = []
var _display_target_chunk: Vector2i = Vector2i.ZERO
var _raster_preset: Dictionary = MountainPlateau2DRasterLayer.default_preset()
var _pending_raster_preset: Dictionary = MountainPlateau2DRasterLayer.default_preset()
var _tuning_panel: PanelContainer = null
var _tuning_status_label: Label = null
var _tuning_sliders: Dictionary = {}
var _tuning_spinboxes: Dictionary = {}
var _is_syncing_tuning_controls: bool = false

func _ready() -> void:
	WorldTileSetFactory.bootstrap()
	_camera.enabled = true
	_camera.make_current()
	_load_raster_preset_from_disk(false)
	_build_tuning_panel()
	_build_scene()

func _process(delta: float) -> void:
	var movement := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		movement.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		movement.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		movement.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		movement.y += 1.0
	if movement != Vector2.ZERO:
		_camera.position += movement.normalized() * PAN_SPEED_PX_PER_SEC * delta / _camera.zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_P:
					show_plateau_layer = not show_plateau_layer
					if show_plateau_layer:
						show_raster_layer = false
					_sync_compare_visibility()
				KEY_R:
					show_raster_layer = not show_raster_layer
					if show_raster_layer:
						show_plateau_layer = false
					_sync_compare_visibility()
				KEY_N:
					set_raster_normal_preview_enabled(not show_raster_normal_preview)
				KEY_L:
					set_raster_light_preview_enabled(not show_raster_light_preview)
				KEY_T:
					show_tilemap_baseline = not show_tilemap_baseline
					_sync_compare_visibility()
				KEY_E:
					show_plateau_edge_debug = not show_plateau_edge_debug
					if _plateau_layer != null and is_instance_valid(_plateau_layer):
						_plateau_layer.draw_debug_edges = show_plateau_edge_debug
						_plateau_layer.queue_redraw()
					_update_info_label()
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_apply_zoom(ZOOM_STEP)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_apply_zoom(1.0 / ZOOM_STEP)
		elif mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_mouse_panning = mouse_button.pressed
			_last_mouse_position = mouse_button.position
	elif event is InputEventMouseMotion and _is_mouse_panning:
		var mouse_motion := event as InputEventMouseMotion
		var delta: Vector2 = mouse_motion.position - _last_mouse_position
		_camera.position -= delta / _camera.zoom.x
		_last_mouse_position = mouse_motion.position

func get_debug_snapshot() -> Dictionary:
	return _debug_snapshot.duplicate(true)

func apply_raster_preset() -> void:
	_ensure_raster_layer()
	_raster_layer.set_preset(_pending_raster_preset)
	_raster_preset = _raster_layer.get_preset()
	_pending_raster_preset = _raster_preset.duplicate(true)
	_sync_tuning_controls_from_preset(_pending_raster_preset)
	if not _display_packets.is_empty():
		_raster_layer.rebuild_from_packets(_display_packets, _display_target_chunk)
	_sync_raster_debug_snapshot()
	_set_tuning_status("Применено: FHD-рендер пересобран")

func save_raster_preset() -> void:
	var preset_to_save: Dictionary = _pending_raster_preset.duplicate(true)
	var file: FileAccess = FileAccess.open(RASTER_PRESET_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save mountain raster preset: %s" % RASTER_PRESET_PATH)
		_set_tuning_status("Не удалось сохранить preset")
		return
	file.store_string(JSON.stringify(preset_to_save, "\t"))
	_set_tuning_status("Preset сохранен")
	_sync_raster_debug_snapshot()
	_debug_snapshot["raster_preset"] = preset_to_save

func load_raster_preset() -> void:
	if not _load_raster_preset_from_disk(true):
		return
	apply_raster_preset()

func reset_raster_preset() -> void:
	_pending_raster_preset = MountainPlateau2DRasterLayer.default_preset()
	apply_raster_preset()

func set_raster_normal_preview_enabled(enabled: bool) -> void:
	show_raster_normal_preview = enabled
	if show_raster_normal_preview:
		show_raster_light_preview = false
	if _raster_layer != null and is_instance_valid(_raster_layer):
		_raster_layer.set_display_normal_map(show_raster_normal_preview)
	if _light_probe != null and is_instance_valid(_light_probe):
		_light_probe.call("set_light_mode_enabled", show_raster_light_preview)
	_sync_raster_debug_snapshot()
	_update_info_label()

func set_raster_light_preview_enabled(enabled: bool) -> void:
	show_raster_light_preview = enabled
	if show_raster_light_preview:
		show_raster_normal_preview = false
	var probe: Node2D = _ensure_light_probe()
	if _raster_layer != null and is_instance_valid(_raster_layer):
		_raster_layer.set_display_light_map(show_raster_light_preview)
	probe.call("set_light_mode_enabled", show_raster_light_preview)
	_sync_raster_debug_snapshot()
	_update_info_label()

func _build_scene() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	assert(world_core != null, "WorldCore required - build GDExtension before opening mountain_2d_dev_scene.")
	if world_core == null:
		_set_failure("WorldCore is unavailable.")
		return

	var settings_packed: PackedFloat32Array = _build_settings_packed()
	var spawn_tile: Vector2i = _resolve_spawn_tile(world_core, settings_packed)
	if spawn_tile == Vector2i(-1, -1):
		_set_failure("Native spawn resolver did not return a current-world spawn tile.")
		return

	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn_tile)
	var target: Dictionary = _find_mountain_target(world_core, settings_packed, center_chunk)
	if target.is_empty():
		_set_failure("No generated mountain chunk was found within search radius %d." % SEARCH_RADIUS_CHUNKS)
		return

	var target_chunk: Vector2i = target.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var target_local: Vector2i = target.get("first_local", Vector2i.ZERO) as Vector2i
	var display_packets: Array[Dictionary] = _generate_display_packets(world_core, settings_packed, target_chunk)
	_apply_display_packets(display_packets, target_chunk)
	_center_camera(target_chunk, target_local)
	_ensure_light_probe().call("set_light_position", _camera.position)
	_update_debug_snapshot(spawn_tile, target, display_packets)
	_update_info_label()

func _build_settings_packed() -> PackedFloat32Array:
	_world_bounds = WorldBoundsSettings.hard_coded_defaults()
	var mountain_settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.for_bounds(_world_bounds)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, _world_bounds)
	return lake_settings.write_to_settings_packed(packed)

func _resolve_spawn_tile(world_core: Object, settings_packed: PackedFloat32Array) -> Vector2i:
	var result_variant: Variant = world_core.call(
		"resolve_world_foundation_spawn_tile",
		probe_seed,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	if result_variant is not Dictionary:
		return Vector2i(-1, -1)
	var result: Dictionary = result_variant as Dictionary
	if not bool(result.get("success", false)):
		return Vector2i(-1, -1)
	return result.get("spawn_tile", Vector2i(-1, -1)) as Vector2i

func _find_mountain_target(
	world_core: Object,
	settings_packed: PackedFloat32Array,
	center_chunk: Vector2i
) -> Dictionary:
	var visited: Dictionary = {}
	var best: Dictionary = {}
	for radius: int in range(SEARCH_RADIUS_CHUNKS + 1):
		var ring_coords: Array[Vector2i] = _build_ring_coords(center_chunk, radius, visited)
		for batch_start: int in range(0, ring_coords.size(), GENERATION_BATCH_SIZE):
			var batch: Array[Vector2i] = ring_coords.slice(
				batch_start,
				mini(batch_start + GENERATION_BATCH_SIZE, ring_coords.size())
			)
			var packets: Array = _generate_packets(world_core, settings_packed, batch)
			for packet_variant: Variant in packets:
				var packet: Dictionary = packet_variant as Dictionary
				var stats: Dictionary = _summarize_mountain_packet(packet)
				var mountain_cells: int = int(stats.get("mountain_cells", 0))
				if mountain_cells <= int(best.get("mountain_cells", 0)):
					continue
				best = stats
				best["chunk_coord"] = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
				best["search_radius"] = radius
				if mountain_cells >= MIN_TARGET_MOUNTAIN_CELLS:
					return best
	return best

func _build_ring_coords(center_chunk: Vector2i, radius: int, visited: Dictionary) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for y: int in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for x: int in range(center_chunk.x - radius, center_chunk.x + radius + 1):
			if radius > 0 \
					and x != center_chunk.x - radius \
					and x != center_chunk.x + radius \
					and y != center_chunk.y - radius \
					and y != center_chunk.y + radius:
				continue
			var coord: Vector2i = _canonicalize_chunk(Vector2i(x, y))
			if not _is_chunk_y_in_bounds(coord):
				continue
			if visited.has(coord):
				continue
			visited[coord] = true
			coords.append(coord)
	return coords

func _generate_display_packets(
	world_core: Object,
	settings_packed: PackedFloat32Array,
	target_chunk: Vector2i
) -> Array[Dictionary]:
	var coords: Array[Vector2i] = []
	var seen: Dictionary = {}
	for y: int in range(target_chunk.y - DISPLAY_RADIUS_CHUNKS, target_chunk.y + DISPLAY_RADIUS_CHUNKS + 1):
		for x: int in range(target_chunk.x - DISPLAY_RADIUS_CHUNKS, target_chunk.x + DISPLAY_RADIUS_CHUNKS + 1):
			var coord: Vector2i = _canonicalize_chunk(Vector2i(x, y))
			if not _is_chunk_y_in_bounds(coord):
				continue
			if seen.has(coord):
				continue
			seen[coord] = true
			coords.append(coord)
	var packets: Array[Dictionary] = []
	for batch_start: int in range(0, coords.size(), GENERATION_BATCH_SIZE):
		var batch: Array[Vector2i] = coords.slice(
			batch_start,
			mini(batch_start + GENERATION_BATCH_SIZE, coords.size())
		)
		for packet_variant: Variant in _generate_packets(world_core, settings_packed, batch):
			packets.append(packet_variant as Dictionary)
	return packets

func _generate_packets(
	world_core: Object,
	settings_packed: PackedFloat32Array,
	coords: Array[Vector2i]
) -> Array:
	var packed_coords := PackedVector2Array()
	for coord: Vector2i in coords:
		packed_coords.append(Vector2(float(coord.x), float(coord.y)))
	var packets_variant: Variant = world_core.call(
		"generate_chunk_packets_batch",
		probe_seed,
		packed_coords,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	assert(packets_variant is Array, "WorldCore.generate_chunk_packets_batch must return an Array.")
	if packets_variant is Array:
		return packets_variant as Array
	return []

func _summarize_mountain_packet(packet: Dictionary) -> Dictionary:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var mountain_cells: int = 0
	var wall_cells: int = 0
	var foot_cells: int = 0
	var first_local := Vector2i(-1, -1)
	var mountain_id_counts: Dictionary = {}
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if not _is_mountain_terrain(terrain_id):
			continue
		var flags: int = int(mountain_flags[index]) if index < mountain_flags.size() else 0
		if terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
				and (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
			continue
		mountain_cells += 1
		if (flags & WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT) != 0:
			foot_cells += 1
		else:
			wall_cells += 1
		if first_local == Vector2i(-1, -1):
			first_local = WorldRuntimeConstants.index_to_local(index)
		if index < mountain_ids.size():
			var mountain_id: int = int(mountain_ids[index])
			if mountain_id > 0:
				mountain_id_counts[mountain_id] = int(mountain_id_counts.get(mountain_id, 0)) + 1
	return {
		"mountain_cells": mountain_cells,
		"wall_cells": wall_cells,
		"foot_cells": foot_cells,
		"first_local": first_local,
		"mountain_id_count": mountain_id_counts.size(),
	}

func _apply_display_packets(packets: Array[Dictionary], target_chunk: Vector2i) -> void:
	_display_packets = packets
	_display_target_chunk = target_chunk
	for child: Node in _terrain_root.get_children():
		child.queue_free()
	_terrain_root.position = -WorldRuntimeConstants.chunk_origin_px(target_chunk)
	packets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_coord: Vector2i = a.get("chunk_coord", Vector2i.ZERO) as Vector2i
		var b_coord: Vector2i = b.get("chunk_coord", Vector2i.ZERO) as Vector2i
		return a_coord.x < b_coord.x if a_coord.x != b_coord.x else a_coord.y < b_coord.y
	)
	for packet: Dictionary in packets:
		var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
		var view := ChunkView.new()
		view.name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
		_terrain_root.add_child(view)
		view.configure(chunk_coord)
		view.begin_apply(packet)
		while view.apply_next_batch(WorldRuntimeConstants.CHUNK_CELL_COUNT):
			pass
		view.set_debug_overlays(show_debug_grid, show_mountain_solid_mask, show_mountain_contour)
		if show_mountain_contour:
			view.apply_contour_debug_data(
				_build_solid_mask(packet),
				PackedVector2Array(),
				PackedInt32Array()
			)
		view.visible = true
	_ensure_plateau_layer()
	_plateau_layer.rebuild_from_packets(packets, target_chunk)
	_plateau_layer.draw_debug_edges = show_plateau_edge_debug
	_ensure_raster_layer()
	_raster_layer.set_preset(_raster_preset)
	_raster_layer.rebuild_from_packets(packets, target_chunk)
	_raster_preset = _raster_layer.get_preset()
	_pending_raster_preset = _raster_preset.duplicate(true)
	_sync_tuning_controls_from_preset(_pending_raster_preset)
	_sync_compare_visibility()

func _build_solid_mask(packet: Dictionary) -> PackedByteArray:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mask := PackedByteArray()
	mask.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		if not _is_mountain_terrain(int(terrain_ids[index])):
			continue
		if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
			continue
		mask[index] = 1
	return mask

func _center_camera(target_chunk: Vector2i, target_local: Vector2i) -> void:
	var target_world_tile: Vector2i = target_chunk * WorldRuntimeConstants.CHUNK_SIZE + target_local
	_camera.position = WorldRuntimeConstants.tile_to_world_center(target_world_tile) \
		- WorldRuntimeConstants.chunk_origin_px(target_chunk)
	_camera.zoom = Vector2(0.65, 0.65)

func _update_debug_snapshot(
	spawn_tile: Vector2i,
	target: Dictionary,
	display_packets: Array[Dictionary]
) -> void:
	var displayed_mountain_cells: int = 0
	var displayed_chunks_with_mountain: int = 0
	for packet: Dictionary in display_packets:
		var stats: Dictionary = _summarize_mountain_packet(packet)
		var mountain_cells: int = int(stats.get("mountain_cells", 0))
		displayed_mountain_cells += mountain_cells
		if mountain_cells > 0:
			displayed_chunks_with_mountain += 1
	_debug_snapshot = {
		"ready": true,
		"seed": probe_seed,
		"world_version": WorldRuntimeConstants.WORLD_VERSION,
		"spawn_tile": spawn_tile,
		"target_chunk": target.get("chunk_coord", Vector2i.ZERO),
		"target_local": target.get("first_local", Vector2i.ZERO),
		"target_search_radius": int(target.get("search_radius", -1)),
		"target_mountain_cells": int(target.get("mountain_cells", 0)),
		"target_wall_cells": int(target.get("wall_cells", 0)),
		"target_foot_cells": int(target.get("foot_cells", 0)),
		"displayed_chunk_count": display_packets.size(),
		"displayed_chunks_with_mountain": displayed_chunks_with_mountain,
		"displayed_mountain_cells": displayed_mountain_cells,
	}
	if _plateau_layer != null and is_instance_valid(_plateau_layer):
		var plateau_debug: Dictionary = _plateau_layer.get_debug_snapshot()
		_debug_snapshot["plateau"] = plateau_debug
		_debug_snapshot["plateau_ready"] = bool(plateau_debug.get("ready", false))
		_debug_snapshot["plateau_mountain_tiles"] = int(plateau_debug.get("mountain_tile_count", 0))
		_debug_snapshot["plateau_edge_tiles"] = int(plateau_debug.get("edge_tile_count", 0))
		_debug_snapshot["plateau_connector_count"] = int(plateau_debug.get("right_connector_count", 0)) \
			+ int(plateau_debug.get("down_connector_count", 0))
		_debug_snapshot["plateau_exposed_edges"] = int(plateau_debug.get("exposed_edge_count", 0))
		_debug_snapshot["plateau_facade_edges"] = int(plateau_debug.get("facade_edge_count", 0))
		_debug_snapshot["plateau_rim_edges"] = int(plateau_debug.get("rim_edge_count", 0))
		_debug_snapshot["plateau_top_texture_loaded"] = bool(plateau_debug.get("top_texture_loaded", false))
		_debug_snapshot["plateau_face_texture_loaded"] = bool(plateau_debug.get("face_texture_loaded", false))
	if _raster_layer != null and is_instance_valid(_raster_layer):
		_sync_raster_debug_snapshot()
	_debug_snapshot["tuning_panel_ready"] = _tuning_panel != null and is_instance_valid(_tuning_panel)
	_debug_snapshot["raster_preset_path"] = RASTER_PRESET_PATH
	_debug_snapshot["raster_preset"] = _pending_raster_preset.duplicate(true)
	_sync_tuning_debug_snapshot()

func _update_info_label() -> void:
	if _info_label == null:
		return
	if not bool(_debug_snapshot.get("ready", false)):
		_info_label.text = "2D mountain dev scene: not ready"
		return
	_info_label.text = Mountain2DDevInfoText.build(
		_debug_snapshot,
		show_raster_layer,
		show_raster_light_preview,
		show_plateau_layer,
		show_tilemap_baseline,
		show_plateau_edge_debug,
		RASTER_PRESET_PATH
	)

func _apply_zoom(multiplier: float) -> void:
	var next_zoom: float = clampf(_camera.zoom.x * multiplier, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2(next_zoom, next_zoom)

func _set_failure(message: String) -> void:
	push_error(message)
	_debug_snapshot = {
		"ready": false,
		"error": message,
	}
	_update_info_label()

func _ensure_plateau_layer() -> MountainPlateau2DLayer:
	if _plateau_layer != null and is_instance_valid(_plateau_layer):
		return _plateau_layer
	_plateau_layer = MountainPlateau2DLayer.new()
	_plateau_layer.name = "MountainPlateau2DLayer"
	_plateau_layer.z_index = 20
	add_child(_plateau_layer)
	return _plateau_layer

func _ensure_raster_layer() -> MountainPlateau2DRasterLayer:
	if _raster_layer != null and is_instance_valid(_raster_layer):
		return _raster_layer
	_raster_layer = MountainPlateau2DRasterLayer.new()
	_raster_layer.name = "MountainPlateau2DRasterLayer"
	_raster_layer.z_index = 30
	_raster_layer.set_display_normal_map(show_raster_normal_preview)
	_raster_layer.set_display_light_map(show_raster_light_preview)
	add_child(_raster_layer)
	return _raster_layer

func _ensure_light_probe() -> Node2D:
	if _light_probe != null and is_instance_valid(_light_probe):
		return _light_probe
	_light_probe = Mountain2DLightProbeScript.new()
	_light_probe.name = "Mountain2DLightProbe"
	add_child(_light_probe)
	_light_probe.call("set_light_mode_enabled", show_raster_light_preview)
	return _light_probe

func _build_tuning_panel() -> void:
	if _tuning_panel != null and is_instance_valid(_tuning_panel):
		return
	_tuning_panel = PanelContainer.new()
	_tuning_panel.name = "RasterTuningPanel"
	_tuning_panel.anchor_left = 1.0
	_tuning_panel.anchor_right = 1.0
	_tuning_panel.anchor_top = 0.0
	_tuning_panel.anchor_bottom = 0.0
	_tuning_panel.offset_left = -TUNING_PANEL_WIDTH_PX
	_tuning_panel.offset_right = -16.0
	_tuning_panel.offset_top = 16.0
	_tuning_panel.offset_bottom = 740.0
	_tuning_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	$Hud.add_child(_tuning_panel)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	_tuning_panel.add_child(root_box)

	var title := Label.new()
	title.text = "Настройка 2D-горы"
	title.add_theme_font_size_override("font_size", 16)
	root_box.add_child(title)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 6)
	root_box.add_child(button_row)
	_add_tuning_button(button_row, "Применить", Callable(self, "apply_raster_preset"))
	_add_tuning_button(button_row, "Сохранить", Callable(self, "save_raster_preset"))
	_add_tuning_button(button_row, "Загрузить", Callable(self, "load_raster_preset"))
	_add_tuning_button(button_row, "Сброс", Callable(self, "reset_raster_preset"))

	_tuning_status_label = Label.new()
	_tuning_status_label.text = "Крути значения, потом жми Применить"
	_tuning_status_label.add_theme_font_size_override("font_size", 12)
	root_box.add_child(_tuning_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)

	var slider_box := VBoxContainer.new()
	slider_box.add_theme_constant_override("separation", 5)
	scroll.add_child(slider_box)

	var current_group: String = ""
	for spec: Dictionary in MountainPlateau2DRasterLayer.preset_specs():
		var group_name: String = _tuning_group_for_key(str(spec["key"]))
		if group_name != current_group:
			current_group = group_name
			_add_tuning_group_header(slider_box, current_group)
		_add_tuning_slider(slider_box, spec)
	_sync_tuning_controls_from_preset(_pending_raster_preset)
	_sync_tuning_debug_snapshot()

func _add_tuning_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(104.0, 32.0)
	button.pressed.connect(callback)
	parent.add_child(button)

func _add_tuning_group_header(parent: Control, text: String) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.96, 0.78, 0.46, 1.0))
	parent.add_child(label)

func _add_tuning_slider(parent: Control, spec: Dictionary) -> void:
	var key: String = str(spec["key"])
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)

	var name_label := Label.new()
	name_label.text = _tuning_label_for_key(key, str(spec["label"]))
	name_label.add_theme_font_size_override("font_size", 12)
	block.add_child(name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	block.add_child(row)

	var slider := HSlider.new()
	slider.min_value = float(spec["min"])
	slider.max_value = float(spec["max"])
	slider.step = float(spec["step"])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(360.0, 30.0)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_tuning_slider_changed.bind(key))
	row.add_child(slider)
	_tuning_sliders[key] = slider

	var spinbox := SpinBox.new()
	spinbox.min_value = float(spec["min"])
	spinbox.max_value = float(spec["max"])
	spinbox.step = float(spec["step"])
	spinbox.custom_minimum_size = Vector2(116.0, 30.0)
	spinbox.value_changed.connect(_on_tuning_slider_changed.bind(key))
	row.add_child(spinbox)
	_tuning_spinboxes[key] = spinbox

func _on_tuning_slider_changed(value: float, key: String) -> void:
	if _is_syncing_tuning_controls:
		return
	_pending_raster_preset[key] = value
	_is_syncing_tuning_controls = true
	_sync_one_tuning_control(key, value)
	_is_syncing_tuning_controls = false
	_set_tuning_status("Есть изменения: нажми Применить для пересборки")

func _sync_tuning_controls_from_preset(preset: Dictionary) -> void:
	_is_syncing_tuning_controls = true
	for key_variant: Variant in _tuning_sliders.keys():
		var key: String = str(key_variant)
		var value: float = float(preset.get(key, MountainPlateau2DRasterLayer.default_preset().get(key, 0.0)))
		_sync_one_tuning_control(key, value)
	_is_syncing_tuning_controls = false

func _sync_one_tuning_control(key: String, value: float) -> void:
	if _tuning_sliders.has(key):
		var slider: HSlider = _tuning_sliders[key] as HSlider
		slider.value = value
	if _tuning_spinboxes.has(key):
		var spinbox: SpinBox = _tuning_spinboxes[key] as SpinBox
		spinbox.value = value

func _tuning_group_for_key(key: String) -> String:
	var ui: Array = TUNING_UI_RU.get(key, ["Прочее", ""]) as Array
	return str(ui[0])

func _tuning_label_for_key(key: String, fallback: String) -> String:
	var ui: Array = TUNING_UI_RU.get(key, ["", fallback]) as Array
	return str(ui[1])

func _set_tuning_status(text: String) -> void:
	if _tuning_status_label != null and is_instance_valid(_tuning_status_label):
		_tuning_status_label.text = text

func _load_raster_preset_from_disk(report_missing: bool) -> bool:
	if not FileAccess.file_exists(RASTER_PRESET_PATH):
		if report_missing:
			_set_tuning_status("Preset-файл не найден")
		_pending_raster_preset = _raster_preset.duplicate(true)
		return false
	var file: FileAccess = FileAccess.open(RASTER_PRESET_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot load mountain raster preset: %s" % RASTER_PRESET_PATH)
		_set_tuning_status("Не удалось загрузить preset")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Mountain raster preset JSON must be a Dictionary: %s" % RASTER_PRESET_PATH)
		_set_tuning_status("Preset поврежден")
		return false
	_pending_raster_preset = parsed as Dictionary
	_raster_preset = _pending_raster_preset.duplicate(true)
	_set_tuning_status("Preset загружен")
	return true

func _sync_raster_debug_snapshot() -> void:
	if _raster_layer == null or not is_instance_valid(_raster_layer):
		return
	var raster_debug: Dictionary = _raster_layer.get_debug_snapshot()
	_debug_snapshot["raster"] = raster_debug
	_debug_snapshot["raster_ready"] = bool(raster_debug.get("ready", false))
	_debug_snapshot["raster_visible"] = bool(_raster_layer.visible)
	_debug_snapshot["raster_mountain_tiles"] = int(raster_debug.get("mountain_tile_count", 0))
	_debug_snapshot["raster_top_pixels"] = int(raster_debug.get("top_pixel_count", 0))
	_debug_snapshot["raster_face_pixels"] = int(raster_debug.get("face_pixel_count", 0))
	_debug_snapshot["raster_rim_pixels"] = int(raster_debug.get("rim_pixel_count", 0))
	_debug_snapshot["raster_image_width"] = int(raster_debug.get("image_width", 0))
	_debug_snapshot["raster_image_height"] = int(raster_debug.get("image_height", 0))
	_debug_snapshot["raster_normal_ready"] = bool(raster_debug.get("normal_ready", false))
	_debug_snapshot["raster_normal_preview"] = bool(raster_debug.get("normal_preview", false))
	_debug_snapshot["raster_normal_image_width"] = int(raster_debug.get("normal_image_width", 0))
	_debug_snapshot["raster_normal_image_height"] = int(raster_debug.get("normal_image_height", 0))
	_debug_snapshot["raster_normal_pixel_count"] = int(raster_debug.get("normal_pixel_count", 0))
	_debug_snapshot["raster_light_preview"] = bool(raster_debug.get("light_preview", false))
	_debug_snapshot["raster_lit_texture_ready"] = bool(raster_debug.get("lit_texture_ready", false))
	_debug_snapshot["raster_light_split_surface_ready"] = bool(raster_debug.get("lit_split_surface_ready", false))
	_debug_snapshot["raster_light_occluder_ready"] = bool(raster_debug.get("light_occluder_ready", false))
	_debug_snapshot["raster_light_occluder_point_count"] = int(raster_debug.get("light_occluder_point_count", 0))
	var light_debug: Dictionary = {}
	if _light_probe != null and is_instance_valid(_light_probe):
		light_debug = _light_probe.call("get_debug_snapshot") as Dictionary
	_debug_snapshot["raster_light"] = light_debug
	_debug_snapshot["raster_light_node_ready"] = bool(light_debug.get("node_ready", false))
	_debug_snapshot["raster_preset"] = raster_debug.get("preset", _pending_raster_preset)
	_debug_snapshot["raster_preset_path"] = RASTER_PRESET_PATH
	_debug_snapshot["tuning_panel_ready"] = _tuning_panel != null and is_instance_valid(_tuning_panel)
	_sync_tuning_debug_snapshot()

func _sync_tuning_debug_snapshot() -> void:
	_debug_snapshot["tuning_panel_locale"] = "ru"
	_debug_snapshot["tuning_panel_width_px"] = TUNING_PANEL_WIDTH_PX
	_debug_snapshot["tuning_slider_count"] = _tuning_sliders.size()
	_debug_snapshot["tuning_numeric_input_count"] = _tuning_spinboxes.size()
	_debug_snapshot["tuning_has_ru_labels"] = true

func _sync_compare_visibility() -> void:
	var has_custom_mountain_layer: bool = show_plateau_layer or show_raster_layer
	_terrain_root.visible = show_tilemap_baseline or not has_custom_mountain_layer
	_terrain_root.modulate = Color(1.0, 1.0, 1.0, tilemap_baseline_alpha if has_custom_mountain_layer else 1.0)
	if _plateau_layer != null and is_instance_valid(_plateau_layer):
		_plateau_layer.visible = show_plateau_layer
	if _raster_layer != null and is_instance_valid(_raster_layer):
		_raster_layer.set_display_light_map(show_raster_light_preview)
		if not show_raster_light_preview:
			_raster_layer.set_display_normal_map(show_raster_normal_preview)
		_raster_layer.visible = show_raster_layer
		_debug_snapshot["raster_visible"] = show_raster_layer
	_update_info_label()

func _canonicalize_chunk(chunk_coord: Vector2i) -> Vector2i:
	if not WorldRuntimeConstants.uses_world_foundation(WorldRuntimeConstants.WORLD_VERSION):
		return chunk_coord
	return _world_bounds.canonicalize_chunk(chunk_coord)

func _is_chunk_y_in_bounds(chunk_coord: Vector2i) -> bool:
	if not WorldRuntimeConstants.uses_world_foundation(WorldRuntimeConstants.WORLD_VERSION):
		return true
	return _world_bounds.is_chunk_y_in_bounds(chunk_coord.y)

func _is_mountain_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
		or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED
