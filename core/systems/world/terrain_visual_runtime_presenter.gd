class_name TerrainVisualRuntimePresenter
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const TerrainVisualPacketMaterial = preload(
	"res://data/terrain_visual/terrain_visual_packet_material.gd"
)
const TerrainVisualRecipePayload = preload(
	"res://data/terrain_visual/terrain_visual_recipe_payload.gd"
)

const DEBUG_MODE_ALBEDO := 0
const ROCK_FILL_Z_INDEX := 11
const PACKET_SHADER_PATH := "res://assets/shaders/terrain_visual_packet.gdshader"
const PACKET_TEXTURE_FIELDS := [
	["zone_ids", "zone_texture", Image.FORMAT_R8, 1],
	["coverage_top", "coverage_top_texture", Image.FORMAT_R8, 1],
	["coverage_edge", "coverage_edge_texture", Image.FORMAT_R8, 1],
	["coverage_face", "coverage_face_texture", Image.FORMAT_R8, 1],
	["coverage_back", "coverage_back_texture", Image.FORMAT_R8, 1],
	["height_q16", "height_texture", Image.FORMAT_RG8, 2],
	["normal_rgba8", "normal_texture", Image.FORMAT_RGBA8, 4],
	["material_u_q16", "material_u_texture", Image.FORMAT_RG8, 2],
	["material_v_q16", "material_v_texture", Image.FORMAT_RG8, 2],
]

var _solver: Object = null
var _packet_layer: ColorRect = null
var _last_packet: Dictionary = { }
var _packet_images: Dictionary = { }
var _packet_textures: Dictionary = { }
var _last_dirty_rect_tiles: Rect2i = Rect2i(Vector2i.ZERO, Vector2i.ZERO)
var _last_patch_world_origin_tile: Vector2i = Vector2i.ZERO
var _last_patch_pixel_size: Vector2i = Vector2i.ZERO
var _last_patch_intersection_px: Rect2i = Rect2i(Vector2i.ZERO, Vector2i.ZERO)
var _full_solve_count: int = 0
var _dirty_mark_count: int = 0
var _patch_solve_count: int = 0
var _patch_apply_count: int = 0
var _has_pending_dirty_patch: bool = false
var _did_warn_missing_solver: bool = false
var _enabled: bool = false
var _recipe: Resource = null
var _seed: int = 0


func _exit_tree() -> void:
	clear()
	if _solver != null:
		_solver.free()
	_solver = null


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not _enabled:
		clear()


func set_recipe(recipe: Resource) -> void:
	_recipe = recipe


func is_enabled() -> bool:
	return _enabled and _recipe != null


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
	clear()
	_has_pending_dirty_patch = false
	if recipe == null:
		push_error("Terrain visual V2 runtime presenter requires a TerrainVisualRecipe.")
		return false

	var mask_result := _build_solid_mask(packet)
	if int(mask_result.get("solid_count", 0)) <= 0:
		return true

	var solver := _ensure_solver()
	if solver == null:
		return false
	if not solver.has_method("build_chunk_visual_packet"):
		push_error(
			"TerrainVisualSolver.build_chunk_visual_packet is required for runtime V2 chunks.",
		)
		return false

	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var visual_packet: Dictionary = solver.call(
		"build_chunk_visual_packet",
		mask_result.get("solid_mask", PackedByteArray()) as PackedByteArray,
		int(mask_result.get("width_tiles", 0)),
		int(mask_result.get("height_tiles", 0)),
		TerrainVisualRecipePayload.make_payload(recipe),
		chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + (
			mask_result.get("origin_local", Vector2i.ZERO) as Vector2i
		),
		chunk_coord,
		seed,
	)
	if visual_packet.is_empty():
		return false

	_last_packet = visual_packet
	_full_solve_count += 1
	_apply_packet_material(visual_packet, recipe)
	return true


