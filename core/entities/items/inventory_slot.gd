class_name InventorySlot
extends Resource

## Представляет одну ячейку инвентаря.
## Содержит ссылку на ресурс предмета и количество.

@export var item: ItemData = null
@export var amount: int = 0

## Проверяет, пуста ли ячейка.
func is_empty() -> bool:
	return item == null or amount <= 0

## Очищает ячейку.
func clear() -> void:
	item = null
	amount = 0