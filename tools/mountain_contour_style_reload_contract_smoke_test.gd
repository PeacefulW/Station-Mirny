extends SceneTree

const STYLE_SOURCE: String = "res://core/systems/world/mountain_contour_style.gd"
const STREAMER_SOURCE: String = "res://core/systems/world/world_streamer.gd"
const SCENE_SOURCE: String = "res://scenes/world/world_runtime_v0_scene.gd"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var style_source: String = FileAccess.get_file_as_string(STYLE_SOURCE)
	var streamer_source: String = FileAccess.get_file_as_string(STREAMER_SOURCE)
	var scene_source: String = FileAccess.get_file_as_string(SCENE_SOURCE)

	_assert(style_source.contains("_load_texture2d_uncached"), "MountainContourStyle must load exported PNGs through an uncached image path.")
	_assert(style_source.contains("get_source_signature"), "MountainContourStyle must expose a source signature for exported package diagnostics.")
	_assert(streamer_source.contains("reload_mountain_contour_style_from_disk"), "WorldStreamer must expose an explicit dev style reload entrypoint.")
	_assert(streamer_source.contains("_refresh_mountain_contour_runtime_for_loaded_chunks"), "Style reload must re-apply loaded contour chunks.")
	_assert(scene_source.contains("KEY_F11"), "Runtime scene must expose a debug hotkey for style reload.")
	_assert(scene_source.contains("reload_mountain_contour_style_from_disk"), "F11 must call the contour style reload entrypoint.")
	quit(1 if _failed else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
