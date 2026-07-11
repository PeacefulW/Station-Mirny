extends SceneTree
## Windowed production proof. Captures the same fixed world crop in three
## resolver-selected states; no dev overlay or manual visibility toggle exists.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/mountain_runtime_dig_dev_scene"
const MAX_READY_FRAMES: int = 3000
const MAX_SETTLE_FRAMES: int = 3000
const MAX_PROTOTYPE_FRAMES: int = 1800
const MAX_SELECTOR_FRAMES: int = 360
const EVIDENCE_FILES: PackedStringArray = [
	"artifacts/mountain_runtime_dig_dev_scene/production_outside_closed.png",
	"artifacts/mountain_runtime_dig_dev_scene/production_inside_open.png",
	"artifacts/mountain_runtime_dig_dev_scene/production_outside_restored.png",
	"artifacts/mountain_runtime_dig_dev_scene/production_inside_torch_organic.png",
]
const LEGACY_PROTOTYPE_FILES: PackedStringArray = [
	"artifacts/mountain_runtime_dig_dev_scene/prototype_outside_closed.png",
	"artifacts/mountain_runtime_dig_dev_scene/prototype_inside_open.png",
	"artifacts/mountain_runtime_dig_dev_scene/prototype_outside_restored.png",
]

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_stale_evidence()
	if DisplayServer.get_name() == "headless":
		push_error("Production roof render probe requires a real renderer; stale evidence was removed.")
		quit(1)
		return
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Construction-roof dev scene must load.")
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
	_assert(bool(snapshot.get("ready", false)), "Dev scene must become ready.")
	if not bool(snapshot.get("ready", false)):
		await _finish(scene)
		return
	print("ROOF_PROBE stage=scene_ready target=%s" % str(snapshot.get("mountain_tile", Vector2i.ZERO)))

	# Freeze daylight. Mountain materials do not use dev-only parameters; both
	# production sprites receive their regular sun state from WorldStreamer.
	var time_manager: Node = root.get_node_or_null("TimeManager")
	_assert(time_manager != null, "TimeManager autoload must be present.")
	if time_manager != null:
		time_manager.call("restore_persisted_state", 9.0, 1, 0)
		time_manager.call("set_paused", true)
	var brightness: float = 0.0
	for _step: int in range(120):
		for _frame: int in range(15):
			await process_frame
		brightness = _viewport_center_brightness()
		if brightness >= 0.24:
			break
	_assert(brightness >= 0.24, "Viewport must brighten before screenshots (got %.3f)." % brightness)
	# Freeze shader TIME as well as gameplay time. This makes the restored roof
	# crop a byte-for-byte proof instead of comparing two wind/cloud phases.
	Engine.time_scale = 0.0

	snapshot = await _wait_target_native_settled(scene)
	_assert(_target_native_is_settled(snapshot), "Target production dual mask must settle before digging.")
	if not _target_native_is_settled(snapshot):
		await _finish(scene)
		return
	var started: Dictionary = scene.call("debug_start_roof_prototype") as Dictionary
	_assert(bool(started.get("success", false)), "Production roof scenario must start: %s" % str(started))
	if not bool(started.get("success", false)):
		await _finish(scene)
		return

	for _frame: int in range(MAX_PROTOTYPE_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		var running: Dictionary = snapshot.get("prototype", { }) as Dictionary
		if bool(running.get("ready", false)) or bool(running.get("failed", false)):
			break
	var outside_state: Dictionary = snapshot.get("prototype", { }) as Dictionary
	if not bool(outside_state.get("ready", false)):
		print("ROOF_PROBE production_timeout=%s native=%s" % [str(outside_state), str(snapshot.get("native", { }))])
	_assert(bool(outside_state.get("ready", false)), "Production roof scenario must reach OUTSIDE.")
	_assert(not bool(outside_state.get("failed", false)), "Production roof scenario must not fail: %s" % str(outside_state.get("error", "")))
	if not bool(outside_state.get("ready", false)):
		await _finish(scene)
		return
	_assert(bool(outside_state.get("dual_mask_ready", false)), "Render fixture must use production dual masks.")
	_assert(int(outside_state.get("dig_count", 0)) == 6, "Probe must excavate the complete T through public harvest.")
	_assert(int(outside_state.get("dug_floor_count", 0)) == 6, "Every T tile must be real DUG terrain.")
	_assert(int(outside_state.get("remaining_mask_open_count", 0)) == 6, "Native remaining mass must carve every DUG center.")
	_assert(int(outside_state.get("initial_closed_mask_hash", 0)) == int(outside_state.get("closed_mask_hash", -1)), "Production CLOSED must survive excavation unchanged.")
	_assert(int(outside_state.get("remaining_mask_hash", 0)) != int(outside_state.get("initial_base_mask_hash", 0)), "Production remaining mass must reflect excavation.")
	var traversal: Dictionary = scene.call("debug_probe_prototype_player_traversal") as Dictionary
	_assert(bool(traversal.get("success", false)), "Real player footprint must traverse production T: %s" % str(traversal))
	_assert_retaining_walls(scene.call("debug_get_prototype_retaining_wall_states") as Array)

	# Hide only UI. The actual Player, production BASE and production ROOF remain.
	var dev_label: CanvasItem = scene.get_node_or_null("DevHud/InfoLabel") as CanvasItem
	if dev_label != null:
		dev_label.visible = false
	var runtime_hud: CanvasLayer = scene.get_node_or_null("WorldRuntimeV0/HudLayer") as CanvasLayer
	if runtime_hud != null:
		runtime_hud.visible = false
	var camera: PlayerCamera = scene.get_node_or_null("WorldRuntimeV0/Player/Camera2D") as PlayerCamera
	_assert(camera != null, "Player camera must exist.")
	if camera != null:
		camera._target_zoom = 1.55
		camera.zoom = Vector2.ONE * 1.55
		camera.top_level = true
		var mouth: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
		camera.global_position = WorldRuntimeConstants.tile_to_world_center(mouth + Vector2i(0, -2))
		camera.reset_smoothing()
		camera.force_update_scroll()
		camera.process_mode = Node.PROCESS_MODE_DISABLED

	# OUTSIDE: Player stands south of the mouth. Resolver publishes component 0;
	# the production roof sprite stays visible and its selector is zero.
	_assert(bool(scene.call("debug_place_player_for_prototype", false)), "Player must stand outside.")
	var outside_snapshot: Dictionary = await _wait_selector(scene, false)
	var outside: Dictionary = outside_snapshot.get("prototype", { }) as Dictionary
	_assert(bool(outside.get("overlay_visible", false)), "Production roof sprite must be rendered OUTSIDE.")
	_assert((int(outside.get("outside_mouth_direction_or", 0)) & 4) != 0, "OUTSIDE render must carry SOUTH mouth direction.")
	var mouth_selector: Dictionary = scene.call("debug_get_prototype_mouth_aperture_state") as Dictionary
	_assert(int(mouth_selector.get("direction_code", 0)) == 4, "Rendered fixture mouth selector must be SOUTH=4.")
	_assert(int(mouth_selector.get("active_value", 255)) != 255, "OUTSIDE rendered mouth must not be a full active-floor tile.")
	_capture("%s/production_outside_closed.png" % OUTPUT_DIR)
	var outside_crop: Image = await _capture_entrance_crop_without_player(scene, outside_snapshot)
	_assert_crop_has_visual_information(outside_crop, "OUTSIDE")
	print("ROOF_PROBE stage=production_outside_captured")
	var stable_state_signature: String = str(outside.get("prototype_state_signature", ""))
	var outside_effective_signature: String = str(outside.get("effective_roof_signature", ""))
	var remaining_hash: int = int(outside.get("remaining_mask_hash", 0))
	var closed_hash: int = int(outside.get("closed_mask_hash", 0))

	# INSIDE: only Player position changes. Resolver selects the connected T and
	# the production shader composes CLOSED -> remaining mass over that floor.
	_assert(bool(scene.call("debug_place_player_for_prototype", true)), "Player must enter the T junction.")
	var inside_snapshot: Dictionary = await _wait_selector(scene, true)
	var inside: Dictionary = inside_snapshot.get("prototype", { }) as Dictionary
	_assert(bool(inside.get("inside", false)), "Resolver must report INSIDE.")
	_assert(bool(inside.get("active_floor_reveal_active", false)), "INSIDE must publish floor reveal.")
	_assert(int(inside.get("active_floor_halo_tile_count", 0)) >= 6, "INSIDE reveal must contain the T.")
	_assert(bool(inside.get("overlay_visible", false)), "Production roof sprite remains present INSIDE.")
	_assert(str(inside.get("prototype_state_signature", "")) == stable_state_signature, "INSIDE must not mutate dual masks/diff.")
	_assert(int(inside.get("remaining_mask_hash", 0)) == remaining_hash, "INSIDE must preserve remaining mass.")
	_assert(int(inside.get("closed_mask_hash", 0)) == closed_hash, "INSIDE must preserve CLOSED.")
	_capture("%s/production_inside_open.png" % OUTPUT_DIR)
	var inside_crop: Image = await _capture_entrance_crop_without_player(scene, inside_snapshot)
	_assert_crop_has_visual_information(inside_crop, "INSIDE")
	print("ROOF_PROBE stage=production_inside_captured")

	# Restore OUTSIDE through the resolver and demand exact pixels in the fixed
	# entrance crop. This catches hidden texture replacement and selector leaks.
	_assert(bool(scene.call("debug_place_player_for_prototype", false)), "Player must leave the cavity.")
	var restored_snapshot: Dictionary = await _wait_selector(scene, false)
	var restored: Dictionary = restored_snapshot.get("prototype", { }) as Dictionary
	_assert(not bool(restored.get("inside", true)), "Resolver must restore OUTSIDE.")
	_assert(not bool(restored.get("active_floor_reveal_active", true)), "Restored OUTSIDE active-floor reveal must be zero.")
	_assert(int(restored.get("outside_mouth_halo_tile_count", 0)) > 0, "Restored OUTSIDE must recover directional mouth.")
	_assert(str(restored.get("prototype_state_signature", "")) == stable_state_signature, "OUTSIDE restore must preserve dual masks/diff.")
	_assert(str(restored.get("effective_roof_signature", "")) == outside_effective_signature, "OUTSIDE effective state must restore exactly.")
	_assert(int(restored.get("remaining_mask_hash", 0)) == remaining_hash, "Restored OUTSIDE must preserve remaining mass.")
	_assert(int(restored.get("closed_mask_hash", 0)) == closed_hash, "Restored OUTSIDE must preserve CLOSED.")
	_capture("%s/production_outside_restored.png" % OUTPUT_DIR)
	var restored_crop: Image = await _capture_entrance_crop_without_player(scene, restored_snapshot)
	_assert_crop_has_visual_information(restored_crop, "RESTORED OUTSIDE")
	var restored_difference: int = _count_different_pixels(outside_crop, restored_crop)
	_assert(outside_crop.get_size() == restored_crop.get_size(), "First/restored OUTSIDE crops must share exact dimensions.")
	_assert(restored_difference == 0, "First/restored OUTSIDE entrance crop must be pixel-identical (diff %d)." % restored_difference)
	var inside_difference: int = _count_different_pixels(outside_crop, inside_crop)
	_assert(inside_difference >= 512, "INSIDE entrance/floor crop must visibly differ from CLOSED (got %d pixels)." % inside_difference)
	var perf: Dictionary = restored_snapshot.get("native", { }) as Dictionary
	_assert(int(perf.get("native_mask_visual_upload_queue_count", -1)) == 0, "Final native visual queue must be empty.")
	_assert(int(perf.get("native_mask_visual_pending_count", -1)) == 0, "Final native visual pending count must be zero.")
	_assert(int(perf.get("chunk_visibility_waiting_for_roof_count", -1)) == 0, "No chunk may remain hidden waiting for roof upload.")
	print("ROOF_PROBE stage=production_outside_restored outside_diff=%d inside_diff=%d" % [
		restored_difference,
		inside_difference,
	])
	print("ROOF_PROBE perf upload_last_ms=%.3f upload_max_ms=%.3f queue=%d pending=%d visibility_waiting=%d" % [
		float(perf.get("native_mask_visual_upload_elapsed_ms_last", 0.0)),
		float(perf.get("native_mask_visual_upload_elapsed_ms_max_total", 0.0)),
		int(perf.get("native_mask_visual_upload_queue_count", -1)),
		int(perf.get("native_mask_visual_pending_count", -1)),
		int(perf.get("chunk_visibility_waiting_for_roof_count", -1)),
	])

	# Final visual proof for the reported regression: at night the torch field
	# must consume active remaining mass S, while the construction roof keeps its
	# original floor-only reveal semantics. This capture deliberately happens
	# after the byte-exact OUTSIDE restore proof.
	_assert(bool(scene.call("debug_place_player_for_prototype", true)), "Player must re-enter for torch proof.")
	await _wait_selector(scene, true)
	var torch: PointLight2D = scene.get_node_or_null("WorldRuntimeV0/Player/Torch") as PointLight2D
	var daylight: CanvasModulate = scene.get_node_or_null("WorldRuntimeV0/Daylight") as CanvasModulate
	var streamer: Node = scene.get_node_or_null("WorldRuntimeV0/WorldStreamer")
	var shadow_field: CanvasItem = scene.get_node_or_null("WorldRuntimeV0/MountainTorchShadowField") as CanvasItem
	_assert(torch != null and daylight != null and streamer != null and shadow_field != null, "Torch proof runtime nodes must exist.")
	if torch != null and daylight != null and streamer != null and shadow_field != null:
		if time_manager != null:
			time_manager.call("restore_persisted_state", 23.0, 1, 0)
		if daylight.has_method("_sync_from_current_context"):
			daylight.call("_sync_from_current_context", true)
		if streamer.has_method("_sync_sun_lighting_from_time"):
			streamer.call("_sync_sun_lighting_from_time", true)
		var proof_night := Color(0.025, 0.028, 0.038)
		daylight.color = proof_night
		daylight.set("_target_color", proof_night)
		torch.enabled = true
		var shadow_ready: bool = false
		for _frame: int in range(180):
			await process_frame
			var shadow_debug: Dictionary = streamer.call(
				"get_mountain_torch_shadow_field_debug_state",
			) as Dictionary
			shadow_ready = shadow_field.visible \
					and not bool(shadow_debug.get("pending", true)) \
					and int(shadow_debug.get("solid_sample_count", 0)) > 0
			if shadow_ready:
				break
		_assert(shadow_ready, "Live mountain torch shadow field must settle inside the excavated T.")
		for _settle_frame: int in range(30):
			await process_frame
		_capture("%s/production_inside_torch_organic.png" % OUTPUT_DIR)
		print("ROOF_PROBE stage=production_inside_torch_organic_captured")
	await _finish(scene)


func _cleanup_stale_evidence() -> void:
	var dir: DirAccess = DirAccess.open("res://")
	if dir == null:
		return
	dir.make_dir_recursive("artifacts/mountain_runtime_dig_dev_scene")
	for relative_path: String in EVIDENCE_FILES:
		if dir.file_exists(relative_path):
			dir.remove(relative_path)
	for relative_path: String in LEGACY_PROTOTYPE_FILES:
		if dir.file_exists(relative_path):
			dir.remove(relative_path)


func _wait_target_native_settled(scene: Node) -> Dictionary:
	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_SETTLE_FRAMES):
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if _target_native_is_settled(snapshot):
			return snapshot
		await process_frame
	return snapshot


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
				and int(state.get("active_floor_halo_tile_count", 0)) >= 6
		else:
			settled = settled \
				and int(state.get("active_component_id", -1)) == 0 \
				and not bool(state.get("active_floor_reveal_active", true)) \
				and int(state.get("active_floor_halo_tile_count", -1)) == 0 \
				and int(state.get("outside_mouth_halo_tile_count", 0)) > 0
		if settled and _target_native_is_settled(snapshot):
			for _settle: int in range(8):
				await process_frame
			return scene.call("get_debug_snapshot") as Dictionary
	_assert(false, "Production selector did not settle to %s: %s" % ["INSIDE" if expected_inside else "OUTSIDE", str(snapshot.get("prototype", { }))])
	return snapshot


