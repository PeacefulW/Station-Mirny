class_name NewGamePanel
extends Control

const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldPreviewCanvas = preload("res://scenes/ui/world_preview_canvas.gd")
const WorldPreviewController = preload("res://core/systems/world/world_preview_controller.gd")
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

uniform float blur_strength : hint_range(0.0, 3.0) = 0.8;
uniform vec4 tint : source_color = vec4(0.06, 0.05, 0.04, 0.12);
uniform float scanline_count : hint_range(0.0, 1080.0) = 480.0;
uniform float scanline_speed : hint_range(0.0, 5.0) = 1.0;
uniform float sweep_speed : hint_range(0.0, 2.0) = 0.4;

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE * blur_strength;
	vec4 color = texture(TEXTURE, UV) * 0.4;
	color += texture(TEXTURE, UV + vec2(texel.x, 0.0)) * 0.15;
	color += texture(TEXTURE, UV - vec2(texel.x, 0.0)) * 0.15;
	color += texture(TEXTURE, UV + vec2(0.0, texel.y)) * 0.15;
	color += texture(TEXTURE, UV - vec2(0.0, texel.y)) * 0.15;

	// Scanlines
	float scanline = sin(UV.y * scanline_count + TIME * scanline_speed) * 0.04 + 0.96;
	color.rgb *= scanline;

	// Radar Sweep
	float sweep = mod(UV.y - TIME * sweep_speed, 1.0);
	sweep = smoothstep(0.95, 1.0, sweep) * 0.08;
	color.rgb += vec3(sweep);

	COLOR = mix(color, tint, tint.a);
}
"""
const RADAR_GRID_SHADER_CODE: String = """
shader_type canvas_item;

uniform vec4 grid_color : source_color = vec4(0.92, 0.73, 0.43, 0.05);
uniform float cell_count : hint_range(1.0, 50.0) = 10.0;
uniform float line_width : hint_range(0.001, 0.1) = 0.01;

