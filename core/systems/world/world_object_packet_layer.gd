class_name WorldObjectPacketLayer
extends Node2D

const WorldDecorBatchLayer = preload("res://core/systems/world/world_decor_batch_layer.gd")
const TREE_BATCH_SHADER = preload("res://assets/shaders/tree_decor_atlas_batch.gdshader")
const TREE_SHADOW_SHADER = preload("res://assets/shaders/tree_silhouette_shadow.gdshader")
const ObjectCollisionDebugLayer = preload("res://core/systems/world/object_collision_debug_layer.gd")

const OBJECT_KIND_ROCK: int = 1
const OBJECT_KIND_LIVING_FLORA: int = 2
const OBJECT_KIND_SPIKY_FLORA: int = 3
const OBJECT_KIND_TREE: int = 4
const OBJECT_KIND_BIG_GRASS_ROCK: int = 5
const OBJECT_KIND_GRASS_EDGE_SMALL_ROCK: int = 6
const OBJECT_FLAG_COLLIDER: int = 1 << 0
const OBJECT_LOCAL_PX_QUANTUM: float = 4.0

const ROCK_FRAME_COLUMNS: int = 8
const ROCK_FRAME_ROWS: int = 4
const ROCK_FRAME_COUNT: int = 32
const RARE_ROCK_FORMATION_ATLAS_INDEX: int = 3
const ROCK_COLLISION_LAYER: int = 2
const ROCK_COLLISION_RADIUS_SCALE: float = 0.32
const RARE_ROCK_FORMATION_VISUAL_SCALE: float = 2.35
const RARE_ROCK_FORMATION_COLLISION_RADIUS_SCALE: float = 0.08
const RARE_ROCK_FORMATION_COLLISION_CENTER_Y_SCALE: float = 0.42
const ROCK_SHADOW_WIDTH_SCALE: float = 0.92
const ROCK_SHADOW_HEIGHT_SCALE: float = 0.30
const ROCK_SHADOW_CENTER_Y_SCALE: float = 0.30
const ROCK_SHADOW_MIN_WIDTH_PX: float = 14.0
const ROCK_SHADOW_MIN_HEIGHT_PX: float = 6.0
const ROCK_SHADOW_MIN_PROJECTED_SCALE: float = 0.52

const LIVING_FLORA_FRAME_COLUMNS: int = 16
const LIVING_FLORA_FRAME_ROWS: int = 4
const LIVING_FLORA_FRAMES_PER_VIEW: int = 16
const LIVING_FLORA_FRAME_COUNT: int = LIVING_FLORA_FRAME_COLUMNS * LIVING_FLORA_FRAME_ROWS
const LIVING_FLORA_ANIMATION_FPS: float = 7.0
const LIVING_FLORA_SHADOW_WIDTH_SCALE: float = 0.42
const LIVING_FLORA_SHADOW_HEIGHT_SCALE: float = 0.13
const LIVING_FLORA_SHADOW_CENTER_Y_SCALE: float = 0.32
const LIVING_FLORA_SHADOW_MIN_WIDTH_PX: float = 10.0
const LIVING_FLORA_SHADOW_MIN_HEIGHT_PX: float = 4.0

const SPIKY_FLORA_FRAME_COLUMNS: int = 4
const SPIKY_FLORA_FRAME_ROWS: int = 1
const SPIKY_FLORA_FRAME_COUNT: int = 4

const TREE_FRAME_COLUMNS: int = 4
const TREE_FRAME_ROWS: int = 4
const TREE_FRAME_COUNT: int = 16
# Основание дерева в кадре атласа — на доле (frame-margin)/frame от верха. Спрайт
# центрируется в точке, поэтому сдвигаем его вверх на (frac-0.5)*size, чтобы комель
# лёг в точку земли; полоса depth-лесенки тогда падает на «ноги» (см. spec).
const TREE_BASE_ANCHOR_OFFSET_FRAC: float = 0.46875
const TREE_SHADOW_WIDTH_SCALE: float = 0.34
const TREE_SHADOW_HEIGHT_SCALE: float = 0.11
const TREE_SHADOW_CENTER_Y_SCALE: float = 0.02
const TREE_SHADOW_MIN_WIDTH_PX: float = 18.0
const TREE_SHADOW_MIN_HEIGHT_PX: float = 6.0
# Силуэт-тень — поверх ВСЕЙ травяной/объектной лесенки и поверх игрока
# (WorldRuntimeConstants.Z_CAST_SHADOW), а не под травой.
const TREE_SHADOW_Z_INDEX: int = WorldRuntimeConstants.Z_CAST_SHADOW
# Дерево — препятствие: маленький круг у комля (ствол), крона проходима.
# Chunk-scoped статика на том же obstacle-слое, что крупные камни (LAW 10:
# готово к reveal вместе с объектным слоем; шейп-овнеры на одном теле, не нода-на-дерево).
const TREE_COLLISION_ENABLED: bool = true
const TREE_COLLISION_RADIUS_SCALE: float = 0.065
const TREE_COLLISION_MIN_RADIUS_PX: float = 9.0
const TREE_COLLISION_MAX_RADIUS_PX: float = 20.0

const BIG_GRASS_ROCK_FRAME_COLUMNS: int = 1
const BIG_GRASS_ROCK_FRAME_ROWS: int = 1
const BIG_GRASS_ROCK_FRAME_COUNT: int = 1
const BIG_GRASS_ROCK_BASE_ANCHOR_OFFSET_FRAC: float = 0.22
const BIG_GRASS_ROCK_SHADOW_WIDTH_SCALE: float = 0.72
const BIG_GRASS_ROCK_SHADOW_HEIGHT_SCALE: float = 0.22
const BIG_GRASS_ROCK_SHADOW_CENTER_Y_SCALE: float = 0.18
const BIG_GRASS_ROCK_SHADOW_MIN_WIDTH_PX: float = 50.0
const BIG_GRASS_ROCK_SHADOW_MIN_HEIGHT_PX: float = 16.0
const BIG_GRASS_ROCK_COLLISION_RADIUS_SCALE: float = 0.14
const BIG_GRASS_ROCK_COLLISION_MIN_RADIUS_PX: float = 20.0
const BIG_GRASS_ROCK_COLLISION_MAX_RADIUS_PX: float = 34.0
const BIG_GRASS_ROCK_COLLISION_CENTER_Y_SCALE: float = 0.14
const GRASS_EDGE_SMALL_ROCK_SHADOW_WIDTH_SCALE: float = 0.76
const GRASS_EDGE_SMALL_ROCK_SHADOW_HEIGHT_SCALE: float = 0.22
const GRASS_EDGE_SMALL_ROCK_SHADOW_CENTER_Y_SCALE: float = 0.20
const GRASS_EDGE_SMALL_ROCK_SHADOW_MIN_WIDTH_PX: float = 5.0
const GRASS_EDGE_SMALL_ROCK_SHADOW_MIN_HEIGHT_PX: float = 2.0

