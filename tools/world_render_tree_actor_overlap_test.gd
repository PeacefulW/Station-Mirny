extends Node2D
## Windowed proof that one authored tree and Player share the native painter
## order at both supported zoom extremes.

const WorldLayeredObjectAssetCatalog = preload(
	"res://core/systems/world/world_layered_object_asset_catalog.gd"
)
const WorldRenderClassRegistry = preload(
	"res://core/systems/world/world_render_class_registry.gd"
)
const BODY_SHADER: Shader = preload("res://assets/shaders/world_render_body.gdshader")
const GPU_STRIDE: int = 16
const TREE_FEET_Y: float = 100.0
const PLAYER_X: float = 24.0
const PLAYER_FEET_OFFSET_PX: float = 38.4
const PLAYER_FRAME_SIZE := Vector2(208.0, 288.0)
const SAMPLE_HALF_EXTENT: int = 96
const REPORT_PATH: String = "user://world_render_tree_actor_overlap.txt"
## Distinct from both 0 (verified) and 1 (regression): the proof did not run.
const SKIP_EXIT_CODE: int = 2

var _world_core: Object = null
var _catalog: WorldLayeredObjectAssetCatalog = null
var _registry: WorldRenderClassRegistry = null
var _material: ShaderMaterial = null
var _multimesh: MultiMesh = null
var _probe_viewport: SubViewport = null
var _camera: Camera2D = null
var _cases: Array[Dictionary] = [
	{"label": "north_zoom_1_0", "feet_y": 90.0, "zoom": 1.0, "top": "tree"},
	{"label": "south_zoom_1_0", "feet_y": 110.0, "zoom": 1.0, "top": "actor"},
	{"label": "north_zoom_0_2", "feet_y": 90.0, "zoom": 0.2, "top": "tree"},
	{"label": "south_zoom_0_2", "feet_y": 110.0, "zoom": 0.2, "top": "actor"},
]
var _case_index: int = 0
var _capture_stage: int = 0
var _frames: int = 0
var _tree_image: Image = null
var _actor_image: Image = null
var _failed: bool = false
var _skipped: bool = false
var _lines := PackedStringArray()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		# This proof needs a real framebuffer. Reporting it as PASS would make an
		# unrun contract indistinguishable from a verified one.
		_skipped = true
		_say("world_render_tree_actor_overlap_test: SKIP headless framebuffer")
		_finish.call_deferred()
		return
	if not ClassDB.class_exists(&"WorldCore"):
		_fail("native WorldCore is unavailable")
		_finish.call_deferred()
		return
	_world_core = ClassDB.instantiate(&"WorldCore")
	_catalog = WorldLayeredObjectAssetCatalog.new()
	_registry = WorldRenderClassRegistry.new()
	if _world_core == null or not _catalog.is_ready() or not _registry.configure():
		_fail("production renderer sources are unavailable")
		_finish.call_deferred()
		return
	_prepare_render_target()
	_prepare_material_and_mesh()
	_configure_case()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % 8 != 0:
		return
	var current_case: Dictionary = _cases[_case_index]
	var label: String = str(current_case.get("label", "case"))
	match _capture_stage:
		0:
			_tree_image = _capture("%s_tree" % label)
			_set_profile_visibility(false, true)
			_capture_stage = 1
		1:
			_actor_image = _capture("%s_actor" % label)
			_set_profile_visibility(true, true)
			_capture_stage = 2
		2:
			_analyze_case(current_case, _tree_image, _actor_image, _capture("%s_combined" % label))
			_case_index += 1
			if _case_index >= _cases.size():
				_finish()
				return
			_capture_stage = 0
			_configure_case()


