@tool
extends Control

const TerrainVisualPacketMaterialBuilder = preload(
	"res://data/terrain_visual/terrain_visual_packet_material.gd"
)
const TerrainVisualRecipePayload = preload(
	"res://data/terrain_visual/terrain_visual_recipe_payload.gd"
)
const DEFAULT_RECIPE: Resource = preload("res://data/terrain_visual/recipes/rock_default.tres")

const SOLID_VALUE := 1
const EMPTY_VALUE := 0
const DEFAULT_MASK_SIZE := Vector2i(8, 8)
const DEFAULT_EXPORT_PATH := "user://terrain_visual_v2_reference.png"

var _recipe: Resource = null
var _solid_mask := PackedByteArray()
var _mask_size := Vector2i.ZERO
var _solver: Object = null
var _last_packet: Dictionary = { }
var _last_debug_counters: Dictionary = { }
var _last_validation_errors := PackedStringArray()
var _refresh_count := 0
var _debug_mode := 0
var _is_bulk_mask_edit := false

var _preview_quad: ColorRect = null
var _control_panel: PanelContainer = null
var _mask_grid: GridContainer = null
var _mask_buttons: Array[Button] = []
var _shape_sliders: Dictionary = { }
var _material_color_pickers: Dictionary = { }
var _debug_mode_select: OptionButton = null
var _mask_preset_select: OptionButton = null


func _ready() -> void:
	_ensure_ui()
	if _mask_size == Vector2i.ZERO:
		apply_mask_preset(&"solid_4x3")
	if _recipe == null:
		set_recipe(DEFAULT_RECIPE.duplicate(true))


func _exit_tree() -> void:
	_disconnect_recipe_changed()
	if _solver != null and is_instance_valid(_solver):
		_solver.free()
	_solver = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _control_panel != null:
		_control_panel.visible = size.x >= 260.0


func set_recipe(recipe: Resource) -> void:
	_disconnect_recipe_changed()
	_recipe = recipe
	_connect_recipe_changed()
	_update_ui_from_recipe()
	if _is_mask_ready():
		_refresh_preview()


func get_recipe() -> Resource:
	return _recipe


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
	var resolved_value := value
	if field_name == &"shape_supersampling":
		resolved_value = float(clampi(roundi(value), 1, 8))
	_recipe.set(field_name, resolved_value)
	_update_slider_value(field_name, resolved_value)
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
	if _debug_mode_select != null:
		_debug_mode_select.select(_debug_mode)
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
	_mask_size = preset.get("size", DEFAULT_MASK_SIZE)
	_solid_mask = preset.get("mask", PackedByteArray()).duplicate()
	_rebuild_mask_grid()
	_sync_mask_buttons()
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


func _ensure_ui() -> void:
	if _preview_quad != null and is_instance_valid(_preview_quad):
		return
	_preview_quad = ColorRect.new()
	_preview_quad.name = "PacketPreview"
	_preview_quad.color = Color.TRANSPARENT
	_preview_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview_quad)

	_control_panel = PanelContainer.new()
	_control_panel.name = "WorkbenchControls"
	_control_panel.custom_minimum_size = Vector2(240.0, 0.0)
	_control_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_control_panel.offset_right = 240.0
	add_child(_control_panel)

	var scroll := ScrollContainer.new()
	scroll.name = "WorkbenchControlScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_control_panel.add_child(scroll)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	scroll.add_child(controls)

	_add_debug_mode_select(controls)
	_add_mask_preset_select(controls)

	for control_spec: Dictionary in _shape_control_specs():
		_add_shape_slider(
			controls,
			control_spec.get("field", &""),
			float(control_spec.get("min", 0.0)),
			float(control_spec.get("max", 1.0)),
			float(control_spec.get("step", 0.1)),
		)

	for slot_id: StringName in [&"top", &"face", &"back", &"base"]:
		_add_material_color_picker(controls, slot_id)

	var export_button := Button.new()
	export_button.name = "ExportReferenceScreenshot"
	export_button.text = "export"
	export_button.pressed.connect(func() -> void: export_reference_screenshot())
	controls.add_child(export_button)

	_mask_grid = GridContainer.new()
	_mask_grid.name = "MaskGrid"
	controls.add_child(_mask_grid)


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
	label.text = str(field_name)
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
	for debug_mode: Dictionary in _debug_modes():
		_debug_mode_select.add_item(
			String(debug_mode.get("label", "")),
			int(debug_mode.get("id", 0)),
		)
	_debug_mode_select.item_selected.connect(
		func(index: int) -> void:
			set_debug_mode(_debug_mode_select.get_item_id(index))
	)
	parent.add_child(_debug_mode_select)


