class_name WorldRuntimeConstants
extends RefCounted

const TILE_SIZE_PX: int = 32
const CHUNK_SIZE: int = 32
const CHUNK_CELL_COUNT: int = CHUNK_SIZE * CHUNK_SIZE
const STREAM_RADIUS_CHUNKS: int = 1
const PUBLISH_BATCH_SIZE: int = 128
const WATER_OVERLAY_DIRTY_BLOCK_SIZE: int = 16

const DEFAULT_WORLD_SEED: int = 131071
const WORLD_VERSION: int = 36
const WORLD_FOUNDATION_VERSION: int = 9
const WORLD_RIVER_VERSION: int = 17
const WORLD_LAKE_VERSION: int = 18
const WORLD_DELTA_VERSION: int = 19
const WORLD_ORGANIC_WATER_VERSION: int = 20
const WORLD_OCEAN_SHORE_VERSION: int = 21
const WORLD_REFINED_RIVER_VERSION: int = 22
const WORLD_CURVATURE_RIVER_VERSION: int = 23
const WORLD_Y_CONFLUENCE_RIVER_VERSION: int = 24
const WORLD_BRAID_LOOP_RIVER_VERSION: int = 25
const WORLD_BASIN_CONTOUR_LAKE_VERSION: int = 26
const WORLD_ORGANIC_COASTLINE_VERSION: int = 27
const WORLD_HYDROLOGY_SHAPE_FIX_VERSION: int = 28
const WORLD_HEADLAND_COAST_VERSION: int = 29
const WORLD_HYDROLOGY_VISUAL_V3_VERSION: int = 30
const WORLD_HYDROLOGY_CLEARANCE_V4_VERSION: int = 31
const WORLD_RIVER_DISCHARGE_WIDTH_V4_VERSION: int = 32
const WORLD_ESTUARY_DELTA_V4_VERSION: int = 33
const WORLD_LAKE_BASIN_CONTINUITY_V4_VERSION: int = 34
const WORLD_LAKES_ONLY_PRESET_V4_VERSION: int = 35
const WORLD_HYDROLOGY_V4_CLOSURE_VERSION: int = 36
const FOUNDATION_COARSE_CELL_SIZE_TILES: int = 64
const LEGACY_WORLD_WRAP_WIDTH_TILES: int = 65536
const SPAWN_SAFE_PATCH_MIN_TILE: int = 12
const SPAWN_SAFE_PATCH_MAX_TILE: int = 20

const TERRAIN_PLAINS_GROUND: int = 0
const TERRAIN_LEGACY_BLOCKED: int = 1
const TERRAIN_PLAINS_DUG: int = 2
const TERRAIN_MOUNTAIN_WALL: int = 3
const TERRAIN_MOUNTAIN_FOOT: int = 4
const TERRAIN_RIVERBED_SHALLOW: int = 5
const TERRAIN_RIVERBED_DEEP: int = 6
const TERRAIN_LAKEBED: int = 7
const TERRAIN_OCEAN_FLOOR: int = 8
const TERRAIN_SHORE: int = 9
const TERRAIN_FLOODPLAIN: int = 10

const WATER_CLASS_NONE: int = 0
const WATER_CLASS_SHALLOW: int = 1
const WATER_CLASS_DEEP: int = 2
const WATER_CLASS_OCEAN: int = 3

const HYDROLOGY_FLAG_RIVERBED: int = 1
const HYDROLOGY_FLAG_LAKEBED: int = 2
const HYDROLOGY_FLAG_SHORE: int = 4
const HYDROLOGY_FLAG_BANK: int = 8
const HYDROLOGY_FLAG_FLOODPLAIN: int = 16
const HYDROLOGY_FLAG_DELTA: int = 32
const HYDROLOGY_FLAG_BRAID_SPLIT: int = 64
const HYDROLOGY_FLAG_CONFLUENCE: int = 128
const HYDROLOGY_FLAG_SOURCE: int = 256
const HYDROLOGY_FLAG_FLOODPLAIN_NEAR: int = 512
const HYDROLOGY_FLAG_FLOODPLAIN_FAR: int = 1024

const MOUNTAIN_FLAG_INTERIOR: int = 1
const MOUNTAIN_FLAG_WALL: int = 2
const MOUNTAIN_FLAG_FOOT: int = 4
const MOUNTAIN_FLAG_ANCHOR: int = 8

