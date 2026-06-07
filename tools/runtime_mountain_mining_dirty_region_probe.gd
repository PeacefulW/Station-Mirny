extends SceneTree

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
const SCAN_RADIUS: int = 16
const MAX_SETTLE_FRAMES: int = 360

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var core: Object = ClassDB.instantiate("WorldCore")
	_assert(core != null, "WorldCore native extension must be available.")
	if core == null:
		_finish()
		return
	var settings_packed: PackedFloat32Array = _settings_packed()
	var spawn: Dictionary = core.call(
		"resolve_world_foundation_spawn_tile",
		SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	) as Dictionary
	var center_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(
		spawn.get("spawn_tile", Vector2i.ZERO) as Vector2i
	)
	var target_tile: Vector2i = _find_dense_mountain_tile(core, settings_packed, center_chunk)

	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var streamer: Node = scene.get_node_or_null("WorldStreamer")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	_assert(streamer != null, "World scene must contain WorldStreamer.")
	_assert(player != null, "World scene must contain Player.")
	if streamer == null or player == null:
		_finish()
		return

	var settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	settings.density = DENSITY
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	streamer.initialize_new_world(SEED, settings, bounds, foundation, lakes)
	player.global_position = WorldRuntimeConstants.tile_to_world_center(target_tile)
	streamer._update_player_chunk_coord()

	var settled_debug: Dictionary = await _settle_streamer(streamer)
	_assert(
		int(settled_debug.get("native_mask_visual_upload_queue_count", 1)) == 0,
		"Native mask visual upload queue must be empty before mining probe."
	)
	_assert(
		int(settled_debug.get("native_mask_visual_pending_count", 1)) == 0,
		"Native mask visual pending count must be zero before mining probe."
	)
	var dig_pos: Vector2 = _find_center_dig_pos(streamer)
	_assert(is_finite(dig_pos.x), "Probe must find a center-solid dig position.")
	if not is_finite(dig_pos.x):
		_finish()
		return

	var dig_tile: Vector2i = WorldRuntimeConstants.world_to_tile(dig_pos)
	var dig_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(dig_tile)
	_assert(
		_chunk_foothill_mask_active(streamer, dig_chunk),
		"Probe chunk must have a captured mountain foothill footprint before mining."
	)
	var dirty_chunks: Array[Vector2i] = streamer._build_mountain_native_mask_dirty_chunks_for_tile(dig_tile)
	var before_debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
	var before_upload_total: int = int(before_debug.get("native_mask_visual_upload_count_total", 0))
	var harvest: Dictionary = streamer.try_harvest_at_world(dig_pos)
	var after_debug: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
	var after_upload_total: int = int(after_debug.get("native_mask_visual_upload_count_total", 0))

	_assert(bool(harvest.get("success", false)), "Mining must succeed through the native mask.")
	_assert(
		after_upload_total == before_upload_total,
		"Mining must not upload a native mask texture inside try_harvest_at_world."
	)
	_assert(
		int(after_debug.get("native_mask_visual_upload_queue_count", 0)) == 0,
		"Mining must not queue a visual texture upload before native reconciliation completes."
	)
	_assert(
		int(after_debug.get("native_mask_visual_pending_count", 0)) == 0,
		"Local collision-only mining patch must not mark visible mask textures dirty."
	)
	_assert(
		streamer.is_walkable_at_world(dig_pos),
		"Local collision-only mining patch must open the mined mask point immediately."
	)
	_assert(
		_chunk_foothill_mask_active(streamer, dig_chunk),
		"Local mining must preserve the captured mountain foothill footprint."
	)
	_assert(
		dirty_chunks.size() <= 9,
		"Mining dirty chunk set must stay bounded to owner plus fixed halo neighbours."
	)
	var refreshed_chunks: Array = after_debug.get("native_mask_last_refreshed_chunks", []) as Array
	_assert(
		refreshed_chunks.size() == dirty_chunks.size(),
		"Mining must refresh exactly the bounded native-mask dirty chunks."
	)

	var final_debug: Dictionary = await _settle_streamer(streamer)
	_assert(
		int(final_debug.get("native_mask_visual_upload_queue_count", 0)) == 0,
		"Native mask visual upload queue must drain after mining reconciliation."
	)
	_assert(
		int(final_debug.get("native_mask_visual_pending_count", 0)) == 0,
		"Native mask visual pending count must drain after mining reconciliation."
	)
	_assert(
		_chunk_foothill_mask_active(streamer, dig_chunk),
		"Native mining reconciliation must preserve the captured mountain foothill footprint."
	)
	print("runtime_mountain_mining_dirty_region_probe: dig_tile=%s dirty_chunks=%d upload_total_delta=%d final=%s" % [
		str(dig_tile),
		dirty_chunks.size(),
		after_upload_total - before_upload_total,
		JSON.stringify(_compact_debug(final_debug)),
	])
	scene.queue_free()
	await process_frame
	_finish()

