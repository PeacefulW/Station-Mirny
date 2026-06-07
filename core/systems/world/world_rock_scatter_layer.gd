class_name WorldRockScatterLayer
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldDecorBatchLayer = preload("res://core/systems/world/world_decor_batch_layer.gd")

const FRAME_COLUMNS: int = 8
const FRAME_ROWS: int = 4
const FRAME_COUNT: int = 32
const SCATTER_GRID_SIDE: int = 8
const PRIMARY_DENSITY: float = 0.23
const SATELLITE_DENSITY: float = 0.18
const VOLCANIC_ROCK_CHANCE: float = 0.08
const EDGE_PADDING_PX: float = 18.0

var _atlases: Array[Texture2D] = []
var _terrain_ids: PackedInt32Array = PackedInt32Array()
var _lake_flags: PackedByteArray = PackedByteArray()
var _chunk_coord: Vector2i = Vector2i.ZERO
var _world_seed: int = WorldRuntimeConstants.DEFAULT_WORLD_SEED
var _world_version: int = WorldRuntimeConstants.WORLD_VERSION
var _batch_layer: WorldDecorBatchLayer = null
var _rock_count: int = 0

# Temporary visual adapter only; final dense object placement belongs in the
# native chunk packet path and should feed WorldDecorBatchLayer directly.
func set_atlases(atlases: Array[Texture2D]) -> void:
	_atlases = atlases.duplicate()
	if _atlases.is_empty():
		_clear_batch()

func configure_chunk(
	chunk_coord: Vector2i,
	world_seed: int,
	world_version: int,
	terrain_ids: PackedInt32Array,
	lake_flags: PackedByteArray
) -> void:
	_chunk_coord = chunk_coord
	_world_seed = world_seed
	_world_version = world_version
	_terrain_ids = terrain_ids.duplicate()
	_lake_flags = lake_flags.duplicate()
	if _lake_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_lake_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	_rebuild_batch()

func set_sun_lighting(
	light_angle_deg: float,
	shadow_length_px: float,
	shadow_opacity: float,
	shadow_softness_px: float
) -> void:
	if _batch_layer == null or not is_instance_valid(_batch_layer):
		return
	_batch_layer.set_sun_lighting(
		light_angle_deg,
		shadow_length_px,
		shadow_opacity,
		shadow_softness_px
	)

func get_rock_count() -> int:
	return _rock_count

func _rebuild_batch() -> void:
	_rock_count = 0
	visible = false
	if _atlases.is_empty() or _terrain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		_clear_batch()
		return
	var sprite_buffers: Array = []
	for _atlas_index: int in range(_atlases.size()):
		sprite_buffers.append(PackedFloat32Array())
	var shadow_buffer := PackedFloat32Array()
	var chunk_size_px: float = float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
	var cell_size_px: float = chunk_size_px / float(SCATTER_GRID_SIDE)
	var used_variants: Dictionary = {}
	for grid_y: int in range(SCATTER_GRID_SIDE):
		for grid_x: int in range(SCATTER_GRID_SIDE):
			var cell_hash: int = _hash4(
				_chunk_coord.x,
				_chunk_coord.y,
				grid_x + grid_y * SCATTER_GRID_SIDE,
				_world_seed ^ (_world_version * 31)
			)
			if _unit_float(cell_hash) > PRIMARY_DENSITY:
				continue
			var position: Vector2 = _candidate_position(grid_x, grid_y, cell_size_px, cell_hash)
			_append_rock(position, cell_hash, false, used_variants, sprite_buffers, shadow_buffer)
			if _unit_float(_hash4(cell_hash, grid_x, grid_y, 17)) <= SATELLITE_DENSITY:
				var angle: float = _unit_float(_hash4(cell_hash, 3, 5, 19)) * TAU
				var distance_px: float = lerpf(26.0, 72.0, _unit_float(_hash4(cell_hash, 11, 13, 23)))
				_append_rock(
					position + Vector2(cos(angle), sin(angle)) * distance_px,
					_hash4(cell_hash, 29, 31, 37),
					true,
					used_variants,
					sprite_buffers,
					shadow_buffer
				)
	if _rock_count <= 0:
		_clear_batch()
		return
	var batch_layer: WorldDecorBatchLayer = _ensure_batch_layer()
	batch_layer.set_chunk_size_px(chunk_size_px)
	batch_layer.set_atlas_layout(FRAME_COLUMNS, FRAME_ROWS, FRAME_COUNT)
	batch_layer.set_batches(_atlases, sprite_buffers, shadow_buffer)
	visible = true

