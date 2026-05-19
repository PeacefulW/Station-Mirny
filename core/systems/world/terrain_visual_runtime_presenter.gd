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
const RUNTIME_PACKET_TILE_SIZE_PX := 32
const PACKET_SHADER_PATH := "res://assets/shaders/terrain_visual_packet.gdshader"
const PACKET_SHADER: Shader = preload("res://assets/shaders/terrain_visual_packet.gdshader")
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
var _last_solver_method: StringName = &""
var _full_solve_count: int = 0
var _dirty_mark_count: int = 0
var _patch_solve_count: int = 0
var _patch_apply_count: int = 0
var _has_pending_dirty_patch: bool = false
var _chunk_solid_halo: PackedByteArray = PackedByteArray()
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


func set_chunk_solid_halo(solid_halo: PackedByteArray) -> void:
	_chunk_solid_halo = solid_halo.duplicate()


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

	var mask_result: Dictionary = { }
	if _has_valid_chunk_solid_halo():
		mask_result = _build_solid_mask_with_halo(packet)
	else:
		mask_result = _build_solid_mask(packet)
	if int(mask_result.get("solid_count", 0)) <= 0:
		return true

	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var visual_packet := _build_visual_packet(mask_result, chunk_coord, recipe, seed)
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
	var mask_result := (
		_build_solid_mask_with_halo_for_output_rect(
			mountain_ids,
			mountain_flags,
			_last_dirty_rect_tiles,
		)
		if _has_valid_chunk_solid_halo()
		else _build_solid_mask_for_rect(mountain_ids, mountain_flags, _last_dirty_rect_tiles)
	)
	if int(mask_result.get("width_tiles", 0)) <= 0 \
			or int(mask_result.get("height_tiles", 0)) <= 0:
		return false

	var visual_packet := _build_visual_packet(mask_result, chunk_coord, _recipe, _seed)
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
		_packet_layer.free()
	_packet_layer = null
	_last_packet = { }
	_packet_images.clear()
	_packet_textures.clear()
	_last_solver_method = &""


func get_debug_state() -> Dictionary:
	return {
		"enabled": _enabled,
		"recipe_id": TerrainVisualRecipePayload.recipe_id(_recipe),
		"ready": not _last_packet.is_empty(),
		"has_visual_layer": _packet_layer != null and is_instance_valid(_packet_layer),
		"chunk_coord": _last_packet.get("chunk_coord", Vector2i.ZERO),
		"world_origin_tile": _last_packet.get("world_origin_tile", Vector2i.ZERO),
		"tile_size_px": int(_last_packet.get("tile_size_px", 0)),
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
		"last_solver_method": _last_solver_method,
		"has_chunk_solid_halo": _has_valid_chunk_solid_halo(),
		"has_pending_dirty_patch": _has_pending_dirty_patch,
		"shader_path": PACKET_SHADER_PATH,
	}


func _apply_packet_material(packet: Dictionary, recipe: Resource) -> void:
	_packet_layer = ColorRect.new()
	_packet_layer.name = "TerrainVisualV2PacketLayer"
	_packet_layer.color = Color.WHITE
	_packet_layer.size = _packet_world_pixel_size(packet)
	_packet_layer.z_index = ROCK_FILL_Z_INDEX
	var material := ShaderMaterial.new()
	material.shader = PACKET_SHADER
	var packet_material := TerrainVisualPacketMaterial.new()
	packet_material.apply_recipe_materials(material, recipe)
	packet_material.set_debug_mode(material, DEBUG_MODE_ALBEDO)
	material.set_shader_parameter("packet_pixel_size", _packet_pixel_size_vec2(packet))
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
	material.set_shader_parameter("packet_pixel_size", Vector2(pixel_size))
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
		var dst_texture := _packet_textures.get(field_name) as ImageTexture
		if dst_texture == null:
			dst_texture = ImageTexture.create_from_image(dst_image)
			_packet_textures[field_name] = dst_texture
			var material := _packet_layer.material as ShaderMaterial
			material.set_shader_parameter(shader_name, dst_texture)
		else:
			dst_texture.update(dst_image)

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


func _packet_pixel_size_vec2(packet: Dictionary) -> Vector2:
	return Vector2(
		float(int(packet.get("pixel_width", 0))),
		float(int(packet.get("pixel_height", 0))),
	)


