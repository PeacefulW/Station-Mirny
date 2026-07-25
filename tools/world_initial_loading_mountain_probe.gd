extends SceneTree
## S3 integration probe: the deterministic F6 mountain scene must keep its
## viewport blocked until the complete maximum-zoom plus movement-reserve
## bubble is authoritative and materialized.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_READY_FRAMES: int = 3000
const EXPECTED_VISIBLE_RADIUS: int = 4
const EXPECTED_RESERVE_RADIUS: int = 5
const EXPECTED_VISIBLE_CHUNKS: int = 81
const EXPECTED_RESERVE_CHUNKS: int = 40
const EXPECTED_TARGET_CHUNKS: int = 121

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "S3 mountain scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var world_scene: Node = null
	var streamer: Node = null
	var player: Node = null
	var ready_state: Dictionary = { }
	var ready_snapshot: Dictionary = { }
	var observed_blocking_screen: bool = false
	for frame_index: int in range(MAX_READY_FRAMES):
		await process_frame
		if world_scene == null:
			world_scene = scene.get_node_or_null("WorldRuntimeV0")
			if world_scene != null:
				streamer = world_scene.get_node_or_null("WorldStreamer")
				player = world_scene.get_node_or_null("Player")
		if world_scene == null or streamer == null or player == null:
			continue
		var state: Dictionary = world_scene.call("get_initial_loading_state") as Dictionary
		ready_state = state
		if bool(state.get("active", false)) and not bool(state.get("ready", false)):
			var loading_screen: Node = world_scene.get_node_or_null("InitialLoadingScreen")
			_assert(loading_screen != null, "Unready initial bubble must remain covered.")
			_assert(
				player.process_mode == Node.PROCESS_MODE_DISABLED,
				"Player processing must remain disabled behind initial loading.",
			)
			observed_blocking_screen = observed_blocking_screen or loading_screen != null
		if frame_index > 0 and frame_index % 600 == 0:
			print(
				(
					"S3_LOADING_PROGRESS frame=%d stage=%s progress=%.3f generated=%d "
					+ "gameplay=%d presentation=%d reserve=%d target=%d"
				)
				% [
					frame_index,
					String(state.get("current_stage", "")),
					float(state.get("progress_ratio", 0.0)),
					int(state.get("generated_chunk_count", 0)),
					int(state.get("gameplay_ready_chunk_count", 0)),
					int(state.get("presentation_ready_chunk_count", 0)),
					int(state.get("reserve_ready_chunk_count", 0)),
					int(state.get("target_chunk_count", 0)),
				],
			)
		if bool(state.get("ready", false)):
			ready_snapshot = streamer.get_streaming_readiness_debug_snapshot()
			break
	_assert(observed_blocking_screen, "Probe must observe the blocking loading surface.")
	_assert(bool(ready_state.get("ready", false)), "Initial bubble must become ready.")
	if not bool(ready_state.get("ready", false)):
		ready_snapshot = streamer.get_streaming_readiness_debug_snapshot()
		print(
			"S3_LOADING_BLOCKED state=%s reasons=%s stages=%s"
			% [
				str(ready_state),
				str(ready_snapshot.get("reason_counts", { })),
				str(ready_snapshot.get("stage_counts", { })),
			],
		)
		scene.queue_free()
		await process_frame
		quit(1)
		return
	_assert_initial_ready_state(ready_state)
	_assert_ready_snapshot(ready_snapshot)

	var presented_state: Dictionary = ready_state
	for frame_index: int in range(MAX_READY_FRAMES):
		await process_frame
		presented_state = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(presented_state.get("presented", false)):
			break
	_assert(bool(presented_state.get("presented", false)), "First world frame must be acknowledged.")
	_assert(
		not bool(presented_state.get("active", true)),
		"Startup pin must release after presentation.",
	)
	_assert(
		int(presented_state.get("first_presented_process_frame", -1))
		>= int(presented_state.get("ready_at_process_frame", -1)),
		"First presented frame cannot precede readiness.",
	)
	_assert(
		player.process_mode != Node.PROCESS_MODE_DISABLED,
		"Player processing must resume only after the first world frame.",
	)
	if not _failed:
		print(
			(
				"world_initial_loading_mountain_probe: OK "
				+ "elapsed_ms=%d target=%d visible=%d reserve=%d "
				+ "chunks_per_second=%.3f ram=%d peak_ram=%d vram=%d "
				+ "ready_frame=%d presented_frame=%d"
			)
			% [
				int(presented_state.get("elapsed_ms", -1)),
				int(presented_state.get("target_chunk_count", -1)),
				int(presented_state.get("visible_chunk_count", -1)),
				int(presented_state.get("reserve_chunk_count", -1)),
				float(presented_state.get("prepared_chunks_per_second", 0.0)),
				int(presented_state.get("memory_static_bytes", 0)),
				int(presented_state.get("memory_static_peak_bytes", 0)),
				int(presented_state.get("video_memory_bytes", 0)),
				int(presented_state.get("ready_at_process_frame", -1)),
				int(presented_state.get("first_presented_process_frame", -1)),
			],
		)
	scene.queue_free()
	await process_frame
	await process_frame
	quit(1 if _failed else 0)


