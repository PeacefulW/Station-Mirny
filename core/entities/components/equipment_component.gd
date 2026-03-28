class_name EquipmentComponent
extends Node

## Хранит экипированные предметы. Один компонент на игрока.
## Слоты определяются через EquipmentSlotType.Slot enum.

signal equipment_changed(slot: int, item: ItemData)

## Экипированные предметы: slot_id → ItemData (null = пусто).
var _equipped: Dictionary = {}

func _ready() -> void:
	_reset_slots()

## Экипировать предмет. Возвращает ранее экипированный (или null).
func equip(slot: int, item: ItemData) -> ItemData:
	_ensure_initialized()
	var previous: ItemData = _equipped.get(slot)
	_equipped[slot] = item
	equipment_changed.emit(slot, item)
	return previous

## Снять предмет из слота. Возвращает снятый предмет (или null).
func unequip(slot: int) -> ItemData:
	_ensure_initialized()
	var item: ItemData = _equipped.get(slot)
	_equipped[slot] = null
	equipment_changed.emit(slot, null)
	return item

## Получить предмет в слоте (или null).
func get_equipped(slot: int) -> ItemData:
	_ensure_initialized()
	return _equipped.get(slot)

## Проверить подходит ли предмет в слот.
func can_equip(slot: int, item: ItemData) -> bool:
	if not item:
		return false
	return item.equipment_slot == slot

## Получить все экипированные предметы.
func get_all_equipped() -> Dictionary:
	_ensure_initialized()
	return _equipped.duplicate()

func equip_from_inventory_slot(inventory: InventoryComponent, slot_index: int) -> bool:
	if not inventory:
		return false
	_ensure_initialized()
	if slot_index < 0 or slot_index >= inventory.slots.size():
		return false
	var slot: InventorySlot = inventory.slots[slot_index]
	if slot.is_empty() or slot.item.equipment_slot < 0:
		return false
	var equip_slot: int = slot.item.equipment_slot
	if not can_equip(equip_slot, slot.item):
		return false
	var removed: Dictionary = inventory.remove_amount_from_slot(slot_index, 1)
	if removed.is_empty():
		return false
	var equipped_item: ItemData = removed.get("item") as ItemData
	var previous: ItemData = equip(equip_slot, equipped_item)
	if previous:
		var leftover: int = inventory.add_item(previous, 1)
		if leftover > 0:
			push_error("EquipmentComponent.equip_from_inventory_slot() could not return previous item to inventory")
	return true

func unequip_to_inventory(slot: int, inventory: InventoryComponent) -> bool:
	if not inventory:
		return false
	_ensure_initialized()
	var item: ItemData = _equipped.get(slot)
	if not item:
		return false
	var leftover: int = inventory.add_item(item, 1)
	if leftover > 0:
		return false
	unequip(slot)
	return true

## Сохранить состояние экипировки.
func save_state() -> Dictionary:
	_ensure_initialized()
	var data: Dictionary = {}
	for slot: int in _equipped:
		var item: ItemData = _equipped[slot]
		if item:
			data[slot] = item.id
	return data

## Восстановить состояние экипировки.
func load_state(data: Dictionary) -> void:
	_reset_slots(true)
	for slot_key: Variant in data:
		var slot: int = int(slot_key)
		var item_id: String = str(data[slot_key])
		var item: ItemData = ItemRegistry.get_item(item_id)
		if item:
			_equipped[slot] = item
			equipment_changed.emit(slot, item)

func _ensure_initialized() -> void:
	if _equipped.is_empty():
		_reset_slots()

func _reset_slots(emit_clear_signals: bool = false) -> void:
	for slot_value: int in EquipmentSlotType.Slot.values():
		var had_item: bool = _equipped.has(slot_value) and _equipped[slot_value] != null
		_equipped[slot_value] = null
		if emit_clear_signals and had_item:
			equipment_changed.emit(slot_value, null)
