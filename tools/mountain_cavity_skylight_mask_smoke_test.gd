extends SceneTree

const REACH_SAMPLES: int = 4
const CURRENT_TUNING_REACH_SAMPLES: int = 8

var _failed: bool = false
var _world_core: Object = null


func _init() -> void:
	_world_core = ClassDB.instantiate("WorldCore")
	_assert(_world_core != null, "WorldCore must be available for skylight-mask checks.")
	if _world_core == null:
		_finish()
		return
	_assert(
		_world_core.has_method("build_mountain_skylight_exposure"),
		"WorldCore must bind build_mountain_skylight_exposure().",
	)
	if not _world_core.has_method("build_mountain_skylight_exposure"):
		_finish()
		return

	_assert_sealed_pocket_stays_dark()
	_assert_single_mouth_falloff()
	_assert_current_one_tile_tuning_falloff()
	_assert_wider_and_second_mouth_are_monotonic()
	_assert_diagonal_corner_does_not_leak()
	_assert_halo_windows_match_global_solution()
	_assert_determinism_and_invalid_input()
	_assert_static_worker_and_apply_contract()
	_finish()


func _assert_sealed_pocket_stays_dark() -> void:
	var width: int = 9
	var height: int = 7
	var closed: PackedByteArray = _closed_rect(width, height, Rect2i(1, 1, 7, 5))
	var live: PackedByteArray = closed.duplicate()
	for x: int in range(3, 6):
		live[_index(x, 3, width)] = 0
	var result: Dictionary = _solve(closed, live, width, height)
	var exposure: PackedByteArray = _exposure(result)
	_assert(exposure.size() == width * height, "Sealed-pocket result must keep the full mask shape.")
	for x: int in range(3, 6):
		_assert(exposure[_index(x, 3, width)] == 0, "Sealed pocket must have zero sky exposure.")
	_assert(int(result.get("source_sample_count", -1)) == 0, "Sealed pocket must have no sky source.")


func _assert_single_mouth_falloff() -> void:
	var width: int = 9
	var height: int = 7
	var closed: PackedByteArray = _closed_rect(width, height, Rect2i(1, 1, 7, 5))
	var live: PackedByteArray = closed.duplicate()
	for x: int in range(1, 7):
		live[_index(x, 3, width)] = 0
	var result: Dictionary = _solve(closed, live, width, height)
	var exposure: PackedByteArray = _exposure(result)
	var previous: int = 256
	for x: int in range(1, 6):
		var current: int = int(exposure[_index(x, 3, width)])
		_assert(current <= previous, "Single-mouth exposure must fall monotonically with distance.")
		previous = current
	_assert(int(exposure[_index(1, 3, width)]) == 255, "Mouth source must begin at full exposure.")
	_assert(int(exposure[_index(5, 3, width)]) == 0, "Exposure must reach zero at the configured reach.")
	_assert(int(exposure[_index(6, 3, width)]) == 0, "Exposure must remain zero beyond the reach.")


func _assert_current_one_tile_tuning_falloff() -> void:
	var width: int = 13
	var height: int = 7
	var closed: PackedByteArray = _closed_rect(width, height, Rect2i(1, 1, 11, 5))
	var live: PackedByteArray = closed.duplicate()
	for x: int in range(1, 11):
		live[_index(x, 3, width)] = 0
	var result: Dictionary = _solve(
		closed,
		live,
		width,
		height,
		CURRENT_TUNING_REACH_SAMPLES,
	)
	var exposure: PackedByteArray = _exposure(result)
	_assert(
		int(result.get("reach_samples", 0)) == CURRENT_TUNING_REACH_SAMPLES,
		"One-tile tuning must publish eight samples at the current 8 px mask step.",
	)
	_assert(int(exposure[_index(1, 3, width)]) == 255, "One-tile mouth must start fully exposed.")
	_assert(int(exposure[_index(8, 3, width)]) > 0, "Exposure must still fade inside one tile.")
	_assert(int(exposure[_index(9, 3, width)]) == 0, "Exposure must reach zero at one tile.")
	_assert(int(exposure[_index(10, 3, width)]) == 0, "Exposure must stay zero beyond one tile.")


