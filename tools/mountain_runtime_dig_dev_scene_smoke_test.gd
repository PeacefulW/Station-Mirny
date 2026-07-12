extends SceneTree
## Production construction-roof smoke:
## real runtime -> six public digs -> worker dual masks -> native reconcile ->
## OUTSIDE/INSIDE/OUTSIDE only through Player position and MountainResolver.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const MAX_READY_FRAMES: int = 3000
const MAX_PROTOTYPE_FRAMES: int = 1800
const MAX_SELECTOR_FRAMES: int = 360
const EXPECTED_RETAINING_WALL_COUNT: int = 11
const EXPECTED_T_OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(0, -1),
	Vector2i(0, -2),
	Vector2i(0, -3),
	Vector2i(-1, -3),
	Vector2i(1, -3),
]

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Mountain construction dev scene must load.")
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
	_assert(not bool(snapshot.get("failed", false)), "Dev scene must not fail: %s" % str(snapshot.get("fail_reason", "")))
	_assert(bool(snapshot.get("ready", false)), "Dev scene must become ready.")
	if not bool(snapshot.get("ready", false)):
		await _finish(scene)
		return

	var target_terrain_id: int = int(snapshot.get("target_terrain_id", -1))
	_assert(
		target_terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
			or target_terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
		"Mouth must start as a real mountain wall/foot tile.",
	)
	_assert(int(snapshot.get("scanned_foot_tile_count", 0)) > 0, "Scan must see runtime mountain foot tiles.")
	_assert_t_footprint(snapshot)

	# Starting before the remote target chunk has uploaded its native visual is
	# intentional: the dev scenario must await production masks without a race.
	var started: Dictionary = scene.call("debug_start_roof_prototype") as Dictionary
	_assert(bool(started.get("success", false)), "Production scenario must start: %s" % str(started))
	if not bool(started.get("success", false)):
		await _finish(scene)
		return
	for _frame: int in range(MAX_PROTOTYPE_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		var running: Dictionary = snapshot.get("prototype", { }) as Dictionary
		if bool(running.get("ready", false)) or bool(running.get("failed", false)):
			break
	var outside: Dictionary = snapshot.get("prototype", { }) as Dictionary
	if not bool(outside.get("ready", false)):
		print("PRODUCTION_ROOF_TIMEOUT snapshot=%s native=%s" % [str(outside), str(snapshot.get("native", { }))])
	_assert(not bool(outside.get("failed", false)), "Production scenario must not fail: %s" % str(outside.get("error", "")))
	_assert(bool(outside.get("ready", false)), "Production scenario must reach OUTSIDE-ready state.")
	if not bool(outside.get("ready", false)):
		await _finish(scene)
		return

	_assert(_is_native_settled(snapshot), "Worker/native/visual queues must be settled at finalize.")
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	_assert(bool(native.get("native_mask_runtime_enabled", false)), "Scenario must use native mountain masks.")
	_assert(int(native.get("ready_native_mask_chunk_count", 0)) > 0, "At least one native mask must be ready.")
	_assert(bool(snapshot.get("stand_walkable", false)), "South stand tile must be walkable.")
	_assert(bool(outside.get("dual_mask_ready", false)), "Target ChunkView must own production dual masks.")
	_assert(int(outside.get("remaining_mask_byte_count", 0)) > 0, "Remaining-mass bytes must exist.")
	_assert(
		int(outside.get("remaining_mask_byte_count", 0)) == int(outside.get("closed_roof_mask_byte_count", -1)),
		"CLOSED and remaining masks must share exact raster geometry.",
	)
	_assert(int(outside.get("dig_count", 0)) == EXPECTED_T_OFFSETS.size(), "All six T tiles must use public harvest.")
	_assert(int(outside.get("dug_floor_count", 0)) == EXPECTED_T_OFFSETS.size(), "All six T tiles must be real DUG floor.")
	_assert(int(outside.get("mask_walkable_count", 0)) == EXPECTED_T_OFFSETS.size(), "Every DUG center must be runtime-walkable.")
	_assert(
		int(outside.get("remaining_mask_open_count", 0)) == EXPECTED_T_OFFSETS.size(),
		"Worker reconcile must keep every DUG source center open in remaining mass.",
	)
	_assert(int(outside.get("dug_halo_tile_count", 0)) >= EXPECTED_T_OFFSETS.size(), "Worker DUG halo must contain the complete T.")
	_assert(bool(outside.get("overlay_visible", false)), "Production roof Sprite2D must stay present OUTSIDE.")
	_assert(not bool(outside.get("inside", true)), "Initial finalized selector must be OUTSIDE.")
	_assert(int(outside.get("active_component_id", -1)) == 0, "OUTSIDE must select no cavity component.")
	_assert(not bool(outside.get("active_floor_reveal_active", true)), "OUTSIDE active-floor selector must be zero.")
	_assert(int(outside.get("outside_mouth_halo_tile_count", 0)) > 0, "OUTSIDE must reveal the real directional mouth.")
	var mouth_direction_or: int = int(outside.get("outside_mouth_direction_or", 0))
	_assert((mouth_direction_or & 4) != 0, "South-facing fixture must publish SOUTH mouth bit.")
	_assert(
		(mouth_direction_or & 64) != 0 and (mouth_direction_or & 128) == 0,
		"Mouth halo must contain exterior projection without decorative ownership.",
	)
	var mouth_aperture: Dictionary = scene.call("debug_get_prototype_mouth_aperture_state") as Dictionary
	_assert(bool(mouth_aperture.get("ready", false)), "CPU mouth selector debug must be ready OUTSIDE.")
	_assert(int(mouth_aperture.get("direction_code", 0)) == 4, "South mouth tile must carry exact SOUTH=4 direction code.")
	_assert(
		int(mouth_aperture.get("active_value", 255)) == 0,
		"OUTSIDE roof selector must stay zero at the physical mouth.",
	)
	_assert(
		int(mouth_aperture.get("mouth_nonzero_count", 0)) \
			== int(outside.get("outside_mouth_halo_tile_count", -1)),
		"Directional selector count must match reported mouth count.",
	)
	_assert(
		int(mouth_aperture.get("active_nonzero_count", -1)) == 0,
		"OUTSIDE active-floor selector must remain component-only and empty.",
	)
	_assert(
		int(mouth_aperture.get("aperture_nonzero_count", 0)) > 0,
		"Native full-resolution aperture must own the BASE facade break.",
	)

	var initial_base_hash: int = int(outside.get("initial_base_mask_hash", 0))
	var initial_closed_hash: int = int(outside.get("initial_closed_mask_hash", 0))
	var remaining_hash: int = int(outside.get("remaining_mask_hash", 0))
	var closed_hash: int = int(outside.get("closed_mask_hash", 0))
	_assert(initial_base_hash != 0 and initial_closed_hash != 0, "Pre-dig production mask hashes must exist.")
	_assert(initial_base_hash == initial_closed_hash, "Untouched BASE and CLOSED must start from the same silhouette.")
	_assert(remaining_hash != 0 and remaining_hash != initial_base_hash, "Excavation must change remaining mass.")
	_assert(closed_hash == initial_closed_hash, "Excavation must not mutate immutable CLOSED.")
	_assert(int(outside.get("open_mask_hash", 0)) == remaining_hash, "Final BASE must be native remaining mass; no dev carve is allowed.")
	_assert(bool(outside.get("roof_sprite_id_stable", false)), "Production roof sprite instance must stay stable.")
	_assert(bool(outside.get("roof_texture_id_stable", false)), "Production roof texture instance must stay stable.")
	_assert(bool(outside.get("roof_material_id_stable", false)), "Production roof material instance must stay stable.")
	_assert(bool(outside.get("base_sprite_id_stable", false)), "BASE sprite instance must stay stable.")
	_assert(bool(outside.get("base_texture_id_stable", false)), "BASE texture instance must stay stable.")
	_assert(bool(outside.get("base_material_id_stable", false)), "BASE material instance must stay stable.")
	_assert_dug_tile_states(outside)

	var traversal: Dictionary = scene.call("debug_probe_prototype_player_traversal") as Dictionary
	_assert(bool(traversal.get("success", false)), "Real nine-point footprint must traverse the reconciled T: %s" % str(traversal))
	_assert(int(traversal.get("min_footprint_sample_count", 0)) >= 9, "Traversal must use Player's full nine-point footprint.")
	_assert(int(traversal.get("native_open_sample_count", 0)) > 0, "Traversal must sample production remaining-mass bytes.")
	var retaining_states: Array = scene.call("debug_get_prototype_retaining_wall_states") as Array
	_assert_retaining_wall_states(retaining_states)
	var retaining_signature: String = str(retaining_states)
	var stable_state_signature: String = str(outside.get("prototype_state_signature", ""))
	var outside_effective_signature: String = str(outside.get("effective_roof_signature", ""))

	# INSIDE is caused only by placing the real Player on the junction. The
	# player's MountainResolver publishes the active connected component.
	_assert(bool(scene.call("debug_place_player_for_prototype", true)), "Player must move into the cavity.")
	var inside_snapshot: Dictionary = await _wait_selector(scene, true)
	var inside: Dictionary = inside_snapshot.get("prototype", { }) as Dictionary
	_assert(bool(inside.get("inside", false)), "Resolver must report INSIDE.")
	_assert(int(inside.get("active_component_id", 0)) > 0, "INSIDE must select a connected component.")
	_assert(bool(inside.get("active_floor_reveal_active", false)), "INSIDE must publish active-floor reveal.")
	_assert(int(inside.get("active_floor_halo_tile_count", 0)) >= EXPECTED_T_OFFSETS.size(), "INSIDE reveal must contain the complete T component.")
	_assert(bool(inside.get("overlay_visible", false)), "Production roof sprite remains alive; shader selects remaining mass.")
	_assert(str(inside.get("prototype_state_signature", "")) == stable_state_signature, "Resolver transition must not mutate BASE/CLOSED/DUG state.")
	_assert(int(inside.get("remaining_mask_hash", 0)) == remaining_hash, "INSIDE must keep exact remaining-mass bytes.")
	_assert(int(inside.get("closed_mask_hash", 0)) == closed_hash, "INSIDE must keep exact CLOSED bytes.")
	_assert(str(inside.get("effective_roof_signature", "")) != outside_effective_signature, "INSIDE effective selector must differ from OUTSIDE.")
	var inside_component_id: int = int(inside.get("active_component_id", 0))

	# Regression from the real organic-corner screenshot: exact authored tile has
	# no component, CLOSED is solid and remaining S is open. The real Player must
	# keep the same active cave through the resolver's organic-cutout fallback.
	var fringe: Dictionary = scene.call("debug_find_prototype_organic_fringe_candidate") as Dictionary
	_assert(bool(fringe.get("success", false)), "Fixture must contain a walkable organic C-solid/S-open fringe: %s" % str(fringe))
	if bool(fringe.get("success", false)):
		_assert(
			int((fringe.get("resolved", { }) as Dictionary).get("component_id", 0)) == inside_component_id,
			"Organic fringe must resolve to active component: %s" % str(fringe),
		)
		_assert(bool(scene.call("debug_place_player_at_world", fringe.get("world_position", Vector2.ZERO) as Vector2)), "Player must move onto organic fringe.")
		var fringe_snapshot: Dictionary = await _wait_selector(scene, true)
		var fringe_state: Dictionary = fringe_snapshot.get("prototype", { }) as Dictionary
		var resolver: Dictionary = fringe_state.get("resolver", { }) as Dictionary
		_assert(int(fringe_state.get("active_component_id", 0)) == inside_component_id, "Organic fringe must retain the exact same component.")
		_assert(bool(fringe_state.get("overlay_visible", false)), "Roof overlay must remain revealed on organic fringe.")
		_assert(bool(resolver.get("resolved_from_organic_cutout", false)), "Real MountainResolver must report organic-cutout fallback.")
		_assert(str(fringe_state.get("prototype_state_signature", "")) == stable_state_signature, "Organic fallback must not mutate masks/diff.")
		_assert(bool(scene.call("debug_place_player_for_prototype", true)), "Player must return to T junction after fringe regression.")
		inside_snapshot = await _wait_selector(scene, true)

	_assert(bool(scene.call("debug_place_player_for_prototype", false)), "Player must return outside.")
	var restored_snapshot: Dictionary = await _wait_selector(scene, false)
	var restored: Dictionary = restored_snapshot.get("prototype", { }) as Dictionary
	_assert(not bool(restored.get("inside", true)), "Resolver must restore OUTSIDE.")
	_assert(int(restored.get("active_component_id", -1)) == 0, "Restored OUTSIDE must clear component id.")
	_assert(not bool(restored.get("active_floor_reveal_active", true)), "Restored OUTSIDE active-floor selector must be zero.")
	_assert(int(restored.get("outside_mouth_halo_tile_count", 0)) > 0, "Restored OUTSIDE must recover directional mouth.")
	_assert(int(restored.get("active_floor_halo_tile_count", -1)) == 0, "Restored OUTSIDE floor selector must be empty.")
	_assert(str(restored.get("prototype_state_signature", "")) == stable_state_signature, "OUTSIDE restore must preserve BASE/CLOSED/DUG state.")
	_assert(str(restored.get("effective_roof_signature", "")) == outside_effective_signature, "OUTSIDE effective state must restore exactly.")
	_assert(int(restored.get("remaining_mask_hash", 0)) == remaining_hash, "OUTSIDE restore must keep exact remaining mass.")
	_assert(int(restored.get("closed_mask_hash", 0)) == closed_hash, "OUTSIDE restore must keep exact CLOSED.")
	_assert(bool(restored.get("roof_texture_id_stable", false)), "OUTSIDE restore must reuse production roof texture.")
	_assert(str(scene.call("debug_get_prototype_retaining_wall_states")) == retaining_signature, "Resolver transitions must not change retaining walls.")
	var restored_native: Dictionary = restored_snapshot.get("native", { }) as Dictionary
	var outside_native: Dictionary = snapshot.get("native", { }) as Dictionary
	var inside_native: Dictionary = inside_snapshot.get("native", { }) as Dictionary
	print("PRODUCTION_ROOF_PERF first_roof_ms=%.3f enter_ms=%.3f exit_ms=%.3f startup_max_ms=%.3f queue=%d pending=%d visibility_wait=%d" % [
		float(outside_native.get("native_mask_visual_upload_elapsed_ms_last", 0.0)),
		float(inside_native.get("native_mask_visual_upload_elapsed_ms_last", 0.0)),
		float(restored_native.get("native_mask_visual_upload_elapsed_ms_last", 0.0)),
		float(restored_native.get("native_mask_visual_upload_elapsed_ms_max_total", 0.0)),
		int(restored_native.get("native_mask_visual_upload_queue_count", -1)),
		int(restored_native.get("native_mask_visual_pending_count", -1)),
		int(restored_native.get("chunk_visibility_waiting_for_roof_count", -1)),
	])

	await _finish(scene)


func _wait_selector(scene: Node, expected_inside: bool) -> Dictionary:
	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_SELECTOR_FRAMES):
		await physics_frame
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		var state: Dictionary = snapshot.get("prototype", { }) as Dictionary
		var settled: bool = bool(state.get("inside", false)) == expected_inside
		if expected_inside:
			settled = settled \
				and int(state.get("active_component_id", 0)) > 0 \
				and bool(state.get("active_floor_reveal_active", false)) \
				and int(state.get("active_floor_halo_tile_count", 0)) >= EXPECTED_T_OFFSETS.size()
		else:
			settled = settled \
				and int(state.get("active_component_id", -1)) == 0 \
				and not bool(state.get("active_floor_reveal_active", true)) \
				and int(state.get("active_floor_halo_tile_count", -1)) == 0 \
				and int(state.get("outside_mouth_halo_tile_count", 0)) > 0
		if settled and _is_native_settled(snapshot):
			return snapshot
	_assert(false, "Production roof selector did not settle to %s: %s" % ["INSIDE" if expected_inside else "OUTSIDE", str(snapshot.get("prototype", { }))])
	return snapshot


