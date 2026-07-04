extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const MOUNTAIN_SHADER_PATH: String = "res://assets/shaders/mountain_top_mask_underlay.gdshader"
const WORLD_STREAMER_PATH: String = "res://core/systems/world/world_streamer.gd"

var _failed: bool = false


func _init() -> void:
	_assert_mountain_shader_gates_point_lights()
	_assert_mountain_mask_runtime_resolution()

	var mask_width: int = 32
	var mask_height: int = 32
	var mask := PackedByteArray()
	mask.resize(mask_width * mask_height)
	for y: int in range(4, 24):
		for x: int in range(4, 28):
			mask[y * mask_width + x] = 255
	var debug: Dictionary = _build_debug_for_mask(mask, mask_width, mask_height, Vector2.ZERO)
	_assert(int(debug.get("occluder_count", 0)) > 0, "Mountain torch occluders must be built.")
	_assert(
		int(debug.get("closed_count", 0)) == 0,
		"Mountain torch occluders must be open contour segments, not filled rect quads.",
	)
	_assert(
		int(debug.get("max_verts", 0)) > 2,
		"Mountain torch occluders should carry contour polylines instead of two-point stubs only.",
	)

	var crossing_width: int = 96
	var crossing_height: int = 32
	var crossing_mask := PackedByteArray()
	crossing_mask.resize(crossing_width * crossing_height)
	for y: int in range(4, 24):
		for x: int in range(0, crossing_width):
			crossing_mask[y * crossing_width + x] = 255
	var crossing_debug: Dictionary = _build_debug_for_mask(
		crossing_mask,
		crossing_width,
		crossing_height,
		Vector2(-256.0, 0.0),
	)
	_assert(
		int(crossing_debug.get("occluder_count", 0)) > 0,
		"Mountain torch occluders must keep open contour paths that cross chunk borders.",
	)
	_assert(
		int(crossing_debug.get("closed_count", 0)) == 0,
		"Chunk-border contour paths must remain open occluder segments.",
	)

	quit(1 if _failed else 0)


func _build_debug_for_mask(
		mask: PackedByteArray,
		mask_width: int,
		mask_height: int,
		origin_world: Vector2,
) -> Dictionary:
	var view := ChunkView.new()
	root.add_child(view)
	view.configure(Vector2i.ZERO)
	var applied: bool = view.apply_mountain_native_mask_data({
		"mask": mask,
		"width": mask_width,
		"height": mask_height,
		"step_px": 8.0,
		"solid_sample_count": mask_width * mask_height,
		"pixels_per_tile": 8,
	}, origin_world)
	_assert(applied, "ChunkView must accept the synthetic mountain mask.")

	view.set_mountain_light_occluders_enabled(true)
	view.sync_mountain_light_occluders()
	var debug: Dictionary = view.get_mountain_light_occluder_debug_state()
	view.queue_free()
	return debug


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true


func _assert_mountain_shader_gates_point_lights() -> void:
	var shader_source: String = FileAccess.get_file_as_string(MOUNTAIN_SHADER_PATH)
	_assert(
		shader_source.contains("varying float point_light_facade_accept"),
		"Mountain shader must pass facade point-light acceptance from fragment to light pass.",
	)
	_assert(
		shader_source.contains("void light()"),
		"Mountain shader must own the CanvasItem light pass.",
	)
	_assert(
		shader_source.contains("float accept = clamp(point_light_facade_accept"),
		"Mountain shader must gate PointLight2D contribution by facade acceptance.",
	)
	_assert(
		not shader_source.contains("point_light_facade_accept = is_wall ? 1.0 : 0.0"),
		"Mountain shader must not use a binary is_wall point-light gate; runtime mask texels make that visible as stair steps.",
	)
	_assert(
		shader_source.contains("wall_mask"),
		"Mountain shader must expose a smoothed wall/facade mask for lighting and wall blending.",
	)
	_assert(
		shader_source.contains("SHADOW_MODULATE = vec4(1.0)"),
		"Mountain shader must not apply the engine shadow texture to the mountain sprite point-light pass.",
	)
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	_assert(
		chunk_view_source.contains("_smooth_mountain_occluder_polyline"),
		"Mountain torch occluder contour must smooth the traced mask grid; raw orthogonal cell edges show stair steps under the torch.",
	)


func _assert_mountain_mask_runtime_resolution() -> void:
	var streamer_source: String = FileAccess.get_file_as_string(WORLD_STREAMER_PATH)
	_assert(
		streamer_source.contains("const MOUNTAIN_HALO_MASK_PIXELS_PER_TILE: int = 8"),
		"Runtime mountain visual mask must stay at 8 px/tile samples; 4 samples/tile exposes 16px stair steps under torch light.",
	)
