extends GdUnitTestSuite

const ZONE_EMPTY := 0
const ZONE_TOP := 1
const ZONE_EDGE := 2
const ZONE_FACE := 3
const ZONE_BACK := 4

const TILE_SIZE := 16


func test_empty_mask_emits_empty_packet() -> void:
	var packet := _solve(_mask([0, 0, 0, 0]), 2, 2)
	if packet.is_empty():
		return

	assert_that(packet.get("schema_version")).is_equal(1)
	assert_that(packet.get("recipe_id")).is_equal(&"test:rock_solver")
	assert_that(packet.get("pixel_width")).is_equal(32)
	assert_that(packet.get("pixel_height")).is_equal(32)
	assert_that(packet.get("zone_ids").size()).is_equal(32 * 32)
	assert_that(_count_zone(packet, ZONE_EMPTY)).is_equal(32 * 32)
	assert_that(packet.get("debug_counters").get("solid_pixels")).is_equal(0)


func test_full_mask_has_top_zone_and_is_deterministic() -> void:
	var mask := _mask(
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
		],
	)

	var first := _solve(mask, 3, 3)
	var second := _solve(mask, 3, 3)
	if first.is_empty() or second.is_empty():
		return

	var center_index := _pixel_index(first, 24, 24)
	assert_that(first.get("zone_ids")[center_index]).is_equal(ZONE_TOP)
	assert_that(_height_at(first, center_index)).is_greater(0)
	assert_that(first.get("zone_ids")).is_equal(second.get("zone_ids"))
	assert_that(first.get("height_q16")).is_equal(second.get("height_q16"))
	assert_that(first.get("normal_rgba8")).is_equal(second.get("normal_rgba8"))
	assert_that(first.get("material_u_q16")).is_equal(second.get("material_u_q16"))
	assert_that(first.get("material_v_q16")).is_equal(second.get("material_v_q16"))


func test_single_cell_has_south_face_height_gradient_and_normal_change() -> void:
	var packet := _solve(_mask([1]), 1, 1)
	if packet.is_empty():
		return

	var top_index := _pixel_index(packet, 8, 8)
	var face_index := _pixel_index(packet, 8, 15)
	assert_that(packet.get("zone_ids")[top_index]).is_equal(ZONE_TOP)
	assert_that(packet.get("zone_ids")[face_index]).is_equal(ZONE_FACE)
	assert_that(_height_at(packet, face_index)).is_less(_height_at(packet, top_index))
	assert_that(_normal_at(packet, face_index)).is_not_equal(_normal_at(packet, top_index))
	assert_that(_coverage_at(packet, "coverage_face", face_index)).is_greater(0)


func test_diagonal_mask_keeps_mixed_zone_packet_deterministic() -> void:
	var mask := _mask(
		[
			1,
			0,
			0,
			1,
		],
	)

	var first := _solve(mask, 2, 2)
	var second := _solve(mask, 2, 2)
	if first.is_empty() or second.is_empty():
		return

	assert_that(_count_zone(first, ZONE_EMPTY)).is_greater(0)
	assert_that(_count_zone(first, ZONE_EDGE) + _count_zone(first, ZONE_FACE)).is_greater(0)
	assert_that(first.get("debug_counters").get("solid_pixels")).is_greater(0)
	assert_that(first.get("zone_ids")).is_equal(second.get("zone_ids"))
	assert_that(first.get("height_q16")).is_equal(second.get("height_q16"))


func test_diagonal_mask_emits_partial_organic_contour_coverage() -> void:
	var packet := _solve(
		_mask(
			[
				1,
				0,
				0,
				1,
			],
		),
		2,
		2,
	)
	if packet.is_empty():
		return

	assert_that(_has_partial_surface_coverage(packet)).is_true()


func test_contour_warp_changes_native_packet_geometry_deterministically() -> void:
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
	var flat_recipe := _base_recipe_payload()
	flat_recipe["contour_warp_px"] = 0.0
	flat_recipe["geometry_variance"] = 0.0
	var warped_recipe := _base_recipe_payload()
	warped_recipe["contour_warp_px"] = 3.0
	warped_recipe["geometry_variance"] = 1.0

	var flat_packet := _solve_with_recipe(mask, 3, 3, flat_recipe, 6789)
	var first_warped_packet := _solve_with_recipe(mask, 3, 3, warped_recipe, 6789)
	var second_warped_packet := _solve_with_recipe(mask, 3, 3, warped_recipe, 6789)
	if flat_packet.is_empty() or first_warped_packet.is_empty() or second_warped_packet.is_empty():
		return

	assert_that(_coverage_hash(first_warped_packet)).is_not_equal(_coverage_hash(flat_packet))
	assert_that(first_warped_packet.get("zone_ids")).is_equal(second_warped_packet.get("zone_ids"))
	assert_that(first_warped_packet.get("coverage_top")).is_equal(
		second_warped_packet.get("coverage_top"),
	)
	assert_that(first_warped_packet.get("coverage_edge")).is_equal(
		second_warped_packet.get("coverage_edge"),
	)
	assert_that(first_warped_packet.get("coverage_face")).is_equal(
		second_warped_packet.get("coverage_face"),
	)


