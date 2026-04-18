class_name WorldRuntimeConstants
extends RefCounted

const TILE_SIZE_PX: int = 32
const CHUNK_SIZE: int = 32
const CHUNK_CELL_COUNT: int = CHUNK_SIZE * CHUNK_SIZE
const STREAM_RADIUS_CHUNKS: int = 1
const PUBLISH_BATCH_SIZE: int = 128

const DEFAULT_WORLD_SEED: int = 131071
const WORLD_VERSION: int = 1

const TERRAIN_PLAINS_GROUND: int = 0
const TERRAIN_PLAINS_ROCK: int = 1
const TERRAIN_PLAINS_DUG: int = 2

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
