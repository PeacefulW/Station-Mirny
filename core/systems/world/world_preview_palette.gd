class_name WorldPreviewPalette
extends RefCounted

const WorldPreviewRenderMode = preload("res://core/systems/world/world_preview_render_mode.gd")

const PALETTE_ID_PREFIX: String = "terrain_preview_v1"

var _world_core: WorldCore = WorldCore.new()

func get_palette_id(render_mode: StringName) -> StringName:
	var normalized_mode: StringName = _resolve_patch_render_mode(render_mode)
	return StringName("%s.%s" % [PALETTE_ID_PREFIX, String(normalized_mode)])

func build_patch_texture(packet: Dictionary, render_mode: StringName) -> Texture2D:
	var normalized_mode: StringName = _resolve_patch_render_mode(render_mode)
	var image: Image = _world_core.make_world_preview_patch_image(packet, normalized_mode)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _resolve_patch_render_mode(render_mode: StringName) -> StringName:
	var normalized_mode: StringName = WorldPreviewRenderMode.coerce(render_mode)
	return WorldPreviewRenderMode.TERRAIN if normalized_mode == WorldPreviewRenderMode.SPAWN_SAFE_PATCH else normalized_mode
