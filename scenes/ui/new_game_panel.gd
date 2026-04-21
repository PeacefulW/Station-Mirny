class_name NewGamePanel
extends Control

const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DEFAULT_SETTINGS_PATH: String = "res://data/balance/mountain_gen_settings.tres"
const BACKDROP_IMAGE_PATH: String = "res://assets/ui/backgrounds/mountain_worldgen_backdrop.jpg"
const PANEL_WIDTH: int = 560
const SURFACE_COLOR: Color = Color(0.07, 0.08, 0.10, 0.90)
const SURFACE_BORDER_COLOR: Color = Color(0.83, 0.66, 0.42, 0.32)
const SURFACE_ALT_COLOR: Color = Color(0.11, 0.12, 0.14, 0.92)
const SURFACE_MUTED_COLOR: Color = Color(0.09, 0.10, 0.12, 0.88)
const ACCENT_COLOR: Color = Color(0.92, 0.73, 0.43, 1.0)
const ACCENT_HOVER_COLOR: Color = Color(0.97, 0.80, 0.52, 1.0)
const TEXT_PRIMARY_COLOR: Color = Color(0.93, 0.93, 0.91, 1.0)
const TEXT_SECONDARY_COLOR: Color = Color(0.67, 0.68, 0.70, 1.0)
const BACKDROP_COLOR: Color = Color(0.04, 0.04, 0.05, 0.56)
const GLOW_WARM_COLOR: Color = Color(0.95, 0.71, 0.33, 0.04)
const GLOW_COLD_COLOR: Color = Color(0.36, 0.48, 0.58, 0.03)
const BUTTON_TEXT_DARK: Color = Color(0.13, 0.11, 0.08, 1.0)
const FRAME_COLOR: Color = Color(0.19, 0.14, 0.10, 0.42)
const HELP_BUTTON_COLOR: Color = Color(0.17, 0.17, 0.18, 0.92)
const HELP_BUTTON_HOVER_COLOR: Color = Color(0.22, 0.20, 0.18, 0.96)
const BACKDROP_SHADER_CODE: String = """
shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 3.0) = 1.2;
uniform vec4 tint : source_color = vec4(0.08, 0.07, 0.06, 0.18);

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE * blur_strength;
	vec4 color = texture(TEXTURE, UV) * 0.2;
	color += texture(TEXTURE, UV + vec2(texel.x, 0.0)) * 0.1;
	color += texture(TEXTURE, UV - vec2(texel.x, 0.0)) * 0.1;
	color += texture(TEXTURE, UV + vec2(0.0, texel.y)) * 0.1;
	color += texture(TEXTURE, UV - vec2(0.0, texel.y)) * 0.1;
	color += texture(TEXTURE, UV + texel) * 0.05;
	color += texture(TEXTURE, UV - texel) * 0.05;
	color += texture(TEXTURE, UV + vec2(texel.x, -texel.y)) * 0.05;
	color += texture(TEXTURE, UV + vec2(-texel.x, texel.y)) * 0.05;
	COLOR = mix(color, tint, tint.a);
}
"""
const FRAME_OVERLAY_SHADER_CODE: String = """
shader_type canvas_item;

uniform vec4 frame_color : source_color = vec4(0.21, 0.15, 0.11, 0.82);
uniform float frame_size : hint_range(0.02, 0.25) = 0.085;
uniform float softness : hint_range(0.005, 0.25) = 0.11;
uniform float dirt_strength : hint_range(0.0, 0.35) = 0.10;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 edge = min(UV, 1.0 - UV);
	float distance_to_edge = min(edge.x, edge.y);
	float vignette = 1.0 - smoothstep(frame_size, frame_size + softness, distance_to_edge);
	float dirt = (hash(floor(UV * vec2(260.0, 180.0))) - 0.5) * dirt_strength;
	float alpha = clamp(vignette + vignette * dirt, 0.0, 1.0) * frame_color.a;
	COLOR = vec4(frame_color.rgb, alpha);
}
"""

