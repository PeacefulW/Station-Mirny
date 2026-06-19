extends SceneTree

# Воспроизводит ПЕРЕХОД к пасмурно (рампа cloud_cover) и измеряет
# горизонтальный разброс яркости по 5 вертикальным полосам на каждом шаге.
# Гипотеза: при низкочастотном теневом поле падающий порог гонит изолинию
# тени поперёк экрана -> большой разброс L..R на средних cloud_cover (полоса),
# и тёмная сторона мигрирует слева направо. Daylight заморожен (изолируем тень).
# Windowed:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/cloud_transition_probe.gd

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const LakeGenSettings = preload("res://core/resources/lake_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const DefaultLakeGenSettings = preload("res://data/balance/lake_gen_settings.tres")

const OUTPUT_DIR: String = "res://artifacts/cloud_transition_probe"
const STEPS: Array = [0.05, 0.12, 0.2, 0.3, 0.42, 0.55, 0.68, 0.8]

var _streamer: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cloud_transition_probe: must run windowed")
		quit(1)
		return
	var scene: Node = (load("res://scenes/world/world_runtime_v0.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	_streamer = scene.get_node("WorldStreamer")
	var tm: Node = root.get_node("TimeManager")
	var daylight: CanvasModulate = scene.get_node("Daylight") as CanvasModulate
	var cloud: Sprite2D = scene.get_node("CloudShadowOverlay") as Sprite2D
	var cam: Camera2D = scene.get_node("Player/Camera2D")
	var bounds: WorldBoundsSettings = WorldBoundsSettings.hard_coded_defaults()
	_streamer.initialize_new_world(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		MountainGenSettings.hard_coded_defaults(),
		bounds,
		FoundationGenSettings.for_bounds(bounds),
		LakeGenSettings.from_save_dict(DefaultLakeGenSettings.to_save_dict()),
	)
	tm.call("set_paused", true)
	tm.call("restore_persisted_state", 12.0, 1, 0)
	tm.call("set_paused", true)
	cam.enabled = true
	cam.position_smoothing_enabled = false
	cam.set_process(false)
	cam.zoom = Vector2(0.4, 0.4)
	cam.set("_target_zoom", 0.4)
	DirAccess.open("res://").make_dir_recursive("artifacts/cloud_transition_probe")
	await _settle()
	cam.force_update_scroll()

	# Заморозить Daylight в нейтраль и сам слой — рулим cloud_cover вручную.
	daylight.set_process(false)
	daylight.color = Color.WHITE
	cloud.set_process(false)
	var mat: ShaderMaterial = cloud.material as ShaderMaterial
	_position_overlay(cloud, mat, cam)
	await _wait(10)

	print("cloud_transition_probe: cc | L ML M MR R | spread | darkest_band")
	for cc: float in STEPS:
		mat.set_shader_parameter("cloud_cover", cc)
		_position_overlay(cloud, mat, cam)
		await _wait(10)
		var img: Image = await _capture()
		var prof: Array = _column_luma_profile(img)
		var lo: float = prof.min()
		var hi: float = prof.max()
		var darkest: int = prof.find(lo)
		print(
			"cloud_transition_probe: %.2f | %.3f %.3f %.3f %.3f %.3f | %.3f | band %d" % [
				cc,
				prof[0],
				prof[1],
				prof[2],
				prof[3],
				prof[4],
				hi - lo,
				darkest,
			],
		)
		if cc == 0.3 or cc == 0.55:
			img.save_png("%s/ramp_%02d.png" % [OUTPUT_DIR, int(cc * 100.0)])
	print("cloud_transition_probe: DONE")
	scene.queue_free()
	await process_frame
	quit(0)


func _position_overlay(cloud: Sprite2D, mat: ShaderMaterial, cam: Camera2D) -> void:
	var margin: float = 1.06
	var zoom: Vector2 = Vector2(maxf(cam.zoom.x, 0.001), maxf(cam.zoom.y, 0.001))
	var view_size: Vector2 = cam.get_viewport().get_visible_rect().size / zoom
	var view_center: Vector2 = cam.get_screen_center_position()
	cloud.global_position = view_center
	cloud.scale = view_size * margin
	mat.set_shader_parameter("view_world_origin", view_center - view_size * (margin * 0.5))
	mat.set_shader_parameter("view_world_size", view_size * margin)


func _column_luma_profile(source: Image) -> Array:
	var img: Image = source.duplicate() as Image
	img.resize(100, 56, Image.INTERPOLATE_BILINEAR)
	var bands: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var counts: Array = [0, 0, 0, 0, 0]
	for x: int in range(img.get_width()):
		var bi: int = clampi(int(float(x) / float(img.get_width()) * 5.0), 0, 4)
		for y: int in range(img.get_height()):
			var c: Color = img.get_pixel(x, y)
			bands[bi] += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			counts[bi] += 1
	for i: int in range(5):
		bands[i] = bands[i] / maxf(float(counts[i]), 1.0)
	return bands


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _wait(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _settle() -> void:
	for _i: int in range(500):
		_streamer._streaming_tick()
		_streamer._mountain_native_mask_visual_apply_tick()
		await process_frame
		if _streamer._requested_chunks.is_empty() and not _streamer._has_pending_streaming_work():
			return
