extends SceneTree

# Рендер-проба Итерации 1 спеки wind_and_grass_scatter_presentation:
# 1) motion: при фиксированном override (сила 0.85, угол 0°) кадры с шагом
#    ~0.7с различаются, фронты порывов бегут по ветру (панель motion_panel.png)
# 2) freeze: при wind_strength = 0 кадры с интервалом идентичны попиксельно
# 3) pause: при паузе дерева кадры идентичны (WindRuntime паузится с деревом).
# Windowed (захват вьюпорта требует GPU). Запуск:
#   Godot_v4.6.2-stable_win64_console.exe -s tools/wind_gust_probe.gd

const DEV_SCENE: String = "res://scenes/dev/grass_wind_dev_scene.tscn"
const OUTPUT_DIR: String = "res://artifacts/wind_gust_probe"
const MOTION_FRAME_STEP: int = 42
const SETTLE_FRAMES: int = 24
# Прогрев async-компиляции пайплайнов (D3D12): свежеизменённый шейдер может
# подменить ubershader на специализированный посреди замеров и исказить
# попиксельные сравнения, не имея отношения к движению травы.
const WARMUP_FRAMES: int = 180
const PANEL_DIVIDER_PX: int = 4

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("wind_gust_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load(DEV_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var hud: CanvasLayer = scene.get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		# HUD показывает живое wind_time и испортил бы попиксельные сравнения.
		hud.visible = false
	DirAccess.open("res://").make_dir_recursive("artifacts/wind_gust_probe")

	var wind: Node = root.get_node_or_null("WindRuntime")
	if wind == null:
		push_error("wind_gust_probe: WindRuntime autoload missing")
		quit(1)
		return

	await _wait_frames(WARMUP_FRAMES)

	# --- motion: бегущие фронты при фиксированной силе/направлении ---
	wind.call("set_debug_strength_override", 0.85)
	wind.call("set_debug_direction_override_deg", 0.0)
	await _wait_frames(SETTLE_FRAMES)
	var motion_frames: Array[Image] = []
	for capture_index: int in range(3):
		var img: Image = await _capture()
		img.save_png("%s/motion_%d.png" % [OUTPUT_DIR, capture_index])
		motion_frames.append(img)
		if capture_index < 2:
			await _wait_frames(MOTION_FRAME_STEP)
	_check(
		not _images_identical(motion_frames[0], motion_frames[1]),
		"motion: кадры t0/t1 различаются (ветер движет траву)",
	)
	_check(
		not _images_identical(motion_frames[1], motion_frames[2]),
		"motion: кадры t1/t2 различаются (движение продолжается)",
	)
	_save_panel(motion_frames, "%s/motion_panel.png" % OUTPUT_DIR)
	_save_motion_diff(motion_frames[0], motion_frames[1], "%s/motion_diff_t0_t1.png" % OUTPUT_DIR)
	_save_motion_diff(motion_frames[1], motion_frames[2], "%s/motion_diff_t1_t2.png" % OUTPUT_DIR)

	# --- диагностика: gust-поле яркостью (фронты и их бег видны напрямую) ---
	_set_debug_gust_view(scene, 1.0)
	await _wait_frames(SETTLE_FRAMES)
	var gust_a: Image = await _capture()
	await _wait_frames(MOTION_FRAME_STEP)
	var gust_b: Image = await _capture()
	gust_a.save_png("%s/gust_field_a.png" % OUTPUT_DIR)
	gust_b.save_png("%s/gust_field_b.png" % OUTPUT_DIR)
	_set_debug_gust_view(scene, 0.0)

	# --- no-stretch: сила меняет темп, а не размах — силуэты не длиннее ---
	wind.call("set_debug_strength_override", 0.25)
	await _wait_frames(SETTLE_FRAMES)
	var strength_low: Image = await _capture()
	wind.call("set_debug_strength_override", 1.0)
	await _wait_frames(SETTLE_FRAMES)
	var strength_high: Image = await _capture()
	strength_low.save_png("%s/strength_low.png" % OUTPUT_DIR)
	strength_high.save_png("%s/strength_high.png" % OUTPUT_DIR)
	var strength_frames: Array[Image] = [strength_low, strength_high]
	_save_panel(strength_frames, "%s/strength_compare_panel.png" % OUTPUT_DIR)
	var strength_crops: Array[Image] = [_center_crop(strength_low), _center_crop(strength_high)]
	_save_panel(strength_crops, "%s/strength_compare_crop_panel.png" % OUTPUT_DIR)

	# --- freeze: сила 0 замораживает траву, время продолжает идти ---
	wind.call("set_debug_strength_override", 0.0)
	await _wait_frames(SETTLE_FRAMES)
	var freeze_a: Image = await _capture()
	await _wait_frames(MOTION_FRAME_STEP)
	var freeze_b: Image = await _capture()
	var freeze_identical: bool = _images_identical(freeze_a, freeze_b)
	if not freeze_identical:
		# Одноразовые события рендера (поздняя специализация пайплайна)
		# не повторяются: настоящее движение провалит и второе сравнение.
		print("wind_gust_probe: freeze retry (first comparison differed)")
		_print_diff_stats(freeze_a, freeze_b, "freeze_first")
		await _wait_frames(WARMUP_FRAMES)
		freeze_a = await _capture()
		await _wait_frames(MOTION_FRAME_STEP)
		freeze_b = await _capture()
		freeze_identical = _images_identical(freeze_a, freeze_b)
	freeze_a.save_png("%s/freeze_a.png" % OUTPUT_DIR)
	freeze_b.save_png("%s/freeze_b.png" % OUTPUT_DIR)
	_check(freeze_identical, "freeze: wind_strength=0 даёт попиксельно идентичные кадры")
	if not freeze_identical:
		_print_diff_stats(freeze_a, freeze_b, "freeze")
		_save_motion_diff(freeze_a, freeze_b, "%s/freeze_diff.png" % OUTPUT_DIR)

	# --- pause: пауза дерева останавливает WindRuntime и траву ---
	wind.call("set_debug_strength_override", 0.85)
	await _wait_frames(SETTLE_FRAMES)
	paused = true
	await _wait_frames(SETTLE_FRAMES)
	var pause_a: Image = await _capture()
	await _wait_frames(MOTION_FRAME_STEP)
	var pause_b: Image = await _capture()
	var pause_identical: bool = _images_identical(pause_a, pause_b)
	if not pause_identical:
		# Та же защита, что у freeze: одноразовые события рендера не
		# повторяются, настоящее движение провалит и второе сравнение.
		print("wind_gust_probe: pause retry (first comparison differed)")
		_print_diff_stats(pause_a, pause_b, "pause_first")
		await _wait_frames(WARMUP_FRAMES)
		pause_a = await _capture()
		await _wait_frames(MOTION_FRAME_STEP)
		pause_b = await _capture()
		pause_identical = _images_identical(pause_a, pause_b)
	paused = false
	pause_a.save_png("%s/pause_a.png" % OUTPUT_DIR)
	pause_b.save_png("%s/pause_b.png" % OUTPUT_DIR)
	_check(
		pause_identical,
		"pause: пауза дерева даёт попиксельно идентичные кадры",
	)

	wind.call("clear_debug_wind_override")
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("wind_gust_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("wind_gust_probe: FAILED %s" % failure)
		quit(1)


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


func _check(passed: bool, description: String) -> void:
	if passed:
		print("wind_gust_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("wind_gust_probe: FAIL %s" % description)


func _set_debug_gust_view(scene: Node, value: float) -> void:
	for child: Node in scene.get_children():
		var layer := child as MultiMeshInstance2D
		if layer == null:
			continue
		var material := layer.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("debug_gust_view", value)


# Карта движения: |a - b| с усилением. Вытянутые светлые области — фронты
# порывов; их смещение между двумя diff-картами — бег фронтов по ветру.
func _save_motion_diff(a: Image, b: Image, path: String) -> void:
	var half_a: Image = a.duplicate() as Image
	var half_b: Image = b.duplicate() as Image
	half_a.resize(a.get_width() / 2, a.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	half_b.resize(b.get_width() / 2, b.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	var diff := Image.create(half_a.get_width(), half_a.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in range(half_a.get_height()):
		for x: int in range(half_a.get_width()):
			var ca: Color = half_a.get_pixel(x, y)
			var cb: Color = half_b.get_pixel(x, y)
			var amount: float = clampf(
				(absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) * 1.8,
				0.0,
				1.0,
			)
			diff.set_pixel(x, y, Color(amount, amount, amount, 1.0))
	diff.save_png(path)
	print("wind_gust_probe: motion diff saved %s" % ProjectSettings.globalize_path(path))


func _print_diff_stats(a: Image, b: Image, label: String) -> void:
	var data_a: PackedByteArray = a.get_data()
	var data_b: PackedByteArray = b.get_data()
	if data_a.size() != data_b.size():
		print("wind_gust_probe: %s diff sizes %d vs %d" % [label, data_a.size(), data_b.size()])
		return
	var differing: int = 0
	var max_delta: int = 0
	for index: int in range(data_a.size()):
		var delta: int = absi(int(data_a[index]) - int(data_b[index]))
		if delta > 0:
			differing += 1
			max_delta = maxi(max_delta, delta)
	print(
		"wind_gust_probe: %s diff bytes=%d/%d max_delta=%d" % [
			label,
			differing,
			data_a.size(),
			max_delta,
		],
	)


# Центральная четверть кадра 1:1 — детали наклона пучков без ужатия превью.
func _center_crop(source: Image) -> Image:
	var size: Vector2i = source.get_size()
	var crop_size := Vector2i(size.x / 2, size.y / 2)
	var origin := Vector2i((size.x - crop_size.x) / 2, (size.y - crop_size.y) / 2)
	return source.get_region(Rect2i(origin, crop_size))


func _images_identical(a: Image, b: Image) -> bool:
	if a == null or b == null:
		return false
	if a.get_size() != b.get_size():
		return false
	return a.get_data() == b.get_data()


func _save_panel(frames: Array[Image], path: String) -> void:
	if frames.is_empty():
		return
	var frame_size: Vector2i = frames[0].get_size()
	var panel := Image.create(
		frame_size.x * frames.size() + PANEL_DIVIDER_PX * (frames.size() - 1),
		frame_size.y,
		false,
		frames[0].get_format(),
	)
	panel.fill(Color.BLACK)
	for index: int in range(frames.size()):
		panel.blit_rect(
			frames[index],
			Rect2i(Vector2i.ZERO, frame_size),
			Vector2i(index * (frame_size.x + PANEL_DIVIDER_PX), 0),
		)
	panel.save_png(path)
	print("wind_gust_probe: panel saved %s" % ProjectSettings.globalize_path(path))
