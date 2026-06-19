class_name CloudShadowOverlay
extends WorldViewOverlay
## Слой бегущих теней облаков (cloud_shadow_overlay.gdshader): мягкие тёмные
## пятна, плотность которых растёт с облачностью WeatherRuntime, дрейф по
## ветру. При ясном небе слой пуст (почти бесплатен). Инфраструктура слоя —
## в WorldViewOverlay. Контракт: docs/02_system_specs/world/weather_runtime.md

const CLOUD_SHADER = preload("res://assets/shaders/cloud_shadow_overlay.gdshader")
const CLOUD_Z_INDEX: int = 395
const NOISE_TEX_SIZE: int = 256

var _current_z: int = 0
var _noise_texture: NoiseTexture2D = null


func _ready() -> void:
	super._ready()
	_current_z = _resolve_current_z()
	if EventBus != null and not EventBus.z_level_changed.is_connected(_on_z_level_changed):
		EventBus.z_level_changed.connect(_on_z_level_changed)


func set_active_z_level(new_z: int) -> void:
	_current_z = new_z


func _overlay_shader() -> Shader:
	return CLOUD_SHADER


func _overlay_z() -> int:
	return CLOUD_Z_INDEX


func _on_overlay_ready(overlay_material: ShaderMaterial) -> void:
	# Бесшовная процедурная текстура шума -> поле теней без сеточных артефактов
	# точности на больших мировых координатах (см. шейдер). Генерится в потоке.
	overlay_material.set_shader_parameter("cloud_noise", _build_noise_texture())


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	# Тени облаков — outside-only (sanctuary): под землёй cloud_cover=0, чтобы
	# слой не затемнял раскрытое подземелье у игрока, как и flatten/sun-ray.
	var cloud_cover: float = 0.0
	if _is_surface_context() and WeatherRuntime != null:
		cloud_cover = WeatherRuntime.get_cloud_cover()
	overlay_material.set_shader_parameter("cloud_cover", cloud_cover)


func _build_noise_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = NOISE_TEX_SIZE
	tex.height = NOISE_TEX_SIZE
	tex.seamless = true
	tex.seamless_blend_skirt = 0.2
	tex.generate_mipmaps = true
	tex.noise = noise
	_noise_texture = tex
	return tex


func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	set_active_z_level(new_z)


func _is_surface_context() -> bool:
	return _current_z == 0


func _resolve_current_z() -> int:
	var z_managers: Array[Node] = get_tree().get_nodes_in_group("z_level_manager")
	if z_managers.is_empty():
		return 0
	var z_manager: Node = z_managers[0]
	if z_manager.has_method("get_current_z"):
		return int(z_manager.get_current_z())
	return 0
