class_name EnemyBalance
extends Resource

## Параметры баланса врагов (Очистителей).

@export_group("Характеристики")
@export var max_health: float = 30.0
@export var move_speed: float = 60.0
@export var damage_to_player: float = 15.0
@export var damage_to_wall: float = 8.0
@export var attack_cooldown: float = 1.5

@export_group("Спавн")
## Интервал появления в секундах.
@export var spawn_interval: float = 15.0
## Минимальная дистанция от игрока при появлении.
@export var spawn_distance_min: float = 400.0
@export var spawn_distance_max: float = 700.0
## Максимум врагов одновременно.
@export var max_enemies: int = 8

@export_group("Дроп")
## Количество скрапа при убийстве.
@export var scrap_drop_min: int = 1
@export var scrap_drop_max: int = 3
