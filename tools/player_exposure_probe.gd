extends SceneTree

# Deterministic headless probe for warning-only player wetness/cold exposure.
# Run:
#   godot --headless --path . -s tools/player_exposure_probe.gd

const BalanceScript = preload("res://data/balance/player_exposure_balance.gd")

const EPSILON: float = 0.0001
const PRECIPITATION_NONE: int = 0
const PRECIPITATION_RAIN: int = 1

var _failures: Array[String] = []
var _exposure_script: GDScript = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# A -s script is parsed before project autoload globals exist. Loading the
	# component after the deferred boot phase lets its EventBus references resolve
	# exactly as they do in a regular scene run.
	_exposure_script = load(
		"res://core/entities/components/player_exposure_component.gd",
	) as GDScript
	if _exposure_script == null:
		_check(false, "player exposure script loads after autoload boot")
		_finish()
		return
	var tuning: PlayerExposureBalance = BalanceScript.new()
	_check(tuning.is_valid_balance(), "default exposure balance is valid")
	var invalid_multiplier: PlayerExposureBalance = BalanceScript.new()
	invalid_multiplier.covered_wet_chill_multiplier = NAN
	_check(
		not invalid_multiplier.is_valid_balance(),
		"non-finite covered wet-chill multiplier fails boot validation",
	)
	_check_rain_authority(tuning)
	_check_drying_order(tuning)
	_check_cold_monotonicity(tuning)
	_check_powered_comfort(tuning)
	_check_save_contract()
	_check_warning_only_source()

	_finish()


func _check_rain_authority(tuning: PlayerExposureBalance) -> void:
	var initial: Vector2 = Vector2(0.40, 0.0)
	var rain_open: Vector2 = _step(
		tuning,
		initial,
		10.0,
		PRECIPITATION_RAIN,
		0.75,
		true,
		false,
		false,
		20.0,
		0.0,
	)
	var expected_wetness: float = (
		initial.x + tuning.rain_wetness_rate_per_second * 0.75 * 10.0
	)
	_check_close(
		rain_open.x,
		expected_wetness,
		"RAIN under open sky increases wetness by authored intensity/rate",
	)

	var none_open: Vector2 = _step(
		tuning,
		initial,
		10.0,
		PRECIPITATION_NONE,
		1.0,
		true,
		false,
		false,
		20.0,
		0.0,
	)
	var other_open: Vector2 = _step(
		tuning,
		initial,
		10.0,
		99,
		1.0,
		true,
		false,
		false,
		20.0,
		0.0,
	)
	var rain_covered: Vector2 = _step(
		tuning,
		initial,
		10.0,
		PRECIPITATION_RAIN,
		1.0,
		false,
		false,
		false,
		20.0,
		0.0,
	)
	_check(
		none_open.x < initial.x and other_open.x < initial.x,
		"NONE and unknown precipitation kinds never increase wetness",
	)
	_check(
		rain_covered.x < initial.x,
		"cover blocks wetness gain even during full-intensity RAIN",
	)


func _check_drying_order(tuning: PlayerExposureBalance) -> void:
	var initial: Vector2 = Vector2(0.80, 0.0)
	var dry_open: Vector2 = _step(
		tuning,
		initial,
		10.0,
		PRECIPITATION_NONE,
		0.0,
		true,
		false,
		false,
		20.0,
		0.0,
	)
	var dry_covered: Vector2 = _step(
		tuning,
		initial,
		10.0,
		PRECIPITATION_NONE,
		0.0,
		false,
		false,
		false,
		20.0,
		0.0,
	)
	var dry_powered: Vector2 = _step(
		tuning,
		initial,
		10.0,
		PRECIPITATION_NONE,
		0.0,
		false,
		true,
		true,
		20.0,
		0.0,
	)
	_check(
		dry_powered.x < dry_covered.x and dry_covered.x < dry_open.x,
		"drying is fastest powered indoor, then cover, then open air",
	)
	_check_close(
		dry_open.x,
		initial.x - tuning.dry_open_rate_per_second * 10.0,
		"open-air drying uses its authored rate",
	)
	_check_close(
		dry_covered.x,
		initial.x - tuning.dry_covered_rate_per_second * 10.0,
		"covered drying uses its authored rate",
	)
	_check_close(
		dry_powered.x,
		initial.x - tuning.dry_powered_indoor_rate_per_second * 10.0,
		"powered-indoor drying uses its authored rate",
	)


func _check_cold_monotonicity(tuning: PlayerExposureBalance) -> void:
	var wind_results: Array[float] = []
	for wind_strength: float in [0.0, 0.5, 1.0]:
		wind_results.append(
			_step(
				tuning,
				Vector2(0.0, 0.30),
				1.0,
				PRECIPITATION_NONE,
				0.0,
				true,
				false,
				false,
				6.0,
				wind_strength,
			).y,
		)
	_check(
		_is_non_decreasing(wind_results),
		"at fixed air temperature, stronger wind never lowers cold load %s"
		% str(wind_results),
	)

	var wetness_results: Array[float] = []
	for wetness: float in [0.0, 0.5, 1.0]:
		wetness_results.append(
			_step(
				tuning,
				Vector2(wetness, 0.30),
				1.0,
				PRECIPITATION_NONE,
				0.0,
				true,
				false,
				false,
				6.0,
				0.0,
			).y,
		)
	_check(
		_is_non_decreasing(wetness_results),
		"at fixed air temperature, greater wetness never lowers cold load %s"
		% str(wetness_results),
	)


