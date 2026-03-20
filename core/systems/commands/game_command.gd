class_name GameCommand
extends RefCounted

## Базовая команда игрового действия.
## Возвращает словарь формата:
## { "success": bool, "message": String, ... }

func execute() -> Dictionary:
	return {
		"success": false,
		"message": "Команда не реализована",
	}
