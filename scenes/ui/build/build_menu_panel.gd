class_name BuildMenuPanel
extends Control

## Меню строительства с вкладками категорий и карточками зданий.
## Появляется внизу экрана при B. Данные из BuildingData.
## Пустые категории (нет зданий) — не показываются.

signal building_selected(building: BuildingData)

var _panel: PanelContainer = null
var _tabs_container: HBoxContainer = null
var _card_container: HBoxContainer = null
var _tooltip: BuildingTooltip = null
var _hint_label: Label = null

var _category_buttons: Dictionary = {}
var _card_nodes: Array[BuildingCard] = []
var _current_category: int = BuildingData.Category.STRUCTURE
var _selected_building: BuildingData = null
var _all_buildings: Array[BuildingData] = []
var _is_open: bool = false

func _ready() -> void:
	add_to_group("build_menu")
	add_to_group("closeable_ui")
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_load_buildings()
	_build_ui()
	EventBus.build_mode_changed.connect(_on_build_mode_changed)
	EventBus.language_changed.connect(_on_language_changed)

## Получить текущую выбранную постройку.
func get_selected() -> BuildingData:
	return _selected_building

# --- Построение UI ---

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.offset_top = -180
	_panel.offset_bottom = 0
	_panel.mouse_filter = MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.06, 0.94)
	style.border_color = Color(0.22, 0.21, 0.18)
	style.border_width_top = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Вкладки категорий
	_tabs_container = HBoxContainer.new()
	_tabs_container.add_theme_constant_override("separation", 4)
	_build_category_tabs()
	vbox.add_child(_tabs_container)

	# Карточки зданий (скроллируемый горизонтальный ряд)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = SIZE_EXPAND_FILL

	_card_container = HBoxContainer.new()
	_card_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_card_container)
	vbox.add_child(scroll)

	# Подсказка
	_hint_label = Label.new()
	_hint_label.text = Localization.t("UI_BUILD_PLACE_HINT")
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", Color(0.35, 0.33, 0.28))
	vbox.add_child(_hint_label)

	_panel.add_child(vbox)
	add_child(_panel)

	# Тултип (поверх всего)
	_tooltip = BuildingTooltip.new()
	add_child(_tooltip)

	# Показать первую непустую категорию
	_show_category(_find_first_category())

func _build_category_tabs() -> void:
	for child: Node in _tabs_container.get_children():
		child.queue_free()
	_category_buttons.clear()

	for cat_value: int in BuildingData.Category.values():
		var buildings: Array[BuildingData] = _get_buildings_for_category(cat_value)
		if buildings.is_empty():
			continue
		var cat_key: String = BuildingData.CATEGORY_NAME_KEYS.get(cat_value, "???")
		var btn := Button.new()
		btn.text = Localization.t(cat_key)
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 12)
		btn.toggle_mode = true
		var captured_cat: int = cat_value
		btn.pressed.connect(func() -> void: _show_category(captured_cat))
		_tabs_container.add_child(btn)
		_category_buttons[cat_value] = btn

# --- Показ категории ---

func _show_category(category: int) -> void:
	_current_category = category

	# Обновить выделение вкладок
	for cat: int in _category_buttons:
		(_category_buttons[cat] as Button).button_pressed = (cat == category)

	# Очистить карточки
	for child: Node in _card_container.get_children():
		child.queue_free()
	_card_nodes.clear()

	# Создать карточки
	var buildings: Array[BuildingData] = _get_buildings_for_category(category)
	for bd: BuildingData in buildings:
		var card := BuildingCard.new()
		card.setup(bd)
		card.card_clicked.connect(_on_card_clicked)
		card.card_hovered.connect(_on_card_hovered)
		card.card_unhovered.connect(_on_card_unhovered)
		_card_container.add_child(card)
		_card_nodes.append(card)
		if bd == _selected_building:
			card.set_selected(true)

# --- Обработчики ---

func _on_card_clicked(building: BuildingData) -> void:
	_selected_building = building
	for card: BuildingCard in _card_nodes:
		card.set_selected(card._building == building)
	building_selected.emit(building)

func _on_card_hovered(building: BuildingData) -> void:
	if _tooltip:
		_tooltip.show_building(building, get_global_mouse_position())

func _on_card_unhovered() -> void:
	if _tooltip:
		_tooltip.hide_tooltip()

func _on_build_mode_changed(is_active: bool) -> void:
	_is_open = is_active
	visible = is_active
	if is_active:
		_show_category(_current_category)
		# Автовыбор первого здания если ничего не выбрано
		if not _selected_building and not _card_nodes.is_empty():
			_on_card_clicked(_card_nodes[0]._building)
	else:
		_selected_building = null
		if _tooltip:
			_tooltip.hide_tooltip()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Хоткеи (1-9)
	if event is InputEventKey and event.pressed:
		var key: int = (event as InputEventKey).keycode - KEY_0
		if key >= 1 and key <= 9:
			for bd: BuildingData in _get_buildings_for_category(_current_category):
				if bd.hotkey == key:
					_on_card_clicked(bd)
					get_viewport().set_input_as_handled()
					return

# --- Данные ---

func _load_buildings() -> void:
	_all_buildings = ItemRegistry.get_all_buildings()
	if _all_buildings.is_empty():
		_all_buildings = BuildingCatalog.get_default_buildings()

func _get_buildings_for_category(category: int) -> Array[BuildingData]:
	var result: Array[BuildingData] = []
	for bd: BuildingData in _all_buildings:
		if bd.category == category:
			result.append(bd)
	return result

func _find_first_category() -> int:
	for cat_value: int in BuildingData.Category.values():
		if not _get_buildings_for_category(cat_value).is_empty():
			return cat_value
	return BuildingData.Category.STRUCTURE

func _on_language_changed(_locale: String) -> void:
	_build_category_tabs()
	_show_category(_current_category)
	if _hint_label:
		_hint_label.text = Localization.t("UI_BUILD_PLACE_HINT")
