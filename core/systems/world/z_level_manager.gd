class_name ZLevelManager
extends Node

## Управляет переключением между z-уровнями (этажами).
## Хранит текущий уровень, оповещает через сигнал и EventBus.
## Дочерний узел GameWorld, не Autoload.

signal z_level_changed(new_z: int, old_z: int)

const Z_MIN: int = -1
const Z_MAX: int = 1

var _current_z: int = 0

func _ready() -> void:
	add_to_group("z_level_manager")

## Переключиться на указанный z-уровень.
func change_level(new_z: int) -> void:
	if new_z < Z_MIN or new_z > Z_MAX:
		return
	if new_z == _current_z:
		return
	var old_z: int = _current_z
	_current_z = new_z
	z_level_changed.emit(new_z, old_z)
	EventBus.z_level_changed.emit(new_z, old_z)

## Получить текущий z-уровень.
func get_current_z() -> int:
	return _current_z
