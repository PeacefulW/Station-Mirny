extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const TARGET_SEED: int = 240518
const MAX_POLL_FRAMES: int = 240

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()

	var streamer := WorldStreamer.new()
	root.add_child(streamer)
	await process_frame

	var world_core: Object = ClassDB.instantiate("WorldCore")
	_assert(world_core != null, "WorldCore must be available for contour streaming smoke.")
	if world_core == null:
		await _shutdown_streamer(streamer)
		quit(1)
		return

	var target_chunk := Vector2i(streamer._world_bounds_settings.get_width_chunks() - 1, 0)
	_load_generated_target_packet(streamer, world_core, target_chunk)

	var wrapped_diff_tile := Vector2i(0, WorldRuntimeConstants.CHUNK_SIZE / 2)
	_set_diff_override_without_request(streamer, wrapped_diff_tile, WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL, false)

	_assert_halo_contracts(streamer, target_chunk)
	_assert_worker_request_includes_native_ground_before_mountain(streamer, target_chunk)
	await _assert_worker_result_lifecycle(streamer, target_chunk)

	await _shutdown_streamer(streamer)
	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_streaming_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("_request_contour_results_for_chunk"),
		"WorldStreamer must own contour result requests for loaded chunks."
	)
	_assert(
		streamer_source.contains("_build_contour_worker_request"),
		"WorldStreamer must snapshot packet + diff data before contour worker compute."
	)
	_assert(
		streamer_source.contains("generate_chunk_packets_batch"),
		"Contour halo assembly must request transient native base packets for unloaded neighbors."
	)
	_assert(
		streamer_source.contains("build_contour_chunk"),
		"Contour streaming must call WorldCore.build_contour_chunk(input)."
	)

	var registry_source: String = FileAccess.get_file_as_string("res://core/systems/world/terrain_presentation_registry.gd")
	_assert(
		registry_source.contains("get_contour_recipe_for_class"),
		"TerrainPresentationRegistry must expose contour recipe lookup by terrain class."
	)

	var api_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/system_api.md")
	_assert(
		api_source.contains("get_contour_result_debug_state"),
		"system_api.md must document contour result debug readback."
	)

func _load_generated_target_packet(streamer: WorldStreamer, world_core: Object, target_chunk: Vector2i) -> void:
	var coords := PackedVector2Array()
	coords.append(target_chunk)
	var packets_variant: Variant = world_core.call(
		"generate_chunk_packets_batch",
		TARGET_SEED,
		coords,
		streamer.world_version,
		streamer._worldgen_settings_packed
	)
	_assert(packets_variant is Array, "Native target packet generation must return an Array.")
	if packets_variant is not Array:
		return
	var packets: Array = packets_variant as Array
	_assert(packets.size() == 1, "Native target packet generation must return one packet.")
	if packets.size() != 1:
		return
	streamer.world_seed = TARGET_SEED
	streamer._chunk_packets[target_chunk] = packets[0] as Dictionary

