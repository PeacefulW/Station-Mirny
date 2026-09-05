extends SceneTree

const MAIN_MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const MAX_FRAMES := 8000
const REPORT_INTERVAL_FRAMES := 300


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(MAIN_MENU_SCENE_PATH) as PackedScene
	if packed == null:
		quit(1)
		return
	var menu := packed.instantiate()
	root.add_child(menu)
	current_scene = menu
	for _warmup_frame: int in range(5):
		await process_frame
	var panel: Node = menu.get("_new_game_panel") as Node
	if panel == null:
		push_error("main menu did not create the new-game panel")
		quit(1)
		return
	var seed_value: int = int(panel.get("_preview_seed_value"))
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if not user_args.is_empty() and user_args[0].is_valid_int():
		seed_value = int(user_args[0])
	print("MAIN_MENU_STARTUP seed=%d" % seed_value)
	menu.call(
		"_on_new_game_start_requested",
		seed_value,
		panel.get("_settings"),
		panel.get("_world_bounds"),
		panel.get("_foundation_settings"),
		panel.get("_lake_settings"),
	)
	for frame: int in range(MAX_FRAMES):
		await process_frame
		var world: Node = current_scene
		if world == null or not world.has_method("get_initial_loading_state"):
			continue
		var loading: Dictionary = world.call("get_initial_loading_state") as Dictionary
		if frame % REPORT_INTERVAL_FRAMES == 0 or bool(loading.get("ready", false)):
			var streamer: Node = world.get_node_or_null("WorldStreamer")
			var debug: Dictionary = { }
			if streamer != null:
				var readiness: Dictionary = streamer.call(
					"get_streaming_readiness_debug_snapshot",
				) as Dictionary
				var backend: Object = streamer.get("_world_compute_backend") as Object
				var renderer: Node = streamer.get("_world_render_world") as Node
				debug = {
					"object_results": (streamer.get("_object_presentation_results_by_chunk") as Dictionary).size(),
					"grass_results": (streamer.get("_grass_scatter_results_by_chunk") as Dictionary).size(),
					"render_residency": (streamer.get("_world_render_residency_by_chunk") as Dictionary).size(),
					"render_refresh_pending": bool(streamer.get("_world_render_refresh_pending")),
					"render_inflight_generation": int(streamer.get("_world_render_inflight_generation")),
					"render_request_generation": int(streamer.get("_world_render_request_generation")),
					"render_has_completed": bool(backend.call("has_completed_world_render_snapshots")),
					"backend_pending": bool(backend.call("has_pending_requests")),
					"render_pending_snapshot": renderer != null \
							and bool(renderer.call("has_pending_snapshot")),
					"render_page_cursor": int(renderer.get("_pending_snapshot_page_cursor")) \
							if renderer != null else -1,
					"render_stream_cursor": int(renderer.get("_pending_snapshot_stream_cursor")) \
							if renderer != null else -1,
					"readiness_missing": int(readiness.get("missing_chunk_count", -1)),
					"readiness_reasons": readiness.get("reason_counts", { }),
				}
			print("MAIN_MENU_STARTUP frame=%d loading=%s debug=%s" % [
				frame,
				JSON.stringify(loading),
				JSON.stringify(debug),
			])
		if bool(loading.get("ready", false)):
			quit(0)
			return
	push_error("main-menu startup timed out")
	quit(1)
