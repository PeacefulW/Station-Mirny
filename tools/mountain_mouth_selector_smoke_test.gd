extends SceneTree

const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "World runtime scene must load for mouth selector test.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	var streamer: Node = scene.get_node_or_null("WorldStreamer")
	_assert(streamer != null, "World runtime must contain WorldStreamer.")
	if streamer == null:
		scene.queue_free()
		await process_frame
		quit(1)
		return
	_assert_wide_horizontal(streamer, 1) # NORTH
	_assert_wide_horizontal(streamer, 4) # SOUTH
	_assert_wide_vertical(streamer, 2) # EAST
	_assert_wide_vertical(streamer, 8) # WEST
	_assert_multi_direction_corner_isolated(streamer)
	_assert_owner_chunk_seam_continues(streamer)
	_assert_wrapped_resolver_distance(streamer)
	_assert_shader_mixed_direction_mapping()
	scene.queue_free()
	await process_frame
	if not _failed:
		print("mountain_mouth_selector_smoke_test: OK")
	quit(1 if _failed else 0)


func _assert_wide_horizontal(streamer: Node, direction_bit: int) -> void:
	var side: int = 7
	var source := PackedByteArray()
	source.resize(side * side)
	for x: int in range(2, 5):
		source[3 * side + x] = direction_bit
	var encoded: PackedByteArray = streamer.call(
		"_encode_mountain_mouth_lateral_continuations",
		source,
		side,
	) as PackedByteArray
	_assert(int(encoded[3 * side + 2]) == (direction_bit | 32), "Wide horizontal mouth first cell must continue positive.")
	_assert(int(encoded[3 * side + 3]) == (direction_bit | 16 | 32), "Wide horizontal mouth middle cell must continue both ways.")
	_assert(int(encoded[3 * side + 4]) == (direction_bit | 16), "Wide horizontal mouth last cell must continue negative.")


func _assert_wide_vertical(streamer: Node, direction_bit: int) -> void:
	var side: int = 7
	var source := PackedByteArray()
	source.resize(side * side)
	for y: int in range(2, 5):
		source[y * side + 3] = direction_bit
	var encoded: PackedByteArray = streamer.call(
		"_encode_mountain_mouth_lateral_continuations",
		source,
		side,
	) as PackedByteArray
	_assert(int(encoded[2 * side + 3]) == (direction_bit | 32), "Wide vertical mouth first cell must continue positive.")
	_assert(int(encoded[3 * side + 3]) == (direction_bit | 16 | 32), "Wide vertical mouth middle cell must continue both ways.")
	_assert(int(encoded[4 * side + 3]) == (direction_bit | 16), "Wide vertical mouth last cell must continue negative.")


func _assert_multi_direction_corner_isolated(streamer: Node) -> void:
	var side: int = 5
	var source := PackedByteArray()
	source.resize(side * side)
	var center: int = 2 * side + 2
	source[center] = 2 | 4 # EAST + SOUTH organic corner
	source[center - 1] = 4
	source[center + side] = 2
	var encoded: PackedByteArray = streamer.call(
		"_encode_mountain_mouth_lateral_continuations",
		source,
		side,
	) as PackedByteArray
	_assert(
		int(encoded[center]) == (2 | 4),
		"Multi-direction corner must not inherit shared continuation bits.",
	)


func _assert_owner_chunk_seam_continues(streamer: Node) -> void:
	var side: int = 32
	var target_chunk := Vector2i(1, 1)
	var west_mask := PackedByteArray()
	var owner_mask := PackedByteArray()
	west_mask.resize(16 * 16)
	owner_mask.resize(16 * 16)
	west_mask[8 * 16 + 15] = 1
	owner_mask[8 * 16] = 1
	var source_masks: Dictionary = {
		Vector2i(0, 1): west_mask,
		Vector2i(1, 1): owner_mask,
	}
	var copied: PackedByteArray = streamer.call(
		"_build_cover_tile_visibility_halo",
		target_chunk,
		source_masks,
		true,
	) as PackedByteArray
	# With radius 8, target local x=-1/0 lands at selector x=7/8. This proves
	# the real 3x3 source-copy path before testing continuation encoding.
	var left: int = 16 * side + 7
	var right: int = left + 1
	_assert(int(copied[left]) == 1, "West source chunk mouth must copy to halo x=7.")
	_assert(int(copied[right]) == 1, "Owner chunk mouth must copy to halo x=8.")
	var source := PackedByteArray()
	source.resize(side * side)
	source[left] = 4
	source[right] = 4
	var encoded: PackedByteArray = streamer.call(
		"_encode_mountain_mouth_lateral_continuations",
		source,
		side,
	) as PackedByteArray
	_assert(int(encoded[left]) == (4 | 32), "Mouth must continue across owner chunk seam.")
	_assert(int(encoded[right]) == (4 | 16), "Owner seam neighbour must continue back.")


func _assert_wrapped_resolver_distance(streamer: Node) -> void:
	var bounds: Resource = streamer.get("_world_bounds_settings") as Resource
	var width_tiles: int = int(bounds.get("width_tiles"))
	var width_px: float = float(width_tiles * 64)
	var seam_distance_sq: float = float(streamer.call(
		"_wrapped_distance_squared_to_tile_center",
		Vector2(1.0, 32.0),
		Vector2i(width_tiles - 1, 0),
	))
	_assert(
		is_equal_approx(seam_distance_sq, 33.0 * 33.0),
		"Organic resolver distance must wrap X instead of crossing full world width (%.1f)." % seam_distance_sq,
	)
	_assert(seam_distance_sq < width_px, "Wrapped seam distance must stay local.")


func _assert_shader_mixed_direction_mapping() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://assets/shaders/mountain_top_mask_underlay.gdshader",
	)
	for contract: String in [
		"north_negative = selector_has_bit(left_code, 1.0)",
		"north_positive = selector_has_bit(right_code, 1.0)",
		"south_negative = selector_has_bit(left_code, 4.0)",
		"south_positive = selector_has_bit(right_code, 4.0)",
		"east_negative = selector_has_bit(up_code, 2.0)",
		"east_positive = selector_has_bit(down_code, 2.0)",
		"west_negative = selector_has_bit(up_code, 8.0)",
		"west_positive = selector_has_bit(down_code, 8.0)",
	]:
		_assert(source.contains(contract), "Shader mixed-mouth mapping missing: %s" % contract)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
