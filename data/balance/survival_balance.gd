class_name SurvivalBalance
extends Resource

## Параметры баланса системы выживания.
## Все числа здесь, не в коде.

@export_group("Кислород")
@export var max_oxygen: float = 100.0
## Скорость расхода O₂ в секунду на улице.
@export var oxygen_drain_rate: float = 6.0
## Скорость восполнения O₂ в секунду внутри базы.
@export var oxygen_refill_rate: float = 20.0
## Если база герметична, но питание не подано, O₂ всё равно медленно падает.
@export var oxygen_unpowered_indoor_drain_rate: float = 1.5
## Порог предупреждения (0.0 — 1.0).
@export var low_oxygen_threshold: float = 0.3
## Множитель скорости при низком O₂.
@export var speed_penalty_at_low_oxygen: float = 0.4

@export_group("Гипоксия")
## Порог потери сознания (0.0 — 1.0).
@export var blackout_threshold: float = 0.05
## Урон в секунду при нулевом O₂.
@export var suffocation_damage: float = 10.0
