class_name WorldOverviewCanvas
extends Control

const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")

const BACKGROUND_COLOR: Color = Color(0.045, 0.055, 0.065, 0.96)
const MAP_BACKGROUND_COLOR: Color = Color(0.025, 0.035, 0.045, 1.0)
const FRAME_COLOR: Color = Color(0.92, 0.73, 0.43, 0.28)
const WRAP_HINT_COLOR: Color = Color(0.92, 0.73, 0.43, 0.62)
const LOADING_SWEEP_COLOR: Color = Color(0.92, 0.73, 0.43, 0.10)
const MAP_PADDING: float = 10.0

var _overview_texture: Texture2D = null
var _expected_aspect: float = 2.0
var _is_loading: bool = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func reset_overview(world_bounds: WorldBoundsSettings = null) -> void:
	_overview_texture = null
	_expected_aspect = _resolve_world_aspect(world_bounds)
	set_loading(false)
	queue_redraw()

func set_loading(is_loading: bool) -> void:
	_is_loading = is_loading
	set_process(_is_loading)
	queue_redraw()

func publish_overview(overview_texture: Texture2D) -> void:
	_overview_texture = overview_texture
	_is_loading = false
	set_process(false)
	queue_redraw()

func _process(_delta: float) -> void:
	if _is_loading:
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
	var map_rect: Rect2 = _resolve_map_rect()
	draw_rect(map_rect, MAP_BACKGROUND_COLOR, true)
	if _overview_texture != null:
		draw_texture_rect(_overview_texture, map_rect, false)
	elif _is_loading:
		_draw_loading_sweep(map_rect)
	_draw_wrap_hint(map_rect)
	draw_rect(map_rect, FRAME_COLOR, false, 1.0)

func _resolve_map_rect() -> Rect2:
	var usable_size := Vector2(
		maxf(size.x - MAP_PADDING * 2.0, 1.0),
		maxf(size.y - MAP_PADDING * 2.0, 1.0)
	)
	var aspect: float = _expected_aspect
	if _overview_texture != null and _overview_texture.get_height() > 0:
		aspect = float(_overview_texture.get_width()) / float(_overview_texture.get_height())
	var map_size := Vector2(usable_size.x, usable_size.x / maxf(aspect, 0.01))
	if map_size.y > usable_size.y:
		map_size.y = usable_size.y
		map_size.x = usable_size.y * aspect
	var map_origin := Vector2(
		floorf((size.x - map_size.x) * 0.5),
		floorf((size.y - map_size.y) * 0.5)
	)
	return Rect2(map_origin, map_size)

func _draw_loading_sweep(map_rect: Rect2) -> void:
	var sweep_width: float = maxf(map_rect.size.x * 0.18, 12.0)
	var t: float = fmod(float(Time.get_ticks_msec()) / 900.0, 1.0)
	var sweep_x: float = map_rect.position.x + (map_rect.size.x + sweep_width) * t - sweep_width
	draw_rect(
		Rect2(Vector2(sweep_x, map_rect.position.y), Vector2(sweep_width, map_rect.size.y)),
		LOADING_SWEEP_COLOR,
		true
	)

func _draw_wrap_hint(map_rect: Rect2) -> void:
	var mid_y: float = map_rect.position.y + map_rect.size.y * 0.5
	var tick: float = clampf(map_rect.size.y * 0.12, 6.0, 14.0)
	draw_line(
		Vector2(map_rect.position.x, map_rect.position.y),
		Vector2(map_rect.position.x, map_rect.end.y),
		WRAP_HINT_COLOR,
		1.0
	)
	draw_line(
		Vector2(map_rect.end.x, map_rect.position.y),
		Vector2(map_rect.end.x, map_rect.end.y),
		WRAP_HINT_COLOR,
		1.0
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(map_rect.position.x + 4.0, mid_y),
			Vector2(map_rect.position.x + 4.0 + tick, mid_y - tick * 0.5),
			Vector2(map_rect.position.x + 4.0 + tick, mid_y + tick * 0.5),
		]),
		WRAP_HINT_COLOR
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(map_rect.end.x - 4.0, mid_y),
			Vector2(map_rect.end.x - 4.0 - tick, mid_y - tick * 0.5),
			Vector2(map_rect.end.x - 4.0 - tick, mid_y + tick * 0.5),
		]),
		WRAP_HINT_COLOR
	)

func _resolve_world_aspect(world_bounds: WorldBoundsSettings) -> float:
	if world_bounds == null or world_bounds.height_tiles <= 0:
		return 2.0
	return float(world_bounds.width_tiles) / float(world_bounds.height_tiles)
