extends Node2D
## Runtime regression for the RenderWorld painter contract and the engine's
## observed ascending-instance overlap rule.

const WorldRuntimeConstants = preload(
	"res://core/systems/world/world_runtime_constants.gd"
)
const REPORT_PATH := "user://multimesh_instance_order_contract.txt"
const SHOT_PATH := "user://multimesh_instance_order_contract.png"
const GPU_STRIDE: int = 16
const QUAD_PX: float = 200.0
const PAIR_POSITION := Vector2(80.0, 40.0)

var _world_core: Object = null
var _multimesh: MultiMesh = null
var _holder: MultiMeshInstance2D = null
var _lines := PackedStringArray()
var _frames: int = 0
var _stage: int = 0
var _passed: bool = true
var _pass_layers: Array[Polygon2D] = []
var _pass_expected: Array[String] = ["cyan", "magenta", "yellow", "blue", "green", "red"]
var _pass_cursor: int = 0


func _ready() -> void:
	if not ClassDB.class_exists(&"WorldCore"):
		_fail("native WorldCore is unavailable")
		_finish.call_deferred()
		return
	_world_core = ClassDB.instantiate(&"WorldCore")
	if _world_core == null or not _world_core.has_method("compose_world_render_actors"):
		_fail("native actor composer is unavailable")
		_finish.call_deferred()
		return
	_say("engine: %s" % Engine.get_version_info().get("string", "unknown"))
	_say("renderer: %s / %s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(),
	])
	_say("adapter: %s" % RenderingServer.get_video_adapter_name())
	_run_data_contracts()
	if DisplayServer.get_name() == "headless":
		_say("framebuffer: SKIP under the dummy headless display")
		_finish.call_deferred()
		return
	_prepare_framebuffer_probe()
	_show_overlap(110.0)
	_say("framebuffer stage 1: actor south of static record")


func _run_data_contracts() -> void:
	var base := _static_snapshot([
		_page(0, [_static_instance(100.0, 10, 100, Color.RED)]),
	])
	var north := _compose(base, [_actor(90.0, 20, 1, Color.BLUE)])
	_expect_ids(north, 0, PackedInt64Array([1, 100]), "actor north/static overlap")
	var south := _compose(base, [_actor(110.0, 20, 1, Color.BLUE)])
	_expect_ids(south, 0, PackedInt64Array([100, 1]), "actor south/static overlap")

	var same_y := _compose(base, [
		_actor(100.0, 20, 2, Color.BLUE),
		_actor(100.0, 20, 1, Color.GREEN),
	])
	_expect_ids(same_y, 0, PackedInt64Array([100, 1, 2]), "same-Y semantic/stable tie")

	var page_gap := _static_snapshot([
		_page(5, [_static_instance(5200.0, 10, 500, Color.RED)]),
		_page(6, []),
		_page(7, [_static_instance(7200.0, 10, 700, Color.RED)]),
	])
	var gap_result := _compose(page_gap, [_actor(7210.0, 20, 1, Color.BLUE)])
	_expect(
		_page_ys(gap_result) == PackedInt64Array([5, 6, 7]),
		"empty absolute page slot is retained",
	)
	_expect(
		int((gap_result.get("pages", []) as Array)[1].get("instance_count", -1)) == 0,
		"empty page remains empty and cannot shift southern z",
	)

	var crossing_base := _static_snapshot([
		_page(0, [_static_instance(900.0, 10, 900, Color.RED)]),
	])
	var before_crossing := _compose(
		crossing_base,
		[_actor(1023.0, 20, 1, Color.BLUE)],
	)
	var after_crossing := _compose(
		crossing_base,
		[_actor(1025.0, 20, 1, Color.BLUE)],
	)
	_expect(
		_page_ys(before_crossing) == PackedInt64Array([0])
				and _page_ys(after_crossing) == PackedInt64Array([0, 1]),
		"actor crossing 1024px boundary changes absolute page without collapsing page 0",
	)
	_expect_ids(after_crossing, 0, PackedInt64Array([900]), "crossing restores static page")
	_expect_ids(after_crossing, 1, PackedInt64Array([1]), "crossing publishes actor on page 1")
	var pass_z: Array[int] = [
		WorldRuntimeConstants.Z_WORLD_SHADOW,
		WorldRuntimeConstants.Z_MOUNTAIN_PAGE,
		WorldRuntimeConstants.Z_MOUNTAIN_TORCH_SHADOW,
		WorldRuntimeConstants.Z_MOUNTAIN_TOP,
		WorldRuntimeConstants.Z_MOUNTAIN_ROOF,
		WorldRuntimeConstants.Z_ACTOR_SHADOW,
		WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE,
		WorldRuntimeConstants.Z_GRASS_SPORE,
		WorldRuntimeConstants.Z_MINING_FEEDBACK,
		WorldRuntimeConstants.Z_DEBUG_OVERLAY,
	]
	var strictly_increasing: bool = true
	for index: int in range(1, pass_z.size()):
		strictly_increasing = strictly_increasing and pass_z[index] > pass_z[index - 1]
	_expect(strictly_increasing, "world/mountain/actor/body/emissive/overhead z passes are unique")