func mark_dirty_patch(local_coord: Vector2i) -> void:
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
		dirty_rect = _merge_rects(_last_dirty_rect_tiles, dirty_rect)
	_last_dirty_rect_tiles = dirty_rect
	_dirty_mark_count += 1
	_has_pending_dirty_patch = true


func apply_dirty_patch(
		chunk_coord: Vector2i,
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
) -> bool:
	if not is_enabled() or not _has_pending_dirty_patch or _last_packet.is_empty():
		return false
	var solver := _ensure_solver()
	if solver == null:
		return false
	if not solver.has_method("build_chunk_visual_packet"):
		push_error(
			"TerrainVisualSolver.build_chunk_visual_packet is required for V2 dirty patches.",
		)
		return false

	var mask_result := _build_solid_mask_for_rect(
		mountain_ids,
		mountain_flags,
		_last_dirty_rect_tiles,
	)
	if int(mask_result.get("width_tiles", 0)) <= 0 \
			or int(mask_result.get("height_tiles", 0)) <= 0:
		return false

	var origin_local: Vector2i = mask_result.get("origin_local", Vector2i.ZERO) as Vector2i
	var visual_packet: Dictionary = solver.call(
		"build_chunk_visual_packet",
		mask_result.get("solid_mask", PackedByteArray()) as PackedByteArray,
		int(mask_result.get("width_tiles", 0)),
		int(mask_result.get("height_tiles", 0)),
		TerrainVisualRecipePayload.make_payload(_recipe),
		chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + origin_local,
		chunk_coord,
		_seed,
	)
	_patch_solve_count += 1
	if visual_packet.is_empty():
		return false
	if not _copy_patch_packet_to_current_textures(visual_packet):
		return false
	_patch_apply_count += 1
	_has_pending_dirty_patch = false
	return true


func clear() -> void:
	if _packet_layer != null and is_instance_valid(_packet_layer):
		_packet_layer.queue_free()
	_packet_layer = null
	_last_packet = { }
	_packet_images.clear()
	_packet_textures.clear()


func get_debug_state() -> Dictionary:
	return {
		"enabled": _enabled,
		"recipe_id": TerrainVisualRecipePayload.recipe_id(_recipe),
		"ready": not _last_packet.is_empty(),
		"has_visual_layer": _packet_layer != null and is_instance_valid(_packet_layer),
		"chunk_coord": _last_packet.get("chunk_coord", Vector2i.ZERO),
		"world_origin_tile": _last_packet.get("world_origin_tile", Vector2i.ZERO),
		"pixel_width": int(_last_packet.get("pixel_width", 0)),
		"pixel_height": int(_last_packet.get("pixel_height", 0)),
		"full_solve_count": _full_solve_count,
		"dirty_mark_count": _dirty_mark_count,
		"patch_solve_count": _patch_solve_count,
		"patch_apply_count": _patch_apply_count,
		"last_dirty_rect_tiles": _last_dirty_rect_tiles,
		"last_patch_world_origin_tile": _last_patch_world_origin_tile,
		"last_patch_pixel_size": _last_patch_pixel_size,
		"last_patch_intersection_px": _last_patch_intersection_px,
		"has_pending_dirty_patch": _has_pending_dirty_patch,
		"shader_path": PACKET_SHADER_PATH,
	}


func _apply_packet_material(packet: Dictionary, recipe: Resource) -> void:
	_packet_layer = ColorRect.new()
	_packet_layer.name = "TerrainVisualV2PacketLayer"
	_packet_layer.color = Color.WHITE
	_packet_layer.size = Vector2(
		float(packet.get("pixel_width", 0)),
		float(packet.get("pixel_height", 0)),
	)
	_packet_layer.z_index = ROCK_FILL_Z_INDEX
	var material: ShaderMaterial = TerrainVisualPacketMaterial.new().build_material(
		packet,
		DEBUG_MODE_ALBEDO,
		recipe,
	)
	material.set_shader_parameter("base_source", 2)
	material.set_shader_parameter("base_flat_color", Color(0.0, 0.0, 0.0, 0.0))
	_store_mutable_packet_textures(material, packet)
	_packet_layer.material = material
	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var world_origin_tile: Vector2i = packet.get("world_origin_tile", Vector2i.ZERO) as Vector2i
	_packet_layer.position = Vector2(
		float(world_origin_tile.x - chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE),
		float(world_origin_tile.y - chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE),
	) * float(WorldRuntimeConstants.TILE_SIZE_PX)
	add_child(_packet_layer)


