class_name TerrainVisualChunkLayer
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const TerrainVisualPacketMaterial = preload(
	"res://data/terrain_visual/terrain_visual_packet_material.gd"
)

const DEBUG_MODE_ALBEDO := 0
const ROCK_FILL_Z_INDEX := 11
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

var packet_layer: ColorRect = null
var last_packet: Dictionary = { }
var packet_images: Dictionary = { }
var packet_textures: Dictionary = { }
var last_solver_method: StringName = &""


func clear() -> void:
	if packet_layer != null and is_instance_valid(packet_layer):
		packet_layer.free()
	packet_layer = null
	last_packet = { }
	packet_images.clear()
	packet_textures.clear()
	last_solver_method = &""


func is_ready() -> bool:
	return not last_packet.is_empty()


func has_visual_layer() -> bool:
	return packet_layer != null and is_instance_valid(packet_layer)


func texture_field_count() -> int:
	return PACKET_TEXTURE_FIELDS.size()


func make_pending_layer(
		packet: Dictionary,
		recipe: Resource,
		contact_outline_width_px: float,
) -> Dictionary:
	var layer := ColorRect.new()
	layer.name = "TerrainVisualV2PacketLayer"
	layer.color = Color.WHITE
	layer.size = packet_world_pixel_size(packet)
	layer.z_index = ROCK_FILL_Z_INDEX

	var material := ShaderMaterial.new()
	material.shader = PACKET_SHADER
	var packet_material := TerrainVisualPacketMaterial.new()
	packet_material.apply_recipe_materials(material, recipe)
	packet_material.set_debug_mode(material, DEBUG_MODE_ALBEDO)
	material.set_shader_parameter("packet_pixel_size", packet_pixel_size_vec2(packet))
	material.set_shader_parameter("contact_outline_width_px", contact_outline_width_px)
	material.set_shader_parameter("base_source", 2)
	material.set_shader_parameter("base_flat_color", Color(0.0, 0.0, 0.0, 0.0))
	layer.material = material

	var chunk_coord: Vector2i = packet.get("chunk_coord", Vector2i.ZERO) as Vector2i
	var world_origin_tile: Vector2i = packet.get("world_origin_tile", Vector2i.ZERO) as Vector2i
	layer.position = Vector2(
		float(world_origin_tile.x - chunk_coord.x * WorldRuntimeConstants.CHUNK_SIZE),
		float(world_origin_tile.y - chunk_coord.y * WorldRuntimeConstants.CHUNK_SIZE),
	) * float(WorldRuntimeConstants.TILE_SIZE_PX)

	return {
		"layer": layer,
		"material": material,
		"images": { },
		"textures": { },
	}


func store_packet_texture_field(
		material: ShaderMaterial,
		packet: Dictionary,
		pixel_size: Vector2i,
		field_spec: Array,
		image_store: Dictionary,
		texture_store: Dictionary,
) -> bool:
	var field_name := field_spec[0] as String
	var shader_name := field_spec[1] as String
	var image := make_packet_image(
		packet,
		field_name,
		pixel_size,
		int(field_spec[2]),
		int(field_spec[3]),
	)
	if image == null:
		return false
	var texture := ImageTexture.create_from_image(image)
	image_store[field_name] = image
	texture_store[field_name] = texture
	material.set_shader_parameter(shader_name, texture)
	return true


func commit_full(
		parent: Node,
		layer: ColorRect,
		images: Dictionary,
		textures: Dictionary,
		packet: Dictionary,
		solver_method: StringName,
) -> void:
	if packet_layer != null and is_instance_valid(packet_layer):
		packet_layer.free()
	packet_layer = layer
	packet_images = images
	packet_textures = textures
	last_packet = packet
	last_solver_method = solver_method
	if packet_layer.get_parent() == null:
		parent.add_child(packet_layer)


