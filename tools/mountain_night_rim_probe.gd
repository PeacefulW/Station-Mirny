extends SceneTree

# Рендер-проба ночного свечения кромок горы: rim/cut/lip подсветка должна
# гаснуть вместе с тенями (projected_shadow_opacity -> 0 ночью), а не
# разгораться от low-sun длины теней. Артефакты:
# - mountain_day.png / mountain_night.png + mountain_day_night_panel.png
# - лог: p99 люмы ночного кадра (неоновая кромка задирала хвост яркости).
# Windowed. Запуск:
#   Godot_v4.6.2-stable_win64_console.exe --path . -s tools/mountain_night_rim_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/mountain_night_rim_probe"
const MAX_SETTLE_FRAMES: int = 600
const PANEL_DIVIDER_PX: int = 4

var _streamer: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_night_rim_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var daylight: CanvasModulate = scene.get_node_or_null("Daylight") as CanvasModulate
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		mountain,
		bounds,
		foundation,
		lakes,
	)
	time_manager.call("set_paused", true)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)
	camera.zoom = Vector2(0.45, 0.45)
	camera.set("_target_zoom", 0.45)
	DirAccess.open("res://").make_dir_recursive("artifacts/mountain_night_rim_probe")

	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	# Спавн применяется асинхронно: позицию читаем после первого stable.
	await _stream_until_stable()
	var home: Vector2 = player.global_position
	var mountain_offset: Vector2 = _find_mountain_offset(home)
	if mountain_offset == Vector2.INF:
		push_error("mountain_night_rim_probe: no partial mountain chunk found")
		quit(1)
		return
	player.global_position = home + mountain_offset
	_streamer._update_player_chunk_coord()
	await _stream_until_stable()
	camera.force_update_scroll()

	var frames: Array[Image] = []
	for capture: Dictionary in [
		{ "name": "day", "hour": 12.0 },
		{ "name": "night", "hour": 23.0 },
	]:
		time_manager.call("set_paused", true)
		time_manager.call("restore_persisted_state", float(capture["hour"]), 1, 0)
		time_manager.call("set_paused", true)
		daylight._sync_from_current_context(true)
		_streamer._sync_sun_lighting_from_time(true)
		await _wait_frames(10)
		var img: Image = await _capture()
		img.save_png("%s/mountain_%s.png" % [OUTPUT_DIR, str(capture["name"])])
		frames.append(img)
		print(
			"mountain_night_rim_probe: %s p99_luma=%.3f" % [
				str(capture["name"]),
				_p99_luma(img),
			],
		)
	_save_panel(frames, "%s/mountain_day_night_panel.png" % OUTPUT_DIR)
	print("mountain_night_rim_probe: DONE")
	scene.queue_free()
	await process_frame
	quit(0)


func _p99_luma(source: Image) -> float:
	var img: Image = source.duplicate() as Image
	img.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	var lumas: Array[float] = []
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var pixel: Color = img.get_pixel(x, y)
			lumas.append(pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114)
	lumas.sort()
	return lumas[int(float(lumas.size() - 1) * 0.99)]


func _find_mountain_offset(home: Vector2) -> Vector2:
	var core: Object = ClassDB.instantiate("WorldCore")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	packed = lakes.write_to_settings_packed(packed)
	var home_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(
		WorldRuntimeConstants.world_to_tile(home),
	)
	for radius: int in range(1, 25):
		var coords := PackedVector2Array()
		for cy: int in range(home_chunk.y - radius, home_chunk.y + radius + 1):
			for cx: int in range(home_chunk.x - radius, home_chunk.x + radius + 1):
				if maxi(absi(cx - home_chunk.x), absi(cy - home_chunk.y)) == radius:
					coords.append(Vector2(cx, cy))
		var packets: Array = core.call(
			"generate_chunk_packets_batch",
			WorldRuntimeConstants.DEFAULT_WORLD_SEED,
			coords,
			WorldRuntimeConstants.WORLD_VERSION,
			packed,
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			var solids: int = _mountain_solid_count(packet)
			if solids < 70 or solids > 200:
				continue
			var south_tile: Vector2i = _find_south_mountain_edge_tile(packet)
			if south_tile == Vector2i(-1, -1):
				continue
			var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
			var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE \
					+ south_tile + Vector2i(0, 4)
			print("mountain_night_rim_probe: mountain chunk %s south_tile=%s" % [str(chunk_coord), str(south_tile)])
			return WorldRuntimeConstants.tile_to_world_center(world_tile) - home
	return Vector2.INF


func _find_south_mountain_edge_tile(packet: Dictionary) -> Vector2i:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	if terrain_ids.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return Vector2i(-1, -1)
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE - 6, 1, -1):
		for x: int in range(2, WorldRuntimeConstants.CHUNK_SIZE - 2):
			var terrain_id: int = int(terrain_ids[y * WorldRuntimeConstants.CHUNK_SIZE + x])
			var below_id: int = int(terrain_ids[(y + 1) * WorldRuntimeConstants.CHUNK_SIZE + x])
			var solid: bool = terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
			var below_open: bool = below_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					and below_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
			if solid and below_open:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _mountain_solid_count(packet: Dictionary) -> int:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var count: int = 0
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			count += 1
	return count


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


func _stream_until_stable() -> void:
	for _tick: int in range(MAX_SETTLE_FRAMES):
		_streamer._streaming_tick()
		if _streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			_streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
		if _streamer._requested_chunks.is_empty() \
				and int(debug.get("native_mask_inflight_count", 0)) == 0 \
				and int(debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_inflight_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("grass_scatter_visual_upload_queue_count", 0)) == 0 \
				and not _streamer._has_pending_streaming_work():
			return


func _save_panel(frames: Array[Image], path: String) -> void:
	if frames.is_empty():
		return
	var frame_size: Vector2i = frames[0].get_size()
	var panel := Image.create(
		frame_size.x * frames.size() + PANEL_DIVIDER_PX * (frames.size() - 1),
		frame_size.y,
		false,
		frames[0].get_format(),
	)
	panel.fill(Color.BLACK)
	for index: int in range(frames.size()):
		panel.blit_rect(
			frames[index],
			Rect2i(Vector2i.ZERO, frame_size),
			Vector2i(index * (frame_size.x + PANEL_DIVIDER_PX), 0),
		)
	panel.save_png(path)
	print("mountain_night_rim_probe: panel saved %s" % ProjectSettings.globalize_path(path))
