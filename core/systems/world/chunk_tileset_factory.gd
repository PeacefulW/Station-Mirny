class_name ChunkTilesetFactory
extends RefCounted

## Создаёт процедурные тайлсеты для мира.
## Это позволяет быстро менять визуал гор через balance-ресурс.

const TERRAIN_SOURCE_ID: int = 0
const OVERLAY_SOURCE_ID: int = 1

const ROCK_FACES_PATH: String = "res://assets/sprites/terrain/rock_faces_atlas.png"
const ROCK_FACES_DUNGEON_PATH: String = "res://assets/sprites/terrain/rock_faces_atlas_dungeon.png"
## Количество базовых тайлов стен (без вариантов). Обновляется при сборке tileset.
static var wall_base_count: int = 0
## Количество вариантов (1 = без вариативности, 3 = три варианта).
static var wall_variant_count: int = 1

const TILE_GROUND_DARK: Vector2i = Vector2i(0, 0)
const TILE_GROUND: Vector2i = Vector2i(1, 0)
const TILE_GROUND_LIGHT: Vector2i = Vector2i(2, 0)
const TILE_ROCK: Vector2i = Vector2i(3, 0)
const TILE_ROCK_INTERIOR: Vector2i = Vector2i(4, 0)
const TILE_MINED_FLOOR: Vector2i = Vector2i(5, 0)
const TILE_MOUNTAIN_ENTRANCE: Vector2i = Vector2i(6, 0)
static var tile_water: Vector2i = Vector2i(7, 0)
static var tile_sand: Vector2i = Vector2i(8, 0)
static var tile_grass: Vector2i = Vector2i(9, 0)
static var tile_sparse_flora: Vector2i = Vector2i(10, 0)
static var tile_dense_flora: Vector2i = Vector2i(11, 0)
static var tile_clearing: Vector2i = Vector2i(12, 0)
static var tile_rocky_patch: Vector2i = Vector2i(13, 0)
static var tile_wet_patch: Vector2i = Vector2i(14, 0)

const SURFACE_VARIATION_NONE: int = 0
const SURFACE_VARIATION_SPARSE_FLORA: int = 1
const SURFACE_VARIATION_DENSE_FLORA: int = 2
const SURFACE_VARIATION_CLEARING: int = 3
const SURFACE_VARIATION_ROCKY_PATCH: int = 4
const SURFACE_VARIATION_WET_PATCH: int = 5

