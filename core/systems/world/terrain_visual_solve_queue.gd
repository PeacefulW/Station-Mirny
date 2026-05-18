class_name TerrainVisualSolveQueue
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const TerrainVisualRecipePayload = preload(
	"res://data/terrain_visual/terrain_visual_recipe_payload.gd"
)
const TerrainVisualPacketBackend = preload(
	"res://core/systems/world/terrain_visual_packet_backend.gd"
)

const RUNTIME_PACKET_TILE_SIZE_PX := 32

var _solver: Object = null
var _packet_backend: TerrainVisualPacketBackend = null
var _owns_packet_backend: bool = false
var _did_warn_missing_solver: bool = false
var _world_wrap_width_tiles: int = 0


func release() -> void:
	_release_owned_packet_backend()
	if _solver != null:
		_solver.free()
	_solver = null


func set_packet_backend(packet_backend: TerrainVisualPacketBackend) -> void:
	if _packet_backend == packet_backend:
		return
	_release_owned_packet_backend()
	_packet_backend = packet_backend
	_owns_packet_backend = false


func has_packet_backend(packet_backend: TerrainVisualPacketBackend) -> bool:
	return _packet_backend == packet_backend


func set_world_wrap_width_tiles(width_tiles: int) -> bool:
	width_tiles = maxi(0, width_tiles)
	if _world_wrap_width_tiles == width_tiles:
		return false
	_world_wrap_width_tiles = width_tiles
	return true


func queue_solve_request(
		mask_result: Dictionary,
		chunk_coord: Vector2i,
		recipe: Resource,
		seed: int,
) -> int:
	var recipe_payload := _make_runtime_recipe_payload(recipe)
	var input_origin_local: Vector2i = (
		mask_result.get(
			"input_origin_local",
			mask_result.get("origin_local", Vector2i.ZERO),
		) as Vector2i
	)
	var output_rect: Rect2i = (
		mask_result.get("output_rect_tiles", Rect2i(Vector2i.ZERO, Vector2i.ZERO)) as Rect2i
	)
	return _ensure_packet_backend().queue_chunk_visual_packet_request(
		mask_result.get("solid_mask", PackedByteArray()) as PackedByteArray,
		int(mask_result.get("width_tiles", 0)),
		int(mask_result.get("height_tiles", 0)),
		recipe_payload,
		chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + input_origin_local,
		chunk_coord,
		seed,
		bool(mask_result.get("uses_halo", false)),
		output_rect,
	)


func take_completed_request(request_id: int) -> Dictionary:
	if _packet_backend == null:
		return { }
	return _packet_backend.take_completed_request(request_id)


func cancel_request(request_id: int) -> void:
	if request_id > 0 and _packet_backend != null:
		_packet_backend.cancel_request(request_id)


func runtime_scaled_recipe_px(recipe: Resource, property_name: StringName) -> float:
	if recipe == null:
		return 0.0
	var authored_tile_size_px := int(recipe.get("tile_size_px"))
	if authored_tile_size_px <= 0:
		authored_tile_size_px = WorldRuntimeConstants.TILE_SIZE_PX
	var runtime_scale := float(RUNTIME_PACKET_TILE_SIZE_PX) / float(authored_tile_size_px)
	return maxf(0.0, float(recipe.get(property_name)) * runtime_scale)


func copy_patch_field_bytes(
		dst_bytes: PackedByteArray,
		src_bytes: PackedByteArray,
		base_pixel_size: Vector2i,
		patch_pixel_size: Vector2i,
		dst_rect: Rect2i,
		src_rect: Rect2i,
		bytes_per_pixel: int,
) -> PackedByteArray:
	var solver := _ensure_solver()
	if solver == null or not solver.has_method("copy_patch_field_bytes"):
		push_error("TerrainVisualSolver.copy_patch_field_bytes is required for V2 patch apply.")
		return PackedByteArray()
	var patched_bytes_variant: Variant = solver.call(
		"copy_patch_field_bytes",
		dst_bytes,
		src_bytes,
		base_pixel_size,
		patch_pixel_size,
		dst_rect,
		src_rect,
		bytes_per_pixel,
	)
	if not patched_bytes_variant is PackedByteArray:
		push_error("TerrainVisualSolver.copy_patch_field_bytes returned an invalid buffer.")
		return PackedByteArray()
	return patched_bytes_variant as PackedByteArray


func _ensure_packet_backend() -> TerrainVisualPacketBackend:
	if _packet_backend != null:
		return _packet_backend
	_packet_backend = TerrainVisualPacketBackend.new()
	_packet_backend.start()
	_owns_packet_backend = true
	return _packet_backend


func _release_owned_packet_backend() -> void:
	if _packet_backend != null and _owns_packet_backend:
		_packet_backend.stop()
	_packet_backend = null
	_owns_packet_backend = false


func _ensure_solver() -> Object:
	if _solver != null and is_instance_valid(_solver):
		return _solver
	if not ClassDB.class_exists(&"TerrainVisualSolver"):
		if not _did_warn_missing_solver:
			push_error("TerrainVisualSolver native class is required for TerrainVisual V2 runtime.")
			_did_warn_missing_solver = true
		return null
	_solver = ClassDB.instantiate(&"TerrainVisualSolver")
	if _solver == null and not _did_warn_missing_solver:
		push_error("Failed to instantiate TerrainVisualSolver native class.")
		_did_warn_missing_solver = true
	return _solver


func _make_runtime_recipe_payload(recipe: Resource) -> Dictionary:
	var recipe_payload := TerrainVisualRecipePayload.make_payload(recipe)
	var authored_tile_size_px := int(
		recipe_payload.get("tile_size_px", WorldRuntimeConstants.TILE_SIZE_PX),
	)
	if authored_tile_size_px <= 0:
		authored_tile_size_px = WorldRuntimeConstants.TILE_SIZE_PX
	var runtime_scale := float(RUNTIME_PACKET_TILE_SIZE_PX) / float(authored_tile_size_px)
	recipe_payload["tile_size_px"] = RUNTIME_PACKET_TILE_SIZE_PX
	for metric_key: String in [
		"rim_width_px",
		"south_height_px",
		"north_height_px",
		"side_height_px",
		"crown_bevel_px",
		"outer_corner_radius_px",
		"inner_corner_radius_px",
		"corner_round_px",
		"diagonal_smooth_px",
		"contour_warp_px",
		"contact_outline_width_px",
		"height_to_normal_blur_radius_px",
	]:
		recipe_payload[metric_key] = float(recipe_payload.get(metric_key, 0.0)) * runtime_scale
	recipe_payload["world_wrap_width_tiles"] = _world_wrap_width_tiles
	return recipe_payload
