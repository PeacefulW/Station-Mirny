class_name HudExposureWidget
extends HudWidget
## Threshold-revealed suit telemetry. Wetness and cold stay quiet while the
## player is comfortable and never claim the critical alarm channel.

const FADE_SECONDS: float = 0.18
const PLAYER_LOOKUP_INTERVAL_SECONDS: float = 0.5
const ICON_SIZE: float = 15.0

var _wetness_group: HBoxContainer = null
var _cold_group: HBoxContainer = null
var _wetness_icon: HudIcon = null
var _cold_icon: HudIcon = null
var _wetness_label: Label = null
var _cold_label: Label = null
var _component: PlayerExposureComponent = null
var _fade_tween: Tween = null
var _lookup_elapsed: float = PLAYER_LOOKUP_INTERVAL_SECONDS
var _target_visible: bool = false


func _setup() -> void:
	visible = false
	modulate.a = 0.0

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ExposureMetrics"
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(row)

	_wetness_icon = _make_icon("WetnessIcon", HudIcons.Id.WETNESS)
	_wetness_label = _make_value_label("WetnessValue")
	_wetness_group = _make_metric_group(
		"WetnessMetric",
		_wetness_icon,
		_wetness_label,
	)
	row.add_child(_wetness_group)

	_cold_icon = _make_icon("ColdIcon", HudIcons.Id.COLD)
	_cold_label = _make_value_label("ColdValue")
	_cold_group = _make_metric_group("ColdMetric", _cold_icon, _cold_label)
	row.add_child(_cold_group)

	_wetness_group.visible = false
	_cold_group.visible = false
	call_deferred("_bind_current_player")


func _process(delta: float) -> void:
	_lookup_elapsed += maxf(delta, 0.0)
	if _lookup_elapsed < PLAYER_LOOKUP_INTERVAL_SECONDS:
		return
	_lookup_elapsed = 0.0
	_bind_current_player()


func _make_icon(node_name: StringName, glyph: HudIcons.Id) -> HudIcon:
	var icon: HudIcon = HudIcon.new()
	icon.name = node_name
	icon.configure(glyph, ICON_SIZE, HudPalette.TEXT_SECONDARY, 1.35)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func _make_value_label(node_name: StringName) -> Label:
	var label: Label = _make_hud_label(
		LabelStyle.VALUE,
		12,
		HudPalette.TEXT_SECONDARY,
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	label.name = node_name
	label.custom_minimum_size.x = 38.0
	return label


func _make_metric_group(
		node_name: StringName,
		icon: HudIcon,
		label: Label,
) -> HBoxContainer:
	var group: HBoxContainer = HBoxContainer.new()
	group.name = node_name
	group.add_theme_constant_override("separation", 6)
	group.mouse_filter = MOUSE_FILTER_IGNORE
	group.add_child(icon)
	group.add_child(label)
	return group


func _bind_current_player() -> void:
	var player: Node = null
	if PlayerAuthority != null and PlayerAuthority.has_method("get_local_player"):
		player = PlayerAuthority.get_local_player()
	var next_component: PlayerExposureComponent = PlayerExposureComponent.from_player(player)
	if next_component == _component and (_component == null or is_instance_valid(_component)):
		return
	if _component != null \
			and is_instance_valid(_component) \
			and _component.exposure_changed.is_connected(_on_exposure_changed):
		_component.exposure_changed.disconnect(_on_exposure_changed)
	_component = next_component
	if _component == null:
		_apply_exposure(0.0, 0.0)
		return
	if not _component.exposure_changed.is_connected(_on_exposure_changed):
		_component.exposure_changed.connect(_on_exposure_changed)
	_apply_exposure(_component.get_wetness(), _component.get_cold_load())


func _on_exposure_changed(wetness: float, cold_load: float) -> void:
	_apply_exposure(wetness, cold_load)


func _apply_exposure(wetness: float, cold_load: float) -> void:
	if _component == null or not is_instance_valid(_component):
		_set_row_visible(false)
		return
	var wetness_active: bool = wetness >= _component.get_wetness_visible_threshold()
	var cold_active: bool = cold_load >= _component.get_cold_visible_threshold()
	var any_active: bool = wetness_active or cold_active
	if any_active:
		_wetness_group.visible = wetness_active
		_cold_group.visible = cold_active
		if wetness_active:
			_apply_metric(
				wetness,
				_component.get_wetness_warning_threshold(),
				_component.get_wetness_critical_threshold(),
				_wetness_icon,
				_wetness_label,
			)
		if cold_active:
			_apply_metric(
				cold_load,
				_component.get_cold_warning_threshold(),
				_component.get_cold_critical_threshold(),
				_cold_icon,
				_cold_label,
			)
		update_minimum_size()
	_set_row_visible(any_active)


func _apply_metric(
		ratio: float,
		warning_at: float,
		critical_at: float,
		icon: HudIcon,
		label: Label,
) -> void:
	var state_color: Color = HudPalette.TEXT_SECONDARY
	if ratio >= warning_at:
		var danger_mix: float = clampf(
			inverse_lerp(warning_at, critical_at, ratio),
			0.0,
			1.0,
		)
		state_color = HudPalette.CAUTION.lerp(HudPalette.CRITICAL, danger_mix)
	label.text = "%d%%" % int(round(clampf(ratio, 0.0, 1.0) * 100.0))
	label.add_theme_color_override("font_color", state_color)
	icon.set_glyph_color(state_color)


func _set_row_visible(should_show: bool) -> void:
	if should_show == _target_visible:
		return
	_target_visible = should_show
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if should_show:
		visible = true
		_fade_tween.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
		return
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_fade_tween.tween_callback(_finish_hide)


func _finish_hide() -> void:
	if _target_visible:
		return
	visible = false
	_wetness_group.visible = false
	_cold_group.visible = false
	update_minimum_size()
