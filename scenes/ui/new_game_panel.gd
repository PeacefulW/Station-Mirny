class_name NewGamePanel
extends Control

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldPreviewCanvas = preload("res://scenes/ui/world_preview_canvas.gd")
const WorldPreviewController = preload("res://core/systems/world/world_preview_controller.gd")
const WorldPreviewRenderMode = preload("res://core/systems/world/world_preview_render_mode.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")

const DEFAULT_SETTINGS_PATH: String = "res://data/balance/mountain_gen_settings.tres"
const DEFAULT_FOUNDATION_SETTINGS_PATH: String = "res://data/balance/foundation_gen_settings.tres"
const BACKDROP_IMAGE_PATH: String = "res://assets/ui/backgrounds/mountain_worldgen_backdrop.jpg"
const PANEL_WIDTH: int = 960
const SURFACE_COLOR: Color = Color(0.05, 0.06, 0.07, 0.94)
const SURFACE_BORDER_COLOR: Color = Color(0.83, 0.66, 0.42, 0.25)
const SURFACE_ALT_COLOR: Color = Color(0.08, 0.09, 0.11, 0.96)
const SURFACE_MUTED_COLOR: Color = Color(0.07, 0.08, 0.09, 0.90)
const ACCENT_COLOR: Color = Color(0.92, 0.73, 0.43, 1.0)
const ACCENT_HOVER_COLOR: Color = Color(1.0, 0.85, 0.65, 1.0)
const TEXT_PRIMARY_COLOR: Color = Color(0.95, 0.95, 0.93, 1.0)
const TEXT_SECONDARY_COLOR: Color = Color(0.60, 0.62, 0.65, 1.0)
const BACKDROP_COLOR: Color = Color(0.02, 0.02, 0.03, 0.65)
const BUTTON_TEXT_DARK: Color = Color(0.1, 0.08, 0.05, 1.0)
const FRAME_COLOR: Color = Color(0.15, 0.12, 0.08, 0.45)
const HELP_BUTTON_COLOR: Color = Color(0.15, 0.15, 0.16, 0.94)
const HELP_BUTTON_HOVER_COLOR: Color = Color(0.20, 0.18, 0.15, 0.98)

const BACKDROP_SHADER_CODE: String = """
shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 3.0) = 0.8;
uniform vec4 tint : source_color = vec4(0.06, 0.05, 0.04, 0.15);
uniform float scanline_count : hint_range(0.0, 1080.0) = 480.0;
uniform float scanline_speed : hint_range(0.0, 5.0) = 0.8;
uniform float sweep_speed : hint_range(0.0, 2.0) = 0.3;

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE * blur_strength;
	vec4 color = texture(TEXTURE, UV) * 0.4;
	color += texture(TEXTURE, UV + vec2(texel.x, 0.0)) * 0.15;
	color += texture(TEXTURE, UV - vec2(texel.x, 0.0)) * 0.15;
	color += texture(TEXTURE, UV + vec2(0.0, texel.y)) * 0.15;
	color += texture(TEXTURE, UV - vec2(0.0, texel.y)) * 0.15;
	
	float scanline = sin(UV.y * scanline_count + TIME * scanline_speed) * 0.03 + 0.97;
	color.rgb *= scanline;
	
	float sweep = mod(UV.y - TIME * sweep_speed, 1.0);
	sweep = smoothstep(0.96, 1.0, sweep) * 0.06;
	color.rgb += vec3(sweep);
	
	COLOR = mix(color, tint, tint.a);
}
"""

