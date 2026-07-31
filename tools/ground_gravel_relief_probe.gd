extends SceneTree
## Рендер-проба щебневого рельефа земли (gravel relief) для
## docs/02_system_specs/world/plains_ground_gravel_relief.md.
##
## Поднимает ту же dev-сцену, что и проба каменной россыпи: там есть и открытый
## грунт, и трава, и гора рядом, то есть все три случая, которые спека обязана
## закрыть одним кадром.
##
## Зум-свип здесь не украшение: камушек 5..14 px, у процедурного поля нет
## мипмапов, поэтому LOD-затухание — самое вероятное место ошибки.
##
## Запускать дважды, чтобы получить пару before/after. Вариант `off` обнуляет
## gravel_coverage на общем ground material set до сборки мира — тот же
## параметр, который крутит visual runtime lab.
##
##     Godot_v4.7-stable_win64_console.exe --path . -s tools/ground_gravel_relief_probe.gd -- off
##     Godot_v4.7-stable_win64_console.exe --path . -s tools/ground_gravel_relief_probe.gd -- on
##
## Запускать без --headless: захват кадра требует оконного рендерера.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const GROUND_MATERIAL_SET: String = "res://data/terrain/material_sets/plains_ground_material_set.tres"
const OUTPUT_ROOT: String = "res://artifacts/gravel_relief"
const MAX_READY_FRAMES: int = 9000
const SETTLE_FRAMES: int = 240
const ZOOM_SETTLE_FRAMES: int = 120
const PROBE_HOUR: float = 9.0
const FRAME_TIME_SAMPLES: int = 240
const DIG_STEPS: int = 60
const ZOOMS: Array[Array] = [
	[2.20, "closeup"],
	[1.00, "play"],
	[0.45, "wide"],
	[0.18, "far"],
]

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("ground_gravel_relief_probe requires a windowed GPU renderer.")
		quit(1)
		return
	# Without this every frame measures the vsync interval instead of the work.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var variant: String = "on"
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		variant = String(user_args[0]).strip_edges().to_lower()
	if variant != "on" and variant != "off":
		push_error("ground_gravel_relief_probe: variant must be 'on' or 'off', got '%s'" % variant)
		quit(1)
		return
	var output_dir: String = "%s/%s" % [OUTPUT_ROOT, variant]

	# Правим общий material set до сборки материалов мира:
	# world_tile_set_factory копирует sampling_params на шейдер по имени.
	var ground_set: Resource = load(GROUND_MATERIAL_SET)
	_assert(ground_set != null, "Ground material set must load.")
	if ground_set == null:
		_finish()
		return
	var params: Dictionary = ground_set.get("sampling_params")
	_assert(params.has("gravel_coverage"), "sampling_params must carry gravel_coverage.")
	if not params.has("gravel_coverage"):
		_finish()
		return
	if variant == "off":
		params["gravel_coverage"] = 0.0
		ground_set.set("sampling_params", params)
	print("RENDER_PROBE variant=%s gravel_coverage=%s" % [variant, params["gravel_coverage"]])

	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/gravel_relief/%s" % variant)

	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Dev scene must load.")
	if packed_scene == null:
		_finish()
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
		_finish()
		return

	var world_scene: Node = scene.get_node_or_null("WorldRuntimeV0")
	_assert(world_scene != null, "Dev scene must expose WorldRuntimeV0.")
	if world_scene == null:
		_finish()
		return
	var loading_state: Dictionary = await _wait_for_initial_world_presented(world_scene)
	_assert(bool(loading_state.get("presented", false)), "Initial chunk bubble must be presented.")
	if not bool(loading_state.get("presented", false)):
		_finish()
		return
	print("RENDER_PROBE stage=ready elapsed_ms=%d" % int(loading_state.get("elapsed_ms", -1)))

	# Мир стартует на рассвете; на движущемся солнце кадр не устаканивается.
	# Щебень читает ground_sun_day, поэтому дневной час обязателен.
	var time_manager: Node = root.get_node_or_null("TimeManager")
	_assert(time_manager != null, "TimeManager autoload must be present.")
	if time_manager != null:
		time_manager.call("restore_persisted_state", PROBE_HOUR, 1, 0)
		time_manager.call("set_paused", true)

	await _settle(SETTLE_FRAMES)
	var camera: Camera2D = _find_camera(scene)
	_assert(camera != null, "Dev scene must expose a Camera2D.")
	if camera == null:
		_finish()
		return

	for entry: Array in ZOOMS:
		await _capture_zoom(camera, float(entry[0]), String(entry[1]), output_dir)

	# Excavated mountain interior: the spec claims gravel needs no mountain-aware
	# mechanism because the cavity skylight field darkens the floor for it. That
	# claim is only worth anything if a dug cavity is actually captured.
	await _dig_cavity(scene)
	await _capture_zoom(camera, 2.20, "cavity", output_dir)

	scene.queue_free()
	await process_frame
	await process_frame
	_finish()


func _capture_zoom(camera: Camera2D, zoom: float, label: String, output_dir: String) -> void:
	camera.set("_target_zoom", zoom)
	camera.zoom = Vector2(zoom, zoom)
	camera.force_update_scroll()
	await _settle(ZOOM_SETTLE_FRAMES)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	_assert(img != null, "Capture must return an image for %s." % label)
	if img == null:
		return
	# Почти чёрный кадр означает, что сверху ещё висел оверлей. Сохранять его
	# нельзя: в папке артефактов он выглядит как отрендеренный мир.
	var centre: Color = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	_assert(centre.get_luminance() >= 0.02, "Frame %s must not be black." % label)
	if centre.get_luminance() < 0.02:
		return
	var path: String = "%s/%s.png" % [output_dir, label]
	img.save_png(path)
	print("RENDER_PROBE saved=%s size=%dx%d" % [path, img.get_width(), img.get_height()])

	# Frame time on this exact view, vsync off. Meaningful only as an on/off
	# pair from the same machine and the same run pair — the shader is the only
	# thing that differs between them.
	var started_usec: int = Time.get_ticks_usec()
	await _settle(FRAME_TIME_SAMPLES)
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	print("RENDER_PROBE frame_time zoom=%s mean_ms=%.3f samples=%d"
		% [label, float(elapsed_usec) / 1000.0 / float(FRAME_TIME_SAMPLES), FRAME_TIME_SAMPLES])


func _dig_cavity(scene: Node) -> void:
	var dug: int = 0
	for _step: int in range(DIG_STEPS):
		var result: Dictionary = scene.call("debug_dig_target_once") as Dictionary
		if bool(result.get("success", false)):
			dug += 1
		await _settle(4)
	_assert(dug > 0, "Dev scene must excavate at least one mountain sample.")
	print("RENDER_PROBE dig successful_steps=%d of %d" % [dug, DIG_STEPS])
	await _settle(SETTLE_FRAMES)


func _wait_for_initial_world_presented(world_scene: Node) -> Dictionary:
	var state: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		state = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(state.get("presented", false)):
			return state
	return state


func _settle(frames: int) -> void:
	for _frame: int in range(frames):
		await process_frame


func _find_camera(node: Node) -> Camera2D:
	if node is Camera2D:
		return node as Camera2D
	for child: Node in node.get_children():
		var found: Camera2D = _find_camera(child)
		if found != null:
			return found
	return null


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ground_gravel_relief_probe: %s" % message)


func _finish() -> void:
	if _failed:
		print("ground_gravel_relief_probe: FAILED")
		quit(1)
		return
	print("ground_gravel_relief_probe: OK")
	quit(0)
