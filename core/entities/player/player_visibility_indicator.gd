class_name PlayerVisibilityIndicator
extends Node2D

## Player-local visibility ring. Uses the current underground reveal radius as the
## only explicit visibility circle defined by the runtime today.

const UndergroundFogState = preload("res://core/systems/world/underground_fog_state.gd")
const FALLBACK_TILE_SIZE_PX: float = 64.0
const OUTLINE_COLOR: Color = Color(0.78, 0.92, 1.0, 0.9)
const FILL_COLOR: Color = Color(0.34, 0.60, 0.78, 0.08)
const OUTLINE_WIDTH_PX: float = 6.0
const ARC_POINT_COUNT: int = 96

var _radius_px: float = 0.0
var _world_generator: Node = null

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
	var tile_size_px: float = FALLBACK_TILE_SIZE_PX
	var world_generator: Node = _resolve_world_generator()
	if world_generator != null:
		var balance: Object = world_generator.get("balance") as Object
		if balance != null:
			tile_size_px = float(balance.get("tile_size"))
	return float(UndergroundFogState.REVEAL_RADIUS) * tile_size_px

func _resolve_world_generator() -> Node:
	if _world_generator != null and is_instance_valid(_world_generator):
		return _world_generator
	_world_generator = get_node_or_null("/root/WorldGenerator")
	return _world_generator
