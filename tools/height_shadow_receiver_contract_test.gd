extends SceneTree

const WorldHeightShadowProfile = preload(
	"res://core/systems/world/world_height_shadow_profile.gd"
)
const DepthLadderBandRoot = preload(
	"res://core/systems/world/depth_ladder_band_root.gd"
)
const HEIGHT_PROFILE: WorldHeightShadowProfile = preload(
	"res://data/world_objects/presentation_profiles/world_height_shadow_profile.tres"
)

var _failures: Array[String] = []


func _init() -> void:
	_check_height_contract()
	_check_visibility_contract()
	_check_shader_receiver_contract()
	_check_runtime_wiring_contract()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	print("height_shadow_receiver_contract_test: PASS")
	quit(0)


func _check_height_contract() -> void:
	_expect(
		HEIGHT_PROFILE.tree_height > HEIGHT_PROFILE.small_rock_height,
		"tree caster height must exceed small-rock receiver height",
	)
	_expect(
		HEIGHT_PROFILE.caster_class == WorldHeightShadowProfile.ReceiverClass.TREE,
		"authored field caster class must resolve to tree",
	)
	_expect(
		HEIGHT_PROFILE.small_rock_height > HEIGHT_PROFILE.grass_height,
		"small-rock receiver height must exceed grass receiver height",
	)
	_expect(
		HEIGHT_PROFILE.mask_resolution_scale > 0.0
				and HEIGHT_PROFILE.mask_resolution_scale <= 1.0,
		"height shadow mask scale must stay bounded to the main viewport",
	)
	_expect(
		is_equal_approx(
			HEIGHT_PROFILE.height_for(WorldHeightShadowProfile.ReceiverClass.GRASS),
			HEIGHT_PROFILE.grass_height,
		),
		"authored receiver class lookup must resolve the grass height",
	)


func _check_visibility_contract() -> void:
	var ancestor := Node2D.new()
	var child := Node2D.new()
	ancestor.add_child(child)
	WorldHeightShadowProfile.mark_tall_caster_path(child)
	var caster_layer: int = WorldHeightShadowProfile.CASTER_VISIBILITY_LAYER
	_expect(
		(child.visibility_layer & caster_layer) != 0,
		"tall caster leaf must opt into the dedicated cull layer",
	)
	_expect(
		(ancestor.visibility_layer & caster_layer) != 0,
		"every CanvasItem ancestor must opt into the dedicated cull layer",
	)

	var ladder := DepthLadderBandRoot.new()
	ladder.include_visibility_layer(caster_layer)
	_expect(
		(ladder.visibility_layer & caster_layer) != 0,
		"depth ladder root must expose the caster cull layer",
	)
	_expect(ladder.get_child_count() == 3, "depth ladder must keep its fixed three-band graph")
	for child_index: int in range(ladder.get_child_count()):
		var band_root: Node2D = ladder.get_child(child_index) as Node2D
		_expect(
			band_root != null and (band_root.visibility_layer & caster_layer) != 0,
			"every future stripe migration target must expose the caster cull layer",
		)
	ancestor.free()
	ladder.free()


func _check_shader_receiver_contract() -> void:
	var include_source := FileAccess.get_file_as_string(
		"res://assets/shaders/includes/world_height_shadow_receiver.gdshaderinc",
	)
	_expect(
		include_source.contains("height_shadow_caster_height")
				and include_source.contains("height_shadow_receiver_height"),
		"receiver include must compare caster and receiver height metadata",
	)
	_expect(
		include_source.contains("texture(height_shadow_mask, screen_uv).a"),
		"receiver include must sample the camera-aligned caster mask",
	)
	for shader_path: String in [
		"res://assets/shaders/grass_scatter_batch.gdshader",
		"res://assets/shaders/layered_object_albedo_batch.gdshader",
		"res://assets/shaders/layered_object_snow_batch.gdshader",
	]:
		var shader_source := FileAccess.get_file_as_string(shader_path)
		_expect(
			shader_source.contains("world_height_shadow_receiver.gdshaderinc")
					and shader_source.contains("apply_world_height_shadow"),
			"%s must use the shared height-shadow receiver contract" % shader_path,
		)
	for non_receiver_path: String in [
		"res://assets/shaders/layered_tree_trunk_batch.gdshader",
		"res://assets/shaders/layered_tree_foliage_batch.gdshader",
	]:
		var non_receiver_source := FileAccess.get_file_as_string(non_receiver_path)
		_expect(
			not non_receiver_source.contains("apply_world_height_shadow"),
			"%s must stay above projected shadows as a non-receiver"
					% non_receiver_path,
		)


func _check_runtime_wiring_contract() -> void:
	var scene_source := FileAccess.get_file_as_string(
		"res://scenes/world/world_runtime_v0.tscn",
	)
	var runtime_source := FileAccess.get_file_as_string(
		"res://scenes/world/world_runtime_v0_scene.gd",
	)
	var streamer_source := FileAccess.get_file_as_string(
		"res://core/systems/world/world_streamer.gd",
	)
	var tree_batch_source := FileAccess.get_file_as_string(
		"res://core/systems/world/layered_tree_batch_layer.gd",
	)
	_expect(
		scene_source.contains("WorldHeightShadowField")
				and scene_source.contains("world_height_shadow_field.gd"),
		"production world scene must own the bounded height-shadow field",
	)
	_expect(
		runtime_source.contains("bind_height_shadow_field"),
		"production root must bind the field after child readiness",
	)
	_expect(
		streamer_source.contains("ReceiverClass.GRASS")
				and streamer_source.contains("ReceiverClass.SMALL_ROCK")
				and streamer_source.contains("get_rock_albedo_material")
				and streamer_source.contains("get_rock_snow_material"),
		"WorldStreamer must bind grass and both rock channels as low receivers",
	)
	_expect(
		tree_batch_source.contains("mark_tall_caster_path")
				and tree_batch_source.contains("include_visibility_layer"),
		"native tree shadows must enter the dedicated cull pass across ladder migrations",
	)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
