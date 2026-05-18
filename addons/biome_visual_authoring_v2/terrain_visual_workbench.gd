@tool
extends Control

const TerrainVisualPacketMaterialBuilder = preload(
	"res://data/terrain_visual/terrain_visual_packet_material.gd"
)
const TerrainVisualRecipePayload = preload(
	"res://data/terrain_visual/terrain_visual_recipe_payload.gd"
)
const DEFAULT_RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"
const DEFAULT_RECIPE: Resource = preload(DEFAULT_RECIPE_PATH)

const SOLID_VALUE := 1
const EMPTY_VALUE := 0
const DEFAULT_MASK_SIZE := Vector2i(8, 8)
const DEFAULT_EXPORT_PATH := "user://terrain_visual_v2_reference.png"
const CONTROL_PANEL_WIDTH := 360.0
const CONTROL_PANEL_MIN_VISIBLE_WIDTH := 720.0
const PREVIEW_PADDING := 24.0
const PREVIEW_MAX_SCALE := 1.0
const PREVIEW_BACKGROUND_COLOR := Color(0.34, 0.20, 0.09, 1.0)

var _recipe: Resource = null
var _solid_mask := PackedByteArray()
var _mask_size := Vector2i.ZERO
var _solver: Object = null
var _last_packet: Dictionary = { }
var _last_debug_counters: Dictionary = { }
var _last_validation_errors := PackedStringArray()
var _refresh_count := 0
var _debug_mode := 6
var _is_bulk_mask_edit := false
var _recipe_save_path := DEFAULT_RECIPE_PATH
var _current_mask_preset_id := &""
var _localized_text_controls: Array[Dictionary] = []
var _save_status_key := &"UI_TERRAIN_VISUAL_SAVE_HINT"
var _save_status_args := { }

var _layout_root: HBoxContainer = null
var _preview_stage: Control = null
var _preview_background: ColorRect = null
var _preview_quad: ColorRect = null
var _control_panel: PanelContainer = null
var _mask_grid: GridContainer = null
var _mask_buttons: Array[Button] = []
var _shape_sliders: Dictionary = { }
var _material_color_pickers: Dictionary = { }
var _debug_mode_select: OptionButton = null
var _mask_preset_select: OptionButton = null
var _mask_preset_option_ids: Array[StringName] = []
var _save_status_label: Label = null


func _ready() -> void:
	_ensure_ui()
	if _mask_size == Vector2i.ZERO:
		apply_mask_preset(&"cave_cut_5x4")
	if _recipe == null:
		set_recipe(DEFAULT_RECIPE.duplicate(true))


func _exit_tree() -> void:
	_disconnect_recipe_changed()
	if _solver != null and is_instance_valid(_solver):
		_solver.free()
	_solver = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_layout_visibility()
		call_deferred("_layout_preview_quad")
	elif what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh_localized_texts()


func set_recipe(recipe: Resource) -> void:
	_disconnect_recipe_changed()
	_recipe = recipe
	if _recipe != null and not _recipe.resource_path.is_empty():
		_recipe_save_path = _recipe.resource_path
	_normalize_recipe_runtime_limits()
	_connect_recipe_changed()
	_update_ui_from_recipe()
	if _is_mask_ready():
		_refresh_preview()


func get_recipe() -> Resource:
	return _recipe


func get_recipe_save_path() -> String:
	return _recipe_save_path


func set_mask_size(mask_size: Vector2i) -> void:
	_mask_size = Vector2i(maxi(1, mask_size.x), maxi(1, mask_size.y))
	_solid_mask.resize(_mask_size.x * _mask_size.y)
	_solid_mask.fill(EMPTY_VALUE)
	_rebuild_mask_grid()
	if _recipe != null:
		_refresh_preview()


func get_mask_size() -> Vector2i:
	return _mask_size


