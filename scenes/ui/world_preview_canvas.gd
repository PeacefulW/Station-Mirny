class_name WorldPreviewCanvas
extends Control

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const BACKGROUND_COLOR: Color = Color(0.06, 0.08, 0.09, 0.94)
const MAP_BACKGROUND_COLOR: Color = Color(0.04, 0.05, 0.06, 1.0)
const GRID_COLOR: Color = Color(0.92, 0.73, 0.43, 0.09)
const FRAME_COLOR: Color = Color(0.92, 0.73, 0.43, 0.26)
const PROGRESS_PANEL_FILL: Color = Color(0.07, 0.08, 0.09, 0.88)
const PROGRESS_PANEL_BORDER: Color = Color(0.92, 0.73, 0.43, 0.18)
const PROGRESS_TEXT: Color = Color(0.94, 0.92, 0.87, 0.96)
const SPAWN_MARKER_COLOR: Color = Color(1.0, 0.94, 0.76, 0.98)
const CANVAS_PADDING: float = 12.0

var _center_chunk_coord: Vector2i = Vector2i.ZERO
var _spawn_tile: Vector2i = Vector2i.ZERO
var _full_radius_chunks: int = 0
var _patches_by_chunk: Dictionary = {}
var _progress_stage_span_chunks: int = 0
var _ready_chunk_count: int = 0
var _published_chunk_count: int = 0
var _target_chunk_count: int = 0
var _progress_panel: PanelContainer = null
var _stage_label: Label = null
var _count_label: Label = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_ensure_progress_overlay()
	_refresh_progress_overlay()

func reset_preview(center_chunk_coord: Vector2i, spawn_tile: Vector2i, full_radius_chunks: int) -> void:
	_center_chunk_coord = center_chunk_coord
	_spawn_tile = spawn_tile
	_full_radius_chunks = maxi(full_radius_chunks, 0)
	_patches_by_chunk.clear()
	_progress_stage_span_chunks = 0
	_ready_chunk_count = 0
	_published_chunk_count = 0
	_target_chunk_count = 0
	_refresh_progress_overlay()
	queue_redraw()

func publish_chunk_patch(chunk_coord: Vector2i, patch_texture: Texture2D) -> void:
	_patches_by_chunk[chunk_coord] = patch_texture
	queue_redraw()

func set_progress(
	stage_span_chunks: int,
	ready_chunk_count: int,
	published_chunk_count: int,
	target_chunk_count: int
) -> void:
	_progress_stage_span_chunks = maxi(stage_span_chunks, 0)
	_ready_chunk_count = maxi(ready_chunk_count, 0)
	_published_chunk_count = maxi(published_chunk_count, 0)
	_target_chunk_count = maxi(target_chunk_count, 0)
	_refresh_progress_overlay()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
	if _full_radius_chunks <= 0:
		return
	var metrics: Dictionary = _build_render_metrics()
	var map_rect := Rect2(
		metrics.get("map_origin", Vector2.ZERO) as Vector2,
		metrics.get("map_size", Vector2.ZERO) as Vector2
	)
	draw_rect(map_rect, MAP_BACKGROUND_COLOR, true)
	_draw_chunk_grid(metrics)
	_draw_patches(metrics)
	_draw_spawn_marker(metrics)
	draw_rect(map_rect, FRAME_COLOR, false, 1.0)

func _draw_chunk_grid(metrics: Dictionary) -> void:
	var map_origin: Vector2 = metrics.get("map_origin", Vector2.ZERO) as Vector2
	var map_size: Vector2 = metrics.get("map_size", Vector2.ZERO) as Vector2
	var chunk_size_px: float = float(metrics.get("chunk_size_px", 0.0))
	var chunk_count: int = int(metrics.get("chunk_count", 0))
	for index: int in range(chunk_count + 1):
		var offset: float = chunk_size_px * float(index)
		draw_line(
			map_origin + Vector2(offset, 0.0),
			map_origin + Vector2(offset, map_size.y),
			GRID_COLOR,
			1.0
		)
		draw_line(
			map_origin + Vector2(0.0, offset),
			map_origin + Vector2(map_size.x, offset),
			GRID_COLOR,
			1.0
		)

func _draw_patches(metrics: Dictionary) -> void:
	var chunk_coords: Array[Vector2i] = []
	for chunk_coord_variant: Variant in _patches_by_chunk.keys():
		chunk_coords.append(chunk_coord_variant as Vector2i)
	chunk_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	for chunk_coord: Vector2i in chunk_coords:
		var patch_texture: Texture2D = _patches_by_chunk.get(chunk_coord, null) as Texture2D
		if patch_texture == null:
			continue
		draw_texture_rect(
			patch_texture,
			_resolve_chunk_rect(chunk_coord, metrics),
			false
		)