const PRIMARY_SLIDER_SPECS: Array[Dictionary] = [
	{
		"property": "density",
		"label_key": "UI_WORLDGEN_MOUNTAINS_DENSITY",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_DENSITY_DESC",
		"min": 0.0,
		"max": 1.0,
		"step": 0.01,
		"is_integer": false,
		"decimals": 2,
	},
	{
		"property": "scale",
		"label_key": "UI_WORLDGEN_MOUNTAINS_SCALE",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_SCALE_DESC",
		"min": 32.0,
		"max": 2048.0,
		"step": 1.0,
		"is_integer": false,
		"decimals": 0,
	},
	{
		"property": "continuity",
		"label_key": "UI_WORLDGEN_MOUNTAINS_CONTINUITY",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_CONTINUITY_DESC",
		"min": 0.0,
		"max": 1.0,
		"step": 0.01,
		"is_integer": false,
		"decimals": 2,
	},
	{
		"property": "ruggedness",
		"label_key": "UI_WORLDGEN_MOUNTAINS_RUGGEDNESS",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_RUGGEDNESS_DESC",
		"min": 0.0,
		"max": 1.0,
		"step": 0.01,
		"is_integer": false,
		"decimals": 2,
	},
]

const ADVANCED_SLIDER_SPECS: Array[Dictionary] = [
	{
		"property": "anchor_cell_size",
		"label_key": "UI_WORLDGEN_MOUNTAINS_ANCHOR_CELL_SIZE",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_ANCHOR_CELL_SIZE_DESC",
		"min": 32.0,
		"max": 512.0,
		"step": 1.0,
		"is_integer": true,
		"decimals": 0,
	},
	{
		"property": "gravity_radius",
		"label_key": "UI_WORLDGEN_MOUNTAINS_GRAVITY_RADIUS",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_GRAVITY_RADIUS_DESC",
		"min": 32.0,
		"max": 256.0,
		"step": 1.0,
		"is_integer": true,
		"decimals": 0,
	},
	{
		"property": "foot_band",
		"label_key": "UI_WORLDGEN_MOUNTAINS_FOOT_BAND",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_FOOT_BAND_DESC",
		"min": 0.02,
		"max": 0.3,
		"step": 0.01,
		"is_integer": false,
		"decimals": 2,
	},
	{
		"property": "interior_margin",
		"label_key": "UI_WORLDGEN_MOUNTAINS_INTERIOR_MARGIN",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_INTERIOR_MARGIN_DESC",
		"min": 0.0,
		"max": 4.0,
		"step": 1.0,
		"is_integer": true,
		"decimals": 0,
	},
	{
		"property": "latitude_influence",
		"label_key": "UI_WORLDGEN_MOUNTAINS_LATITUDE_INFLUENCE",
		"tooltip_key": "UI_WORLDGEN_MOUNTAINS_LATITUDE_INFLUENCE_DESC",
		"min": -1.0,
		"max": 1.0,
		"step": 0.05,
		"is_integer": false,
		"decimals": 2,
	},
]

signal back_requested
signal start_requested(seed_value: int, settings: MountainGenSettings)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
var _seed_line_edit: LineEdit = null
var _advanced_toggle: Button = null
var _advanced_container: VBoxContainer = null

func _ready() -> void:
	_rng.randomize()
	if EventBus and EventBus.has_signal("language_changed") and not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)
	reload_defaults()

func reload_defaults() -> void:
	_settings = _load_default_settings()
	_rebuild_ui("", false)
	_regenerate_seed_text()

func _rebuild_ui(seed_text: String, advanced_visible: bool) -> void:
	for child: Node in get_children():
		child.queue_free()
	_seed_line_edit = null
	_advanced_toggle = null
	_advanced_container = null
	_build_ui(seed_text, advanced_visible)