func _assert_initial_ready_state(state: Dictionary) -> void:
	_assert(bool(state.get("ready", false)), "Initial state must be ready.")
	_assert(bool(state.get("active", false)), "Ready bubble stays pinned through loading fade.")
	_assert(
		int(state.get("visible_radius_chunks", -1)) == EXPECTED_VISIBLE_RADIUS,
		"Visible target must use maximum zoom-out radius.",
	)
	_assert(
		int(state.get("reserve_radius_chunks", -1)) == EXPECTED_RESERVE_RADIUS,
		"Movement reserve must add one chunk ring.",
	)
	_assert(
		int(state.get("target_chunk_count", -1)) == EXPECTED_TARGET_CHUNKS,
		"Initial bubble target size changed.",
	)
	_assert(
		int(state.get("visible_chunk_count", -1)) == EXPECTED_VISIBLE_CHUNKS,
		"Initial visible envelope size changed.",
	)
	_assert(
		int(state.get("reserve_chunk_count", -1)) == EXPECTED_RESERVE_CHUNKS,
		"Initial movement reserve size changed.",
	)
	for count_key: String in [
		"generated_chunk_count",
		"gameplay_ready_chunk_count",
		"presentation_ready_chunk_count",
		"reserve_ready_chunk_count",
	]:
		_assert(
			int(state.get(count_key, -1)) == EXPECTED_TARGET_CHUNKS,
			"%s must cover the complete initial bubble." % count_key,
		)
	_assert(
		is_equal_approx(float(state.get("progress_ratio", 0.0)), 1.0),
		"Progress must be factual 100%.",
	)
	_assert(int(state.get("elapsed_ms", 0)) > 0, "Cold-start wall time must be measured.")
	_assert(
		float(state.get("prepared_chunks_per_second", 0.0)) > 0.0,
		"Prepared chunks/second must be measured.",
	)
	_assert(int(state.get("memory_static_bytes", 0)) > 0, "Initial bubble RAM must be measured.")
	_assert(int(state.get("ready_at_process_frame", -1)) >= 0, "Ready frame must be recorded.")
	var cumulative: Dictionary = state.get("stage_cumulative_ms", { }) as Dictionary
	var durations: Dictionary = state.get("stage_duration_ms", { }) as Dictionary
	for stage_name: String in [
		"target_established",
		"generated",
		"gameplay_ready",
		"presentation_ready",
		"reserve_ready",
	]:
		_assert(int(cumulative.get(stage_name, -1)) >= 0, "%s cumulative time missing." % stage_name)
		_assert(
			int(durations.get(stage_name, -1)) >= 0,
			"%s duration missing." % stage_name,
		)


func _assert_ready_snapshot(snapshot: Dictionary) -> void:
	_assert(
		int(snapshot.get("desired_visible_count", -1)) == EXPECTED_VISIBLE_CHUNKS,
		"S2 snapshot must see the complete visible envelope.",
	)
	_assert(
		int(snapshot.get("desired_source_count", -1)) == EXPECTED_TARGET_CHUNKS,
		"S2 snapshot must see the complete initial source bubble.",
	)
	_assert(
		int(snapshot.get("missing_chunk_count", -1)) == 0,
		"No initial target chunk may retain a readiness blocker.",
	)
	var stage_counts: Dictionary = snapshot.get("stage_counts", { }) as Dictionary
	_assert(
		int(stage_counts.get("visible", 0)) == EXPECTED_VISIBLE_CHUNKS,
		"Every maximum-zoom chunk must be visible behind the loading surface.",
	)
	_assert(
		int(stage_counts.get("reserve_ready", 0)) == EXPECTED_RESERVE_CHUNKS,
		"Every outer reserve chunk must be fully prepared and hidden.",
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