func _store_mutable_packet_textures(material: ShaderMaterial, packet: Dictionary) -> void:
	_packet_images.clear()
	_packet_textures.clear()
	var pixel_size := Vector2i(
		int(packet.get("pixel_width", 0)),
		int(packet.get("pixel_height", 0)),
	)
	for field_spec: Array in PACKET_TEXTURE_FIELDS:
		var field_name := field_spec[0] as String
		var shader_name := field_spec[1] as String
		var image := _make_packet_image(
			packet,
			field_name,
			pixel_size,
			int(field_spec[2]),
			int(field_spec[3]),
		)
		if image == null:
			continue
		var texture := ImageTexture.create_from_image(image)
		_packet_images[field_name] = image
		_packet_textures[field_name] = texture
		material.set_shader_parameter(shader_name, texture)


func _copy_patch_packet_to_current_textures(patch_packet: Dictionary) -> bool:
	if _packet_layer == null or not is_instance_valid(_packet_layer):
		return false
	var base_pixel_size := Vector2i(
		int(_last_packet.get("pixel_width", 0)),
		int(_last_packet.get("pixel_height", 0)),
	)
	var patch_pixel_size := Vector2i(
		int(patch_packet.get("pixel_width", 0)),
		int(patch_packet.get("pixel_height", 0)),
	)
	var tile_size_px := int(_last_packet.get("tile_size_px", WorldRuntimeConstants.TILE_SIZE_PX))
	var base_origin: Vector2i = _last_packet.get("world_origin_tile", Vector2i.ZERO) as Vector2i
	var patch_origin: Vector2i = patch_packet.get("world_origin_tile", Vector2i.ZERO) as Vector2i
	var dst_offset_px := (patch_origin - base_origin) * tile_size_px
	var dst_rect := Rect2i(dst_offset_px, patch_pixel_size)
	var intersection := dst_rect.intersection(Rect2i(Vector2i.ZERO, base_pixel_size))
	if intersection.size.x <= 0 or intersection.size.y <= 0:
		return false

	for field_spec: Array in PACKET_TEXTURE_FIELDS:
		var field_name := field_spec[0] as String
		var shader_name := field_spec[1] as String
		var dst_image := _packet_images.get(field_name) as Image
		if dst_image == null:
			return false
		var src_image := _make_packet_image(
			patch_packet,
			field_name,
			patch_pixel_size,
			int(field_spec[2]),
			int(field_spec[3]),
		)
		if src_image == null:
			return false
		var src_rect := Rect2i(intersection.position - dst_offset_px, intersection.size)
		dst_image.blit_rect(src_image, src_rect, intersection.position)
		var dst_texture := ImageTexture.create_from_image(dst_image)
		_packet_textures[field_name] = dst_texture
		(_packet_layer.material as ShaderMaterial).set_shader_parameter(shader_name, dst_texture)

	_last_patch_world_origin_tile = patch_origin
	_last_patch_pixel_size = patch_pixel_size
	_last_patch_intersection_px = intersection
	return true


func _make_packet_image(
		packet: Dictionary,
		field_name: String,
		pixel_size: Vector2i,
		image_format: int,
		bytes_per_pixel: int,
) -> Image:
	var bytes: PackedByteArray = packet.get(field_name, PackedByteArray())
	var expected_size := pixel_size.x * pixel_size.y * bytes_per_pixel
	if bytes.size() != expected_size:
		push_error(
			"TerrainVisualRuntimePresenter field %s has %d bytes, expected %d."
			% [field_name, bytes.size(), expected_size],
		)
		return null
	return Image.create_from_data(pixel_size.x, pixel_size.y, false, image_format, bytes)