## Rock visual-class tiles (from atlas, positions 7+)
const WALL_INTERIOR: Vector2i = Vector2i(7, 0)
const WALL_NOTCH_NE: Vector2i = Vector2i(8, 0)
const WALL_NOTCH_NW: Vector2i = Vector2i(9, 0)
const WALL_NOTCH_SE: Vector2i = Vector2i(10, 0)
const WALL_NOTCH_SW: Vector2i = Vector2i(11, 0)
const WALL_SOUTH: Vector2i = Vector2i(12, 0)
const WALL_NORTH: Vector2i = Vector2i(13, 0)
const WALL_WEST: Vector2i = Vector2i(14, 0)
const WALL_EAST: Vector2i = Vector2i(15, 0)
const WALL_CORNER_SW: Vector2i = Vector2i(16, 0)
const WALL_CORNER_SE: Vector2i = Vector2i(17, 0)
const WALL_CORNER_NW: Vector2i = Vector2i(18, 0)
const WALL_CORNER_NE: Vector2i = Vector2i(19, 0)
const WALL_CORRIDOR_EW: Vector2i = Vector2i(20, 0)
const WALL_CORRIDOR_NS: Vector2i = Vector2i(21, 0)
const WALL_PENINSULA_S: Vector2i = Vector2i(22, 0)
const WALL_PENINSULA_N: Vector2i = Vector2i(23, 0)
const WALL_PENINSULA_E: Vector2i = Vector2i(24, 0)
const WALL_PENINSULA_W: Vector2i = Vector2i(25, 0)
const WALL_PILLAR: Vector2i = Vector2i(26, 0)
const WALL_CROSS: Vector2i = Vector2i(27, 0)
const WALL_T_SOUTH: Vector2i = Vector2i(28, 0)
const WALL_T_NORTH: Vector2i = Vector2i(29, 0)
const WALL_T_WEST: Vector2i = Vector2i(30, 0)
const WALL_T_EAST: Vector2i = Vector2i(31, 0)
const WALL_CORNER_NW_T: Vector2i = Vector2i(32, 0)
const WALL_CORNER_NE_T: Vector2i = Vector2i(33, 0)
const WALL_CORNER_SW_T: Vector2i = Vector2i(34, 0)
const WALL_CORNER_SE_T: Vector2i = Vector2i(35, 0)
const WALL_EDGE_EW: Vector2i = Vector2i(36, 0)
const WALL_NORTH_SE: Vector2i = Vector2i(37, 0)
const WALL_NORTH_SW: Vector2i = Vector2i(38, 0)
const WALL_SOUTH_NE: Vector2i = Vector2i(39, 0)
const WALL_SOUTH_NW: Vector2i = Vector2i(40, 0)
const WALL_WEST_NE: Vector2i = Vector2i(41, 0)
const WALL_WEST_SE: Vector2i = Vector2i(42, 0)
const WALL_EAST_NW: Vector2i = Vector2i(43, 0)
const WALL_EAST_SW: Vector2i = Vector2i(44, 0)
const WALL_DIAG_NE_NW: Vector2i = Vector2i(45, 0)
const WALL_DIAG_NE_SE: Vector2i = Vector2i(46, 0)
const WALL_DIAG_NW_SW: Vector2i = Vector2i(47, 0)
const WALL_DIAG_NE_SW: Vector2i = Vector2i(48, 0)
const WALL_DIAG_NW_SE: Vector2i = Vector2i(49, 0)
const WALL_DIAG3_NO_SW: Vector2i = Vector2i(50, 0)
const WALL_DIAG3_NO_SE: Vector2i = Vector2i(51, 0)
const WALL_DIAG3_NO_NW: Vector2i = Vector2i(52, 0)
const WALL_DIAG3_NO_NE: Vector2i = Vector2i(53, 0)
const TILE_DEFS_COUNT: int = 47

## Runtime flip symmetry classification for wall tiles.
## 0 = no flips, 1 = H only, 2 = V only, 3 = H+V (4 variants).
## Indexed by tile def offset (WALL_INTERIOR.x - 7 = 0, WALL_NOTCH_NE.x - 7 = 1, etc.)
const _WALL_FLIP_CLASS: PackedByteArray = [
	3, # 00 INTERIOR      — fully symmetric
	0, # 01 NOTCH_NE       — asymmetric corner
	0, # 02 NOTCH_NW       — asymmetric corner
	0, # 03 NOTCH_SE       — asymmetric corner
	0, # 04 NOTCH_SW       — asymmetric corner
	1, # 05 SOUTH          — H-symmetric
	1, # 06 NORTH          — H-symmetric
	2, # 07 WEST           — V-symmetric
	2, # 08 EAST           — V-symmetric
	0, # 09 CORNER_SW      — asymmetric
	0, # 10 CORNER_SE      — asymmetric
	0, # 11 CORNER_NW      — asymmetric
	0, # 12 CORNER_NE      — asymmetric
	2, # 13 CORRIDOR_EW    — V-symmetric (wall edges same top/bottom)
	1, # 14 CORRIDOR_NS    — H-symmetric
	1, # 15 PENINSULA_S    — H-symmetric
	1, # 16 PENINSULA_N    — H-symmetric
	2, # 17 PENINSULA_E    — V-symmetric
	2, # 18 PENINSULA_W    — V-symmetric
	3, # 19 PILLAR         — fully symmetric
	3, # 20 CROSS          — fully symmetric
	1, # 21 T_SOUTH        — H-symmetric
	1, # 22 T_NORTH        — H-symmetric
	0, # 23 T_WEST         — asymmetric (wallEdge logic)
	0, # 24 T_EAST         — asymmetric (wallEdge logic)
	0, # 25 CORNER_NW_T    — asymmetric
	0, # 26 CORNER_NE_T    — asymmetric
	0, # 27 CORNER_SW_T    — asymmetric
	0, # 28 CORNER_SE_T    — asymmetric
	2, # 29 EDGE_EW        — V-symmetric
	0, # 30 NORTH_SE       — asymmetric
	0, # 31 NORTH_SW       — asymmetric
	0, # 32 SOUTH_NE       — asymmetric
	0, # 33 SOUTH_NW       — asymmetric
	0, # 34 WEST_NE        — asymmetric
	0, # 35 WEST_SE        — asymmetric
	0, # 36 EAST_NW        — asymmetric
	0, # 37 EAST_SW        — asymmetric
	1, # 38 DIAG_NE_NW     — H-symmetric (both notches top)
	0, # 39 DIAG_NE_SE     — asymmetric
	0, # 40 DIAG_NW_SW     — asymmetric
	0, # 41 DIAG_NE_SW     — asymmetric
	0, # 42 DIAG_NW_SE     — asymmetric
	0, # 43 DIAG3_NO_SW    — asymmetric
	0, # 44 DIAG3_NO_SE    — asymmetric
	0, # 45 DIAG3_NO_NW    — asymmetric
	0, # 46 DIAG3_NO_NE    — asymmetric
]

