extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var shadow_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	shadow_image.fill(Color.WHITE)
	var grass_atlas := ImageTexture.create_from_image(shadow_image)
	var grass_material := ShaderMaterial.new()
	var shadow_material := ShaderMaterial.new()
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	var streamer: Node = streamer_script.new() as Node
	_expect(not streamer._chunk_depth_ladder_can_change(Vector2i(0, -4), 0, 3),
		"far north-clamped chunks must skip an unchanged anchor move")
	_expect(not streamer._chunk_depth_ladder_can_change(Vector2i(0, 4), 0, 3),
		"far south-clamped chunks must skip an unchanged anchor move")
	_expect(streamer._chunk_depth_ladder_can_change(Vector2i.ZERO, 0, 3),
		"a chunk intersecting the linear depth window must update")
	_expect(streamer._chunk_depth_ladder_can_change(Vector2i(0, -4), -400, 3),
		"a teleport across clamp bands must update the crossed chunk")
	var coord := Vector2i(5, 3)
	var epoch: int = 7
	var revision: int = 23
	streamer._generation_epoch = epoch
	streamer._grass_scatter_revision_by_chunk[coord] = revision

	var view := ChunkView.new()
	streamer.add_child(view)
	view.configure(coord)
	var packet: Dictionary = _build_packet(coord)
	view.begin_apply(packet, true, false, false)
	_expect(view._water_fill_sync_pending,
		"cold publication must defer water-fill setup out of begin_apply")
	while view.apply_next_batch(64):
		pass
	_expect(not view._water_fill_sync_pending,
		"first terrain apply callback must consume deferred water-fill setup")
	_expect(view.is_terrain_cell_presentation_committed(),
		"terrain cells must commit before the exact-cache check")
	_expect(view.stage_grass_scatter_result(_build_grass_result(coord, epoch, revision)),
		"fresh grass result must stage")
	var guard: int = 0
	while view.has_pending_grass_scatter_visual() and guard < 80:
		_expect(
			view.apply_pending_grass_scatter_visual_phase(
				grass_atlas,
				grass_material,
				grass_atlas,
				shadow_material,
				null,
				null,
				true,
			),
			"every staged grass phase must advance",
		)
		guard += 1
	_expect(guard >= 7 and guard < 16,
		"grass upload must phase real GPU mutations without 64 empty callbacks")
	_expect(view.is_grass_scatter_presentation_committed(), "grass transaction must commit")
	var state_before: Dictionary = view.get_grass_scatter_debug_state()
	_expect(int(state_before.get("instance_count", 0)) == 1, "test grass instance must exist")
	_expect(bool(state_before.get("visible", false)), "committed grass must be visible")
	_expect(int(state_before.get("albedo_draw_layer_count", 0)) == 1,
		"single-stripe fixture must expose one grass draw layer")
	_expect(int(state_before.get("consolidated_shadow_draw_layer_count", 0)) == 1,
		"full-LOD fixture must expose one consolidated directional-shadow layer")
	_expect(int(state_before.get("legacy_shadow_draw_layer_count", -1)) == 0,
		"full-LOD fixture must not expose a per-stripe directional-shadow draw")

	var layer: MultiMeshInstance2D = view._grass_scatter_layers[3]
	_expect(layer != null and layer.multimesh != null, "grass stripe must own a MultiMesh")
	var view_id: int = view.get_instance_id()
	var layer_id: int = layer.get_instance_id()
	var multimesh_rid: RID = layer.multimesh.get_rid()
	var directional_shadow_rid: RID = view._grass_directional_shadow_layer.multimesh.get_rid()
	var cache_hits_before: int = streamer._hot_chunk_view_cache_hit_count_total
	var preserve_hits_before: int = streamer._hot_chunk_view_grass_preserve_hit_count_total

	# Cache preparation must clear coordinate-bound masks, including dirty flags,
	# without touching the validated grass graph. Empty mask texture allocations
	# stay bounded by the same hot-view cap and must survive for update(), never
	# for display of stale pixels.
	var mask_image := Image.create(8, 8, false, Image.FORMAT_L8)
	mask_image.fill(Color.WHITE)
	view._mountain_top_mask_texture = ImageTexture.create_from_image(mask_image)
	view._mountain_foothill_mask_texture = ImageTexture.create_from_image(mask_image)
	view._mountain_foothill_mask_width = 8
	view._mountain_foothill_mask_height = 8
	view._mountain_foothill_mask_step_px = 1.0
	view._terrain_edge_mask_texture = ImageTexture.create_from_image(mask_image)
	var mountain_texture_rid: RID = view._mountain_top_mask_texture.get_rid()
	var foothill_texture_rid: RID = view._mountain_foothill_mask_texture.get_rid()
	var terrain_edge_texture_rid: RID = view._terrain_edge_mask_texture.get_rid()
	view._mountain_top_mask_visual_dirty = true
	view._terrain_edge_mask_visual_dirty = true
	streamer._chunk_views.erase(coord)
	streamer._cache_chunk_view(coord, view)
	_expect(not view.is_mountain_native_mask_visual_pending(),
		"cached view must not retain a pending mountain visual")
	_expect(not view._terrain_edge_mask_visual_dirty,
		"cached view must not retain a pending terrain-edge visual")
	_expect(view._mountain_top_mask_texture != null \
			and view._mountain_top_mask_texture.get_rid() == mountain_texture_rid,
		"hot cache must retain the empty mountain texture allocation")
	_expect(view._mountain_foothill_mask_texture != null \
			and view._mountain_foothill_mask_texture.get_rid() == foothill_texture_rid,
		"hot cache must retain the empty foothill texture allocation")
	_expect(view._terrain_edge_mask_texture != null \
			and view._terrain_edge_mask_texture.get_rid() == terrain_edge_texture_rid,
		"hot cache must retain the empty terrain-edge texture allocation")
	_expect(view._mountain_foothill_mask_width == 0 \
			and view._terrain_edge_mask_width == 0,
		"retained GPU allocations must not retain coordinate-bound mask state")

	var cached: Dictionary = streamer._take_cached_chunk_view(coord)
	var reused: ChunkView = cached.get("view", null) as ChunkView
	_expect(reused.get_instance_id() == view_id, "exact cache hit must reuse the same ChunkView")
	_expect(streamer._hot_chunk_view_cache_hit_count_total == cache_hits_before + 1,
		"exact cache hit telemetry must increment")
	var preserve_grass: bool = streamer._can_preserve_cached_chunk_view_grass(cached, coord)
	_expect(preserve_grass, "matching epoch and revision must preserve grass")
	var preserve_terrain: bool = streamer._can_preserve_cached_chunk_view_terrain(cached, coord)
	_expect(preserve_terrain, "matching epoch and revision must preserve terrain cells")
	_expect(streamer._hot_chunk_view_grass_preserve_hit_count_total == preserve_hits_before + 1,
		"validated grass-preserve telemetry must increment")

	reused.begin_apply(packet, true, false, preserve_grass, preserve_terrain)
	_expect(not reused._water_fill_sync_pending,
		"exact terrain reuse must preserve water-fill without another sync")
	layer = reused._grass_scatter_layers[3]
	_expect(reused.is_grass_scatter_presentation_committed(),
		"exact reuse must not dirty the committed grass transaction")
	_expect(layer.get_instance_id() == layer_id, "exact reuse must keep the same grass layer")
	_expect(layer.multimesh.get_rid() == multimesh_rid,
		"exact reuse must keep the same GPU MultiMesh RID")
	_expect(reused._grass_directional_shadow_layer.multimesh.get_rid() == directional_shadow_rid,
		"exact reuse must keep the consolidated directional-shadow MultiMesh RID")
	_expect(streamer._pending_grass_scatter_visual_upload_chunks.is_empty(),
		"exact reuse must not enqueue a grass re-upload")
	_expect(streamer._grass_scatter_inflight_chunks.is_empty(),
		"exact reuse must not enqueue grass recompute")
	_expect(not reused.apply_next_batch(64),
		"exact terrain reuse must skip the TileMapPattern rebuild")
	_expect(reused.is_terrain_cell_presentation_committed(),
		"exact terrain reuse must remain committed")

	# A changed revision may reuse allocations, but never their presentation.
	streamer._chunk_views.erase(coord)
	streamer._cache_chunk_view(coord, reused)
	streamer._grass_scatter_revision_by_chunk[coord] = revision + 1
	var stale_cached: Dictionary = streamer._take_cached_chunk_view(coord)
	var stale_reuse: ChunkView = stale_cached.get("view", null) as ChunkView
	var preserve_stale_grass: bool = streamer._can_preserve_cached_chunk_view_grass(
		stale_cached,
		coord,
	)
	var preserve_stale_terrain: bool = streamer._can_preserve_cached_chunk_view_terrain(
		stale_cached,
		coord,
	)
	_expect(not preserve_stale_grass, "revision mismatch must reject grass preservation")
	_expect(not preserve_stale_terrain, "revision mismatch must reject terrain preservation")
	stale_reuse.begin_apply(packet, true, false, false)
	var stale_state: Dictionary = stale_reuse.get_grass_scatter_debug_state()
	_expect(bool(stale_state.get("pending", false)), "stale grass must become pending")
	_expect(not bool(stale_state.get("visible", true)),
		"stale grass must be hidden immediately, before the upload dispatcher runs")
	_expect(stale_reuse._grass_scatter_layers[3].multimesh.get_rid() == multimesh_rid,
		"rejected presentation may retain its allocation for overwrite")

	# Evicting a partial transaction must release its unbudgeted envelope/GPU
	# fragments. A subsequent non-exact reuse must still inherit the current
	# player-relative depth anchor before any hot object layer can be adopted.
	_expect(stale_reuse.stage_grass_scatter_result(
		_build_grass_result(coord, epoch, revision + 1),
	), "stale view must accept its replacement grass transaction")
	for _phase: int in range(5):
		stale_reuse.apply_pending_grass_scatter_visual_phase(
			grass_atlas,
			grass_material,
			grass_atlas,
			shadow_material,
			null,
			null,
			true,
		)
	streamer._cache_chunk_view(coord, stale_reuse)
	_expect(stale_reuse._pending_grass_scatter_result.is_empty(),
		"hot cache must release a partial grass CPU envelope")
	_expect(stale_reuse._grass_scatter_apply_phase == 0,
		"hot cache must cancel a partial grass phase machine")
	_expect(stale_reuse._grass_scatter_layers[3].multimesh == null,
		"hot cache must release partial grass GPU buffers")
	_expect(stale_reuse._grass_directional_shadow_layer.multimesh == null,
		"hot cache must release a partial consolidated shadow GPU buffer")
	var recycled_coord := coord + Vector2i.RIGHT
	streamer._ladder_anchor_stripe = 37
	var recycled: ChunkView = streamer._ensure_chunk_view(recycled_coord)
	_expect(recycled == stale_reuse, "non-exact cache reuse must recycle the prepared view")
	_expect(recycled._applied_ladder_anchor_stripe == 37,
		"non-exact cache reuse must seed the current depth anchor independently of grass")
	streamer._chunk_views.erase(recycled_coord)

	# A transient worker failure must never poison the immutable result cache.
	var failure_revision: int = revision + 1
	streamer._player_chunk_coord = coord
	streamer._current_stream_radius_chunks = 1
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var source_coord := coord + Vector2i(offset_x, offset_y)
			streamer._chunk_packets[source_coord] = _build_packet(source_coord)
	streamer._grass_scatter_inflight_chunks[coord] = failure_revision
	streamer._grass_scatter_backend._completed_grass_scatter_buffers.append({
		"success": false,
		"message": "synthetic transient grass failure",
		"target_chunk": coord,
		"epoch": epoch,
		"revision": failure_revision,
	})
	streamer._drain_completed_grass_scatter_buffers(1)
	_expect(not streamer._grass_scatter_results_by_chunk.has(coord),
		"failed grass output must not enter the live result cache")
	_expect(not streamer._warm_grass_scatter_cache.has(coord),
		"failed grass output must not enter the warm result cache")
	var retry_state: Dictionary = streamer._grass_scatter_retry_by_chunk.get(coord, { }) as Dictionary
	_expect(int(retry_state.get("failure_count", 0)) == 1,
		"failed grass output must schedule bounded retry state")
	_expect(int(retry_state.get("not_before_msec", 0)) > Time.get_ticks_msec(),
		"grass retry must use backoff instead of a tight worker loop")
	streamer._request_grass_scatter_build(coord)
	_expect(not streamer._grass_scatter_inflight_chunks.has(coord),
		"grass retry must not requeue before its backoff deadline")
	retry_state["not_before_msec"] = 0
	streamer._grass_scatter_retry_by_chunk[coord] = retry_state
	streamer._retry_failed_grass_scatter_builds(1)
	_expect(streamer._grass_scatter_inflight_chunks.has(coord),
		"expired grass backoff must be driven into a real worker retry")

	# The finite north edge has only six real packet sources. Its three explicit
	# native void slots must not turn publication into an impossible 3x3 wait.
	var edge_coord := Vector2i(5, 0)
	for source_y: int in range(0, 2):
		for source_x: int in range(edge_coord.x - 1, edge_coord.x + 2):
			var source_coord := Vector2i(source_x, source_y)
			streamer._chunk_packets[source_coord] = _build_packet(source_coord)
	_expect(streamer._has_loaded_chunk_halo_sources(edge_coord),
		"finite world edge must treat out-of-bounds halo sources as ready void")
	var edge_halo: Dictionary = streamer._build_combined_chunk_halo_fields(edge_coord, 8)
	_expect(bool(edge_halo.get("success", false)),
		"finite world edge must build a combined native halo with explicit void slots")

	_assert_directional_shadow_layer_count_contract(
		grass_atlas,
		grass_material,
		shadow_material,
	)

	# This synthetic streamer is intentionally never added to SceneTree, so its
	# normal _exit_tree() backend stop cannot run. Drain the worker explicitly and
	# release test-only render resources before quitting to keep leak diagnostics
	# meaningful for production objects.
	streamer._world_compute_backend.stop()
	streamer.free()
	grass_atlas = null
	grass_material = null
	shadow_material = null
	shadow_image = null
	await process_frame
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	print("grass_hot_chunk_view_cache_smoke_test: PASS")
	quit(0)


