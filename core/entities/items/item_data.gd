class_name ItemData
extends Resource

## Базовый класс для всех предметов в игре.
## Следует Data-Driven подходу: каждый предмет это отдельный .tres файл.

@export var id: String = "base:unknown"
@export var display_name_key: String = ""
@export var display_name: String = ""
@export var description_key: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var max_stack: int = 99
@export var weight: float = 1.0
## -1 = не экипируется. 0+ = EquipmentSlotType.Slot.
@export var equipment_slot: int = -1

func get_display_name() -> String:
	return Localization.td(display_name_key, display_name)

func get_description() -> String:
	return Localization.td(description_key, description)