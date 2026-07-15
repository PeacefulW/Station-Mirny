class_name HudPerformanceGraph
extends Control

const PerformanceHudMetrics = preload("res://core/runtime/performance_hud_metrics.gd")

const BACKGROUND_COLOR: Color = Color(0.018, 0.027, 0.035, 0.72)
const GRID_COLOR: Color = Color(0.44, 0.58, 0.65, 0.10)
const LINE_COLOR: Color = Color(0.31, 0.84, 0.94, 0.95)
const FILL_COLOR: Color = Color(0.20, 0.68, 0.80, 0.14)
const BUDGET_COLOR: Color = Color(0.95, 0.75, 0.35, 0.48)
const HITCH_COLOR: Color = Color(1.0, 0.34, 0.28, 0.56)

var _samples: PackedFloat32Array = PackedFloat32Array()
var _window_label: String = "300 FRAME WINDOW"


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 84.0)


func set_samples(samples: PackedFloat32Array) -> void:
	_samples = samples
	queue_redraw()


func set_window_label(label: String) -> void:
	if _window_label == label:
		return
	_window_label = label
	queue_redraw()


func _draw() -> void:
	var graph_size: Vector2 = size
	if graph_size.x <= 1.0 or graph_size.y <= 1.0:
		return
	draw_rect(Rect2(Vector2.ZERO, graph_size), BACKGROUND_COLOR)
	var font: Font = ThemeDB.fallback_font
	var plot_rect := Rect2(8.0, 7.0, graph_size.x - 16.0, graph_size.y - 14.0)
	var scale_max_ms: float = 33.34
	for sample: float in _samples:
		scale_max_ms = maxf(scale_max_ms, minf(sample, 100.0))
	_draw_threshold(plot_rect, 8.33, scale_max_ms, GRID_COLOR, "8.3")
	_draw_threshold(
		plot_rect,
		PerformanceHudMetrics.FRAME_BUDGET_60_FPS_MS,
		scale_max_ms,
		BUDGET_COLOR,
		"16.7",
	)
	_draw_threshold(
		plot_rect,
		PerformanceHudMetrics.HITCH_THRESHOLD_MS,
		scale_max_ms,
		HITCH_COLOR,
		"22",
	)
	if _samples.size() < 2:
		return
	var line_points := PackedVector2Array()
	line_points.resize(_samples.size())
	var denominator: float = float(maxi(1, _samples.size() - 1))
	for index: int in range(_samples.size()):
		var x: float = plot_rect.position.x \
				+ plot_rect.size.x * float(index) / denominator
		var normalized: float = clampf(float(_samples[index]) / scale_max_ms, 0.0, 1.0)
		var y: float = plot_rect.end.y - plot_rect.size.y * normalized
		line_points[index] = Vector2(x, y)
	var fill_points := PackedVector2Array()
	fill_points.resize(line_points.size() + 2)
	fill_points[0] = Vector2(line_points[0].x, plot_rect.end.y)
	for index: int in range(line_points.size()):
		fill_points[index + 1] = line_points[index]
	fill_points[fill_points.size() - 1] = Vector2(line_points[-1].x, plot_rect.end.y)
	draw_colored_polygon(fill_points, FILL_COLOR)
	draw_polyline(line_points, LINE_COLOR, 1.35, true)
	var last_ms: float = float(_samples[-1])
	var last_color: Color = _health_color(PerformanceHudMetrics.classify_frame_time(last_ms))
	draw_circle(line_points[-1], 2.6, last_color)
	if font != null:
		draw_string(
			font,
			Vector2(plot_rect.end.x - 100.0, plot_rect.position.y + 10.0),
			_window_label,
			HORIZONTAL_ALIGNMENT_RIGHT,
			100.0,
			9,
			Color(0.55, 0.64, 0.68, 0.62),
		)


func _draw_threshold(
		plot_rect: Rect2,
		threshold_ms: float,
		scale_max_ms: float,
		color: Color,
		label: String,
) -> void:
	var normalized: float = clampf(threshold_ms / scale_max_ms, 0.0, 1.0)
	var y: float = plot_rect.end.y - plot_rect.size.y * normalized
	draw_line(Vector2(plot_rect.position.x, y), Vector2(plot_rect.end.x, y), color, 1.0)
	var font: Font = ThemeDB.fallback_font
	if font != null:
		draw_string(
			font,
			Vector2(plot_rect.position.x + 3.0, y - 2.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			32.0,
			9,
			color,
		)


func _health_color(health: int) -> Color:
	match health:
		PerformanceHudMetrics.Health.GOOD:
			return Color(0.35, 0.94, 0.61)
		PerformanceHudMetrics.Health.WARNING:
			return Color(0.98, 0.75, 0.31)
		PerformanceHudMetrics.Health.CRITICAL:
			return Color(1.0, 0.34, 0.28)
	return Color(0.55, 0.64, 0.68)
