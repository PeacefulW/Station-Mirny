extends Node

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/runtime_mountain_raster_walk_probe"
const DENSITY: float = 0.60
const LAKE_DENSITY: float = 0.0
const PROBE_SEED: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
const ROUTE_TARGET_COUNT: int = 7
const MAX_SCAN_RADIUS_CHUNKS: int = 18
const MAX_SETTLE_FRAMES: int = 1200
const PROBE_PLAYER_SPEED_PX_PER_SEC: float = 350.0
const PROBE_FPS: float = 60.0

var _failed: bool = false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("runtime_mountain_raster_walk_probe: start density=%.2f" % DENSITY)
	_prepare_output_dir()
	var marker_file := FileAccess.open("%s/started.txt" % OUTPUT_DIR, FileAccess.WRITE)
	if marker_file != null:
		marker_file.store_string("started")
		marker_file.close()
	var route: Array[Dictionary] = _build_density60_route()
	print("runtime_mountain_raster_walk_probe: route_size=%d" % route.size())
	_write_marker("route_%d" % route.size())
	_assert(route.size() >= 3, "Walk probe must find enough density 0.60 mountain targets.")
	if route.size() < 3:
		_finish({})
		return

	var packed_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "World runtime scene must load.")
	if packed_scene == null:
		_finish({})
		return

	var scene: Node = packed_scene.instantiate()
	add_child(scene)
	_write_marker("scene_added")
	await get_tree().process_frame
	_write_marker("after_first_frame")

	var streamer = scene.get_node_or_null("WorldStreamer")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	_write_marker("nodes_streamer_%s_player_%s_camera_%s" % [str(streamer != null), str(player != null), str(camera != null)])
	_assert(streamer != null, "World runtime scene must contain WorldStreamer.")
	_assert(player != null, "World runtime scene must contain Player.")
	_assert(camera != null, "Player must contain Camera2D.")
	if streamer == null or player == null or camera == null:
		_finish({})
		return

	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(0.80, 0.80)
	camera.force_update_scroll()

	var settings: MountainGenSettings = _build_mountain_settings()
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	streamer.initialize_new_world(PROBE_SEED, settings, bounds, foundation, lakes)
	_write_marker("initialized")
	var spawn_ready: Dictionary = await _wait_until_settled(streamer, 900)
	_write_marker("spawn_ready_%s" % str(spawn_ready.get("ready", false)))
	_assert(bool(spawn_ready.get("ready", false)), "Initial density 0.60 world stream must settle.")

	var step_reports: Array[Dictionary] = []
	for index: int in range(route.size()):
		_write_marker("step_%d_start" % index)
		var entry: Dictionary = route[index]
		var target_tile: Vector2i = entry.get("target_tile", Vector2i.ZERO) as Vector2i
		var target_world: Vector2 = WorldRuntimeConstants.tile_to_world_center(target_tile)
		if index == 0:
			player.global_position = target_world
			camera.force_update_scroll()
			streamer._update_player_chunk_coord()
		else:
			await _walk_player_to(streamer, player, target_world)
			camera.force_update_scroll()
		var settled: Dictionary = await _wait_until_settled(streamer, MAX_SETTLE_FRAMES)
		_write_marker("step_%d_settled_%s" % [index, str(settled.get("ready", false))])
		var screenshot_path: String = "%s/walk_%02d.png" % [OUTPUT_DIR, index]
		var screenshot_status: Dictionary = _capture_viewport(screenshot_path)
		var debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
		var step_report: Dictionary = {
			"index": index,
			"target_chunk": entry.get("chunk", Vector2i.ZERO),
			"target_tile": target_tile,
			"settled": settled,
			"debug": _compact_raster_debug(debug),
			"screenshot": ProjectSettings.globalize_path(screenshot_path),
			"screenshot_status": screenshot_status,
		}
		step_reports.append(step_report)
		_assert(bool(settled.get("ready", false)), "Step %d must finish without visible native-mask backlog." % index)
		_assert(bool(debug.get("native_mask_runtime_enabled", false)), "Step %d must use native mountain masks." % index)
		_assert(int(debug.get("ready_native_mask_chunk_count", 0)) > 0, "Step %d must have ready native mountain masks." % index)
		_assert(int(debug.get("missing_mountain_chunk_count", 0)) == 0, "Step %d must have no missing mountain mask chunks." % index)
		_assert(not bool(debug.get("request_in_flight", false)), "Step %d must not leave mountain mask request in flight." % index)
		_assert(int(debug.get("native_mask_visual_upload_queue_count", 0)) == 0, "Step %d must drain native mask visual upload queue." % index)
		_assert(int(debug.get("native_mask_visual_pending_count", 0)) == 0, "Step %d must drain native mask visual pending flags." % index)

	_write_marker("loop_done")
	var mining_report: Dictionary = _probe_raster_collision_and_mining(streamer)
	_write_marker("mining_done")
	_assert(bool(mining_report.get("solid_blocks_walk", false)), "Raster hit mask must block visual solid mountain pixels.")
	_assert(bool(mining_report.get("empty_corner_walks", false)), "Raster hit mask must allow rounded-off empty mountain corners.")
	_assert(bool(mining_report.get("mining_succeeds", false)), "Raster mining probe must commit an actual harvest.")
	_assert(int(mining_report.get("dirty_chunk_count", 99)) <= 9, "Mining must dirty only the local native mask and halo neighbours.")
	_assert(bool(mining_report.get("walkable_after_mining", false)), "Mined tile must become walkable immediately without waiting for a full mountain redraw.")
	_assert(int(mining_report.get("visual_patch_skip_delta", 0)) > 0, "Mountain mining must skip the square terrain visual patch.")
	var mining_immediate_screenshot_path: String = "%s/mining_immediate.png" % OUTPUT_DIR
	var mining_immediate_screenshot_status: Dictionary = _capture_viewport(mining_immediate_screenshot_path)
	var mining_settled: Dictionary = await _wait_until_settled(streamer, MAX_SETTLE_FRAMES)
	_assert(bool(mining_settled.get("ready", false)), "Post-mining native mask reconciliation must settle.")
	var post_mining_debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
	var visible_republish_skip_delta: int = int(post_mining_debug.get(
		"native_mask_visible_republish_skip_count_total",
		0
	)) - int(mining_report.get("visible_republish_skip_before", 0))
	mining_report["visible_republish_skip_delta_after_settle"] = visible_republish_skip_delta
	mining_report["post_settled_debug"] = _compact_raster_debug(post_mining_debug)
	_assert(
		visible_republish_skip_delta >= 0,
		"Post-mining native mask reconciliation must not republish already visible chunks."
	)
	var mining_settled_screenshot_path: String = "%s/mining_settled.png" % OUTPUT_DIR
	var mining_settled_screenshot_status: Dictionary = _capture_viewport(mining_settled_screenshot_path)

	var report: Dictionary = {
		"seed": PROBE_SEED,
		"density": DENSITY,
		"lake_density": LAKE_DENSITY,
		"route_size": route.size(),
		"spawn_settled": spawn_ready,
		"steps": step_reports,
		"mining": mining_report,
		"mining_immediate_screenshot": ProjectSettings.globalize_path(mining_immediate_screenshot_path),
		"mining_immediate_screenshot_status": mining_immediate_screenshot_status,
		"mining_settled": mining_settled,
		"mining_settled_screenshot": ProjectSettings.globalize_path(mining_settled_screenshot_path),
		"mining_settled_screenshot_status": mining_settled_screenshot_status,
		"failed": _failed,
	}
	var report_path: String = "%s/walk_probe_report.json" % OUTPUT_DIR
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	_write_marker("report_written")
	print("RUNTIME_MOUNTAIN_RASTER_WALK_PROBE_JSON=" + JSON.stringify(report))
	if DisplayServer.get_name() != "headless":
		for _frame: int in range(300):
			await get_tree().process_frame
	scene.queue_free()
	await get_tree().process_frame
	_finish(report)

