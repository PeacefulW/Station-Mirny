class_name WorldFoundationPalette
extends RefCounted

const PALETTE_ID: StringName = &"foundation_overview_v1"
const TERRAIN: StringName = &"terrain"
const HYDROLOGY_WATER: StringName = &"hydrology_water"
const HYDRO_HEIGHT: StringName = &"hydro_height"
const LAYER_MASK_TERRAIN: int = 0
const LAYER_MASK_HYDRO_HEIGHT: int = 1 << 4
const LAYER_MASK_HYDROLOGY_WATER: int = 1 << 5
# Must match native write_overview_rgba in world_prepass.cpp.
const COLOR_MOUNTAIN_FOOT: Color = Color(106.0 / 255.0, 98.0 / 255.0, 74.0 / 255.0, 1.0)
const COLOR_MOUNTAIN_WALL: Color = Color(164.0 / 255.0, 160.0 / 255.0, 146.0 / 255.0, 1.0)
const COLOR_UNKNOWN: Color = Color(0.04, 0.05, 0.06, 1.0)
const OVERVIEW_PIXELS_PER_CELL: int = 4

const _ORDERED_MODES: Array[StringName] = [
	TERRAIN,
	HYDROLOGY_WATER,
	HYDRO_HEIGHT,
]

const _LABEL_KEYS: Dictionary = {
	TERRAIN: &"UI_WORLDGEN_OVERVIEW_MODE_TERRAIN",
	HYDROLOGY_WATER: &"UI_WORLDGEN_OVERVIEW_MODE_WATER",
	HYDRO_HEIGHT: &"UI_WORLDGEN_OVERVIEW_MODE_HEIGHT",
}

var _active_mode: StringName = TERRAIN

static func all_modes() -> Array[StringName]:
	return _ORDERED_MODES.duplicate()

static func coerce_mode(mode: StringName) -> StringName:
	return mode if _LABEL_KEYS.has(mode) else TERRAIN

static func get_label_key(mode: StringName) -> StringName:
	var normalized_mode: StringName = coerce_mode(mode)
	return _LABEL_KEYS.get(normalized_mode, &"UI_WORLDGEN_OVERVIEW_MODE_TERRAIN") as StringName

func get_palette_id() -> StringName:
	return StringName("%s.%s" % [String(PALETTE_ID), String(_active_mode)])

func get_mode() -> StringName:
	return _active_mode

func set_mode(mode: StringName) -> void:
	_active_mode = coerce_mode(mode)

func get_layer_mask() -> int:
	match _active_mode:
		HYDROLOGY_WATER:
			return LAYER_MASK_HYDROLOGY_WATER
		HYDRO_HEIGHT:
			return LAYER_MASK_HYDRO_HEIGHT
		_:
			return LAYER_MASK_TERRAIN

func get_pixels_per_cell() -> int:
	return OVERVIEW_PIXELS_PER_CELL

func build_overview_texture_from_snapshot(snapshot: Dictionary) -> Texture2D:
	var image: Image = build_overview_image(snapshot)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func build_overview_texture(overview_image: Image) -> Texture2D:
	if overview_image == null or overview_image.is_empty():
		return null
	return ImageTexture.create_from_image(overview_image)

func build_overview_image(snapshot: Dictionary) -> Image:
	var grid_width: int = int(snapshot.get("grid_width", 0))
	var grid_height: int = int(snapshot.get("grid_height", 0))
	if grid_width <= 0 or grid_height <= 0:
		return null
	var image: Image = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	image.fill(COLOR_UNKNOWN)
	for index: int in range(grid_width * grid_height):
		image.set_pixel(
			index % grid_width,
			int(index / grid_width),
			_resolve_node_color(snapshot, index)
		)
	if OVERVIEW_PIXELS_PER_CELL > 1:
		image.resize(
			grid_width * OVERVIEW_PIXELS_PER_CELL,
			grid_height * OVERVIEW_PIXELS_PER_CELL,
			Image.INTERPOLATE_BILINEAR
		)
	return image

func _resolve_node_color(snapshot: Dictionary, index: int) -> Color:
	var hydro: float = clampf(_read_float(snapshot.get("hydro_height", PackedFloat32Array()), index), 0.0, 1.0)
	if _active_mode == HYDRO_HEIGHT:
		return _resolve_height_color(hydro)
	var wall: float = clampf(_read_float(snapshot.get("coarse_wall_density", PackedFloat32Array()), index), 0.0, 1.0)
	var foot: float = clampf(_read_float(snapshot.get("coarse_foot_density", PackedFloat32Array()), index), 0.0, 1.0)
	if wall > 0.0:
		return COLOR_MOUNTAIN_WALL.lerp(Color(238.0 / 255.0, 234.0 / 255.0, 220.0 / 255.0, 1.0), clampf(wall, 0.0, 1.0))
	if foot > 0.0:
		return COLOR_MOUNTAIN_FOOT.lerp(Color(178.0 / 255.0, 143.0 / 255.0, 101.0 / 255.0, 1.0), clampf(foot, 0.0, 1.0))
	var base: float = clampf((42.0 + hydro * 24.0) / 255.0, 0.0, 1.0)
	return Color(
		base,
		clampf(base + 18.0 / 255.0, 0.0, 1.0),
		clampf(base - 4.0 / 255.0, 0.0, 1.0),
		1.0
	)

func _resolve_height_color(height: float) -> Color:
	var low: Color = Color(24.0 / 255.0, 38.0 / 255.0, 60.0 / 255.0, 1.0)
	var mid_low: Color = Color(58.0 / 255.0, 96.0 / 255.0, 86.0 / 255.0, 1.0)
	var mid_high: Color = Color(156.0 / 255.0, 132.0 / 255.0, 82.0 / 255.0, 1.0)
	var high: Color = Color(235.0 / 255.0, 230.0 / 255.0, 202.0 / 255.0, 1.0)
	if height <= 0.42:
		return low.lerp(mid_low, clampf(height / 0.42, 0.0, 1.0))
	if height <= 0.75:
		return mid_low.lerp(mid_high, clampf((height - 0.42) / 0.33, 0.0, 1.0))
	return mid_high.lerp(high, clampf((height - 0.75) / 0.25, 0.0, 1.0))

func _read_byte(values: Variant, index: int) -> int:
	if values is not PackedByteArray:
		return 0
	var typed_values: PackedByteArray = values as PackedByteArray
	return int(typed_values[index]) if index >= 0 and index < typed_values.size() else 0

func _read_float(values: Variant, index: int) -> float:
	if values is not PackedFloat32Array:
		return 0.0
	var typed_values: PackedFloat32Array = values as PackedFloat32Array
	return float(typed_values[index]) if index >= 0 and index < typed_values.size() else 0.0