## Lookup: flip_class → array of [flip_h, flip_v] pairs for alternative tiles.
const _FLIP_TRANSFORMS: Array = [
	[],                                    # class 0: no flips
	[[true, false]],                       # class 1: H-flip only
	[[false, true]],                       # class 2: V-flip only
	[[true, false], [false, true], [true, true]],  # class 3: H, V, H+V
]

## How many alternative tile IDs exist per flip class (0=1, 1=2, 2=2, 3=4).
static var wall_flip_alt_count: PackedByteArray = PackedByteArray([1, 2, 2, 4])

const TILE_ROOF: Vector2i = Vector2i(0, 0)
const TILE_INTERIOR_FILL: Vector2i = Vector2i(1, 0)
const TILE_SHADOW_SOUTH: Vector2i = Vector2i(2, 0)
const TILE_SHADOW_EAST: Vector2i = Vector2i(3, 0)
const TILE_TOP_EDGE: Vector2i = Vector2i(4, 0)
const TILE_SHADOW_NORTH: Vector2i = Vector2i(5, 0)
const TILE_SHADOW_WEST: Vector2i = Vector2i(6, 0)

static func build_tilesets(balance: WorldGenBalance, biome: BiomeData) -> Dictionary:
	return {
		"terrain": _build_terrain_tileset(balance, biome),
		"overlay": _build_overlay_tileset(balance, biome),
	}

static func build_underground_terrain_tileset(balance: WorldGenBalance, biome: BiomeData) -> TileSet:
	return _build_terrain_tileset(balance, biome, ROCK_FACES_DUNGEON_PATH)

