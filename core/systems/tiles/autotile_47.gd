class_name Autotile47
extends RefCounted

const CASE_COUNT: int = 47
const DEFAULT_VARIANT_COUNT: int = 6
const ATLAS_COLUMNS: int = 8
const VARIANT_SEED_OFFSET: int = 907

static var _catalog_ready: bool = false
static var _base_index_by_signature_code: Dictionary = {}

static func build_signature_code(
	n: bool,
	ne: bool,
	e: bool,
	se: bool,
	s: bool,
	sw: bool,
	w: bool,
	nw: bool
) -> int:
	var open_n: int = 0 if n else 1
	var open_e: int = 0 if e else 1
	var open_s: int = 0 if s else 1
	var open_w: int = 0 if w else 1
	var notch_ne: int = 1 if n and e and not ne else 0
	var notch_se: int = 1 if s and e and not se else 0
	var notch_sw: int = 1 if s and w and not sw else 0
	var notch_nw: int = 1 if n and w and not nw else 0
	return (open_n << 7) \
		| (open_e << 6) \
		| (open_s << 5) \
		| (open_w << 4) \
		| (notch_ne << 3) \
		| (notch_se << 2) \
		| (notch_sw << 1) \
		| notch_nw

static func build_atlas_index(signature_code: int, variant_index: int) -> int:
	_ensure_catalog()
	var safe_variant: int = maxi(0, variant_index)
	return safe_variant * CASE_COUNT + int(_base_index_by_signature_code.get(signature_code, 0))

static func pick_variant(
	tile_coord: Vector2i,
	seed: int,
	variant_count: int = DEFAULT_VARIANT_COUNT
) -> int:
	var safe_variant_count: int = maxi(1, variant_count)
	var hashed: int = _hash2d(tile_coord.x, tile_coord.y, seed + VARIANT_SEED_OFFSET)
	return posmod(hashed, safe_variant_count)

static func atlas_index_to_coords(atlas_index: int) -> Vector2i:
	var safe_index: int = maxi(0, atlas_index)
	return Vector2i(safe_index % ATLAS_COLUMNS, safe_index / ATLAS_COLUMNS)

static func build_full_atlas_source(texture: Texture2D, tile_size: int) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_size, tile_size)
	var columns: int = maxi(1, texture.get_width() / tile_size)
	var rows: int = maxi(1, texture.get_height() / tile_size)
	for row: int in range(rows):
		for column: int in range(columns):
			source.create_tile(Vector2i(column, row))
	return source

static func _ensure_catalog() -> void:
	if _catalog_ready:
		return
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	for mask: int in range(256):
		var code: int = build_signature_code(
			int(mask & 1) != 0,
			int(mask & 2) != 0,
			int(mask & 4) != 0,
			int(mask & 8) != 0,
			int(mask & 16) != 0,
			int(mask & 32) != 0,
			int(mask & 64) != 0,
			int(mask & 128) != 0
		)
		if seen.has(code):
			continue
		seen[code] = true
		entries.append({
			"code": code,
			"edge_count": _count_edge_bits(code),
			"notch_count": _count_notch_bits(code),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var edge_a: int = int(a.get("edge_count", 0))
		var edge_b: int = int(b.get("edge_count", 0))
		if edge_a != edge_b:
			return edge_a < edge_b
		var notch_a: int = int(a.get("notch_count", 0))
		var notch_b: int = int(b.get("notch_count", 0))
		if notch_a != notch_b:
			return notch_a < notch_b
		return int(a.get("code", 0)) < int(b.get("code", 0))
	)
	_base_index_by_signature_code.clear()
	for index: int in range(entries.size()):
		_base_index_by_signature_code[int((entries[index] as Dictionary).get("code", 0))] = index
	_catalog_ready = true

static func _count_edge_bits(signature_code: int) -> int:
	return _count_bits((signature_code >> 4) & 0x0F)

static func _count_notch_bits(signature_code: int) -> int:
	return _count_bits(signature_code & 0x0F)

static func _count_bits(value: int) -> int:
	var count: int = 0
	var bits: int = value
	while bits != 0:
		count += bits & 1
		bits >>= 1
	return count

static func _hash2d(x: int, y: int, seed: int) -> int:
	var value: int = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
	value = (value ^ (value >> 13)) & 0xFFFFFFFF
	value = (value * 1274126177) & 0xFFFFFFFF
	value = (value ^ (value >> 16)) & 0xFFFFFFFF
	return value
