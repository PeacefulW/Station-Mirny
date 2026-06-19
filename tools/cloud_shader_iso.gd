extends SceneTree

# Полная изоляция облачного шейдера: серый фон + один ColorRect с
# cloud_shadow_overlay.gdshader. Никакого мира, травы, Daylight. Снимаем поле
# тени на спавн-координатах и далеко, при игровом зуме 1.0. Если вертикальные
# прямоугольные полосы видны ЗДЕСЬ -> это сам шейдер (шум/точность), не грунт.
# Windowed:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/cloud_shader_iso.gd

const CLOUD_SHADER = preload("res://assets/shaders/cloud_shadow_overlay.gdshader")
const OUTPUT_DIR: String = "res://artifacts/cloud_shader_iso"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cloud_shader_iso: must run windowed")
		quit(1)
		return
	DirAccess.open("res://").make_dir_recursive("artifacts/cloud_shader_iso")
	var view_px: Vector2 = root.get_visible_rect().size

	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.45, 0.45)
	bg.size = view_px
	root.add_child(bg)

	var cloud := ColorRect.new()
	cloud.size = view_px
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	mat.set_shader_parameter("cloud_cover", 0.5)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.seamless_blend_skirt = 0.2
	tex.generate_mipmaps = true
	tex.noise = noise
	mat.set_shader_parameter("cloud_noise", tex)
	cloud.material = mat
	root.add_child(cloud)
	while tex.get_image() == null: # дождаться потоковой генерации текстуры
		await process_frame

	# Глобалы ветра (обычно их пишет WindRuntime) фиксируем сами.
	RenderingServer.global_shader_parameter_set("wind_gust_scroll_px", Vector2(120.0, 30.0))
	RenderingServer.global_shader_parameter_set("wind_time", 4.0)

	# Игровой зум 1.0: world-видимая область = пиксели вида / zoom = пиксели вида.
	var view_size: Vector2 = view_px # zoom 1.0
	var margin: float = 1.06

	var spawn := Vector2(14368.0, 43040.0)
	_set_sample(mat, spawn, view_size, margin)
	await _frame()
	var spawn_img: Image = await _capture()
	spawn_img.save_png("%s/iso_spawn.png" % OUTPUT_DIR)

	var far := spawn + Vector2(400000.0, 250000.0)
	_set_sample(mat, far, view_size, margin)
	await _frame()
	var far_img: Image = await _capture()
	far_img.save_png("%s/iso_far.png" % OUTPUT_DIR)

	# Ближе к нулю координат — контроль (точность лучшая; эталон гладкости).
	_set_sample(mat, Vector2(800.0, 600.0), view_size, margin)
	await _frame()
	var origin_img: Image = await _capture()
	origin_img.save_png("%s/iso_origin.png" % OUTPUT_DIR)

	# Метрика "резких краёв": доля пикселей с большим горизонтальным скачком
	# яркости. Сеточная нарезка точности (старый ручной хеш) даёт МНОГО резких
	# краёв на дальних координатах; бесшовная текстура держит far ~ origin.
	var origin_edges: float = _sharp_edge_fraction(origin_img)
	var spawn_edges: float = _sharp_edge_fraction(spawn_img)
	var far_edges: float = _sharp_edge_fraction(far_img)
	print(
		"cloud_shader_iso: sharp-edge fraction origin=%.4f spawn=%.4f far=%.4f" % [
			origin_edges,
			spawn_edges,
			far_edges,
		],
	)
	var ok: bool = far_edges < origin_edges * 2.0 + 0.01
	if ok:
		print("cloud_shader_iso: PASS far гладкий как origin (нет сеточной нарезки точности)")
		print("cloud_shader_iso: ALL CHECKS PASSED")
		quit(0)
	else:
		print(
			"cloud_shader_iso: FAILED сеточная нарезка на дальних координатах (far=%.4f >> origin=%.4f)" % [
				far_edges,
				origin_edges,
			],
		)
		quit(1)


func _sharp_edge_fraction(source: Image) -> float:
	var img: Image = source.duplicate() as Image
	img.resize(220, 124, Image.INTERPOLATE_BILINEAR)
	var sharp: int = 0
	var total: int = 0
	for y: int in range(img.get_height()):
		for x: int in range(1, img.get_width()):
			var a: Color = img.get_pixel(x, y)
			var b: Color = img.get_pixel(x - 1, y)
			var la: float = a.r * 0.299 + a.g * 0.587 + a.b * 0.114
			var lb: float = b.r * 0.299 + b.g * 0.587 + b.b * 0.114
			if absf(la - lb) > 0.05:
				sharp += 1
			total += 1
	return float(sharp) / maxf(float(total), 1.0)


func _set_sample(mat: ShaderMaterial, center: Vector2, view_size: Vector2, margin: float) -> void:
	mat.set_shader_parameter("view_world_origin", center - view_size * (margin * 0.5))
	mat.set_shader_parameter("view_world_size", view_size * margin)


func _frame() -> void:
	for _i: int in range(4):
		await process_frame


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