func set_mask_cell(cell: Vector2i, is_solid: bool) -> void:
	if not _is_cell_inside_mask(cell):
		push_warning("TerrainVisualWorkbenchV2 ignored mask edit outside preview bounds.")
		return
	var index := _mask_index(cell)
	_solid_mask[index] = SOLID_VALUE if is_solid else EMPTY_VALUE
	if index < _mask_buttons.size():
		_mask_buttons[index].set_pressed_no_signal(is_solid)
	if not _is_bulk_mask_edit:
		_refresh_preview()


func get_mask_cell(cell: Vector2i) -> bool:
	if not _is_cell_inside_mask(cell):
		return false
	return _solid_mask[_mask_index(cell)] == SOLID_VALUE


func fill_mask(is_solid: bool) -> void:
	_is_bulk_mask_edit = true
	_solid_mask.fill(SOLID_VALUE if is_solid else EMPTY_VALUE)
	_sync_mask_buttons()
	_is_bulk_mask_edit = false
	_refresh_preview()


func set_shape_control(field_name: StringName, value: float) -> void:
	if _recipe == null:
		return
	if field_name in [&"tile_size_px", &"runtime_tile_size_px"]:
		_normalize_recipe_runtime_limits()
		_refresh_preview()
		return
	var resolved_value: Variant = value
	if field_name == &"variant_count":
		resolved_value = maxi(0, roundi(value))
		resolved_value = maxi(1, int(resolved_value))
	elif field_name == &"shape_supersampling":
		resolved_value = clampi(
			roundi(value),
			1,
			TerrainVisualRecipePayload.MAX_RUNTIME_SHAPE_SUPERSAMPLING,
		)
	_recipe.set(field_name, resolved_value)
	_update_slider_value(field_name, float(resolved_value))
	_refresh_preview()


func set_material_color(slot_id: StringName, color: Color) -> void:
	if _recipe == null or not _recipe.has_method("get_material_slot"):
		return
	var slot: Resource = _recipe.call("get_material_slot", slot_id) as Resource
	if slot == null and slot_id == &"edge":
		slot = _recipe.call("get_material_slot", &"face") as Resource
	if slot == null:
		push_warning("TerrainVisualWorkbenchV2 ignored material color edit for missing slot.")
		return
	slot.set("color_a", color)
	if slot.get("source") == &"flat":
		slot.set("flat_color", color)
	var color_picker: ColorPickerButton = _material_color_pickers.get(slot_id, null)
	if color_picker != null:
		color_picker.color = color
	_refresh_preview()


func set_debug_mode(debug_mode: int) -> void:
	_debug_mode = clampi(debug_mode, 0, 6)
	_sync_debug_mode_select()
	_apply_packet_to_preview()


func get_debug_mode() -> int:
	return _debug_mode


func get_solver_class_name() -> StringName:
	return &"TerrainVisualSolver" if _solver != null and is_instance_valid(_solver) else &""


func get_last_packet() -> Dictionary:
	return _last_packet.duplicate(true)


func get_last_debug_counters() -> Dictionary:
	return _last_debug_counters.duplicate(true)


func get_last_validation_errors() -> PackedStringArray:
	return _last_validation_errors.duplicate()


func get_refresh_count() -> int:
	return _refresh_count


func apply_mask_preset(preset_id: StringName) -> bool:
	var preset := _mask_preset(preset_id)
	if preset.is_empty():
		return false
	_current_mask_preset_id = preset_id
	_mask_size = preset.get("size", DEFAULT_MASK_SIZE)
	_solid_mask = preset.get("mask", PackedByteArray()).duplicate()
	_rebuild_mask_grid()
	_sync_mask_buttons()
	_sync_mask_preset_select()
	if _recipe != null:
		_refresh_preview()
	return true


func capture_reference_image() -> Image:
	if get_viewport() == null or get_viewport().get_texture() == null:
		return null
	return get_viewport().get_texture().get_image()


