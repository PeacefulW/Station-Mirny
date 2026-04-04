class_name WorldCreationScreen
extends Control

## Экран создания нового мира.
## Даёт seed и три параметра горной генерации: плотность, площадь и цепочки.

const GAME_SCENE_PATH: String = "res://scenes/world/game_world.tscn"
const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"

var _balance: WorldGenBalance = null
var _seed_input: LineEdit = null
var _mountain_count_slider: HSlider = null
var _mountain_area_slider: HSlider = null
var _mountain_chains_slider: HSlider = null
var _mountain_count_value_label: Label = null
var _mountain_area_value_label: Label = null
var _mountain_chains_value_label: Label = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _seed_label: Label = null
var _hint_label: Label = null
var _start_button: Button = null
var _random_button: Button = null
var _mountain_count_name_label: Label = null
var _mountain_area_name_label: Label = null
var _mountain_chains_name_label: Label = null
var _loading_screen: LoadingScreen = null
var _is_starting: bool = false

func _ready() -> void:
	if TimeManager and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)
	_balance = load(BALANCE_PATH) as WorldGenBalance
	_build_ui()
	_randomize_seed()
	_apply_localization()
	EventBus.language_changed.connect(_on_language_changed)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.05)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := VBoxContainer.new()
	center.set_anchors_preset(PRESET_CENTER)
	center.custom_minimum_size = Vector2(420, 0)
	center.position = Vector2(-210, -220)
	add_child(center)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	center.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 16)
	_subtitle_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40))
	center.add_child(_subtitle_label)
	center.add_child(_spacer(16))
	var seed_row := HBoxContainer.new()
	_seed_label = Label.new()
	_seed_label.custom_minimum_size.x = 120
	_seed_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	seed_row.add_child(_seed_label)
	_seed_input = LineEdit.new()
	_seed_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_seed_input.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	seed_row.add_child(_seed_input)
	_random_button = Button.new()
	_random_button.pressed.connect(_randomize_seed)
	seed_row.add_child(_random_button)
	center.add_child(seed_row)
	center.add_child(_spacer(12))
	var count_row: Array = _create_slider_row(5, 35, int(round(_balance.mountain_density * 100.0)), true)
	_mountain_count_slider = count_row[0]
	_mountain_count_value_label = count_row[1]
	_mountain_count_name_label = count_row[2]
	_mountain_count_slider.value_changed.connect(func(v: float) -> void:
		_mountain_count_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(v)})
	)
	center.add_child(count_row[3])
	var area_row: Array = _create_slider_row(1, 3, _balance.mountain_area, false)
	_mountain_area_slider = area_row[0]
	_mountain_area_slider.step = 1.0
	_mountain_area_value_label = area_row[1]
	_mountain_area_name_label = area_row[2]
	_mountain_area_value_label.text = _mountain_size_text(_balance.mountain_area)
	_mountain_area_slider.value_changed.connect(func(v: float) -> void:
		_mountain_area_value_label.text = _mountain_size_text(int(v))
	)
	center.add_child(area_row[3])
	var chain_row: Array = _create_slider_row(0, 100, int(round(_balance.mountain_chaininess * 100.0)), true)
	_mountain_chains_slider = chain_row[0]
	_mountain_chains_value_label = chain_row[1]
	_mountain_chains_name_label = chain_row[2]
	_mountain_chains_slider.value_changed.connect(func(v: float) -> void:
		_mountain_chains_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(v)})
	)
	center.add_child(chain_row[3])
	center.add_child(_spacer(6))
	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.40, 0.38, 0.32))
	center.add_child(_hint_label)
	center.add_child(_spacer(16))
	_start_button = Button.new()
	_start_button.custom_minimum_size.y = 50
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.pressed.connect(_on_start_pressed)
	center.add_child(_start_button)

func _randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed_input.text = str(rng.randi_range(10000, 99999))

