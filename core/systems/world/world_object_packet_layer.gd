class_name WorldObjectPacketLayer
extends Node2D

const WorldDecorBatchLayer = preload("res://core/systems/world/world_decor_batch_layer.gd")
const LayeredTreeObjectLayer = preload("res://core/systems/world/layered_tree_object_layer.gd")
const LayeredRockObjectLayer = preload("res://core/systems/world/layered_rock_object_layer.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const TREE_BATCH_SHADER = preload("res://assets/shaders/tree_decor_atlas_batch.gdshader")
const TREE_SHADOW_SHADER = preload("res://assets/shaders/tree_silhouette_shadow.gdshader")
const ObjectCollisionDebugLayer = preload("res://core/systems/world/object_collision_debug_layer.gd")

const OBJECT_KIND_LIVING_FLORA: int = 2
const OBJECT_KIND_SPIKY_FLORA: int = 3
const OBJECT_KIND_TREE: int = 4
const OBJECT_KIND_SMALL_ROCK: int = 7
const OBJECT_LOCAL_PX_QUANTUM: float = 4.0
const OBJECT_COLLISION_LAYER: int = 2

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
# Метаданные генератора: per-frame точка комля (anchor_local, px) для каждого из
# 16 нарисованных вариантов дерева. Раньше комель считался ОДНОЙ усреднённой
# константой на все кадры (TREE_BASE_ANCHOR_OFFSET_FRAC ниже) — но варианты
# заметно расходятся по позиции ствола (anchor_local.x: 123..243 из 384,
# anchor_local.y: 335..354), поэтому у части деревьев спрайт/коллизия садились
# мимо истинного комля. Формула переноса — см. _tree_frame_anchor_fraction.
const TREE_ATLAS_META_PATH: String = "res://assets/sprites/flora/atlases/plains_trees_atlas.json"
# Фоллбэк, если метаданные недоступны/битые (громкая ошибка в _ensure_tree_frame_anchors_loaded,
# не тихая деградация): доля от верха кадра до комля, усреднённая по старому подбору.
const TREE_BASE_ANCHOR_OFFSET_FRAC: float = 0.46875
const TREE_SHADOW_WIDTH_SCALE: float = 0.34
const TREE_SHADOW_HEIGHT_SCALE: float = 0.11
const TREE_SHADOW_CENTER_Y_SCALE: float = 0.02
const TREE_SHADOW_MIN_WIDTH_PX: float = 18.0
const TREE_SHADOW_MIN_HEIGHT_PX: float = 6.0
const TREE_CONTACT_SHADOW_ENABLED: bool = false
# Силуэт-тень — поверх ВСЕЙ травяной/объектной лесенки и поверх игрока
# (WorldRuntimeConstants.Z_CAST_SHADOW), а не под травой.
const TREE_SHADOW_Z_INDEX: int = WorldRuntimeConstants.Z_CAST_SHADOW
# Дерево — препятствие: маленький круг у комля (ствол), крона проходима.
# Chunk-scoped статика готова к reveal вместе с объектным слоем; шейп-овнеры
# на одном теле, не нода-на-дерево.
const TREE_COLLISION_ENABLED: bool = true
const TREE_COLLISION_RADIUS_SCALE: float = 0.065
const TREE_COLLISION_MIN_RADIUS_PX: float = 9.0
const TREE_COLLISION_MAX_RADIUS_PX: float = 20.0

var _living_flora_atlas: Texture2D = null
var _spiky_flora_atlases: Array[Texture2D] = []
var _tree_atlas: Texture2D = null
var _layered_tree_asset_dir: String = ""
var _layered_tree_asset_dirs: Array[String] = []
var _layered_small_rock_asset_dir: String = ""
var _layered_small_rock_asset_dirs: Array[String] = []
var _living_flora_batch_layer: WorldDecorBatchLayer = null
var _spiky_flora_batch_layer: WorldDecorBatchLayer = null
var _tree_batch_layer: WorldDecorBatchLayer = null
var _layered_tree_layer: LayeredTreeObjectLayer = null
var _layered_small_rock_layer: LayeredRockObjectLayer = null
var _tree_collision_body: StaticBody2D = null
var _tree_collision_shape_owner_ids: Array[int] = []
var _tree_collider_count: int = 0
## Dev-оверлей коллизий (F11): рамки деревьев, presentation only.
var _collision_debug_layer: ObjectCollisionDebugLayer = null
var _debug_collisions_visible: bool = false
var _tree_debug_rects: Array[Rect2] = []
var _tree_shadow_layer: MultiMeshInstance2D = null
var _tree_shadow_material: ShaderMaterial = null
var _sun_light_angle_deg: float = 120.0
var _sun_shadow_length_px: float = 78.0
var _sun_shadow_opacity: float = 0.0
var _living_flora_count: int = 0
var _spiky_flora_count: int = 0
var _tree_count: int = 0
var _small_rock_count: int = 0
var _world_origin_y: float = 0.0


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


func set_layered_tree_asset_dir(asset_dir: String) -> void:
	set_layered_tree_asset_dirs([asset_dir] if not asset_dir.is_empty() else [])


func set_layered_tree_asset_dirs(asset_dirs: Array) -> void:
	_layered_tree_asset_dirs = _normalize_layered_tree_asset_dirs(asset_dirs)
	_layered_tree_asset_dir = _layered_tree_asset_dirs[0] if not _layered_tree_asset_dirs.is_empty() else ""
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		if _layered_tree_asset_dirs.is_empty():
			_layered_tree_layer.clear_instances()
		else:
			_layered_tree_layer.set_asset_dirs(_layered_tree_asset_dirs)


func set_layered_small_rock_asset_dir(asset_dir: String) -> void:
	set_layered_small_rock_asset_dirs([asset_dir] if not asset_dir.is_empty() else [])


func set_layered_small_rock_asset_dirs(asset_dirs: Array) -> void:
	_layered_small_rock_asset_dirs = _normalize_layered_small_rock_asset_dirs(asset_dirs)
	_layered_small_rock_asset_dir = _layered_small_rock_asset_dirs[0] if not _layered_small_rock_asset_dirs.is_empty() else ""
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		if _layered_small_rock_asset_dirs.is_empty():
			_layered_small_rock_layer.clear_instances()
		else:
			_layered_small_rock_layer.set_asset_dirs(_layered_small_rock_asset_dirs)


func set_sun_lighting(
		light_angle_deg: float,
		shadow_length_px: float,
		shadow_opacity: float,
		shadow_softness_px: float,
) -> void:
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
	_sun_light_angle_deg = light_angle_deg
	_sun_shadow_length_px = shadow_length_px
	_sun_shadow_opacity = shadow_opacity
	_apply_sun_to_tree_shadow()
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		_layered_tree_layer.set_sun_lighting(
			light_angle_deg,
			shadow_length_px,
			shadow_opacity,
			shadow_softness_px,
		)
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		_layered_small_rock_layer.set_sun_lighting(
			light_angle_deg,
			shadow_length_px,
			shadow_opacity,
			shadow_softness_px,
		)


## Мировой Y чанка для глобальных полос depth-лесенки.
func set_world_origin_y(world_origin_y: float) -> void:
	_world_origin_y = world_origin_y
	_apply_world_origin_to_batch_layer(_living_flora_batch_layer)
	_apply_world_origin_to_batch_layer(_spiky_flora_batch_layer)
	_apply_world_origin_to_batch_layer(_tree_batch_layer)
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		_layered_tree_layer.set_world_origin_y(_world_origin_y)
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		_layered_small_rock_layer.set_world_origin_y(_world_origin_y)


## Перестановка полос объектного декора на player-relative лесенке.
func update_ladder_z(anchor_stripe: int) -> void:
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.update_ladder_z(anchor_stripe)
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.update_ladder_z(anchor_stripe)
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.update_ladder_z(anchor_stripe)
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		_layered_tree_layer.update_ladder_z(anchor_stripe)
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		_layered_small_rock_layer.update_ladder_z(anchor_stripe)


func configure_packet(packet: Dictionary) -> void:
	_living_flora_count = 0
	_spiky_flora_count = 0
	_tree_count = 0
	_small_rock_count = 0
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

	var living_buffer := PackedFloat32Array()
	var living_shadow_buffer := PackedFloat32Array()
	var spiky_buffers: Array = []
	spiky_buffers.resize(_spiky_flora_atlases.size())
	for atlas_index: int in range(spiky_buffers.size()):
		spiky_buffers[atlas_index] = PackedFloat32Array()
	var empty_shadow_buffer := PackedFloat32Array()
	var tree_buffer := PackedFloat32Array()
	var tree_shadow_buffer := PackedFloat32Array()
	var layered_tree_records: Array[Dictionary] = []
	var layered_small_rock_records: Array[Dictionary] = []
	var tree_collision_records: Array[Dictionary] = []
	for index: int in range(object_count):
		var kind: int = int(object_kind[index])
		var position := Vector2(_decode_local_px(object_x[index]), _decode_local_px(object_y[index]))
		var size_px: float = float(int(object_size[index]))
		var atlas_index: int = int(object_atlas[index])
		var frame_index: int = int(object_variant[index])
		var tint_factor: float = float(int(object_tint[index])) / 255.0
		var phase: float = float(int(object_phase[index])) / 255.0
		match kind:
			OBJECT_KIND_LIVING_FLORA:
				_append_living_flora(position, size_px, frame_index, tint_factor, phase, living_buffer, living_shadow_buffer)
			OBJECT_KIND_SPIKY_FLORA:
				_append_spiky_flora(position, size_px, atlas_index, frame_index, tint_factor, phase, spiky_buffers)
			OBJECT_KIND_TREE:
				_append_tree(
					position,
					size_px,
					frame_index,
					tint_factor,
					phase,
					tree_buffer,
					tree_shadow_buffer,
					layered_tree_records,
					tree_collision_records,
				)
			OBJECT_KIND_SMALL_ROCK:
				_append_small_rock(
					position,
					size_px,
					frame_index,
					tint_factor,
					layered_small_rock_records,
				)

	_sync_living_flora_batch(living_buffer, living_shadow_buffer)
	_sync_spiky_flora_batch(spiky_buffers, empty_shadow_buffer)
	_sync_tree_batch(tree_buffer, tree_shadow_buffer, layered_tree_records)
	_sync_layered_small_rock_layer(layered_small_rock_records)
	_sync_tree_collision(tree_collision_records)
	visible = _living_flora_count > 0 \
			or _spiky_flora_count > 0 \
			or _tree_count > 0 \
			or _small_rock_count > 0


func get_debug_state() -> Dictionary:
	return {
		"living_flora_count": _living_flora_count,
		"spiky_flora_count": _spiky_flora_count,
		"tree_count": _tree_count,
		"small_rock_count": _small_rock_count,
		"tree_collider_count": _tree_collider_count,
		"small_rock_uses_collision": false,
		"tree_contact_shadow_enabled": TREE_CONTACT_SHADOW_ENABLED,
		"uses_layered_tree_runtime": _uses_layered_tree_runtime(),
		"layered_tree_asset_count": _layered_tree_asset_dirs.size(),
		"layered_tree_count": _layered_tree_instance_count(),
		"layered_tree_shadow_count": _layered_tree_shadow_instance_count(),
		"uses_layered_small_rock_runtime": _uses_layered_small_rock_runtime(),
		"layered_small_rock_asset_count": _layered_small_rock_asset_dirs.size(),
		"layered_small_rock_count": _layered_small_rock_instance_count(),
		"layered_small_rock_shadow_count": _layered_small_rock_shadow_instance_count(),
	}


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

## Доля (0..1 от frame_width/frame_height) от левого-верхнего угла кадра атласа
## до точки комля дерева, по frame_index — из плоских метаданных генератора
## (TREE_ATLAS_META_PATH). Кэшируется статически на весь сеанс (один разовый
## парсинг JSON на первый вызов, не на инстанс/кадр — LAW 1).
static var _tree_frame_anchor_fractions: Array[Vector2] = []
static var _tree_frame_anchors_ready: bool = false


static func _tree_frame_anchor_fraction(frame_index: int) -> Vector2:
	_ensure_tree_frame_anchors_loaded()
	if frame_index >= 0 and frame_index < _tree_frame_anchor_fractions.size():
		return _tree_frame_anchor_fractions[frame_index]
	push_error(
		"WorldObjectPacketLayer: no tree anchor metadata for frame_index=%d in %s — using approximate frame-average fallback." % [
			frame_index,
			TREE_ATLAS_META_PATH,
		],
	)
	return Vector2(0.5, 0.5 + TREE_BASE_ANCHOR_OFFSET_FRAC)


static func _ensure_tree_frame_anchors_loaded() -> void:
	if _tree_frame_anchors_ready:
		return
	_tree_frame_anchors_ready = true
	if not FileAccess.file_exists(TREE_ATLAS_META_PATH):
		push_error(
			"WorldObjectPacketLayer: missing tree atlas metadata %s — all tree frames will use the approximate frame-average anchor fallback (sprite/collision misalignment expected for off-centre variants)." % TREE_ATLAS_META_PATH,
		)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TREE_ATLAS_META_PATH))
	if not (parsed is Dictionary):
		push_error("WorldObjectPacketLayer: tree atlas metadata %s is not valid JSON." % TREE_ATLAS_META_PATH)
		return
	var meta: Dictionary = parsed as Dictionary
	var frame_count: int = int(meta.get("frame_count", TREE_FRAME_COUNT))
	var frame_width: float = maxf(1.0, float(meta.get("frame_width", 384.0)))
	var frame_height: float = maxf(1.0, float(meta.get("frame_height", 384.0)))
	var fractions: Array[Vector2] = []
	fractions.resize(frame_count)
	fractions.fill(Vector2(0.5, 0.5 + TREE_BASE_ANCHOR_OFFSET_FRAC))
	for frame_variant: Variant in (meta.get("frames", []) as Array):
		var frame: Dictionary = frame_variant as Dictionary
		var index: int = int(frame.get("index", -1))
		var anchor_local: Array = frame.get("anchor_local", []) as Array
		if index < 0 or index >= fractions.size() or anchor_local.size() < 2:
			continue
		fractions[index] = Vector2(
			float(anchor_local[0]) / frame_width,
			float(anchor_local[1]) / frame_height,
		)
	_tree_frame_anchor_fractions = fractions


