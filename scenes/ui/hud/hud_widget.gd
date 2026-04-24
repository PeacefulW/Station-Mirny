class_name HudWidget
extends Control

## Базовый класс для всех виджетов HUD.
## Наследники переопределяют _setup() и подписываются на EventBus.

## Показать виджет.
func show_widget() -> void:
	visible = true

## Скрыть виджет.
func hide_widget() -> void:
	visible = false

## Переопределить в наследнике: построить UI.
func _setup() -> void:
	pass

func _get_minimum_size() -> Vector2:
	var minimum: Vector2 = Vector2.ZERO
	for child: Node in get_children():
		var control: Control = child as Control
		if control == null:
			continue
		var child_minimum: Vector2 = control.get_combined_minimum_size()
		minimum.x = maxf(minimum.x, child_minimum.x)
		minimum.y = maxf(minimum.y, child_minimum.y)
	return minimum

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_setup()
	update_minimum_size()
