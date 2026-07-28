class_name VisualRuntimeLabPanel
extends CanvasLayer

signal apply_requested
signal save_requested
signal reset_requested
signal zone_overlay_changed(enabled: bool)
signal grid_overlay_changed(enabled: bool)
signal mountain_overlay_changed(enabled: bool)
signal collision_overlay_changed(enabled: bool)
signal day_night_requested

const PANEL_WIDTH: float = 386.0
const COLOR_PANEL: Color = Color(0.035, 0.055, 0.05, 0.94)
const COLOR_SURFACE: Color = Color(0.075, 0.105, 0.09, 0.96)
const COLOR_BORDER: Color = Color(0.31, 0.46, 0.36, 0.72)
const COLOR_ACCENT: Color = Color(0.67, 0.86, 0.54, 1.0)
const COLOR_TEXT: Color = Color(0.87, 0.92, 0.84, 1.0)
const COLOR_MUTED: Color = Color(0.59, 0.67, 0.60, 1.0)

const CONTROL_GROUPS: Array[Dictionary] = [
	{
		"title": &"UI_VISUAL_LAB_GROUP_GROUND",
		"controls": [
			[&"ground.grass_coverage", &"UI_VISUAL_LAB_GROUND_GRASS_COVERAGE", 0.0, 1.0, 0.01],
			[&"ground.orange_coverage", &"UI_VISUAL_LAB_GROUND_ORANGE_COVERAGE", 0.0, 0.8, 0.01],
			[&"ground.rock_visual_coverage", &"UI_VISUAL_LAB_GROUND_ROCK_COVERAGE", 0.0, 1.0, 0.01],
			[&"ground.path_strength", &"UI_VISUAL_LAB_GROUND_PATH_STRENGTH", 0.0, 1.0, 0.01],
		],
	},
	{
		"title": &"UI_VISUAL_LAB_GROUP_GRASS",
		"controls": [
			[&"grass.density_scale", &"UI_VISUAL_LAB_GRASS_DENSITY", 0.0, 8.0, 0.05],
			[&"grass.height_scale", &"UI_VISUAL_LAB_GRASS_HEIGHT_SCALE", 0.25, 2.0, 0.01],
			[&"grass.tuft_min_height_px", &"UI_VISUAL_LAB_GRASS_MIN_HEIGHT", 8.0, 64.0, 1.0],
			[&"grass.tuft_max_height_px", &"UI_VISUAL_LAB_GRASS_MAX_HEIGHT", 20.0, 96.0, 1.0],
			[&"grass.variety", &"UI_VISUAL_LAB_GRASS_VARIETY", 1.0, 16.0, 1.0],
			[&"grass.wind_sway_fraction", &"UI_VISUAL_LAB_GRASS_SWAY", 0.0, 0.35, 0.01],
		],
	},
	{
		"title": &"UI_VISUAL_LAB_GROUP_TREES",
		"controls": [
			[&"trees.density", &"UI_VISUAL_LAB_TREES_DENSITY", 0.0, 1.0, 0.01],
			[&"trees.min_distance_px", &"UI_VISUAL_LAB_TREES_DISTANCE", 32.0, 256.0, 2.0],
			[&"trees.visual_size_min_px", &"UI_VISUAL_LAB_TREES_MIN_SIZE", 64.0, 240.0, 2.0],
			[&"trees.visual_size_max_px", &"UI_VISUAL_LAB_TREES_MAX_SIZE", 96.0, 254.0, 2.0],
		],
	},
	{
		"title": &"UI_VISUAL_LAB_GROUP_ROCKS",
		"controls": [
			[&"rocks.density", &"UI_VISUAL_LAB_ROCKS_DENSITY", 0.0, 1.0, 0.01],
			[&"rocks.max_per_chunk", &"UI_VISUAL_LAB_ROCKS_MAX", 0.0, 64.0, 1.0],
			[&"rocks.asset_variant_count", &"UI_VISUAL_LAB_ROCKS_VARIETY", 1.0, 10.0, 1.0],
		],
	},
	{
		"title": &"UI_VISUAL_LAB_GROUP_WORLD",
		"controls": [
			[&"lakes.deep_threshold", &"UI_VISUAL_LAB_LAKE_DEPTH", 0.05, 0.5, 0.01],
			[&"lakes.shore_warp_amplitude", &"UI_VISUAL_LAB_LAKE_SHORE", 0.0, 1.0, 0.01],
			[&"mountains.density", &"UI_VISUAL_LAB_MOUNTAIN_DENSITY", 0.0, 1.0, 0.01],
			[&"mountains.ruggedness", &"UI_VISUAL_LAB_MOUNTAIN_RUGGEDNESS", 0.0, 1.0, 0.01],
		],
	},
]

