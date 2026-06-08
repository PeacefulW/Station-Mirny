class_name WorldSpikyFloraScatterLayer
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldDecorBatchLayer = preload("res://core/systems/world/world_decor_batch_layer.gd")

const FRAME_COLUMNS: int = 4
const FRAME_ROWS: int = 1
const FRAME_COUNT: int = 4
const FRONT_TOP_FRAME_INDEX: int = 0
const CANDIDATE_COUNT_PER_CHUNK: int = 48
const MAX_PLANTS_PER_CHUNK: int = 2
const EDGE_PADDING_PX: float = 36.0
const MIN_SIZE_PX: float = 58.0
const MAX_SIZE_PX: float = 220.0
const SIZE_VARIATION_EXPONENT: float = 1.65
const MIN_PLANT_DISTANCE_PX: float = 158.0
const BIOFIELD_PATCH_CELL_PX: float = 2750.0
const BIOFIELD_PATCH_DENSITY: float = 0.72
const BIOFIELD_EDGE_CLEARANCE_PX: float = 30.0
const MASK_PREFLIGHT_STRIDE: int = 8
const MASK_PREFLIGHT_MIN_VALUE: int = 64
const TERRAIN_THRESHOLD_LOW: float = 0.40
const TERRAIN_THRESHOLD_HIGH: float = 0.58
const BIOFIELD_PLACEMENT_THRESHOLD: float = 0.36
const BIOFIELD_MIN_DENSITY: float = 0.01
const BIOFIELD_MAX_DENSITY: float = 0.06

var _atlas: Texture2D = null
var _terrain_ids: PackedInt32Array = PackedInt32Array()
var _lake_flags: PackedByteArray = PackedByteArray()
var _chunk_coord: Vector2i = Vector2i.ZERO
var _chunk_origin_world_px: Vector2 = Vector2.ZERO
var _world_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var _world_version: int = WorldRuntimeConstants.WORLD_VERSION
var _mask_bytes: PackedByteArray = PackedByteArray()
var _mask_width: int = 0
var _mask_height: int = 0
var _mask_origin_world_px: Vector2 = Vector2.ZERO
var _mask_step_px: float = 0.0
var _batch_layer: WorldDecorBatchLayer = null
var _plant_count: int = 0

# Temporary visual adapter only. Final dense flora placement belongs in the
# native packet-backed object placement path when the placement seam graduates.
func set_atlas(atlas: Texture2D) -> void:
	_atlas = atlas
	if _atlas == null:
		_clear_batch()

func configure_chunk(
	chunk_coord: Vector2i,
	world_seed: int,
	world_version: int,
	terrain_ids: PackedInt32Array,
	lake_flags: PackedByteArray,
	mask_bytes: PackedByteArray,
	mask_width: int,
	mask_height: int,
	mask_origin_world_px: Vector2,
	mask_step_px: float
) -> void:
	_chunk_coord = chunk_coord
	_chunk_origin_world_px = WorldRuntimeConstants.chunk_origin_px(chunk_coord)
	_world_seed = world_seed
	_world_version = world_version
	_terrain_ids = terrain_ids.duplicate()
	_lake_flags = lake_flags.duplicate()
	if _lake_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_mask_bytes = mask_bytes.duplicate()
	_mask_width = mask_width
	_mask_height = mask_height
	_mask_origin_world_px = mask_origin_world_px
	_mask_step_px = mask_step_px
	_rebuild_batch()

func get_plant_count() -> int:
	return _plant_count