func _settle_streamer(streamer: Node) -> Dictionary:
	var last_debug: Dictionary = {}
	for _frame: int in range(MAX_SETTLE_FRAMES):
		streamer._streaming_tick()
		streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		last_debug = streamer.get_mountain_mask_runtime_debug_state()
		if streamer._requested_chunks.is_empty() \
				and int(last_debug.get("native_mask_inflight_count", 0)) == 0 \
				and int(last_debug.get("native_mask_visual_upload_queue_count", 0)) == 0 \
				and int(last_debug.get("native_mask_visual_pending_count", 0)) == 0 \
				and not streamer._has_pending_streaming_work():
			return last_debug
	_assert(false, "World streamer did not settle inside probe frame budget: %s" % JSON.stringify(_compact_debug(last_debug)))
	return last_debug

func _find_center_dig_pos(streamer: Node) -> Vector2:
	for packet_variant: Variant in streamer._chunk_packets.values():
		var packet: Dictionary = packet_variant as Dictionary
		var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
		for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
			var terrain_id: int = int(terrain_ids[index])
			if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
					and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
				continue
			if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
				continue
			var local_coord := Vector2i(index % WorldRuntimeConstants.CHUNK_SIZE, index / WorldRuntimeConstants.CHUNK_SIZE)
			var world_tile: Vector2i = streamer._chunk_local_to_tile(chunk_coord, local_coord)
			var world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(world_tile)
			var hit_sample: Dictionary = streamer._sample_mountain_raster_hit(world_pos)
			if not bool(hit_sample.get("ready", false)) \
					or not bool(hit_sample.get("in_bounds", false)) \
					or not bool(hit_sample.get("solid", false)):
				continue
			if streamer.has_resource_at_world(world_pos):
				return world_pos
	return Vector2(INF, INF)

func _find_dense_mountain_tile(core: Object, settings: PackedFloat32Array, center: Vector2i) -> Vector2i:
	var best: Vector2i = center * WorldRuntimeConstants.CHUNK_SIZE
	var best_solids: int = -1
	for radius: int in range(0, SCAN_RADIUS + 1):
		var coords := PackedVector2Array()
		for cy: int in range(center.y - radius, center.y + radius + 1):
			for cx: int in range(center.x - radius, center.x + radius + 1):
				if maxi(absi(cx - center.x), absi(cy - center.y)) == radius:
					coords.append(Vector2(cx, cy))
		if coords.is_empty():
			continue
		var packets: Array = core.call(
			"generate_chunk_packets_batch",
			SEED,
			coords,
			WorldRuntimeConstants.WORLD_VERSION,
			settings
		) as Array
		for packet_variant: Variant in packets:
			var packet: Dictionary = packet_variant as Dictionary
			var solids: int = _count_solids(packet)
			if solids > best_solids:
				best_solids = solids
				best = (packet.get("chunk_coord", Vector2i.ZERO) as Vector2i) \
					* WorldRuntimeConstants.CHUNK_SIZE \
					+ Vector2i(8, 8)
		if best_solids >= 150:
			break
	return best

func _count_solids(packet: Dictionary) -> int:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var count: int = 0
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var terrain_id: int = int(terrain_ids[index])
		if terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				and terrain_id != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			continue
		if index < walkable_flags.size() and int(walkable_flags[index]) != 0:
			continue
		count += 1
	return count

func _settings_packed() -> PackedFloat32Array:
	var settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	settings.density = DENSITY
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	var packed: PackedFloat32Array = settings.flatten_to_packed()
	packed = foundation.write_to_settings_packed(packed, bounds)
	return lakes.write_to_settings_packed(packed)

func _compact_debug(debug: Dictionary) -> Dictionary:
	return {
		"ready_native_mask_chunk_count": int(debug.get("ready_native_mask_chunk_count", 0)),
		"native_mask_inflight_count": int(debug.get("native_mask_inflight_count", 0)),
		"native_mask_visual_pending_count": int(debug.get("native_mask_visual_pending_count", 0)),
		"native_mask_visual_upload_queue_count": int(debug.get("native_mask_visual_upload_queue_count", 0)),
		"native_mask_visual_upload_count_total": int(debug.get("native_mask_visual_upload_count_total", 0)),
		"native_mask_last_reason": str(debug.get("native_mask_last_reason", "")),
	}

func _chunk_foothill_mask_active(streamer: Node, chunk_coord: Vector2i) -> bool:
	var chunk_views: Dictionary = streamer._chunk_views
	var chunk_view = chunk_views.get(chunk_coord, null)
	if chunk_view == null:
		return false
	var debug: Dictionary = chunk_view.get_mountain_native_mask_debug_state()
	return bool(debug.get("foothill_mask_active", false))

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true

func _finish() -> void:
	quit(1 if _failed else 0)