func _assert_wider_and_second_mouth_are_monotonic() -> void:
	var width: int = 15
	var height: int = 7
	var closed: PackedByteArray = _closed_rect(width, height, Rect2i(1, 1, 13, 5))
	var one_mouth_live: PackedByteArray = closed.duplicate()
	for x: int in range(1, 12):
		one_mouth_live[_index(x, 3, width)] = 0
	var one_mouth: PackedByteArray = _exposure(
		_solve(closed, one_mouth_live, width, height),
	)

	var wider_live: PackedByteArray = one_mouth_live.duplicate()
	for x: int in range(1, 12):
		wider_live[_index(x, 2, width)] = 0
	var wider: PackedByteArray = _exposure(_solve(closed, wider_live, width, height))
	for x: int in range(1, 12):
		_assert(
			int(wider[_index(x, 3, width)]) >= int(one_mouth[_index(x, 3, width)]),
			"Widening a mouth must not lower existing exposure.",
		)

	var two_mouth_live: PackedByteArray = one_mouth_live.duplicate()
	for x: int in range(12, 14):
		two_mouth_live[_index(x, 3, width)] = 0
	var two_mouth: PackedByteArray = _exposure(_solve(closed, two_mouth_live, width, height))
	for x: int in range(1, 12):
		_assert(
			int(two_mouth[_index(x, 3, width)]) >= int(one_mouth[_index(x, 3, width)]),
			"Adding a second mouth must preserve or raise exposure.",
		)
	_assert(
		int(two_mouth[_index(11, 3, width)]) > int(one_mouth[_index(11, 3, width)]),
		"Second mouth must brighten its local region.",
	)


func _assert_diagonal_corner_does_not_leak() -> void:
	var width: int = 5
	var height: int = 5
	var closed: PackedByteArray = _closed_rect(width, height, Rect2i(1, 1, 3, 3))
	var live: PackedByteArray = closed.duplicate()
	live[_index(1, 1, width)] = 0
	live[_index(2, 2, width)] = 0
	var exposure: PackedByteArray = _exposure(_solve(closed, live, width, height))
	_assert(int(exposure[_index(1, 1, width)]) == 255, "Corner case must retain its real mouth source.")
	_assert(int(exposure[_index(2, 2, width)]) == 0, "Diagonal-only contact must not leak skylight.")


func _assert_halo_windows_match_global_solution() -> void:
	var global_width: int = 24
	var height: int = 7
	var closed: PackedByteArray = _closed_rect(global_width, height, Rect2i(1, 1, 22, 5))
	var live: PackedByteArray = closed.duplicate()
	for x: int in range(1, 23):
		live[_index(x, 3, global_width)] = 0
	closed[_index(12, 3, global_width)] = 0
	live[_index(12, 3, global_width)] = 0

	var global_exposure: PackedByteArray = _exposure(
		_solve(closed, live, global_width, height),
	)
	var window_width: int = 16
	var left_closed: PackedByteArray = _crop_mask(closed, global_width, 0, window_width, height)
	var left_live: PackedByteArray = _crop_mask(live, global_width, 0, window_width, height)
	var right_closed: PackedByteArray = _crop_mask(closed, global_width, 8, window_width, height)
	var right_live: PackedByteArray = _crop_mask(live, global_width, 8, window_width, height)
	var left_exposure: PackedByteArray = _exposure(
		_solve(left_closed, left_live, window_width, height),
	)
	var right_exposure: PackedByteArray = _exposure(
		_solve(right_closed, right_live, window_width, height),
	)
	for y: int in range(height):
		for local_x: int in range(4, 12):
			_assert(
				left_exposure[_index(local_x, y, window_width)] \
						== global_exposure[_index(local_x, y, global_width)],
				"Left halo window must match the global solution in its central output.",
			)
			var global_x: int = local_x + 8
			_assert(
				right_exposure[_index(local_x, y, window_width)] \
						== global_exposure[_index(global_x, y, global_width)],
				"Right halo window must match the global solution in its central output.",
			)