func copy_patch_packet_field(
		patch_packet: Dictionary,
		field_spec: Array,
		patch_pixel_size: Vector2i,
		intersection_px: Rect2i,
		src_rect_px: Rect2i,
		solve_queue: Object,
) -> bool:
	var field_name := field_spec[0] as String
	var shader_name := field_spec[1] as String
	var bytes_per_pixel := int(field_spec[3])
	var dst_image := packet_images.get(field_name) as Image
	if dst_image == null:
		return false
	var src_image := make_packet_image(
		patch_packet,
		field_name,
		patch_pixel_size,
		int(field_spec[2]),
		bytes_per_pixel,
	)
	if src_image == null:
		return false
	var base_pixel_size := Vector2i(
		int(last_packet.get("pixel_width", 0)),
		int(last_packet.get("pixel_height", 0)),
	)
	if not _copy_patch_bytes_to_current_packet(
		patch_packet,
		field_name,
		base_pixel_size,
		patch_pixel_size,
		intersection_px,
		src_rect_px,
		bytes_per_pixel,
		solve_queue,
	):
		return false
	dst_image.blit_rect(src_image, src_rect_px, intersection_px.position)
	var dst_texture := packet_textures.get(field_name) as ImageTexture
	if dst_texture == null:
		dst_texture = ImageTexture.create_from_image(dst_image)
		packet_textures[field_name] = dst_texture
		var material := packet_layer.material as ShaderMaterial
		material.set_shader_parameter(shader_name, dst_texture)
	else:
		dst_texture.update(dst_image)
	return true


func make_packet_image(
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
			"TerrainVisualChunkLayer field %s has %d bytes, expected %d."
			% [field_name, bytes.size(), expected_size],
		)
		return null
	return Image.create_from_data(pixel_size.x, pixel_size.y, false, image_format, bytes)


func packet_pixel_size_vec2(packet: Dictionary) -> Vector2:
	return Vector2(
		float(int(packet.get("pixel_width", 0))),
		float(int(packet.get("pixel_height", 0))),
	)


func packet_world_pixel_size(packet: Dictionary) -> Vector2:
	var dirty_rect: Rect2i = packet.get(
		"dirty_rect_tiles",
		Rect2i(Vector2i.ZERO, Vector2i.ZERO),
	) as Rect2i
	if dirty_rect.size.x > 0 and dirty_rect.size.y > 0:
		return Vector2(dirty_rect.size * WorldRuntimeConstants.TILE_SIZE_PX)
	return packet_pixel_size_vec2(packet)


func _copy_patch_bytes_to_current_packet(
		patch_packet: Dictionary,
		field_name: String,
		base_pixel_size: Vector2i,
		patch_pixel_size: Vector2i,
		dst_rect: Rect2i,
		src_rect: Rect2i,
		bytes_per_pixel: int,
		solve_queue: Object,
) -> bool:
	var dst_bytes: PackedByteArray = last_packet.get(field_name, PackedByteArray())
	var src_bytes: PackedByteArray = patch_packet.get(field_name, PackedByteArray())
	var expected_dst_size := base_pixel_size.x * base_pixel_size.y * bytes_per_pixel
	var expected_src_size := patch_pixel_size.x * patch_pixel_size.y * bytes_per_pixel
	if dst_bytes.size() != expected_dst_size or src_bytes.size() != expected_src_size:
		push_error(
			"TerrainVisualChunkLayer cannot patch field %s bytes (%d/%d, expected %d/%d)."
			% [
				field_name,
				dst_bytes.size(),
				src_bytes.size(),
				expected_dst_size,
				expected_src_size,
			],
		)
		return false

	var patched_bytes: PackedByteArray = solve_queue.copy_patch_field_bytes(
		dst_bytes,
		src_bytes,
		base_pixel_size,
		patch_pixel_size,
		dst_rect,
		src_rect,
		bytes_per_pixel,
	)
	if patched_bytes.size() != expected_dst_size:
		return false
	last_packet[field_name] = patched_bytes
	return true
