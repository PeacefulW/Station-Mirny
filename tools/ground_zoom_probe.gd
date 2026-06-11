extends Node

# Multi-zoom ground look probe: renders the live runtime ground at close, mid,
# and far camera zoom over the spawn plains so texture repetition, aliasing,
# seams, and macro tone quality can be compared before/after material changes.
# Windowed (viewport capture needs a GPU).

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/ground_zoom_probe"
const CAPTURE_HOUR: float = 12.0
const ZOOM_LEVELS: Array[float] = [1.0, 0.45, 0.22]
const MAX_SETTLE_FRAMES: int = 600

var _streamer: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ground_zoom_probe: must run windowed")
		get_tree().quit(1)
		return
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
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
		lakes
	)
	TimeManager.set_paused(true)
	TimeManager.restore_persisted_state(CAPTURE_HOUR, 1, 0)
	TimeManager.set_paused(true)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.set_process(false)

	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var home: Vector2 = player.global_position
	var spots: Dictionary = {
		"spawn": Vector2.ZERO,
		"edge": Vector2(1600.0, 1100.0),
	}
	var shore_offset: Vector2 = _find_shore_offset(home)
	if shore_offset != Vector2.INF:
		spots["shore"] = shore_offset
	DirAccess.open("res://").make_dir_recursive("artifacts/ground_zoom_probe")
	for spot_name: String in spots.keys():
		player.global_position = home + (spots[spot_name] as Vector2)
		_streamer._update_player_chunk_coord()
		if spot_name == "shore":
			await _stream_until_stable()
			_dump_terrain_edge_states(player.global_position)
			await _capture_water_fill_ablation(camera)
		for zoom: float in ZOOM_LEVELS:
			camera.zoom = Vector2(zoom, zoom)
			camera.set("_target_zoom", zoom)
			await _stream_until_stable()
			_streamer._sync_sun_lighting_from_time(true)
			camera.force_update_scroll()
			for _frame: int in range(10):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			if img == null:
				print("ground_zoom_probe: capture FAILED zoom %.2f" % zoom)
				continue
			var path: String = "%s/%s_zoom_%03d.png" % [OUTPUT_DIR, spot_name, int(zoom * 100.0)]
			img.save_png(path)
			print("ground_zoom_probe: saved %s" % ProjectSettings.globalize_path(path))

	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _find_shore_offset(home: Vector2) -> Vector2:
	# Scan generated packets around the spawn for the nearest chunk holding both
	# dry land and visible lake water, so the shoreline band can be captured.
	var core: Object = ClassDB.instantiate("WorldCore")
	if core == null or not core.has_method("generate_chunk_packets_batch"):
		return Vector2.INF
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	packed = lakes.write_to_settings_packed(packed)
	var home_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(
		WorldRuntimeConstants.world_to_tile(home)
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
			packed
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			var shore_local: Vector2i = _find_shore_land_tile(packet)
			if shore_local == Vector2i(-1, -1):
				continue
			var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
			var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + shore_local
			print("ground_zoom_probe: shore chunk %s tile %s" % [str(chunk_coord), str(shore_local)])
			return WorldRuntimeConstants.tile_to_world_center(world_tile) - home
	return Vector2.INF

func _find_shore_land_tile(packet: Dictionary) -> Vector2i:
	# Pick a dry land tile orthogonally adjacent to visible water, so the
	# capture frames the actual shoreline band instead of open water.
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
	if terrain_ids.size() < WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return Vector2i(-1, -1)
	for y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			var index: int = y * WorldRuntimeConstants.CHUNK_SIZE + x
			if _is_water_index(lake_flags, index):
				continue
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or ny < 0 or nx >= WorldRuntimeConstants.CHUNK_SIZE or ny >= WorldRuntimeConstants.CHUNK_SIZE:
					continue
				if _is_water_index(lake_flags, ny * WorldRuntimeConstants.CHUNK_SIZE + nx):
					return Vector2i(x, y)
	return Vector2i(-1, -1)

func _is_water_index(lake_flags: PackedByteArray, index: int) -> bool:
	return index < lake_flags.size() \
		and (int(lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0

func _capture_water_fill_ablation(camera: Camera2D) -> void:
	camera.zoom = Vector2(0.45, 0.45)
	camera.set("_target_zoom", 0.45)
	camera.force_update_scroll()
	var hidden: Array[Sprite2D] = []
	for chunk_view_variant: Variant in _streamer._chunk_views.values():
		var chunk_view: Node = chunk_view_variant as Node
		var fill: Sprite2D = chunk_view.get("_water_fill_sprite") as Sprite2D
		if fill != null and is_instance_valid(fill) and fill.visible:
			hidden.append(fill)
			fill.visible = false
	print("ground_zoom_probe: water_fill_visible_chunks=%d" % hidden.size())
	for _frame: int in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/shore_nofill.png" % OUTPUT_DIR)
		print("ground_zoom_probe: saved shore_nofill.png")
	for fill: Sprite2D in hidden:
		if is_instance_valid(fill):
			fill.visible = true

func _dump_terrain_edge_states(world_pos: Vector2) -> void:
	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(
		WorldRuntimeConstants.world_to_tile(world_pos)
	)
	for dy: int in range(-2, 3):
		var row: String = ""
		for dx: int in range(-2, 3):
			var coord: Vector2i = center_chunk + Vector2i(dx, dy)
			var chunk_view: Node = _streamer._chunk_views.get(coord, null) as Node
			if chunk_view == null:
				row += " [%s: no-view]" % str(coord)
				continue
			var state: Dictionary = chunk_view.get_terrain_edge_mask_debug_state()
			var packet: Dictionary = _streamer._chunk_packets.get(coord, {}) as Dictionary
			var lake_flags: PackedByteArray = packet.get("lake_flags", PackedByteArray()) as PackedByteArray
			var water_count: int = 0
			for index: int in range(mini(lake_flags.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
				if (int(lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0:
					water_count += 1
			var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
			var mountain_count: int = 0
			var bed_count: int = 0
			for tile_index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
				var tid: int = int(terrain_ids[tile_index])
				if tid == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
						or tid == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
					mountain_count += 1
				elif tid == WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW \
						or tid == WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP:
					bed_count += 1
			var mountain_debug: Dictionary = chunk_view.get_mountain_render_page_debug_state() \
				if chunk_view.has_method("get_mountain_render_page_debug_state") else {}
			row += " [%s: act=%d w=%d mnt=%d bed=%d mask_ready=%s]" % [
				str(coord),
				1 if bool(state.get("terrain_edge_mask_active", false)) else 0,
				water_count,
				mountain_count,
				bed_count,
				str(mountain_debug.get("ready", "?")),
			]
		print("ground_zoom_probe: edge_state%s" % row)

func _stream_until_stable() -> void:
	for _tick: int in range(MAX_SETTLE_FRAMES):
		_streamer._streaming_tick()
		if _streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			_streamer._mountain_native_mask_visual_apply_tick()
		await get_tree().process_frame
		var debug: Dictionary = _streamer.get_mountain_mask_runtime_debug_state()
		if _streamer._requested_chunks.is_empty() \
				and int(debug.get("native_mask_inflight_count", 0)) == 0 \
				and int(debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_inflight_count", 0)) == 0 \
				and int(debug.get("terrain_edge_mask_visual_upload_queue_count", 0)) == 0 \
				and not _streamer._has_pending_streaming_work():
			return
