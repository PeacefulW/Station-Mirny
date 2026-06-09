class_name WorldDecorBatchLayer
extends Node2D

const ATLAS_BATCH_SHADER = preload("res://assets/shaders/world_decor_atlas_batch.gdshader")
const SHADOW_BATCH_SHADER = preload("res://assets/shaders/world_decor_shadow_batch.gdshader")

const BUFFER_STRIDE: int = 12
const BUFFER_X: int = 0
const BUFFER_Y: int = 1
const BUFFER_SIZE_X: int = 2
const BUFFER_SIZE_Y: int = 3
const BUFFER_FRAME_INDEX: int = 4
const BUFFER_TINT_R: int = 5
const BUFFER_TINT_G: int = 6
const BUFFER_TINT_B: int = 7
const BUFFER_TINT_A: int = 8
const BUFFER_WIND_AMPLITUDE: int = 9
const BUFFER_WIND_PHASE: int = 10
const BUFFER_SHADOW_SCALE: int = 11

const DEPTH_BUCKET_COUNT: int = 8
const DEFAULT_ATLAS_COLUMNS: int = 8
const DEFAULT_ATLAS_ROWS: int = 4
const DEFAULT_ATLAS_FRAME_COUNT: int = 32
const FRAME_COLOR_SCALE: float = 255.0
const CONTACT_SHADOW_Z_INDEX: int = 4
const DECOR_SPRITE_Z_INDEX: int = 5
const DECOR_SPRITE_BEHIND_PLAYER_Z_INDEX: int = 5
const DECOR_SPRITE_FRONT_PLAYER_Z_INDEX: int = 7
const CONTACT_SHADOW_BASE_OPACITY: float = 0.30
const CONTACT_SHADOW_SUN_OPACITY_SCALE: float = 0.08
const CONTACT_SHADOW_MAX_OPACITY: float = 0.40

static var _shared_unit_texture: ImageTexture = null

var _sprite_layers_by_atlas: Array = []
var _shadow_layer: MultiMeshInstance2D = null
var _shadow_material: ShaderMaterial = null
var _instance_count: int = 0
var _shadow_instance_count: int = 0
var _atlas_columns: int = DEFAULT_ATLAS_COLUMNS
var _atlas_rows: int = DEFAULT_ATLAS_ROWS
var _atlas_frame_count: int = DEFAULT_ATLAS_FRAME_COUNT
var _chunk_size_px: float = 1024.0
var _animation_frames_per_group: int = 1
var _animation_fps: float = 0.0
var _depth_reference_enabled: bool = false
var _depth_chunk_origin_y: float = 0.0
var _depth_reference_world_y: float = 0.0

func set_atlas_layout(columns: int, rows: int, frame_count: int) -> void:
	_atlas_columns = maxi(1, columns)
	_atlas_rows = maxi(1, rows)
	_atlas_frame_count = maxi(1, frame_count)
	_update_sprite_material_layouts()

func set_chunk_size_px(chunk_size_px: float) -> void:
	_chunk_size_px = maxf(1.0, chunk_size_px)
	_update_sprite_layer_depth_indices()

func set_depth_sort_reference(chunk_origin_world_y: float, reference_world_y: float) -> void:
	_depth_reference_enabled = true
	_depth_chunk_origin_y = chunk_origin_world_y
	_depth_reference_world_y = reference_world_y
	_update_sprite_layer_depth_indices()

func set_animation(frames_per_group: int, fps: float) -> void:
	_animation_frames_per_group = maxi(1, frames_per_group)
	_animation_fps = maxf(0.0, fps)
	_update_sprite_material_layouts()

func clear_batches() -> void:
	_instance_count = 0
	_shadow_instance_count = 0
	visible = false
	for layer_group: Array in _sprite_layers_by_atlas:
		for layer: MultiMeshInstance2D in layer_group:
			layer.visible = false
			layer.multimesh = null
	if _shadow_layer != null and is_instance_valid(_shadow_layer):
		_shadow_layer.visible = false
		_shadow_layer.multimesh = null

