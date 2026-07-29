class_name HudManager
extends Control
## Менеджер HUD. Размещает виджеты по зонам экрана.
## Добавить новый виджет = создать экземпляр + добавить в зону.
##
## Композиция подчинена контрасту "внутри безопасно — снаружи враждебно":
## кластеры прижаты к углам и растворяются к центру, а в укрытии с питанием
## панель обстановки гаснет — интерфейс успокаивается вместе с игроком.

const PerformanceHudWidgetScript = preload("res://scenes/ui/hud/hud_performance_widget.gd")

const SCREEN_MARGIN: float = 16.0
const SURVIVAL_PLATE_WIDTH: float = 272.0
const ENVIRONMENT_PLATE_WIDTH: float = 310.0
const PLATE_PADDING: Vector4 = Vector4(16.0, 13.0, 16.0, 14.0)
const CONTEXT_PADDING: Vector4 = Vector4(20.0, 14.0, 20.0, 14.0)
const SHELTERED_ENVIRONMENT_ALPHA: float = 0.55
const OXYGEN_ALARM_RATIO: float = 0.25

# --- Зоны экрана ---
var _top_left: VBoxContainer = null
var _top_right: VBoxContainer = null
var _bottom_context: HBoxContainer = null
var _bottom_center: HBoxContainer = null
var _alerts: VBoxContainer = null
var _environment_panel: HudScrim = null
var _bottom_context_panel: HudScrim = null
var _alarm_vignette: HudAlarmVignette = null
var _action_bar: HudActionBarWidget = null
var _environment_tween: Tween = null
var _is_sheltered: bool = false
var _is_life_support_powered: bool = false
var _is_oxygen_critical: bool = false
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
	_connect_state_signals()

# --- Зоны ---


func _create_zones() -> void:
	# Тревога рисуется первой: она живёт под кластерами, а не поверх текста.
	_alarm_vignette = HudAlarmVignette.new()
	_alarm_vignette.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_alarm_vignette)

	var survival_panel: HudScrim = HudScrim.new()
	survival_panel.name = "SurvivalPanel"
	survival_panel.configure(PLATE_PADDING)
	survival_panel.custom_minimum_size = Vector2(SURVIVAL_PLATE_WIDTH, 0.0)
	survival_panel.position = Vector2(SCREEN_MARGIN, SCREEN_MARGIN)
	add_child(survival_panel)

	# Top-left: жизненные показатели и состояние укрытия.
	_top_left = VBoxContainer.new()
	_top_left.add_theme_constant_override("separation", 9)
	_top_left.mouse_filter = MOUSE_FILTER_IGNORE
	survival_panel.add_child(_top_left)

	_environment_panel = HudScrim.new()
	_environment_panel.name = "EnvironmentPanel"
	_environment_panel.configure(PLATE_PADDING)
	_environment_panel.anchor_left = 1.0
	_environment_panel.anchor_right = 1.0
	_environment_panel.offset_left = -(ENVIRONMENT_PLATE_WIDTH + SCREEN_MARGIN)
	_environment_panel.offset_right = -SCREEN_MARGIN
	_environment_panel.offset_top = SCREEN_MARGIN
	_environment_panel.offset_bottom = SCREEN_MARGIN
	# Плита прижата к правому краю: расти она обязана влево, иначе длинная
	# строка координат уезжает за экран.
	_environment_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_environment_panel)

	# Top-right: время, среда и тихая навигация.
	_top_right = VBoxContainer.new()
	_top_right.add_theme_constant_override("separation", 7)
	_top_right.mouse_filter = MOUSE_FILTER_IGNORE
	_environment_panel.add_child(_top_right)

	# Bottom-center: доступные действия, исчезающие вне режима.
	_bottom_context_panel = HudScrim.new()
	_bottom_context_panel.name = "ContextPanel"
	_bottom_context_panel.configure(CONTEXT_PADDING)
	_bottom_context_panel.anchor_left = 0.5
	_bottom_context_panel.anchor_right = 0.5
	_bottom_context_panel.anchor_top = 1.0
	_bottom_context_panel.anchor_bottom = 1.0
	_bottom_context_panel.offset_left = 0.0
	_bottom_context_panel.offset_right = 0.0
	_bottom_context_panel.offset_top = -SCREEN_MARGIN
	_bottom_context_panel.offset_bottom = -SCREEN_MARGIN
	# Плита подгоняется под набор действий: в режиме стройки их втрое меньше, и
	# фиксированная ширина оставила бы пустое стекло.
	_bottom_context_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom_context_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_bottom_context_panel)
	_bottom_context = HBoxContainer.new()
	_bottom_context.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom_context.mouse_filter = MOUSE_FILTER_IGNORE
	_bottom_context_panel.add_child(_bottom_context)

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
	_top_left.add_child(_make_rule(HudRule.Fade.TO_RIGHT))
	_top_left.add_child(HudStatusWidget.new())

	_top_right.add_child(HudTimeWidget.new())
	_top_right.add_child(_make_rule(HudRule.Fade.TO_LEFT))
	_top_right.add_child(HudWindWidget.new())
	_top_right.add_child(HudWeatherWidget.new())
	_top_right.add_child(_make_rule(HudRule.Fade.TO_LEFT))

	var navigation_row := HBoxContainer.new()
	navigation_row.alignment = BoxContainer.ALIGNMENT_END
	navigation_row.add_theme_constant_override("separation", 14)
	navigation_row.mouse_filter = MOUSE_FILTER_IGNORE
	navigation_row.add_child(HudFloorWidget.new())
	navigation_row.add_child(HudCoordinatesWidget.new())
	_top_right.add_child(navigation_row)

	_action_bar = HudActionBarWidget.new()
	_action_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_context.add_child(_action_bar)
	_action_bar.visibility_changed.connect(_sync_context_panel_visibility)
	_sync_context_panel_visibility()

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


