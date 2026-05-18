class_name TerrainVisualRuntimePresenter
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const TerrainVisualRecipePayload = preload(
	"res://data/terrain_visual/terrain_visual_recipe_payload.gd"
)
const TerrainVisualPacketBackend = preload(
	"res://core/systems/world/terrain_visual_packet_backend.gd"
)
const TerrainVisualApplyMachine = preload(
	"res://core/systems/world/terrain_visual_apply_machine.gd"
)
const TerrainVisualChunkLayer = preload("res://core/systems/world/terrain_visual_chunk_layer.gd")
const TerrainVisualMaskBuilder = preload("res://core/systems/world/terrain_visual_mask_builder.gd")
const TerrainVisualSolveQueue = preload("res://core/systems/world/terrain_visual_solve_queue.gd")

var _solve_queue: TerrainVisualSolveQueue = TerrainVisualSolveQueue.new()
var _mask_builder: TerrainVisualMaskBuilder = TerrainVisualMaskBuilder.new()
var _chunk_layer: TerrainVisualChunkLayer = TerrainVisualChunkLayer.new()
var _apply_machine: TerrainVisualApplyMachine = TerrainVisualApplyMachine.new()
var _last_packet: Dictionary = { }
var _packet_images: Dictionary = { }
var _packet_textures: Dictionary = { }
var _pending_full_solve_request_id: int = 0
var _pending_full_solve_recipe: Resource = null
var _pending_patch_solve_request_id: int = 0
var _last_patch_solve_usec: int = 0
var _last_dirty_rect_tiles: Rect2i = Rect2i(Vector2i.ZERO, Vector2i.ZERO)
var _full_solve_count: int = 0
var _full_solve_request_count: int = 0
var _last_full_solve_usec: int = 0
var _dirty_mark_count: int = 0
var _patch_solve_count: int = 0
var _has_pending_dirty_patch: bool = false
var _enabled: bool = false
var _recipe: Resource = null
var _seed: int = 0


func _exit_tree() -> void:
	clear()
	_solve_queue.release()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not _enabled:
		clear()


func set_recipe(recipe: Resource) -> void:
	if _recipe != recipe:
		_cancel_pending_full_solve()
		_apply_machine.cancel_full_apply()
		_cancel_pending_patch_solve()
		_apply_machine.cancel_patch_apply()
	_recipe = recipe


func set_packet_backend(packet_backend: TerrainVisualPacketBackend) -> void:
	if _solve_queue.has_packet_backend(packet_backend):
		return
	_cancel_pending_full_solve()
	_cancel_pending_patch_solve()
	_solve_queue.set_packet_backend(packet_backend)


func set_chunk_solid_halo(solid_halo: PackedByteArray) -> void:
	if not _mask_builder.set_chunk_solid_halo(solid_halo):
		return
	_cancel_pending_full_solve()
	_apply_machine.cancel_full_apply()
	_cancel_pending_patch_solve()
	_apply_machine.cancel_patch_apply()


func set_world_wrap_width_tiles(width_tiles: int) -> void:
	if not _solve_queue.set_world_wrap_width_tiles(width_tiles):
		return
	_cancel_pending_full_solve()
	_apply_machine.cancel_full_apply()
	_cancel_pending_patch_solve()
	_apply_machine.cancel_patch_apply()


func is_enabled() -> bool:
	return _enabled and _recipe != null


func is_ready() -> bool:
	return _chunk_layer.is_ready() \
			and not _has_pending_full_solve() \
			and not _apply_machine.has_pending_full_apply()


func begin_chunk_apply(packet: Dictionary) -> void:
	_seed = int(packet.get("world_seed", 0))
	if _seed == 0 and _recipe != null:
		_seed = int(_recipe.get("default_seed"))
	if is_enabled():
		clear()
		_has_pending_dirty_patch = false


func apply_full_pending(
		chunk_coord: Vector2i,
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
) -> bool:
	if _has_pending_full_solve():
		return _advance_pending_full_solve()
	if _apply_machine.has_pending_full_apply():
		return _advance_pending_full_apply_step()
	return apply_full_chunk(
		{
			"chunk_coord": chunk_coord,
			"mountain_id_per_tile": mountain_ids,
			"mountain_flags": mountain_flags,
		},
		_recipe,
		_seed,
	)


func apply_full_chunk(packet: Dictionary, recipe: Resource, seed: int) -> bool:
	_cancel_pending_full_solve()
	_apply_machine.cancel_full_apply()
	_cancel_pending_patch_solve()
	_apply_machine.cancel_patch_apply()
	_has_pending_dirty_patch = false
	if recipe == null:
		push_error("Terrain visual V2 runtime presenter requires a TerrainVisualRecipe.")
		return false

	var mask_result: Dictionary = { }
	if _mask_builder.has_valid_chunk_solid_halo():
		mask_result = _mask_builder.build_solid_mask_with_halo(packet)
	else:
		mask_result = _mask_builder.build_solid_mask(packet)
	if int(mask_result.get("solid_count", 0)) <= 0:
		clear()
		return false

	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var request_id := _queue_solve_request(
		mask_result,
		chunk_coord,
		recipe,
		seed,
		TerrainVisualPacketBackend.FULL_SOLVE_PRIORITY,
	)
	if request_id <= 0:
		return false
	_pending_full_solve_request_id = request_id
	_pending_full_solve_recipe = recipe
	_full_solve_request_count += 1
	return true


