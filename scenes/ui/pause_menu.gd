class_name PauseMenu
extends Control

## Меню паузы. Esc — открыть/закрыть (пауза игры).
## Вкладки: Игра, Графика, Звук, Управление, Сохранение.

var _is_open: bool = false
var _tab_container: TabContainer = null
var _locale_option: OptionButton = null
var _save_load_tab: SaveLoadTab = null

const LOCALES: Array[Array] = [["ru", "Русский"], ["en", "English"]]
const AUTOSAVE_OPTIONS: Array[int] = [0, 60, 300, 600]

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	get_tree().paused = _is_open
	if _is_open and _save_load_tab:
		_save_load_tab.refresh()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false

# --- Построение UI ---

func _build_ui() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	# Затемнение
	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.mouse_filter = MOUSE_FILTER_STOP
	add_child(dimmer)

	# Центральная панель
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 420)
	panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	panel.size = Vector2(520, 420)
	panel.position -= panel.size * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.border_color = Color(0.25, 0.28, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Заголовок
	var title := Label.new()
	title.text = Localization.t("UI_PAUSE_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	vbox.add_child(title)

	# Вкладки
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(_tab_container)

	_tab_container.add_child(_build_game_tab())
	_tab_container.add_child(_build_graphics_tab())
	_tab_container.add_child(_build_audio_tab())
	_tab_container.add_child(_build_controls_tab())

	_save_load_tab = SaveLoadTab.new()
	_save_load_tab.name = Localization.t("UI_SETTINGS_TAB_SAVE")
	_tab_container.add_child(_save_load_tab)

	# Кнопки внизу
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)

	var btn_resume := Button.new()
	btn_resume.text = Localization.t("UI_PAUSE_RESUME")
	btn_resume.custom_minimum_size.x = 140
	btn_resume.pressed.connect(close)
	btn_row.add_child(btn_resume)

	var btn_quit := Button.new()
	btn_quit.text = Localization.t("UI_PAUSE_QUIT")
	btn_quit.custom_minimum_size.x = 140
	btn_quit.pressed.connect(func() -> void: get_tree().quit())
	btn_row.add_child(btn_quit)

	vbox.add_child(btn_row)

# --- Вкладка: Игра ---

func _build_game_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = Localization.t("UI_SETTINGS_TAB_GAME")
	tab.add_theme_constant_override("separation", 10)

	# Язык
	var lang_row := _make_row(Localization.t("UI_SETTINGS_LANGUAGE"))
	_locale_option = OptionButton.new()
	_locale_option.custom_minimum_size.x = 160
	var current_locale: String = SettingsManager.locale
	for i: int in range(LOCALES.size()):
		_locale_option.add_item(LOCALES[i][1], i)
		if LOCALES[i][0] == current_locale:
			_locale_option.selected = i
	_locale_option.item_selected.connect(_on_locale_changed)
	lang_row.add_child(_locale_option)
	tab.add_child(lang_row)

	# Автосохранение
	var auto_row := _make_row(Localization.t("UI_SETTINGS_AUTOSAVE"))
	var auto_opt := OptionButton.new()
	auto_opt.custom_minimum_size.x = 160
	var labels: Array[String] = [
		Localization.t("UI_SETTINGS_AUTOSAVE_OFF"),
		Localization.t("UI_SETTINGS_AUTOSAVE_1MIN"),
		Localization.t("UI_SETTINGS_AUTOSAVE_5MIN"),
		Localization.t("UI_SETTINGS_AUTOSAVE_10MIN"),
	]
	for i: int in range(AUTOSAVE_OPTIONS.size()):
		auto_opt.add_item(labels[i], i)
		if AUTOSAVE_OPTIONS[i] == SettingsManager.autosave_interval:
			auto_opt.selected = i
	auto_opt.item_selected.connect(func(idx: int) -> void:
		SettingsManager.autosave_interval = AUTOSAVE_OPTIONS[idx]
		SettingsManager.save_settings()
	)
	auto_row.add_child(auto_opt)
	tab.add_child(auto_row)
	return tab

# --- Вкладка: Графика ---

func _build_graphics_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = Localization.t("UI_SETTINGS_TAB_GRAPHICS")
	tab.add_theme_constant_override("separation", 10)

	tab.add_child(_make_toggle(
		Localization.t("UI_SETTINGS_FULLSCREEN"),
		SettingsManager.fullscreen,
		func(val: bool) -> void:
			SettingsManager.fullscreen = val
			SettingsManager.apply_graphics()
			SettingsManager.save_settings()
	))
	tab.add_child(_make_toggle(
		Localization.t("UI_SETTINGS_VSYNC"),
		SettingsManager.vsync,
		func(val: bool) -> void:
			SettingsManager.vsync = val
			SettingsManager.apply_graphics()
			SettingsManager.save_settings()
	))
	tab.add_child(_make_slider(
		Localization.t("UI_SETTINGS_UI_SCALE"),
		SettingsManager.ui_scale, 0.8, 1.5, 0.1,
		func(val: float) -> void:
			SettingsManager.ui_scale = val
			SettingsManager.apply_graphics()
			SettingsManager.save_settings()
	))
	tab.add_child(_make_slider(
		Localization.t("UI_SETTINGS_BRIGHTNESS"),
		SettingsManager.brightness, 0.5, 1.5, 0.1,
		func(val: float) -> void:
			SettingsManager.brightness = val
			SettingsManager.save_settings()
	))
	return tab

# --- Вкладка: Звук ---

func _build_audio_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = Localization.t("UI_SETTINGS_TAB_AUDIO")
	tab.add_theme_constant_override("separation", 10)

	var sliders: Array[Array] = [
		["UI_SETTINGS_VOLUME_MASTER", SettingsManager.volume_master, "master"],
		["UI_SETTINGS_VOLUME_MUSIC", SettingsManager.volume_music, "music"],
		["UI_SETTINGS_VOLUME_SFX", SettingsManager.volume_sfx, "sfx"],
		["UI_SETTINGS_VOLUME_AMBIENT", SettingsManager.volume_ambient, "ambient"],
	]
	for s: Array in sliders:
		var field: String = s[2]
		tab.add_child(_make_slider(
			Localization.t(s[0]), s[1], 0.0, 1.0, 0.05,
			func(val: float) -> void:
				SettingsManager.set(("volume_" + field), val)
				SettingsManager.apply_audio()
				SettingsManager.save_settings()
		))
	return tab

# --- Вкладка: Управление ---

func _build_controls_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = Localization.t("UI_SETTINGS_TAB_CONTROLS")
	tab.add_theme_constant_override("separation", 6)

	var bindings: Array[Array] = [
		["UI_CONTROLS_MOVE", "WASD"],
		["UI_CONTROLS_BUILD", "B"],
		["UI_CONTROLS_INVENTORY", "Tab"],
		["UI_CONTROLS_POWER", "P"],
		["UI_CONTROLS_INTERACT", "E"],
		["UI_CONTROLS_ATTACK", Localization.t("UI_CONTROLS_SPACE")],
		["UI_CONTROLS_PAUSE", "Esc"],
	]
	for b: Array in bindings:
		var row := _make_row(Localization.t(b[0]))
		var key_label := Label.new()
		key_label.text = b[1]
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		row.add_child(key_label)
		tab.add_child(row)
	return tab

# --- Хелперы ---

func _on_locale_changed(idx: int) -> void:
	SettingsManager.locale = LOCALES[idx][0]
	SettingsManager.apply_locale()
	SettingsManager.save_settings()
	# Перестроить UI с новым языком
	close()
	for child: Node in get_children():
		child.queue_free()
	call_deferred("_build_ui")

func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	row.add_child(lbl)
	return row

func _make_toggle(label_text: String, value: bool, callback: Callable) -> HBoxContainer:
	var row := _make_row(label_text)
	var toggle := CheckButton.new()
	toggle.button_pressed = value
	toggle.toggled.connect(callback)
	row.add_child(toggle)
	return row

func _make_slider(label_text: String, value: float, min_val: float, max_val: float, step: float, callback: Callable) -> HBoxContainer:
	var row := _make_row(label_text)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 160
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = value
	var val_label := Label.new()
	val_label.custom_minimum_size.x = 40
	val_label.text = "%.0f%%" % (value * 100)
	val_label.add_theme_font_size_override("font_size", 13)
	val_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	slider.value_changed.connect(func(v: float) -> void:
		val_label.text = "%.0f%%" % (v * 100)
		callback.call(v)
	)
	row.add_child(slider)
	row.add_child(val_label)
	return row
