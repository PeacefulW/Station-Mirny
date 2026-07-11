extends SceneTree
## Tools-only GPU diagnostic for the production mountain mouth. It reaches the
## same deterministic OUTSIDE state as mountain_runtime_dig_dev_scene_render_probe,
## then captures one fixed entrance crop while toggling only the four production
## ChunkView sprites that can plausibly draw the apparent threshold.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/mountain_mouth_layer_isolation"
const MAX_READY_FRAMES: int = 3000
const MAX_SETTLE_FRAMES: int = 3000
const MAX_PROTOTYPE_FRAMES: int = 1800
const MAX_SELECTOR_FRAMES: int = 360
const TARGET_LAYER_NAMES: PackedStringArray = [
	"MountainTopMaskUnderlay",
	"MountainClosedRoofOverlay",
	"MountainRockUnderlay",
	"MountainFoothillOverlay",
]

var _failed: bool = false
var _report_lines: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_prepare_output_dir(false)
	if DisplayServer.get_name() == "headless":
		_fail("Layer isolation requires a real renderer.")
		quit(1)
		return
	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Mountain runtime dig dev scene must load.")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	var snapshot: Dictionary = await _wait_scene_ready(scene)
	_assert(bool(snapshot.get("ready", false)), "Dev scene must become ready.")
	if not bool(snapshot.get("ready", false)):
		await _finish(scene)
		return

	var time_manager: Node = root.get_node_or_null("TimeManager")
	_assert(time_manager != null, "TimeManager autoload must exist.")
	if time_manager != null:
		time_manager.call("restore_persisted_state", 9.0, 1, 0)
		time_manager.call("set_paused", true)
	await _wait_for_daylight()

	snapshot = await _wait_target_native_settled(scene)
	_assert(_target_native_is_settled(snapshot), "Target native mountain mask must settle.")
	if not _target_native_is_settled(snapshot):
		await _finish(scene)
		return
	var started: Dictionary = scene.call("debug_start_roof_prototype") as Dictionary
	_assert(bool(started.get("success", false)), "Roof prototype must start: %s" % str(started))
	if not bool(started.get("success", false)):
		await _finish(scene)
		return
	snapshot = await _wait_prototype_ready(scene)
	var outside_state: Dictionary = snapshot.get("prototype", { }) as Dictionary
	_assert(bool(outside_state.get("ready", false)), "Roof prototype must reach READY.")
	_assert(not bool(outside_state.get("failed", false)), "Roof prototype failed: %s" % str(outside_state.get("error", "")))
	if not bool(outside_state.get("ready", false)):
		await _finish(scene)
		return

	_hide_hud_and_fix_camera(scene, snapshot)
	_assert(bool(scene.call("debug_place_player_for_prototype", false)), "Player must move OUTSIDE.")
	snapshot = await _wait_selector(scene, false)
	var outside: Dictionary = snapshot.get("prototype", { }) as Dictionary
	_assert(not bool(outside.get("inside", true)), "Resolver must be OUTSIDE.")
	_assert((int(outside.get("outside_mouth_direction_or", 0)) & 4) != 0, "OUTSIDE mouth must include SOUTH direction.")
	var chunk_view: ChunkView = scene.call("_target_chunk_view") as ChunkView
	_assert(chunk_view != null, "Target ChunkView must exist.")
	if chunk_view == null:
		await _finish(scene)
		return

	var layers: Dictionary = { }
	var initial_visibility: Dictionary = { }
	for layer_name: String in TARGET_LAYER_NAMES:
		var layer: CanvasItem = chunk_view.get_node_or_null(NodePath(layer_name)) as CanvasItem
		_assert(layer != null, "Target ChunkView must contain %s." % layer_name)
		if layer == null:
			continue
		layers[layer_name] = layer
		initial_visibility[layer_name] = layer.visible
		_record_layer_metadata(layer_name, layer)
	_assert(layers.size() == TARGET_LAYER_NAMES.size(), "All four target layers must exist.")
	if layers.size() != TARGET_LAYER_NAMES.size():
		await _finish(scene)
		return
	# Do not destroy the last good evidence until the replacement fixture has
	# definitely reached the exact capture boundary.
	_prepare_output_dir(true)

	var player: CanvasItem = scene.get_node_or_null("WorldRuntimeV0/Player") as CanvasItem
	if player != null:
		player.visible = false
	# The dev fixture continuously validates that the production ROOF remains
	# visible. Once OUTSIDE is proven, stop scene logic before intentionally
	# hiding that sprite; CanvasItems continue to render for the GPU captures.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	# Freeze shader TIME as well as gameplay time so every toggle is compared at
	# byte-stable daylight/wind/cloud phase.
	Engine.time_scale = 0.0
	for _settle: int in range(8):
		await process_frame

	var captures: Dictionary = { }
	captures["00_all"] = await _capture_variant(
		"00_all", layers, initial_visibility, initial_visibility, snapshot
	)
	for index: int in range(TARGET_LAYER_NAMES.size()):
		var omitted_name: String = TARGET_LAYER_NAMES[index]
		var omitted_visibility: Dictionary = initial_visibility.duplicate()
		omitted_visibility[omitted_name] = false
		var key: String = "%02d_without_%s" % [index + 1, _short_layer_name(omitted_name)]
		captures[key] = await _capture_variant(
			key, layers, initial_visibility, omitted_visibility, snapshot
		)

	var none_visibility: Dictionary = { }
	for layer_name: String in TARGET_LAYER_NAMES:
		none_visibility[layer_name] = false
	captures["05_without_all_four"] = await _capture_variant(
		"05_without_all_four", layers, initial_visibility, none_visibility, snapshot
	)
	for index: int in range(TARGET_LAYER_NAMES.size()):
		var only_name: String = TARGET_LAYER_NAMES[index]
		var only_visibility: Dictionary = none_visibility.duplicate()
		only_visibility[only_name] = bool(initial_visibility.get(only_name, false))
		var key: String = "%02d_only_%s" % [index + 6, _short_layer_name(only_name)]
		captures[key] = await _capture_variant(
			key, layers, initial_visibility, only_visibility, snapshot
		)

	_restore_visibility(layers, initial_visibility)
	var all_capture: Dictionary = captures.get("00_all", { }) as Dictionary
	var all_crop: Image = all_capture.get("entrance", Image.new()) as Image
	var all_threshold: Image = all_capture.get("threshold", Image.new()) as Image
	for key_variant: Variant in captures.keys():
		var key: String = str(key_variant)
		if key == "00_all":
			continue
		var capture: Dictionary = captures[key] as Dictionary
		var entrance: Image = capture.get("entrance", Image.new()) as Image
		var threshold: Image = capture.get("threshold", Image.new()) as Image
		var entrance_diff: int = _count_different_pixels(all_crop, entrance)
		var threshold_diff: int = _count_different_pixels(all_threshold, threshold)
		var threshold_luma_delta: float = _sum_absolute_luma_delta(all_threshold, threshold)
		_report("DIFF %s entrance_pixels=%d threshold_pixels=%d threshold_luma_delta=%.3f" % [
			key,
			entrance_diff,
			threshold_diff,
			threshold_luma_delta,
		])
		var diff_image: Image = _make_amplified_diff(all_threshold, threshold, 8.0)
		_save_image(diff_image, "%s/diff_%s_x8.png" % [OUTPUT_DIR, key])

	_write_report(snapshot, chunk_view)
	await _finish(scene)


