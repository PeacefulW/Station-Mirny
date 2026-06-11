extends Node

# Mountain dressing variant probe: renders the SAME partial-mountain spot with
# several presentation presets (silhouette warp / sun-relative flank shading /
# roof drift / vein cracks) in one run, at mid and close zoom, under late
# afternoon light so flank shading and shadows read. Output feeds a comparison
# grid for art direction picks. Windowed (viewport capture needs a GPU).

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const WORLD_SCENE: String = "res://scenes/world/world_runtime_v0.tscn"
const OUTPUT_DIR: String = "res://artifacts/mountain_variants"
const CAPTURE_HOUR: float = 16.5
const MAX_SETTLE_FRAMES: int = 600

const VARIANTS: Array[Dictionary] = [
	{"name": "v0_current", "mask_warp_px": 7.0, "side_shade_strength": 0.16, "roof_drift_strength": 0.07, "roof_vein_strength": 0.16},
	{"name": "v1_drama", "mask_warp_px": 12.0, "side_shade_strength": 0.30, "roof_drift_strength": 0.12, "roof_vein_strength": 0.22},
	{"name": "v2_volume", "mask_warp_px": 9.0, "side_shade_strength": 0.45, "roof_drift_strength": 0.08, "roof_vein_strength": 0.10},
	{"name": "v3_jagged", "mask_warp_px": 16.0, "side_shade_strength": 0.22, "roof_drift_strength": 0.10, "roof_vein_strength": 0.30},
	{"name": "v4_epic", "mask_warp_px": 10.0, "side_shade_strength": 0.35, "roof_drift_strength": 0.15, "roof_vein_strength": 0.14},
]

var _streamer: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("mountain_variant_probe: must run windowed")
		get_tree().quit(1)
		return
	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	_streamer = scene.get_node_or_null("WorldStreamer")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
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

	# Let the async new-game spawn resolve land BEFORE taking the home anchor,
	# or the spawn snap will yank the player away from the probe spot.
	await _stream_until_stable()
	var home: Vector2 = player.global_position
	var mountain_offset: Vector2 = _find_mountain_offset(home)
	if mountain_offset == Vector2.INF:
		push_error("mountain_variant_probe: no partial-mountain chunk found")
		get_tree().quit(1)
		return
	player.global_position = home + mountain_offset
	_streamer._update_player_chunk_coord()
	await _stream_until_stable()
	_streamer._sync_sun_lighting_from_time(true)

	DirAccess.open("res://").make_dir_recursive("artifacts/mountain_variants")
	for variant: Dictionary in VARIANTS:
		_apply_variant(variant)
		for zoom: float in [0.45, 1.0]:
			camera.zoom = Vector2(zoom, zoom)
			camera.set("_target_zoom", zoom)
			camera.force_update_scroll()
			for _frame: int in range(6):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			if img == null:
				print("mountain_variant_probe: capture FAILED %s" % str(variant.get("name")))
				continue
			var path: String = "%s/%s_z%03d.png" % [OUTPUT_DIR, str(variant.get("name")), int(zoom * 100.0)]
			img.save_png(path)
			print("mountain_variant_probe: saved %s" % ProjectSettings.globalize_path(path))

	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _apply_variant(variant: Dictionary) -> void:
	for chunk_view_variant: Variant in _streamer._chunk_views.values():
		var chunk_view: Node = chunk_view_variant as Node
		if chunk_view == null:
			continue
		var material: ShaderMaterial = chunk_view.get("_mountain_top_mask_material") as ShaderMaterial
		if material == null:
			continue
		for key: String in ["mask_warp_px", "side_shade_strength", "roof_drift_strength", "roof_vein_strength"]:
			material.set_shader_parameter(key, float(variant.get(key, 0.0)))

func _find_mountain_offset(home: Vector2) -> Vector2:
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
			var solids: int = _mountain_solid_count(packet)
			if solids < 70 or solids > 200:
				continue
			var south_tile: Vector2i = _find_south_mountain_edge_tile(packet)
			if south_tile == Vector2i(-1, -1):
				continue
			var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
			var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE \
				+ south_tile + Vector2i(0, 4)
			print("mountain_variant_probe: mountain chunk %s tile %s" % [str(chunk_coord), str(south_tile)])
			return WorldRuntimeConstants.tile_to_world_center(world_tile) - home
	return Vector2.INF

func _mountain_solid_count(packet: Dictionary) -> int:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var count: int = 0
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			count += 1
	return count

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
