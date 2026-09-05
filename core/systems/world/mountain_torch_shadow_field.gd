class_name MountainTorchShadowField
extends WorldViewOverlay

const SHADOW_FIELD_SHADER = preload("res://assets/shaders/mountain_torch_shadow_field.gdshader")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const MASK_MARGIN_PX: float = 160.0

var _world_streamer: Node = null
var _torch: PointLight2D = null
var _mask_texture: ImageTexture = null
var _mask_signature: String = ""


func _overlay_shader() -> Shader:
	return SHADOW_FIELD_SHADER


func _overlay_z() -> int:
	return WorldRuntimeConstants.Z_MOUNTAIN_TORCH_SHADOW


func _on_overlay_ready(overlay_material: ShaderMaterial) -> void:
	var image := Image.create(1, 1, false, Image.FORMAT_L8)
	image.fill(Color.BLACK)
	_mask_texture = ImageTexture.create_from_image(image)
	overlay_material.set_shader_parameter("mountain_mask", _mask_texture)
	overlay_material.set_shader_parameter("torch_strength", 0.0)


func _update_overlay(overlay_material: ShaderMaterial) -> void:
	var torch: PointLight2D = _get_torch()
	if torch == null or not torch.enabled:
		_hide_field(overlay_material)
		return
	var strength: float = _torch_block_strength(torch)
	if strength <= 0.01:
		_hide_field(overlay_material)
		return
	var streamer: Node = _get_world_streamer()
	if streamer == null or not streamer.has_method("get_mountain_torch_shadow_field_mask"):
		_hide_field(overlay_material)
		return
	var radius_px: float = _torch_radius_px(torch)
	var mask_result: Dictionary = streamer.call(
		"get_mountain_torch_shadow_field_mask",
		torch.global_position,
		radius_px + MASK_MARGIN_PX,
	) as Dictionary
	if not bool(mask_result.get("ready", false)) \
			or int(mask_result.get("solid_sample_count", 0)) <= 0:
		_hide_field(overlay_material)
		return
	_update_mask_texture(mask_result, overlay_material)
	visible = true
	overlay_material.set_shader_parameter("torch_world_pos", torch.global_position)
	overlay_material.set_shader_parameter("torch_radius_px", radius_px)
	overlay_material.set_shader_parameter("torch_strength", strength)


func _hide_field(overlay_material: ShaderMaterial) -> void:
	visible = false
	overlay_material.set_shader_parameter("torch_strength", 0.0)


func _update_mask_texture(mask_result: Dictionary, overlay_material: ShaderMaterial) -> void:
	var signature: String = str(mask_result.get("signature", ""))
	if signature == _mask_signature:
		return
	var upload_started_usec: int = WorldPerfProbe.begin()
	var bytes: PackedByteArray = mask_result.get("mask", PackedByteArray()) as PackedByteArray
	var width: int = int(mask_result.get("width", 0))
	var height: int = int(mask_result.get("height", 0))
	var step_px: float = float(mask_result.get("step_px", 0.0))
	if width <= 0 or height <= 0 or step_px <= 0.0 or bytes.size() != width * height:
		return
	var image := Image.create_from_data(width, height, false, Image.FORMAT_L8, bytes)
	if _mask_texture != null and _mask_texture.get_width() == width and _mask_texture.get_height() == height:
		_mask_texture.update(image)
	else:
		_mask_texture = ImageTexture.create_from_image(image)
		overlay_material.set_shader_parameter("mountain_mask", _mask_texture)
	var origin: Vector2 = mask_result.get("origin_world", Vector2.ZERO) as Vector2
	overlay_material.set_shader_parameter("mask_origin_px", origin)
	overlay_material.set_shader_parameter("mask_size_px", Vector2(float(width), float(height)) * step_px)
	overlay_material.set_shader_parameter("facade_height_px", 72.0)
	_mask_signature = signature
	WorldPerfProbe.end("MountainTorchShadowField.texture_upload", upload_started_usec)


func _torch_radius_px(torch: PointLight2D) -> float:
	var texture_width: float = 512.0
	if torch.texture != null:
		texture_width = float(torch.texture.get_width())
	return texture_width * torch.texture_scale * 0.5


func _torch_block_strength(torch: PointLight2D) -> float:
	return clampf(torch.energy / PlayerTorch.ENERGY, 0.0, 1.0)


func _get_torch() -> PointLight2D:
	if _torch != null and is_instance_valid(_torch):
		return _torch
	var player: Node = PlayerAuthority.get_local_player() if PlayerAuthority != null else null
	if player == null:
		return null
	_torch = player.get_node_or_null("Torch") as PointLight2D
	return _torch


func _get_world_streamer() -> Node:
	if _world_streamer != null and is_instance_valid(_world_streamer):
		return _world_streamer
	var nodes: Array[Node] = get_tree().get_nodes_in_group("chunk_manager")
	if nodes.is_empty():
		return null
	_world_streamer = nodes[0]
	return _world_streamer
