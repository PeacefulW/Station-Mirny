class_name CloudShadowOverlay
extends WorldViewOverlay
## Слой бегущих теней облаков (cloud_shadow_overlay.gdshader): мягкие тёмные
## пятна, плотность которых растёт с облачностью WeatherRuntime, дрейф по
## ветру. При ясном небе слой пуст (почти бесплатен). Инфраструктура слоя —
## в WorldViewOverlay. Контракт: docs/02_system_specs/world/weather_runtime.md

const CLOUD_SHADER = preload("res://assets/shaders/cloud_shadow_overlay.gdshader")
const CLOUD_Z_INDEX: int = 395


func _overlay_shader() -> Shader:
	return CLOUD_SHADER


func _overlay_z() -> int:
	return CLOUD_Z_INDEX


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	if WeatherRuntime != null:
		overlay_material.set_shader_parameter("cloud_cover", WeatherRuntime.get_cloud_cover())
