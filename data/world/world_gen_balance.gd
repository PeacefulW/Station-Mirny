class_name WorldGenBalance
extends Resource

## Упрощённые параметры генерации мира.
## Только земля + горы. Остальное будет добавлено позже.

@export_group("Чанки")
@export var chunk_size_tiles: int = 64
@export var tile_size: int = 64
@export var load_radius: int = 2
@export var unload_radius: int = 4

@export_group("Рельеф — основной шум")
@export var height_frequency: float = 0.01
@export var height_octaves: int = 4
@export_range(0.55, 0.90) var rock_threshold: float = 0.73

@export_group("Рельеф — Domain Warping")
@export_range(0.0, 60.0) var warp_strength: float = 25.0
@export var warp_frequency: float = 0.008

@export_group("Рельеф — горные хребты")
@export_range(0.0, 0.5) var ridge_weight: float = 0.30
@export var ridge_frequency: float = 0.012

@export_group("Рельеф — континентальный масштаб")
@export_range(0.0, 0.4) var continental_weight: float = 0.20
@export var continental_frequency: float = 0.003

@export_group("Горные формации")
@export_range(1, 3) var mountain_size: int = 2

@export_group("Стартовая зона")
@export var safe_zone_radius: int = 12
@export var land_guarantee_radius: int = 24

func get_chunk_size_pixels() -> int:
	return chunk_size_tiles * tile_size
