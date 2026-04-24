class_name WorldBoundsSettings
extends Resource

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const PRESET_SMALL: StringName = &"small"
const PRESET_MEDIUM: StringName = &"medium"
const PRESET_LARGE: StringName = &"large"
const PRESET_CUSTOM: StringName = &"custom"
const DEFAULT_PRESET: StringName = PRESET_MEDIUM

const MIN_WIDTH_TILES: int = 1024
const MIN_HEIGHT_TILES: int = 512
const MAX_WIDTH_TILES: int = 16384
const MAX_HEIGHT_TILES: int = 8192

@export var preset_id: StringName = DEFAULT_PRESET
@export var width_tiles: int = 4096
@export var height_tiles: int = 2048

func to_save_dict() -> Dictionary:
	return {
		"width_tiles": width_tiles,
		"height_tiles": height_tiles,
	}

func get_width_chunks() -> int:
	return maxi(1, width_tiles / WorldRuntimeConstants.CHUNK_SIZE)

func get_height_chunks() -> int:
	return maxi(1, height_tiles / WorldRuntimeConstants.CHUNK_SIZE)

func is_tile_y_in_bounds(tile_y: int) -> bool:
	return tile_y >= 0 and tile_y < height_tiles

func is_chunk_y_in_bounds(chunk_y: int) -> bool:
	return chunk_y >= 0 and chunk_y < get_height_chunks()

func wrap_tile_x(tile_x: int) -> int:
	return posmod(tile_x, width_tiles)

func wrap_chunk_x(chunk_x: int) -> int:
	return posmod(chunk_x, get_width_chunks())

func canonicalize_tile(tile_coord: Vector2i) -> Vector2i:
	return Vector2i(wrap_tile_x(tile_coord.x), tile_coord.y)

func canonicalize_chunk(chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(wrap_chunk_x(chunk_coord.x), chunk_coord.y)

static func preset_ids() -> Array[StringName]:
	return [PRESET_SMALL, PRESET_MEDIUM, PRESET_LARGE]

static func preset_label_key(preset: StringName) -> StringName:
	match preset:
		PRESET_SMALL:
			return &"UI_WORLDGEN_SIZE_SMALL"
		PRESET_LARGE:
			return &"UI_WORLDGEN_SIZE_LARGE"
		_:
			return &"UI_WORLDGEN_SIZE_MEDIUM"

static func for_preset(preset: StringName) -> WorldBoundsSettings:
	var settings: WorldBoundsSettings = new()
	settings.preset_id = preset
	match preset:
		PRESET_SMALL:
			settings.width_tiles = 2048
			settings.height_tiles = 1024
		PRESET_LARGE:
			settings.width_tiles = 8192
			settings.height_tiles = 4096
		_:
			settings.preset_id = PRESET_MEDIUM
			settings.width_tiles = 4096
			settings.height_tiles = 2048
	return settings

static func hard_coded_defaults() -> WorldBoundsSettings:
	return for_preset(DEFAULT_PRESET)

static func from_save_dict(data: Dictionary) -> WorldBoundsSettings:
	var settings: WorldBoundsSettings = hard_coded_defaults()
	settings.preset_id = PRESET_CUSTOM
	settings.width_tiles = _sanitize_dimension(
		int(data.get("width_tiles", settings.width_tiles)),
		MIN_WIDTH_TILES,
		MAX_WIDTH_TILES
	)
	settings.height_tiles = _sanitize_dimension(
		int(data.get("height_tiles", settings.height_tiles)),
		MIN_HEIGHT_TILES,
		MAX_HEIGHT_TILES
	)
	return settings

static func _sanitize_dimension(value: int, min_value: int, max_value: int) -> int:
	var aligned_value: int = clampi(value, min_value, max_value)
	var alignment: int = WorldRuntimeConstants.FOUNDATION_COARSE_CELL_SIZE_TILES
	return maxi(alignment, (aligned_value / alignment) * alignment)
