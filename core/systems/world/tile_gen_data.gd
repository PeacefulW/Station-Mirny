class_name TileGenData
extends RefCounted

## Данные генерации для одного тайла.

## Типы поверхности (упрощено: только земля + горы).
enum TerrainType {
	GROUND = 0,
	ROCK = 1,
	# TODO: вернуть когда добавим воду/ресурсы
	# WATER = 2,
	# SAND = 3,
	# GRASS = 4,
	MINED_FLOOR = 5,
	MOUNTAIN_ENTRANCE = 6,
}

var terrain: TerrainType = TerrainType.GROUND
var height: float = 0.5
var distance_from_spawn: float = 0.0
