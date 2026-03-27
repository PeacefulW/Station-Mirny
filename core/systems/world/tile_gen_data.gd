class_name TileGenData
extends RefCounted

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
var world_height: float = 0.5
var canonical_world_pos: Vector2i = Vector2i.ZERO
var temperature: float = 0.5
var moisture: float = 0.5
var ruggedness: float = 0.5
var flora_density: float = 0.5
var latitude: float = 0.0
var ridge_strength: float = 0.0
var mountain_mass: float = 0.0
var river_strength: float = 0.0
var floodplain_strength: float = 0.0
var biome_id: StringName = &""
var biome_score: float = -1.0
var local_variation_id: int = 0
var local_variation_kind: StringName = &"none"
var local_variation_score: float = 0.0
var flora_modulation: float = 0.0
var wetness_modulation: float = 0.0
var rockiness_modulation: float = 0.0
var openness_modulation: float = 0.0
var distance_from_spawn: float = 0.0
