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

@export_group("Помещения")
## Базовый local proof-padding для room patch в клетках.
@export var room_patch_padding: int = 6
## Верхний предел proof-padding для staged room patch в клетках.
@export var room_patch_max_padding: int = 32
## Gap для слияния соседних dirty region в клетках.
@export var room_patch_merge_gap: int = 2
## Сколько flood-step узлов допускается в одном staged full rebuild tick.
@export var room_full_rebuild_flood_budget: int = 192
## Сколько scan-step клеток допускается в одном staged full rebuild tick.
@export var room_full_rebuild_scan_budget: int = 256