func _assert_t_footprint(snapshot: Dictionary) -> void:
	var mouth: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
	var stand: Vector2i = snapshot.get("stand_tile", Vector2i.ZERO) as Vector2i
	_assert(mouth - stand == Vector2i.UP, "Fixture entrance must face south.")
	var dig_tiles: Array = snapshot.get("prototype_dig_tiles", []) as Array
	_assert(dig_tiles.size() == EXPECTED_T_OFFSETS.size(), "Fixture must contain exactly six tiles.")
	if dig_tiles.size() != EXPECTED_T_OFFSETS.size():
		return
	var owner_chunk: Vector2i = WorldRuntimeConstants.tile_to_chunk(mouth)
	for index: int in range(EXPECTED_T_OFFSETS.size()):
		var tile: Vector2i = dig_tiles[index] as Vector2i
		_assert(tile == mouth + EXPECTED_T_OFFSETS[index], "T tile %d must match deterministic geometry." % index)
		_assert(WorldRuntimeConstants.tile_to_chunk(tile) == owner_chunk, "Every T tile must stay in one chunk.")


func _assert_dug_tile_states(prototype: Dictionary) -> void:
	var states: Array = prototype.get("tile_states", []) as Array
	_assert(states.size() == EXPECTED_T_OFFSETS.size(), "Scenario must report every T tile.")
	for state_variant: Variant in states:
		var state: Dictionary = state_variant as Dictionary
		_assert(bool(state.get("ready", false)), "DUG tile must stay loaded.")
		_assert(int(state.get("terrain_id", -1)) == WorldRuntimeConstants.TERRAIN_PLAINS_DUG, "DUG tile must use TERRAIN_PLAINS_DUG.")
		_assert(bool(state.get("terrain_walkable", false)), "DUG tile must be walkable in diff data.")
		_assert(bool(state.get("mask_walkable", false)), "DUG tile center must be runtime-walkable.")
		_assert(bool(state.get("remaining_mask_ready", false)), "DUG tile must sample reconciled remaining mass.")
		_assert(not bool(state.get("remaining_mask_solid", true)), "DUG tile center must be carved from remaining mass.")


