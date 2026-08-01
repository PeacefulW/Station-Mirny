class_name PlayerHelmetLamps
extends Node2D
## Два конусных фонаря на шлеме скафандра (visual-only).
## Спека: docs/02_system_specs/progression/player_helmet_lamps_v1.md
##
## Свет — это не маска персонажа: источником служит PointLight2D, а форму пятна
## задаёт его текстура. Здесь текстура — конус, а узел разворачивается по
## направлению взгляда, поэтому темнота перестаёт быть равномерной и у игрока
## появляется причина повернуться.
##
## ADR-0005: свет — геймплейная система, и у источника обязана быть цена на
## питание. V1 строит только визуальную половину, ровно по тому же прецеденту,
## что уже задокументирован в player_torch.gd. Батарея — отдельная задача.
## Ни одна геймплейная система не читает эти узлы для видимости.

## Дальность считаем в тайлах (64 px), а не «на глаз»: фигура занимает около
## 56 px, поэтому конус радиусом в пол-экрана подавляет сцену вместо того,
## чтобы её раскрывать.
## Основной блок: две линзы, узкий луч примерно на 6.5 тайла.
const MAIN_CONE_HALF_ANGLE_DEGREES: float = 21.0
const MAIN_CONE_ENERGY: float = 1.0
const MAIN_CONE_RANGE_SCALE: float = 1.7
const MAIN_CONE_COLOR: Color = Color(1.0, 0.94, 0.82)
## Боковой фонарь: широкий подсвет примерно на 3.5 тайла, чтобы шаг вбок не был
## слепым, но чтобы он не спорил с основным лучом.
const SIDE_CONE_HALF_ANGLE_DEGREES: float = 44.0
const SIDE_CONE_ENERGY: float = 0.42
const SIDE_CONE_RANGE_SCALE: float = 0.9
const SIDE_CONE_COLOR: Color = Color(0.94, 0.95, 1.0)
const SIDE_CONE_YAW_DEGREES: float = 34.0
## Положение ламп задано в долях КАДРА, а не в экранных пикселях: масштаб
## спрайта меняется (игрока делали крупнее), и жёсткие пиксели отвязали бы свет
## от шлема при каждой такой правке.
## Голова стоит на 86.2% роста фигуры, поэтому по кадру она приходится на
## `ground_anchor - 0.862 * figure_height` = 0.806 - 0.862*0.70.
const LAMP_HEAD_FRAME_FRACTION: float = 0.203
## Разнос ламп по бокам шлема, тоже в долях высоты кадра.
const MAIN_LAMP_SIDE_FRAME_FRACTION: float = -0.063
const SIDE_LAMP_SIDE_FRAME_FRACTION: float = 0.048
const LIGHT_HEIGHT: float = 140.0
const CONE_TEXTURE_SIZE_PX: int = 512
## Клавиша включения. Заменяет факел на F (см. player_torch.gd).
const TOGGLE_KEYCODE: int = KEY_L

static var _cached_cone_textures: Dictionary = {}

@export var player_path: NodePath = ^".."

var _main_light: PointLight2D = null
var _side_light: PointLight2D = null
var _player: Node2D = null
var _enabled: bool = false
var _last_facing: Vector2 = Vector2.INF


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_main_light = _build_light(
		"HelmetLampMain",
		MAIN_CONE_HALF_ANGLE_DEGREES,
		MAIN_CONE_ENERGY,
		MAIN_CONE_RANGE_SCALE,
		MAIN_CONE_COLOR,
		_lamp_offset(MAIN_LAMP_SIDE_FRAME_FRACTION),
	)
	_side_light = _build_light(
		"HelmetLampSide",
		SIDE_CONE_HALF_ANGLE_DEGREES,
		SIDE_CONE_ENERGY,
		SIDE_CONE_RANGE_SCALE,
		SIDE_CONE_COLOR,
		_lamp_offset(SIDE_LAMP_SIDE_FRAME_FRACTION),
	)
	_apply_enabled()


func _lamp_offset(side_fraction: float) -> Vector2:
	## Переводит долю кадра в экранные пиксели по текущему спрайту игрока.
	## Читается один раз на _ready: масштаб Visual в рантайме не меняется.
	var visual: Sprite2D = null
	if _player != null:
		visual = _player.get_node_or_null(^"Visual") as Sprite2D
	if visual == null or visual.region_rect.size.y <= 0.0:
		# Без спрайта позицию шлема взять неоткуда — это сбой сцены, а не повод
		# светить из случайной точки.
		push_error("PlayerHelmetLamps: Visual sprite not found, cannot place lamps")
		return Vector2.ZERO
	var frame_height: float = visual.region_rect.size.y
	var local_y: float = (LAMP_HEAD_FRAME_FRACTION * frame_height - frame_height * 0.5 + visual.offset.y) * visual.scale.y
	var local_x: float = side_fraction * frame_height * visual.scale.x
	return Vector2(local_x, local_y)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == TOGGLE_KEYCODE:
		_enabled = not _enabled
		_apply_enabled()


