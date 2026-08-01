extends SceneTree
## Static smoke test for Player Helmet Lamps V1 (Iteration 1).
## Spec: docs/02_system_specs/progression/player_helmet_lamps_v1.md
##
## Source text is inspected rather than instantiated: the player scene pulls the
## `Localization` autoload, which does not exist in a `--script` run.

const LAMPS_SCRIPT_PATH: String = "res://core/entities/player/player_helmet_lamps.gd"
const PLAYER_SCRIPT_PATH: String = "res://core/entities/player/player.gd"
const TORCH_SCRIPT_PATH: String = "res://core/entities/player/player_torch.gd"
const SCENE_PATH: String = "res://scenes/player/player.tscn"

var _failed: bool = false


func _init() -> void:
	var lamps: String = FileAccess.get_file_as_string(LAMPS_SCRIPT_PATH)
	var player: String = FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH)
	var torch: String = FileAccess.get_file_as_string(TORCH_SCRIPT_PATH)
	var scene: String = FileAccess.get_file_as_string(SCENE_PATH)

	_assert(not lamps.is_empty(), "player_helmet_lamps.gd must be readable")
	_assert(
		lamps.contains("const TOGGLE_KEYCODE: int = KEY_L"),
		"Helmet lamps must toggle on L.",
	)
	_assert(
		torch.contains("const TOGGLE_KEYCODE: int = KEY_F"),
		"Torch must keep its own key until Iteration 2 migrates it.",
	)
	_assert(
		lamps.contains("static var _cached_cone_textures"),
		"Cone textures must be built once and cached, not per toggle.",
	)
	_assert(
		lamps.contains("light.shadow_enabled = false"),
		"Helmet lamps must not use engine shadow maps; mountain occlusion is MountainTorchShadowField's job.",
	)
	_assert(
		lamps.contains("_enabled: bool = false"),
		"Helmet lamps must start switched off.",
	)
	_assert(
		player.contains("func get_visual_facing_vector() -> Vector2:"),
		"Player must expose a continuous facing vector for the lamps to aim with.",
	)
	_assert(
		scene.contains("[node name=\"HelmetLamps\" type=\"Node2D\" parent=\".\"]"),
		"Player scene must carry the HelmetLamps node.",
	)
	# ADR-0005: these are visual only. Nothing here may claim visibility authority.
	_assert(
		not lamps.contains("is_cell_indoor") and not lamps.contains("get_visibility"),
		"Helmet lamps must not become a gameplay visibility authority (ADR-0005).",
	)

	if _failed:
		quit(1)
		return
	print("player_helmet_lamps_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