var _rock_atlases: Array[Texture2D] = []
var _living_flora_atlas: Texture2D = null
var _spiky_flora_atlases: Array[Texture2D] = []
var _tree_atlas: Texture2D = null
var _big_grass_rock_atlases: Array[Texture2D] = []
var _grass_edge_small_rock_atlas: Texture2D = null
var _grass_edge_small_rock_atlas_columns: int = 1
var _grass_edge_small_rock_atlas_rows: int = 1
var _grass_edge_small_rock_frame_count: int = 1
var _rock_batch_layer: WorldDecorBatchLayer = null
var _living_flora_batch_layer: WorldDecorBatchLayer = null
var _spiky_flora_batch_layer: WorldDecorBatchLayer = null
var _tree_batch_layer: WorldDecorBatchLayer = null
var _big_grass_rock_batch_layer: WorldDecorBatchLayer = null
var _grass_edge_small_rock_batch_layer: WorldDecorBatchLayer = null
var _collision_body: StaticBody2D = null
var _collision_shape_owner_ids: Array[int] = []
var _tree_collision_body: StaticBody2D = null
var _tree_collision_shape_owner_ids: Array[int] = []
var _tree_collider_count: int = 0
var _big_grass_rock_collision_body: StaticBody2D = null
var _big_grass_rock_collision_shape_owner_ids: Array[int] = []
var _big_grass_rock_collider_count: int = 0
## Dev-оверлей коллизий (F11): рамки камней/валунов/деревьев, presentation only.
var _collision_debug_layer: ObjectCollisionDebugLayer = null
var _debug_collisions_visible: bool = false
var _rock_debug_rects: Array[Rect2] = []
var _tree_debug_rects: Array[Rect2] = []
var _big_grass_rock_debug_rects: Array[Rect2] = []
var _tree_shadow_layer: MultiMeshInstance2D = null
var _tree_shadow_material: ShaderMaterial = null
var _sun_light_angle_deg: float = 120.0
var _sun_shadow_length_px: float = 78.0
var _sun_shadow_opacity: float = 0.0
var _rock_count: int = 0
var _living_flora_count: int = 0
var _spiky_flora_count: int = 0
var _tree_count: int = 0
var _big_grass_rock_count: int = 0
var _grass_edge_small_rock_count: int = 0
var _collider_count: int = 0
var _world_origin_y: float = 0.0


func set_rock_atlases(atlases: Array[Texture2D]) -> void:
	_rock_atlases = atlases.duplicate()
	if _rock_batch_layer != null and is_instance_valid(_rock_batch_layer):
		_rock_batch_layer.clear_batches()


func set_living_flora_atlas(atlas: Texture2D) -> void:
	_living_flora_atlas = atlas
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.clear_batches()


func set_spiky_flora_atlas(atlas: Texture2D) -> void:
	if atlas == null:
		set_spiky_flora_atlases([])
	else:
		set_spiky_flora_atlases([atlas])


func set_spiky_flora_atlases(atlases: Array[Texture2D]) -> void:
	_spiky_flora_atlases = atlases.duplicate()
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.clear_batches()


func set_tree_atlas(atlas: Texture2D) -> void:
	_tree_atlas = atlas
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.clear_batches()


func set_big_grass_rock_atlases(atlases: Array[Texture2D]) -> void:
	_big_grass_rock_atlases = atlases.duplicate()
	if _big_grass_rock_batch_layer != null and is_instance_valid(_big_grass_rock_batch_layer):
		_big_grass_rock_batch_layer.clear_batches()


func set_grass_edge_small_rock_source(atlas: Texture2D, columns: int, rows: int, frame_count: int) -> void:
	_grass_edge_small_rock_atlas = atlas
	_grass_edge_small_rock_atlas_columns = maxi(1, columns)
	_grass_edge_small_rock_atlas_rows = maxi(1, rows)
	_grass_edge_small_rock_frame_count = maxi(1, frame_count)
	if _grass_edge_small_rock_batch_layer != null and is_instance_valid(_grass_edge_small_rock_batch_layer):
		_grass_edge_small_rock_batch_layer.clear_batches()


func set_sun_lighting(
		light_angle_deg: float,
		shadow_length_px: float,
		shadow_opacity: float,
		shadow_softness_px: float,
) -> void:
	if _rock_batch_layer != null and is_instance_valid(_rock_batch_layer):
		_rock_batch_layer.set_sun_lighting(
			light_angle_deg,
			shadow_length_px,
			shadow_opacity,
			shadow_softness_px,
		)
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.set_sun_lighting(
			light_angle_deg,
			shadow_length_px,
			shadow_opacity,
			shadow_softness_px,
		)
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.set_sun_lighting(
			light_angle_deg,
			shadow_length_px,
			shadow_opacity,
			shadow_softness_px,
		)
	if _big_grass_rock_batch_layer != null and is_instance_valid(_big_grass_rock_batch_layer):
		_big_grass_rock_batch_layer.set_sun_lighting(
			light_angle_deg,
			shadow_length_px,
			shadow_opacity,
			shadow_softness_px,
		)
	if _grass_edge_small_rock_batch_layer != null and is_instance_valid(_grass_edge_small_rock_batch_layer):
		_grass_edge_small_rock_batch_layer.set_sun_lighting(
			light_angle_deg,
			shadow_length_px,
			shadow_opacity,
			shadow_softness_px,
		)
	_sun_light_angle_deg = light_angle_deg
	_sun_shadow_length_px = shadow_length_px
	_sun_shadow_opacity = shadow_opacity
	_apply_sun_to_tree_shadow()


## Мировой Y чанка для глобальных полос depth-лесенки.
func set_world_origin_y(world_origin_y: float) -> void:
	_world_origin_y = world_origin_y
	_apply_world_origin_to_batch_layer(_rock_batch_layer)
	_apply_world_origin_to_batch_layer(_living_flora_batch_layer)
	_apply_world_origin_to_batch_layer(_spiky_flora_batch_layer)
	_apply_world_origin_to_batch_layer(_tree_batch_layer)
	_apply_world_origin_to_batch_layer(_big_grass_rock_batch_layer)
	_apply_world_origin_to_batch_layer(_grass_edge_small_rock_batch_layer)