func _build_ui(seed_text: String, advanced_visible: bool) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP

	var backdrop := TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	backdrop.texture = _load_backdrop_texture()
	var backdrop_shader := Shader.new()
	backdrop_shader.code = BACKDROP_SHADER_CODE
	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = backdrop_shader
	backdrop_material.set_shader_parameter("blur_strength", 0.72)
	backdrop_material.set_shader_parameter("tint", Color(0.08, 0.06, 0.05, 0.08))
	backdrop.material = backdrop_material
	add_child(backdrop)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.color = BACKDROP_COLOR
	add_child(scrim)

	var warm_glow := ColorRect.new()
	warm_glow.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	warm_glow.color = GLOW_WARM_COLOR
	add_child(warm_glow)

	var cold_glow := ColorRect.new()
	cold_glow.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	cold_glow.color = GLOW_COLD_COLOR
	add_child(cold_glow)

	var frame_overlay := ColorRect.new()
	frame_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	frame_overlay.color = Color.WHITE
	var frame_shader := Shader.new()
	frame_shader.code = FRAME_OVERLAY_SHADER_CODE
	var frame_material := ShaderMaterial.new()
	frame_material.shader = frame_shader
	frame_material.set_shader_parameter("frame_color", FRAME_COLOR)
	frame_material.set_shader_parameter("frame_size", 0.034)
	frame_material.set_shader_parameter("softness", 0.055)
	frame_material.set_shader_parameter("dirt_strength", 0.025)
	frame_overlay.material = frame_material
	add_child(frame_overlay)

	var safe_area := MarginContainer.new()
	safe_area.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	safe_area.add_theme_constant_override("margin_left", 32)
	safe_area.add_theme_constant_override("margin_top", 20)
	safe_area.add_theme_constant_override("margin_right", 32)
	safe_area.add_theme_constant_override("margin_bottom", 20)
	add_child(safe_area)

	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	safe_area.add_child(center)

	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_height: float = maxf(340.0, minf(viewport_size.y - 40.0, 580.0))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, panel_height)
	panel.add_theme_stylebox_override("panel", _make_surface_stylebox())
	center.add_child(panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 18)
	panel_margin.add_theme_constant_override("margin_top", 14)
	panel_margin.add_theme_constant_override("margin_right", 18)
	panel_margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(panel_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_margin.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	content.add_child(header)

	var title := Label.new()
	title.text = Localization.t("UI_WORLDGEN_MOUNTAINS_PANEL_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)
	header.add_child(title)

	var title_rule_wrap := CenterContainer.new()
	header.add_child(title_rule_wrap)

	var title_rule := ColorRect.new()
	title_rule.custom_minimum_size = Vector2(72, 2)
	title_rule.color = ACCENT_COLOR
	title_rule_wrap.add_child(title_rule)

	var seed_section := PanelContainer.new()
	seed_section.add_theme_stylebox_override("panel", _make_section_stylebox())
	content.add_child(seed_section)

	var seed_margin := MarginContainer.new()
	seed_margin.add_theme_constant_override("margin_left", 12)
	seed_margin.add_theme_constant_override("margin_top", 10)
	seed_margin.add_theme_constant_override("margin_right", 12)
	seed_margin.add_theme_constant_override("margin_bottom", 10)
	seed_section.add_child(seed_margin)

	var seed_content := VBoxContainer.new()
	seed_content.add_theme_constant_override("separation", 8)
	seed_margin.add_child(seed_content)

	var seed_label := Label.new()
	seed_label.text = Localization.t("UI_WORLD_CREATE_SEED_LABEL")
	seed_label.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	seed_label.add_theme_font_size_override("font_size", 13)
	seed_content.add_child(seed_label)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_content.add_child(seed_row)

	_seed_line_edit = LineEdit.new()
	_seed_line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_seed_line_edit.placeholder_text = Localization.t("UI_WORLD_CREATE_SEED_PLACEHOLDER")
	_seed_line_edit.text = seed_text
	_apply_input_style(_seed_line_edit)
	seed_row.add_child(_seed_line_edit)

	var random_button := Button.new()
	random_button.text = Localization.t("UI_WORLD_CREATE_RANDOM_BUTTON")
	random_button.custom_minimum_size = Vector2(116, 38)
	_apply_secondary_button_style(random_button)
	random_button.pressed.connect(_on_random_seed_pressed)
	seed_row.add_child(random_button)

	var primary_section := VBoxContainer.new()
	primary_section.add_theme_constant_override("separation", 2)
	content.add_child(primary_section)
	for spec: Dictionary in PRIMARY_SLIDER_SPECS:
		primary_section.add_child(_build_slider_row(spec))

	_advanced_toggle = Button.new()
	_advanced_toggle.toggle_mode = true
	_advanced_toggle.flat = true
	_advanced_toggle.button_pressed = advanced_visible
	_advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_advanced_toggle.size_flags_horizontal = SIZE_EXPAND_FILL
	_advanced_toggle.custom_minimum_size = Vector2(0, 28)
	_advanced_toggle.text = _format_advanced_toggle_text(advanced_visible)
	_apply_text_button_style(_advanced_toggle)
	_advanced_toggle.toggled.connect(_on_advanced_toggled)
	content.add_child(_advanced_toggle)

	_advanced_container = VBoxContainer.new()
	_advanced_container.visible = advanced_visible
	_advanced_container.add_theme_constant_override("separation", 2)
	content.add_child(_advanced_container)
	for spec: Dictionary in ADVANCED_SLIDER_SPECS:
		_advanced_container.add_child(_build_slider_row(spec))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	content.add_child(buttons)

	var back_button := Button.new()
	back_button.text = Localization.t("UI_MAIN_LOAD_BACK")
	back_button.custom_minimum_size = Vector2(96, 36)
	_apply_secondary_button_style(back_button)
	back_button.pressed.connect(func() -> void:
		back_requested.emit()
	)
	buttons.add_child(back_button)

	var start_button := Button.new()
	start_button.text = Localization.t("UI_WORLDGEN_MOUNTAINS_START_BUTTON")
	start_button.custom_minimum_size = Vector2(182, 36)
	_apply_primary_button_style(start_button)
	start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(start_button)

func _build_slider_row(spec: Dictionary) -> Control:
	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 2)
	row_margin.add_theme_constant_override("margin_top", 4)
	row_margin.add_theme_constant_override("margin_right", 2)
	row_margin.add_theme_constant_override("margin_bottom", 4)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	row_margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)

	var label := Label.new()
	label.text = Localization.t(str(spec.get("label_key", "")))
	label.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)
	label.add_theme_font_size_override("font_size", 13)
	header.add_child(label)

	var help_button := _make_help_button(str(spec.get("tooltip_key", "")))
	header.add_child(help_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(56, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", ACCENT_COLOR)
	value_label.add_theme_font_size_override("font_size", 12)
	_update_value_label(value_label, spec, _read_setting_value(spec))
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.min_value = float(spec.get("min", 0.0))
	slider.max_value = float(spec.get("max", 1.0))
	slider.step = float(spec.get("step", 0.01))
	slider.value = _read_setting_value(spec)
	slider.modulate = Color(0.95, 0.95, 0.95, 1.0)
	column.add_child(slider)

	slider.value_changed.connect(func(new_value: float) -> void:
		_apply_setting_value(spec, new_value)
		_update_value_label(value_label, spec, new_value)
	)
	return row_margin

func _make_help_button(tooltip_key: String) -> Button:
	var button := Button.new()
	button.text = "?"
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_HELP
	button.tooltip_text = Localization.t(tooltip_key)
	button.custom_minimum_size = Vector2(18, 18)
	_apply_help_button_style(button)
	return button

func _make_surface_stylebox() -> StyleBoxFlat:
	var style := _make_stylebox(SURFACE_COLOR, Color.TRANSPARENT, 0, 20)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 10)
	return style

func _make_section_stylebox() -> StyleBoxFlat:
	return _make_stylebox(SURFACE_ALT_COLOR, Color.TRANSPARENT, 0, 14)

func _make_button_stylebox(fill: Color, border: Color) -> StyleBoxFlat:
	return _make_stylebox(fill, border, 1, 14)

func _make_stylebox(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style

func _apply_primary_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_button_stylebox(ACCENT_COLOR, ACCENT_COLOR))
	button.add_theme_stylebox_override("hover", _make_button_stylebox(ACCENT_HOVER_COLOR, ACCENT_HOVER_COLOR))
	button.add_theme_stylebox_override("pressed", _make_button_stylebox(Color(0.77, 0.60, 0.32, 1.0), Color(0.77, 0.60, 0.32, 1.0)))
	button.add_theme_stylebox_override("focus", _make_button_stylebox(ACCENT_HOVER_COLOR, ACCENT_HOVER_COLOR))
	button.add_theme_stylebox_override("disabled", _make_button_stylebox(Color(0.30, 0.27, 0.22, 0.9), Color(0.30, 0.27, 0.22, 0.9)))
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", BUTTON_TEXT_DARK)
	button.add_theme_color_override("font_hover_color", BUTTON_TEXT_DARK)
	button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_DARK)
	button.add_theme_color_override("font_focus_color", BUTTON_TEXT_DARK)