static func _build_terrain_tileset(balance: WorldGenBalance, biome: BiomeData, faces_path: String = ROCK_FACES_PATH) -> TileSet:
	var ts: int = balance.tile_size
	var faces_tex: Texture2D = load(faces_path) as Texture2D
	var atlas_tiles: int = 0
	var faces_img: Image = null
	var atlas_cols: int = 0
	if faces_tex:
		faces_img = faces_tex.get_image()
		if faces_img:
			atlas_cols = faces_img.get_width() / ts
			var atlas_rows: int = faces_img.get_height() / ts
			atlas_tiles = atlas_cols * atlas_rows
	wall_base_count = TILE_DEFS_COUNT
	wall_variant_count = maxi(1, atlas_tiles / wall_base_count)
	print("[ChunkTilesetFactory] atlas_tiles=%d, wall_base_count=%d, wall_variant_count=%d" % [atlas_tiles, wall_base_count, wall_variant_count])
	var surface_extra_tiles: int = 8
	var extras_start: int = 7 + atlas_tiles
	tile_water = Vector2i(extras_start, 0)
	tile_sand = Vector2i(extras_start + 1, 0)
	tile_grass = Vector2i(extras_start + 2, 0)
	tile_sparse_flora = Vector2i(extras_start + 3, 0)
	tile_dense_flora = Vector2i(extras_start + 4, 0)
	tile_clearing = Vector2i(extras_start + 5, 0)
	tile_rocky_patch = Vector2i(extras_start + 6, 0)
	tile_wet_patch = Vector2i(extras_start + 7, 0)
	var total: int = extras_start + surface_extra_tiles
	var img := Image.create(ts * total, ts, false, Image.FORMAT_RGBA8)
	_draw_ground_tile(img, Rect2i(0, 0, ts, ts), biome.ground_color.darkened(0.12), 0)
	_draw_ground_tile(img, Rect2i(ts, 0, ts, ts), biome.ground_color, 1)
	_draw_ground_tile(img, Rect2i(ts * 2, 0, ts, ts), biome.ground_color.lightened(0.10), 2)
	_draw_rock_tile(img, Rect2i(ts * 3, 0, ts, ts), balance.rock_color)
	_draw_rock_interior_tile(img, Rect2i(ts * 4, 0, ts, ts), balance.rock_color)
	_draw_mined_floor_tile(img, Rect2i(ts * 5, 0, ts, ts), balance.mined_floor_color)
	_draw_entrance_tile(img, Rect2i(ts * 6, 0, ts, ts), balance.entrance_color, balance.mined_floor_color, biome.ground_color)
	if faces_img:
		for i: int in range(atlas_tiles):
			var src_col: int = i % atlas_cols
			var src_row: int = i / atlas_cols
			img.blit_rect(faces_img, Rect2i(src_col * ts, src_row * ts, ts, ts), Vector2i((7 + i) * ts, 0))
	_draw_water_tile(img, Rect2i(tile_water.x * ts, 0, ts, ts), biome.water_color)
	_draw_sand_tile(img, Rect2i(tile_sand.x * ts, 0, ts, ts), biome.sand_color, biome.water_color)
	_draw_grass_tile(img, Rect2i(tile_grass.x * ts, 0, ts, ts), biome.grass_color, biome.ground_color)
	_draw_sparse_flora_tile(img, Rect2i(tile_sparse_flora.x * ts, 0, ts, ts), biome.ground_color, biome.grass_color)
	_draw_dense_flora_tile(img, Rect2i(tile_dense_flora.x * ts, 0, ts, ts), biome.ground_color, biome.grass_color)
	_draw_clearing_tile(img, Rect2i(tile_clearing.x * ts, 0, ts, ts), biome.ground_color)
	_draw_rocky_patch_tile(img, Rect2i(tile_rocky_patch.x * ts, 0, ts, ts), biome.ground_color, balance.rock_color)
	_draw_wet_patch_tile(img, Rect2i(tile_wet_patch.x * ts, 0, ts, ts), biome.ground_color, biome.water_color)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	for x: int in range(total):
		src.create_tile(Vector2i(x, 0))
	## Create alternative tiles with runtime flips for wall tiles.
	for vi: int in range(wall_variant_count):
		for def_i: int in range(TILE_DEFS_COUNT):
			var flip_class: int = _WALL_FLIP_CLASS[def_i]
			if flip_class == 0:
				continue
			var atlas_x: int = 7 + def_i + vi * wall_base_count
			var coords := Vector2i(atlas_x, 0)
			var transforms: Array = _FLIP_TRANSFORMS[flip_class]
			for t_i: int in range(transforms.size()):
				var alt_id: int = src.create_alternative_tile(coords)
				var alt_data: TileData = src.get_tile_data(coords, alt_id)
				alt_data.flip_h = transforms[t_i][0]
				alt_data.flip_v = transforms[t_i][1]
	tileset.add_source(src, TERRAIN_SOURCE_ID)
	return tileset