func set_batches(
	atlases: Array[Texture2D],
	instance_buffers_by_atlas: Array,
	shadow_buffer: PackedFloat32Array
) -> void:
	_instance_count = 0
	_shadow_instance_count = _buffer_instance_count(shadow_buffer)
	_sync_shadow_batch(shadow_buffer)
	for atlas_index: int in range(maxi(_sprite_layers_by_atlas.size(), atlases.size())):
		if atlas_index >= atlases.size():
			_hide_sprite_layers_for_atlas(atlas_index)
			continue
		var atlas: Texture2D = atlases[atlas_index]
		var buffer: PackedFloat32Array = PackedFloat32Array()
		if atlas_index < instance_buffers_by_atlas.size():
			buffer = instance_buffers_by_atlas[atlas_index]
		_sync_sprite_atlas_batch(atlas_index, atlas, buffer)
	visible = _instance_count > 0 or _shadow_instance_count > 0

func set_sun_lighting(
	light_angle_deg: float,
	shadow_length_px: float,
	shadow_opacity: float,
	shadow_softness_px: float
) -> void:
	var material: ShaderMaterial = _ensure_shadow_material()
	material.set_shader_parameter("shadow_angle_rad", deg_to_rad(light_angle_deg + 180.0))
	material.set_shader_parameter("shadow_length_px", 0.0)
	material.set_shader_parameter(
		"shadow_opacity",
		clampf(
			CONTACT_SHADOW_BASE_OPACITY + shadow_opacity * CONTACT_SHADOW_SUN_OPACITY_SCALE,
			0.0,
			CONTACT_SHADOW_MAX_OPACITY
		)
	)
	material.set_shader_parameter("shadow_softness_px", maxf(1.0, shadow_softness_px))

func set_wind(wind_time: float, wind_direction: Vector2, wind_strength_px: float) -> void:
	var safe_direction: Vector2 = wind_direction.normalized()
	if safe_direction == Vector2.ZERO:
		safe_direction = Vector2.RIGHT
	for layer_group: Array in _sprite_layers_by_atlas:
		for layer: MultiMeshInstance2D in layer_group:
			var material: ShaderMaterial = layer.material as ShaderMaterial
			if material == null:
				continue
			material.set_shader_parameter("wind_time", wind_time)
			material.set_shader_parameter("wind_direction", safe_direction)
			material.set_shader_parameter("wind_strength_px", maxf(0.0, wind_strength_px))

func get_debug_state() -> Dictionary:
	return {
		"instance_count": _instance_count,
		"shadow_instance_count": _shadow_instance_count,
		"sprite_layer_group_count": _sprite_layers_by_atlas.size(),
		"uses_multimesh": true,
	}

static func append_instance(
	buffer: PackedFloat32Array,
	position: Vector2,
	size: Vector2,
	frame_index: int,
	tint: Color,
	wind_amplitude: float,
	wind_phase: float,
	shadow_scale: float
) -> void:
	buffer.append(position.x)
	buffer.append(position.y)
	buffer.append(size.x)
	buffer.append(size.y)
	buffer.append(float(frame_index))
	buffer.append(tint.r)
	buffer.append(tint.g)
	buffer.append(tint.b)
	buffer.append(tint.a)
	buffer.append(wind_amplitude)
	buffer.append(wind_phase)
	buffer.append(shadow_scale)

func _sync_sprite_atlas_batch(atlas_index: int, atlas: Texture2D, buffer: PackedFloat32Array) -> void:
	var layers: Array = _ensure_sprite_layers_for_atlas(atlas_index)
	var bucket_buffers: Array = _split_buffer_by_depth_bucket(buffer)
	for bucket_index: int in range(DEPTH_BUCKET_COUNT):
		var layer: MultiMeshInstance2D = layers[bucket_index] as MultiMeshInstance2D
		var bucket_buffer: PackedFloat32Array = bucket_buffers[bucket_index] as PackedFloat32Array
		var count: int = _buffer_instance_count(bucket_buffer)
		_instance_count += count
		_apply_buffer_to_layer(layer, atlas, bucket_buffer, false)

