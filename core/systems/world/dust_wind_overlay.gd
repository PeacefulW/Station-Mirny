class_name DustWindOverlay
extends WorldViewOverlay
## Слой летящей пыли (визуальный спидометр ветра). Плотность, длина стриков и
## непрозрачность пыли растут с wind_strength; скролл — по wind_* global
## uniforms (dust_wind_overlay.gdshader). Инфраструктура слоя — в
## WorldViewOverlay.

const DUST_SHADER = preload("res://assets/shaders/dust_wind_overlay.gdshader")
const DUST_Z_INDEX: int = 400


func _overlay_shader() -> Shader:
	return DUST_SHADER


func _overlay_z() -> int:
	return DUST_Z_INDEX
