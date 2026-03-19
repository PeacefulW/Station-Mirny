class_name PlayerBalance
extends Resource

## Параметры баланса игрока: движение, атака и добыча.

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
