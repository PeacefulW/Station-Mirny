extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldStreamer = preload("res://core/systems/world/world_streamer.gd")

const OUTPUT_DIR: String = "res://artifacts/mountain_contour_mining_dirty_smoke_test"
const REPORT_PATH: String = "%s/report.json" % OUTPUT_DIR
const HARD_LIMIT_USEC: int = 100000

var _failed: bool = false
var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_static_contract()
	if _failed:
		_write_report()
		quit(1)
		return

	var center_streamer := WorldStreamer.new()
	root.add_child(center_streamer)
	await process_frame
	_assert_center_tile_rebuilds_immediately(center_streamer)
	await _shutdown_streamer(center_streamer)

	var seam_streamer := WorldStreamer.new()
	root.add_child(seam_streamer)
	await process_frame
	_assert_seam_tile_rebuilds_owner_and_neighbour(seam_streamer)
	await _shutdown_streamer(seam_streamer)

	if _failed:
		_write_report()
		quit(1)
		return
	_write_report()
	print("mountain_contour_mining_dirty_smoke_test: OK")
	quit(0)

func _assert_static_contract() -> void:
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		streamer_source.contains("_resolve_mountain_contour_dirty_chunks_for_tile"),
		"WorldStreamer must own an exact contour dirty chunk resolver for mined tiles."
	)
	_assert(
		streamer_source.contains("_refresh_mountain_contour_runtime_after_mining"),
		"WorldStreamer must synchronously rebuild contour runtime data after mining a mountain tile."
	)
	_assert(
		streamer_source.contains("mountain_contour_dirty_update"),
		"try_harvest_at_world() must return mining contour dirty-update telemetry."
	)
	_assert(
		streamer_source.contains("contour_rebuild_usec"),
		"Mining contour dirty updates must report total contour_rebuild_usec telemetry."
	)
	_assert(
		streamer_source.contains("visual_apply_usec"),
		"Mining contour dirty updates must report visual_apply_usec telemetry."
	)
	_assert(
		streamer_source.contains("collision_apply_usec"),
		"Mining contour dirty updates must report collision_apply_usec telemetry."
	)
	var resolver_body: String = _function_body(streamer_source, "_resolve_mountain_contour_dirty_chunks_for_tile")
	_assert(
		not resolver_body.contains("range(-1, 2)"),
		"Mining contour dirty resolver must not use a blind 3x3 rebuild."
	)
	_assert(
		not resolver_body.contains("range(-1,2)"),
		"Mining contour dirty resolver must not use a blind 3x3 rebuild."
	)

func _assert_center_tile_rebuilds_immediately(streamer: WorldStreamer) -> void:
	var chunk_coord := Vector2i.ZERO
	_load_chunk(streamer, chunk_coord, _build_packet(chunk_coord, [
		Vector2i(7, 7),
		Vector2i(8, 7),
		Vector2i(7, 8),
		Vector2i(8, 8),
	]))
	var before: Dictionary = streamer.get_mountain_contour_runtime_debug_snapshot(chunk_coord)
	var before_revision: int = int(before.get("runtime_revision", -1))
	var before_solid_count: int = int(before.get("halo_solid_sample_count", 0))

	var mined_tile := Vector2i(8, 8)
	var result: Dictionary = streamer.try_harvest_at_world(WorldRuntimeConstants.tile_to_world_center(mined_tile))
	_assert(bool(result.get("success", false)), "Center mountain harvest must succeed.")
	var update: Dictionary = result.get("mountain_contour_dirty_update", {}) as Dictionary
	_assert_update_common(update, 1)
	_assert((update.get("affected_chunks", []) as Array).has(chunk_coord), "Center mining must rebuild the owning chunk.")

	var after: Dictionary = streamer.get_mountain_contour_runtime_debug_snapshot(chunk_coord)
	var after_revision: int = int(after.get("runtime_revision", -1))
	_assert(after_revision > before_revision, "Center mining must advance the contour runtime revision immediately.")
	_assert(
		int(after.get("halo_solid_sample_count", 0)) == before_solid_count - 1,
		"Center mining must remove exactly one solid mountain sample from the contour halo."
	)
	_assert_visual_collision_revisions_match(after, "Center mining")
	_assert(
		streamer.is_capsule_walkable_at_world(WorldRuntimeConstants.tile_to_world_center(mined_tile), 16.0),
		"Center mining must clear stale rectangular contour collision at the dug tile center."
	)

