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
var _hint_label: Label = null
var _buttons: Array[Button] = []
var _buildings: Array[BuildingData] = []
var _selected_index: int = 0

func _ready() -> void:
	add_to_group("build_menu")
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_load_buildings()
	_build_ui()
	EventBus.build_mode_changed.connect(_on_build_mode_changed)
	EventBus.language_changed.connect(_on_language_changed)

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

	var header := HBoxContainer.new()
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	header.add_child(_label)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.45, 0.43, 0.38))
	header.add_child(_hint_label)
	vbox.add_child(header)

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
	_apply_localization()

func _create_building_button(bd: BuildingData, index: int) -> Button:
	var btn := Button.new()
	var hotkey_text: String = ""
	if bd.hotkey > 0 and bd.hotkey <= 9:
		hotkey_text = "[%d] " % bd.hotkey
	btn.text = Localization.t("UI_BUILD_BUTTON", {
		"hotkey": hotkey_text,
		"name": bd.get_display_name(),
		"cost": bd.scrap_cost,
	})
	btn.custom_minimum_size = Vector2(120, 36)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(select_index.bind(index))
	btn.mouse_filter = MOUSE_FILTER_STOP
	return btn

# --- Загрузка построек ---

func _load_buildings() -> void:
	_buildings = ItemRegistry.get_all_buildings()
	if _buildings.is_empty():
		_load_default_buildings()
	_buildings.sort_custom(func(a: BuildingData, b: BuildingData) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.get_display_name() < b.get_display_name()
	)

## Встроенные постройки если .tres файлы не найдены.
func _load_default_buildings() -> void:
	_buildings = BuildingCatalog.get_default_buildings()

# --- Визуал выделения ---

func _update_selection_visual() -> void:
	for i: int in range(_buttons.size()):
		var btn: Button = _buttons[i]
		if i == _selected_index:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		else:
			btn.remove_theme_color_override("font_color")
	var sel: BuildingData = get_selected()
	if sel and _label:
		_label.text = Localization.t("UI_BUILD_TITLE_SELECTED", {"building": sel.get_display_name()})
	elif _label:
		_label.text = Localization.t("UI_BUILD_TITLE")

# --- Обработчики ---

func _on_build_mode_changed(is_active: bool) -> void:
	visible = is_active
	if is_active and not _buildings.is_empty():
		select_index(_selected_index)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var key: int = event.keycode - KEY_0
		if key >= 1 and key <= 9:
			for i: int in range(_buildings.size()):
				if _buildings[i].hotkey == key:
					select_index(i)
					get_viewport().set_input_as_handled()
					return

func _apply_localization() -> void:
	if _hint_label:
		_hint_label.text = Localization.t("UI_BUILD_HINT")
	for i: int in range(_buttons.size()):
		var building_data: BuildingData = _buildings[i]
		var hotkey_text: String = ""
		if building_data.hotkey > 0 and building_data.hotkey <= 9:
			hotkey_text = "[%d] " % building_data.hotkey
		_buttons[i].text = Localization.t("UI_BUILD_BUTTON", {
			"hotkey": hotkey_text,
			"name": building_data.get_display_name(),
			"cost": building_data.scrap_cost,
		})
	_update_selection_visual()

func _on_language_changed(_locale_code: String) -> void:
	_apply_localization()