func _prepare_framebuffer_probe() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = mesh
	_multimesh.instance_count = 0
	_multimesh.custom_aabb = AABB(
		Vector3(-512.0, -384.0, -1.0),
		Vector3(1024.0, 768.0, 2.0),
	)
	_holder = MultiMeshInstance2D.new()
	_holder.multimesh = _multimesh
	_holder.position = get_viewport_rect().size * 0.5
	add_child(_holder)


func _show_overlap(actor_feet_y: float) -> void:
	var base := _static_snapshot([
		_page(0, [_static_instance(100.0, 10, 100, Color.RED, PAIR_POSITION)]),
	])
	var result := _compose(
		base,
		[_actor(actor_feet_y, 20, 1, Color.BLUE, PAIR_POSITION)],
	)
	var page: Dictionary = (result.get("pages", []) as Array)[0] as Dictionary
	var count: int = int(page.get("instance_count", 0))
	_multimesh.instance_count = count
	_multimesh.visible_instance_count = count
	_multimesh.buffer = page.get("body_buffer", PackedFloat32Array()) as PackedFloat32Array


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % 12 != 0:
		return
	match _stage:
		0:
			_check_framebuffer("actor_south", "blue")
			_show_overlap(90.0)
			_say("framebuffer stage 2: actor north of static record")
			_stage = 1
		1:
			_check_framebuffer("actor_north", "red")
			_holder.visible = false
			_prepare_pass_order_probe()
			_say("framebuffer stage 3: explicit pass-order stack")
			_stage = 2
		2:
			var expected: String = _pass_expected[_pass_cursor]
			_check_framebuffer("pass_%s" % expected, expected)
			var layer_index: int = _pass_layers.size() - 1 - _pass_cursor
			_pass_layers[layer_index].visible = false
			_pass_cursor += 1
			if _pass_cursor >= _pass_expected.size():
				_finish()


func _compose(static_snapshot: Dictionary, actors: Array) -> Dictionary:
	var value: Variant = _world_core.call(
		"compose_world_render_actors",
		static_snapshot,
		actors,
	)
	if not value is Dictionary:
		_fail("actor composer returned non-Dictionary")
		return { }
	var result: Dictionary = value as Dictionary
	if not bool(result.get("success", false)):
		_fail("actor composer failed: %s" % str(result.get("error", "unknown")))
	return result