## Перестановка полос объектного декора на player-relative лесенке.
func update_ladder_z(anchor_stripe: int) -> void:
	if _rock_batch_layer != null and is_instance_valid(_rock_batch_layer):
		_rock_batch_layer.update_ladder_z(anchor_stripe)
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.update_ladder_z(anchor_stripe)
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.update_ladder_z(anchor_stripe)
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.update_ladder_z(anchor_stripe)
	if _big_grass_rock_batch_layer != null and is_instance_valid(_big_grass_rock_batch_layer):
		_big_grass_rock_batch_layer.update_ladder_z(anchor_stripe)
	if _grass_edge_small_rock_batch_layer != null and is_instance_valid(_grass_edge_small_rock_batch_layer):
		_grass_edge_small_rock_batch_layer.update_ladder_z(anchor_stripe)


func configure_packet(packet: Dictionary) -> void:
	_rock_count = 0
	_living_flora_count = 0
	_spiky_flora_count = 0
	_tree_count = 0
	_big_grass_rock_count = 0
	_grass_edge_small_rock_count = 0
	_collider_count = 0
	_clear_collision_shapes()
	_clear_big_grass_rock_collision_shapes()
	var object_kind: PackedByteArray = packet.get("object_kind", PackedByteArray()) as PackedByteArray
	var object_x: PackedByteArray = packet.get("object_local_x_px_q4", PackedByteArray()) as PackedByteArray
	var object_y: PackedByteArray = packet.get("object_local_y_px_q4", PackedByteArray()) as PackedByteArray
	var object_size: PackedByteArray = packet.get("object_size_px", PackedByteArray()) as PackedByteArray
	var object_atlas: PackedByteArray = packet.get("object_atlas_index", PackedByteArray()) as PackedByteArray
	var object_variant: PackedByteArray = packet.get("object_variant", PackedByteArray()) as PackedByteArray
	var object_flags: PackedByteArray = packet.get("object_flags", PackedByteArray()) as PackedByteArray
	var object_tint: PackedByteArray = packet.get("object_tint", PackedByteArray()) as PackedByteArray
	var object_phase: PackedByteArray = packet.get("object_phase", PackedByteArray()) as PackedByteArray
	var object_count: int = _valid_object_count(
		[
			object_kind,
			object_x,
			object_y,
			object_size,
			object_atlas,
			object_variant,
			object_flags,
			object_tint,
			object_phase,
		],
	)
	if object_count <= 0:
		_clear_batches()
		return

	var rock_buffers: Array = []
	for _atlas_index: int in range(_rock_atlases.size()):
		rock_buffers.append(PackedFloat32Array())
	var rock_shadow_buffer := PackedFloat32Array()
	var rock_collision_records: Array[Dictionary] = []
	var living_buffer := PackedFloat32Array()
	var living_shadow_buffer := PackedFloat32Array()
	var spiky_buffers: Array = []
	for _atlas_index: int in range(_spiky_flora_atlases.size()):
		spiky_buffers.append(PackedFloat32Array())
	var empty_shadow_buffer := PackedFloat32Array()
	var tree_buffer := PackedFloat32Array()
	var tree_shadow_buffer := PackedFloat32Array()
	var tree_collision_records: Array[Dictionary] = []
	var big_grass_rock_buffers: Array = []
	for _atlas_index: int in range(_big_grass_rock_atlases.size()):
		big_grass_rock_buffers.append(PackedFloat32Array())
	var big_grass_rock_shadow_buffer := PackedFloat32Array()
	var big_grass_rock_collision_records: Array[Dictionary] = []
	var grass_edge_small_rock_buffer := PackedFloat32Array()
	var grass_edge_small_rock_shadow_buffer := PackedFloat32Array()
	for index: int in range(object_count):
		var kind: int = int(object_kind[index])
		var position := Vector2(_decode_local_px(object_x[index]), _decode_local_px(object_y[index]))
		var size_px: float = float(int(object_size[index]))
		var atlas_index: int = int(object_atlas[index])
		var frame_index: int = int(object_variant[index])
		var flags: int = int(object_flags[index])
		var tint_factor: float = float(int(object_tint[index])) / 255.0
		var phase: float = float(int(object_phase[index])) / 255.0
		match kind:
			OBJECT_KIND_ROCK:
				_append_rock(
					position,
					size_px,
					atlas_index,
					frame_index,
					flags,
					tint_factor,
					phase,
					rock_buffers,
					rock_shadow_buffer,
					rock_collision_records,
				)
			OBJECT_KIND_LIVING_FLORA:
				_append_living_flora(position, size_px, frame_index, tint_factor, phase, living_buffer, living_shadow_buffer)
			OBJECT_KIND_SPIKY_FLORA:
				_append_spiky_flora(position, size_px, atlas_index, frame_index, tint_factor, phase, spiky_buffers)
			OBJECT_KIND_TREE:
				_append_tree(position, size_px, frame_index, tint_factor, phase, tree_buffer, tree_shadow_buffer, tree_collision_records)
			OBJECT_KIND_BIG_GRASS_ROCK:
				_append_big_grass_rock(
					position,
					size_px,
					atlas_index,
					flags,
					tint_factor,
					phase,
					big_grass_rock_buffers,
					big_grass_rock_shadow_buffer,
					big_grass_rock_collision_records,
				)
			OBJECT_KIND_GRASS_EDGE_SMALL_ROCK:
				_append_grass_edge_small_rock(
					position,
					size_px,
					frame_index,
					tint_factor,
					phase,
					grass_edge_small_rock_buffer,
					grass_edge_small_rock_shadow_buffer,
				)

	_sync_rock_batches(rock_buffers, rock_shadow_buffer, rock_collision_records)
	_sync_living_flora_batch(living_buffer, living_shadow_buffer)
	_sync_spiky_flora_batch(spiky_buffers, empty_shadow_buffer)
	_sync_tree_batch(tree_buffer, tree_shadow_buffer)
	_sync_tree_collision(tree_collision_records)
	_sync_big_grass_rock_batch(big_grass_rock_buffers, big_grass_rock_shadow_buffer)
	_sync_big_grass_rock_collision(big_grass_rock_collision_records)
	_sync_grass_edge_small_rock_batch(grass_edge_small_rock_buffer, grass_edge_small_rock_shadow_buffer)
	visible = _rock_count > 0 \
			or _living_flora_count > 0 \
			or _spiky_flora_count > 0 \
			or _tree_count > 0 \
			or _big_grass_rock_count > 0 \
			or _grass_edge_small_rock_count > 0


