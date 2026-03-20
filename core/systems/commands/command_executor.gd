class_name CommandExecutor
extends Node

## Выполняет команды игрового действия и нормализует ответ.

func _ready() -> void:
	add_to_group("command_executor")

func execute(command: GameCommand) -> Dictionary:
	if not command:
		return {
			"success": false,
			"message_key": "SYSTEM_COMMAND_MISSING",
		}
	var result: Dictionary = command.execute()
	if not result.has("success"):
		result["success"] = false
	if not result.has("message_key"):
		result["message_key"] = ""
	if not result.has("message_args"):
		result["message_args"] = {}
	return result