func _wait_scene_ready(scene: Node) -> Dictionary:
	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if bool(snapshot.get("failed", false)) or bool(snapshot.get("ready", false)):
			return snapshot
	return snapshot


func _wait_for_daylight() -> void:
	var brightness: float = 0.0
	for _step: int in range(120):
		for _frame: int in range(15):
			await process_frame
		brightness = _viewport_center_brightness()
		if brightness >= 0.24:
			break
	_assert(brightness >= 0.24, "Viewport must brighten before isolation captures (%.3f)." % brightness)


func _wait_target_native_settled(scene: Node) -> Dictionary:
	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_SETTLE_FRAMES):
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if _target_native_is_settled(snapshot):
			return snapshot
		await process_frame
	return snapshot


func _wait_prototype_ready(scene: Node) -> Dictionary:
	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_PROTOTYPE_FRAMES):
		await process_frame
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		var state: Dictionary = snapshot.get("prototype", { }) as Dictionary
		if bool(state.get("ready", false)) or bool(state.get("failed", false)):
			return snapshot
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
				and bool(state.get("active_floor_reveal_active", false))
		else:
			settled = settled \
				and int(state.get("active_component_id", -1)) == 0 \
				and not bool(state.get("active_floor_reveal_active", true)) \
				and int(state.get("outside_mouth_halo_tile_count", 0)) > 0
		if settled and _target_native_is_settled(snapshot):
			for _settle: int in range(8):
				await process_frame
			return scene.call("get_debug_snapshot") as Dictionary
	return snapshot


