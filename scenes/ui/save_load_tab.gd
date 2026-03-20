class_name SaveLoadTab
extends VBoxContainer

## Вкладка сохранения/загрузки в меню паузы.
## Показывает список слотов, позволяет сохранить/загрузить/удалить.

const MAX_SLOTS: int = 5
const SAVE_DIR: String = "user://saves/"

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

	for i: int in range(1, MAX_SLOTS + 1):
		var slot_name: String = "save_%02d" % i
		var slot_path: String = SAVE_DIR + slot_name + "/"
		var exists: bool = DirAccess.dir_exists_absolute(slot_path)

		var btn := Button.new()
		btn.custom_minimum_size.y = 36
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		if exists:
			var meta: Dictionary = _read_meta(slot_path)
			var date: String = meta.get("date", "???")
			var day: int = meta.get("day", 0)
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
		SaveManager.save_game(_selected_slot)
		_set_status(Localization.t("UI_SAVE_SUCCESS", {"slot": _selected_slot}), Color(0.4, 0.8, 0.4))
		refresh()
	else:
		_set_status(Localization.t("UI_SAVE_UNAVAILABLE"), Color(0.9, 0.4, 0.3))

func _on_load_pressed() -> void:
	if _selected_slot.is_empty():
		_set_status(Localization.t("UI_SAVE_SELECT_SLOT"), Color(0.9, 0.7, 0.3))
		return
	var slot_path: String = SAVE_DIR + _selected_slot + "/"
	if not DirAccess.dir_exists_absolute(slot_path):
		_set_status(Localization.t("UI_SAVE_EMPTY_SLOT"), Color(0.9, 0.5, 0.3))
		return
	if SaveManager and SaveManager.has_method("load_game"):
		# Снимаем паузу перед загрузкой
		get_tree().paused = false
		SaveManager.load_game(_selected_slot)
		# Закрываем меню
		var menu: PauseMenu = get_parent().get_parent().get_parent() as PauseMenu
		if menu:
			menu.close()

func _on_delete_pressed() -> void:
	if _selected_slot.is_empty():
		_set_status(Localization.t("UI_SAVE_SELECT_SLOT"), Color(0.9, 0.7, 0.3))
		return
	var slot_path: String = SAVE_DIR + _selected_slot + "/"
	if DirAccess.dir_exists_absolute(slot_path):
		_delete_dir_recursive(slot_path)
		_set_status(Localization.t("UI_SAVE_DELETED", {"slot": _selected_slot}), Color(0.7, 0.6, 0.5))
		refresh()

func _set_status(text: String, color: Color) -> void:
	if _status_label:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", color)

func _read_meta(slot_path: String) -> Dictionary:
	var meta_path: String = slot_path + "meta.json"
	if not FileAccess.file_exists(meta_path):
		return {}
	var file := FileAccess.open(meta_path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func _delete_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_delete_dir_recursive(path + entry + "/")
		else:
			dir.remove(entry)
		entry = dir.get_next()
	DirAccess.remove_absolute(path)

var _button_group: ButtonGroup = null
func _get_or_create_group() -> ButtonGroup:
	if not _button_group:
		_button_group = ButtonGroup.new()
	return _button_group
