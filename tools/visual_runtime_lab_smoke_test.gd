extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/visual_runtime_lab_scene.tscn"
const MAX_READY_MSEC: int = 150000
const REQUIRED_OBJECT_KINDS: Array[int] = [2, 3, 4, 7]

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Visual runtime lab scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var snapshot: Dictionary = {}
	var deadline_msec: int = Time.get_ticks_msec() + MAX_READY_MSEC
	while Time.get_ticks_msec() < deadline_msec:
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("failed", false)) or bool(snapshot.get("ready", false)):
			break
	_assert(
		not bool(snapshot.get("failed", false)),
		"Visual runtime lab must not fail: %s" % str(snapshot),
	)
	_assert(bool(snapshot.get("ready", false)), "Visual runtime lab must become ready.")
	_assert(
		bool(snapshot.get("world_runtime_instanced", false)),
		"Visual runtime lab must instantiate production world_runtime_v0.",
	)
	_assert(int(snapshot.get("world_seed", 0)) == 707, "Visual lab seed must stay fixed.")
	_assert(
		is_equal_approx(
			float(snapshot.get("camera_zoom", -1.0)),
			float(snapshot.get("expected_min_zoom", -2.0)),
		),
		"Visual runtime lab camera must use PlayerBalance.zoom_min.",
	)
	var patch: Dictionary = snapshot.get("patch", {}) as Dictionary
	_assert(bool(patch.get("exact_match", false)), "Visual patch must be a full requested match.")
	var loading: Dictionary = snapshot.get("loading", {}) as Dictionary
	_assert(
		loading.get("target_center_chunk", Vector2i.ZERO)
			== patch.get("camera_chunk", Vector2i.ONE),
		"Production loading gate must finish at the selected camera patch.",
	)
	_assert(
		int(loading.get("target_chunk_count", 0)) == 81 \
			and int(loading.get("reserve_chunk_count", -1)) == 0,
		"Lab gate must wait for exactly the 81 production-visible chunks.",
	)
	var lake_chunk: Vector2i = patch.get("lake_chunk", Vector2i.ZERO) as Vector2i
	var mountain_chunk: Vector2i = patch.get("mountain_chunk", Vector2i.ZERO) as Vector2i
	_assert(
		mountain_chunk.x > lake_chunk.x,
		"Mountain chunk must be east/right of the lake chunk.",
	)
	_assert(
		int(patch.get("shallow_tile_count", 0)) > 0 \
			and int(patch.get("deep_tile_count", 0)) > 0,
		"Patch must contain both shallow and deep lake water.",
	)
	_assert(int(patch.get("mountain_tile_count", 0)) > 7, "Patch must contain a mountain mass.")
	var object_counts: Dictionary = patch.get("object_counts", {}) as Dictionary
	for kind: int in REQUIRED_OBJECT_KINDS:
		_assert(
			int(object_counts.get(kind, 0)) > 0,
			"Patch must contain object_kind=%d." % kind,
		)
	scene.queue_free()
	await process_frame
	if _failed:
		quit(1)
		return
	print(
		"visual_runtime_lab_smoke_test: OK patch=%s"
		% str(patch)
	)
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
