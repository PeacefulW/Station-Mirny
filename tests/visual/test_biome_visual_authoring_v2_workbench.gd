extends GdUnitTestSuite

const WORKBENCH_SCENE_PATH := "res://addons/biome_visual_authoring_v2/terrain_visual_workbench.tscn"
const RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"
const VIEWPORT_SIZE := Vector2i(96, 96)

const DEBUG_MODE_ALBEDO := 0
const DEBUG_MODE_HEIGHT := 3


func test_workbench_uses_native_solver_packet_and_refreshes_on_mask_edit() -> void:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	workbench.call("set_recipe", _recipe_fixture())
	workbench.call("set_mask_size", Vector2i(3, 3))
	workbench.call("set_mask_cell", Vector2i(0, 0), true)
	workbench.call("set_mask_cell", Vector2i(1, 0), true)
	await _settle()

	assert_that(workbench.call("get_solver_class_name")).is_equal(&"TerrainVisualSolver")
	var first_packet: Dictionary = workbench.call("get_last_packet")
	var first_refresh_count: int = workbench.call("get_refresh_count")
	var first_counters: Dictionary = workbench.call("get_last_debug_counters")
	assert_that(first_packet.is_empty()).is_false()
	assert_that(first_counters.get("solid_tiles", 0)).is_equal(2)

	workbench.call("set_mask_cell", Vector2i(1, 1), true)
	await _settle()

	var second_packet: Dictionary = workbench.call("get_last_packet")
	var second_counters: Dictionary = workbench.call("get_last_debug_counters")
	assert_that(workbench.call("get_refresh_count")).is_greater(first_refresh_count)
	assert_that(second_counters.get("solid_tiles", 0)).is_equal(3)
	assert_that(_byte_hash(second_packet.get("zone_ids", PackedByteArray()))).is_not_equal(
		_byte_hash(first_packet.get("zone_ids", PackedByteArray())),
	)

	viewport.free()


func test_shape_and_material_controls_change_preview() -> void:
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	workbench.call("set_recipe", _recipe_fixture())
	workbench.call("set_mask_size", Vector2i(2, 2))
	workbench.call("fill_mask", true)
	workbench.call("set_debug_mode", DEBUG_MODE_HEIGHT)
	await _settle()

	var first_packet: Dictionary = workbench.call("get_last_packet")
	var height_preview_before: Image = workbench.call("capture_reference_image") as Image
	var height_hash_before := _image_lsb_hash(height_preview_before)
	workbench.call("set_shape_control", &"south_height_px", 12.0)
	await _settle()

	var second_packet: Dictionary = workbench.call("get_last_packet")
	var height_preview_after: Image = workbench.call("capture_reference_image") as Image
	assert_that(_byte_hash(second_packet.get("height_q16", PackedByteArray()))).is_not_equal(
		_byte_hash(first_packet.get("height_q16", PackedByteArray())),
	)
	assert_that(_image_lsb_hash(height_preview_after)).is_not_equal(height_hash_before)

	workbench.call("set_debug_mode", DEBUG_MODE_ALBEDO)
	await _settle()
	var albedo_before: Image = workbench.call("capture_reference_image") as Image
	var albedo_hash_before := _image_lsb_hash(albedo_before)
	workbench.call("set_material_color", &"top", Color(0.95, 0.10, 0.08, 1.0))
	await _settle()

	var albedo_after: Image = workbench.call("capture_reference_image") as Image
	assert_that(_image_lsb_hash(albedo_after)).is_not_equal(albedo_hash_before)

	viewport.free()