static func get_surface_variation_tile(variation_id: int) -> Vector2i:
	match variation_id:
		SURFACE_VARIATION_SPARSE_FLORA:
			return tile_sparse_flora
		SURFACE_VARIATION_DENSE_FLORA:
			return tile_dense_flora
		SURFACE_VARIATION_CLEARING:
			return tile_clearing
		SURFACE_VARIATION_ROCKY_PATCH:
			return tile_rocky_patch
		SURFACE_VARIATION_WET_PATCH:
			return tile_wet_patch
		_:
			return Vector2i(-1, -1)

static func _build_overlay_tileset(balance: WorldGenBalance, _biome: BiomeData) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(balance.tile_size, balance.tile_size)
	# Overlay atlas is currently an inactive/unfinished subsystem.
	# _redraw_cliff_tile() is a no-op, so the game does not need a hard
	# runtime dependency on rock_overlay_atlas.png right now.
	return tileset

## Fog of war tileset for underground. Two tiles: UNSEEN (opaque black) and DISCOVERED (dim).
const FOG_SOURCE_ID: int = 0
const TILE_FOG_UNSEEN: Vector2i = Vector2i(0, 0)
const TILE_FOG_DISCOVERED: Vector2i = Vector2i(1, 0)

static func create_fog_tileset(tile_size: int) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile_size, tile_size)
	var image := Image.create(tile_size * 2, tile_size, false, Image.FORMAT_RGBA8)
	# Tile 0: UNSEEN — nearly black, fully opaque
	var unseen_color := Color(0.02, 0.02, 0.03, 1.0)
	for py: int in range(tile_size):
		for px: int in range(tile_size):
			image.set_pixel(px, py, unseen_color)
	# Tile 1: DISCOVERED — dark, semi-transparent
	var discovered_color := Color(0.03, 0.03, 0.05, 0.65)
	for py: int in range(tile_size):
		for px: int in range(tile_size, tile_size * 2):
			image.set_pixel(px, py, discovered_color)
	var texture := ImageTexture.create_from_image(image)
	var src := TileSetAtlasSource.new()
	src.texture = texture
	src.texture_region_size = Vector2i(tile_size, tile_size)
	src.create_tile(TILE_FOG_UNSEEN)
	src.create_tile(TILE_FOG_DISCOVERED)
	tileset.add_source(src, FOG_SOURCE_ID)
	return tileset

static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			image.set_pixel(px, py, color)

static func _draw_ground_tile(image: Image, rect: Rect2i, base_color: Color, variant_seed: int) -> void:
	_fill_rect(image, rect, base_color)
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var wave: float = sin(float(local_x + variant_seed * 7) * 0.22) * 0.015
			var grain: float = sin(float(local_y + variant_seed * 11) * 0.31 + float(local_x) * 0.07) * 0.02
			var c: Color = base_color.lightened(wave + grain)
			if (local_x + local_y + variant_seed) % 17 == 0:
				c = c.darkened(0.05)
			image.set_pixel(px, py, c)

static func _draw_rock_tile(image: Image, rect: Rect2i, base_color: Color) -> void:
	_fill_rect(image, rect, base_color)
	var highlight: Color = base_color.lightened(0.18)
	var shadow: Color = base_color.darkened(0.18)
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var ridge: float = sin(float(local_x) * 0.20 + float(local_y) * 0.06) * 0.05
			var strata: float = cos(float(local_y) * 0.16) * 0.04
			var c: Color = base_color.lightened(ridge + strata)
			if local_y < rect.size.y / 5:
				c = c.lightened(0.08)
			if local_x > rect.size.x * 0.7:
				c = c.darkened(0.06)
			image.set_pixel(px, py, c)
	for rock_idx: int in range(7):
		var center_x: int = rect.position.x + 8 + rock_idx * max(6, rect.size.x / 9)
		var center_y: int = rect.position.y + 10 + int(abs(sin(float(rock_idx) * 1.7)) * (rect.size.y * 0.55))
		_draw_blob(image, Vector2i(center_x, center_y), 4 + rock_idx % 3, highlight, shadow)

