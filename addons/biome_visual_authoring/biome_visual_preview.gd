@tool
extends Node2D

## WYSIWYG preview for Variant D rock authoring.
##
## Left click — paint rock cell.
## Right click — erase rock cell.
## LMB drag — paint continuously.
## Ctrl+R — clear mask.
## Ctrl+F — fill bounding rectangle.
##
## Run via F6 (Play This Scene) so Control's gui_input fires — the 2D editor
## viewport eats mouse events otherwise.
##
## Architecture: one mask texture + one big rectangle polygon covering the
## rock bbox, with rock_variant_d.gdshader doing context-aware per-cell
## zone classification and discarding non-rock fragments. Outlines come
## from RockMarchingSquares polylines drawn as Line2D. This is the same
## path used by ChunkView in-game — parity by construction.

const ROCK_VARIANT_D_SHADER: Shader = preload("res://assets/shaders/rock_variant_d.gdshader")
const MASK_SIZE: int = 16
const TILE_PX: float = 24.0
const ROCK_MASK_VALUE: int = 1

@export var biome_visual: RockVisualResource:
	set(value):
		if _biome_visual == value:
			return
		if _biome_visual != null and _biome_visual.changed.is_connected(_on_resource_changed):
			_biome_visual.changed.disconnect(_on_resource_changed)
		_biome_visual = value
		if _biome_visual != null and not _biome_visual.changed.is_connected(_on_resource_changed):
			_biome_visual.changed.connect(_on_resource_changed)
		_apply_color_uniforms()
	get:
		return _biome_visual

@export var seed_mask: PackedInt32Array = PackedInt32Array():
	set(value):
		seed_mask = value
		if is_inside_tree():
			_reset_mask_from_seed()
			_rebuild_view()

var _biome_visual: RockVisualResource
var _shader_material: ShaderMaterial = null
var _rock_marching_squares: Object = null
var _mask: PackedInt32Array = PackedInt32Array()
var _mask_texture: ImageTexture = null
var _mask_image: Image = null
var _sdf_texture: ImageTexture = null
var _is_painting: bool = false
var _paint_value: int = ROCK_MASK_VALUE

@onready var _background: ColorRect = $PreviewRect
@onready var _mask_grid: Node2D = $MaskGrid
@onready var _fill_layer: Node2D = $FillLayer
@onready var _outline_layer: Node2D = $OutlineLayer
@onready var _input_overlay: Control = $InputOverlay


func _ready() -> void:
	_reset_mask_from_seed()
	_ensure_mask_texture()
	if is_instance_valid(_input_overlay):
		_input_overlay.gui_input.connect(_on_overlay_gui_input)
		_input_overlay.focus_mode = Control.FOCUS_ALL
		_input_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		_input_overlay.position = Vector2.ZERO
		_input_overlay.size = Vector2(MASK_SIZE * TILE_PX, MASK_SIZE * TILE_PX)
	_shader_material = _make_shader_material()
	_apply_color_uniforms()
	_rebuild_view()


func _on_resource_changed() -> void:
	_apply_color_uniforms()


# --- Mask management ---

func _reset_mask_from_seed() -> void:
	_mask.resize(MASK_SIZE * MASK_SIZE)
	for i: int in range(_mask.size()):
		_mask[i] = 0
	if seed_mask.is_empty():
		_apply_default_seed()
		return
	var copy_count: int = mini(seed_mask.size(), _mask.size())
	for i: int in range(copy_count):
		_mask[i] = ROCK_MASK_VALUE if int(seed_mask[i]) == ROCK_MASK_VALUE else 0


func _apply_default_seed() -> void:
	var default_cells: Array = [
		Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5),
		Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6),
		Vector2i(9, 6), Vector2i(10, 6),
		Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7),
		Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7),
		Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8),
		Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8),
		Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(8, 9),
		Vector2i(9, 9), Vector2i(10, 9),
		Vector2i(6, 10), Vector2i(7, 10), Vector2i(8, 10), Vector2i(9, 10),
		Vector2i(7, 11), Vector2i(8, 11),
	]
	for cell: Vector2i in default_cells:
		_set_mask_cell(cell, ROCK_MASK_VALUE)


func _set_mask_cell(cell: Vector2i, value: int) -> bool:
	if cell.x < 0 or cell.x >= MASK_SIZE or cell.y < 0 or cell.y >= MASK_SIZE:
		return false
	var index: int = cell.y * MASK_SIZE + cell.x
	if _mask[index] == value:
		return false
	_mask[index] = value
	return true


