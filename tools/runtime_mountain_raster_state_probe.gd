extends SceneTree

const WORLD_RUNTIME_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const PROBE_TARGET_CHUNK: Vector2i = Vector2i(138, 97)
const PROBE_TARGET_LOCAL: Vector2i = Vector2i(7, 3)

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("runtime_mountain_raster_state_probe: instantiating world scene")
	var packed_scene: PackedScene = ResourceLoader.load(WORLD_RUNTIME_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "WorldRuntimeV0 scene must load.")
	if packed_scene == null:
		_finish()
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	print("runtime_mountain_raster_state_probe: world scene added")
	var streamer: Node = scene.get_node_or_null("WorldStreamer")
	_assert(streamer != null, "WorldRuntimeV0 must contain WorldStreamer.")
	if streamer == null:
		_finish()
		return

	var last_debug: Dictionary = {}
	for frame: int in range(720):
		await process_frame
		if frame == 30:
			var player: Node2D = scene.get_node_or_null("Player") as Node2D
			_assert(player != null, "WorldRuntimeV0 must contain Player.")
			if player != null:
				var target_tile: Vector2i = PROBE_TARGET_CHUNK * WorldRuntimeConstants.CHUNK_SIZE + PROBE_TARGET_LOCAL
				player.global_position = WorldRuntimeConstants.tile_to_world_center(target_tile)
				if streamer.has_method("get_mountain_mask_runtime_debug_state"):
					print("runtime_mountain_raster_state_probe: moved player to tile=%s chunk=%s" % [
						str(target_tile),
						str(PROBE_TARGET_CHUNK),
					])
				if streamer.has_method("_update_player_chunk_coord"):
					streamer.call("_update_player_chunk_coord")
		if streamer.has_method("_streaming_tick"):
			streamer.call("_streaming_tick")
		if streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			streamer.call("_mountain_native_mask_visual_apply_tick")
		last_debug = streamer.call("get_mountain_mask_runtime_debug_state") as Dictionary
		if frame % 60 == 0:
			print("runtime_mountain_raster_state_probe: frame=%d debug=%s" % [
				frame,
				JSON.stringify(_compact_debug(last_debug)),
			])
		if int(last_debug.get("ready_native_mask_chunk_count", 0)) > 0 \
				and int(last_debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(last_debug.get("native_mask_visual_pending_count", 0)) == 0 \
				and not bool(last_debug.get("request_in_flight", false)):
			break

	print("runtime_mountain_raster_state_probe: %s" % JSON.stringify(_compact_debug(last_debug)))
	var layer_debug: Dictionary = last_debug.get("layer", {}) as Dictionary
	_assert(bool(last_debug.get("native_mask_runtime_enabled", false)), "Runtime mountain presentation must use native masks.")
	_assert(not bool(last_debug.get("legacy_page_runtime_enabled", true)), "Legacy mountain page runtime must stay disabled.")
	_assert(not bool(last_debug.get("request_in_flight", false)), "Native mountain runtime must not leave legacy page requests in flight.")
	_assert(int(last_debug.get("ready_native_mask_chunk_count", 0)) > 0, "Runtime native mountain masks must become ready.")
	_assert(int(last_debug.get("native_mask_pixel_count", 0)) > 0, "Runtime native mountain masks must expose mask pixels.")
	_assert(int(last_debug.get("native_mask_solid_sample_count", 0)) > 0, "Runtime native mountain masks must contain solid samples.")
	_assert(int(last_debug.get("native_mask_visual_pending_count", 0)) == 0, "Runtime native mask visual uploads must drain.")
	_assert(int(last_debug.get("native_mask_visual_upload_queue_count", 0)) == 0, "Runtime native mask visual upload queue must drain.")
	_assert(bool(layer_debug.get("ready", false)), "Runtime native mask debug layer must become ready.")
	_assert(bool(layer_debug.get("native_mask_runtime", false)), "Runtime native mask debug must report native-mask runtime.")
	_assert_gameplay_uses_native_mask(streamer)
	scene.queue_free()
	await process_frame
	_finish()

func _compact_debug(debug: Dictionary) -> Dictionary:
	var layer: Dictionary = debug.get("layer", {}) as Dictionary
	return {
		"dirty": bool(debug.get("dirty", false)),
		"request_in_flight": bool(debug.get("request_in_flight", false)),
		"requested_revision": int(debug.get("requested_revision", -1)),
		"applied_revision": int(debug.get("applied_revision", -1)),
		"current_revision": int(debug.get("current_revision", -1)),
		"target_chunk": str(debug.get("target_chunk", Vector2i.ZERO)),
		"source_packet_count": int(debug.get("source_packet_count", 0)),
		"packet_count": int(debug.get("packet_count", 0)),
		"applied_source_chunk_count": int(debug.get("applied_source_chunk_count", 0)),
		"layer_count": int(debug.get("layer_count", 0)),
		"native_mask_runtime_enabled": bool(debug.get("native_mask_runtime_enabled", false)),
		"legacy_page_runtime_enabled": bool(debug.get("legacy_page_runtime_enabled", true)),
		"visible_chunk_count": int(debug.get("visible_chunk_count", 0)),
		"ready_native_mask_chunk_count": int(debug.get("ready_native_mask_chunk_count", 0)),
		"native_mask_pixel_count": int(debug.get("native_mask_pixel_count", 0)),
		"native_mask_solid_sample_count": int(debug.get("native_mask_solid_sample_count", 0)),
		"native_mask_visual_ready_count": int(debug.get("native_mask_visual_ready_count", 0)),
		"native_mask_visual_pending_count": int(debug.get("native_mask_visual_pending_count", 0)),
		"native_mask_visual_upload_queue_count": int(debug.get("native_mask_visual_upload_queue_count", 0)),
		"native_mask_visual_upload_count_total": int(debug.get("native_mask_visual_upload_count_total", 0)),
		"native_mask_visual_upload_elapsed_ms_max_total": float(debug.get("native_mask_visual_upload_elapsed_ms_max_total", 0.0)),
		"native_mask_cached_count": int(debug.get("native_mask_cached_count", 0)),
		"native_mask_inflight_count": int(debug.get("native_mask_inflight_count", 0)),
		"native_mask_build_count_total": int(debug.get("native_mask_build_count_total", 0)),
		"native_mask_build_count_last_tick": int(debug.get("native_mask_build_count_last_tick", 0)),
		"native_mask_build_count_max_tick": int(debug.get("native_mask_build_count_max_tick", 0)),
		"native_mask_elapsed_ms_max_total": float(debug.get("native_mask_elapsed_ms_max_total", 0.0)),
		"native_mask_elapsed_ms_last_tick_max": float(debug.get("native_mask_elapsed_ms_last_tick_max", 0.0)),
		"native_mask_worker_elapsed_ms_max_total": float(debug.get("native_mask_worker_elapsed_ms_max_total", 0.0)),
		"native_mask_request_to_complete_ms_max_total": float(debug.get("native_mask_request_to_complete_ms_max_total", 0.0)),
		"preset_path": str(debug.get("preset_path", "")),
		"queue_wait_ms": int(layer.get("queue_wait_ms", debug.get("queue_wait_ms", 0))),
		"worker_elapsed_ms": int(layer.get("worker_elapsed_ms", debug.get("worker_elapsed_ms", 0))),
		"request_to_complete_ms": int(layer.get("request_to_complete_ms", debug.get("request_to_complete_ms", 0))),
		"success": bool(debug.get("success", false)),
		"message": str(debug.get("message", "")),
		"layer_ready": bool(layer.get("ready", false)),
		"layer_packet_count": int(layer.get("packet_count", 0)),
		"mountain_tile_count": int(layer.get("mountain_tile_count", 0)),
		"target_chunk_anchor_enabled": bool(layer.get("target_chunk_anchor_enabled", true)),
		"layer_position": str(layer.get("layer_position", Vector2.INF)),
		"image_width": int(layer.get("image_width", 0)),
		"image_height": int(layer.get("image_height", 0)),
		"top_pixels": int(layer.get("top_pixel_count", 0)),
		"face_pixels": int(layer.get("face_pixel_count", 0)),
		"rim_pixels": int(layer.get("rim_pixel_count", 0)),
		"hit_mask_ready": bool(layer.get("hit_mask_ready", false)),
		"hit_mask_solid_pixels": int(layer.get("hit_mask_solid_pixel_count", 0)),
		"runtime_mountain_only": bool(layer.get("runtime_mountain_only", false)),
		"native_mask_runtime": bool(layer.get("native_mask_runtime", false)),
	}

func _assert_gameplay_uses_native_mask(streamer: Node) -> void:
	var solid_blocks_walk: bool = false
	var empty_mountain_corner_walks: bool = false
	var mining_succeeds: bool = false
	var sampled: int = 0
	var offsets: Array[Vector2] = [
		Vector2(0.12, 0.12),
		Vector2(0.50, 0.50),
		Vector2(0.88, 0.12),
		Vector2(0.12, 0.88),
		Vector2(0.88, 0.88),
	]
	var packets: Dictionary = streamer.get("_chunk_packets") as Dictionary
	for packet_variant: Variant in packets.values():
		var packet: Dictionary = packet_variant as Dictionary
		var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
		var limit: int = mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)
		for index: int in range(limit):
			var terrain_id: int = int(terrain_ids[index])
			if not _is_mountain_surface_terrain(terrain_id):
				continue
			if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
				continue
			var local_coord := Vector2i(index % WorldRuntimeConstants.CHUNK_SIZE, index / WorldRuntimeConstants.CHUNK_SIZE)
			var world_tile: Vector2i = streamer.call("_chunk_local_to_tile", chunk_coord, local_coord) as Vector2i
			var tile_origin := Vector2(
				float(world_tile.x * WorldRuntimeConstants.TILE_SIZE_PX),
				float(world_tile.y * WorldRuntimeConstants.TILE_SIZE_PX)
			)
			for offset: Vector2 in offsets:
				sampled += 1
				if sampled > 80000:
					_assert(false, "Runtime native mask gameplay probe hit sample limit.")
					return
				var world_pos: Vector2 = tile_origin + offset * float(WorldRuntimeConstants.TILE_SIZE_PX)
				var hit_sample: Dictionary = streamer.call("_sample_mountain_raster_hit", world_pos) as Dictionary
				if not bool(hit_sample.get("ready", false)) or not bool(hit_sample.get("in_bounds", false)):
					continue
				var tile_data: Dictionary = streamer.call("_get_tile_data", world_pos) as Dictionary
				if not bool(tile_data.get("ready", false)):
					continue
				var sampled_terrain_id: int = int(tile_data.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
				var square_walkable: bool = bool(tile_data.get("walkable", false))
				if bool(hit_sample.get("solid", false)):
					if not bool(streamer.call("is_walkable_at_world", world_pos)):
						solid_blocks_walk = true
					if not mining_succeeds and bool(streamer.call("has_resource_at_world", world_pos)):
						var harvest: Dictionary = streamer.call("try_harvest_at_world", world_pos) as Dictionary
						mining_succeeds = bool(harvest.get("success", false))
				elif _is_mountain_surface_terrain(sampled_terrain_id) and not square_walkable:
					if bool(streamer.call("is_walkable_at_world", world_pos)):
						empty_mountain_corner_walks = true
				if solid_blocks_walk and empty_mountain_corner_walks and mining_succeeds:
					_assert(true, "Runtime native mask gameplay probe completed.")
					return
	_assert(solid_blocks_walk, "Runtime collision must block visual solid native-mask mountain pixels.")
	_assert(empty_mountain_corner_walks, "Runtime collision must allow rounded-off native-mask mountain square corners.")
	_assert(mining_succeeds, "Runtime mining must succeed through the native mountain contour.")

func _is_mountain_surface_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true

func _finish() -> void:
	quit(1 if _failed else 0)
