class_name TileGenData
extends RefCounted

## Данные генерации для одного тайла.

## Типы поверхности.
enum TerrainType {
	GROUND = 0,
	ROCK = 1,
}

var terrain: TerrainType = TerrainType.GROUND
var height: float = 0.5
var distance_from_spawn: float = 0.0
