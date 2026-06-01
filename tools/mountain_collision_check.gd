extends Node

# Direct check of the MOVEMENT collision query for the visible native-mask area:
# every SOLID mountain mask pixel (mask>107) and south facade-band pixel inside
# the owning chunk must report is_walkable_at_world() == false; truly open pixels
# in that same visible area must be walkable. Halo pixels are sampled by the shader
# for continuity, but clipped from rendering, so they are not part of the visible
# collision contract.

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
const SOLID_THRESHOLD: int = 107
const FACADE_COLLISION_DEPTH_PX: float = 12.0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("mountain_collision_check: start")
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
	var settings: MountainGenSettings = MountainGenSettings.hard_coded_defaults()
	settings.density = DENSITY
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	var foundation: FoundationGenSettings = FoundationGenSettings.for_bounds(bounds)
	var lakes: LakeGenSettings = LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict())
	lakes.density = LAKE_DENSITY
	streamer.initialize_new_world(SEED, settings, bounds, foundation, lakes)
	player.global_position = WorldRuntimeConstants.tile_to_world_center(target_tile)
	streamer._update_player_chunk_coord()
	for _f: int in range(240):
		streamer._streaming_tick()
		if streamer.has_method("_mountain_native_mask_visual_apply_tick"):
			streamer._mountain_native_mask_visual_apply_tick()
		await get_tree().process_frame
		var d: Dictionary = streamer.get_mountain_mask_runtime_debug_state()
		if streamer._requested_chunks.is_empty() and int(d.get("native_mask_inflight_count", 0)) == 0 \
				and int(d.get("ready_native_mask_chunk_count", 0)) > 0 and not streamer._has_pending_streaming_work():
			break

	var solid_blocked: int = 0
	var solid_walkable_BUG: int = 0
	var open_walkable: int = 0
	var open_blocked: int = 0
	var facade_blocked: int = 0
	var facade_walkable_BUG: int = 0
	var checked: int = 0
	var skipped_halo: int = 0
	var solid_mismatch_examples: Array[String] = []
	var facade_mismatch_examples: Array[String] = []
	var open_mismatch_examples: Array[String] = []
	for key: Variant in streamer._chunk_views.keys():
		var mask_chunk: Vector2i = key as Vector2i
		var cv = streamer._chunk_views[key]
		if cv == null:
			continue
		var bytes: PackedByteArray = cv._mountain_top_mask_bytes
		var w: int = cv._mountain_top_mask_width
		var h: int = cv._mountain_top_mask_height
		var step: float = cv._mountain_top_mask_step_px
		var origin: Vector2 = cv._mountain_top_mask_origin_world
		if bytes.is_empty() or w <= 0 or h <= 0 or step <= 0.0:
			continue
		for my: int in range(0, h, 2):
			for mx: int in range(0, w, 2):
				var here: int = int(bytes[my * w + mx])
				var wpos: Vector2 = origin + Vector2(float(mx) + 0.5, float(my) + 0.5) * step
				var walkable: bool = bool(streamer.is_walkable_at_world(wpos))
				var owner_chunk: Vector2i = streamer._canonicalize_chunk_coord(
					WorldRuntimeConstants.tile_to_chunk(WorldRuntimeConstants.world_to_tile(wpos))
				)
				if owner_chunk != mask_chunk:
					skipped_halo += 1
					continue
				checked += 1
				var facade: bool = here <= SOLID_THRESHOLD and _is_facade_band_pixel(bytes, w, h, step, mx, my)
				if here > SOLID_THRESHOLD:
					if walkable:
						solid_walkable_BUG += 1
						if solid_mismatch_examples.size() < 8:
							solid_mismatch_examples.append("solid_walkable mask_chunk=%s owner_chunk=%s mask=(%d,%d) world=(%.1f,%.1f)" % [
								str(key),
								str(owner_chunk),
								mx,
								my,
								wpos.x,
								wpos.y,
							])
					else:
						solid_blocked += 1
				elif facade:
					if walkable:
						facade_walkable_BUG += 1
						if facade_mismatch_examples.size() < 8:
							facade_mismatch_examples.append("facade_walkable mask_chunk=%s owner_chunk=%s mask=(%d,%d) world=(%.1f,%.1f)" % [
								str(key),
								str(owner_chunk),
								mx,
								my,
								wpos.x,
								wpos.y,
							])
					else:
						facade_blocked += 1
				else:
					if walkable:
						open_walkable += 1
					else:
						open_blocked += 1
						if open_mismatch_examples.size() < 8:
							open_mismatch_examples.append("open_blocked mask_chunk=%s owner_chunk=%s mask=(%d,%d) world=(%.1f,%.1f)" % [
								str(key),
								str(owner_chunk),
								mx,
								my,
								wpos.x,
								wpos.y,
							])
		if checked > 200000:
			break

	print("mountain_collision_check: checked=%d" % checked)
	print("mountain_collision_check: skipped_halo=%d" % skipped_halo)
	print("  SOLID (mask>%d): blocked=%d  WALKABLE(bug)=%d" % [SOLID_THRESHOLD, solid_blocked, solid_walkable_BUG])
	print("  facade-band:      blocked=%d  WALKABLE(bug)=%d" % [facade_blocked, facade_walkable_BUG])
	print("  open  (mask<=%d): walkable=%d  blocked=%d" % [SOLID_THRESHOLD, open_walkable, open_blocked])
	for example: String in solid_mismatch_examples:
		print("  mismatch: %s" % example)
	for example: String in facade_mismatch_examples:
		print("  mismatch: %s" % example)
	for example: String in open_mismatch_examples:
		print("  mismatch: %s" % example)
	var ok: bool = solid_blocked > 0 \
		and facade_blocked > 0 \
		and solid_walkable_BUG == 0 \
		and facade_walkable_BUG == 0 \
		and open_blocked == 0
	print("mountain_collision_check: COLLISION %s" % ("WORKS (visible mask matches walkability)" if ok else "BROKEN (visible mask/walkability mismatch)"))
	print("mountain_collision_check: %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _is_facade_band_pixel(bytes: PackedByteArray, width: int, height: int, step_px: float, x: int, y: int) -> bool:
	if bytes.is_empty() or width <= 0 or height <= 0 or step_px <= 0.0:
		return false
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	var facade_texels: int = maxi(1, ceili(FACADE_COLLISION_DEPTH_PX / step_px))
	for distance: int in range(1, facade_texels + 1):
		var north_y: int = y - distance
		if north_y < 0:
			return false
		var north_index: int = north_y * width + x
		if north_index >= 0 and north_index < bytes.size() and int(bytes[north_index]) > SOLID_THRESHOLD:
			return true
	return false

func _find_dense_mountain_tile(core: Object, settings: PackedFloat32Array, center: Vector2i) -> Vector2i:
	var best: Vector2i = center * WorldRuntimeConstants.CHUNK_SIZE + Vector2i(8, 8)
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
	var c: int = 0
	for i: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var t: int = int(terrain_ids[i])
		if (t == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL or t == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT) \
				and (i >= walkable_flags.size() or int(walkable_flags[i]) == 0) \
				and i < mountain_ids.size() and int(mountain_ids[i]) > 0:
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