func _build_mountain_settings() -> MountainGenSettings:
	var settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	settings.density = DENSITY
	return settings

func _build_settings_packed() -> PackedFloat32Array:
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	var packed: PackedFloat32Array = _build_mountain_settings().flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	return lakes.write_to_settings_packed(packed)

func _build_density60_route() -> Array[Dictionary]:
	var core: Object = ClassDB.instantiate("WorldCore")
	_assert(core != null, "WorldCore must be available for route scan.")
	if core == null:
		return []
	var settings_packed: PackedFloat32Array = _build_settings_packed()
	var spawn_result: Dictionary = core.call(
		"resolve_world_foundation_spawn_tile",
		PROBE_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	) as Dictionary
	_assert(bool(spawn_result.get("success", false)), "Density 0.60 spawn resolution must succeed.")
	if not bool(spawn_result.get("success", false)):
		return []
	var spawn_tile: Vector2i = spawn_result.get("spawn_tile", Vector2i.ZERO) as Vector2i
	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn_tile)
	var route: Array[Dictionary] = [{
		"chunk": center_chunk,
		"target_tile": spawn_tile,
		"kind": "spawn",
	}]
	var candidates: Array[Dictionary] = []
	for radius: int in range(1, MAX_SCAN_RADIUS_CHUNKS + 1):
		var coords: PackedVector2Array = _build_chunk_ring(center_chunk, radius)
		var packets: Array = core.call(
			"generate_chunk_packets_batch",
			PROBE_SEED,
			coords,
			WorldRuntimeConstants.WORLD_VERSION,
			settings_packed
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			if not _packet_has_mountain(packet):
				continue
			var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
			var local_coord: Vector2i = _find_edge_mountain_local(packet)
			candidates.append({
				"chunk": chunk_coord,
				"local": local_coord,
				"target_tile": chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord,
				"kind": "mountain",
			})
		if candidates.size() >= ROUTE_TARGET_COUNT:
			break
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector2i = a.get("chunk", Vector2i.ZERO) as Vector2i
		var cb: Vector2i = b.get("chunk", Vector2i.ZERO) as Vector2i
		var da: int = abs(ca.x - center_chunk.x) + abs(ca.y - center_chunk.y)
		var db: int = abs(cb.x - center_chunk.x) + abs(cb.y - center_chunk.y)
		return da < db if da != db else (ca.x < cb.x if ca.x != cb.x else ca.y < cb.y)
	)
	var seen_chunks: Dictionary = {center_chunk: true}
	for candidate: Dictionary in candidates:
		var chunk_coord: Vector2i = candidate.get("chunk", Vector2i.ZERO) as Vector2i
		if seen_chunks.has(chunk_coord):
			continue
		seen_chunks[chunk_coord] = true
		route.append(candidate)
		if route.size() >= ROUTE_TARGET_COUNT:
			break
	return route

