extends SceneTree

# Dev validation probe for the REAL in-scene 2D lighting (Iteration 1). Loads the
# world scene (which now owns the DaylightSystem sun + player Torch), drives the
# DaylightSystem ambient to day/night and toggles the player's Torch, and captures:
#   01 day, torch off        -> the true daytime look (no torch wash)
#   02 night, torch off      -> pitch black (zero visibility = intended)
#   03 night, torch on       -> warm torch pool in the dark
# Windowed (needs a GPU). Main scene untouched.
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/ground_light_probe.gd

const DEV_SCENE: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/ground_light_probe"
const ZOOM: float = 0.45
const MAX_SETTLE_FRAMES: int = 20000
const TARGET_VIEWPORT_SIZE: Vector2i = Vector2i(1920, 1080)
const MIN_TORCH_CHANGED_PIXELS: int = 3000
const MIN_TORCH_LUMA_GAIN: float = 25.0
const MIN_POSTPROCESS_EDGE_CHANGED_PIXELS: int = 300
# Local mirrors of DaylightSystem ambient floors (avoid a static class reference
# that drags the EventBus autoload into this -s tool's compile step).
const PROBE_DAY: Color = Color(0.85, 0.85, 0.83)
const PROBE_NIGHT: Color = Color(0.03, 0.035, 0.05)