func _rebuild_batch() -> void:
	_plant_count = 0
	visible = false
	if _atlas == null \
			or _terrain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or _mask_width <= 0 \
			or _mask_height <= 0 \
			or _mask_step_px <= 0.0 \
			or _mask_bytes.size() != _mask_width * _mask_height:
		_clear_batch()
		return
	if not _has_plain_ground_cells() or not _has_terrain_mask_coverage():
		_clear_batch()
		return

	var sprite_buffer := PackedFloat32Array()
	var shadow_buffer := PackedFloat32Array()
	var chunk_size_px: float = float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
	var placed_positions: Array[Vector2] = []
	for candidate_index: int in range(CANDIDATE_COUNT_PER_CHUNK):
		if _plant_count >= MAX_PLANTS_PER_CHUNK:
			break
		var candidate_hash: int = _hash4(
			_chunk_coord.x,
			_chunk_coord.y,
			candidate_index,
			_world_seed ^ (_world_version * 67)
		)
		var density_roll: float = _unit_float(_hash4(candidate_hash, 181, 191, 193))
		if density_roll > BIOFIELD_MAX_DENSITY:
			continue
		var position: Vector2 = _candidate_position(chunk_size_px, candidate_hash)
		var biofield_score: float = _placement_biofield_score(position)
		if biofield_score < BIOFIELD_PLACEMENT_THRESHOLD:
			continue
		var chance: float = _placement_chance(biofield_score)
		if density_roll > chance:
			continue
		if _is_too_close_to_existing(position, placed_positions):
			continue
		_append_spiky_flora(position, candidate_hash, biofield_score, sprite_buffer)
		placed_positions.append(position)

	if _plant_count <= 0:
		_clear_batch()
		return

	var batch_layer: WorldDecorBatchLayer = _ensure_batch_layer()
	batch_layer.set_chunk_size_px(chunk_size_px)
	batch_layer.set_atlas_layout(FRAME_COLUMNS, FRAME_ROWS, FRAME_COUNT)
	batch_layer.set_animation(1, 0.0)
	batch_layer.set_batches([_atlas], [sprite_buffer], shadow_buffer)
	visible = true

func _append_spiky_flora(
	position: Vector2,
	salt: int,
	biofield_score: float,
	sprite_buffer: PackedFloat32Array
) -> void:
	var frame_index: int = FRONT_TOP_FRAME_INDEX
	var size_roll: float = pow(_unit_float(_hash4(salt, 107, 109, 113)), SIZE_VARIATION_EXPONENT)
	var size_px: float = lerpf(MIN_SIZE_PX, MAX_SIZE_PX, size_roll)
	size_px *= lerpf(0.94, 1.10, clampf(biofield_score, 0.0, 1.0))
	var tint_factor: float = lerpf(0.92, 1.08, _unit_float(_hash4(salt, 127, 131, 137)))
	var phase: float = _unit_float(_hash4(salt, 139, 149, 151))
	WorldDecorBatchLayer.append_instance(
		sprite_buffer,
		position,
		Vector2.ONE * size_px,
		frame_index,
		Color(tint_factor, tint_factor, tint_factor, 0.98),
		0.0,
		phase,
		size_px / 64.0
	)
	_plant_count += 1

func _candidate_position(chunk_size_px: float, salt: int) -> Vector2:
	return Vector2(
		lerpf(
			EDGE_PADDING_PX,
			chunk_size_px - EDGE_PADDING_PX,
			_unit_float(_hash4(salt, 41, 43, 47))
		),
		lerpf(
			EDGE_PADDING_PX,
			chunk_size_px - EDGE_PADDING_PX,
			_unit_float(_hash4(salt, 53, 59, 61))
		)
	)