func export_reference_screenshot(path: String = DEFAULT_EXPORT_PATH) -> bool:
	var image := capture_reference_image()
	if image == null:
		return false
	return image.save_png(path) == OK


func save_current_recipe(path: String = "") -> bool:
	if _recipe == null:
		_set_save_status(&"UI_TERRAIN_VISUAL_SAVE_FAILED", { "path": path })
		return false
	_normalize_recipe_runtime_limits()
	var resolved_path := path if not path.is_empty() else _recipe_save_path
	if resolved_path.is_empty():
		resolved_path = DEFAULT_RECIPE_PATH
	var result := ResourceSaver.save(_recipe, resolved_path)
	if result != OK:
		_set_save_status(&"UI_TERRAIN_VISUAL_SAVE_FAILED", { "path": resolved_path })
		return false
	_recipe_save_path = resolved_path
	_recipe.take_over_path(resolved_path)
	_set_save_status(&"UI_TERRAIN_VISUAL_SAVE_SUCCESS", { "path": resolved_path })
	return true


func _ensure_ui() -> void:
	if _preview_quad != null and is_instance_valid(_preview_quad):
		return

	_layout_root = HBoxContainer.new()
	_layout_root.name = "WorkbenchLayout"
	_layout_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout_root.add_theme_constant_override("separation", 10)
	add_child(_layout_root)

	_preview_stage = Control.new()
	_preview_stage.name = "PreviewStage"
	_preview_stage.clip_contents = true
	_preview_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_stage.resized.connect(_layout_preview_quad)
	_layout_root.add_child(_preview_stage)

	_preview_background = ColorRect.new()
	_preview_background.name = "PreviewBackdrop"
	_preview_background.color = PREVIEW_BACKGROUND_COLOR
	_preview_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_stage.add_child(_preview_background)

	_preview_quad = ColorRect.new()
	_preview_quad.name = "PacketPreview"
	_preview_quad.color = Color.TRANSPARENT
	_preview_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_stage.add_child(_preview_quad)

	_control_panel = PanelContainer.new()
	_control_panel.name = "WorkbenchControls"
	_control_panel.custom_minimum_size = Vector2(CONTROL_PANEL_WIDTH, 0.0)
	_control_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout_root.add_child(_control_panel)

	var scroll := ScrollContainer.new()
	scroll.name = "WorkbenchControlScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_control_panel.add_child(scroll)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(CONTROL_PANEL_WIDTH - 34.0, 0.0)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 6)
	scroll.add_child(controls)

	var debug_section := _add_control_section(
		controls,
		"Debug",
		&"UI_TERRAIN_VISUAL_SECTION_DEBUG",
	)
	_add_debug_mode_select(debug_section)

	var save_button := Button.new()
	save_button.name = "SaveRecipe"
	_set_localized_text(save_button, &"UI_TERRAIN_VISUAL_SAVE_RECIPE")
	save_button.pressed.connect(func() -> void: save_current_recipe())
	debug_section.add_child(save_button)

	var export_button := Button.new()
	export_button.name = "ExportReferenceScreenshot"
	_set_localized_text(export_button, &"UI_TERRAIN_VISUAL_EXPORT_REFERENCE")
	export_button.pressed.connect(func() -> void: export_reference_screenshot())
	debug_section.add_child(export_button)

	_save_status_label = Label.new()
	_save_status_label.name = "SaveStatus"
	_save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_status_label.add_theme_font_size_override("font_size", 11)
	_save_status_label.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60))
	debug_section.add_child(_save_status_label)
	_refresh_save_status()

	var mask_section := _add_control_section(
		controls,
		"Mask",
		&"UI_TERRAIN_VISUAL_SECTION_MASK",
	)
	_add_mask_preset_select(mask_section)

	var control_sections := {
		"Mask": mask_section,
		"Shape": _add_control_section(
			controls,
			"Shape",
			&"UI_TERRAIN_VISUAL_SECTION_SHAPE",
		),
		"Facade": _add_control_section(
			controls,
			"Facade",
			&"UI_TERRAIN_VISUAL_SECTION_FACADE",
		),
		"Rim": _add_control_section(
			controls,
			"Rim",
			&"UI_TERRAIN_VISUAL_SECTION_RIM",
		),
		"Normal": _add_control_section(
			controls,
			"Normal",
			&"UI_TERRAIN_VISUAL_SECTION_NORMAL",
		),
	}
	for control_spec: Dictionary in _shape_control_specs():
		var group_name := String(control_spec.get("group", "Shape"))
		_add_shape_slider(
			control_sections.get(group_name, control_sections["Shape"]),
			control_spec.get("field", &""),
			float(control_spec.get("min", 0.0)),
			float(control_spec.get("max", 1.0)),
			float(control_spec.get("step", 0.1)),
		)

	_mask_grid = GridContainer.new()
	_mask_grid.name = "MaskGrid"
	mask_section.add_child(_mask_grid)

	var material_section := _add_control_section(
		controls,
		"Materials",
		&"UI_TERRAIN_VISUAL_SECTION_MATERIALS",
	)
	for slot_id: StringName in [&"top", &"face", &"back", &"base"]:
		_add_material_color_picker(material_section, slot_id)

	_sync_layout_visibility()
	call_deferred("_layout_preview_quad")


