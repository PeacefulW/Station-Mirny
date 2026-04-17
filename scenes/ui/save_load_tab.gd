class_name SaveLoadTab
extends VBoxContainer

## Вкладка сохранения/загрузки в меню паузы.
## Показывает список слотов, позволяет сохранить/загрузить/удалить.

const MAX_SLOTS: int = 5
const WORLD_REBUILD_SCENE_PATH: String = "res://scenes/ui/world_rebuild_notice.tscn"
var _slot_list: VBoxContainer = null
var _status_label: Label = null
var _selected_slot: String = ""

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build_ui()
	refresh()

func refresh() -> void:
	_rebuild_slot_list()

func _build_ui() -> void:
	# Подсказка
	var hint := Label.new()
	hint.text = Localization.t("UI_SAVE_HINT")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55))
	add_child(hint)

	# Список слотов
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_slot_list = VBoxContainer.new()
	_slot_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_slot_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_slot_list)

	# Кнопки
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)

	var btn_save := Button.new()
	btn_save.text = Localization.t("UI_SAVE_BUTTON_SAVE")
	btn_save.custom_minimum_size.x = 120
	btn_save.pressed.connect(_on_save_pressed)
	btn_row.add_child(btn_save)

	var btn_load := Button.new()
	btn_load.text = Localization.t("UI_SAVE_BUTTON_LOAD")
	btn_load.custom_minimum_size.x = 120
	btn_load.pressed.connect(_on_load_pressed)
	btn_row.add_child(btn_load)

	var btn_delete := Button.new()
	btn_delete.text = Localization.t("UI_SAVE_BUTTON_DELETE")
	btn_delete.custom_minimum_size.x = 120
	btn_delete.pressed.connect(_on_delete_pressed)
	btn_row.add_child(btn_delete)

	add_child(btn_row)

	# Статус
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)

func _rebuild_slot_list() -> void:
	for child: Node in _slot_list.get_children():
		child.queue_free()
	var saves_by_slot: Dictionary = {}
	if SaveManager and SaveManager.has_method("get_save_list"):
		for entry: Dictionary in SaveManager.get_save_list():
			var slot_name: String = str(entry.get("slot_name", ""))
			if not slot_name.is_empty():
				saves_by_slot[slot_name] = entry

	for i: int in range(1, MAX_SLOTS + 1):
		var slot_name: String = "save_%02d" % i
		var exists: bool = saves_by_slot.has(slot_name)

		var btn := Button.new()
		btn.custom_minimum_size.y = 36
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		if exists:
			var meta: Dictionary = saves_by_slot.get(slot_name, {}) as Dictionary
			var date: String = str(meta.get("save_time", meta.get("date", "???")))
			var day: int = int(meta.get("game_day", meta.get("day", 0)))
			btn.text = Localization.t("UI_SAVE_SLOT_USED", {
				"slot": i, "day": day, "date": date
			})
		else:
			btn.text = Localization.t("UI_SAVE_SLOT_EMPTY", {"slot": i})

		var captured_name: String = slot_name
		btn.pressed.connect(func() -> void: _select_slot(captured_name))
		btn.toggle_mode = true
		btn.button_group = _get_or_create_group()
		_slot_list.add_child(btn)

	_selected_slot = ""

func _select_slot(slot_name: String) -> void:
	_selected_slot = slot_name

func _on_save_pressed() -> void:
	if _selected_slot.is_empty():
		_set_status(Localization.t("UI_SAVE_SELECT_SLOT"), Color(0.9, 0.7, 0.3))
		return
	if SaveManager and SaveManager.has_method("save_game"):
		if SaveManager.save_game(_selected_slot):
			_set_status(Localization.t("UI_SAVE_SUCCESS", {"slot": _selected_slot}), Color(0.4, 0.8, 0.4))
			refresh()
		else:
			_set_status(Localization.t("UI_SAVE_UNAVAILABLE"), Color(0.9, 0.4, 0.3))
	else:
		_set_status(Localization.t("UI_SAVE_UNAVAILABLE"), Color(0.9, 0.4, 0.3))

func _on_load_pressed() -> void:
	if _selected_slot.is_empty():
		_set_status(Localization.t("UI_SAVE_SELECT_SLOT"), Color(0.9, 0.7, 0.3))
		return
	if not SaveManager or not SaveManager.has_method("save_exists") or not SaveManager.save_exists(_selected_slot):
		_set_status(Localization.t("UI_SAVE_EMPTY_SLOT"), Color(0.9, 0.5, 0.3))
		return
	get_tree().paused = false
	if TimeManager and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)
	SaveManager.request_load_after_scene_change(_selected_slot)
	get_tree().change_scene_to_file(WORLD_REBUILD_SCENE_PATH)

func _on_delete_pressed() -> void:
	if _selected_slot.is_empty():
		_set_status(Localization.t("UI_SAVE_SELECT_SLOT"), Color(0.9, 0.7, 0.3))
		return
	if SaveManager and SaveManager.has_method("delete_save") and SaveManager.delete_save(_selected_slot):
		_set_status(Localization.t("UI_SAVE_DELETED", {"slot": _selected_slot}), Color(0.7, 0.6, 0.5))
		refresh()
	else:
		_set_status(Localization.t("UI_SAVE_UNAVAILABLE"), Color(0.9, 0.4, 0.3))

func _set_status(text: String, color: Color) -> void:
	if _status_label:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", color)

var _button_group: ButtonGroup = null
func _get_or_create_group() -> ButtonGroup:
	if not _button_group:
		_button_group = ButtonGroup.new()
	return _button_group
