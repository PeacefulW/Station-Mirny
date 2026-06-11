extends SceneTree

# Streaming throughput probe: after spawn settles, teleports the player a fixed
# distance and measures frames/time until the world is fully streamed, published,
# and visually uploaded. Run before/after streaming changes for an A/B number.

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const TELEPORT_OFFSETS: Array[Vector2] = [
	Vector2(6000.0, 0.0),
	Vector2(0.0, 5000.0),
	Vector2(-7000.0, -3000.0),
]
const MAX_FRAMES: int = 3600

var _streamer: Node = null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		mountain,
		bounds,
		foundation,
		lakes
	)
	var settle_frames: int = await _wait_streamed()
	print("streaming_perf_probe: initial settle frames=%d" % settle_frames)
	for offset: Vector2 in TELEPORT_OFFSETS:
		player.global_position += offset
		_streamer._update_player_chunk_coord()
		var started_usec: int = Time.get_ticks_usec()
		var frames: int = await _wait_streamed()
		var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
		print("streaming_perf_probe: offset=%s frames=%d elapsed_ms=%.0f" % [
			str(offset), frames, elapsed_ms
		])
	quit(0)

func _wait_streamed() -> int:
	for frame: int in range(MAX_FRAMES):
		await process_frame
		var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
		if not _streamer._awaiting_new_game_spawn_result \
				and not _streamer._has_pending_streaming_work() \
				and int(debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) == 0:
			return frame
	return MAX_FRAMES