func _target_native_is_settled(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("ready", false)):
		return false
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	if native.is_empty() or int(native.get("ready_native_mask_chunk_count", 0)) <= 0:
		return false
	var production: Dictionary = snapshot.get("prototype", { }) as Dictionary
	return bool(production.get("target_mask_sprite_ready", false)) \
		and bool(production.get("dual_mask_ready", false)) \
		and int(production.get("remaining_mask_hash", 0)) != 0 \
		and int(production.get("closed_mask_hash", 0)) != 0 \
		and bool(snapshot.get("stand_walkable", false))


func _assert_retaining_walls(states: Array) -> void:
	_assert(states.size() == 11, "Render fixture must retain all eleven surrounding wall tiles.")
	for state_variant: Variant in states:
		var state: Dictionary = state_variant as Dictionary
		_assert(not bool(state.get("terrain_walkable", true)), "Retaining wall terrain must stay blocked.")
		_assert(not bool(state.get("mask_walkable", true)), "Retaining wall center must stay blocked.")
		_assert(bool(state.get("resource_bearing", false)), "Retaining wall must remain resource-bearing.")


func _viewport_center_brightness() -> float:
	var image: Image = root.get_texture().get_image()
	if image == null:
		return 0.0
	var width: int = image.get_width()
	var height: int = image.get_height()
	var total: float = 0.0
	var samples: int = 0
	for grid_y: int in range(5):
		for grid_x: int in range(5):
			var pixel: Color = image.get_pixel(
				int(width * (0.3 + 0.1 * float(grid_x))),
				int(height * (0.3 + 0.1 * float(grid_y))),
			)
			total += (pixel.r + pixel.g + pixel.b) / 3.0
			samples += 1
	return total / float(samples)


