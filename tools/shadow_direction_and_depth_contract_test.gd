extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const AssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")
const TreeBatchLayer = preload("res://core/systems/world/layered_tree_batch_layer.gd")
const RockBatchLayer = preload("res://core/systems/world/layered_rock_batch_layer.gd")
const BushBatchLayer = preload("res://core/systems/world/layered_bush_batch_layer.gd")

const NORTH_STRIPE: int = 8
const SOUTH_STRIPE: int = 20
const ANCHOR_STRIPE: int = 12
const EPSILON: float = 0.00001

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_fixed_sun_contract()
	var catalog: AssetCatalog = AssetCatalog.new()
	_expect(catalog.is_ready(), "layered object catalog must be ready")
	if catalog.is_ready():
		_verify_tree_depth(catalog)
		_verify_rock_depth(catalog)
		_verify_bush_depth(catalog)
	await process_frame
	if _failures.is_empty():
		print("shadow_direction_and_depth_contract_test: OK")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _verify_fixed_sun_contract() -> void:
	var expected_light_angle: float = WorldVisualLightingProfile.FIXED_LIGHT_ANGLE_DEG
	var expected_shadow_direction: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION
	for hour: float in [0.0, 6.0, 12.0, 18.0, 23.5]:
		_expect(
			is_equal_approx(
				WorldVisualLightingProfile.light_angle_deg_for_hour(hour),
				expected_light_angle,
			),
			"visual sun azimuth must stay fixed at hour %.1f" % hour,
		)
	var time_manager_source: String = FileAccess.get_file_as_string(
		"res://core/autoloads/time_manager.gd",
	)
	_expect(
		time_manager_source.contains(
			"return deg_to_rad(WorldVisualLightingProfile.FIXED_LIGHT_ANGLE_DEG)",
		),
		"TimeManager must delegate its visual sun azimuth to the shared fixed profile",
	)
	var packet_layer_source: String = FileAccess.get_file_as_string(
		"res://core/systems/world/world_object_packet_layer.gd",
	)
	_expect(
		packet_layer_source.contains(
			"var _sun_light_angle_deg: float = "
					+ "WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG",
		),
		"packet-layer fallback must start on the shared fixed visual azimuth",
	)
	var asset_lab_source: String = FileAccess.get_file_as_string(
		"res://scenes/dev/layered_tree_asset_lab_scene.gd",
	)
	_expect(
		asset_lab_source.contains(
			"const SHADOW_DIRECTION: Vector2 = "
					+ "WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION",
		),
		"tree asset lab must preview the same south-east shadow contract",
	)
	var runtime_shadow_direction := Vector2.RIGHT.rotated(
		deg_to_rad(expected_light_angle + 180.0),
	).normalized()
	_expect(
		runtime_shadow_direction.distance_to(expected_shadow_direction) <= EPSILON,
		"fixed visual sun must project along the authored layered-asset direction",
	)
	_expect(
		runtime_shadow_direction.x > 0.0 and runtime_shadow_direction.y > 0.0,
		"all sun shadows must point screen south-east",
	)
	for family_direction: Vector2 in [
		AssetCatalog.TREE_SHADOW_DIRECTION,
		AssetCatalog.SHADOW_DIRECTION,
		AssetCatalog.BUSH_SHADOW_DIRECTION,
	]:
		_expect(
			family_direction.distance_to(expected_shadow_direction) <= EPSILON,
			"every migrated layered family must share the fixed south-east direction",
		)
	var dawn_low_sun: float = WorldVisualLightingProfile.low_sun_for_progress(
		WorldVisualLightingProfile.sun_progress_for_hour(6.0),
	)
	var noon_low_sun: float = WorldVisualLightingProfile.low_sun_for_progress(
		WorldVisualLightingProfile.sun_progress_for_hour(12.0),
	)
	_expect(
		WorldVisualLightingProfile.shadow_length_px_for_low_sun(dawn_low_sun)
				> WorldVisualLightingProfile.shadow_length_px_for_low_sun(noon_low_sun),
		"dawn/dusk must stretch a fixed-direction shadow farther than noon",
	)


func _verify_tree_depth(catalog: AssetCatalog) -> void:
	var layer: TreeBatchLayer = TreeBatchLayer.new()
	root.add_child(layer)
	layer.configure_catalog(catalog)
	layer.reserve_pool_slots(2)
	_expect(
		layer.begin_apply({"tree_atlas_bucket_buffers": _two_stripe_buffers()}),
		"tree batch must accept the synthetic depth payload",
	)
	_drain_layer(layer)
	layer.set_world_origin_y(0.0)
	layer.update_ladder_z(ANCHOR_STRIPE)
	_verify_four_channel_family(layer, "TreeBatch", "tree")
	_expect(
		int((layer.get_debug_state().get("depth_ladder", {}) as Dictionary).get(
			"registered_item_count",
			-1,
		)) == 8,
		"tree ladder must own shadow plus three visual channels for each stripe",
	)
	layer.free()


func _verify_bush_depth(catalog: AssetCatalog) -> void:
	var layer: BushBatchLayer = BushBatchLayer.new()
	root.add_child(layer)
	layer.configure_catalog(catalog)
	layer.reserve_pool_slots(2)
	_expect(
		layer.begin_apply({"bush_atlas_bucket_buffers": _two_stripe_buffers()}),
		"bush batch must accept the synthetic depth payload",
	)
	_drain_layer(layer)
	layer.set_world_origin_y(0.0)
	layer.update_ladder_z(ANCHOR_STRIPE)
	_verify_four_channel_family(layer, "BushBatch", "bush")
	_expect(
		int((layer.get_debug_state().get("depth_ladder", {}) as Dictionary).get(
			"registered_item_count",
			-1,
		)) == 8,
		"bush ladder must own shadow plus three visual channels for each stripe",
	)
	layer.free()


