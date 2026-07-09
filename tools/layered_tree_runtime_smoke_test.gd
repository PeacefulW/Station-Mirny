extends SceneTree

const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")

const OBJECT_KIND_TREE: int = 4
const LAYERED_TREE_DIR: String = "res://assets/sprites/flora/layered_trees/tree_01"
const LAYERED_TREE_DIR_2: String = "res://assets/sprites/flora/layered_trees/tree_02"
const LAYERED_TREE_DIR_3: String = "res://assets/sprites/flora/layered_trees/tree_03"
const LAYERED_TREE_DIR_4: String = "res://assets/sprites/flora/layered_trees/tree_04"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var layer := WorldObjectPacketLayer.new()
	root.add_child(layer)
	layer.set_layered_tree_asset_dirs([LAYERED_TREE_DIR, LAYERED_TREE_DIR_2, LAYERED_TREE_DIR_3, LAYERED_TREE_DIR_4])
	layer.configure_packet(_single_tree_packet())
	layer.set_sun_lighting(234.0, 78.0, 0.62, 24.0)
	layer.update_ladder_z(0)

	var state: Dictionary = layer.get_debug_state()
	_assert(int(state.get("tree_count", 0)) == 4, "WorldObjectPacketLayer must consume the layered tree packet.")
	_assert(bool(state.get("uses_layered_tree_runtime", false)), "WorldObjectPacketLayer must route trees to layered runtime renderer.")
	_assert(int(state.get("layered_tree_count", 0)) == 4, "Layered runtime renderer must contain four tree instances.")
	_assert(int(state.get("layered_tree_shadow_count", 0)) == 4, "Layered runtime renderer must contain one baked sun shadow per tree.")

	var layered: Node = layer.get_node_or_null("LayeredTreeObjectLayer")
	_assert(layered != null, "LayeredTreeObjectLayer node must be created.")
	if layered != null:
		var layered_state: Dictionary = layered.call("get_debug_state") as Dictionary
		_assert(bool(layered_state.get("ready", false)), "Layered tree renderer must load layered tree metadata.")
		_assert(int(layered_state.get("asset_count", 0)) == 4, "Layered tree renderer must load all generated tree assets.")
		_assert(int(layered_state.get("loaded_asset_count", 0)) == 4, "Layered tree renderer must keep all layered tree assets ready.")
		_assert(int(layered_state.get("unique_asset_dir_count", 0)) == 4, "Layered tree renderer must use object variants to select all tree assets.")
		_assert(int(layered_state.get("instance_count", 0)) == 4, "Layered tree renderer must expose four visual trees.")
		_assert(int(layered_state.get("shadow_instance_count", 0)) == 4, "Layered tree renderer must expose four shadow trees.")
		_assert(bool(layered_state.get("has_trunk_material", false)), "Layered tree renderer must apply trunk material.")
		_assert(bool(layered_state.get("has_foliage_material", false)), "Layered tree renderer must apply foliage material.")
		_assert(bool(layered_state.get("has_snow_material", false)), "Layered tree renderer must apply snow material.")
		_assert(not bool(layered_state.get("has_normal_texture", true)), "Layered tree renderer must keep normal maps disabled for now.")
		_assert(not bool(layered_state.get("trunk_has_normal_texture", true)), "Layered trunk material must not receive the normal texture for now.")
		_assert(not bool(layered_state.get("foliage_has_normal_texture", true)), "Layered foliage material must not receive the normal texture for now.")
		_assert(not bool(layered_state.get("snow_has_normal_texture", true)), "Layered snow material must not receive the normal texture for now.")
		_assert(absf(float(layered_state.get("shadow_backward_stretch_scale", 0.0)) - 1.0) < 0.01, "Layered sun shadow must keep root side fixed.")
		_assert(not bool(layered_state.get("uses_packet_tint", true)), "Layered tree renderer must ignore packet tint for the prototype tree.")
		_assert(int(layered_state.get("unique_visual_scale_count", 0)) == 1, "Layered tree renderer must ignore packet size variability.")
		_assert(_shader_uses_scene_lighting("res://assets/shaders/layered_tree_trunk_season.gdshader"), "Layered trunk shader must follow 2D scene lighting.")
		_assert(_shader_uses_scene_lighting("res://assets/shaders/layered_tree_foliage_wind.gdshader"), "Layered foliage shader must follow 2D scene lighting.")
		_assert(_shader_uses_scene_lighting("res://assets/shaders/layered_tree_snow_accumulation.gdshader"), "Layered snow shader must follow 2D scene lighting.")
		_assert(_shader_avoids_color_double_multiply("res://assets/shaders/layered_tree_trunk_season.gdshader"), "Layered trunk shader must not multiply sampled albedo by COLOR again.")
		_assert(_shader_avoids_color_double_multiply("res://assets/shaders/layered_tree_foliage_wind.gdshader"), "Layered foliage shader must not multiply sampled albedo by COLOR again.")
		_assert(_shader_avoids_color_double_multiply("res://assets/shaders/layered_tree_snow_accumulation.gdshader"), "Layered snow shader must not multiply sampled snow by COLOR again.")
		_assert(not _shader_writes_normal_map("res://assets/shaders/layered_tree_trunk_season.gdshader"), "Layered trunk shader must not write NORMAL_MAP for now.")
		_assert(not _shader_writes_normal_map("res://assets/shaders/layered_tree_foliage_wind.gdshader"), "Layered foliage shader must not write NORMAL_MAP for now.")
		_assert(not _shader_writes_normal_map("res://assets/shaders/layered_tree_snow_accumulation.gdshader"), "Layered snow shader must not write NORMAL_MAP for now.")

	var old_tree_batch: Node = layer.get_node_or_null("TreeObjectPacketBatchLayer")
	_assert(old_tree_batch == null, "Layered runtime tree path must not create the old flat tree atlas batch.")

	layer.free()
	if _failed:
		quit(1)
		return
	print("layered_tree_runtime_smoke_test: OK")
	quit(0)


func _single_tree_packet() -> Dictionary:
	return {
		"object_kind": PackedByteArray([OBJECT_KIND_TREE, OBJECT_KIND_TREE, OBJECT_KIND_TREE, OBJECT_KIND_TREE]),
		"object_local_x_px_q4": PackedByteArray([80, 136, 192, 220]),
		"object_local_y_px_q4": PackedByteArray([128, 148, 132, 164]),
		"object_size_px": PackedByteArray([112, 180, 240, 208]),
		"object_atlas_index": PackedByteArray([0, 0, 0, 0]),
		"object_variant": PackedByteArray([0, 1, 2, 3]),
		"object_flags": PackedByteArray([1, 1, 1, 1]),
		"object_tint": PackedByteArray([64, 128, 255, 192]),
		"object_phase": PackedByteArray([0, 96, 192, 224]),
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _shader_uses_scene_lighting(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var source: String = FileAccess.get_file_as_string(path)
	return source.contains("render_mode") and not source.contains("unshaded")


func _shader_writes_normal_map(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var source: String = FileAccess.get_file_as_string(path)
	return source.contains("NORMAL_MAP")


func _shader_avoids_color_double_multiply(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var source: String = FileAccess.get_file_as_string(path)
	return not source.contains("* COLOR")
