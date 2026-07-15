extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const HALO_RADIUS_TILES: int = 8
const PIXELS_PER_TILE: int = 8
const EPOCH: int = 23
const OWNER_CHUNK: Vector2i = Vector2i(5, 5)
const EAST_CHUNK: Vector2i = Vector2i(6, 5)
const SOUTH_CHUNK: Vector2i = Vector2i(5, 6)
const SOUTH_EAST_CHUNK: Vector2i = Vector2i(6, 6)

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Autoload singletons used by WorldStreamer are registered after this
	# SceneTree script is compiled, so load the runtime owner on the first frame.
	await process_frame
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	_assert(streamer_script != null, "WorldStreamer script must load after project autoloads are ready.")
	if streamer_script == null:
		quit(1)
		return
	var streamer: Node = streamer_script.new() as Node
	streamer._generation_epoch = EPOCH
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore is required for native halo-mask excavation verification.")
	if world_core == null:
		streamer.free()
		quit(1)
		return

	var solid_world_tiles: Dictionary = _build_edge_mountain_tiles()
	_load_halo_source_packets(streamer, solid_world_tiles)
	var owner_view: ChunkView = _attach_chunk_view(streamer, OWNER_CHUNK)
	var east_view: ChunkView = _attach_chunk_view(streamer, EAST_CHUNK)

	var owner_initial_result: Dictionary = _build_mask_result(
		streamer,
		world_core,
		OWNER_CHUNK,
		streamer._get_mountain_mask_revision(OWNER_CHUNK),
		&"initial",
	)
	var east_initial_result: Dictionary = _build_mask_result(
		streamer,
		world_core,
		EAST_CHUNK,
		streamer._get_mountain_mask_revision(EAST_CHUNK),
		&"initial",
	)
	_accept_worker_result(streamer, owner_initial_result)
	_accept_worker_result(streamer, east_initial_result)
	streamer._drop_mountain_native_mask_visual_upload(OWNER_CHUNK)
	streamer._drop_mountain_native_mask_visual_upload(EAST_CHUNK)

	var dug_tile := Vector2i(
		OWNER_CHUNK.x * WorldRuntimeConstants.CHUNK_SIZE + WorldRuntimeConstants.CHUNK_SIZE - 1,
		OWNER_CHUNK.y * WorldRuntimeConstants.CHUNK_SIZE + 8,
	)
	var dug_world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(dug_tile)
	_assert_initial_mountain_state(streamer, owner_view, east_view, dug_world_pos)

	var expected_dirty_chunks: Array[Vector2i] = [
		OWNER_CHUNK,
		EAST_CHUNK,
		SOUTH_CHUNK,
		SOUTH_EAST_CHUNK,
	]
	var actual_dirty_chunks: Array[Vector2i] = \
			streamer._build_mountain_native_mask_dirty_chunks_for_tile(dug_tile)
	_assert_same_coord_set(
		actual_dirty_chunks,
		expected_dirty_chunks,
		"A seam dig must invalidate only the owner plus halo-overlapping east/south neighbours.",
	)
	var revisions_before: Dictionary = { }
	for chunk_coord: Vector2i in expected_dirty_chunks:
		revisions_before[chunk_coord] = streamer._get_mountain_mask_revision(chunk_coord)

	var stale_owner_result: Dictionary = owner_initial_result.duplicate(true)
	var harvest_result: Dictionary = streamer.try_harvest_at_world(dug_world_pos)
	_assert(bool(harvest_result.get("success", false)), "Exposed seam mountain tile must be harvestable.")
	_assert(
		(harvest_result.get("chunk_coord", Vector2i(-1, -1)) as Vector2i) == OWNER_CHUNK,
		"Mask mining must resolve back to the authoritative owner chunk.",
	)
	_assert(
		(harvest_result.get("local_coord", Vector2i(-1, -1)) as Vector2i)
				== WorldRuntimeConstants.tile_to_local(dug_tile),
		"Mask mining must mutate the exact exposed authoritative tile.",
	)
	_assert_post_dig_state(
		streamer,
		owner_view,
		east_view,
		dug_tile,
		dug_world_pos,
		expected_dirty_chunks,
		revisions_before,
	)

	var current_owner_revision: int = streamer._get_mountain_mask_revision(OWNER_CHUNK)
	streamer._handle_completed_mountain_native_mask(stale_owner_result)
	_assert(
		int((streamer._mountain_native_mask_inflight_chunks.get(OWNER_CHUNK, { }) as Dictionary).get("revision", -1))
				== current_owner_revision,
		"A stale worker result must not clear the newer in-flight revision.",
	)
	_assert(
		streamer._get_ready_mountain_native_mask_result(OWNER_CHUNK).is_empty(),
		"A stale pre-dig mask must not re-enter the ready cache.",
	)
	_assert(
		streamer.is_walkable_at_world(dug_world_pos),
		"A stale pre-dig result must not restore collision over the mined opening.",
	)

	var reconciled_owner_result: Dictionary = _build_mask_result(
		streamer,
		world_core,
		OWNER_CHUNK,
		current_owner_revision,
		&"mining",
	)
	streamer._handle_completed_mountain_native_mask(reconciled_owner_result)
	_assert_reconciled_state(streamer, owner_view, dug_world_pos, current_owner_revision)

	streamer.free()
	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_excavation_smoke_test: PASS")
	quit(0)


