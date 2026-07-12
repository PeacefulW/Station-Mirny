extends SceneTree

const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const ChunkView = preload("res://core/systems/world/chunk_view.gd")

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
	_assert_owner_x_wrap_seam_continues(streamer)
	_assert_wrapped_resolver_distance(streamer)
	_assert_projected_metadata_all_cardinals()
	_assert_active_component_excludes_neighbor_and_island()
	_assert_shader_facade_contract()
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
		0,
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


func _assert_owner_x_wrap_seam_continues(streamer: Node) -> void:
	var bounds: Resource = streamer.get("_world_bounds_settings") as Resource
	var width_tiles: int = int(bounds.get("width_tiles"))
	var chunks_x: int = width_tiles / 16
	_assert(chunks_x > 1, "X-wrap mouth fixture requires at least two world chunks.")
	if chunks_x <= 1:
		return
	var side: int = 32
	var target_chunk := Vector2i(0, 1)
	var wrapped_west_chunk := Vector2i(chunks_x - 1, 1)
	var west_mask := PackedByteArray()
	var owner_mask := PackedByteArray()
	west_mask.resize(16 * 16)
	owner_mask.resize(16 * 16)
	west_mask[8 * 16 + 15] = 1
	owner_mask[8 * 16] = 1
	var source_masks: Dictionary = {
		wrapped_west_chunk: west_mask,
		target_chunk: owner_mask,
	}
	var copied: PackedByteArray = streamer.call(
		"_build_cover_tile_visibility_halo",
		target_chunk,
		source_masks,
		true,
		0,
	) as PackedByteArray
	var left: int = 16 * side + 7
	var right: int = left + 1
	_assert(int(copied[left]) == 1, "Wrapped west-world mouth must copy to halo x=7.")
	_assert(int(copied[right]) == 1, "Wrapped owner mouth must copy to halo x=8.")
	var source := PackedByteArray()
	source.resize(side * side)
	source[left] = 4
	source[right] = 4
	var encoded: PackedByteArray = streamer.call(
		"_encode_mountain_mouth_lateral_continuations",
		source,
		side,
	) as PackedByteArray
	_assert(int(encoded[left]) == (4 | 32), "Mouth must continue across the X-wrap seam.")
	_assert(int(encoded[right]) == (4 | 16), "X-wrap owner neighbour must continue back.")


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


func _assert_projected_metadata_all_cardinals() -> void:
	var view: ChunkView = ChunkView.new()
	var side: int = 9
	var center := Vector2i(4, 4)
	var fixtures: Array[Dictionary] = [
		{"bit": 1, "outward": Vector2i.UP},
		{"bit": 2, "outward": Vector2i.RIGHT},
		{"bit": 4, "outward": Vector2i.DOWN},
		{"bit": 8, "outward": Vector2i.LEFT},
	]
	for fixture: Dictionary in fixtures:
		var direction_bit: int = int(fixture.get("bit", 0))
		var outward: Vector2i = fixture.get("outward", Vector2i.ZERO) as Vector2i
		var source := PackedByteArray()
		source.resize(side * side)
		var source_index: int = center.y * side + center.x
		var source_code: int = direction_bit | 16 | 32
		source[source_index] = source_code
		var projected: PackedByteArray = view.call(
			"_build_projected_physical_mouth_halo",
			source,
			side,
		) as PackedByteArray
		var target: Vector2i = center + outward
		var target_index: int = target.y * side + target.x
		_assert(
			int(projected[source_index]) == source_code,
			"Physical mouth metadata must preserve cardinal source code %d." % direction_bit,
		)
		_assert(
			int(projected[target_index]) == (source_code | 64),
			"Physical mouth metadata must project cardinal code %d outward once." % direction_bit,
		)
		var second: Vector2i = target + outward
		_assert(
			int(projected[second.y * side + second.x]) == 0,
			"Physical mouth metadata must not project cardinal code %d twice." % direction_bit,
		)
	view.free()


func _assert_active_component_excludes_neighbor_and_island() -> void:
	var view: ChunkView = ChunkView.new()
	var side: int = 9
	var active_component := PackedByteArray()
	var outside_mouth_metadata := PackedByteArray()
	active_component.resize(side * side)
	outside_mouth_metadata.resize(side * side)
	for y: int in range(2, 7):
		for x: int in range(2, 7):
			active_component[y * side + x] = 1
	var retained_island := Vector2i(4, 4)
	var neighboring_cavity := Vector2i(7, 4)
	active_component[retained_island.y * side + retained_island.x] = 0
	# Give the neighboring cavity a physical mouth code: facade metadata must
	# still never union it into the active roof component.
	outside_mouth_metadata[neighboring_cavity.y * side + neighboring_cavity.x] = 4
	var closed_stub := PackedByteArray()
	closed_stub.append(255)
	view.set("_mountain_closed_roof_mask_bytes", closed_stub)
	view.set("_mountain_dug_halo_side", side)
	_assert(
		view.apply_mountain_roof_reveal_halo(active_component, outside_mouth_metadata),
		"Active component fixture must publish its selector.",
	)
	var reveal: PackedByteArray = view.call("_build_mountain_roof_reveal_mask") as PackedByteArray
	_assert(reveal.size() == side * side, "Active component reveal must retain halo shape.")
	if reveal.size() == side * side:
		_assert(
			int(reveal[3 * side + 3]) == 255,
			"Selected connected cavity must be present in roof reveal.",
		)
		_assert(
			int(reveal[retained_island.y * side + retained_island.x]) == 0,
			"Retained mountain island must stay roof-covered.",
		)
		_assert(
			int(reveal[neighboring_cavity.y * side + neighboring_cavity.x]) == 0,
			"Neighboring cavity and its mouth metadata must stay roof-covered.",
		)
	view.free()


func _assert_shader_facade_contract() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://assets/shaders/mountain_top_mask_underlay.gdshader",
	)
	for contract: String in [
		"uniform sampler2D physical_mouth_aperture_texture : filter_linear",
		"uniform float physical_mouth_aperture_enabled = 0.0",
		"uniform float component_reveal_blend = 0.0",
		"return texture(closed_mask_texture, uv).r",
		"float mouth_unwarp = sample_physical_mouth_unwarp(UV) * (1.0 - overlay_mode)",
		"out_alpha *= 1.0 - clamp(displayed_weight * component_reveal_blend, 0.0, 1.0)",
	]:
		_assert(source.contains(contract), "Shader facade contract missing: %s" % contract)
	for removed_contract: String in [
		"mouth_direction_signed_distance",
		"sample_physical_mouth_signed_distance",
		"mouth_portal_",
		"physical_mouth_halo_texture",
		"remaining_mask_texture",
	]:
		_assert(
			not source.contains(removed_contract),
			"Removed procedural roof-mouth contract returned: %s" % removed_contract,
		)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