func _merge_rects(first: Rect2i, second: Rect2i) -> Rect2i:
	var min_coord := Vector2i(
		mini(first.position.x, second.position.x),
		mini(first.position.y, second.position.y),
	)
	var first_end := first.position + first.size
	var second_end := second.position + second.size
	var max_coord := Vector2i(maxi(first_end.x, second_end.x), maxi(first_end.y, second_end.y))
	return Rect2i(min_coord, max_coord - min_coord)


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


func _build_solid_mask(packet: Dictionary) -> Dictionary:
	var mask := PackedByteArray()
	var mountain_ids: PackedInt32Array = packet.get(
		"mountain_id_per_tile",
		PackedInt32Array(),
	) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get(
		"mountain_flags",
		PackedByteArray(),
	) as PackedByteArray
	if mountain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return { "solid_mask": mask, "solid_count": 0 }

	var min_coord := Vector2i(WorldRuntimeConstants.CHUNK_SIZE, WorldRuntimeConstants.CHUNK_SIZE)
	var max_coord := Vector2i(-1, -1)
	var solid_count := 0
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var flags: int = int(mountain_flags[index])
		if int(mountain_ids[index]) <= 0:
			continue
		if (
			flags
			& (WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT)
		) == 0:
			continue
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		min_coord.x = mini(min_coord.x, local_coord.x)
		min_coord.y = mini(min_coord.y, local_coord.y)
		max_coord.x = maxi(max_coord.x, local_coord.x)
		max_coord.y = maxi(max_coord.y, local_coord.y)
		solid_count += 1
	if solid_count <= 0:
		return { "solid_mask": mask, "solid_count": 0 }

	var bounds_size: Vector2i = max_coord - min_coord + Vector2i.ONE
	mask.resize(bounds_size.x * bounds_size.y)
	for y: int in range(min_coord.y, max_coord.y + 1):
		for x: int in range(min_coord.x, max_coord.x + 1):
			var source_index := WorldRuntimeConstants.local_to_index(Vector2i(x, y))
			var source_flags: int = int(mountain_flags[source_index])
			if int(mountain_ids[source_index]) <= 0:
				continue
			var source_surface_flags := (
				WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
			)
			if (source_flags & source_surface_flags) == 0:
				continue
			var mask_index := (y - min_coord.y) * bounds_size.x + (x - min_coord.x)
			mask[mask_index] = 1
	return {
		"solid_mask": mask,
		"solid_count": solid_count,
		"origin_local": min_coord,
		"width_tiles": bounds_size.x,
		"height_tiles": bounds_size.y,
	}


func _build_solid_mask_for_rect(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		dirty_rect: Rect2i,
) -> Dictionary:
	var mask := PackedByteArray()
	if mountain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or dirty_rect.size.x <= 0 \
			or dirty_rect.size.y <= 0:
		return { "solid_mask": mask, "solid_count": 0 }

	mask.resize(dirty_rect.size.x * dirty_rect.size.y)
	var solid_count := 0
	for y: int in range(dirty_rect.position.y, dirty_rect.end.y):
		for x: int in range(dirty_rect.position.x, dirty_rect.end.x):
			var local_coord := Vector2i(x, y)
			var source_index := WorldRuntimeConstants.local_to_index(local_coord)
			var source_flags: int = int(mountain_flags[source_index])
			if int(mountain_ids[source_index]) <= 0:
				continue
			var source_surface_flags := (
				WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
			)
			if (source_flags & source_surface_flags) == 0:
				continue
			var mask_index := (y - dirty_rect.position.y) * dirty_rect.size.x + (
				x - dirty_rect.position.x
			)
			mask[mask_index] = 1
			solid_count += 1
	return {
		"solid_mask": mask,
		"solid_count": solid_count,
		"origin_local": dirty_rect.position,
		"width_tiles": dirty_rect.size.x,
		"height_tiles": dirty_rect.size.y,
	}