static func _draw_rock_interior_tile(image: Image, rect: Rect2i, base_color: Color) -> void:
	var dark: Color = base_color.darkened(0.25)
	_fill_rect(image, rect, dark)
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var strata: float = sin(float(local_y) * 0.12 + float(local_x) * 0.03) * 0.03
			var c: Color = dark.lightened(strata)
			if (local_x + local_y * 3) % 23 == 0:
				c = c.darkened(0.04)
			image.set_pixel(px, py, c)

static func _draw_mined_floor_tile(image: Image, rect: Rect2i, base_color: Color) -> void:
	_fill_rect(image, rect, base_color)
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var c: Color = base_color
			c = c.lightened(sin(float(local_x) * 0.15 + float(local_y) * 0.11) * 0.03)
			if local_y > rect.size.y * 0.72:
				c = c.darkened(0.07)
			image.set_pixel(px, py, c)
	for pebble_idx: int in range(8):
		var px: int = rect.position.x + 6 + (pebble_idx * 7) % max(8, rect.size.x - 10)
		var py: int = rect.position.y + 8 + int(abs(cos(float(pebble_idx) * 1.3)) * (rect.size.y - 16))
		_draw_blob(image, Vector2i(px, py), 2, base_color.lightened(0.12), base_color.darkened(0.18))

static func _draw_entrance_tile(image: Image, rect: Rect2i, base_color: Color, floor_color: Color, outside_color: Color) -> void:
	_draw_mined_floor_tile(image, rect, floor_color)
	var band_width: int = maxi(6, rect.size.x / 6)
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.position.x + band_width):
			var blend: float = float(px - rect.position.x) / float(maxi(1, band_width))
			var c: Color = outside_color.lerp(base_color, blend)
			image.set_pixel(px, py, c)
	var lip_color: Color = base_color.darkened(0.14)
	for py: int in range(rect.position.y, rect.position.y + maxi(3, rect.size.y / 12)):
		for px: int in range(rect.position.x + band_width, rect.end.x):
			image.set_pixel(px, py, lip_color)
	for py: int in range(rect.end.y - maxi(3, rect.size.y / 12), rect.end.y):
		for px: int in range(rect.position.x + band_width, rect.end.x):
			image.set_pixel(px, py, lip_color.darkened(0.04))

static func _draw_water_tile(image: Image, rect: Rect2i, base_color: Color) -> void:
	_fill_rect(image, rect, base_color.darkened(0.08))
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var wave: float = sin(float(local_x) * 0.32 + float(local_y) * 0.18) * 0.05
			var ripple: float = cos(float(local_y) * 0.28 - float(local_x) * 0.11) * 0.03
			var c: Color = base_color.lightened(wave + ripple)
			if local_y < rect.size.y / 3:
				c = c.lightened(0.06)
			image.set_pixel(px, py, c)

static func _draw_sand_tile(image: Image, rect: Rect2i, base_color: Color, water_color: Color) -> void:
	_fill_rect(image, rect, base_color)
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var grain: float = sin(float(local_x + local_y) * 0.24) * 0.025
			var c: Color = base_color.lightened(grain)
			if local_y < rect.size.y / 4:
				c = c.lerp(water_color, 0.12)
			if (local_x * 3 + local_y) % 19 == 0:
				c = c.darkened(0.06)
			image.set_pixel(px, py, c)

static func _draw_grass_tile(image: Image, rect: Rect2i, base_color: Color, ground_color: Color) -> void:
	_fill_rect(image, rect, ground_color.lerp(base_color, 0.68))
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var sway: float = sin(float(local_x) * 0.26 + float(local_y) * 0.09) * 0.04
			var c: Color = base_color.lightened(sway)
			if local_y > rect.size.y * 0.7:
				c = ground_color.lerp(c, 0.55)
			if (local_x + local_y * 5) % 13 == 0:
				c = c.darkened(0.05)
			image.set_pixel(px, py, c)

