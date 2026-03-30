class_name GameWorldDebug
extends Node

## Debug-оверлей: FPS-счётчик, подсветка тайла, отладочное размещение скал.
## Извлечён из GameWorld для изоляции debug-кода от runtime (Iteration 5, ADR-0001).

const RuntimeValidationDriverScript = preload("res://core/debug/runtime_validation_driver.gd")
const WorldPreviewExporterScript = preload("res://core/debug/world_preview_exporter.gd")
const LOCAL_PREVIEW_TEXTURE_SIZE: Vector2 = Vector2(300, 300)

var _chunk_manager: ChunkManager = null
var _ui_layer: CanvasLayer = null
var _game_world: GameWorld = null
var _fps_label: Label = null
var _fps_log_timer: float = 0.0
var _tile_highlight: ColorRect = null
var _tile_info_label: Label = null
var _last_highlighted_tile: Vector2i = Vector2i(999999, 999999)
var _last_tile_data: TileGenData = null
var _stairs_container: Node2D = null
var _world_preview_exporter: WorldPreviewExporter = null
var _local_preview_panel: PanelContainer = null
var _local_preview_header_label: Label = null
var _local_preview_hint_label: Label = null
var _local_preview_biome_rect: TextureRect = null
var _local_preview_terrain_rect: TextureRect = null
var _local_preview_structure_rect: TextureRect = null

func setup(chunk_manager: ChunkManager, ui_layer: CanvasLayer, game_world: GameWorld = null) -> void:
	_chunk_manager = chunk_manager
	_ui_layer = ui_layer
	_game_world = game_world
	_setup_fps_counter()
	_setup_tile_highlight()
	_setup_runtime_validation_driver()
	_setup_world_preview_exporter()
	_setup_local_preview_panel()

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
		elif event.keycode == KEY_J:
			_debug_spawn_underground_pocket()
		elif event.keycode == KEY_F6:
			call_deferred("_debug_capture_local_preview")
		elif event.keycode == KEY_F7:
			_toggle_local_preview_panel()
		elif event.keycode == KEY_F8:
			call_deferred("_debug_export_world_preview")

func _debug_toggle_rock(place: bool) -> void:
	var mouse_pos: Vector2 = get_parent().get_global_mouse_position()
	if not place:
		_chunk_manager.try_harvest_at_world(mouse_pos)
		return
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(mouse_pos)
	var chunk: Chunk = _chunk_manager.get_chunk_at_tile(tile_pos)
	if not chunk:
		return
	var local_tile: Vector2i = chunk.global_to_local(tile_pos)
	var current_type: int = chunk.get_terrain_type_at(local_tile)
	if current_type == TileGenData.TerrainType.ROCK:
		return
	chunk.set_mining_write_authorized(true)
	chunk._set_terrain_type(local_tile, TileGenData.TerrainType.ROCK)
	chunk.mark_tile_modified(local_tile, {"terrain": TileGenData.TerrainType.ROCK})
	chunk.set_mining_write_authorized(false)
	chunk._refresh_open_neighbors(local_tile)
	chunk._redraw_terrain_tile(local_tile)
	## Redraw cardinal AND diagonal neighbors — wall form depends on all 8 directions.
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor: Vector2i = local_tile + Vector2i(dx, dy)
			if chunk._is_inside(neighbor):
				chunk._redraw_terrain_tile(neighbor)
	_chunk_manager._on_mountain_tile_changed(tile_pos, current_type, TileGenData.TerrainType.ROCK)

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

func _setup_world_preview_exporter() -> void:
	if WorldGenerator:
		_world_preview_exporter = WorldPreviewExporterScript.new().initialize(WorldGenerator)

