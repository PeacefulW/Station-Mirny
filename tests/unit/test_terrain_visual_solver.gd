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
	assert_that(_coverage_at(packet, "coverage_face", face_index)).is_equal(255)


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


func _solve(mask: PackedByteArray, width_tiles: int, height_tiles: int) -> Dictionary:
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
		_base_recipe_payload(),
		Vector2i.ZERO,
		12345,
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


func _pixel_index(packet: Dictionary, x: int, y: int) -> int:
	return y * int(packet.get("pixel_width")) + x


func _count_zone(packet: Dictionary, zone: int) -> int:
	var count := 0
	for value: int in packet.get("zone_ids"):
		if value == zone:
			count += 1
	return count


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