var _streamer: Node = null
var _daylight: CanvasModulate = null
var _torch: PointLight2D = null
var _failed: bool = false
var _target_viewport_size: Vector2i = TARGET_VIEWPORT_SIZE


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ground_light_probe: must run windowed")
		quit(1)
		return
	_apply_command_line_overrides()
	DisplayServer.window_set_size(_target_viewport_size)
	root.size = _target_viewport_size
	root.content_scale_size = _target_viewport_size
	var scene: Node = (load(DEV_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	var world_scene: Node = null
	for _frame: int in range(300):
		await process_frame
		world_scene = scene.get_node_or_null("WorldRuntimeV0")
		if world_scene != null:
			break
	if world_scene == null:
		push_error("ground_light_probe: real world scene did not instantiate")
		quit(1)
		return
	_streamer = world_scene.get_node_or_null("WorldStreamer")
	var time_manager: Node = root.get_node_or_null("TimeManager")
	var camera: Camera2D = world_scene.get_node_or_null("Player/Camera2D") as Camera2D
	var player: Node2D = world_scene.get_node_or_null("Player") as Node2D
	_daylight = world_scene.get_node_or_null("Daylight") as CanvasModulate
	_torch = player.get_node_or_null("Torch") as PointLight2D
	if time_manager != null:
		time_manager.call("set_paused", true)
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.set("_target_zoom", ZOOM)

	if not await _stream_until_presented(world_scene, player):
		push_error("ground_light_probe: production loading gate never presented the world")
		quit(1)
		return
	_validate_player_screen_center(world_scene, player)
	DirAccess.open("res://").make_dir_recursive("artifacts/ground_light_probe")
	await _validate_postprocess_fullscreen(world_scene, camera)

	await _set_phase(PROBE_DAY, false)
	var day_image: Image = await _capture(camera, "01_day_torch_off")

	await _set_phase(PROBE_NIGHT, false)
	var night_off_image: Image = await _capture(camera, "02_night_torch_off")

	await _set_phase(PROBE_NIGHT, true)
	var night_on_image: Image = await _capture(camera, "03_night_torch_on")
	_validate_captures(day_image, night_off_image, night_on_image)

	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _apply_command_line_overrides() -> void:
	var width: int = TARGET_VIEWPORT_SIZE.x
	var height: int = TARGET_VIEWPORT_SIZE.y
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--width="):
			width = maxi(1, int(argument.trim_prefix("--width=")))
		elif argument.begins_with("--height="):
			height = maxi(1, int(argument.trim_prefix("--height=")))
	_target_viewport_size = Vector2i(width, height)


# Force the DaylightSystem ambient and the torch, then let its _process settle the
# sun (energy/angle derive from the ambient brightness).
func _set_phase(ambient: Color, torch_on: bool) -> void:
	if _daylight != null:
		_daylight.color = ambient
		_daylight.set("_target_color", ambient)
	if _torch != null:
		_torch.enabled = torch_on
	for _f: int in range(24):
		await process_frame


func _capture(camera: Camera2D, label: String) -> Image:
	camera.force_update_scroll()
	for _f: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("ground_light_probe: capture FAILED %s" % label)
		return null
	img.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	print("ground_light_probe: saved %s/%s.png" % [ProjectSettings.globalize_path(OUTPUT_DIR), label])
	return img


func _validate_postprocess_fullscreen(world_scene: Node, camera: Camera2D) -> void:
	var overlay: ColorRect = world_scene.get_node_or_null(
		"PostProcessLayer/PostProcessOverlay"
	) as ColorRect
	var compositor: Node = world_scene.get_node_or_null("WorldResolutionCompositor")
	var world_viewport: SubViewport = compositor.get("_terrain_viewport") as SubViewport \
			if compositor != null else null
	if overlay == null:
		_fail("cannot resolve the production postprocess overlay")
		return
	if world_viewport == null:
		_fail("cannot resolve the production world viewport")
		return
	overlay.call("sync_render_target_rect")
	var overlay_size := Vector2i(roundi(overlay.size.x), roundi(overlay.size.y))
	var expected_overlay_size := Vector2i(world_viewport.get_visible_rect().size)
	print(
		"ground_light_probe: viewport physical=%s logical=%s postprocess position=%s size=%s" % [
			str(root.size),
			str(expected_overlay_size),
			str(overlay.position),
			str(overlay_size),
		],
	)
	if not overlay.position.is_equal_approx(Vector2.ZERO):
		_fail("postprocess overlay is offset from the viewport origin")
	if overlay_size != expected_overlay_size:
		_fail("postprocess overlay does not cover the logical world viewport")

	overlay.call("set_postprocess_enabled", false)
	var disabled_image: Image = await _capture(camera, "00_postprocess_off")
	overlay.call("set_postprocess_enabled", true)
	var enabled_image: Image = await _capture(camera, "00_postprocess_on")
	if disabled_image == null or enabled_image == null:
		_fail("postprocess framebuffer proof is missing")
		return
	if disabled_image.get_size() != root.size \
			or enabled_image.get_size() != root.size:
		_fail("postprocess framebuffer size differs from the physical window")
		return
	var edge_counts: PackedInt32Array = _count_postprocess_edge_changes(
		disabled_image,
		enabled_image,
	)
	print(
		"ground_light_probe: postprocess_edge_proof top=%d right=%d bottom=%d left=%d" % [
			edge_counts[0], edge_counts[1], edge_counts[2], edge_counts[3],
		],
	)
	for edge_name: String in ["top", "right", "bottom", "left"]:
		var edge_index: int = ["top", "right", "bottom", "left"].find(edge_name)
		if edge_counts[edge_index] < MIN_POSTPROCESS_EDGE_CHANGED_PIXELS:
			_fail("postprocess does not affect the %s viewport edge" % edge_name)


func _count_postprocess_edge_changes(disabled_image: Image, enabled_image: Image) -> PackedInt32Array:
	var size: Vector2i = enabled_image.get_size()
	var band: int = mini(80, maxi(16, mini(size.x, size.y) / 10))
	var x_start: int = roundi(float(size.x) * 0.30)
	var x_end: int = roundi(float(size.x) * 0.70)
	var y_start: int = roundi(float(size.y) * 0.30)
	var y_end: int = roundi(float(size.y) * 0.70)
	var counts := PackedInt32Array([0, 0, 0, 0])
	for y: int in range(0, band, 2):
		for x: int in range(x_start, x_end, 2):
			if _pixel_changed(disabled_image, enabled_image, x, y):
				counts[0] += 1
	for y: int in range(y_start, y_end, 2):
		for x: int in range(size.x - band, size.x, 2):
			if _pixel_changed(disabled_image, enabled_image, x, y):
				counts[1] += 1
	for y: int in range(size.y - band, size.y, 2):
		for x: int in range(x_start, x_end, 2):
			if _pixel_changed(disabled_image, enabled_image, x, y):
				counts[2] += 1
	for y: int in range(y_start, y_end, 2):
		for x: int in range(0, band, 2):
			if _pixel_changed(disabled_image, enabled_image, x, y):
				counts[3] += 1
	return counts


func _pixel_changed(disabled_image: Image, enabled_image: Image, x: int, y: int) -> bool:
	return absf(
		_luma(disabled_image.get_pixel(x, y)) - _luma(enabled_image.get_pixel(x, y))
	) >= 0.004


func _stream_until_presented(world_scene: Node, player: Node2D) -> bool:
	for _tick: int in range(MAX_SETTLE_FRAMES):
		await process_frame
		var loading_state: Dictionary = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(loading_state.get("presented", false)) \
				and world_scene.get_node_or_null("InitialLoadingScreen") == null \
				and player.process_mode != Node.PROCESS_MODE_DISABLED:
			for _settle: int in range(12):
				await process_frame
			return true
	return false


func _validate_captures(day_image: Image, night_off_image: Image, night_on_image: Image) -> void:
	if day_image == null or night_off_image == null or night_on_image == null:
		_fail("one or more framebuffer captures are missing")
		return
	if day_image.get_size() != night_off_image.get_size() \
			or night_off_image.get_size() != night_on_image.get_size():
		_fail("capture sizes differ")
		return
	var center: Vector2i = night_on_image.get_size() / 2
	var half_extent: int = 360
	var changed_pixels: int = 0
	var positive_luma_gain: float = 0.0
	for y: int in range(maxi(0, center.y - half_extent), mini(night_on_image.get_height(), center.y + half_extent), 2):
		for x: int in range(maxi(0, center.x - half_extent), mini(night_on_image.get_width(), center.x + half_extent), 2):
			var off_color: Color = night_off_image.get_pixel(x, y)
			var on_color: Color = night_on_image.get_pixel(x, y)
			var gain: float = _luma(on_color) - _luma(off_color)
			if absf(gain) >= 0.01:
				changed_pixels += 1
			positive_luma_gain += maxf(0.0, gain)
	print(
		"ground_light_probe: torch_pixel_proof changed=%d positive_luma_gain=%.3f enabled=%s" % [
			changed_pixels,
			positive_luma_gain,
			str(_torch != null and _torch.enabled),
		],
	)
	if _torch == null or not _torch.enabled:
		_fail("torch did not remain enabled")
	if changed_pixels < MIN_TORCH_CHANGED_PIXELS:
		_fail("torch changed too few real world pixels: %d" % changed_pixels)
	if positive_luma_gain < MIN_TORCH_LUMA_GAIN:
		_fail("torch did not add enough light to the real world: %.3f" % positive_luma_gain)


func _validate_player_screen_center(world_scene: Node, player: Node2D) -> void:
	var compositor: Node = world_scene.get_node_or_null("WorldResolutionCompositor")
	var world_viewport: SubViewport = compositor.get("_terrain_viewport") as SubViewport \
			if compositor != null else null
	if world_viewport == null or player == null:
		_fail("cannot resolve the production world viewport/player")
		return
	var player_screen_position: Vector2 = \
			world_viewport.canvas_transform * player.global_position
	var expected_center: Vector2 = Vector2(world_viewport.size_2d_override) * 0.5
	var center_error_px: float = player_screen_position.distance_to(expected_center)
	print(
		"ground_light_probe: player_center screen=%s expected=%s error_px=%.3f" % [
			str(player_screen_position),
			str(expected_center),
			center_error_px,
		],
	)
	if center_error_px > 1.0:
		_fail("player is not centered in the rendered world: %.3f px" % center_error_px)


func _luma(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _fail(message: String) -> void:
	push_error("ground_light_probe: %s" % message)
	_failed = true
