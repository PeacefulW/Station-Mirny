class_name BuildMenu
extends Control

## Меню строительства. Появляется внизу экрана когда
## игрок нажимает B (режим строительства).
## Показывает доступные постройки, игрок выбирает и ставит.

# --- Сигналы ---
## Игрок выбрал постройку из меню.
signal building_selected(building: BuildingData)

# --- Приватные ---
var _container: HBoxContainer = null
var _panel: PanelContainer = null
var _label: Label = null
var _buttons: Array[Button] = []
var _buildings: Array[BuildingData] = []
var _selected_index: int = 0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_load_buildings()
	_build_ui()
	EventBus.build_mode_changed.connect(_on_build_mode_changed)

# --- Публичные методы ---

## Получить текущую выбранную постройку (или null).
func get_selected() -> BuildingData:
	if _selected_index >= 0 and _selected_index < _buildings.size():
		return _buildings[_selected_index]
	return null

## Выбрать постройку по индексу.
func select_index(index: int) -> void:
	if index < 0 or index >= _buildings.size():
		return
	_selected_index = index
	_update_selection_visual()
	building_selected.emit(_buildings[index])

# --- Построение UI ---

func _build_ui() -> void:
	# Панель внизу экрана
	_panel = PanelContainer.new()
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.position.y = -10
	_panel.mouse_filter = MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.07, 0.92)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Заголовок + подсказка
	var header := HBoxContainer.new()
	_label = Label.new()
	_label.text = "СТРОИТЕЛЬСТВО"
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	header.add_child(_label)

	var hint := Label.new()
	hint.text = "  |  ЛКМ — поставить  |  ПКМ — снести  |  B — закрыть"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.45, 0.43, 0.38))
	header.add_child(hint)
	vbox.add_child(header)

	# Кнопки построек
	_container = HBoxContainer.new()
	_container.add_theme_constant_override("separation", 6)

	for i: int in range(_buildings.size()):
		var bd: BuildingData = _buildings[i]
		var btn := _create_building_button(bd, i)
		_container.add_child(btn)
		_buttons.append(btn)

	vbox.add_child(_container)
	_panel.add_child(vbox)
	add_child(_panel)

	if not _buildings.is_empty():
		select_index(0)

func _create_building_button(bd: BuildingData, index: int) -> Button:
	var btn := Button.new()
	var hotkey_text: String = ""
	if bd.hotkey > 0 and bd.hotkey <= 9:
		hotkey_text = "[%d] " % bd.hotkey
	btn.text = "%s%s (%d)" % [hotkey_text, bd.display_name, bd.scrap_cost]
	btn.custom_minimum_size = Vector2(120, 36)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(select_index.bind(index))
	btn.mouse_filter = MOUSE_FILTER_STOP
	return btn

# --- Загрузка построек ---

func _load_buildings() -> void:
	var dir_path: String = "res://data/buildings/"
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_warning("BuildMenu: папка %s не найдена, использую встроенные" % dir_path)
		_load_default_buildings()
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: Resource = load(dir_path + file_name)
			if res is BuildingData:
				_buildings.append(res as BuildingData)
		file_name = dir.get_next()
	# Сортируем по категории, потом по имени
	_buildings.sort_custom(func(a: BuildingData, b: BuildingData) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.display_name < b.display_name
	)
	if _buildings.is_empty():
		_load_default_buildings()

## Встроенные постройки если .tres файлы не найдены.
func _load_default_buildings() -> void:
	var wall := BuildingData.new()
	wall.id = &"wall"
	wall.display_name = "Стена"
	wall.description = "Базовая стена. Герметизирует помещение."
	wall.category = BuildingData.Category.STRUCTURE
	wall.scrap_cost = 2
	wall.health = 50.0
	wall.placeholder_color = Color(0.45, 0.48, 0.52)
	wall.hotkey = 1
	_buildings.append(wall)

	var battery := BuildingData.new()
	battery.id = &"ark_battery"
	battery.display_name = "Батарея Ковчега"
	battery.description = "Конечный запас энергии. Когда сядет — навсегда."
	battery.category = BuildingData.Category.POWER
	battery.scrap_cost = 0
	battery.health = 80.0
	battery.placeholder_color = Color(0.3, 0.5, 0.8)
	battery.hotkey = 2
	battery.script_path = "res://core/entities/structures/ark_battery.gd"
	battery.balance_path = "res://data/balance/power_balance.tres"
	_buildings.append(battery)

	var burner := BuildingData.new()
	burner.id = &"thermo_burner"
	burner.display_name = "Термосжигатель"
	burner.description = "Жжёт биомассу → энергия. Шумит!"
	burner.category = BuildingData.Category.POWER
	burner.scrap_cost = 8
	burner.health = 60.0
	burner.placeholder_color = Color(0.8, 0.4, 0.15)
	burner.hotkey = 3
	burner.script_path = "res://core/entities/structures/thermo_burner.gd"
	burner.balance_path = "res://data/balance/power_balance.tres"
	_buildings.append(burner)

# --- Визуал выделения ---

func _update_selection_visual() -> void:
	for i: int in range(_buttons.size()):
		var btn: Button = _buttons[i]
		if i == _selected_index:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		else:
			btn.remove_theme_color_override("font_color")
	# Обновляем описание
	var sel: BuildingData = get_selected()
	if sel and _label:
		_label.text = "СТРОИТЕЛЬСТВО: %s" % sel.display_name

# --- Обработчики ---

func _on_build_mode_changed(is_active: bool) -> void:
	visible = is_active
	if is_active and not _buildings.is_empty():
		select_index(_selected_index)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		# Цифровые горячие клавиши 1-9
		var key: int = event.keycode - KEY_0
		if key >= 1 and key <= 9:
			for i: int in range(_buildings.size()):
				if _buildings[i].hotkey == key:
					select_index(i)
					get_viewport().set_input_as_handled()
					return
