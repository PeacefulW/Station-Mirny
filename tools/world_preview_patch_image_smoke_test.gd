extends SceneTree

const WorldPreviewPalette = preload("res://core/systems/world/world_preview_palette.gd")
const WorldPreviewRenderMode = preload("res://core/systems/world/world_preview_render_mode.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

func _init() -> void:
	var packet := _make_packet()
	var palette := WorldPreviewPalette.new()
	for mode: StringName in [
		WorldPreviewRenderMode.TERRAIN,
		WorldPreviewRenderMode.MOUNTAIN_ID,
		WorldPreviewRenderMode.MOUNTAIN_CLASSIFICATION,
	]:
		var texture := palette.build_patch_texture(packet, mode)
		if texture == null:
			push_error("world_preview_patch_image_smoke_test: null texture for mode %s" % [mode])
			quit(1)
			return
		if texture.get_width() != WorldRuntimeConstants.CHUNK_SIZE or texture.get_height() != WorldRuntimeConstants.CHUNK_SIZE:
			push_error("world_preview_patch_image_smoke_test: unexpected texture size for mode %s" % [mode])
			quit(1)
			return
	print("world_preview_patch_image_smoke_test: OK")
	quit(0)

func _make_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var mountain_ids := PackedInt32Array()
	var mountain_flags := PackedByteArray()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	mountain_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		mountain_ids[index] = 0
		mountain_flags[index] = 0
	terrain_ids[0] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL
	mountain_ids[0] = 101
	mountain_flags[0] = WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR
	terrain_ids[1] = WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT
	mountain_ids[1] = 101
	mountain_flags[1] = WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	return {
		"terrain_ids": terrain_ids,
		"mountain_id_per_tile": mountain_ids,
		"mountain_flags": mountain_flags,
	}