func _assert_initial_mountain_state(
		streamer: Node,
		owner_view: ChunkView,
		east_view: ChunkView,
		world_pos: Vector2,
) -> void:
	var owner_sample: Dictionary = owner_view.sample_mountain_page_hit_at_world(world_pos)
	var east_sample: Dictionary = east_view.sample_mountain_page_hit_at_world(world_pos)
	_assert(
		bool(owner_sample.get("ready", false)) and bool(owner_sample.get("in_bounds", false))
				and bool(owner_sample.get("solid", false)),
		"Owner native halo mask must block the exposed mountain tile before mining.",
	)
	_assert(
		bool(east_sample.get("ready", false)) and bool(east_sample.get("in_bounds", false))
				and bool(east_sample.get("solid", false)),
		"East neighbour halo must agree on the solid cross-chunk sample before mining.",
	)
	_assert(not streamer.is_walkable_at_world(world_pos), "Solid native mountain mask must block movement.")
	_assert(streamer.has_resource_at_world(world_pos), "Exposed solid mountain mask must resolve a resource tile.")


func _assert_post_dig_state(
		streamer: Node,
		owner_view: ChunkView,
		east_view: ChunkView,
		dug_tile: Vector2i,
		dug_world_pos: Vector2,
		expected_dirty_chunks: Array[Vector2i],
		revisions_before: Dictionary,
) -> void:
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(dug_tile)
	var override_data: Dictionary = streamer._diff_store.get_tile_override(OWNER_CHUNK, local_coord)
	_assert(
		int(override_data.get("terrain_id", -1)) == WorldRuntimeConstants.TERRAIN_PLAINS_DUG
				and bool(override_data.get("walkable", false)),
		"Mining must write one authoritative walkable tile override into WorldDiffStore.",
	)
	for chunk_coord: Vector2i in expected_dirty_chunks:
		var expected_revision: int = int(revisions_before.get(chunk_coord, -1)) + 1
		_assert(
			streamer._get_mountain_mask_revision(chunk_coord) == expected_revision,
			"Each halo-overlapping chunk mask revision must increment exactly once.",
		)
		var inflight: Dictionary = streamer._mountain_native_mask_inflight_chunks.get(chunk_coord, { }) as Dictionary
		_assert(
			int(inflight.get("revision", -1)) == expected_revision,
			"Each affected chunk must queue reconciliation for its current revision.",
		)

	var owner_sample: Dictionary = owner_view.sample_mountain_page_hit_at_world(dug_world_pos)
	var east_sample: Dictionary = east_view.sample_mountain_page_hit_at_world(dug_world_pos)
	_assert(
		bool(owner_sample.get("ready", false)) and bool(owner_sample.get("in_bounds", false))
				and not bool(owner_sample.get("solid", true)),
		"Interactive mining must clear owner collision bytes immediately.",
	)
	_assert(
		bool(east_sample.get("ready", false)) and bool(east_sample.get("in_bounds", false))
				and not bool(east_sample.get("solid", true)),
		"Interactive mining must clear overlapping neighbour collision bytes at the seam.",
	)
	_assert(streamer.is_walkable_at_world(dug_world_pos), "Mined mask opening must become walkable immediately.")
	_assert(not streamer.has_resource_at_world(dug_world_pos), "Mined open mask pixel must stop exposing a resource.")
	_assert(
		not streamer._pending_mountain_native_mask_visual_upload_set.has(OWNER_CHUNK)
				and not streamer._pending_mountain_native_mask_visual_upload_set.has(EAST_CHUNK),
		"Interactive collision patch must not upload or enqueue an ImageTexture before worker reconciliation.",
	)
	var serialized: String = JSON.stringify(streamer.collect_chunk_diffs())
	_assert(serialized.contains("terrain_id"), "Serialized diff must retain the mined tile mutation.")
	_assert(
		not serialized.contains("mask_revision") and not serialized.contains("native_mask"),
		"Derived halo-mask revisions and bytes must never enter authoritative save diffs.",
	)


