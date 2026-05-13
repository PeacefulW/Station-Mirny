extends SceneTree

const CHUNK_SIZE_TILES: int = 16
const TILE_SIZE_PX: int = 64
const HALO_TILES: int = 2
const OUTPUT_SIZE_PX: int = CHUNK_SIZE_TILES * TILE_SIZE_PX
const COLLISION_SAMPLE_PX: int = 4
const COLLISION_SIDE: int = OUTPUT_SIZE_PX / COLLISION_SAMPLE_PX + 1
const FIXTURE_RECIPE_PATH: String = "res://tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/mountain_runtime_sdf_recipe.json"
const FIXTURE_MASK_PATH: String = "res://tools/rimworld-autotile-lab/desktop_app/exports/runtime_sdf_reference/mountain_reference_mask.png"
const FIXTURE_ROWS: Array[String] = [
	"00000000",
	"00111100",
	"01111110",
	"01101110",
	"01111110",
	"00111000",
	"00010000",
	"00000000",
]

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for runtime SDF contour field checks.")
	if world_core == null:
		quit(1)
		return
	_assert(world_core.has_method("build_contour_chunk"), "WorldCore must bind build_contour_chunk(input).")
	if not world_core.has_method("build_contour_chunk"):
		quit(1)
		return

	var recipe: Dictionary = _load_recipe(FIXTURE_RECIPE_PATH)
	_assert(not recipe.is_empty(), "Iteration 01 runtime SDF recipe fixture must load.")
	if recipe.is_empty():
		quit(1)
		return

	_assert_reference_fixture_shape(world_core, recipe)
	_assert_empty_and_full_masks(world_core, recipe)
	_assert_single_island_rounded_occupancy(world_core, recipe)
	_assert_diagonal_smoothing_changes_field(world_core, recipe)

	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_field_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	_assert(FileAccess.file_exists(FIXTURE_RECIPE_PATH), "Iteration 01 mountain recipe fixture must exist.")
	_assert(FileAccess.file_exists(FIXTURE_MASK_PATH), "Iteration 01 mountain reference mask fixture must exist.")

	var world_core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	var contour_field_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_contour_field.cpp")
	_assert(
		world_core_source.contains("build_contour_chunk"),
		"WorldCore must expose build_contour_chunk() for Iteration 02."
	)
	_assert(
		world_core_source.contains("world_contour_field"),
		"WorldCore must delegate runtime contour field building to native world_contour_field code."
	)
	_assert(
		contour_field_source.contains("controlled_sdf_distance_px(p_input, p_sdf"),
		"Native mountain outline must be derived from the SDF field, not from vertical pixel probes that create chunk-corner brackets."
	)

	var schema_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/packet_schemas.md")
	_assert(
		schema_source.contains("ContourChunkInputV1") and schema_source.contains("ContourChunkResultV1"),
		"packet_schemas.md must document ContourChunkInputV1 and ContourChunkResultV1."
	)

	var api_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/system_api.md")
	_assert(
		api_source.contains("build_contour_chunk"),
		"system_api.md must document WorldCore.build_contour_chunk(input)."
	)

func _assert_reference_fixture_shape(world_core: Object, recipe: Dictionary) -> void:
	var input: Dictionary = _build_input(recipe, _build_fixture_mask())
	var first: Dictionary = _call_build_contour_chunk(world_core, input)
	var second: Dictionary = _call_build_contour_chunk(world_core, input)
	_assert_result_shape(first, "fixture")
	_assert_result_shape(second, "fixture repeat")
	_assert_results_equal(first, second, "Repeated calls for the same fixture must be deterministic.")

	var mask: PackedByteArray = first.get("mask_rgba8", PackedByteArray())
	var collision: PackedFloat32Array = first.get("collision_sdf_f32", PackedFloat32Array())
	_assert(_has_alpha_above(mask, 240), "Fixture field must contain occupied pixels.")
	_assert(_has_alpha_below(mask, 15), "Fixture field must contain empty pixels.")
	_assert(_has_positive_and_negative(collision), "Fixture collision SDF must contain positive inside and negative outside samples.")

