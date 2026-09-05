extends SceneTree
## A staged static bank must publish the actor state from its commit, including
## registration changes and a page-window extension, without a later physics tick.

const RenderWorld = preload("res://core/systems/world/world_render_world.gd")
const RenderRegistry = preload("res://core/systems/world/world_render_class_registry.gd")
const RuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const LightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const ShadowShader = preload("res://assets/shaders/world_render_shadow.gdshader")
const INSTANCE_STRIDE: int = 16

class VisualProxy:
	extends Node2D

	var pose: Vector2 = Vector2(10.0, 100.0)
	var renderer_active: bool = false


	func get_world_render_record() -> Dictionary:
		return {
			"stable_id": 4242,
			"feet_y": pose.y,
			"body_transform": Transform2D(0.0, pose),
			"sprite_id": 0,
			"shadow_visible": true,
			"shadow_transform": Transform2D(0.0, pose + Vector2(2.0, 3.0)),
		}


	func set_world_render_proxy_active(active: bool) -> void:
		renderer_active = active


var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists(&"WorldCore"):
		_expect(false, "native WorldCore is required")
		_finish()
		return
	var renderer: RenderWorld = RenderWorld.new()
	var registry: RenderRegistry = RenderRegistry.new()
	if not registry.configure(RenderRegistry.DEFAULT_REGISTRY_PATH, false):
		_expect(false, "registry metadata configures")
		renderer.free()
		_finish()
		return
	_test_shadow_crop_guard(registry)
	_test_lighting_uniform()
	var world_core: Object = ClassDB.instantiate(&"WorldCore")
	renderer.set("_world_core", world_core)
	renderer.set("_registry", registry)
	renderer.call("_prepare_layers")
	renderer.set("_configured", true)
	root.add_child(renderer)
	renderer.set_physics_process(false)
	var proxy: VisualProxy = VisualProxy.new()
	root.add_child(proxy)
	var source: Dictionary = _make_static_snapshot(world_core, registry)
	_expect(bool(source.get("success", false)), "one native static body page is prepared")
	if not bool(source.get("success", false)):
		renderer.free()
		proxy.free()
		_finish()
		return

	_expect(renderer.register_visual_proxy(proxy), "proxy registers before first publication")
	_expect(renderer.begin_built_snapshot(source, 0), "first bank begins staging")
	for _phase: int in range(4):
		_expect(not renderer.advance_built_snapshot(1), "partial bank stays hidden")
	proxy.pose = Vector2(200.0, -10.0)
	_commit(renderer)
	_expect_actor_pose(renderer, registry.get_actor_descriptor_id(0), proxy.pose)
	_expect(proxy.renderer_active, "fallback switches off only after publication")
	var shadow: MultiMesh = renderer.get("_actor_shadow_multimesh") as MultiMesh
	_expect(shadow.instance_count == 1, "current actor shadow is published")
	_expect(_buffer_origin(shadow.buffer, 0).is_equal_approx(proxy.pose + Vector2(2.0, 3.0)),
		"shadow pose is current at the commit itself")
	var ground_layers: Array = renderer.get("_ground_layers") as Array
	_expect((ground_layers[0] as Node2D).z_index == RuntimeConstants.Z_RENDER_BODY_PAGE_BASE + 1,
		"static pass depth follows an actor extending the page window north")

	_expect(renderer.begin_built_snapshot(source, 0), "replacement bank includes registered proxy")
	for _phase: int in range(4):
		renderer.advance_built_snapshot(1)
	renderer.unregister_visual_proxy(proxy)
	_expect(not proxy.renderer_active, "unregister restores fallback immediately")
	_commit(renderer)
	_expect(_actor_origins(renderer, registry.get_actor_descriptor_id(0)).is_empty(),
		"unregistered actor cannot reappear from a staged bank")
	_expect(shadow.instance_count == 0, "unregistered shadow cannot reappear")
	_expect(not proxy.renderer_active, "commit does not reactivate an unregistered proxy")
	var state: Dictionary = renderer.get_debug_state()
	_expect(int(state.get("instance_count", -1)) == int(source.get("instance_count", 0)),
		"published instance accounting excludes the removed actor")
	_expect(int(state.get("gpu_buffer_bytes", -1)) == int(source.get("buffer_float_count", 0)) * 4,
		"published GPU accounting excludes the removed actor and shadow")

	_expect(renderer.begin_built_snapshot(source, 0), "bank without actors begins staging")
	for _phase: int in range(4):
		renderer.advance_built_snapshot(1)
	proxy.pose = Vector2(300.0, 1200.0)
	_expect(renderer.register_visual_proxy(proxy), "proxy registers while bank is pending")
	_commit(renderer)
	_expect_actor_pose(renderer, registry.get_actor_descriptor_id(0), proxy.pose)
	renderer.free()
	_expect(not proxy.renderer_active, "renderer teardown restores fallback")
	proxy.free()
	_finish()


