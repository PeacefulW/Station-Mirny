class_name WorldRebuildNotice
extends Control

func _ready() -> void:
	if TimeManager and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)
	_rebuild_ui()
	if EventBus and EventBus.has_signal("language_changed") and not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)

func _rebuild_ui() -> void:
	for child: Node in get_children():
		child.queue_free()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP

	var pending_slot: String = ""
	if SaveManager and SaveManager.has_method("consume_pending_load_slot"):
		pending_slot = SaveManager.consume_pending_load_slot()

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.06, 0.07)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	panel.add_child(body)

	var title := Label.new()
	title.text = Localization.t("UI_WORLD_REBUILD_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	body.add_child(title)

	var message := Label.new()
	message.text = Localization.t("UI_WORLD_REBUILD_MESSAGE")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(message)

	if not pending_slot.is_empty():
		var pending_label := Label.new()
		pending_label.text = Localization.t("UI_WORLD_REBUILD_PENDING_LOAD", {"slot": pending_slot})
		pending_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pending_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(pending_label)

	var back_button := Button.new()
	back_button.text = Localization.t("UI_WORLD_REBUILD_BACK")
	back_button.custom_minimum_size = Vector2(240, 44)
	back_button.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
	body.add_child(back_button)

func _on_language_changed(_locale: String) -> void:
	call_deferred("_rebuild_ui")