func _build_chunk_ring(center_chunk: Vector2i, radius: int) -> PackedVector2Array:
	var coords: PackedVector2Array = PackedVector2Array()
	for chunk_y: int in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for chunk_x: int in range(center_chunk.x - radius, center_chunk.x + radius + 1):
			if maxi(absi(chunk_x - center_chunk.x), absi(chunk_y - center_chunk.y)) != radius:
				continue
			coords.append(Vector2(chunk_x, chunk_y))
	return coords

func _packet_has_mountain(packet: Dictionary) -> bool:
	return _find_edge_mountain_local(packet) != Vector2i(-1, -1)

func _find_edge_mountain_local(packet: Dictionary) -> Vector2i:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var fallback: Vector2i = Vector2i(-1, -1)
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		if not _is_solid_mountain_index(index, terrain_ids, walkable_flags, mountain_flags):
			continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		if fallback == Vector2i(-1, -1):
			fallback = local_coord
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = local_coord + offset
			if neighbor.x < 0 or neighbor.y < 0 \
					or neighbor.x >= WorldRuntimeConstants.CHUNK_SIZE \
					or neighbor.y >= WorldRuntimeConstants.CHUNK_SIZE:
				return local_coord
			var neighbor_index: int = WorldRuntimeConstants.local_to_index(neighbor)
			if not _is_solid_mountain_index(neighbor_index, terrain_ids, walkable_flags, mountain_flags):
				return local_coord
	return fallback

func _is_solid_mountain_index(
	index: int,
	terrain_ids: PackedInt32Array,
	walkable_flags: PackedByteArray,
	mountain_flags: PackedByteArray
) -> bool:
	if index < 0 or index >= terrain_ids.size():
		return false
	var terrain_id: int = int(terrain_ids[index])
	if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
			and terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
		return false
	if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
		return false
	if terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED and index < mountain_flags.size():
		var flags: int = int(mountain_flags[index])
		if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
			return false
	return true

