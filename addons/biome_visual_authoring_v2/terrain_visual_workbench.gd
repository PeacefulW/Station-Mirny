@tool
extends Control

const TerrainVisualPacketMaterialBuilder = preload(
	"res://data/terrain_visual/terrain_visual_packet_material.gd"
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
var _top_color_picker: ColorPickerButton = null


func _ready() -> void:
	_ensure_ui()
	if _mask_size == Vector2i.ZERO:
		set_mask_size(DEFAULT_MASK_SIZE)
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
		_mask_buttons[index].button_pressed = is_solid
	if not _is_bulk_mask_edit:
		_refresh_preview()


func get_mask_cell(cell: Vector2i) -> bool:
	if not _is_cell_inside_mask(cell):
		return false
	return _solid_mask[_mask_index(cell)] == SOLID_VALUE


func fill_mask(is_solid: bool) -> void:
	_is_bulk_mask_edit = true
	_solid_mask.fill(SOLID_VALUE if is_solid else EMPTY_VALUE)
	for button: Button in _mask_buttons:
		button.button_pressed = is_solid
	_is_bulk_mask_edit = false
	_refresh_preview()


func set_shape_control(field_name: StringName, value: float) -> void:
	if _recipe == null:
		return
	_recipe.set(field_name, value)
	_update_slider_value(field_name, value)
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
	if slot_id == &"top" and _top_color_picker != null:
		_top_color_picker.color = color
	_refresh_preview()


func set_debug_mode(debug_mode: int) -> void:
	_debug_mode = clampi(debug_mode, 0, 6)
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

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	_control_panel.add_child(controls)

	_add_shape_slider(controls, &"south_height_px", 0.0, 128.0)
	_add_shape_slider(controls, &"rim_width_px", 0.0, 64.0)
	_add_shape_slider(controls, &"side_height_px", 0.0, 128.0)

	_top_color_picker = ColorPickerButton.new()
	_top_color_picker.name = "TopMaterialColor"
	_top_color_picker.text = "top"
	_top_color_picker.color_changed.connect(
		func(color: Color) -> void: set_material_color(&"top", color),
	)
	controls.add_child(_top_color_picker)

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
	slider.step = 0.1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void: set_shape_control(field_name, value))
	row.add_child(slider)
	_shape_sliders[field_name] = slider


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
	return {
		"schema_version": int(_recipe.get("schema_version")),
		"recipe_id": StringName(_recipe.get("id")),
		"surface_kind": StringName(_recipe.get("surface_kind")),
		"tile_size_px": int(_recipe.get("tile_size_px")),
		"rim_width_px": float(_recipe.get("rim_width_px")),
		"south_height_px": float(_recipe.get("south_height_px")),
		"north_height_px": float(_recipe.get("north_height_px")),
		"side_height_px": float(_recipe.get("side_height_px")),
		"face_power": float(_recipe.get("face_power")),
		"back_drop": float(_recipe.get("back_drop")),
		"normal_strength": float(_recipe.get("normal_strength")),
	}


func _update_ui_from_recipe() -> void:
	if _recipe == null:
		return
	for field_name: StringName in _shape_sliders:
		_update_slider_value(field_name, float(_recipe.get(field_name)))
	var top_slot: Resource = null
	if _recipe.has_method("get_material_slot"):
		top_slot = _recipe.call("get_material_slot", &"top") as Resource
	if top_slot != null and _top_color_picker != null:
		var color_value: Variant = top_slot.get("color_a")
		if color_value is Color:
			_top_color_picker.color = color_value


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