func _target_native_is_settled(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("ready", false)):
		return false
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	var production: Dictionary = snapshot.get("prototype", { }) as Dictionary
	return int(native.get("ready_native_mask_chunk_count", 0)) > 0 \
		and bool(production.get("target_mask_sprite_ready", false)) \
		and bool(production.get("dual_mask_ready", false)) \
		and int(production.get("remaining_mask_hash", 0)) != 0 \
		and int(production.get("closed_mask_hash", 0)) != 0 \
		and bool(snapshot.get("stand_walkable", false))


func _hide_hud_and_fix_camera(scene: Node, snapshot: Dictionary) -> void:
	var dev_label: CanvasItem = scene.get_node_or_null("DevHud/InfoLabel") as CanvasItem
	if dev_label != null:
		dev_label.visible = false
	var runtime_hud: CanvasLayer = scene.get_node_or_null("WorldRuntimeV0/HudLayer") as CanvasLayer
	if runtime_hud != null:
		runtime_hud.visible = false
	var camera: PlayerCamera = scene.get_node_or_null("WorldRuntimeV0/Player/Camera2D") as PlayerCamera
	_assert(camera != null, "Player camera must exist.")
	if camera == null:
		return
	camera._target_zoom = 1.55
	camera.zoom = Vector2.ONE * 1.55
	camera.top_level = true
	var mouth: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
	camera.global_position = WorldRuntimeConstants.tile_to_world_center(mouth + Vector2i(0, -2))
	camera.reset_smoothing()
	camera.force_update_scroll()
	camera.process_mode = Node.PROCESS_MODE_DISABLED


func _capture_variant(
		key: String,
		layers: Dictionary,
		initial_visibility: Dictionary,
		desired_visibility: Dictionary,
		snapshot: Dictionary,
) -> Dictionary:
	_restore_visibility(layers, initial_visibility)
	for layer_name: String in TARGET_LAYER_NAMES:
		var layer: CanvasItem = layers.get(layer_name) as CanvasItem
		if layer != null:
			layer.visible = bool(desired_visibility.get(layer_name, false))
	for _settle: int in range(3):
		await process_frame
	var viewport_image: Image = root.get_texture().get_image()
	var entrance: Image = _extract_entrance_crop(viewport_image, snapshot)
	var threshold: Image = _extract_threshold_crop(viewport_image, snapshot)
	_assert(not entrance.is_empty(), "%s entrance crop must exist." % key)
	_assert(not threshold.is_empty(), "%s threshold crop must exist." % key)
	_save_image(entrance, "%s/%s_entrance.png" % [OUTPUT_DIR, key])
	_save_image(threshold, "%s/%s_threshold.png" % [OUTPUT_DIR, key])
	_report("CAPTURE %s visibility=%s entrance=%s threshold=%s" % [
		key,
		_visibility_signature(desired_visibility),
		str(entrance.get_size()),
		str(threshold.get_size()),
	])
	return { "entrance": entrance, "threshold": threshold }


func _extract_entrance_crop(viewport_image: Image, snapshot: Dictionary) -> Image:
	var mouth: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
	var tile_size: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	return _extract_world_crop(
		viewport_image,
		Vector2(float(mouth.x - 2) * tile_size, float(mouth.y - 5) * tile_size),
		Vector2(float(mouth.x + 3) * tile_size, float(mouth.y + 1) * tile_size),
	)


func _extract_threshold_crop(viewport_image: Image, snapshot: Dictionary) -> Image:
	var mouth: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
	var tile_size: float = float(WorldRuntimeConstants.TILE_SIZE_PX)
	return _extract_world_crop(
		viewport_image,
		Vector2((float(mouth.x) - 1.5) * tile_size, (float(mouth.y) - 0.55) * tile_size),
		Vector2((float(mouth.x) + 1.5) * tile_size, (float(mouth.y) + 1.35) * tile_size),
	)


func _extract_world_crop(viewport_image: Image, world_min: Vector2, world_max: Vector2) -> Image:
	if viewport_image == null or viewport_image.is_empty():
		return Image.new()
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


func _record_layer_metadata(label: String, layer: CanvasItem) -> void:
	var material: Material = layer.material
	var material_class: String = material.get_class() if material != null else "<none>"
	var shader_path: String = "<none>"
	if material is ShaderMaterial:
		var shader: Shader = (material as ShaderMaterial).shader
		if shader != null:
			shader_path = shader.resource_path
	_report("LAYER %s node=%s class=%s visible=%s z=%d material=%s shader=%s" % [
		label,
		str(layer.get_path()),
		layer.get_class(),
		str(layer.visible),
		layer.z_index,
		material_class,
		shader_path,
	])


