extends GdUnitTestSuite

const TerrainVisualPacketMaterial = preload(
	"res://data/terrain_visual/terrain_visual_packet_material.gd"
)
const TerrainVisualRecipePayload = preload(
	"res://data/terrain_visual/terrain_visual_recipe_payload.gd"
)

const GOLDEN_PATH := "res://tests/visual/golden/terrain_visual_v2_golden.json"
const RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"
const DEV_COMMAND := (
	"powershell -NoProfile -ExecutionPolicy Bypass -File "
	+ "tools/agent/Invoke-GdUnit4.ps1 -NoHeadless -TestPath "
	+ "res://tests/visual/test_terrain_visual_golden_regression.gd"
)
const HASH_MOD := 2147483647
const VIEWPORT_SIZE := Vector2i(96, 96)
const DEBUG_MODE_ALBEDO := 0
const DEBUG_MODE_ZONE := 1
const DEBUG_MODE_HEIGHT := 3
const DEBUG_MODE_NORMAL := 4


func test_golden_fixture_locks_solver_packets_and_controlled_viewport_screenshots() -> void:
	var actual := _json_roundtrip(await _build_actual_snapshot())
	var golden := _load_golden_or_fail(actual)
	if golden.is_empty():
		return

	assert_that(golden.get("schema_version")).is_equal(actual.get("schema_version"))
	assert_that(golden.get("fixture_id")).is_equal(actual.get("fixture_id"))
	assert_that(golden.get("dev_command")).is_equal(DEV_COMMAND)
	assert_that(golden.get("tolerance")).is_equal(actual.get("tolerance"))
	assert_that(JSON.stringify(golden.get("packets"))).is_equal(
		JSON.stringify(actual.get("packets")),
	)
	assert_that(JSON.stringify(golden.get("screenshots"))).is_equal(
		JSON.stringify(actual.get("screenshots")),
	)


func test_editor_and_runtime_packets_are_byte_equivalent_for_golden_mask() -> void:
	var recipe := _recipe_fixture()
	var solver := _new_solver()
	if solver == null:
		return
	var mask := _mask(
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
	)
	var payload := TerrainVisualRecipePayload.make_payload(recipe)
	var editor_packet: Dictionary = solver.call(
		"build_editor_preview_packet",
		mask,
		3,
		3,
		payload,
		Vector2i(32, 48),
		777,
	)
	var runtime_packet: Dictionary = solver.call(
		"build_chunk_visual_packet",
		mask,
		3,
		3,
		payload,
		Vector2i(32, 48),
		Vector2i(2, 3),
		777,
	)
	solver.free()

	for field_name: String in [
		"zone_ids",
		"coverage_top",
		"coverage_edge",
		"coverage_face",
		"coverage_back",
		"height_q16",
		"normal_rgba8",
		"material_u_q16",
		"material_v_q16",
	]:
		assert_that(runtime_packet.get(field_name)).is_equal(editor_packet.get(field_name))


func _build_actual_snapshot() -> Dictionary:
	var recipe := _recipe_fixture()
	var fixtures := _fixture_masks()
	var packets := { }
	var screenshots := { }

	for fixture_id: String in fixtures.keys():
		var fixture: Dictionary = fixtures.get(fixture_id) as Dictionary
		var packet := _solve_packet(
			fixture.get("mask", PackedByteArray()) as PackedByteArray,
			int(fixture.get("width_tiles", 0)),
			int(fixture.get("height_tiles", 0)),
			recipe,
			int(fixture.get("seed", 0)),
		)
		packets[fixture_id] = _packet_digest(packet)
		if fixture_id == "notch_3x3":
			screenshots[fixture_id] = await _screenshot_digests(packet, recipe)

	return {
		"schema_version": 1,
		"fixture_id": "terrain_visual_v2_it8_golden",
		"dev_command": DEV_COMMAND,
		"tolerance": {
			"packet_hash_delta": 0,
			"screenshot_hash_delta": 0,
			"max_channel_delta_lsb": 0,
			"max_differing_pixel_ratio": 0.0,
		},
		"packets": packets,
		"screenshots": screenshots,
	}