func _append_tree(
		position: Vector2,
		size_px: float,
		frame_index: int,
		tint_factor: float,
		phase: float,
		tree_buffer: PackedFloat32Array,
		tree_shadow_buffer: PackedFloat32Array,
		layered_tree_records: Array[Dictionary],
		tree_collision_records: Array[Dictionary],
) -> void:
	if _uses_layered_tree_runtime():
		layered_tree_records.append(
			{
				"position": position,
				"asset_dir": _layered_tree_asset_dir_for_variant(frame_index),
			},
		)
		if TREE_COLLISION_ENABLED:
			var layered_collision_radius: float = clampf(
				size_px * TREE_COLLISION_RADIUS_SCALE,
				TREE_COLLISION_MIN_RADIUS_PX,
				TREE_COLLISION_MAX_RADIUS_PX,
			)
			tree_collision_records.append(
				{
					"position": position - Vector2(0.0, layered_collision_radius * 0.5),
					"radius": layered_collision_radius,
				},
			)
		_tree_count += 1
		return
	if _tree_atlas == null:
		return
	# Спрайт центрируется в позиции → сдвигаем центр так, чтобы КОНКРЕТНО ЭТОГО
	# кадра комель лёг в точку земли (per-frame anchor_local, не единая
	# усреднённая константа — см. комментарий у TREE_ATLAS_META_PATH выше).
	var anchor_fraction: Vector2 = _tree_frame_anchor_fraction(frame_index)
	var sprite_position: Vector2 = position - size_px * (anchor_fraction - Vector2(0.5, 0.5))
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
	if TREE_CONTACT_SHADOW_ENABLED:
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
		var collision_radius: float = clampf(
			size_px * TREE_COLLISION_RADIUS_SCALE,
			TREE_COLLISION_MIN_RADIUS_PX,
			TREE_COLLISION_MAX_RADIUS_PX,
		)
		tree_collision_records.append(
			{
				# Круг чуть выше точки земли (утоплен в ствол): игрок может
				# подойти к дереву вплотную с юга (запрос пользователя 2026-07-04).
				"position": position - Vector2(0.0, collision_radius * 0.5),
				"radius": collision_radius,
			},
		)
	_tree_count += 1