func _capture(path: String) -> Image:
	var viewport_image: Image = root.get_texture().get_image()
	if viewport_image == null:
		_assert(false, "Viewport image must be available for %s." % path)
		return Image.new()
	var err: Error = viewport_image.save_png(path)
	_assert(err == OK, "Screenshot must save to %s (err %d)." % [path, err])
	_assert(FileAccess.file_exists(path), "Fresh screenshot must exist at %s." % path)
	return viewport_image


func _capture_entrance_crop_without_player(scene: Node, snapshot: Dictionary) -> Image:
	var player: CanvasItem = scene.get_node_or_null("WorldRuntimeV0/Player") as CanvasItem
	var was_visible: bool = player.visible if player != null else false
	if player != null:
		player.visible = false
	await process_frame
	var viewport_image: Image = root.get_texture().get_image()
	var crop: Image = _extract_entrance_world_crop(viewport_image, snapshot)
	if player != null:
		player.visible = was_visible
	await process_frame
	return crop


func _extract_entrance_world_crop(viewport_image: Image, snapshot: Dictionary) -> Image:
	if viewport_image == null or viewport_image.is_empty():
		return Image.new()
	var mouth: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
	var tile_size: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	var world_min := Vector2(float(mouth.x - 2) * tile_size, float(mouth.y - 5) * tile_size)
	var world_max := Vector2(float(mouth.x + 3) * tile_size, float(mouth.y + 1) * tile_size)
	var canvas_transform: Transform2D = root.get_canvas_transform()
	var screen_a: Vector2 = canvas_transform * world_min
	var screen_b: Vector2 = canvas_transform * world_max
	var min_x: int = clampi(floori(minf(screen_a.x, screen_b.x)), 0, viewport_image.get_width())
	var min_y: int = clampi(floori(minf(screen_a.y, screen_b.y)), 0, viewport_image.get_height())
	var max_x: int = clampi(ceili(maxf(screen_a.x, screen_b.x)), 0, viewport_image.get_width())
	var max_y: int = clampi(ceili(maxf(screen_a.y, screen_b.y)), 0, viewport_image.get_height())
	if max_x <= min_x or max_y <= min_y:
		return Image.new()
	return viewport_image.get_region(Rect2i(min_x, min_y, max_x - min_x, max_y - min_y))


