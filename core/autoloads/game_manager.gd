class_name GameManagerSingleton
extends Node

## Глобальный менеджер игры. Настраивает управление,
## отслеживает базовое состояние игры.

const INPUT_ACTIONS: Dictionary = {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"toggle_build_mode": KEY_B,
	"toggle_inventory": KEY_TAB,
	"toggle_power_ui": KEY_P,
	"attack": KEY_SPACE,
	"interact": KEY_E,
}

const MOUSE_ACTIONS: Dictionary = {
	"primary_action": MOUSE_BUTTON_LEFT,
	"secondary_action": MOUSE_BUTTON_RIGHT,
}

var is_game_over: bool = false

func _ready() -> void:
	_setup_input_actions()

func _setup_input_actions() -> void:
	for action_name: String in INPUT_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var event := InputEventKey.new()
			event.physical_keycode = INPUT_ACTIONS[action_name]
			InputMap.action_add_event(action_name, event)
	for action_name: String in MOUSE_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_ACTIONS[action_name]
			InputMap.action_add_event(action_name, event)
