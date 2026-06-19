class_name CloudShadowOverlay
extends WorldViewOverlay
## Слой бегущих теней облаков (cloud_shadow_overlay.gdshader): мягкие тёмные
## пятна, плотность которых растёт с облачностью WeatherRuntime, дрейф по
## ветру. При ясном небе слой пуст (почти бесплатен). Инфраструктура слоя —
## в WorldViewOverlay. Контракт: docs/02_system_specs/world/weather_runtime.md

const CLOUD_SHADER = preload("res://assets/shaders/cloud_shadow_overlay.gdshader")
const CLOUD_Z_INDEX: int = 395
const NOISE_TEX_SIZE: int = 256

var _noise_texture: NoiseTexture2D = null


func _overlay_shader() -> Shader:
	return CLOUD_SHADER


func _overlay_z() -> int:
	return CLOUD_Z_INDEX


func _on_overlay_ready(overlay_material: ShaderMaterial) -> void:
	# Бесшовная процедурная текстура шума -> поле теней без сеточных артефактов
	# точности на больших мировых координатах (см. шейдер). Генерится в потоке.
	overlay_material.set_shader_parameter("cloud_noise", _build_noise_texture())


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	if WeatherRuntime != null:
		overlay_material.set_shader_parameter("cloud_cover", WeatherRuntime.get_cloud_cover())


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
