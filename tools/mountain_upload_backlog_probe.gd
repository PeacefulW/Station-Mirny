extends Node

# Runtime evidence for the "staggered visual upload" seam cause: mask TEXTURE uploads
# are limited to 1 chunk/frame (_mountain_native_mask_visual_apply_tick), so when many
# mountain chunks become ready at once (streaming a ring, or a dig dirtying several),
# their sprites update one-per-frame -> for several frames adjacent chunks show
# new-vs-old/blank masks -> a hard chunk-boundary seam. Headless (reads debug metrics).

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
const MAX_FRAMES: int = 240

var _failed: bool = false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("mountain_upload_backlog_probe: start")
	var core: Object = ClassDB.instantiate("WorldCore")
	var settings_packed: PackedFloat32Array = _settings_packed()
	var spawn: Dictionary = core.call("resolve_world_foundation_spawn_tile", SEED, WorldRuntimeConstants.WORLD_VERSION, settings_packed) as Dictionary
	var center: Vector2i = WorldRuntimeConstants.tile_to_chunk(spawn.get("spawn_tile", Vector2i.ZERO) as Vector2i)
	var target_tile: Vector2i = _find_dense_mountain_tile(core, settings_packed, center)

	var scene: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var streamer = scene.get_node_or_null("WorldStreamer")
	var player: Node2D = scene.get_node_or_null("Player") as Node2D
	if streamer == null or player == null:
		push_error("world scene missing WorldStreamer/Player"); _finish(); return

	var settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	settings.density = DENSITY
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	streamer.initialize_new_world(SEED, settings, bounds, foundation, lakes)
	player.global_position = WorldRuntimeConstants.tile_to_world_center(target_tile)
	streamer._update_player_chunk_coord()

	# Stream the area in; log the per-frame upload queue depth vs applied-per-tick.
	var max_queue: int = 0
	var max_pending: int = 0
	var max_applied_per_tick: int = 0
	var frames_with_backlog: int = 0
	var samples: Array[String] = []
	for frame: int in range(MAX_FRAMES):
		streamer._streaming_tick()
		if streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			streamer._mountain_native_mask_visual_apply_tick()
		await get_tree().process_frame
		var d: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
		var q: int = int(d.get("native_mask_visual_upload_queue_count", 0))
		var applied: int = int(d.get("native_mask_visual_upload_count_last_tick", 0))
		var pending: int = int(d.get("native_mask_visual_pending_count", 0))
		var inflight: int = int(d.get("native_mask_inflight_count", 0))
		max_queue = maxi(max_queue, q)
		max_pending = maxi(max_pending, pending)
		max_applied_per_tick = maxi(max_applied_per_tick, applied)
		if q > 0:
			frames_with_backlog += 1
		if frame < 60 and (q > 0 or applied > 0 or inflight > 0):
			samples.append("f%d: queue=%d applied_this_tick=%d pending=%d inflight=%d ready=%d" % [
				frame, q, applied, pending, inflight, int(d.get("ready_native_mask_chunk_count", 0))])
		if _settled(streamer, d) and frame > 5:
			samples.append("f%d: SETTLED queue=0" % frame)
			break

	for s: String in samples:
		print("  " + s)
	print("mountain_upload_backlog_probe: max_upload_queue=%d  max_applied_per_tick=%d  max_pending=%d  frames_with_backlog=%d" % [
		max_queue, max_applied_per_tick, max_pending, frames_with_backlog])
	print("mountain_upload_backlog_probe: [STREAM] uploads applied per frame never exceeded %d; chunks appear one-by-one." % max_applied_per_tick)

	# Phase 2: dig a tile near a chunk border -> dirties several chunks at once.
	var dig_pos: Vector2 = _find_border_dig_pos(streamer)
	var dig_max_queue: int = 0
	if is_finite(dig_pos.x):
		var harvest: Dictionary = streamer.try_harvest_at_world(dig_pos)
		var dig_lines: Array[String] = []
		for frame: int in range(40):
			streamer._streaming_tick()
			if streamer.has_method("_mountain_native_mask_visual_apply_tick"):
				streamer._mountain_native_mask_visual_apply_tick()
			await get_tree().process_frame
			var dd: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
			var q: int = int(dd.get("native_mask_visual_upload_queue_count", 0))
			var ap: int = int(dd.get("native_mask_visual_upload_count_last_tick", 0))
			var infl: int = int(dd.get("native_mask_inflight_count", 0))
			dig_max_queue = maxi(dig_max_queue, q)
			if q > 0 or ap > 0 or infl > 0:
				dig_lines.append("dig f%d: upload_queue=%d applied_this_tick=%d rebuilds_inflight=%d" % [frame, q, ap, infl])
			if q == 0 and infl == 0 and frame > 2:
				break
		print("mountain_upload_backlog_probe: dig tile=%s success=%s" % [
			str(WorldRuntimeConstants.world_to_tile(dig_pos)), str(harvest.get("success", false))])
		for l: String in dig_lines:
			print("  " + l)
	else:
		print("mountain_upload_backlog_probe: no diggable border tile found")

	var confirmed: bool = (max_queue > 1 or dig_max_queue > 1) and max_applied_per_tick <= 1
	print("mountain_upload_backlog_probe: STAGGERED-UPLOAD %s — uploads capped at %d/frame; queue peaked at %d (stream) / %d (dig). While draining, neighbouring chunks show new-vs-old/blank masks = transient boundary seam." % [
		"CONFIRMED" if confirmed else "not observed", max_applied_per_tick, max_queue, dig_max_queue])
	print("mountain_upload_backlog_probe: OK")
	_finish()

