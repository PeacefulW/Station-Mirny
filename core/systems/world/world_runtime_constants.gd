class_name WorldRuntimeConstants
extends RefCounted

const TILE_SIZE_PX: int = 64
const CHUNK_SIZE: int = 16
const CHUNK_CELL_COUNT: int = CHUNK_SIZE * CHUNK_SIZE
const STREAM_RADIUS_CHUNKS: int = 1
# Tiles applied to the active publish chunk per streaming tick. 64 set_cell
# applies cost well under a millisecond, so a chunk becomes visible in ~4 ticks
# the old value of 4 stretched one chunk over 64 ticks (~1 s) and let a running
# player outrace the streamer.
const PUBLISH_BATCH_SIZE: int = 64

const DEFAULT_WORLD_SEED: int = 131071
const WORLD_VERSION: int = 61
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
const SETTINGS_PACKED_LAYOUT_TREE_DENSITY: int = 22
const SETTINGS_PACKED_LAYOUT_TREE_SCATTER_GRID_SIDE: int = 23
const SETTINGS_PACKED_LAYOUT_TREE_EDGE_PADDING_PX: int = 24
const SETTINGS_PACKED_LAYOUT_TREE_MIN_DISTANCE_PX: int = 25
const SETTINGS_PACKED_LAYOUT_TREE_MAX_PER_CHUNK: int = 26
const SETTINGS_PACKED_LAYOUT_TREE_MIN_SIZE_PX: int = 27
const SETTINGS_PACKED_LAYOUT_TREE_MAX_SIZE_PX: int = 28
const SETTINGS_PACKED_LAYOUT_TREE_SMALL_CHANCE: int = 29
const SETTINGS_PACKED_LAYOUT_TREE_SMALL_SIZE_PX: int = 30
const SETTINGS_PACKED_LAYOUT_TREE_HERO_CHANCE: int = 31
const SETTINGS_PACKED_LAYOUT_TREE_HERO_SIZE_PX: int = 32
const SETTINGS_PACKED_LAYOUT_TREE_GRASS_DENSITY_MIN: int = 33
const SETTINGS_PACKED_LAYOUT_TREE_GRASS_FIELD_SCALE_PX: int = 34
const SETTINGS_PACKED_LAYOUT_TREE_GRASS_COVERAGE: int = 35
const SETTINGS_PACKED_LAYOUT_TREE_ROCK_FIELD_SCALE_PX: int = 36
const SETTINGS_PACKED_LAYOUT_TREE_ROCK_COVERAGE: int = 37
const SETTINGS_PACKED_LAYOUT_TREE_MACRO_MASS_SCALE_PX: int = 38
const SETTINGS_PACKED_LAYOUT_TREE_MACRO_MASS_STRENGTH: int = 39
const SETTINGS_PACKED_LAYOUT_TREE_PATH_SCALE_PX: int = 40
const SETTINGS_PACKED_LAYOUT_TREE_PATH_WIDTH: int = 41
const SETTINGS_PACKED_LAYOUT_TREE_PATH_WARP_PX: int = 42
const SETTINGS_PACKED_LAYOUT_TREE_PATH_STRENGTH: int = 43
const SETTINGS_PACKED_LAYOUT_TREE_FIELD_COUNT: int = 44

const DEFAULT_SAVE_SLOT: String = "save_001"