func _append_small_rock(
		position: Vector2,
		size_px: float,
		frame_index: int,
		tint_factor: float,
		layered_small_rock_records: Array[Dictionary],
) -> void:
	if not _uses_layered_small_rock_runtime():
		return
	layered_small_rock_records.append(
		{
			"position": position,
			"asset_dir": _layered_small_rock_asset_dir_for_variant(frame_index),
			"size_px": size_px,
			"tint": Color(tint_factor, tint_factor, tint_factor, 1.0),
		},
	)
	_small_rock_count += 1


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


func _uses_layered_tree_runtime() -> bool:
	return not _layered_tree_asset_dirs.is_empty()


func _uses_layered_small_rock_runtime() -> bool:
	return not _layered_small_rock_asset_dirs.is_empty()


func _sync_tree_batch(
		tree_buffer: PackedFloat32Array,
		tree_shadow_buffer: PackedFloat32Array,
		layered_tree_records: Array[Dictionary],
) -> void:
	if _uses_layered_tree_runtime():
		if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
			_tree_batch_layer.clear_batches()
		_sync_tree_silhouette(PackedFloat32Array())
		_sync_layered_tree_layer(layered_tree_records)
		return
	_clear_layered_tree_layer()
	if _tree_atlas == null or _tree_count <= 0:
		if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
			_tree_batch_layer.clear_batches()
		_sync_tree_silhouette(PackedFloat32Array())
		return
	var batch_layer: WorldDecorBatchLayer = _ensure_tree_batch_layer()
	batch_layer.set_atlas_layout(TREE_FRAME_COLUMNS, TREE_FRAME_ROWS, TREE_FRAME_COUNT)
	batch_layer.set_animation(1, 0.0)
	# Деревья не получают плоский овальный contact AO: он читается как пятно,
	# а не как тень. Дальняя силуэт-тень от солнца остаётся отдельным слоем ниже.
	batch_layer.set_batches([_tree_atlas], [tree_buffer], tree_shadow_buffer)
	_sync_tree_silhouette(tree_buffer)