func _make_rule(fade: HudRule.Fade) -> HudRule:
	var rule: HudRule = HudRule.new()
	rule.configure(fade)
	return rule


func _sync_context_panel_visibility() -> void:
	if _bottom_context_panel == null or _action_bar == null:
		return
	_bottom_context_panel.visible = _action_bar.visible

# --- Состояние укрытия ---


func _connect_state_signals() -> void:
	EventBus.player_entered_indoor.connect(_on_entered_indoor)
	EventBus.player_exited_indoor.connect(_on_exited_indoor)
	EventBus.life_support_power_changed.connect(_on_life_support_power_changed)
	EventBus.oxygen_changed.connect(_on_oxygen_changed)


func _on_entered_indoor() -> void:
	_is_sheltered = true
	_apply_shelter_mood()


func _on_exited_indoor() -> void:
	_is_sheltered = false
	_apply_shelter_mood()


func _on_life_support_power_changed(is_powered: bool) -> void:
	_is_life_support_powered = is_powered
	_apply_shelter_mood()


func _on_oxygen_changed(current: float, maximum: float) -> void:
	if maximum <= 0.0:
		return
	var is_critical: bool = current / maximum < OXYGEN_ALARM_RATIO
	if is_critical == _is_oxygen_critical:
		return
	_is_oxygen_critical = is_critical
	_apply_shelter_mood()


## В укрытии с работающим жизнеобеспечением обстановка снаружи перестаёт быть
## задачей игрока, поэтому её панель уходит на второй план.
func _apply_shelter_mood() -> void:
	if _alarm_vignette != null:
		var is_shelter_failing: bool = _is_sheltered and not _is_life_support_powered
		_alarm_vignette.set_alarm(_is_oxygen_critical or is_shelter_failing)
	if _environment_panel == null:
		return
	var target_alpha: float = 1.0
	if _is_sheltered and _is_life_support_powered and not _is_oxygen_critical:
		target_alpha = SHELTERED_ENVIRONMENT_ALPHA
	if is_equal_approx(_environment_panel.modulate.a, target_alpha):
		return
	if _environment_tween != null and _environment_tween.is_valid():
		_environment_tween.kill()
	_environment_tween = create_tween()
	_environment_tween.tween_property(_environment_panel, "modulate:a", target_alpha, 0.35)


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
