extends SceneTree

var _failed: bool = false


func _init() -> void:
	var player_source: String = FileAccess.get_file_as_string("res://core/entities/player/player.gd")
	var player_scene_source: String = FileAccess.get_file_as_string("res://scenes/player/player.tscn")
	var debug_layer_source: String = FileAccess.get_file_as_string("res://core/systems/world/object_collision_debug_layer.gd")
	var runtime_scene_source: String = FileAccess.get_file_as_string("res://scenes/world/world_runtime_v0_scene.gd")

	_assert(
		player_source.contains("func set_debug_collision_visible(enabled: bool) -> void:"),
		"Player must expose a debug collision visibility toggle for F11.",
	)
	_assert(
		player_source.contains("PlayerCollisionDebugLayer"),
		"Player must create a named local collision debug layer.",
	)
	_assert(
		player_source.contains("get_node_or_null(\"CollisionShape2D\")"),
		"Player debug overlay must derive boxes from the body CollisionShape2D.",
	)
	_assert(
		player_source.contains("layer.set_debug_boxes(_build_collision_debug_rects())"),
		"Player debug overlay must publish collision boxes to ObjectCollisionDebugLayer.",
	)
	_assert(
		player_source.contains("func _resolve_blocking_local_center() -> Vector2:")
				and player_source.contains("var sample_center: Vector2 = target_pos + _resolve_blocking_local_center()"),
		"Player terrain blocking samples must follow the shifted body CollisionShape2D center.",
	)
	_assert(
		player_scene_source.contains("size = Vector2(24, 16)"),
		"Player body collision must be narrow and roughly half as tall as the previous torso box.",
	)
	_assert(
		player_scene_source.contains("[node name=\"CollisionShape2D\" type=\"CollisionShape2D\" parent=\".\" unique_id=543236914]\nposition = Vector2(0, 15)\nshape = SubResource(\"player_shape\")"),
		"Player body collision must remain authored around the feet.",
	)
	# Значение выведено из кадра спрайта: (288/2 - offset 16px) * scale 0.30.
	# Меняется вместе с раскладкой атласа (player_visual_presentation_v1.md).
	_assert(
		player_source.contains("const PLAYER_FEET_OFFSET_PX: float = 38.4"),
		"Player depth sorting must retain the grass-safe visual-feet anchor.",
	)
	var streamer_source: String = FileAccess.get_file_as_string(
		"res://core/systems/world/world_streamer.gd",
	)
	_assert(
		streamer_source.contains("player.global_position.y + Player.PLAYER_FEET_OFFSET_PX"),
		"WorldStreamer must keep grass and the player on the visual-feet ladder.",
	)
	_assert(
		debug_layer_source.contains("func get_debug_box_count() -> int:"),
		"Collision debug layer must expose box count for smoke verification.",
	)
	_assert(
		runtime_scene_source.contains("var debug_collisions_visible: bool = _world_streamer.toggle_debug_object_collisions()")
				and runtime_scene_source.contains("_set_player_debug_collision_visible(debug_collisions_visible)"),
		"F11 must pass the world object collision debug state to the local player.",
	)

	if _failed:
		quit(1)
		return
	print("player_collision_debug_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
