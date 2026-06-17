extends SceneTree

# Крупный план травы (зум 2.6) на самом густом загруженном чанке: видны форма
# пучков, тёмные корни, подложка, макро-вариация и (если есть) тени/споры.
# Windowed. Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --path . -s tools/grass_closeup_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const OUTPUT_DIR: String = "res://artifacts/grass_runtime_probe"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("grass_closeup_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var streamer: Node = scene.get_node("WorldStreamer")
	var tm: Node = root.get_node("TimeManager")
	var cam: Camera2D = scene.get_node("Player/Camera2D")
	var player: Node2D = scene.get_node("Player")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
	)
	tm.call("set_paused", true)
	tm.call("restore_persisted_state", 12.0, 1, 0)
	tm.call("set_paused", true)
	cam.enabled = true
	cam.position_smoothing_enabled = false
	cam.set_process(false)
	DirAccess.open("res://").make_dir_recursive("artifacts/grass_runtime_probe")
	await _settle(streamer)
	# Чанк умеренной плотности: на густейшем трава прячет тени на земле, нужен
	# участок где видны и кустики, и грунт между ними.
	var best := Vector2i.ZERO
	var bestc: int = -1
	for k: Variant in streamer._chunk_views.keys():
		var c: int = int((streamer._chunk_views[k] as Node).get_grass_scatter_debug_state().get("instance_count", 0))
		if c >= 600 and c <= 1500 and c > bestc:
			bestc = c
			best = k
	if bestc < 0:
		for k: Variant in streamer._chunk_views.keys():
			var c: int = int((streamer._chunk_views[k] as Node).get_grass_scatter_debug_state().get("instance_count", 0))
			if c > bestc:
				bestc = c
				best = k
	player.global_position = WorldRuntimeConstants.chunk_origin_px(best) + Vector2(512, 512)
	streamer._update_player_chunk_coord()
	cam.zoom = Vector2(2.6, 2.6)
	cam.set("_target_zoom", 2.6)
	await _settle(streamer)
	streamer._sync_sun_lighting_from_time(true)
	cam.force_update_scroll()
	for _i: int in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/grounded_full.png" % OUTPUT_DIR)
	var crop := Vector2i(600, 460)
	var origin := Vector2i((img.get_width() - crop.x) / 2, (img.get_height() - crop.y) / 2)
	img.get_region(Rect2i(origin, crop)).save_png("%s/grounded_closeup.png" % OUTPUT_DIR)
	print("grass_closeup_probe: saved grounded_closeup.png chunk=%s grass=%d" % [str(best), bestc])
	scene.queue_free()
	await process_frame
	quit(0)


func _settle(streamer: Node) -> void:
	for _i: int in range(500):
		streamer._streaming_tick()
		streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		if streamer._requested_chunks.is_empty() and not streamer._has_pending_streaming_work():
			return