func _prepare_render_target() -> void:
	_probe_viewport = SubViewport.new()
	_probe_viewport.name = "TreeActorOverlapViewport"
	_probe_viewport.size = Vector2i(512, 512)
	_probe_viewport.disable_3d = true
	_probe_viewport.transparent_bg = true
	_probe_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_probe_viewport)
	var world := Node2D.new()
	world.name = "World"
	_probe_viewport.add_child(world)
	_camera = Camera2D.new()
	_camera.position = Vector2(0.0, TREE_FEET_Y)
	world.add_child(_camera)
	_camera.make_current()
	var holder := MultiMeshInstance2D.new()
	holder.name = "SharedTreeActorBodyPage"
	world.add_child(holder)
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	_multimesh.mesh = mesh
	holder.multimesh = _multimesh
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _prepare_material_and_mesh() -> void:
	_material = ShaderMaterial.new()
	_material.shader = BODY_SHADER
	_material.set_shader_parameter("world_body_base_atlas", _registry.get_texture(&"body_base"))
	_material.set_shader_parameter("world_foliage_atlas", _registry.get_texture(&"foliage"))
	_material.set_shader_parameter("world_snow_overlay_atlas", _registry.get_texture(&"snow_overlay"))
	_material.set_shader_parameter("world_wind_mask_atlas", _registry.get_texture(&"wind_mask"))
	_material.set_shader_parameter("world_snow_mask_atlas", _registry.get_texture(&"snow_mask"))
	_material.set_shader_parameter("world_season_mask_atlas", _registry.get_texture(&"season_mask"))
	_material.set_shader_parameter("actor_body_atlas", _registry.get_texture(&"actor_body"))
	_material.set_shader_parameter("render_descriptor_lut", _registry.get_descriptor_lut())
	_material.set_shader_parameter("render_variant_crop_lut", _registry.get_variant_crop_lut())
	_material.set_shader_parameter("season_amount", 0.0)
	var holder: MultiMeshInstance2D = _probe_viewport.get_node("World/SharedTreeActorBodyPage") \
			as MultiMeshInstance2D
	holder.material = _material


func _configure_case() -> void:
	var current_case: Dictionary = _cases[_case_index]
	var feet_y: float = float(current_case.get("feet_y", TREE_FEET_Y))
	var zoom: float = float(current_case.get("zoom", 1.0))
	_camera.zoom = Vector2(zoom, zoom)
	var composed_variant: Variant = _world_core.call(
		"compose_world_render_actors",
		_static_tree_snapshot(),
		[_actor_record(feet_y)],
	)
	if not composed_variant is Dictionary:
		_fail("%s composer returned a non-Dictionary" % str(current_case.get("label")))
		return
	var composed: Dictionary = composed_variant as Dictionary
	if not bool(composed.get("success", false)):
		_fail("%s composer failed: %s" % [
			str(current_case.get("label")),
			str(composed.get("error", "unknown")),
		])
		return
	var pages: Array = composed.get("pages", []) as Array
	if pages.size() != 1:
		_fail("%s expected one shared render page" % str(current_case.get("label")))
		return
	var page: Dictionary = pages[0] as Dictionary
	var expected_ids := PackedInt64Array([1, 100]) \
			if feet_y < TREE_FEET_Y else PackedInt64Array([100, 1])
	if (page.get("body_stable_ids", PackedInt64Array()) as PackedInt64Array) != expected_ids:
		_fail("%s native painter tuple has the wrong order" % str(current_case.get("label")))
	var count: int = int(page.get("body_instance_count", 0))
	_multimesh.instance_count = count
	_multimesh.visible_instance_count = count
	_multimesh.buffer = page.get("body_buffer", PackedFloat32Array()) as PackedFloat32Array
	_set_profile_visibility(true, false)
	_say("framebuffer case: %s" % str(current_case.get("label")))


