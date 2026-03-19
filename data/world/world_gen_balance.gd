class_name WorldGenBalance
extends Resource

## Параметры баланса генерации мира.
## Все настройки генератора здесь — не в коде.
## Мод может заменить этот .tres файл и получить другую генерацию.
## Игрок может настроить часть параметров на экране создания мира.

@export_group("Чанки")
## Размер чанка в тайлах (одна сторона квадрата).
@export var chunk_size_tiles: int = 64
## Размер одного тайла в пикселях.
@export var tile_size: int = 32
## Радиус загрузки чанков вокруг игрока.
@export var load_radius: int = 3
## Радиус выгрузки чанков (должен быть > load_radius).
@export var unload_radius: int = 5

@export_group("Рельеф — основной шум")
## Частота шума (меньше = крупнее формы рельефа).
@export var height_frequency: float = 0.01
## Количество октав (больше = детальнее).
@export var height_octaves: int = 4
## Порог воды (ниже = вода). Настраивается игроком.
@export_range(0.0, 1.0) var water_threshold: float = 0.30
## Порог камня (выше = горы). Настраивается игроком.
@export_range(0.0, 1.0) var rock_threshold: float = 0.73

@export_group("Рельеф — Domain Warping")
## Сила искривления (0 = выключено). Настраивается игроком.
## Делает береговые линии и формы рельефа органичными.
@export_range(0.0, 60.0) var warp_strength: float = 25.0
## Частота шума warping.
@export var warp_frequency: float = 0.008

@export_group("Рельеф — горные хребты (Ridged Noise)")
## Вклад хребтового шума (0.0 = нет хребтов). Настраивается игроком.
@export_range(0.0, 0.5) var ridge_weight: float = 0.30
## Частота хребтового шума.
@export var ridge_frequency: float = 0.012

@export_group("Рельеф — континентальный масштаб")
## Вклад крупномасштабного шума (суша vs океан).
@export_range(0.0, 0.4) var continental_weight: float = 0.20
## Частота (очень низкая = огромные континенты).
@export var continental_frequency: float = 0.003

@export_group("Реки")
## Количество истоков рек.
@export var river_count: int = 8
## Минимальная высота истока (доля от rock_threshold).
@export_range(0.3, 0.9) var river_min_start_height: float = 0.5
## Ширина реки в тайлах (у истока).
@export var river_width_start: float = 1.5
## Ширина реки в тайлах (у устья, после 200+ шагов).
@export var river_width_end: float = 3.5

@export_group("Влажность и растительность")
## Частота шума влажности.
@export var moisture_frequency: float = 0.015
## Порог: выше — трава.
@export_range(0.0, 1.0) var grass_threshold: float = 0.35
## Порог: выше — деревья (только где трава).
@export_range(0.0, 1.0) var tree_threshold: float = 0.72

@export_group("Споры")
## Частота шума спор.
@export var spore_frequency: float = 0.007
## Количество октав.
@export var spore_octaves: int = 3
## Минимальная плотность спор (есть везде).
@export_range(0.0, 1.0) var spore_min_density: float = 0.15

@export_group("Ресурсы")
## Частота шума для размещения ресурсов.
@export var resource_frequency: float = 0.02
## Порог: выше = залежь ресурса.
@export_range(0.0, 1.0) var resource_deposit_threshold: float = 0.62

@export_group("Стартовая зона")
## Радиус безопасной зоны (тайлы): мало спор, гарантированная суша.
@export var safe_zone_radius: int = 12
## Радиус гарантированной суши (тайлы).
@export var land_guarantee_radius: int = 24

## Вычислить размер чанка в пикселях.
func get_chunk_size_pixels() -> int:
	return chunk_size_tiles * tile_size
