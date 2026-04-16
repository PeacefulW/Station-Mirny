class_name WorldChunkDebugOverlay
extends Node2D

## Minimal F11 chunk debug overlay.
## Presentation-only: reads a bounded snapshot and renders chunk rectangles plus a small HUD.

const SNAPSHOT_INTERVAL_SEC: float = 0.10
const SNAPSHOT_QUEUE_ROWS: int = 1
const HUD_POSITION: Vector2 = Vector2(10.0, 10.0)
const LOAD_RING_COLOR: Color = Color(0.22, 0.82, 0.96, 0.92)
const UNLOAD_RING_COLOR: Color = Color(0.92, 0.94, 0.98, 0.80)
const GRID_BORDER_COLOR: Color = Color(0.10, 0.12, 0.14, 0.48)
const PLAYER_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.98)
const STATUS_COLORS := {
	"loaded": Color(0.24, 0.84, 0.40, 0.34),
	"generating": Color(0.96, 0.82, 0.24, 0.36),
	"staged": Color(0.28, 0.54, 0.96, 0.34),
	"queued": Color(0.56, 0.60, 0.64, 0.24),
	"unloading": Color(0.86, 0.54, 0.24, 0.28),
	"error": Color(0.96, 0.18, 0.16, 0.42),
	"absent": Color(0.0, 0.0, 0.0, 0.0),
}

var _chunk_manager: Node = null
var _overlay_visible: bool = false
var _snapshot_timer: float = 0.0
var _snapshot: Dictionary = {}
var _hud_label: Label = null

func setup(chunk_manager: Node, ui_layer: CanvasLayer, _game_world: Node2D = null) -> void:
	_chunk_manager = chunk_manager
	z_index = 900
	_build_hud(ui_layer)
	set_overlay_visible(false)

func _exit_tree() -> void:
	if _hud_label != null and is_instance_valid(_hud_label):
		_hud_label.queue_free()

func is_overlay_visible() -> bool:
	return _overlay_visible

func toggle_overlay() -> void:
	set_overlay_visible(not _overlay_visible)

func set_overlay_visible(value: bool) -> void:
	_overlay_visible = value
	visible = value
	if _hud_label != null:
		_hud_label.visible = value
	set_process(value)
	if not value:
		_snapshot = {}
		queue_redraw()
		return
	_snapshot_timer = SNAPSHOT_INTERVAL_SEC
	_refresh_snapshot()

func _process(delta: float) -> void:
	if not _overlay_visible:
		return
	_snapshot_timer += delta
	if _snapshot_timer < SNAPSHOT_INTERVAL_SEC:
		return
	_snapshot_timer = 0.0
	_refresh_snapshot()

func _draw() -> void:
	if not _overlay_visible or _snapshot.is_empty():
		return
	var generator: Node = _get_world_generator()
	if generator == null:
		return
	var chunk_px: float = _chunk_pixel_size(generator)
	if chunk_px <= 0.0:
		return
	var player_chunk: Vector2i = _snapshot.get("player_chunk", Vector2i.ZERO) as Vector2i
	_draw_ring(player_chunk, int((_snapshot.get("radii", {}) as Dictionary).get("preload_radius", 0)), chunk_px, LOAD_RING_COLOR)
	_draw_ring(player_chunk, int((_snapshot.get("radii", {}) as Dictionary).get("retention_radius", 0)), chunk_px, UNLOAD_RING_COLOR)
	for raw_entry: Variant in _snapshot.get("chunks", []) as Array:
		_draw_chunk(raw_entry as Dictionary, player_chunk, chunk_px)

func _refresh_snapshot() -> void:
	if _chunk_manager == null or not is_instance_valid(_chunk_manager):
		return
	if not _chunk_manager.has_method("get_chunk_debug_overlay_snapshot"):
		return
	_snapshot = _chunk_manager.get_chunk_debug_overlay_snapshot(SNAPSHOT_QUEUE_ROWS)
	_update_hud()
	queue_redraw()

