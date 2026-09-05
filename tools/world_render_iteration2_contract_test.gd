extends SceneTree
## Iteration-2 architecture proof: fixed passes, data-only family extension,
## bounded native packing, collision-only chunk ownership and scale-1 bypass.

const WorldRenderClassRegistry = preload(
	"res://core/systems/world/world_render_class_registry.gd"
)
const WorldObjectCollisionOwner = preload(
	"res://core/systems/world/world_object_collision_owner.gd"
)
const WorldLayeredObjectAssetCatalog = preload(
	"res://core/systems/world/world_layered_object_asset_catalog.gd"
)
const WorldResolutionCompositor = preload(
	"res://core/systems/world/world_resolution_compositor.gd"
)

const SYNTHETIC_09: String = "res://data/world_render/synthetic_render_class_pack_09.json"
const SYNTHETIC_10: String = "res://data/world_render/synthetic_render_class_pack_10.json"
const GPU_SOURCE_STRIDE: int = 12
const MAX_VISIBLE_INSTANCES: int = 1_048_576
const MAX_RENDER_ATOM_STRIDE_BYTES: int = 160
const MAX_CPU_RENDER_ATOM_BYTES: int = MAX_VISIBLE_INSTANCES * MAX_RENDER_ATOM_STRIDE_BYTES
const MAX_CPU_SORT_INDEX_BYTES: int = MAX_VISIBLE_INSTANCES * 8
const MAX_CPU_SNAPSHOT_WORKING_SET_BYTES: int = 1_073_741_824

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_production_registry()
	_test_data_only_tenth_family()
	_test_native_synthetic_pack()
	await _test_collision_owner()
	await _test_compositor_bypass()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error("world_render_iteration2_contract_test: %s" % failure)
		quit(1)
		return
	print("world_render_iteration2_contract_test: PASS")
	quit(0)


func _test_production_registry() -> void:
	var registry := WorldRenderClassRegistry.new()
	_expect(registry.configure(), "production RenderClassRegistry loads all fixed atlases")
	_expect(registry.get_descriptor_count() == 9, "production registry has nine descriptors")
	_expect(registry.get_source_binding_count() == 4, "production registry has four data bindings")
	_expect(registry.get_pass_count() == 5, "production registry has five fixed passes")
	for texture_id: StringName in [
		&"body_base", &"foliage", &"snow_overlay", &"wind_mask", &"snow_mask",
		&"season_mask", &"shadow", &"emissive", &"overhead", &"actor_body", &"actor_shadow",
	]:
		_expect(registry.get_texture(texture_id) != null, "%s atlas is boot-resident" % texture_id)
	var bounds: Dictionary = registry.get_hard_bounds()
	_expect(int(bounds.get("max_descriptors", 0)) == 64, "descriptor hard bound is 64")
	_expect(int(bounds.get("max_variants_per_descriptor", 0)) == 256, "variant hard bound is 256")
	_expect(int(bounds.get("max_fixed_passes", 0)) == 5, "pass hard bound is 5")
	_expect(int(bounds.get("max_render_page_slots", 0)) == 17, "page-slot hard bound is 17")
	_expect(
		int(bounds.get("max_visible_instances", 0)) == MAX_VISIBLE_INSTANCES,
		"visible-instance hard bound is 1,048,576",
	)
	_expect(int(bounds.get("max_visible_actors", 0)) == 4_096,
		"visible-actor hard bound is 4,096")
	_expect(int(bounds.get("max_spore_instances", 0)) == MAX_VISIBLE_INSTANCES,
		"spore-instance hard bound is 1,048,576")
	_expect(
		int(bounds.get("max_gpu_instance_payload_bytes", 0)) == 335_544_320,
		"authored maximum GPU instance payload is 320 MiB",
	)
	_expect(
		int(bounds.get("max_cpu_render_atom_bytes", 0)) == MAX_CPU_RENDER_ATOM_BYTES,
		"authored render-atom capacity is bounded to 160 MiB",
	)
	_expect(
		int(bounds.get("max_cpu_sort_index_bytes", 0)) == MAX_CPU_SORT_INDEX_BYTES,
		"authored sort-index capacity is bounded to 8 MiB",
	)
	_expect(
		int(bounds.get("max_cpu_snapshot_working_set_bytes", 0)) \
				== MAX_CPU_SNAPSHOT_WORKING_SET_BYTES,
		"authored native snapshot working set is bounded to 1 GiB",
	)
	var expected_samplers: Dictionary = {
		"res://assets/shaders/world_render_ground.gdshader": 5,
		"res://assets/shaders/world_render_body.gdshader": 9,
		"res://assets/shaders/world_render_shadow.gdshader": 4,
		"res://assets/shaders/world_render_emissive.gdshader": 3,
		"res://assets/shaders/world_render_overhead.gdshader": 3,
	}
	for shader_path: String in expected_samplers:
		var source: String = FileAccess.get_file_as_string(shader_path)
		_expect(
			source.count("uniform sampler2D") == int(expected_samplers[shader_path]),
			"%s keeps its fixed sampler budget" % shader_path.get_file(),
		)