func _assert_reconciled_state(
		streamer: Node,
		owner_view: ChunkView,
		dug_world_pos: Vector2,
		expected_revision: int,
) -> void:
	var ready_result: Dictionary = streamer._get_ready_mountain_native_mask_result(OWNER_CHUNK)
	_assert(not ready_result.is_empty(), "Current post-dig native mask result must enter the ready cache.")
	_assert(
		int(ready_result.get("revision", -1)) == expected_revision,
		"Ready native mask cache must expose only the current revision.",
	)
	_assert(
		not streamer._mountain_native_mask_inflight_chunks.has(OWNER_CHUNK),
		"Accepted current worker result must clear its in-flight marker.",
	)
	var remaining_sample: Dictionary = owner_view.sample_mountain_remaining_mass_hit_at_world(dug_world_pos)
	var closed_sample: Dictionary = owner_view.sample_mountain_closed_roof_hit_at_world(dug_world_pos)
	_assert(
		bool(remaining_sample.get("ready", false)) and bool(remaining_sample.get("in_bounds", false))
				and not bool(remaining_sample.get("solid", true)),
		"Reconciled remaining-mass mask must keep the mined center open.",
	)
	_assert(
		bool(closed_sample.get("ready", false)) and bool(closed_sample.get("in_bounds", false))
				and bool(closed_sample.get("solid", false)),
		"Construction-roof mask must preserve the immutable pre-dig mountain silhouette.",
	)
	var debug: Dictionary = owner_view.get_mountain_native_mask_debug_state()
	_assert(
		int(debug.get("dug_halo_tile_count", 0)) > 0,
		"Reconciled chunk must retain derived dug-halo ownership for roof presentation.",
	)
	_assert(streamer.is_walkable_at_world(dug_world_pos), "Worker reconciliation must not re-block the mined opening.")
	_assert(
		streamer._pending_mountain_native_mask_visual_upload_set.has(OWNER_CHUNK),
		"Only the accepted reconciled mask result may enqueue the deferred visual upload.",
	)


func _accept_worker_result(streamer: Node, result: Dictionary) -> void:
	var chunk_coord: Vector2i = result.get("target_chunk", Vector2i(-1, -1)) as Vector2i
	var revision: int = int(result.get("revision", -1))
	streamer._mountain_native_mask_inflight_chunks[chunk_coord] = {
		"revision": revision,
		"reason": result.get("reason", &"smoke") as StringName,
	}
	streamer._handle_completed_mountain_native_mask(result)
	_assert(
		int(streamer._get_ready_mountain_native_mask_result(chunk_coord).get("revision", -1)) == revision,
		"Current native halo-mask worker result must be accepted.",
	)