func _static_tree_snapshot() -> Dictionary:
	var body: PackedFloat32Array = _tree_gpu_instance()
	return {
		"success": true,
		"pages": [{
			"page_y": 0,
			"body_buffer": body,
			"body_feet_y": PackedFloat32Array([TREE_FEET_Y]),
			"body_semantic_layers": PackedInt32Array([10]),
			"body_stable_ids": PackedInt64Array([100]),
			"body_bounds": Rect2(-512.0, -512.0, 1024.0, 1024.0),
			"body_instance_count": 1,
			"instance_count": 1,
			"static_instance_count": 1,
			"ground_count": 0,
			"emissive_count": 0,
			"overhead_count": 0,
		}],
		"page_window_min_y": 0,
		"page_window_max_y": 0,
		"world_shadow_buffer": PackedFloat32Array(),
		"world_shadow_bounds": Rect2(),
		"world_shadow_count": 0,
		"spore_buffer": PackedFloat32Array(),
		"spore_bounds": Rect2(),
		"spore_count": 0,
		"instance_count": 1,
		"buffer_float_count": GPU_STRIDE,
	}


func _tree_gpu_instance() -> PackedFloat32Array:
	var metrics: PackedFloat32Array = _catalog.get_tree_native_metrics()
	var tree_binding: Dictionary = _tree_binding()
	var crops: PackedFloat32Array = tree_binding.get("render_crops", PackedFloat32Array()) \
			as PackedFloat32Array
	var frame_width: float = metrics[0]
	var frame_height: float = metrics[1]
	var anchor_x: float = metrics[2]
	var anchor_y: float = metrics[3]
	var scale: float = metrics[4]
	var crop_x: float = crops[0]
	var crop_y: float = crops[1]
	var crop_width: float = crops[2]
	var crop_height: float = crops[3]
	var full_xx: float = frame_width * scale
	var full_yy: float = frame_height * scale
	var full_origin := Vector2(
		-(anchor_x - frame_width * 0.5) * scale,
		TREE_FEET_Y - (anchor_y - frame_height * 0.5) * scale,
	)
	var buffer := PackedFloat32Array()
	buffer.resize(GPU_STRIDE)
	buffer[0] = full_xx * crop_width
	buffer[3] = full_origin.x + full_xx * (crop_x + crop_width * 0.5 - 0.5)
	buffer[5] = full_yy * crop_height
	buffer[7] = full_origin.y + full_yy * (crop_y + crop_height * 0.5 - 0.5)
	buffer[8] = 1.0
	buffer[9] = 1.0
	buffer[10] = 1.0
	buffer[11] = 1.0
	buffer[12] = 1.0
	buffer[13] = 0.0
	buffer[14] = 0.0
	return buffer


func _tree_binding() -> Dictionary:
	for binding_value: Variant in _registry.get_native_source_bindings():
		var binding: Dictionary = binding_value as Dictionary
		if int(binding.get("descriptor_id", -1)) == 1:
			return binding
	return { }


func _actor_record(feet_y: float) -> Dictionary:
	var root_y: float = feet_y - PLAYER_FEET_OFFSET_PX
	return {
		"stable_id": 1,
		"semantic_layer": 20,
		"feet_y": feet_y,
		"body_transform": Transform2D(
			Vector2(PLAYER_FRAME_SIZE.x * 0.3, 0.0),
			Vector2(0.0, PLAYER_FRAME_SIZE.y * 0.3),
			Vector2(PLAYER_X, root_y - 16.0 * 0.3),
		),
		"tint": Color.WHITE,
		"direction_index": 0,
		"frame_index": 0,
		"sprite_id": 4,
		"shadow_visible": false,
	}


func _set_profile_visibility(objects: bool, actors: bool) -> void:
	_material.set_shader_parameter("object_profiles_visible", objects)
	_material.set_shader_parameter("actor_profiles_visible", actors)


func _capture(label: String) -> Image:
	var image: Image = _probe_viewport.get_texture().get_image()
	if image == null:
		_fail("%s framebuffer readback returned no image" % label)
		return null
	image.save_png("user://world_render_%s.png" % label)
	return image