func _add_control_section(
		parent: VBoxContainer,
		section_id: String,
		title_key: StringName,
) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = "%sSection" % section_id.replace(" ", "")
	section.add_theme_constant_override("separation", 4)
	parent.add_child(section)

	var label := Label.new()
	label.name = "%sTitle" % section_id.replace(" ", "")
	_set_localized_text(label, title_key)
	label.add_theme_font_size_override("font_size", 13)
	section.add_child(label)
	return section


func _add_shape_slider(
		parent: VBoxContainer,
		field_name: StringName,
		min_value: float,
		max_value: float,
		step: float = 0.1,
) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var label := Label.new()
	label.name = "%sLabel" % str(field_name).capitalize().replace(" ", "")
	_set_localized_text(label, _control_label_key(field_name))
	row.add_child(label)

	var slider := HSlider.new()
	slider.name = str(field_name)
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void: set_shape_control(field_name, value))
	row.add_child(slider)
	_shape_sliders[field_name] = slider


func _add_debug_mode_select(parent: VBoxContainer) -> void:
	_debug_mode_select = OptionButton.new()
	_debug_mode_select.name = "DebugMode"
	_refresh_debug_mode_options()
	_debug_mode_select.item_selected.connect(
		func(index: int) -> void:
			set_debug_mode(_debug_mode_select.get_item_id(index))
	)
	parent.add_child(_debug_mode_select)


func _add_mask_preset_select(parent: VBoxContainer) -> void:
	_mask_preset_select = OptionButton.new()
	_mask_preset_select.name = "MaskPreset"
	_refresh_mask_preset_options()
	_mask_preset_select.item_selected.connect(
		func(index: int) -> void:
			if index >= 0 and index < _mask_preset_option_ids.size():
				apply_mask_preset(_mask_preset_option_ids[index])
	)
	parent.add_child(_mask_preset_select)


func _add_material_color_picker(parent: VBoxContainer, slot_id: StringName) -> void:
	var color_picker := ColorPickerButton.new()
	color_picker.name = "%sMaterialColor" % str(slot_id).capitalize()
	_set_localized_text(color_picker, _material_slot_label_key(slot_id))
	color_picker.color_changed.connect(
		func(color: Color) -> void: set_material_color(slot_id, color),
	)
	parent.add_child(color_picker)
	_material_color_pickers[slot_id] = color_picker