func _assert_seam_tile_rebuilds_owner_and_neighbour(streamer: WorldStreamer) -> void:
	var owning_chunk := Vector2i.ZERO
	var east_chunk := Vector2i(1, 0)
	_load_chunk(streamer, owning_chunk, _build_packet(owning_chunk, [
		Vector2i(14, 7),
		Vector2i(15, 7),
		Vector2i(14, 8),
		Vector2i(15, 8),
	]))
	_load_chunk(streamer, east_chunk, _build_packet(east_chunk, []))
	var owner_before: Dictionary = streamer.get_mountain_contour_runtime_debug_snapshot(owning_chunk)
	var east_before: Dictionary = streamer.get_mountain_contour_runtime_debug_snapshot(east_chunk)

	var seam_tile := Vector2i(WorldRuntimeConstants.CHUNK_SIZE - 1, 7)
	var result: Dictionary = streamer.try_harvest_at_world(WorldRuntimeConstants.tile_to_world_center(seam_tile))
	_assert(bool(result.get("success", false)), "East seam mountain harvest must succeed.")
	var update: Dictionary = result.get("mountain_contour_dirty_update", {}) as Dictionary
	_assert_update_common(update, 2)
	var affected_chunks: Array = update.get("affected_chunks", []) as Array
	_assert(affected_chunks.has(owning_chunk), "Seam mining must rebuild the owning chunk.")
	_assert(affected_chunks.has(east_chunk), "East seam mining must rebuild the east seam-neighbour chunk.")

	var owner_after: Dictionary = streamer.get_mountain_contour_runtime_debug_snapshot(owning_chunk)
	var east_after: Dictionary = streamer.get_mountain_contour_runtime_debug_snapshot(east_chunk)
	var dirty_revision: int = int(update.get("runtime_revision", -1))
	_assert(
		int(owner_after.get("runtime_revision", -1)) == dirty_revision,
		"Owning chunk must receive the mining dirty contour revision."
	)
	_assert(
		int(east_after.get("runtime_revision", -1)) == dirty_revision,
		"Seam-neighbour chunk must receive the same mining dirty contour revision."
	)
	_assert(
		int(owner_after.get("runtime_revision", -1)) > int(owner_before.get("runtime_revision", -1)),
		"Owning chunk contour revision must advance after seam mining."
	)
	_assert(
		int(east_after.get("runtime_revision", -1)) > int(east_before.get("runtime_revision", -1)),
		"East seam-neighbour contour revision must advance after seam mining."
	)
	_assert_visual_collision_revisions_match(owner_after, "Seam owning chunk")
	_assert_visual_collision_revisions_match(east_after, "Seam east-neighbour chunk")

func _assert_update_common(update: Dictionary, expected_affected_count: int) -> void:
	_assert(not update.is_empty(), "Mining result must include mountain_contour_dirty_update telemetry.")
	_assert(
		int(update.get("affected_chunk_count", -1)) == expected_affected_count,
		"Mining dirty update must report the exact affected chunk count."
	)
	_assert(
		int(update.get("contour_rebuild_usec", -1)) >= 0,
		"Mining dirty update must report non-negative contour_rebuild_usec."
	)
	_assert(
		int(update.get("contour_rebuild_usec", HARD_LIMIT_USEC + 1)) < HARD_LIMIT_USEC,
		"Mining dirty update must stay below the 100 ms hard contour rebuild limit in the smoke fixture."
	)
	_assert(
		int(update.get("visual_apply_usec", -1)) >= 0,
		"Mining dirty update must report non-negative visual_apply_usec."
	)
	_assert(
		int(update.get("collision_apply_usec", -1)) >= 0,
		"Mining dirty update must report non-negative collision_apply_usec."
	)
	_assert(
		int(update.get("runtime_revision", -1)) >= 0,
		"Mining dirty update must report the contour runtime revision applied to affected chunks."
	)

func _assert_visual_collision_revisions_match(snapshot: Dictionary, label: String) -> void:
	var runtime_revision: int = int(snapshot.get("runtime_revision", -1))
	_assert(runtime_revision >= 0, "%s must expose a non-negative runtime revision." % [label])
	_assert(
		int(snapshot.get("visual_revision", -2)) == runtime_revision,
		"%s visual revision must match the runtime revision." % [label]
	)
	_assert(
		int(snapshot.get("collision_revision", -3)) == runtime_revision,
		"%s collision revision must match the runtime revision." % [label]
	)
	_assert(bool(snapshot.get("visual_ready", false)), "%s visual contour must be ready after mining dirty rebuild." % [label])
	_assert(bool(snapshot.get("collision_ready", false)), "%s collision contour must be ready after mining dirty rebuild." % [label])

func _load_chunk(streamer: WorldStreamer, chunk_coord: Vector2i, packet: Dictionary) -> void:
	streamer._chunk_packets[chunk_coord] = packet
	var chunk_view = streamer._ensure_chunk_view(chunk_coord)
	chunk_view.begin_apply(packet)
	while chunk_view.apply_next_batch(WorldRuntimeConstants.PUBLISH_BATCH_SIZE):
		pass
	chunk_view.visible = true
	streamer._rebuild_mountain_contour_runtime_for_chunk(chunk_coord)

func _build_packet(chunk_coord: Vector2i, mountain_locals: Array[Vector2i]) -> Dictionary:
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
	for local_coord: Vector2i in mountain_locals:
		var index: int = WorldRuntimeConstants.local_to_index(local_coord)
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
		walkable_flags[index] = 0
		mountain_ids[index] = 7
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

func _function_body(source: String, function_name: String) -> String:
	var start: int = source.find("func %s" % [function_name])
	if start < 0:
		return ""
	var next: int = source.find("\nfunc ", start + 1)
	if next < 0:
		return source.substr(start)
	return source.substr(start, next - start)

func _shutdown_streamer(streamer: WorldStreamer) -> void:
	if streamer == null:
		return
	if is_instance_valid(streamer):
		streamer._packet_backend.stop()
		if streamer.get_parent() != null:
			streamer.get_parent().remove_child(streamer)
		streamer.free()
		await process_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_errors.append(message)
	_failed = true

func _write_report() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR).replace("\\", "/")
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		push_error("Failed to create report directory %s: %d" % [absolute_dir, err])
		return
	var file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if file == null:
		push_error("Failed to open report %s: %d" % [REPORT_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({
		"ok": not _failed,
		"errors": _errors,
	}, "\t"))
	file.close()
