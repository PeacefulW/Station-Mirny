extends GdUnitTestSuite

const WORKBENCH_SCENE_PATH := "res://addons/biome_visual_authoring_v2/terrain_visual_workbench.tscn"
const RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"
const VIEWPORT_SIZE := Vector2i(96, 96)

const DEBUG_MODE_ALBEDO := 0
const DEBUG_MODE_HEIGHT := 3
const DEBUG_MODE_LIT_PREVIEW := 6


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
	var fields := { }
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


func test_workbench_does_not_expose_pixel_size_controls() -> void:
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	var specs: Array = workbench.call("_shape_control_specs") as Array
	var fields := { }
	for spec_variant: Variant in specs:
		var spec: Dictionary = spec_variant as Dictionary
		fields[spec.get("field", &"")] = true

	assert_that(fields.has(&"tile_size_px")).is_false()
	assert_that(fields.has(&"runtime_tile_size_px")).is_false()
	assert_that(workbench.find_child("tile_size_px", true, false)).is_null()
	assert_that(workbench.find_child("runtime_tile_size_px", true, false)).is_null()

	viewport.free()


func test_workbench_caps_shape_supersampling_to_runtime_budget() -> void:
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	var specs: Array = workbench.call("_shape_control_specs") as Array
	var supersampling_spec := { }
	for spec_variant: Variant in specs:
		var spec: Dictionary = spec_variant as Dictionary
		if spec.get("field", &"") == &"shape_supersampling":
			supersampling_spec = spec
			break

	assert_that(supersampling_spec.is_empty()).is_false()
	assert_that(float(supersampling_spec.get("max", 0.0))).is_equal(4.0)

	var recipe := _recipe_fixture()
	recipe.set("shape_supersampling", 8)
	workbench.call("set_recipe", recipe)
	workbench.call("set_shape_control", &"shape_supersampling", 8.0)
	await _settle()
	assert_that(int(workbench.call("get_recipe").get("shape_supersampling"))).is_equal(4)

	viewport.free()


func test_workbench_keeps_controls_outside_preview_stage() -> void:
	var mounted := await _mount_workbench_with_size(Vector2i(1280, 720))
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	workbench.call("set_recipe", _recipe_fixture())
	workbench.call("apply_mask_preset", &"cave_cut_5x4")
	await _settle()

	var preview_stage := workbench.find_child("PreviewStage", true, false) as Control
	var controls := workbench.find_child("WorkbenchControls", true, false) as Control
	var preview_quad := workbench.find_child("PacketPreview", true, false) as Control
	assert_that(preview_stage).is_not_null()
	assert_that(controls).is_not_null()
	assert_that(preview_quad).is_not_null()
	if preview_stage == null or controls == null or preview_quad == null:
		viewport.free()
		return

	assert_that(controls.visible).is_true()
	assert_that(preview_stage.get_global_rect().end.x).is_less_equal(
		controls.get_global_rect().position.x + 1.0,
	)
	assert_that(preview_quad.get_global_rect().position.x).is_greater_equal(
		preview_stage.get_global_rect().position.x,
	)
	assert_that(preview_quad.get_global_rect().end.x).is_less_equal(
		preview_stage.get_global_rect().end.x,
	)
	assert_that(preview_quad.get_global_rect().end.y).is_less_equal(
		preview_stage.get_global_rect().end.y,
	)

	viewport.free()


func test_workbench_opens_on_lit_preview_and_cave_reference_mask() -> void:
	var mounted := await _mount_workbench_with_size(Vector2i(1280, 720))
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	var debug_select := workbench.find_child("DebugMode", true, false) as OptionButton
	assert_that(workbench.call("get_debug_mode")).is_equal(6)
	assert_that(workbench.call("get_mask_size")).is_equal(Vector2i(5, 4))
	assert_that(debug_select).is_not_null()
	if debug_select != null:
		assert_that(debug_select.get_selected_id()).is_equal(6)

	viewport.free()


