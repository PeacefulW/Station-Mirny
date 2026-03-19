class_name PowerBalance
extends Resource

## Параметры баланса системы электричества.

@export_group("Обновление")
## Как часто пересчитывать энергобаланс (секунды).
@export var update_interval: float = 1.0

@export_group("Аварийные батареи Ковчега")
## Мощность одной батареи (Вт).
@export var ark_battery_output: float = 80.0
## Начальный заряд одной батареи (Вт⋅ч — ватт-часы).
@export var ark_battery_capacity: float = 2000.0
## Стоимость размещения (скрап). 0 = найдена в обломках.
@export var ark_battery_cost: int = 0

@export_group("Термосжигатель")
## Мощность (Вт).
@export var burner_output: float = 120.0
## Расход биомассы в секунду.
@export var burner_fuel_rate: float = 0.5
## Максимум топлива в загрузке.
@export var burner_fuel_capacity: float = 100.0
## Радиус шума (привлекает Очистителей).
@export var burner_noise_radius: float = 250.0
## Уровень шума (0.0–1.0).
@export var burner_noise_level: float = 0.7
## Стоимость размещения (скрап).
@export var burner_cost: int = 8

@export_group("Визуал (заглушки)")
## Цвет батареи.
@export var ark_battery_color: Color = Color(0.3, 0.5, 0.8)
## Цвет термосжигателя.
@export var burner_color: Color = Color(0.8, 0.4, 0.15)
## Размер постройки (тайлов).
@export var building_tile_size: int = 1