func _walk_player_to(streamer, player: Node2D, target_world: Vector2) -> void:
	var start: Vector2 = player.global_position
	var distance_px: float = start.distance_to(target_world)
	var frame_count: int = maxi(1, int(ceil(distance_px / PROBE_PLAYER_SPEED_PX_PER_SEC * PROBE_FPS)))
	for frame: int in range(frame_count):
		var t: float = float(frame + 1) / float(frame_count)
		player.global_position = start.lerp(target_world, t)
		streamer._streaming_tick()
		await get_tree().process_frame

func _wait_until_settled(streamer, max_frames: int) -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	var last_debug: Dictionary = {}
	for frame: int in range(max_frames):
		streamer._streaming_tick()
		if streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			streamer._mountain_native_mask_visual_apply_tick()
		await get_tree().process_frame
		last_debug = streamer.get_mountain_mask_runtime_debug_state()
		if _is_stream_settled(streamer, last_debug):
			return {
				"ready": true,
				"frames": frame + 1,
				"elapsed_ms": Time.get_ticks_msec() - started_msec,
				"debug": _compact_raster_debug(last_debug),
			}
	return {
		"ready": false,
		"frames": max_frames,
		"elapsed_ms": Time.get_ticks_msec() - started_msec,
		"debug": _compact_raster_debug(last_debug),
		"pending_publish": _pending_publish_count(streamer),
		"requested_chunks": streamer._requested_chunks.size(),
	}

func _is_stream_settled(streamer, debug: Dictionary) -> bool:
	if streamer._awaiting_new_game_spawn_result or streamer._new_game_spawn_failed:
		return false
	if not streamer._requested_chunks.is_empty():
		return false
	if _pending_publish_count(streamer) > 0:
		return false
	if bool(debug.get("dirty", false)) or bool(debug.get("request_in_flight", false)):
		return false
	if int(debug.get("missing_mountain_chunk_count", 0)) > 0:
		return false
	if int(debug.get("native_mask_visual_upload_queue_count", 0)) > 0 \
			or int(debug.get("native_mask_visual_pending_count", 0)) > 0:
		return false
	return not streamer._has_pending_streaming_work()

func _pending_publish_count(streamer) -> int:
	var count: int = streamer._pending_publish_queue.size()
	if streamer._active_publish_chunk != streamer.INVALID_CHUNK_COORD:
		count += 1
	return count

func _probe_raster_collision_and_mining(streamer) -> Dictionary:
	var result: Dictionary = {
		"ready": false,
		"solid_blocks_walk": false,
		"empty_corner_walks": false,
		"mining_succeeds": false,
	}
	var sampled: int = 0
	var offsets: Array[Vector2] = [
		Vector2(0.12, 0.12),
		Vector2(0.50, 0.50),
		Vector2(0.88, 0.12),
		Vector2(0.12, 0.88),
		Vector2(0.88, 0.88),
	]
	for packet_variant: Variant in streamer._chunk_packets.values():
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
			var world_tile: Vector2i = streamer._chunk_local_to_tile(chunk_coord, local_coord)
			var tile_origin: Vector2 = Vector2(
				float(world_tile.x * WorldRuntimeConstants.TILE_SIZE_PX),
				float(world_tile.y * WorldRuntimeConstants.TILE_SIZE_PX)
			)
			for offset: Vector2 in offsets:
				sampled += 1
				if sampled > 80000:
					result["sample_limit_reached"] = sampled
					return result
				var world_pos: Vector2 = tile_origin + offset * float(WorldRuntimeConstants.TILE_SIZE_PX)
				var hit_sample: Dictionary = streamer._sample_mountain_raster_hit(world_pos)
				if not bool(hit_sample.get("ready", false)) or not bool(hit_sample.get("in_bounds", false)):
					continue
				result["ready"] = true
				if bool(hit_sample.get("solid", false)):
					if not streamer.is_walkable_at_world(world_pos):
						result["solid_blocks_walk"] = true
					if not bool(result.get("mining_succeeds", false)) and streamer.has_resource_at_world(world_pos):
						var dirty_chunks: Array[Vector2i] = streamer._build_mountain_native_mask_dirty_chunks_for_tile(world_tile)
						var before_debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
						var before_visual_skip_count: int = int(before_debug.get(
							"mountain_surface_dig_visual_patch_skip_count_total",
							0
						))
						var before_visible_republish_skip_count: int = int(before_debug.get(
							"native_mask_visible_republish_skip_count_total",
							0
						))
						var harvest_result: Dictionary = streamer.try_harvest_at_world(world_pos)
						var after_debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
						var after_visual_skip_count: int = int(after_debug.get(
							"mountain_surface_dig_visual_patch_skip_count_total",
							0
						))
						result["mining_succeeds"] = bool(harvest_result.get("success", false))
						result["mining_tile"] = world_tile
						result["dirty_chunk_count"] = dirty_chunks.size()
						result["dirty_chunks"] = dirty_chunks
						result["walkable_after_mining"] = streamer.is_walkable_at_world(world_pos)
						result["visual_patch_skip_delta"] = after_visual_skip_count - before_visual_skip_count
						result["visible_republish_skip_before"] = before_visible_republish_skip_count
				elif streamer.is_walkable_at_world(world_pos):
					result["empty_corner_walks"] = true
				if bool(result.get("solid_blocks_walk", false)) \
						and bool(result.get("empty_corner_walks", false)) \
						and bool(result.get("mining_succeeds", false)):
					return result
	result["sampled"] = sampled
	return result

