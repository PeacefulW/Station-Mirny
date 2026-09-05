extends SceneTree
## Smoke-тест dev-сцены «копаем рантайм-гору»: сцена должна подняться на
## настоящем world_runtime_v0, найти гору, поставить игрока к её краю и
## закоммитить копок публичным путём try_harvest_at_world.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_READY_FRAMES: int = 3000
const MAX_SETTLE_FRAMES: int = 1800

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Mountain runtime dig dev scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("failed", false)) or bool(snapshot.get("ready", false)):
			break
	_assert(
		not bool(snapshot.get("failed", false)),
		"Dev scene must not fail: %s" % str(snapshot.get("fail_reason", "")),
	)
	_assert(bool(snapshot.get("ready", false)), "Dev scene must become ready (spawn + teleport).")
	if not bool(snapshot.get("ready", false)):
		quit(1)
		return
	for _frame: int in range(MAX_SETTLE_FRAMES):
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if _is_settled(snapshot):
			break
		await process_frame
	if not _is_settled(snapshot):
		print("mountain_runtime_dig_dev_scene_smoke_test unsettled snapshot: ", snapshot)
	_assert(_is_settled(snapshot), "Mountain native masks must settle near the dig spot.")
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	_assert(
		bool(native.get("native_mask_runtime_enabled", false)),
		"Dev scene must run on native mountain masks (runtime presentation).",
	)
	_assert(
		int(native.get("ready_native_mask_chunk_count", 0)) > 0,
		"Dev scene must have ready native mountain mask chunks.",
	)
	var target_terrain_id: int = int(snapshot.get("target_terrain_id", -1))
	_assert(
		target_terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or target_terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
		"Dig target must be a runtime mountain wall or foot tile.",
	)
	_assert(
		int(snapshot.get("scanned_foot_tile_count", 0)) > 0,
		"Scan must see mountain foot tiles (foot как в рантайме).",
	)
	_assert(
		bool(snapshot.get("stand_walkable", false)),
		"Player stand tile next to the mountain must be walkable.",
	)
	var streamer: Node = scene.get("_streamer") as Node
	var player: Node2D = scene.get("_player") as Node2D
	var mountain_tile: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
	var target_world: Vector2 = WorldRuntimeConstants.tile_to_world_center(mountain_tile)
	var torch_mask_before: Dictionary = streamer.call(
		"get_mountain_torch_shadow_field_mask",
		target_world,
		512.0,
	) as Dictionary
	_assert(
		bool(torch_mask_before.get("ready", false))
				and not str(torch_mask_before.get("signature", "")).is_empty(),
		"Torch shadow field must have a stable pre-dig cache identity.",
	)
	var visual_before: Dictionary = _capture_immediate_visual_state(streamer, mountain_tile)
	print(
		"mountain_runtime_dig_dev_scene_smoke_test target=%s local=%s overlapping_views=%d" % [
			str(mountain_tile),
			str(WorldRuntimeConstants.tile_to_local(mountain_tile)),
			visual_before.size(),
		],
	)
	_assert(
		not visual_before.is_empty(),
		"Real runtime mining must begin with a visible live mountain mask.",
	)
	var dig_started_usec: int = Time.get_ticks_usec()
	var dig: Dictionary = scene.call("debug_dig_target_once") as Dictionary
	var dig_elapsed_ms: float = float(Time.get_ticks_usec() - dig_started_usec) / 1000.0
	print(
		"mountain_runtime_dig_dev_scene_smoke_test interaction_ms=%.3f" % dig_elapsed_ms,
	)
	_assert(
		dig_elapsed_ms <= 1000.0 / 60.0,
		"The complete mining interaction transaction must fit one 60 FPS frame.",
	)
	_assert(
		bool(dig.get("success", false)),
		"Dig into the runtime mountain must commit a harvest: %s" % str(dig),
	)
	_assert(
		bool(dig.get("walkable_after", false)),
		"Mined mountain tile center must become walkable (вкопались в гору).",
	)
	var visual_after: Dictionary = _capture_immediate_visual_state(streamer, mountain_tile)
	_assert(
		_did_immediate_mountain_visual_change(visual_before, visual_after),
		"The exact organic mountain mask must change in the same interaction tick.",
	)
	var lighting_after: Dictionary = _capture_immediate_cave_lighting_state(
		streamer,
		mountain_tile,
	)
	_assert(
		int(lighting_after.get("ready_chunk_count", 0)) > 0,
		"Cave darkness textures must be publishable in the same interaction tick.",
	)
	_assert(
		int(lighting_after.get("dug_chunk_count", 0)) \
				== int(lighting_after.get("ready_chunk_count", -1)),
		"Every immediate cave-lighting source must contain the current dug halo.",
	)
	_assert(
		bool(lighting_after.get("full_native_still_pending", false)),
		"The immediate cave-lighting assertion must run before the full worker result.",
	)
	var torch_mask: Dictionary = streamer.call(
		"get_mountain_torch_shadow_field_mask",
		target_world,
		512.0,
	) as Dictionary
	_assert(
		bool(torch_mask.get("ready", false)) \
				and not bool(torch_mask.get("pending", false)) \
				and int(torch_mask.get("solid_sample_count", 0)) > 0,
		"Torch occlusion must use the current live mask while the full worker is pending: mask=%s lighting=%s" \
				% [str(torch_mask), str(lighting_after)],
	)
	_assert(
		str(torch_mask.get("signature", "")) \
				!= str(torch_mask_before.get("signature", "")),
		"Live mining must invalidate torch occlusion without an F off/on toggle.",
	)
	var native_immediate: Dictionary = streamer.call(
		"get_mountain_mask_runtime_debug_state",
	) as Dictionary
	_assert(
		int(native_immediate.get("interactive_skylight_queue_count", -1)) == 0,
		"Mining must never enqueue exact skylight work on the main thread.",
	)
	_assert(
		await _wait_for_worker_skylight(streamer, mountain_tile, 600),
		"The background mountain worker must publish exact cave skylight for every affected view.",
	)
	var organic_settled: bool = await _wait_for_organic_native_settle(
		streamer,
		mountain_tile,
	)
	_assert(organic_settled, "The authoritative native mountain rebuild must settle after mining.")
	var visual_final: Dictionary = _capture_immediate_visual_state(streamer, mountain_tile)
	_assert(
		_immediate_patch_matches_authoritative_native(visual_after, visual_final),
		"Immediate mining patch must already equal the authoritative organic contour.",
	)
	var native_after_dig: Dictionary = streamer.call(
		"get_mountain_mask_runtime_debug_state",
	) as Dictionary
	print(
		"mountain_runtime_dig_dev_scene_smoke_test organic_patch_ms=%.3f" % float(
			native_after_dig.get("mountain_incremental_dig_patch_elapsed_ms_last", 999.0),
		),
	)
	_assert(
		float(native_after_dig.get("mountain_incremental_dig_patch_elapsed_ms_last", 999.0)) \
				<= 1000.0 / 60.0,
		"Incremental organic mining patch must fit one 60 FPS frame.",
	)
	# Walk into the tile immediately after the public dig. This reproduces the
	# player's report: collision may already be open, but the roof must not wait
	# behind background mountain uploads for seconds.
	player.global_position = WorldRuntimeConstants.tile_to_world_center(mountain_tile)
	var cover_probe: Dictionary = streamer.call(
		"resolve_mountain_cover_at_world",
		player.global_position,
		0,
	) as Dictionary
	streamer.call(
		"set_active_mountain_component",
		int(cover_probe.get("mountain_id", 0)),
		int(cover_probe.get("component_id", 0)),
	)
	var first_reveal_frame: int = -1
	var fully_open_frame: int = -1
	for reveal_frame: int in range(36):
		await process_frame
		var blend: float = float(streamer.get("_mountain_roof_reveal_blend"))
		if first_reveal_frame < 0 and blend > 0.001:
			first_reveal_frame = reveal_frame + 1
		if blend >= 0.999:
			fully_open_frame = reveal_frame + 1
			break
	print(
		"mountain_runtime_dig_dev_scene_smoke_test roof_response first=%d full=%d" % [
			first_reveal_frame,
			fully_open_frame,
		],
	)
	_assert(
		first_reveal_frame > 0 and first_reveal_frame <= 8,
		"Mountain roof reveal must begin within 8 rendered frames after entry.",
	)
	_assert(
		fully_open_frame > 0 and fully_open_frame <= 24,
		"Mountain roof must complete its authored 150 ms reveal within 24 frames.",
	)
	scene.queue_free()
	await process_frame
	if _failed:
		quit(1)
		return
	print("mountain_runtime_dig_dev_scene_smoke_test: OK")
	quit(0)

