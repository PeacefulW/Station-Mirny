class_name WorldOverviewCanvas
extends Control

const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const BACKGROUND_COLOR: Color = Color(0.045, 0.055, 0.065, 0.96)
const MAP_BACKGROUND_COLOR: Color = Color(0.025, 0.035, 0.045, 1.0)
const FRAME_COLOR: Color = Color(0.92, 0.73, 0.43, 0.28)
const WRAP_HINT_COLOR: Color = Color(0.92, 0.73, 0.43, 0.62)
const LOADING_SWEEP_COLOR: Color = Color(0.92, 0.73, 0.43, 0.10)
const DETAIL_REGION_FILL: Color = Color(0.92, 0.73, 0.43, 0.12)
const DETAIL_REGION_OUTLINE: Color = Color(1.0, 0.83, 0.50, 0.92)
const SPAWN_MARKER_COLOR: Color = Color(1.0, 0.96, 0.74, 1.0)
const SPAWN_MARKER_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.65)
const MAP_PADDING: float = 10.0

var _overview_texture: Texture2D = null
var _expected_aspect: float = 2.0
var _world_width_tiles: int = 4096
var _world_height_tiles: int = 2048
var _center_chunk_coord: Vector2i = Vector2i.ZERO
var _spawn_tile: Vector2i = Vector2i.ZERO
var _detail_radius_chunks: int = 0
var _has_detail_context: bool = false
var _is_loading: bool = false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func reset_overview(world_bounds: WorldBoundsSettings = null) -> void:
	_overview_texture = null
	_world_width_tiles = maxi(1, world_bounds.width_tiles if world_bounds != null else 4096)
	_world_height_tiles = maxi(1, world_bounds.height_tiles if world_bounds != null else 2048)
	_expected_aspect = _resolve_world_aspect(world_bounds)
	_has_detail_context = false
	set_loading(false)
	queue_redraw()

func set_detail_region_context(
	center_chunk_coord: Vector2i,
	spawn_tile: Vector2i,
	full_radius_chunks: int
) -> void:
	_center_chunk_coord = center_chunk_coord
	_spawn_tile = spawn_tile
	_detail_radius_chunks = maxi(full_radius_chunks, 0)
	_has_detail_context = true
	queue_redraw()

func clear_detail_region_context() -> void:
	_has_detail_context = false
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
	_draw_detail_region_overlay(map_rect)
	_draw_spawn_marker(map_rect)
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

func _draw_detail_region_overlay(map_rect: Rect2) -> void:
	if not _has_detail_context:
		return
	var chunk_span: int = _detail_radius_chunks * 2 + 1
	if chunk_span <= 0:
		return
	var region_size_tiles: int = chunk_span * WorldRuntimeConstants.CHUNK_SIZE
	var start_tile_x: int = (_center_chunk_coord.x - _detail_radius_chunks) * WorldRuntimeConstants.CHUNK_SIZE
	var start_tile_y: int = (_center_chunk_coord.y - _detail_radius_chunks) * WorldRuntimeConstants.CHUNK_SIZE
	var end_tile_y: int = start_tile_y + region_size_tiles
	var clipped_start_y: int = clampi(start_tile_y, 0, _world_height_tiles)
	var clipped_end_y: int = clampi(end_tile_y, 0, _world_height_tiles)
	if clipped_start_y >= clipped_end_y:
		return
	if region_size_tiles >= _world_width_tiles:
		_draw_detail_region_segment(map_rect, 0, _world_width_tiles, clipped_start_y, clipped_end_y)
		return
	var canonical_start_x: int = posmod(start_tile_x, _world_width_tiles)
	var first_width: int = mini(region_size_tiles, _world_width_tiles - canonical_start_x)
	_draw_detail_region_segment(
		map_rect,
		canonical_start_x,
		canonical_start_x + first_width,
		clipped_start_y,
		clipped_end_y
	)
	var remaining_width: int = region_size_tiles - first_width
	if remaining_width > 0:
		_draw_detail_region_segment(map_rect, 0, remaining_width, clipped_start_y, clipped_end_y)

func _draw_detail_region_segment(
	map_rect: Rect2,
	start_tile_x: int,
	end_tile_x: int,
	start_tile_y: int,
	end_tile_y: int
) -> void:
	var region_rect := Rect2(
		Vector2(
			_tile_x_to_map_x(start_tile_x, map_rect),
			_tile_y_to_map_y(start_tile_y, map_rect)
		),
		Vector2(
			_tile_x_to_map_x(end_tile_x, map_rect) - _tile_x_to_map_x(start_tile_x, map_rect),
			_tile_y_to_map_y(end_tile_y, map_rect) - _tile_y_to_map_y(start_tile_y, map_rect)
		)
	)
	if region_rect.size.x <= 0.0 or region_rect.size.y <= 0.0:
		return
	draw_rect(region_rect, DETAIL_REGION_FILL, true)
	draw_rect(region_rect, DETAIL_REGION_OUTLINE, false, 2.0)

func _draw_spawn_marker(map_rect: Rect2) -> void:
	if not _has_detail_context:
		return
	var spawn_pos := Vector2(
		_tile_x_to_map_x(posmod(_spawn_tile.x, _world_width_tiles) + 0.5, map_rect),
		_tile_y_to_map_y(clampf(float(_spawn_tile.y) + 0.5, 0.0, float(_world_height_tiles)), map_rect)
	)
	var marker_half: float = clampf(minf(map_rect.size.x, map_rect.size.y) * 0.045, 4.0, 8.0)
	draw_circle(spawn_pos, marker_half + 2.0, SPAWN_MARKER_SHADOW)
	draw_line(spawn_pos + Vector2(-marker_half, 0.0), spawn_pos + Vector2(marker_half, 0.0), SPAWN_MARKER_COLOR, 2.0)
	draw_line(spawn_pos + Vector2(0.0, -marker_half), spawn_pos + Vector2(0.0, marker_half), SPAWN_MARKER_COLOR, 2.0)
	draw_circle(spawn_pos, clampf(marker_half * 0.35, 1.5, 3.0), SPAWN_MARKER_COLOR)

func _tile_x_to_map_x(tile_x: float, map_rect: Rect2) -> float:
	return map_rect.position.x + (tile_x / float(_world_width_tiles)) * map_rect.size.x

func _tile_y_to_map_y(tile_y: float, map_rect: Rect2) -> float:
	return map_rect.position.y + (tile_y / float(_world_height_tiles)) * map_rect.size.y

func _resolve_world_aspect(world_bounds: WorldBoundsSettings) -> float:
	if world_bounds == null or world_bounds.height_tiles <= 0:
		return 2.0
	return float(world_bounds.width_tiles) / float(world_bounds.height_tiles)
