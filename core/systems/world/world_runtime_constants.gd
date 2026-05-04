class_name WorldRuntimeConstants
extends RefCounted

const TILE_SIZE_PX: int = 32
const CHUNK_SIZE: int = 32
const CHUNK_CELL_COUNT: int = CHUNK_SIZE * CHUNK_SIZE
const STREAM_RADIUS_CHUNKS: int = 1
const PUBLISH_BATCH_SIZE: int = 128

const DEFAULT_WORLD_SEED: int = 131071
const WORLD_VERSION: int = 42
const WORLD_FOUNDATION_VERSION: int = 9
const FOUNDATION_COARSE_CELL_SIZE_TILES: int = 64
const LEGACY_WORLD_WRAP_WIDTH_TILES: int = 65536
const SPAWN_SAFE_PATCH_MIN_TILE: int = 12
const SPAWN_SAFE_PATCH_MAX_TILE: int = 20

const TERRAIN_PLAINS_GROUND: int = 0
const TERRAIN_LEGACY_BLOCKED: int = 1
const TERRAIN_PLAINS_DUG: int = 2
const TERRAIN_MOUNTAIN_WALL: int = 3
const TERRAIN_MOUNTAIN_FOOT: int = 4
const TERRAIN_LAKE_BED_SHALLOW: int = 5
const TERRAIN_LAKE_BED_DEEP: int = 6

const MOUNTAIN_FLAG_INTERIOR: int = 1
const MOUNTAIN_FLAG_WALL: int = 2
const MOUNTAIN_FLAG_FOOT: int = 4
const MOUNTAIN_FLAG_ANCHOR: int = 8
const LAKE_FLAG_WATER_PRESENT: int = 1

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
const SETTINGS_PACKED_LAYOUT_LAKE_DENSITY: int = 15
const SETTINGS_PACKED_LAYOUT_LAKE_SCALE: int = 16
const SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_AMPLITUDE: int = 17
const SETTINGS_PACKED_LAYOUT_LAKE_SHORE_WARP_SCALE: int = 18
const SETTINGS_PACKED_LAYOUT_LAKE_DEEP_THRESHOLD: int = 19
const SETTINGS_PACKED_LAYOUT_LAKE_MOUNTAIN_CLEARANCE: int = 20
const SETTINGS_PACKED_LAYOUT_LAKE_CONNECTIVITY: int = 21
const SETTINGS_PACKED_LAYOUT_FIELD_COUNT: int = 22

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

static func is_current_world_version(version: int) -> bool:
	return version == WORLD_VERSION
