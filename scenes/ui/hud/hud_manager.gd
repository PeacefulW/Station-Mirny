class_name HudManager
extends Control
## Менеджер HUD. Размещает виджеты по зонам экрана.
## Добавить новый виджет = создать экземпляр + добавить в зону.

const PerformanceHudWidgetScript = preload("res://scenes/ui/hud/hud_performance_widget.gd")

# --- Зоны экрана ---
var _top_left: VBoxContainer = null
var _top_right: VBoxContainer = null
var _bottom_left: VBoxContainer = null
var _bottom_center: HBoxContainer = null
var _alerts: VBoxContainer = null
var _performance_hud: HudPerformanceWidget = null
var _performance_recorder: PerformanceFlightRecorder = null
var _performance_toast: PanelContainer = null
var _performance_toast_label: Label = null
var _performance_toast_revision: int = 0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_create_zones()
	_create_widgets()
	_create_performance_toast()

# --- Зоны ---


func _create_zones() -> void:
	# Top-left: O₂, HP, статус, скрап
	_top_left = VBoxContainer.new()
	_top_left.position = Vector2(12, 12)
	_top_left.add_theme_constant_override("separation", 4)
	_top_left.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_top_left)

	# Top-right: время, день, этаж
	_top_right = VBoxContainer.new()
	_top_right.anchor_left = 1.0
	_top_right.anchor_right = 1.0
	_top_right.offset_left = -220.0
	_top_right.offset_top = 12.0
	_top_right.offset_right = -12.0
	_top_right.offset_bottom = 12.0
	_top_right.add_theme_constant_override("separation", 4)
	_top_right.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_top_right)

	# Bottom-left: подсказки
	_bottom_left = VBoxContainer.new()
	_bottom_left.anchor_top = 1.0
	_bottom_left.anchor_bottom = 1.0
	_bottom_left.position = Vector2(12, -40)
	_bottom_left.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bottom_left)

	# Bottom-center: quickbar (будущее)
	_bottom_center = HBoxContainer.new()
	_bottom_center.anchor_top = 1.0
	_bottom_center.anchor_bottom = 1.0
	_bottom_center.anchor_left = 0.5
	_bottom_center.anchor_right = 0.5
	_bottom_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom_center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bottom_center)

	# Center-right: предупреждения (будущее)
	_alerts = VBoxContainer.new()
	_alerts.anchor_left = 1.0
	_alerts.anchor_right = 1.0
	_alerts.anchor_top = 0.5
	_alerts.position = Vector2(-180, 0)
	_alerts.add_theme_constant_override("separation", 4)
	_alerts.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_alerts)

# --- Виджеты ---


func _create_widgets() -> void:
	# === РЕАЛИЗОВАНО (механики есть) ===
	_top_left.add_child(HudOxygenWidget.new())
	_top_left.add_child(HudHpWidget.new())
	_top_left.add_child(HudStatusWidget.new())
	_top_right.add_child(HudTimeWidget.new())
	_top_right.add_child(HudFloorWidget.new())
	_top_right.add_child(HudCoordinatesWidget.new())
	_top_right.add_child(HudWindWidget.new())
	_top_right.add_child(HudWeatherWidget.new())
	_bottom_left.add_child(HudHintsWidget.new())

	# Diagnostic overlay owns its absolute position and must not reflow survival
	# widgets when F3 switches between compact and detailed modes.
	_performance_hud = PerformanceHudWidgetScript.new() as HudPerformanceWidget
	add_child(_performance_hud)

	# === ЗАГЛУШКИ (раскомментировать когда появится механика) ===
	# _top_left.add_child(HudHungerWidget.new())       # Этап 5.1
	# _top_left.add_child(HudThirstWidget.new())       # Этап 5.1
	# _top_left.add_child(HudStaminaWidget.new())      # когда спринт
	# _alerts.add_child(HudTemperatureAlert.new())     # Этап 5.4
	# _alerts.add_child(HudToxicityAlert.new())        # Этап 5.5
	# _bottom_center.add_child(HudQuickbar.new())      # Этап 8.2


func set_performance_source(streamer: Node) -> void:
	if _performance_hud != null:
		_performance_hud.set_performance_source(streamer)


func set_performance_recorder(recorder: PerformanceFlightRecorder) -> void:
	if _performance_recorder != null and is_instance_valid(_performance_recorder):
		var previous_callable: Callable = Callable(
			self,
			"_on_performance_notification_requested",
		)
		if _performance_recorder.notification_requested.is_connected(previous_callable):
			_performance_recorder.notification_requested.disconnect(previous_callable)
	_performance_recorder = recorder
	if _performance_hud != null:
		_performance_hud.set_performance_recorder(recorder)
	if _performance_recorder != null:
		_performance_recorder.notification_requested.connect(
			Callable(self, "_on_performance_notification_requested"),
		)


func cycle_performance_mode() -> int:
	if _performance_hud == null:
		return HudPerformanceWidget.DisplayMode.HIDDEN
	return _performance_hud.cycle_display_mode()


func get_performance_hud() -> HudPerformanceWidget:
	return _performance_hud


func _create_performance_toast() -> void:
	_performance_toast = PanelContainer.new()
	_performance_toast.name = "PerformanceCaptureToast"
	_performance_toast.anchor_left = 0.5
	_performance_toast.anchor_right = 0.5
	_performance_toast.offset_left = -360.0
	_performance_toast.offset_top = 18.0
	_performance_toast.offset_right = 360.0
	_performance_toast.offset_bottom = 76.0
	_performance_toast.mouse_filter = MOUSE_FILTER_IGNORE
	_performance_toast.visible = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.037, 0.048, 0.96)
	style.border_color = Color(0.31, 0.84, 0.94, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	_performance_toast.add_theme_stylebox_override("panel", style)
	add_child(_performance_toast)
	_performance_toast_label = Label.new()
	_performance_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_performance_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_performance_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_performance_toast_label.add_theme_font_size_override("font_size", 11)
	_performance_toast_label.add_theme_color_override(
		"font_color",
		Color(0.90, 0.96, 0.97),
	)
	_performance_toast.add_child(_performance_toast_label)


func _on_performance_notification_requested(
		message_key: StringName,
		message_args: Dictionary,
	) -> void:
	if _performance_toast == null or _performance_toast_label == null:
		return
	_performance_toast_revision += 1
	var localization: Node = get_node_or_null("/root/Localization")
	_performance_toast_label.text = (
		String(localization.call("t", String(message_key), message_args))
		if localization != null and localization.has_method("t")
		else String(message_key)
	)
	_performance_toast.visible = true
	_performance_toast.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_performance_toast, "modulate:a", 1.0, 0.12)
	_hide_performance_toast_after_delay(_performance_toast_revision)


func _hide_performance_toast_after_delay(revision: int) -> void:
	await get_tree().create_timer(4.0).timeout
	if revision != _performance_toast_revision or _performance_toast == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_performance_toast, "modulate:a", 0.0, 0.16)
	await tween.finished
	if revision == _performance_toast_revision:
		_performance_toast.visible = false
