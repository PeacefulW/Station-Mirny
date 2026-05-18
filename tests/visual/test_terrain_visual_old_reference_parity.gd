extends GdUnitTestSuite

const OLD_REFERENCE_DIR := (
	"res://tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/"
)
const OLD_REFERENCE_MASK_PATH := OLD_REFERENCE_DIR + "mountain_reference_mask.png"
const OLD_REFERENCE_RECIPE_PATH := OLD_REFERENCE_DIR + "mountain_runtime_sdf_recipe.json"

const ZONE_EMPTY := 0
const ZONE_TOP := 1
const ZONE_EDGE := 2
const ZONE_FACE := 3
const ZONE_BACK := 4

const REFERENCE_MASK_ROWS := [
	"00111100",
	"01111110",
	"11111110",
	"11111110",
	"11111110",
	"01111000",
	"00110000",
	"00000000",
]


func test_native_rock_solver_matches_old_generator_reference_shape_metrics() -> void:
	var reference_image := _load_reference_mask()
	if reference_image == null:
		return

	var reference_recipe := _load_reference_recipe()
	if reference_recipe.is_empty():
		return

	var tile_size := int(reference_recipe.get("tile_size_px", 64))
	var width_tiles := reference_image.get_width() / tile_size
	var height_tiles := reference_image.get_height() / tile_size
	var old_mask := _derive_old_solid_tile_mask(reference_image, tile_size)
	assert_that(_mask_rows(old_mask, width_tiles, height_tiles)).is_equal(REFERENCE_MASK_ROWS)

	var packet := _solve_old_reference_packet(
		old_mask,
		width_tiles,
		height_tiles,
		_recipe_payload_from_old_reference(reference_recipe),
		int((reference_recipe.get("determinism", { }) as Dictionary).get("seed", 13371337)),
	)
	if packet.is_empty():
		return

	var reference_metrics := _reference_metrics(reference_image)
	var native_metrics := _packet_metrics(packet)

	_assert_ratio_close(
		"surface_ratio",
		float(native_metrics["surface_ratio"]),
		float(reference_metrics["surface_ratio"]),
		0.03,
	)
	_assert_ratio_close(
		"top_ratio",
		float(native_metrics["top_ratio"]),
		float(reference_metrics["top_ratio"]),
		0.03,
	)
	_assert_ratio_close(
		"edge_ratio",
		float(native_metrics["edge_ratio"]),
		float(reference_metrics["edge_ratio"]),
		0.02,
	)
	_assert_ratio_close(
		"face_ratio",
		float(native_metrics["face_ratio"]),
		float(reference_metrics["face_ratio"]),
		0.025,
	)
	_assert_ratio_close(
		"face_center_y",
		float(native_metrics["face_center_y"]),
		float(reference_metrics["face_center_y"]),
		0.04,
	)
	assert_bool(int(native_metrics["partial_surface_pixels"]) > 350) \
			.override_failure_message(
				"Native solver produced too few partially covered contour pixels: %s" % [
					native_metrics,
				],
			) \
			.is_true()


func _load_reference_mask() -> Image:
	var image := Image.new()
	var file := FileAccess.open(OLD_REFERENCE_MASK_PATH, FileAccess.READ)
	assert_that(file).is_not_null()
	if file == null:
		return null
	var load_result := image.load_png_from_buffer(file.get_buffer(file.get_length()))
	assert_that(load_result).is_equal(OK)
	if load_result != OK:
		return null
	return image


func _load_reference_recipe() -> Dictionary:
	var source := FileAccess.get_file_as_string(OLD_REFERENCE_RECIPE_PATH)
	assert_that(source.is_empty()).is_false()
	if source.is_empty():
		return { }

	var parsed: Variant = JSON.parse_string(source)
	assert_that(typeof(parsed)).is_equal(TYPE_DICTIONARY)
	if typeof(parsed) != TYPE_DICTIONARY:
		return { }
	return parsed as Dictionary