const SETTINGS_PACKED_LAYOUT_DENSITY: int = 0
const SETTINGS_PACKED_LAYOUT_SCALE: int = 1
const SETTINGS_PACKED_LAYOUT_CONTINUITY: int = 2
const SETTINGS_PACKED_LAYOUT_RUGGEDNESS: int = 3
const SETTINGS_PACKED_LAYOUT_ANCHOR_CELL_SIZE: int = 4
const SETTINGS_PACKED_LAYOUT_GRAVITY_RADIUS: int = 5
const SETTINGS_PACKED_LAYOUT_FOOT_BAND: int = 6
const SETTINGS_PACKED_LAYOUT_INTERIOR_MARGIN: int = 7
const SETTINGS_PACKED_LAYOUT_LATITUDE_INFLUENCE: int = 8
const SETTINGS_PACKED_LAYOUT_MOUNTAIN_FIELD_COUNT: int = 9
const SETTINGS_PACKED_LAYOUT_WORLD_WIDTH_TILES: int = 9
const SETTINGS_PACKED_LAYOUT_WORLD_HEIGHT_TILES: int = 10
const SETTINGS_PACKED_LAYOUT_OCEAN_BAND_TILES: int = 11
const SETTINGS_PACKED_LAYOUT_BURNING_BAND_TILES: int = 12
const SETTINGS_PACKED_LAYOUT_POLE_ORIENTATION: int = 13
const SETTINGS_PACKED_LAYOUT_FOUNDATION_SLOPE_BIAS: int = 14
const SETTINGS_PACKED_LAYOUT_FIELD_COUNT: int = 15
const SETTINGS_PACKED_LAYOUT_RIVER_ENABLED: int = 15
const SETTINGS_PACKED_LAYOUT_RIVER_TARGET_TRUNK_COUNT: int = 16
const SETTINGS_PACKED_LAYOUT_RIVER_DENSITY: int = 17
const SETTINGS_PACKED_LAYOUT_RIVER_WIDTH_SCALE: int = 18
const SETTINGS_PACKED_LAYOUT_RIVER_LAKE_CHANCE: int = 19
const SETTINGS_PACKED_LAYOUT_RIVER_MEANDER_STRENGTH: int = 20
const SETTINGS_PACKED_LAYOUT_RIVER_BRAID_CHANCE: int = 21
const SETTINGS_PACKED_LAYOUT_RIVER_SHALLOW_CROSSING_FREQUENCY: int = 22
const SETTINGS_PACKED_LAYOUT_RIVER_MOUNTAIN_CLEARANCE_TILES: int = 23
const SETTINGS_PACKED_LAYOUT_RIVER_DELTA_SCALE: int = 24
const SETTINGS_PACKED_LAYOUT_RIVER_NORTH_DRAINAGE_BIAS: int = 25
const SETTINGS_PACKED_LAYOUT_RIVER_HYDROLOGY_CELL_SIZE_TILES: int = 26
const SETTINGS_PACKED_LAYOUT_FIELD_COUNT_WITH_RIVERS: int = 27

const DEFAULT_SAVE_SLOT: String = "save_001"

static func chunk_origin_px(chunk_coord: Vector2i) -> Vector2:
	return Vector2(
		chunk_coord.x * CHUNK_SIZE * TILE_SIZE_PX,
		chunk_coord.y * CHUNK_SIZE * TILE_SIZE_PX
	)

static func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / float(TILE_SIZE_PX)),
		floori(world_pos.y / float(TILE_SIZE_PX))
	)

static func tile_to_world_center(tile_coord: Vector2i) -> Vector2:
	return Vector2(
		(float(tile_coord.x) + 0.5) * float(TILE_SIZE_PX),
		(float(tile_coord.y) + 0.5) * float(TILE_SIZE_PX)
	)

static func tile_to_chunk(tile_coord: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(tile_coord.x) / float(CHUNK_SIZE))),
		int(floor(float(tile_coord.y) / float(CHUNK_SIZE)))
	)

static func tile_to_local(tile_coord: Vector2i) -> Vector2i:
	var chunk_coord: Vector2i = tile_to_chunk(tile_coord)
	return Vector2i(
		tile_coord.x - chunk_coord.x * CHUNK_SIZE,
		tile_coord.y - chunk_coord.y * CHUNK_SIZE
	)

static func chunk_file_name(chunk_coord: Vector2i) -> String:
	return "%d_%d.json" % [chunk_coord.x, chunk_coord.y]

static func index_to_local(index: int) -> Vector2i:
	return Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE)

static func local_to_index(local_coord: Vector2i) -> int:
	return local_coord.y * CHUNK_SIZE + local_coord.x

static func is_local_coord_valid(local_coord: Vector2i) -> bool:
	return local_coord.x >= 0 \
		and local_coord.x < CHUNK_SIZE \
		and local_coord.y >= 0 \
		and local_coord.y < CHUNK_SIZE

static func uses_world_foundation(version: int) -> bool:
	return version >= WORLD_FOUNDATION_VERSION

static func uses_river_generation(version: int) -> bool:
	return version >= WORLD_RIVER_VERSION
