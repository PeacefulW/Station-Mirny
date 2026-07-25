extends SceneTree
## S1 contract-test: two independent instances of the measurement scene must
## resolve exactly the same world inputs and the same runtime mountain target.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_READY_FRAMES: int = 3000
const EXPECTED_PROBE_ID: String = "s1_mountain_runtime_baseline_v1"
const EXPECTED_WORLD_SEED: int = 131071
const EXPECTED_WORLD_VERSION: int = 63
const EXPECTED_WORLDGEN_SIGNATURE: String = "b797f4120400f757a08bf5a14e6a6c09721e51fd"
const EXPECTED_MOUNTAIN_TILE: Vector2i = Vector2i(2104, 464)
const EXPECTED_STAND_TILE: Vector2i = Vector2i(2103, 465)

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var first: Dictionary = await _capture_probe_run()
	var second: Dictionary = await _capture_probe_run()
	_assert(not first.is_empty(), "First deterministic probe run must finish.")
	_assert(not second.is_empty(), "Second deterministic probe run must finish.")
	_assert(first == second, "Two deterministic probe runs must match.\nfirst=%s\nsecond=%s" % [
		JSON.stringify(first),
		JSON.stringify(second),
	])
	var probe: Dictionary = first.get("probe", { }) as Dictionary
	_assert(String(probe.get("probe_id", "")) == EXPECTED_PROBE_ID, "Probe ID changed.")
	_assert(int(probe.get("world_seed", 0)) == EXPECTED_WORLD_SEED, "Probe seed changed.")
	_assert(int(probe.get("world_version", 0)) == EXPECTED_WORLD_VERSION, "Probe world version changed.")
	_assert(
		String(probe.get("worldgen_signature", "")) == EXPECTED_WORLDGEN_SIGNATURE,
		"Probe worldgen signature changed.",
	)
	_assert(first.get("mountain_tile", Vector2i.ZERO) == EXPECTED_MOUNTAIN_TILE, "Mountain target changed.")
	_assert(first.get("stand_tile", Vector2i.ZERO) == EXPECTED_STAND_TILE, "Initial stand tile changed.")
	if not _failed:
		print("mountain_runtime_dig_dev_scene_determinism_test: OK %s" % JSON.stringify(first))
	quit(1 if _failed else 0)


func _capture_probe_run() -> Dictionary:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Measurement scene must load.")
	if packed_scene == null:
		return { }
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
		"Measurement scene must not fail: %s" % str(snapshot.get("fail_reason", "")),
	)
	_assert(bool(snapshot.get("ready", false)), "Measurement scene must become ready.")
	print("S1_PROBE_READY elapsed_ms=%.3f" % float(snapshot.get("probe_ready_elapsed_ms", -1.0)))
	var canonical: Dictionary = {
		"probe": snapshot.get("probe", { }),
		"world_seed": int(snapshot.get("world_seed", 0)),
		"mountain_tile": snapshot.get("mountain_tile", Vector2i.ZERO),
		"stand_tile": snapshot.get("stand_tile", Vector2i.ZERO),
		"target_terrain_id": int(snapshot.get("target_terrain_id", -1)),
		"scanned_foot_tile_count": int(snapshot.get("scanned_foot_tile_count", 0)),
	}
	scene.queue_free()
	await process_frame
	return canonical


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