func _sync_layered_tree_layer(layered_tree_records: Array[Dictionary]) -> void:
	if layered_tree_records.is_empty():
		_clear_layered_tree_layer()
		return
	var layer: LayeredTreeObjectLayer = _ensure_layered_tree_layer()
	layer.set_asset_dirs(_layered_tree_asset_dirs)
	layer.set_world_origin_y(_world_origin_y)
	layer.set_instances(layered_tree_records)
	layer.set_sun_lighting(
		_sun_light_angle_deg,
		_sun_shadow_length_px,
		_sun_shadow_opacity,
		WorldVisualLightingProfile.DEFAULT_SHADOW_SOFTNESS_PX,
	)


func _ensure_layered_tree_layer() -> LayeredTreeObjectLayer:
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		return _layered_tree_layer
	_layered_tree_layer = LayeredTreeObjectLayer.new()
	_layered_tree_layer.name = "LayeredTreeObjectLayer"
	add_child(_layered_tree_layer)
	_layered_tree_layer.set_world_origin_y(_world_origin_y)
	_layered_tree_layer.set_asset_dirs(_layered_tree_asset_dirs)
	return _layered_tree_layer


func _clear_layered_tree_layer() -> void:
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		_layered_tree_layer.clear_instances()


func _sync_layered_small_rock_layer(layered_small_rock_records: Array[Dictionary]) -> void:
	if layered_small_rock_records.is_empty():
		_clear_layered_small_rock_layer()
		return
	var layer: LayeredRockObjectLayer = _ensure_layered_small_rock_layer()
	layer.set_asset_dirs(_layered_small_rock_asset_dirs)
	layer.set_world_origin_y(_world_origin_y)
	layer.set_instances(layered_small_rock_records)
	layer.set_sun_lighting(
		_sun_light_angle_deg,
		_sun_shadow_length_px,
		_sun_shadow_opacity,
		WorldVisualLightingProfile.DEFAULT_SHADOW_SOFTNESS_PX,
	)