func _assert_empty_and_full_masks(world_core: Object, recipe: Dictionary) -> void:
	var empty_result: Dictionary = _call_build_contour_chunk(world_core, _build_input(recipe, _build_constant_mask(0)))
	_assert_result_shape(empty_result, "empty")
	var empty_mask: PackedByteArray = empty_result.get("mask_rgba8", PackedByteArray())
	_assert(_sample_alpha(empty_mask, OUTPUT_SIZE_PX / 2, OUTPUT_SIZE_PX / 2) == 0, "Empty mask must produce transparent occupancy.")

	var full_result: Dictionary = _call_build_contour_chunk(world_core, _build_input(recipe, _build_constant_mask(1)))
	_assert_result_shape(full_result, "full")
	var full_mask: PackedByteArray = full_result.get("mask_rgba8", PackedByteArray())
	_assert(_sample_alpha(full_mask, OUTPUT_SIZE_PX / 2, OUTPUT_SIZE_PX / 2) == 255, "Full mask must produce full center occupancy.")

func _assert_single_island_rounded_occupancy(world_core: Object, recipe: Dictionary) -> void:
	var mask := _build_constant_mask(0)
	_set_local_cell(mask, 8, 8, 1)
	var result: Dictionary = _call_build_contour_chunk(world_core, _build_input(recipe, mask))
	_assert_result_shape(result, "single island")
	var rgba: PackedByteArray = result.get("mask_rgba8", PackedByteArray())
	var center_alpha: int = _sample_alpha(rgba, 8 * TILE_SIZE_PX + TILE_SIZE_PX / 2, 8 * TILE_SIZE_PX + TILE_SIZE_PX / 2)
	var corner_alpha: int = _sample_alpha(rgba, 8 * TILE_SIZE_PX, 8 * TILE_SIZE_PX)
	_assert(center_alpha > 240, "Single solid island center must be occupied.")
	_assert(corner_alpha > 0 and corner_alpha < center_alpha, "Single island corner must be rounded/anti-aliased, not a hard full square.")

func _assert_diagonal_smoothing_changes_field(world_core: Object, recipe: Dictionary) -> void:
	var diagonal_mask := _build_constant_mask(0)
	_set_local_cell(diagonal_mask, 7, 7, 1)
	_set_local_cell(diagonal_mask, 8, 8, 1)

	var sharp_recipe: Dictionary = recipe.duplicate(true)
	var sharp_geometry: Dictionary = sharp_recipe.get("geometry", {}) as Dictionary
	sharp_geometry["diagonal_smooth_px"] = 0.0
	sharp_recipe["geometry"] = sharp_geometry

	var smooth_result: Dictionary = _call_build_contour_chunk(world_core, _build_input(recipe, diagonal_mask))
	var sharp_result: Dictionary = _call_build_contour_chunk(world_core, _build_input(sharp_recipe, diagonal_mask))
	_assert_result_shape(smooth_result, "diagonal smooth")
	_assert_result_shape(sharp_result, "diagonal sharp")
	_assert(
		not _packed_byte_equal(
			smooth_result.get("mask_rgba8", PackedByteArray()),
			sharp_result.get("mask_rgba8", PackedByteArray())
		),
		"diagonal_smooth_px must affect the emitted mask field."
	)

func _call_build_contour_chunk(world_core: Object, input: Dictionary) -> Dictionary:
	var result: Variant = world_core.call("build_contour_chunk", input)
	_assert(result is Dictionary, "build_contour_chunk(input) must return a Dictionary.")
	if result is Dictionary:
		return result as Dictionary
	return {}

func _assert_result_shape(result: Dictionary, label: String) -> void:
	_assert(bool(result.get("ready", false)), "%s result must be ready." % [label])
	_assert(result.has("mask_rgba8"), "%s result must include mask_rgba8." % [label])
	_assert(result.has("height_r16"), "%s result must include height_r16." % [label])
	_assert(result.has("normal_rgba8"), "%s result must include normal_rgba8." % [label])
	_assert(result.has("collision_sdf_f32"), "%s result must include collision_sdf_f32." % [label])
	_assert(result.get("pixel_size", Vector2i.ZERO) == Vector2i(OUTPUT_SIZE_PX, OUTPUT_SIZE_PX), "%s result pixel_size must be 1024x1024." % [label])
	_assert((result.get("mask_rgba8", PackedByteArray()) as PackedByteArray).size() == OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 4, "%s mask byte length must be 1024*1024*4." % [label])
	_assert((result.get("height_r16", PackedByteArray()) as PackedByteArray).size() == OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 2, "%s height byte length must be 1024*1024*2." % [label])
	_assert((result.get("normal_rgba8", PackedByteArray()) as PackedByteArray).size() == OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 4, "%s normal byte length must be 1024*1024*4." % [label])
	var collision: PackedFloat32Array = result.get("collision_sdf_f32", PackedFloat32Array()) as PackedFloat32Array
	_assert(collision.size() == COLLISION_SIDE * COLLISION_SIDE, "%s collision field must be 257*257 samples." % [label])
	_assert(result.get("collision_size", Vector2i.ZERO) == Vector2i(COLLISION_SIDE, COLLISION_SIDE), "%s collision_size must be 257x257." % [label])
	_assert(int(result.get("collision_sample_px", 0)) == COLLISION_SAMPLE_PX, "%s collision_sample_px must be 4." % [label])

