extends SceneTree

const SHADER_FIELD_SCRIPT_PATH: String = "res://core/systems/world/mountain_torch_shadow_field.gd"
const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const PLAYER_TORCH_PATH: String = "res://core/entities/player/player_torch.gd"
const CHUNK_VIEW_PATH: String = "res://core/systems/world/chunk_view.gd"
const WORLD_STREAMER_PATH: String = "res://core/systems/world/world_streamer.gd"
const SHADER_PATH: String = "res://assets/shaders/mountain_torch_shadow_field.gdshader"

var _failed: bool = false


func _init() -> void:
	_assert_shadow_field_is_live()
	_assert_engine_occluder_path_is_retired()
	_assert_shader_field_uses_soft_visibility()
	quit(1 if _failed else 0)


func _assert_shadow_field_is_live() -> void:
	_assert(FileAccess.file_exists(SHADER_FIELD_SCRIPT_PATH), "live MountainTorchShadowField script must exist")
	var scene_source: String = FileAccess.get_file_as_string(WORLD_SCENE_PATH)
	_assert(
		scene_source.contains("res://core/systems/world/mountain_torch_shadow_field.gd"),
		"world_runtime_v0.tscn must instantiate MountainTorchShadowField",
	)


func _assert_engine_occluder_path_is_retired() -> void:
	var torch_source: String = FileAccess.get_file_as_string(PLAYER_TORCH_PATH)
	var chunk_view_source: String = FileAccess.get_file_as_string(CHUNK_VIEW_PATH)
	var streamer_source: String = FileAccess.get_file_as_string(WORLD_STREAMER_PATH)
	_assert(torch_source.contains("shadow_enabled = false"), "PlayerTorch must not use engine shadow maps for mountain torch occlusion")
	_assert(not torch_source.contains("MOUNTAIN_OCCLUDER_LIGHT_LAYER"), "PlayerTorch must not keep the old occluder cull layer")
	_assert(not chunk_view_source.contains("mountain_light_occluder"), "ChunkView must not keep the retired mountain LightOccluder2D path")
	_assert(not chunk_view_source.contains("mountain_occluder"), "ChunkView must not keep retired mountain occluder helpers")
	_assert(not streamer_source.contains("_update_mountain_light_occluders"), "WorldStreamer must not update retired mountain LightOccluder2D geometry")
	_assert(not streamer_source.contains("MOUNTAIN_LIGHT_OCCLUDER_CHUNK_RADIUS"), "WorldStreamer must not keep retired occluder proximity state")


func _assert_shader_field_uses_soft_visibility() -> void:
	var shader_source: String = FileAccess.get_file_as_string(SHADER_PATH)
	_assert(shader_source.contains("visibility"), "shadow field shader should accumulate soft visibility, not hard max-only blocking")
	_assert(not shader_source.contains("blocked = max(blocked"), "shadow field shader must not use a hard max-only umbra march")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