func _packet_world_pixel_size(packet: Dictionary) -> Vector2:
	var dirty_rect: Rect2i = packet.get(
		"dirty_rect_tiles",
		Rect2i(Vector2i.ZERO, Vector2i.ZERO),
	) as Rect2i
	if dirty_rect.size.x > 0 and dirty_rect.size.y > 0:
		return Vector2(dirty_rect.size * WorldRuntimeConstants.TILE_SIZE_PX)
	return _packet_pixel_size_vec2(packet)


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


func _build_visual_packet(
		mask_result: Dictionary,
		chunk_coord: Vector2i,
		recipe: Resource,
		seed: int,
) -> Dictionary:
	var solver := _ensure_solver()
	if solver == null:
		return { }

	var recipe_payload := _make_runtime_recipe_payload(recipe)
	if bool(mask_result.get("uses_halo", false)):
		if not solver.has_method("build_chunk_visual_packet_with_halo"):
			push_error(
				(
					"TerrainVisualSolver.build_chunk_visual_packet_with_halo "
					+ "is required for halo-backed V2 chunks."
				),
			)
			return { }
		_last_solver_method = &"build_chunk_visual_packet_with_halo"
		return solver.call(
			"build_chunk_visual_packet_with_halo",
			mask_result.get("solid_mask", PackedByteArray()) as PackedByteArray,
			int(mask_result.get("width_tiles", 0)),
			int(mask_result.get("height_tiles", 0)),
			recipe_payload,
			chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + (
				mask_result.get("input_origin_local", Vector2i.ZERO) as Vector2i
			),
			chunk_coord,
			seed,
			mask_result.get("output_rect_tiles", Rect2i(Vector2i.ZERO, Vector2i.ZERO)) as Rect2i,
		) as Dictionary

	if not solver.has_method("build_chunk_visual_packet"):
		push_error(
			"TerrainVisualSolver.build_chunk_visual_packet is required for runtime V2 chunks.",
		)
		return { }
	_last_solver_method = &"build_chunk_visual_packet"
	var origin_local: Vector2i = mask_result.get("origin_local", Vector2i.ZERO) as Vector2i
	return solver.call(
		"build_chunk_visual_packet",
		mask_result.get("solid_mask", PackedByteArray()) as PackedByteArray,
		int(mask_result.get("width_tiles", 0)),
		int(mask_result.get("height_tiles", 0)),
		recipe_payload,
		chunk_coord * WorldRuntimeConstants.CHUNK_SIZE + origin_local,
		chunk_coord,
		seed,
	) as Dictionary


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
	]:
		recipe_payload[metric_key] = float(recipe_payload.get(metric_key, 0.0)) * runtime_scale
	return recipe_payload


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


func _build_solid_mask_with_halo(packet: Dictionary) -> Dictionary:
	var mountain_ids: PackedInt32Array = packet.get(
		"mountain_id_per_tile",
		PackedInt32Array(),
	) as PackedInt32Array
	var mountain_flags: PackedByteArray = packet.get(
		"mountain_flags",
		PackedByteArray(),
	) as PackedByteArray
	var bounds := _find_current_chunk_solid_bounds(mountain_ids, mountain_flags)
	if int(bounds.get("solid_count", 0)) <= 0:
		return { "solid_mask": PackedByteArray(), "solid_count": 0 }
	return _build_solid_mask_with_halo_for_output_rect(
		mountain_ids,
		mountain_flags,
		bounds.get("output_rect", Rect2i(Vector2i.ZERO, Vector2i.ZERO)) as Rect2i,
	)