func _ensure_layered_small_rock_layer() -> LayeredRockObjectLayer:
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		return _layered_small_rock_layer
	_layered_small_rock_layer = LayeredRockObjectLayer.new()
	_layered_small_rock_layer.name = "LayeredSmallRockObjectLayer"
	add_child(_layered_small_rock_layer)
	_layered_small_rock_layer.set_world_origin_y(_world_origin_y)
	_layered_small_rock_layer.set_asset_dirs(_layered_small_rock_asset_dirs)
	return _layered_small_rock_layer


func _clear_layered_small_rock_layer() -> void:
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		_layered_small_rock_layer.clear_instances()


func _layered_tree_instance_count() -> int:
	if _layered_tree_layer == null or not is_instance_valid(_layered_tree_layer):
		return 0
	var state: Dictionary = _layered_tree_layer.get_debug_state()
	return int(state.get("instance_count", 0))


func _layered_tree_shadow_instance_count() -> int:
	if _layered_tree_layer == null or not is_instance_valid(_layered_tree_layer):
		return 0
	var state: Dictionary = _layered_tree_layer.get_debug_state()
	return int(state.get("shadow_instance_count", 0))


func _layered_small_rock_instance_count() -> int:
	if _layered_small_rock_layer == null or not is_instance_valid(_layered_small_rock_layer):
		return 0
	var state: Dictionary = _layered_small_rock_layer.get_debug_state()
	return int(state.get("instance_count", 0))