func _sync_shadow_batch(shadow_buffer: PackedFloat32Array) -> void:
	var layer: MultiMeshInstance2D = _ensure_shadow_layer()
	_apply_buffer_to_layer(layer, _get_unit_texture(), shadow_buffer, true)

func _apply_buffer_to_layer(
	layer: MultiMeshInstance2D,
	texture: Texture2D,
	buffer: PackedFloat32Array,
	is_shadow: bool
) -> void:
	var count: int = _buffer_instance_count(buffer)
	if count <= 0 or texture == null:
		layer.visible = false
		layer.multimesh = null
		return
	var multimesh: MultiMesh = _create_multimesh(count)
	for instance_index: int in range(count):
		var offset: int = instance_index * BUFFER_STRIDE
		var position := Vector2(buffer[offset + BUFFER_X], buffer[offset + BUFFER_Y])
		var size := Vector2(buffer[offset + BUFFER_SIZE_X], buffer[offset + BUFFER_SIZE_Y])
		var transform: Transform2D = _make_transform(position, size)
		multimesh.set_instance_transform_2d(instance_index, transform)
		var tint: float = (
			buffer[offset + BUFFER_TINT_R]
			+ buffer[offset + BUFFER_TINT_G]
			+ buffer[offset + BUFFER_TINT_B]
		) / 3.0
		if is_shadow:
			multimesh.set_instance_color(instance_index, Color(
				clampf(buffer[offset + BUFFER_SHADOW_SCALE] / 4.0, 0.0, 1.0),
				1.0 / maxf(1.0, size.x),
				1.0 / maxf(1.0, size.y),
				clampf(buffer[offset + BUFFER_TINT_A], 0.0, 1.0)
			))
		else:
			multimesh.set_instance_color(instance_index, Color(
				clampf(buffer[offset + BUFFER_FRAME_INDEX] / FRAME_COLOR_SCALE, 0.0, 1.0),
				clampf(tint, 0.0, 1.0),
				clampf(buffer[offset + BUFFER_WIND_PHASE], 0.0, 1.0),
				clampf(buffer[offset + BUFFER_TINT_A], 0.0, 1.0)
			))
	layer.texture = texture
	layer.multimesh = multimesh
	layer.visible = true
	if is_shadow:
		layer.material = _ensure_shadow_material()

func _split_buffer_by_depth_bucket(buffer: PackedFloat32Array) -> Array:
	var bucket_buffers: Array = []
	for _bucket_index: int in range(DEPTH_BUCKET_COUNT):
		bucket_buffers.append(PackedFloat32Array())
	var count: int = _buffer_instance_count(buffer)
	for instance_index: int in range(count):
		var offset: int = instance_index * BUFFER_STRIDE
		var y_position: float = buffer[offset + BUFFER_Y] + buffer[offset + BUFFER_SIZE_Y] * 0.45
		var bucket_index: int = clampi(
			floori((y_position / _chunk_size_px) * float(DEPTH_BUCKET_COUNT)),
			0,
			DEPTH_BUCKET_COUNT - 1
		)
		var target_buffer: PackedFloat32Array = bucket_buffers[bucket_index]
		for stride_offset: int in range(BUFFER_STRIDE):
			target_buffer.append(buffer[offset + stride_offset])
		bucket_buffers[bucket_index] = target_buffer
	return bucket_buffers

func _ensure_sprite_layers_for_atlas(atlas_index: int) -> Array:
	while _sprite_layers_by_atlas.size() <= atlas_index:
		_sprite_layers_by_atlas.append([])
	var layers: Array = _sprite_layers_by_atlas[atlas_index] as Array
	while layers.size() < DEPTH_BUCKET_COUNT:
		var layer := MultiMeshInstance2D.new()
		layer.name = "DecorAtlas%dDepth%d" % [atlas_index, layers.size()]
		layer.z_as_relative = true
		layer.z_index = DECOR_SPRITE_Z_INDEX
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		layer.material = _make_sprite_material()
		layer.visible = false
		add_child(layer)
		layers.append(layer)
	_update_sprite_layer_depth_indices()
	return layers