## Depth-лесенка mid-слоя (трава, объектный декор, игрок): мир режется
## горизонтальными полосами по DEPTH_STRIPE_PX (абсолютными, без периода —
## периодические классы оборачивались на границе периода и ломали порядок
## где угодно на экране). z полосы считается ОТНОСИТЕЛЬНО якорной полосы
## игрока с клампом ±DEPTH_LADDER_HALF_RANGE_STRIPES: внутри точной зоны
## (±768 px — больше экрана на игровых зумах) южное перекрывает северное с
## точностью 16 px; за её пределами полосы прижаты к краям лесенки, где
## взаимные ошибки уже не различимы. Якорь обновляет WorldStreamer при
## смене полосы ног игрока. Трава полосы — z = base + (rel+K)*2, объекты и
## игрок — +1. Зеркало native: grass_scatter::DEPTH_STRIPE_PX /
## DEPTH_STRIPES_PER_CHUNK (полосы в чанке — chunk-local, 0..63).
const DEPTH_STRIPE_PX: int = 16
const DEPTH_STRIPES_PER_CHUNK: int = 64
const DEPTH_LADDER_HALF_RANGE_STRIPES: int = 48
## Контактные тени травы — на земле, под всей лесенкой травы/декора.
const Z_GRASS_SHADOW: int = 18
const Z_MID_LADDER_BASE: int = 20
## Отбрасываемые тени объектов (силуэт дерева) — ПОВЕРХ всей травяной/объектной
## лесенки (макс. z = Z_MID_LADDER_BASE + (48+48)*2 + 1 = 213) и поверх игрока
## (фиксированный z = 117): тень ложится на траву/камни/игрока, а не под них.
## Ниже спор. Гора теперь тоже ниже лесенки (см. Z_MOUNTAIN_TOP) — тень дерева
## может лечь на скалу рядом, что физически корректно.
const Z_CAST_SHADOW: int = 214
## Споры биополя — в воздухе над травой.
const Z_GRASS_SPORE: int = 290
## Гора — НИЖЕ всей объектной лесенки: деревья/камни/игрок рисуются ПОВЕРХ горы.
## Это геометрически корректно: объекты не размещаются на горных тайлах, а их
## спрайты тянутся вверх от якоря, поэтому перекрытие пикселей горы объектом
## всегда означает «объект спереди» (mountain_object_occlusion.md, 2026-07-04
## заменило отвергнутый пользователем canopy-carve). Выше подошвы (4) и
## контактных теней травы (18), ниже лесенки (20+). Крыша интерьера
## (RoofLayer, Z_DEBUG_OVERLAY) остаётся высоко и по-прежнему прячет полости.
const Z_MOUNTAIN_TOP: int = 19
const Z_MOUNTAIN_PAGE: int = 19
const Z_MINING_FEEDBACK: int = 320
const Z_DEBUG_OVERLAY: int = 350


static func depth_stripe_for_world_y(world_y: float) -> int:
	return floori(world_y / float(DEPTH_STRIPE_PX))


static func z_for_stripe_vs_anchor(world_stripe: int, anchor_stripe: int, is_object_layer: bool) -> int:
	var relative: int = clampi(
		world_stripe - anchor_stripe,
		-DEPTH_LADDER_HALF_RANGE_STRIPES,
		DEPTH_LADDER_HALF_RANGE_STRIPES,
	)
	var z: int = Z_MID_LADDER_BASE + (relative + DEPTH_LADDER_HALF_RANGE_STRIPES) * 2
	return z + 1 if is_object_layer else z


static func chunk_origin_px(chunk_coord: Vector2i) -> Vector2:
	return Vector2(
		chunk_coord.x * CHUNK_SIZE * TILE_SIZE_PX,
		chunk_coord.y * CHUNK_SIZE * TILE_SIZE_PX,
	)


static func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / float(TILE_SIZE_PX)),
		floori(world_pos.y / float(TILE_SIZE_PX)),
	)


static func tile_to_world_center(tile_coord: Vector2i) -> Vector2:
	return Vector2(
		(float(tile_coord.x) + 0.5) * float(TILE_SIZE_PX),
		(float(tile_coord.y) + 0.5) * float(TILE_SIZE_PX),
	)


static func tile_to_chunk(tile_coord: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(tile_coord.x) / float(CHUNK_SIZE))),
		int(floor(float(tile_coord.y) / float(CHUNK_SIZE))),
	)


static func tile_to_local(tile_coord: Vector2i) -> Vector2i:
	var chunk_coord: Vector2i = tile_to_chunk(tile_coord)
	return Vector2i(
		tile_coord.x - chunk_coord.x * CHUNK_SIZE,
		tile_coord.y - chunk_coord.y * CHUNK_SIZE,
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