func _layered_small_rock_shadow_instance_count() -> int:
	if _layered_small_rock_layer == null or not is_instance_valid(_layered_small_rock_layer):
		return 0
	var state: Dictionary = _layered_small_rock_layer.get_debug_state()
	return int(state.get("shadow_instance_count", 0))


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
	_tree_collision_body.collision_layer = OBJECT_COLLISION_LAYER
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
## коллайдеров деревьев. Presentation only.
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
	combined.append_array(_tree_debug_rects)
	_ensure_collision_debug_layer().set_debug_boxes(combined)


func _clear_batches() -> void:
	_living_flora_count = 0
	_spiky_flora_count = 0
	_tree_count = 0
	_small_rock_count = 0
	_clear_tree_collision_shapes()
	_tree_debug_rects = []
	_sync_collision_debug_layer()
	visible = false
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.clear_batches()
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.clear_batches()
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.clear_batches()
	if _tree_shadow_layer != null and is_instance_valid(_tree_shadow_layer):
		_tree_shadow_layer.visible = false
		_tree_shadow_layer.multimesh = null
	_clear_layered_tree_layer()
	_clear_layered_small_rock_layer()


func _layered_tree_asset_dir_for_variant(frame_index: int) -> String:
	if _layered_tree_asset_dirs.is_empty():
		return ""
	return _layered_tree_asset_dirs[abs(frame_index) % _layered_tree_asset_dirs.size()]


func _layered_small_rock_asset_dir_for_variant(frame_index: int) -> String:
	if _layered_small_rock_asset_dirs.is_empty():
		return ""
	return _layered_small_rock_asset_dirs[abs(frame_index) % _layered_small_rock_asset_dirs.size()]


func _normalize_layered_tree_asset_dirs(asset_dirs: Array) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = { }
	for value: Variant in asset_dirs:
		var asset_dir: String = str(value).strip_edges()
		if asset_dir.is_empty() or seen.has(asset_dir):
			continue
		seen[asset_dir] = true
		result.append(asset_dir)
	return result


func _normalize_layered_small_rock_asset_dirs(asset_dirs: Array) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = { }
	for value: Variant in asset_dirs:
		var asset_dir: String = str(value).strip_edges()
		if asset_dir.is_empty() or seen.has(asset_dir):
			continue
		seen[asset_dir] = true
		result.append(asset_dir)
	return result


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
