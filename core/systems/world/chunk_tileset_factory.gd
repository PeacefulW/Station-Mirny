class_name ChunkTilesetFactory
extends RefCounted

## Создаёт процедурные тайлсеты для мира.
## Это позволяет быстро менять визуал гор через balance-ресурс.

const TERRAIN_SOURCE_ID: int = 0
const OVERLAY_SOURCE_ID: int = 1

const TILE_GROUND_DARK: Vector2i = Vector2i(0, 0)
const TILE_GROUND: Vector2i = Vector2i(1, 0)
const TILE_GROUND_LIGHT: Vector2i = Vector2i(2, 0)
const TILE_ROCK: Vector2i = Vector2i(3, 0)
const TILE_ROCK_INTERIOR: Vector2i = Vector2i(4, 0)
const TILE_MINED_FLOOR: Vector2i = Vector2i(5, 0)
const TILE_MOUNTAIN_ENTRANCE: Vector2i = Vector2i(6, 0)

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

static func _build_terrain_tileset(balance: WorldGenBalance, biome: BiomeData) -> TileSet:
	var ts: int = balance.tile_size
	var img := Image.create(ts * 7, ts, false, Image.FORMAT_RGBA8)
	_draw_ground_tile(img, Rect2i(0, 0, ts, ts), biome.ground_color.darkened(0.12), 0)
	_draw_ground_tile(img, Rect2i(ts, 0, ts, ts), biome.ground_color, 1)
	_draw_ground_tile(img, Rect2i(ts * 2, 0, ts, ts), biome.ground_color.lightened(0.10), 2)
	_draw_rock_tile(img, Rect2i(ts * 3, 0, ts, ts), balance.rock_color)
	_draw_rock_interior_tile(img, Rect2i(ts * 4, 0, ts, ts), balance.rock_color)
	_draw_mined_floor_tile(img, Rect2i(ts * 5, 0, ts, ts), balance.mined_floor_color)
	_draw_entrance_tile(img, Rect2i(ts * 6, 0, ts, ts), balance.entrance_color, balance.mined_floor_color, biome.ground_color)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	for x: int in range(7):
		src.create_tile(Vector2i(x, 0))
	tileset.add_source(src, TERRAIN_SOURCE_ID)
	return tileset

static func _build_overlay_tileset(balance: WorldGenBalance, biome: BiomeData) -> TileSet:
	var ts: int = balance.tile_size
	var img := Image.create(ts * 7, ts, false, Image.FORMAT_RGBA8)
	_draw_roof_tile(img, Rect2i(0, 0, ts, ts), balance.roof_color, balance.rock_color)
	_draw_rock_interior_tile(img, Rect2i(ts, 0, ts, ts), balance.rock_color)
	_draw_south_shadow(img, Rect2i(ts * 2, 0, ts, ts), balance.rock_shadow_color)
	_draw_east_shadow(img, Rect2i(ts * 3, 0, ts, ts), balance.rock_shadow_color)
	_draw_top_edge(img, Rect2i(ts * 4, 0, ts, ts), balance.rock_top_color, biome.ground_color)
	_draw_north_shadow(img, Rect2i(ts * 5, 0, ts, ts), balance.rock_shadow_color)
	_draw_west_shadow(img, Rect2i(ts * 6, 0, ts, ts), balance.rock_shadow_color)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(ts, ts)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(ts, ts)
	for x: int in range(7):
		src.create_tile(Vector2i(x, 0))
	tileset.add_source(src, OVERLAY_SOURCE_ID)
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