func _derive_old_solid_tile_mask(reference_image: Image, tile_size: int) -> PackedByteArray:
	var width_tiles := reference_image.get_width() / tile_size
	var height_tiles := reference_image.get_height() / tile_size
	var mask := PackedByteArray()
	mask.resize(width_tiles * height_tiles)

	for tile_y: int in range(height_tiles):
		for tile_x: int in range(width_tiles):
			var colored_samples := 0
			var total_samples := 0
			for local_y: int in range(0, tile_size, 4):
				for local_x: int in range(0, tile_size, 4):
					var color := reference_image.get_pixel(
						tile_x * tile_size + local_x,
						tile_y * tile_size + local_y,
					)
					if _reference_zone(color) != ZONE_EMPTY:
						colored_samples += 1
					total_samples += 1
			var ratio := float(colored_samples) / float(total_samples)
			mask[tile_y * width_tiles + tile_x] = 1 if ratio >= 0.12 else 0
	return mask


func _recipe_payload_from_old_reference(reference_recipe: Dictionary) -> Dictionary:
	var geometry: Dictionary = reference_recipe.get("geometry", { }) as Dictionary
	var materials: Dictionary = reference_recipe.get("materials", { }) as Dictionary
	return {
		"schema_version": 1,
		"recipe_id": &"old_reference:mountain",
		"surface_kind": &"rock",
		"tile_size_px": int(reference_recipe.get("tile_size_px", 64)),
		"rim_width_px": float(geometry.get("rim_width_px", geometry.get("edge_width_px", 8.0))),
		"south_height_px": float(geometry.get("south_height_px", 32.0)),
		"north_height_px": float(geometry.get("north_height_px", 0.0)),
		"side_height_px": float(geometry.get("side_height_px", 0.0)),
		"face_power": float(geometry.get("face_power", 2.5)),
		"back_drop": float(geometry.get("back_drop", 0.8)),
		"crown_bevel_px": float(geometry.get("crown_bevel_px", 10.0)),
		"outer_corner_radius_px": float(geometry.get("outer_corner_radius_px", 20.0)),
		"inner_corner_radius_px": float(geometry.get("inner_corner_radius_px", 20.0)),
		"corner_round_px": float(geometry.get("corner_round_px", 16.0)),
		"diagonal_smooth_px": float(geometry.get("diagonal_smooth_px", 32.0)),
		"contour_relax": float(geometry.get("contour_relax", 1.0)),
		"contour_warp_px": float(geometry.get("contour_warp_px", 0.75)),
		"corner_variation": float(geometry.get("corner_variation", 0.55)),
		"geometry_variance": float(geometry.get("geometry_variance", 0.75)),
		"shape_supersampling": int(geometry.get("shape_supersampling", 4)),
		"normal_strength": float(materials.get("normal_strength", 8.0)),
	}


func _solve_old_reference_packet(
		mask: PackedByteArray,
		width_tiles: int,
		height_tiles: int,
		recipe_payload: Dictionary,
		seed: int,
) -> Dictionary:
	assert_that(ClassDB.class_exists(&"TerrainVisualSolver")).is_true()
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		return { }

	var solver: Object = ClassDB.instantiate(&"TerrainVisualSolver")
	assert_that(solver).is_not_null()
	if solver == null:
		return { }

	var packet: Dictionary = solver.call(
		"build_editor_preview_packet",
		mask,
		width_tiles,
		height_tiles,
		recipe_payload,
		Vector2i.ZERO,
		seed,
	)
	solver.free()
	return packet


func _reference_metrics(reference_image: Image) -> Dictionary:
	var counts := _empty_zone_counts()
	var face_y_sum := 0.0
	var total_pixels := reference_image.get_width() * reference_image.get_height()
	for y: int in range(reference_image.get_height()):
		for x: int in range(reference_image.get_width()):
			var zone := _reference_zone(reference_image.get_pixel(x, y))
			counts[zone] += 1
			if zone == ZONE_FACE:
				face_y_sum += float(y)
	return _metrics_from_counts(
		counts,
		total_pixels,
		reference_image.get_height(),
		face_y_sum,
		0,
	)


