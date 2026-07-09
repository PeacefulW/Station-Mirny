extends SceneTree
## Smoke-тест dev-сцены «копаем рантайм-гору»: сцена должна подняться на
## настоящем world_runtime_v0, найти гору, поставить игрока к её краю и
## закоммитить копок публичным путём try_harvest_at_world.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_READY_FRAMES: int = 3000
const MAX_SETTLE_FRAMES: int = 1800

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Mountain runtime dig dev scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("failed", false)) or bool(snapshot.get("ready", false)):
			break
	_assert(
		not bool(snapshot.get("failed", false)),
		"Dev scene must not fail: %s" % str(snapshot.get("fail_reason", "")),
	)
	_assert(bool(snapshot.get("ready", false)), "Dev scene must become ready (spawn + teleport).")
	if not bool(snapshot.get("ready", false)):
		quit(1)
		return
	for _frame: int in range(MAX_SETTLE_FRAMES):
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if _is_settled(snapshot):
			break
		await process_frame
	_assert(_is_settled(snapshot), "Mountain native masks must settle near the dig spot.")
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	_assert(
		bool(native.get("native_mask_runtime_enabled", false)),
		"Dev scene must run on native mountain masks (runtime presentation).",
	)
	_assert(
		int(native.get("ready_native_mask_chunk_count", 0)) > 0,
		"Dev scene must have ready native mountain mask chunks.",
	)
	var target_terrain_id: int = int(snapshot.get("target_terrain_id", -1))
	_assert(
		target_terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or target_terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
		"Dig target must be a runtime mountain wall or foot tile.",
	)
	_assert(
		int(snapshot.get("scanned_foot_tile_count", 0)) > 0,
		"Scan must see mountain foot tiles (foot как в рантайме).",
	)
	_assert(
		bool(snapshot.get("stand_walkable", false)),
		"Player stand tile next to the mountain must be walkable.",
	)
	var dig: Dictionary = scene.call("debug_dig_target_once") as Dictionary
	_assert(
		bool(dig.get("success", false)),
		"Dig into the runtime mountain must commit a harvest: %s" % str(dig),
	)
	_assert(
		bool(dig.get("walkable_after", false)),
		"Mined mountain tile center must become walkable (вкопались в гору).",
	)
	scene.queue_free()
	await process_frame
	if _failed:
		quit(1)
		return
	print("mountain_runtime_dig_dev_scene_smoke_test: OK")
	quit(0)

func _is_settled(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("ready", false)):
		return false
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	if native.is_empty():
		return false
	if int(native.get("missing_mountain_chunk_count", 99)) > 0:
		return false
	# Игрок стоит вплотную к горе, поэтому маски обязаны появиться:
	# нулевой счётчик означает, что desired-набор ещё не пересчитан после
	# телепорта, а не «гор нет».
	if int(native.get("ready_native_mask_chunk_count", 0)) <= 0:
		return false
	if bool(native.get("dirty", false)) or bool(native.get("request_in_flight", false)):
		return false
	if int(native.get("native_mask_visual_upload_queue_count", 0)) > 0 \
			or int(native.get("native_mask_visual_pending_count", 0)) > 0:
		return false
	return bool(snapshot.get("stand_walkable", false))

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