func _test_data_only_tenth_family() -> void:
	var manifest_09: Dictionary = _read_json(SYNTHETIC_09)
	var manifest_10: Dictionary = _read_json(SYNTHETIC_10)
	var descriptors_09: Array = manifest_09.get("descriptors", []) as Array
	var descriptors_10: Array = manifest_10.get("descriptors", []) as Array
	var bindings_09: Array = manifest_09.get("source_bindings", []) as Array
	var bindings_10: Array = manifest_10.get("source_bindings", []) as Array
	_expect(descriptors_09.size() == 9 and bindings_09.size() == 9, "base synthetic pack has nine families")
	_expect(descriptors_10.size() == 10 and bindings_10.size() == 10, "extended synthetic pack has ten families")
	_expect(
		descriptors_10.slice(0, 9) == descriptors_09 and bindings_10.slice(0, 9) == bindings_09,
		"the tenth family is an append-only descriptor/binding change",
	)
	var semantic_set: Dictionary = { }
	for descriptor_value: Variant in descriptors_10:
		var descriptor: Dictionary = descriptor_value as Dictionary
		semantic_set[str(descriptor.get("semantic", ""))] = true
		_expect(
			(descriptor.get("render_crops", []) as Array).size() == 10,
			"%s has ten authored variants" % str(descriptor.get("id", "?")),
		)
	_expect(semantic_set.has("foliage_wind"), "synthetic pack includes foliage/wind")
	_expect(semantic_set.has("emissive"), "synthetic pack includes emissive")
	_expect(semantic_set.has("opaque_cutout"), "synthetic pack includes ordinary cutout")
	for renderer_path: String in [
		"res://core/systems/world/world_render_class_registry.gd",
		"res://core/systems/world/world_render_world.gd",
		"res://gdextension/src/world_render_buffer.cpp",
		"res://assets/shaders/world_render_ground.gdshader",
		"res://assets/shaders/world_render_body.gdshader",
		"res://assets/shaders/world_render_shadow.gdshader",
		"res://assets/shaders/world_render_emissive.gdshader",
		"res://assets/shaders/world_render_overhead.gdshader",
	]:
		_expect(
			not FileAccess.get_file_as_string(renderer_path).contains("synthetic_family_10"),
			"tenth family is absent from %s" % renderer_path.get_file(),
		)


func _test_native_synthetic_pack() -> void:
	var registry := WorldRenderClassRegistry.new()
	_expect(registry.configure(SYNTHETIC_10, false), "synthetic registry configures without texture loads")
	if not registry.is_ready() or not ClassDB.class_exists(&"WorldCore"):
		_expect(false, "native WorldCore and synthetic registry are available")
		return
	var object_result: Dictionary = { }
	for family_index: int in range(10):
		object_result["synthetic_family_%02d_bucket_buffers" % (family_index + 1)] = [
			_synthetic_family_buffer(family_index),
		]
	var world_core: Object = ClassDB.instantiate(&"WorldCore")
	var result: Dictionary = world_core.call(
		"build_world_render_snapshot",
		PackedVector2Array([Vector2.ZERO]),
		[object_result],
		[{ }],
		registry.get_native_source_bindings(),
		1.0,
	) as Dictionary
	_expect(bool(result.get("success", false)), "native packer accepts the ten-family data pack")
	_expect(int(result.get("source_binding_count", 0)) == 10, "native packer consumed ten generic bindings")
	_expect(int(result.get("instance_count", 0)) == 100, "native packer emitted 100 body instances")
	_expect(int(result.get("world_shadow_count", 0)) == 100, "native packer emitted 100 shadows")
	var render_atom_stride_bytes: int = int(result.get("render_atom_stride_bytes", 0))
	_expect(
		render_atom_stride_bytes > 0 and render_atom_stride_bytes <= MAX_RENDER_ATOM_STRIDE_BYTES,
		"native RenderAtom fits the authored 160-byte stride envelope",
	)
	_expect(
		int(result.get("cpu_render_atom_capacity_bytes", 0)) \
				== render_atom_stride_bytes * MAX_VISIBLE_INSTANCES,
		"native render-atom capacity is derived from the hard instance bound",
	)
	_expect(
		int(result.get("cpu_render_atom_capacity_bytes", 0)) <= MAX_CPU_RENDER_ATOM_BYTES,
		"native render-atom capacity stays within the authored CPU bound",
	)
	_expect(
		int(result.get("cpu_sort_index_capacity_bytes", 0)) == MAX_CPU_SORT_INDEX_BYTES,
		"native sort-index capacity stays within the authored CPU bound",
	)
	_expect(
		int(result.get("cpu_snapshot_working_set_bound_bytes", 0)) \
				== MAX_CPU_SNAPSHOT_WORKING_SET_BYTES,
		"native snapshot reports the 1 GiB working-set ceiling",
	)
	var descriptor_counts: PackedInt32Array = result.get("descriptor_counts", PackedInt32Array())
	for descriptor_id: int in range(10):
		_expect(descriptor_counts.size() > descriptor_id and descriptor_counts[descriptor_id] == 10,
			"descriptor %d has ten variants" % descriptor_id)
	var body_count: int = 0
	var emissive_count: int = 0
	var overhead_count: int = 0
	for page_value: Variant in result.get("pages", []) as Array:
		var page: Dictionary = page_value as Dictionary
		body_count += int(page.get("body_instance_count", 0))
		emissive_count += int(page.get("emissive_count", 0))
		overhead_count += int(page.get("overhead_count", 0))
		_expect(not page.has("tall_caster_buffer"), "render page has no removed caster payload")
	_expect(body_count == 100, "fixed body pass received all synthetic instances")
	_expect(emissive_count == 30, "fixed emissive pass received three families")
	_expect(overhead_count == 20, "fixed overhead pass received two families")


