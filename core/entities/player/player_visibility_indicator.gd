class_name PlayerVisibilityIndicator
extends Node2D

## Player-local visibility ring. Uses the current underground reveal radius as the
## only explicit visibility circle defined by the runtime today.

const FALLBACK_TILE_SIZE_PX: float = 64.0
const FALLBACK_REVEAL_RADIUS_TILES: float = 6.0
const OUTLINE_COLOR: Color = Color(0.78, 0.92, 1.0, 0.9)
const FILL_COLOR: Color = Color(0.34, 0.60, 0.78, 0.08)
const OUTLINE_WIDTH_PX: float = 6.0
const ARC_POINT_COUNT: int = 96

var _radius_px: float = 0.0

func _ready() -> void:
	top_level = false
	show_behind_parent = true
	z_index = -1
	set_process(true)
	_update_radius(true)

func _process(_delta: float) -> void:
	_update_radius()

func _draw() -> void:
	if _radius_px <= 0.0:
		return
	draw_circle(Vector2.ZERO, _radius_px, FILL_COLOR)
	draw_arc(Vector2.ZERO, _radius_px, 0.0, TAU, ARC_POINT_COUNT, OUTLINE_COLOR, OUTLINE_WIDTH_PX, true)

func _update_radius(force_redraw: bool = false) -> void:
	var next_radius_px: float = _resolve_radius_px()
	if force_redraw or not is_equal_approx(next_radius_px, _radius_px):
		_radius_px = next_radius_px
		queue_redraw()

func _resolve_radius_px() -> float:
	return FALLBACK_REVEAL_RADIUS_TILES * FALLBACK_TILE_SIZE_PX
