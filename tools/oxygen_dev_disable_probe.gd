extends SceneTree

# Headless regression probe for the temporary exterior-O2 development override.
# Run:
#   godot --headless --path . -s tools/oxygen_dev_disable_probe.gd

const OXYGEN_SCRIPT_PATH: String = "res://core/systems/survival/oxygen_system.gd"
const BALANCE_PATH: String = "res://data/balance/survival_balance.tres"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var oxygen_script: Script = load(OXYGEN_SCRIPT_PATH) as Script
	var balance: Resource = load(BALANCE_PATH) as Resource
	_check(oxygen_script != null and oxygen_script.can_instantiate(), "OxygenSystem loads")
	_check(balance != null, "SurvivalBalance loads")
	if oxygen_script == null or not oxygen_script.can_instantiate() or balance == null:
		_finish()
		return

	var oxygen: Node = oxygen_script.new() as Node
	oxygen.set("balance", balance)
	oxygen.set("_current_oxygen", 50.0)
	oxygen.set("_is_indoor", false)
	oxygen.set("_is_base_powered", false)
	oxygen.call("_update_oxygen", 10.0)
	_check_close(
		float(oxygen.get("_current_oxygen")),
		50.0,
		"exterior oxygen stays unchanged while the dev override is active",
	)

	oxygen.set("_is_indoor", true)
	oxygen.set("_is_base_powered", true)
	oxygen.call("_update_oxygen", 1.0)
	_check_close(
		float(oxygen.get("_current_oxygen")),
		70.0,
		"powered indoor oxygen still refills",
	)

	oxygen.set("_current_oxygen", 50.0)
	oxygen.set("_is_base_powered", false)
	oxygen.call("_update_oxygen", 2.0)
	_check_close(
		float(oxygen.get("_current_oxygen")),
		47.0,
		"unpowered indoor oxygen still depletes",
	)

	var saved_state: Dictionary = oxygen.call("save_state") as Dictionary
	var restored: Node = oxygen_script.new() as Node
	restored.set("balance", balance)
	restored.call("load_state", saved_state)
	_check_close(
		float(restored.get("_current_oxygen")),
		47.0,
		"oxygen save/load remains unchanged",
	)

	var source: String = FileAccess.get_file_as_string(OXYGEN_SCRIPT_PATH)
	_check(
		source.contains("ВРЕМЕННО ДЛЯ РАЗРАБОТКИ ИГРЫ")
		and source.contains("# \t_current_oxygen - balance.oxygen_drain_rate * delta"),
		"disabled exterior branch carries an explicit reversible development comment",
	)

	oxygen.free()
	restored.free()
	_finish()


func _check_close(actual: float, expected: float, description: String) -> void:
	_check(
		is_equal_approx(actual, expected),
		"%s (actual=%.3f expected=%.3f)" % [description, actual, expected],
	)


func _check(passed: bool, description: String) -> void:
	if passed:
		print("oxygen_dev_disable_probe: PASS %s" % description)
		return
	_failures.append(description)
	print("oxygen_dev_disable_probe: FAIL %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("oxygen_dev_disable_probe: ALL CHECKS PASSED")
		quit(0)
		return
	for failure: String in _failures:
		print("oxygen_dev_disable_probe: FAILED %s" % failure)
	quit(1)