func _build_hud(ui_layer: CanvasLayer) -> void:
	_hud_label = Label.new()
	_hud_label.name = "WorldChunkDebugOverlayHud"
	_hud_label.visible = false
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_label.position = HUD_POSITION
	_hud_label.add_theme_font_size_override("font_size", 13)
	_hud_label.add_theme_color_override("font_color", Color(0.90, 0.96, 0.94, 1.0))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_hud_label.add_theme_constant_override("shadow_offset_x", 1)
	_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	if ui_layer != null:
		ui_layer.add_child(_hud_label)
	else:
		add_child(_hud_label)

func _update_hud() -> void:
	if _hud_label == null:
		return
	if _snapshot.is_empty():
		_hud_label.text = ""
		return
	var metrics: Dictionary = _snapshot.get("metrics", {}) as Dictionary
	var player_chunk: Vector2i = _snapshot.get("player_chunk", Vector2i.ZERO) as Vector2i
	_hud_label.text = "FPS %d | chunk (%d,%d) | z %d" % [
		int(round(float(metrics.get("fps", 0.0)))),
		player_chunk.x,
		player_chunk.y,
		int(_snapshot.get("active_z", 0)),
	]

func _draw_ring(player_chunk: Vector2i, radius: int, chunk_px: float, color: Color) -> void:
	if radius < 0:
		return
	var center_display: Vector2i = _get_display_chunk_coord(player_chunk, player_chunk)
	var top_left_chunk: Vector2i = center_display - Vector2i(radius, radius)
	var rect := Rect2(
		Vector2(top_left_chunk.x * chunk_px, top_left_chunk.y * chunk_px),
		Vector2((radius * 2 + 1) * chunk_px, (radius * 2 + 1) * chunk_px)
	)
	draw_rect(rect, color, false, 3.0)

func _draw_chunk(entry: Dictionary, player_chunk: Vector2i, chunk_px: float) -> void:
	var coord: Vector2i = entry.get("coord", Vector2i.ZERO) as Vector2i
	var display_coord: Vector2i = _get_display_chunk_coord(coord, player_chunk)
	var rect := Rect2(Vector2(display_coord.x * chunk_px, display_coord.y * chunk_px), Vector2.ONE * chunk_px)
	var status: String = _overlay_status(entry)
	var fill: Color = STATUS_COLORS.get(status, STATUS_COLORS["absent"]) as Color
	if fill.a > 0.0:
		draw_rect(rect.grow(-1.0), fill, true)
	var border_color: Color = PLAYER_BORDER_COLOR if bool(entry.get("is_player_chunk", false)) else GRID_BORDER_COLOR
	var border_width: float = 3.0 if bool(entry.get("is_player_chunk", false)) else 1.0
	if status == "error":
		border_color = STATUS_COLORS["error"] as Color
		border_width = 3.0
	draw_rect(rect, border_color, false, border_width)

func _overlay_status(entry: Dictionary) -> String:
	if bool(entry.get("is_stalled", false)):
		return "error"
	match str(entry.get("state", "absent")):
		"ready", "visible", "simulating", "building_visual":
			return "loaded"
		"generating":
			return "generating"
		"data_ready":
			return "staged"
		"requested", "queued":
			return "queued"
		"unloading":
			return "unloading"
		"error", "stalled":
			return "error"
		_:
			return "absent"

func _get_world_generator() -> Node:
	return get_node_or_null("/root/WorldGenerator")

func _chunk_pixel_size(generator: Node) -> float:
	var balance: Resource = generator.get("balance") as Resource
	if balance == null:
		return 0.0
	return float(int(balance.get("chunk_size_tiles")) * int(balance.get("tile_size")))

func _get_display_chunk_coord(coord: Vector2i, reference_chunk: Vector2i) -> Vector2i:
	var generator: Node = _get_world_generator()
	if generator != null and generator.has_method("get_display_chunk_coord"):
		return generator.call("get_display_chunk_coord", coord, reference_chunk) as Vector2i
	return coord
