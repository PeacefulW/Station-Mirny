class_name ZLevelBalance
extends Resource

## Параметры баланса z-уровней: переходы, лестницы, визуал.

@export_group("Переход")
## Длительность затемнения (сек).
@export var fade_in_duration: float = 0.15
## Пауза на чёрном экране (сек).
@export var fade_hold_duration: float = 0.05
## Длительность осветления (сек).
@export var fade_out_duration: float = 0.15

@export_group("Лестница")
## Кулдаун перехода после наступания (сек).
@export var stairs_cooldown: float = 1.0
## Кулдаун после переключения уровня (сек).
@export var stairs_post_transition_cooldown: float = 0.5
## Цвет люка вниз (заглушка).
@export var stairs_down_color: Color = Color(0.6, 0.5, 0.2)
## Цвет лестницы вверх (заглушка).
@export var stairs_up_color: Color = Color(0.3, 0.5, 0.8)