var _authoring: VisualRuntimeLabAuthoring = null
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _action_buttons: Array[BaseButton] = []
var _status_label: Label = null
var _probe_label: Label = null
var _inspector_label: Label = null
var _auto_apply: CheckButton = null
var _zone_toggle: CheckButton = null
var _texture_manifest: RichTextLabel = null
var _cursor_tooltip: PanelContainer = null
var _cursor_tooltip_label: Label = null
var _is_refreshing: bool = false


func _ready() -> void:
	layer = 60


func setup(authoring: VisualRuntimeLabAuthoring) -> void:
	_authoring = authoring
	_build_ui()
	if _authoring != null and _authoring.ground != null:
		refresh_values()


func refresh_values() -> void:
	if _authoring == null:
		return
	_is_refreshing = true
	for control_id_variant: Variant in _sliders.keys():
		var control_id: StringName = control_id_variant as StringName
		var slider: HSlider = _sliders.get(control_id, null) as HSlider
		if slider != null:
			slider.value = _authoring.get_value(control_id)
			_update_value_label(control_id, slider.value)
	_texture_manifest.text = _authoring.get_texture_manifest_text()
	_is_refreshing = false


func set_busy(is_busy: bool) -> void:
	for button: BaseButton in _action_buttons:
		button.disabled = is_busy
	for slider_variant: Variant in _sliders.values():
		var slider: HSlider = slider_variant as HSlider
		if slider != null:
			slider.editable = not is_busy


func set_status(key: String, args: Dictionary = {}) -> void:
	if _status_label != null:
		_status_label.text = Localization.t(key, args)


func set_probe_summary(summary: Dictionary) -> void:
	if _probe_label == null:
		return
	_probe_label.text = Localization.t(
		"UI_VISUAL_LAB_PROBE_SUMMARY",
		{
			"seed": int(summary.get("seed", 0)),
			"version": int(summary.get("version", 0)),
			"zoom": "%.2f" % float(summary.get("zoom", 0.0)),
			"chunks": int(summary.get("chunk_count", 0)),
			"match": (
				Localization.t("UI_VISUAL_LAB_MATCH_FULL")
				if bool(summary.get("exact_match", false))
				else Localization.t("UI_VISUAL_LAB_MATCH_BEST")
			),
		},
	)


func set_inspector_text(text: String) -> void:
	if _inspector_label != null:
		_inspector_label.text = text


func is_zone_overlay_enabled() -> bool:
	return _zone_toggle != null and _zone_toggle.button_pressed


func set_zone_overlay_enabled_without_signal(enabled: bool) -> void:
	if _zone_toggle != null:
		_zone_toggle.set_pressed_no_signal(enabled)


func get_cursor_texture_tooltip_debug_snapshot() -> Dictionary:
	return {
		"visible": _cursor_tooltip != null and _cursor_tooltip.visible,
		"text": (
			_cursor_tooltip_label.text
			if _cursor_tooltip_label != null
			else ""
		),
	}


func show_cursor_texture_tooltip(viewport_position: Vector2, text: String) -> void:
	if _cursor_tooltip == null or _cursor_tooltip_label == null:
		return
	_cursor_tooltip_label.text = text
	_cursor_tooltip.visible = true
	_cursor_tooltip.reset_size()
	var tooltip_size: Vector2 = _cursor_tooltip.get_combined_minimum_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_cursor_tooltip.position = Vector2(
		clampf(
			viewport_position.x + 18.0,
			8.0,
			maxf(8.0, viewport_size.x - tooltip_size.x - 8.0),
		),
		clampf(
			viewport_position.y + 18.0,
			8.0,
			maxf(8.0, viewport_size.y - tooltip_size.y - 8.0),
		),
	)


func hide_cursor_texture_tooltip() -> void:
	if _cursor_tooltip != null:
		_cursor_tooltip.visible = false


