class_name GameCommand
extends RefCounted

## Базовая команда игрового действия.
## Возвращает словарь формата:
## { "success": bool, "message_key": String, ... }

func execute() -> Dictionary:
	return {
		"success": false,
		"message_key": "SYSTEM_COMMAND_NOT_IMPLEMENTED",
	}