func _is_settled(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("ready", false)):
		return false
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	if native.is_empty():
		return false
	if int(native.get("missing_mountain_chunk_count", 99)) > 0:
		return false
	# Игрок стоит вплотную к горе, поэтому маски обязаны появиться:
	# нулевой счётчик означает, что desired-набор ещё не пересчитан после
	# телепорта, а не «гор нет».
	if int(native.get("ready_native_mask_chunk_count", 0)) <= 0:
		return false
	# The source ring continuously prefetches native masks beyond this local
	# interaction.  A request elsewhere in that ring is not a blocker for the
	# already-published target beside the player; waiting for the global inflight
	# flag made this smoke test time out before it ever attempted a dig.
	if bool(native.get("dirty", false)):
		return false
	if int(native.get("native_mask_visual_upload_queue_count", 0)) > 0 \
			or int(native.get("native_mask_visual_pending_count", 0)) > 0:
		return false
	return bool(snapshot.get("stand_walkable", false))


func _capture_immediate_visual_state(streamer: Node, world_tile: Vector2i) -> Dictionary:
	var state: Dictionary = { }
	if streamer == null:
		return state
	var affected_variant: Variant = streamer.call(
		"_build_mountain_native_mask_dirty_chunks_for_tile",
		world_tile,
	)
	for coord_variant: Variant in affected_variant as Array:
		var coord: Vector2i = coord_variant as Vector2i
		var views: Dictionary = streamer.get("_chunk_views") as Dictionary
		var view: Node = views.get(coord, null) as Node
		if view == null or not is_instance_valid(view):
			continue
		var image: Image = view.get("_mountain_top_mask_image") as Image
		if image == null or image.is_empty():
			continue
		var debug: Dictionary = view.call("get_mountain_native_mask_debug_state") as Dictionary
		state[coord] = {
			"image_hash": hash(image.get_data()),
			"mask_hash": hash(view.get("_mountain_top_mask_bytes")),
			"mask_bytes": (view.get("_mountain_top_mask_bytes") as PackedByteArray).duplicate(),
			"patch_count": int(debug.get("organic_dig_patch_count", 0)),
			"patch_min": debug.get("organic_dig_patch_min", Vector2i.ZERO),
			"patch_size": debug.get("organic_dig_patch_size", Vector2i.ZERO),
			"visual_dirty": bool(view.get("_mountain_top_mask_visual_dirty")),
			"mask_generation": int(debug.get("mask_generation", -1)),
			"roof_visible": bool(debug.get("roof_overlay_visible", false)),
			"roof_pending": bool(debug.get("roof_overlay_visual_pending", true)),
		}
	return state


