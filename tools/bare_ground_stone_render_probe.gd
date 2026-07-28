extends SceneTree
## Рендер-проба каменной россыпи на голой земле: поднимает dev-сцену, ставит
## дневное время, снимает кадр в игровом зуме и в отъезде, чтобы было видно и
## край травы, и открытый грунт.
##
##     Godot --path . -s tools/bare_ground_stone_render_probe.gd
##
## Запускать без --headless: захват кадра требует оконного рендерера.

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/bare_ground_stones"
const MAX_READY_FRAMES: int = 9000
const SETTLE_FRAMES: int = 240
const PROBE_HOUR: float = 9.0
const WIDE_ZOOM: float = 0.72
const CLOSE_ZOOM: float = 2.2

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("bare_ground_stone_render_probe requires a windowed GPU renderer.")
		quit(1)
		return
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/bare_ground_stones")

	var packed_scene: PackedScene = load(DEV_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Dev scene must load.")
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
		_finish()
		return
	var world_scene: Node = scene.get_node_or_null("WorldRuntimeV0")
	_assert(world_scene != null, "Dev scene must expose WorldRuntimeV0.")
	if world_scene == null:
		_finish()
		return
	var initial_loading_state: Dictionary = await _wait_for_initial_world_presented(world_scene)
	_assert(bool(initial_loading_state.get("presented", false)), "Initial chunk bubble must be presented.")
	if not bool(initial_loading_state.get("presented", false)):
		_finish()
		return
	print(
		"RENDER_PROBE stage=ready elapsed_ms=%d"
		% int(initial_loading_state.get("elapsed_ms", -1)),
	)

	# Мир стартует на рассвете; на движущемся солнце маски перезажигаются и
	# кадр не устаканивается. Фиксируем дневной час.
	var time_manager: Node = root.get_node_or_null("TimeManager")
	_assert(time_manager != null, "TimeManager autoload must be present.")
	if time_manager != null:
		time_manager.call("restore_persisted_state", PROBE_HOUR, 1, 0)
		time_manager.call("set_paused", true)

	await _settle_viewport()
	var brightness: float = _viewport_center_brightness()
	print("RENDER_PROBE stage=daylight brightness=%.3f" % brightness)

	_capture("%s/stones_game_zoom.png" % OUTPUT_DIR)
	print("RENDER_PROBE stage=game_zoom_captured")

	var camera: Camera2D = _find_camera(scene)
	_assert(camera != null, "Dev scene must expose a Camera2D for the wide shot.")
	if camera != null:
		camera.set("_target_zoom", WIDE_ZOOM)
		camera.zoom = Vector2(WIDE_ZOOM, WIDE_ZOOM)
		# Отъезд запрашивает новые чанки: фиксированное число кадров даёт
		# presentation-очереди доехать, не превращая probe в многоминутное
		# ожидание зависимого от монитора порога яркости.
		await _settle_viewport()
		_capture("%s/stones_wide.png" % OUTPUT_DIR)
		print("RENDER_PROBE stage=wide_captured")

		# Камни-кайма мелкие и декоративные: на общем плане их не оценить.
		camera.set("_target_zoom", CLOSE_ZOOM)
		camera.zoom = Vector2(CLOSE_ZOOM, CLOSE_ZOOM)
		await _settle_viewport()
		_capture("%s/stones_close.png" % OUTPUT_DIR)
		print("RENDER_PROBE stage=close_captured")

	scene.queue_free()
	await process_frame
	await process_frame
	_finish()


func _settle_viewport() -> void:
	for _frame: int in range(SETTLE_FRAMES):
		await process_frame


func _wait_for_initial_world_presented(world_scene: Node) -> Dictionary:
	var state: Dictionary = { }
	for _frame: int in range(MAX_READY_FRAMES):
		await process_frame
		state = world_scene.call("get_initial_loading_state") as Dictionary
		if bool(state.get("presented", false)):
			break
	return state


func _viewport_center_brightness() -> float:
	var image: Image = root.get_texture().get_image()
	if image == null:
		return 0.0
	var total: float = 0.0
	var samples: int = 0
	var step_x: int = maxi(1, image.get_width() / 24)
	var step_y: int = maxi(1, image.get_height() / 24)
	for y: int in range(0, image.get_height(), step_y):
		for x: int in range(0, image.get_width(), step_x):
			var pixel: Color = image.get_pixel(x, y)
			total += (pixel.r + pixel.g + pixel.b) / 3.0
			samples += 1
	return total / maxf(1.0, float(samples))


func _find_camera(node: Node) -> Camera2D:
	if node is Camera2D:
		return node as Camera2D
	for child: Node in node.get_children():
		var found: Camera2D = _find_camera(child)
		if found != null:
			return found
	return null


func _capture(path: String) -> void:
	var viewport_image: Image = root.get_texture().get_image()
	if viewport_image == null:
		_assert(false, "Viewport image must be available for %s." % path)
		return
	var err: Error = viewport_image.save_png(path)
	_assert(err == OK, "Screenshot must save to %s (err %d)." % [path, err])


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("bare_ground_stone_render_probe: OK")
	quit(0)