func _static_snapshot(pages: Array) -> Dictionary:
	var instance_count: int = 0
	var float_count: int = 0
	for page_variant: Variant in pages:
		var page: Dictionary = page_variant as Dictionary
		instance_count += int(page.get("instance_count", 0))
		float_count += (page.get("body_buffer", PackedFloat32Array()) as PackedFloat32Array).size()
	return {
		"success": true,
		"pages": pages,
		"page_window_min_y": int(pages[0].get("page_y", 0)) if not pages.is_empty() else 0,
		"page_window_max_y": int(pages[-1].get("page_y", -1)) if not pages.is_empty() else -1,
		"world_shadow_buffer": PackedFloat32Array(),
		"world_shadow_bounds": Rect2(),
		"world_shadow_count": 0,
		"spore_buffer": PackedFloat32Array(),
		"spore_bounds": Rect2(),
		"spore_count": 0,
		"instance_count": instance_count,
		"buffer_float_count": float_count,
	}


func _page(page_y: int, instances: Array) -> Dictionary:
	var body := PackedFloat32Array()
	body.resize(instances.size() * GPU_STRIDE)
	var feet_y := PackedFloat32Array()
	var semantic_layers := PackedInt32Array()
	var stable_ids := PackedInt64Array()
	feet_y.resize(instances.size())
	semantic_layers.resize(instances.size())
	stable_ids.resize(instances.size())
	for index: int in range(instances.size()):
		var instance: Dictionary = instances[index] as Dictionary
		var gpu: PackedFloat32Array = instance.get("gpu") as PackedFloat32Array
		for component: int in range(GPU_STRIDE):
			body[index * GPU_STRIDE + component] = gpu[component]
		feet_y[index] = float(instance.get("feet_y", 0.0))
		semantic_layers[index] = int(instance.get("semantic_layer", 0))
		stable_ids[index] = int(instance.get("stable_id", 0))
	return {
		"page_y": page_y,
		"body_buffer": body,
		"body_feet_y": feet_y,
		"body_semantic_layers": semantic_layers,
		"body_stable_ids": stable_ids,
		"body_bounds": Rect2(-512.0, -512.0, 1024.0, 1024.0),
		"body_instance_count": instances.size(),
		"instance_count": instances.size(),
		"static_instance_count": instances.size(),
		"ground_count": 0,
		"emissive_count": 0,
		"overhead_count": 0,
	}


func _static_instance(
		feet_y: float,
		semantic_layer: int,
		stable_id: int,
		color: Color,
		position: Vector2 = Vector2.ZERO,
) -> Dictionary:
	return {
		"feet_y": feet_y,
		"semantic_layer": semantic_layer,
		"stable_id": stable_id,
		"gpu": _gpu_instance(position, color),
	}


func _actor(
		feet_y: float,
		semantic_layer: int,
		stable_id: int,
		color: Color,
		position: Vector2 = Vector2.ZERO,
) -> Dictionary:
	return {
		"stable_id": stable_id,
		"semantic_layer": semantic_layer,
		"feet_y": feet_y,
		"body_transform": Transform2D(
			Vector2(QUAD_PX, 0.0),
			Vector2(0.0, QUAD_PX),
			position,
		),
		"tint": color,
		"direction_index": 0,
		"frame_index": 0,
		"sprite_id": 4,
		"shadow_visible": false,
	}


func _gpu_instance(position: Vector2, color: Color) -> PackedFloat32Array:
	var gpu := PackedFloat32Array()
	gpu.resize(GPU_STRIDE)
	gpu[0] = QUAD_PX
	gpu[3] = position.x
	gpu[5] = QUAD_PX
	gpu[7] = position.y
	gpu[8] = color.r
	gpu[9] = color.g
	gpu[10] = color.b
	gpu[11] = color.a
	return gpu