void fragment() {
	vec2 grid = fract(UV * cell_count);
	float line = step(1.0 - line_width, grid.x) + step(1.0 - line_width, grid.y);
	COLOR = vec4(grid_color.rgb, clamp(line, 0.0, 1.0) * grid_color.a);
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
const BUTTON_PULSE_SHADER_CODE: String = """
shader_type canvas_item;

uniform vec4 pulse_color : source_color = vec4(0.92, 0.73, 0.43, 0.15);
uniform float speed : hint_range(0.1, 5.0) = 1.2;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	// Pure additive glow on top of original color to keep text readable
	float pulse = (sin(TIME * speed) * 0.5 + 0.5) * intensity;
	COLOR = vec4(color.rgb + pulse_color.rgb * pulse, color.a);
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
var _preview_canvas: WorldPreviewCanvas = null
var _preview_controller: WorldPreviewController = WorldPreviewController.new()
var _preview_seed_value: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED

func _ready() -> void:
	_rng.randomize()
	_preview_controller.start()
	if EventBus and EventBus.has_signal("language_changed") and not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)
	reload_defaults()

func _exit_tree() -> void:
	_preview_controller.stop()

func _process(delta: float) -> void:
	_preview_controller.tick(delta)

func reload_defaults() -> void:
	_settings = _load_default_settings()
	_rebuild_ui("", 0)
	_regenerate_seed_text()

func _rebuild_ui(seed_text: String, tab_index: int = 0) -> void:
	_preview_canvas = null
	_preview_controller.attach_canvas(null)
	for child: Node in get_children():
		child.queue_free()
	_seed_line_edit = null
	_advanced_toggle = null
	_advanced_container = null
	_build_ui(seed_text, tab_index)

func _build_ui(seed_text: String, active_tab: int) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	modulate.a = 0.0
	var entrance_tween := create_tween()
	entrance_tween.tween_property(self, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)

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

	var radar_grid := ColorRect.new()
	radar_grid.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var grid_shader := Shader.new()
	grid_shader.code = RADAR_GRID_SHADER_CODE
	var grid_material := ShaderMaterial.new()
	grid_material.shader = grid_shader
	radar_grid.material = grid_material
	add_child(radar_grid)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scrim.color = BACKDROP_COLOR
	add_child(scrim)

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
	var panel_height: float = maxf(420.0, minf(viewport_size.y - 40.0, 680.0))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, panel_height)
	panel.add_theme_stylebox_override("panel", _make_surface_stylebox())
	center.add_child(panel)

	var panel_layout := VBoxContainer.new()
	panel_layout.add_theme_constant_override("separation", 0)
	panel.add_child(panel_layout)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 20)
	header_margin.add_theme_constant_override("margin_top", 16)
	header_margin.add_theme_constant_override("margin_right", 20)
	header_margin.add_theme_constant_override("margin_bottom", 12)
	panel_layout.add_child(header_margin)

	var header := HBoxContainer.new()
	header_margin.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	var title := Label.new()
	title.text = Localization.t("UI_WORLDGEN_MOUNTAINS_PANEL_TITLE")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "STATION MIRNY // DEPLOYMENT PROTOCOL"
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", ACCENT_COLOR)
	title_box.add_child(subtitle)

	var preview_margin := MarginContainer.new()
	preview_margin.add_theme_constant_override("margin_left", 20)
	preview_margin.add_theme_constant_override("margin_top", 0)
	preview_margin.add_theme_constant_override("margin_right", 20)
	preview_margin.add_theme_constant_override("margin_bottom", 14)
	panel_layout.add_child(preview_margin)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(0.0, 250.0)
	preview_panel.add_theme_stylebox_override("panel", _make_section_stylebox())
	preview_margin.add_child(preview_panel)

	_preview_canvas = WorldPreviewCanvas.new()
	_preview_canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_canvas.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_canvas.custom_minimum_size = Vector2(0.0, 250.0)
	preview_panel.add_child(_preview_canvas)
	_preview_controller.attach_canvas(_preview_canvas)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	tabs.clip_tabs = false
	tabs.current_tab = active_tab
	_apply_tabs_style(tabs)
	panel_layout.add_child(tabs)

	_build_comms_tab(tabs, seed_text)
	_build_geology_tab(tabs)

	# Explicitly set titles AFTER adding children to avoid underscores from node names
	tabs.set_tab_title(0, Localization.t("UI_NEW_GAME_TAB_COMMS"))
	tabs.set_tab_title(1, Localization.t("UI_NEW_GAME_TAB_GEOLOGY"))

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 20)
	footer_margin.add_theme_constant_override("margin_top", 12)
	footer_margin.add_theme_constant_override("margin_right", 20)
	footer_margin.add_theme_constant_override("margin_bottom", 16)
	panel_layout.add_child(footer_margin)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	footer_margin.add_child(footer)

	var back_button := Button.new()
	back_button.text = Localization.t("UI_MAIN_LOAD_BACK")
	back_button.custom_minimum_size = Vector2(110, 36)
	_apply_secondary_button_style(back_button)
	back_button.pressed.connect(func() -> void:
		back_requested.emit()
	)
	footer.add_child(back_button)

	var start_button := Button.new()
	start_button.text = Localization.t("UI_WORLDGEN_MOUNTAINS_START_BUTTON")
	start_button.custom_minimum_size = Vector2(210, 36)
	_apply_primary_button_style(start_button)
	var pulse_shader := Shader.new()
	pulse_shader.code = BUTTON_PULSE_SHADER_CODE
	var pulse_mat := ShaderMaterial.new()
	pulse_mat.shader = pulse_shader
	start_button.material = pulse_mat
	# Set base intensity for the shader
	start_button.material.set_shader_parameter("intensity", 0.1)
	start_button.pressed.connect(_on_start_pressed)
	footer.add_child(start_button)

func _build_comms_tab(tabs: TabContainer, seed_text: String) -> void:
	var margin := MarginContainer.new()
	tabs.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	margin.add_child(content)

	var sector_label := _make_title_label(Localization.t("UI_NEW_GAME_SECTOR_LABEL") % Localization.t("UI_NEW_GAME_COMMS_TITLE"))
	content.add_child(sector_label)

	var seed_section := VBoxContainer.new()
	seed_section.add_theme_constant_override("separation", 8)
	content.add_child(seed_section)

	var seed_label := Label.new()
	seed_label.text = Localization.t("UI_WORLD_CREATE_SEED_LABEL")
	seed_label.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	seed_label.add_theme_font_size_override("font_size", 13)
	seed_section.add_child(seed_label)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	seed_section.add_child(seed_row)

	_seed_line_edit = LineEdit.new()
	_seed_line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_seed_line_edit.placeholder_text = Localization.t("UI_WORLD_CREATE_SEED_PLACEHOLDER")
	_seed_line_edit.text = seed_text
	_apply_input_style(_seed_line_edit)
	_seed_line_edit.text_changed.connect(_on_seed_text_changed)
	seed_row.add_child(_seed_line_edit)

	var random_button := Button.new()
	random_button.text = Localization.t("UI_WORLD_CREATE_RANDOM_BUTTON")
	random_button.custom_minimum_size = Vector2(130, 38)
	_apply_secondary_button_style(random_button)
	random_button.pressed.connect(_on_random_seed_pressed)
	seed_row.add_child(random_button)

	var info_box := PanelContainer.new()
	info_box.add_theme_stylebox_override("panel", _make_section_stylebox())
	content.add_child(info_box)

	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 14)
	info_margin.add_theme_constant_override("margin_top", 12)
	info_margin.add_theme_constant_override("margin_right", 14)
	info_margin.add_theme_constant_override("margin_bottom", 12)
	info_box.add_child(info_margin)

	var info_text := Label.new()
	info_text.text = "READY FOR INITIAL DEPLOYMENT. ALL SYSTEMS NOMINAL. SELECT TARGET PARAMETERS TO BEGIN SURFACE MAPPING."
	info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_text.add_theme_font_size_override("font_size", 11)
	info_text.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	info_margin.add_child(info_text)

func _build_geology_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var sector_label := _make_title_label(Localization.t("UI_NEW_GAME_SECTOR_LABEL") % Localization.t("UI_NEW_GAME_GEOLOGY_TITLE"))
	content.add_child(sector_label)

	var primary_section := VBoxContainer.new()
	primary_section.add_theme_constant_override("separation", 4)
	content.add_child(primary_section)
	for spec: Dictionary in PRIMARY_SLIDER_SPECS:
		primary_section.add_child(_build_slider_row(spec))

	var advanced_header := HBoxContainer.new()
	advanced_header.add_theme_constant_override("separation", 10)
	content.add_child(advanced_header)

	var advanced_line := ColorRect.new()
	advanced_line.size_flags_horizontal = SIZE_EXPAND_FILL
	advanced_line.custom_minimum_size.y = 1
	advanced_line.color = Color(1, 1, 1, 0.1)
	advanced_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	advanced_header.add_child(advanced_line)

	_advanced_toggle = Button.new()
	_advanced_toggle.toggle_mode = true
	_advanced_toggle.flat = true
	_advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_advanced_toggle.text = Localization.t("UI_WORLDGEN_MOUNTAINS_ADVANCED_TOGGLE")
	_apply_text_button_style(_advanced_toggle)
	_advanced_toggle.toggled.connect(_on_advanced_toggled)
	advanced_header.add_child(_advanced_toggle)

	_advanced_container = VBoxContainer.new()
	_advanced_container.visible = false
	_advanced_container.add_theme_constant_override("separation", 4)
	content.add_child(_advanced_container)
	for spec: Dictionary in ADVANCED_SLIDER_SPECS:
		_advanced_container.add_child(_build_slider_row(spec))

func _make_title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	return label

func _apply_tabs_style(tabs: TabContainer) -> void:
	tabs.add_theme_stylebox_override("panel", _make_stylebox(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	tabs.add_theme_stylebox_override("tab_unselected", _make_tab_stylebox(Color(1, 1, 1, 0.05), false))
	tabs.add_theme_stylebox_override("tab_selected", _make_tab_stylebox(ACCENT_COLOR, true))
	tabs.add_theme_stylebox_override("tab_hovered", _make_tab_stylebox(Color(1, 1, 1, 0.1), false))
	tabs.add_theme_color_override("font_selected_color", BUTTON_TEXT_DARK)
	tabs.add_theme_color_override("font_unselected_color", TEXT_SECONDARY_COLOR)
	tabs.add_theme_font_size_override("font_size", 11)

func _make_tab_stylebox(color: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color if selected else Color(0.1, 0.1, 0.1, 0.4)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	if selected:
		style.border_width_bottom = 0
	return style

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
		_schedule_preview_rebuild()
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

func _setup_button_juice(button: Button) -> void:
	button.pivot_offset = button.custom_minimum_size / 2.0
	if not button.mouse_entered.is_connected(_on_button_hover):
		button.mouse_entered.connect(_on_button_hover.bind(button))
	if not button.mouse_exited.is_connected(_on_button_unhover):
		button.mouse_exited.connect(_on_button_unhover.bind(button))

	button.button_down.connect(func() -> void:
		var tween := create_tween()
		tween.tween_property(button, "scale", Vector2(0.95, 0.95), 0.05)
	)
	button.button_up.connect(func() -> void:
		var tween := create_tween()
		tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.1)
	)

func _on_button_hover(button: Button) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if button.material is ShaderMaterial:
		tween.tween_method(func(v: float) -> void:
			button.material.set_shader_parameter("intensity", v), 0.1, 0.22, 0.2)

func _on_button_unhover(button: Button) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)
	if button.material is ShaderMaterial:
		tween.tween_method(func(v: float) -> void:
			button.material.set_shader_parameter("intensity", v), 0.22, 0.1, 0.2)

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
	_setup_button_juice(button)

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
	_setup_button_juice(button)

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

func _on_seed_text_changed(_new_text: String) -> void:
	_schedule_preview_rebuild()

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
		return _preview_seed_value
	var raw_value: String = _seed_line_edit.text.strip_edges()
	if raw_value.is_empty():
		var generated_seed: int = _generate_seed_value()
		_preview_seed_value = generated_seed
		_seed_line_edit.text = str(generated_seed)
		return generated_seed
	_preview_seed_value = _coerce_seed_text(raw_value)
	return _preview_seed_value

func _resolve_preview_seed_value() -> int:
	if _seed_line_edit == null:
		return _preview_seed_value
	var raw_value: String = _seed_line_edit.text.strip_edges()
	if raw_value.is_empty():
		return _preview_seed_value
	_preview_seed_value = _coerce_seed_text(raw_value)
	return _preview_seed_value

func _coerce_seed_text(raw_value: String) -> int:
	if raw_value.is_valid_int():
		return int(raw_value)
	return _hash_seed_text(raw_value)

func _regenerate_seed_text() -> void:
	if _seed_line_edit == null:
		return
	_preview_seed_value = _generate_seed_value()
	_seed_line_edit.text = str(_preview_seed_value)
	_schedule_preview_rebuild()

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
	# Find current tab if possible, or default to 0
	_rebuild_ui(current_seed_text, 0)
	_schedule_preview_rebuild()

func _schedule_preview_rebuild() -> void:
	_preview_controller.queue_preview_rebuild(
		_resolve_preview_seed_value(),
		MountainGenSettings.from_save_dict(_settings.to_save_dict())
	)
