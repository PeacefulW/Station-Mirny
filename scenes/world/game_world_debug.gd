class_name GameWorldDebug
extends Node

## Debug-оверлей: FPS-счётчик, подсветка тайла, отладочное размещение скал.
## Извлечён из GameWorld для изоляции debug-кода от runtime (Iteration 5, ADR-0001).

const RuntimeValidationDriverScript = preload("res://core/debug/runtime_validation_driver.gd")

var _chunk_manager: ChunkManager = null
var _ui_layer: CanvasLayer = null
var _fps_label: Label = null
var _fps_log_timer: float = 0.0
var _tile_highlight: ColorRect = null
var _tile_info_label: Label = null

func setup(chunk_manager: ChunkManager, ui_layer: CanvasLayer) -> void:
	_chunk_manager = chunk_manager
	_ui_layer = ui_layer
	_setup_fps_counter()
	_setup_tile_highlight()
	_setup_runtime_validation_driver()

func _process(delta: float) -> void:
	_update_fps(delta)
	_update_tile_highlight()

func _unhandled_input(event: InputEvent) -> void:
	if not _chunk_manager or not WorldGenerator:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			_debug_toggle_rock(true)
		elif event.keycode == KEY_H:
			_debug_toggle_rock(false)

func _debug_toggle_rock(place: bool) -> void:
	var mouse_pos: Vector2 = get_parent().get_global_mouse_position()
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(mouse_pos)
	var chunk_coord: Vector2i = WorldGenerator.tile_to_chunk(tile_pos)
	var chunk: Chunk = _chunk_manager.get_chunk(chunk_coord)
	if not chunk:
		return
	var local: Vector2i = chunk.global_to_local(tile_pos)
	var current_type: int = chunk.get_terrain_type_at(local)
	if place and current_type != TileGenData.TerrainType.ROCK:
		chunk._set_terrain_type(local, TileGenData.TerrainType.ROCK)
	elif not place and current_type == TileGenData.TerrainType.ROCK:
		chunk._set_terrain_type(local, TileGenData.TerrainType.GROUND)
	else:
		return
	chunk._cache_has_mountain()
	var dirty: Dictionary = {}
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var t: Vector2i = local + Vector2i(dx, dy)
			if chunk._is_inside(t):
				dirty[t] = true
	chunk._redraw_dirty_tiles(dirty)

func _setup_fps_counter() -> void:
	_fps_label = Label.new()
	_fps_label.name = "FPSLabel"
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.0, 0.8))
	_fps_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	_fps_label.add_theme_constant_override("shadow_offset_x", 1)
	_fps_label.add_theme_constant_override("shadow_offset_y", 1)
	_fps_label.position = Vector2(8, 8)
	if _ui_layer:
		_ui_layer.add_child(_fps_label)

func _setup_tile_highlight() -> void:
	_tile_highlight = ColorRect.new()
	_tile_highlight.name = "TileHighlight"
	_tile_highlight.color = Color(1.0, 1.0, 0.0, 0.25)
	_tile_highlight.z_index = 100
	_tile_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(_tile_highlight)
	_tile_info_label = Label.new()
	_tile_info_label.name = "TileInfoLabel"
	_tile_info_label.add_theme_font_size_override("font_size", 12)
	_tile_info_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0, 0.9))
	_tile_info_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_tile_info_label.add_theme_constant_override("shadow_offset_x", 1)
	_tile_info_label.add_theme_constant_override("shadow_offset_y", 1)
	_tile_info_label.position = Vector2(8, 60)
	if _ui_layer:
		_ui_layer.add_child(_tile_info_label)

func _setup_runtime_validation_driver() -> void:
	var driver := RuntimeValidationDriverScript.new()
	driver.name = "RuntimeValidationDriver"
	get_parent().add_child(driver)

func _update_tile_highlight() -> void:
	if not _tile_highlight or not WorldGenerator or not _chunk_manager:
		return
	var mouse_pos: Vector2 = get_parent().get_global_mouse_position()
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(mouse_pos)
	var ts: int = WorldGenerator.balance.tile_size
	_tile_highlight.size = Vector2(ts, ts)
	_tile_highlight.global_position = Vector2(tile_pos.x * ts, tile_pos.y * ts)
	if _tile_info_label:
		var chunk: Chunk = _chunk_manager.get_chunk_at_tile(tile_pos)
		if chunk:
			var local: Vector2i = chunk.global_to_local(tile_pos)
			var terrain: int = chunk.get_terrain_type_at(local)
			var type_name: String = "GROUND"
			match terrain:
				TileGenData.TerrainType.ROCK: type_name = "ROCK"
				TileGenData.TerrainType.MINED_FLOOR: type_name = "MINED"
				TileGenData.TerrainType.MOUNTAIN_ENTRANCE: type_name = "ENTRANCE"
				TileGenData.TerrainType.WATER: type_name = "WATER"
				TileGenData.TerrainType.SAND: type_name = "SAND"
				TileGenData.TerrainType.GRASS: type_name = "GRASS"
			_tile_info_label.text = "Tile: %s | %s | local:%s" % [tile_pos, type_name, local]
		else:
			_tile_info_label.text = "Tile: %s | unloaded" % [tile_pos]

func _update_fps(delta: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	if _fps_label:
		_fps_label.text = "FPS: %d" % int(fps)
	_fps_log_timer += delta
	if _fps_log_timer >= 5.0:
		_fps_log_timer = 0.0
		print("[WorldPerf] FPS: %.1f" % fps)