func _rebuild_mask_grid() -> void:
	_ensure_ui()
	if _mask_grid == null:
		return
	for child: Node in _mask_grid.get_children():
		child.queue_free()
	_mask_buttons.clear()
	_mask_grid.columns = _mask_size.x
	for y: int in range(_mask_size.y):
		for x: int in range(_mask_size.x):
			var cell := Vector2i(x, y)
			var button := Button.new()
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(18.0, 18.0)
			button.tooltip_text = _text(
				&"UI_TERRAIN_VISUAL_MASK_CELL_TOOLTIP",
				{ "x": x, "y": y },
			)
			button.toggled.connect(func(is_pressed: bool) -> void: set_mask_cell(cell, is_pressed))
			_mask_grid.add_child(button)
			_mask_buttons.append(button)


func _sync_mask_buttons() -> void:
	for index: int in range(mini(_mask_buttons.size(), _solid_mask.size())):
		_mask_buttons[index].set_pressed_no_signal(_solid_mask[index] == SOLID_VALUE)


func _refresh_preview() -> bool:
	_ensure_ui()
	if not _validate_editor_state():
		return false
	if _solver == null or not is_instance_valid(_solver):
		_solver = ClassDB.instantiate(&"TerrainVisualSolver")
	if _solver == null:
		push_error("TerrainVisualWorkbenchV2 requires TerrainVisualSolver GDExtension.")
		return false

	var packet: Dictionary = _solver.call(
		"build_editor_preview_packet",
		_solid_mask,
		_mask_size.x,
		_mask_size.y,
		_make_recipe_payload(),
		Vector2i.ZERO,
		int(_recipe.get("default_seed")),
	)
	if packet.is_empty():
		push_error("TerrainVisualWorkbenchV2 received an empty TerrainVisualPacket.")
		return false
	_last_packet = packet
	_last_debug_counters = packet.get("debug_counters", { }).duplicate(true)
	_last_debug_counters["solid_tiles"] = _count_solid_tiles()
	_last_debug_counters["mask_size"] = _mask_size
	_refresh_count += 1
	_apply_packet_to_preview()
	return true


func _validate_editor_state() -> bool:
	_last_validation_errors.clear()
	if _recipe == null:
		_last_validation_errors.append("recipe is required")
	if _mask_size.x <= 0 or _mask_size.y <= 0 or _solid_mask.size() != _mask_size.x * _mask_size.y:
		_last_validation_errors.append("mask size does not match mask buffer")
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		_last_validation_errors.append("TerrainVisualSolver native class is missing")
	if _recipe != null and _recipe.has_method("validate"):
		_last_validation_errors.append_array(_recipe.call("validate"))
	if not _last_validation_errors.is_empty():
		push_warning(
			"TerrainVisualWorkbenchV2 validation failed: %s" % "; ".join(_last_validation_errors),
		)
		return false
	return true


func _apply_packet_to_preview() -> void:
	if _preview_quad == null or not is_instance_valid(_preview_quad) or _last_packet.is_empty():
		return
	var material_builder: RefCounted = TerrainVisualPacketMaterialBuilder.new()
	_preview_quad.material = material_builder.build_material(_last_packet, _debug_mode, _recipe)
	_preview_quad.scale = Vector2.ONE
	_preview_quad.size = Vector2(
		float(_last_packet.get("pixel_width", 0)),
		float(_last_packet.get("pixel_height", 0)),
	)
	_layout_preview_quad()


func _layout_preview_quad() -> void:
	if _preview_quad == null or not is_instance_valid(_preview_quad):
		return
	var packet_size := _preview_quad.size
	if packet_size.x <= 0.0 or packet_size.y <= 0.0:
		return
	var stage_size := size
	if _preview_stage != null and is_instance_valid(_preview_stage):
		stage_size = _preview_stage.size
	var available_size := Vector2(
		maxf(1.0, stage_size.x - PREVIEW_PADDING * 2.0),
		maxf(1.0, stage_size.y - PREVIEW_PADDING * 2.0),
	)
	var preview_scale := minf(
		available_size.x / packet_size.x,
		available_size.y / packet_size.y,
	)
	preview_scale = clampf(preview_scale, 0.05, PREVIEW_MAX_SCALE)
	var scaled_size := packet_size * preview_scale
	_preview_quad.scale = Vector2(preview_scale, preview_scale)
	_preview_quad.position = (stage_size - scaled_size) * 0.5