static func _draw_sparse_flora_tile(image: Image, rect: Rect2i, ground_color: Color, flora_color: Color) -> void:
	_draw_ground_tile(image, rect, ground_color, 3)
	var tuft_color: Color = ground_color.lerp(flora_color, 0.58)
	for tuft_idx: int in range(8):
		var px: int = rect.position.x + 6 + (tuft_idx * 7) % max(8, rect.size.x - 12)
		var py: int = rect.position.y + 10 + int(abs(sin(float(tuft_idx) * 1.9)) * (rect.size.y - 18))
		_draw_grass_tuft(image, Vector2i(px, py), 2, tuft_color)

static func _draw_dense_flora_tile(image: Image, rect: Rect2i, ground_color: Color, flora_color: Color) -> void:
	_fill_rect(image, rect, ground_color.lerp(flora_color, 0.28))
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var sway: float = sin(float(local_x) * 0.35 + float(local_y) * 0.14) * 0.05
			var c: Color = flora_color.lightened(sway)
			if local_y > rect.size.y * 0.74:
				c = ground_color.lerp(c, 0.45)
			if (local_x * 5 + local_y * 3) % 17 == 0:
				c = c.darkened(0.08)
			image.set_pixel(px, py, c)
	for tuft_idx: int in range(14):
		var px: int = rect.position.x + 4 + (tuft_idx * 5) % max(8, rect.size.x - 8)
		var py: int = rect.position.y + 8 + int(abs(cos(float(tuft_idx) * 1.3)) * (rect.size.y - 14))
		_draw_grass_tuft(image, Vector2i(px, py), 3, flora_color.lightened(0.08))

static func _draw_clearing_tile(image: Image, rect: Rect2i, ground_color: Color) -> void:
	_draw_ground_tile(image, rect, ground_color.lightened(0.08), 4)
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			if (local_x + local_y * 2) % 21 == 0:
				image.set_pixel(px, py, ground_color.darkened(0.08))

static func _draw_rocky_patch_tile(image: Image, rect: Rect2i, ground_color: Color, rock_color: Color) -> void:
	_draw_ground_tile(image, rect, ground_color.darkened(0.03), 5)
	for stone_idx: int in range(9):
		var px: int = rect.position.x + 7 + (stone_idx * 6) % max(8, rect.size.x - 12)
		var py: int = rect.position.y + 8 + int(abs(sin(float(stone_idx) * 1.5)) * (rect.size.y - 16))
		_draw_blob(image, Vector2i(px, py), 2 + stone_idx % 2, rock_color.lightened(0.12), rock_color.darkened(0.16))

static func _draw_wet_patch_tile(image: Image, rect: Rect2i, ground_color: Color, water_color: Color) -> void:
	_fill_rect(image, rect, ground_color.darkened(0.12).lerp(water_color, 0.18))
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var sheen: float = sin(float(local_x) * 0.28 + float(local_y) * 0.19) * 0.04
			var c: Color = ground_color.darkened(0.12).lerp(water_color, 0.18).lightened(sheen)
			if local_y < rect.size.y / 3:
				c = c.lightened(0.04)
			if (local_x * 2 + local_y * 7) % 23 == 0:
				c = c.lerp(water_color, 0.22)
			image.set_pixel(px, py, c)
	for puddle_idx: int in range(4):
		var px: int = rect.position.x + 10 + puddle_idx * max(8, rect.size.x / 5)
		var py: int = rect.position.y + rect.size.y / 2 + int(sin(float(puddle_idx) * 1.8) * 6.0)
		_draw_blob(image, Vector2i(px, py), 4, water_color.lightened(0.10), water_color.darkened(0.14))

static func _draw_grass_tuft(image: Image, center: Vector2i, height: int, color: Color) -> void:
	for blade: int in range(3):
		var blade_x: int = center.x + blade - 1
		for step: int in range(height):
			var py: int = center.y - step
			if blade_x < 0 or py < 0 or blade_x >= image.get_width() or py >= image.get_height():
				continue
			var blade_color: Color = color.lightened(float(height - step) * 0.03)
			image.set_pixel(blade_x, py, blade_color)

