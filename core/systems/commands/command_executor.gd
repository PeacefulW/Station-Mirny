class_name CommandExecutor
extends Node

## Выполняет команды игрового действия и нормализует ответ.

func _ready() -> void:
	add_to_group("command_executor")

func execute(command: GameCommand) -> Dictionary:
	if not command:
		return {
			"success": false,
			"message": "Команда не передана",
		}
	var result: Dictionary = command.execute()
	if not result.has("success"):
		result["success"] = false
	if not result.has("message"):
		result["message"] = ""
	return result
