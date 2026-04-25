class_name WorldPreviewPalette
extends RefCounted

const WorldPreviewRenderMode = preload("res://core/systems/world/world_preview_render_mode.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const PALETTE_ID_PREFIX: String = "terrain_preview_v1"
const COLOR_GROUND: Color = Color(0.18, 0.23, 0.18, 1.0)
const COLOR_RIVERBED_SHALLOW: Color = Color(0.42, 0.36, 0.24, 1.0)
const COLOR_RIVERBED_DEEP: Color = Color(0.27, 0.22, 0.17, 1.0)
const COLOR_LAKEBED_SHALLOW: Color = Color(0.46, 0.42, 0.30, 1.0)
const COLOR_LAKEBED_DEEP: Color = Color(0.25, 0.25, 0.22, 1.0)
const COLOR_OCEAN_BED_SHALLOW: Color = Color(0.18, 0.36, 0.52, 1.0)
const COLOR_OCEAN_BED_DEEP: Color = Color(0.06, 0.20, 0.38, 1.0)
const COLOR_MOUNTAIN_FOOT: Color = Color(0.53, 0.49, 0.39, 1.0)
const COLOR_MOUNTAIN_WALL: Color = Color(0.86, 0.83, 0.76, 1.0)
const COLOR_CLASSIFICATION_GROUND: Color = Color(0.13, 0.16, 0.13, 1.0)
const COLOR_CLASSIFICATION_FOOT: Color = Color(0.84, 0.56, 0.20, 1.0)
const COLOR_CLASSIFICATION_WALL: Color = Color(0.23, 0.67, 0.88, 1.0)
const COLOR_CLASSIFICATION_INTERIOR: Color = Color(0.92, 0.29, 0.55, 1.0)
const COLOR_UNKNOWN: Color = Color(0.07, 0.09, 0.10, 1.0)
const MIPMAP_LEVELS: int = 6

func get_palette_id(render_mode: StringName) -> StringName:
	var normalized_mode: StringName = _resolve_patch_render_mode(render_mode)
	return StringName("%s.%s" % [PALETTE_ID_PREFIX, String(normalized_mode)])

func build_patch_texture(packet: Dictionary, render_mode: StringName) -> Texture2D:
	var normalized_mode: StringName = _resolve_patch_render_mode(render_mode)
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var mountain_ids: PackedInt32Array = packet.get("mountain_id_per_tile", PackedInt32Array()) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get("mountain_flags", PackedByteArray()) as PackedByteArray
	var image: Image = Image.create(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(COLOR_UNKNOWN)
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		image.set_pixel(
			local_coord.x,
			local_coord.y,
			_resolve_tile_color(
				normalized_mode,
				int(terrain_ids[index]),
				_read_int_from_array(mountain_ids, index),
				_read_int_from_array(mountain_flags, index)
			)
		)
	var ground_color: Color = _resolve_ground_color_for_mode(normalized_mode)
	var levels: Array[Image] = [image]
	var current: Image = image
	while (current.get_width() > 1 or current.get_height() > 1) and levels.size() < MIPMAP_LEVELS:
		current = _downsample_mountain_preserving(current, ground_color)
		levels.append(current)
	var combined_bytes := PackedByteArray()
	for level: Image in levels:
		combined_bytes.append_array(level.get_data())
	var mipmapped_image: Image = Image.create_from_data(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		true,
		Image.FORMAT_RGBA8,
		combined_bytes
	)
	return ImageTexture.create_from_image(mipmapped_image)

func _resolve_ground_color_for_mode(render_mode: StringName) -> Color:
	match render_mode:
		WorldPreviewRenderMode.MOUNTAIN_ID, WorldPreviewRenderMode.MOUNTAIN_CLASSIFICATION:
			return _quantize_rgba8_color(COLOR_CLASSIFICATION_GROUND)
		_:
			return _quantize_rgba8_color(COLOR_GROUND)

func _downsample_mountain_preserving(src: Image, ground_color: Color) -> Image:
	var dst_w: int = maxi(1, int(src.get_width() / 2))
	var dst_h: int = maxi(1, int(src.get_height() / 2))
	var dst: Image = Image.create(dst_w, dst_h, false, Image.FORMAT_RGBA8)
	for y: int in range(dst_h):
		for x: int in range(dst_w):
			var sx: int = x * 2
			var sy: int = y * 2
			var sx1: int = mini(sx + 1, src.get_width() - 1)
			var sy1: int = mini(sy + 1, src.get_height() - 1)
			var picked: Color = ground_color
			for sample: Color in [
				src.get_pixel(sx, sy),
				src.get_pixel(sx1, sy),
				src.get_pixel(sx, sy1),
				src.get_pixel(sx1, sy1),
			]:
				if not sample.is_equal_approx(ground_color):
					picked = sample
					break
			dst.set_pixel(x, y, picked)
	return dst

func _quantize_rgba8_color(color: Color) -> Color:
	return Color(
		float(clampi(roundi(color.r * 255.0), 0, 255)) / 255.0,
		float(clampi(roundi(color.g * 255.0), 0, 255)) / 255.0,
		float(clampi(roundi(color.b * 255.0), 0, 255)) / 255.0,
		float(clampi(roundi(color.a * 255.0), 0, 255)) / 255.0
	)

func _resolve_tile_color(
	render_mode: StringName,
	terrain_id: int,
	mountain_id: int,
	mountain_flag_value: int
) -> Color:
	match render_mode:
		WorldPreviewRenderMode.MOUNTAIN_ID:
			return _resolve_mountain_id_color(mountain_id, mountain_flag_value)
		WorldPreviewRenderMode.MOUNTAIN_CLASSIFICATION:
			return _resolve_classification_color(mountain_flag_value)
		_:
			return _resolve_terrain_color(terrain_id)

func _resolve_terrain_color(terrain_id: int) -> Color:
	match terrain_id:
		WorldRuntimeConstants.TERRAIN_RIVERBED_SHALLOW:
			return COLOR_RIVERBED_SHALLOW
		WorldRuntimeConstants.TERRAIN_RIVERBED_DEEP:
			return COLOR_RIVERBED_DEEP
		WorldRuntimeConstants.TERRAIN_LAKEBED_SHALLOW:
			return COLOR_LAKEBED_SHALLOW
		WorldRuntimeConstants.TERRAIN_LAKEBED_DEEP:
			return COLOR_LAKEBED_DEEP
		WorldRuntimeConstants.TERRAIN_OCEAN_BED_SHALLOW:
			return COLOR_OCEAN_BED_SHALLOW
		WorldRuntimeConstants.TERRAIN_OCEAN_BED_DEEP:
			return COLOR_OCEAN_BED_DEEP
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL:
			return COLOR_MOUNTAIN_WALL
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			return COLOR_MOUNTAIN_FOOT
		_:
			return COLOR_GROUND

func _resolve_classification_color(mountain_flag_value: int) -> Color:
	if (mountain_flag_value & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0:
		return COLOR_CLASSIFICATION_INTERIOR
	if (mountain_flag_value & WorldRuntimeConstants.MOUNTAIN_FLAG_WALL) != 0:
		return COLOR_CLASSIFICATION_WALL
	if (mountain_flag_value & WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT) != 0:
		return COLOR_CLASSIFICATION_FOOT
	return COLOR_CLASSIFICATION_GROUND

func _resolve_mountain_id_color(mountain_id: int, mountain_flag_value: int) -> Color:
	if mountain_id <= 0:
		return COLOR_CLASSIFICATION_GROUND
	var hashed_id: int = mountain_id & 0x7FFFFFFF
	hashed_id = int(hashed_id ^ (hashed_id >> 16))
	hashed_id *= 224682251
	hashed_id = int(hashed_id ^ (hashed_id >> 13))
	var hue: float = float(hashed_id & 1023) / 1023.0
	var saturation: float = 0.58 + float((hashed_id >> 10) & 63) / 210.0
	var value: float = 0.72
	if (mountain_flag_value & WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR) != 0:
		value = 0.84
	elif (mountain_flag_value & WorldRuntimeConstants.MOUNTAIN_FLAG_WALL) != 0:
		value = 0.92
	return Color.from_hsv(hue, minf(saturation, 0.92), value, 1.0)

func _read_int_from_array(values: Variant, index: int) -> int:
	if values is PackedInt32Array:
		var int_values: PackedInt32Array = values as PackedInt32Array
		return int(int_values[index]) if index < int_values.size() else 0
	if values is PackedByteArray:
		var byte_values: PackedByteArray = values as PackedByteArray
		return int(byte_values[index]) if index < byte_values.size() else 0
	return 0

func _resolve_patch_render_mode(render_mode: StringName) -> StringName:
	var normalized_mode: StringName = WorldPreviewRenderMode.coerce(render_mode)
	return WorldPreviewRenderMode.TERRAIN if normalized_mode == WorldPreviewRenderMode.SPAWN_SAFE_PATCH else normalized_mode
