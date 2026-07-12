extends Node

# Close-up multi-chunk render of the LIVE runtime mountains (real ChunkView sprites)
# so chunk-boundary artifacts (overlap doubling, texture shimmer) are visible.
# Windowed (viewport capture needs a GPU). Saves a zoomed screenshot.

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const SEED: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
const DENSITY: float = 0.60
const LAKE_DENSITY: float = 0.0
const SCAN_RADIUS: int = 24
const ZOOM: float = 1.3
const OUT: String = "res://artifacts/mountain_closeup/closeup.png"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("must run windowed"); get_tree().quit(1); return
	var core: Object = ClassDB.instantiate("WorldCore")
	var settings_packed: PackedFloat32Array = _settings_packed()
	var spawn: Dictionary = core.call("resolve_world_foundation_spawn_tile", SEED, WorldRuntimeConstants.WORLD_VERSION, settings_packed) as Dictionary
	var center: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn.get("spawn_tile", Vector2i.ZERO) as Vector2i)
	var edge_tile: Vector2i = _find_dense_mountain_tile(core, settings_packed, center)
	if edge_tile == Vector2i(-1, -1):
		push_error("mountain_closeup_probe: no partial mountain edge found")
		get_tree().quit(1)
		return

	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var streamer = scene.get_node_or_null("WorldStreamer")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	var camera: Camera2D = scene.get_node_or_null("Player/Camera2D") as Camera2D
	var settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	settings.density = DENSITY
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	streamer.initialize_new_world(SEED, settings, bounds, foundation, lakes)
	if camera != null:
		camera.enabled = true
		camera.position_smoothing_enabled = false
		camera.zoom = Vector2(ZOOM, ZOOM)
	# Let the async foundation spawn settle before moving the player; otherwise
	# the deferred spawn assignment can overwrite the probe target.
	await _stream_until_stable(streamer)
	player.global_position = WorldRuntimeConstants.tile_to_world_center(edge_tile)
	streamer._update_player_chunk_coord()
	await _stream_until_stable(streamer)
	if camera != null:
		camera.force_update_scroll()
	for _frame: int in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	DirAccess.open("res://").make_dir_recursive("artifacts/mountain_closeup")
	if img != null:
		img.save_png(OUT)
		print("mountain_closeup_probe: OK -> %s" % ProjectSettings.globalize_path(OUT))
	else:
		print("mountain_closeup_probe: capture failed")
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _stream_until_stable(streamer: Variant) -> void:
	for _f: int in range(300):
		streamer._streaming_tick()
		if streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			streamer._mountain_native_mask_visual_apply_tick()
		await get_tree().process_frame
		var d: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
		if streamer._requested_chunks.is_empty() \
				and int(d.get("native_mask_inflight_count", 0)) == 0 \
				and int(d.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(d.get("ready_native_mask_chunk_count", 0)) > 0 \
				and not streamer._has_pending_streaming_work():
			return

func _find_dense_mountain_tile(core: Object, settings: PackedFloat32Array, center: Vector2i) -> Vector2i:
	# Pick a partly-mountain chunk (has an edge, ~half solid) so the capture frames
	# both the rock top and the facade/contour where artifacts show.
	for radius: int in range(1, SCAN_RADIUS + 1):
		var coords := PackedVector2Array()
		for cy: int in range(center.y - radius, center.y + radius + 1):
			for cx: int in range(center.x - radius, center.x + radius + 1):
				if maxi(absi(cx - center.x), absi(cy - center.y)) == radius:
					coords.append(Vector2(cx, cy))
		if coords.is_empty():
			continue
		var packets: Array = core.call("generate_chunk_packets_batch", SEED, coords, WorldRuntimeConstants.WORLD_VERSION, settings) as Array
		for pv: Variant in packets:
			var p: Dictionary = pv as Dictionary
			var s: int = _solids(p)
			if s < 70 or s > 200:
				continue
			var south_tile: Vector2i = _find_south_mountain_edge_tile(p)
			if south_tile == Vector2i(-1, -1):
				continue
			var chunk_coord: Vector2i = p.get("chunk_coord", Vector2i.ZERO) as Vector2i
			return chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + south_tile + Vector2i(0, 1)
	return Vector2i(-1, -1)


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

func _solids(packet: Dictionary) -> int:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var c: int = 0
	for i: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var t: int = int(terrain_ids[i])
		if t == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				or t == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			c += 1
	return c

func _settings_packed() -> PackedFloat32Array:
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	var mountain: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	mountain.density = DENSITY
	var packed: PackedFloat32Array = mountain.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	return lakes.write_to_settings_packed(packed)