func _short_layer_name(layer_name: String) -> String:
	match layer_name:
		"MountainTopMaskUnderlay":
			return "base"
		"MountainClosedRoofOverlay":
			return "roof"
		"MountainRockUnderlay":
			return "rock"
		"MountainFoothillOverlay":
			return "foothill"
	return layer_name.to_snake_case()


func _visibility_signature(visibility: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for layer_name: String in TARGET_LAYER_NAMES:
		parts.append("%s:%d" % [
			_short_layer_name(layer_name),
			1 if bool(visibility.get(layer_name, false)) else 0,
		])
	return ",".join(parts)


func _restore_visibility(layers: Dictionary, visibility: Dictionary) -> void:
	for layer_name: String in TARGET_LAYER_NAMES:
		var layer: CanvasItem = layers.get(layer_name) as CanvasItem
		if layer != null:
			layer.visible = bool(visibility.get(layer_name, false))


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


func _sum_absolute_luma_delta(first: Image, second: Image) -> float:
	if first == null or second == null or first.get_size() != second.get_size():
		return 0.0
	var total: float = 0.0
	for y: int in range(first.get_height()):
		for x: int in range(first.get_width()):
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			total += absf((a.r + a.g + a.b - b.r - b.g - b.b) / 3.0)
	return total


func _make_amplified_diff(first: Image, second: Image, gain: float) -> Image:
	if first == null or second == null or first.get_size() != second.get_size():
		return Image.new()
	var result: Image = Image.create(first.get_width(), first.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in range(first.get_height()):
		for x: int in range(first.get_width()):
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			result.set_pixel(x, y, Color(
				clampf(absf(a.r - b.r) * gain, 0.0, 1.0),
				clampf(absf(a.g - b.g) * gain, 0.0, 1.0),
				clampf(absf(a.b - b.b) * gain, 0.0, 1.0),
				1.0,
			))
	return result


func _save_image(image: Image, path: String) -> void:
	if image == null or image.is_empty():
		_assert(false, "Image for %s must not be empty." % path)
		return
	var err: Error = image.save_png(path)
	_assert(err == OK, "PNG must save to %s (err %d)." % [path, err])


func _prepare_output_dir(clear_existing: bool) -> void:
	var dir: DirAccess = DirAccess.open("res://")
	if dir == null:
		return
	dir.make_dir_recursive("artifacts/mountain_mouth_layer_isolation")
	if not clear_existing:
		return
	var output: DirAccess = DirAccess.open(OUTPUT_DIR)
	if output == null:
		return
	output.list_dir_begin()
	var entry: String = output.get_next()
	while not entry.is_empty():
		if not output.current_is_dir():
			output.remove(entry)
		entry = output.get_next()
	output.list_dir_end()


func _write_report(snapshot: Dictionary, chunk_view: ChunkView) -> void:
	var mouth: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
	_report("TARGET mouth_tile=%s chunk_coord=%s chunk_node=%s" % [
		str(mouth),
		str(chunk_view.chunk_coord),
		str(chunk_view.get_path()),
	])
	_report("ROOT_CAUSE pre_rebuild_threshold_owner=MountainTopMaskUnderlay shader=res://assets/shaders/mountain_top_mask_underlay.gdshader pass=structural_wall_mask_to_wall_mask cause=residual_visual_remaining_mass_strip_at_south_mouth_edge")
	_report("CURRENT_SET note=captured_after_visual-mask_rebuild; inspect_00_all_threshold_for_post-rebuild_result")
	var file: FileAccess = FileAccess.open("%s/report.txt" % OUTPUT_DIR, FileAccess.WRITE)
	_assert(file != null, "Isolation report file must open.")
	if file == null:
		return
	for line: String in _report_lines:
		file.store_line(line)
	file.close()


func _viewport_center_brightness() -> float:
	var image: Image = root.get_texture().get_image()
	if image == null:
		return 0.0
	var total: float = 0.0
	var samples: int = 0
	for grid_y: int in range(5):
		for grid_x: int in range(5):
			var pixel: Color = image.get_pixel(
				int(image.get_width() * (0.3 + 0.1 * float(grid_x))),
				int(image.get_height() * (0.3 + 0.1 * float(grid_y))),
			)
			total += (pixel.r + pixel.g + pixel.b) / 3.0
			samples += 1
	return total / float(maxi(samples, 1))


func _report(message: String) -> void:
	_report_lines.append(message)
	print("MOUTH_LAYER_ISOLATION %s" % message)


func _finish(scene: Node) -> void:
	Engine.time_scale = 1.0
	if scene != null:
		scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _fail(message: String) -> void:
	push_error(message)
	_failed = true


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)
