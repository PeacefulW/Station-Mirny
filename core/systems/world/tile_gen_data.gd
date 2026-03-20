class_name TileGenData
extends RefCounted

## Данные генерации для одного тайла.
## WorldGenerator возвращает это при запросе "что здесь?".
## Легковесный объект — создаётся сотнями при генерации чанка.

## Типы поверхности.
enum TerrainType { GROUND, ROCK, WATER, SAND, GRASS, MINED_FLOOR, MOUNTAIN_ENTRANCE }

## Типы ресурсных залежей (NONE = нет ресурса).
enum DepositType { NONE, IRON_ORE, COPPER_ORE, STONE, WATER_SOURCE }

## Тип поверхности в этом тайле.
var terrain: TerrainType = TerrainType.GROUND

## Нормализованная высота (0.0 — 1.0).
var height: float = 0.5

## Плотность спор в этой точке (0.0 — 1.0).
var spore_density: float = 0.0

## Ресурсная залежь (если есть).
var deposit: DepositType = DepositType.NONE

## Есть ли дерево в этом тайле.
var has_tree: bool = false

## Есть ли декоративная трава.
var has_grass: bool = false

## Расстояние от точки старта (в тайлах). Нужно для safe zone.
var distance_from_spawn: float = 0.0