func _build_solid_mask_with_halo_for_output_rect(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		output_rect: Rect2i,
) -> Dictionary:
	var mask := PackedByteArray()
	if not _has_valid_chunk_solid_halo() \
			or mountain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or output_rect.size.x <= 0 \
			or output_rect.size.y <= 0:
		return { "solid_mask": mask, "solid_count": 0 }

	var input_rect := output_rect.grow(1).intersection(
		Rect2i(
			Vector2i(-1, -1),
			Vector2i(WorldRuntimeConstants.CHUNK_SIZE + 2, WorldRuntimeConstants.CHUNK_SIZE + 2),
		),
	)
	if input_rect.size.x <= 0 or input_rect.size.y <= 0:
		return { "solid_mask": mask, "solid_count": 0 }

	mask.resize(input_rect.size.x * input_rect.size.y)
	var output_solid_count := 0
	for local_y: int in range(input_rect.position.y, input_rect.end.y):
		for local_x: int in range(input_rect.position.x, input_rect.end.x):
			var local_coord := Vector2i(local_x, local_y)
			var solid := _is_solid_sample_for_halo_mask(mountain_ids, mountain_flags, local_coord)
			if not solid:
				continue
			var mask_index := (local_y - input_rect.position.y) * input_rect.size.x + (
				local_x - input_rect.position.x
			)
			mask[mask_index] = 1
			if output_rect.has_point(local_coord):
				output_solid_count += 1
	return {
		"solid_mask": mask,
		"solid_count": output_solid_count,
		"input_origin_local": input_rect.position,
		"width_tiles": input_rect.size.x,
		"height_tiles": input_rect.size.y,
		"output_rect_tiles": Rect2i(output_rect.position - input_rect.position, output_rect.size),
		"uses_halo": true,
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


func _find_current_chunk_solid_bounds(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
) -> Dictionary:
	if mountain_ids.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT \
			or mountain_flags.size() != WorldRuntimeConstants.CHUNK_CELL_COUNT:
		return { "solid_count": 0 }

	var min_coord := Vector2i(WorldRuntimeConstants.CHUNK_SIZE, WorldRuntimeConstants.CHUNK_SIZE)
	var max_coord := Vector2i(-1, -1)
	var solid_count := 0
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		var local_coord: Vector2i = WorldRuntimeConstants.index_to_local(index)
		if not _is_current_chunk_solid_sample(mountain_ids, mountain_flags, local_coord):
			continue
		min_coord.x = mini(min_coord.x, local_coord.x)
		min_coord.y = mini(min_coord.y, local_coord.y)
		max_coord.x = maxi(max_coord.x, local_coord.x)
		max_coord.y = maxi(max_coord.y, local_coord.y)
		solid_count += 1
	if solid_count <= 0:
		return { "solid_count": 0 }
	return {
		"solid_count": solid_count,
		"output_rect": Rect2i(min_coord, max_coord - min_coord + Vector2i.ONE),
	}


func _is_solid_sample_for_halo_mask(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		local_coord: Vector2i,
) -> bool:
	if local_coord.x >= 0 \
			and local_coord.x < WorldRuntimeConstants.CHUNK_SIZE \
			and local_coord.y >= 0 \
			and local_coord.y < WorldRuntimeConstants.CHUNK_SIZE:
		return _is_current_chunk_solid_sample(mountain_ids, mountain_flags, local_coord)
	return _is_chunk_halo_solid(local_coord)


func _is_current_chunk_solid_sample(
		mountain_ids: PackedInt32Array,
		mountain_flags: PackedByteArray,
		local_coord: Vector2i,
) -> bool:
	var source_index := WorldRuntimeConstants.local_to_index(local_coord)
	if source_index < 0 \
			or source_index >= mountain_ids.size() \
			or source_index >= mountain_flags.size():
		return false
	var source_flags: int = int(mountain_flags[source_index])
	if int(mountain_ids[source_index]) <= 0:
		return false
	var source_surface_flags := (
		WorldRuntimeConstants.MOUNTAIN_FLAG_WALL | WorldRuntimeConstants.MOUNTAIN_FLAG_FOOT
	)
	return (source_flags & source_surface_flags) != 0


func _is_chunk_halo_solid(local_coord: Vector2i) -> bool:
	if not _has_valid_chunk_solid_halo():
		return false
	var halo_side := WorldRuntimeConstants.CHUNK_SIZE + 2
	var halo_coord := local_coord + Vector2i.ONE
	if halo_coord.x < 0 \
			or halo_coord.y < 0 \
			or halo_coord.x >= halo_side \
			or halo_coord.y >= halo_side:
		return false
	return int(_chunk_solid_halo[halo_coord.y * halo_side + halo_coord.x]) != 0


func _has_valid_chunk_solid_halo() -> bool:
	var halo_side := WorldRuntimeConstants.CHUNK_SIZE + 2
	return _chunk_solid_halo.size() == halo_side * halo_side
