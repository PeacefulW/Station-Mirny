extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HALO_RADIUS_TILES: int = 8
const PIXELS_PER_TILE: int = 8
const EPOCH: int = 31
const OWNER_CHUNK: Vector2i = Vector2i(4, 4)
const EAST_CHUNK: Vector2i = Vector2i(5, 4)

var _failed: bool = false
var _streamer_script: Script = null
var _world_core: Object = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# WorldStreamer references project autoloads, which become compile-visible
	# after this standalone SceneTree script reaches its first frame.
	await process_frame
	_streamer_script = load("res://core/systems/world/world_streamer.gd") as Script
	_world_core = ClassDB.instantiate("WorldCore")
	_assert(_streamer_script != null, "WorldStreamer script must load after project autoloads are ready.")
	_assert(_world_core != null, "WorldCore is required for native mountain collision verification.")
	if _failed:
		quit(1)
		return

	_assert_missing_mask_uses_logical_collision()
	_assert_native_mask_splits_organic_collision_from_logical_tiles()
	_assert_stale_mask_cannot_replace_current_collision()
	_assert_seam_sampling_prefers_owner_chunk()

	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_collision_smoke_test: PASS")
	quit(0)


func _assert_missing_mask_uses_logical_collision() -> void:
	var solid_world_tiles: Dictionary = { _world_tile(OWNER_CHUNK, Vector2i(8, 8)): true }
	var streamer: Node = _new_streamer()
	streamer._chunk_packets[OWNER_CHUNK] = _build_packet(OWNER_CHUNK, solid_world_tiles)
	var mountain_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(
		_world_tile(OWNER_CHUNK, Vector2i(8, 8)),
	)
	var ground_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(
		_world_tile(OWNER_CHUNK, Vector2i(2, 2)),
	)
	_assert(
		not streamer.is_walkable_at_world(mountain_pos),
		"A loaded logical mountain tile must remain fail-closed before its native mask is ready.",
	)
	_assert(
		streamer.is_walkable_at_world(ground_pos),
		"Missing mountain presentation data must not block an ordinary loaded ground tile.",
	)
	streamer.free()


func _assert_native_mask_splits_organic_collision_from_logical_tiles() -> void:
	var solid_world_tiles: Dictionary = _build_organic_block_tiles()
	var streamer: Node = _new_streamer()
	streamer._chunk_packets[OWNER_CHUNK] = _build_packet(OWNER_CHUNK, solid_world_tiles)
	var chunk_view: ChunkView = _attach_chunk_view(streamer, OWNER_CHUNK)
	var result: Dictionary = _build_native_mask_result(
		OWNER_CHUNK,
		solid_world_tiles,
		streamer._get_mountain_mask_revision(OWNER_CHUNK),
		&"collision_shape",
	)
	_accept_current_result(streamer, result)

	var samples: Dictionary = _find_open_and_solid_mountain_samples(chunk_view, solid_world_tiles)
	var open_pos: Vector2 = samples.get("open", Vector2.INF) as Vector2
	var solid_pos: Vector2 = samples.get("solid", Vector2.INF) as Vector2
	_assert(open_pos != Vector2.INF, "Native organic mask must round at least one logical mountain pixel open.")
	_assert(solid_pos != Vector2.INF, "Native organic mask must retain solid collision inside the mountain mass.")
	if open_pos != Vector2.INF:
		_assert(
			_is_logical_mountain_at(streamer, open_pos),
			"Rounded-open sample must still belong to a logical mountain tile.",
		)
		_assert(
			streamer.is_walkable_at_world(open_pos),
			"Movement must pass through a logical mountain corner opened by the native mask.",
		)
	if solid_pos != Vector2.INF:
		_assert(
			_is_logical_mountain_at(streamer, solid_pos),
			"Solid native sample must belong to the same logical mountain terrain family.",
		)
		_assert(
			not streamer.is_walkable_at_world(solid_pos),
			"Movement must remain blocked at solid native mountain occupancy.",
		)
	streamer.free()


