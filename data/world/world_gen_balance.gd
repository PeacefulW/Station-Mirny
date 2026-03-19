class_name WorldGenBalance
extends Resource

## Параметры баланса генерации мира.
## Все настройки генератора здесь — не в коде.
## Мод может заменить этот .tres файл и получить другую генерацию.

@export_group("Чанки")
## Размер чанка в тайлах (одна сторона квадрата).
@export var chunk_size_tiles: int = 64
## Размер одного тайла в пикселях.
@export var tile_size: int = 32
## Радиус загрузки чанков вокруг игрока.
@export var load_radius: int = 3
## Радиус выгрузки чанков (должен быть > load_radius).
@export var unload_radius: int = 5

@export_group("Шум высот")
## Частота шума (меньше = крупнее формы рельефа).
@export var height_frequency: float = 0.008
## Количество октав (больше = детальнее).
@export var height_octaves: int = 4
## Порог воды (ниже этого значения — вода).
@export_range(0.0, 1.0) var water_threshold: float = 0.28
## Порог камня (выше этого значения — каменистая зона).
@export_range(0.0, 1.0) var rock_threshold: float = 0.72

@export_group("Шум спор")
## Частота шума спор.
@export var spore_frequency: float = 0.005
## Количество октав.
@export var spore_octaves: int = 3
## Минимальная плотность спор (есть везде).
@export_range(0.0, 1.0) var spore_min_density: float = 0.15

@export_group("Шум ресурсов")
## Частота шума для размещения ресурсов.
@export var resource_frequency: float = 0.015
## Количество октав.
@export var resource_octaves: int = 2
## Порог: выше этого значения — залежь ресурса.
@export_range(0.0, 1.0) var resource_deposit_threshold: float = 0.65

@export_group("Шум растительности")
## Частота шума для трав и деревьев.
@export var vegetation_frequency: float = 0.02
## Порог: выше — трава/деревья.
@export_range(0.0, 1.0) var grass_threshold: float = 0.35
## Порог: выше — деревья (только в зоне травы).
@export_range(0.0, 1.0) var tree_threshold: float = 0.75

@export_group("Стартовая зона")
## Радиус безопасной зоны вокруг точки старта (в тайлах).
## Внутри этой зоны: нет воды, нет камня, щадящие споры.
@export var safe_zone_radius: int = 12
## Радиус обязательной суши вокруг старта (в тайлах).
@export var land_guarantee_radius: int = 20

## Вычислить размер чанка в пикселях.
func get_chunk_size_pixels() -> int:
	return chunk_size_tiles * tile_size
