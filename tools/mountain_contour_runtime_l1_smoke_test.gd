extends SceneTree

const MountainContourCollisionCache = preload("res://core/systems/world/mountain_contour_collision_cache.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const REQUIRED_FIELDS: Array[String] = [
	"ready",
	"chunk_size",
	"tile_size_px",
	"halo_side",
	"solid_sample_count",
	"visual_top_vertices",
	"visual_top_indices",
	"visual_top_attributes",
	"visual_face_vertices",
	"visual_face_indices",
	"visual_face_attributes",
	"visual_rim_vertices",
	"visual_rim_indices",
	"visual_rim_attributes",
	"visual_outline_vertices",
	"visual_outline_indices",
	"visual_outline_attributes",
	"collision_loops",
	"collision_aabbs",
	"boundary_edge_count",
	"seam_touch_mask",
	"compute_time_usec",
]

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()

	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for production mountain contour runtime checks.")
	if world_core == null:
		quit(1)
		return
	_assert(world_core.has_method("build_mountain_contour_debug"), "Debug contour helper must remain bound for compatibility.")
	_assert(world_core.has_method("build_mountain_contour_runtime"), "WorldCore must bind build_mountain_contour_runtime().")
	if not world_core.has_method("build_mountain_contour_runtime"):
		quit(1)
		return

	_assert_empty_result_shape(world_core)
	_assert_single_tile_result(world_core)
	_assert_two_by_two_blob_result(world_core)
	_assert_diagonal_contact_stays_separate(world_core)
	_assert_inner_hole_result(world_core)
	_assert_chunk_edge_opening_collision_passes(world_core)
	_assert_seam_touch_mask(world_core)
	_assert_deterministic_result(world_core)

	if _failed:
		quit(1)
		return
	print("mountain_contour_runtime_l1_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var world_core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	var contour_source: String = FileAccess.get_file_as_string("res://gdextension/src/mountain_contour.cpp")
	_assert(world_core_source.contains("build_mountain_contour_runtime"), "WorldCore must expose the production runtime contour helper.")
	_assert(world_core_source.contains("build_mountain_contour_debug"), "Task 3 must keep the debug contour helper until cutover.")
	_assert(contour_source.contains("build_runtime_result"), "mountain_contour.cpp must own production contour runtime generation.")
	_assert(
		not contour_source.contains("append_top_tile(top_vertices"),
		"Runtime top contour must not render one square top quad per solid tile."
	)
	_assert(not contour_source.contains("void append_top_tile("), "Runtime visual code must not keep tile-top quad helpers in the production contour file.")
	_assert(not contour_source.contains("void append_south_face("), "Runtime visual code must not keep south-face tile rectangle helpers in the production contour file.")
	_assert(not contour_source.contains("void append_south_outline("), "Runtime visual code must not keep south-outline tile rectangle helpers in the production contour file.")
	_assert(not contour_source.contains("void append_rim_edge("), "Runtime visual code must not keep per-tile rim rectangle helpers in the production contour file.")
	_assert(contour_source.contains("edge_u"), "Runtime contour attributes must include edge_u.")
	_assert(contour_source.contains("edge_v"), "Runtime contour attributes must include edge_v.")
	_assert(contour_source.contains("signed_distance"), "Runtime contour attributes must include signed_distance.")
	_assert(contour_source.contains("face_depth_px"), "Runtime contour attributes must include face_depth_px.")
	_assert(contour_source.contains("facade_side"), "Runtime contour attributes must include facade_side.")
	_assert(contour_source.contains("zone"), "Runtime contour attributes must include zone.")
	_assert(contour_source.contains("corner_round_px"), "Runtime contour builder must consume corner_round_px from the style package.")
	_assert(contour_source.contains("diagonal_smooth_px"), "Runtime contour builder must consume diagonal_smooth_px from the style package.")
	_assert(not contour_source.contains("mask_rgba8"), "Runtime contour result must not allocate per-chunk mask image bytes.")
	_assert(not contour_source.contains("height_r16"), "Runtime contour result must not allocate per-chunk height image bytes.")
	_assert(not contour_source.contains("normal_rgba8"), "Runtime contour result must not allocate per-chunk normal image bytes.")

	var packet_schema_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/packet_schemas.md")
	_assert(packet_schema_source.contains("MountainContourRuntimeResultV1"), "packet_schemas.md must document MountainContourRuntimeResultV1.")

func _assert_empty_result_shape(world_core: Object) -> void:
	var result: Dictionary = _call_runtime(world_core, _build_constant_halo(0))
	_assert_required_shape(result, "empty")
	_assert(bool(result.get("ready", false)), "Empty runtime result must be ready.")
	_assert(int(result.get("solid_sample_count", -1)) == 0, "Empty runtime result must count zero solid samples.")
	_assert((result.get("visual_top_vertices", PackedVector2Array()) as PackedVector2Array).is_empty(), "Empty runtime result must not emit top vertices.")
	_assert((result.get("collision_loops", []) as Array).is_empty(), "Empty runtime result must not emit collision loops.")

func _assert_single_tile_result(world_core: Object) -> void:
	var halo := _build_constant_halo(0)
	_set_local_cell(halo, 8, 8, 1)
	var result: Dictionary = _call_runtime(world_core, halo)
	_assert_required_shape(result, "single tile")
	_assert(int(result.get("solid_sample_count", 0)) == 1, "Single-tile result must count one solid sample.")
	_assert((result.get("visual_top_vertices", PackedVector2Array()) as PackedVector2Array).size() >= 4, "Single tile must emit top mesh vertices.")
	_assert(
		_has_off_tile_grid_contour_vertex(result.get("visual_top_vertices", PackedVector2Array()) as PackedVector2Array),
		"Single tile runtime top contour must include SDF-interpolated vertices instead of only square tile corners."
	)
	_assert((result.get("visual_face_vertices", PackedVector2Array()) as PackedVector2Array).size() >= 4, "Single tile must emit south face mesh vertices.")
	_assert((result.get("visual_rim_vertices", PackedVector2Array()) as PackedVector2Array).size() >= 4, "Single tile must emit rim mesh vertices.")
	_assert((result.get("visual_outline_vertices", PackedVector2Array()) as PackedVector2Array).size() >= 4, "Single tile must emit bottom outline mesh vertices when style enables outline.")
	_assert_collision_triangles_match_top_mesh(result, "Single tile")
	_assert(_attributes_match_vertices(result, "visual_top"), "Top custom attributes must match top vertex count.")
	_assert(_attributes_match_vertices(result, "visual_face"), "Face custom attributes must match face vertex count.")
	_assert(_attributes_match_vertices(result, "visual_rim"), "Rim custom attributes must match rim vertex count.")
	_assert(_attributes_match_vertices(result, "visual_outline"), "Outline custom attributes must match outline vertex count.")

func _assert_two_by_two_blob_result(world_core: Object) -> void:
	var halo := _build_constant_halo(0)
	for y: int in range(7, 9):
		for x: int in range(7, 9):
			_set_local_cell(halo, x, y, 1)
	var result: Dictionary = _call_runtime(world_core, halo)
	_assert_required_shape(result, "2x2 blob")
	_assert(int(result.get("solid_sample_count", 0)) == 4, "2x2 blob must count four solid samples.")
	_assert_collision_triangles_match_top_mesh(result, "2x2 blob")
	_assert(int(result.get("boundary_edge_count", 0)) == 8, "2x2 blob must expose eight boundary edges.")

func _assert_diagonal_contact_stays_separate(world_core: Object) -> void:
	var halo := _build_constant_halo(0)
	_set_local_cell(halo, 7, 7, 1)
	_set_local_cell(halo, 8, 8, 1)
	var result: Dictionary = _call_runtime(world_core, halo)
	_assert_required_shape(result, "diagonal contact")
	_assert_collision_triangles_match_top_mesh(result, "Diagonal-only contact")

func _assert_inner_hole_result(world_core: Object) -> void:
	var halo := _build_constant_halo(0)
	for y: int in range(6, 11):
		for x: int in range(6, 11):
			if x == 8 and y == 8:
				continue
			_set_local_cell(halo, x, y, 1)
	var result: Dictionary = _call_runtime(world_core, halo)
	_assert_required_shape(result, "inner hole")
	_assert(int(result.get("solid_sample_count", 0)) == 24, "Inner-hole fixture must count every solid sample except the hole.")
	_assert(int(result.get("boundary_edge_count", 0)) > 20, "Inner-hole fixture must expose both outer and inner boundary edges.")

func _assert_chunk_edge_opening_collision_passes(world_core: Object) -> void:
	var halo := _build_constant_halo(0)
	for y: int in range(4, 16):
		for x: int in range(4, 16):
			if x >= 8 and y >= 10:
				continue
			_set_local_cell(halo, x, y, 1)
	var result: Dictionary = _call_runtime(world_core, halo)
	_assert_required_shape(result, "chunk edge opening")
	var cache := MountainContourCollisionCache.new()
	cache.configure(
		Vector2i.ZERO,
		result.get("collision_loops", []) as Array,
		result.get("collision_aabbs", []) as Array
	)
	var passable_opening := Vector2(12.5, 14.5) * float(WorldRuntimeConstants.TILE_SIZE_PX)
	var blocked_mountain := Vector2(5.5, 5.5) * float(WorldRuntimeConstants.TILE_SIZE_PX)
	_assert(
		not cache.is_capsule_blocked(passable_opening, 16.0),
		"Chunk-edge carved opening must remain passable; collision must not close it into a hidden seam wall."
	)
	_assert(
		cache.is_capsule_blocked(blocked_mountain, 16.0),
		"Chunk-edge opening fixture must still block inside actual contour mountain geometry."
	)

func _assert_seam_touch_mask(world_core: Object) -> void:
	var halo := _build_constant_halo(0)
	_set_local_cell(halo, 0, 4, 1)
	_set_local_cell(halo, 15, 6, 1)
	_set_local_cell(halo, 7, 0, 1)
	_set_local_cell(halo, 9, 15, 1)
	var result: Dictionary = _call_runtime(world_core, halo)
	_assert_required_shape(result, "seam touch")
	var seam_touch_mask: int = int(result.get("seam_touch_mask", 0))
	_assert((seam_touch_mask & 1) != 0, "Seam touch mask must include west edge.")
	_assert((seam_touch_mask & 2) != 0, "Seam touch mask must include east edge.")
	_assert((seam_touch_mask & 4) != 0, "Seam touch mask must include north edge.")
	_assert((seam_touch_mask & 8) != 0, "Seam touch mask must include south edge.")

func _assert_deterministic_result(world_core: Object) -> void:
	var halo := _build_constant_halo(0)
	_set_local_cell(halo, 7, 7, 1)
	_set_local_cell(halo, 8, 7, 1)
	_set_local_cell(halo, 8, 8, 1)
	var first: Dictionary = _call_runtime(world_core, halo)
	var second: Dictionary = _call_runtime(world_core, halo)
	_assert(_packed_vec2_equal(first.get("visual_top_vertices", PackedVector2Array()), second.get("visual_top_vertices", PackedVector2Array())), "Runtime contour top vertices must be deterministic.")
	_assert(_packed_i32_equal(first.get("visual_top_indices", PackedInt32Array()), second.get("visual_top_indices", PackedInt32Array())), "Runtime contour top indices must be deterministic.")
	_assert(_collision_loop_count(first) == _collision_loop_count(second), "Runtime contour collision loop count must be deterministic.")

func _call_runtime(world_core: Object, solid_halo: PackedByteArray) -> Dictionary:
	var result_variant: Variant = world_core.call(
		"build_mountain_contour_runtime",
		solid_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		_style_params()
	)
	_assert(result_variant is Dictionary, "build_mountain_contour_runtime() must return Dictionary.")
	if result_variant is Dictionary:
		return result_variant as Dictionary
	return {}

func _assert_required_shape(result: Dictionary, label: String) -> void:
	for field_name: String in REQUIRED_FIELDS:
		_assert(result.has(field_name), "%s runtime result missing field: %s" % [label, field_name])
	_assert(int(result.get("chunk_size", 0)) == WorldRuntimeConstants.CHUNK_SIZE, "%s chunk_size must match runtime constants." % [label])
	_assert(int(result.get("tile_size_px", 0)) == WorldRuntimeConstants.TILE_SIZE_PX, "%s tile_size_px must match runtime constants." % [label])
	_assert(int(result.get("halo_side", 0)) == WorldRuntimeConstants.CHUNK_SIZE + 2, "%s halo_side must match one-tile halo." % [label])
	_assert(result.get("visual_top_vertices", null) is PackedVector2Array, "%s top vertices must be PackedVector2Array." % [label])
	_assert(result.get("visual_top_indices", null) is PackedInt32Array, "%s top indices must be PackedInt32Array." % [label])
	_assert(result.get("visual_top_attributes", null) is PackedFloat32Array, "%s top attributes must be PackedFloat32Array." % [label])
	_assert(result.get("collision_loops", null) is Array, "%s collision loops must be Array." % [label])
	_assert(result.get("collision_aabbs", null) is Array, "%s collision AABBs must be Array." % [label])
	_assert(not result.has("mask_rgba8"), "%s result must not include image mask bytes." % [label])
	_assert(not result.has("height_r16"), "%s result must not include image height bytes." % [label])
	_assert(not result.has("normal_rgba8"), "%s result must not include image normal bytes." % [label])

func _style_params() -> Dictionary:
	return {
		"south_height_px": 32.0,
		"side_height_px": 16.0,
		"corner_round_px": 16.0,
		"diagonal_smooth_px": 32.0,
		"contour_warp_px": 0.75,
		"rim_width_px": 8.0,
		"mountain_outline_enabled": true,
		"mountain_outline_width_px": 3.0,
	}

func _build_constant_halo(value: int) -> PackedByteArray:
	var side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	var solid_halo := PackedByteArray()
	solid_halo.resize(side * side)
	for index: int in solid_halo.size():
		solid_halo[index] = value
	return solid_halo

func _set_local_cell(solid_halo: PackedByteArray, local_x: int, local_y: int, value: int) -> void:
	var side: int = WorldRuntimeConstants.CHUNK_SIZE + 2
	solid_halo[(local_y + 1) * side + local_x + 1] = value

func _attributes_match_vertices(result: Dictionary, prefix: String) -> bool:
	var vertices: PackedVector2Array = result.get("%s_vertices" % [prefix], PackedVector2Array()) as PackedVector2Array
	var attributes: PackedFloat32Array = result.get("%s_attributes" % [prefix], PackedFloat32Array()) as PackedFloat32Array
	return attributes.size() == vertices.size() * 8

func _collision_loop_count(result: Dictionary) -> int:
	return (result.get("collision_loops", []) as Array).size()

func _assert_collision_triangles_match_top_mesh(result: Dictionary, label: String) -> void:
	var top_indices: PackedInt32Array = result.get("visual_top_indices", PackedInt32Array()) as PackedInt32Array
	var collision_loops: Array = result.get("collision_loops", []) as Array
	_assert(top_indices.size() > 0, "%s must emit top mesh indices." % [label])
	_assert(
		collision_loops.size() == top_indices.size() / 3,
		"%s collision loops must mirror filled top mesh triangles so chunk-edge openings do not require closed boundary loops." % [label]
	)

func _has_off_tile_grid_contour_vertex(vertices: PackedVector2Array) -> bool:
	for vertex: Vector2 in vertices:
		var mod_x: float = fposmod(vertex.x, float(WorldRuntimeConstants.TILE_SIZE_PX))
		var mod_y: float = fposmod(vertex.y, float(WorldRuntimeConstants.TILE_SIZE_PX))
		if not (is_equal_approx(mod_x, 0.0) or is_equal_approx(mod_x, float(WorldRuntimeConstants.TILE_SIZE_PX))) \
				or not (is_equal_approx(mod_y, 0.0) or is_equal_approx(mod_y, float(WorldRuntimeConstants.TILE_SIZE_PX))):
			return true
	return false

func _packed_vec2_equal(lhs_variant: Variant, rhs_variant: Variant) -> bool:
	var lhs: PackedVector2Array = lhs_variant as PackedVector2Array
	var rhs: PackedVector2Array = rhs_variant as PackedVector2Array
	if lhs.size() != rhs.size():
		return false
	for index: int in lhs.size():
		if lhs[index] != rhs[index]:
			return false
	return true

func _packed_i32_equal(lhs_variant: Variant, rhs_variant: Variant) -> bool:
	var lhs: PackedInt32Array = lhs_variant as PackedInt32Array
	var rhs: PackedInt32Array = rhs_variant as PackedInt32Array
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