func _build_ui() -> void:
	var root: PanelContainer = PanelContainer.new()
	root.name = "VisualLabRail"
	root.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	root.offset_left = 16.0
	root.offset_top = 16.0
	root.offset_right = PANEL_WIDTH + 16.0
	root.offset_bottom = -16.0
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, COLOR_BORDER, 12.0))
	add_child(root)

	var rail_margin: MarginContainer = MarginContainer.new()
	rail_margin.add_theme_constant_override("margin_left", 16)
	rail_margin.add_theme_constant_override("margin_top", 14)
	rail_margin.add_theme_constant_override("margin_right", 16)
	rail_margin.add_theme_constant_override("margin_bottom", 14)
	root.add_child(rail_margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	rail_margin.add_child(column)
	column.add_child(_make_title())
	column.add_child(_make_toolbar())

	_probe_label = _make_label("", 12, COLOR_MUTED)
	_probe_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_probe_label)
	_status_label = _make_label(Localization.t("UI_VISUAL_LAB_STATUS_READY"), 13, COLOR_ACCENT)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.custom_minimum_size.x = PANEL_WIDTH - 56.0
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	for group: Dictionary in CONTROL_GROUPS:
		content.add_child(_make_control_group(group))
	content.add_child(_make_inspector_section())
	content.add_child(_make_texture_section())
	column.add_child(_make_actions())
	_build_cursor_tooltip()


func _build_cursor_tooltip() -> void:
	_cursor_tooltip = PanelContainer.new()
	_cursor_tooltip.name = "CursorTextureTooltip"
	_cursor_tooltip.visible = false
	_cursor_tooltip.z_index = 100
	_cursor_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_tooltip.custom_minimum_size.x = 290.0
	_cursor_tooltip.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.025, 0.04, 0.035, 0.97), COLOR_ACCENT, 8.0),
	)
	add_child(_cursor_tooltip)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_cursor_tooltip.add_child(margin)
	_cursor_tooltip_label = _make_label("", 12, COLOR_TEXT)
	_cursor_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(_cursor_tooltip_label)


func _make_title() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var eyebrow: Label = _make_label(Localization.t("UI_VISUAL_LAB_EYEBROW"), 11, COLOR_ACCENT)
	eyebrow.uppercase = true
	box.add_child(eyebrow)
	var title: Label = _make_label(Localization.t("UI_VISUAL_LAB_TITLE"), 24, COLOR_TEXT)
	box.add_child(title)
	var subtitle: Label = _make_label(Localization.t("UI_VISUAL_LAB_SUBTITLE"), 12, COLOR_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(subtitle)
	return box


func _make_toolbar() -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 7)
	_zone_toggle = _make_toggle("UI_VISUAL_LAB_ZONES", _on_zone_toggled)
	grid.add_child(_zone_toggle)
	grid.add_child(_make_toggle("UI_VISUAL_LAB_GRID", _on_grid_toggled))
	grid.add_child(_make_toggle("UI_VISUAL_LAB_MOUNTAIN_MASK", _on_mountain_toggled))
	grid.add_child(_make_toggle("UI_VISUAL_LAB_COLLISIONS", _on_collision_toggled))
	var day_button: Button = _make_button("UI_VISUAL_LAB_DAY_NIGHT", _on_day_night_pressed)
	grid.add_child(day_button)
	_auto_apply = _make_toggle("UI_VISUAL_LAB_AUTO_APPLY", Callable())
	_auto_apply.button_pressed = true
	grid.add_child(_auto_apply)
	return grid


func _make_control_group(group: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_SURFACE, Color(0.2, 0.3, 0.24, 0.6), 8.0))
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	box.add_child(
		_make_label(Localization.t(String(group.get("title", &""))), 14, COLOR_ACCENT)
	)
	var controls: Array = group.get("controls", []) as Array
	for definition_variant: Variant in controls:
		box.add_child(_make_slider(definition_variant as Array))
	return panel


func _make_slider(definition: Array) -> Control:
	var control_id: StringName = definition[0] as StringName
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var header: HBoxContainer = HBoxContainer.new()
	var label: Label = _make_label(Localization.t(String(definition[1])), 12, COLOR_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label: Label = _make_label("", 12, COLOR_ACCENT)
	value_label.custom_minimum_size.x = 52.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value_label)
	row.add_child(header)
	var slider: HSlider = HSlider.new()
	slider.min_value = float(definition[2])
	slider.max_value = float(definition[3])
	slider.step = float(definition[4])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_slider_value_changed.bind(control_id))
	slider.drag_ended.connect(_on_slider_drag_ended)
	row.add_child(slider)
	_sliders[control_id] = slider
	_value_labels[control_id] = value_label
	return row