func _is_mountain_surface_terrain(terrain_id: int) -> bool:
	return terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _compact_raster_debug(debug: Dictionary) -> Dictionary:
	var layer: Dictionary = debug.get("layer", {}) as Dictionary
	var display_layer: Dictionary = debug.get("display_layer", {}) as Dictionary
	return {
		"dirty": bool(debug.get("dirty", false)),
		"dirty_requires_rebuild": bool(debug.get("dirty_requires_rebuild", false)),
		"request_in_flight": bool(debug.get("request_in_flight", false)),
		"desired_mountain_chunk_count": int(debug.get("desired_mountain_chunk_count", 0)),
		"missing_mountain_chunk_count": int(debug.get("missing_mountain_chunk_count", 0)),
		"source_packet_count": int(debug.get("source_packet_count", 0)),
		"packet_count": int(debug.get("packet_count", 0)),
		"display_packet_count": int(debug.get("display_packet_count", 0)),
		"display_ready": bool(debug.get("display_ready", false)),
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
		"native_mask_visible_republish_skip_count_total": int(debug.get("native_mask_visible_republish_skip_count_total", 0)),
		"native_mask_cached_count": int(debug.get("native_mask_cached_count", 0)),
		"native_mask_inflight_count": int(debug.get("native_mask_inflight_count", 0)),
		"native_mask_pixels_per_tile": int(debug.get("native_mask_pixels_per_tile", 0)),
		"native_mask_halo_radius_tiles": int(debug.get("native_mask_halo_radius_tiles", 0)),
		"native_mask_build_count_total": int(debug.get("native_mask_build_count_total", 0)),
		"native_mask_build_count_last_tick": int(debug.get("native_mask_build_count_last_tick", 0)),
		"native_mask_build_count_max_tick": int(debug.get("native_mask_build_count_max_tick", 0)),
		"native_mask_elapsed_ms_last": float(debug.get("native_mask_elapsed_ms_last", 0.0)),
		"native_mask_elapsed_ms_max_total": float(debug.get("native_mask_elapsed_ms_max_total", 0.0)),
		"native_mask_elapsed_ms_last_tick_max": float(debug.get("native_mask_elapsed_ms_last_tick_max", 0.0)),
		"native_mask_worker_elapsed_ms_max_total": float(debug.get("native_mask_worker_elapsed_ms_max_total", 0.0)),
		"native_mask_request_to_complete_ms_max_total": float(debug.get("native_mask_request_to_complete_ms_max_total", 0.0)),
		"native_mask_last_chunk": str(debug.get("native_mask_last_chunk", Vector2i.ZERO)),
		"native_mask_last_reason": str(debug.get("native_mask_last_reason", "")),
		"native_mask_last_refreshed_chunks": debug.get("native_mask_last_refreshed_chunks", []),
		"mountain_surface_dig_visual_patch_skip_count_total": int(debug.get("mountain_surface_dig_visual_patch_skip_count_total", 0)),
		"display_request_in_flight": bool(debug.get("display_request_in_flight", false)),
		"display_image_width": int(display_layer.get("image_width", 0)),
		"display_image_height": int(display_layer.get("image_height", 0)),
		"display_runtime_clip_half_width_px": int(display_layer.get("runtime_clip_half_width_px", 0)),
		"display_runtime_clip_half_height_px": int(display_layer.get("runtime_clip_half_height_px", 0)),
		"display_timing_total_ms": int(display_layer.get("timing_total_ms", 0)),
		"display_worker_elapsed_ms": int(display_layer.get("worker_elapsed_ms", 0)),
		"applied_source_chunk_count": int(debug.get("applied_source_chunk_count", 0)),
		"layer_count": int(debug.get("layer_count", 0)),
		"queued_source_chunks": debug.get("queued_source_chunks", []),
		"success": bool(debug.get("success", false)),
		"worker_elapsed_ms": int(layer.get("worker_elapsed_ms", debug.get("worker_elapsed_ms", 0))),
		"request_to_complete_ms": int(layer.get("request_to_complete_ms", debug.get("request_to_complete_ms", 0))),
		"timing_total_ms": int(layer.get("timing_total_ms", debug.get("timing_total_ms", 0))),
		"timing_blur_ms": int(layer.get("timing_blur_ms", debug.get("timing_blur_ms", 0))),
		"timing_alpha_ms": int(layer.get("timing_alpha_ms", debug.get("timing_alpha_ms", 0))),
		"timing_paint_ms": int(layer.get("timing_paint_ms", debug.get("timing_paint_ms", 0))),
		"timing_normal_ms": int(layer.get("timing_normal_ms", debug.get("timing_normal_ms", 0))),
		"image_width": int(layer.get("image_width", 0)),
		"image_height": int(layer.get("image_height", 0)),
		"runtime_clip_half_width_px": int(layer.get("runtime_clip_half_width_px", 0)),
		"runtime_clip_half_height_px": int(layer.get("runtime_clip_half_height_px", 0)),
		"top_pixels": int(layer.get("top_pixel_count", 0)),
		"face_pixels": int(layer.get("face_pixel_count", 0)),
		"rim_pixels": int(layer.get("rim_pixel_count", 0)),
		"runtime_clip_enabled": bool(layer.get("runtime_clip_enabled", debug.get("runtime_clip_enabled", false))),
		"hit_mask_ready": bool(layer.get("hit_mask_ready", false)),
		"hit_mask_solid_pixels": int(layer.get("hit_mask_solid_pixel_count", 0)),
	}