func _assert_determinism_and_invalid_input() -> void:
	var width: int = 9
	var height: int = 7
	var closed: PackedByteArray = _closed_rect(width, height, Rect2i(1, 1, 7, 5))
	var live: PackedByteArray = closed.duplicate()
	for x: int in range(1, 7):
		live[_index(x, 3, width)] = 0
	var first: PackedByteArray = _exposure(_solve(closed, live, width, height))
	var second: PackedByteArray = _exposure(_solve(closed, live, width, height))
	_assert(first == second, "Identical inputs must produce byte-identical exposure.")

	var invalid_variant: Variant = _world_core.call(
		"build_mountain_skylight_exposure",
		closed,
		PackedByteArray([0]),
		width,
		height,
		1.0,
		REACH_SAMPLES,
	)
	_assert(invalid_variant is Dictionary, "Invalid native input must still return a Dictionary.")
	if invalid_variant is Dictionary:
		_assert((invalid_variant as Dictionary).is_empty(), "Invalid native input must fail with an empty result.")


func _assert_static_worker_and_apply_contract() -> void:
	var backend_source: String = FileAccess.get_file_as_string(
		"res://core/systems/world/world_chunk_packet_backend.gd",
	)
	_assert(
		backend_source.contains("if output_valid and construction_roof_requested:"),
		"Zero-dug chunks must keep the legacy path without skylight compute.",
	)
	_assert(
		backend_source.contains("build_mountain_skylight_exposure"),
		"The existing mountain worker must call the native skylight helper.",
	)
	_assert(
		backend_source.contains("const MOUNTAIN_SKYLIGHT_REACH_TILES: int = 1"),
		"The current M8 tuning trial must keep daylight reach at one tile.",
	)
	_assert(
		not backend_source.contains("func _build_mountain_skylight_exposure"),
		"The worker must not contain a GDScript exposure fallback.",
	)

	var chunk_source: String = FileAccess.get_file_as_string(
		"res://core/systems/world/chunk_view.gd",
	)
	_assert(
		chunk_source.contains("_mountain_sky_exposure_texture"),
		"ChunkView must own the derived exposure texture.",
	)
	var reveal_start: int = chunk_source.find("func set_mountain_roof_reveal_blend")
	var reveal_end: int = chunk_source.find("\nfunc ", reveal_start + 5)
	var reveal_source: String = chunk_source.substr(reveal_start, reveal_end - reveal_start)
	_assert(
		not reveal_source.contains("sky_exposure"),
		"Roof reveal blend must not mutate or rebuild sky exposure.",
	)


func _solve(
		closed: PackedByteArray,
		live: PackedByteArray,
		width: int,
		height: int,
		reach_samples: int = REACH_SAMPLES,
) -> Dictionary:
	var result_variant: Variant = _world_core.call(
		"build_mountain_skylight_exposure",
		closed,
		live,
		width,
		height,
		1.0,
		reach_samples,
	)
	_assert(result_variant is Dictionary, "Native skylight helper must return a Dictionary.")
	return result_variant as Dictionary if result_variant is Dictionary else {}


func _exposure(result: Dictionary) -> PackedByteArray:
	return result.get("sky_exposure_mask", PackedByteArray()) as PackedByteArray


func _closed_rect(width: int, height: int, rect: Rect2i) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(width * height)
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			mask[_index(x, y, width)] = 255
	return mask


func _crop_mask(
		source: PackedByteArray,
		source_width: int,
		start_x: int,
		width: int,
		height: int,
) -> PackedByteArray:
	var cropped := PackedByteArray()
	cropped.resize(width * height)
	for y: int in range(height):
		for x: int in range(width):
			cropped[_index(x, y, width)] = source[_index(start_x + x, y, source_width)]
	return cropped


func _index(x: int, y: int, width: int) -> int:
	return y * width + x


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true


func _finish() -> void:
	if not _failed:
		print("mountain_cavity_skylight_mask_smoke_test: OK")
	quit(1 if _failed else 0)