func _on_start_pressed() -> void:
	if _is_starting:
		return
	if not _balance:
		push_error(Localization.t("SYSTEM_WORLD_BALANCE_MISSING"))
		return
	_is_starting = true
	_set_start_controls_enabled(false)
	_balance.mountain_density = _mountain_count_slider.value / 100.0
	_balance.mountain_area = int(_mountain_area_slider.value)
	_balance.mountain_chaininess = _mountain_chains_slider.value / 100.0
	var seed_text: String = _seed_input.text.strip_edges()
	var seed_val: int = 0
	if seed_text.is_valid_int():
		seed_val = seed_text.to_int()
	elif seed_text.length() > 0:
		seed_val = seed_text.hash()
	else:
		seed_val = randi()
	SaveManager.clear_pending_load_request()
	call_deferred("_begin_world_start", seed_val)

func _begin_world_start(seed_val: int) -> void:
	if not is_inside_tree():
		return
	if _loading_screen == null:
		_loading_screen = LoadingScreen.new()
		_loading_screen.name = "LoadingScreen"
		add_child(_loading_screen)
	if not _loading_screen.is_presented():
		await _loading_screen.screen_presented
	_loading_screen.set_progress(5.0, Localization.t("UI_LOADING_INITIALIZING_WORLD"))
	await get_tree().process_frame
	var initialize_usec: int = WorldPerfProbe.begin()
	WorldGenerator.initialize_world(seed_val)
	WorldPerfProbe.end("WorldCreationScreen.initialize_world_before_scene_change", initialize_usec)
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _set_start_controls_enabled(enabled: bool) -> void:
	if _seed_input:
		_seed_input.editable = enabled
	if _random_button:
		_random_button.disabled = not enabled
	if _start_button:
		_start_button.disabled = not enabled

func _mountain_size_text(size: int) -> String:
	match size:
		1:
			return Localization.t("UI_WORLD_CREATE_MTN_SMALL")
		2:
			return Localization.t("UI_WORLD_CREATE_MTN_MEDIUM")
		3:
			return Localization.t("UI_WORLD_CREATE_MTN_LARGE")
	return str(size)

func _create_slider_row(min_val: float, max_val: float, default_val: float, is_percent: bool) -> Array:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size.x = 140
	label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = 1.0
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(default_val)}) if is_percent else Localization.t("UI_WORLD_CREATE_NUMBER", {"value": int(default_val)})
	value_label.custom_minimum_size.x = 80
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	row.add_child(value_label)
	return [slider, value_label, label, row]

func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer

func _apply_localization() -> void:
	_title_label.text = Localization.t("UI_WORLD_CREATE_TITLE")
	_subtitle_label.text = Localization.t("UI_WORLD_CREATE_SUBTITLE")
	_seed_label.text = Localization.t("UI_WORLD_CREATE_SEED_LABEL")
	_seed_input.placeholder_text = Localization.t("UI_WORLD_CREATE_SEED_PLACEHOLDER")
	_random_button.text = Localization.t("UI_WORLD_CREATE_RANDOM_BUTTON")
	_mountain_count_name_label.text = Localization.t("UI_WORLD_CREATE_MOUNTAIN_COUNT_LABEL")
	_mountain_area_name_label.text = Localization.t("UI_WORLD_CREATE_MOUNTAIN_AREA_LABEL")
	_mountain_chains_name_label.text = Localization.t("UI_WORLD_CREATE_MOUNTAIN_CHAINS_LABEL")
	_hint_label.text = Localization.t("UI_WORLD_CREATE_HINT")
	_start_button.text = Localization.t("UI_WORLD_CREATE_START_BUTTON")
	_mountain_count_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(_mountain_count_slider.value)})
	_mountain_area_value_label.text = _mountain_size_text(int(_mountain_area_slider.value))
	_mountain_chains_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(_mountain_chains_slider.value)})

func _on_language_changed(_locale_code: String) -> void:
	_apply_localization()
