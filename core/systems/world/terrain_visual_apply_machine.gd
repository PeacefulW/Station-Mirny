class_name TerrainVisualApplyMachine
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const TerrainVisualChunkLayer = preload("res://core/systems/world/terrain_visual_chunk_layer.gd")

const FULL_APPLY_TEXTURES_PER_STEP := 1

var full_apply_step_count: int = 0
var last_full_apply_texture_count: int = 0
var patch_apply_count: int = 0
var last_patch_world_origin_tile: Vector2i = Vector2i.ZERO
var last_patch_pixel_size: Vector2i = Vector2i.ZERO
var last_patch_intersection_px: Rect2i = Rect2i(Vector2i.ZERO, Vector2i.ZERO)

var _pending_full_packet: Dictionary = { }
var _pending_full_recipe: Resource = null
var _pending_full_solver_method: StringName = &""
var _pending_full_layer: ColorRect = null
var _pending_full_material: ShaderMaterial = null
var _pending_full_images: Dictionary = { }
var _pending_full_textures: Dictionary = { }
var _pending_full_texture_index: int = 0
var _pending_patch_packet: Dictionary = { }
var _pending_patch_solver_method: StringName = &""
var _pending_patch_texture_index: int = 0
var _pending_patch_intersection_px: Rect2i = Rect2i(Vector2i.ZERO, Vector2i.ZERO)
var _pending_patch_src_rect_px: Rect2i = Rect2i(Vector2i.ZERO, Vector2i.ZERO)
var _pending_patch_patch_pixel_size: Vector2i = Vector2i.ZERO
var _last_patch_step_committed: bool = false


func begin_full_apply(
		packet: Dictionary,
		recipe: Resource,
		solver_method: StringName,
		chunk_layer: TerrainVisualChunkLayer,
		contact_outline_width_px: float,
) -> void:
	var pending := chunk_layer.make_pending_layer(packet, recipe, contact_outline_width_px)
	_pending_full_packet = packet
	_pending_full_recipe = recipe
	_pending_full_solver_method = solver_method
	_pending_full_layer = pending.get("layer") as ColorRect
	_pending_full_material = pending.get("material") as ShaderMaterial
	_pending_full_images = pending.get("images", { }) as Dictionary
	_pending_full_textures = pending.get("textures", { }) as Dictionary
	_pending_full_texture_index = 0
	last_full_apply_texture_count = 0


func advance_full_apply_step(chunk_layer: TerrainVisualChunkLayer, parent: Node) -> bool:
	if not has_pending_full_apply():
		return false
	var pixel_size := Vector2i(
		int(_pending_full_packet.get("pixel_width", 0)),
		int(_pending_full_packet.get("pixel_height", 0)),
	)
	var applied_count := 0
	var texture_fields: Array = TerrainVisualChunkLayer.PACKET_TEXTURE_FIELDS
	while applied_count < FULL_APPLY_TEXTURES_PER_STEP \
			and _pending_full_texture_index < texture_fields.size():
		var field_spec: Array = texture_fields[_pending_full_texture_index]
		if not chunk_layer.store_packet_texture_field(
			_pending_full_material,
			_pending_full_packet,
			pixel_size,
			field_spec,
			_pending_full_images,
			_pending_full_textures,
		):
			cancel_full_apply()
			return false
		_pending_full_texture_index += 1
		last_full_apply_texture_count = _pending_full_texture_index
		applied_count += 1

	full_apply_step_count += 1
	if _pending_full_texture_index >= texture_fields.size():
		_commit_pending_full_apply(chunk_layer, parent)
		return false
	return true


func begin_patch_apply(
		packet: Dictionary,
		solver_method: StringName,
		chunk_layer: TerrainVisualChunkLayer,
) -> bool:
	_last_patch_step_committed = false
	if not chunk_layer.has_visual_layer() or chunk_layer.last_packet.is_empty():
		return false
	var base_pixel_size := Vector2i(
		int(chunk_layer.last_packet.get("pixel_width", 0)),
		int(chunk_layer.last_packet.get("pixel_height", 0)),
	)
	var patch_pixel_size := Vector2i(
		int(packet.get("pixel_width", 0)),
		int(packet.get("pixel_height", 0)),
	)
	if base_pixel_size.x <= 0 \
			or base_pixel_size.y <= 0 \
			or patch_pixel_size.x <= 0 \
			or patch_pixel_size.y <= 0:
		return false
	var tile_size_px := int(
		chunk_layer.last_packet.get("tile_size_px", WorldRuntimeConstants.TILE_SIZE_PX),
	)
	var base_origin: Vector2i = (
		chunk_layer.last_packet.get("world_origin_tile", Vector2i.ZERO) as Vector2i
	)
	var patch_origin: Vector2i = packet.get("world_origin_tile", Vector2i.ZERO) as Vector2i
	var dst_offset_px := (patch_origin - base_origin) * tile_size_px
	var dst_rect := Rect2i(dst_offset_px, patch_pixel_size)
	var intersection := dst_rect.intersection(Rect2i(Vector2i.ZERO, base_pixel_size))
	if intersection.size.x <= 0 or intersection.size.y <= 0:
		return false
	_pending_patch_packet = packet
	_pending_patch_solver_method = solver_method
	_pending_patch_texture_index = 0
	_pending_patch_intersection_px = intersection
	_pending_patch_src_rect_px = Rect2i(intersection.position - dst_offset_px, intersection.size)
	_pending_patch_patch_pixel_size = patch_pixel_size
	return true