func _check_powered_comfort(tuning: PlayerExposureBalance) -> void:
	var state: Vector2 = Vector2(0.80, 0.80)
	var unpowered: Vector2 = _step(
		tuning,
		state,
		1.0,
		PRECIPITATION_NONE,
		0.0,
		false,
		true,
		false,
		-30.0,
		1.0,
	)
	var powered: Vector2 = _step(
		tuning,
		state,
		1.0,
		PRECIPITATION_NONE,
		0.0,
		false,
		true,
		true,
		-30.0,
		1.0,
	)
	_check(
		powered.y < state.y and powered.y < unpowered.y,
		"powered indoor control recovers cold load despite hostile outdoor air",
	)
	_check(
		powered.x < unpowered.x,
		"powered indoor shelter also uses the fastest drying path",
	)


func _check_save_contract() -> void:
	var component: Node = _exposure_script.new()
	component.load_state({ "wetness": 0.37, "cold_load": 0.62 })
	var saved: Dictionary = component.save_state()
	var restored: Node = _exposure_script.new()
	restored.load_state(saved)
	_check_close(restored.get_wetness(), 0.37, "wetness save/load round-trips")
	_check_close(restored.get_cold_load(), 0.62, "cold load save/load round-trips")
	_check(
		saved.size() == 2 and saved.has("wetness") and saved.has("cold_load"),
		"component save payload owns only the two exposure scalars",
	)

	restored.load_state({ })
	_check(
		is_zero_approx(restored.get_wetness()) and is_zero_approx(restored.get_cold_load()),
		"old save without exposure fields defaults to dry and warm",
	)
	restored.load_state({ "wetness": "soaked", "cold_load": [0.75] })
	_check(
		is_zero_approx(restored.get_wetness()) and is_zero_approx(restored.get_cold_load()),
		"malformed exposure values default to zero",
	)
	restored.load_state({ "wetness": 7.0, "cold_load": -3.0 })
	_check_close(restored.get_wetness(), 1.0, "oversized wetness is clamped")
	_check_close(restored.get_cold_load(), 0.0, "negative cold load is clamped")
	restored.load_state({ "wetness": INF, "cold_load": NAN })
	_check(
		is_zero_approx(restored.get_wetness()) and is_zero_approx(restored.get_cold_load()),
		"non-finite save values fail closed to zero",
	)
	component.free()
	restored.free()


func _check_warning_only_source() -> void:
	var path: String = "res://core/entities/components/player_exposure_component.gd"
	_check(FileAccess.file_exists(path), "player exposure source is available for static audit")
	var executable_source: String = _without_comments(FileAccess.get_file_as_string(path))
	var forbidden_tokens: Array[String] = [
		"HealthComponent",
		"health_component",
		"OxygenSystem",
		"oxygen_system",
		"apply_damage(",
		"take_damage(",
		"change_health(",
		"queue_free(",
		"velocity =",
		"stamina",
		"fatigue",
		"EventBus.health",
		"EventBus.player_died",
	]
	var found: Array[String] = []
	for token: String in forbidden_tokens:
		if executable_source.contains(token):
			found.append(token)
	_check(
		found.is_empty(),
		"warning-only component has no health/death/movement/oxygen side effects %s"
		% str(found),
	)


func _step(
		tuning: PlayerExposureBalance,
		state: Vector2,
		delta: float,
		precipitation_kind: int,
		precipitation_intensity: float,
		open_sky: bool,
		building_indoor: bool,
		life_support_powered: bool,
		air_temperature_c: float,
		wind_strength: float,
) -> Vector2:
	return _exposure_script.calculate_next_state(
		tuning,
		state,
		delta,
		precipitation_kind,
		precipitation_intensity,
		open_sky,
		building_indoor,
		life_support_powered,
		air_temperature_c,
		wind_strength,
	)


func _is_non_decreasing(values: Array[float]) -> bool:
	for index: int in range(1, values.size()):
		if values[index] + EPSILON < values[index - 1]:
			return false
	return true


func _without_comments(source: String) -> String:
	var executable_source: String = ""
	for source_line: String in source.split("\n"):
		var comment_index: int = source_line.find("#")
		var code_line: String = (
			source_line.left(comment_index) if comment_index >= 0 else source_line
		)
		executable_source += code_line + "\n"
	return executable_source


func _check_close(actual: float, expected: float, description: String) -> void:
	_check(
		absf(actual - expected) <= EPSILON,
		"%s (actual=%.6f expected=%.6f)" % [description, actual, expected],
	)


func _finish() -> void:
	if _failures.is_empty():
		print("player_exposure_probe: ALL CHECKS PASSED")
		quit(0)
		return
	for failure: String in _failures:
		print("player_exposure_probe: FAILED %s" % failure)
	quit(1)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("player_exposure_probe: PASS %s" % description)
		return
	_failures.append(description)
	print("player_exposure_probe: FAIL %s" % description)
