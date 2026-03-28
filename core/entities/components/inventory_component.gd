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

func move_slot_contents(from_index: int, to_index: int) -> bool:
	if from_index == to_index:
		return false
	if not _is_valid_slot_index(from_index) or not _is_valid_slot_index(to_index):
		return false
	var slot_a: InventorySlot = slots[from_index]
	var slot_b: InventorySlot = slots[to_index]
	if slot_a.is_empty() and slot_b.is_empty():
		return false
	if not slot_a.is_empty() and not slot_b.is_empty() and slot_a.item.id == slot_b.item.id:
		var space: int = slot_b.item.max_stack - slot_b.amount
		if space <= 0:
			return false
		var transfer: int = mini(space, slot_a.amount)
		slot_b.amount += transfer
		slot_a.amount -= transfer
		if slot_a.amount <= 0:
			slot_a.clear()
	else:
		var tmp_item: ItemData = slot_a.item
		var tmp_amount: int = slot_a.amount
		slot_a.item = slot_b.item
		slot_a.amount = slot_b.amount
		slot_b.item = tmp_item
		slot_b.amount = tmp_amount
	_emit_inventory_updated()
	return true

func split_stack(slot_index: int) -> bool:
	if not _is_valid_slot_index(slot_index):
		return false
	var slot: InventorySlot = slots[slot_index]
	if slot.is_empty() or slot.amount <= 1:
		return false
	var empty_index: int = _find_empty_slot_index()
	if empty_index < 0:
		return false
	var split_amount: int = slot.amount / 2
	slot.amount -= split_amount
	var target_slot: InventorySlot = slots[empty_index]
	target_slot.item = slot.item
	target_slot.amount = split_amount
	_emit_inventory_updated()
	return true

func sort_slots_by_name() -> bool:
	if slots.is_empty():
		return false
	var items: Array[Dictionary] = []
	for slot: InventorySlot in slots:
		if not slot.is_empty():
			items.append({"item": slot.item, "amount": slot.amount})
		slot.clear()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["item"] as ItemData).get_display_name() < (b["item"] as ItemData).get_display_name()
	)
	var idx: int = 0
	for entry: Dictionary in items:
		if idx >= slots.size():
			break
		slots[idx].item = entry["item"]
		slots[idx].amount = entry["amount"]
		idx += 1
	_emit_inventory_updated()
	return true

func remove_amount_from_slot(slot_index: int, amount: int) -> Dictionary:
	var removed: Dictionary = _remove_amount_from_slot_internal(slot_index, amount)
	if removed.is_empty():
		return {}
	_emit_inventory_updated()
	return removed

func remove_slot_contents(slot_index: int) -> Dictionary:
	if not _is_valid_slot_index(slot_index):
		return {}
	var slot: InventorySlot = slots[slot_index]
	if slot.is_empty():
		return {}
	return remove_amount_from_slot(slot_index, slot.amount)

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

func _is_valid_slot_index(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < slots.size()

func _find_empty_slot_index() -> int:
	for i: int in range(slots.size()):
		if slots[i].is_empty():
			return i
	return -1

func _remove_amount_from_slot_internal(slot_index: int, amount: int) -> Dictionary:
	if not _is_valid_slot_index(slot_index) or amount <= 0:
		return {}
	var slot: InventorySlot = slots[slot_index]
	if slot.is_empty():
		return {}
	var removed_amount: int = mini(amount, slot.amount)
	var item_data: ItemData = slot.item
	slot.amount -= removed_amount
	if slot.amount <= 0:
		slot.clear()
	return {
		"item": item_data,
		"item_id": item_data.id,
		"amount": removed_amount,
	}

func _emit_inventory_updated() -> void:
	EventBus.inventory_updated.emit(self)
