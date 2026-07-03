class_name ObjectCollisionDebugLayer
extends Node2D
## Dev-оверлей: квадраты вокруг коллайдеров камней/валунов/деревьев (в стиле
## Factorio). Включается WorldStreamer.toggle_debug_object_collisions() (хоткей
## F11 в scenes/world/world_runtime_v0_scene.gd). Presentation only (ADR-0007):
## не влияет на геймплей, коллизии, сохранения.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const BOX_COLOR := Color(0.25, 1.0, 0.35, 0.9)
const LINE_WIDTH_PX: float = 2.0

var _rects: Array[Rect2] = []


func _ready() -> void:
	z_as_relative = false
	z_index = WorldRuntimeConstants.Z_DEBUG_OVERLAY


## Полная замена набора рамок (пересобирается при каждой пересборке коллизий
## объектного пакета, пока дебаг включён).
func set_debug_boxes(rects: Array[Rect2]) -> void:
	_rects = rects
	queue_redraw()


func _draw() -> void:
	for rect: Rect2 in _rects:
		draw_rect(rect, BOX_COLOR, false, LINE_WIDTH_PX)
