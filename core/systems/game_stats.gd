class_name GameStats
extends Node

## Статистика текущей игровой сессии.
## Подписывается на EventBus, считает события.

var days_survived: int = 0
var enemies_killed: int = 0
var buildings_placed: int = 0
var items_crafted: int = 0
var resources_gathered: int = 0

func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.item_crafted.connect(_on_item_crafted)
	EventBus.item_collected.connect(_on_item_collected)
	if TimeManager:
		days_survived = TimeManager.current_day

## Получить сводку для UI.
func get_summary() -> Dictionary:
	return {
		"days_survived": days_survived,
		"enemies_killed": enemies_killed,
		"buildings_placed": buildings_placed,
		"items_crafted": items_crafted,
		"resources_gathered": resources_gathered,
	}

func _on_day_changed(day_number: int) -> void:
	days_survived = day_number

func _on_enemy_killed(_position: Vector2) -> void:
	enemies_killed += 1

func _on_building_placed(_position: Vector2i) -> void:
	buildings_placed += 1

func _on_item_crafted(_item_id: String, amount: int) -> void:
	items_crafted += amount

func _on_item_collected(_item_id: String, amount: int) -> void:
	resources_gathered += amount
