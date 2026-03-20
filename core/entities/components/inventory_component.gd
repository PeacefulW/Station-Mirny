class_name InventoryComponent
extends Node

## Универсальный компонент инвентаря.
## Управляет массивом ячеек, логикой добавления/удаления стаков.
## Общается с UI и другими системами через EventBus.

# --- Экспортируемые ---
@export var capacity: int = 20

# --- Публичные переменные ---
var slots: Array[InventorySlot] = []

func _ready() -> void:
	_initialize_slots()

# --- Публичные методы ---

## Пытается добавить предмет в инвентарь.
## Возвращает количество предмета, которое НЕ поместилось (0, если влезло всё).
func add_item(item_data: ItemData, amount: int) -> int:
	if amount <= 0 or not item_data:
		return 0
		
	var remaining: int = amount
	
	# Шаг 1: Пытаемся заполнить неполные стаки такого же предмета
	for slot: InventorySlot in slots:
		if not slot.is_empty() and slot.item.id == item_data.id:
			var space: int = slot.item.max_stack - slot.amount
			if space > 0:
				var to_add: int = mini(space, remaining)
				slot.amount += to_add
				remaining -= to_add
				if remaining <= 0:
					EventBus.inventory_updated.emit(self)
					return 0
					
	# Шаг 2: Ищем пустые слоты для остатка
	for slot: InventorySlot in slots:
		if slot.is_empty():
			slot.item = item_data
			var to_add: int = mini(item_data.max_stack, remaining)
			slot.amount = to_add
			remaining -= to_add
			if remaining <= 0:
				EventBus.inventory_updated.emit(self)
				return 0
				
	# Если дошли сюда — инвентарь заполнился, а остаток не влез
	if remaining != amount:
		EventBus.inventory_updated.emit(self)
		
	return remaining

## Удаляет предмет из инвентаря.
## Возвращает true, если было удалено нужное количество, иначе false.
func remove_item(item_data: ItemData, amount: int) -> bool:
	if not has_item(item_data, amount):
		return false
		
	var remaining_to_remove: int = amount
	
	for slot: InventorySlot in slots:
		if not slot.is_empty() and slot.item.id == item_data.id:
			var to_remove: int = mini(slot.amount, remaining_to_remove)
			slot.amount -= to_remove
			remaining_to_remove -= to_remove
			
			if slot.amount <= 0:
				slot.clear()
				
			if remaining_to_remove <= 0:
				EventBus.inventory_updated.emit(self)
				return true
				
	return false

## Подсчитать общее количество предмета по ID.
func get_item_count(item_id: String) -> int:
	var total: int = 0
	for slot: InventorySlot in slots:
		if not slot.is_empty() and slot.item and slot.item.id == item_id:
			total += slot.amount
	return total

## Проверяет, есть ли в инвентаре нужное количество предмета.
func has_item(item_data: ItemData, amount: int) -> bool:
	var total: int = 0
	for slot: InventorySlot in slots:
		if not slot.is_empty() and slot.item.id == item_data.id:
			total += slot.amount
			if total >= amount:
				return true
	return false

## Сохранить состояние инвентаря.
func save_state() -> Dictionary:
	var serialized_slots: Array[Dictionary] = []
	for slot: InventorySlot in slots:
		if slot.is_empty() or not slot.item:
			serialized_slots.append({})
			continue
		serialized_slots.append({
			"item_id": slot.item.id,
			"amount": slot.amount,
		})
	return {
		"capacity": capacity,
		"slots": serialized_slots,
	}

## Восстановить состояние инвентаря.
func load_state(data: Dictionary) -> void:
	capacity = int(data.get("capacity", capacity))
	_initialize_slots()

	var serialized_slots: Array = data.get("slots", [])
	var limit: int = mini(serialized_slots.size(), slots.size())
	for i: int in range(limit):
		var slot_data: Dictionary = serialized_slots[i]
		if slot_data.is_empty():
			continue
		var item_id: String = str(slot_data.get("item_id", ""))
		var amount: int = int(slot_data.get("amount", 0))
		var item_data: ItemData = ItemRegistry.get_item(item_id)
		if not item_data or amount <= 0:
			continue
		slots[i].item = item_data
		slots[i].amount = mini(amount, item_data.max_stack)

	EventBus.inventory_updated.emit(self)

# --- Приватные методы ---

func _initialize_slots() -> void:
	slots.clear()
	for i: int in range(capacity):
		slots.append(InventorySlot.new())
