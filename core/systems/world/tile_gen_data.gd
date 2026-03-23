class_name TileGenData
extends RefCounted

## Данные генерации для одного тайла.

## Типы поверхности.
enum TerrainType {
	GROUND = 0,
	ROCK = 1,
	WATER = 2,
	SAND = 3,
	GRASS = 4,
	MINED_FLOOR = 5,
	MOUNTAIN_ENTRANCE = 6,
}

var terrain: TerrainType = TerrainType.GROUND
var height: float = 0.5
var distance_from_spawn: float = 0.0
