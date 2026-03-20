class_name PlayerBalance
extends Resource

## Параметры баланса игрока: движение, атака, добыча, камера, взаимодействие.

@export_group("Движение")
@export var move_speed: float = 150.0

@export_group("Атака")
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 0.4
@export var attack_range: float = 48.0
@export var attack_flash_duration: float = 0.1

@export_group("Добыча")
@export var harvest_cooldown: float = 0.5
@export var harvest_range: float = 48.0
@export var harvest_flash_duration: float = 0.15
@export var harvest_popup_rise_distance: float = 40.0
@export var harvest_popup_duration: float = 0.8
@export var harvest_popup_fade_delay: float = 0.3

@export_group("Камера")
## Минимальный зум (отдаление).
@export var zoom_min: float = 1.0
## Максимальный зум (приближение).
@export var zoom_max: float = 4.0
## Шаг зума при скролле.
@export var zoom_step: float = 0.25
## Скорость интерполяции зума.
@export var zoom_speed: float = 8.0
## Зум по умолчанию при старте.
@export var zoom_default: float = 2.5

@export_group("Взаимодействие")
## Дистанция дозаправки термосжигателя (пиксели).
@export var burner_refuel_range: float = 21.0
## Топлива за единицу биомассы.
@export var burner_fuel_per_wood: float = 20.0