func _find_border_dig_pos(streamer) -> Vector2:
	for key: Variant in streamer._chunk_packets.keys():
		var chunk: Vector2i = key as Vector2i
		var packet: Dictionary = streamer._chunk_packets[chunk] as Dictionary
		var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
		var walkable: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
		for ly: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			for lx: int in range(WorldRuntimeConstants.CHUNK_SIZE):
				if lx > 1 and lx < 14 and ly > 1 and ly < 14:
					continue
				var idx: int = ly * WorldRuntimeConstants.CHUNK_SIZE + lx
				if idx >= terrain_ids.size():
					continue
				var t: int = int(terrain_ids[idx])
				if t != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL and t != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
					continue
				if idx < walkable.size() and int(walkable[idx]) != 0:
					continue
				var wpos: Vector2 = WorldRuntimeConstants.tile_to_world_center(chunk * WorldRuntimeConstants.CHUNK_SIZE + Vector2i(lx, ly))
				if streamer.has_resource_at_world(wpos):
					return wpos
	return Vector2(INF, INF)

func _settled(streamer, d: Dictionary) -> bool:
	if not streamer._requested_chunks.is_empty():
		return false
	if int(d.get("native_mask_visual_upload_queue_count", 0)) > 0:
		return false
	if int(d.get("native_mask_inflight_count", 0)) > 0:
		return false
	if int(d.get("missing_mountain_chunk_count", 0)) > 0:
		return false
	return not streamer._has_pending_streaming_work()

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
		var packets: Array = core.call("generate_chunk_packets_batch", SEED, coords, WorldRuntimeConstants.WORLD_VERSION, settings) as Array
		for pv: Variant in packets:
			var p: Dictionary = pv as Dictionary
			var s: int = _solids(p)
			if s > best_solids:
				best_solids = s
				best = (p.get("chunk_coord", Vector2i.ZERO) as Vector2i) * WorldRuntimeConstants.CHUNK_SIZE + Vector2i(8, 8)
		if best_solids >= 150:
			break
	return best

func _solids(packet: Dictionary) -> int:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var c: int = 0
	for i: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var t: int = int(terrain_ids[i])
		if t != WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL and t != WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			continue
		if i < walkable_flags.size() and int(walkable_flags[i]) != 0:
			continue
		if i >= mountain_ids.size() or int(mountain_ids[i]) <= 0:
			continue
		if i < mountain_flags.size() and (int(mountain_flags[i]) & (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)) != 0:
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

func _finish() -> void:
	get_tree().quit(1 if _failed else 0)