func _packet_metrics(packet: Dictionary) -> Dictionary:
	var zone_ids: PackedByteArray = packet.get("zone_ids", PackedByteArray())
	var counts := _empty_zone_counts()
	var face_y_sum := 0.0
	var partial_surface_pixels := 0
	var width := int(packet.get("pixel_width", 0))
	var height := int(packet.get("pixel_height", 0))
	var pixel_count := width * height

	for index: int in range(pixel_count):
		var zone := int(zone_ids[index])
		counts[zone] += 1
		if zone == ZONE_FACE:
			face_y_sum += float(index / width)
		var surface_coverage := _packet_surface_coverage(packet, index)
		if surface_coverage > 0 and surface_coverage < 255:
			partial_surface_pixels += 1

	return _metrics_from_counts(counts, pixel_count, height, face_y_sum, partial_surface_pixels)


func _metrics_from_counts(
		counts: Dictionary,
		total_pixels: int,
		height: int,
		face_y_sum: float,
		partial_surface_pixels: int,
) -> Dictionary:
	var surface_count := total_pixels - int(counts[ZONE_EMPTY])
	var face_count := int(counts[ZONE_FACE])
	return {
		"surface_ratio": float(surface_count) / float(total_pixels),
		"top_ratio": float(counts[ZONE_TOP]) / float(total_pixels),
		"edge_ratio": float(counts[ZONE_EDGE]) / float(total_pixels),
		"face_ratio": float(counts[ZONE_FACE]) / float(total_pixels),
		"back_ratio": float(counts[ZONE_BACK]) / float(total_pixels),
		"face_center_y": (
			face_y_sum / float(face_count) / float(maxi(1, height - 1))
			if face_count > 0
			else 0.0
		),
		"partial_surface_pixels": partial_surface_pixels,
		"zone_counts": counts,
	}


func _reference_zone(color: Color) -> int:
	var red := _to_lsb(color.r)
	var green := _to_lsb(color.g)
	var blue := _to_lsb(color.b)
	var alpha := _to_lsb(color.a)
	if alpha <= 8 or red + green + blue <= 8:
		return ZONE_EMPTY
	if green > red and green > blue:
		return ZONE_FACE
	if red > 80 and green > 80 and blue < 80:
		return ZONE_EDGE
	if red > green and red > blue:
		return ZONE_TOP
	return ZONE_EMPTY


func _packet_surface_coverage(packet: Dictionary, pixel_index: int) -> int:
	var top: PackedByteArray = packet.get("coverage_top", PackedByteArray())
	var edge: PackedByteArray = packet.get("coverage_edge", PackedByteArray())
	var face: PackedByteArray = packet.get("coverage_face", PackedByteArray())
	var back: PackedByteArray = packet.get("coverage_back", PackedByteArray())
	return maxi(
		maxi(int(top[pixel_index]), int(edge[pixel_index])),
		maxi(int(face[pixel_index]), int(back[pixel_index])),
	)


func _mask_rows(mask: PackedByteArray, width: int, height: int) -> Array[String]:
	var rows: Array[String] = []
	for y: int in range(height):
		var row := ""
		for x: int in range(width):
			row += "1" if mask[y * width + x] != 0 else "0"
		rows.append(row)
	return rows


func _empty_zone_counts() -> Dictionary:
	return {
		ZONE_EMPTY: 0,
		ZONE_TOP: 0,
		ZONE_EDGE: 0,
		ZONE_FACE: 0,
		ZONE_BACK: 0,
	}


func _assert_ratio_close(name: String, actual: float, expected: float, tolerance: float) -> void:
	var delta: float = abs(actual - expected)
	assert_bool(delta <= tolerance) \
			.override_failure_message(
				"%s mismatch: actual=%.5f expected=%.5f tolerance=%.5f" % [
					name,
					actual,
					expected,
					tolerance,
				],
			) \
			.is_true()


func _to_lsb(value: float) -> int:
	return clampi(roundi(value * 255.0), 0, 255)