func mark_dirty_patch(local_coord: Vector2i) -> void:
	_cancel_pending_full_solve()
	_apply_machine.cancel_full_apply()
	_cancel_pending_patch_solve()
	_apply_machine.cancel_patch_apply()
	var min_coord := Vector2i(
		clampi(local_coord.x - 1, 0, WorldRuntimeConstants.CHUNK_SIZE - 1),
		clampi(local_coord.y - 1, 0, WorldRuntimeConstants.CHUNK_SIZE - 1),
	)
	var max_coord := Vector2i(
		clampi(local_coord.x + 1, 0, WorldRuntimeConstants.CHUNK_SIZE - 1),
		clampi(local_coord.y + 1, 0, WorldRuntimeConstants.CHUNK_SIZE - 1),
	)
	var dirty_rect := Rect2i(min_coord, max_coord - min_coord + Vector2i.ONE)
	if _has_pending_dirty_patch:
		dirty_rect = _mask_builder.merge_rects(_last_dirty_rect_tiles, dirty_rect)
	_last_dirty_rect_tiles = dirty_rect
	_dirty_mark_count += 1
	_has_pending_dirty_patch = true


func apply_dirty_patch(
		chunk_coord: Vector2i,
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
) -> bool:
	if not is_enabled():
		return false

	if _has_pending_patch_solve():
		return _advance_pending_patch_solve()
	if _apply_machine.has_pending_patch_apply():
		return _advance_pending_patch_apply_step()

	if _chunk_layer.last_packet.is_empty():
		if _has_pending_full_solve() or _apply_machine.has_pending_full_apply():
			return apply_full_pending(chunk_coord, mountain_ids, mountain_flags)
		if not _has_pending_dirty_patch:
			return false
		_has_pending_dirty_patch = false
		return apply_full_chunk(
			{
				"chunk_coord": chunk_coord,
				"mountain_id_per_tile": mountain_ids,
				"mountain_flags": mountain_flags,
			},
			_recipe,
			_seed,
		)

	if not _has_pending_dirty_patch:
		return false

	if _has_pending_full_solve():
		_cancel_pending_full_solve()
	if _apply_machine.has_pending_full_apply():
		_apply_machine.cancel_full_apply()
	var mask_result := (
		_mask_builder.build_solid_mask_with_halo_for_output_rect(
			mountain_ids,
			mountain_flags,
			_last_dirty_rect_tiles,
		)
		if _mask_builder.has_valid_chunk_solid_halo()
		else _mask_builder.build_solid_mask_for_rect(
			mountain_ids,
			mountain_flags,
			_last_dirty_rect_tiles,
		)
	)
	if int(mask_result.get("width_tiles", 0)) <= 0 \
			or int(mask_result.get("height_tiles", 0)) <= 0:
		return false

	var request_id := _queue_solve_request(
		mask_result,
		chunk_coord,
		_recipe,
		_seed,
		TerrainVisualPacketBackend.PATCH_SOLVE_PRIORITY,
	)
	if request_id <= 0:
		return false
	_pending_patch_solve_request_id = request_id
	return true


func clear() -> void:
	_cancel_pending_full_solve()
	_apply_machine.cancel_full_apply()
	_cancel_pending_patch_solve()
	_apply_machine.cancel_patch_apply()
	_chunk_layer.clear()
	_sync_legacy_readback_fields()
	_apply_machine.last_full_apply_texture_count = 0
	_has_pending_dirty_patch = false


