extends SceneTree

# Статический guard структуры ветрового отклика травы (Iteration 4):
# - трава читает wind_gustiness
# - локальный поворот направления (local_dir через поворот глобального ветра)
# - внутрикустовая рябь по ширине квада (intra_tuft_flutter + UV.x)
# - колебание по local_dir, а storm_lean — по ГЛОБАЛьному ветру
# - запрет амплитуды от силы: нет произведения wind_strength * oscillation.
# Запуск:
#   Godot_v4.7-stable_win64_console.exe --headless --path . -s tools/grass_wind_style_probe.gd

const SHADER_PATH: String = "res://assets/shaders/grass_scatter_batch.gdshader"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var src: String = FileAccess.get_file_as_string(SHADER_PATH)
	var reads_gustiness: bool = src.contains("global uniform float wind_gustiness")
	var has_local_dir: bool = (
		src.contains("local_angle")
		and src.contains("local_dir = vec2")
		and src.contains("cos(local_angle)")
	)
	var swirl_in_gust: bool = src.contains("gust * local_dir_gust_gain")
	var intra_uv_x: bool = src.contains("intra_tuft_flutter") and src.contains("UV.x")
	var osc_local: bool = src.contains("local_dir * oscillation")
	var storm_global: bool = src.contains("dir * storm_lean")
	var no_strength_amp: bool = (
		not src.contains("wind_strength * oscillation")
		and not src.contains("oscillation * wind_strength")
		and not src.contains("wind_strength * sway")
	)

	print(
		(
			"grass_wind_style_probe: gustiness=%s local_dir=%s swirl=%s intra=%s "
			+ "osc_local=%s storm_global=%s no_strength_amp=%s"
		)
		% [
			str(reads_gustiness),
			str(has_local_dir),
			str(swirl_in_gust),
			str(intra_uv_x),
			str(osc_local),
			str(storm_global),
			str(no_strength_amp),
		],
	)
	_check(reads_gustiness, "трава читает глобал wind_gustiness")
	_check(has_local_dir, "локальный поворот направления (local_dir из поворота ветра)")
	_check(swirl_in_gust, "локальное отклонение усиливается во фронте порыва (gust gain)")
	_check(intra_uv_x, "внутрикустовая рябь по ширине квада (intra_tuft_flutter + UV.x)")
	_check(osc_local, "колебание идёт по локальному направлению")
	_check(storm_global, "storm_lean остаётся по глобальному ветру")
	_check(no_strength_amp, "нет запрещённого произведения сила * размах")

	if _failures.is_empty():
		print("grass_wind_style_probe: ALL CHECKS PASSED")
		quit(0)
	else:
		for f: String in _failures:
			print("grass_wind_style_probe: FAILED %s" % f)
		quit(1)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("grass_wind_style_probe: PASS %s" % description)
	else:
		_failures.append(description)
		print("grass_wind_style_probe: FAIL %s" % description)