func _apply_secondary_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_button_stylebox(SURFACE_ALT_COLOR, Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", _make_button_stylebox(Color(0.15, 0.16, 0.18, 0.96), SURFACE_BORDER_COLOR))
	button.add_theme_stylebox_override("pressed", _make_button_stylebox(Color(0.11, 0.12, 0.14, 0.98), SURFACE_BORDER_COLOR))
	button.add_theme_stylebox_override("focus", _make_button_stylebox(Color(0.15, 0.16, 0.18, 0.96), SURFACE_BORDER_COLOR))
	button.add_theme_stylebox_override("disabled", _make_button_stylebox(Color(0.10, 0.11, 0.13, 0.78), Color.TRANSPARENT))
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_PRIMARY_COLOR)
	button.add_theme_color_override("font_focus_color", TEXT_PRIMARY_COLOR)

func _apply_text_button_style(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)
	button.add_theme_color_override("font_hover_color", ACCENT_COLOR)
	button.add_theme_color_override("font_pressed_color", ACCENT_COLOR)
	button.add_theme_color_override("font_focus_color", ACCENT_COLOR)

func _apply_help_button_style(button: Button) -> void:
	var normal := _make_stylebox(HELP_BUTTON_COLOR, Color.TRANSPARENT, 0, 9)
	var hover := _make_stylebox(HELP_BUTTON_HOVER_COLOR, Color.TRANSPARENT, 0, 9)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_PRIMARY_COLOR)
	button.add_theme_color_override("font_focus_color", TEXT_PRIMARY_COLOR)