func _assert_halo_contracts(streamer: WorldStreamer, target_chunk: Vector2i) -> void:
	var expected_side: int = WorldRuntimeConstants.CHUNK_SIZE + WorldRuntimeConstants.CONTOUR_HALO_TILES * 2
	for contour_class: StringName in WorldRuntimeConstants.CONTOUR_CLASSES:
		var halo: Dictionary = streamer.get_contour_halo_debug_state(target_chunk, contour_class)
		_assert(bool(halo.get("ready", false)), "%s halo debug state must be ready." % contour_class)
		_assert(int(halo.get("halo_side", 0)) == expected_side, "%s halo side must be 20." % contour_class)
		_assert((halo.get("solid_mask_with_halo", PackedByteArray()) as PackedByteArray).size() == expected_side * expected_side, "%s solid halo must contain 400 cells." % contour_class)
		_assert((halo.get("contour_class_mask_with_halo", PackedByteArray()) as PackedByteArray).size() == expected_side * expected_side, "%s class halo must contain 400 cells." % contour_class)
		_assert((halo.get("mountain_id_with_halo", PackedInt32Array()) as PackedInt32Array).size() == expected_side * expected_side, "%s mountain id halo must contain 400 cells." % contour_class)

	var mountain_halo: Dictionary = streamer.get_contour_halo_debug_state(
		target_chunk,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	var source_mask: PackedByteArray = mountain_halo.get("source_mask_with_halo", PackedByteArray()) as PackedByteArray
	var terrain_ids: PackedInt32Array = mountain_halo.get("terrain_id_with_halo", PackedInt32Array()) as PackedInt32Array
	var solid_mask: PackedByteArray = mountain_halo.get("solid_mask_with_halo", PackedByteArray()) as PackedByteArray
	var chunks: Array = mountain_halo.get("chunk_coord_with_halo", []) as Array
	var side: int = int(mountain_halo.get("halo_side", 0))

	var wrapped_generated_index: int = (WorldRuntimeConstants.CHUNK_SIZE / 2 + WorldRuntimeConstants.CONTOUR_HALO_TILES) * side + WorldRuntimeConstants.CONTOUR_HALO_TILES + WorldRuntimeConstants.CHUNK_SIZE + 1
	_assert(source_mask[wrapped_generated_index] == WorldRuntimeConstants.CONTOUR_SOURCE_GENERATED_BASE, "Unloaded wrapped neighbor halo must come from generated base packet data.")
	_assert(chunks[wrapped_generated_index] == Vector2i(0, target_chunk.y), "Right-side halo at the world seam must wrap to chunk x=0.")

	var wrapped_diff_index: int = (WorldRuntimeConstants.CHUNK_SIZE / 2 + WorldRuntimeConstants.CONTOUR_HALO_TILES) * side + WorldRuntimeConstants.CONTOUR_HALO_TILES + WorldRuntimeConstants.CHUNK_SIZE
	_assert(source_mask[wrapped_diff_index] == WorldRuntimeConstants.CONTOUR_SOURCE_UNLOADED_DIFF, "Runtime diff override must win over generated base packet data for unloaded neighbors.")
	_assert(terrain_ids[wrapped_diff_index] == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL, "Diff override terrain id must be visible in the halo.")
	_assert(solid_mask[wrapped_diff_index] == 1, "Mountain diff override must mark the mountain contour solid.")

	var out_of_world_index: int = 0
	_assert(source_mask[out_of_world_index] == WorldRuntimeConstants.CONTOUR_SOURCE_OUT_OF_WORLD, "Top halo outside finite Y bounds must be empty.")
	_assert(solid_mask[out_of_world_index] == 0, "Out-of-world halo cells must not be solid.")

func _assert_worker_request_includes_native_ground_before_mountain(streamer: WorldStreamer, target_chunk: Vector2i) -> void:
	var request: Dictionary = streamer._build_contour_worker_request(target_chunk, streamer._contour_diff_revision)
	var contour_classes: Array = request.get("contour_classes", []) as Array
	_assert(not contour_classes.is_empty(), "Contour worker request must include active contour classes.")
	if contour_classes.is_empty():
		return
	_assert(
		contour_classes[0] == WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE,
		"Contour worker must keep ground_surface first so native ground and mountain readiness is deterministic."
	)

func _assert_worker_result_lifecycle(streamer: WorldStreamer, target_chunk: Vector2i) -> void:
	streamer.request_contour_results_for_chunk_debug(target_chunk)
	await _poll_contour_ready(streamer, target_chunk, WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS)
	var first_state: Dictionary = streamer.get_contour_result_debug_state(
		target_chunk,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	_assert(bool(first_state.get("ready", false)), "Mountain contour result must become ready through the worker lifecycle.")
	var first_revision: int = int(first_state.get("diff_revision", -1))

	_set_diff_override_without_request(
		streamer,
		Vector2i(0, WorldRuntimeConstants.CHUNK_SIZE / 2 + 1),
		WorldRuntimeConstants.TERRAIN_PLAINS_GROUND,
		true
	)
	streamer._contour_diff_revision += 1
	var unchanged_state: Dictionary = streamer.get_contour_result_debug_state(
		target_chunk,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	_assert(bool(unchanged_state.get("ready", false)), "Unchanged chunks must keep their ready contour revision after an unrelated global diff.")
	_assert(int(unchanged_state.get("required_diff_revision", -1)) == first_revision, "Unchanged chunks must keep their per-chunk required contour revision.")
	streamer._contour_requested_revision_by_chunk[target_chunk] = streamer._contour_diff_revision
	streamer._contour_ready_revision_by_chunk.erase(target_chunk)
	var stale_state: Dictionary = streamer.get_contour_result_debug_state(
		target_chunk,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	_assert(not bool(stale_state.get("ready", true)), "Contour results older than a chunk's required dirty revision must not read as ready.")
	_assert(int(stale_state.get("stored_diff_revision", -1)) == first_revision, "Debug readback must expose the stale stored revision.")
	_assert(int(stale_state.get("current_diff_revision", -1)) > first_revision, "Debug readback must expose the newer current revision.")
	_assert(int(stale_state.get("required_diff_revision", -1)) > first_revision, "Debug readback must expose the chunk-required dirty revision.")

	streamer._release_contour_results_for_chunk(target_chunk)
	var released_state: Dictionary = streamer.get_contour_result_debug_state(
		target_chunk,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS
	)
	_assert(not bool(released_state.get("ready", true)), "Unloading/releasing a chunk must drop contour result references.")

func _poll_contour_ready(streamer: WorldStreamer, chunk_coord: Vector2i, contour_class: StringName) -> void:
	for _frame: int in range(MAX_POLL_FRAMES):
		streamer.drain_contour_results_debug(8)
		var state: Dictionary = streamer.get_contour_result_debug_state(chunk_coord, contour_class)
		if bool(state.get("ready", false)):
			return
		await process_frame
	_assert(false, "Timed out waiting for contour worker result for %s." % contour_class)

func _set_diff_override_without_request(streamer: WorldStreamer, world_tile: Vector2i, terrain_id: int, walkable: bool) -> void:
	var canonical_tile: Vector2i = streamer._canonicalize_tile_coord(world_tile)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(canonical_tile)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(canonical_tile)
	streamer._diff_store.set_tile_override(chunk_coord, local_coord, terrain_id, walkable)

func _shutdown_streamer(streamer: WorldStreamer) -> void:
	if streamer == null:
		return
	if is_instance_valid(streamer):
		streamer._stop_contour_worker()
		streamer._packet_backend.stop()
		if streamer.get_parent() != null:
			streamer.get_parent().remove_child(streamer)
		streamer.free()
		await process_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
