class_name WorldCreationScreen
extends Control

## Экран создания нового мира. Игрок настраивает seed и
## параметры генерации, затем нажимает кнопку старта.
## Настройки передаются в WorldGenerator перед загрузкой мира.

const GAME_SCENE_PATH: String = "res://scenes/world/game_world.tscn"
const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"

var _balance: WorldGenBalance = null
var _seed_input: LineEdit = null
var _water_slider: HSlider = null
var _rock_slider: HSlider = null
var _warp_slider: HSlider = null
var _ridge_slider: HSlider = null
var _water_value_label: Label = null
var _rock_value_label: Label = null
var _warp_value_label: Label = null
var _ridge_value_label: Label = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _seed_label: Label = null
var _hint_label: Label = null
var _start_button: Button = null
var _random_button: Button = null
var _water_name_label: Label = null
var _rock_name_label: Label = null
var _warp_name_label: Label = null
var _ridge_name_label: Label = null

func _ready() -> void:
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

	center.add_child(_spacer(20))

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

	center.add_child(_spacer(16))

	var water_row: Array = _create_slider_row(10, 50, 30, true)
	_water_slider = water_row[0]
	_water_value_label = water_row[1]
	_water_name_label = water_row[2]
	_water_slider.value_changed.connect(func(v: float) -> void: _water_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(v)}))
	center.add_child(water_row[3])

	var rock_row: Array = _create_slider_row(55, 90, 73, true)
	_rock_slider = rock_row[0]
	_rock_value_label = rock_row[1]
	_rock_name_label = rock_row[2]
	_rock_slider.value_changed.connect(func(v: float) -> void: _rock_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(v)}))
	center.add_child(rock_row[3])

	var warp_row: Array = _create_slider_row(0, 50, 25, false)
	_warp_slider = warp_row[0]
	_warp_value_label = warp_row[1]
	_warp_name_label = warp_row[2]
	_warp_slider.value_changed.connect(func(v: float) -> void: _warp_value_label.text = Localization.t("UI_WORLD_CREATE_NUMBER", {"value": int(v)}))
	center.add_child(warp_row[3])

	var ridge_row: Array = _create_slider_row(0, 50, 30, true)
	_ridge_slider = ridge_row[0]
	_ridge_value_label = ridge_row[1]
	_ridge_name_label = ridge_row[2]
	_ridge_slider.value_changed.connect(func(v: float) -> void: _ridge_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(v)}))
	center.add_child(ridge_row[3])

	center.add_child(_spacer(8))

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.40, 0.38, 0.32))
	center.add_child(_hint_label)

	center.add_child(_spacer(24))

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
	if not _balance:
		push_error(Localization.t("SYSTEM_WORLD_BALANCE_MISSING"))
		return

	_balance.water_threshold = _water_slider.value / 100.0
	_balance.rock_threshold = _rock_slider.value / 100.0
	_balance.warp_strength = _warp_slider.value
	_balance.ridge_weight = _ridge_slider.value / 100.0

	var seed_text: String = _seed_input.text.strip_edges()
	var seed_val: int = 0
	if seed_text.is_valid_int():
		seed_val = seed_text.to_int()
	elif seed_text.length() > 0:
		seed_val = seed_text.hash()
	else:
		seed_val = randi()

	WorldGenerator.initialize_world(seed_val)
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _create_slider_row(min_val: float, max_val: float, default_val: float, is_percent: bool) -> Array:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size.x = 120
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
	value_label.custom_minimum_size.x = 50
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
	_water_name_label.text = Localization.t("UI_WORLD_CREATE_WATER_LABEL")
	_rock_name_label.text = Localization.t("UI_WORLD_CREATE_ROCK_LABEL")
	_warp_name_label.text = Localization.t("UI_WORLD_CREATE_WARP_LABEL")
	_ridge_name_label.text = Localization.t("UI_WORLD_CREATE_RIDGE_LABEL")
	_hint_label.text = Localization.t("UI_WORLD_CREATE_HINT")
	_start_button.text = Localization.t("UI_WORLD_CREATE_START_BUTTON")
	_water_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(_water_slider.value)})
	_rock_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(_rock_slider.value)})
	_warp_value_label.text = Localization.t("UI_WORLD_CREATE_NUMBER", {"value": int(_warp_slider.value)})
	_ridge_value_label.text = Localization.t("UI_WORLD_CREATE_PERCENT", {"value": int(_ridge_slider.value)})

func _on_language_changed(_locale_code: String) -> void:
	_apply_localization()