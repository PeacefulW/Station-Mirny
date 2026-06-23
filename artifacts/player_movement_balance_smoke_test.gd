extends SceneTree


const PLAYER_BALANCE_PATH: String = "res://data/balance/player_balance.tres"
const PLAYER_SCRIPT_PATH: String = "res://core/entities/player/player.gd"


func _init() -> void:
	var balance: Resource = ResourceLoader.load(PLAYER_BALANCE_PATH)
	if balance == null:
		_fail("player balance should load")
		return
	var move_speed: float = float(balance.get("move_speed"))
	if not is_equal_approx(move_speed, 320.0):
		_fail("move_speed should be 320.0, got %.2f" % move_speed)
		return
	var backward_multiplier: float = float(balance.get("backward_move_speed_multiplier"))
	if not is_equal_approx(backward_multiplier, 0.72):
		_fail("backward_move_speed_multiplier should be 0.72, got %.2f" % backward_multiplier)
		return
	var script_text: String = FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH)
	if not script_text.contains("_movement_speed_multiplier_for_direction"):
		_fail("player script should define directional movement multiplier")
		return
	if not script_text.contains("balance.backward_move_speed_multiplier"):
		_fail("player script should read backward_move_speed_multiplier")
		return
	print("PLAYER_MOVEMENT_BALANCE_SMOKE_OK speed=%.1f backward=%.2f" % [move_speed, backward_multiplier])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