func _assert_retaining_wall_states(states: Array) -> void:
	_assert(states.size() == EXPECTED_RETAINING_WALL_COUNT, "Every authored retaining wall must be reported.")
	for state_variant: Variant in states:
		var state: Dictionary = state_variant as Dictionary
		var terrain_id: int = int(state.get("terrain_id", -1))
		_assert(
			terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
				or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
			"Retaining tile must remain mountain terrain.",
		)
		_assert(not bool(state.get("terrain_walkable", true)), "Retaining terrain must remain blocked.")
		_assert(not bool(state.get("mask_walkable", true)), "Retaining center must remain blocked.")
		_assert(bool(state.get("resource_bearing", false)), "Retaining tile must remain mineable/resource-bearing.")


func _is_native_settled(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("ready", false)):
		return false
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	if native.is_empty() or int(native.get("ready_native_mask_chunk_count", 0)) <= 0:
		return false
	if bool(native.get("dirty", false)) \
			or bool(native.get("request_in_flight", false)) \
			or int(native.get("native_mask_visual_upload_queue_count", 0)) > 0 \
			or int(native.get("native_mask_visual_pending_count", 0)) > 0 \
			or int(native.get("chunk_visibility_waiting_for_roof_count", 0)) > 0:
		return false
	var production: Dictionary = snapshot.get("prototype", { }) as Dictionary
	return bool(production.get("target_mask_sprite_ready", false)) \
		and bool(production.get("dual_mask_ready", false)) \
		and int(production.get("remaining_mask_hash", 0)) != 0 \
		and int(production.get("closed_mask_hash", 0)) != 0 \
		and bool(snapshot.get("stand_walkable", false))


func _finish(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	if _failed:
		quit(1)
		return
	print("mountain_runtime_dig_dev_scene_smoke_test: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
