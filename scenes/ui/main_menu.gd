class_name MainMenu
extends Control

## Главное меню при запуске игры.
## Кнопки: Новая игра, Продолжить, Загрузить, Настройки, Выход.

var _btn_continue: Button = null
var _load_panel: Control = null
var _settings_panel: Control = null
var _buttons_container: VBoxContainer = null

func _ready() -> void:
	if TimeManager and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)
	_build_ui()
	EventBus.language_changed.connect(_on_language_changed)

# --- Построение UI ---

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP

	# Фон
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.06, 0.08)
	add_child(bg)

	# Центральный контейнер
	_buttons_container = VBoxContainer.new()
	_buttons_container.set_anchors_and_offsets_preset(PRESET_CENTER)
	_buttons_container.grow_horizontal = GROW_DIRECTION_BOTH
	_buttons_container.grow_vertical = GROW_DIRECTION_BOTH
	_buttons_container.custom_minimum_size = Vector2(300, 0)
	_buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons_container.add_theme_constant_override("separation", 8)
	add_child(_buttons_container)

	# Название
	var title := Label.new()
	title.text = Localization.t("UI_MAIN_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
	_buttons_container.add_child(title)

	# Подзаголовок
	var subtitle := Label.new()
	subtitle.text = Localization.t("UI_MAIN_SUBTITLE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
	_buttons_container.add_child(subtitle)

	# Отступ
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	_buttons_container.add_child(spacer)

	# Кнопки
	var btn_new := _make_button(Localization.t("UI_MAIN_NEW_GAME"), _on_new_game_pressed)
	_buttons_container.add_child(btn_new)

	_btn_continue = _make_button(Localization.t("UI_MAIN_CONTINUE"), _on_continue_pressed)
	_btn_continue.visible = _has_any_saves()
	_buttons_container.add_child(_btn_continue)

	var btn_load := _make_button(Localization.t("UI_MAIN_LOAD"), _on_load_pressed)
	_buttons_container.add_child(btn_load)

	var btn_settings := _make_button(Localization.t("UI_MAIN_SETTINGS"), _on_settings_pressed)
	_buttons_container.add_child(btn_settings)

	var btn_quit := _make_button(Localization.t("UI_MAIN_QUIT"), _on_quit_pressed)
	_buttons_container.add_child(btn_quit)

	_build_load_panel()
	_build_settings_panel()

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/world_creation_screen.tscn")
func _on_continue_pressed() -> void:
	var latest: String = _find_latest_save()
	if latest.is_empty(): return
	_start_game_from_save(latest)
func _on_load_pressed() -> void:
	_buttons_container.visible = false
	_load_panel.visible = true
func _on_settings_pressed() -> void:
	_buttons_container.visible = false
	_settings_panel.visible = true
func _on_quit_pressed() -> void:
	get_tree().quit()

# --- Панель загрузки ---

func _build_load_panel() -> void:
	_load_panel = VBoxContainer.new()
	_load_panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	_load_panel.grow_horizontal = GROW_DIRECTION_BOTH
	_load_panel.grow_vertical = GROW_DIRECTION_BOTH
	_load_panel.custom_minimum_size = Vector2(400, 340)
	_load_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_load_panel.add_theme_constant_override("separation", 8)
	_load_panel.visible = false
	add_child(_load_panel)

	var load_title := Label.new()
	load_title.text = Localization.t("UI_MAIN_LOAD_TITLE")
	load_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_title.add_theme_font_size_override("font_size", 18)
	load_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	_load_panel.add_child(load_title)

	var save_list := _build_save_list()
	_load_panel.add_child(save_list)

	var btn_back := _make_button(Localization.t("UI_MAIN_LOAD_BACK"), _on_load_back)
	_load_panel.add_child(btn_back)

func _build_save_list() -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	var saves: Array[Dictionary] = SaveManager.get_save_list()
	if saves.is_empty():
		var empty_label := Label.new()
		empty_label.text = Localization.t("UI_SAVE_EMPTY_SLOT", {"slot": ""})
		empty_label.add_theme_font_size_override("font_size", 14)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.48, 0.42))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(empty_label)
	else:
		for save_info: Dictionary in saves:
			var slot_name: String = save_info.get("slot_name", "")
			var day: int = int(save_info.get("game_day", save_info.get("day", 0)))
			var date: String = str(save_info.get("save_time", save_info.get("date", "???")))
			var btn := _make_button(
				Localization.t("UI_SAVE_SLOT_USED", {"slot": slot_name, "day": day, "date": date}),
				_start_game_from_save.bind(slot_name)
			)
			container.add_child(btn)
	return container

func _on_load_back() -> void:
	_load_panel.visible = false
	_buttons_container.visible = true

# --- Панель настроек ---