func _sync_layout_visibility() -> void:
	if _control_panel == null:
		return
	_control_panel.visible = size.x >= CONTROL_PANEL_MIN_VISIBLE_WIDTH


func _make_recipe_payload() -> Dictionary:
	return TerrainVisualRecipePayload.make_payload(_recipe)


func _normalize_recipe_runtime_limits() -> void:
	if _recipe == null:
		return
	if _recipe.has_method("normalize_runtime_limits"):
		_recipe.call("normalize_runtime_limits")
		return
	_recipe.set("tile_size_px", TerrainVisualRecipePayload.FIXED_GAME_TILE_SIZE_PX)
	_recipe.set("runtime_tile_size_px", TerrainVisualRecipePayload.FIXED_GAME_TILE_SIZE_PX)
	_recipe.set(
		"shape_supersampling",
		clampi(
			int(_recipe.get("shape_supersampling")),
			1,
			TerrainVisualRecipePayload.MAX_RUNTIME_SHAPE_SUPERSAMPLING,
		),
	)


func _update_ui_from_recipe() -> void:
	if _recipe == null:
		return
	for field_name: StringName in _shape_sliders:
		_update_slider_value(field_name, float(_recipe.get(field_name)))
	if not _recipe.has_method("get_material_slot"):
		return
	for slot_id: StringName in _material_color_pickers:
		var slot: Resource = _recipe.call("get_material_slot", slot_id) as Resource
		var color_picker: ColorPickerButton = _material_color_pickers.get(slot_id, null)
		if slot != null and color_picker != null:
			var color_value: Variant = slot.get("color_a")
			if color_value is Color:
				color_picker.color = color_value


func _update_slider_value(field_name: StringName, value: float) -> void:
	var slider: HSlider = _shape_sliders.get(field_name, null) as HSlider
	if slider == null:
		return
	slider.set_value_no_signal(value)


func _set_localized_text(control: Control, key: StringName, args: Dictionary = { }) -> void:
	_localized_text_controls.append(
		{
			"control": control,
			"key": key,
			"args": args.duplicate(true),
		},
	)
	_apply_localized_text(control, key, args)


func _apply_localized_text(control: Control, key: StringName, args: Dictionary = { }) -> void:
	var text := _text(key, args)
	if control is Label:
		(control as Label).text = text
	elif control is Button:
		(control as Button).text = text


func _refresh_localized_texts() -> void:
	var next_controls: Array[Dictionary] = []
	for entry: Dictionary in _localized_text_controls:
		var control: Control = entry.get("control", null) as Control
		if control == null or not is_instance_valid(control):
			continue
		_apply_localized_text(
			control,
			entry.get("key", &""),
			entry.get("args", { }) as Dictionary,
		)
		next_controls.append(entry)
	_localized_text_controls = next_controls
	_refresh_debug_mode_options()
	_refresh_mask_preset_options()
	_refresh_save_status()


func _text(key: StringName, args: Dictionary = { }) -> String:
	var text := tr(str(key))
	for arg_key: String in args:
		text = text.replace("{%s}" % arg_key, str(args[arg_key]))
	return text


func _set_save_status(key: StringName, args: Dictionary = { }) -> void:
	_save_status_key = key
	_save_status_args = args.duplicate(true)
	_refresh_save_status()


func _refresh_save_status() -> void:
	if _save_status_label == null or not is_instance_valid(_save_status_label):
		return
	_save_status_label.text = _text(_save_status_key, _save_status_args)