func _make_inspector_section() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(_make_label(Localization.t("UI_VISUAL_LAB_INSPECTOR"), 14, COLOR_ACCENT))
	_inspector_label = _make_label(Localization.t("UI_VISUAL_LAB_INSPECTOR_EMPTY"), 11, COLOR_MUTED)
	_inspector_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector_label.custom_minimum_size.y = 68.0
	box.add_child(_inspector_label)
	return box


func _make_texture_section() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(_make_label(Localization.t("UI_VISUAL_LAB_TEXTURES"), 14, COLOR_ACCENT))
	var legend: Label = _make_label(Localization.t("UI_VISUAL_LAB_ZONE_LEGEND"), 11, COLOR_MUTED)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(legend)
	_texture_manifest = RichTextLabel.new()
	_texture_manifest.bbcode_enabled = true
	_texture_manifest.fit_content = true
	_texture_manifest.custom_minimum_size.y = 130.0
	_texture_manifest.add_theme_font_size_override("normal_font_size", 10)
	_texture_manifest.add_theme_color_override("default_color", COLOR_MUTED)
	box.add_child(_texture_manifest)
	return box


func _make_actions() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	var apply_button: Button = _make_button("UI_VISUAL_LAB_APPLY", _on_apply_pressed)
	apply_button.add_theme_color_override("font_color", Color(0.05, 0.08, 0.04, 1.0))
	apply_button.add_theme_stylebox_override(
		"normal",
		_panel_style(COLOR_ACCENT, Color(0.8, 0.95, 0.7, 1.0), 7.0),
	)
	box.add_child(apply_button)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var save_button: Button = _make_button("UI_VISUAL_LAB_SAVE_RUNTIME", _on_save_pressed)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(save_button)
	var reset_button: Button = _make_button("UI_VISUAL_LAB_RESET", _on_reset_pressed)
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reset_button)
	box.add_child(row)
	return box


func _make_button(key: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = Localization.t(key)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34.0
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(Color(0.11, 0.16, 0.13, 1.0), Color(0.27, 0.4, 0.32, 1.0), 7.0),
	)
	if callback.is_valid():
		button.pressed.connect(callback)
	_action_buttons.append(button)
	return button


func _make_toggle(key: String, callback: Callable) -> CheckButton:
	var button: CheckButton = CheckButton.new()
	button.text = Localization.t(key)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(165.0, 30.0)
	button.add_theme_font_size_override("font_size", 11)
	if callback.is_valid():
		button.toggled.connect(callback)
	_action_buttons.append(button)
	return button


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _panel_style(fill: Color, border: Color, radius: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(radius))
	return style


func _on_slider_value_changed(value: float, control_id: StringName) -> void:
	if _is_refreshing or _authoring == null:
		return
	_authoring.set_value(control_id, value)
	_update_value_label(control_id, _authoring.get_value(control_id))
	set_status("UI_VISUAL_LAB_STATUS_STAGED")


func _on_slider_drag_ended(value_changed: bool) -> void:
	if value_changed and _auto_apply != null and _auto_apply.button_pressed:
		apply_requested.emit()


func _update_value_label(control_id: StringName, value: float) -> void:
	var label: Label = _value_labels.get(control_id, null) as Label
	if label == null:
		return
	var slider: HSlider = _sliders.get(control_id, null) as HSlider
	if slider != null and slider.step >= 1.0:
		label.text = str(roundi(value))
	else:
		label.text = "%.2f" % value


func _on_zone_toggled(enabled: bool) -> void:
	zone_overlay_changed.emit(enabled)


func _on_grid_toggled(enabled: bool) -> void:
	grid_overlay_changed.emit(enabled)


func _on_mountain_toggled(enabled: bool) -> void:
	mountain_overlay_changed.emit(enabled)


func _on_collision_toggled(enabled: bool) -> void:
	collision_overlay_changed.emit(enabled)


func _on_day_night_pressed() -> void:
	day_night_requested.emit()


func _on_apply_pressed() -> void:
	apply_requested.emit()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_reset_pressed() -> void:
	reset_requested.emit()
