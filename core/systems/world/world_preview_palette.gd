class_name WorldPreviewPalette
extends RefCounted

const WorldPreviewRenderMode = preload("res://core/systems/world/world_preview_render_mode.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const PALETTE_ID_PREFIX: String = "terrain_preview_v1"
const COLOR_GROUND: Color = Color(0.18, 0.23, 0.18, 1.0)
const COLOR_MOUNTAIN_FOOT: Color = Color(0.53, 0.49, 0.39, 1.0)
const COLOR_MOUNTAIN_WALL: Color = Color(0.86, 0.83, 0.76, 1.0)
const COLOR_CLASSIFICATION_GROUND: Color = Color(0.13, 0.16, 0.13, 1.0)
const COLOR_CLASSIFICATION_FOOT: Color = Color(0.84, 0.56, 0.20, 1.0)
const COLOR_CLASSIFICATION_WALL: Color = Color(0.23, 0.67, 0.88, 1.0)
const COLOR_CLASSIFICATION_INTERIOR: Color = Color(0.92, 0.29, 0.55, 1.0)
const COLOR_UNKNOWN: Color = Color(0.07, 0.09, 0.10, 1.0)

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
	return ImageTexture.create_from_image(image)

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