func _refresh_debug_mode_options() -> void:
	if _debug_mode_select == null:
		return
	_debug_mode_select.clear()
	for debug_mode: Dictionary in _debug_modes():
		_debug_mode_select.add_item(
			_text(debug_mode.get("label_key", &"")),
			int(debug_mode.get("id", 0)),
		)
	_sync_debug_mode_select()


func _sync_debug_mode_select() -> void:
	if _debug_mode_select == null:
		return
	for index: int in range(_debug_mode_select.item_count):
		if _debug_mode_select.get_item_id(index) == _debug_mode:
			_debug_mode_select.select(index)
			return


func _refresh_mask_preset_options() -> void:
	if _mask_preset_select == null:
		return
	_mask_preset_select.clear()
	_mask_preset_option_ids.clear()
	for preset_id: StringName in _mask_preset_ids():
		_mask_preset_option_ids.append(preset_id)
		_mask_preset_select.add_item(_text(_mask_preset_label_key(preset_id)))
	_sync_mask_preset_select()


func _sync_mask_preset_select() -> void:
	if _mask_preset_select == null:
		return
	for index: int in range(_mask_preset_option_ids.size()):
		if _mask_preset_option_ids[index] == _current_mask_preset_id:
			_mask_preset_select.select(index)
			return


func _control_label_key(field_name: StringName) -> StringName:
	return StringName("UI_TERRAIN_VISUAL_CONTROL_%s" % str(field_name).to_upper())


func _material_slot_label_key(slot_id: StringName) -> StringName:
	return StringName("UI_TERRAIN_VISUAL_MATERIAL_%s" % str(slot_id).to_upper())


func _mask_preset_label_key(preset_id: StringName) -> StringName:
	return StringName("UI_TERRAIN_VISUAL_MASK_%s" % str(preset_id).to_upper())


func _connect_recipe_changed() -> void:
	if _recipe == null:
		return
	var changed_callback := Callable(self, "_on_recipe_changed")
	if not _recipe.is_connected("changed", changed_callback):
		_recipe.connect("changed", changed_callback)


func _disconnect_recipe_changed() -> void:
	if _recipe == null:
		return
	var changed_callback := Callable(self, "_on_recipe_changed")
	if _recipe.is_connected("changed", changed_callback):
		_recipe.disconnect("changed", changed_callback)


func _on_recipe_changed() -> void:
	_update_ui_from_recipe()
	_refresh_preview()


