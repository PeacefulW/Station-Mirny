class_name DeathScreen
extends Control

## Экран смерти. Статистика + кнопки (загрузить / новая игра / меню).

var _stats_container: VBoxContainer = null

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)

## Показать экран смерти со статистикой.
func show_death(stats: Dictionary) -> void:
	visible = true
	get_tree().paused = true
	_build_ui(stats)

# --- Построение UI ---

func _build_ui(stats: Dictionary) -> void:
	# Очистить предыдущее
	for child: Node in get_children():
		child.queue_free()

	# Затемнение
	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dimmer.color = Color(0.08, 0.02, 0.02, 0.85)
	dimmer.mouse_filter = MOUSE_FILTER_STOP
	add_child(dimmer)

	# Панель
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 360)
	panel.set_anchors_preset(PRESET_CENTER)
	panel.size = Vector2(400, 360)
	panel.position -= panel.size * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.04, 0.95)
	style.border_color = Color(0.4, 0.15, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# Заголовок
	var title := Label.new()
	title.text = Localization.t("UI_DEATH_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.15))
	vbox.add_child(title)

	# Подзаголовок
	var subtitle := Label.new()
	subtitle.text = Localization.t("UI_DEATH_SUBTITLE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.38, 0.35))
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	# Статистика
	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 4)
	_add_stat_row("UI_DEATH_STAT_DAYS", stats.get("days_survived", 0))
	_add_stat_row("UI_DEATH_STAT_KILLS", stats.get("enemies_killed", 0))
	_add_stat_row("UI_DEATH_STAT_BUILDINGS", stats.get("buildings_placed", 0))
	_add_stat_row("UI_DEATH_STAT_CRAFTED", stats.get("items_crafted", 0))
	_add_stat_row("UI_DEATH_STAT_RESOURCES", stats.get("resources_gathered", 0))
	vbox.add_child(_stats_container)

	vbox.add_child(HSeparator.new())

	# Кнопки
	var btn_load := _make_button(Localization.t("UI_DEATH_LOAD_SAVE"), _on_load_pressed)
	vbox.add_child(btn_load)

	var btn_new := _make_button(Localization.t("UI_DEATH_NEW_GAME"), _on_new_game_pressed)
	vbox.add_child(btn_new)

	var btn_menu := _make_button(Localization.t("UI_DEATH_MAIN_MENU"), _on_main_menu_pressed)
	vbox.add_child(btn_menu)

	panel.add_child(vbox)

func _add_stat_row(key: String, value: int) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = Localization.t(key)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	row.add_child(label)

	var val_label := Label.new()
	val_label.text = str(value)
	val_label.add_theme_font_size_override("font_size", 13)
	val_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.6))
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_label)

	_stats_container.add_child(row)

func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 38)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(callback)
	return btn

# --- Кнопки ---

func _on_load_pressed() -> void:
	get_tree().paused = false
	if TimeManager:
		TimeManager.is_paused = true
	var latest: String = _find_latest_save()
	if latest.is_empty():
		_on_main_menu_pressed()
		return
	SaveManager.pending_load_slot = latest
	get_tree().change_scene_to_file("res://scenes/world/game_world.tscn")

func _on_new_game_pressed() -> void:
	get_tree().paused = false
	if TimeManager:
		TimeManager.is_paused = true
	get_tree().change_scene_to_file("res://scenes/ui/world_creation_screen.tscn")

func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	if TimeManager:
		TimeManager.is_paused = true
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _find_latest_save() -> String:
	var saves: Array[Dictionary] = SaveManager.get_save_list()
	if saves.is_empty():
		return ""
	return saves[0].get("slot_name", "")