func _placement_biofield_score(position: Vector2) -> float:
	var chunk_size_px: float = float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
	if position.x < EDGE_PADDING_PX \
			or position.y < EDGE_PADDING_PX \
			or position.x > chunk_size_px - EDGE_PADDING_PX \
			or position.y > chunk_size_px - EDGE_PADDING_PX:
		return -1.0
	var local_coord := Vector2i(
		floori(position.x / float(WorldRuntimeConstants.TILE_SIZE_PX)),
		floori(position.y / float(WorldRuntimeConstants.TILE_SIZE_PX))
	)
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return -1.0
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index < 0 or index >= _terrain_ids.size():
		return -1.0
	if int(_terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
		return -1.0
	if index < _lake_flags.size() and (int(_lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0:
		return -1.0
	var world_pos: Vector2 = _chunk_origin_world_px + position
	return _orange_biofield_score(world_pos)

func _placement_chance(biofield_score: float) -> float:
	var biofield_bias: float = smoothstep(BIOFIELD_PLACEMENT_THRESHOLD, 0.86, biofield_score)
	return lerpf(BIOFIELD_MIN_DENSITY, BIOFIELD_MAX_DENSITY, biofield_bias)

func _is_too_close_to_existing(position: Vector2, placed_positions: Array[Vector2]) -> bool:
	var min_distance_sq: float = MIN_PLANT_DISTANCE_PX * MIN_PLANT_DISTANCE_PX
	for existing: Vector2 in placed_positions:
		if position.distance_squared_to(existing) < min_distance_sq:
			return true
	return false

func _has_plain_ground_cells() -> bool:
	for index: int in range(_terrain_ids.size()):
		if int(_terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
			continue
		if index < _lake_flags.size() and (int(_lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0:
			continue
		return true
	return false

func _has_terrain_mask_coverage() -> bool:
	var stride: int = maxi(1, MASK_PREFLIGHT_STRIDE)
	for y: int in range(0, _mask_height, stride):
		var row_offset: int = y * _mask_width
		for x: int in range(0, _mask_width, stride):
			var index: int = row_offset + x
			if index >= 0 and index < _mask_bytes.size() and int(_mask_bytes[index]) >= MASK_PREFLIGHT_MIN_VALUE:
				return true
	return false

func _orange_biofield_score(world_px: Vector2) -> float:
	var uv: Vector2 = (world_px - _mask_origin_world_px) / maxf(_mask_step_px, 0.001)
	uv = Vector2(
		uv.x / maxf(float(_mask_width), 1.0),
		uv.y / maxf(float(_mask_height), 1.0)
	)
	var ground: float = _terrain_mask(uv)
	if ground <= 0.01:
		return -1.0
	var texel := Vector2(1.0 / maxf(float(_mask_width), 1.0), 1.0 / maxf(float(_mask_height), 1.0))
	var clearance_texels: float = maxf(BIOFIELD_EDGE_CLEARANCE_PX / maxf(_mask_step_px, 0.001), 1.0)
	var edge_safe: float = ground
	edge_safe = minf(edge_safe, _terrain_mask(uv + Vector2(texel.x * clearance_texels, 0.0)))
	edge_safe = minf(edge_safe, _terrain_mask(uv - Vector2(texel.x * clearance_texels, 0.0)))
	edge_safe = minf(edge_safe, _terrain_mask(uv + Vector2(0.0, texel.y * clearance_texels)))
	edge_safe = minf(edge_safe, _terrain_mask(uv - Vector2(0.0, texel.y * clearance_texels)))
	edge_safe = minf(edge_safe, _terrain_mask(uv + Vector2(texel.x, texel.y) * clearance_texels * 0.72))
	edge_safe = minf(edge_safe, _terrain_mask(uv + Vector2(-texel.x, texel.y) * clearance_texels * 0.72))
	edge_safe = minf(edge_safe, _terrain_mask(uv + Vector2(texel.x, -texel.y) * clearance_texels * 0.72))
	edge_safe = minf(edge_safe, _terrain_mask(uv + Vector2(-texel.x, -texel.y) * clearance_texels * 0.72))
	edge_safe = smoothstep(0.36, 0.92, edge_safe)
	if edge_safe <= 0.01:
		return -1.0
	return _organic_region_mask(world_px) * edge_safe * ground

func _terrain_mask(uv: Vector2) -> float:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return 0.0
	return smoothstep(TERRAIN_THRESHOLD_LOW, TERRAIN_THRESHOLD_HIGH, _mask_value_at_uv(uv))

func _mask_value_at_uv(uv: Vector2) -> float:
	if _mask_width <= 0 or _mask_height <= 0 or _mask_bytes.is_empty():
		return 0.0
	var x: int = clampi(floori(uv.x * float(_mask_width)), 0, _mask_width - 1)
	var y: int = clampi(floori(uv.y * float(_mask_height)), 0, _mask_height - 1)
	var index: int = y * _mask_width + x
	if index < 0 or index >= _mask_bytes.size():
		return 0.0
	return float(int(_mask_bytes[index])) / 255.0

func _organic_region_mask(world_px: Vector2) -> float:
	var p: Vector2 = world_px / maxf(BIOFIELD_PATCH_CELL_PX, 1.0)
	var broad_warp := Vector2(
		_fbm2(p * 0.72 + Vector2(13.4, -8.9)),
		_fbm2(p * 0.69 + Vector2(-31.7, 24.1))
	) - Vector2(0.5, 0.5)
	var local_warp := Vector2(
		_fbm2(p * 1.86 + Vector2(71.0, 9.5)),
		_fbm2(p * 1.61 + Vector2(-44.6, 58.2))
	) - Vector2(0.5, 0.5)
	var warped: Vector2 = p + broad_warp * 1.55 + local_warp * 0.42
	var large_regions: float = _fbm2(warped * 0.94 + Vector2(5.1, 17.3))
	var medium_cut: float = _fbm2(warped * 2.15 + Vector2(-19.0, 41.0))
	var edge_breakup: float = _fbm2(warped * 5.8 + Vector2(62.0, -27.0))
	var field: float = large_regions * 0.70 + medium_cut * 0.22 + edge_breakup * 0.08
	field += (edge_breakup - 0.5) * 0.10
	var threshold: float = lerpf(0.76, 0.43, clampf(BIOFIELD_PATCH_DENSITY, 0.0, 1.0))
	var region: float = smoothstep(threshold - 0.065, threshold + 0.085, field)
	var erosion: float = _fbm2(warped * 8.5 + Vector2(-3.0, 103.0))
	region = clampf(region + (erosion - 0.52) * 0.18, 0.0, 1.0)
	return smoothstep(0.16, 0.86, region)

func _ensure_batch_layer() -> WorldDecorBatchLayer:
	if _batch_layer != null and is_instance_valid(_batch_layer):
		return _batch_layer
	_batch_layer = WorldDecorBatchLayer.new()
	_batch_layer.name = "SpikyFloraDecorBatchLayer"
	add_child(_batch_layer)
	return _batch_layer

func _clear_batch() -> void:
	_plant_count = 0
	visible = false
	if _batch_layer != null and is_instance_valid(_batch_layer):
		_batch_layer.clear_batches()

static func _fbm2(p_start: Vector2) -> float:
	var p: Vector2 = p_start
	var value: float = 0.0
	var amplitude: float = 0.56
	var total: float = 0.0
	for _index: int in range(3):
		value += _value_noise(p) * amplitude
		total += amplitude
		p = p * 2.03 + Vector2(19.7, -11.2)
		amplitude *= 0.48
	return value / maxf(total, 0.0001)

static func _value_noise(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f: Vector2 = p - i
	var u := Vector2(
		f.x * f.x * (3.0 - 2.0 * f.x),
		f.y * f.y * (3.0 - 2.0 * f.y)
	)
	var a: float = _hash12(i)
	var b: float = _hash12(i + Vector2(1.0, 0.0))
	var c: float = _hash12(i + Vector2(0.0, 1.0))
	var d: float = _hash12(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)

static func _hash12(p: Vector2) -> float:
	var p3 := Vector3(
		_fract(p.x * 0.1031),
		_fract(p.y * 0.1031),
		_fract(p.x * 0.1031)
	)
	var shifted := Vector3(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33)
	var d: float = p3.dot(shifted)
	p3 += Vector3(d, d, d)
	return _fract((p3.x + p3.y) * p3.z)

static func _fract(value: float) -> float:
	return value - floorf(value)

static func _hash4(a: int, b: int, c: int, d: int) -> int:
	var value: int = a * 73856093 ^ b * 19349663 ^ c * 83492791 ^ d * 2654435761
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return value & 0x7fffffff

static func _unit_float(value: int) -> float:
	return float(value & 0xffff) / 65535.0
