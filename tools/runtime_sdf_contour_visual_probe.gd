extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/runtime_sdf_contour_visual_probe"
const PROBE_SEED: int = 240518
const DENSITY: float = 0.60
const MAX_PROBE_FRAMES: int = 900
const MINING_STEPS: int = 5

var _failed: bool = false
var _chunk_loaded_times: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_prepare_output_dir()
	var selected: Dictionary = _find_density60_mountain_target()
	if selected.is_empty():
		_fail("No mountain target found for density 0.60 in probe scan.")
		quit(1)
		return

	var packed_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("World runtime scene missing: %s" % WORLD_SCENE_PATH)
		quit(1)
		return

	var world_scene: Node = packed_scene.instantiate()
	root.add_child(world_scene)
	current_scene = world_scene
	await process_frame

	var streamer: WorldStreamer = world_scene.get_node_or_null("WorldStreamer") as WorldStreamer
	if streamer == null:
		_fail("WorldStreamer missing in probe world scene.")
		quit(1)
		return

	var settings: MountainGenSettings = _build_mountain_settings()
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = 0.0

	var event_bus: Node = root.get_node_or_null("EventBus")
	if event_bus != null and event_bus.has_signal("chunk_loaded") \
			and not event_bus.is_connected("chunk_loaded", _on_chunk_loaded):
		event_bus.connect("chunk_loaded", _on_chunk_loaded)

	streamer.initialize_new_world(
		int(selected.get("seed", WorldRuntimeConstants.DEFAULT_WORLD_SEED)),
		settings,
		bounds,
		foundation,
		lakes
	)

	var target_chunk: Vector2i = selected.get("target_chunk", Vector2i.ZERO) as Vector2i
	var target_local: Vector2i = selected.get("target_local", Vector2i.ZERO) as Vector2i
	var player: Node2D = root.get_node_or_null("WorldRuntimeV0/Player") as Node2D
	var camera: Camera2D = root.get_node_or_null("WorldRuntimeV0/Player/Camera2D") as Camera2D
	await _wait_for_spawn_resolution(streamer)
	if player != null:
		var target_tile_for_streaming: Vector2i = target_chunk * WorldRuntimeConstants.CHUNK_SIZE + target_local
		player.global_position = WorldRuntimeConstants.tile_to_world_center(target_tile_for_streaming) + Vector2(160.0, 96.0)
	if camera != null:
		camera.enabled = true
		camera.position_smoothing_enabled = false
		camera.zoom = Vector2(0.80, 0.80)
		camera.force_update_scroll()
	streamer._update_player_chunk_coord()
	_chunk_loaded_times.clear()
	var start_msec: int = Time.get_ticks_msec()
	var early_screenshot_msec: int = -1
	var early_path: String = "%s/contour_density60_early.png" % OUTPUT_DIR
	var early_stats: Dictionary = {}
	var first_chunk_msec: int = -1
	var all_ready_msec: int = -1
	var target_visible_msec: int = -1
	var expected_count: int = 0
	var frame_count: int = 0
	var target_chunk_coord: Vector2i = target_chunk

	while frame_count < MAX_PROBE_FRAMES:
		streamer._streaming_tick()
		await process_frame
		frame_count += 1
		var elapsed_msec: int = Time.get_ticks_msec() - start_msec
		if early_screenshot_msec < 0 and elapsed_msec >= 500:
			_capture_viewport(early_path)
			early_stats = _sample_current_viewport_stats()
			early_screenshot_msec = elapsed_msec
		if first_chunk_msec < 0 and not _chunk_loaded_times.is_empty():
			first_chunk_msec = int(_chunk_loaded_times.values()[0]) - start_msec
		if streamer._player_chunk_coord != streamer.INVALID_CHUNK_COORD:
			var desired: Array[Vector2i] = streamer._build_desired_chunk_coords(streamer._player_chunk_coord)
			expected_count = desired.size()
			if all_ready_msec < 0 and _all_desired_chunks_contour_ready(streamer, desired):
				all_ready_msec = Time.get_ticks_msec() - start_msec
		if target_visible_msec < 0 and _chunk_contour_ready(streamer, target_chunk_coord):
			target_visible_msec = Time.get_ticks_msec() - start_msec
		if all_ready_msec >= 0 and target_visible_msec >= 0:
			break

	if player != null:
		var target_tile: Vector2i = target_chunk * WorldRuntimeConstants.CHUNK_SIZE + target_local
		player.global_position = WorldRuntimeConstants.tile_to_world_center(target_tile) + Vector2(160.0, 96.0)
	if camera != null:
		camera.enabled = true
		camera.position_smoothing_enabled = false
		camera.zoom = Vector2(0.80, 0.80)
		camera.force_update_scroll()

	var mining_report: Dictionary = await _run_mining_sequence(streamer, player)
	var last_mined_tile: Vector2i = mining_report.get("last_mined_tile", Vector2i(-1, -1)) as Vector2i
	if player != null and last_mined_tile != Vector2i(-1, -1):
		player.global_position = WorldRuntimeConstants.tile_to_world_center(last_mined_tile) + Vector2(96.0, 64.0)
		if camera != null:
			camera.force_update_scroll()

	await _settle_frames(30)
	var normal_path: String = "%s/contour_density60_normal.png" % OUTPUT_DIR
	_capture_viewport(normal_path)
	var normal_stats: Dictionary = _sample_current_viewport_stats()

	if not streamer._debug_mountain_solid_visible:
		streamer.toggle_debug_mountain_solid_mask()
	if not streamer._debug_mountain_contour_visible:
		streamer.toggle_debug_mountain_contour()
	await _settle_frames(20)
	var debug_path: String = "%s/contour_density60_debug.png" % OUTPUT_DIR
	_capture_viewport(debug_path)
	var debug_stats: Dictionary = _sample_current_viewport_stats()

	var target_state: Dictionary = streamer.get_contour_result_debug_state(
		target_chunk_coord,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	var target_result: Dictionary = {}
	var chunk_results: Dictionary = streamer._contour_results_by_chunk.get(target_chunk_coord, {}) as Dictionary
	if not chunk_results.is_empty():
		target_result = chunk_results.get(WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS, {}) as Dictionary
	var render_state: Dictionary = _get_chunk_render_state(streamer, target_chunk_coord)
	var report: Dictionary = {
		"seed": int(selected.get("seed", 0)),
		"density_internal": DENSITY,
		"density_ui_percent": int(roundi(DENSITY * 100.0)),
		"lake_density_internal": 0.0,
		"target_chunk": target_chunk_coord,
		"target_local": target_local,
		"target_tile": target_chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + target_local,
		"expected_initial_chunks": expected_count,
		"loaded_chunk_events": _chunk_loaded_times.size(),
		"first_chunk_loaded_ms": first_chunk_msec,
		"early_screenshot_ms": early_screenshot_msec,
		"early_screenshot": ProjectSettings.globalize_path(early_path),
		"early_image_stats": early_stats,
		"all_desired_contour_ready_ms": all_ready_msec,
		"target_mountain_contour_ready_ms": target_visible_msec,
		"probe_note": "Timing starts after new-world spawn resolution, when player is moved next to the density 60 mountain target.",
		"target_mountain_result": target_state,
		"target_mountain_mask_stats": _summarize_contour_mask(target_result),
		"target_mountain_cover_stats": _summarize_target_cover(streamer, target_chunk_coord),
		"target_ground_material_stats": _summarize_target_ground_material(streamer, target_chunk_coord),
		"target_mountain_material_stats": _summarize_target_mountain_material(streamer, target_chunk_coord),
		"target_render_state": render_state,
		"mining_sequence": mining_report,
		"normal_screenshot": ProjectSettings.globalize_path(normal_path),
		"debug_screenshot": ProjectSettings.globalize_path(debug_path),
		"normal_image_stats": normal_stats,
		"debug_image_stats": debug_stats,
	}
	var json_path: String = "%s/probe_report.json" % OUTPUT_DIR
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	report["report_path"] = ProjectSettings.globalize_path(json_path)
	print("RUNTIME_SDF_CONTOUR_VISUAL_PROBE_JSON=" + JSON.stringify(report))

	if event_bus != null and event_bus.has_signal("chunk_loaded") \
			and event_bus.is_connected("chunk_loaded", _on_chunk_loaded):
		event_bus.disconnect("chunk_loaded", _on_chunk_loaded)
	current_scene = null
	world_scene.queue_free()
	await _settle_frames(30)
	quit(1 if _failed else 0)

func _build_mountain_settings() -> MountainGenSettings:
	var settings := MountainGenSettings.hard_coded_defaults()
	settings.density = DENSITY
	return settings

func _find_density60_mountain_target() -> Dictionary:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	if world_core == null:
		return {}
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = 0.0
	var seed: int = PROBE_SEED
	var settings: MountainGenSettings = _build_mountain_settings()
	var scratch := WorldStreamer.new()
	scratch._apply_worldgen_settings(settings, bounds, foundation, lakes)
	var settings_packed: PackedFloat32Array = scratch._worldgen_settings_packed.duplicate()
	var spawn_result: Variant = world_core.call(
		"resolve_world_foundation_spawn_tile",
		seed,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	if spawn_result is not Dictionary or not bool((spawn_result as Dictionary).get("success", false)):
		scratch.free()
		return {}
	var spawn_tile: Vector2i = (spawn_result as Dictionary).get("spawn_tile", Vector2i.ZERO) as Vector2i
	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn_tile)
	var desired: Array[Vector2i] = scratch._build_desired_chunk_coords(center_chunk)
	var coords := PackedVector2Array()
	for coord: Vector2i in desired:
		coords.append(Vector2(coord.x, coord.y))
	print("visual_probe: scanning spawn radius seed=%d density=%.2f spawn_tile=%s" % [seed, DENSITY, str(spawn_tile)])
	var packets_variant: Variant = world_core.call(
		"generate_chunk_packets_batch",
		seed,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	scratch.free()
	if packets_variant is not Array:
		return {}
	var packets: Array = packets_variant as Array
	for packet_variant: Variant in packets:
		var packet: Dictionary = packet_variant as Dictionary
		var mountain_local: Vector2i = _find_mountain_local_in_packet(packet)
		if mountain_local != Vector2i(-1, -1):
			return {
				"seed": seed,
				"spawn_tile": spawn_tile,
				"target_chunk": packet.get("chunk_coord", Vector2i.ZERO) as Vector2i,
				"target_local": mountain_local,
			}
	var ring_result: Dictionary = _scan_mountain_target_around_chunk(
		world_core,
		seed,
		settings_packed,
		center_chunk
	)
	if not ring_result.is_empty():
		ring_result["spawn_tile"] = spawn_tile
		return ring_result
	return {}

func _scan_mountain_target_around_chunk(
	world_core: Object,
	seed: int,
	settings_packed: PackedFloat32Array,
	center_chunk: Vector2i
) -> Dictionary:
	var seen: Dictionary = {}
	for radius: int in range(2, 9):
		var candidates: Array[Vector2i] = []
		for y: int in range(center_chunk.y - radius, center_chunk.y + radius + 1):
			for x: int in range(center_chunk.x - radius, center_chunk.x + radius + 1):
				if x != center_chunk.x - radius \
						and x != center_chunk.x + radius \
						and y != center_chunk.y - radius \
						and y != center_chunk.y + radius:
					continue
				var coord := Vector2i(x, y)
				if seen.has(coord):
					continue
				seen[coord] = true
				candidates.append(coord)
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da: int = (a - center_chunk).length_squared()
			var db: int = (b - center_chunk).length_squared()
			return da < db if da != db else (a.x < b.x if a.x != b.x else a.y < b.y)
		)
		print("visual_probe: scanning mountain ring radius=%d candidate_count=%d" % [radius, candidates.size()])
		for coord: Vector2i in candidates:
			var coords := PackedVector2Array()
			coords.append(Vector2(coord.x, coord.y))
			var packets_variant: Variant = world_core.call(
				"generate_chunk_packets_batch",
				seed,
				coords,
				WorldRuntimeConstants.WORLD_VERSION,
				settings_packed
			)
			if packets_variant is not Array:
				continue
			var packets: Array = packets_variant as Array
			if packets.is_empty():
				continue
			var packet: Dictionary = packets[0] as Dictionary
			var mountain_local: Vector2i = _find_mountain_local_in_packet(packet)
			if mountain_local != Vector2i(-1, -1):
				return {
					"seed": seed,
					"target_chunk": packet.get("chunk_coord", coord) as Vector2i,
					"target_local": mountain_local,
				}
	return {}

func _wait_for_spawn_resolution(streamer: WorldStreamer) -> void:
	for _frame: int in range(MAX_PROBE_FRAMES):
		streamer._streaming_tick()
		if not streamer._awaiting_new_game_spawn_result and streamer._player_chunk_coord != streamer.INVALID_CHUNK_COORD:
			return
		await process_frame

func _find_mountain_local_in_packet(packet: Dictionary) -> Vector2i:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		var is_mountain: bool = terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
			or terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED
		if not is_mountain:
			continue
		if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
			continue
		if index < mountain_flags.size() \
				and terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
			var flags: int = int(mountain_flags[index])
			if (flags & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) == 0:
				continue
		return WorldRuntimeConstants.index_to_local(index)
	return Vector2i(-1, -1)

func _all_desired_chunks_contour_ready(streamer: WorldStreamer, desired: Array[Vector2i]) -> bool:
	if desired.is_empty():
		return false
	for coord: Vector2i in desired:
		if not _chunk_contour_ready(streamer, coord):
			return false
	return true

func _chunk_contour_ready(streamer: WorldStreamer, coord: Vector2i) -> bool:
	var view: ChunkView = streamer._chunk_views.get(coord) as ChunkView
	if view == null:
		return false
	var state: Dictionary = view.get_contour_render_debug_state()
	return bool(state.get("ready", false)) and bool(state.get("visible", false))

func _run_mining_sequence(streamer: WorldStreamer, player: Node2D) -> Dictionary:
	var records: Array[Dictionary] = []
	var last_mined_tile := Vector2i(-1, -1)
	var anchor: Vector2 = player.global_position if player != null else Vector2.ZERO
	for step_index: int in range(MINING_STEPS):
		var dig_tile: Vector2i = _find_loaded_diggable_tile(streamer, anchor)
		if dig_tile == Vector2i(-1, -1):
			break
		var dig_world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(dig_tile)
		var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(dig_tile)
		var start_usec: int = Time.get_ticks_usec()
		var result: Dictionary = streamer.try_harvest_at_world(dig_world_pos)
		var call_usec: int = Time.get_ticks_usec() - start_usec
		var success: bool = bool(result.get("success", false))
		var immediate_path: String = ""
		var immediate_stats: Dictionary = {}
		var immediate_render_state: Dictionary = {}
		if success and step_index == 0:
			await process_frame
			immediate_path = "%s/contour_density60_after_first_dig_immediate.png" % OUTPUT_DIR
			_capture_viewport(immediate_path)
			immediate_stats = _sample_current_viewport_stats()
			immediate_render_state = _get_chunk_render_state(streamer, chunk_coord)
		var ready_msec: int = -1
		var wait_start_msec: int = Time.get_ticks_msec()
		for _frame: int in range(MAX_PROBE_FRAMES):
			streamer._streaming_tick()
			await process_frame
			var dirty_state: Dictionary = streamer.get_contour_dirty_debug_state(chunk_coord)
			if bool(dirty_state.get("ready", false)) and _chunk_contour_ready(streamer, chunk_coord):
				ready_msec = Time.get_ticks_msec() - wait_start_msec
				break
		if success:
			last_mined_tile = dig_tile
			anchor = dig_world_pos
		records.append({
			"step": step_index,
			"success": success,
			"tile": dig_tile,
			"chunk": chunk_coord,
			"call_usec": call_usec,
			"contour_ready_ms": ready_msec,
			"dirty_state": streamer.get_contour_dirty_debug_state(chunk_coord),
			"result_state": streamer.get_contour_result_debug_state(
				chunk_coord,
				WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
			),
			"immediate_screenshot": ProjectSettings.globalize_path(immediate_path) if not immediate_path.is_empty() else "",
			"immediate_image_stats": immediate_stats,
			"immediate_render_state": immediate_render_state,
			"pending_request_count": streamer._contour_pending_requests.size(),
			"inflight_count": streamer._contour_inflight_count,
			"message_key": str(result.get("message_key", "")),
		})
		if not success:
			break
	return {
		"requested_steps": MINING_STEPS,
		"completed_steps": records.size(),
		"last_mined_tile": last_mined_tile,
		"records": records,
	}

func _find_loaded_diggable_tile(streamer: WorldStreamer, anchor: Vector2) -> Vector2i:
	var best_tile := Vector2i(-1, -1)
	var best_distance_sq: float = 1000000000000.0
	var chunk_coords: Array[Vector2i] = []
	for chunk_variant: Variant in streamer._chunk_packets.keys():
		chunk_coords.append(chunk_variant as Vector2i)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	for chunk_coord: Vector2i in chunk_coords:
		for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
			var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
			var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord
			var world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(world_tile)
			if not streamer.has_resource_at_world(world_pos):
				continue
			var distance_sq: float = world_pos.distance_squared_to(anchor)
			if distance_sq < best_distance_sq:
				best_distance_sq = distance_sq
				best_tile = world_tile
	return best_tile

func _get_chunk_render_state(streamer: WorldStreamer, coord: Vector2i) -> Dictionary:
	var view: ChunkView = streamer._chunk_views.get(coord) as ChunkView
	if view == null:
		return {"ready": false}
	return view.get_contour_render_debug_state()

func _summarize_contour_mask(result: Dictionary) -> Dictionary:
	var pixel_size: Vector2i = result.get("pixel_size", Vector2i.ZERO) as Vector2i
	var mask: PackedByteArray = result.get("mask_rgba8", PackedByteArray()) as PackedByteArray
	if pixel_size.x <= 0 or pixel_size.y <= 0 or mask.size() != pixel_size.x * pixel_size.y * 4:
		return {"ready": false}
	var stride: int = 16
	var samples: int = 0
	var top: int = 0
	var face: int = 0
	var back: int = 0
	var alpha: int = 0
	var top_sum: int = 0
	var face_sum: int = 0
	var back_sum: int = 0
	var alpha_sum: int = 0
	for y: int in range(0, pixel_size.y, stride):
		for x: int in range(0, pixel_size.x, stride):
			var offset: int = (y * pixel_size.x + x) * 4
			samples += 1
			var top_value: int = int(mask[offset])
			var face_value: int = int(mask[offset + 1])
			var back_value: int = int(mask[offset + 2])
			var alpha_value: int = int(mask[offset + 3])
			top_sum += top_value
			face_sum += face_value
			back_sum += back_value
			alpha_sum += alpha_value
			if top_value > 10:
				top += 1
			if face_value > 10:
				face += 1
			if back_value > 10:
				back += 1
			if alpha_value > 10:
				alpha += 1
	return {
		"ready": true,
		"samples": samples,
		"top_ratio": float(top) / float(maxi(1, samples)),
		"face_ratio": float(face) / float(maxi(1, samples)),
		"back_ratio": float(back) / float(maxi(1, samples)),
		"alpha_ratio": float(alpha) / float(maxi(1, samples)),
		"top_avg": float(top_sum) / float(maxi(1, samples)),
		"face_avg": float(face_sum) / float(maxi(1, samples)),
		"back_avg": float(back_sum) / float(maxi(1, samples)),
		"alpha_avg": float(alpha_sum) / float(maxi(1, samples)),
	}

func _summarize_target_cover(streamer: WorldStreamer, coord: Vector2i) -> Dictionary:
	var view: ChunkView = streamer._chunk_views.get(coord) as ChunkView
	if view == null:
		return {"ready": false}
	var result: Dictionary = {"ready": true, "mountains": {}}
	for mountain_id_variant: Variant in view._roof_mask_images_by_mountain.keys():
		var mountain_id: int = int(mountain_id_variant)
		var image: Image = view._roof_mask_images_by_mountain.get(mountain_id, null) as Image
		if image == null:
			continue
		var samples: int = 0
		var covered: int = 0
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				samples += 1
				if image.get_pixel(x, y).r > 0.5:
					covered += 1
		(result["mountains"] as Dictionary)[mountain_id] = {
			"samples": samples,
			"covered_ratio": float(covered) / float(maxi(1, samples)),
			"membership_ratio": _sample_l8_image_ratio(
				view._contour_membership_images_by_mountain.get(mountain_id, null) as Image
			),
		}
	return result

func _summarize_target_ground_material(streamer: WorldStreamer, coord: Vector2i) -> Dictionary:
	var view: ChunkView = streamer._chunk_views.get(coord) as ChunkView
	if view == null or view._contour_ground_visual == null:
		return {"ready": false}
	var material: ShaderMaterial = view._contour_ground_visual.material as ShaderMaterial
	if material == null:
		return {"ready": false}
	return {
		"ready": true,
		"base_albedo": _summarize_texture(material.get_shader_parameter(&"base_albedo_tex")),
		"top_albedo": _summarize_texture(material.get_shader_parameter(&"top_albedo_tex")),
		"face_albedo": _summarize_texture(material.get_shader_parameter(&"face_albedo_tex")),
		"top_normal": _summarize_texture(material.get_shader_parameter(&"top_normal_tex")),
		"face_normal": _summarize_texture(material.get_shader_parameter(&"face_normal_tex")),
	}

func _summarize_target_mountain_material(streamer: WorldStreamer, coord: Vector2i) -> Dictionary:
	var view: ChunkView = streamer._chunk_views.get(coord) as ChunkView
	if view == null:
		return {"ready": false}
	var result: Dictionary = {"ready": true, "mountains": {}}
	for mountain_id_variant: Variant in view._contour_mountain_visuals_by_id.keys():
		var mountain_id: int = int(mountain_id_variant)
		var visual: Sprite2D = view._contour_mountain_visuals_by_id.get(mountain_id, null) as Sprite2D
		var material: ShaderMaterial = visual.material as ShaderMaterial if visual != null else null
		if material == null:
			continue
		(result["mountains"] as Dictionary)[mountain_id] = {
			"base_albedo": _summarize_texture(material.get_shader_parameter(&"base_albedo_tex")),
			"top_albedo": _summarize_texture(material.get_shader_parameter(&"top_albedo_tex")),
			"face_albedo": _summarize_texture(material.get_shader_parameter(&"face_albedo_tex")),
			"top_modulation": _summarize_texture(material.get_shader_parameter(&"top_modulation")),
			"face_modulation": _summarize_texture(material.get_shader_parameter(&"face_modulation")),
			"top_normal": _summarize_texture(material.get_shader_parameter(&"top_normal_tex")),
			"face_normal": _summarize_texture(material.get_shader_parameter(&"face_normal_tex")),
		}
	return result

func _summarize_texture(texture_variant: Variant) -> Dictionary:
	var texture: Texture2D = texture_variant as Texture2D
	if texture == null:
		return {"ready": false}
	var image: Image = texture.get_image()
	if image == null:
		return {"ready": false, "resource_path": texture.resource_path}
	var samples: int = 0
	var brightness_sum: float = 0.0
	for y: int in range(0, image.get_height(), 16):
		for x: int in range(0, image.get_width(), 16):
			var color: Color = image.get_pixel(x, y)
			brightness_sum += (color.r + color.g + color.b) / 3.0
			samples += 1
	return {
		"ready": true,
		"resource_path": texture.resource_path,
		"width": image.get_width(),
		"height": image.get_height(),
		"avg_brightness": brightness_sum / float(maxi(1, samples)),
	}

func _sample_l8_image_ratio(image: Image) -> float:
	if image == null:
		return -1.0
	var samples: int = 0
	var active: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			samples += 1
			if image.get_pixel(x, y).r > 0.5:
				active += 1
	return float(active) / float(maxi(1, samples))

func _settle_frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame

func _capture_viewport(path: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	var absolute_path: String = (ProjectSettings.globalize_path(path) if path.begins_with("res://") else path).replace("\\", "/")
	var png_bytes: PackedByteArray = image.save_png_to_buffer()
	if png_bytes.is_empty():
		_fail("Failed to encode viewport capture %s." % [absolute_path])
		return
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_fail("Failed to open viewport capture %s: %d" % [absolute_path, FileAccess.get_open_error()])
		return
	file.store_buffer(png_bytes)
	file.close()

func _sample_image_stats(path: String) -> Dictionary:
	var image := Image.new()
	var absolute_path: String = (ProjectSettings.globalize_path(path) if path.begins_with("res://") else path).replace("\\", "/")
	var err: Error = image.load(absolute_path)
	if err != OK:
		return {"loaded": false, "error": err}
	return _sample_image_stats_from_image(image)

func _sample_current_viewport_stats() -> Dictionary:
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null:
		return {"loaded": false, "error": "viewport_image_null"}
	return _sample_image_stats_from_image(image)

func _sample_image_stats_from_image(image: Image) -> Dictionary:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var sample_count: int = 0
	var dark_count: int = 0
	var cyan_count: int = 0
	var non_background_count: int = 0
	for y: int in range(0, height, 8):
		for x: int in range(0, width, 8):
			var color: Color = image.get_pixel(x, y)
			sample_count += 1
			var brightness: float = (color.r + color.g + color.b) / 3.0
			if brightness < 0.025:
				dark_count += 1
			if color.g > 0.55 and color.b > 0.55 and color.r < 0.20:
				cyan_count += 1
			if absf(color.r - 0.08) > 0.025 or absf(color.g - 0.10) > 0.025 or absf(color.b - 0.06) > 0.025:
				non_background_count += 1
	return {
		"loaded": true,
		"width": width,
		"height": height,
		"samples": sample_count,
		"dark_ratio": float(dark_count) / float(maxi(1, sample_count)),
		"cyan_ratio": float(cyan_count) / float(maxi(1, sample_count)),
		"non_background_ratio": float(non_background_count) / float(maxi(1, sample_count)),
	}

func _prepare_output_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

func _on_chunk_loaded(chunk_coord: Vector2i) -> void:
	if not _chunk_loaded_times.has(chunk_coord):
		_chunk_loaded_times[chunk_coord] = Time.get_ticks_msec()

func _fail(message: String) -> void:
	push_error(message)
	_failed = true