func _setup_local_preview_panel() -> void:
	_local_preview_panel = PanelContainer.new()
	_local_preview_panel.name = "LocalWorldPreviewPanel"
	_local_preview_panel.visible = false
	_local_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_local_preview_panel.position = Vector2(12, 116)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	panel_style.border_color = Color(0.30, 0.34, 0.42, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10
	_local_preview_panel.add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_local_preview_panel.add_child(root)

	_local_preview_header_label = Label.new()
	_local_preview_header_label.add_theme_font_size_override("font_size", 13)
	_local_preview_header_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96))
	_local_preview_header_label.text = "Local generator preview"
	root.add_child(_local_preview_header_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)

	_local_preview_biome_rect = _create_local_preview_card(row, "Biomes")
	_local_preview_terrain_rect = _create_local_preview_card(row, "Terrain")
	_local_preview_structure_rect = _create_local_preview_card(row, "Structures")

	_local_preview_hint_label = Label.new()
	_local_preview_hint_label.add_theme_font_size_override("font_size", 11)
	_local_preview_hint_label.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68))
	_local_preview_hint_label.text = "F6 snapshot + save | F7 hide/show | F8 full export"
	root.add_child(_local_preview_hint_label)

	if _ui_layer:
		_ui_layer.add_child(_local_preview_panel)
	else:
		get_parent().add_child(_local_preview_panel)

func _create_local_preview_card(parent: BoxContainer, title: String) -> TextureRect:
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(LOCAL_PREVIEW_TEXTURE_SIZE.x, 0.0)
	card.add_theme_constant_override("separation", 4)
	parent.add_child(card)

	var title_label := Label.new()
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	title_label.text = title
	card.add_child(title_label)

	var preview_bg := Panel.new()
	preview_bg.custom_minimum_size = LOCAL_PREVIEW_TEXTURE_SIZE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.10, 0.11, 0.14, 1.0)
	bg_style.border_color = Color(0.20, 0.24, 0.30, 1.0)
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(4)
	preview_bg.add_theme_stylebox_override("panel", bg_style)
	card.add_child(preview_bg)

	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_bg.add_child(texture_rect)

	return texture_rect

func _toggle_local_preview_panel() -> void:
	if _local_preview_panel:
		_local_preview_panel.visible = not _local_preview_panel.visible

func _debug_capture_local_preview() -> void:
	if _world_preview_exporter == null:
		_setup_world_preview_exporter()
	if _world_preview_exporter == null:
		print("[Debug] Local world preview exporter is unavailable.")
		return
	var center_tile: Vector2i = _get_preview_center_tile()
	var preview: Dictionary = _world_preview_exporter.build_local_preview(center_tile)
	if preview.is_empty():
		print("[Debug] Local world preview build failed.")
		return
	_apply_preview_image(_local_preview_biome_rect, preview.get("biomes_image", null) as Image)
	_apply_preview_image(_local_preview_terrain_rect, preview.get("terrain_image", null) as Image)
	_apply_preview_image(_local_preview_structure_rect, preview.get("structures_image", null) as Image)
	var resolved_center_tile: Vector2i = preview.get("center_tile", center_tile)
	var radius_tiles: int = int(preview.get("radius_tiles", 0))
	var saved: Dictionary = _world_preview_exporter.save_local_preview(preview)
	if _local_preview_header_label:
		_local_preview_header_label.text = "Local generator preview | center:%s | radius:%d tiles" % [resolved_center_tile, radius_tiles]
	if _local_preview_panel:
		_local_preview_panel.visible = true
	print("[Debug] Local world preview updated at %s." % [resolved_center_tile])
	if not saved.is_empty():
		print("[Debug] Local world preview saved:")
		print("  biomes: %s" % [saved.get("biomes", "")])
		print("  terrain: %s" % [saved.get("terrain", "")])
		print("  structures: %s" % [saved.get("structures", "")])

func _get_preview_center_tile() -> Vector2i:
	if not WorldGenerator:
		return Vector2i.ZERO
	var mouse_pos: Vector2 = get_parent().get_global_mouse_position()
	return WorldGenerator.world_to_tile(mouse_pos)

func _apply_preview_image(texture_rect: TextureRect, image: Image) -> void:
	if texture_rect == null or image == null:
		return
	texture_rect.texture = ImageTexture.create_from_image(image)