func get_debug_state() -> Dictionary:
	return {
		"rock_count": _rock_count,
		"living_flora_count": _living_flora_count,
		"spiky_flora_count": _spiky_flora_count,
		"tree_count": _tree_count,
		"tree_collider_count": _tree_collider_count,
		"big_grass_rock_count": _big_grass_rock_count,
		"big_grass_rock_collider_count": _big_grass_rock_collider_count,
		"grass_edge_small_rock_count": _grass_edge_small_rock_count,
		"collider_count": _collider_count,
	}


func _append_rock(
		position: Vector2,
		size_px: float,
		atlas_index: int,
		frame_index: int,
		flags: int,
		tint_factor: float,
		phase: float,
		rock_buffers: Array,
		rock_shadow_buffer: PackedFloat32Array,
		collision_records: Array[Dictionary],
) -> void:
	if atlas_index < 0 or atlas_index >= rock_buffers.size():
		return
	var visual_size_px: float = size_px
	var visual_position: Vector2 = position
	if atlas_index == RARE_ROCK_FORMATION_ATLAS_INDEX:
		visual_size_px *= RARE_ROCK_FORMATION_VISUAL_SCALE
		visual_position.y -= (visual_size_px - size_px) * 0.5
	var sprite_buffer: PackedFloat32Array = rock_buffers[atlas_index]
	WorldDecorBatchLayer.append_instance(
		sprite_buffer,
		visual_position,
		Vector2.ONE * visual_size_px,
		frame_index,
		Color(tint_factor, tint_factor, tint_factor, 0.96),
		0.0,
		phase,
		visual_size_px / 64.0,
	)
	rock_buffers[atlas_index] = sprite_buffer
	var shadow_size := Vector2(
		maxf(size_px * ROCK_SHADOW_WIDTH_SCALE, ROCK_SHADOW_MIN_WIDTH_PX),
		maxf(size_px * ROCK_SHADOW_HEIGHT_SCALE, ROCK_SHADOW_MIN_HEIGHT_PX),
	)
	WorldDecorBatchLayer.append_instance(
		rock_shadow_buffer,
		position + Vector2(0.0, size_px * ROCK_SHADOW_CENTER_Y_SCALE),
		shadow_size,
		0,
		Color(1.0, 1.0, 1.0, 0.58 if atlas_index == RARE_ROCK_FORMATION_ATLAS_INDEX else 0.92),
		0.0,
		phase,
		maxf(size_px / 64.0, ROCK_SHADOW_MIN_PROJECTED_SCALE),
	)
	if (flags & OBJECT_FLAG_COLLIDER) != 0:
		var collision_radius: float = clampf(size_px * ROCK_COLLISION_RADIUS_SCALE, 10.0, 18.0)
		var collision_position: Vector2 = position + Vector2(0.0, size_px * 0.18)
		if atlas_index == RARE_ROCK_FORMATION_ATLAS_INDEX:
			collision_radius = clampf(size_px * RARE_ROCK_FORMATION_COLLISION_RADIUS_SCALE, 12.0, 24.0)
			collision_position = position + Vector2(0.0, size_px * RARE_ROCK_FORMATION_COLLISION_CENTER_Y_SCALE)
		collision_records.append(
			{
				"position": collision_position,
				"radius": collision_radius,
			},
		)
	_rock_count += 1


func _append_living_flora(
		position: Vector2,
		size_px: float,
		frame_index: int,
		tint_factor: float,
		phase: float,
		living_buffer: PackedFloat32Array,
		living_shadow_buffer: PackedFloat32Array,
) -> void:
	if _living_flora_atlas == null:
		return
	WorldDecorBatchLayer.append_instance(
		living_buffer,
		position,
		Vector2.ONE * size_px,
		frame_index,
		Color(tint_factor, tint_factor, tint_factor, 0.96),
		0.0,
		phase,
		size_px / 64.0,
	)
	var shadow_size := Vector2(
		maxf(size_px * LIVING_FLORA_SHADOW_WIDTH_SCALE, LIVING_FLORA_SHADOW_MIN_WIDTH_PX),
		maxf(size_px * LIVING_FLORA_SHADOW_HEIGHT_SCALE, LIVING_FLORA_SHADOW_MIN_HEIGHT_PX),
	)
	WorldDecorBatchLayer.append_instance(
		living_shadow_buffer,
		position + Vector2(0.0, size_px * LIVING_FLORA_SHADOW_CENTER_Y_SCALE),
		shadow_size,
		0,
		Color(1.0, 1.0, 1.0, 0.58),
		0.0,
		phase,
		maxf(size_px / 96.0, 0.36),
	)
	_living_flora_count += 1


func _append_spiky_flora(
		position: Vector2,
		size_px: float,
		atlas_index: int,
		frame_index: int,
		tint_factor: float,
		phase: float,
		spiky_buffers: Array,
) -> void:
	if atlas_index < 0 or atlas_index >= spiky_buffers.size():
		return
	var spiky_buffer: PackedFloat32Array = spiky_buffers[atlas_index]
	WorldDecorBatchLayer.append_instance(
		spiky_buffer,
		position,
		Vector2.ONE * size_px,
		frame_index,
		Color(tint_factor, tint_factor, tint_factor, 0.98),
		0.0,
		phase,
		size_px / 64.0,
	)
	spiky_buffers[atlas_index] = spiky_buffer
	_spiky_flora_count += 1


func _append_tree(
		position: Vector2,
		size_px: float,
		frame_index: int,
		tint_factor: float,
		phase: float,
		tree_buffer: PackedFloat32Array,
		tree_shadow_buffer: PackedFloat32Array,
		tree_collision_records: Array[Dictionary],
) -> void:
	if _tree_atlas == null:
		return
	# Спрайт центрируется в позиции → сдвигаем центр вверх, чтобы комель кадра лёг
	# в точку земли; полоса depth-лесенки тогда падает на «ноги» дерева.
	var sprite_position: Vector2 = position - Vector2(0.0, size_px * TREE_BASE_ANCHOR_OFFSET_FRAC)
	WorldDecorBatchLayer.append_instance(
		tree_buffer,
		sprite_position,
		Vector2.ONE * size_px,
		frame_index,
		Color(tint_factor, tint_factor, tint_factor, 1.0),
		0.0,
		phase,
		size_px / 64.0,
	)
	var shadow_size := Vector2(
		maxf(size_px * TREE_SHADOW_WIDTH_SCALE, TREE_SHADOW_MIN_WIDTH_PX),
		maxf(size_px * TREE_SHADOW_HEIGHT_SCALE, TREE_SHADOW_MIN_HEIGHT_PX),
	)
	WorldDecorBatchLayer.append_instance(
		tree_shadow_buffer,
		position + Vector2(0.0, size_px * TREE_SHADOW_CENTER_Y_SCALE),
		shadow_size,
		0,
		Color(1.0, 1.0, 1.0, 0.85),
		0.0,
		phase,
		maxf(size_px / 96.0, 0.42),
	)
	if TREE_COLLISION_ENABLED:
		tree_collision_records.append(
			{
				"position": position,
				"radius": clampf(size_px * TREE_COLLISION_RADIUS_SCALE, TREE_COLLISION_MIN_RADIUS_PX, TREE_COLLISION_MAX_RADIUS_PX),
			},
		)
	_tree_count += 1


