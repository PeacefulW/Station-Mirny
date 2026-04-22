class_name WorldPreviewCanvas
extends Control

const WorldPreviewRenderMode = preload("res://core/systems/world/world_preview_render_mode.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const BACKGROUND_COLOR: Color = Color(0.06, 0.08, 0.09, 0.94)
const MAP_BACKGROUND_COLOR: Color = Color(0.04, 0.05, 0.06, 1.0)
const GRID_COLOR: Color = Color(0.92, 0.73, 0.43, 0.09)
const FRAME_COLOR: Color = Color(0.92, 0.73, 0.43, 0.26)
const PROGRESS_PANEL_FILL: Color = Color(0.07, 0.08, 0.09, 0.88)
const PROGRESS_PANEL_BORDER: Color = Color(0.92, 0.73, 0.43, 0.18)
const PROGRESS_TEXT: Color = Color(0.94, 0.92, 0.87, 0.96)
const SPAWN_MARKER_COLOR: Color = Color(1.0, 0.94, 0.76, 0.98)
const SPAWN_SAFE_PATCH_FILL: Color = Color(0.30, 0.82, 0.56, 0.24)
const SPAWN_SAFE_PATCH_OUTLINE: Color = Color(0.40, 1.0, 0.67, 0.90)
const ZOOM_LEVELS: Array[float] = [1.0, 1.5, 2.0, 3.0, 4.0]
const CANVAS_PADDING: float = 12.0

var _center_chunk_coord: Vector2i = Vector2i.ZERO
var _spawn_tile: Vector2i = Vector2i.ZERO
var _spawn_safe_patch_rect: Rect2i = Rect2i()
var _full_radius_chunks: int = 0
var _patches_by_chunk: Dictionary = {}
var _progress_stage_span_chunks: int = 0
var _ready_chunk_count: int = 0
var _published_chunk_count: int = 0
var _target_chunk_count: int = 0
var _progress_panel: PanelContainer = null
var _stage_label: Label = null
var _count_label: Label = null
var _render_mode: StringName = WorldPreviewRenderMode.TERRAIN
var _zoom_level_index: int = 0
var _pan_offset: Vector2 = Vector2.ZERO
var _is_dragging_view: bool = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_progress_overlay()
	_refresh_progress_overlay()

func reset_preview(center_chunk_coord: Vector2i, spawn_tile: Vector2i, full_radius_chunks: int) -> void:
	_center_chunk_coord = center_chunk_coord
	_spawn_tile = spawn_tile
	_full_radius_chunks = maxi(full_radius_chunks, 0)
	_patches_by_chunk.clear()
	reset_view()
	_progress_stage_span_chunks = 0
	_ready_chunk_count = 0
	_published_chunk_count = 0
	_target_chunk_count = 0
	_refresh_progress_overlay()
	queue_redraw()

func set_render_mode(render_mode: StringName, spawn_safe_patch_rect: Rect2i) -> void:
	_render_mode = WorldPreviewRenderMode.coerce(render_mode)
	_spawn_safe_patch_rect = spawn_safe_patch_rect
	queue_redraw()

func publish_chunk_patch(chunk_coord: Vector2i, patch_texture: Texture2D) -> void:
	_patches_by_chunk[chunk_coord] = patch_texture
	queue_redraw()

func clear_patches() -> void:
	_patches_by_chunk.clear()
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

func reset_view() -> void:
	_zoom_level_index = 0
	_pan_offset = Vector2.ZERO
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
		match mouse_button_event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mouse_button_event.pressed:
					_step_zoom(1)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mouse_button_event.pressed:
					_step_zoom(-1)
					accept_event()
			MOUSE_BUTTON_LEFT:
				_is_dragging_view = mouse_button_event.pressed and _can_pan()
				if not mouse_button_event.pressed:
					_is_dragging_view = false
				accept_event()
	elif event is InputEventMouseMotion and _is_dragging_view:
		var mouse_motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		_pan_offset += mouse_motion_event.relative
		queue_redraw()
		accept_event()

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
	_draw_spawn_safe_patch_overlay(metrics)
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

func _draw_spawn_safe_patch_overlay(metrics: Dictionary) -> void:
	if _render_mode != WorldPreviewRenderMode.SPAWN_SAFE_PATCH or _spawn_safe_patch_rect.size == Vector2i.ZERO:
		return
	var tile_rect: Rect2 = _resolve_tile_rect(_spawn_safe_patch_rect, metrics)
	draw_rect(tile_rect, SPAWN_SAFE_PATCH_FILL, true)
	draw_rect(tile_rect, SPAWN_SAFE_PATCH_OUTLINE, false, 2.0)

func _build_render_metrics() -> Dictionary:
	var chunk_count: int = _full_radius_chunks * 2 + 1
	var usable_width: float = maxf(size.x - CANVAS_PADDING * 2.0, 1.0)
	var usable_height: float = maxf(size.y - CANVAS_PADDING * 2.0, 1.0)
	var base_chunk_size_px: float = floorf(minf(usable_width, usable_height) / float(chunk_count))
	base_chunk_size_px = maxf(base_chunk_size_px, 1.0)
	var chunk_size_px: float = base_chunk_size_px * _resolve_zoom_factor()
	var map_size := Vector2(
		chunk_size_px * float(chunk_count),
		chunk_size_px * float(chunk_count)
	)
	var centered_origin := Vector2(
		floorf((size.x - map_size.x) * 0.5),
		floorf((size.y - map_size.y) * 0.5)
	)
	var map_origin := centered_origin
	var min_origin_x: float = size.x - CANVAS_PADDING - map_size.x
	var max_origin_x: float = CANVAS_PADDING
	var min_origin_y: float = size.y - CANVAS_PADDING - map_size.y
	var max_origin_y: float = CANVAS_PADDING
	if map_size.x > usable_width:
		map_origin.x = clampf(centered_origin.x + _pan_offset.x, min_origin_x, max_origin_x)
		_pan_offset.x = map_origin.x - centered_origin.x
	else:
		_pan_offset.x = 0.0
	if map_size.y > usable_height:
		map_origin.y = clampf(centered_origin.y + _pan_offset.y, min_origin_y, max_origin_y)
		_pan_offset.y = map_origin.y - centered_origin.y
	else:
		_pan_offset.y = 0.0
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

func _resolve_tile_rect(tile_rect: Rect2i, metrics: Dictionary) -> Rect2:
	var center_offset: int = _full_radius_chunks
	var map_origin: Vector2 = metrics.get("map_origin", Vector2.ZERO) as Vector2
	var chunk_size_px: float = float(metrics.get("chunk_size_px", 0.0))
	var tile_size_px: float = chunk_size_px / float(WorldRuntimeConstants.CHUNK_SIZE)
	var chunk_coord: Vector2i = WorldRuntimeConstants.tile_to_chunk(tile_rect.position)
	var local_coord: Vector2i = WorldRuntimeConstants.tile_to_local(tile_rect.position)
	var chunk_delta: Vector2i = chunk_coord - _center_chunk_coord
	return Rect2(
		map_origin + Vector2(
			(float(chunk_delta.x + center_offset) * chunk_size_px) + float(local_coord.x) * tile_size_px,
			(float(chunk_delta.y + center_offset) * chunk_size_px) + float(local_coord.y) * tile_size_px
		),
		Vector2(
			float(tile_rect.size.x) * tile_size_px,
			float(tile_rect.size.y) * tile_size_px
		)
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

func _resolve_zoom_factor() -> float:
	if _zoom_level_index < 0 or _zoom_level_index >= ZOOM_LEVELS.size():
		return 1.0
	return float(ZOOM_LEVELS[_zoom_level_index])

func _step_zoom(direction: int) -> void:
	var target_index: int = clampi(
		_zoom_level_index + direction,
		0,
		ZOOM_LEVELS.size() - 1
	)
	if target_index == _zoom_level_index:
		return
	_zoom_level_index = target_index
	queue_redraw()

func _can_pan() -> bool:
	return _resolve_zoom_factor() > 1.0