func _build_mask_result(
		streamer: Node,
		world_core: Object,
		chunk_coord: Vector2i,
		revision: int,
		reason: StringName,
) -> Dictionary:
	var fields: Dictionary = streamer._build_mountain_halo_fields(chunk_coord, HALO_RADIUS_TILES)
	var remaining_halo: PackedByteArray = fields.get("remaining_halo", PackedByteArray()) as PackedByteArray
	var origin_world: Vector2 = streamer._build_mountain_native_mask_origin(chunk_coord)
	var result_variant: Variant = world_core.call(
		"build_mountain_halo_mask",
		remaining_halo,
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.TILE_SIZE_PX,
		PIXELS_PER_TILE,
		origin_world.x,
		origin_world.y,
	)
	var result: Dictionary = result_variant as Dictionary if result_variant is Dictionary else { }
	var mask: PackedByteArray = result.get("mask", PackedByteArray()) as PackedByteArray
	var width: int = int(result.get("width", 0))
	var height: int = int(result.get("height", 0))
	var output_valid: bool = width > 0 and height > 0 and mask.size() == width * height
	var dug_halo: PackedByteArray = fields.get("dug_halo", PackedByteArray()) as PackedByteArray
	if _has_nonzero(dug_halo):
		var closed_halo: PackedByteArray = fields.get("closed_halo", PackedByteArray()) as PackedByteArray
		var closed_variant: Variant = world_core.call(
			"build_mountain_halo_mask",
			closed_halo,
			WorldRuntimeConstants.CHUNK_SIZE,
			WorldRuntimeConstants.TILE_SIZE_PX,
			PIXELS_PER_TILE,
			origin_world.x,
			origin_world.y,
		)
		var closed_result: Dictionary = closed_variant as Dictionary if closed_variant is Dictionary else { }
		var closed_mask: PackedByteArray = closed_result.get("mask", PackedByteArray()) as PackedByteArray
		var closed_width: int = int(closed_result.get("width", 0))
		var closed_height: int = int(closed_result.get("height", 0))
		var closed_output_valid: bool = closed_width == width \
				and closed_height == height \
				and closed_mask.size() == closed_width * closed_height \
				and is_equal_approx(
					float(closed_result.get("step_px", 0.0)),
					float(result.get("step_px", 0.0)),
				) \
				and int(closed_result.get("halo_side", 0)) == int(result.get("halo_side", 0))
		var reach_samples: int = \
				WorldChunkPacketBackend.MOUNTAIN_SKYLIGHT_REACH_TILES * PIXELS_PER_TILE
		var exposure_result: Dictionary = { }
		if closed_output_valid:
			var exposure_variant: Variant = world_core.call(
				"build_mountain_skylight_exposure",
				closed_mask,
				mask,
				width,
				height,
				float(result.get("step_px", 0.0)),
				reach_samples,
			)
			if exposure_variant is Dictionary:
				exposure_result = exposure_variant as Dictionary
		var exposure_mask: PackedByteArray = exposure_result.get(
			"sky_exposure_mask",
			PackedByteArray(),
		) as PackedByteArray
		var exposure_output_valid: bool = exposure_mask.size() == width * height \
				and int(exposure_result.get("width", 0)) == width \
				and int(exposure_result.get("height", 0)) == height \
				and is_equal_approx(
					float(exposure_result.get("step_px", 0.0)),
					float(result.get("step_px", 0.0)),
				) \
				and int(exposure_result.get("reach_samples", 0)) == reach_samples
		output_valid = output_valid and closed_output_valid and exposure_output_valid
		if exposure_output_valid:
			result["closed_roof_mask"] = closed_mask
			result["dug_halo"] = dug_halo.duplicate()
			result["sky_exposure_mask"] = exposure_mask
			result["sky_exposure_reach_samples"] = reach_samples
			result["sky_exposure_source_sample_count"] = int(
				exposure_result.get("source_sample_count", 0),
			)
	result["success"] = output_valid
	result["epoch"] = EPOCH
	result["revision"] = revision
	result["reason"] = reason
	result["mask_purpose"] = &"mountain"
	result["target_chunk"] = chunk_coord
	result["mask_origin_world"] = origin_world
	return result


func _attach_chunk_view(streamer: Node, chunk_coord: Vector2i) -> ChunkView:
	var chunk_view := ChunkView.new()
	chunk_view.configure(chunk_coord)
	streamer.add_child(chunk_view)
	streamer._chunk_views[chunk_coord] = chunk_view
	return chunk_view


func _load_halo_source_packets(streamer: Node, solid_world_tiles: Dictionary) -> void:
	# The four dirty targets share this exact 4x4 source packet set. No missing
	# packet may be interpreted as open air during a seam rebuild.
	for chunk_y: int in range(OWNER_CHUNK.y - 1, OWNER_CHUNK.y + 3):
		for chunk_x: int in range(OWNER_CHUNK.x - 1, OWNER_CHUNK.x + 3):
			var chunk_coord := Vector2i(chunk_x, chunk_y)
			streamer._chunk_packets[chunk_coord] = _build_packet(chunk_coord, solid_world_tiles)


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
		var world_tile: Vector2i = chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + local_coord
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


func _build_edge_mountain_tiles() -> Dictionary:
	var solid_world_tiles: Dictionary = { }
	var owner_origin: Vector2i = OWNER_CHUNK * WorldRuntimeConstants.CHUNK_SIZE
	for local_y: int in range(6, 11):
		for local_x: int in range(12, WorldRuntimeConstants.CHUNK_SIZE):
			solid_world_tiles[owner_origin + Vector2i(local_x, local_y)] = true
	return solid_world_tiles


func _has_nonzero(bytes: PackedByteArray) -> bool:
	for value: int in bytes:
		if value != 0:
			return true
	return false


func _assert_same_coord_set(
		actual: Array[Vector2i],
		expected: Array[Vector2i],
		message: String,
) -> void:
	var actual_set: Dictionary = { }
	for coord: Vector2i in actual:
		actual_set[coord] = true
	var expected_set: Dictionary = { }
	for coord: Vector2i in expected:
		expected_set[coord] = true
	_assert(actual_set == expected_set, message)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