func _is_cell_inside_mask(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _mask_size.x and cell.y < _mask_size.y


func _is_mask_ready() -> bool:
	return (
		_mask_size.x > 0
		and _mask_size.y > 0
		and _solid_mask.size() == _mask_size.x * _mask_size.y
	)


func _mask_index(cell: Vector2i) -> int:
	return cell.y * _mask_size.x + cell.x


func _count_solid_tiles() -> int:
	var count := 0
	for value: int in _solid_mask:
		if value == SOLID_VALUE:
			count += 1
	return count


func _shape_control_specs() -> Array[Dictionary]:
	return [
		_control_spec("Facade", &"south_height_px", 0.0, 128.0, 0.1),
		_control_spec("Facade", &"north_height_px", 0.0, 128.0, 0.1),
		_control_spec("Facade", &"side_height_px", 0.0, 128.0, 0.1),
		_control_spec("Facade", &"face_power", 0.1, 8.0, 0.01),
		_control_spec("Facade", &"back_drop", 0.0, 1.0, 0.01),
		_control_spec("Rim", &"rim_width_px", 0.0, 64.0, 0.1),
		_control_spec("Rim", &"crown_bevel_px", 0.0, 64.0, 0.1),
		_control_spec("Rim", &"edge_debris", 0.0, 1.0, 0.01),
		_control_spec("Rim", &"edge_color_strength", 0.0, 1.0, 0.01),
		_control_spec("Rim", &"contact_outline_width_px", 0.0, 32.0, 0.1),
		_control_spec("Shape", &"outer_corner_radius_px", 0.0, 128.0, 0.1),
		_control_spec("Shape", &"inner_corner_radius_px", 0.0, 128.0, 0.1),
		_control_spec("Shape", &"corner_round_px", 0.0, 128.0, 0.1),
		_control_spec("Shape", &"diagonal_smooth_px", 0.0, 128.0, 0.1),
		_control_spec("Shape", &"contour_relax", 0.0, 1.0, 0.01),
		_control_spec("Shape", &"contour_warp_px", 0.0, 16.0, 0.1),
		_control_spec("Shape", &"corner_variation", 0.0, 1.0, 0.01),
		_control_spec("Shape", &"geometry_variance", 0.0, 1.0, 0.01),
		_control_spec(
			"Shape",
			&"shape_supersampling",
			1.0,
			float(TerrainVisualRecipePayload.MAX_RUNTIME_SHAPE_SUPERSAMPLING),
			1.0,
		),
		_control_spec("Normal", &"normal_strength", 0.0, 16.0, 0.01),
		_control_spec("Normal", &"normal_detail_strength", 0.0, 16.0, 0.01),
		_control_spec("Normal", &"height_to_normal_blur_radius_px", 0.0, 16.0, 0.1),
	]


func _control_spec(
		group: String,
		field: StringName,
		min_value: float,
		max_value: float,
		step: float,
) -> Dictionary:
	return {
		"group": group,
		"field": field,
		"min": min_value,
		"max": max_value,
		"step": step,
	}


func _debug_modes() -> Array[Dictionary]:
	return [
		{ "id": 0, "label_key": &"UI_TERRAIN_VISUAL_DEBUG_ALBEDO" },
		{ "id": 1, "label_key": &"UI_TERRAIN_VISUAL_DEBUG_ZONE" },
		{ "id": 2, "label_key": &"UI_TERRAIN_VISUAL_DEBUG_COVERAGE" },
		{ "id": 3, "label_key": &"UI_TERRAIN_VISUAL_DEBUG_HEIGHT" },
		{ "id": 4, "label_key": &"UI_TERRAIN_VISUAL_DEBUG_NORMAL" },
		{ "id": 5, "label_key": &"UI_TERRAIN_VISUAL_DEBUG_MATERIAL_UV" },
		{ "id": 6, "label_key": &"UI_TERRAIN_VISUAL_DEBUG_LIT_PREVIEW" },
	]


func _mask_preset_ids() -> Array[StringName]:
	return [
		&"solid_4x3",
		&"notch_3x3",
		&"diagonal_3x3",
		&"cave_cut_5x4",
		&"single_1x1",
	]


func _mask_preset(preset_id: StringName) -> Dictionary:
	match preset_id:
		&"solid_4x3":
			return {
				"size": Vector2i(4, 3),
				"mask": PackedByteArray(
					[
						1,
						1,
						1,
						1,
						1,
						1,
						1,
						1,
						1,
						1,
						1,
						1,
					],
				),
			}
		&"notch_3x3":
			return {
				"size": Vector2i(3, 3),
				"mask": PackedByteArray(
					[
						1,
						1,
						1,
						1,
						0,
						1,
						1,
						1,
						1,
					],
				),
			}
		&"diagonal_3x3":
			return {
				"size": Vector2i(3, 3),
				"mask": PackedByteArray(
					[
						1,
						0,
						0,
						1,
						1,
						0,
						1,
						1,
						1,
					],
				),
			}
		&"cave_cut_5x4":
			return {
				"size": Vector2i(5, 4),
				"mask": PackedByteArray(
					[
						1,
						1,
						1,
						1,
						1,
						1,
						0,
						0,
						1,
						1,
						1,
						1,
						0,
						1,
						0,
						1,
						1,
						1,
						1,
						0,
					],
				),
			}
		&"single_1x1":
			return {
				"size": Vector2i(1, 1),
				"mask": PackedByteArray([1]),
			}
		_:
			return { }