func _analyze_case(
		current_case: Dictionary,
		tree_image: Image,
		actor_image: Image,
		combined_image: Image,
) -> void:
	var label: String = str(current_case.get("label", "case"))
	if tree_image == null or actor_image == null or combined_image == null:
		_fail("%s has a missing framebuffer" % label)
		return
	var top_is_tree: bool = str(current_case.get("top", "tree")) == "tree"
	var center := Vector2i(combined_image.get_width() / 2, combined_image.get_height() / 2)
	var overlap_count: int = 0
	var discriminating_count: int = 0
	var correct_count: int = 0
	var expected_error_sum: float = 0.0
	var reverse_error_sum: float = 0.0
	for y: int in range(center.y - SAMPLE_HALF_EXTENT, center.y + SAMPLE_HALF_EXTENT):
		for x: int in range(center.x - SAMPLE_HALF_EXTENT, center.x + SAMPLE_HALF_EXTENT):
			var tree: Color = tree_image.get_pixel(x, y)
			var actor: Color = actor_image.get_pixel(x, y)
			if tree.a <= 0.02 or actor.a <= 0.02:
				continue
			overlap_count += 1
			var expected: Color = _alpha_over(tree, actor) if top_is_tree else _alpha_over(actor, tree)
			var reversed: Color = _alpha_over(actor, tree) if top_is_tree else _alpha_over(tree, actor)
			var combined: Color = combined_image.get_pixel(x, y)
			var expected_error: float = _color_distance(combined, expected)
			var reverse_error: float = _color_distance(combined, reversed)
			expected_error_sum += expected_error
			reverse_error_sum += reverse_error
			if _color_distance(expected, reversed) > 0.02:
				discriminating_count += 1
				if expected_error + 0.005 < reverse_error:
					correct_count += 1
	var expected_mean: float = expected_error_sum / maxf(float(overlap_count), 1.0)
	var reverse_mean: float = reverse_error_sum / maxf(float(overlap_count), 1.0)
	var correct_ratio: float = float(correct_count) / maxf(float(discriminating_count), 1.0)
	_say(
		"%s: overlap=%d discriminating=%d correct=%.3f expected_error=%.4f reverse_error=%.4f"
		% [label, overlap_count, discriminating_count, correct_ratio, expected_mean, reverse_mean],
	)
	var minimum_overlap: int = 8 if float(current_case.get("zoom", 1.0)) >= 0.99 else 1
	if overlap_count < minimum_overlap:
		_fail("%s does not contain enough real tree/Player overlap pixels" % label)
	if discriminating_count < minimum_overlap:
		_fail("%s does not contain enough order-discriminating pixels" % label)
	if correct_ratio < 0.85:
		_fail("%s framebuffer follows the wrong painter order" % label)
	var maximum_expected_error: float = 0.05 \
			if float(current_case.get("zoom", 1.0)) < 0.99 else 0.025
	if expected_mean > maximum_expected_error or expected_mean >= reverse_mean:
		_fail("%s framebuffer does not match the expected alpha composition" % label)


func _alpha_over(top: Color, bottom: Color) -> Color:
	var out_alpha: float = top.a + bottom.a * (1.0 - top.a)
	if out_alpha <= 0.00001:
		return Color.TRANSPARENT
	return Color(
		(top.r * top.a + bottom.r * bottom.a * (1.0 - top.a)) / out_alpha,
		(top.g * top.a + bottom.g * bottom.a * (1.0 - top.a)) / out_alpha,
		(top.b * top.a + bottom.b * bottom.a * (1.0 - top.a)) / out_alpha,
		out_alpha,
	)


func _color_distance(a: Color, b: Color) -> float:
	return maxf(
		maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)),
		absf(a.a - b.a),
	)


func _fail(message: String) -> void:
	_failed = true
	_say("FAIL: %s" % message)


func _finish() -> void:
	set_process(false)
	var verdict: String = \
			"PASS: one authored tree and Player share the native painter order at zoom 1.0/0.2."
	var exit_code: int = 0
	if _failed:
		verdict = "FAIL: authored tree/Player overlap regression."
		exit_code = 1
	elif _skipped:
		verdict = "SKIP: tree/Player painter order not verified (no framebuffer)."
		exit_code = SKIP_EXIT_CODE
	_say(verdict)
	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report != null:
		report.store_string("\n".join(_lines) + "\n")
		report.close()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _say(line: String) -> void:
	print(line)
	_lines.append(line)
