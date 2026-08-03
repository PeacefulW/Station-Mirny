class_name TimeBalance
extends Resource

const SeasonProfile = preload("res://core/systems/world/season_profile.gd")

## Параметры баланса системы времени.
## Все числа здесь, не в коде.

@export_group("Цикл дня")
## Длительность одного игрового дня в реальных минутах.
@export var day_duration_minutes: float = 2.0
## Количество часов в игровом дне.
@export var hours_per_day: int = 24

@export_group("Фазы дня (часы)")
## Час начала рассвета.
@export var dawn_hour: int = 5
## Час начала дня.
@export var day_hour: int = 7
## Час начала заката.
@export var dusk_hour: int = 18
## Час начала ночи.
@export var night_hour: int = 21

@export_group("Сезоны")
## Длительность одного сезона в игровых днях.
@export var season_length_days: int = 15
## Фиксированные V0-профили WARM/SPORE/COLD/STORM. TimeManager валидирует
## полный набор и уникальные stable ids при boot.
@export var season_profiles: Array[SeasonProfile] = []