func _synthetic_family_buffer(family_index: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(10 * GPU_SOURCE_STRIDE)
	for variant: int in range(10):
		var offset: int = variant * GPU_SOURCE_STRIDE
		result[offset] = 64.0
		result[offset + 1] = 0.0
		result[offset + 2] = 0.0
		result[offset + 3] = float(family_index * 80 + variant * 4)
		result[offset + 4] = 0.0
		result[offset + 5] = 64.0
		result[offset + 6] = 0.0
		result[offset + 7] = 100.0 + float(family_index * 8)
		result[offset + 8] = float(variant) / 255.0
		result[offset + 9] = 1.0
		result[offset + 10] = 1.0
		result[offset + 11] = 1.0
	return result


func _test_collision_owner() -> void:
	var catalog := WorldLayeredObjectAssetCatalog.new()
	var owner := WorldObjectCollisionOwner.new()
	root.add_child(owner)
	_expect(catalog.is_ready(), "CPU object source catalog is boot-ready")
	_expect(owner.prepare_presentation_envelope(catalog), "collision owner prepares one fixed shell")
	var result: Dictionary = {
		"success": true,
		"tree_instance_count": 2,
		"ignored_instance_count": 0,
		"tree_collision_records": PackedFloat32Array([
			10.0, 20.0, 24.0, 34.0,
			50.0, 60.0, 28.0, 36.0,
		]),
	}
	_expect(owner.begin_presentation_result(result, catalog), "collision owner accepts compact records")
	var guard: int = 0
	while not owner.is_presentation_complete() and guard < 16:
		owner.apply_next_presentation_slice(1, 1, 1)
		guard += 1
	var state: Dictionary = owner.get_debug_state()
	_expect(owner.is_presentation_complete(), "collision transaction completes in bounded slices")
	_expect(int(state.get("tree_collider_count", 0)) == 2, "collision owner created two shapes")
	_expect(int(state.get("gpu_buffer_bytes", -1)) == 0, "collision owner owns zero GPU bytes")
	_expect(int(state.get("legacy_visual_resource_count", -1)) == 0, "legacy visual resource count is zero")
	_expect(_multimesh_descendant_count(owner) == 0, "collision owner has no MultiMesh nodes")
	owner.queue_free()
	await process_frame


func _test_compositor_bypass() -> void:
	var compositor := WorldResolutionCompositor.new()
	compositor.world_render_scale = 1.0
	root.add_child(compositor)
	await process_frame
	var auxiliary: SubViewport = compositor.get("_terrain_viewport") as SubViewport
	var composite_layer: CanvasLayer = compositor.get("_composite_layer") as CanvasLayer
	_expect(compositor.get_world_viewport_rid() == root.get_viewport().get_viewport_rid(),
		"scale 1.0 routes world rendering directly through the main viewport")
	_expect(auxiliary.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"scale 1.0 disables the auxiliary SubViewport")
	_expect(not compositor.get_static_terrain_viewport_rid().is_valid(),
		"scale 1.0 reports no separately rendered terrain pass")
	_expect(composite_layer != null and not composite_layer.visible,
		"scale 1.0 disables the fullscreen blit")
	_expect(not compositor.enable_render_time_measurement,
		"render-time measurement defaults to instrumentation-off")
	compositor.world_render_scale = 0.75
	await process_frame
	_expect(compositor.get_world_viewport_rid() == auxiliary.get_viewport_rid(),
		"sub-native scale uses the bounded-resolution viewport")
	_expect(auxiliary.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"sub-native scale enables the auxiliary viewport")
	compositor.queue_free()
	await process_frame


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else { }


static func _multimesh_descendant_count(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is MultiMeshInstance2D:
			count += 1
		count += _multimesh_descendant_count(child)
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
