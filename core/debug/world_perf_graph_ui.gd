class_name WorldPerfGraphUI
extends Control

const HISTORY_SIZE: int = 180
const MS_PER_PIXEL: float = 5.0 # 10ms = 50 pixels

var _history: Array[Dictionary] = []
var _monitor: Node = null

func _ready() -> void:
	custom_minimum_size = Vector2(0, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if _monitor == null:
		_monitor = get_node_or_null("/root/WorldPerfMonitor")
	if _monitor != null and _monitor.has_method("get_debug_snapshot"):
		var snapshot: Dictionary = _monitor.call("get_debug_snapshot") as Dictionary
		if _history.is_empty() or _history.back().get("timestamp_usec", 0) != snapshot.get("timestamp_usec", 0):
			_history.append(snapshot)
			if _history.size() > HISTORY_SIZE:
				_history.pop_front()
			if is_visible_in_tree():
				queue_redraw()

func _draw() -> void:
	if _history.is_empty():
		return
	
	var rect: Rect2 = get_rect()
	var w: float = rect.size.x
	var h: float = rect.size.y
	
	# draw background
	draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.05, 0.05, 0.95))
	
	# draw budget lines
	_draw_line(h, 16.66, Color(1.0, 0.2, 0.2, 0.6), "16.6ms (60 FPS)")
	_draw_line(h, 8.33, Color(1.0, 0.6, 0.2, 0.5), "8.3ms (120 FPS)")
	_draw_line(h, 6.0, Color(1.0, 0.9, 0.2, 0.5), "6.0ms (Background Budget)")
	_draw_line(h, 2.0, Color(0.2, 1.0, 0.2, 0.4), "2.0ms (Action limit)")
	
	var bar_w: float = w / float(HISTORY_SIZE)
	var x: float = 0.0
	
	var font: Font = ThemeDB.fallback_font
	var labels_to_draw: Array[Dictionary] = []
	
	for i: int in range(_history.size()):
		var snapshot: Dictionary = _history[i]
		var frame_ms: float = float(snapshot.get("frame_time_ms", 0.0))
		var cats: Dictionary = snapshot.get("categories", {}) as Dictionary
		
		var current_y: float = h
		
		# Helpers for category rendering
		var draw_cat = func(cat: String, color: Color) -> void:
			var val: float = float(cats.get(cat, 0.0))
			if val > 0.0:
				var bar_h: float = val * MS_PER_PIXEL
				draw_rect(Rect2(x, current_y - bar_h, maxf(1.0, bar_w - 0.5), bar_h), color)
				current_y -= bar_h
		
		# Draw categories in specific order
		draw_cat.call("other", Color(0.3, 0.3, 0.3)) # Dark gray
		draw_cat.call("dispatcher", Color(0.5, 0.5, 0.5)) # Gray
		draw_cat.call("power", Color(0.6, 0.8, 0.2)) # Light green
		draw_cat.call("topology", Color(0.2, 0.8, 0.2)) # Green
		draw_cat.call("shadow", Color(0.2, 0.4, 0.8)) # Blue
		draw_cat.call("visual", Color(0.2, 0.6, 1.0)) # Cyan
		draw_cat.call("streaming_redraw", Color(0.6, 0.2, 0.9)) # Deep Purple
		draw_cat.call("streaming_load", Color(0.8, 0.2, 0.8)) # Purple
		draw_cat.call("building", Color(0.8, 0.6, 0.2)) # Yellow
		draw_cat.call("spawn", Color(0.9, 0.4, 0.2)) # Orange
		draw_cat.call("interactive", Color(1.0, 0.2, 0.2)) # Red
		
		# Identify spikes
		if frame_ms > 4.0:
			var ops: Dictionary = snapshot.get("ops", {}) as Dictionary
			var heaviest_op: String = ""
			var max_op_ms: float = 0.0
			for op: String in ops:
				var val: float = float(ops[op])
				if val > max_op_ms:
					max_op_ms = val
					heaviest_op = op
			# Only show label if the heaviest op took a noticeable chunk
			if max_op_ms > 1.5:
				labels_to_draw.append({"x": x, "y": current_y, "text": "%s (%.1fms)" % [heaviest_op.replace("ChunkManager.", "").replace("MountainRoofSystem.", ""), max_op_ms], "color": Color(1.0, 0.8, 0.8)})
		
		x += bar_w
		
	# Draw labels last so they are on top
	var last_label_y: float = -100.0
	for lbl: Dictionary in labels_to_draw:
		var ly: float = maxf(20.0, float(lbl.get("y", 0.0)) - 5.0)
		if abs(ly - last_label_y) < 12.0:
			ly -= 12.0 # Push it up to avoid overlap
		if font != null:
			draw_string(font, Vector2(float(lbl.get("x", 0.0)) + 2.0, ly), str(lbl.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, lbl.get("color", Color.WHITE) as Color)
		last_label_y = ly
		
	# Legend
	_draw_legend()

func _draw_line(h: float, ms: float, color: Color, text: String) -> void:
	var y: float = h - (ms * MS_PER_PIXEL)
	if y > 0 and y < h:
		draw_line(Vector2(0, y), Vector2(get_rect().size.x, y), color, 1.0)
		var font: Font = ThemeDB.fallback_font
		if font != null:
			draw_string(font, Vector2(5, y - 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)

func _draw_legend() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var labels: Array = [
		{"name": "Interactive (Mining/Place)", "color": Color(1.0, 0.2, 0.2)},
		{"name": "Spawn", "color": Color(0.9, 0.4, 0.2)},
		{"name": "Building", "color": Color(0.8, 0.6, 0.2)},
		{"name": "Stream Redraw", "color": Color(0.6, 0.2, 0.9)},
		{"name": "Stream Load", "color": Color(0.8, 0.2, 0.8)},
		{"name": "Visual/Cover", "color": Color(0.2, 0.6, 1.0)},
		{"name": "Shadow", "color": Color(0.2, 0.4, 0.8)},
		{"name": "Topology", "color": Color(0.2, 0.8, 0.2)},
	]
	var lx: float = get_rect().size.x - 180.0
	var ly: float = 20.0
	for item: Dictionary in labels:
		draw_rect(Rect2(lx, ly - 8, 10, 10), item.get("color", Color.WHITE) as Color)
		draw_string(font, Vector2(lx + 15, ly + 1), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color.WHITE)
		ly += 16.0
