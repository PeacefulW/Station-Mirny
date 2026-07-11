extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const TARGET_CHUNK := Vector2i(4, 4)
const PLAYER_LOCAL_TILE := Vector2i(8, 8)
const MOUNTAIN_ID: int = 731
const HALO_RADIUS_TILES: int = 8
const HALO_SIDE: int = WorldRuntimeConstants.CHUNK_SIZE + HALO_RADIUS_TILES * 2

var _failed: bool = false
var _streamer: Node = null
var _player: Node2D = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Load autoload-dependent scripts after the first deferred turn. Direct
	# --script entrypoints are parsed before named autoload globals are registered.
	var world_streamer_script: Script = load("res://core/systems/world/world_streamer.gd")
	var fake_player_script: Script = load("res://tools/mountain_construction_roof_reload_fake_player.gd")
	var save_collectors_script: Script = load("res://core/autoloads/save_collectors.gd")
	var save_appliers_script: Script = load("res://core/autoloads/save_appliers.gd")
	_assert(world_streamer_script != null, "WorldStreamer script must load")
	_assert(fake_player_script != null, "typed fake Player script must load")
	_assert(save_collectors_script != null, "SaveCollectors script must load")
	_assert(save_appliers_script != null, "SaveAppliers script must load")
	if _failed:
		_finish()
		return
	_streamer = world_streamer_script.new() as Node
	_player = fake_player_script.new() as Node2D
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(_player)
	_player_authority().call("clear_cache")
	_player.global_position = WorldRuntimeConstants.tile_to_world_center(_player_world_tile())
	_streamer._mountain_mask_backend.start(1)

	_seed_live_fully_dug_chunk()
	_streamer._handle_cover_chunk_published(TARGET_CHUNK)
	_assert_inside_cover_restored("live session")

	var world_save: Dictionary = _streamer.save_world_state()
	var chunk_diff_save: Array[Dictionary] = _streamer.collect_chunk_diffs()
	var player_save: Dictionary = save_collectors_script.call("collect_player", self) as Dictionary
	_assert_save_contract(world_save, chunk_diff_save, player_save)

	var epoch_before_reload: int = _streamer._generation_epoch
	_player.global_position = WorldRuntimeConstants.tile_to_world_center(Vector2i(2, 2))
	_assert(_streamer.load_world_state(world_save), "current world save must pass the public load_world_state path")
	_assert(_streamer._generation_epoch == epoch_before_reload + 1, "world reload must advance the runtime generation epoch")
	_assert(_streamer._chunk_packets.is_empty(), "world reload must discard loaded packet caches")
	_assert(_streamer._active_cover_mountain_id == 0, "world reload must discard the derived active mountain id")
	_assert(_streamer._active_cover_component_id == 0, "world reload must discard the derived active cavity component id")
	_assert(_streamer.collect_chunk_diffs().is_empty(), "world reload must clear diffs before the chunk-diff payload is applied")

	_streamer.load_chunk_diffs(chunk_diff_save)
	save_appliers_script.call("apply_player", self, player_save)
	_assert(
		WorldRuntimeConstants.world_to_tile(_player.global_position) == _player_world_tile(),
		"player restore must put the player back on the saved interior floor",
	)
	_install_regenerated_packet_ring()

	var restored_packet: Dictionary = _streamer.get_chunk_packet(TARGET_CHUNK)
	_assert_fully_dug_packet_preserves_immutable_mountain(restored_packet)
	_assert(
		_streamer._packet_has_roof_bearing_mountain_metadata(restored_packet),
		"a fully dug chunk must remain roof-bearing through immutable mountain metadata",
	)
	_assert(
		not _streamer._packet_has_raster_mountain(restored_packet),
		"the fixture must be fully dug and therefore have no live blocked raster mountain cells",
	)
	_assert_restored_halo_contract()

	_streamer._handle_cover_chunk_published(TARGET_CHUNK)
	_assert_inside_cover_restored("reloaded session")
	await _assert_roof_bearing_publish_gate(restored_packet)

	_finish()