func test_contour_relax_erodes_cell_mask_toward_organic_reference_shape() -> void:
	var mask := _mask(
		[
			0,
			1,
			1,
			1,
			1,
			1,
			1,
			1,
			0,
		],
	)
	var flat_recipe := _base_recipe_payload()
	flat_recipe["contour_relax"] = 0.0
	flat_recipe["contour_warp_px"] = 0.0
	var relaxed_recipe := _base_recipe_payload()
	relaxed_recipe["contour_relax"] = 1.0
	relaxed_recipe["contour_warp_px"] = 0.0
	relaxed_recipe["crown_bevel_px"] = 4.0
	relaxed_recipe["outer_corner_radius_px"] = 8.0
	relaxed_recipe["inner_corner_radius_px"] = 8.0
	relaxed_recipe["corner_round_px"] = 8.0
	relaxed_recipe["diagonal_smooth_px"] = 12.0

	var flat_packet := _solve_with_recipe(mask, 3, 3, flat_recipe, 24601)
	var relaxed_packet := _solve_with_recipe(mask, 3, 3, relaxed_recipe, 24601)
	if flat_packet.is_empty() or relaxed_packet.is_empty():
		return

	assert_that(relaxed_packet.get("debug_counters").get("solid_pixels")).is_less(
		flat_packet.get("debug_counters").get("solid_pixels"),
	)
	assert_that(_has_partial_surface_coverage(relaxed_packet)).is_true()


func test_organic_shape_field_changes_corner_and_diagonal_coverage() -> void:
	var mask := _mask_filled(3, 3)
	var relaxed_recipe := _base_recipe_payload()
	relaxed_recipe["contour_relax"] = 1.0
	relaxed_recipe["contour_warp_px"] = 0.0
	relaxed_recipe["crown_bevel_px"] = 4.0
	relaxed_recipe["outer_corner_radius_px"] = 0.0
	relaxed_recipe["inner_corner_radius_px"] = 0.0
	relaxed_recipe["corner_round_px"] = 0.0
	relaxed_recipe["diagonal_smooth_px"] = 0.0
	var organic_recipe := _base_recipe_payload()
	organic_recipe["contour_relax"] = 1.0
	organic_recipe["contour_warp_px"] = 0.0
	organic_recipe["crown_bevel_px"] = 4.0
	organic_recipe["outer_corner_radius_px"] = 10.0
	organic_recipe["inner_corner_radius_px"] = 10.0
	organic_recipe["corner_round_px"] = 10.0
	organic_recipe["diagonal_smooth_px"] = 12.0

	var relaxed_packet := _solve_with_recipe(mask, 3, 3, relaxed_recipe, 13579)
	var organic_packet := _solve_with_recipe(mask, 3, 3, organic_recipe, 13579)
	if relaxed_packet.is_empty() or organic_packet.is_empty():
		return

	assert_that(_coverage_hash(organic_packet)).is_not_equal(_coverage_hash(relaxed_packet))
	assert_that(organic_packet.get("zone_ids").size()).is_equal(relaxed_packet.get("zone_ids").size())
	assert_that(float(organic_packet.get("debug_counters").get("shape_field_radius_px"))).is_greater(
		0.0,
	)


