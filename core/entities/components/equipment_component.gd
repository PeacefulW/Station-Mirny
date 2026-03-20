class_name EquipmentComponent
extends Node

## Хранит экипированные предметы. Один компонент на игрока.
## Слоты определяются через EquipmentSlotType.Slot enum.

signal equipment_changed(slot: int, item: ItemData)

## Экипированные предметы: slot_id → ItemData (null = пусто).
var _equipped: Dictionary = {}

func _ready() -> void:
	for slot_value: int in EquipmentSlotType.Slot.values():
		_equipped[slot_value] = null

## Экипировать предмет. Возвращает ранее экипированный (или null).
func equip(slot: int, item: ItemData) -> ItemData:
	var previous: ItemData = _equipped.get(slot)
	_equipped[slot] = item
	equipment_changed.emit(slot, item)
	return previous

## Снять предмет из слота. Возвращает снятый предмет (или null).
func unequip(slot: int) -> ItemData:
	var item: ItemData = _equipped.get(slot)
	_equipped[slot] = null
	equipment_changed.emit(slot, null)
	return item

## Получить предмет в слоте (или null).
func get_equipped(slot: int) -> ItemData:
	return _equipped.get(slot)

## Проверить подходит ли предмет в слот.
func can_equip(slot: int, item: ItemData) -> bool:
	if not item:
		return false
	return item.equipment_slot == slot

## Получить все экипированные предметы.
func get_all_equipped() -> Dictionary:
	return _equipped.duplicate()

## Сохранить состояние экипировки.
func save_state() -> Dictionary:
	var data: Dictionary = {}
	for slot: int in _equipped:
		var item: ItemData = _equipped[slot]
		if item:
			data[slot] = item.id
	return data

## Восстановить состояние экипировки.
func load_state(data: Dictionary) -> void:
	for slot_key: Variant in data:
		var slot: int = int(slot_key)
		var item_id: String = str(data[slot_key])
		var item: ItemData = ItemRegistry.get_item(item_id)
		if item:
			_equipped[slot] = item
			equipment_changed.emit(slot, item)
