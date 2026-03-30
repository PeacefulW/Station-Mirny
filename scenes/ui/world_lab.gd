class_name WorldLab
extends Control

const BALANCE_PATH := "res://data/world/world_gen_balance.tres"
const GLOBAL_PREVIEW_MAX_DIM := 768
const LOCAL_PREVIEW_SIZE := 256
const RIVER_BASIN_MIN_TILES := 50
const NOISE_ISLAND_MAX_TILES := 20

const VIEW_MODE_BIOME := 0
const VIEW_MODE_TERRAIN := 1
const VIEW_MODE_STRUCTURE := 2
const PREVIEW_MODE_GLOBAL := 0
const PREVIEW_MODE_SPAWN_LOCAL := 1

const TERRAIN_COLORS := {
	TileGenData.TerrainType.GROUND: Color(0.35, 0.55, 0.25),
	TileGenData.TerrainType.ROCK: Color(0.55, 0.50, 0.48),
	TileGenData.TerrainType.WATER: Color(0.15, 0.35, 0.70),
	TileGenData.TerrainType.SAND: Color(0.70, 0.60, 0.35),
	TileGenData.TerrainType.GRASS: Color(0.40, 0.58, 0.25),
	TileGenData.TerrainType.MINED_FLOOR: Color(0.50, 0.42, 0.35),
	TileGenData.TerrainType.MOUNTAIN_ENTRANCE: Color(0.55, 0.48, 0.38),
}

var _seed_input: SpinBox
var _preview_mode_button: OptionButton
var _view_mode_button: OptionButton
var _cancel_button: Button
var _status_label: Label
var _map_preview: TextureRect
var _metrics_label: RichTextLabel
var _legend_panel: PanelContainer
var _legend_list: VBoxContainer

var _generation_id := 0
var _pending_generation_id := -1
var _is_generating := false
var _active_tasks: Dictionary = {}
var _worker_mutex: Mutex = Mutex.new()
var _worker_results: Dictionary = {}
var _current_result := {}
var _seed_history: Array[int] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	set_process(true)
	_build_ui()
	_rebuild_biome_legend(BiomeRegistry.get_palette_order())
	_update_side_panels()

func _process(_delta: float) -> void:
	if _active_tasks.is_empty():
		return
	var completed_generations: Array[int] = []
	for generation_variant: Variant in _active_tasks.keys():
		var generation_id: int = int(generation_variant)
		var task_id: int = int(_active_tasks.get(generation_id, -1))
		if task_id >= 0 and WorkerThreadPool.is_task_completed(task_id):
			completed_generations.append(generation_id)
	if completed_generations.is_empty():
		return
	completed_generations.sort()
	for generation_id: int in completed_generations:
		var task_id: int = int(_active_tasks.get(generation_id, -1))
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
		_active_tasks.erase(generation_id)
		_worker_mutex.lock()
		var payload: Dictionary = (_worker_results.get(generation_id, {}) as Dictionary).duplicate(true)
		_worker_results.erase(generation_id)
		_worker_mutex.unlock()
		if generation_id != _pending_generation_id or generation_id != _generation_id:
			continue
		_pending_generation_id = -1
		_is_generating = false
		_cancel_button.disabled = true
		if payload.is_empty():
			_finish_with_error("Generation returned no preview data.")
			continue
		_on_worker_done(payload)

func _unhandled_input(event: InputEvent) -> void:
	if _is_generating or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_LEFT, KEY_DOWN:
			_browse_seed(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_UP:
			_browse_seed(1)
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.07)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 40
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	var title := Label.new()
	title.text = "WorldLab"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.78, 0.38))
	top.add_child(title)
	top.add_child(_make_label("Seed:"))

	_seed_input = SpinBox.new()
	_seed_input.min_value = 1
	_seed_input.max_value = 999999
	_seed_input.step = 1
	_seed_input.value = 42
	_seed_input.custom_minimum_size.x = 120
	top.add_child(_seed_input)

	top.add_child(_make_label("Preview:"))
	_preview_mode_button = OptionButton.new()
	_preview_mode_button.add_item("Global")
	_preview_mode_button.add_item("Spawn Local")
	_preview_mode_button.selected = PREVIEW_MODE_GLOBAL
	_preview_mode_button.item_selected.connect(_on_preview_mode_changed)
	top.add_child(_preview_mode_button)

	top.add_child(_make_label("Map:"))
	_view_mode_button = OptionButton.new()
	_view_mode_button.add_item("Biome")
	_view_mode_button.add_item("Terrain")
	_view_mode_button.add_item("Structure")
	_view_mode_button.selected = VIEW_MODE_TERRAIN
	_view_mode_button.item_selected.connect(_on_view_mode_changed)
	top.add_child(_view_mode_button)

	top.add_child(_make_button("Generate", _on_generate_pressed, Vector2(110, 32)))
	_cancel_button = _make_button("Cancel", _on_cancel_pressed, Vector2(90, 32))
	_cancel_button.disabled = true
	top.add_child(_cancel_button)
	top.add_child(_make_button("Copy Seeds", _on_export_pressed, Vector2(110, 32)))
	top.add_child(_make_button("Back", _on_back_pressed, Vector2(80, 32)))

	_status_label = Label.new()
	_status_label.text = "Generate a fullscreen preview. Arrow keys browse seeds."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.add_theme_color_override("font_color", Color(0.58, 0.64, 0.60))
	top.add_child(_status_label)

	var preview_root := Control.new()
	preview_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(preview_root)

	_map_preview = TextureRect.new()
	_map_preview.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_root.add_child(_map_preview)

	_legend_panel = _make_panel(Vector2i(0, -320), Vector2i(260, 0), false)
	preview_root.add_child(_legend_panel)
	var legend_root := VBoxContainer.new()
	legend_root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	legend_root.offset_left = 10
	legend_root.offset_top = 10
	legend_root.offset_right = -10
	legend_root.offset_bottom = -10
	legend_root.add_theme_constant_override("separation", 6)
	_legend_panel.add_child(legend_root)
	var legend_title := Label.new()
	legend_title.text = "Biome Legend"
	legend_title.add_theme_font_size_override("font_size", 16)
	legend_root.add_child(legend_title)
	var legend_scroll := ScrollContainer.new()
	legend_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	legend_root.add_child(legend_scroll)
	_legend_list = VBoxContainer.new()
	_legend_list.add_theme_constant_override("separation", 4)
	legend_scroll.add_child(_legend_list)

	var metrics_panel := _make_panel(Vector2i(-360, -300), Vector2i(0, 0), true)
	preview_root.add_child(metrics_panel)
	_metrics_label = RichTextLabel.new()
	_metrics_label.fit_content = false
	_metrics_label.scroll_active = true
	_metrics_label.bbcode_enabled = false
	_metrics_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_metrics_label.offset_left = 10
	_metrics_label.offset_top = 10
	_metrics_label.offset_right = -10
	_metrics_label.offset_bottom = -10
	_metrics_label.text = "Metrics will appear here."
	metrics_panel.add_child(_metrics_label)

func _make_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label

func _make_button(text_value: String, callback: Callable, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = min_size
	button.pressed.connect(callback)
	return button

func _make_panel(top_left: Vector2i, bottom_right: Vector2i, from_right: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0 if from_right else 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0 if from_right else 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = top_left.x
	panel.offset_top = top_left.y
	panel.offset_right = bottom_right.x
	panel.offset_bottom = bottom_right.y
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.24, 0.28, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel
