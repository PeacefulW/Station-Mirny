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

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_setup()