func _verify_rock_depth(catalog: AssetCatalog) -> void:
	var layer: RockBatchLayer = RockBatchLayer.new()
	root.add_child(layer)
	layer.configure_catalog(catalog)
	layer.reserve_pool_slots(2)
	_expect(
		layer.begin_apply({"rock_atlas_bucket_buffers": _two_stripe_buffers()}),
		"rock batch must accept the synthetic depth payload",
	)
	_drain_layer(layer)
	layer.set_world_origin_y(0.0)
	layer.update_ladder_z(ANCHOR_STRIPE)
	var north_shadow: CanvasItem = _find_canvas_item(layer, "RockBatch0Shadow")
	var north_body: CanvasItem = _find_canvas_item(layer, "RockBatch0Albedo")
	var north_snow: CanvasItem = _find_canvas_item(layer, "RockBatch0Snow")
	var south_shadow: CanvasItem = _find_canvas_item(layer, "RockBatch1Shadow")
	var south_body: CanvasItem = _find_canvas_item(layer, "RockBatch1Albedo")
	if north_shadow != null \
			and north_body != null \
			and north_snow != null \
			and south_shadow != null \
			and south_body != null:
		_expect(
			_effective_z(north_shadow) + 1 == _effective_z(north_body),
			"rock shadow must render directly below its body",
		)
		_expect(
			_effective_z(north_body) + 1 == _effective_z(north_snow),
			"rock snow must render directly above its body",
		)
		_expect(
			_effective_z(north_shadow) < _effective_z(south_body),
			"north rock shadow must remain below a southern object",
		)
		_expect(
			_effective_z(north_shadow) < _effective_z(south_shadow),
			"rock shadows must preserve north-to-south caster order",
		)
	_expect(
		int((layer.get_debug_state().get("depth_ladder", {}) as Dictionary).get(
			"registered_item_count",
			-1,
		)) == 6,
		"rock ladder must own all three channels for each stripe",
	)
	layer.free()


func _verify_four_channel_family(layer: Node, prefix: String, family: String) -> void:
	var north_shadow: CanvasItem = _find_canvas_item(layer, "%s0Shadow" % prefix)
	var north_trunk: CanvasItem = _find_canvas_item(layer, "%s0Trunk" % prefix)
	var north_foliage: CanvasItem = _find_canvas_item(layer, "%s0Foliage" % prefix)
	var north_snow: CanvasItem = _find_canvas_item(layer, "%s0Snow" % prefix)
	var south_shadow: CanvasItem = _find_canvas_item(layer, "%s1Shadow" % prefix)
	var south_trunk: CanvasItem = _find_canvas_item(layer, "%s1Trunk" % prefix)
	if north_shadow == null \
			or north_trunk == null \
			or north_foliage == null \
			or north_snow == null \
			or south_shadow == null \
			or south_trunk == null:
		return
	_expect(
		north_shadow.get_parent() == north_trunk.get_parent(),
		"%s shadow and body must share one depth-band owner" % family,
	)
	_expect(
		_effective_z(north_shadow) + 1 == _effective_z(north_trunk),
		"%s shadow must render directly below its trunk" % family,
	)
	_expect(
		_effective_z(north_trunk) + 1 == _effective_z(north_foliage),
		"%s foliage must render directly above its trunk" % family,
	)
	_expect(
		_effective_z(north_foliage) + 1 == _effective_z(north_snow),
		"%s snow must render directly above its foliage" % family,
	)
	_expect(
		_effective_z(north_shadow) < _effective_z(south_trunk),
		"north %s shadow must remain below a southern object" % family,
	)
	_expect(
		_effective_z(north_shadow) < _effective_z(south_shadow),
		"%s shadows must preserve north-to-south caster order" % family,
	)


func _two_stripe_buffers() -> Array[PackedFloat32Array]:
	var buffers: Array[PackedFloat32Array] = []
	for _stripe_index: int in range(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK):
		buffers.append(PackedFloat32Array())
	buffers[NORTH_STRIPE] = _single_instance_buffer(
		float(NORTH_STRIPE * WorldRuntimeConstants.DEPTH_STRIPE_PX),
	)
	buffers[SOUTH_STRIPE] = _single_instance_buffer(
		float(SOUTH_STRIPE * WorldRuntimeConstants.DEPTH_STRIPE_PX),
	)
	return buffers


func _single_instance_buffer(y: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		64.0, 0.0, 0.0, 128.0,
		0.0, 64.0, 0.0, y,
		0.0, 1.0, 0.5, 1.0,
	])


func _drain_layer(layer: Node) -> void:
	var guard: int = 0
	var has_more: bool = true
	while has_more:
		has_more = bool(layer.call("apply_next_batch", 4))
		guard += 1
		if guard > WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK:
			_expect(false, "%s incremental apply did not finish" % layer.name)
			return


func _find_canvas_item(owner: Node, item_name: String) -> CanvasItem:
	var item: Node = owner.find_child(item_name, true, false)
	_expect(item is CanvasItem, "%s must exist" % item_name)
	return item as CanvasItem


func _effective_z(item: CanvasItem) -> int:
	var result: int = 0
	var current: Node = item
	while current is CanvasItem:
		var canvas_item: CanvasItem = current as CanvasItem
		if not canvas_item.z_as_relative:
			return canvas_item.z_index
		result += canvas_item.z_index
		current = current.get_parent()
	return result


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