func _assert_stale_mask_cannot_replace_current_collision() -> void:
	var solid_world_tiles: Dictionary = _build_organic_block_tiles()
	var streamer: Node = _new_streamer()
	streamer._chunk_packets[OWNER_CHUNK] = _build_packet(OWNER_CHUNK, solid_world_tiles)
	var chunk_view: ChunkView = _attach_chunk_view(streamer, OWNER_CHUNK)
	var current_result: Dictionary = _build_native_mask_result(
		OWNER_CHUNK,
		solid_world_tiles,
		0,
		&"current",
	)
	_accept_current_result(streamer, current_result)
	var samples: Dictionary = _find_open_and_solid_mountain_samples(chunk_view, solid_world_tiles)
	var solid_pos: Vector2 = samples.get("solid", Vector2.INF) as Vector2
	_assert(solid_pos != Vector2.INF, "Stale-result proof requires a current solid collision sample.")

	streamer._forget_mountain_mask(OWNER_CHUNK, false, true)
	var current_revision: int = streamer._get_mountain_mask_revision(OWNER_CHUNK)
	streamer._mountain_native_mask_inflight_chunks[OWNER_CHUNK] = {
		"revision": current_revision,
		"reason": &"rebuild",
	}
	var stale_open_result: Dictionary = _build_constant_mask_result(
		OWNER_CHUNK,
		0,
		0,
		&"stale",
	)
	streamer._handle_completed_mountain_native_mask(stale_open_result)

	_assert(
		streamer._get_ready_mountain_native_mask_result(OWNER_CHUNK).is_empty(),
		"A stale mask must not re-enter the current ready cache.",
	)
	_assert(
		int((streamer._mountain_native_mask_inflight_chunks.get(OWNER_CHUNK, { }) as Dictionary).get("revision", -1))
				== current_revision,
		"A stale result must not clear the newer in-flight collision revision.",
	)
	if solid_pos != Vector2.INF:
		var sample_after_stale: Dictionary = chunk_view.sample_mountain_page_hit_at_world(solid_pos)
		_assert(
			bool(sample_after_stale.get("ready", false))
					and bool(sample_after_stale.get("solid", false)),
			"A stale all-open result must not overwrite the currently published solid collision bytes.",
		)
		_assert(
			not streamer.is_walkable_at_world(solid_pos),
			"Rejected stale collision data must not make the mountain walkable.",
		)
	streamer.free()


