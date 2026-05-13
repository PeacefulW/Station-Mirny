extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const OUTPUT_SIZE_PX: int = 8
const COLLISION_SIDE: int = 5
const COLLISION_SAMPLE_PX: int = 256

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	if _failed:
		quit(1)
		return

	var streamer := WorldStreamer.new()
	root.add_child(streamer)
	await process_frame

	var dug_tile := Vector2i(WorldRuntimeConstants.CHUNK_SIZE - 1, 8)
	_load_edge_excavation_packets(streamer, dug_tile)
	var diff_revision: int = _assert_excavation_marks_dirty_revision(streamer, dug_tile)
	_assert_stale_result_discarded(streamer, diff_revision)
	_assert_visual_and_collision_ready_together(streamer, dug_tile, diff_revision)

	await _shutdown_streamer(streamer)
	if _failed:
		quit(1)
		return
	print("runtime_sdf_contour_excavation_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var diff_store_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_diff_store.gd")
	_assert(
		diff_store_source.contains("var diff_revision"),
		"WorldDiffStore must own a monotonic diff_revision."
	)
	_assert(
		diff_store_source.contains("func get_diff_revision"),
		"WorldDiffStore must expose get_diff_revision()."
	)

	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("_contour_requested_revision_by_chunk"),
		"WorldStreamer must track requested contour revisions per chunk."
	)
	_assert(
		streamer_source.contains("_contour_ready_revision_by_chunk"),
		"WorldStreamer must track ready contour revisions per chunk."
	)
	_assert(
		streamer_source.contains("get_contour_dirty_debug_state"),
		"WorldStreamer must expose contour dirty revision debug readback."
	)

	var api_source: String = FileAccess.get_file_as_string("res://docs/02_system_specs/meta/system_api.md")
	_assert(
		api_source.contains("get_contour_dirty_debug_state"),
		"system_api.md must document contour dirty revision debug readback."
	)

func _load_edge_excavation_packets(streamer: WorldStreamer, dug_tile: Vector2i) -> void:
	streamer._chunk_packets[Vector2i.ZERO] = _build_packet(
		Vector2i.ZERO,
		{
			WorldRuntimeConstants.tile_to_local(dug_tile): true,
		}
	)
	streamer._chunk_packets[Vector2i(1, 0)] = _build_packet(Vector2i(1, 0), {})

func _assert_excavation_marks_dirty_revision(streamer: WorldStreamer, dug_tile: Vector2i) -> int:
	var previous_revision: int = streamer._diff_store.get_diff_revision()
	var harvest_result: Dictionary = streamer.try_harvest_at_world(
		WorldRuntimeConstants.tile_to_world_center(dug_tile)
	)
	_assert(bool(harvest_result.get("success", false)), "Edge mountain harvest must succeed.")

	var diff_revision: int = streamer._diff_store.get_diff_revision()
	_assert(
		diff_revision == previous_revision + 1,
		"Successful harvest must increment WorldDiffStore.diff_revision exactly once."
	)
	_assert(
		streamer._contour_diff_revision == diff_revision,
		"WorldStreamer contour revision mirror must match WorldDiffStore after harvest."
	)

	var owning_state: Dictionary = streamer.get_contour_dirty_debug_state(Vector2i.ZERO)
	_assert(
		int(owning_state.get("requested_revision", -1)) == diff_revision,
		"Owning chunk must be marked dirty for the new diff revision."
	)
	_assert(
		int(owning_state.get("ready_revision", -1)) != diff_revision,
		"Owning chunk must not be movement-ready before fresh contour results apply."
	)

	var seam_neighbor_state: Dictionary = streamer.get_contour_dirty_debug_state(Vector2i(1, 0))
	_assert(
		int(seam_neighbor_state.get("requested_revision", -1)) == diff_revision,
		"Direct seam-neighbor chunk must be marked dirty when a tile within the two-tile halo changes."
	)

	var serialized_diffs: String = JSON.stringify(streamer.collect_chunk_diffs())
	_assert(
		not serialized_diffs.contains("diff_revision"),
		"WorldDiffStore.diff_revision must not be serialized in chunk diff payloads."
	)
	return diff_revision

func _assert_stale_result_discarded(streamer: WorldStreamer, diff_revision: int) -> void:
	var stale_result: Dictionary = _build_contour_result(
		Vector2i.ZERO,
		WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
		diff_revision - 1,
		-8.0,
		streamer._generation_epoch
	)
	_assert(
		not streamer._register_contour_result(stale_result),
		"Stale contour result must be rejected after a newer diff revision exists."
	)
	var state: Dictionary = streamer.get_contour_dirty_debug_state(Vector2i.ZERO)
	_assert(
		int(state.get("ready_revision", -1)) != diff_revision - 1,
		"Rejected stale result must not update ready contour revision."
	)

