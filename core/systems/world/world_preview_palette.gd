class_name WorldPreviewPalette
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const PALETTE_ID: StringName = &"terrain_preview_v1"
const COLOR_GROUND: Color = Color(0.18, 0.23, 0.18, 1.0)
const COLOR_MOUNTAIN_FOOT: Color = Color(0.53, 0.49, 0.39, 1.0)
const COLOR_MOUNTAIN_WALL: Color = Color(0.86, 0.83, 0.76, 1.0)
const COLOR_UNKNOWN: Color = Color(0.07, 0.09, 0.10, 1.0)

func get_palette_id() -> StringName:
	return PALETTE_ID

func build_patch_texture(packet: Dictionary) -> Texture2D:
	var terrain_ids: PackedInt32Array = packet.get("terrain_ids", PackedInt32Array()) as PackedInt32Array
	var image: Image = Image.create(
		WorldRuntimeConstants.CHUNK_SIZE,
		WorldRuntimeConstants.CHUNK_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(COLOR_UNKNOWN)
	for index: int in range(mini(terrain_ids.size(), WorldRuntimeConstants.CHUNK_CELL_COUNT)):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		image.set_pixel(local_coord.x, local_coord.y, _resolve_tile_color(int(terrain_ids[index])))
	return ImageTexture.create_from_image(image)

func _resolve_tile_color(terrain_id: int) -> Color:
	match terrain_id:
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL:
			return COLOR_MOUNTAIN_WALL
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT:
			return COLOR_MOUNTAIN_FOOT
		_:
			return COLOR_GROUND