func advance_patch_apply_step(
		chunk_layer: TerrainVisualChunkLayer,
		solve_queue: Object,
) -> Dictionary:
	_last_patch_step_committed = false
	if not has_pending_patch_apply():
		return { "has_more": false, "committed": false, "failed": false }
	var texture_fields: Array = TerrainVisualChunkLayer.PACKET_TEXTURE_FIELDS
	if _pending_patch_texture_index >= texture_fields.size():
		_commit_pending_patch_apply(chunk_layer)
		return { "has_more": false, "committed": true, "failed": false }
	var field_spec: Array = texture_fields[_pending_patch_texture_index]
	if not chunk_layer.copy_patch_packet_field(
		_pending_patch_packet,
		field_spec,
		_pending_patch_patch_pixel_size,
		_pending_patch_intersection_px,
		_pending_patch_src_rect_px,
		solve_queue,
	):
		cancel_patch_apply()
		return { "has_more": false, "committed": false, "failed": true }
	_pending_patch_texture_index += 1
	if _pending_patch_texture_index >= texture_fields.size():
		_commit_pending_patch_apply(chunk_layer)
		return { "has_more": false, "committed": true, "failed": false }
	return { "has_more": true, "committed": false, "failed": false }


func cancel_full_apply() -> void:
	var had_pending_full_apply := has_pending_full_apply()
	if _pending_full_layer != null and is_instance_valid(_pending_full_layer):
		_pending_full_layer.free()
	_pending_full_packet = { }
	_pending_full_recipe = null
	_pending_full_solver_method = &""
	_pending_full_layer = null
	_pending_full_material = null
	_pending_full_images.clear()
	_pending_full_textures.clear()
	_pending_full_texture_index = 0
	if had_pending_full_apply:
		last_full_apply_texture_count = 0


func cancel_patch_apply() -> void:
	_pending_patch_solver_method = &""
	_pending_patch_packet = { }
	_pending_patch_texture_index = 0
	_pending_patch_intersection_px = Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	_pending_patch_src_rect_px = Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	_pending_patch_patch_pixel_size = Vector2i.ZERO


func has_pending_full_apply() -> bool:
	return not _pending_full_packet.is_empty() \
			and _pending_full_layer != null \
			and is_instance_valid(_pending_full_layer) \
			and _pending_full_material != null


func has_pending_patch_apply() -> bool:
	return not _pending_patch_packet.is_empty()


func pending_full_texture_index() -> int:
	return _pending_full_texture_index


func pending_full_chunk_coord() -> Vector2i:
	return _pending_full_packet.get("chunk_coord", Vector2i.ZERO) as Vector2i


func pending_patch_texture_index() -> int:
	return _pending_patch_texture_index


func _commit_pending_full_apply(chunk_layer: TerrainVisualChunkLayer, parent: Node) -> void:
	if not has_pending_full_apply():
		return
	chunk_layer.commit_full(
		parent,
		_pending_full_layer,
		_pending_full_images,
		_pending_full_textures,
		_pending_full_packet,
		_pending_full_solver_method,
	)
	_pending_full_packet = { }
	_pending_full_recipe = null
	_pending_full_solver_method = &""
	_pending_full_layer = null
	_pending_full_material = null
	_pending_full_images = { }
	_pending_full_textures = { }
	_pending_full_texture_index = 0


func _commit_pending_patch_apply(chunk_layer: TerrainVisualChunkLayer) -> void:
	var patch_origin: Vector2i = _pending_patch_packet.get(
		"world_origin_tile",
		Vector2i.ZERO,
	) as Vector2i
	last_patch_world_origin_tile = patch_origin
	last_patch_pixel_size = _pending_patch_patch_pixel_size
	last_patch_intersection_px = _pending_patch_intersection_px
	chunk_layer.last_solver_method = _pending_patch_solver_method
	patch_apply_count += 1
	_last_patch_step_committed = true
	cancel_patch_apply()