func _ensure_shadow_layer() -> MultiMeshInstance2D:
	if _shadow_layer != null and is_instance_valid(_shadow_layer):
		return _shadow_layer
	_shadow_layer = MultiMeshInstance2D.new()
	_shadow_layer.name = "DecorShadowBatch"
	_shadow_layer.z_as_relative = true
	_shadow_layer.z_index = CONTACT_SHADOW_Z_INDEX
	_shadow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_shadow_layer.material = _ensure_shadow_material()
	_shadow_layer.visible = false
	add_child(_shadow_layer)
	return _shadow_layer

func _make_sprite_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ATLAS_BATCH_SHADER
	material.set_shader_parameter("atlas_columns", float(_atlas_columns))
	material.set_shader_parameter("atlas_rows", float(_atlas_rows))
	material.set_shader_parameter("atlas_frame_count", float(_atlas_frame_count))
	material.set_shader_parameter("animation_frames_per_group", float(_animation_frames_per_group))
	material.set_shader_parameter("animation_fps", _animation_fps)
	material.set_shader_parameter("wind_direction", Vector2.RIGHT)
	return material

func _ensure_shadow_material() -> ShaderMaterial:
	if _shadow_material != null:
		return _shadow_material
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = SHADOW_BATCH_SHADER
	return _shadow_material

func _update_sprite_material_layouts() -> void:
	for layer_group: Array in _sprite_layers_by_atlas:
		for layer: MultiMeshInstance2D in layer_group:
			var material: ShaderMaterial = layer.material as ShaderMaterial
			if material == null:
				continue
			material.set_shader_parameter("atlas_columns", float(_atlas_columns))
			material.set_shader_parameter("atlas_rows", float(_atlas_rows))
			material.set_shader_parameter("atlas_frame_count", float(_atlas_frame_count))
			material.set_shader_parameter("animation_frames_per_group", float(_animation_frames_per_group))
			material.set_shader_parameter("animation_fps", _animation_fps)

func _hide_sprite_layers_for_atlas(atlas_index: int) -> void:
	if atlas_index < 0 or atlas_index >= _sprite_layers_by_atlas.size():
		return
	var layers: Array = _sprite_layers_by_atlas[atlas_index] as Array
	for layer: MultiMeshInstance2D in layers:
		layer.visible = false
		layer.multimesh = null

static func _create_multimesh(instance_count: int) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = instance_count
	multimesh.visible_instance_count = instance_count
	return multimesh

static func _make_transform(position: Vector2, size: Vector2) -> Transform2D:
	return Transform2D(
		Vector2(size.x, 0.0),
		Vector2(0.0, size.y),
		position
	)

static func _buffer_instance_count(buffer: PackedFloat32Array) -> int:
	return buffer.size() / BUFFER_STRIDE

static func _get_unit_texture() -> Texture2D:
	if _shared_unit_texture != null:
		return _shared_unit_texture
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_shared_unit_texture = ImageTexture.create_from_image(image)
	return _shared_unit_texture

func _update_sprite_layer_depth_indices() -> void:
	for layer_group: Array in _sprite_layers_by_atlas:
		for bucket_index: int in range(layer_group.size()):
			var layer: MultiMeshInstance2D = layer_group[bucket_index] as MultiMeshInstance2D
			if layer == null:
				continue
			if not _depth_reference_enabled:
				layer.z_index = DECOR_SPRITE_Z_INDEX
				continue
			var bucket_center_y: float = _depth_chunk_origin_y \
				+ (float(bucket_index) + 0.5) / float(DEPTH_BUCKET_COUNT) * _chunk_size_px
			layer.z_index = DECOR_SPRITE_FRONT_PLAYER_Z_INDEX \
				if bucket_center_y > _depth_reference_world_y \
				else DECOR_SPRITE_BEHIND_PLAYER_Z_INDEX