func _physics_process(_delta: float) -> void:
	if not _enabled:
		return
	_update_facing()


func is_enabled() -> bool:
	return _enabled


func _apply_enabled() -> void:
	if _main_light != null:
		_main_light.enabled = _enabled
	if _side_light != null:
		_side_light.enabled = _enabled
	if _enabled:
		_last_facing = Vector2.INF
		_update_facing()


func _update_facing() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("get_visual_facing_vector"):
		return
	var facing: Vector2 = _player.call("get_visual_facing_vector")
	if facing.length_squared() <= 0.0001:
		return
	# Поворот трогаем только при смене направления: в 2D это дешёвая операция,
	# но она не обязана происходить каждый кадр.
	if _last_facing != Vector2.INF and facing.distance_squared_to(_last_facing) < 0.0001:
		return
	_last_facing = facing
	# Текстура конуса нарисована «вверх», то есть в -Y; angle() отсчитывается от +X.
	var base_rotation: float = facing.angle() + PI * 0.5
	if _main_light != null:
		_main_light.rotation = base_rotation
	if _side_light != null:
		_side_light.rotation = base_rotation + deg_to_rad(SIDE_CONE_YAW_DEGREES)


func _build_light(
	node_name: String,
	half_angle_degrees: float,
	energy: float,
	range_scale: float,
	color: Color,
	offset_px: Vector2,
) -> PointLight2D:
	var light := PointLight2D.new()
	light.name = node_name
	light.texture = _cone_texture(half_angle_degrees)
	light.color = color
	light.energy = energy
	light.texture_scale = range_scale
	light.height = LIGHT_HEIGHT
	# Перекрытие горой остаётся за MountainTorchShadowField; движковые карты
	# теней здесь не используются, как и у факела.
	light.shadow_enabled = false
	light.position = offset_px
	light.enabled = false
	add_child(light)
	return light


func _cone_texture(half_angle_degrees: float) -> Texture2D:
	var key: String = "%d_%d" % [CONE_TEXTURE_SIZE_PX, int(round(half_angle_degrees))]
	if _cached_cone_textures.has(key):
		var cached: Texture2D = _cached_cone_textures[key]
		return cached
	var texture: Texture2D = _make_cone(CONE_TEXTURE_SIZE_PX, half_angle_degrees)
	_cached_cone_textures[key] = texture
	return texture


func _make_cone(size_px: int, half_angle_degrees: float) -> Texture2D:
	## Вершина конуса — в центре текстуры, луч уходит вверх (-Y).
	## Центр совпадает с позицией лампы, поэтому свет исходит из железа, а не
	## из абстрактной точки рядом с головой.
	var image := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size_px - 1), float(size_px - 1)) * 0.5
	var radius: float = maxf(float(size_px) * 0.5, 1.0)
	var half_angle: float = deg_to_rad(half_angle_degrees)
	for y: int in range(size_px):
		for x: int in range(size_px):
			var delta := Vector2(float(x), float(y)) - center
			var distance: float = delta.length()
			var alpha: float = 0.0
			if distance > 0.001 and distance < radius:
				var direction: Vector2 = delta / distance
				# Угол между направлением на пиксель и осью конуса (-Y).
				var axis_dot: float = -direction.y
				var angle: float = acos(clampf(axis_dot, -1.0, 1.0))
				if angle < half_angle:
					# Пологое затухание, а не smoothstep: кубическая кривая гасит
					# луч на трети радиуса, и фонарь читается обрубленным вместо
					# того, чтобы бить вдаль.
					var radial: float = pow(1.0 - distance / radius, 0.75)
					# Мягкая кромка конуса: гаснем к его краю, а не режем.
					var angular: float = 1.0 - angle / half_angle
					angular = smoothstep(0.0, 0.45, angular)
					# У самой вершины конус ещё узкий — подсвечиваем ядро, иначе
					# у лампы получается тёмная дыра.
					var core: float = smoothstep(0.0, 0.06 * radius, distance)
					alpha = clampf(radial * angular * core, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)