func _assert_results_equal(first: Dictionary, second: Dictionary, message: String) -> void:
	_assert(_packed_byte_equal(first.get("mask_rgba8", PackedByteArray()), second.get("mask_rgba8", PackedByteArray())), message + " mask_rgba8 differs.")
	_assert(_packed_byte_equal(first.get("height_r16", PackedByteArray()), second.get("height_r16", PackedByteArray())), message + " height_r16 differs.")
	_assert(_packed_byte_equal(first.get("normal_rgba8", PackedByteArray()), second.get("normal_rgba8", PackedByteArray())), message + " normal_rgba8 differs.")
	_assert(_packed_float_equal(first.get("collision_sdf_f32", PackedFloat32Array()), second.get("collision_sdf_f32", PackedFloat32Array())), message + " collision_sdf_f32 differs.")

func _load_recipe(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

func _build_input(recipe: Dictionary, solid_mask: PackedByteArray) -> Dictionary:
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(solid_mask.size())
	for index: int in solid_mask.size():
		if solid_mask[index] != 0:
			mountain_ids[index] = 1
	return {
		"chunk_coord": Vector2i.ZERO,
		"world_seed": int((recipe.get("determinism", {}) as Dictionary).get("seed", 13371337)),
		"world_version": 44,
		"tile_size_px": TILE_SIZE_PX,
		"chunk_size_tiles": CHUNK_SIZE_TILES,
		"halo_tiles": HALO_TILES,
		"recipe_id": StringName(str(recipe.get("asset_name", "mountain"))),
		"recipe": recipe,
		"solid_mask_with_halo": solid_mask,
		"contour_class_mask_with_halo": solid_mask,
		"mountain_id_with_halo": mountain_ids,
		"diff_revision": 5,
	}

func _build_fixture_mask() -> PackedByteArray:
	var mask := _build_constant_mask(0)
	var offset_x: int = 4
	var offset_y: int = 4
	for y: int in FIXTURE_ROWS.size():
		var row: String = FIXTURE_ROWS[y]
		for x: int in row.length():
			if row.unicode_at(x) == "1".unicode_at(0):
				_set_local_cell(mask, offset_x + x, offset_y + y, 1)
	return mask

func _build_constant_mask(value: int) -> PackedByteArray:
	var side: int = CHUNK_SIZE_TILES + HALO_TILES * 2
	var mask := PackedByteArray()
	mask.resize(side * side)
	for index: int in mask.size():
		mask[index] = value
	return mask

func _set_local_cell(mask: PackedByteArray, local_x: int, local_y: int, value: int) -> void:
	var side: int = CHUNK_SIZE_TILES + HALO_TILES * 2
	mask[(local_y + HALO_TILES) * side + local_x + HALO_TILES] = value

func _sample_alpha(mask_rgba8: PackedByteArray, x: int, y: int) -> int:
	var offset: int = (y * OUTPUT_SIZE_PX + x) * 4 + 3
	if offset < 0 or offset >= mask_rgba8.size():
		return 0
	return mask_rgba8[offset]

func _has_alpha_above(mask_rgba8: PackedByteArray, threshold: int) -> bool:
	for offset: int in range(3, mask_rgba8.size(), 4):
		if mask_rgba8[offset] > threshold:
			return true
	return false

func _has_alpha_below(mask_rgba8: PackedByteArray, threshold: int) -> bool:
	for offset: int in range(3, mask_rgba8.size(), 4):
		if mask_rgba8[offset] < threshold:
			return true
	return false

func _has_positive_and_negative(values: PackedFloat32Array) -> bool:
	var has_positive: bool = false
	var has_negative: bool = false
	for value: float in values:
		has_positive = has_positive or value > 0.0
		has_negative = has_negative or value < 0.0
		if has_positive and has_negative:
			return true
	return false

func _packed_byte_equal(lhs: PackedByteArray, rhs: PackedByteArray) -> bool:
	if lhs.size() != rhs.size():
		return false
	for index: int in lhs.size():
		if lhs[index] != rhs[index]:
			return false
	return true

func _packed_float_equal(lhs: PackedFloat32Array, rhs: PackedFloat32Array) -> bool:
	if lhs.size() != rhs.size():
		return false
	for index: int in lhs.size():
		if lhs[index] != rhs[index]:
			return false
	return true

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