func _assert_seam_sampling_prefers_owner_chunk() -> void:
	var streamer: Node = _new_streamer()
	streamer._chunk_packets[OWNER_CHUNK] = _build_packet(OWNER_CHUNK, { })
	streamer._chunk_packets[EAST_CHUNK] = _build_packet(EAST_CHUNK, { })
	_attach_chunk_view(streamer, OWNER_CHUNK)
	_attach_chunk_view(streamer, EAST_CHUNK)
	_accept_current_result(
		streamer,
		_build_constant_mask_result(OWNER_CHUNK, 255, 0, &"west_solid"),
	)
	_accept_current_result(
		streamer,
		_build_constant_mask_result(EAST_CHUNK, 0, 0, &"east_open"),
	)

	var seam_x: float = float(EAST_CHUNK.x * WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
	var sample_y: float = float(
		(OWNER_CHUNK.y * WorldRuntimeConstants.CHUNK_SIZE + 8) * WorldRuntimeConstants.TILE_SIZE_PX,
	) + 32.0
	var west_owner_pos := Vector2(seam_x - 32.0, sample_y)
	var east_owner_pos := Vector2(seam_x + 32.0, sample_y)
	var west_sample: Dictionary = streamer._sample_mountain_mask_hit(west_owner_pos)
	var east_sample: Dictionary = streamer._sample_mountain_mask_hit(east_owner_pos)
	_assert(
		(west_sample.get("chunk_coord", Vector2i(-1, -1)) as Vector2i) == OWNER_CHUNK
				and bool(west_sample.get("solid", false)),
		"The west owner must supply collision immediately before the seam.",
	)
	_assert(
		(east_sample.get("chunk_coord", Vector2i(-1, -1)) as Vector2i) == EAST_CHUNK
				and not bool(east_sample.get("solid", true)),
		"The east owner must win immediately after the seam even when west overlap is solid.",
	)
	_assert(
		not streamer.is_walkable_at_world(west_owner_pos),
		"Solid west owner mask must block movement before the seam.",
	)
	_assert(
		streamer.is_walkable_at_world(east_owner_pos),
		"Open east owner mask must allow movement after the seam.",
	)
	streamer.free()


func _new_streamer() -> Node:
	var streamer: Node = _streamer_script.new() as Node
	streamer._generation_epoch = EPOCH
	return streamer


func _attach_chunk_view(streamer: Node, chunk_coord: Vector2i) -> ChunkView:
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	streamer.add_child(chunk_view)
	streamer._chunk_views[chunk_coord] = chunk_view
	return chunk_view


func _accept_current_result(streamer: Node, result: Dictionary) -> void:
	var chunk_coord: Vector2i = result.get("target_chunk", Vector2i(-1, -1)) as Vector2i
	var revision: int = int(result.get("revision", -1))
	_assert(bool(result.get("success", false)), "Synthetic/native collision result must be structurally valid.")
	streamer._mountain_native_mask_inflight_chunks[chunk_coord] = {
		"revision": revision,
		"reason": result.get("reason", &"collision_smoke") as StringName,
	}
	streamer._handle_completed_mountain_native_mask(result)
	_assert(
		int(streamer._get_ready_mountain_native_mask_result(chunk_coord).get("revision", -1)) == revision,
		"Current collision mask revision must enter the ready cache.",
	)


func _build_native_mask_result(
		chunk_coord: Vector2i,
		solid_world_tiles: Dictionary,
		revision: int,
		reason: StringName,
) -> Dictionary:
	var halo: PackedByteArray = _build_halo(chunk_coord, solid_world_tiles)
	var origin_world: Vector2 = _mask_origin_world(chunk_coord)
	var result_variant: Variant = _world_core.call(
		"build_mountain_halo_mask",
		halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		PIXELS_PER_TILE,
		origin_world.x,
		origin_world.y,
	)
	var result: Dictionary = result_variant as Dictionary if result_variant is Dictionary else { }
	_complete_result_metadata(result, chunk_coord, revision, reason, origin_world)
	return result


func _build_constant_mask_result(
		chunk_coord: Vector2i,
		fill_value: int,
		revision: int,
		reason: StringName,
) -> Dictionary:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + HALO_RADIUS_TILES * 2
	var side_px: int = halo_side * PIXELS_PER_TILE
	var mask := PackedByteArray()
	mask.resize(side_px * side_px)
	mask.fill(clampi(fill_value, 0, 255))
	var result: Dictionary = {
		"mask": mask,
		"width": side_px,
		"height": side_px,
		"step_px": float(WorldRuntimeConstants.TILE_SIZE_PX) / float(PIXELS_PER_TILE),
		"pixels_per_tile": PIXELS_PER_TILE,
		"halo_side": halo_side,
		"halo_radius_tiles": HALO_RADIUS_TILES,
		"solid_sample_count": 0,
	}
	_complete_result_metadata(result, chunk_coord, revision, reason, _mask_origin_world(chunk_coord))
	return result


func _complete_result_metadata(
		result: Dictionary,
		chunk_coord: Vector2i,
		revision: int,
		reason: StringName,
		origin_world: Vector2,
) -> void:
	var mask: PackedByteArray = result.get("mask", PackedByteArray()) as PackedByteArray
	var width: int = int(result.get("width", 0))
	var height: int = int(result.get("height", 0))
	result["success"] = width > 0 and height > 0 and mask.size() == width * height
	result["epoch"] = EPOCH
	result["revision"] = revision
	result["reason"] = reason
	result["mask_purpose"] = &"mountain"
	result["target_chunk"] = chunk_coord
	result["mask_origin_world"] = origin_world


func _find_open_and_solid_mountain_samples(
		chunk_view: ChunkView,
		solid_world_tiles: Dictionary,
) -> Dictionary:
	var found: Dictionary = { }
	var sample_step_px: float = float(WorldRuntimeConstants.TILE_SIZE_PX) / float(PIXELS_PER_TILE)
	for tile_variant: Variant in solid_world_tiles.keys():
		var world_tile: Vector2i = tile_variant as Vector2i
		if WorldRuntimeConstants.tile_to_chunk(world_tile) != OWNER_CHUNK:
			continue
		var tile_origin := Vector2(
			float(world_tile.x * WorldRuntimeConstants.TILE_SIZE_PX),
			float(world_tile.y * WorldRuntimeConstants.TILE_SIZE_PX),
		)
		for sample_y: int in range(PIXELS_PER_TILE):
			for sample_x: int in range(PIXELS_PER_TILE):
				var world_pos: Vector2 = tile_origin + Vector2(
					(float(sample_x) + 0.5) * sample_step_px,
					(float(sample_y) + 0.5) * sample_step_px,
				)
				var sample: Dictionary = chunk_view.sample_mountain_page_hit_at_world(world_pos)
				if not bool(sample.get("ready", false)) or not bool(sample.get("in_bounds", false)):
					continue
				if bool(sample.get("solid", false)):
					if not found.has("solid"):
						found["solid"] = world_pos
				elif not found.has("open"):
					found["open"] = world_pos
				if found.has("solid") and found.has("open"):
					return found
	return found


func _is_logical_mountain_at(streamer: Node, world_pos: Vector2) -> bool:
	var world_tile: Vector2i = WorldRuntimeConstants.world_to_tile(world_pos)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(world_tile)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(world_tile)
	var packet: Dictionary = streamer._chunk_packets.get(chunk_coord, { }) as Dictionary
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index < 0 or index >= terrain_ids.size():
		return false
	var terrain_id: int = int(terrain_ids[index])
	return terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT


func _build_packet(chunk_coord: Vector2i, solid_world_tiles: Dictionary) -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var terrain_atlas_indices := PackedInt32Array()
	var walkable_flags := PackedByteArray()
	var lake_flags := PackedByteArray()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	var mountain_atlas_indices := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		var world_tile: Vector2i = _world_tile(chunk_coord, local_coord)
		if solid_world_tiles.has(world_tile):
			terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
			walkable_flags[index] = 0
			mountain_ids[index] = 1
			mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
		else:
			terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
			walkable_flags[index] = 1
	return {
		"chunk_coord": chunk_coord,
		"world_seed": WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		"world_version": WorldRuntimeConstants.WORLD_VERSION,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}


func _build_organic_block_tiles() -> Dictionary:
	var solid_world_tiles: Dictionary = { }
	for local_y: int in range(4, 11):
		for local_x: int in range(4, 11):
			solid_world_tiles[_world_tile(OWNER_CHUNK, Vector2i(local_x, local_y))] = true
	return solid_world_tiles


func _build_halo(chunk_coord: Vector2i, solid_world_tiles: Dictionary) -> PackedByteArray:
	var halo_side: int = WorldRuntimeConstants.CHUNK_SIZE + HALO_RADIUS_TILES * 2
	var halo := PackedByteArray()
	halo.resize(halo_side * halo_side)
	var origin_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE \
			- Vector2i.ONE * HALO_RADIUS_TILES
	for y: int in range(halo_side):
		for x: int in range(halo_side):
			if solid_world_tiles.has(origin_tile + Vector2i(x, y)):
				halo[y * halo_side + x] = 1
	return halo


func _mask_origin_world(chunk_coord: Vector2i) -> Vector2:
	return WorldRuntimeConstants.chunk_origin_px(chunk_coord) \
			- Vector2.ONE * float(HALO_RADIUS_TILES * WorldRuntimeConstants.TILE_SIZE_PX)


func _world_tile(chunk_coord: Vector2i, local_coord: Vector2i) -> Vector2i:
	return chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
