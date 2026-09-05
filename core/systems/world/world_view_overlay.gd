class_name WorldViewOverlay
extends Sprite2D
## Базовый полноэкранный атмосферный слой в МИРЕ (а не на CanvasLayer):
## 1x1 спрайт, растянутый на текущий вид и следящий за камерой, с шейдером,
## которому сообщается мировой прямоугольник вида (view_world_origin/size).
## Живёт под Daylight-модулятором, поэтому тонируется день/ночь вместе с
## миром. Наследники задают шейдер и z через _overlay_shader/_overlay_z.
## Презентация (ADR-0007 layer 4); состояние не сохраняется.

const VIEW_MARGIN: float = 1.06

static var _shared_unit_texture: ImageTexture = null


func _ready() -> void:
	z_as_relative = false
	z_index = _overlay_z()
	centered = true
	texture = _shared_view_texture()
	var overlay_material := ShaderMaterial.new()
	overlay_material.shader = _overlay_shader()
	material = overlay_material
	_on_overlay_ready(overlay_material)


func _process(_delta: float) -> void:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null:
		return
	var viewport: Viewport = get_viewport()
	var camera: Camera2D = viewport.get_camera_2d()
	if camera == null or not is_instance_valid(camera):
		visible = false
		return
	visible = true
	# Canvas transforms map world coordinates into the logical visible rect.
	# Physical window pixels have a separate stretch transform and must not be
	# combined with this inverse, including when the compositor scales its target.
	var canvas_to_world: Transform2D = viewport.canvas_transform.affine_inverse()
	var visible_rect: Rect2 = viewport.get_visible_rect()
	var world_corners: Array[Vector2] = [
		canvas_to_world * visible_rect.position,
		canvas_to_world * Vector2(visible_rect.end.x, visible_rect.position.y),
		canvas_to_world * visible_rect.end,
		canvas_to_world * Vector2(visible_rect.position.x, visible_rect.end.y),
	]
	var world_min: Vector2 = world_corners[0]
	var world_max: Vector2 = world_corners[0]
	for corner: Vector2 in world_corners:
		world_min = world_min.min(corner)
		world_max = world_max.max(corner)
	var view_size: Vector2 = world_max - world_min
	var view_center: Vector2 = (world_min + world_max) * 0.5
	# 1x1 текстура -> scale задаёт пиксельный размер покрытия вида (+запас).
	global_position = view_center
	scale = view_size * VIEW_MARGIN
	var view_origin: Vector2 = view_center - view_size * (VIEW_MARGIN * 0.5)
	shader_material.set_shader_parameter("view_world_origin", view_origin)
	shader_material.set_shader_parameter("view_world_size", view_size * VIEW_MARGIN)
	_update_overlay(shader_material)


## Шейдер слоя. Переопределить.
func _overlay_shader() -> Shader:
	return null


## z слоя. Переопределить при необходимости.
func _overlay_z() -> int:
	return 400


## Однократная настройка материала. Переопределить при необходимости.
func _on_overlay_ready(_overlay_material: ShaderMaterial) -> void:
	pass


## Покадровое обновление специфичных параметров. Переопределить.
func _update_overlay(_overlay_material: ShaderMaterial) -> void:
	pass


static func _shared_view_texture() -> Texture2D:
	if _shared_unit_texture != null:
		return _shared_unit_texture
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_shared_unit_texture = ImageTexture.create_from_image(image)
	return _shared_unit_texture
