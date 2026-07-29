extends SceneTree

const WorldHeightShadowField = preload(
	"res://core/systems/world/world_height_shadow_field.gd"
)
const WorldHeightShadowProfile = preload(
	"res://core/systems/world/world_height_shadow_profile.gd"
)
const RECEIVER_SHADER: Shader = preload(
	"res://assets/shaders/layered_object_albedo_batch.gdshader"
)
const GRASS_RECEIVER_SHADER: Shader = preload(
	"res://assets/shaders/grass_scatter_batch.gdshader"
)
const SNOW_RECEIVER_SHADER: Shader = preload(
	"res://assets/shaders/layered_object_snow_batch.gdshader"
)

const VIEWPORT_SIZE := Vector2i(192, 128)
const SHADOW_CENTER := Vector2(52.0, 30.0)
const FLIPPED_CONTROL_CENTER := Vector2(52.0, 98.0)
const GRASS_SHADOW_CENTER := Vector2(130.0, 30.0)
const ROCK_SNOW_SHADOW_CENTER := Vector2(130.0, 98.0)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("height_shadow_receiver_render_smoke_test requires a windowed GPU renderer")
		quit(2)
		return
	RenderingServer.set_default_clear_color(Color(0.08, 0.10, 0.12, 1.0))

	var source_viewport := SubViewport.new()
	source_viewport.size = VIEWPORT_SIZE
	source_viewport.transparent_bg = false
	source_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	source_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(source_viewport)
	var world_root := Node2D.new()
	source_viewport.add_child(world_root)
	var field := WorldHeightShadowField.new()
	world_root.add_child(field)

	var opaque_white := _solid_texture(Color.WHITE, Vector2i(34, 34))
	var opaque_shadow := _solid_texture(Color(0.0, 0.0, 0.0, 0.92), Vector2i(30, 30))
	for shadow_center: Vector2 in [
		SHADOW_CENTER,
		GRASS_SHADOW_CENTER,
		ROCK_SNOW_SHADOW_CENTER,
	]:
		var shadow := Sprite2D.new()
		shadow.texture = opaque_shadow
		shadow.position = shadow_center
		shadow.z_index = 0
		world_root.add_child(shadow)
		WorldHeightShadowProfile.mark_tall_caster_path(shadow)

	var receiver_material := ShaderMaterial.new()
	receiver_material.shader = RECEIVER_SHADER
	receiver_material.set_shader_parameter("atlas_columns", 1.0)
	receiver_material.set_shader_parameter("atlas_rows", 1.0)
	receiver_material.set_shader_parameter("atlas_frame_count", 1.0)
	receiver_material.set_shader_parameter("frame_texel_size", Vector2.ONE / 34.0)
	field.bind_receiver(
		receiver_material,
		WorldHeightShadowProfile.ReceiverClass.GRASS,
	)
	for receiver_center: Vector2 in [SHADOW_CENTER, FLIPPED_CONTROL_CENTER]:
		var receiver := Sprite2D.new()
		receiver.texture = opaque_white
		receiver.position = receiver_center
		receiver.z_index = 1
		receiver.material = receiver_material
		world_root.add_child(receiver)
	var grass_material := ShaderMaterial.new()
	grass_material.shader = GRASS_RECEIVER_SHADER
	grass_material.set_shader_parameter("atlas_columns", 1.0)
	grass_material.set_shader_parameter("atlas_rows", 1.0)
	grass_material.set_shader_parameter("atlas_frame_count", 1.0)
	field.bind_receiver(
		grass_material,
		WorldHeightShadowProfile.ReceiverClass.GRASS,
	)
	_add_receiver_sprite(world_root, opaque_white, grass_material, GRASS_SHADOW_CENTER)

	var snow_material := ShaderMaterial.new()
	snow_material.shader = SNOW_RECEIVER_SHADER
	snow_material.set_shader_parameter("atlas_columns", 1.0)
	snow_material.set_shader_parameter("atlas_rows", 1.0)
	snow_material.set_shader_parameter("atlas_frame_count", 1.0)
	snow_material.set_shader_parameter("frame_texel_size", Vector2.ONE / 34.0)
	snow_material.set_shader_parameter("snow_mask_texture", opaque_white)
	snow_material.set_shader_parameter("season_amount", 1.0)
	field.bind_receiver(
		snow_material,
		WorldHeightShadowProfile.ReceiverClass.SMALL_ROCK,
	)
	_add_receiver_sprite(world_root, opaque_white, snow_material, ROCK_SNOW_SHADOW_CENTER)

	for _frame_index: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = source_viewport.get_texture().get_image()
	var shadowed_receiver: Color = rendered.get_pixelv(Vector2i(SHADOW_CENTER))
	var flipped_control: Color = rendered.get_pixelv(Vector2i(FLIPPED_CONTROL_CENTER))
	var grass_control: Color = rendered.get_pixel(130, 30)
	var snow_control: Color = rendered.get_pixel(130, 98)
	print(
		"height_shadow_receiver_render_smoke_test samples: shadowed=%s control=%s"
		% [shadowed_receiver, flipped_control],
	)
	_expect(
		shadowed_receiver.get_luminance() < 0.55,
		"opaque receiver above the direct shadow must be darkened by the height mask",
	)
	_expect(
		flipped_control.get_luminance() > 0.90,
		"mask sampling must keep screen Y orientation and leave the mirrored control white",
	)
	_expect(
		grass_control.a > 0.95 and grass_control.get_luminance() < 0.55,
		"production grass shader must receive a taller caster's shadow",
	)
	_expect(
		snow_control.a > 0.95 and snow_control.get_luminance() < 0.55,
		"production small-rock snow shader must receive a taller caster's shadow",
	)
	var mask_image: Image = field.get_mask_texture().get_image()
	var mask_point := Vector2i(
		roundi(SHADOW_CENTER.x * field.profile.mask_resolution_scale),
		roundi(SHADOW_CENTER.y * field.profile.mask_resolution_scale),
	)
	_expect(
		mask_image.get_pixelv(mask_point).a > 0.75,
		"tall-caster viewport must contain the authored shadow alpha",
	)

	world_root.queue_free()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		quit(1)
		return
	print("height_shadow_receiver_render_smoke_test: PASS")
	quit(0)


func _solid_texture(color: Color, size: Vector2i) -> ImageTexture:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _add_receiver_sprite(
		parent: Node,
		texture: Texture2D,
		receiver_material: ShaderMaterial,
		center: Vector2,
) -> void:
	var receiver := Sprite2D.new()
	receiver.texture = texture
	receiver.position = center
	receiver.z_index = 1
	receiver.material = receiver_material
	parent.add_child(receiver)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
