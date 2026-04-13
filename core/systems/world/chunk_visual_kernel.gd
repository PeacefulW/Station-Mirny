class_name ChunkVisualKernel
extends RefCounted

const REDRAW_PHASE_TERRAIN: int = 0
const REDRAW_PHASE_COVER: int = 1
const REDRAW_PHASE_CLIFF: int = 2
const REDRAW_PHASE_FLORA: int = 3
const REDRAW_PHASE_DEBUG_INTERIOR: int = 4
const REDRAW_PHASE_DEBUG_COLLISION: int = 5
const REDRAW_PHASE_DONE: int = 6

const VISUAL_BATCH_MODE_PHASE: StringName = &"phase"
const VISUAL_BATCH_MODE_DIRTY: StringName = &"dirty"
const VISUAL_COMMAND_OP_SET: int = 0
const VISUAL_COMMAND_OP_ERASE: int = 1
const VISUAL_LAYER_TERRAIN: int = 0
const VISUAL_LAYER_GROUND_FACE: int = 1
const VISUAL_LAYER_ROCK: int = 2
const VISUAL_LAYER_COVER: int = 3
const VISUAL_LAYER_CLIFF: int = 4
const VISUAL_APPLY_BUFFER_STRIDE: int = 7
const VISUAL_COMMAND_BUFFER_STRIDE: int = 8

const PREBAKED_ROCK_VISUAL_NONE: int = 255
const PREBAKED_GROUND_FACE_NONE: int = -1
const PREBAKED_COVER_NONE: int = -1
const PREBAKED_CLIFF_NONE: int = 0
const PREBAKED_CLIFF_SOUTH: int = 1
const PREBAKED_CLIFF_WEST: int = 2
const PREBAKED_CLIFF_EAST: int = 3
const PREBAKED_CLIFF_TOP: int = 4
const PREBAKED_CLIFF_SURFACE_NORTH: int = 5
const PREBAKED_MASK_ALT_SHIFT: int = 8

const _INTERIOR_FAMILY_TARGET_COUNT: int = 3
const _INTERIOR_FAMILY_WINDOW_SIZE: int = 3
const _INTERIOR_FAMILY_SCALE: float = 18.0
const _INTERIOR_FAMILY_DETAIL_SCALE: float = 9.0
const _INTERIOR_FAMILY_SEED: int = 13183
const _INTERIOR_VARIATION_SEED: int = 12345
const _INTERIOR_REHASH_SEED: int = 12442
const _ECOTONE_BLEND_SEED: int = 18257
const _ECOTONE_BLEND_SCALE: float = 6.0
const _ECOTONE_BLEND_START: float = 0.18
const _HASH32_MASK: int = 0xffffffff

const _CARDINAL_DIRS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]

const _COVER_REVEAL_DIRS := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1),
]

static func visual_phase_name(phase: int) -> StringName:
	match phase:
		REDRAW_PHASE_TERRAIN:
			return &"terrain"
		REDRAW_PHASE_COVER:
			return &"cover"
		REDRAW_PHASE_CLIFF:
			return &"cliff"
		REDRAW_PHASE_FLORA:
			return &"flora"
		REDRAW_PHASE_DEBUG_INTERIOR:
			return &"debug_interior"
		REDRAW_PHASE_DEBUG_COLLISION:
			return &"debug_collision"
		_:
			return &"done"

static func make_visual_set_command(layer: int, local_tile: Vector2i, source_id: int, atlas: Vector2i, alt_id: int) -> Dictionary:
	return {
		"layer": layer,
		"tile": local_tile,
		"op": VISUAL_COMMAND_OP_SET,
		"source_id": source_id,
		"atlas": atlas,
		"alt_id": alt_id,
	}

static func make_visual_erase_command(layer: int, local_tile: Vector2i) -> Dictionary:
	return {
		"layer": layer,
		"tile": local_tile,
		"op": VISUAL_COMMAND_OP_ERASE,
	}

static func default_biome_palette_index() -> int:
	return BiomeRegistry.get_default_palette_index() if BiomeRegistry else 0

static func prebaked_wall_def_from_index(def_index: int) -> Vector2i:
	return Vector2i(def_index + 7, 0)

static func prebaked_linear_index_to_coords(linear_index: int) -> Vector2i:
	var columns: int = maxi(1, ChunkTilesetFactory.terrain_tiles_per_row)
	return Vector2i(linear_index % columns, linear_index / columns)

static func pack_prebaked_mask(atlas_index: int, alt_id: int) -> int:
	return (maxi(0, alt_id) << PREBAKED_MASK_ALT_SHIFT) | maxi(0, atlas_index)

static func unpack_prebaked_mask_atlas(mask_value: int) -> int:
	if mask_value < 0:
		return -1
	return mask_value & ((1 << PREBAKED_MASK_ALT_SHIFT) - 1)

static func unpack_prebaked_mask_alt(mask_value: int) -> int:
	if mask_value < 0:
		return 0
	return mask_value >> PREBAKED_MASK_ALT_SHIFT

static func prebaked_cliff_overlay_coords(kind: int) -> Vector2i:
	match kind:
		PREBAKED_CLIFF_SOUTH:
			return ChunkTilesetFactory.TILE_SHADOW_SOUTH
		PREBAKED_CLIFF_WEST:
			return ChunkTilesetFactory.TILE_SHADOW_WEST
		PREBAKED_CLIFF_EAST:
			return ChunkTilesetFactory.TILE_SHADOW_EAST
		PREBAKED_CLIFF_TOP:
			return ChunkTilesetFactory.TILE_TOP_EDGE
		PREBAKED_CLIFF_SURFACE_NORTH:
			return ChunkTilesetFactory.TILE_SHADOW_NORTH
		_:
			return Vector2i(-1, -1)

static func hash32_to_unit_float(h: int) -> float:
	return float(h & _HASH32_MASK) / float(_HASH32_MASK)

static func smoothstep01(t: float) -> float:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	return clamped_t * clamped_t * (3.0 - 2.0 * clamped_t)

static func tile_hash_xy(tile_x: int, tile_y: int) -> int:
	return hash32_xy(tile_x, tile_y, 0)

static func hash32_xy(tile_x: int, tile_y: int, seed: int) -> int:
	var h: int = (tile_x * 374761393 + tile_y * 668265263 + seed * 1442695041) & _HASH32_MASK
	h = (h ^ (h >> 13)) & _HASH32_MASK
	h = (h * 1274126177) & _HASH32_MASK
	h = (h ^ (h >> 16)) & _HASH32_MASK
	return h

static func interior_family_count(base_count: int) -> int:
	return maxi(1, mini(_INTERIOR_FAMILY_TARGET_COUNT, base_count))

static func interior_family_window(base_count: int, family_index: int) -> Vector2i:
	var family_count: int = interior_family_count(base_count)
	var clamped_family_index: int = clampi(family_index, 0, family_count - 1)
	var window_size: int = maxi(1, mini(base_count, _INTERIOR_FAMILY_WINDOW_SIZE))
	if base_count <= window_size or family_count <= 1:
		return Vector2i(0, base_count)
	var max_start: int = base_count - window_size
	var start: int = int(round(float(clamped_family_index * max_start) / float(family_count - 1)))
	return Vector2i(start, window_size)

static func shift_interior_family_base(base_index: int, family_window: Vector2i, step: int) -> int:
	if family_window.y <= 1:
		return family_window.x
	return family_window.x + ((base_index - family_window.x + step) % family_window.y)

