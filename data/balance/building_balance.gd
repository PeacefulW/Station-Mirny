class_name BuildingBalance
extends Resource

## Параметры баланса строительной системы.

@export_group("Сетка")
## Размер ячейки сетки в пикселях.
@export var grid_size: int = 32

@export_group("Стены")
@export var wall_health: float = 50.0
## Стоимость постройки стены в скрапе.
@export var wall_scrap_cost: int = 2
