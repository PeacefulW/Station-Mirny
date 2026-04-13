class_name ChunkDebugRenderer
extends Node2D

var _rects: Array[Dictionary] = []

func clear_markers() -> void:
	if _rects.is_empty():
		visible = false
		return
	_rects.clear()
	visible = false
	queue_redraw()

func add_world_rect(center: Vector2, size: Vector2, color: Color) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_rects.append({
		"center": center,
		"size": size,
		"color": color,
	})
	visible = true
	queue_redraw()

func _draw() -> void:
	for rect_variant: Variant in _rects:
		var rect_data: Dictionary = rect_variant as Dictionary
		var center: Vector2 = rect_data.get("center", Vector2.ZERO) as Vector2
		var size: Vector2 = rect_data.get("size", Vector2.ZERO) as Vector2
		var color: Color = rect_data.get("color", Color.WHITE) as Color
		var half: Vector2 = size * 0.5
		draw_rect(Rect2(center - half, size), color, true)