func _build_packet(coord: Vector2i) -> Dictionary:
	var terrain_ids := PackedInt32Array()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_ids.fill(WorldRuntimeConstants.TERRAIN_PLAINS_GROUND)
	var terrain_atlas_indices := PackedInt32Array()
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var walkable_flags := PackedByteArray()
	walkable_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	walkable_flags.fill(1)
	var lake_flags := PackedByteArray()
	lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_ids := PackedInt32Array()
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_flags := PackedByteArray()
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	var mountain_atlas_indices := PackedInt32Array()
	mountain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	return {
		"chunk_coord": coord,
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


func _build_grass_result(coord: Vector2i, epoch: int, revision: int) -> Dictionary:
	var bucket_buffers: Array = []
	for stripe_index: int in range(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK):
		bucket_buffers.append(PackedFloat32Array())
	bucket_buffers[3] = PackedFloat32Array([
		1.0, 0.0, 0.0, 64.0,
		0.0, 1.0, 0.0, 64.0,
		1.0, 1.0, 1.0, 1.0,
	])
	return {
		"success": true,
		"target_chunk": coord,
		"epoch": epoch,
		"revision": revision,
		"instance_count": 1,
		"bucket_buffers": bucket_buffers,
		"directional_shadow_buffer": bucket_buffers[3],
		"shadow_buffer": PackedFloat32Array(),
		"spore_buffer": PackedFloat32Array(),
		"buffer_float_count": 24,
		"payload_bytes": 96,
		"non_empty_bucket_count": 1,
	}


func _assert_directional_shadow_layer_count_contract(
		grass_atlas: Texture2D,
		grass_material: ShaderMaterial,
		shadow_material: ShaderMaterial,
) -> void:
	var full_lod_view := ChunkView.new()
	root.add_child(full_lod_view)
	full_lod_view.configure(Vector2i.ZERO)
	full_lod_view.begin_apply(_build_packet(Vector2i.ZERO), true, false, false)
	full_lod_view.seed_mid_ladder_z(31)
	var dense_result: Dictionary = _build_dense_grass_result()
	_expect(full_lod_view.stage_grass_scatter_result(dense_result),
		"dense full-LOD grass result must stage")
	var guard: int = 0
	while full_lod_view.has_pending_grass_scatter_visual() and guard < 80:
		full_lod_view.apply_pending_grass_scatter_visual_phase(
			grass_atlas,
			grass_material,
			grass_atlas,
			shadow_material,
			null,
			null,
			true,
		)
		guard += 1
	_expect(guard < 80, "dense full-LOD grass transaction must complete")
	var full_state: Dictionary = full_lod_view.get_grass_scatter_debug_state()
	_expect(int(full_state.get("albedo_draw_layer_count", 0)) == 64,
		"dense fixture must retain all 64 exact albedo depth stripes")
	_expect(int(full_state.get("directional_shadow_draw_layer_count", 0)) == 1,
		"64 albedo stripes must collapse to one directional-shadow draw layer")
	_expect(int(full_state.get("grass_and_directional_shadow_draw_layer_count", 0)) == 65,
		"full-LOD layer proof must reduce the old 128 draw layers to 65")
	_expect(int(full_state.get("legacy_shadow_draw_layer_count", -1)) == 0,
		"consolidated mode must leave legacy shadow draw layers hidden")
	var ladder_state: Dictionary = full_state.get("depth_ladder", { }) as Dictionary
	_expect(int(ladder_state.get("registered_item_count", 0)) == 64,
		"consolidation must not remove or merge exact albedo ladder stripes")
	_expect(full_lod_view._grass_directional_shadow_layer.z_index \
			== WorldRuntimeConstants.Z_GRASS_SHADOW + 1,
		"consolidated shadow must remain at the exact fixed pre-ladder z")
	_expect(int(dense_result.get("payload_bytes", 0)) == 64 * 12 * 4 * 2,
		"warm-cache payload accounting must include bucket and flat shadow copies")
	full_lod_view.free()

	var fractional_view := ChunkView.new()
	root.add_child(fractional_view)
	fractional_view.configure(Vector2i.ZERO)
	fractional_view.begin_apply(_build_packet(Vector2i.ZERO), true, false, false)
	_expect(fractional_view.stage_grass_scatter_result(dense_result),
		"fractional-LOD compatibility result must stage")
	guard = 0
	while fractional_view.has_pending_grass_scatter_visual() and guard < 80:
		fractional_view.apply_pending_grass_scatter_visual_phase(
			grass_atlas,
			grass_material,
			grass_atlas,
			shadow_material,
			null,
			null,
			false,
		)
		guard += 1
	_expect(guard < 80, "fractional-LOD compatibility transaction must complete")
	var legacy_rid: RID = fractional_view._grass_shadow_atlas_layers[0].multimesh.get_rid()
	fractional_view.set_grass_scatter_lod_fraction(0.5)
	var fractional_state: Dictionary = fractional_view.get_grass_scatter_debug_state()
	_expect(int(fractional_state.get("legacy_shadow_draw_layer_count", 0)) == 64,
		"fractional profile must retain exact per-stripe shadows")
	_expect(int(fractional_state.get("consolidated_shadow_draw_layer_count", -1)) == 0,
		"fractional profile must not publish a consolidated shadow")
	_expect(fractional_view._grass_shadow_atlas_layers[0].multimesh.get_rid() == legacy_rid,
		"zoom LOD must trim the legacy graph without rebuilding its MultiMesh")
	_expect(fractional_view._grass_shadow_atlas_layers[0].multimesh.visible_instance_count == 1,
		"legacy shadow must share the grass stripe's exact LOD count")
	fractional_view.free()


func _build_dense_grass_result() -> Dictionary:
	var buckets: Array = []
	var flat := PackedFloat32Array()
	flat.resize(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK * 12)
	for stripe_index: int in range(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK):
		var instance := PackedFloat32Array([
			1.0, 0.0, 0.0, float(stripe_index * 4),
			0.0, 1.0, 0.0, float(stripe_index * WorldRuntimeConstants.DEPTH_STRIPE_PX),
			1.0, 1.0, 1.0, 1.0,
		])
		buckets.append(instance)
		for element_index: int in range(12):
			flat[stripe_index * 12 + element_index] = instance[element_index]
	var float_count: int = flat.size() * 2
	return {
		"success": true,
		"target_chunk": Vector2i.ZERO,
		"epoch": 1,
		"revision": 1,
		"instance_count": WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK,
		"bucket_buffers": buckets,
		"directional_shadow_buffer": flat,
		"shadow_buffer": PackedFloat32Array(),
		"spore_buffer": PackedFloat32Array(),
		"buffer_float_count": float_count,
		"payload_bytes": float_count * 4,
		"non_empty_bucket_count": WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK,
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