func _prepare_pass_order_probe() -> void:
	var pass_specs: Array = [
		[WorldRuntimeConstants.Z_WORLD_SHADOW, Color.RED],
		[WorldRuntimeConstants.Z_MOUNTAIN_ROOF, Color.GREEN],
		[WorldRuntimeConstants.Z_ACTOR_SHADOW, Color.BLUE],
		[WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE, Color.YELLOW],
		[WorldRuntimeConstants.Z_GRASS_SPORE, Color.MAGENTA],
		[WorldRuntimeConstants.Z_MINING_FEEDBACK, Color.CYAN],
	]
	for spec_variant: Variant in pass_specs:
		var spec: Array = spec_variant as Array
		var layer := Polygon2D.new()
		layer.polygon = PackedVector2Array([
			Vector2(-QUAD_PX * 0.5, -QUAD_PX * 0.5),
			Vector2(QUAD_PX * 0.5, -QUAD_PX * 0.5),
			Vector2(QUAD_PX * 0.5, QUAD_PX * 0.5),
			Vector2(-QUAD_PX * 0.5, QUAD_PX * 0.5),
		])
		layer.color = spec[1] as Color
		layer.position = get_viewport_rect().size * 0.5 + PAIR_POSITION
		layer.z_as_relative = false
		layer.z_index = int(spec[0])
		add_child(layer)
		_pass_layers.append(layer)


func _page_ys(result: Dictionary) -> PackedInt64Array:
	var values := PackedInt64Array()
	for page_variant: Variant in result.get("pages", []):
		values.append(int((page_variant as Dictionary).get("page_y", 0)))
	return values


func _expect_ids(
		result: Dictionary,
		page_slot: int,
		expected: PackedInt64Array,
		label: String,
) -> void:
	var pages: Array = result.get("pages", []) as Array
	var actual := PackedInt64Array()
	if page_slot >= 0 and page_slot < pages.size():
		actual = (pages[page_slot] as Dictionary).get(
			"body_stable_ids",
			PackedInt64Array(),
		) as PackedInt64Array
	_expect(actual == expected, "%s: %s" % [label, actual])


func _expect(condition: bool, label: String) -> void:
	if condition:
		_say("PASS data: %s" % label)
	else:
		_fail("data: %s" % label)


func _check_framebuffer(label: String, expected: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		_fail("framebuffer readback returned no image")
		return
	image.save_png("user://multimesh_instance_order_%s.png" % label)
	if label == "actor_north":
		image.save_png(SHOT_PATH)
	var logical_size: Vector2 = get_viewport_rect().size
	var logical_sample: Vector2 = logical_size * 0.5 + PAIR_POSITION
	var sample_position := Vector2i(
		clampi(roundi(logical_sample.x * float(image.get_width()) / logical_size.x), 0, image.get_width() - 1),
		clampi(roundi(logical_sample.y * float(image.get_height()) / logical_size.y), 0, image.get_height() - 1),
	)
	var color: Color = image.get_pixelv(sample_position)
	var seen: String = _color_name(color)
	_say("%s: rgb(%.2f, %.2f, %.2f) -> %s (expected %s)" % [
		label, color.r, color.g, color.b, seen, expected,
	])
	if seen != expected:
		_fail("framebuffer %s expected %s, saw %s" % [label, expected, seen])


func _color_name(color: Color) -> String:
	if color.r > 0.7 and color.g > 0.7 and color.b < 0.3:
		return "yellow"
	if color.r > 0.7 and color.b > 0.7 and color.g < 0.3:
		return "magenta"
	if color.g > 0.7 and color.b > 0.7 and color.r < 0.3:
		return "cyan"
	if color.r > 0.7 and color.g < 0.3 and color.b < 0.3:
		return "red"
	if color.g > 0.7 and color.r < 0.3 and color.b < 0.3:
		return "green"
	if color.b > 0.7 and color.r < 0.3 and color.g < 0.3:
		return "blue"
	return "other"


func _fail(message: String) -> void:
	_passed = false
	_say("FAIL: %s" % message)


func _finish() -> void:
	set_process(false)
	if _holder != null:
		_holder.multimesh = null
		_holder.queue_free()
	_holder = null
	_multimesh = null
	for layer: Polygon2D in _pass_layers:
		layer.queue_free()
	_pass_layers.clear()
	_world_core = null
	_say("")
	_say("PASS: shared painter tuple, absolute pages and framebuffer overlap." \
			if _passed else "FAIL: RenderWorld painter contract regression.")
	_say("screenshot: %s" % SHOT_PATH)
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _passed else 1)


func _say(line: String) -> void:
	print(line)
	_lines.append(line)
