class_name ChunkTilesetFactory
extends RefCounted

## Создаёт процедурные тайлсеты для мира.
## Это позволяет быстро менять визуал гор через balance-ресурс.

const TERRAIN_SOURCE_ID: int = 0
const OVERLAY_SOURCE_ID: int = 1

const ROCK_FACES_PATH: String = "res://assets/sprites/terrain/rock_faces_atlas.png"
const ROCK_FACES_DUNGEON_PATH: String = "res://assets/sprites/terrain/rock_faces_atlas_dungeon.png"
const GROUND_FACES_PATH: String = "res://assets/sprites/terrain/ground_faces_atlas.png"
const SAND_FACES_PATH: String = "res://assets/sprites/terrain/sand_faces_atlas.png"
## Количество базовых тайлов стен (без вариантов). Обновляется при сборке tileset.
static var wall_base_count: int = 0
## Количество вариантов (1 = без вариативности, 3 = три варианта).
static var wall_variant_count: int = 1
static var terrain_tiles_per_row: int = 64
const MAX_TERRAIN_ATLAS_EDGE_PX: int = 4096
const SURFACE_PALETTE_TILE_COUNT: int = 11

static var _surface_palette_tiles: Array[Dictionary] = []
## Offset of ground face tiles in atlas (linear index of first ground face tile)
static var ground_face_tiles_start: int = -1
static var sand_face_tiles_start: int = -1

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

## Rock visual-class tiles.
## Atlas offsets must match the canonical TD order from tools/sprite-forge/sprite_forge_v5.html.
## Keep the semantic WALL_* names stable so chunk visual logic does not depend on raw atlas indices.
const WALL_INTERIOR: Vector2i = Vector2i(7, 0)
const WALL_NOTCH_NE: Vector2i = Vector2i(8, 0)
const WALL_NOTCH_NW: Vector2i = Vector2i(9, 0)
const WALL_NOTCH_SE: Vector2i = Vector2i(10, 0)
const WALL_NOTCH_SW: Vector2i = Vector2i(11, 0)
const WALL_DIAG_NE_NW: Vector2i = Vector2i(12, 0)
const WALL_DIAG_NE_SE: Vector2i = Vector2i(13, 0)
const WALL_DIAG_NE_SW: Vector2i = Vector2i(14, 0)
const WALL_DIAG_NW_SE: Vector2i = Vector2i(15, 0)
const WALL_DIAG_NW_SW: Vector2i = Vector2i(16, 0)
const WALL_EDGE_EW: Vector2i = Vector2i(17, 0)
const WALL_DIAG3_NO_SW: Vector2i = Vector2i(18, 0)
const WALL_DIAG3_NO_SE: Vector2i = Vector2i(19, 0)
const WALL_DIAG3_NO_NW: Vector2i = Vector2i(20, 0)
const WALL_DIAG3_NO_NE: Vector2i = Vector2i(21, 0)
const WALL_CROSS: Vector2i = Vector2i(22, 0)
const WALL_NORTH: Vector2i = Vector2i(23, 0)
const WALL_NORTH_SE: Vector2i = Vector2i(24, 0)
const WALL_NORTH_SW: Vector2i = Vector2i(25, 0)
const WALL_T_NORTH: Vector2i = Vector2i(26, 0)
const WALL_SOUTH: Vector2i = Vector2i(27, 0)
const WALL_SOUTH_NE: Vector2i = Vector2i(28, 0)
const WALL_SOUTH_NW: Vector2i = Vector2i(29, 0)
const WALL_T_SOUTH: Vector2i = Vector2i(30, 0)
const WALL_EAST: Vector2i = Vector2i(31, 0)
const WALL_EAST_NW: Vector2i = Vector2i(32, 0)
const WALL_EAST_SW: Vector2i = Vector2i(33, 0)
const WALL_T_EAST: Vector2i = Vector2i(34, 0)
const WALL_WEST: Vector2i = Vector2i(35, 0)
const WALL_WEST_NE: Vector2i = Vector2i(36, 0)
const WALL_WEST_SE: Vector2i = Vector2i(37, 0)
const WALL_T_WEST: Vector2i = Vector2i(38, 0)
const WALL_CORNER_NW: Vector2i = Vector2i(39, 0)
const WALL_CORNER_NW_T: Vector2i = Vector2i(40, 0)
const WALL_CORNER_NE: Vector2i = Vector2i(41, 0)
const WALL_CORNER_NE_T: Vector2i = Vector2i(42, 0)
const WALL_CORNER_SW: Vector2i = Vector2i(43, 0)
const WALL_CORNER_SW_T: Vector2i = Vector2i(44, 0)
const WALL_CORNER_SE: Vector2i = Vector2i(45, 0)
const WALL_CORNER_SE_T: Vector2i = Vector2i(46, 0)
const WALL_CORRIDOR_NS: Vector2i = Vector2i(47, 0)
const WALL_CORRIDOR_EW: Vector2i = Vector2i(48, 0)
const WALL_PENINSULA_N: Vector2i = Vector2i(49, 0)
const WALL_PENINSULA_S: Vector2i = Vector2i(50, 0)
const WALL_PENINSULA_E: Vector2i = Vector2i(51, 0)
const WALL_PENINSULA_W: Vector2i = Vector2i(52, 0)
const WALL_PILLAR: Vector2i = Vector2i(53, 0)
const TILE_DEFS_COUNT: int = 47

