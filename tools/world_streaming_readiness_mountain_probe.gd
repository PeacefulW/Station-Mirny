extends SceneTree
## S2 headless probe: exercises the real deterministic mountain runtime and
## validates the bounded readiness snapshot without driving user input.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_READY_FRAMES: int = 3000
const SETTLE_FRAMES: int = 30
const SNAPSHOT_SOFT_LIMIT_USEC: int = 10_000

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Deterministic mountain scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var probe_state: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		probe_state = scene.call("get_debug_snapshot") as Dictionary
		if bool(probe_state.get("failed", false)) or bool(probe_state.get("ready", false)):
			break
	_assert(bool(probe_state.get("ready", false)), "Deterministic mountain probe must become ready.")
	_assert(not bool(probe_state.get("failed", false)), "Deterministic mountain probe must not fail.")
	for _frame: int in range(SETTLE_FRAMES):
		await process_frame
	var streamer: Node = get_first_node_in_group("chunk_manager")
	_assert(streamer != null, "Real mountain runtime must expose its WorldStreamer.")
	_assert(
		streamer != null and streamer.has_method("get_streaming_readiness_debug_snapshot"),
		"WorldStreamer must expose S2 diagnostics.",
	)
	if streamer == null or not streamer.has_method("get_streaming_readiness_debug_snapshot"):
		scene.queue_free()
		quit(1)
		return
	var before: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary
	var started_usec: int = Time.get_ticks_usec()
	var snapshot: Dictionary = streamer.call(
		"get_streaming_readiness_debug_snapshot",
	) as Dictionary
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	var after: Dictionary = streamer.call("get_perf_hud_snapshot") as Dictionary
	_assert(int(snapshot.get("schema_version", 0)) == 1, "Readiness schema must be version 1.")
	var entries: Array = snapshot.get("entries", []) as Array
	_assert(not entries.is_empty(), "Real working set must produce readiness entries.")
	_assert(
		entries.size() == int(snapshot.get("desired_source_count", 0)),
		"Current entries must remain bounded exactly to current source demand.",
	)
	for entry_variant: Variant in entries:
		var entry: Dictionary = entry_variant as Dictionary
		var layers: Dictionary = entry.get("layers", { }) as Dictionary
		for required_layer: String in [
			"packet", "gameplay", "terrain", "mountain_mask", "terrain_edge_mask",
			"objects", "grass", "roof_cavity", "visibility",
		]:
			_assert(layers.has(required_layer), "Entry missing layer %s." % required_layer)
			var layer: Dictionary = layers.get(required_layer, { }) as Dictionary
			if String(layer.get("state", "")) == "waiting":
				_assert(
					not String(layer.get("reason", "")).is_empty(),
					"Waiting layer %s must have one concrete reason." % required_layer,
				)
				_assert(int(layer.get("elapsed_ms", -1)) >= 0, "Waiting layer must be timed.")
		if not bool(entry.get("ready", false)):
			_assert(
				not String(entry.get("blocking_layer", "")).is_empty()
						and not String(entry.get("blocking_reason", "")).is_empty(),
				"Every missing working-set entry must have one blocker.",
			)
			_assert(
				String(entry.get("blocking_reason", "")) != "not_ready",
				"Generic not_ready is forbidden.",
			)
	_assert(
		int(before.get("requested_packets", -1)) == int(after.get("requested_packets", -2))
				and int(before.get("publish_queue", -1)) == int(after.get("publish_queue", -2))
				and int(before.get("visibility_wait", -1)) == int(after.get("visibility_wait", -2)),
		"Diagnostic read must not mutate streaming queues.",
	)
	_assert(
		elapsed_usec <= SNAPSHOT_SOFT_LIMIT_USEC,
		"Explicit bounded snapshot exceeded %d us: %d us." % [
			SNAPSHOT_SOFT_LIMIT_USEC,
			elapsed_usec,
		],
	)
	print(
		"world_streaming_readiness_mountain_probe: entries=%d missing=%d elapsed_usec=%d stages=%s reasons=%s" % [
			entries.size(),
			int(snapshot.get("missing_chunk_count", 0)),
			elapsed_usec,
			JSON.stringify(snapshot.get("stage_counts", { })),
			JSON.stringify(snapshot.get("reason_counts", { })),
		],
	)
	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
