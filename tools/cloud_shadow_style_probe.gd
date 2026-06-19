extends SceneTree

# Static style guard for cloud-shadow readability:
# clouds should read as real Godot-like shadows: a screen-space darkening mask
# over the already rendered surface, not a colored cloud-shaped paint layer.
# Запуск:
#   Godot_v4.7-stable_win64_console.exe --headless --path . -s tools/cloud_shadow_style_probe.gd

const SHADER_PATH: String = "res://assets/shaders/cloud_shadow_overlay.gdshader"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source: String = FileAccess.get_file_as_string(SHADER_PATH)
	var scale_px: float = _extract_float_uniform(source, "cloud_scale_px")
	var opacity: float = _extract_float_uniform(source, "cloud_shadow_opacity")
	var darkening: float = _extract_float_uniform(source, "cloud_shadow_darkening")
	var effective_darkening: float = opacity * darkening
	var uses_screen_texture: bool = source.contains("hint_screen_texture") and source.contains("SCREEN_UV")
	var paints_color: bool = source.contains("cloud_shadow_color")

	print(
		"cloud_shadow_style_probe: screen_texture=%s paints_color=%s scale=%.1f opacity=%.3f darkening=%.3f effective=%.3f" % [
			str(uses_screen_texture),
			str(paints_color),
			scale_px,
			opacity,
			darkening,
			effective_darkening,
		],
	)
	_check(uses_screen_texture, "тень затемняет уже отрисованную поверхность через screen texture")
	_check(not paints_color, "shader не рисует отдельный cloud_shadow_color поверх мира")
	_check(scale_px >= 5600.0, "cloud footprint остаётся крупным (scale=%.1f)" % scale_px)
	_check(opacity >= 0.35 and opacity <= 0.70, "opacity даёт мягкую маску, не чёрную заливку (opacity=%.3f)" % opacity)
	_check(darkening >= 0.22 and darkening <= 0.42, "darkening похож на обычную тень, не на чёрное пятно (darkening=%.3f)" % darkening)
	_check(effective_darkening <= 0.25, "пиковое затемнение ограничено (effective=%.3f)" % effective_darkening)

	if _failures.is_empty():
		print("cloud_shadow_style_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for failure: String in _failures:
			print("cloud_shadow_style_probe: FAILED %s" % failure)
		quit(1)


func _extract_float_uniform(source: String, uniform_name: String) -> float:
	var pattern := RegEx.new()
	pattern.compile("uniform\\s+float\\s+%s\\s*=\\s*([0-9.]+)" % uniform_name)
	var result: RegExMatch = pattern.search(source)
	if result == null:
		return 0.0
	return float(result.get_string(1))


func _check(passed: bool, description: String) -> void:
	if passed:
		print("cloud_shadow_style_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("cloud_shadow_style_probe: FAIL %s" % description)