func _load_golden_or_fail(actual: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		print("IT8_ACTUAL_GOLDEN_JSON_BEGIN")
		print(JSON.stringify(actual, "\t"))
		print("IT8_ACTUAL_GOLDEN_JSON_END")
		var message := "Missing terrain visual V2 golden fixture at %s." % GOLDEN_PATH
		assert_bool(false) \
				.override_failure_message(message) \
				.is_true()
		return { }
	var text := FileAccess.get_file_as_string(GOLDEN_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert_that(typeof(parsed)).is_equal(TYPE_DICTIONARY)
	if typeof(parsed) != TYPE_DICTIONARY:
		return { }
	return _json_roundtrip(parsed as Dictionary)


func _json_roundtrip(value: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(value))
	if typeof(parsed) != TYPE_DICTIONARY:
		return { }
	return parsed as Dictionary


func _fixture_masks() -> Dictionary:
	return {
		"single_cell": {
			"width_tiles": 1,
			"height_tiles": 1,
			"seed": 101,
			"mask": _mask([1]),
		},
		"notch_3x3": {
			"width_tiles": 3,
			"height_tiles": 3,
			"seed": 202,
			"mask": _mask(
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
		},
		"diagonal_2x2": {
			"width_tiles": 2,
			"height_tiles": 2,
			"seed": 303,
			"mask": _mask(
				[
					1,
					0,
					0,
					1,
				],
			),
		},
	}


func _solve_packet(
		mask: PackedByteArray,
		width_tiles: int,
		height_tiles: int,
		recipe: Resource,
		seed: int,
) -> Dictionary:
	var solver := _new_solver()
	if solver == null:
		return { }
	var packet: Dictionary = solver.call(
		"build_editor_preview_packet",
		mask,
		width_tiles,
		height_tiles,
		TerrainVisualRecipePayload.make_payload(recipe),
		Vector2i.ZERO,
		seed,
	)
	solver.free()
	return packet


func _packet_digest(packet: Dictionary) -> Dictionary:
	return {
		"pixel_size": [int(packet.get("pixel_width", 0)), int(packet.get("pixel_height", 0))],
		"zone_ids": _byte_hash(packet.get("zone_ids", PackedByteArray())),
		"height_q16": _byte_hash(packet.get("height_q16", PackedByteArray())),
		"normal_rgba8": _byte_hash(packet.get("normal_rgba8", PackedByteArray())),
		"material_u_q16": _byte_hash(packet.get("material_u_q16", PackedByteArray())),
		"material_v_q16": _byte_hash(packet.get("material_v_q16", PackedByteArray())),
		"zone_counts": _zone_counts(packet.get("zone_ids", PackedByteArray())),
	}


func _screenshot_digests(packet: Dictionary, recipe: Resource) -> Dictionary:
	var result := { }
	for mode_name: String in ["albedo", "zone", "height", "normal"]:
		var debug_mode := _debug_mode_for(mode_name)
		var image := await _render_packet(packet, recipe, debug_mode)
		assert_that(image).is_not_null()
		if image == null:
			result[mode_name] = {
				"hash": 0,
				"visible_pixels": 0,
				"size": [0, 0],
			}
			continue
		result[mode_name] = {
			"hash": _image_hash(image),
			"visible_pixels": _count_visible_pixels(image),
			"size": [image.get_width(), image.get_height()],
		}
	return result


func _render_packet(packet: Dictionary, recipe: Resource, debug_mode: int) -> Image:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var quad := ColorRect.new()
	quad.color = Color.WHITE
	quad.size = Vector2(
		float(packet.get("pixel_width", VIEWPORT_SIZE.x)),
		float(packet.get("pixel_height", VIEWPORT_SIZE.y)),
	)
	quad.material = TerrainVisualPacketMaterial.new().build_material(packet, debug_mode, recipe)
	viewport.add_child(quad)

	await await_idle_frame()
	await await_idle_frame()
	await await_millis(50)

	var viewport_texture := viewport.get_texture()
	if viewport_texture == null:
		viewport.free()
		return null
	var image := viewport_texture.get_image()
	viewport.free()
	return image


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


func _new_solver() -> Object:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		return null
	var solver: Object = ClassDB.instantiate(&"TerrainVisualSolver")
	assert_that(solver).is_not_null()
	return solver


func _mask(values: Array[int]) -> PackedByteArray:
	var mask := PackedByteArray()
	for value: int in values:
		mask.append(value)
	return mask


func _byte_hash(bytes: PackedByteArray) -> int:
	var hash := 17
	for value: int in bytes:
		hash = int((hash * 131 + value) % HASH_MOD)
	return hash


func _image_hash(image: Image) -> int:
	var hash := 17
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color := image.get_pixel(x, y)
			hash = int((hash * 131 + _to_lsb(color.r)) % HASH_MOD)
			hash = int((hash * 131 + _to_lsb(color.g)) % HASH_MOD)
			hash = int((hash * 131 + _to_lsb(color.b)) % HASH_MOD)
			hash = int((hash * 131 + _to_lsb(color.a)) % HASH_MOD)
	return hash


func _zone_counts(zone_ids: PackedByteArray) -> Dictionary:
	var counts := {
		"empty": 0,
		"top": 0,
		"edge": 0,
		"face": 0,
		"back": 0,
		"unknown": 0,
	}
	for zone_id: int in zone_ids:
		match zone_id:
			0:
				counts["empty"] += 1
			1:
				counts["top"] += 1
			2:
				counts["edge"] += 1
			3:
				counts["face"] += 1
			4:
				counts["back"] += 1
			_:
				counts["unknown"] += 1
	return counts


func _count_visible_pixels(image: Image) -> int:
	var count := 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if _to_lsb(image.get_pixel(x, y).a) > 0:
				count += 1
	return count


func _debug_mode_for(mode_name: String) -> int:
	match mode_name:
		"zone":
			return DEBUG_MODE_ZONE
		"height":
			return DEBUG_MODE_HEIGHT
		"normal":
			return DEBUG_MODE_NORMAL
		_:
			return DEBUG_MODE_ALBEDO


func _to_lsb(value: float) -> int:
	return clampi(roundi(value * 255.0), 0, 255)