func _append_rock(
	position: Vector2,
	salt: int,
	is_satellite: bool,
	used_variants: Dictionary,
	sprite_buffers: Array,
	shadow_buffer: PackedFloat32Array
) -> void:
	if not _is_position_valid_for_rock(position):
		return
	var atlas_index: int = _choose_atlas_index(salt)
	if atlas_index < 0 or atlas_index >= sprite_buffers.size():
		return
	var frame_index: int = _choose_unique_frame(atlas_index, salt, used_variants)
	var size_px: float = _choose_size_px(salt, atlas_index, is_satellite)
	var tint_factor: float = lerpf(0.88, 1.08, _unit_float(_hash4(salt, 67, 71, 73)))
	var wind_phase: float = _unit_float(_hash4(salt, 157, 163, 167))
	var sprite_buffer: PackedFloat32Array = sprite_buffers[atlas_index]
	WorldDecorBatchLayer.append_instance(
		sprite_buffer,
		position,
		Vector2.ONE * size_px,
		frame_index,
		Color(tint_factor, tint_factor, tint_factor, 0.96),
		0.0,
		wind_phase,
		size_px / 64.0
	)
	sprite_buffers[atlas_index] = sprite_buffer
	WorldDecorBatchLayer.append_instance(
		shadow_buffer,
		position + Vector2(0.0, size_px * 0.24),
		Vector2(size_px * 0.72, size_px * 0.24),
		0,
		Color(1.0, 1.0, 1.0, 1.0),
		0.0,
		wind_phase,
		size_px / 64.0
	)
	_rock_count += 1

func _candidate_position(grid_x: int, grid_y: int, cell_size_px: float, salt: int) -> Vector2:
	var jitter_x: float = (_unit_float(_hash4(salt, 41, 43, 47)) - 0.5) \
		* maxf(8.0, cell_size_px - EDGE_PADDING_PX * 2.0)
	var jitter_y: float = (_unit_float(_hash4(salt, 53, 59, 61)) - 0.5) \
		* maxf(8.0, cell_size_px - EDGE_PADDING_PX * 2.0)
	return Vector2(
		(float(grid_x) + 0.5) * cell_size_px + jitter_x,
		(float(grid_y) + 0.5) * cell_size_px + jitter_y
	)

func _choose_atlas_index(salt: int) -> int:
	var roll: float = _unit_float(_hash4(salt, 79, 83, 89))
	if _atlases.size() >= 3 and roll < VOLCANIC_ROCK_CHANCE:
		return 2
	if _atlases.size() >= 2:
		return 0 if roll < 0.54 else 1
	return 0

func _choose_unique_frame(atlas_index: int, salt: int, used_variants: Dictionary) -> int:
	var frame_index: int = _hash4(salt, 97, 101, 103) % FRAME_COUNT
	for offset: int in range(FRAME_COUNT):
		var candidate: int = (frame_index + offset * 7) % FRAME_COUNT
		var key: String = "%d:%d" % [atlas_index, candidate]
		if used_variants.has(key):
			continue
		used_variants[key] = true
		return candidate
	return frame_index

func _choose_size_px(salt: int, atlas_index: int, is_satellite: bool) -> float:
	var size_roll: float = _unit_float(_hash4(salt, 107, 109, 113))
	var size_px: float = lerpf(42.0, 76.0, size_roll)
	if is_satellite:
		size_px *= lerpf(0.64, 0.84, _unit_float(_hash4(salt, 127, 131, 137)))
	if atlas_index == 2:
		size_px *= 0.88
	if _unit_float(_hash4(salt, 139, 149, 151)) < 0.10 and not is_satellite:
		size_px *= 1.22
	return clampf(size_px, 28.0, 96.0)

func _is_position_valid_for_rock(position: Vector2) -> bool:
	var chunk_size_px: float = float(WorldRuntimeConstants.CHUNK_SIZE * WorldRuntimeConstants.TILE_SIZE_PX)
	if position.x < EDGE_PADDING_PX \
			or position.y < EDGE_PADDING_PX \
			or position.x > chunk_size_px - EDGE_PADDING_PX \
			or position.y > chunk_size_px - EDGE_PADDING_PX:
		return false
	var local_coord := Vector2i(
		floori(position.x / float(WorldRuntimeConstants.TILE_SIZE_PX)),
		floori(position.y / float(WorldRuntimeConstants.TILE_SIZE_PX))
	)
	if not WorldRuntimeConstants.is_local_coord_valid(local_coord):
		return false
	var index: int = WorldRuntimeConstants.local_to_index(local_coord)
	if index < 0 or index >= _terrain_ids.size():
		return false
	if int(_terrain_ids[index]) != WorldRuntimeConstants.TERRAIN_PLAINS_GROUND:
		return false
	if index < _lake_flags.size() and (int(_lake_flags[index]) & WorldRuntimeConstants.LAKE_FLAG_WATER_PRESENT) != 0:
		return false
	return true

func _ensure_batch_layer() -> WorldDecorBatchLayer:
	if _batch_layer != null and is_instance_valid(_batch_layer):
		return _batch_layer
	_batch_layer = WorldDecorBatchLayer.new()
	_batch_layer.name = "RockDecorBatchLayer"
	add_child(_batch_layer)
	return _batch_layer

func _clear_batch() -> void:
	_rock_count = 0
	visible = false
	if _batch_layer != null and is_instance_valid(_batch_layer):
		_batch_layer.clear_batches()

static func _hash4(a: int, b: int, c: int, d: int) -> int:
	var value: int = a * 73856093 ^ b * 19349663 ^ c * 83492791 ^ d * 2654435761
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return value & 0x7fffffff

static func _unit_float(value: int) -> float:
	return float(value & 0xffff) / 65535.0