func _build_settings_panel() -> void:
	_settings_panel = VBoxContainer.new()
	_settings_panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	_settings_panel.grow_horizontal = GROW_DIRECTION_BOTH
	_settings_panel.grow_vertical = GROW_DIRECTION_BOTH
	_settings_panel.custom_minimum_size = Vector2(480, 380)
	_settings_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_panel.add_theme_constant_override("separation", 8)
	_settings_panel.visible = false
	add_child(_settings_panel)

	var settings_title := Label.new()
	settings_title.text = Localization.t("UI_MAIN_SETTINGS")
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 18)
	settings_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	_settings_panel.add_child(settings_title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.custom_minimum_size.y = 280
	_settings_panel.add_child(tabs)

	tabs.add_child(_build_lang_tab())
	tabs.add_child(_build_graphics_tab())
	tabs.add_child(_build_audio_tab())

	var btn_back := _make_button(Localization.t("UI_MAIN_SETTINGS_BACK"), _on_settings_back)
	_settings_panel.add_child(btn_back)

func _build_lang_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = Localization.t("UI_SETTINGS_TAB_GAME")
	tab.add_theme_constant_override("separation", 10)
	var row := _make_settings_row(Localization.t("UI_SETTINGS_LANGUAGE"))
	var opt := OptionButton.new()
	opt.custom_minimum_size.x = 160
	var locales: Array[Array] = [["ru", "Русский"], ["en", "English"]]
	for i: int in range(locales.size()):
		opt.add_item(locales[i][1], i)
		if locales[i][0] == SettingsManager.locale:
			opt.selected = i
	opt.item_selected.connect(func(idx: int) -> void:
		SettingsManager.locale = locales[idx][0]
		SettingsManager.apply_locale()
		SettingsManager.save_settings()
	)
	row.add_child(opt)
	tab.add_child(row)
	return tab

func _build_graphics_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = Localization.t("UI_SETTINGS_TAB_GRAPHICS")
	tab.add_theme_constant_override("separation", 10)
	tab.add_child(_make_toggle_row(Localization.t("UI_SETTINGS_FULLSCREEN"), SettingsManager.fullscreen, func(v: bool) -> void:
		SettingsManager.fullscreen = v; SettingsManager.apply_graphics(); SettingsManager.save_settings()))
	tab.add_child(_make_toggle_row(Localization.t("UI_SETTINGS_VSYNC"), SettingsManager.vsync, func(v: bool) -> void:
		SettingsManager.vsync = v; SettingsManager.apply_graphics(); SettingsManager.save_settings()))
	return tab

func _build_audio_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = Localization.t("UI_SETTINGS_TAB_AUDIO")
	tab.add_theme_constant_override("separation", 10)
	var fields: Array[Array] = [
		["UI_SETTINGS_VOLUME_MASTER", SettingsManager.volume_master, "master"],
		["UI_SETTINGS_VOLUME_MUSIC", SettingsManager.volume_music, "music"],
		["UI_SETTINGS_VOLUME_SFX", SettingsManager.volume_sfx, "sfx"],
	]
	for f: Array in fields:
		var field: String = f[2]
		tab.add_child(_make_slider_row(Localization.t(f[0]), f[1], func(v: float) -> void:
			SettingsManager.set(("volume_" + field), v); SettingsManager.apply_audio(); SettingsManager.save_settings()))
	return tab

func _make_settings_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	row.add_child(lbl)
	return row

func _make_toggle_row(label_text: String, value: bool, callback: Callable) -> HBoxContainer:
	var row := _make_settings_row(label_text)
	var toggle := CheckButton.new()
	toggle.button_pressed = value
	toggle.toggled.connect(callback)
	row.add_child(toggle)
	return row

func _make_slider_row(label_text: String, value: float, callback: Callable) -> HBoxContainer:
	var row := _make_settings_row(label_text)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 160
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.value_changed.connect(callback)
	row.add_child(slider)
	return row

func _on_settings_back() -> void:
	_settings_panel.visible = false
	_buttons_container.visible = true

# --- Утилиты ---

func _start_game_from_save(slot_name: String) -> void:
	SaveManager.request_load_after_scene_change(slot_name)
	get_tree().change_scene_to_file("res://scenes/world/game_world.tscn")

func _find_latest_save() -> String:
	var saves: Array[Dictionary] = SaveManager.get_save_list()
	if saves.is_empty():
		return ""
	return saves[0].get("slot_name", "")

func _has_any_saves() -> bool:
	return not _find_latest_save().is_empty()

func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(callback)
	return btn

func _on_language_changed(_locale: String) -> void:
	for child: Node in get_children():
		child.queue_free()
	_load_panel = null
	_settings_panel = null
	_buttons_container = null
	_btn_continue = null
	call_deferred("_build_ui")
