extends SceneTree

const CHUNK_VIEW_PATH: String = "res://core/systems/world/chunk_view.gd"
const NATIVE_CONTOUR_PATH: String = "res://gdextension/src/mountain_contour.cpp"
const VISUAL_LAYER_PATH: String = "res://core/systems/world/mountain_contour_visual_layer.gd"
const SHADER_PATH: String = "res://assets/shaders/mountain_contour_runtime.gdshader"
const SPEC_PATH: String = "res://docs/02_system_specs/world/mountain_contour_runtime_v2.md"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var chunk_view_source: String = FileAccess.get_file_as_string(CHUNK_VIEW_PATH)
	var native_source: String = FileAccess.get_file_as_string(NATIVE_CONTOUR_PATH)
	var visual_layer_source: String = FileAccess.get_file_as_string(VISUAL_LAYER_PATH)
	var shader_source: String = FileAccess.get_file_as_string(SHADER_PATH)
	var spec_source: String = FileAccess.get_file_as_string(SPEC_PATH)

	_assert(chunk_view_source.contains("MOUNTAIN_CONTOUR_VISUAL_CUTOVER_ACCEPTED"), "ChunkView must expose an explicit visual cutover acceptance gate.")
	_assert(
		chunk_view_source.contains("const MOUNTAIN_CONTOUR_VISUAL_CUTOVER_ACCEPTED: bool = false"),
		"Live gameplay cutover must stay disabled until strict real-render parity is accepted."
	)
	_assert(chunk_view_source.contains("return MOUNTAIN_CONTOUR_VISUAL_CUTOVER_ACCEPTED"), "ChunkView cutover policy must use the explicit acceptance gate.")
	_assert(chunk_view_source.contains("resolved_runtime_visible"), "ChunkView must hide the contour visual layer when cutover is not accepted.")
	_assert(chunk_view_source.contains("\"visual_cutover_accepted\""), "ChunkView debug stats must report whether visual cutover is accepted.")
	_assert(chunk_view_source.contains("\"visual_cutover_blocked_reason\""), "ChunkView debug stats must report why visual cutover is blocked.")
	_assert(not native_source.contains("void append_top_tile("), "Production native contour visual must not keep tile-top quad helpers.")
	_assert(not native_source.contains("void append_south_face("), "Production native contour visual must not keep south-face tile rectangle helpers.")
	_assert(not native_source.contains("void append_south_outline("), "Production native contour visual must not keep south-outline tile rectangle helpers.")
	_assert(not native_source.contains("void append_rim_edge("), "Production native contour visual must not keep per-tile rim rectangle helpers.")
	_assert(native_source.contains("ATTRIBUTE_STRIDE = 8") or native_source.contains("ATTRIBUTE_STRIDE = 8;"), "Native contour attributes must use eight floats per vertex.")
	_assert(visual_layer_source.contains("const ATTRIBUTE_STRIDE: int = 8"), "Visual layer must decode eight native contour attributes per vertex.")
	_assert(shader_source.contains("edge_u"), "Runtime shader must read edge_u from mesh attributes.")
	_assert(shader_source.contains("edge_v"), "Runtime shader must read edge_v from mesh attributes.")
	_assert(shader_source.contains("signed_distance"), "Runtime shader must read signed_distance from mesh attributes.")
	_assert(shader_source.contains("face_depth_px"), "Runtime shader must read face_depth_px from mesh attributes.")
	_assert(shader_source.contains("facade_side"), "Runtime shader must read facade_side from mesh attributes.")
	_assert(spec_source.contains("Task 11R") and spec_source.contains("Visual Parity Rescue"), "Canonical spec must document the Task 11R rescue gate.")
	_assert(spec_source.contains("live gameplay cutover disabled"), "Canonical spec must state that live gameplay cutover is disabled until strict parity is accepted.")
	for required_attr: String in ["edge_u", "edge_v", "signed_distance", "face_depth_px", "facade_side", "zone"]:
		_assert(spec_source.contains(required_attr), "Canonical spec must name the required contour shader attribute `%s`." % [required_attr])
	quit(1 if _failed else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
