class_name NoiseComponent
extends Node

## Компонент шума. Прикрепляется к шумным постройкам.
## Очистители реагируют на шум через группу "noise_sources".
## Чем выше noise_level и radius — тем больше внимания.

# --- Экспортируемые ---
## Радиус слышимости (пиксели).
@export var noise_radius: float = 200.0
## Уровень шума (0.0–1.0). Влияет на агрессивность реакции.
@export var noise_level: float = 0.5
## Активен ли шум сейчас.
@export var is_active: bool = false

func _ready() -> void:
	add_to_group("noise_sources")

## Включить/выключить шум.
func set_active(active: bool) -> void:
	is_active = active

## Получить мировую позицию источника шума.
func get_noise_position() -> Vector2:
	var parent: Node = get_parent()
	if parent is Node2D:
		return (parent as Node2D).global_position
	return Vector2.ZERO

## Проверить, слышит ли точка этот шум.
func is_audible_at(world_pos: Vector2) -> bool:
	if not is_active:
		return false
	return get_noise_position().distance_to(world_pos) <= noise_radius
