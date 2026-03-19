class_name ItemData
extends Resource

## Базовый класс для всех предметов в игре.
## Следует Data-Driven подходу: каждый предмет это отдельный .tres файл.

@export var id: String = "base:unknown"
@export var display_name: String = "Неизвестный предмет"
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var max_stack: int = 99
@export var weight: float = 1.0