func _draw_spawn_marker(metrics: Dictionary) -> void:
	var map_origin: Vector2 = metrics.get("map_origin", Vector2.ZERO) as Vector2
	var chunk_size_px: float = float(metrics.get("chunk_size_px", 0.0))
	var center_offset: int = _full_radius_chunks
	var spawn_chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(_spawn_tile)
	var spawn_local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(_spawn_tile)
	var chunk_delta: Vector2i = spawn_chunk_coord - _center_chunk_coord
	var marker_pos := map_origin + Vector2(
		(float(chunk_delta.x + center_offset) + (float(spawn_local_coord.x) + 0.5) / float(WorldRuntimeConstants.CHUNK_SIZE)) * chunk_size_px,
		(float(chunk_delta.y + center_offset) + (float(spawn_local_coord.y) + 0.5) / float(WorldRuntimeConstants.CHUNK_SIZE)) * chunk_size_px
	)
	var marker_half: float = clampf(chunk_size_px * 0.16, 3.0, 8.0)
	draw_line(
		marker_pos + Vector2(-marker_half, 0.0),
		marker_pos + Vector2(marker_half, 0.0),
		SPAWN_MARKER_COLOR,
		2.0
	)
	draw_line(
		marker_pos + Vector2(0.0, -marker_half),
		marker_pos + Vector2(0.0, marker_half),
		SPAWN_MARKER_COLOR,
		2.0
	)
	draw_circle(marker_pos, clampf(marker_half * 0.42, 1.5, 3.0), SPAWN_MARKER_COLOR)

func _build_render_metrics() -> Dictionary:
	var chunk_count: int = _full_radius_chunks * 2 + 1
	var usable_width: float = maxf(size.x - CANVAS_PADDING * 2.0, 1.0)
	var usable_height: float = maxf(size.y - CANVAS_PADDING * 2.0, 1.0)
	var chunk_size_px: float = floorf(minf(usable_width, usable_height) / float(chunk_count))
	chunk_size_px = maxf(chunk_size_px, 1.0)
	var map_size := Vector2(
		chunk_size_px * float(chunk_count),
		chunk_size_px * float(chunk_count)
	)
	var map_origin := Vector2(
		floorf((size.x - map_size.x) * 0.5),
		floorf((size.y - map_size.y) * 0.5)
	)
	return {
		"chunk_count": chunk_count,
		"chunk_size_px": chunk_size_px,
		"map_size": map_size,
		"map_origin": map_origin,
	}

func _resolve_chunk_rect(chunk_coord: Vector2i, metrics: Dictionary) -> Rect2:
	var center_offset: int = _full_radius_chunks
	var map_origin: Vector2 = metrics.get("map_origin", Vector2.ZERO) as Vector2
	var chunk_size_px: float = float(metrics.get("chunk_size_px", 0.0))
	var chunk_delta: Vector2i = chunk_coord - _center_chunk_coord
	return Rect2(
		map_origin + Vector2(
			float(chunk_delta.x + center_offset) * chunk_size_px,
			float(chunk_delta.y + center_offset) * chunk_size_px
		),
		Vector2(chunk_size_px, chunk_size_px)
	)

func _ensure_progress_overlay() -> void:
	if _progress_panel != null:
		return
	_progress_panel = PanelContainer.new()
	_progress_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_panel.anchor_left = 0.0
	_progress_panel.anchor_top = 0.0
	_progress_panel.anchor_right = 1.0
	_progress_panel.anchor_bottom = 0.0
	_progress_panel.offset_left = 12.0
	_progress_panel.offset_top = 12.0
	_progress_panel.offset_right = -12.0
	_progress_panel.offset_bottom = 40.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PROGRESS_PANEL_FILL
	panel_style.border_color = PROGRESS_PANEL_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	_progress_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_progress_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	_progress_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	_stage_label = Label.new()
	_stage_label.add_theme_color_override("font_color", PROGRESS_TEXT)
	_stage_label.add_theme_font_size_override("font_size", 11)
	row.add_child(_stage_label)

	_count_label = Label.new()
	_count_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_color_override("font_color", PROGRESS_TEXT)
	_count_label.add_theme_font_size_override("font_size", 11)
	row.add_child(_count_label)

func _refresh_progress_overlay() -> void:
	if _progress_panel == null or _stage_label == null or _count_label == null:
		return
	var clamped_published: int = mini(_published_chunk_count, _target_chunk_count)
	var clamped_ready: int = mini(_ready_chunk_count, _target_chunk_count)
	var publish_backlog: int = maxi(clamped_ready - clamped_published, 0)
	_stage_label.text = "%dx%d" % [_progress_stage_span_chunks, _progress_stage_span_chunks] if _progress_stage_span_chunks > 0 else "--"
	_count_label.text = "%d/%d" % [clamped_published, _target_chunk_count]
	if publish_backlog > 0:
		_count_label.text += " +%d" % publish_backlog
	_progress_panel.visible = _target_chunk_count > 0