func _assert_crop_has_visual_information(crop: Image, label: String) -> void:
	_assert(crop != null and not crop.is_empty(), "%s entrance crop must exist." % label)
	if crop == null or crop.is_empty():
		return
	_assert(crop.get_width() >= 240 and crop.get_height() >= 180, "%s crop must cover the actual entrance and T floor." % label)
	var min_luma: float = 1.0
	var max_luma: float = 0.0
	var total_luma: float = 0.0
	var samples: int = 0
	for y: int in range(0, crop.get_height(), 4):
		for x: int in range(0, crop.get_width(), 4):
			var pixel: Color = crop.get_pixel(x, y)
			var luma: float = (pixel.r + pixel.g + pixel.b) / 3.0
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)
			total_luma += luma
			samples += 1
	var average_luma: float = total_luma / float(maxi(1, samples))
	_assert(average_luma >= 0.05, "%s entrance crop must be visible, not black." % label)
	_assert(max_luma - min_luma >= 0.12, "%s entrance crop must contain real facade/floor detail." % label)


func _count_different_pixels(first: Image, second: Image) -> int:
	if first == null or second == null or first.is_empty() or second.is_empty():
		return 0
	if first.get_size() != second.get_size():
		return first.get_width() * first.get_height()
	var differences: int = 0
	for y: int in range(first.get_height()):
		for x: int in range(first.get_width()):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				differences += 1
	return differences


func _finish(scene: Node) -> void:
	Engine.time_scale = 1.0
	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