func _append_big_grass_rock(
		position: Vector2,
		size_px: float,
		atlas_index: int,
		flags: int,
		tint_factor: float,
		phase: float,
		big_grass_rock_buffers: Array,
		big_grass_rock_shadow_buffer: PackedFloat32Array,
		big_grass_rock_collision_records: Array[Dictionary],
) -> void:
	if atlas_index < 0 or atlas_index >= big_grass_rock_buffers.size():
		return
	var sprite_position: Vector2 = position - Vector2(0.0, size_px * BIG_GRASS_ROCK_BASE_ANCHOR_OFFSET_FRAC)
	var sprite_buffer: PackedFloat32Array = big_grass_rock_buffers[atlas_index]
	WorldDecorBatchLayer.append_instance(
		sprite_buffer,
		sprite_position,
		Vector2.ONE * size_px,
		0,
		Color(tint_factor, tint_factor, tint_factor, 1.0),
		0.0,
		phase,
		size_px / 96.0,
	)
	big_grass_rock_buffers[atlas_index] = sprite_buffer
	var shadow_size := Vector2(
		maxf(size_px * BIG_GRASS_ROCK_SHADOW_WIDTH_SCALE, BIG_GRASS_ROCK_SHADOW_MIN_WIDTH_PX),
		maxf(size_px * BIG_GRASS_ROCK_SHADOW_HEIGHT_SCALE, BIG_GRASS_ROCK_SHADOW_MIN_HEIGHT_PX),
	)
	WorldDecorBatchLayer.append_instance(
		big_grass_rock_shadow_buffer,
		position + Vector2(0.0, size_px * BIG_GRASS_ROCK_SHADOW_CENTER_Y_SCALE),
		shadow_size,
		0,
		Color(1.0, 1.0, 1.0, 0.84),
		0.0,
		phase,
		maxf(size_px / 128.0, 0.62),
	)
	if (flags & OBJECT_FLAG_COLLIDER) != 0:
		big_grass_rock_collision_records.append(
			{
				"position": position + Vector2(0.0, size_px * BIG_GRASS_ROCK_COLLISION_CENTER_Y_SCALE),
				"radius": clampf(
					size_px * BIG_GRASS_ROCK_COLLISION_RADIUS_SCALE,
					BIG_GRASS_ROCK_COLLISION_MIN_RADIUS_PX,
					BIG_GRASS_ROCK_COLLISION_MAX_RADIUS_PX,
				),
			},
		)
	_big_grass_rock_count += 1


func _append_grass_edge_small_rock(
		position: Vector2,
		size_px: float,
		frame_index: int,
		tint_factor: float,
		phase: float,
		grass_edge_small_rock_buffer: PackedFloat32Array,
		grass_edge_small_rock_shadow_buffer: PackedFloat32Array,
) -> void:
	if _grass_edge_small_rock_atlas == null:
		return
	var safe_frame: int = clampi(frame_index, 0, _grass_edge_small_rock_frame_count - 1)
	WorldDecorBatchLayer.append_instance(
		grass_edge_small_rock_buffer,
		position,
		Vector2.ONE * size_px,
		safe_frame,
		Color(tint_factor, tint_factor, tint_factor, 0.94),
		0.0,
		phase,
		maxf(size_px / 96.0, 0.24),
	)
	var shadow_size := Vector2(
		maxf(size_px * GRASS_EDGE_SMALL_ROCK_SHADOW_WIDTH_SCALE, GRASS_EDGE_SMALL_ROCK_SHADOW_MIN_WIDTH_PX),
		maxf(size_px * GRASS_EDGE_SMALL_ROCK_SHADOW_HEIGHT_SCALE, GRASS_EDGE_SMALL_ROCK_SHADOW_MIN_HEIGHT_PX),
	)
	WorldDecorBatchLayer.append_instance(
		grass_edge_small_rock_shadow_buffer,
		position + Vector2(0.0, size_px * GRASS_EDGE_SMALL_ROCK_SHADOW_CENTER_Y_SCALE),
		shadow_size,
		0,
		Color(1.0, 1.0, 1.0, 0.42),
		0.0,
		phase,
		maxf(size_px / 128.0, 0.24),
	)
	_grass_edge_small_rock_count += 1


func _sync_rock_batches(
		rock_buffers: Array,
		rock_shadow_buffer: PackedFloat32Array,
		collision_records: Array[Dictionary],
) -> void:
	if _rock_atlases.is_empty() or _rock_count <= 0:
		if _rock_batch_layer != null and is_instance_valid(_rock_batch_layer):
			_rock_batch_layer.clear_batches()
		_clear_collision_shapes()
		_rock_debug_rects = []
		_sync_collision_debug_layer()
		return
	var batch_layer: WorldDecorBatchLayer = _ensure_rock_batch_layer()
	batch_layer.set_atlas_layout(ROCK_FRAME_COLUMNS, ROCK_FRAME_ROWS, ROCK_FRAME_COUNT)
	batch_layer.set_animation(1, 0.0)
	batch_layer.set_batches(_rock_atlases, rock_buffers, rock_shadow_buffer)
	_sync_collision_shapes(collision_records)


func _sync_living_flora_batch(living_buffer: PackedFloat32Array, living_shadow_buffer: PackedFloat32Array) -> void:
	if _living_flora_atlas == null or _living_flora_count <= 0:
		if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
			_living_flora_batch_layer.clear_batches()
		return
	var batch_layer: WorldDecorBatchLayer = _ensure_living_flora_batch_layer()
	batch_layer.set_atlas_layout(LIVING_FLORA_FRAME_COLUMNS, LIVING_FLORA_FRAME_ROWS, LIVING_FLORA_FRAME_COUNT)
	batch_layer.set_animation(LIVING_FLORA_FRAMES_PER_VIEW, LIVING_FLORA_ANIMATION_FPS)
	batch_layer.set_batches([_living_flora_atlas], [living_buffer], living_shadow_buffer)