func test_organic_shape_controls_are_sent_to_native_preview_payload() -> void:
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	workbench.call("set_recipe", _recipe_fixture())
	workbench.call("set_mask_size", Vector2i(3, 3))
	workbench.call("fill_mask", true)
	workbench.call("set_mask_cell", Vector2i(1, 1), false)
	await _settle()

	var relaxed_packet: Dictionary = workbench.call("get_last_packet")
	var relaxed_coverage_hash := _byte_hash(
		relaxed_packet.get("coverage_top", PackedByteArray()),
	)
	workbench.call("set_shape_control", &"contour_relax", 0.0)
	await _settle()

	var hard_packet: Dictionary = workbench.call("get_last_packet")
	assert_that(_byte_hash(hard_packet.get("coverage_top", PackedByteArray()))).is_not_equal(
		relaxed_coverage_hash,
	)

	viewport.free()


func test_workbench_exposes_edge_outline_and_normal_authoring_controls() -> void:
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	var specs: Array = workbench.call("_shape_control_specs") as Array
	var fields := {}
	for spec_variant: Variant in specs:
		var spec: Dictionary = spec_variant as Dictionary
		fields[spec.get("field", &"")] = true

	for field: StringName in [
		&"edge_debris",
		&"edge_color_strength",
		&"contact_outline_width_px",
		&"normal_detail_strength",
		&"height_to_normal_blur_radius_px",
	]:
		assert_that(fields.has(field)).is_true()

	viewport.free()


func test_reference_screenshot_exports_without_png_atlas_intermediate() -> void:
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	workbench.call("set_recipe", _recipe_fixture())
	workbench.call("set_mask_size", Vector2i(2, 2))
	workbench.call("fill_mask", true)
	await _settle()

	var image: Image = workbench.call("capture_reference_image") as Image
	assert_that(image).is_not_null()
	assert_that(image.get_size()).is_equal(VIEWPORT_SIZE)

	var export_path := "user://terrain_visual_v2_workbench_reference.png"
	assert_that(workbench.call("export_reference_screenshot", export_path)).is_true()
	assert_that(FileAccess.file_exists(export_path)).is_true()

	viewport.free()


func _mount_workbench() -> Dictionary:
	assert_that(FileAccess.file_exists(WORKBENCH_SCENE_PATH)).is_true()
	var scene: PackedScene = load(WORKBENCH_SCENE_PATH) as PackedScene
	assert_that(scene).is_not_null()
	if scene == null:
		return { }

	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var workbench: Control = scene.instantiate() as Control
	assert_that(workbench).is_not_null()
	if workbench == null:
		viewport.free()
		return { }
	workbench.set_anchors_preset(Control.PRESET_TOP_LEFT)
	workbench.size = Vector2(VIEWPORT_SIZE)
	viewport.add_child(workbench)
	await _settle()
	return {
		"viewport": viewport,
		"workbench": workbench,
	}


func _recipe_fixture() -> Resource:
	var recipe: Resource = load(RECIPE_PATH).duplicate(true)
	recipe.set("tile_size_px", 16)
	recipe.set("rim_width_px", 2.0)
	recipe.set("south_height_px", 6.0)
	recipe.set("north_height_px", 0.0)
	recipe.set("side_height_px", 4.0)
	recipe.set("face_power", 1.0)
	recipe.set("back_drop", 0.5)
	recipe.set("normal_strength", 2.0)
	return recipe


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()
	await await_millis(50)


func _byte_hash(bytes: PackedByteArray) -> int:
	var hash := 17
	for index: int in range(0, bytes.size(), 11):
		hash = int(hash * 31 + bytes[index])
	return hash


func _image_lsb_hash(image: Image) -> int:
	assert_that(image).is_not_null()
	if image == null:
		return 0
	var hash := 17
	for y: int in range(0, image.get_height(), 3):
		for x: int in range(0, image.get_width(), 3):
			var color := image.get_pixel(x, y)
			hash = int(hash * 31 + _to_lsb(color.r))
			hash = int(hash * 31 + _to_lsb(color.g))
			hash = int(hash * 31 + _to_lsb(color.b))
			hash = int(hash * 31 + _to_lsb(color.a))
	return hash


func _to_lsb(value: float) -> int:
	return clampi(roundi(value * 255.0), 0, 255)
