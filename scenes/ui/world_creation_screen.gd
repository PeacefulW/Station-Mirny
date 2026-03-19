class_name WorldCreationScreen
extends Control

## Экран создания нового мира. Игрок настраивает seed и
## параметры генерации, затем нажимает "Начать".
## Настройки передаются в WorldGenerator перед загрузкой мира.

# --- Константы ---
const GAME_SCENE_PATH: String = "res://scenes/world/game_world.tscn"
const BALANCE_PATH: String = "res://data/world/world_gen_balance.tres"

# --- Приватные ---
var _balance: WorldGenBalance = null
var _seed_input: LineEdit = null
var _water_slider: HSlider = null
var _rock_slider: HSlider = null
var _warp_slider: HSlider = null
var _ridge_slider: HSlider = null
var _water_label: Label = null
var _rock_label: Label = null
var _warp_label: Label = null
var _ridge_label: Label = null

func _ready() -> void:
	_balance = load(BALANCE_PATH) as WorldGenBalance
	_build_ui()
	_randomize_seed()

# --- Построение UI ---

func _build_ui() -> void:
	# Фон
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.05)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	# Контейнер по центру
	var center := VBoxContainer.new()
	center.set_anchors_preset(PRESET_CENTER)
	center.custom_minimum_size = Vector2(420, 0)
	center.position = Vector2(-210, -220)
	add_child(center)

	# Заголовок
	var title := Label.new()
	title.text = "СТАНЦИЯ «МИРНЫЙ»"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Создание нового мира"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40))
	center.add_child(subtitle)

	center.add_child(_spacer(20))

	# Seed
	var seed_row := HBoxContainer.new()
	var seed_label := Label.new()
	seed_label.text = "Seed мира:"
	seed_label.custom_minimum_size.x = 120
	seed_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	seed_row.add_child(seed_label)

	_seed_input = LineEdit.new()
	_seed_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_seed_input.placeholder_text = "Число или слово"
	_seed_input.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	seed_row.add_child(_seed_input)

	var rand_btn := Button.new()
	rand_btn.text = "Случайный"
	rand_btn.pressed.connect(_randomize_seed)
	seed_row.add_child(rand_btn)
	center.add_child(seed_row)

	center.add_child(_spacer(16))

	# Слайдеры
	var water_row: Array = _create_slider_row("Уровень воды:", 10, 50, 30, "%")
	_water_slider = water_row[0]
	_water_label = water_row[1]
	_water_slider.value_changed.connect(func(v: float) -> void: _water_label.text = "%d%%" % int(v))
	center.add_child(water_row[2])

	var rock_row: Array = _create_slider_row("Высота гор:", 55, 90, 73, "%")
	_rock_slider = rock_row[0]
	_rock_label = rock_row[1]
	_rock_slider.value_changed.connect(func(v: float) -> void: _rock_label.text = "%d%%" % int(v))
	center.add_child(rock_row[2])

	var warp_row: Array = _create_slider_row("Извилистость:", 0, 50, 25, "")
	_warp_slider = warp_row[0]
	_warp_label = warp_row[1]
	_warp_slider.value_changed.connect(func(v: float) -> void: _warp_label.text = "%d" % int(v))
	center.add_child(warp_row[2])

	var ridge_row: Array = _create_slider_row("Горные хребты:", 0, 50, 30, "%")
	_ridge_slider = ridge_row[0]
	_ridge_label = ridge_row[1]
	_ridge_slider.value_changed.connect(func(v: float) -> void: _ridge_label.text = "%d%%" % int(v))
	center.add_child(ridge_row[2])

	center.add_child(_spacer(8))

	# Подсказки
	var hint := Label.new()
	hint.text = "Одинаковый seed = одинаковая планета"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.40, 0.38, 0.32))
	center.add_child(hint)

	center.add_child(_spacer(24))

	# Кнопка старта
	var start_btn := Button.new()
	start_btn.text = "▶  ВЫСАДКА НА ПЛАНЕТУ"
	start_btn.custom_minimum_size.y = 50
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.pressed.connect(_on_start_pressed)
	center.add_child(start_btn)

# --- Обработчики ---

func _randomize_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed_input.text = str(rng.randi_range(10000, 99999))

func _on_start_pressed() -> void:
	if not _balance:
		push_error("WorldCreationScreen: баланс не загружен")
		return

	# Применяем настройки игрока к балансу
	_balance.water_threshold = _water_slider.value / 100.0
	_balance.rock_threshold = _rock_slider.value / 100.0
	_balance.warp_strength = _warp_slider.value
	_balance.ridge_weight = _ridge_slider.value / 100.0

	# Вычисляем seed из текста (число или хеш строки)
	var seed_text: String = _seed_input.text.strip_edges()
	var seed_val: int = 0
	if seed_text.is_valid_int():
		seed_val = seed_text.to_int()
	elif seed_text.length() > 0:
		seed_val = seed_text.hash()
	else:
		seed_val = randi()

	# Инициализируем генератор
	WorldGenerator.initialize_world(seed_val)

	# Переходим к игровой сцене
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

# --- Утилиты ---

func _create_slider_row(label_text: String, min_val: float, max_val: float, default_val: float, suffix: String) -> Array:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
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

	var val_label := Label.new()
	val_label.text = "%d%s" % [int(default_val), suffix]
	val_label.custom_minimum_size.x = 50
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	row.add_child(val_label)

	return [slider, val_label, row]

func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = height
	return s