func _update_tile_highlight() -> void:
	if not _tile_highlight or not WorldGenerator or not _chunk_manager:
		return
	var mouse_pos: Vector2 = get_parent().get_global_mouse_position()
	var tile_pos: Vector2i = WorldGenerator.world_to_tile(mouse_pos)
	var ts: int = WorldGenerator.balance.tile_size
	_tile_highlight.size = Vector2(ts, ts)
	_tile_highlight.global_position = Vector2(tile_pos.x * ts, tile_pos.y * ts)
	if _tile_info_label:
		if tile_pos != _last_highlighted_tile:
			_last_highlighted_tile = tile_pos
			_last_tile_data = WorldGenerator.get_tile_data(tile_pos.x, tile_pos.y)
		var tile_data: TileGenData = _last_tile_data
		var biome_text: String = "biome:-"
		var variation_text: String = "subzone:none"
		var structure_text: String = "ridge:- mass:- river:- flood:-"
		if tile_data:
			if not String(tile_data.biome_id).is_empty():
				biome_text = "biome:%s" % String(tile_data.biome_id)
			if tile_data.local_variation_id != 0 or tile_data.local_variation_score > 0.0:
				variation_text = "subzone:%s %.2f" % [String(tile_data.local_variation_kind), tile_data.local_variation_score]
			structure_text = "ridge:%.2f mass:%.2f river:%.2f flood:%.2f" % [
				tile_data.ridge_strength,
				tile_data.mountain_mass,
				tile_data.river_strength,
				tile_data.floodplain_strength
			]
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
			_tile_info_label.text = "Tile: %s | %s | %s | %s | local:%s" % [
				tile_pos,
				type_name,
				biome_text,
				variation_text,
				local
			]
			_tile_info_label.text += " | %s" % structure_text
		else:
			_tile_info_label.text = "Tile: %s | unloaded | %s | %s | %s" % [tile_pos, biome_text, variation_text, structure_text]

func _update_fps(delta: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	if _fps_label:
		_fps_label.text = "FPS: %d" % int(fps)
	_fps_log_timer += delta
	if _fps_log_timer >= 5.0:
		_fps_log_timer = 0.0
		print("[WorldPerf] FPS: %.1f" % fps)

func _debug_spawn_underground_pocket() -> void:
	if not _game_world or not _chunk_manager:
		return
	# Place at mouse cursor, like building placement
	var stair_pos: Vector2 = _game_world.get_global_mouse_position()
	var stair_tile: Vector2i = WorldGenerator.world_to_tile(stair_pos)
	# Snap to tile center
	var ts: int = WorldGenerator.balance.tile_size
	stair_pos = Vector2(stair_tile.x * ts + ts / 2, stair_tile.y * ts + ts / 2)
	# Create stairs container if needed
	if not _stairs_container:
		_stairs_container = Node2D.new()
		_stairs_container.name = "DebugStairsContainer"
		_game_world.add_child(_stairs_container)
	# Surface staircase (z=0 → z=-1)
	var stairs_down := ZStairs.new()
	stairs_down.target_z = -1
	stairs_down.source_z = 0
	stairs_down.global_position = stair_pos
	stairs_down.name = "DebugStairsDown_%d" % Time.get_ticks_msec()
	_stairs_container.add_child(stairs_down)
	# Underground staircase (z=-1 → z=0)
	var stairs_up := ZStairs.new()
	stairs_up.target_z = 0
	stairs_up.source_z = -1
	stairs_up.stairs_type = &"stairs_up"
	stairs_up.global_position = stair_pos
	stairs_up.name = "DebugStairsUp_%d" % Time.get_ticks_msec()
	_stairs_container.add_child(stairs_up)
	# Create underground pocket: stair tile + 3x3 area around it for movement space
	# Player spawns to the right of the staircase
	var pocket_tiles: Array = []
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 3):
			pocket_tiles.append(stair_tile + Vector2i(dx, dy))
	_chunk_manager.ensure_underground_pocket(stair_tile, pocket_tiles)
	print("[Debug] Underground pocket at cursor %s (tile %s). Walk into staircase to descend." % [stair_pos, stair_tile])

func _debug_export_world_preview() -> void:
	if _world_preview_exporter == null:
		_setup_world_preview_exporter()
	if _world_preview_exporter == null:
		print("[Debug] World preview exporter is unavailable.")
		return
	var exported: Dictionary = _world_preview_exporter.export_current_world_preview()
	if exported.is_empty():
		print("[Debug] World preview export failed.")
		return
	print("[Debug] World preview exported:")
	print("  biomes: %s" % [exported.get("biomes", "")])
	print("  terrain: %s" % [exported.get("terrain", "")])
	print("  structures: %s" % [exported.get("structures", "")])
