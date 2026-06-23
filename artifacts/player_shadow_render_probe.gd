extends SceneTree

# Рендер-проба тени игрока (изолированно, без мира) в SubViewport фикс. размера:
# тело (Visual, полупрозрачное) + PlayerSunShadow при разных условиях солнца.
# Красная линия = фиксированная линия земли (ground_uv_y). Основание тени должно
# лежать на ней во всех кадрах бега (без дрожания), не отрываться.
# Windowed (захват вьюпорта требует GPU). Запуск:
#   godot --path . -s artifacts/player_shadow_render_probe.gd

const ShadowScript = preload("res://core/entities/player/player_sun_shadow.gd")
const IDLE_TEX: Texture2D = preload("res://assets/sprites/player/player_idle_mixamo_16dir_16frames_256.png")
const RUN_TEX: Texture2D = preload("res://assets/sprites/player/player_run_forward_mixamo_16dir_16frames_256.png")
const OUTPUT_DIR: String = "res://artifacts/player_shadow_render_probe"
const FRAME: int = 256
const VP: Vector2i = Vector2i(420, 460)
const SCALE: float = 0.85
const GROUND_UV: float = 0.773

var _vp: SubViewport = null
var _visual: Sprite2D = null
var _shadow: Sprite2D = null
var _origin := Vector2(170, 165)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("player_shadow_render_probe: must run windowed")
		quit(1)
		return
	DirAccess.open("res://").make_dir_recursive("artifacts/player_shadow_render_probe")

	_vp = SubViewport.new()
	_vp.size = VP
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	root.add_child(_vp)

	var bg := ColorRect.new()
	bg.color = Color(0.30, 0.32, 0.28)
	bg.size = VP
	_vp.add_child(bg)

	# Линия земли (куда обязан садиться контакт ног).
	var ground := Line2D.new()
	var gy: float = _origin.y + (GROUND_UV - 0.5) * FRAME * SCALE
	ground.add_point(Vector2(0, gy))
	ground.add_point(Vector2(VP.x, gy))
	ground.width = 1.0
	ground.default_color = Color(0.9, 0.2, 0.2, 0.9)
	ground.z_index = 40
	_vp.add_child(ground)

	var container := Node2D.new()
	container.position = _origin
	_vp.add_child(container)

	_visual = Sprite2D.new()
	_visual.name = "Visual"
	_visual.texture = IDLE_TEX
	_visual.region_enabled = true
	_visual.region_rect = Rect2(0, 0, FRAME, FRAME)
	_visual.scale = Vector2(SCALE, SCALE)
	_visual.modulate = Color(1, 1, 1, 1.0)  # непрозрачное тело — как в игре
	_visual.z_index = 30                       # тело выше тени (как в игре)
	container.add_child(_visual)

	_shadow = ShadowScript.new()
	_shadow.name = "SunShadow"
	container.add_child(_shadow)
	_shadow.visual_node_path = ^"../Visual"

	await _wait(6)

	await _shot("01_idle_default_hour10")

	_force_sun(0.5, 1.1, Vector2(0.45, 0.62))
	await _shot("02_idle_low_sun")

	_set_frame(RUN_TEX, 0, 0)
	_force_sun(0.5, 1.1, Vector2(0.45, 0.62))
	await _shot("03_run_f0")
	_set_frame(RUN_TEX, 6, 0)
	_force_sun(0.5, 1.1, Vector2(0.45, 0.62))
	await _shot("04_run_f6")
	_set_frame(RUN_TEX, 11, 0)
	_force_sun(0.5, 1.1, Vector2(0.45, 0.62))
	await _shot("05_run_f11")

	_set_frame(IDLE_TEX, 0, 0)
	_force_sun(0.28, 0.5, Vector2(0.45, 0.62))
	await _shot("06_idle_high_sun")

	# --- Диагностика: подсветить контактное пятно красным, чтобы видеть, где оно
	# и как «врастает» в силуэт. Это только проба, на боевую тень не влияет. ---
	_set_frame(IDLE_TEX, 0, 0)
	_force_sun(0.0, 1.0, Vector2(0.45, 0.62))         # силуэт прозрачный
	_shadow._contact_pool.self_modulate = Color(0.9, 0.12, 0.12, 0.85)
	await _shot("07_dbg_pool_only")
	_force_sun(0.55, 1.0, Vector2(0.45, 0.62))        # тёмный силуэт + красное пятно
	_shadow._contact_pool.self_modulate = Color(0.9, 0.12, 0.12, 0.7)
	await _shot("08_dbg_pool_red_plus_silhouette")

	print("player_shadow_render_probe: DONE -> %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _set_frame(tex: Texture2D, col: int, row: int) -> void:
	_visual.texture = tex
	_visual.region_rect = Rect2(col * FRAME, row * FRAME, FRAME, FRAME)
	_shadow.set_physics_process(false)
	_shadow._sync_visual_frame()


func _force_sun(opacity: float, projection: float, dir: Vector2) -> void:
	_shadow.set_physics_process(false)
	_shadow.visible = true
	var mat: ShaderMaterial = _shadow.material as ShaderMaterial
	mat.set_shader_parameter("shadow_opacity", opacity)
	mat.set_shader_parameter("shadow_projection", projection)
	mat.set_shader_parameter("shadow_dir", dir.normalized())
	_shadow._update_contact_pool(dir.normalized(), projection, opacity)


func _shot(probe_name: String) -> void:
	await _wait(4)
	var img: Image = await _capture()
	img.save_png("%s/%s.png" % [OUTPUT_DIR, probe_name])
	var mat: ShaderMaterial = _shadow.material as ShaderMaterial
	print("player_shadow_render_probe: %s visible=%s contact=%.3f opacity=%.3f" % [
		probe_name,
		str(_shadow.visible),
		float(mat.get_shader_parameter("contact_uv_y")),
		float(mat.get_shader_parameter("shadow_opacity")),
	])


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


func _wait(count: int) -> void:
	for _i: int in range(count):
		await process_frame
