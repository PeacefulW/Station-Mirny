extends SceneTree

const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldPreviewController = preload("res://core/systems/world/world_preview_controller.gd")

var _failed: bool = false

func _init() -> void:
	_assert_backend_preserves_request_identity()
	_assert_stage_plan_wraps_x_and_clips_y()
	if _failed:
		quit(1)
		return
	print("world_preview_edge_wrap_smoke_test: OK")
	quit(0)

func _assert_backend_preserves_request_identity() -> void:
	var backend := WorldChunkPacketBackend.new()
	var requested_coord := Vector2i(-1, 7)
	var canonical_coord := Vector2i(63, 7)
	backend._append_completed_packets(
		[{
			"coord": requested_coord,
			"epoch": 42,
		}],
		[{
			"chunk_coord": canonical_coord,
			"terrain_ids": PackedInt32Array(),
		}]
	)
	var completed: Array[Dictionary] = backend.drain_completed_packets(1)
	_assert(completed.size() == 1, "backend should publish one completed packet")
	var packet: Dictionary = completed[0] if not completed.is_empty() else {}
	_assert(packet.get("request_chunk_coord", Vector2i.ZERO) == requested_coord, "preview request identity should survive X wrap")
	_assert(packet.get("chunk_coord", Vector2i.ZERO) == canonical_coord, "native canonical chunk_coord should stay unchanged")
	_assert(int(packet.get("epoch", -1)) == 42, "epoch should stay attached to completed packet")

func _assert_stage_plan_wraps_x_and_clips_y() -> void:
	var controller := WorldPreviewController.new()
	controller._active_world_bounds = WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var plans: Array[Dictionary] = controller._build_stage_plans(Vector2i.ZERO)
	_assert(not plans.is_empty(), "stage planner should build preview stages")
	var first_window: Array[Vector2i] = controller._coerce_chunk_coords((plans[0] as Dictionary).get("window_coords", []))
	_assert(first_window.has(Vector2i(-1, 0)), "stage window should keep negative X display coords for wrap preview")
	for chunk_coord: Vector2i in first_window:
		_assert(chunk_coord.y >= 0, "stage window should not request chunks above finite Y bounds")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