# --- Input handling (paint / erase) ---

func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var btn: InputEventMouseButton = event
		if btn.button_index == MOUSE_BUTTON_LEFT:
			if btn.pressed:
				_begin_paint(btn.position, ROCK_MASK_VALUE)
			else:
				_end_paint()
		elif btn.button_index == MOUSE_BUTTON_RIGHT:
			if btn.pressed:
				_begin_paint(btn.position, 0)
			else:
				_end_paint()
	elif event is InputEventMouseMotion and _is_painting:
		var mm: InputEventMouseMotion = event
		_paint_at_position(mm.position, _paint_value)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		if key.ctrl_pressed and key.keycode == KEY_R:
			_clear_mask()
		elif key.ctrl_pressed and key.keycode == KEY_F:
			_fill_bounding_box()


func _begin_paint(local_position: Vector2, value: int) -> void:
	_is_painting = true
	_paint_value = value
	_paint_at_position(local_position, value)


func _end_paint() -> void:
	_is_painting = false


func _paint_at_position(local_position: Vector2, value: int) -> void:
	var cell := Vector2i(int(local_position.x / TILE_PX), int(local_position.y / TILE_PX))
	if _set_mask_cell(cell, value):
		_rebuild_view()


func _clear_mask() -> void:
	for i: int in range(_mask.size()):
		_mask[i] = 0
	_rebuild_view()


func _fill_bounding_box() -> void:
	var bounds: Rect2i = _compute_mask_bounds()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	for y: int in range(bounds.position.y, bounds.position.y + bounds.size.y):
		for x: int in range(bounds.position.x, bounds.position.x + bounds.size.x):
			_mask[y * MASK_SIZE + x] = ROCK_MASK_VALUE
	_rebuild_view()


# --- View rebuild ---

func _rebuild_view() -> void:
	if not is_instance_valid(_fill_layer) or not is_instance_valid(_outline_layer):
		return
	_clear_children(_fill_layer)
	_clear_children(_outline_layer)
	_clear_children(_mask_grid)

	_render_mask_debug_grid()
	_update_mask_texture()
	_update_sdf_texture()

	var bounds: Rect2i = _compute_mask_bounds()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return

	_spawn_unified_rock_polygon(bounds)
	_spawn_outlines()


func _compute_mask_bounds() -> Rect2i:
	var min_cell := Vector2i(MASK_SIZE, MASK_SIZE)
	var max_cell := Vector2i(-1, -1)
	for y: int in range(MASK_SIZE):
		for x: int in range(MASK_SIZE):
			if _mask[y * MASK_SIZE + x] == ROCK_MASK_VALUE:
				min_cell.x = mini(min_cell.x, x)
				min_cell.y = mini(min_cell.y, y)
				max_cell.x = maxi(max_cell.x, x)
				max_cell.y = maxi(max_cell.y, y)
	if max_cell.x < 0:
		return Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


# --- Single unified rock polygon ---

func _spawn_unified_rock_polygon(bounds: Rect2i) -> void:
	var bbox_min := Vector2(float(bounds.position.x), float(bounds.position.y))
	var bbox_max := Vector2(
		float(bounds.position.x + bounds.size.x),
		float(bounds.position.y + bounds.size.y)
	)
	var rect_pixels := PackedVector2Array([
		bbox_min * TILE_PX,
		Vector2(bbox_max.x, bbox_min.y) * TILE_PX,
		bbox_max * TILE_PX,
		Vector2(bbox_min.x, bbox_max.y) * TILE_PX,
	])
	var rect_uv := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	var polygon := Polygon2D.new()
	polygon.polygon = rect_pixels
	polygon.uv = rect_uv
	# polygon.texture binds the SDF as TEXTURE — shader reads it via texture(TEXTURE, uv).
	# Polygon2D needs an assigned texture or canvas_item UV interpolation gets stripped.
	polygon.texture = _sdf_texture
	polygon.material = _shader_material
	_shader_material.set_shader_parameter("bbox_min", bbox_min)
	_shader_material.set_shader_parameter("bbox_max", bbox_max)
	_shader_material.set_shader_parameter("mask_size", Vector2(MASK_SIZE, MASK_SIZE))
	_shader_material.set_shader_parameter("sdf_max_dist", SdfHelper.max_dist_for(MASK_SIZE, MASK_SIZE))
	_fill_layer.add_child(polygon)


# --- Outlines (all polylines, outer + inner holes) ---

