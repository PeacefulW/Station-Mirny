class_name RuntimeDirtyQueue
extends RefCounted

## Очередь dirty work с de-dupe по ключу.

var _items: Array = []
var _queued: Dictionary = {}

func enqueue(item: Variant) -> bool:
	if _queued.has(item):
		return false
	_queued[item] = true
	_items.append(item)
	return true

func enqueue_many(items: Array) -> int:
	var added: int = 0
	for item: Variant in items:
		if enqueue(item):
			added += 1
	return added

func pop_next() -> Variant:
	if _items.is_empty():
		return null
	var item: Variant = _items.pop_front()
	_queued.erase(item)
	return item

func clear() -> void:
	_items.clear()
	_queued.clear()

func is_empty() -> bool:
	return _items.is_empty()

func has_work() -> bool:
	return not _items.is_empty()

func size() -> int:
	return _items.size()

func snapshot() -> Array:
	return _items.duplicate()