## Runtime flip symmetry classification for wall tiles.
## 0 = no flips, 1 = H only, 2 = V only, 3 = H+V (4 variants).
## Indexed by sprite_forge_v5 TD order (offset 0..46 after the first 7 non-wall terrain tiles).
const _WALL_FLIP_CLASS: PackedByteArray = [
	3, # 00 INTERIOR      — fully symmetric
	0, # 01 NOTCH_NE       — asymmetric corner
	0, # 02 NOTCH_NW       — asymmetric corner
	0, # 03 NOTCH_SE       — asymmetric corner
	0, # 04 NOTCH_SW       — asymmetric corner
	1, # 05 DIAG_NE_NW     — H-symmetric
	0, # 06 DIAG_NE_SE     — asymmetric
	0, # 07 DIAG_NE_SW     — asymmetric
	0, # 08 DIAG_NW_SE     — asymmetric
	0, # 09 DIAG_NW_SW     — asymmetric
	2, # 10 DIAG_SE_SW     — V-symmetric (legacy EDGE_EW semantics)
	0, # 11 TRI_NO_SW      — asymmetric
	0, # 12 TRI_NO_SE      — asymmetric
	0, # 13 TRI_NO_NW      — asymmetric
	0, # 14 TRI_NO_NE      — asymmetric
	3, # 15 QUAD           — fully symmetric
	1, # 16 NORTH          — H-symmetric
	0, # 17 NORTH_SE       — asymmetric
	0, # 18 NORTH_SW       — asymmetric
	1, # 19 NORTH_SE_SW    — H-symmetric (legacy T_NORTH semantics)
	1, # 20 SOUTH          — H-symmetric
	0, # 21 SOUTH_NE       — asymmetric
	0, # 22 SOUTH_NW       — asymmetric
	1, # 23 SOUTH_NE_NW    — H-symmetric (legacy T_SOUTH semantics)
	2, # 24 EAST           — V-symmetric
	0, # 25 EAST_NW        — asymmetric
	0, # 26 EAST_SW        — asymmetric
	0, # 27 EAST_NW_SW     — asymmetric (legacy T_EAST semantics)
	2, # 28 WEST           — V-symmetric
	0, # 29 WEST_NE        — asymmetric
	0, # 30 WEST_SE        — asymmetric
	0, # 31 WEST_NE_SE     — asymmetric (legacy T_WEST semantics)
	0, # 32 CORNER_NW      — asymmetric
	0, # 33 CORNER_NW_CSE  — asymmetric
	0, # 34 CORNER_NE      — asymmetric
	0, # 35 CORNER_NE_CSW  — asymmetric
	0, # 36 CORNER_SW      — asymmetric
	0, # 37 CORNER_SW_CNE  — asymmetric
	0, # 38 CORNER_SE      — asymmetric
	0, # 39 CORNER_SE_CNW  — asymmetric
	1, # 40 CORRIDOR_NS    — H-symmetric
	2, # 41 CORRIDOR_EW    — V-symmetric
	1, # 42 PEN_N          — H-symmetric
	1, # 43 PEN_S          — H-symmetric
	2, # 44 PEN_E          — V-symmetric
	2, # 45 PEN_W          — V-symmetric
	3, # 46 PILLAR         — fully symmetric
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

static func build_surface_tileset(balance: WorldGenBalance, biomes: Array[BiomeData]) -> TileSet:
	return _build_surface_terrain_tileset(balance, biomes)

static func build_overlay_tileset(balance: WorldGenBalance, biome: BiomeData) -> TileSet:
	return _build_overlay_tileset(balance, biome)

static func build_underground_terrain_tileset(balance: WorldGenBalance, biome: BiomeData) -> TileSet:
	return _build_terrain_tileset(balance, biome, ROCK_FACES_DUNGEON_PATH)

static func get_surface_ground_tile(biome_palette_index: int, height_value: float) -> Vector2i:
	var palette: Dictionary = _get_surface_palette(biome_palette_index)
	if height_value < 0.38:
		return palette.get("ground_dark", TILE_GROUND_DARK)
	if height_value > 0.62:
		return palette.get("ground_light", TILE_GROUND_LIGHT)
	return palette.get("ground", TILE_GROUND)

static func get_surface_terrain_tile(terrain_type: int, biome_palette_index: int) -> Vector2i:
	var palette: Dictionary = _get_surface_palette(biome_palette_index)
	match terrain_type:
		TileGenData.TerrainType.WATER:
			return palette.get("water", tile_water)
		TileGenData.TerrainType.SAND:
			return palette.get("sand", tile_sand)
		TileGenData.TerrainType.GRASS:
			return palette.get("grass", tile_grass)
		_:
			return Vector2i(-1, -1)

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
	print("[ChunkTilesetFactory] rock_atlas=%d, wall_base=%d, variants=%d" % [atlas_tiles, wall_base_count, wall_variant_count])
	var surface_extra_tiles: int = 8
	var extras_start: int = 7 + atlas_tiles
	var total: int = extras_start + surface_extra_tiles
	terrain_tiles_per_row = _resolve_terrain_tiles_per_row(total, ts)
	var total_rows: int = int(ceili(float(total) / float(terrain_tiles_per_row)))
	var img := Image.create(ts * terrain_tiles_per_row, ts * total_rows, false, Image.FORMAT_RGBA8)
	_draw_ground_tile(img, _rect_for_linear_index(0, ts), biome.ground_color.darkened(0.12), 0)
	_draw_ground_tile(img, _rect_for_linear_index(1, ts), biome.ground_color, 1)
	_draw_ground_tile(img, _rect_for_linear_index(2, ts), biome.ground_color.lightened(0.10), 2)
	_draw_rock_tile(img, _rect_for_linear_index(3, ts), balance.rock_color)
	_draw_rock_interior_tile(img, _rect_for_linear_index(4, ts), balance.rock_color)
	_draw_mined_floor_tile(img, _rect_for_linear_index(5, ts), balance.mined_floor_color)
	_draw_entrance_tile(img, _rect_for_linear_index(6, ts), balance.entrance_color, balance.mined_floor_color, biome.ground_color)
	if faces_img:
		for i: int in range(atlas_tiles):
			var src_col: int = i % atlas_cols
			var src_row: int = i / atlas_cols
			img.blit_rect(faces_img, Rect2i(src_col * ts, src_row * ts, ts, ts), _coords_for_linear_index(7 + i) * ts)
	tile_water = _coords_for_linear_index(extras_start)
	tile_sand = _coords_for_linear_index(extras_start + 1)
	tile_grass = _coords_for_linear_index(extras_start + 2)
	tile_sparse_flora = _coords_for_linear_index(extras_start + 3)
	tile_dense_flora = _coords_for_linear_index(extras_start + 4)
	tile_clearing = _coords_for_linear_index(extras_start + 5)
	tile_rocky_patch = _coords_for_linear_index(extras_start + 6)
	tile_wet_patch = _coords_for_linear_index(extras_start + 7)
	_draw_water_tile(img, Rect2i(tile_water.x * ts, tile_water.y * ts, ts, ts), biome.water_color)
	_draw_sand_tile(img, Rect2i(tile_sand.x * ts, tile_sand.y * ts, ts, ts), biome.sand_color, biome.water_color)
	_draw_grass_tile(img, Rect2i(tile_grass.x * ts, tile_grass.y * ts, ts, ts), biome.grass_color, biome.ground_color)
	_draw_sparse_flora_tile(img, Rect2i(tile_sparse_flora.x * ts, tile_sparse_flora.y * ts, ts, ts), biome.ground_color, biome.grass_color)
	_draw_dense_flora_tile(img, Rect2i(tile_dense_flora.x * ts, tile_dense_flora.y * ts, ts, ts), biome.ground_color, biome.grass_color)
	_draw_clearing_tile(img, Rect2i(tile_clearing.x * ts, tile_clearing.y * ts, ts, ts), biome.ground_color)
	_draw_rocky_patch_tile(img, Rect2i(tile_rocky_patch.x * ts, tile_rocky_patch.y * ts, ts, ts), biome.ground_color, balance.rock_color)
	_draw_wet_patch_tile(img, Rect2i(tile_wet_patch.x * ts, tile_wet_patch.y * ts, ts, ts), biome.ground_color, biome.water_color)
	## Ground elevation faces — neutral gray atlas tinted with biome ground_color
	var ground_faces_tex: Texture2D = load(GROUND_FACES_PATH) as Texture2D
	var gf_count: int = 0
	ground_face_tiles_start = total
	if ground_faces_tex == null:
		push_warning("[ChunkTilesetFactory] ground_faces_atlas.png not found at %s" % GROUND_FACES_PATH)
	if ground_faces_tex:
		var gf_img: Image = ground_faces_tex.get_image()
		if gf_img:
			var gf_cols: int = gf_img.get_width() / ts
			var gf_rows: int = gf_img.get_height() / ts
			gf_count = mini(gf_cols * gf_rows, TILE_DEFS_COUNT)  ## Only first 47 (variant 0)
			## Tint gray atlas with biome ground_color
			## Blit ground faces untinted — color applied via layer modulate in Chunk
			var src_gf: Image = gf_img.duplicate()
			src_gf.decompress()
			if src_gf.get_format() != Image.FORMAT_RGBA8:
				src_gf.convert(Image.FORMAT_RGBA8)
			## Expand atlas image to fit new tiles
			var new_total: int = total + gf_count
			var new_rows: int = int(ceili(float(new_total) / float(terrain_tiles_per_row)))
			if new_rows * ts > img.get_height():
				var expanded := Image.create(img.get_width(), new_rows * ts, false, Image.FORMAT_RGBA8)
				expanded.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
				img = expanded
			for i: int in range(gf_count):
				var src_col: int = i % gf_cols
				var src_row: int = i / gf_cols
				var dst_coords: Vector2i = _coords_for_linear_index(ground_face_tiles_start + i)
				img.blit_rect(src_gf, Rect2i(src_col * ts, src_row * ts, ts, ts), dst_coords * ts)
			total = new_total
			print("[ChunkTilesetFactory] ground_faces: start=%d count=%d" % [ground_face_tiles_start, gf_count])
	## Sand elevation faces — same ground_faces atlas tinted with biome sand_color
	sand_face_tiles_start = total
	if ground_faces_tex and gf_count > 0:
		var gf_img2: Image = ground_faces_tex.get_image()
		if gf_img2:
			var gf_cols2: int = gf_img2.get_width() / ts
			var tinted_sf: Image = gf_img2.duplicate()
			tinted_sf.decompress()
			if tinted_sf.get_format() != Image.FORMAT_RGBA8:
				tinted_sf.convert(Image.FORMAT_RGBA8)
			var sand_tint: Color = biome.sand_color
			for py: int in range(tinted_sf.get_height()):
				for px: int in range(tinted_sf.get_width()):
					var c: Color = tinted_sf.get_pixel(px, py)
					var lum: float = c.r * 0.33 + c.g * 0.34 + c.b * 0.33
					tinted_sf.set_pixel(px, py, Color(sand_tint.r * lum * 2.0, sand_tint.g * lum * 2.0, sand_tint.b * lum * 2.0, c.a))
			var sf_count: int = gf_count
			var new_total2: int = total + sf_count
			var new_rows2: int = int(ceili(float(new_total2) / float(terrain_tiles_per_row)))
			if new_rows2 * ts > img.get_height():
				var expanded2 := Image.create(img.get_width(), new_rows2 * ts, false, Image.FORMAT_RGBA8)
				expanded2.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
				img = expanded2
			for i: int in range(sf_count):
				var src_col: int = i % gf_cols2
				var src_row: int = i / gf_cols2
				var dst_coords: Vector2i = _coords_for_linear_index(sand_face_tiles_start + i)
				img.blit_rect(tinted_sf, Rect2i(src_col * ts, src_row * ts, ts, ts), dst_coords * ts)
			total = new_total2
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	for tile_index: int in range(total):
		src.create_tile(_coords_for_linear_index(tile_index))
	## Create alternative tiles with runtime flips for wall tiles.
	for vi: int in range(wall_variant_count):
		for def_i: int in range(TILE_DEFS_COUNT):
			var flip_class: int = _WALL_FLIP_CLASS[def_i]
			if flip_class == 0:
				continue
			var coords := _coords_for_linear_index(7 + def_i + vi * wall_base_count)
			var transforms: Array = _FLIP_TRANSFORMS[flip_class]
			for t_i: int in range(transforms.size()):
				var alt_id: int = src.create_alternative_tile(coords)
				var alt_data: TileData = src.get_tile_data(coords, alt_id)
				alt_data.flip_h = transforms[t_i][0]
				alt_data.flip_v = transforms[t_i][1]
	tileset.add_source(src, TERRAIN_SOURCE_ID)
	return tileset

static func _build_surface_terrain_tileset(balance: WorldGenBalance, biomes: Array[BiomeData]) -> TileSet:
	var ordered_biomes: Array[BiomeData] = biomes.duplicate()
	if ordered_biomes.is_empty():
		ordered_biomes.append(BiomeData.new())
	var default_biome: BiomeData = ordered_biomes[0]
	var ts: int = balance.tile_size
	var faces_tex: Texture2D = load(ROCK_FACES_PATH) as Texture2D
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
	var palette_start: int = 7 + atlas_tiles
	var total: int = palette_start + SURFACE_PALETTE_TILE_COUNT * ordered_biomes.size()
	terrain_tiles_per_row = _resolve_terrain_tiles_per_row(total, ts)
	var total_rows: int = int(ceili(float(total) / float(terrain_tiles_per_row)))
	var img := Image.create(ts * terrain_tiles_per_row, ts * total_rows, false, Image.FORMAT_RGBA8)
	_draw_ground_tile(img, _rect_for_linear_index(0, ts), default_biome.ground_color.darkened(0.12), 0)
	_draw_ground_tile(img, _rect_for_linear_index(1, ts), default_biome.ground_color, 1)
	_draw_ground_tile(img, _rect_for_linear_index(2, ts), default_biome.ground_color.lightened(0.10), 2)
	_draw_rock_tile(img, _rect_for_linear_index(3, ts), balance.rock_color)
	_draw_rock_interior_tile(img, _rect_for_linear_index(4, ts), balance.rock_color)
	_draw_mined_floor_tile(img, _rect_for_linear_index(5, ts), balance.mined_floor_color)
	_draw_entrance_tile(img, _rect_for_linear_index(6, ts), balance.entrance_color, balance.mined_floor_color, default_biome.ground_color)
	if faces_img:
		for i: int in range(atlas_tiles):
			var src_col: int = i % atlas_cols
			var src_row: int = i / atlas_cols
			img.blit_rect(faces_img, Rect2i(src_col * ts, src_row * ts, ts, ts), _coords_for_linear_index(7 + i) * ts)
	_surface_palette_tiles.clear()
	ground_face_tiles_start = -1
	sand_face_tiles_start = -1
	var ground_faces_img: Image = _load_face_image(GROUND_FACES_PATH)
	var sand_faces_img: Image = _load_face_image(SAND_FACES_PATH)
	for biome_index: int in range(ordered_biomes.size()):
		var biome: BiomeData = ordered_biomes[biome_index]
		var start_index: int = palette_start + biome_index * SURFACE_PALETTE_TILE_COUNT
		var palette := {
			"ground_dark": _coords_for_linear_index(start_index),
			"ground": _coords_for_linear_index(start_index + 1),
			"ground_light": _coords_for_linear_index(start_index + 2),
			"water": _coords_for_linear_index(start_index + 3),
			"sand": _coords_for_linear_index(start_index + 4),
			"grass": _coords_for_linear_index(start_index + 5),
			"sparse_flora": _coords_for_linear_index(start_index + 6),
			"dense_flora": _coords_for_linear_index(start_index + 7),
			"clearing": _coords_for_linear_index(start_index + 8),
			"rocky_patch": _coords_for_linear_index(start_index + 9),
			"wet_patch": _coords_for_linear_index(start_index + 10),
		}
		var ground_dark: Vector2i = palette["ground_dark"]
		var ground: Vector2i = palette["ground"]
		var ground_light: Vector2i = palette["ground_light"]
		var water: Vector2i = palette["water"]
		var sand: Vector2i = palette["sand"]
		var grass: Vector2i = palette["grass"]
		var sparse_flora: Vector2i = palette["sparse_flora"]
		var dense_flora: Vector2i = palette["dense_flora"]
		var clearing: Vector2i = palette["clearing"]
		var rocky_patch: Vector2i = palette["rocky_patch"]
		var wet_patch: Vector2i = palette["wet_patch"]
		_draw_ground_tile(img, Rect2i(ground_dark.x * ts, ground_dark.y * ts, ts, ts), biome.ground_color.darkened(0.12), 0)
		_draw_ground_tile(img, Rect2i(ground.x * ts, ground.y * ts, ts, ts), biome.ground_color, 1)
		_draw_ground_tile(img, Rect2i(ground_light.x * ts, ground_light.y * ts, ts, ts), biome.ground_color.lightened(0.10), 2)
		_draw_water_tile(img, Rect2i(water.x * ts, water.y * ts, ts, ts), biome.water_color)
		_draw_sand_tile(img, Rect2i(sand.x * ts, sand.y * ts, ts, ts), biome.sand_color, biome.water_color)
		_draw_grass_tile(img, Rect2i(grass.x * ts, grass.y * ts, ts, ts), biome.grass_color, biome.ground_color)
		_draw_sparse_flora_tile(img, Rect2i(sparse_flora.x * ts, sparse_flora.y * ts, ts, ts), biome.ground_color, biome.grass_color)
		_draw_dense_flora_tile(img, Rect2i(dense_flora.x * ts, dense_flora.y * ts, ts, ts), biome.ground_color, biome.grass_color)
		_draw_clearing_tile(img, Rect2i(clearing.x * ts, clearing.y * ts, ts, ts), biome.ground_color)
		_draw_rocky_patch_tile(img, Rect2i(rocky_patch.x * ts, rocky_patch.y * ts, ts, ts), biome.ground_color, balance.rock_color)
		_draw_wet_patch_tile(img, Rect2i(wet_patch.x * ts, wet_patch.y * ts, ts, ts), biome.ground_color, biome.water_color)
		var ground_face_append: Dictionary = _append_face_tiles(
			img,
			total,
			_tint_face_image(ground_faces_img, biome.ground_color),
			ts
		)
		img = ground_face_append["image"]
		var ground_face_start: int = int(ground_face_append["start"])
		total = int(ground_face_append["total"])
		if biome_index == 0:
			ground_face_tiles_start = ground_face_start
		var sand_face_append: Dictionary = _append_face_tiles(
			img,
			total,
			_tint_face_image(sand_faces_img, biome.sand_color),
			ts
		)
		img = sand_face_append["image"]
		var sand_face_start: int = int(sand_face_append["start"])
		total = int(sand_face_append["total"])
		if biome_index == 0:
			sand_face_tiles_start = sand_face_start
		palette["ground_face_start"] = ground_face_start
		palette["sand_face_start"] = sand_face_start
		_surface_palette_tiles.append(palette)
	tile_water = _coords_for_linear_index(palette_start + 3)
	tile_sand = _coords_for_linear_index(palette_start + 4)
	tile_grass = _coords_for_linear_index(palette_start + 5)
	tile_sparse_flora = _coords_for_linear_index(palette_start + 6)
	tile_dense_flora = _coords_for_linear_index(palette_start + 7)
	tile_clearing = _coords_for_linear_index(palette_start + 8)
	tile_rocky_patch = _coords_for_linear_index(palette_start + 9)
	tile_wet_patch = _coords_for_linear_index(palette_start + 10)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	for tile_index: int in range(total):
		src.create_tile(_coords_for_linear_index(tile_index))
	for vi: int in range(wall_variant_count):
		for def_i: int in range(TILE_DEFS_COUNT):
			var flip_class: int = _WALL_FLIP_CLASS[def_i]
			if flip_class == 0:
				continue
			var coords := _coords_for_linear_index(7 + def_i + vi * wall_base_count)
			var transforms: Array = _FLIP_TRANSFORMS[flip_class]
			for t_i: int in range(transforms.size()):
				var alt_id: int = src.create_alternative_tile(coords)
				var alt_data: TileData = src.get_tile_data(coords, alt_id)
				alt_data.flip_h = transforms[t_i][0]
				alt_data.flip_v = transforms[t_i][1]
	tileset.add_source(src, TERRAIN_SOURCE_ID)
	return tileset

static func get_surface_variation_tile(variation_id: int, biome_palette_index: int = 0) -> Vector2i:
	var palette: Dictionary = _get_surface_palette(biome_palette_index)
	match variation_id:
		SURFACE_VARIATION_SPARSE_FLORA:
			return palette.get("sparse_flora", tile_sparse_flora)
		SURFACE_VARIATION_DENSE_FLORA:
			return palette.get("dense_flora", tile_dense_flora)
		SURFACE_VARIATION_CLEARING:
			return palette.get("clearing", tile_clearing)
		SURFACE_VARIATION_ROCKY_PATCH:
			return palette.get("rocky_patch", tile_rocky_patch)
		SURFACE_VARIATION_WET_PATCH:
			return palette.get("wet_patch", tile_wet_patch)
		_:
			return Vector2i(-1, -1)

static func get_sand_face_coords(wall_def: Vector2i, biome_palette_index: int = -1) -> Vector2i:
	var def_index: int = _wall_def_index(wall_def)
	if def_index < 0:
		return Vector2i(-1, -1)
	if biome_palette_index >= 0:
		var palette: Dictionary = _get_surface_palette(biome_palette_index)
		var start_index: int = int(palette.get("sand_face_start", -1))
		if start_index >= 0:
			return _coords_for_linear_index(start_index + def_index)
	if sand_face_tiles_start < 0:
		return Vector2i(-1, -1)
	return _coords_for_linear_index(sand_face_tiles_start + def_index)

static func get_ground_face_coords(wall_def: Vector2i, biome_palette_index: int = -1) -> Vector2i:
	var def_index: int = _wall_def_index(wall_def)
	if def_index < 0:
		return Vector2i(-1, -1)
	if biome_palette_index >= 0:
		var palette: Dictionary = _get_surface_palette(biome_palette_index)
		var start_index: int = int(palette.get("ground_face_start", -1))
		if start_index >= 0:
			return _coords_for_linear_index(start_index + def_index)
	if ground_face_tiles_start < 0:
		return Vector2i(-1, -1)
	return _coords_for_linear_index(ground_face_tiles_start + def_index)

static func get_wall_variant_coords(base: Vector2i, variant_index: int) -> Vector2i:
	var def_index: int = base.x - 7
	if def_index < 0:
		return base
	return _coords_for_linear_index(7 + def_index + variant_index * wall_base_count)

static func _wall_def_index(wall_def: Vector2i) -> int:
	var def_index: int = wall_def.x - 7
	if def_index < 0 or def_index >= TILE_DEFS_COUNT:
		return -1
	return def_index

static func _load_face_image(face_path: String) -> Image:
	var face_tex: Texture2D = load(face_path) as Texture2D
	if face_tex == null:
		push_warning("[ChunkTilesetFactory] face atlas not found at %s" % face_path)
		return null
	var face_img: Image = face_tex.get_image()
	if face_img == null:
		push_warning("[ChunkTilesetFactory] failed to read face atlas at %s" % face_path)
	return face_img

static func _tint_face_image(face_img: Image, tint_color: Color) -> Image:
	if face_img == null:
		return null
	var tinted: Image = face_img.duplicate()
	tinted.decompress()
	if tinted.get_format() != Image.FORMAT_RGBA8:
		tinted.convert(Image.FORMAT_RGBA8)
	for py: int in range(tinted.get_height()):
		for px: int in range(tinted.get_width()):
			var c: Color = tinted.get_pixel(px, py)
			var lum: float = c.r * 0.33 + c.g * 0.34 + c.b * 0.33
			tinted.set_pixel(
				px,
				py,
				Color(
					minf(1.0, tint_color.r * lum * 2.0),
					minf(1.0, tint_color.g * lum * 2.0),
					minf(1.0, tint_color.b * lum * 2.0),
					c.a
				)
			)
	return tinted

static func _ensure_terrain_image_rows(img: Image, total_tiles: int, tile_size: int) -> Image:
	var required_rows: int = int(ceili(float(total_tiles) / float(terrain_tiles_per_row)))
	if required_rows * tile_size <= img.get_height():
		return img
	var expanded := Image.create(img.get_width(), required_rows * tile_size, false, Image.FORMAT_RGBA8)
	expanded.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	return expanded

static func _append_face_tiles(img: Image, total: int, face_img: Image, tile_size: int) -> Dictionary:
	if face_img == null:
		return {"image": img, "start": -1, "count": 0, "total": total}
	var face_cols: int = face_img.get_width() / tile_size
	var face_rows: int = face_img.get_height() / tile_size
	var face_count: int = mini(face_cols * face_rows, TILE_DEFS_COUNT)
	if face_count <= 0:
		return {"image": img, "start": -1, "count": 0, "total": total}
	var start_index: int = total
	var new_total: int = total + face_count
	img = _ensure_terrain_image_rows(img, new_total, tile_size)
	for i: int in range(face_count):
		var src_col: int = i % face_cols
		var src_row: int = i / face_cols
		var dst_coords: Vector2i = _coords_for_linear_index(start_index + i)
		img.blit_rect(face_img, Rect2i(src_col * tile_size, src_row * tile_size, tile_size, tile_size), dst_coords * tile_size)
	return {"image": img, "start": start_index, "count": face_count, "total": new_total}

static func _resolve_terrain_tiles_per_row(total_tiles: int, tile_size: int) -> int:
	if total_tiles <= 0:
		return 1
	var max_columns: int = maxi(1, int(floori(float(MAX_TERRAIN_ATLAS_EDGE_PX) / float(maxi(1, tile_size)))))
	return max_columns

static func _coords_for_linear_index(index: int) -> Vector2i:
	var columns: int = maxi(1, terrain_tiles_per_row)
	return Vector2i(index % columns, index / columns)

static func _rect_for_linear_index(index: int, tile_size: int) -> Rect2i:
	var coords: Vector2i = _coords_for_linear_index(index)
	return Rect2i(coords.x * tile_size, coords.y * tile_size, tile_size, tile_size)

static func _get_surface_palette(biome_palette_index: int) -> Dictionary:
	if _surface_palette_tiles.is_empty():
		return {}
	var clamped_index: int = clampi(biome_palette_index, 0, _surface_palette_tiles.size() - 1)
	return _surface_palette_tiles[clamped_index] as Dictionary

static func _build_overlay_tileset(balance: WorldGenBalance, _biome: BiomeData) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(balance.tile_size, balance.tile_size)
	var ts: int = balance.tile_size
	var image := Image.create(ts * 7, ts, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_draw_overlay_fill(image, Rect2i(TILE_ROOF.x * ts, 0, ts, ts), Color(0.04, 0.03, 0.02, 0.24))
	_draw_overlay_fill(image, Rect2i(TILE_INTERIOR_FILL.x * ts, 0, ts, ts), Color(0.02, 0.02, 0.02, 0.16))
	_draw_overlay_vertical_shadow(image, Rect2i(TILE_SHADOW_SOUTH.x * ts, 0, ts, ts), false, Color(0.02, 0.02, 0.01, 0.50))
	_draw_overlay_horizontal_shadow(image, Rect2i(TILE_SHADOW_EAST.x * ts, 0, ts, ts), true, Color(0.02, 0.02, 0.01, 0.32))
	_draw_overlay_top_edge(image, Rect2i(TILE_TOP_EDGE.x * ts, 0, ts, ts))
	_draw_overlay_vertical_shadow(image, Rect2i(TILE_SHADOW_NORTH.x * ts, 0, ts, ts), true, Color(0.02, 0.02, 0.01, 0.24))
	_draw_overlay_horizontal_shadow(image, Rect2i(TILE_SHADOW_WEST.x * ts, 0, ts, ts), false, Color(0.02, 0.02, 0.01, 0.32))
	var texture := ImageTexture.create_from_image(image)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(ts, ts)
	for coords: Vector2i in [
		TILE_ROOF,
		TILE_INTERIOR_FILL,
		TILE_SHADOW_SOUTH,
		TILE_SHADOW_EAST,
		TILE_TOP_EDGE,
		TILE_SHADOW_NORTH,
		TILE_SHADOW_WEST,
	]:
		source.create_tile(coords)
	tileset.add_source(source, OVERLAY_SOURCE_ID)
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

static func _draw_overlay_fill(image: Image, rect: Rect2i, color: Color) -> void:
	_fill_rect(image, rect, color)

static func _draw_overlay_vertical_shadow(image: Image, rect: Rect2i, from_top: bool, base_color: Color) -> void:
	for py: int in range(rect.position.y, rect.end.y):
		var t: float = float(py - rect.position.y) / float(maxi(1, rect.size.y - 1))
		var strength: float = 1.0 - t if from_top else t
		var color: Color = Color(base_color.r, base_color.g, base_color.b, base_color.a * strength)
		for px: int in range(rect.position.x, rect.end.x):
			image.set_pixel(px, py, color)

static func _draw_overlay_horizontal_shadow(image: Image, rect: Rect2i, from_right: bool, base_color: Color) -> void:
	for px: int in range(rect.position.x, rect.end.x):
		var t: float = float(px - rect.position.x) / float(maxi(1, rect.size.x - 1))
		var strength: float = t if from_right else 1.0 - t
		var color: Color = Color(base_color.r, base_color.g, base_color.b, base_color.a * strength)
		for py: int in range(rect.position.y, rect.end.y):
			image.set_pixel(px, py, color)

static func _draw_overlay_top_edge(image: Image, rect: Rect2i) -> void:
	for py: int in range(rect.position.y, rect.end.y):
		var local_y: int = py - rect.position.y
		var alpha: float = 0.0
		if local_y <= 2:
			alpha = 0.38 - float(local_y) * 0.08
		elif local_y <= 6:
			alpha = 0.12 - float(local_y - 3) * 0.02
		if alpha <= 0.0:
			continue
		for px: int in range(rect.position.x, rect.end.x):
			var local_x: int = px - rect.position.x
			var jitter: float = 0.0
			if (local_x * 5 + local_y * 11) % 9 == 0:
				jitter = 0.05
			image.set_pixel(px, py, Color(0.90, 0.82, 0.66, alpha + jitter))

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