func get_debug_state() -> Dictionary:
	return {
		"enabled": _enabled,
		"recipe_id": TerrainVisualRecipePayload.recipe_id(_recipe),
		"ready": _chunk_layer.is_ready(),
		"has_visual_layer": _chunk_layer.has_visual_layer(),
		"chunk_coord": _chunk_layer.last_packet.get("chunk_coord", Vector2i.ZERO),
		"world_origin_tile": _chunk_layer.last_packet.get("world_origin_tile", Vector2i.ZERO),
		"tile_size_px": int(_chunk_layer.last_packet.get("tile_size_px", 0)),
		"pixel_width": int(_chunk_layer.last_packet.get("pixel_width", 0)),
		"pixel_height": int(_chunk_layer.last_packet.get("pixel_height", 0)),
		"full_solve_count": _full_solve_count,
		"full_solve_request_count": _full_solve_request_count,
		"last_full_solve_usec": _last_full_solve_usec,
		"has_pending_full_solve": _has_pending_full_solve(),
		"pending_full_solve_request_id": _pending_full_solve_request_id,
		"full_apply_step_count": _apply_machine.full_apply_step_count,
		"full_apply_texture_count": _apply_machine.last_full_apply_texture_count,
		"full_apply_texture_total": _chunk_layer.texture_field_count(),
		"full_apply_texture_budget": TerrainVisualApplyMachine.FULL_APPLY_TEXTURES_PER_STEP,
		"pending_full_texture_index": _apply_machine.pending_full_texture_index(),
		"pending_full_chunk_coord": _apply_machine.pending_full_chunk_coord(),
		"dirty_mark_count": _dirty_mark_count,
		"patch_solve_count": _patch_solve_count,
		"patch_apply_count": _apply_machine.patch_apply_count,
		"last_patch_solve_usec": _last_patch_solve_usec,
		"has_pending_patch_solve": _has_pending_patch_solve(),
		"pending_patch_solve_request_id": _pending_patch_solve_request_id,
		"has_pending_patch_apply": _apply_machine.has_pending_patch_apply(),
		"pending_patch_texture_index": _apply_machine.pending_patch_texture_index(),
		"last_dirty_rect_tiles": _last_dirty_rect_tiles,
		"last_patch_world_origin_tile": _apply_machine.last_patch_world_origin_tile,
		"last_patch_pixel_size": _apply_machine.last_patch_pixel_size,
		"last_patch_intersection_px": _apply_machine.last_patch_intersection_px,
		"last_solver_method": _chunk_layer.last_solver_method,
		"has_chunk_solid_halo": _mask_builder.has_valid_chunk_solid_halo(),
		"has_pending_full_apply": _apply_machine.has_pending_full_apply(),
		"has_pending_dirty_patch": _has_pending_dirty_patch,
		"shader_path": TerrainVisualChunkLayer.PACKET_SHADER_PATH,
	}


func is_packet_solid_at_world(world_pos: Vector2) -> bool:
	return _chunk_layer.sample_world_solid(world_pos)


func _advance_pending_full_solve() -> bool:
	if not _has_pending_full_solve():
		return false
	var result := _solve_queue.take_completed_request(_pending_full_solve_request_id)
	if result.is_empty():
		return true
	var solve_recipe := _pending_full_solve_recipe
	_pending_full_solve_request_id = 0
	_pending_full_solve_recipe = null
	if not bool(result.get("success", false)):
		push_error(str(result.get("message", "Terrain visual full solve failed.")))
		return false
	var visual_packet: Dictionary = result.get("packet", { }) as Dictionary
	if visual_packet.is_empty():
		return false
	_full_solve_count += 1
	_last_full_solve_usec = int(result.get("solve_usec", 0))
	_apply_machine.begin_full_apply(
		visual_packet,
		solve_recipe,
		result.get("solver_method", &"") as StringName,
		_chunk_layer,
		_solve_queue.runtime_scaled_recipe_px(solve_recipe, &"contact_outline_width_px"),
	)
	return _advance_pending_full_apply_step()


func _advance_pending_patch_solve() -> bool:
	if not _has_pending_patch_solve():
		return false
	var result := _solve_queue.take_completed_request(_pending_patch_solve_request_id)
	if result.is_empty():
		return true
	_pending_patch_solve_request_id = 0
	if not bool(result.get("success", false)):
		push_error(str(result.get("message", "Terrain visual patch solve failed.")))
		return false
	var visual_packet: Dictionary = result.get("packet", { }) as Dictionary
	if visual_packet.is_empty():
		return false
	_patch_solve_count += 1
	_last_patch_solve_usec = int(result.get("solve_usec", 0))
	if not _apply_machine.begin_patch_apply(
		visual_packet,
		result.get("solver_method", &"") as StringName,
		_chunk_layer,
	):
		return false
	return _advance_pending_patch_apply_step()


func _cancel_pending_full_solve() -> void:
	_solve_queue.cancel_request(_pending_full_solve_request_id)
	_pending_full_solve_request_id = 0
	_pending_full_solve_recipe = null


func _cancel_pending_patch_solve() -> void:
	_solve_queue.cancel_request(_pending_patch_solve_request_id)
	_pending_patch_solve_request_id = 0


func _advance_pending_full_apply_step() -> bool:
	var has_more := _apply_machine.advance_full_apply_step(_chunk_layer, self)
	_sync_legacy_readback_fields()
	return has_more


func _advance_pending_patch_apply_step() -> bool:
	var patch_result := _apply_machine.advance_patch_apply_step(_chunk_layer, _solve_queue)
	_sync_legacy_readback_fields()
	if bool(patch_result.get("committed", false)):
		_has_pending_dirty_patch = false
	return bool(patch_result.get("has_more", false))


func _sync_legacy_readback_fields() -> void:
	_last_packet = _chunk_layer.last_packet
	_packet_images = _chunk_layer.packet_images
	_packet_textures = _chunk_layer.packet_textures


func _has_pending_full_solve() -> bool:
	return _pending_full_solve_request_id > 0


func _has_pending_patch_solve() -> bool:
	return _pending_patch_solve_request_id > 0


func _queue_solve_request(
		mask_result: Dictionary,
		chunk_coord: Vector2i,
		recipe: Resource,
		seed: int,
		priority: int,
) -> int:
	return _solve_queue.queue_solve_request(mask_result, chunk_coord, recipe, seed, priority)