static func interior_variant_matches(a: Vector2i, b: Vector2i) -> bool:
	return a.x == b.x and a.y == b.y

static func resolve_ecotone_secondary_weight(ecotone_factor: float) -> float:
	var normalized_factor: float = clampf(
		(ecotone_factor - _ECOTONE_BLEND_START) / maxf(0.001, 1.0 - _ECOTONE_BLEND_START),
		0.0,
		1.0
	)
	return 0.5 * smoothstep01(normalized_factor)

static func sample_ecotone_blend_noise(global_x: int, global_y: int, scale: float, seed: int) -> float:
	var resolved_scale: float = maxf(1.0, scale)
	var scaled_x: float = float(global_x) / resolved_scale
	var scaled_y: float = float(global_y) / resolved_scale
	var cell_x: int = floori(scaled_x)
	var cell_y: int = floori(scaled_y)
	var frac_x: float = smoothstep01(scaled_x - float(cell_x))
	var frac_y: float = smoothstep01(scaled_y - float(cell_y))
	var v00: float = hash32_to_unit_float(hash32_xy(cell_x, cell_y, seed))
	var v10: float = hash32_to_unit_float(hash32_xy(cell_x + 1, cell_y, seed))
	var v01: float = hash32_to_unit_float(hash32_xy(cell_x, cell_y + 1, seed))
	var v11: float = hash32_to_unit_float(hash32_xy(cell_x + 1, cell_y + 1, seed))
	return lerpf(lerpf(v00, v10, frac_x), lerpf(v01, v11, frac_x), frac_y)

static func resolve_effective_surface_palette_index(
	primary_biome_palette_index: int,
	secondary_biome_palette_index: int,
	ecotone_factor: float,
	global_x: int,
	global_y: int
) -> int:
	if secondary_biome_palette_index == primary_biome_palette_index:
		return primary_biome_palette_index
	var secondary_weight: float = resolve_ecotone_secondary_weight(ecotone_factor)
	if secondary_weight <= 0.0:
		return primary_biome_palette_index
	var blend_noise: float = sample_ecotone_blend_noise(global_x, global_y, _ECOTONE_BLEND_SCALE, _ECOTONE_BLEND_SEED)
	return secondary_biome_palette_index if blend_noise < secondary_weight else primary_biome_palette_index

static func sample_interior_family_noise(global_x: int, global_y: int, scale: float, seed: int) -> float:
	var scaled_x: float = float(global_x) / scale
	var scaled_y: float = float(global_y) / scale
	var cell_x: int = floori(scaled_x)
	var cell_y: int = floori(scaled_y)
	var frac_x: float = smoothstep01(scaled_x - float(cell_x))
	var frac_y: float = smoothstep01(scaled_y - float(cell_y))
	var v00: float = hash32_to_unit_float(hash32_xy(cell_x, cell_y, seed))
	var v10: float = hash32_to_unit_float(hash32_xy(cell_x + 1, cell_y, seed))
	var v01: float = hash32_to_unit_float(hash32_xy(cell_x, cell_y + 1, seed))
	var v11: float = hash32_to_unit_float(hash32_xy(cell_x + 1, cell_y + 1, seed))
	var nx0: float = lerpf(v00, v10, frac_x)
	var nx1: float = lerpf(v01, v11, frac_x)
	return lerpf(nx0, nx1, frac_y)

static func resolve_interior_family(global_x: int, global_y: int, base_count: int) -> int:
	var family_count: int = interior_family_count(base_count)
	if family_count <= 1:
		return 0
	var macro_noise: float = sample_interior_family_noise(global_x, global_y, _INTERIOR_FAMILY_SCALE, _INTERIOR_FAMILY_SEED)
	var detail_noise: float = sample_interior_family_noise(
		global_x,
		global_y,
		_INTERIOR_FAMILY_DETAIL_SCALE,
		_INTERIOR_FAMILY_SEED + 53
	)
	var blended_noise: float = clampf(macro_noise * 0.82 + detail_noise * 0.18, 0.0, 0.999999)
	return mini(family_count - 1, int(floor(blended_noise * family_count)))

static func raw_interior_variant(global_x: int, global_y: int, family_index: int, seed: int = _INTERIOR_VARIATION_SEED) -> Vector2i:
	var base_count: int = ChunkTilesetFactory.get_interior_base_variant_count()
	if base_count <= 0:
		return Vector2i.ZERO
	var family_window: Vector2i = interior_family_window(base_count, family_index)
	var h: int = hash32_xy(global_x, global_y, seed)
	return Vector2i(
		family_window.x + (h % family_window.y),
		(h >> 8) & (ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT - 1)
	)

static func resolve_interior_variant(global_x: int, global_y: int) -> Vector2i:
	var base_count: int = ChunkTilesetFactory.get_interior_base_variant_count()
	if base_count <= 0:
		return Vector2i.ZERO
	var resolved_family: int = resolve_interior_family(global_x, global_y, base_count)
	var family_window: Vector2i = interior_family_window(base_count, resolved_family)
	var resolved: Vector2i = raw_interior_variant(global_x, global_y, resolved_family)
	var left_variant: Vector2i = raw_interior_variant(
		global_x - 1,
		global_y,
		resolve_interior_family(global_x - 1, global_y, base_count)
	)
	var top_variant: Vector2i = raw_interior_variant(
		global_x,
		global_y - 1,
		resolve_interior_family(global_x, global_y - 1, base_count)
	)
	var left_conflict: bool = interior_variant_matches(resolved, left_variant)
	var top_conflict: bool = interior_variant_matches(resolved, top_variant)
	if left_conflict and top_conflict:
		resolved = raw_interior_variant(global_x, global_y, resolved_family, _INTERIOR_REHASH_SEED)
	if interior_variant_matches(resolved, left_variant):
		resolved.y = (resolved.y + 1) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	if interior_variant_matches(resolved, top_variant):
		if family_window.y > 1:
			resolved.x = shift_interior_family_base(resolved.x, family_window, 1)
		else:
			resolved.y = (resolved.y + 3) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	if interior_variant_matches(resolved, left_variant) or interior_variant_matches(resolved, top_variant):
		resolved = raw_interior_variant(global_x, global_y, resolved_family, _INTERIOR_REHASH_SEED + 97)
		if interior_variant_matches(resolved, left_variant):
			resolved.y = (resolved.y + 5) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
		if interior_variant_matches(resolved, top_variant):
			if family_window.y > 1:
				resolved.x = shift_interior_family_base(resolved.x, family_window, 2)
			else:
				resolved.y = (resolved.y + 2) % ChunkTilesetFactory.INTERIOR_TRANSFORM_COUNT
	return resolved

static func resolve_variant_atlas(base: Vector2i, global_x: int, global_y: int) -> Vector2i:
	if base == ChunkTilesetFactory.WALL_INTERIOR:
		var interior_variant: Vector2i = resolve_interior_variant(global_x, global_y)
		return ChunkTilesetFactory.get_wall_variant_coords(base, interior_variant.x)
	return ChunkTilesetFactory.get_wall_variant_coords(base, 0)