func _assert_visual_and_collision_ready_together(
	streamer: WorldStreamer,
	dug_tile: Vector2i,
	diff_revision: int
) -> void:
	var chunk_view = streamer._ensure_chunk_view(Vector2i.ZERO)
	chunk_view.set_contour_rendering_enabled(true)
	chunk_view.begin_apply(streamer._chunk_packets[Vector2i.ZERO] as Dictionary)
	while chunk_view.apply_next_batch(512):
		pass

	var dug_world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(dug_tile)
	_assert(
		not streamer.is_walkable_at_world(dug_world_pos),
		"Movement must fail closed while the current contour revision is dirty."
	)

	_assert(
		streamer._register_contour_result(_build_contour_result(
			Vector2i.ZERO,
			WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
			diff_revision,
			-8.0,
			streamer._generation_epoch
		)),
		"Fresh mountain contour result must be accepted."
	)
	_assert(
		not streamer.is_walkable_at_world(dug_world_pos),
		"Movement must stay blocked until visual and collision contour classes are ready together."
	)
	var partial_render_state: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(
		not bool(partial_render_state.get("ready", true)),
		"ChunkView must not become render-ready from a collision-only contour result."
	)

	_assert(
		streamer._register_contour_result(_build_contour_result(
			Vector2i.ZERO,
			WorldRuntimeConstants.CONTOUR_CLASS_GROUND_SURFACE,
			diff_revision,
			-8.0,
			streamer._generation_epoch
		)),
		"Fresh ground contour result must be accepted."
	)
	_assert(
		streamer.is_walkable_at_world(dug_world_pos),
		"Movement must become ready after active ground and mountain contour classes are ready."
	)
	var ready_after_active_state: Dictionary = streamer.get_contour_dirty_debug_state(Vector2i.ZERO)
	_assert(
		int(ready_after_active_state.get("ready_revision", -1)) == diff_revision,
		"Chunk contour ready revision must advance after active ground and mountain classes are ready."
	)

	_assert(
		streamer._register_contour_result(_build_contour_result(
			Vector2i.ZERO,
			WorldRuntimeConstants.CONTOUR_CLASS_WATER_SURFACE,
			diff_revision,
			-8.0,
			streamer._generation_epoch
		)),
		"Fresh water contour result must be accepted."
	)

	var ready_state: Dictionary = streamer.get_contour_dirty_debug_state(Vector2i.ZERO)
	_assert(
		int(ready_state.get("ready_revision", -1)) == diff_revision,
		"Optional water contour result must not regress active chunk readiness."
	)
	_assert(
		streamer.is_walkable_at_world(dug_world_pos),
		"Movement must pass through the dug edge after matching collision revision becomes ready."
	)
	var render_state: Dictionary = chunk_view.get_contour_render_debug_state()
	_assert(
		bool(render_state.get("ready", false)),
		"ChunkView visual contour revision must become ready with the matching collision revision."
	)

func _build_packet(chunk_coord: Vector2i, mountain_locals: Dictionary) -> Dictionary:
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
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		walkable_flags[index] = 1
	for local_variant: Variant in mountain_locals.keys():
		var local_coord: Vector2i = local_variant as Vector2i
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		walkable_flags[index] = 0
		mountain_ids[index] = 1
		mountain_flags[index] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL
	return {
		"chunk_coord": chunk_coord,
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"walkable_flags": walkable_flags,
		"lake_flags": lake_flags,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
		"mountain_atlas_indices": mountain_atlas_indices,
	}

func _build_contour_result(
	chunk_coord: Vector2i,
	contour_class: StringName,
	diff_revision: int,
	sdf_fill: float,
	epoch: int
) -> Dictionary:
	var collision_values := PackedFloat32Array()
	collision_values.resize(COLLISION_SIDE * COLLISION_SIDE)
	collision_values.fill(sdf_fill)
	return {
		"chunk_coord": chunk_coord,
		"contour_class": contour_class,
		"recipe_id": contour_class,
		"epoch": epoch,
		"diff_revision": diff_revision,
		"pixel_size": Vector2i(OUTPUT_SIZE_PX, OUTPUT_SIZE_PX),
		"mask_rgba8": _build_byte_buffer(OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 4, 255),
		"height_r16": _build_byte_buffer(OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 2, 127),
		"normal_rgba8": _build_byte_buffer(OUTPUT_SIZE_PX * OUTPUT_SIZE_PX * 4, 128),
		"collision_sdf_f32": collision_values,
		"collision_origin_world_px": WorldRuntimeConstants.chunk_origin_px(chunk_coord),
		"collision_sample_px": COLLISION_SAMPLE_PX,
		"collision_size": Vector2i(COLLISION_SIDE, COLLISION_SIDE),
		"collision_blocks_inside": contour_class == WorldRuntimeConstants.CONTOUR_CLASS_MOUNTAIN_MASS,
		"ready": true,
	}

func _build_byte_buffer(size: int, value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(size)
	bytes.fill(value)
	return bytes

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