static func _draw_blob(image: Image, center: Vector2i, radius: int, light_color: Color, shadow_color: Color) -> void:
	for py: int in range(center.y - radius, center.y + radius + 1):
		for px: int in range(center.x - radius, center.x + radius + 1):
			if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
				continue
			var dx: float = float(px - center.x)
			var dy: float = float(py - center.y)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist > float(radius):
				continue
			var t: float = dist / float(max(1, radius))
			var c: Color = light_color.lerp(shadow_color, t)
			image.set_pixel(px, py, c)

static func _draw_south_shadow(image: Image, rect: Rect2i, color: Color) -> void:
	for py: int in range(rect.position.y, rect.end.y):
		var alpha: float = clampf(float(py - rect.position.y) / maxf(1.0, rect.size.y - 1.0), 0.0, 1.0)
		var row_color: Color = color
		row_color.a *= alpha
		for px: int in range(rect.position.x, rect.end.x):
			image.set_pixel(px, py, row_color)

static func _draw_east_shadow(image: Image, rect: Rect2i, color: Color) -> void:
	for px: int in range(rect.position.x, rect.end.x):
		var alpha: float = clampf(float(px - rect.position.x) / maxf(1.0, rect.size.x - 1.0), 0.0, 1.0)
		var column_color: Color = color
		column_color.a *= alpha
		for py: int in range(rect.position.y, rect.end.y):
			image.set_pixel(px, py, column_color)

static func _draw_north_shadow(image: Image, rect: Rect2i, color: Color) -> void:
	for py: int in range(rect.position.y, rect.end.y):
		var alpha: float = clampf(1.0 - float(py - rect.position.y) / maxf(1.0, rect.size.y - 1.0), 0.0, 1.0)
		var row_color: Color = color
		row_color.a *= alpha
		for px: int in range(rect.position.x, rect.end.x):
			image.set_pixel(px, py, row_color)

static func _draw_west_shadow(image: Image, rect: Rect2i, color: Color) -> void:
	for px: int in range(rect.position.x, rect.end.x):
		var alpha: float = clampf(1.0 - float(px - rect.position.x) / maxf(1.0, rect.size.x - 1.0), 0.0, 1.0)
		var column_color: Color = color
		column_color.a *= alpha
		for py: int in range(rect.position.y, rect.end.y):
			image.set_pixel(px, py, column_color)

static func _draw_top_edge(image: Image, rect: Rect2i, edge_color: Color, fill_color: Color) -> void:
	_fill_rect(image, rect, Color(0.0, 0.0, 0.0, 0.0))
	var lip_height: int = maxi(2, rect.size.y / 12)
	for py: int in range(rect.position.y, rect.position.y + lip_height):
		for px: int in range(rect.position.x, rect.end.x):
			image.set_pixel(px, py, edge_color)
	for py: int in range(rect.position.y + lip_height, rect.position.y + lip_height * 2):
		for px: int in range(rect.position.x, rect.end.x):
			image.set_pixel(px, py, fill_color.darkened(0.08))

static func _draw_roof_tile(image: Image, rect: Rect2i, roof_color: Color, rock_color: Color) -> void:
	_fill_rect(image, rect, roof_color)
	for py: int in range(rect.position.y, rect.end.y):
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var local_y: int = py - rect.position.y
			var ridge: float = sin(float(local_x) * 0.18 + float(local_y) * 0.05) * 0.03
			var c: Color = roof_color.lightened(ridge)
			if local_y < rect.size.y / 6:
				c = c.lightened(0.05)
			if local_x > rect.size.x * 0.72:
				c = c.darkened(0.05)
			image.set_pixel(px, py, c)
	for stone_idx: int in range(6):
		var center_x: int = rect.position.x + 10 + stone_idx * max(6, rect.size.x / 8)
		var center_y: int = rect.position.y + 8 + int(abs(cos(float(stone_idx) * 1.4)) * (rect.size.y * 0.45))
		_draw_blob(image, Vector2i(center_x, center_y), 3 + stone_idx % 2, rock_color.lightened(0.14), roof_color.darkened(0.10))