func _sync_spiky_flora_batch(spiky_buffers: Array, spiky_shadow_buffer: PackedFloat32Array) -> void:
	if _spiky_flora_atlases.is_empty() or _spiky_flora_count <= 0:
		if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
			_spiky_flora_batch_layer.clear_batches()
		return
	var batch_layer: WorldDecorBatchLayer = _ensure_spiky_flora_batch_layer()
	batch_layer.set_atlas_layout(SPIKY_FLORA_FRAME_COLUMNS, SPIKY_FLORA_FRAME_ROWS, SPIKY_FLORA_FRAME_COUNT)
	batch_layer.set_animation(1, 0.0)
	batch_layer.set_batches(_spiky_flora_atlases, spiky_buffers, spiky_shadow_buffer)


func _ensure_rock_batch_layer() -> WorldDecorBatchLayer:
	if _rock_batch_layer != null and is_instance_valid(_rock_batch_layer):
		return _rock_batch_layer
	_rock_batch_layer = WorldDecorBatchLayer.new()
	_rock_batch_layer.name = "RockObjectPacketBatchLayer"
	add_child(_rock_batch_layer)
	_apply_world_origin_to_batch_layer(_rock_batch_layer)
	return _rock_batch_layer


func _ensure_living_flora_batch_layer() -> WorldDecorBatchLayer:
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		return _living_flora_batch_layer
	_living_flora_batch_layer = WorldDecorBatchLayer.new()
	_living_flora_batch_layer.name = "LivingFloraObjectPacketBatchLayer"
	add_child(_living_flora_batch_layer)
	_apply_world_origin_to_batch_layer(_living_flora_batch_layer)
	return _living_flora_batch_layer


func _ensure_spiky_flora_batch_layer() -> WorldDecorBatchLayer:
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		return _spiky_flora_batch_layer
	_spiky_flora_batch_layer = WorldDecorBatchLayer.new()
	_spiky_flora_batch_layer.name = "SpikyFloraObjectPacketBatchLayer"
	add_child(_spiky_flora_batch_layer)
	_apply_world_origin_to_batch_layer(_spiky_flora_batch_layer)
	return _spiky_flora_batch_layer


func _sync_tree_batch(tree_buffer: PackedFloat32Array, tree_shadow_buffer: PackedFloat32Array) -> void:
	if _tree_atlas == null or _tree_count <= 0:
		if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
			_tree_batch_layer.clear_batches()
		_sync_tree_silhouette(PackedFloat32Array())
		return
	var batch_layer: WorldDecorBatchLayer = _ensure_tree_batch_layer()
	batch_layer.set_atlas_layout(TREE_FRAME_COLUMNS, TREE_FRAME_ROWS, TREE_FRAME_COUNT)
	batch_layer.set_animation(1, 0.0)
	# Контактный AO-пул у комля (тот же путь, что камни/флора: плоский эллипс,
	# длина=0, гейт по дневному солнцу) + силуэт-тень ниже. «Вес» под деревом.
	# См. docs/02_system_specs/world/plains_ground_cosmetic_shading.md (Итерация 2).
	batch_layer.set_batches([_tree_atlas], [tree_buffer], tree_shadow_buffer)
	_sync_tree_silhouette(tree_buffer)


func _sync_big_grass_rock_batch(big_grass_rock_buffers: Array, big_grass_rock_shadow_buffer: PackedFloat32Array) -> void:
	if _big_grass_rock_atlases.is_empty() or _big_grass_rock_count <= 0:
		if _big_grass_rock_batch_layer != null and is_instance_valid(_big_grass_rock_batch_layer):
			_big_grass_rock_batch_layer.clear_batches()
		return
	var batch_layer: WorldDecorBatchLayer = _ensure_big_grass_rock_batch_layer()
	batch_layer.set_atlas_layout(BIG_GRASS_ROCK_FRAME_COLUMNS, BIG_GRASS_ROCK_FRAME_ROWS, BIG_GRASS_ROCK_FRAME_COUNT)
	batch_layer.set_animation(1, 0.0)
	batch_layer.set_batches(_big_grass_rock_atlases, big_grass_rock_buffers, big_grass_rock_shadow_buffer)


func _sync_grass_edge_small_rock_batch(
		grass_edge_small_rock_buffer: PackedFloat32Array,
		grass_edge_small_rock_shadow_buffer: PackedFloat32Array,
) -> void:
	if _grass_edge_small_rock_atlas == null or _grass_edge_small_rock_count <= 0:
		if _grass_edge_small_rock_batch_layer != null and is_instance_valid(_grass_edge_small_rock_batch_layer):
			_grass_edge_small_rock_batch_layer.clear_batches()
		return
	var batch_layer: WorldDecorBatchLayer = _ensure_grass_edge_small_rock_batch_layer()
	batch_layer.set_atlas_layout(
		_grass_edge_small_rock_atlas_columns,
		_grass_edge_small_rock_atlas_rows,
		_grass_edge_small_rock_frame_count,
	)
	batch_layer.set_animation(1, 0.0)
	batch_layer.set_batches([_grass_edge_small_rock_atlas], [grass_edge_small_rock_buffer], grass_edge_small_rock_shadow_buffer)


func _sync_tree_silhouette(tree_buffer: PackedFloat32Array) -> void:
	var count: int = tree_buffer.size() / WorldDecorBatchLayer.BUFFER_STRIDE
	if _tree_atlas == null or count <= 0:
		if _tree_shadow_layer != null and is_instance_valid(_tree_shadow_layer):
			_tree_shadow_layer.visible = false
			_tree_shadow_layer.multimesh = null
		return
	var layer: MultiMeshInstance2D = _ensure_tree_shadow_layer()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	multimesh.visible_instance_count = count
	for i: int in range(count):
		var offset: int = i * WorldDecorBatchLayer.BUFFER_STRIDE
		var pos := Vector2(tree_buffer[offset + WorldDecorBatchLayer.BUFFER_X], tree_buffer[offset + WorldDecorBatchLayer.BUFFER_Y])
		var size := Vector2(tree_buffer[offset + WorldDecorBatchLayer.BUFFER_SIZE_X], tree_buffer[offset + WorldDecorBatchLayer.BUFFER_SIZE_Y])
		multimesh.set_instance_transform_2d(i, Transform2D(Vector2(size.x, 0.0), Vector2(0.0, size.y), pos))
		var frame: float = tree_buffer[offset + WorldDecorBatchLayer.BUFFER_FRAME_INDEX]
		multimesh.set_instance_color(i, Color(clampf(frame / 255.0, 0.0, 1.0), 0.0, 0.0, 1.0))
	layer.texture = _tree_atlas
	layer.multimesh = multimesh
	layer.visible = true