func _capture_viewport(path: String) -> Dictionary:
	_write_marker("capture_reached_%s" % path.get_file())
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var status: Dictionary = {
		"path": absolute_path,
		"saved": false,
	}
	if DisplayServer.get_name() == "headless":
		status["skipped"] = "headless"
		return status
	var viewport_image: Image = get_viewport().get_texture().get_image()
	if viewport_image == null:
		status["error"] = "viewport_image_null"
		return status
	status["image_size"] = Vector2i(viewport_image.get_width(), viewport_image.get_height())
	var png_bytes: PackedByteArray = viewport_image.save_png_to_buffer()
	status["png_bytes"] = png_bytes.size()
	if png_bytes.is_empty():
		status["error"] = "png_buffer_empty"
		return status
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status["error"] = "file_open_failed"
		return status
	file.store_buffer(png_bytes)
	file.close()
	status["saved"] = FileAccess.file_exists(path)
	if not bool(status["saved"]):
		status["error"] = "file_missing_after_write"
	return status

func _prepare_output_dir() -> void:
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/runtime_mountain_raster_walk_probe")

func _write_marker(text: String) -> void:
	var marker_file := FileAccess.open("%s/marker.txt" % OUTPUT_DIR, FileAccess.WRITE)
	if marker_file != null:
		marker_file.store_string(text)
		marker_file.close()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true

func _finish(_report: Dictionary) -> void:
	get_tree().quit(1 if _failed else 0)
