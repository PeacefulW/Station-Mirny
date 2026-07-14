class_name MountainCavitySkylightField
extends Node2D

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const FIELD_SHADER = preload("res://assets/shaders/mountain_cavity_skylight_field.gdshader")

const FIELD_Z_INDEX: int = WorldRuntimeConstants.Z_GRASS_SPORE + 1

var _unit_texture: ImageTexture = null
var _sprites_by_chunk: Dictionary = { }
var _active_chunk_count: int = 0
var _reveal_blend: float = 0.0
var _apply_count_total: int = 0
var _remove_count_total: int = 0


func _ready() -> void:
	name = "MountainCavitySkylightField"
	# The unit-white child sprites expose the parent's red modulation channel to
	# their shader. This keeps the shared reveal scalar O(1) while alpha remains
	# available for persistent closed-mouth coverage.
	modulate = Color(_reveal_blend, 1.0, 1.0, 1.0)
	_refresh_visibility()


## Binds ChunkView-owned GPU textures to one non-overlapping central-chunk
## sprite. This is called only from the existing budgeted visual-upload or
## atomic selector-commit path; the field performs no per-frame CPU work.
func apply_chunk_source(chunk_coord: Vector2i, source: Dictionary) -> bool:
	if not bool(source.get("ready", false)):
		remove_chunk(chunk_coord)
		return false

	var live_mask_texture: Texture2D = source.get("live_mask_texture", null) as Texture2D
	var closed_roof_mask_texture: Texture2D = source.get(
		"closed_roof_mask_texture",
		null,
	) as Texture2D
	var sky_exposure_texture: Texture2D = source.get("sky_exposure_texture", null) as Texture2D
	var reveal_selector_texture: Texture2D = source.get(
		"reveal_selector_texture",
		null,
	) as Texture2D
	var any_cutout_texture: Texture2D = source.get("any_cutout_texture", null) as Texture2D
	var chunk_origin_world: Vector2 = source.get("chunk_origin_world", Vector2.ZERO) as Vector2
	var chunk_size_world: Vector2 = source.get("chunk_size_world", Vector2.ZERO) as Vector2
	var mask_origin_world: Vector2 = source.get("mask_origin_world", Vector2.ZERO) as Vector2
	var mask_size_world: Vector2 = source.get("mask_size_world", Vector2.ZERO) as Vector2
	var selector_origin_world: Vector2 = source.get(
		"selector_origin_world",
		Vector2.ZERO,
	) as Vector2
	var selector_size_world: Vector2 = source.get("selector_size_world", Vector2.ZERO) as Vector2
	var mask_sample_step_px: float = float(source.get("mask_sample_step_px", 0.0))
	var facade_height_px: float = float(source.get("facade_height_px", 0.0))
	if live_mask_texture == null \
			or closed_roof_mask_texture == null \
			or sky_exposure_texture == null \
			or reveal_selector_texture == null \
			or any_cutout_texture == null \
			or chunk_size_world.x <= 0.0 \
			or chunk_size_world.y <= 0.0 \
			or mask_size_world.x <= 0.0 \
			or mask_size_world.y <= 0.0 \
			or selector_size_world.x <= 0.0 \
			or selector_size_world.y <= 0.0 \
			or mask_sample_step_px <= 0.0 \
			or facade_height_px <= 0.0:
		remove_chunk(chunk_coord)
		return false

	var sprite: Sprite2D = _sprites_by_chunk.get(chunk_coord, null) as Sprite2D
	if sprite == null or not is_instance_valid(sprite):
		sprite = _create_chunk_sprite(chunk_coord)
		_sprites_by_chunk[chunk_coord] = sprite
	var was_active: bool = sprite.visible
	# A ready M8 source already proves that this chunk owns excavation data.
	# Keep it available while the selector is empty so the real closed-roof
	# mouth remains visible; the shader performs the spatial roof clipping.
	var is_active: bool = true

	sprite.position = chunk_origin_world + chunk_size_world * 0.5
	sprite.scale = chunk_size_world
	var shader_material: ShaderMaterial = sprite.material as ShaderMaterial
	shader_material.set_shader_parameter("live_mask_texture", live_mask_texture)
	shader_material.set_shader_parameter("closed_roof_mask_texture", closed_roof_mask_texture)
	shader_material.set_shader_parameter("sky_exposure_texture", sky_exposure_texture)
	shader_material.set_shader_parameter("reveal_selector_texture", reveal_selector_texture)
	shader_material.set_shader_parameter("any_cutout_halo_texture", any_cutout_texture)
	shader_material.set_shader_parameter("any_cutout_broad_texture", any_cutout_texture)
	shader_material.set_shader_parameter("chunk_origin_world", chunk_origin_world)
	shader_material.set_shader_parameter("chunk_size_world", chunk_size_world)
	shader_material.set_shader_parameter("mask_origin_world", mask_origin_world)
	shader_material.set_shader_parameter("mask_size_world", mask_size_world)
	shader_material.set_shader_parameter("selector_origin_world", selector_origin_world)
	shader_material.set_shader_parameter("selector_size_world", selector_size_world)
	shader_material.set_shader_parameter("mask_sample_step_px", mask_sample_step_px)
	shader_material.set_shader_parameter("facade_height_px", facade_height_px)
	sprite.visible = is_active

	if was_active != is_active:
		_active_chunk_count += 1 if is_active else -1
		_active_chunk_count = maxi(_active_chunk_count, 0)
	_apply_count_total += 1
	_refresh_visibility()
	return true


func remove_chunk(chunk_coord: Vector2i) -> bool:
	var sprite: Sprite2D = _sprites_by_chunk.get(chunk_coord, null) as Sprite2D
	if sprite == null:
		return false
	if is_instance_valid(sprite):
		if sprite.visible:
			_active_chunk_count = maxi(_active_chunk_count - 1, 0)
		sprite.queue_free()
	_sprites_by_chunk.erase(chunk_coord)
	_remove_count_total += 1
	_refresh_visibility()
	return true


func clear() -> void:
	for sprite_variant: Variant in _sprites_by_chunk.values():
		var sprite: Sprite2D = sprite_variant as Sprite2D
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
	_sprites_by_chunk.clear()
	_active_chunk_count = 0
	_refresh_visibility()


func set_reveal_blend(value: float) -> void:
	_reveal_blend = clampf(value, 0.0, 1.0)
	modulate = Color(_reveal_blend, 1.0, 1.0, 1.0)
	_refresh_visibility()


func get_debug_state() -> Dictionary:
	return {
		"sprite_count": _sprites_by_chunk.size(),
		"active_chunk_count": _active_chunk_count,
		"reveal_blend": _reveal_blend,
		"visible": visible,
		"apply_count_total": _apply_count_total,
		"remove_count_total": _remove_count_total,
		"z_index": FIELD_Z_INDEX,
	}


func _create_chunk_sprite(chunk_coord: Vector2i) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	sprite.centered = true
	sprite.texture = _get_unit_texture()
	sprite.z_as_relative = false
	sprite.z_index = FIELD_Z_INDEX
	sprite.visible = false
	var shader_material := ShaderMaterial.new()
	shader_material.shader = FIELD_SHADER
	sprite.material = shader_material
	add_child(sprite)
	return sprite


func _get_unit_texture() -> ImageTexture:
	if _unit_texture != null:
		return _unit_texture
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_unit_texture = ImageTexture.create_from_image(image)
	return _unit_texture


func _refresh_visibility() -> void:
	visible = _active_chunk_count > 0