const RADAR_GRID_SHADER_CODE: String = """
shader_type canvas_item;

uniform vec4 grid_color : source_color = vec4(0.92, 0.73, 0.43, 0.04);
uniform float cell_count : hint_range(1.0, 100.0) = 20.0;
uniform float line_width : hint_range(0.001, 0.1) = 0.015;

void fragment() {
	vec2 grid = fract(UV * cell_count);
	float line = step(1.0 - line_width, grid.x) + step(1.0 - line_width, grid.y);
	COLOR = vec4(grid_color.rgb, clamp(line, 0.0, 1.0) * grid_color.a);
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

const FOUNDATION_SLIDER_SPECS: Array[Dictionary] = [
	{
		"target": "foundation",
		"property": "ocean_band_tiles",
		"label_key": "UI_WORLDGEN_FOUNDATION_OCEAN_BAND",
		"tooltip_key": "UI_WORLDGEN_FOUNDATION_OCEAN_BAND_DESC",
		"min": 64.0,
		"max": 1024.0,
		"step": 1.0,
		"is_integer": true,
		"decimals": 0,
	},
	{
		"target": "foundation",
		"property": "burning_band_tiles",
		"label_key": "UI_WORLDGEN_FOUNDATION_BURNING_BAND",
		"tooltip_key": "UI_WORLDGEN_FOUNDATION_BURNING_BAND_DESC",
		"min": 64.0,
		"max": 1024.0,
		"step": 1.0,
		"is_integer": true,
		"decimals": 0,
	},
]

signal back_requested
signal start_requested(
	seed_value: int,
	settings: MountainGenSettings,
	world_bounds: WorldBoundsSettings,
	foundation_settings: FoundationGenSettings
)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
var _world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
var _foundation_settings: FoundationGenSettings = FoundationGenSettings.hard_coded_defaults()
var _seed_line_edit: LineEdit = null
var _size_preset_select: OptionButton = null
var _advanced_toggle: Button = null
var _advanced_container: VBoxContainer = null
var _preview_canvas: WorldPreviewCanvas = null
var _preview_mode_select: OptionButton = null
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
	_world_bounds = WorldBoundsSettings.hard_coded_defaults()
	_foundation_settings = _load_default_foundation_settings(_world_bounds)
	_rebuild_ui("", 0)
	_regenerate_seed_text()

func _rebuild_ui(seed_text: String, tab_index: int = 0) -> void:
	_preview_canvas = null
	_preview_controller.attach_canvas(null)
	for child: Node in get_children():
		child.queue_free()
	_seed_line_edit = null
	_size_preset_select = null
	_advanced_toggle = null
	_advanced_container = null
	_preview_mode_select = null
	_build_ui(seed_text, tab_index)

func _build_ui(seed_text: String, active_tab: int) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	modulate.a = 0.0
	var entrance_tween := create_tween()
	entrance_tween.tween_property(self, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)

	# 1. Background
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

	# 2. Main Panel
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _make_surface_stylebox())
	center.add_child(panel)

	var panel_layout := VBoxContainer.new()
	panel_layout.add_theme_constant_override("separation", 0)
	panel.add_child(panel_layout)

	# Header
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 24)
	header_margin.add_theme_constant_override("margin_top", 20)
	header_margin.add_theme_constant_override("margin_right", 24)
	header_margin.add_theme_constant_override("margin_bottom", 16)
	panel_layout.add_child(header_margin)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header_margin.add_child(header)

	var title := Label.new()
	title.text = Localization.t("UI_WORLDGEN_MOUNTAINS_PANEL_TITLE")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.text = Localization.t("UI_WORLDGEN_MOUNTAINS_PANEL_SUBTITLE")
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", ACCENT_COLOR)
	header.add_child(subtitle)

	# 3. Horizontal Content Area
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 24)
	panel_layout.add_child(content_hbox)

	# LEFT COLUMN: Tabs / Settings
	var left_column := MarginContainer.new()
	left_column.size_flags_horizontal = SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("margin_left", 24)
	content_hbox.add_child(left_column)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	tabs.current_tab = active_tab
	_apply_tabs_style(tabs)
	left_column.add_child(tabs)

	_build_comms_tab(tabs, seed_text)
	_build_geology_tab(tabs)
	
	tabs.set_tab_title(0, Localization.t("UI_NEW_GAME_TAB_COMMS"))
	tabs.set_tab_title(1, Localization.t("UI_NEW_GAME_TAB_GEOLOGY"))

	# RIGHT COLUMN: Preview
	var right_column := MarginContainer.new()
	right_column.custom_minimum_size = Vector2(400, 0)
	right_column.add_theme_constant_override("margin_right", 24)
	right_column.add_theme_constant_override("margin_bottom", 20)
	content_hbox.add_child(right_column)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.add_theme_constant_override("separation", 8)
	right_column.add_child(preview_vbox)

	var preview_label := _make_title_label(Localization.t("UI_WORLDGEN_PREVIEW_TITLE"))
	preview_vbox.add_child(preview_label)

	var preview_toolbar := HBoxContainer.new()
	preview_toolbar.add_theme_constant_override("separation", 8)
	preview_vbox.add_child(preview_toolbar)

	var preview_mode_label := Label.new()
	preview_mode_label.text = Localization.t("UI_WORLDGEN_PREVIEW_MODE_LABEL")
	preview_mode_label.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	preview_mode_label.add_theme_font_size_override("font_size", 11)
	preview_toolbar.add_child(preview_mode_label)

	_preview_mode_select = OptionButton.new()
	_preview_mode_select.custom_minimum_size = Vector2(200, 34)
	_apply_secondary_button_style(_preview_mode_select)
	_populate_preview_mode_options()
	_preview_mode_select.item_selected.connect(_on_preview_mode_selected)
	preview_toolbar.add_child(_preview_mode_select)

	var preview_toolbar_spacer := Control.new()
	preview_toolbar_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_toolbar.add_child(preview_toolbar_spacer)

	var preview_reset_button := Button.new()
	preview_reset_button.text = Localization.t("UI_WORLDGEN_PREVIEW_RESET_VIEW")
	preview_reset_button.custom_minimum_size = Vector2(116, 34)
	_apply_secondary_button_style(preview_reset_button)
	preview_reset_button.pressed.connect(func() -> void:
		if _preview_canvas != null:
			_preview_canvas.reset_view()
	)
	preview_toolbar.add_child(preview_reset_button)

	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size = Vector2(400, 400)
	preview_frame.add_theme_stylebox_override("panel", _make_section_stylebox())
	preview_frame.tooltip_text = Localization.t("UI_WORLDGEN_PREVIEW_CONTROLS_HINT")
	preview_vbox.add_child(preview_frame)

	_preview_canvas = WorldPreviewCanvas.new()
	_preview_canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	_preview_canvas.size_flags_vertical = SIZE_EXPAND_FILL
	_preview_canvas.tooltip_text = Localization.t("UI_WORLDGEN_PREVIEW_CONTROLS_HINT")
	preview_frame.add_child(_preview_canvas)
	_preview_controller.attach_canvas(_preview_canvas)
	
	# Preview Brackets
	var brackets := Control.new()
	brackets.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	brackets.mouse_filter = MOUSE_FILTER_IGNORE
	preview_frame.add_child(brackets)
	_add_brackets(brackets)

	# Footer
	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 24)
	footer_margin.add_theme_constant_override("margin_top", 16)
	footer_margin.add_theme_constant_override("margin_right", 24)
	footer_margin.add_theme_constant_override("margin_bottom", 24)
	panel_layout.add_child(footer_margin)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 16)
	footer_margin.add_child(footer)

	var back_button := Button.new()
	back_button.text = Localization.t("UI_MAIN_LOAD_BACK")
	back_button.custom_minimum_size = Vector2(120, 40)
	_apply_secondary_button_style(back_button)
	back_button.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back_button)

	var start_button := Button.new()
	start_button.text = Localization.t("UI_WORLDGEN_MOUNTAINS_START_BUTTON")
	start_button.custom_minimum_size = Vector2(240, 40)
	_apply_primary_button_style(start_button)
	start_button.pressed.connect(_on_start_pressed)
	footer.add_child(start_button)

func _add_brackets(parent: Control) -> void:
	var color := ACCENT_COLOR
	color.a = 0.5
	for i in range(4):
		var bracket := Label.new()
		bracket.text = "+"
		bracket.add_theme_color_override("font_color", color)
		bracket.add_theme_font_size_override("font_size", 14)
		match i:
			0: bracket.set_anchors_and_offsets_preset(PRESET_TOP_LEFT, PRESET_MODE_MINSIZE, 8)
			1: bracket.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_MINSIZE, 8)
			2: bracket.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT, PRESET_MODE_MINSIZE, 8)
			3: bracket.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT, PRESET_MODE_MINSIZE, 8)
		parent.add_child(bracket)

func _build_comms_tab(tabs: TabContainer, seed_text: String) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
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
	seed_row.add_theme_constant_override("separation", 12)
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
	random_button.custom_minimum_size = Vector2(100, 38)
	_apply_secondary_button_style(random_button)
	random_button.pressed.connect(_on_random_seed_pressed)
	seed_row.add_child(random_button)

	var size_section := VBoxContainer.new()
	size_section.add_theme_constant_override("separation", 8)
	content.add_child(size_section)

	var size_label := Label.new()
	size_label.text = Localization.t("UI_WORLDGEN_SIZE_LABEL")
	size_label.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	size_label.add_theme_font_size_override("font_size", 13)
	size_section.add_child(size_label)

	_size_preset_select = OptionButton.new()
	_size_preset_select.custom_minimum_size = Vector2(220, 38)
	_apply_secondary_button_style(_size_preset_select)
	for index: int in range(WorldBoundsSettings.preset_ids().size()):
		var preset: StringName = WorldBoundsSettings.preset_ids()[index]
		_size_preset_select.add_item(Localization.t(WorldBoundsSettings.preset_label_key(preset)), index)
		if preset == _world_bounds.preset_id:
			_size_preset_select.selected = index
	_size_preset_select.item_selected.connect(_on_size_preset_selected)
	size_section.add_child(_size_preset_select)

func _build_geology_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	var sector_label := _make_title_label(Localization.t("UI_NEW_GAME_SECTOR_LABEL") % Localization.t("UI_NEW_GAME_GEOLOGY_TITLE"))
	content.add_child(sector_label)

	var foundation_section := VBoxContainer.new()
	foundation_section.add_theme_constant_override("separation", 6)
	content.add_child(foundation_section)
	for spec: Dictionary in FOUNDATION_SLIDER_SPECS:
		foundation_section.add_child(_build_slider_row(spec))

	var primary_section := VBoxContainer.new()
	primary_section.add_theme_constant_override("separation", 6)
	content.add_child(primary_section)
	for spec: Dictionary in PRIMARY_SLIDER_SPECS:
		primary_section.add_child(_build_slider_row(spec))

	var advanced_header := HBoxContainer.new()
	advanced_header.add_theme_constant_override("separation", 12)
	content.add_child(advanced_header)

	var advanced_line := ColorRect.new()
	advanced_line.size_flags_horizontal = SIZE_EXPAND_FILL
	advanced_line.custom_minimum_size.y = 1
	advanced_line.color = Color(1, 1, 1, 0.08)
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
	_advanced_container.add_theme_constant_override("separation", 6)
	content.add_child(_advanced_container)
	for spec: Dictionary in ADVANCED_SLIDER_SPECS:
		_advanced_container.add_child(_build_slider_row(spec))

func _make_title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	label.uppercase = true
	return label

func _apply_tabs_style(tabs: TabContainer) -> void:
	tabs.add_theme_stylebox_override("panel", _make_stylebox(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	tabs.add_theme_stylebox_override("tab_unselected", _make_tab_stylebox(Color(1, 1, 1, 0.03), false))
	tabs.add_theme_stylebox_override("tab_selected", _make_tab_stylebox(ACCENT_COLOR, true))
	tabs.add_theme_stylebox_override("tab_hovered", _make_tab_stylebox(Color(1, 1, 1, 0.08), false))
	tabs.add_theme_color_override("font_selected_color", BUTTON_TEXT_DARK)
	tabs.add_theme_color_override("font_unselected_color", TEXT_SECONDARY_COLOR)
	tabs.add_theme_font_size_override("font_size", 11)

func _make_tab_stylebox(color: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.set_corner_radius_all(2)
	return style

func _build_slider_row(spec: Dictionary) -> Control:
	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_top", 4)
	row_margin.add_theme_constant_override("margin_bottom", 4)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	row_margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
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
	value_label.custom_minimum_size = Vector2(60, 0)
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
	column.add_child(slider)

	slider.value_changed.connect(func(new_value: float) -> void:
		_apply_setting_value(spec, new_value)
		var resolved_value: float = _read_setting_value(spec)
		if not is_equal_approx(slider.value, resolved_value):
			slider.set_value_no_signal(resolved_value)
		_update_value_label(value_label, spec, resolved_value)
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
	var style := _make_stylebox(SURFACE_COLOR, Color.TRANSPARENT, 0, 12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 24
	return style

func _make_section_stylebox() -> StyleBoxFlat:
	var style := _make_stylebox(SURFACE_ALT_COLOR, SURFACE_BORDER_COLOR, 1, 4)
	return style

func _make_button_stylebox(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _make_stylebox(fill, border, 1, 4)
	return style

func _make_stylebox(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style

func _setup_button_juice(button: Button, is_primary: bool = false) -> void:
	button.pivot_offset = button.custom_minimum_size / 2.0
	button.mouse_entered.connect(_on_button_hover.bind(button, is_primary))
	button.mouse_exited.connect(_on_button_unhover.bind(button, is_primary))
	
	button.button_down.connect(func() -> void:
		button.scale = Vector2(0.96, 0.96)
	)
	button.button_up.connect(func() -> void:
		button.scale = Vector2(1.04, 1.04)
	)

func _on_button_hover(button: Button, is_primary: bool) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2(1.04, 1.04), 0.15).set_trans(Tween.TRANS_SINE)
	if is_primary:
		tween.tween_property(button, "theme_override_styles/normal:bg_color", ACCENT_HOVER_COLOR, 0.15)

func _on_button_unhover(button: Button, is_primary: bool) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)
	if is_primary:
		tween.tween_property(button, "theme_override_styles/normal:bg_color", ACCENT_COLOR, 0.15)

func _apply_primary_button_style(button: Button) -> void:
	var style := _make_button_stylebox(ACCENT_COLOR, Color.TRANSPARENT)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", _make_button_stylebox(ACCENT_HOVER_COLOR, Color.TRANSPARENT))
	button.add_theme_stylebox_override("pressed", _make_button_stylebox(ACCENT_COLOR, Color.BLACK))
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", BUTTON_TEXT_DARK)
	button.add_theme_color_override("font_hover_color", BUTTON_TEXT_DARK)
	button.add_theme_color_override("font_pressed_color", BUTTON_TEXT_DARK)
	_setup_button_juice(button, true)

func _apply_secondary_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_button_stylebox(Color(1,1,1,0.05), SURFACE_BORDER_COLOR))
	button.add_theme_stylebox_override("hover", _make_button_stylebox(Color(1,1,1,0.1), ACCENT_COLOR))
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)
	_setup_button_juice(button, false)

func _apply_text_button_style(button: Button) -> void:
	button.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)
	button.add_theme_color_override("font_hover_color", ACCENT_COLOR)

func _apply_help_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _make_stylebox(HELP_BUTTON_COLOR, Color.TRANSPARENT, 0, 9))
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", TEXT_SECONDARY_COLOR)

func _apply_input_style(line_edit: LineEdit) -> void:
	var style := _make_stylebox(SURFACE_MUTED_COLOR, SURFACE_BORDER_COLOR, 1, 4)
	line_edit.add_theme_stylebox_override("normal", style)
	line_edit.add_theme_stylebox_override("focus", _make_stylebox(SURFACE_MUTED_COLOR, ACCENT_COLOR, 1, 4))
	line_edit.add_theme_color_override("font_color", TEXT_PRIMARY_COLOR)

func _format_advanced_toggle_text(is_pressed: bool) -> String:
	return Localization.t("UI_WORLDGEN_MOUNTAINS_ADVANCED_TOGGLE")

func _read_setting_value(spec: Dictionary) -> float:
	var property_name: StringName = StringName(str(spec.get("property", "")))
	if str(spec.get("target", "")) == "foundation":
		return float(_foundation_settings.get(property_name))
	return float(_settings.get(property_name))

func _apply_setting_value(spec: Dictionary, value: float) -> void:
	var property_name: StringName = StringName(str(spec.get("property", "")))
	var target: Object = _foundation_settings if str(spec.get("target", "")) == "foundation" else _settings
	if bool(spec.get("is_integer", false)):
		target.set(property_name, int(round(value)))
	else:
		target.set(property_name, value)
	if str(spec.get("target", "")) == "foundation":
		_foundation_settings = _foundation_settings.normalized_for_bounds(_world_bounds)

func _update_value_label(label: Label, spec: Dictionary, value: float) -> void:
	var decimals: int = int(spec.get("decimals", 0))
	if bool(spec.get("is_integer", false)):
		label.text = str(int(round(value)))
	else:
		label.text = ("%0." + str(decimals) + "f") % value

func _on_random_seed_pressed() -> void:
	_regenerate_seed_text()

func _on_seed_text_changed(_new_text: String) -> void:
	_schedule_preview_rebuild()

func _on_advanced_toggled(is_pressed: bool) -> void:
	if _advanced_container: _advanced_container.visible = is_pressed

func _on_start_pressed() -> void:
	start_requested.emit(
		_resolve_seed_value(),
		MountainGenSettings.from_save_dict(_settings.to_save_dict()),
		WorldBoundsSettings.from_save_dict(_world_bounds.to_save_dict()),
		FoundationGenSettings.from_save_dict(_foundation_settings.to_save_dict(), _world_bounds)
	)

func _on_size_preset_selected(index: int) -> void:
	var presets: Array[StringName] = WorldBoundsSettings.preset_ids()
	if index < 0 or index >= presets.size():
		return
	_world_bounds = WorldBoundsSettings.for_preset(presets[index])
	_foundation_settings = FoundationGenSettings.for_bounds(_world_bounds)
	_rebuild_ui(_seed_line_edit.text if _seed_line_edit else "", 0)
	_schedule_preview_rebuild()

func _resolve_seed_value() -> int:
	if _seed_line_edit == null: return _preview_seed_value
	var raw_value: String = _seed_line_edit.text.strip_edges()
	if raw_value.is_empty():
		_preview_seed_value = _generate_seed_value()
		_seed_line_edit.text = str(_preview_seed_value)
	else:
		_preview_seed_value = _coerce_seed_text(raw_value)
	return _preview_seed_value

func _resolve_preview_seed_value() -> int:
	if _seed_line_edit == null: return _preview_seed_value
	var raw_value: String = _seed_line_edit.text.strip_edges()
	if !raw_value.is_empty():
		_preview_seed_value = _coerce_seed_text(raw_value)
	return _preview_seed_value

func _coerce_seed_text(raw_value: String) -> int:
	if raw_value.is_valid_int(): return int(raw_value)
	return _hash_seed_text(raw_value)

func _regenerate_seed_text() -> void:
	if _seed_line_edit:
		_preview_seed_value = _generate_seed_value()
		_seed_line_edit.text = str(_preview_seed_value)
		_schedule_preview_rebuild()

func _generate_seed_value() -> int:
	return int(_rng.randi() & 0x7FFFFFFF)

func _hash_seed_text(text: String) -> int:
	var hashing_context: HashingContext = HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA1)
	hashing_context.update(text.to_utf8_buffer())
	var digest: PackedByteArray = hashing_context.finish()
	var hashed_value: int = 0
	for i: int in range(mini(4, digest.size())):
		hashed_value = (hashed_value << 8) | int(digest[i])
	return hashed_value & 0x7FFFFFFF

func _load_default_settings() -> MountainGenSettings:
	var resource: MountainGenSettings = ResourceLoader.load(DEFAULT_SETTINGS_PATH, "MountainGenSettings") as MountainGenSettings
	return MountainGenSettings.from_save_dict(resource.to_save_dict()) if resource else MountainGenSettings.hard_coded_defaults()

func _load_default_foundation_settings(world_bounds: WorldBoundsSettings) -> FoundationGenSettings:
	var resource: FoundationGenSettings = ResourceLoader.load(
		DEFAULT_FOUNDATION_SETTINGS_PATH,
		"FoundationGenSettings"
	) as FoundationGenSettings
	return FoundationGenSettings.from_save_dict(resource.to_save_dict(), world_bounds) \
		if resource \
		else FoundationGenSettings.for_bounds(world_bounds)

func _load_backdrop_texture() -> Texture2D:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(BACKDROP_IMAGE_PATH))
	return ImageTexture.create_from_image(image) if image && !image.is_empty() else null

func _on_language_changed(_locale: String) -> void:
	var current_seed_text: String = _seed_line_edit.text if _seed_line_edit else ""
	_rebuild_ui(current_seed_text, 0)
	_schedule_preview_rebuild()

func _schedule_preview_rebuild() -> void:
	_preview_controller.queue_preview_rebuild(
		_resolve_preview_seed_value(),
		MountainGenSettings.from_save_dict(_settings.to_save_dict()),
		WorldBoundsSettings.from_save_dict(_world_bounds.to_save_dict()),
		FoundationGenSettings.from_save_dict(_foundation_settings.to_save_dict(), _world_bounds)
	)

func _populate_preview_mode_options() -> void:
	if _preview_mode_select == null:
		return
	_preview_mode_select.clear()
	var current_mode: StringName = _preview_controller.get_render_mode()
	var available_modes: Array[StringName] = WorldPreviewRenderMode.all_modes()
	for index: int in range(available_modes.size()):
		var mode: StringName = available_modes[index]
		_preview_mode_select.add_item(
			Localization.t(WorldPreviewRenderMode.get_label_key(mode)),
			index
		)
		_preview_mode_select.set_item_metadata(index, mode)
		if mode == current_mode:
			_preview_mode_select.select(index)

func _on_preview_mode_selected(index: int) -> void:
	if _preview_mode_select == null:
		return
	var selected_mode: StringName = _preview_mode_select.get_item_metadata(index) as StringName
	_preview_controller.set_render_mode(selected_mode)