func test_notch_mask_marks_inner_empty_and_edge_pixels() -> void:
	var packet := _solve(
		_mask(
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
		3,
		3,
	)
	if packet.is_empty():
		return

	var notch_center_index := _pixel_index(packet, 24, 24)
	assert_that(packet.get("zone_ids")[notch_center_index]).is_equal(ZONE_EMPTY)
	assert_that(_count_zone(packet, ZONE_EDGE) + _count_zone(packet, ZONE_FACE)).is_greater(0)
	assert_that(typeof(packet.get("outline_polylines"))).is_equal(TYPE_ARRAY)


func test_runtime_scaled_notch_center_stays_empty_with_default_warp() -> void:
	var recipe := _base_recipe_payload()
	recipe["tile_size_px"] = 32
	recipe["rim_width_px"] = 8.0
	recipe["south_height_px"] = 32.0
	recipe["side_height_px"] = 0.0
	recipe["face_power"] = 2.5
	recipe["back_drop"] = 0.8
	recipe["crown_bevel_px"] = 2.0
	recipe["outer_corner_radius_px"] = 20.0
	recipe["inner_corner_radius_px"] = 20.0
	recipe["corner_round_px"] = 16.0
	recipe["diagonal_smooth_px"] = 32.0
	recipe["contour_relax"] = 0.0
	recipe["contour_warp_px"] = 0.75
	var packet := _solve_with_recipe(
		_mask(
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
		3,
		3,
		recipe,
		12345,
	)
	if packet.is_empty():
		return

	var notch_center_index := _pixel_index(packet, 48, 48)
	assert_that(packet.get("zone_ids")[notch_center_index]).is_equal(ZONE_EMPTY)


func test_chunk_packet_entrypoint_preserves_runtime_origin_and_chunk_coord() -> void:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		return

	var solver: Object = ClassDB.instantiate(&"TerrainVisualSolver")
	assert_that(solver).is_not_null()
	if solver == null:
		return
	assert_that(solver.has_method("build_chunk_visual_packet")).is_true()
	if not solver.has_method("build_chunk_visual_packet"):
		solver.free()
		return

	var packet: Dictionary = solver.call(
		"build_chunk_visual_packet",
		_mask([1, 0, 0, 1]),
		2,
		2,
		_base_recipe_payload(),
		Vector2i(112, 128),
		Vector2i(7, 8),
		9876,
	)
	solver.free()
	_assert_packet_shape(packet)
	assert_that(packet.get("chunk_coord")).is_equal(Vector2i(7, 8))
	assert_that(packet.get("world_origin_tile")).is_equal(Vector2i(112, 128))
	assert_that(packet.get("debug_counters").get("seed")).is_equal(9876)


func test_chunk_packet_with_halo_crops_output_and_suppresses_internal_chunk_edge() -> void:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		return

	var solver: Object = ClassDB.instantiate(&"TerrainVisualSolver")
	assert_that(solver).is_not_null()
	if solver == null:
		return
	assert_that(solver.has_method("build_chunk_visual_packet_with_halo")).is_true()
	if not solver.has_method("build_chunk_visual_packet_with_halo"):
		solver.free()
		return

	var packet: Dictionary = solver.call(
		"build_chunk_visual_packet_with_halo",
		_mask_filled(5, 5),
		5,
		5,
		_base_recipe_payload(),
		Vector2i(31, 47),
		Vector2i(2, 3),
		2468,
		Rect2i(Vector2i(1, 1), Vector2i(3, 3)),
	)
	solver.free()
	_assert_packet_shape(packet)
	assert_that(packet.get("chunk_coord")).is_equal(Vector2i(2, 3))
	assert_that(packet.get("world_origin_tile")).is_equal(Vector2i(32, 48))
	assert_that(packet.get("pixel_width")).is_equal(48)
	assert_that(packet.get("pixel_height")).is_equal(48)
	assert_that(packet.get("dirty_rect_tiles")).is_equal(Rect2i(Vector2i.ZERO, Vector2i(3, 3)))

	var internal_right_edge_index := _pixel_index(packet, 47, 24)
	assert_that(packet.get("zone_ids")[internal_right_edge_index]).is_equal(ZONE_TOP)
	assert_that(_coverage_at(packet, "coverage_edge", internal_right_edge_index)).is_equal(0)
	assert_that(_coverage_at(packet, "coverage_face", internal_right_edge_index)).is_equal(0)
	assert_that(packet.get("debug_counters").get("input_width_tiles")).is_equal(5)
	assert_that(packet.get("debug_counters").get("output_width_tiles")).is_equal(3)


func test_contour_warp_is_periodic_at_world_wrap_width() -> void:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		return

	var recipe := _base_recipe_payload()
	recipe["tile_size_px"] = 16
	recipe["contour_warp_px"] = 2.0
	recipe["geometry_variance"] = 1.0
	recipe["corner_variation"] = 0.55
	recipe["world_wrap_width_tiles"] = 8

	var mask := _mask(
		[
			0,
			1,
			1,
			0,
			1,
			1,
			1,
			1,
			0,
			1,
			1,
			0,
		],
	)
	var first := _solve_with_recipe_at_origin(mask, 4, 3, recipe, 4242, Vector2i.ZERO)
	var wrapped := _solve_with_recipe_at_origin(mask, 4, 3, recipe, 4242, Vector2i(8, 0))
	if first.is_empty() or wrapped.is_empty():
		return

	assert_that(wrapped.get("zone_ids")).is_equal(first.get("zone_ids"))
	assert_that(wrapped.get("coverage_top")).is_equal(first.get("coverage_top"))
	assert_that(wrapped.get("height_q16")).is_equal(first.get("height_q16"))


func _solve(mask: PackedByteArray, width_tiles: int, height_tiles: int) -> Dictionary:
	return _solve_with_recipe(mask, width_tiles, height_tiles, _base_recipe_payload(), 12345)


func _solve_with_recipe(
		mask: PackedByteArray,
		width_tiles: int,
		height_tiles: int,
		recipe_payload: Dictionary,
		seed: int,
) -> Dictionary:
	return _solve_with_recipe_at_origin(
		mask,
		width_tiles,
		height_tiles,
		recipe_payload,
		seed,
		Vector2i.ZERO,
	)


func _solve_with_recipe_at_origin(
		mask: PackedByteArray,
		width_tiles: int,
		height_tiles: int,
		recipe_payload: Dictionary,
		seed: int,
		origin_tile: Vector2i,
) -> Dictionary:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		return { }

	var solver: Object = ClassDB.instantiate(&"TerrainVisualSolver")
	assert_that(solver).is_not_null()
	if solver == null:
		return { }
	assert_that(solver.has_method("build_editor_preview_packet")).is_true()
	if not solver.has_method("build_editor_preview_packet"):
		solver.free()
		return { }

	var packet: Dictionary = solver.call(
		"build_editor_preview_packet",
		mask,
		width_tiles,
		height_tiles,
		recipe_payload,
		origin_tile,
		seed,
	)
	solver.free()
	_assert_packet_shape(packet)
	return packet


func _base_recipe_payload() -> Dictionary:
	return {
		"schema_version": 1,
		"recipe_id": &"test:rock_solver",
		"surface_kind": &"rock",
		"tile_size_px": TILE_SIZE,
		"rim_width_px": 2.0,
		"south_height_px": 6.0,
		"north_height_px": 0.0,
		"side_height_px": 4.0,
		"face_power": 1.0,
		"back_drop": 0.5,
		"crown_bevel_px": 1.0,
		"outer_corner_radius_px": 5.0,
		"inner_corner_radius_px": 5.0,
		"corner_round_px": 4.0,
		"diagonal_smooth_px": 8.0,
		"contour_relax": 0.0,
		"contour_warp_px": 0.0,
		"corner_variation": 0.5,
		"geometry_variance": 0.75,
		"shape_supersampling": 4,
		"normal_strength": 2.0,
	}


func _assert_packet_shape(packet: Dictionary) -> void:
	var required_keys := [
		"schema_version",
		"recipe_id",
		"surface_kind",
		"world_origin_tile",
		"chunk_coord",
		"dirty_rect_tiles",
		"dirty_rect_px",
		"tile_size_px",
		"pixel_width",
		"pixel_height",
		"zone_ids",
		"coverage_top",
		"coverage_edge",
		"coverage_face",
		"coverage_back",
		"height_q16",
		"normal_rgba8",
		"material_u_q16",
		"material_v_q16",
		"outline_polylines",
		"debug_counters",
	]
	for key: String in required_keys:
		assert_that(packet.has(key)).is_true()


func _mask(values: Array[int]) -> PackedByteArray:
	var mask := PackedByteArray()
	for value: int in values:
		mask.append(value)
	return mask


func _mask_filled(width: int, height: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(width * height)
	mask.fill(1)
	return mask


func _pixel_index(packet: Dictionary, x: int, y: int) -> int:
	return y * int(packet.get("pixel_width")) + x


func _count_zone(packet: Dictionary, zone: int) -> int:
	var count := 0
	for value: int in packet.get("zone_ids"):
		if value == zone:
			count += 1
	return count


func _has_partial_surface_coverage(packet: Dictionary) -> bool:
	var pixel_count := int(packet.get("pixel_width", 0)) * int(packet.get("pixel_height", 0))
	for field_name: String in [
		"coverage_top",
		"coverage_edge",
		"coverage_face",
		"coverage_back",
	]:
		var bytes: PackedByteArray = packet.get(field_name)
		for index: int in range(pixel_count):
			var value := int(bytes[index])
			if value > 0 and value < 255:
				return true
	return false


func _coverage_hash(packet: Dictionary) -> int:
	var hash := 17
	for field_name: String in [
		"coverage_top",
		"coverage_edge",
		"coverage_face",
		"coverage_back",
	]:
		for value: int in packet.get(field_name):
			hash = int((hash * 131 + value) % 2147483647)
	return hash


func _height_at(packet: Dictionary, pixel_index: int) -> int:
	var bytes: PackedByteArray = packet.get("height_q16")
	var byte_index := pixel_index * 2
	return int(bytes[byte_index]) | (int(bytes[byte_index + 1]) << 8)


func _coverage_at(packet: Dictionary, field_name: String, pixel_index: int) -> int:
	var bytes: PackedByteArray = packet.get(field_name)
	return bytes[pixel_index]


func _normal_at(packet: Dictionary, pixel_index: int) -> PackedByteArray:
	var bytes: PackedByteArray = packet.get("normal_rgba8")
	var byte_index := pixel_index * 4
	return bytes.slice(byte_index, byte_index + 4)