func _ensure_tree_shadow_layer() -> MultiMeshInstance2D:
	if _tree_shadow_layer != null and is_instance_valid(_tree_shadow_layer):
		return _tree_shadow_layer
	_tree_shadow_layer = MultiMeshInstance2D.new()
	_tree_shadow_layer.name = "TreeSilhouetteShadowLayer"
	_tree_shadow_layer.z_as_relative = true
	_tree_shadow_layer.z_index = TREE_SHADOW_Z_INDEX
	_tree_shadow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tree_shadow_layer.material = _ensure_tree_shadow_material()
	add_child(_tree_shadow_layer)
	return _tree_shadow_layer


func _ensure_tree_shadow_material() -> ShaderMaterial:
	if _tree_shadow_material != null:
		return _tree_shadow_material
	_tree_shadow_material = ShaderMaterial.new()
	_tree_shadow_material.shader = TREE_SHADOW_SHADER
	_tree_shadow_material.set_shader_parameter("atlas_columns", float(TREE_FRAME_COLUMNS))
	_tree_shadow_material.set_shader_parameter("atlas_rows", float(TREE_FRAME_ROWS))
	_tree_shadow_material.set_shader_parameter("atlas_frame_count", float(TREE_FRAME_COUNT))
	_apply_sun_to_tree_shadow()
	return _tree_shadow_material


func _apply_sun_to_tree_shadow() -> void:
	if _tree_shadow_material == null:
		return
	var shadow_angle: float = deg_to_rad(_sun_light_angle_deg + 180.0)
	_tree_shadow_material.set_shader_parameter("shadow_dir", Vector2(cos(shadow_angle), sin(shadow_angle)))
	_tree_shadow_material.set_shader_parameter("shadow_foreshorten", clampf(0.4 + _sun_shadow_length_px / 280.0, 0.4, 1.2))
	_tree_shadow_material.set_shader_parameter("shadow_opacity", clampf(0.20 + _sun_shadow_opacity * 0.10, 0.16, 0.4))


func _ensure_tree_batch_layer() -> WorldDecorBatchLayer:
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		return _tree_batch_layer
	_tree_batch_layer = WorldDecorBatchLayer.new()
	_tree_batch_layer.name = "TreeObjectPacketBatchLayer"
	_tree_batch_layer.set_sprite_shader(TREE_BATCH_SHADER)
	add_child(_tree_batch_layer)
	_apply_world_origin_to_batch_layer(_tree_batch_layer)
	return _tree_batch_layer


func _ensure_big_grass_rock_batch_layer() -> WorldDecorBatchLayer:
	if _big_grass_rock_batch_layer != null and is_instance_valid(_big_grass_rock_batch_layer):
		return _big_grass_rock_batch_layer
	_big_grass_rock_batch_layer = WorldDecorBatchLayer.new()
	_big_grass_rock_batch_layer.name = "BigGrassRockObjectPacketBatchLayer"
	add_child(_big_grass_rock_batch_layer)
	_apply_world_origin_to_batch_layer(_big_grass_rock_batch_layer)
	return _big_grass_rock_batch_layer


func _ensure_grass_edge_small_rock_batch_layer() -> WorldDecorBatchLayer:
	if _grass_edge_small_rock_batch_layer != null and is_instance_valid(_grass_edge_small_rock_batch_layer):
		return _grass_edge_small_rock_batch_layer
	_grass_edge_small_rock_batch_layer = WorldDecorBatchLayer.new()
	_grass_edge_small_rock_batch_layer.name = "GrassEdgeSmallRockObjectPacketBatchLayer"
	add_child(_grass_edge_small_rock_batch_layer)
	_apply_world_origin_to_batch_layer(_grass_edge_small_rock_batch_layer)
	return _grass_edge_small_rock_batch_layer


func _ensure_collision_body() -> StaticBody2D:
	if _collision_body != null and is_instance_valid(_collision_body):
		return _collision_body
	_collision_body = StaticBody2D.new()
	_collision_body.name = "ObjectPacketRockCollisionBody"
	_collision_body.collision_layer = ROCK_COLLISION_LAYER
	_collision_body.collision_mask = 0
	add_child(_collision_body)
	return _collision_body


func _ensure_big_grass_rock_collision_body() -> StaticBody2D:
	if _big_grass_rock_collision_body != null and is_instance_valid(_big_grass_rock_collision_body):
		return _big_grass_rock_collision_body
	_big_grass_rock_collision_body = StaticBody2D.new()
	_big_grass_rock_collision_body.name = "BigGrassRockObjectPacketCollisionBody"
	_big_grass_rock_collision_body.collision_layer = ROCK_COLLISION_LAYER
	_big_grass_rock_collision_body.collision_mask = 0
	add_child(_big_grass_rock_collision_body)
	return _big_grass_rock_collision_body


func _sync_collision_shapes(collision_records: Array[Dictionary]) -> void:
	_clear_collision_shapes()
	_rock_debug_rects = _debug_rects_from_records(collision_records)
	if not collision_records.is_empty():
		var body: StaticBody2D = _ensure_collision_body()
		for record: Dictionary in collision_records:
			var shape := CircleShape2D.new()
			shape.radius = float(record.get("radius", 10.0))
			var owner_id: int = body.create_shape_owner(body)
			body.shape_owner_add_shape(owner_id, shape)
			body.shape_owner_set_transform(
				owner_id,
				Transform2D(0.0, record.get("position", Vector2.ZERO) as Vector2),
			)
			_collision_shape_owner_ids.append(owner_id)
		_collider_count = _collision_shape_owner_ids.size()
	_sync_collision_debug_layer()


func _clear_collision_shapes() -> void:
	_collider_count = 0
	if _collision_body == null or not is_instance_valid(_collision_body):
		_collision_shape_owner_ids.clear()
		return
	for owner_id: int in _collision_shape_owner_ids:
		_collision_body.remove_shape_owner(owner_id)
	_collision_shape_owner_ids.clear()