func _test_shadow_crop_guard(registry: RenderRegistry) -> void:
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(RenderRegistry.DEFAULT_REGISTRY_PATH),
	) as Dictionary
	var descriptors: Dictionary = { }
	for descriptor: Dictionary in manifest["descriptors"]:
		descriptors[int(descriptor["descriptor_id"])] = descriptor
	var authored_bindings: Dictionary = { }
	for binding: Dictionary in manifest["source_bindings"]:
		authored_bindings[str(binding["id"])] = binding
	var anchored_shadow_count: int = 0
	var ground_shadow_count: int = 0
	for native_binding: Dictionary in registry.get_native_source_bindings():
		var authored: Dictionary = authored_bindings[str(native_binding["id"])] as Dictionary
		var descriptor: Dictionary = descriptors[int(native_binding["descriptor_id"])] as Dictionary
		var original: Array = authored["shadow_source_crops"] as Array
		var padded: PackedFloat32Array = native_binding["shadow_source_crops"]
		var requires_padding: bool = str(authored["geometry"]) == "anchored" \
				and (int(descriptor["passes"]) & RenderRegistry.PASS_SHADOW) != 0
		anchored_shadow_count += 1 if requires_padding else 0
		ground_shadow_count += 1 if str(authored["geometry"]) == "south_edge" else 0
		var frame_size: Array = descriptor["shadow_frame_size_px"] as Array
		var radius: float = LightingProfile.MAX_OBJECT_SHADOW_SOFTNESS_TEXELS \
				+ LightingProfile.OBJECT_SHADOW_BILINEAR_GUARD_TEXELS
		var padding: Vector2 = Vector2(radius / float(frame_size[0]), radius / float(frame_size[1])) \
				if requires_padding else Vector2.ZERO
		for variant_index: int in range(original.size()):
			var crop: Array = original[variant_index] as Array
			var left: float = maxf(0.0, float(crop[0]) - padding.x)
			var top: float = maxf(0.0, float(crop[1]) - padding.y)
			var right: float = minf(1.0, float(crop[0]) + float(crop[2]) + padding.x)
			var bottom: float = minf(1.0, float(crop[1]) + float(crop[3]) + padding.y)
			var expected: Vector4 = Vector4(left, top, right - left, bottom - top)
			var offset: int = variant_index * 4
			var actual: Vector4 = Vector4(
				padded[offset], padded[offset + 1], padded[offset + 2], padded[offset + 3],
			)
			_expect(actual.is_equal_approx(expected),
				"%s variant %d retains the full filter footprint" % [authored["id"], variant_index])
	_expect(anchored_shadow_count > 0, "production includes anchored object shadows")
	_expect(ground_shadow_count > 0, "compact ground shadows retain their existing crops")


func _test_lighting_uniform() -> void:
	var renderer: RenderWorld = RenderWorld.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = ShadowShader
	renderer.set("_shadow_material", material)
	renderer.set_sun_lighting(LightingProfile.SHADOW_MIN_LENGTH_PX, 1.0)
	_expect(is_equal_approx(float(material.get_shader_parameter("object_shadow_softness_texels")),
		LightingProfile.MIN_OBJECT_SHADOW_SOFTNESS_TEXELS), "high sun uses the shared minimum softness")
	renderer.set_sun_lighting(LightingProfile.SHADOW_MAX_LENGTH_PX, 1.0)
	_expect(is_equal_approx(float(material.get_shader_parameter("object_shadow_softness_texels")),
		LightingProfile.MAX_OBJECT_SHADOW_SOFTNESS_TEXELS), "low sun uses the crop-reserved maximum softness")
	renderer.free()



func _make_static_snapshot(world_core: Object, registry: RenderRegistry) -> Dictionary:
	var bindings: Array = registry.get_native_source_bindings()
	var object_result: Dictionary = { }
	for binding: Dictionary in bindings:
		if int(binding.get("result_set", -1)) == 0 \
				and (int(binding.get("passes", 0)) & RenderRegistry.PASS_BODY) != 0:
			object_result[binding["buffer_key"]] = [PackedFloat32Array([
				64.0, 0.0, 0.0, 100.0,
				0.0, 64.0, 0.0, 100.0,
				0.0, 1.0, 1.0, 1.0,
			])]
			break
	return world_core.call("build_world_render_snapshot", PackedVector2Array([Vector2.ZERO]),
		[object_result], [{ }], bindings, 1.0) as Dictionary


func _commit(renderer: RenderWorld) -> void:
	for _phase: int in range(32):
		if renderer.advance_built_snapshot(1):
			return
	_expect(false, "staging commits within its fixed page bound")


func _expect_actor_pose(renderer: RenderWorld, descriptor_id: int, expected: Vector2) -> void:
	var origins: Array[Vector2] = _actor_origins(renderer, descriptor_id)
	_expect(origins.size() == 1, "body bank contains exactly one current actor")
	if origins.size() == 1:
		_expect(origins[0].is_equal_approx(expected), "actor pose is current before any physics tick")


func _actor_origins(renderer: RenderWorld, descriptor_id: int) -> Array[Vector2]:
	var origins: Array[Vector2] = []
	var multimeshes: Array = renderer.get("_body_multimeshes") as Array
	for multimesh: MultiMesh in multimeshes:
		var buffer: PackedFloat32Array = multimesh.buffer
		for instance_index: int in range(multimesh.instance_count):
			if roundi(buffer[instance_index * INSTANCE_STRIDE + 12]) == descriptor_id:
				origins.append(_buffer_origin(buffer, instance_index))
	return origins


func _buffer_origin(buffer: PackedFloat32Array, instance_index: int) -> Vector2:
	var offset: int = instance_index * INSTANCE_STRIDE
	return Vector2(buffer[offset + 3], buffer[offset + 7])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure: String in _failures:
		push_error("world_render_snapshot_actor_freshness_contract_test: %s" % failure)
	print("world_render_snapshot_actor_freshness_contract_test: %s" % (
		"PASS" if _failures.is_empty() else "FAIL"))
	quit(0 if _failures.is_empty() else 1)