func _apply_input_style(line_edit: LineEdit) -> void:
	var normal := _make_stylebox(SURFACE_MUTED_COLOR, Color(1.0, 1.0, 1.0, 0.08), 1, 12)
	var focus := _make_stylebox(SURFACE_MUTED_COLOR, SURFACE_BORDER_COLOR, 1, 12)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 9
	normal.content_margin_bottom = 9
	focus.content_margin_left = 12
	focus.content_margin_right = 12
	focus.content_margin_top = 9
	focus.content_margin_bottom = 9
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("focus", focus)
	line_edit.add_theme_stylebox_override("read_only", normal)
	line_edit.add_theme_font_size_override("font_size", 14)
	line_edit.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)
	line_edit.add_theme_color_override("font_placeholder_color", TEXT_SECONDARY_COLOR)
	line_edit.caret_blink = true
	line_edit.custom_minimum_size.y = 38

func _format_advanced_toggle_text(is_pressed: bool) -> String:
	var prefix: String = "v" if is_pressed else ">"
	return "%s %s" % [prefix, Localization.t("UI_WORLDGEN_MOUNTAINS_ADVANCED_TOGGLE")]

func _read_setting_value(spec: Dictionary) -> float:
	var property_name: StringName = StringName(str(spec.get("property", "")))
	var value: Variant = _settings.get(property_name)
	return float(value)