func _sync_big_grass_rock_collision(collision_records: Array[Dictionary]) -> void:
	_clear_big_grass_rock_collision_shapes()
	_big_grass_rock_debug_rects = _debug_rects_from_records(collision_records)
	if not collision_records.is_empty():
		var body: StaticBody2D = _ensure_big_grass_rock_collision_body()
		for record: Dictionary in collision_records:
			var shape := CircleShape2D.new()
			shape.radius = float(record.get("radius", 22.0))
			var owner_id: int = body.create_shape_owner(body)
			body.shape_owner_add_shape(owner_id, shape)
			body.shape_owner_set_transform(
				owner_id,
				Transform2D(0.0, record.get("position", Vector2.ZERO) as Vector2),
			)
			_big_grass_rock_collision_shape_owner_ids.append(owner_id)
		_big_grass_rock_collider_count = _big_grass_rock_collision_shape_owner_ids.size()
	_sync_collision_debug_layer()


func _clear_big_grass_rock_collision_shapes() -> void:
	_big_grass_rock_collider_count = 0
	if _big_grass_rock_collision_body == null or not is_instance_valid(_big_grass_rock_collision_body):
		_big_grass_rock_collision_shape_owner_ids.clear()
		return
	for owner_id: int in _big_grass_rock_collision_shape_owner_ids:
		_big_grass_rock_collision_body.remove_shape_owner(owner_id)
	_big_grass_rock_collision_shape_owner_ids.clear()


func _sync_tree_collision(collision_records: Array[Dictionary]) -> void:
	_clear_tree_collision_shapes()
	_tree_debug_rects = _debug_rects_from_records(collision_records) if TREE_COLLISION_ENABLED else []
	if TREE_COLLISION_ENABLED and not collision_records.is_empty():
		var body: StaticBody2D = _ensure_tree_collision_body()
		for record: Dictionary in collision_records:
			var shape := CircleShape2D.new()
			shape.radius = float(record.get("radius", 12.0))
			var owner_id: int = body.create_shape_owner(body)
			body.shape_owner_add_shape(owner_id, shape)
			body.shape_owner_set_transform(
				owner_id,
				Transform2D(0.0, record.get("position", Vector2.ZERO) as Vector2),
			)
			_tree_collision_shape_owner_ids.append(owner_id)
		_tree_collider_count = _tree_collision_shape_owner_ids.size()
	_sync_collision_debug_layer()


func _ensure_tree_collision_body() -> StaticBody2D:
	if _tree_collision_body != null and is_instance_valid(_tree_collision_body):
		return _tree_collision_body
	_tree_collision_body = StaticBody2D.new()
	_tree_collision_body.name = "TreeObjectPacketCollisionBody"
	_tree_collision_body.collision_layer = ROCK_COLLISION_LAYER
	_tree_collision_body.collision_mask = 0
	add_child(_tree_collision_body)
	return _tree_collision_body


func _clear_tree_collision_shapes() -> void:
	_tree_collider_count = 0
	if _tree_collision_body == null or not is_instance_valid(_tree_collision_body):
		_tree_collision_shape_owner_ids.clear()
		return
	for owner_id: int in _tree_collision_shape_owner_ids:
		_tree_collision_body.remove_shape_owner(owner_id)
	_tree_collision_shape_owner_ids.clear()


static func _debug_rects_from_records(records: Array[Dictionary]) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for record: Dictionary in records:
		var position: Vector2 = record.get("position", Vector2.ZERO) as Vector2
		var radius: float = float(record.get("radius", 10.0))
		rects.append(Rect2(position - Vector2(radius, radius), Vector2(radius, radius) * 2.0))
	return rects


## Dev-тумблер (F11, WorldStreamer.toggle_debug_object_collisions): рамки
## коллайдеров камней/валунов/деревьев. Presentation only.
func set_debug_collisions_visible(enabled: bool) -> void:
	if enabled == _debug_collisions_visible:
		return
	_debug_collisions_visible = enabled
	if not enabled:
		if _collision_debug_layer != null and is_instance_valid(_collision_debug_layer):
			_collision_debug_layer.visible = false
		return
	if _collision_debug_layer != null and is_instance_valid(_collision_debug_layer):
		_collision_debug_layer.visible = true
	_sync_collision_debug_layer()


func _ensure_collision_debug_layer() -> ObjectCollisionDebugLayer:
	if _collision_debug_layer != null and is_instance_valid(_collision_debug_layer):
		return _collision_debug_layer
	_collision_debug_layer = ObjectCollisionDebugLayer.new()
	_collision_debug_layer.name = "ObjectCollisionDebugLayer"
	add_child(_collision_debug_layer)
	return _collision_debug_layer


func _sync_collision_debug_layer() -> void:
	if not _debug_collisions_visible:
		return
	var combined: Array[Rect2] = []
	combined.append_array(_rock_debug_rects)
	combined.append_array(_tree_debug_rects)
	combined.append_array(_big_grass_rock_debug_rects)
	_ensure_collision_debug_layer().set_debug_boxes(combined)


func _clear_batches() -> void:
	_rock_count = 0
	_living_flora_count = 0
	_spiky_flora_count = 0
	_tree_count = 0
	_big_grass_rock_count = 0
	_grass_edge_small_rock_count = 0
	_clear_collision_shapes()
	_clear_tree_collision_shapes()
	_clear_big_grass_rock_collision_shapes()
	_rock_debug_rects = []
	_tree_debug_rects = []
	_big_grass_rock_debug_rects = []
	_sync_collision_debug_layer()
	visible = false
	if _rock_batch_layer != null and is_instance_valid(_rock_batch_layer):
		_rock_batch_layer.clear_batches()
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.clear_batches()
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.clear_batches()
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.clear_batches()
	if _big_grass_rock_batch_layer != null and is_instance_valid(_big_grass_rock_batch_layer):
		_big_grass_rock_batch_layer.clear_batches()
	if _grass_edge_small_rock_batch_layer != null and is_instance_valid(_grass_edge_small_rock_batch_layer):
		_grass_edge_small_rock_batch_layer.clear_batches()
	if _tree_shadow_layer != null and is_instance_valid(_tree_shadow_layer):
		_tree_shadow_layer.visible = false
		_tree_shadow_layer.multimesh = null


static func _decode_local_px(value: int) -> float:
	return float(value) * OBJECT_LOCAL_PX_QUANTUM + OBJECT_LOCAL_PX_QUANTUM * 0.5


static func _valid_object_count(arrays: Array) -> int:
	if arrays.is_empty():
		return 0
	var count: int = (arrays[0] as PackedByteArray).size()
	for value: PackedByteArray in arrays:
		if value.size() != count:
			return 0
	return count


func _apply_world_origin_to_batch_layer(batch_layer: WorldDecorBatchLayer) -> void:
	if batch_layer == null or not is_instance_valid(batch_layer):
		return
	batch_layer.set_world_origin_y(_world_origin_y)