func _add_mask_preset_select(parent: VBoxContainer) -> void:
	_mask_preset_select = OptionButton.new()
	_mask_preset_select.name = "MaskPreset"
	for preset_id: StringName in _mask_preset_ids():
		_mask_preset_select.add_item(str(preset_id))
	_mask_preset_select.item_selected.connect(
		func(index: int) -> void:
			apply_mask_preset(StringName(_mask_preset_select.get_item_text(index)))
	)
	parent.add_child(_mask_preset_select)


func _add_material_color_picker(parent: VBoxContainer, slot_id: StringName) -> void:
	var color_picker := ColorPickerButton.new()
	color_picker.name = "%sMaterialColor" % str(slot_id).capitalize()
	color_picker.text = str(slot_id)
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
			button.tooltip_text = "mask %d,%d" % [x, y]
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
	_preview_quad.position = Vector2.ZERO
	_preview_quad.size = Vector2(
		float(_last_packet.get("pixel_width", 0)),
		float(_last_packet.get("pixel_height", 0)),
	)


func _make_recipe_payload() -> Dictionary:
	return TerrainVisualRecipePayload.make_payload(_recipe)


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
		{ "field": &"south_height_px", "min": 0.0, "max": 128.0, "step": 0.1 },
		{ "field": &"north_height_px", "min": 0.0, "max": 128.0, "step": 0.1 },
		{ "field": &"side_height_px", "min": 0.0, "max": 128.0, "step": 0.1 },
		{ "field": &"rim_width_px", "min": 0.0, "max": 64.0, "step": 0.1 },
		{ "field": &"crown_bevel_px", "min": 0.0, "max": 64.0, "step": 0.1 },
		{ "field": &"outer_corner_radius_px", "min": 0.0, "max": 128.0, "step": 0.1 },
		{ "field": &"inner_corner_radius_px", "min": 0.0, "max": 128.0, "step": 0.1 },
		{ "field": &"corner_round_px", "min": 0.0, "max": 128.0, "step": 0.1 },
		{ "field": &"diagonal_smooth_px", "min": 0.0, "max": 128.0, "step": 0.1 },
		{ "field": &"contour_relax", "min": 0.0, "max": 1.0, "step": 0.01 },
		{ "field": &"contour_warp_px", "min": 0.0, "max": 16.0, "step": 0.1 },
		{ "field": &"corner_variation", "min": 0.0, "max": 1.0, "step": 0.01 },
		{ "field": &"geometry_variance", "min": 0.0, "max": 1.0, "step": 0.01 },
		{ "field": &"shape_supersampling", "min": 1.0, "max": 8.0, "step": 1.0 },
		{ "field": &"face_power", "min": 0.1, "max": 8.0, "step": 0.01 },
		{ "field": &"back_drop", "min": 0.0, "max": 1.0, "step": 0.01 },
		{ "field": &"edge_debris", "min": 0.0, "max": 1.0, "step": 0.01 },
		{ "field": &"edge_color_strength", "min": 0.0, "max": 1.0, "step": 0.01 },
		{ "field": &"contact_outline_width_px", "min": 0.0, "max": 32.0, "step": 0.1 },
		{ "field": &"normal_strength", "min": 0.0, "max": 16.0, "step": 0.01 },
		{ "field": &"normal_detail_strength", "min": 0.0, "max": 16.0, "step": 0.01 },
		{ "field": &"height_to_normal_blur_radius_px", "min": 0.0, "max": 16.0, "step": 0.1 },
	]


func _debug_modes() -> Array[Dictionary]:
	return [
		{ "id": 0, "label": "albedo" },
		{ "id": 1, "label": "zone" },
		{ "id": 2, "label": "coverage" },
		{ "id": 3, "label": "height" },
		{ "id": 4, "label": "normal" },
		{ "id": 5, "label": "material uv" },
		{ "id": 6, "label": "lit preview" },
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