func _apply_setting_value(spec: Dictionary, value: float) -> void:
	var property_name: StringName = StringName(str(spec.get("property", "")))
	if bool(spec.get("is_integer", false)):
		_settings.set(property_name, int(round(value)))
		return
	_settings.set(property_name, value)

func _update_value_label(label: Label, spec: Dictionary, value: float) -> void:
	var decimals: int = int(spec.get("decimals", 0))
	if bool(spec.get("is_integer", false)):
		label.text = str(int(round(value)))
		return
	label.text = ("%0." + str(decimals) + "f") % value

func _on_random_seed_pressed() -> void:
	_regenerate_seed_text()

func _on_advanced_toggled(is_pressed: bool) -> void:
	if _advanced_container != null:
		_advanced_container.visible = is_pressed
	if _advanced_toggle != null:
		_advanced_toggle.text = _format_advanced_toggle_text(is_pressed)

func _on_start_pressed() -> void:
	start_requested.emit(
		_resolve_seed_value(),
		MountainGenSettings.from_save_dict(_settings.to_save_dict())
	)

func _resolve_seed_value() -> int:
	if _seed_line_edit == null:
		return WorldRuntimeConstants.DEFAULT_WORLD_SEED
	var raw_value: String = _seed_line_edit.text.strip_edges()
	if raw_value.is_empty():
		_regenerate_seed_text()
		raw_value = _seed_line_edit.text.strip_edges()
	if raw_value.is_valid_int():
		return int(raw_value)
	return _hash_seed_text(raw_value)

func _regenerate_seed_text() -> void:
	if _seed_line_edit == null:
		return
	_seed_line_edit.text = str(_generate_seed_value())

func _generate_seed_value() -> int:
	var generated_seed: int = int(_rng.randi() & 0x7FFFFFFF)
	if generated_seed == 0:
		return WorldRuntimeConstants.DEFAULT_WORLD_SEED
	return generated_seed

func _hash_seed_text(text: String) -> int:
	var hashing_context: HashingContext = HashingContext.new()
	var start_error: Error = hashing_context.start(HashingContext.HASH_SHA1)
	if start_error != OK:
		return WorldRuntimeConstants.DEFAULT_WORLD_SEED
	hashing_context.update(text.to_utf8_buffer())
	var digest: PackedByteArray = hashing_context.finish()
	var hashed_value: int = 0
	for i: int in range(mini(4, digest.size())):
		hashed_value = (hashed_value << 8) | int(digest[i])
	hashed_value &= 0x7FFFFFFF
	if hashed_value == 0:
		return WorldRuntimeConstants.DEFAULT_WORLD_SEED
	return hashed_value

func _load_default_settings() -> MountainGenSettings:
	var resource: MountainGenSettings = ResourceLoader.load(DEFAULT_SETTINGS_PATH, "MountainGenSettings") as MountainGenSettings
	if resource == null:
		return MountainGenSettings.hard_coded_defaults()
	return MountainGenSettings.from_save_dict(resource.to_save_dict())

func _load_backdrop_texture() -> Texture2D:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(BACKDROP_IMAGE_PATH))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _on_language_changed(_locale: String) -> void:
	var current_seed_text: String = _seed_line_edit.text if _seed_line_edit != null else ""
	var advanced_visible: bool = _advanced_toggle.button_pressed if _advanced_toggle != null else false
	_rebuild_ui(current_seed_text, advanced_visible)
