extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RasterLayer = preload("res://core/systems/world/mountain_plateau_2d_raster_layer.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")
const RUNTIME_PRESET_PATH: String = "res://scenes/dev/mountain_2d_raster_preset.json"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var core: Object = ClassDB.instantiate("WorldCore")
	_assert(core != null, "WorldCore must be available.")
	if core == null:
		_finish()
		return

	var settings_packed: PackedFloat32Array = _build_worldgen_settings_packed()
	var seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
	var spawn_result: Dictionary = core.call(
		"resolve_world_foundation_spawn_tile",
		seed,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	) as Dictionary
	_assert(bool(spawn_result.get("success", false)), "Spawn resolution must succeed.")
	var spawn_tile: Vector2i = spawn_result.get("spawn_tile", Vector2i.ZERO) as Vector2i
	var target_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn_tile)
	var packets: Array = []
	var mountain_packets: Array = []
	for radius: int in range(1, 18):
		var coords: PackedVector2Array = _build_chunk_ring(target_chunk, radius)
		print("runtime_mountain_raster_native_probe: scanning radius=%d coords=%d target=%s" % [
			radius,
			coords.size(),
			str(target_chunk),
		])
		packets = core.call(
			"generate_chunk_packets_batch",
			seed,
			coords,
			WorldRuntimeConstants.WORLD_VERSION,
			settings_packed
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			if not _packet_has_mountain(packet):
				continue
			mountain_packets.append(packet)
			target_chunk = packet.get("chunk_coord", target_chunk) as Vector2i
			break
		if not mountain_packets.is_empty():
			break
	print("runtime_mountain_raster_native_probe: packets=%d mountain_packets=%d found_target=%s" % [
		packets.size(),
		mountain_packets.size(),
		str(target_chunk),
	])
	_assert(not mountain_packets.is_empty(), "Probe must find at least one mountain packet near spawn.")
	if mountain_packets.is_empty():
		_finish()
		return

	var layer := RasterLayer.new()
	var source_images: Dictionary = layer.get_source_images()
	layer.free()
	var started: int = Time.get_ticks_msec()
	print("runtime_mountain_raster_native_probe: building native raster")
	var result: Dictionary = core.call(
		"build_mountain_plateau_raster_image",
		mountain_packets,
		target_chunk,
		_load_runtime_preset(),
		source_images.get("top_image", null) as Image,
		source_images.get("face_image", null) as Image
	) as Dictionary
	var elapsed_ms: int = Time.get_ticks_msec() - started
	print("runtime_mountain_raster_native_probe: elapsed_ms=%d result=%s" % [
		elapsed_ms,
		JSON.stringify(_compact_result(result)),
	])
	_assert(bool(result.get("ready", false)), "Native raster must return a ready image.")
	_assert(bool(result.get("runtime_mountain_only", false)), "Native probe must exercise runtime mountain-only payload.")
	_assert((result.get("hit_mask", PackedByteArray()) as PackedByteArray).size() > 0, "Native raster must return a hit mask.")
	_assert(int(result.get("hit_mask_solid_pixel_count", 0)) > 0, "Native raster hit mask must contain solid pixels.")
	_finish()

func _build_worldgen_settings_packed() -> PackedFloat32Array:
	var mountain_settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	var world_bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation_settings: FoundationGenSettings = FoundationGenSettings.for_bounds(world_bounds)
	var lake_settings: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, world_bounds)
	return lake_settings.write_to_settings_packed(packed)

func _build_chunk_ring(center_chunk: Vector2i, radius: int) -> PackedVector2Array:
	var coords: PackedVector2Array = PackedVector2Array()
	for chunk_y: int in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for chunk_x: int in range(center_chunk.x - radius, center_chunk.x + radius + 1):
			if maxi(absi(chunk_x - center_chunk.x), absi(chunk_y - center_chunk.y)) != radius:
				continue
			coords.append(Vector2(chunk_x, chunk_y))
	return coords

func _load_runtime_preset() -> Dictionary:
	var file: FileAccess = FileAccess.open(RUNTIME_PRESET_PATH, FileAccess.READ)
	_assert(file != null, "Runtime mountain raster preset must load.")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_assert(parsed is Dictionary, "Runtime mountain raster preset must be a Dictionary.")
	if parsed is not Dictionary:
		return {}
	var preset: Dictionary = parsed as Dictionary
	preset["runtime_mountain_only"] = true
	preset["hit_mask_threshold"] = float(preset.get("hit_mask_threshold", 0.14))
	return preset

func _packet_has_mountain(packet: Dictionary) -> bool:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT \
				and terrain_id != WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED:
			continue
		if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
			continue
		return true
	return false

func _compact_result(result: Dictionary) -> Dictionary:
	return {
		"ready": bool(result.get("ready", false)),
		"success": bool(result.get("success", false)),
		"message": str(result.get("message", "")),
		"packet_count": int(result.get("packet_count", 0)),
		"mountain_tile_count": int(result.get("mountain_tile_count", 0)),
		"image_width": int(result.get("image_width", 0)),
		"image_height": int(result.get("image_height", 0)),
		"top_pixel_count": int(result.get("top_pixel_count", 0)),
		"face_pixel_count": int(result.get("face_pixel_count", 0)),
		"rim_pixel_count": int(result.get("rim_pixel_count", 0)),
		"hit_mask_width": int(result.get("hit_mask_width", 0)),
		"hit_mask_height": int(result.get("hit_mask_height", 0)),
		"hit_mask_solid_pixel_count": int(result.get("hit_mask_solid_pixel_count", 0)),
		"runtime_mountain_only": bool(result.get("runtime_mountain_only", false)),
	}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true

func _finish() -> void:
	quit(1 if _failed else 0)
