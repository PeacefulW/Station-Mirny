extends SceneTree

const DEV_SCENE_PATH := "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_FRAMES := 8000
const REPORT_INTERVAL_FRAMES := 300


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(DEV_SCENE_PATH) as PackedScene
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var world: Node = null
	for frame: int in range(MAX_FRAMES):
		await process_frame
		if world == null:
			world = scene.get_node_or_null("WorldRuntimeV0")
		if world == null:
			continue
		var loading: Dictionary = world.call("get_initial_loading_state") as Dictionary
		if frame % REPORT_INTERVAL_FRAMES == 0 or bool(loading.get("ready", false)):
			var streamer: Node = world.get_node_or_null("WorldStreamer")
			var render_state: Dictionary = { }
			var queues: Dictionary = { }
			if streamer != null:
				var readiness: Dictionary = streamer.call(
					"get_streaming_readiness_debug_snapshot",
				) as Dictionary
				var renderer: Node = streamer.get("_world_render_world") as Node
				if renderer != null and is_instance_valid(renderer):
					render_state = renderer.call("get_debug_state") as Dictionary
				var complete_object_views: int = 0
				var terrain_layer_canvas_items: int = 0
				var main_layer_canvas_items: int = 0
				for view_variant: Variant in (streamer.get("_chunk_views") as Dictionary).values():
					var view: Node = view_variant as Node
					if view != null and bool(view.call("is_object_presentation_complete")):
						complete_object_views += 1
					if view != null:
						for item_node: Node in view.find_children("*", "CanvasItem", true, false):
							var item := item_node as CanvasItem
							if item.visibility_layer & (1 << 18):
								terrain_layer_canvas_items += 1
							if item.visibility_layer & 1:
								main_layer_canvas_items += 1
				queues = {
					"views": (streamer.get("_chunk_views") as Dictionary).size(),
					"source": (streamer.get("_desired_source_chunk_coords") as Array).size(),
					"visible": (streamer.get("_desired_visible_chunk_coords") as Array).size(),
					"object_results": (streamer.get("_object_presentation_results_by_chunk") as Dictionary).size(),
					"grass_results": (streamer.get("_grass_scatter_results_by_chunk") as Dictionary).size(),
					"render_residency": (streamer.get("_world_render_residency_by_chunk") as Dictionary).size(),
					"object_inflight": (streamer.get("_object_presentation_inflight_chunks") as Dictionary).size(),
					"grass_inflight": (streamer.get("_grass_scatter_inflight_chunks") as Dictionary).size(),
					"object_complete_views": complete_object_views,
					"object_upload_queue": (streamer.get("_pending_object_packet_visual_upload_chunks") as Array).size(),
					"object_prestage": (streamer.get("_pending_hot_object_prestage_chunks") as Array).size(),
					"object_focus": str(streamer.get("_focused_object_packet_visual_upload_chunk")),
					"terrain_layer_items": terrain_layer_canvas_items,
					"main_layer_items_in_chunks": main_layer_canvas_items,
					"readiness_missing": int(readiness.get("missing_chunk_count", -1)),
					"readiness_stages": readiness.get("stage_counts", { }),
					"readiness_reasons": readiness.get("reason_counts", { }),
					"render_refresh_pending": bool(streamer.get("_world_render_refresh_pending")),
					"render_inflight_generation": int(streamer.get("_world_render_inflight_generation")),
					"render_request_generation": int(streamer.get("_world_render_request_generation")),
					"render_staging_residency": (streamer.get("_world_render_staging_residency_by_chunk") as Dictionary).size(),
					"render_has_completed": bool(
						(streamer.get("_world_compute_backend") as Object).call(
							"has_completed_world_render_snapshots",
						)
					),
				}
				if renderer != null and is_instance_valid(renderer):
					var render_color_items: int = 0
					for item_node: Node in renderer.find_children("*", "CanvasItem", true, false):
						var render_item := item_node as CanvasItem
						if render_item.visibility_layer & (1 << 18):
							render_color_items += 1
					queues["render_color_items"] = render_color_items
				var compositor: Node = world.get_node_or_null("WorldResolutionCompositor")
				if compositor != null:
					var world_viewport: Viewport = compositor.get("_terrain_viewport") as Viewport
					if world_viewport != null:
						queues["world_viewport_cull_mask"] = world_viewport.canvas_cull_mask
						queues["world_viewport_size"] = str(world_viewport.size)
			print("WORLD_RENDER_STARTUP frame=%d loading=%s queues=%s render=%s" % [
				frame, JSON.stringify(loading), JSON.stringify(queues), JSON.stringify(render_state),
			])
		if bool(loading.get("ready", false)):
			quit(0)
			return
	quit(1)