func _did_immediate_mountain_visual_change(before: Dictionary, after: Dictionary) -> bool:
	if before.is_empty() or after.size() != before.size():
		return false
	for coord_variant: Variant in before.keys():
		var coord: Vector2i = coord_variant as Vector2i
		if not after.has(coord):
			return false
		var before_state: Dictionary = before.get(coord, { }) as Dictionary
		var after_state: Dictionary = after.get(coord, { }) as Dictionary
		if int(after_state.get("patch_count", 0)) \
				<= int(before_state.get("patch_count", 0)):
			return false
		if int(after_state.get("mask_generation", -1)) \
				<= int(before_state.get("mask_generation", -1)):
			return false
		if int(after_state.get("image_hash", 0)) \
				== int(before_state.get("image_hash", 0)):
			return false
		if bool(after_state.get("visual_dirty", true)) \
				or not bool(after_state.get("roof_visible", false)):
			return false
	return true


func _capture_immediate_cave_lighting_state(streamer: Node, world_tile: Vector2i) -> Dictionary:
	var result := {
		"ready_chunk_count": 0,
		"dug_chunk_count": 0,
		"full_native_still_pending": false,
		"affected_chunks": [],
	}
	if streamer == null:
		return result
	var affected_variant: Variant = streamer.call(
		"_build_mountain_native_mask_dirty_chunks_for_tile",
		world_tile,
	)
	var views: Dictionary = streamer.get("_chunk_views") as Dictionary
	for coord_variant: Variant in affected_variant as Array:
		var coord: Vector2i = coord_variant as Vector2i
		(result["affected_chunks"] as Array).append(coord)
		var view: Node = views.get(coord, null) as Node
		if view == null or not is_instance_valid(view):
			continue
		var source: Dictionary = view.call(
			"get_mountain_cavity_skylight_field_source",
		) as Dictionary
		if bool(source.get("ready", false)):
			result["ready_chunk_count"] = int(result["ready_chunk_count"]) + 1
			var debug: Dictionary = view.call("get_mountain_native_mask_debug_state") as Dictionary
			if int(debug.get("dug_halo_tile_count", 0)) > 0:
				result["dug_chunk_count"] = int(result["dug_chunk_count"]) + 1
		var ready_native: Dictionary = streamer.call(
			"_get_ready_mountain_native_mask_result",
			coord,
		) as Dictionary
		if ready_native.is_empty():
			result["full_native_still_pending"] = true
	return result


