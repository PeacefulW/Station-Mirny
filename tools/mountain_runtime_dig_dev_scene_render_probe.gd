extends SceneTree
## Рендер-проба dev-сцены «копаем рантайм-гору»: поднимает сцену, ждёт
## готовности, копает тоннель в гору публичным путём try_harvest_at_world
## и сохраняет before/after скриншоты в artifacts/ для визуальной приёмки.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const DEV_SCENE_PATH: String = "res://scenes/dev/mountain_runtime_dig_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/mountain_runtime_dig_dev_scene"
const MAX_READY_FRAMES: int = 3000
const MAX_SETTLE_FRAMES: int = 3600
const DIG_TUNNEL_TILES: int = 4

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dir: DirAccess = DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("artifacts/mountain_runtime_dig_dev_scene")
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
	print("RENDER_PROBE stage=ready")
	# Новая игра стартует в 07:00 (рассветная темень) — прыгаем сразу в 09:00
	# и ставим время на паузу: реальное ожидание рассвета убивает игрока без
	# O2, а движущееся солнце непрерывно перезажигает горные маски и мешает
	# settle. Autoload-идентификаторы недоступны --script сценариям на
	# компиляции, поэтому TimeManager берём через root.
	var time_manager: Node = root.get_node_or_null("TimeManager")
	_assert(time_manager != null, "TimeManager autoload must be present.")
	if time_manager != null:
		time_manager.call("restore_persisted_state", 9.0, 1, 0)
		time_manager.call("set_paused", true)
	var daylight_hour: int = int(time_manager.call("get_hour")) if time_manager != null else -1
	_assert(daylight_hour >= 8, "Daylight must reach 08:00+ for a readable before-shot.")
	# Слои освещения (CanvasModulate + динамический свет) доезжают к цели
	# лерпом за несколько секунд — ждём фактической яркости вьюпорта,
	# иначе before-скриншот чёрный. Проверка механизм-независимая.
	# Порог ниже дневного плато (~0.27 на этой палитре грунта): ждём коротко,
	# длинный простой в фокусном окне ловит случайные нажатия пользователя.
	var brightness: float = 0.0
	for _step: int in range(120):
		for _frame: int in range(15):
			await process_frame
		brightness = _viewport_center_brightness()
		if brightness >= 0.24:
			break
	_assert(brightness >= 0.24, "Viewport must brighten before the before-shot (got %.3f)." % brightness)
	print("RENDER_PROBE stage=daylight hour=%d brightness=%.3f" % [daylight_hour, brightness])
	# stand_walkable не требуем: живой пользователь может копнуть E во время
	# прогона, и нависшая губа фасада легитимно закрывает точку стояния.
	snapshot = await _wait_settled(scene, false)
	_assert(_is_settled(snapshot, false), "Native masks must settle before the before-shot.")
	for _frame: int in range(30):
		await process_frame
	_capture("%s/before_dig.png" % OUTPUT_DIR)
	print("RENDER_PROBE stage=before_captured")

	var streamer: Node = scene.get_node_or_null("WorldRuntimeV0/WorldStreamer")
	_assert(streamer != null, "Probe must reach the runtime WorldStreamer.")
	var mountain_tile: Vector2i = snapshot.get("mountain_tile", Vector2i.ZERO) as Vector2i
	var stand_tile: Vector2i = snapshot.get("stand_tile", Vector2i.ZERO) as Vector2i
	var dig_dir: Vector2i = mountain_tile - stand_tile
	var dug_count: int = 0
	for step: int in range(DIG_TUNNEL_TILES):
		var dig_tile: Vector2i = mountain_tile + dig_dir * step
		var world_pos: Vector2 = WorldRuntimeConstants.tile_to_world_center(dig_tile)
		if not bool(streamer.call("has_resource_at_world", world_pos)):
			break
		var result: Dictionary = streamer.call("try_harvest_at_world", world_pos) as Dictionary
		if not bool(result.get("success", false)):
			break
		dug_count += 1
		print("RENDER_PROBE stage=dug tile=%s" % str(dig_tile))
		for _frame: int in range(20):
			await process_frame
	_assert(dug_count >= 1, "Probe must dig at least one mountain tile.")
	print("RENDER_PROBE stage=dig_done dug=%d" % dug_count)
	# После копка точка стояния может легитимно стать непроходимой:
	# перерисованная губа фасада нависает над соседним тайлом.
	snapshot = await _wait_settled(scene, false)
	_assert(_is_settled(snapshot, false), "Native masks must settle after digging.")
	print("RENDER_PROBE stage=settled_after_dig")
	for _frame: int in range(30):
		await process_frame
	_capture("%s/after_dig_%d_tiles.png" % [OUTPUT_DIR, dug_count])
	print("RENDER_PROBE dug=%d target=%s stand=%s" % [dug_count, str(mountain_tile), str(stand_tile)])
	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)

func _wait_settled(scene: Node, require_stand_walkable: bool = true) -> Dictionary:
	var snapshot: Dictionary = { }
	for _frame: int in range(MAX_SETTLE_FRAMES):
		snapshot = scene.call("get_debug_snapshot") as Dictionary
		if _is_settled(snapshot, require_stand_walkable):
			return snapshot
		await process_frame
	print("RENDER_PROBE settle_timeout native=%s stand_walkable=%s" % [
		str(snapshot.get("native", { })),
		str(snapshot.get("stand_walkable", false)),
	])
	return snapshot

func _is_settled(snapshot: Dictionary, require_stand_walkable: bool = true) -> bool:
	if not bool(snapshot.get("ready", false)):
		return false
	var native: Dictionary = snapshot.get("native", { }) as Dictionary
	if native.is_empty():
		return false
	if int(native.get("missing_mountain_chunk_count", 99)) > 0:
		return false
	if int(native.get("ready_native_mask_chunk_count", 0)) <= 0:
		return false
	if bool(native.get("dirty", false)) or bool(native.get("request_in_flight", false)):
		return false
	if int(native.get("native_mask_visual_upload_queue_count", 0)) > 0 \
			or int(native.get("native_mask_visual_pending_count", 0)) > 0:
		return false
	if not require_stand_walkable:
		return true
	return bool(snapshot.get("stand_walkable", false))

func _viewport_center_brightness() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
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


func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var viewport_image: Image = root.get_texture().get_image()
	if viewport_image == null:
		_assert(false, "Viewport image must be available for %s." % path)
		return
	var err: Error = viewport_image.save_png(path)
	_assert(err == OK, "Screenshot must save to %s (err %d)." % [path, err])

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
