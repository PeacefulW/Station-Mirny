extends SceneTree

const AssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")
const TreeBatchLayer = preload("res://core/systems/world/layered_tree_batch_layer.gd")
const RockBatchLayer = preload("res://core/systems/world/layered_rock_batch_layer.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")
const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const TREE_FRAME_SIZE: Vector2i = Vector2i(768, 768)
const ROCK_FRAME_SIZE: Vector2i = Vector2i(96, 96)
const BUSH_FRAME_SIZE: Vector2i = Vector2i(128, 128)
const TREE_CHANNELS: Array[String] = [
	"trunk",
	"foliage",
	"shadow",
	"snow_overlay",
	"wind_mask",
	"snow_mask",
	"season_mask",
]
const ROCK_CHANNELS: Array[String] = ["albedo", "shadow", "snow_overlay", "snow_mask"]
const TREE_ATLAS_DIR: String = "res://assets/sprites/flora/atlases/layered_trees"
const ROCK_ATLAS_DIR: String = "res://assets/sprites/decor/atlases/layered_small_rocks"
const BUSH_ATLAS_DIR: String = "res://assets/sprites/flora/atlases/layered_bushes"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_family_atlases(
		AssetCatalog.TREE_SOURCE_DIRS,
		TREE_CHANNELS,
		TREE_ATLAS_DIR,
		AssetCatalog.TREE_COLUMNS,
		TREE_FRAME_SIZE,
	)
	_verify_family_atlases(
		AssetCatalog.ROCK_SOURCE_DIRS,
		ROCK_CHANNELS,
		ROCK_ATLAS_DIR,
		AssetCatalog.ROCK_COLUMNS,
		ROCK_FRAME_SIZE,
	)
	# Bushes ride the tree channel set, packed at their own frame size.
	_verify_family_atlases(
		AssetCatalog.BUSH_SOURCE_DIRS,
		TREE_CHANNELS,
		BUSH_ATLAS_DIR,
		AssetCatalog.BUSH_COLUMNS,
		BUSH_FRAME_SIZE,
	)
	var catalog: AssetCatalog = AssetCatalog.new()
	_expect(catalog.is_ready(), "catalog must prepare before chunk publish")
	_verify_layered_quad_uv_contract(catalog)
	_verify_shared_catalog_single_owner(catalog)
	_expect(catalog.get_catalog_generation() == 8, "catalog generation")
	_expect(AssetCatalog.TREE_METRIC_STRIDE == 8, "tree metric stride")
	_expect(
		catalog.get_tree_native_metrics().size()
				== AssetCatalog.TREE_SOURCE_DIRS.size() * AssetCatalog.TREE_METRIC_STRIDE,
		"tree native metric layout",
	)
	_expect(
		catalog.get_rock_native_metrics().size()
				== AssetCatalog.ROCK_SOURCE_DIRS.size() * AssetCatalog.ROCK_METRIC_STRIDE,
		"rock native metric layout",
	)
	var native_params: PackedFloat32Array = catalog.get_native_params()
	_expect(native_params.size() == 20, "native presentation parameter layout")
	if native_params.size() == 20:
		_expect(is_equal_approx(native_params[0], 4.0), "native position quantization")
		_expect(is_equal_approx(native_params[1], 16.0), "native depth stripe size")
		_expect(is_equal_approx(native_params[2], 64.0), "native depth stripe count")
		_expect(is_equal_approx(native_params[3], 1.0), "native collision width multiplier")
		_expect(is_equal_approx(native_params[4], 1.0), "native collision depth multiplier")
		_expect(is_equal_approx(native_params[5], 34.0), "native collision minimum depth")
		_expect(is_equal_approx(native_params[6], 0.45), "native classic decor depth anchor")
		_expect(is_equal_approx(native_params[7], 2.0), "native spiky atlas bank count")
		_expect(is_equal_approx(native_params[8], 0.96), "native living alpha")
		_expect(is_equal_approx(native_params[9], 0.98), "native spiky alpha")
		_expect(is_equal_approx(native_params[10], 0.42), "native living shadow width scale")
		_expect(is_equal_approx(native_params[11], 0.13), "native living shadow height scale")
		_expect(is_equal_approx(native_params[12], 0.32), "native living shadow Y scale")
		_expect(is_equal_approx(native_params[13], 10.0), "native living shadow minimum width")
		_expect(is_equal_approx(native_params[14], 4.0), "native living shadow minimum height")
		_expect(is_equal_approx(native_params[15], 0.58), "native living shadow alpha")
		_expect(is_equal_approx(native_params[16], 96.0), "native living shadow size divisor")
		_expect(is_equal_approx(native_params[17], 0.36), "native living shadow minimum scale")
		_expect(is_equal_approx(native_params[18], 0.0), "native living policy defaults disabled")
		_expect(is_equal_approx(native_params[19], 0.0), "native spiky policy defaults disabled")

	var native_result: Dictionary = _make_native_result(catalog)
	_verify_native_payload_metadata_rejection(catalog, native_result)
	_verify_chunk_view_staging_does_not_alias_cache(catalog, native_result)
	_verify_duplicate_live_prestage_cannot_starve_queue(catalog, native_result)
	_verify_completed_hot_layer_adopts_directly(catalog, native_result)
	var tree_layer: TreeBatchLayer = TreeBatchLayer.new()
	var rock_layer: RockBatchLayer = RockBatchLayer.new()
	root.add_child(tree_layer)
	root.add_child(rock_layer)
	tree_layer.configure_catalog(catalog)
	rock_layer.configure_catalog(catalog)
	_expect(tree_layer.begin_apply(native_result), "tree begin_apply")
	_expect(rock_layer.begin_apply(native_result), "rock begin_apply")
	_expect(tree_layer.apply_next_batch(1), "tree apply remains staged after first occupied stripe")
	_expect(rock_layer.apply_next_batch(1), "rock apply remains staged after first occupied stripe")
	_expect(
		bool(tree_layer.get_debug_state().get("last_slice_created_slot", false)) \
				and int(tree_layer.get_debug_state().get("next_stripe", -1)) == 0,
		"tree first-use capacity allocation is separate from cursor scan and raw upload",
	)
	_expect(
		bool(rock_layer.get_debug_state().get("last_slice_created_slot", false)) \
				and int(rock_layer.get_debug_state().get("next_stripe", -1)) == 0,
		"rock first-use capacity allocation is separate from cursor scan and raw upload",
	)
	_expect(tree_layer.apply_next_batch(1), "tree allocates its second required stripe slot")
	_expect(rock_layer.apply_next_batch(1), "rock allocates its second required stripe slot")
	_expect(
		bool(tree_layer.get_debug_state().get("last_slice_created_slot", false)) \
				and int(tree_layer.get_debug_state().get("next_stripe", -1)) == 0,
		"tree completes required capacity before raw upload",
	)
	_expect(
		bool(rock_layer.get_debug_state().get("last_slice_created_slot", false)) \
				and int(rock_layer.get_debug_state().get("next_stripe", -1)) == 0,
		"rock completes required capacity before raw upload",
	)
	_expect(tree_layer.apply_next_batch(1), "tree uploads after its allocation phase")
	_expect(rock_layer.apply_next_batch(1), "rock uploads after its allocation phase")
	_expect(
		int(tree_layer.get_debug_state().get("next_stripe", -1)) == 8,
		"tree skips no-op buckets and applies one occupied stripe",
	)
	_expect(
		int(rock_layer.get_debug_state().get("next_stripe", -1)) == 8,
		"rock skips no-op buckets and applies one occupied stripe",
	)
	_drain_apply(tree_layer, rock_layer)

	var tree_debug: Dictionary = tree_layer.get_debug_state()
	var rock_debug: Dictionary = rock_layer.get_debug_state()
	_expect(int(tree_debug.get("instance_count", -1)) == 3, "tree instance count")
	_expect(int(tree_debug.get("active_stripe_count", -1)) == 2, "tree sparse stripe count")
	_expect(
		_count_descendants_of_class(tree_layer, "MultiMeshInstance2D") == 8,
		"tree nodes scale by two stripes, not three objects",
	)
	_expect(int(rock_debug.get("instance_count", -1)) == 3, "rock instance count")
	_expect(int(rock_debug.get("active_stripe_count", -1)) == 2, "rock sparse stripe count")
	_expect(
		_count_descendants_of_class(rock_layer, "MultiMeshInstance2D") == 6,
		"rock nodes scale by two stripes, not three objects",
	)
	_verify_lossless_atlas_filter_contract(tree_layer, "tree")
	_verify_lossless_atlas_filter_contract(rock_layer, "rock")
	_expect(tree_layer.begin_apply(native_result), "tree repeated begin_apply")
	_expect(rock_layer.begin_apply(native_result), "rock repeated begin_apply")
	_drain_apply(tree_layer, rock_layer)
	_expect(
		_count_descendants_of_class(tree_layer, "MultiMeshInstance2D") == 8,
		"tree stripe slots are reused",
	)
	_expect(
		_count_descendants_of_class(rock_layer, "MultiMeshInstance2D") == 6,
		"rock stripe slots are reused",
	)
	_verify_coherent_object_commit(catalog, native_result)
	await process_frame
	if _failures.is_empty():
		print("Layered object batch contract: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
		quit(1)


func _verify_shared_catalog_single_owner(catalog: AssetCatalog) -> void:
	var initial_season: float = catalog.get_season_amount()
	var initial_shadow_length: float = catalog.get_sun_shadow_length_px()
	var initial_shadow_opacity: float = catalog.get_sun_shadow_opacity()
	const WINTER_AMOUNT: float = 0.82
	const SHADOW_LENGTH: float = 96.0
	const SHADOW_OPACITY: float = 0.61
	catalog.set_season_amount(WINTER_AMOUNT)
	catalog.set_sun_lighting(SHADOW_LENGTH, SHADOW_OPACITY)
	var shared_season_uniform: float = float(
		catalog.get_tree_trunk_material().get_shader_parameter("season_amount")
	)
	var shared_shadow_scale: float = float(
		catalog.get_tree_shadow_material().get_shader_parameter("shadow_length_scale")
	)
	var shared_shadow_opacity: float = float(
		catalog.get_tree_shadow_material().get_shader_parameter("shadow_opacity")
	)

	# Model a cold/pool allocation after the global season has already changed.
	# Local defaults must never overwrite catalog-owned shared materials.
	var tree_layer: TreeBatchLayer = TreeBatchLayer.new()
	var rock_layer: RockBatchLayer = RockBatchLayer.new()
	root.add_child(tree_layer)
	root.add_child(rock_layer)
	tree_layer.configure_catalog(catalog)
	rock_layer.configure_catalog(catalog)
	tree_layer.reserve_pool_slots(1)
	rock_layer.reserve_pool_slots(1)
	var tree_state: Dictionary = tree_layer.get_debug_state()
	var rock_state: Dictionary = rock_layer.get_debug_state()
	_expect(
		is_equal_approx(float(tree_state.get("season_amount", -1.0)), WINTER_AMOUNT),
		"new pooled tree layer adopts catalog winter without resetting it",
	)
	_expect(
		is_equal_approx(float(rock_state.get("season_amount", -1.0)), WINTER_AMOUNT),
		"new pooled rock layer adopts catalog winter without resetting it",
	)
	_expect(
		is_equal_approx(
			float(tree_state.get("sun_shadow_length_px", -1.0)),
			SHADOW_LENGTH,
		) and is_equal_approx(
			float(rock_state.get("sun_shadow_opacity", -1.0)),
			SHADOW_OPACITY,
		),
		"new pooled batch layers adopt catalog sun state",
	)

	# These public methods are chunk-local compatibility APIs, not global writers.
	tree_layer.set_season_amount(0.1)
	rock_layer.set_season_amount(0.2)
	tree_layer.set_sun_lighting(0.0, 12.0, 0.05, 0.0)
	rock_layer.set_sun_lighting(0.0, 14.0, 0.07, 0.0)
	_expect(
		is_equal_approx(catalog.get_season_amount(), WINTER_AMOUNT) \
				and is_equal_approx(catalog.get_sun_shadow_length_px(), SHADOW_LENGTH) \
				and is_equal_approx(catalog.get_sun_shadow_opacity(), SHADOW_OPACITY),
		"batch-local state cannot mutate catalog-owned global lighting",
	)
	_expect(
		is_equal_approx(
			float(catalog.get_tree_trunk_material().get_shader_parameter("season_amount")),
			shared_season_uniform,
		) and is_equal_approx(
			float(catalog.get_tree_shadow_material().get_shader_parameter("shadow_length_scale")),
			shared_shadow_scale,
		) and is_equal_approx(
			float(catalog.get_tree_shadow_material().get_shader_parameter("shadow_opacity")),
			shared_shadow_opacity,
		),
		"batch-local setters cannot rewrite shared shader uniforms",
	)
	for source_path: String in [
		"res://core/systems/world/layered_tree_batch_layer.gd",
		"res://core/systems/world/layered_rock_batch_layer.gd",
	]:
		var source: String = FileAccess.get_file_as_string(source_path)
		_expect(
			not source.contains("_catalog.set_season_amount") \
					and not source.contains("_catalog.set_sun_lighting"),
			"batch layer source keeps catalog setters behind the single-owner boundary",
		)
	tree_layer.queue_free()
	rock_layer.queue_free()
	catalog.set_season_amount(initial_season)
	catalog.set_sun_lighting(initial_shadow_length, initial_shadow_opacity)


func _verify_native_payload_metadata_rejection(
		catalog: AssetCatalog,
		native_result: Dictionary,
) -> void:
	for metadata_key: StringName in [&"buffer_float_count", &"payload_bytes"]:
		var corrupted: Dictionary = native_result.duplicate(false)
		corrupted[metadata_key] = int(corrupted.get(metadata_key, 0)) + 4
		var layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
		root.add_child(layer)
		_expect(
			not layer.begin_presentation_result(corrupted, catalog),
			"consumer rejects mismatched %s" % metadata_key,
		)
		var state: Dictionary = layer.get_debug_state()
		_expect(
			str(state.get("native_begin_state", "")) == "FAILED",
			"payload metadata mismatch ends in explicit failed state",
		)
		_expect(
			layer.get_raw_multimesh_upload_count_total() == 0,
			"payload metadata mismatch is rejected before raw GPU upload",
		)
		_expect(
			int(layer.get_hot_cache_reservation_weight().get("payload_bytes", -1)) == 0,
			"failed payload metadata cannot enter cache accounting",
		)
		layer.queue_free()


func _drain_apply(tree_layer: TreeBatchLayer, rock_layer: RockBatchLayer) -> void:
	var tree_has_more: bool = true
	var rock_has_more: bool = true
	var guard: int = 0
	while tree_has_more or rock_has_more:
		if tree_has_more:
			tree_has_more = tree_layer.apply_next_batch(4)
		if rock_has_more:
			rock_has_more = rock_layer.apply_next_batch(4)
		guard += 1
		if guard > 16:
			_failures.append("incremental apply did not finish within 64 stripes")
			return


func _make_native_result(catalog: AssetCatalog) -> Dictionary:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_expect(world_core != null, "WorldCore native class")
	if world_core == null or not world_core.has_method("build_object_presentation_buffers"):
		_expect(false, "native object presentation API")
		return { }
	var result_variant: Variant = world_core.call(
		"build_object_presentation_buffers",
		PackedByteArray([4, 4, 4, 7, 7, 7]),
		PackedByteArray([30, 65, 135, 30, 65, 135]),
		PackedByteArray([30, 31, 255, 30, 31, 255]),
		PackedByteArray([180, 180, 180, 60, 60, 60]),
		PackedByteArray([0, 0, 0, 0, 0, 0]),
		PackedByteArray([0, 6, 9, 0, 1, 9]),
		PackedByteArray([0, 0, 0, 0, 0, 0]),
		PackedByteArray([235, 235, 235, 235, 235, 235]),
		PackedByteArray([64, 64, 64, 64, 64, 64]),
		catalog.get_tree_native_metrics(),
		catalog.get_rock_native_metrics(),
		catalog.get_bush_native_metrics(),
		catalog.get_native_params(),
	)
	_expect(result_variant is Dictionary, "native object result shape")
	if not result_variant is Dictionary:
		return { }
	var result: Dictionary = result_variant as Dictionary
	result["success"] = not result.has("error")
	_expect(bool(result.get("success", false)), "native object result success")
	_expect(int(result.get("tree_instance_count", -1)) == 3, "native tree count")
	_expect(int(result.get("rock_instance_count", -1)) == 3, "native rock count")
	_expect(
		(result.get("tree_collision_records", PackedFloat32Array()) as PackedFloat32Array).size()
				== 3 * 4,
		"native tree collision record stride",
	)
	_expect(
		int(result.get("payload_bytes", -1)) == int(result.get("buffer_float_count", 0)) * 4,
		"native payload bytes",
	)
	var tree_buffers: Array = result.get("tree_atlas_bucket_buffers", []) as Array
	var rock_buffers: Array = result.get("rock_atlas_bucket_buffers", []) as Array
	_expect(tree_buffers.size() == 64, "native tree stripe count")
	_expect(rock_buffers.size() == 64, "native rock stripe count")
	if tree_buffers.size() == 64:
		var stripe_seven: PackedFloat32Array = tree_buffers[7] as PackedFloat32Array
		var stripe_sixty_three: PackedFloat32Array = tree_buffers[63] as PackedFloat32Array
		_expect(stripe_seven.size() == 24, "native tree bucket grouping")
		_expect(stripe_sixty_three.size() == 12, "native tree last stripe grouping")
		if stripe_seven.size() >= 24:
			_expect(is_equal_approx(stripe_seven[3], 122.0), "native q4 half-quantum X decode")
			_expect(is_equal_approx(stripe_seven[0], 768.0 * 0.64), "native fixed tree scale")
			var expected_modulo_frame: float = float(
				6 % AssetCatalog.TREE_SOURCE_DIRS.size(),
			) / 255.0
			_expect(
				is_equal_approx(stripe_seven[20], expected_modulo_frame),
				"native modulo tree atlas frame: expected %.9f, got %.9f"
						% [expected_modulo_frame, stripe_seven[20]],
			)
	return result


func _verify_coherent_object_commit(catalog: AssetCatalog, native_result: Dictionary) -> void:
	var object_layer: WorldObjectPacketLayer = WorldObjectPacketLayer.new()
	root.add_child(object_layer)
	_expect(object_layer.begin_presentation_result(native_result, catalog), "object result begin")
	_expect(not object_layer.visible, "tree staging stays hidden")
	_expect(not object_layer.is_blocking_presentation_ready(), "tree staging is not blocking-ready")
	var saw_disabled_staged_collision: bool = false
	var guard: int = 0
	while object_layer.has_pending_presentation_apply():
		_expect(
			object_layer.apply_next_presentation_slice(4, 1, 4),
			"object staging slice advances",
		)
		var state: Dictionary = object_layer.get_debug_state()
		if not object_layer.is_blocking_presentation_ready():
			_expect(not object_layer.visible, "all objects remain hidden before atomic commit")
			_expect(int(state.get("tree_collision_layer", -1)) == 0, "staged collision stays disabled")
			if int(state.get("tree_collider_count", 0)) > 0:
				saw_disabled_staged_collision = true
		guard += 1
		if guard > 32:
			_failures.append("coherent object apply did not finish")
			return
	var committed: Dictionary = object_layer.get_debug_state()
	_expect(saw_disabled_staged_collision, "collision is built incrementally before commit")
	_expect(not object_layer.visible, "collision-only packet subtree stays hidden after commit")
	_expect(
		int(committed.get("tree_collision_layer", -1)) == 0,
		"prepared collision waits for owning chunk reveal",
	)
	_expect(int(committed.get("tree_collider_count", 0)) == 3, "all tree colliders committed")
	var collision_body: StaticBody2D = object_layer.get_node_or_null(
		"TreeObjectPacketCollisionBody",
	) as StaticBody2D
	_expect(collision_body != null, "tree collision body exists")
	if collision_body != null:
		var owner_ids: PackedInt32Array = collision_body.get_shape_owners()
		_expect(owner_ids.size() == 3, "one shape owner per tree collider")
		for owner_id: int in owner_ids:
			_expect(
				collision_body.shape_owner_get_shape_count(owner_id) == 1
						and collision_body.shape_owner_get_shape(owner_id, 0)
								is RectangleShape2D,
				"tree collision owners use RectangleShape2D",
			)
	_expect(object_layer.is_blocking_presentation_ready(), "coherent commit is blocking-ready")
	_expect(object_layer.is_presentation_complete(), "coherent object presentation completes")
	object_layer.set_blocking_collision_active(true)
	_expect(
		int(object_layer.get_debug_state().get("tree_collision_layer", 0)) == 2,
		"chunk reveal activates prepared tree collision",
	)


func _verify_chunk_view_staging_does_not_alias_cache(
		catalog: AssetCatalog,
		native_result: Dictionary,
) -> void:
	var cached_result: Dictionary = native_result.duplicate(false)
	var view: ChunkView = ChunkView.new()
	root.add_child(view)
	view._object_packet_visual_dirty = true
	_expect(
		view.stage_object_presentation_result(cached_result, catalog),
		"ChunkView accepts an immutable cached staging envelope",
	)
	_expect(view.apply_pending_object_packet_visual(), "ChunkView begins staged object apply")
	_expect(bool(cached_result.get("success", false)), "ChunkView does not clear the cached result Dictionary")
	_expect(
		(cached_result.get("tree_atlas_bucket_buffers", []) as Array).size() == 64,
		"ChunkView preserves cached packed buffers for warm zoom reuse",
	)
	view.queue_free()


func _verify_duplicate_live_prestage_cannot_starve_queue(
		catalog: AssetCatalog,
		native_result: Dictionary,
) -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	_expect(streamer_script != null, "WorldStreamer loads for duplicate prestage proof")
	if streamer_script == null:
		return
	var streamer: Node = streamer_script.new() as Node
	var coord := Vector2i(7, 9)
	streamer._player_chunk_coord = coord
	streamer._current_stream_radius_chunks = 6
	streamer._layered_object_asset_catalog = catalog
	streamer._object_presentation_results_by_chunk[coord] = native_result
	var view: ChunkView = ChunkView.new()
	view.configure(coord)
	view._object_packet_visual_dirty = true
	streamer.add_child(view)
	streamer._chunk_views[coord] = view
	_expect(
		view.stage_object_presentation_result(native_result, catalog),
		"live view owns its first immutable presentation envelope",
	)
	streamer._pending_hot_object_prestage_set[coord] = true
	streamer._pending_hot_object_prestage_chunks.append(coord)
	streamer._queue_object_packet_visual_upload(coord)
	_expect(
		streamer._stage_pending_hot_object_presentation(coord),
		"duplicate live prestage is recognized as already staged",
	)
	_expect(
		not streamer._pending_hot_object_prestage_set.has(coord),
		"duplicate prestage half is consumed",
	)
	_expect(
		streamer._pending_object_packet_visual_upload_set.has(coord),
		"in-progress live transaction keeps its execution token",
	)
	_expect(
		view.apply_pending_object_packet_visual(),
		"focused live transaction advances after duplicate prestage cleanup",
	)
	_expect(
		view.is_object_presentation_complete(),
		"focused live transaction completes instead of starving the queue",
	)
	streamer.free()


func _verify_completed_hot_layer_adopts_directly(
		catalog: AssetCatalog,
		native_result: Dictionary,
) -> void:
	var streamer_script: Script = load("res://core/systems/world/world_streamer.gd") as Script
	_expect(streamer_script != null, "WorldStreamer loads for direct hot-adopt proof")
	if streamer_script == null:
		return
	var streamer: Node = streamer_script.new() as Node
	var coord := Vector2i(3, 2)
	var revision: int = 41
	streamer._generation_epoch = 7
	streamer._object_presentation_revision_by_chunk[coord] = revision
	streamer._object_presentation_results_by_chunk[coord] = native_result
	var view: ChunkView = ChunkView.new()
	view.configure(coord)
	view.visible = false
	streamer.add_child(view)
	streamer._chunk_views[coord] = view
	var layer := WorldObjectPacketLayer.new()
	streamer._ensure_hot_object_presentation_root().add_child(layer)
	streamer._configure_hot_object_layer(layer, coord)
	_expect(
		layer.begin_presentation_result(native_result, catalog),
		"direct hot-adopt proof begins a native transaction",
	)
	var guard: int = 0
	while layer.has_pending_presentation_apply():
		layer.apply_next_presentation_slice(4, 32, 4)
		guard += 1
		if guard > 64:
			_failures.append("direct hot-adopt transaction did not complete")
			streamer.free()
			return
	_expect(layer.is_hot_cache_eligible(), "completed hot layer is transferable")
	var weight: Dictionary = layer.get_hot_cache_weight()
	streamer._add_hot_object_entry(
		coord,
		{
			"layer": layer,
			"epoch": streamer._generation_epoch,
			"revision": revision,
			"catalog_generation": catalog.get_catalog_generation(),
			"ready": false,
			"gpu_buffer_bytes": int(weight.get("gpu_buffer_bytes", 0)),
			"canvas_item_count": int(weight.get("canvas_item_count", 0)),
			"collider_count": int(weight.get("collider_count", 0)),
		},
	)
	var layer_id: int = layer.get_instance_id()
	var upload_count: int = layer.get_raw_multimesh_upload_count_total()
	var world_parent: Node = layer.get_parent()
	var world_position: Vector2 = layer.position
	_expect(
		streamer._promote_hot_object_presentation(coord, view),
		"COMPLETE live transaction adopts directly without cache-ready round trip",
	)
	_expect(
		view._object_packet_layer != null \
				and view._object_packet_layer.get_instance_id() == layer_id,
		"direct adopt preserves the exact GPU-resident layer",
	)
	_expect(
		layer.get_parent() == world_parent \
				and layer.position == world_position \
				and world_position == WorldRuntimeConstants.chunk_origin_px(coord),
		"direct adopt preserves world parent/transform without a CanvasItem reparent",
	)
	_expect(not layer.visible, "externally-parented objects remain hidden behind reveal gate")
	view.set_object_collision_active(true)
	_expect(layer.visible, "atomic reveal releases externally-parented object visibility")
	_expect(
		view._object_packet_layer.get_raw_multimesh_upload_count_total() == upload_count,
		"direct adopt performs zero new raw MultiMesh uploads",
	)
	_expect(
		not streamer._hot_object_presentation_layers.has(coord),
		"direct adopt removes cache accounting exactly once",
	)
	streamer.free()


func _verify_family_atlases(
		source_dirs: Array[String],
		channels: Array[String],
		atlas_dir: String,
		columns: int,
		frame_size: Vector2i,
) -> void:
	for channel: String in channels:
		var atlas := Image.new()
		var atlas_path: String = "%s/%s.png" % [atlas_dir, channel]
		var atlas_error: Error = atlas.load(ProjectSettings.globalize_path(atlas_path))
		_expect(atlas_error == OK, "atlas exists: %s" % atlas_path)
		if atlas_error != OK:
			continue
		for variant_index: int in range(source_dirs.size()):
			var source := Image.new()
			var source_path: String = "%s/%s.png" % [source_dirs[variant_index], channel]
			var source_error: Error = source.load(ProjectSettings.globalize_path(source_path))
			_expect(source_error == OK, "source exists: %s" % source_path)
			if source_error != OK:
				continue
			if source.get_format() != Image.FORMAT_RGBA8:
				source.convert(Image.FORMAT_RGBA8)
			# A family may pack at a smaller frame than it was baked at; runtime UVs
			# are normalised per frame, so the check resamples the source the same
			# way the atlas builder does.
			if frame_size != source.get_size():
				source.resize(frame_size.x, frame_size.y, Image.INTERPOLATE_LANCZOS)
			var origin := Vector2i(
				(variant_index % columns) * frame_size.x,
				floori(float(variant_index) / float(columns)) * frame_size.y,
			)
			var atlas_frame: Image = atlas.get_region(Rect2i(origin, frame_size))
			_expect(
				atlas_frame.get_data() == source.get_data(),
				"pixel-exact atlas frame: %s variant %d" % [channel, variant_index],
			)


func _verify_layered_quad_uv_contract(catalog: AssetCatalog) -> void:
	var mesh: Mesh = catalog.get_unit_quad_mesh()
	_expect(mesh is QuadMesh, "layered objects preserve the shared primitive quad")
	for shader_path: String in [
		"res://assets/shaders/layered_tree_trunk_batch.gdshader",
		"res://assets/shaders/layered_tree_foliage_batch.gdshader",
		"res://assets/shaders/layered_object_albedo_batch.gdshader",
		"res://assets/shaders/layered_object_snow_batch.gdshader",
	]:
		var source: String = FileAccess.get_file_as_string(shader_path)
		_expect(
			"vec2 sprite_uv(vec2 mesh_uv)" in source \
					and "1.0 - mesh_uv.y" in source \
					and "sprite_uv(UV)" in source,
			"layered QuadMesh shader converts V to PNG orientation: %s" % shader_path,
		)


func _count_descendants_of_class(parent: Node, class_name_to_find: String) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child.is_class(class_name_to_find):
			count += 1
		count += _count_descendants_of_class(child, class_name_to_find)
	return count


func _verify_lossless_atlas_filter_contract(parent: Node, family: String) -> void:
	for child: Node in parent.get_children():
		if child is MultiMeshInstance2D:
			_expect(
				(child as MultiMeshInstance2D).texture_filter
						== CanvasItem.TEXTURE_FILTER_LINEAR,
				"%s atlas sampler must not request an absent mip chain" % family,
			)
		_verify_lossless_atlas_filter_contract(child, family)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