func _spawn_outlines() -> void:
	var polylines: Array = _extract_polylines()
	for polyline_variant: Variant in polylines:
		var polyline: PackedVector2Array = polyline_variant as PackedVector2Array
		if polyline.size() < 2:
			continue
		var pixels := PackedVector2Array()
		pixels.resize(polyline.size())
		for i: int in range(polyline.size()):
			pixels[i] = polyline[i] * TILE_PX
		var line := Line2D.new()
		line.points = pixels
		line.closed = polyline.size() > 2
		line.width = 2.0
		line.default_color = Color(0.05, 0.05, 0.06, 0.85)
		_outline_layer.add_child(line)


func _extract_polylines() -> Array:
	var marching_squares: Object = _ensure_rock_marching_squares()
	if marching_squares == null:
		return []
	var result: Variant = marching_squares.call(
		"extract_polylines",
		_mask,
		MASK_SIZE,
		MASK_SIZE,
		ROCK_MASK_VALUE
	)
	return result as Array


func _ensure_rock_marching_squares() -> Object:
	if _rock_marching_squares != null and is_instance_valid(_rock_marching_squares):
		return _rock_marching_squares
	if not ClassDB.class_exists(&"RockMarchingSquares"):
		push_warning("RockMarchingSquares native class missing — preview shows only the mask grid. Build the GDExtension.")
		return null
	_rock_marching_squares = ClassDB.instantiate(&"RockMarchingSquares")
	return _rock_marching_squares


# --- Mask texture ---

func _ensure_mask_texture() -> void:
	if _mask_image == null:
		_mask_image = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8)
	if _mask_texture == null:
		_mask_texture = ImageTexture.create_from_image(_mask_image)


func _update_mask_texture() -> void:
	_ensure_mask_texture()
	for y: int in range(MASK_SIZE):
		for x: int in range(MASK_SIZE):
			var is_rock: bool = _mask[y * MASK_SIZE + x] == ROCK_MASK_VALUE
			_mask_image.set_pixel(x, y, Color(1.0 if is_rock else 0.0, 0.0, 0.0, 1.0))
	_mask_texture.update(_mask_image)


func _update_sdf_texture() -> void:
	var sdf_image: Image = SdfHelper.compute_sdf_image(_mask, MASK_SIZE, MASK_SIZE)
	if _sdf_texture == null:
		_sdf_texture = ImageTexture.create_from_image(sdf_image)
	else:
		_sdf_texture.update(sdf_image)


# --- Debug mask grid (paint surface backdrop) ---

func _render_mask_debug_grid() -> void:
	for y: int in range(MASK_SIZE):
		for x: int in range(MASK_SIZE):
			var rect := ColorRect.new()
			rect.position = Vector2(x, y) * TILE_PX
			rect.size = Vector2(TILE_PX - 1, TILE_PX - 1)
			var is_rock: bool = _mask[y * MASK_SIZE + x] == ROCK_MASK_VALUE
			rect.color = (
				Color(0.18, 0.16, 0.14, 1.0) if is_rock
				else Color(0.12, 0.13, 0.12, 1.0)
			)
			_mask_grid.add_child(rect)


# --- Material wiring ---

func _make_shader_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ROCK_VARIANT_D_SHADER
	return material


func _apply_color_uniforms() -> void:
	if _shader_material == null:
		return
	if _biome_visual == null:
		return
	_shader_material.set_shader_parameter("top_color", _biome_visual.top_color)
	_shader_material.set_shader_parameter("face_color", _biome_visual.face_color)
	_shader_material.set_shader_parameter("back_color", _biome_visual.back_color)
	_shader_material.set_shader_parameter("ledge_contrast", _biome_visual.ledge_contrast)
	_shader_material.set_shader_parameter("normal_strength", _biome_visual.normal_strength)
	# Legacy uniforms kept for compatibility with existing .tres.
	_shader_material.set_shader_parameter("top_to_face_cutoff", _biome_visual.top_to_face_cutoff)
	_shader_material.set_shader_parameter("face_to_back_cutoff", _biome_visual.face_to_back_cutoff)
	_shader_material.set_shader_parameter("top_coverage", _biome_visual.top_coverage)
	_shader_material.set_shader_parameter("face_coverage", _biome_visual.face_coverage)
	_shader_material.set_shader_parameter("back_coverage", _biome_visual.back_coverage)


# --- Helpers ---

func _clear_children(node: Node) -> void:
	if not is_instance_valid(node):
		return
	for child: Node in node.get_children():
		child.queue_free()