func _wait_for_worker_skylight(
		streamer: Node,
		world_tile: Vector2i,
		max_frames: int,
) -> bool:
	var affected_variant: Variant = streamer.call(
		"_build_mountain_native_mask_dirty_chunks_for_tile",
		world_tile,
	)
	var affected: Array = affected_variant as Array
	for _frame: int in range(max_frames):
		await process_frame
		var native: Dictionary = streamer.call(
			"get_mountain_mask_runtime_debug_state",
		) as Dictionary
		if int(native.get("interactive_skylight_queue_count", -1)) != 0:
			return false
		var all_published: bool = true
		var views: Dictionary = streamer.get("_chunk_views") as Dictionary
		var compared: int = 0
		for coord_variant: Variant in affected:
			var coord: Vector2i = coord_variant as Vector2i
			var view: Node = views.get(coord, null) as Node
			if view == null or not is_instance_valid(view):
				continue
			compared += 1
			var ready: Dictionary = streamer.call(
				"_get_ready_mountain_native_mask_result",
				coord,
			) as Dictionary
			var expected_exposure: PackedByteArray = ready.get(
				"sky_exposure_mask",
				PackedByteArray(),
			) as PackedByteArray
			var live_exposure: PackedByteArray = view.get(
				"_mountain_sky_exposure_bytes",
			) as PackedByteArray
			if expected_exposure.is_empty() or live_exposure != expected_exposure:
				all_published = false
				break
		if all_published and compared > 0:
			return true
	return false


func _wait_for_organic_native_settle(streamer: Node, world_tile: Vector2i) -> bool:
	var affected_variant: Variant = streamer.call(
		"_build_mountain_native_mask_dirty_chunks_for_tile",
		world_tile,
	)
	for _frame: int in range(600):
		var all_ready: bool = true
		for coord_variant: Variant in affected_variant as Array:
			var coord: Vector2i = coord_variant as Vector2i
			var packet_map: Dictionary = streamer.get("_chunk_packets") as Dictionary
			if not packet_map.has(coord):
				continue
			var ready: Dictionary = streamer.call(
				"_get_ready_mountain_native_mask_result",
				coord,
			) as Dictionary
			var views: Dictionary = streamer.get("_chunk_views") as Dictionary
			var view: Node = views.get(coord, null) as Node
			if ready.is_empty() \
					or view == null \
					or bool(view.get("_mountain_top_mask_visual_dirty")):
				all_ready = false
				break
		if all_ready:
			return true
		await process_frame
	return false


func _immediate_patch_matches_authoritative_native(
		immediate: Dictionary,
		authoritative: Dictionary,
) -> bool:
	var compared: int = 0
	for coord_variant: Variant in immediate.keys():
		var coord: Vector2i = coord_variant as Vector2i
		if not authoritative.has(coord):
			continue
		var immediate_state: Dictionary = immediate.get(coord, { }) as Dictionary
		var authoritative_state: Dictionary = authoritative.get(coord, { }) as Dictionary
		var patch_min: Vector2i = immediate_state.get("patch_min", Vector2i.ZERO) as Vector2i
		var patch_size: Vector2i = immediate_state.get("patch_size", Vector2i.ZERO) as Vector2i
		var immediate_bytes: PackedByteArray = immediate_state.get(
			"mask_bytes",
			PackedByteArray(),
		) as PackedByteArray
		var authoritative_bytes: PackedByteArray = authoritative_state.get(
			"mask_bytes",
			PackedByteArray(),
		) as PackedByteArray
		var side: int = int(round(sqrt(float(immediate_bytes.size()))))
		if patch_size.x <= 0 \
				or patch_size.y <= 0 \
				or side <= 0 \
				or authoritative_bytes.size() != immediate_bytes.size():
			return false
		compared += 1
		for y: int in range(patch_min.y, patch_min.y + patch_size.y):
			for x: int in range(patch_min.x, patch_min.x + patch_size.x):
				var index: int = y * side + x
				if immediate_bytes[index] != authoritative_bytes[index]:
					print(
						"mountain_runtime_dig_dev_scene_smoke_test local_mask_mismatch coord=%s pixel=(%d,%d)" % [
							str(coord),
							x,
							y,
						],
					)
					return false
	return compared > 0

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