func test_workbench_saves_current_recipe_to_requested_resource_path() -> void:
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	var recipe := _recipe_fixture()
	workbench.call("set_recipe", recipe)
	workbench.call("set_shape_control", &"outer_corner_radius_px", 23.5)
	workbench.call("set_shape_control", &"runtime_tile_size_px", 64.0)
	await _settle()

	var save_path := "user://terrain_visual_workbench_saved_recipe_%d.tres" % Time.get_ticks_usec()
	assert_that(workbench.call("save_current_recipe", save_path)).is_true()
	assert_that(FileAccess.file_exists(save_path)).is_true()

	var saved_recipe: Resource = ResourceLoader.load(
		save_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as Resource
	assert_that(saved_recipe).is_not_null()
	if saved_recipe != null:
		assert_that(float(saved_recipe.get("outer_corner_radius_px"))).is_equal_approx(23.5, 0.001)
		assert_that(int(saved_recipe.get("runtime_tile_size_px"))).is_equal(64)

	viewport.free()


func test_workbench_save_normalizes_pixel_size_to_fixed_game_size() -> void:
	var mounted := await _mount_workbench()
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	var recipe := _recipe_fixture()
	recipe.set("tile_size_px", 128)
	recipe.set("runtime_tile_size_px", 240)
	workbench.call("set_recipe", recipe)
	await _settle()

	var save_path := "user://terrain_visual_workbench_fixed_size_%d.tres" % Time.get_ticks_usec()
	assert_that(workbench.call("save_current_recipe", save_path)).is_true()

	var saved_recipe: Resource = ResourceLoader.load(
		save_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as Resource
	assert_that(saved_recipe).is_not_null()
	if saved_recipe != null:
		assert_that(int(saved_recipe.get("tile_size_px"))).is_equal(64)
		assert_that(int(saved_recipe.get("runtime_tile_size_px"))).is_equal(64)

	viewport.free()


func test_workbench_uses_localized_editor_labels() -> void:
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	var mounted_ru := await _mount_workbench_with_size(Vector2i(1280, 720))
	var workbench_ru: Control = mounted_ru.get("workbench") as Control
	var viewport_ru: SubViewport = mounted_ru.get("viewport") as SubViewport
	if workbench_ru == null:
		TranslationServer.set_locale(previous_locale)
		return

	var ru_texts := _collect_control_texts(workbench_ru)
	assert_that(ru_texts.has("Форма")).is_true()
	assert_that(ru_texts.has("Внешний радиус угла")).is_true()
	assert_that(ru_texts.has("Сохранить рецепт")).is_true()
	assert_that(ru_texts.has("outer_corner_radius_px")).is_false()
	viewport_ru.free()

	TranslationServer.set_locale("en")
	var mounted_en := await _mount_workbench_with_size(Vector2i(1280, 720))
	var workbench_en: Control = mounted_en.get("workbench") as Control
	var viewport_en: SubViewport = mounted_en.get("viewport") as SubViewport
	if workbench_en != null:
		var en_texts := _collect_control_texts(workbench_en)
		assert_that(en_texts.has("Shape")).is_true()
		assert_that(en_texts.has("Outer corner radius")).is_true()
		assert_that(en_texts.has("Save recipe")).is_true()
		assert_that(en_texts.has("outer_corner_radius_px")).is_false()
	viewport_en.free()
	TranslationServer.set_locale(previous_locale)


func test_workbench_preview_does_not_magnify_packet_pixels() -> void:
	var mounted := await _mount_workbench_with_size(Vector2i(1842, 1008))
	var workbench: Control = mounted.get("workbench") as Control
	var viewport: SubViewport = mounted.get("viewport") as SubViewport
	if workbench == null:
		return

	workbench.call("set_recipe", _recipe_fixture())
	workbench.call("apply_mask_preset", &"solid_4x3")
	workbench.call("set_debug_mode", DEBUG_MODE_LIT_PREVIEW)
	await _settle()

	var preview_quad := workbench.find_child("PacketPreview", true, false) as Control
	assert_that(preview_quad).is_not_null()
	if preview_quad != null:
		assert_that(preview_quad.scale.x).is_less_equal(1.0)
		assert_that(preview_quad.scale.y).is_less_equal(1.0)

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
	return await _mount_workbench_with_size(VIEWPORT_SIZE)


func _mount_workbench_with_size(viewport_size: Vector2i) -> Dictionary:
	assert_that(FileAccess.file_exists(WORKBENCH_SCENE_PATH)).is_true()
	var scene: PackedScene = load(WORKBENCH_SCENE_PATH) as PackedScene
	assert_that(scene).is_not_null()
	if scene == null:
		return { }

	var viewport := SubViewport.new()
	viewport.size = viewport_size
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
	workbench.size = Vector2(viewport_size)
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


func _collect_control_texts(root: Node) -> PackedStringArray:
	var texts := PackedStringArray()
	_collect_control_texts_recursive(root, texts)
	return texts


func _collect_control_texts_recursive(node: Node, texts: PackedStringArray) -> void:
	if node is OptionButton:
		var option_button := node as OptionButton
		for index: int in range(option_button.item_count):
			texts.append(option_button.get_item_text(index))
	elif node is Button:
		texts.append((node as Button).text)
	elif node is Label:
		texts.append((node as Label).text)
	for child: Node in node.get_children():
		_collect_control_texts_recursive(child, texts)
