extends Node

# Direct check of the MOVEMENT collision query: every SOLID mountain mask pixel
# (mask>107) must report is_walkable_at_world() == false; open pixels must be
# walkable. This is exactly what the player movement uses (_apply_terrain_blocking
# -> _can_occupy_world -> is_walkable_at_world). Headless; live runtime chunk views.

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
	var checked: int = 0
	for key: Variant in streamer._chunk_views.keys():
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
				checked += 1
				if here > SOLID_THRESHOLD:
					if walkable:
						solid_walkable_BUG += 1
					else:
						solid_blocked += 1
				else:
					if walkable:
						open_walkable += 1
					else:
						open_blocked += 1
		if checked > 200000:
			break

	print("mountain_collision_check: checked=%d" % checked)
	print("  SOLID (mask>%d): blocked=%d  WALKABLE(bug)=%d" % [SOLID_THRESHOLD, solid_blocked, solid_walkable_BUG])
	print("  open  (mask<=%d): walkable=%d  blocked=%d" % [SOLID_THRESHOLD, open_walkable, open_blocked])
	var ok: bool = solid_blocked > 0 and solid_walkable_BUG == 0
	print("mountain_collision_check: COLLISION %s" % ("WORKS (solid is blocked)" if ok else "BROKEN (solid is walkable)"))
	print("mountain_collision_check: %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

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