func _seed_live_fully_dug_chunk() -> void:
	_install_base_packet_ring()
	for local_y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for local_x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			_streamer._diff_store.set_tile_override(
				TARGET_CHUNK,
				Vector2i(local_x, local_y),
				WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
				true,
			)
	var base_packet: Dictionary = _make_mountain_packet(TARGET_CHUNK)
	_streamer._chunk_packets[TARGET_CHUNK] = _streamer._diff_store.apply_to_packet(base_packet)


func _install_regenerated_packet_ring() -> void:
	_install_base_packet_ring()
	var base_packet: Dictionary = _make_mountain_packet(TARGET_CHUNK)
	_streamer._chunk_packets[TARGET_CHUNK] = _streamer._diff_store.apply_to_packet(base_packet)


func _install_base_packet_ring() -> void:
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var chunk_coord: Vector2i = _streamer._canonicalize_chunk_coord(
				TARGET_CHUNK + Vector2i(offset_x, offset_y),
			)
			_streamer._chunk_packets[chunk_coord] = (
				_make_mountain_packet(chunk_coord)
				if chunk_coord == TARGET_CHUNK
				else _make_ground_packet(chunk_coord)
			)


func _make_mountain_packet(chunk_coord: Vector2i) -> Dictionary:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_ids.fill(WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.fill(MOUNTAIN_ID)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.fill(
		WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR | WorldRuntimeConstants.MOUNTAIN_FLAG_WALL,
	)
	return {
		"chunk_coord": chunk_coord,
		"terrain_ids": terrain_ids,
		"walkable_flags": walkable_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
	}


func _make_ground_packet(chunk_coord: Vector2i) -> Dictionary:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_ids.fill(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.fill(1)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	return {
		"chunk_coord": chunk_coord,
		"terrain_ids": terrain_ids,
		"walkable_flags": walkable_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
	}


func _assert_save_contract(
	world_save: Dictionary,
	chunk_diff_save: Array[Dictionary],
	player_save: Dictionary,
) -> void:
	_assert(chunk_diff_save.size() == 1, "the fully dug fixture must serialize as one dirty chunk")
	if chunk_diff_save.size() == 1:
		var tiles: Array = chunk_diff_save[0].get("tiles", []) as Array
		_assert(
			tiles.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT,
			"the fully dug fixture must serialize all 256 authoritative tile overrides",
		)
	_assert(
		not _variant_contains_any_key(world_save, [
			"closed_roof_mask",
			"remaining_mass_mask",
			"active_cover_component_id",
			"active_cover_mountain_id",
		]),
		"world save must not persist derived construction masks or cavity ids",
	)
	_assert(
		not _variant_contains_any_key(chunk_diff_save, [
			"mountain_id",
			"mountain_id_per_tile",
			"mountain_flags",
			"closed_roof_mask",
			"remaining_mass_mask",
		]),
		"chunk diff save must persist terrain/walkability only, never immutable mountain metadata or derived masks",
	)
	var saved_position: Dictionary = player_save.get("position", {}) as Dictionary
	_assert(not saved_position.is_empty(), "player save must include the position used to restore the active cavity")
	_assert(
		is_equal_approx(float(saved_position.get("x", -1.0)), _player.global_position.x)
			and is_equal_approx(float(saved_position.get("y", -1.0)), _player.global_position.y),
		"player save must capture the interior floor position",
	)


func _assert_fully_dug_packet_preserves_immutable_mountain(packet: Dictionary) -> void:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var walkable_flags: PackedByteArray = packet.get("walkable_flags", PackedByteArray()) as PackedByteArray
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	_assert(terrain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "restored terrain array must keep packet shape")
	_assert(walkable_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "restored walkability array must keep packet shape")
	_assert(mountain_ids.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "restored mountain-id array must keep packet shape")
	_assert(mountain_flags.size() == WorldRuntimeConstants.CHUNK_CELL_COUNT, "restored mountain-flag array must keep packet shape")
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		_assert(terrain_ids[index] == WorldRuntimeConstants.TERRAIN_PLAINS_DUG, "restored tile %d must remain dug" % index)
		_assert(walkable_flags[index] == 1, "restored tile %d must remain walkable" % index)
		_assert(mountain_ids[index] == MOUNTAIN_ID, "restored tile %d must retain immutable mountain ownership" % index)
		_assert(
			(int(mountain_flags[index]) & WorldRuntimeConstants.MOUNTAIN_FLAG_WALL) != 0,
			"restored tile %d must retain immutable roof-bearing flags" % index,
		)


func _assert_restored_halo_contract() -> void:
	var fields: Dictionary = _streamer._build_mountain_halo_fields(TARGET_CHUNK, HALO_RADIUS_TILES)
	var closed_halo: PackedByteArray = fields.get("closed_halo", PackedByteArray()) as PackedByteArray
	var remaining_halo: PackedByteArray = fields.get("remaining_halo", PackedByteArray()) as PackedByteArray
	var dug_halo: PackedByteArray = fields.get("dug_halo", PackedByteArray()) as PackedByteArray
	_assert(bool(fields.get("has_local_closed", false)), "restored fully dug chunk must still advertise local closed construction")
	_assert(closed_halo.size() == HALO_SIDE * HALO_SIDE, "restored closed halo must keep its 32x32 shape")
	_assert(remaining_halo.size() == HALO_SIDE * HALO_SIDE, "restored remaining halo must keep its 32x32 shape")
	_assert(dug_halo.size() == HALO_SIDE * HALO_SIDE, "restored dug halo must keep its 32x32 shape")
	for local_y: int in range(WorldRuntimeConstants.CHUNK_SIZE):
		for local_x: int in range(WorldRuntimeConstants.CHUNK_SIZE):
			var halo_index: int = (local_y + HALO_RADIUS_TILES) * HALO_SIDE + local_x + HALO_RADIUS_TILES
			_assert(closed_halo[halo_index] == 1, "closed construction halo must retain tile (%d,%d)" % [local_x, local_y])
			_assert(remaining_halo[halo_index] == 0, "remaining mass halo must keep dug tile (%d,%d) open" % [local_x, local_y])
			_assert(dug_halo[halo_index] == 1, "dug halo must restore tile (%d,%d) from diff" % [local_x, local_y])


func _assert_inside_cover_restored(label: String) -> void:
	var sample: Dictionary = _streamer.get_mountain_cover_sample(_player_world_tile())
	var component_id: int = int(sample.get("component_id", 0))
	_assert(int(sample.get("mountain_id", 0)) == MOUNTAIN_ID, "%s must resolve the player's immutable mountain id" % label)
	_assert(component_id > 0, "%s must rebuild a cavity component under the player" % label)
	_assert(_streamer._active_cover_mountain_id == MOUNTAIN_ID, "%s must automatically restore the active mountain" % label)
	_assert(_streamer._active_cover_component_id == component_id, "%s must automatically restore the player's active cavity" % label)
	var floor_mask: PackedByteArray = _streamer._mountain_cavity_cache.build_chunk_component_floor_mask(
		TARGET_CHUNK,
		component_id,
	)
	var local_index: int = WorldRuntimeConstants.local_to_index(PLAYER_LOCAL_TILE)
	_assert(local_index < floor_mask.size() and floor_mask[local_index] == 1, "%s active reveal must contain the player's restored floor" % label)


func _assert_roof_bearing_publish_gate(restored_packet: Dictionary) -> void:
	_assert(
		not _streamer._can_publish_chunk_with_mountain_mask(TARGET_CHUNK, restored_packet),
		"fully dug roof-bearing chunk must wait for its native paired mask before publish",
	)
	_assert(
		_streamer._mountain_native_mask_inflight_chunks.has(TARGET_CHUNK),
		"publish gate must queue native paired-mask work for the fully dug chunk",
	)

	var result: Dictionary = {}
	var wait_started_msec: int = Time.get_ticks_msec()
	while result.is_empty() and Time.get_ticks_msec() - wait_started_msec < 5000:
		_streamer._drain_completed_native_masks(8)
		result = _streamer._get_ready_mountain_native_mask_result(TARGET_CHUNK)
		if result.is_empty():
			await process_frame
	_assert(not result.is_empty(), "native paired mask for the restored fully dug chunk must complete")
	if result.is_empty():
		return
	_assert(int(result.get("closed_sample_count", -1)) == WorldRuntimeConstants.CHUNK_CELL_COUNT, "closed native mask must retain all 256 immutable samples")
	_assert(int(result.get("dug_sample_count", -1)) == WorldRuntimeConstants.CHUNK_CELL_COUNT, "native mask must receive all 256 restored dug samples")
	_assert(int(result.get("solid_sample_count", -1)) == 0, "remaining native mask must have zero solid source samples")
	var closed_mask: PackedByteArray = result.get("closed_roof_mask", PackedByteArray()) as PackedByteArray
	var remaining_mask: PackedByteArray = result.get("remaining_mass_mask", PackedByteArray()) as PackedByteArray
	_assert(_mask_has_nonzero(closed_mask), "restored native closed-roof mask must remain visible")
	_assert(
		_native_target_source_core_is_zero(result, remaining_mask),
		"restored native remaining-mass mask must hard-clear every pixel of the fully dug 16x16 source core",
	)
	_assert(
		_streamer._can_publish_chunk_with_mountain_mask(TARGET_CHUNK, restored_packet),
		"fully dug roof-bearing chunk may publish after its paired native mask is ready",
	)


func _player_world_tile() -> Vector2i:
	return TARGET_CHUNK * WorldRuntimeConstants.CHUNK_SIZE + PLAYER_LOCAL_TILE


func _mask_has_nonzero(mask: PackedByteArray) -> bool:
	for value: int in mask:
		if value != 0:
			return true
	return false


func _native_target_source_core_is_zero(result: Dictionary, mask: PackedByteArray) -> bool:
	var width: int = int(result.get("width", 0))
	var height: int = int(result.get("height", 0))
	var pixels_per_tile: int = int(result.get("pixels_per_tile", 0))
	var halo_radius: int = int(result.get("halo_radius_tiles", 0))
	if width <= 0 or height <= 0 or pixels_per_tile <= 0 or mask.size() != width * height:
		return false
	var core_origin_px: int = halo_radius * pixels_per_tile
	var core_side_px: int = WorldRuntimeConstants.CHUNK_SIZE * pixels_per_tile
	for y: int in range(core_origin_px, core_origin_px + core_side_px):
		for x: int in range(core_origin_px, core_origin_px + core_side_px):
			if mask[y * width + x] != 0:
				return false
	return true


func _variant_contains_any_key(value: Variant, keys: Array[String]) -> bool:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		for key: String in keys:
			if dictionary.has(key):
				return true
		for child: Variant in dictionary.values():
			if _variant_contains_any_key(child, keys):
				return true
	elif value is Array:
		for child: Variant in value as Array:
			if _variant_contains_any_key(child, keys):
				return true
	return false


func _finish() -> void:
	if _streamer != null:
		_streamer._mountain_mask_backend.stop()
		_streamer.free()
		_streamer = null
	if is_instance_valid(_player):
		_player_authority().call("clear_cache")
		_player.free()
		_player = null
	call_deferred("_quit_after_cleanup")


func _quit_after_cleanup() -> void:
	if _failed:
		quit(1)
		return
	print("mountain_construction_roof_reload_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true


func _player_authority() -> Node:
	return root.get_node("PlayerAuthority")