static func resolve_variant_alt_id(base: Vector2i, global_x: int, global_y: int, allow_flip: bool) -> int:
	if base == ChunkTilesetFactory.WALL_INTERIOR:
		return resolve_interior_variant(global_x, global_y).y
	if not allow_flip:
		return 0
	var def_index: int = base.x - 7
	if def_index < 0 or def_index >= ChunkTilesetFactory._WALL_FLIP_CLASS.size():
		return 0
	var flip_class: int = ChunkTilesetFactory._WALL_FLIP_CLASS[def_index]
	if flip_class <= 0:
		return 0
	var alt_count: int = ChunkTilesetFactory.wall_flip_alt_count[flip_class]
	if alt_count <= 0:
		return 0
	return tile_hash_xy(global_x + 17, global_y + 31) % alt_count

static func request_to_global_tile(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	var chunk_coord: Vector2i = request.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var chunk_size: int = int(request.get("chunk_size", 64))
	return Vector2i(chunk_coord.x * chunk_size + local_tile.x, chunk_coord.y * chunk_size + local_tile.y)

static func _request_local_tile_index(request: Dictionary, local_tile: Vector2i) -> int:
	var chunk_size: int = int(request.get("chunk_size", 64))
	if local_tile.x < 0 or local_tile.y < 0 or local_tile.x >= chunk_size or local_tile.y >= chunk_size:
		return -1
	return local_tile.y * chunk_size + local_tile.x

static func _request_sparse_terrain_lookup(request: Dictionary, local_tile: Vector2i, default_value: int) -> int:
	var terrain_lookup: Dictionary = request.get("terrain_lookup", {}) as Dictionary
	return int(terrain_lookup.get(local_tile, default_value))

static func request_terrain(request: Dictionary, local_tile: Vector2i) -> int:
	var terrain_bytes: PackedByteArray = request.get("terrain_bytes", PackedByteArray()) as PackedByteArray
	var tile_index: int = _request_local_tile_index(request, local_tile)
	if tile_index >= 0 and tile_index < terrain_bytes.size():
		return int(terrain_bytes[tile_index])
	var terrain_halo: PackedByteArray = request.get("terrain_halo", PackedByteArray()) as PackedByteArray
	if not terrain_halo.is_empty():
		var chunk_size: int = int(request.get("chunk_size", 64))
		var halo_stride: int = chunk_size + 2
		if terrain_halo.size() == halo_stride * halo_stride:
			var halo_x: int = local_tile.x + 1
			var halo_y: int = local_tile.y + 1
			if halo_x >= 0 and halo_y >= 0 and halo_x < halo_stride and halo_y < halo_stride:
				return int(terrain_halo[halo_y * halo_stride + halo_x])
	return _request_sparse_terrain_lookup(request, local_tile, TileGenData.TerrainType.ROCK)

static func request_height(request: Dictionary, local_tile: Vector2i) -> float:
	var height_bytes: PackedFloat32Array = request.get("height_bytes", PackedFloat32Array()) as PackedFloat32Array
	var tile_index: int = _request_local_tile_index(request, local_tile)
	if tile_index >= 0 and tile_index < height_bytes.size():
		return float(height_bytes[tile_index])
	var height_lookup: Dictionary = request.get("height_lookup", {}) as Dictionary
	return float(height_lookup.get(local_tile, 0.5))

static func request_variation(request: Dictionary, local_tile: Vector2i) -> int:
	var variation_bytes: PackedByteArray = request.get("variation_bytes", PackedByteArray()) as PackedByteArray
	var tile_index: int = _request_local_tile_index(request, local_tile)
	if tile_index >= 0 and tile_index < variation_bytes.size():
		return int(variation_bytes[tile_index])
	var variation_lookup: Dictionary = request.get("variation_lookup", {}) as Dictionary
	return int(variation_lookup.get(local_tile, ChunkTilesetFactory.SURFACE_VARIATION_NONE))

static func request_biome(request: Dictionary, local_tile: Vector2i) -> int:
	var biome_bytes: PackedByteArray = request.get("biome_bytes", PackedByteArray()) as PackedByteArray
	var secondary_biome_bytes: PackedByteArray = request.get("secondary_biome_bytes", PackedByteArray()) as PackedByteArray
	var ecotone_values: PackedFloat32Array = request.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array
	var tile_index: int = _request_local_tile_index(request, local_tile)
	var primary_biome_palette_index: int = default_biome_palette_index()
	if tile_index >= 0 and tile_index < biome_bytes.size():
		primary_biome_palette_index = int(biome_bytes[tile_index])
	else:
		var biome_lookup: Dictionary = request.get("biome_lookup", {}) as Dictionary
		primary_biome_palette_index = int(biome_lookup.get(local_tile, primary_biome_palette_index))
	var secondary_biome_palette_index: int = primary_biome_palette_index
	if tile_index >= 0 and tile_index < secondary_biome_bytes.size():
		secondary_biome_palette_index = int(secondary_biome_bytes[tile_index])
	else:
		var secondary_biome_lookup: Dictionary = request.get("secondary_biome_lookup", {}) as Dictionary
		secondary_biome_palette_index = int(secondary_biome_lookup.get(local_tile, primary_biome_palette_index))
	var ecotone_factor: float = 0.0
	if tile_index >= 0 and tile_index < ecotone_values.size():
		ecotone_factor = float(ecotone_values[tile_index])
	else:
		var ecotone_lookup: Dictionary = request.get("ecotone_lookup", {}) as Dictionary
		ecotone_factor = float(ecotone_lookup.get(local_tile, 0.0))
	var global_tile: Vector2i = request_to_global_tile(request, local_tile)
	return resolve_effective_surface_palette_index(
		primary_biome_palette_index,
		secondary_biome_palette_index,
		ecotone_factor,
		global_tile.x,
		global_tile.y
	)

static func is_open_for_visual(terrain_type: int) -> bool:
	return terrain_type != TileGenData.TerrainType.ROCK

static func is_open_exterior(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.WATER \
		or terrain_type == TileGenData.TerrainType.SAND \
		or terrain_type == TileGenData.TerrainType.GRASS

static func is_open_for_surface_rock_visual(terrain_type: int) -> bool:
	return is_open_exterior(terrain_type) \
		or terrain_type == TileGenData.TerrainType.MINED_FLOOR \
		or terrain_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE

static func is_open_for_surface_visual(terrain_type: int, water_only: bool) -> bool:
	if water_only:
		return terrain_type == TileGenData.TerrainType.WATER
	return is_open_for_surface_rock_visual(terrain_type)

static func is_surface_face_terrain(terrain_type: int) -> bool:
	return terrain_type == TileGenData.TerrainType.GROUND \
		or terrain_type == TileGenData.TerrainType.SAND \
		or terrain_type == TileGenData.TerrainType.GRASS

static func has_water_face_neighbor(request: Dictionary, local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		if request_terrain(request, local_tile + dir) == TileGenData.TerrainType.WATER:
			return true
	return false

static func request_ground_atlas_for_height(height_value: float) -> Vector2i:
	if height_value < 0.38:
		return ChunkTilesetFactory.TILE_GROUND_DARK
	if height_value > 0.62:
		return ChunkTilesetFactory.TILE_GROUND_LIGHT
	return ChunkTilesetFactory.TILE_GROUND

static func request_surface_ground_atlas(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	if bool(request.get("is_underground", false)):
		return request_ground_atlas_for_height(request_height(request, local_tile))
	var biome_palette_index: int = request_biome(request, local_tile)
	var variation_tile: Vector2i = ChunkTilesetFactory.get_surface_variation_tile(
		request_variation(request, local_tile),
		biome_palette_index
	)
	if variation_tile.x >= 0:
		return variation_tile
	return ChunkTilesetFactory.get_surface_ground_tile(biome_palette_index, request_height(request, local_tile))

static func _resolve_surface_face_class_from_open_sides(
	s: bool,
	n: bool,
	w: bool,
	e: bool,
	diagonal_reader: Callable
) -> Vector2i:
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		if not n:
			return ChunkTilesetFactory.WALL_PENINSULA_S
		if not s:
			return ChunkTilesetFactory.WALL_PENINSULA_N
		if not w:
			return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		if s and w:
			return ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			return ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			return ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			return ChunkTilesetFactory.WALL_CORNER_NE
		if e and w:
			return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	if count == 1:
		if s:
			var s_ne: bool = diagonal_reader.call(Vector2i(1, -1))
			var s_nw: bool = diagonal_reader.call(Vector2i(-1, -1))
			if s_ne and s_nw:
				return ChunkTilesetFactory.WALL_T_SOUTH
			if s_ne:
				return ChunkTilesetFactory.WALL_SOUTH_NE
			if s_nw:
				return ChunkTilesetFactory.WALL_SOUTH_NW
			return ChunkTilesetFactory.WALL_SOUTH
		if n:
			var n_se: bool = diagonal_reader.call(Vector2i(1, 1))
			var n_sw: bool = diagonal_reader.call(Vector2i(-1, 1))
			if n_se and n_sw:
				return ChunkTilesetFactory.WALL_T_NORTH
			if n_se:
				return ChunkTilesetFactory.WALL_NORTH_SE
			if n_sw:
				return ChunkTilesetFactory.WALL_NORTH_SW
			return ChunkTilesetFactory.WALL_NORTH
		if w:
			var w_ne: bool = diagonal_reader.call(Vector2i(1, -1))
			var w_se: bool = diagonal_reader.call(Vector2i(1, 1))
			if w_ne and w_se:
				return ChunkTilesetFactory.WALL_T_WEST
			if w_ne:
				return ChunkTilesetFactory.WALL_WEST_NE
			if w_se:
				return ChunkTilesetFactory.WALL_WEST_SE
			return ChunkTilesetFactory.WALL_WEST
		var e_nw: bool = diagonal_reader.call(Vector2i(-1, -1))
		var e_sw: bool = diagonal_reader.call(Vector2i(-1, 1))
		if e_nw and e_sw:
			return ChunkTilesetFactory.WALL_T_EAST
		if e_nw:
			return ChunkTilesetFactory.WALL_EAST_NW
		if e_sw:
			return ChunkTilesetFactory.WALL_EAST_SW
		return ChunkTilesetFactory.WALL_EAST
	var d_sw: bool = diagonal_reader.call(Vector2i(-1, 1))
	var d_se: bool = diagonal_reader.call(Vector2i(1, 1))
	var d_ne: bool = diagonal_reader.call(Vector2i(1, -1))
	var d_nw: bool = diagonal_reader.call(Vector2i(-1, -1))
	var d_count: int = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw)
	if d_count == 4:
		return ChunkTilesetFactory.WALL_CROSS
	if d_count == 3:
		if not d_sw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SW
		if not d_se:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SE
		if not d_nw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_NW
		return ChunkTilesetFactory.WALL_DIAG3_NO_NE
	if d_count == 2:
		if d_sw and d_se:
			return ChunkTilesetFactory.WALL_EDGE_EW
		if d_ne and d_nw:
			return ChunkTilesetFactory.WALL_DIAG_NE_NW
		if d_ne and d_se:
			return ChunkTilesetFactory.WALL_DIAG_NE_SE
		if d_nw and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NW_SW
		if d_ne and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NE_SW
		return ChunkTilesetFactory.WALL_DIAG_NW_SE
	if d_sw:
		return ChunkTilesetFactory.WALL_NOTCH_SW
	if d_se:
		return ChunkTilesetFactory.WALL_NOTCH_SE
	if d_ne:
		return ChunkTilesetFactory.WALL_NOTCH_NE
	if d_nw:
		return ChunkTilesetFactory.WALL_NOTCH_NW
	return ChunkTilesetFactory.WALL_INTERIOR

static func _resolve_wall_class_from_open_sides(
	s: bool,
	n: bool,
	w: bool,
	e: bool,
	diagonal_reader: Callable
) -> Vector2i:
	var count: int = int(s) + int(n) + int(w) + int(e)
	if count == 4:
		return ChunkTilesetFactory.WALL_PILLAR
	if count == 3:
		if not n:
			return ChunkTilesetFactory.WALL_PENINSULA_S
		if not s:
			return ChunkTilesetFactory.WALL_PENINSULA_N
		if not w:
			return ChunkTilesetFactory.WALL_PENINSULA_E
		return ChunkTilesetFactory.WALL_PENINSULA_W
	if count == 2:
		if s and w:
			if diagonal_reader.call(Vector2i(1, -1)):
				return ChunkTilesetFactory.WALL_CORNER_SW_T
			return ChunkTilesetFactory.WALL_CORNER_SW
		if s and e:
			if diagonal_reader.call(Vector2i(-1, -1)):
				return ChunkTilesetFactory.WALL_CORNER_SE_T
			return ChunkTilesetFactory.WALL_CORNER_SE
		if n and w:
			if diagonal_reader.call(Vector2i(1, 1)):
				return ChunkTilesetFactory.WALL_CORNER_NW_T
			return ChunkTilesetFactory.WALL_CORNER_NW
		if n and e:
			if diagonal_reader.call(Vector2i(-1, 1)):
				return ChunkTilesetFactory.WALL_CORNER_NE_T
			return ChunkTilesetFactory.WALL_CORNER_NE
		if e and w:
			return ChunkTilesetFactory.WALL_CORRIDOR_EW
		return ChunkTilesetFactory.WALL_CORRIDOR_NS
	if count == 1:
		if s:
			var s_ne: bool = diagonal_reader.call(Vector2i(1, -1))
			var s_nw: bool = diagonal_reader.call(Vector2i(-1, -1))
			if s_ne and s_nw:
				return ChunkTilesetFactory.WALL_T_SOUTH
			if s_ne:
				return ChunkTilesetFactory.WALL_SOUTH_NE
			if s_nw:
				return ChunkTilesetFactory.WALL_SOUTH_NW
			return ChunkTilesetFactory.WALL_SOUTH
		if n:
			var n_se: bool = diagonal_reader.call(Vector2i(1, 1))
			var n_sw: bool = diagonal_reader.call(Vector2i(-1, 1))
			if n_se and n_sw:
				return ChunkTilesetFactory.WALL_T_NORTH
			if n_se:
				return ChunkTilesetFactory.WALL_NORTH_SE
			if n_sw:
				return ChunkTilesetFactory.WALL_NORTH_SW
			return ChunkTilesetFactory.WALL_NORTH
		if w:
			var w_ne: bool = diagonal_reader.call(Vector2i(1, -1))
			var w_se: bool = diagonal_reader.call(Vector2i(1, 1))
			if w_ne and w_se:
				return ChunkTilesetFactory.WALL_T_WEST
			if w_ne:
				return ChunkTilesetFactory.WALL_WEST_NE
			if w_se:
				return ChunkTilesetFactory.WALL_WEST_SE
			return ChunkTilesetFactory.WALL_WEST
		var e_nw: bool = diagonal_reader.call(Vector2i(-1, -1))
		var e_sw: bool = diagonal_reader.call(Vector2i(-1, 1))
		if e_nw and e_sw:
			return ChunkTilesetFactory.WALL_T_EAST
		if e_nw:
			return ChunkTilesetFactory.WALL_EAST_NW
		if e_sw:
			return ChunkTilesetFactory.WALL_EAST_SW
		return ChunkTilesetFactory.WALL_EAST
	var d_sw: bool = diagonal_reader.call(Vector2i(-1, 1))
	var d_se: bool = diagonal_reader.call(Vector2i(1, 1))
	var d_ne: bool = diagonal_reader.call(Vector2i(1, -1))
	var d_nw: bool = diagonal_reader.call(Vector2i(-1, -1))
	var d_count: int = int(d_sw) + int(d_se) + int(d_ne) + int(d_nw)
	if d_count == 4:
		return ChunkTilesetFactory.WALL_CROSS
	if d_count == 3:
		if not d_sw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SW
		if not d_se:
			return ChunkTilesetFactory.WALL_DIAG3_NO_SE
		if not d_nw:
			return ChunkTilesetFactory.WALL_DIAG3_NO_NW
		return ChunkTilesetFactory.WALL_DIAG3_NO_NE
	if d_count == 2:
		if d_sw and d_se:
			return ChunkTilesetFactory.WALL_EDGE_EW
		if d_ne and d_nw:
			return ChunkTilesetFactory.WALL_DIAG_NE_NW
		if d_ne and d_se:
			return ChunkTilesetFactory.WALL_DIAG_NE_SE
		if d_nw and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NW_SW
		if d_ne and d_sw:
			return ChunkTilesetFactory.WALL_DIAG_NE_SW
		return ChunkTilesetFactory.WALL_DIAG_NW_SE
	if d_sw:
		return ChunkTilesetFactory.WALL_NOTCH_SW
	if d_se:
		return ChunkTilesetFactory.WALL_NOTCH_SE
	if d_ne:
		return ChunkTilesetFactory.WALL_NOTCH_NE
	if d_nw:
		return ChunkTilesetFactory.WALL_NOTCH_NW
	return ChunkTilesetFactory.WALL_INTERIOR

static func surface_visual_class(request: Dictionary, local_tile: Vector2i, water_only: bool) -> Vector2i:
	var s: bool = is_open_for_surface_visual(request_terrain(request, local_tile + Vector2i.DOWN), water_only)
	var n: bool = is_open_for_surface_visual(request_terrain(request, local_tile + Vector2i.UP), water_only)
	var w: bool = is_open_for_surface_visual(request_terrain(request, local_tile + Vector2i.LEFT), water_only)
	var e: bool = is_open_for_surface_visual(request_terrain(request, local_tile + Vector2i.RIGHT), water_only)
	return _resolve_surface_face_class_from_open_sides(
		s,
		n,
		w,
		e,
		func(offset: Vector2i) -> bool:
			return is_open_for_surface_visual(request_terrain(request, local_tile + offset), water_only)
	)

static func surface_rock_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return surface_visual_class(request, local_tile, false)

static func water_face_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	return surface_visual_class(request, local_tile, true)

static func rock_visual_class(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	var s: bool = is_open_for_visual(request_terrain(request, local_tile + Vector2i.DOWN))
	var n: bool = is_open_for_visual(request_terrain(request, local_tile + Vector2i.UP))
	var w: bool = is_open_for_visual(request_terrain(request, local_tile + Vector2i.LEFT))
	var e: bool = is_open_for_visual(request_terrain(request, local_tile + Vector2i.RIGHT))
	return _resolve_wall_class_from_open_sides(
		s,
		n,
		w,
		e,
		func(offset: Vector2i) -> bool:
			return is_open_for_visual(request_terrain(request, local_tile + offset))
	)

static func is_cave_edge_rock(request: Dictionary, local_tile: Vector2i) -> bool:
	if request_terrain(request, local_tile) != TileGenData.TerrainType.ROCK:
		return false
	var has_open_neighbor: bool = false
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		var neighbor_type: int = request_terrain(request, local_tile + dir)
		if is_open_exterior(neighbor_type):
			return false
		if neighbor_type == TileGenData.TerrainType.MINED_FLOOR or neighbor_type == TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			has_open_neighbor = true
	return has_open_neighbor

static func is_exterior_surface_rock(request: Dictionary, local_tile: Vector2i) -> bool:
	for dir: Vector2i in _COVER_REVEAL_DIRS:
		if is_open_exterior(request_terrain(request, local_tile + dir)):
			return true
	return false

static func cover_rock_atlas(request: Dictionary, local_tile: Vector2i) -> Vector2i:
	if is_exterior_surface_rock(request, local_tile):
		return ChunkTilesetFactory.WALL_SOUTH
	return ChunkTilesetFactory.WALL_INTERIOR

static func cliff_overlay_kind(request: Dictionary, local_tile: Vector2i) -> int:
	var terrain_type: int = request_terrain(request, local_tile)
	if terrain_type == TileGenData.TerrainType.ROCK:
		if is_open_exterior(request_terrain(request, local_tile + _CARDINAL_DIRS[3])):
			return PREBAKED_CLIFF_SOUTH
		if is_open_exterior(request_terrain(request, local_tile + _CARDINAL_DIRS[0])):
			return PREBAKED_CLIFF_WEST
		if is_open_exterior(request_terrain(request, local_tile + _CARDINAL_DIRS[1])):
			return PREBAKED_CLIFF_EAST
		if is_open_exterior(request_terrain(request, local_tile + _CARDINAL_DIRS[2])):
			return PREBAKED_CLIFF_TOP
		return PREBAKED_CLIFF_NONE
	if not is_surface_face_terrain(terrain_type):
		return PREBAKED_CLIFF_NONE
	if request_terrain(request, local_tile + Vector2i.UP) == TileGenData.TerrainType.ROCK:
		return PREBAKED_CLIFF_SURFACE_NORTH
	if request_terrain(request, local_tile + Vector2i.LEFT) == TileGenData.TerrainType.ROCK:
		return PREBAKED_CLIFF_WEST
	if request_terrain(request, local_tile + Vector2i.RIGHT) == TileGenData.TerrainType.ROCK:
		return PREBAKED_CLIFF_EAST
	if request_terrain(request, local_tile + Vector2i.DOWN) == TileGenData.TerrainType.ROCK:
		return PREBAKED_CLIFF_SOUTH
	return PREBAKED_CLIFF_NONE

static func append_ground_face_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	terrain_type: int,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	if bool(request.get("is_underground", false)):
		if explicit_clear:
			commands.append(make_visual_erase_command(VISUAL_LAYER_GROUND_FACE, local_tile))
		return
	var atlas: Vector2i = Vector2i(-1, -1)
	var alt_id: int = 0
	if is_surface_face_terrain(terrain_type):
		var wall_def: Vector2i = ChunkTilesetFactory.WALL_INTERIOR
		var interior_variant: Vector2i = Vector2i.ZERO
		var global_tile: Vector2i = request_to_global_tile(request, local_tile)
		if has_water_face_neighbor(request, local_tile):
			wall_def = water_face_visual_class(request, local_tile)
		else:
			interior_variant = resolve_interior_variant(global_tile.x, global_tile.y)
			alt_id = interior_variant.y
		var biome_palette_index: int = request_biome(request, local_tile)
		match terrain_type:
			TileGenData.TerrainType.GROUND, TileGenData.TerrainType.GRASS:
				atlas = ChunkTilesetFactory.get_ground_face_coords(wall_def, biome_palette_index, interior_variant.x)
			TileGenData.TerrainType.SAND:
				atlas = ChunkTilesetFactory.get_sand_face_coords(wall_def, biome_palette_index, interior_variant.x)
	if atlas.x >= 0:
		commands.append(make_visual_set_command(
			VISUAL_LAYER_GROUND_FACE,
			local_tile,
			ChunkTilesetFactory.TERRAIN_SOURCE_ID,
			atlas,
			alt_id
		))
	elif explicit_clear:
		commands.append(make_visual_erase_command(VISUAL_LAYER_GROUND_FACE, local_tile))

static func append_terrain_visual_commands(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	var terrain_type: int = request_terrain(request, local_tile)
	var atlas: Vector2i = ChunkTilesetFactory.TILE_GROUND
	var rock_atlas: Vector2i = Vector2i(-1, -1)
	var rock_alt_id: int = 0
	var biome_palette_index: int = request_biome(request, local_tile)
	var variation_id: int = ChunkTilesetFactory.SURFACE_VARIATION_NONE
	var variation_tile: Vector2i = Vector2i(-1, -1)
	var is_underground: bool = bool(request.get("is_underground", false))
	if not is_underground:
		variation_id = request_variation(request, local_tile)
		variation_tile = ChunkTilesetFactory.get_surface_variation_tile(variation_id, biome_palette_index)
	match terrain_type:
		TileGenData.TerrainType.ROCK:
			atlas = request_surface_ground_atlas(request, local_tile)
			var rock_visual: Vector2i = rock_visual_class(request, local_tile)
			if not is_underground:
				rock_visual = surface_rock_visual_class(request, local_tile)
			var global_tile: Vector2i = request_to_global_tile(request, local_tile)
			rock_atlas = resolve_variant_atlas(rock_visual, global_tile.x, global_tile.y)
			rock_alt_id = resolve_variant_alt_id(rock_visual, global_tile.x, global_tile.y, is_underground)
		TileGenData.TerrainType.WATER:
			if variation_id == ChunkTilesetFactory.SURFACE_VARIATION_ICE and variation_tile.x >= 0:
				atlas = variation_tile
			else:
				atlas = ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.SAND:
			atlas = variation_tile if variation_tile.x >= 0 else ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.GRASS:
			atlas = variation_tile if variation_tile.x >= 0 else ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
		TileGenData.TerrainType.MINED_FLOOR:
			atlas = ChunkTilesetFactory.TILE_MINED_FLOOR
		TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
			atlas = ChunkTilesetFactory.TILE_MOUNTAIN_ENTRANCE
		_:
			atlas = variation_tile if variation_tile.x >= 0 else request_surface_ground_atlas(request, local_tile)
	commands.append(make_visual_set_command(
		VISUAL_LAYER_TERRAIN,
		local_tile,
		ChunkTilesetFactory.TERRAIN_SOURCE_ID,
		atlas,
		0
	))
	append_ground_face_visual_command(request, local_tile, terrain_type, commands, explicit_clear)
	if rock_atlas.x >= 0:
		commands.append(make_visual_set_command(
			VISUAL_LAYER_ROCK,
			local_tile,
			ChunkTilesetFactory.TERRAIN_SOURCE_ID,
			rock_atlas,
			rock_alt_id
		))
	elif explicit_clear:
		commands.append(make_visual_erase_command(VISUAL_LAYER_ROCK, local_tile))

static func append_cover_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	if bool(request.get("is_underground", false)):
		if explicit_clear:
			commands.append(make_visual_erase_command(VISUAL_LAYER_COVER, local_tile))
		return
	var terrain_type: int = request_terrain(request, local_tile)
	var need_cover: bool = terrain_type == TileGenData.TerrainType.MINED_FLOOR or is_cave_edge_rock(request, local_tile)
	if not need_cover:
		if explicit_clear:
			commands.append(make_visual_erase_command(VISUAL_LAYER_COVER, local_tile))
		return
	var base: Vector2i = cover_rock_atlas(request, local_tile)
	var global_tile: Vector2i = request_to_global_tile(request, local_tile)
	var atlas: Vector2i = resolve_variant_atlas(base, global_tile.x, global_tile.y)
	var alt_id: int = resolve_variant_alt_id(base, global_tile.x, global_tile.y, false)
	commands.append(make_visual_set_command(
		VISUAL_LAYER_COVER,
		local_tile,
		ChunkTilesetFactory.TERRAIN_SOURCE_ID,
		atlas,
		alt_id
	))

static func append_cliff_visual_command(
	request: Dictionary,
	local_tile: Vector2i,
	commands: Array[Dictionary],
	explicit_clear: bool
) -> void:
	if bool(request.get("is_underground", false)):
		if explicit_clear:
			commands.append(make_visual_erase_command(VISUAL_LAYER_CLIFF, local_tile))
		return
	var overlay: Vector2i = prebaked_cliff_overlay_coords(cliff_overlay_kind(request, local_tile))
	if overlay.x >= 0:
		commands.append(make_visual_set_command(
			VISUAL_LAYER_CLIFF,
			local_tile,
			ChunkTilesetFactory.OVERLAY_SOURCE_ID,
			overlay,
			0
		))
	elif explicit_clear:
		commands.append(make_visual_erase_command(VISUAL_LAYER_CLIFF, local_tile))

static func compute_tile_phase_commands(
	request: Dictionary,
	local_tile: Vector2i,
	phase: int,
	explicit_clear: bool = true
) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	match phase:
		REDRAW_PHASE_TERRAIN:
			append_terrain_visual_commands(request, local_tile, commands, explicit_clear)
		REDRAW_PHASE_COVER:
			append_cover_visual_command(request, local_tile, commands, explicit_clear)
		REDRAW_PHASE_CLIFF:
			append_cliff_visual_command(request, local_tile, commands, explicit_clear)
	return commands

static func compute_visual_batch_fallback(request: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"mode": request.get("mode", &""),
		"phase": int(request.get("phase", REDRAW_PHASE_DONE)),
		"phase_name": request.get("phase_name", &"done"),
		"start_index": int(request.get("start_index", -1)),
		"end_index": int(request.get("end_index", -1)),
		"tiles": request.get("tiles", []),
		"tile_count": int((request.get("tiles", []) as Array).size()),
		"commands": [],
	}
	var commands: Array[Dictionary] = []
	var mode: StringName = StringName(request.get("mode", &""))
	var explicit_clear: bool = mode != VISUAL_BATCH_MODE_DIRTY
	for tile_variant: Variant in request.get("tiles", []):
		var local_tile: Vector2i = tile_variant as Vector2i
		if mode == VISUAL_BATCH_MODE_PHASE:
			match int(request.get("phase", REDRAW_PHASE_DONE)):
				REDRAW_PHASE_TERRAIN:
					append_terrain_visual_commands(request, local_tile, commands, false)
				REDRAW_PHASE_COVER:
					append_cover_visual_command(request, local_tile, commands, false)
				REDRAW_PHASE_CLIFF:
					append_cliff_visual_command(request, local_tile, commands, false)
		else:
			append_terrain_visual_commands(request, local_tile, commands, explicit_clear)
			append_cover_visual_command(request, local_tile, commands, explicit_clear)
			append_cliff_visual_command(request, local_tile, commands, explicit_clear)
	result["commands"] = commands
	result["command_count"] = commands.size()
	return result

static func build_prebaked_visual_payload(request: Dictionary) -> Dictionary:
	var terrain_bytes: PackedByteArray = request.get("terrain_bytes", PackedByteArray()) as PackedByteArray
	var height_bytes: PackedFloat32Array = request.get("height_bytes", PackedFloat32Array()) as PackedFloat32Array
	var variation_bytes: PackedByteArray = request.get("variation_bytes", PackedByteArray()) as PackedByteArray
	var biome_bytes: PackedByteArray = request.get("biome_bytes", PackedByteArray()) as PackedByteArray
	var secondary_biome_bytes: PackedByteArray = request.get("secondary_biome_bytes", PackedByteArray()) as PackedByteArray
	var ecotone_values: PackedFloat32Array = request.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array
	var terrain_halo: PackedByteArray = request.get("terrain_halo", PackedByteArray()) as PackedByteArray
	var chunk_coord: Vector2i = request.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var chunk_size: int = int(request.get("chunk_size", 0))
	if chunk_size <= 0:
		return {}
	var tile_count: int = chunk_size * chunk_size
	if terrain_bytes.size() != tile_count \
		or height_bytes.size() != tile_count \
		or variation_bytes.size() != tile_count \
		or biome_bytes.size() != tile_count \
		or terrain_halo.size() != (chunk_size + 2) * (chunk_size + 2):
		return {}
	var visual_request: Dictionary = {
		"chunk_coord": chunk_coord,
		"chunk_size": chunk_size,
		"is_underground": bool(request.get("is_underground", false)),
		"terrain_bytes": terrain_bytes,
		"height_bytes": height_bytes,
		"variation_bytes": variation_bytes,
		"biome_bytes": biome_bytes,
		"secondary_biome_bytes": secondary_biome_bytes,
		"ecotone_values": ecotone_values,
		"terrain_halo": terrain_halo,
	}
	var rock_visual_class := PackedByteArray()
	var ground_face_atlas := PackedInt32Array()
	var cover_mask := PackedInt32Array()
	var cliff_overlay := PackedByteArray()
	var variant_id := PackedByteArray()
	var alt_id := PackedInt32Array()
	rock_visual_class.resize(tile_count)
	ground_face_atlas.resize(tile_count)
	cover_mask.resize(tile_count)
	cliff_overlay.resize(tile_count)
	variant_id.resize(tile_count)
	alt_id.resize(tile_count)
	for idx: int in range(tile_count):
		rock_visual_class[idx] = PREBAKED_ROCK_VISUAL_NONE
		ground_face_atlas[idx] = PREBAKED_GROUND_FACE_NONE
		cover_mask[idx] = PREBAKED_COVER_NONE
		cliff_overlay[idx] = PREBAKED_CLIFF_NONE
		variant_id[idx] = 0
		alt_id[idx] = 0
	for local_y: int in range(chunk_size):
		for local_x: int in range(chunk_size):
			var idx: int = local_y * chunk_size + local_x
			var local_tile := Vector2i(local_x, local_y)
			var terrain_type: int = terrain_bytes[idx]
			var global_tile: Vector2i = request_to_global_tile(visual_request, local_tile)
			var shared_base: Vector2i = Vector2i(-1, -1)
			var shared_variant: Vector2i = Vector2i.ZERO
			var shared_has_interior: bool = false
			if is_surface_face_terrain(terrain_type):
				var face_wall: Vector2i = ChunkTilesetFactory.WALL_INTERIOR
				var interior_variant: Vector2i = Vector2i.ZERO
				if has_water_face_neighbor(visual_request, local_tile):
					face_wall = water_face_visual_class(visual_request, local_tile)
				else:
					interior_variant = resolve_interior_variant(global_tile.x, global_tile.y)
				var face_atlas: Vector2i = Vector2i(-1, -1)
				var biome_palette_index: int = request_biome(visual_request, local_tile)
				match terrain_type:
					TileGenData.TerrainType.GROUND, TileGenData.TerrainType.GRASS:
						face_atlas = ChunkTilesetFactory.get_ground_face_coords(face_wall, biome_palette_index, interior_variant.x)
					TileGenData.TerrainType.SAND:
						face_atlas = ChunkTilesetFactory.get_sand_face_coords(face_wall, biome_palette_index, interior_variant.x)
				if face_atlas.x >= 0:
					ground_face_atlas[idx] = face_atlas.y * maxi(1, ChunkTilesetFactory.terrain_tiles_per_row) + face_atlas.x
				shared_base = face_wall
				shared_variant = interior_variant
				shared_has_interior = face_wall == ChunkTilesetFactory.WALL_INTERIOR
			if terrain_type == TileGenData.TerrainType.ROCK:
				var rock_visual: Vector2i = surface_rock_visual_class(visual_request, local_tile)
				rock_visual_class[idx] = maxi(0, rock_visual.x - 7)
				shared_base = rock_visual
				shared_has_interior = rock_visual == ChunkTilesetFactory.WALL_INTERIOR
				if shared_has_interior:
					shared_variant = resolve_interior_variant(global_tile.x, global_tile.y)
			if terrain_type == TileGenData.TerrainType.MINED_FLOOR or is_cave_edge_rock(visual_request, local_tile):
				var cover_base: Vector2i = cover_rock_atlas(visual_request, local_tile)
				var cover_variant: Vector2i = Vector2i.ZERO
				var cover_alt: int = 0
				if cover_base == ChunkTilesetFactory.WALL_INTERIOR:
					cover_variant = resolve_interior_variant(global_tile.x, global_tile.y)
					cover_alt = cover_variant.y
					if shared_base.x < 0:
						shared_base = cover_base
						shared_variant = cover_variant
						shared_has_interior = true
				var cover_atlas: Vector2i = ChunkTilesetFactory.get_wall_variant_coords(
					cover_base,
					cover_variant.x if cover_base == ChunkTilesetFactory.WALL_INTERIOR else 0
				)
				cover_mask[idx] = pack_prebaked_mask(
					cover_atlas.y * maxi(1, ChunkTilesetFactory.terrain_tiles_per_row) + cover_atlas.x,
					cover_alt
				)
			cliff_overlay[idx] = cliff_overlay_kind(visual_request, local_tile)
			if shared_base.x >= 0:
				if shared_has_interior:
					variant_id[idx] = shared_variant.x
					alt_id[idx] = shared_variant.y
				else:
					alt_id[idx] = resolve_variant_alt_id(shared_base, global_tile.x, global_tile.y, false)
	return {
		"rock_visual_class": rock_visual_class,
		"ground_face_atlas": ground_face_atlas,
		"cover_mask": cover_mask,
		"cliff_overlay": cliff_overlay,
		"variant_id": variant_id,
		"alt_id": alt_id,
	}

static func compute_prebaked_visual_batch(request: Dictionary) -> Dictionary:
	var tiles: Array = request.get("tiles", [])
	var chunk_size: int = int(request.get("chunk_size", 0))
	var terrain_bytes: PackedByteArray = request.get("terrain_bytes", PackedByteArray()) as PackedByteArray
	var height_bytes: PackedFloat32Array = request.get("height_bytes", PackedFloat32Array()) as PackedFloat32Array
	var variation_bytes: PackedByteArray = request.get("variation_bytes", PackedByteArray()) as PackedByteArray
	var biome_bytes: PackedByteArray = request.get("biome_bytes", PackedByteArray()) as PackedByteArray
	var secondary_biome_bytes: PackedByteArray = request.get("secondary_biome_bytes", PackedByteArray()) as PackedByteArray
	var ecotone_values: PackedFloat32Array = request.get("ecotone_values", PackedFloat32Array()) as PackedFloat32Array
	var rock_visual_class: PackedByteArray = request.get("rock_visual_class", PackedByteArray()) as PackedByteArray
	var ground_face_atlas: PackedInt32Array = request.get("ground_face_atlas", PackedInt32Array()) as PackedInt32Array
	var cover_mask: PackedInt32Array = request.get("cover_mask", PackedInt32Array()) as PackedInt32Array
	var cliff_overlay: PackedByteArray = request.get("cliff_overlay", PackedByteArray()) as PackedByteArray
	var variant_id: PackedByteArray = request.get("variant_id", PackedByteArray()) as PackedByteArray
	var alt_id: PackedInt32Array = request.get("alt_id", PackedInt32Array()) as PackedInt32Array
	var result: Dictionary = {
		"mode": request.get("mode", &""),
		"phase": int(request.get("phase", REDRAW_PHASE_DONE)),
		"phase_name": request.get("phase_name", &"done"),
		"start_index": int(request.get("start_index", -1)),
		"end_index": int(request.get("end_index", -1)),
		"tiles": tiles,
		"tile_count": tiles.size(),
		"commands": [],
	}
	if chunk_size <= 0:
		return result
	var commands: Array[Dictionary] = []
	var phase: int = int(request.get("phase", REDRAW_PHASE_DONE))
	var is_underground: bool = bool(request.get("is_underground", false))
	var has_secondary_biome: bool = secondary_biome_bytes.size() == terrain_bytes.size()
	var has_ecotone_values: bool = ecotone_values.size() == terrain_bytes.size()
	for tile_variant: Variant in tiles:
		var local_tile: Vector2i = tile_variant as Vector2i
		var idx: int = local_tile.y * chunk_size + local_tile.x
		if idx < 0 or idx >= terrain_bytes.size():
			continue
		var terrain_type: int = terrain_bytes[idx]
		var chunk_coord: Vector2i = request.get("chunk_coord", Vector2i.ZERO) as Vector2i
		var global_tile: Vector2i = Vector2i(chunk_coord.x * chunk_size + local_tile.x, chunk_coord.y * chunk_size + local_tile.y)
		var primary_biome_palette_index: int = int(biome_bytes[idx]) if idx < biome_bytes.size() else default_biome_palette_index()
		var secondary_biome_palette_index: int = int(secondary_biome_bytes[idx]) if has_secondary_biome else primary_biome_palette_index
		var ecotone_factor: float = float(ecotone_values[idx]) if has_ecotone_values else 0.0
		var biome_palette_index: int = resolve_effective_surface_palette_index(
			primary_biome_palette_index,
			secondary_biome_palette_index,
			ecotone_factor,
			global_tile.x,
			global_tile.y
		)
		match phase:
			REDRAW_PHASE_TERRAIN:
				var atlas: Vector2i = ChunkTilesetFactory.TILE_GROUND
				var variation_id: int = int(variation_bytes[idx]) if idx < variation_bytes.size() else ChunkTilesetFactory.SURFACE_VARIATION_NONE
				var variation_tile: Vector2i = Vector2i(-1, -1)
				if not is_underground:
					variation_tile = ChunkTilesetFactory.get_surface_variation_tile(variation_id, biome_palette_index)
				match terrain_type:
					TileGenData.TerrainType.ROCK:
						if variation_tile.x >= 0 and not is_underground:
							atlas = variation_tile
						else:
							atlas = ChunkTilesetFactory.get_surface_ground_tile(
								biome_palette_index,
								float(height_bytes[idx]) if idx < height_bytes.size() else 0.5
							)
					TileGenData.TerrainType.WATER:
						atlas = variation_tile if variation_id == ChunkTilesetFactory.SURFACE_VARIATION_ICE and variation_tile.x >= 0 else ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
					TileGenData.TerrainType.SAND, TileGenData.TerrainType.GRASS:
						atlas = variation_tile if variation_tile.x >= 0 else ChunkTilesetFactory.get_surface_terrain_tile(terrain_type, biome_palette_index)
					TileGenData.TerrainType.MINED_FLOOR:
						atlas = ChunkTilesetFactory.TILE_MINED_FLOOR
					TileGenData.TerrainType.MOUNTAIN_ENTRANCE:
						atlas = ChunkTilesetFactory.TILE_MOUNTAIN_ENTRANCE
					_:
						atlas = variation_tile if variation_tile.x >= 0 else ChunkTilesetFactory.get_surface_ground_tile(
							biome_palette_index,
							float(height_bytes[idx]) if idx < height_bytes.size() else 0.5
						)
				commands.append(make_visual_set_command(VISUAL_LAYER_TERRAIN, local_tile, ChunkTilesetFactory.TERRAIN_SOURCE_ID, atlas, 0))
				var face_index: int = int(ground_face_atlas[idx]) if idx < ground_face_atlas.size() else PREBAKED_GROUND_FACE_NONE
				if face_index >= 0:
					commands.append(make_visual_set_command(
						VISUAL_LAYER_GROUND_FACE,
						local_tile,
						ChunkTilesetFactory.TERRAIN_SOURCE_ID,
						prebaked_linear_index_to_coords(face_index),
						int(alt_id[idx]) if idx < alt_id.size() else 0
					))
				var rock_def: int = int(rock_visual_class[idx]) if idx < rock_visual_class.size() else PREBAKED_ROCK_VISUAL_NONE
				if rock_def != PREBAKED_ROCK_VISUAL_NONE:
					var rock_base: Vector2i = prebaked_wall_def_from_index(rock_def)
					commands.append(make_visual_set_command(
						VISUAL_LAYER_ROCK,
						local_tile,
						ChunkTilesetFactory.TERRAIN_SOURCE_ID,
						ChunkTilesetFactory.get_wall_variant_coords(rock_base, int(variant_id[idx]) if idx < variant_id.size() else 0),
						int(alt_id[idx]) if idx < alt_id.size() else 0
					))
			REDRAW_PHASE_COVER:
				var cover_value: int = int(cover_mask[idx]) if idx < cover_mask.size() else PREBAKED_COVER_NONE
				if cover_value >= 0:
					commands.append(make_visual_set_command(
						VISUAL_LAYER_COVER,
						local_tile,
						ChunkTilesetFactory.TERRAIN_SOURCE_ID,
						prebaked_linear_index_to_coords(unpack_prebaked_mask_atlas(cover_value)),
						unpack_prebaked_mask_alt(cover_value)
					))
			REDRAW_PHASE_CLIFF:
				var cliff_kind: int = int(cliff_overlay[idx]) if idx < cliff_overlay.size() else PREBAKED_CLIFF_NONE
				var overlay_coords: Vector2i = prebaked_cliff_overlay_coords(cliff_kind)
				if overlay_coords.x >= 0:
					commands.append(make_visual_set_command(
						VISUAL_LAYER_CLIFF,
						local_tile,
						ChunkTilesetFactory.OVERLAY_SOURCE_ID,
						overlay_coords,
						0
					))
	result["commands"] = commands
	result["command_count"] = commands.size()
	return result
