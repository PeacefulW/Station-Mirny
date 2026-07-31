class_name WorldObjectPacketLayer
extends Node2D

const WorldDecorBatchLayer = preload("res://core/systems/world/world_decor_batch_layer.gd")
const LayeredTreeObjectLayer = preload("res://core/systems/world/layered_tree_object_layer.gd")
const LayeredRockObjectLayer = preload("res://core/systems/world/layered_rock_object_layer.gd")
const LayeredTreeBatchLayer = preload("res://core/systems/world/layered_tree_batch_layer.gd")
const LayeredRockBatchLayer = preload("res://core/systems/world/layered_rock_batch_layer.gd")
const LayeredBushBatchLayer = preload("res://core/systems/world/layered_bush_batch_layer.gd")
const NativeDecorBatchLayer = preload("res://core/systems/world/native_decor_batch_layer.gd")
const WorldLayeredObjectAssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")
const WorldHeightShadowProfile = preload(
	"res://core/systems/world/world_height_shadow_profile.gd"
)
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")
const TREE_BATCH_SHADER = preload("res://assets/shaders/tree_decor_atlas_batch.gdshader")
const TREE_SHADOW_SHADER = preload("res://assets/shaders/tree_silhouette_shadow.gdshader")
const ObjectCollisionDebugLayer = preload("res://core/systems/world/object_collision_debug_layer.gd")

const OBJECT_KIND_LIVING_FLORA: int = 2
const OBJECT_KIND_SPIKY_FLORA: int = 3
const OBJECT_KIND_TREE: int = 4
const OBJECT_KIND_SMALL_ROCK: int = 7
const OBJECT_KIND_BUSH: int = 8
const OBJECT_LOCAL_PX_QUANTUM: float = 4.0
const OBJECT_COLLISION_LAYER: int = 2
const NATIVE_MULTIMESH_BUFFER_STRIDE: int = 12
const TREE_COLLISION_RECORD_STRIDE: int = 4
const NATIVE_FLOAT_BYTE_SIZE: int = 4

const LIVING_FLORA_FRAME_COLUMNS: int = 16
const LIVING_FLORA_FRAME_ROWS: int = 4
const LIVING_FLORA_FRAMES_PER_VIEW: int = 16
const LIVING_FLORA_FRAME_COUNT: int = LIVING_FLORA_FRAME_COLUMNS * LIVING_FLORA_FRAME_ROWS
const LIVING_FLORA_ANIMATION_FPS: float = 7.0
const LIVING_FLORA_SHADOW_WIDTH_SCALE: float = \
		WorldLayeredObjectAssetCatalog.LIVING_FLORA_SHADOW_WIDTH_SCALE
const LIVING_FLORA_SHADOW_HEIGHT_SCALE: float = \
		WorldLayeredObjectAssetCatalog.LIVING_FLORA_SHADOW_HEIGHT_SCALE
const LIVING_FLORA_SHADOW_CENTER_Y_SCALE: float = \
		WorldLayeredObjectAssetCatalog.LIVING_FLORA_SHADOW_CENTER_Y_SCALE
const LIVING_FLORA_SHADOW_MIN_WIDTH_PX: float = \
		WorldLayeredObjectAssetCatalog.LIVING_FLORA_SHADOW_MIN_WIDTH_PX
const LIVING_FLORA_SHADOW_MIN_HEIGHT_PX: float = \
		WorldLayeredObjectAssetCatalog.LIVING_FLORA_SHADOW_MIN_HEIGHT_PX

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
# Старый flat-atlas fallback не умеет сортировать отдельные тени по полосам,
# поэтому держит весь batch на земле под общей depth-лесенкой. Основной
# layered runtime сортирует каждую shadow bucket по полосе ног объекта.
const TREE_SHADOW_Z_INDEX: int = WorldRuntimeConstants.Z_GRASS_SHADOW
# Дерево — препятствие: неглубокий прямоугольник у комля, крона проходима.
# Chunk-scoped статика готова к reveal вместе с объектным слоем; шейп-овнеры
# на одном теле, не нода-на-дерево.
const TREE_COLLISION_ENABLED: bool = true
## Legacy synchronous compatibility path only. Production native presentation
## uses the per-variant authored footprint prepared by the asset catalog.
const LEGACY_TREE_COLLISION_WIDTH_SCALE: float = 0.13
const LEGACY_TREE_COLLISION_MIN_WIDTH_PX: float = 18.0
const LEGACY_TREE_COLLISION_MAX_WIDTH_PX: float = 40.0
const LEGACY_TREE_COLLISION_DEPTH_PX: float = \
		WorldLayeredObjectAssetCatalog.TREE_COLLISION_MIN_DEPTH_PX

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
var _layered_tree_batch_layer: LayeredTreeBatchLayer = null
var _layered_small_rock_batch_layer: LayeredRockBatchLayer = null
var _layered_bush_batch_layer: LayeredBushBatchLayer = null
var _native_living_flora_batch_layer: NativeDecorBatchLayer = null
var _native_spiky_flora_batch_layer: NativeDecorBatchLayer = null
var _tree_collision_body: StaticBody2D = null
var _tree_collision_shape_owner_ids: Array[int] = []
var _tree_collider_count: int = 0
## Dev-оверлей коллизий (F11): рамки деревьев, presentation only.
var _collision_debug_layer: ObjectCollisionDebugLayer = null
var _debug_collisions_visible: bool = false
var _tree_debug_rects: Array[Rect2] = []
static var _layered_tree_collision_footprints_by_asset_dir: Dictionary = { }
var _tree_shadow_layer: MultiMeshInstance2D = null
var _tree_shadow_material: ShaderMaterial = null
var _sun_light_angle_deg: float = WorldVisualLightingProfile.DEFAULT_LIGHT_ANGLE_DEG
var _sun_shadow_length_px: float = 78.0
var _sun_shadow_opacity: float = 0.0
var _living_flora_count: int = 0
var _spiky_flora_count: int = 0
var _tree_count: int = 0
var _small_rock_count: int = 0
var _bush_count: int = 0
var _world_origin_y: float = 0.0
enum NativeApplyState {
	IDLE,
	RESET_PREVIOUS_COLLISIONS,
	TREE_BUCKETS,
	TREE_COLLISIONS,
	LIVING_FLORA_BUFFERS,
	SPIKY_FLORA_BUFFERS,
	ROCK_BUCKETS,
	BUSH_BUCKETS,
	RETIRE_UNUSED_VISUALS,
	COMMIT_BLOCKING,
	COMPLETE,
}

enum NativeBeginState {
	IDLE,
	HEADER,
	TREE,
	ROCK,
	BUSH,
	LIVING_FLORA,
	SPIKY_FLORA,
	FINALIZE,
	COMPLETE,
	FAILED,
}

# Scheduler-facing phase hints. Allocation families are intentionally distinct:
# their Node/RenderingServer costs differ enough that one global estimate would
# either underpredict tree graphs or unnecessarily serialize lighter decor.
const PRESENTATION_PHASE_NONE: StringName = &""
const PRESENTATION_PHASE_TREE_SLOT_ALLOCATION: StringName = &"tree_slot_allocate"
const PRESENTATION_PHASE_LIVING_SLOT_ALLOCATION: StringName = &"living_slot_allocate"
const PRESENTATION_PHASE_SPIKY_SLOT_ALLOCATION: StringName = &"spiky_slot_allocate"
const PRESENTATION_PHASE_ROCK_SLOT_ALLOCATION: StringName = &"rock_slot_allocate"
const PRESENTATION_PHASE_BUSH_SLOT_ALLOCATION: StringName = &"bush_slot_allocate"
const PRESENTATION_PHASE_TREE_APPLY: StringName = &"tree_apply"
const PRESENTATION_PHASE_TREE_COLLISIONS: StringName = &"tree_collisions"
const PRESENTATION_PHASE_LIVING_APPLY: StringName = &"living_apply"
const PRESENTATION_PHASE_SPIKY_APPLY: StringName = &"spiky_apply"
const PRESENTATION_PHASE_ROCK_APPLY: StringName = &"rock_apply"
const PRESENTATION_PHASE_BUSH_APPLY: StringName = &"bush_apply"
const PRESENTATION_PHASE_RETIRE: StringName = &"retire"
const PRESENTATION_PHASE_COMMIT: StringName = &"commit"

var _native_apply_state: NativeApplyState = NativeApplyState.IDLE
var _native_collision_records: PackedFloat32Array = PackedFloat32Array()
var _native_collision_record_index: int = 0
var _native_blocking_ready: bool = false
var _native_presentation_complete: bool = false
var _last_apply_created_visual_slot: bool = false
var _native_begin_state: NativeBeginState = NativeBeginState.IDLE
var _native_begin_result: Dictionary = { }
var _native_begin_catalog: WorldLayeredObjectAssetCatalog = null
var _native_begin_tree_count: int = 0
var _native_begin_rock_count: int = 0
var _native_begin_bush_count: int = 0
var _native_begin_living_count: int = 0
var _native_begin_spiky_count: int = 0
var _native_begin_presented_count: int = 0
var _native_begin_has_previous_collision_owners: bool = false
var _native_begin_validated_float_count: int = 0
var _native_asset_catalog: WorldLayeredObjectAssetCatalog = null
var _native_payload_bytes: int = 0
var _streaming_world_parented: bool = false


func set_living_flora_atlas(atlas: Texture2D) -> void:
	if _living_flora_atlas == atlas:
		return
	_living_flora_atlas = atlas
	if _native_apply_state != NativeApplyState.IDLE:
		_clear_batches()
		return
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.clear_batches()
	if _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		_native_living_flora_batch_layer.clear_batches()


func set_spiky_flora_atlas(atlas: Texture2D) -> void:
	if atlas == null:
		set_spiky_flora_atlases([])
	else:
		set_spiky_flora_atlases([atlas])


func set_spiky_flora_atlases(atlases: Array[Texture2D]) -> void:
	if _texture_banks_are_identical(_spiky_flora_atlases, atlases):
		return
	_spiky_flora_atlases = atlases.duplicate()
	if _native_apply_state != NativeApplyState.IDLE:
		_clear_batches()
		return
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.clear_batches()
	if _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		_native_spiky_flora_batch_layer.clear_batches()


func set_tree_atlas(atlas: Texture2D) -> void:
	if _tree_atlas == atlas:
		return
	_tree_atlas = atlas
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.clear_batches()


func set_layered_tree_asset_dir(asset_dir: String) -> void:
	set_layered_tree_asset_dirs([asset_dir] if not asset_dir.is_empty() else [])


func set_layered_tree_asset_dirs(asset_dirs: Array) -> void:
	var normalized_dirs: Array[String] = _normalize_layered_tree_asset_dirs(asset_dirs)
	if normalized_dirs == _layered_tree_asset_dirs:
		return
	_layered_tree_asset_dirs = normalized_dirs
	_layered_tree_asset_dir = _layered_tree_asset_dirs[0] if not _layered_tree_asset_dirs.is_empty() else ""
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		if _layered_tree_asset_dirs.is_empty():
			_layered_tree_layer.clear_instances()
		else:
			_layered_tree_layer.set_asset_dirs(_layered_tree_asset_dirs)


func set_layered_small_rock_asset_dir(asset_dir: String) -> void:
	set_layered_small_rock_asset_dirs([asset_dir] if not asset_dir.is_empty() else [])


func set_layered_small_rock_asset_dirs(asset_dirs: Array) -> void:
	var normalized_dirs: Array[String] = _normalize_layered_small_rock_asset_dirs(asset_dirs)
	if normalized_dirs == _layered_small_rock_asset_dirs:
		return
	_layered_small_rock_asset_dirs = normalized_dirs
	_layered_small_rock_asset_dir = _layered_small_rock_asset_dirs[0] if not _layered_small_rock_asset_dirs.is_empty() else ""
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		if _layered_small_rock_asset_dirs.is_empty():
			_layered_small_rock_layer.clear_instances()
		else:
			_layered_small_rock_layer.set_asset_dirs(_layered_small_rock_asset_dirs)


static func _texture_banks_are_identical(lhs: Array[Texture2D], rhs: Array[Texture2D]) -> bool:
	if lhs.size() != rhs.size():
		return false
	for index: int in range(lhs.size()):
		if lhs[index] != rhs[index]:
			return false
	return true


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
	# Native tree/rock batches use catalog-owned shared materials. WorldStreamer
	# updates that catalog once per sun change; touching it once per chunk here
	# multiplied identical RenderingServer uniform writes by the view count.
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
	if _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		_native_living_flora_batch_layer.set_world_origin_y(_world_origin_y)
	if _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		_native_spiky_flora_batch_layer.set_world_origin_y(_world_origin_y)
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		_layered_tree_layer.set_world_origin_y(_world_origin_y)
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		_layered_small_rock_layer.set_world_origin_y(_world_origin_y)
	if _layered_tree_batch_layer != null and is_instance_valid(_layered_tree_batch_layer):
		_layered_tree_batch_layer.set_world_origin_y(_world_origin_y)
	if _layered_small_rock_batch_layer != null and is_instance_valid(_layered_small_rock_batch_layer):
		_layered_small_rock_batch_layer.set_world_origin_y(_world_origin_y)
	if _layered_bush_batch_layer != null and is_instance_valid(_layered_bush_batch_layer):
		_layered_bush_batch_layer.set_world_origin_y(_world_origin_y)


## Перестановка полос объектного декора на player-relative лесенке.
func update_ladder_z(anchor_stripe: int) -> void:
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.update_ladder_z(anchor_stripe)
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.update_ladder_z(anchor_stripe)
	if _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		_native_living_flora_batch_layer.update_ladder_z(anchor_stripe)
	if _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		_native_spiky_flora_batch_layer.update_ladder_z(anchor_stripe)
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.update_ladder_z(anchor_stripe)
	if _layered_tree_layer != null and is_instance_valid(_layered_tree_layer):
		_layered_tree_layer.update_ladder_z(anchor_stripe)
	if _layered_small_rock_layer != null and is_instance_valid(_layered_small_rock_layer):
		_layered_small_rock_layer.update_ladder_z(anchor_stripe)
	if _layered_tree_batch_layer != null and is_instance_valid(_layered_tree_batch_layer):
		_layered_tree_batch_layer.update_ladder_z(anchor_stripe)
	if _layered_small_rock_batch_layer != null and is_instance_valid(_layered_small_rock_batch_layer):
		_layered_small_rock_batch_layer.update_ladder_z(anchor_stripe)
	if _layered_bush_batch_layer != null and is_instance_valid(_layered_bush_batch_layer):
		_layered_bush_batch_layer.update_ladder_z(anchor_stripe)


## Prepares the fixed object-family envelope before it enters the frame-budget
## lane. This does not stage packet data, enable collision, or reveal visuals.
## It only pays the first Node/RenderingServer allocation once in the bounded
## WorldStreamer pool; subsequent packets reuse the same owners and slots.
func prepare_presentation_envelope(
		catalog: WorldLayeredObjectAssetCatalog,
		initial_slots_per_family: int = 1,
) -> bool:
	if catalog == null or not catalog.is_ready():
		return false
	var tree_layer: LayeredTreeBatchLayer = _ensure_layered_tree_batch_layer(catalog)
	var rock_layer: LayeredRockBatchLayer = _ensure_layered_small_rock_batch_layer(catalog)
	var bush_layer: LayeredBushBatchLayer = _ensure_layered_bush_batch_layer(catalog)
	if tree_layer == null or rock_layer == null or bush_layer == null:
		return false
	tree_layer.reserve_pool_slots(initial_slots_per_family)
	rock_layer.reserve_pool_slots(initial_slots_per_family)
	bush_layer.reserve_pool_slots(initial_slots_per_family)
	if _living_flora_atlas != null:
		var living_layer: NativeDecorBatchLayer = _ensure_native_living_flora_batch_layer(catalog)
		if living_layer == null:
			return false
		living_layer.reserve_pool_slots(initial_slots_per_family)
	if not _spiky_flora_atlases.is_empty():
		var spiky_layer: NativeDecorBatchLayer = _ensure_native_spiky_flora_batch_layer(catalog)
		if spiky_layer == null:
			return false
		spiky_layer.reserve_pool_slots(initial_slots_per_family)
	var collision_body: StaticBody2D = _ensure_tree_collision_body()
	collision_body.collision_layer = 0
	visible = false
	return true


## Runtime cold envelopes are constructed as explicit fixed-graph phases. One
## call prepares at most one family (owner + depth-band roots), optional decor
## family, or the collision owner. The streaming dispatcher stores the shell
## between calls, so first use never turns acquire+begin into one large burst.
func prepare_next_presentation_envelope_phase(
		catalog: WorldLayeredObjectAssetCatalog,
) -> bool:
	if catalog == null or not catalog.is_ready():
		return false
	if _layered_tree_batch_layer == null \
			or not is_instance_valid(_layered_tree_batch_layer) \
			or not _layered_tree_batch_layer.is_presentation_envelope_fixed_graph_ready():
		var tree_started_usec: int = WorldPerfProbe.begin()
		var tree_layer: LayeredTreeBatchLayer = _ensure_layered_tree_batch_layer(catalog)
		tree_layer.prepare_presentation_envelope_fixed_graph()
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_envelope.tree_fixed",
			tree_started_usec,
		)
		return true
	if _layered_small_rock_batch_layer == null \
			or not is_instance_valid(_layered_small_rock_batch_layer) \
			or not _layered_small_rock_batch_layer.is_presentation_envelope_fixed_graph_ready():
		var rock_started_usec: int = WorldPerfProbe.begin()
		var rock_layer: LayeredRockBatchLayer = _ensure_layered_small_rock_batch_layer(catalog)
		rock_layer.prepare_presentation_envelope_fixed_graph()
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_envelope.rock_fixed",
			rock_started_usec,
		)
		return true
	if _layered_bush_batch_layer == null \
			or not is_instance_valid(_layered_bush_batch_layer) \
			or not _layered_bush_batch_layer.is_presentation_envelope_fixed_graph_ready():
		var bush_started_usec: int = WorldPerfProbe.begin()
		var bush_layer: LayeredBushBatchLayer = _ensure_layered_bush_batch_layer(catalog)
		bush_layer.prepare_presentation_envelope_fixed_graph()
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_envelope.bush_fixed",
			bush_started_usec,
		)
		return true
	if _living_flora_atlas != null \
			and (_native_living_flora_batch_layer == null \
					or not is_instance_valid(_native_living_flora_batch_layer) \
					or not _native_living_flora_batch_layer \
							.is_presentation_envelope_fixed_graph_ready()):
		var living_started_usec: int = WorldPerfProbe.begin()
		var living_layer: NativeDecorBatchLayer = _ensure_native_living_flora_batch_layer(catalog)
		if living_layer == null:
			return false
		living_layer.prepare_presentation_envelope_fixed_graph()
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_envelope.living_fixed",
			living_started_usec,
		)
		return true
	if not _spiky_flora_atlases.is_empty() \
			and (_native_spiky_flora_batch_layer == null \
					or not is_instance_valid(_native_spiky_flora_batch_layer) \
					or not _native_spiky_flora_batch_layer \
							.is_presentation_envelope_fixed_graph_ready()):
		var spiky_started_usec: int = WorldPerfProbe.begin()
		var spiky_layer: NativeDecorBatchLayer = _ensure_native_spiky_flora_batch_layer(catalog)
		if spiky_layer == null:
			return false
		spiky_layer.prepare_presentation_envelope_fixed_graph()
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_envelope.spiky_fixed",
			spiky_started_usec,
		)
		return true
	if _tree_collision_body == null or not is_instance_valid(_tree_collision_body):
		var collision_started_usec: int = WorldPerfProbe.begin()
		_ensure_tree_collision_body().collision_layer = 0
		WorldPerfProbe.end(
			"WorldStreamer.visual_upload.object_packet_envelope.collision_fixed",
			collision_started_usec,
		)
		return true
	return false


func is_presentation_envelope_ready() -> bool:
	if _layered_tree_batch_layer == null \
			or not is_instance_valid(_layered_tree_batch_layer) \
			or not _layered_tree_batch_layer.is_presentation_envelope_fixed_graph_ready():
		return false
	if _layered_small_rock_batch_layer == null \
			or not is_instance_valid(_layered_small_rock_batch_layer) \
			or not _layered_small_rock_batch_layer.is_presentation_envelope_fixed_graph_ready():
		return false
	if _layered_bush_batch_layer == null \
			or not is_instance_valid(_layered_bush_batch_layer) \
			or not _layered_bush_batch_layer.is_presentation_envelope_fixed_graph_ready():
		return false
	if _living_flora_atlas != null \
			and (_native_living_flora_batch_layer == null \
					or not is_instance_valid(_native_living_flora_batch_layer) \
					or not _native_living_flora_batch_layer \
							.is_presentation_envelope_fixed_graph_ready()):
		return false
	if not _spiky_flora_atlases.is_empty() \
			and (_native_spiky_flora_batch_layer == null \
					or not is_instance_valid(_native_spiky_flora_batch_layer) \
					or not _native_spiky_flora_batch_layer \
							.is_presentation_envelope_fixed_graph_ready()):
		return false
	return _tree_collision_body != null and is_instance_valid(_tree_collision_body)


## Starts the worker-prepared production path. No packet scan, resource load,
## per-object Dictionary, or per-instance MultiMesh setter is allowed here.
func begin_presentation_result(
		result: Dictionary,
		catalog: WorldLayeredObjectAssetCatalog,
) -> bool:
	if not begin_incremental_presentation_result(result, catalog):
		return false
	while has_pending_incremental_presentation_begin():
		if not advance_incremental_presentation_begin_phase():
			return false
	return is_incremental_presentation_begin_complete()


func begin_incremental_presentation_result(
		result: Dictionary,
		catalog: WorldLayeredObjectAssetCatalog,
) -> bool:
	if catalog == null or not catalog.is_ready() or not bool(result.get("success", false)):
		push_error("WorldObjectPacketLayer: valid native result and boot-prepared catalog are required")
		return false
	_native_begin_result = result
	_native_begin_catalog = catalog
	_native_begin_validated_float_count = 0
	_native_payload_bytes = 0
	_native_begin_state = NativeBeginState.HEADER
	_native_apply_state = NativeApplyState.IDLE
	_native_blocking_ready = false
	_native_presentation_complete = false
	visible = false
	return true


func has_pending_incremental_presentation_begin() -> bool:
	return _native_begin_state > NativeBeginState.IDLE \
			and _native_begin_state < NativeBeginState.COMPLETE


func is_incremental_presentation_begin_complete() -> bool:
	return _native_begin_state == NativeBeginState.COMPLETE


func has_incremental_presentation_begin_failed() -> bool:
	return _native_begin_state == NativeBeginState.FAILED


## Advances one validation/family-begin phase. No phase performs raw uploads,
## creates colliders, or reveals the layer.
func advance_incremental_presentation_begin_phase() -> bool:
	match _native_begin_state:
		NativeBeginState.HEADER:
			return _advance_incremental_begin_header()
		NativeBeginState.TREE:
			return _advance_incremental_begin_tree()
		NativeBeginState.ROCK:
			return _advance_incremental_begin_rock()
		NativeBeginState.BUSH:
			return _advance_incremental_begin_bush()
		NativeBeginState.LIVING_FLORA:
			return _advance_incremental_begin_living()
		NativeBeginState.SPIKY_FLORA:
			return _advance_incremental_begin_spiky()
		NativeBeginState.FINALIZE:
			return _advance_incremental_begin_finalize()
		_:
			return false


func _advance_incremental_begin_header() -> bool:
	var result: Dictionary = _native_begin_result
	var living_flora_count: int = maxi(0, int(result.get("living_flora_count", 0)))
	var spiky_flora_count: int = maxi(0, int(result.get("spiky_flora_count", 0)))
	var tree_count: int = maxi(0, int(result.get("tree_instance_count", 0)))
	var rock_count: int = maxi(0, int(result.get("rock_instance_count", 0)))
	var bush_count: int = maxi(0, int(result.get("bush_instance_count", 0)))
	var living_record_count: int = maxi(
		0,
		int(result.get("living_flora_record_count", living_flora_count)),
	)
	var spiky_record_count: int = maxi(
		0,
		int(result.get("spiky_flora_record_count", spiky_flora_count)),
	)
	var suppressed_count: int = maxi(0, int(result.get("suppressed_instance_count", 0)))
	var ignored_count: int = maxi(0, int(result.get("ignored_instance_count", 0)))
	if ignored_count > 0:
		push_error(
			"WorldObjectPacketLayer: native result contains %d unsupported object records" \
					% ignored_count,
		)
		return _fail_incremental_presentation_begin()
	if living_record_count < living_flora_count \
			or spiky_record_count < spiky_flora_count \
			or suppressed_count != (living_record_count - living_flora_count) \
					+ (spiky_record_count - spiky_flora_count):
		push_error("WorldObjectPacketLayer: native flora suppression metadata is inconsistent")
		return _fail_incremental_presentation_begin()
	var presented_object_count: int = living_flora_count + spiky_flora_count + tree_count + rock_count + bush_count
	var expected_object_count: int = presented_object_count + suppressed_count
	if int(result.get("object_count", expected_object_count)) != expected_object_count:
		push_error("WorldObjectPacketLayer: native family counts do not match object_count")
		return _fail_incremental_presentation_begin()
	var collision_value: Variant = result.get("tree_collision_records", null)
	if not collision_value is PackedFloat32Array:
		push_error("WorldObjectPacketLayer: native tree collision records have an invalid type")
		return _fail_incremental_presentation_begin()
	var collision_records: PackedFloat32Array = collision_value as PackedFloat32Array
	if collision_records.size() != tree_count * TREE_COLLISION_RECORD_STRIDE:
		push_error(
			"WorldObjectPacketLayer: native tree collision record count does not match tree instances",
		)
		return _fail_incremental_presentation_begin()
	_native_begin_validated_float_count = collision_records.size()

	# Disable previous collision immediately, but retire recycled shape owners in
	# bounded dispatcher slices. A dense pooled layer must not turn begin() into
	# one O(previous tree count) PhysicsServer burst.
	if _tree_collision_body != null and is_instance_valid(_tree_collision_body):
		_tree_collision_body.collision_layer = 0
	_tree_debug_rects.clear()
	_clear_layered_tree_layer()
	_clear_layered_small_rock_layer()
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.clear_batches()
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.clear_batches()
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.clear_batches()
	if _layered_bush_batch_layer != null and is_instance_valid(_layered_bush_batch_layer):
		_layered_bush_batch_layer.clear_batches()
	if _tree_shadow_layer != null and is_instance_valid(_tree_shadow_layer):
		_tree_shadow_layer.visible = false
		_tree_shadow_layer.multimesh = null

	_native_begin_tree_count = tree_count
	_native_begin_rock_count = rock_count
	_native_begin_bush_count = bush_count
	_native_begin_living_count = living_flora_count
	_native_begin_spiky_count = spiky_flora_count
	_native_begin_presented_count = presented_object_count
	_native_begin_has_previous_collision_owners = \
			not _tree_collision_shape_owner_ids.is_empty()
	_tree_count = _native_begin_tree_count
	_small_rock_count = _native_begin_rock_count
	_bush_count = _native_begin_bush_count
	_living_flora_count = _native_begin_living_count
	_spiky_flora_count = _native_begin_spiky_count
	# Worker results are immutable CPU-cache truth and may be shared by hot
	# eviction/re-zoom transactions. Keep the packed array by reference, but never
	# mutate it: cancellation below drops this layer's reference in O(1).
	_native_collision_records = collision_records
	_native_asset_catalog = _native_begin_catalog
	_native_collision_record_index = 0
	_native_begin_state = NativeBeginState.TREE
	return true


func _advance_incremental_begin_tree() -> bool:
	var tree_float_count: int = _native_bucket_buffers_float_count(
		_native_begin_result,
		&"tree_atlas_bucket_buffers",
		_native_begin_tree_count,
	)
	if tree_float_count < 0:
		return _fail_incremental_presentation_begin()
	_native_begin_validated_float_count += tree_float_count
	var tree_layer: LayeredTreeBatchLayer = _ensure_layered_tree_batch_layer(
		_native_begin_catalog,
	)
	if _native_begin_tree_count > 0:
		if not tree_layer.begin_apply(_native_begin_result):
			return _fail_incremental_presentation_begin()
	else:
		tree_layer.clear_batches()
	_native_begin_state = NativeBeginState.ROCK
	return true


func _advance_incremental_begin_rock() -> bool:
	var rock_float_count: int = _native_bucket_buffers_float_count(
		_native_begin_result,
		&"rock_atlas_bucket_buffers",
		_native_begin_rock_count,
	)
	if rock_float_count < 0:
		return _fail_incremental_presentation_begin()
	_native_begin_validated_float_count += rock_float_count
	var rock_layer: LayeredRockBatchLayer = _ensure_layered_small_rock_batch_layer(
		_native_begin_catalog,
	)
	if _native_begin_rock_count > 0:
		if not rock_layer.begin_apply(_native_begin_result):
			return _fail_incremental_presentation_begin()
	else:
		rock_layer.clear_batches()
	_native_begin_state = NativeBeginState.BUSH
	return true


func _advance_incremental_begin_bush() -> bool:
	# The native builder allocates the bush stripe table lazily, so a chunk with
	# no bushes returns an empty array rather than 64 empty buffers. Validate the
	# stripe table only when the family is actually present.
	if _native_begin_bush_count > 0:
		var bush_float_count: int = _native_bucket_buffers_float_count(
			_native_begin_result,
			&"bush_atlas_bucket_buffers",
			_native_begin_bush_count,
		)
		if bush_float_count < 0:
			return _fail_incremental_presentation_begin()
		_native_begin_validated_float_count += bush_float_count
	var bush_layer: LayeredBushBatchLayer = _ensure_layered_bush_batch_layer(
		_native_begin_catalog,
	)
	if _native_begin_bush_count > 0:
		if not bush_layer.begin_apply(_native_begin_result):
			return _fail_incremental_presentation_begin()
	else:
		bush_layer.clear_batches()
	_native_begin_state = NativeBeginState.LIVING_FLORA
	return true


func _advance_incremental_begin_living() -> bool:
	var living_float_count: int = _native_living_flora_buffers_float_count(
		_native_begin_result,
		_native_begin_living_count,
	)
	if living_float_count < 0:
		return _fail_incremental_presentation_begin()
	_native_begin_validated_float_count += living_float_count
	if _native_begin_living_count > 0:
		var living_layer: NativeDecorBatchLayer = _ensure_native_living_flora_batch_layer(
			_native_begin_catalog,
		)
		var living_buckets: Array = _native_begin_result.get(
			"living_flora_bucket_buffers",
			[],
		) as Array
		var living_shadow: PackedFloat32Array = _native_begin_result.get(
			"living_flora_shadow_buffer",
			PackedFloat32Array(),
		) as PackedFloat32Array
		if living_layer == null or not living_layer.begin_apply(
			[living_buckets],
			living_shadow,
			_native_begin_living_count,
			_native_begin_living_count,
		):
			return _fail_incremental_presentation_begin()
	elif _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		_native_living_flora_batch_layer.clear_batches()
	_native_begin_state = NativeBeginState.SPIKY_FLORA
	return true


func _advance_incremental_begin_spiky() -> bool:
	var spiky_float_count: int = _native_spiky_flora_buffers_float_count(
		_native_begin_result,
		_native_begin_spiky_count,
	)
	if spiky_float_count < 0:
		return _fail_incremental_presentation_begin()
	_native_begin_validated_float_count += spiky_float_count
	if _native_begin_spiky_count > 0:
		var spiky_layer: NativeDecorBatchLayer = _ensure_native_spiky_flora_batch_layer(
			_native_begin_catalog,
		)
		var spiky_buckets: Array = _native_begin_result.get(
			"spiky_flora_atlas_bucket_buffers",
			[],
		) as Array
		if spiky_layer == null or not spiky_layer.begin_apply(
			spiky_buckets,
			PackedFloat32Array(),
			_native_begin_spiky_count,
			0,
		):
			return _fail_incremental_presentation_begin()
	elif _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		_native_spiky_flora_batch_layer.clear_batches()
	_native_begin_state = NativeBeginState.FINALIZE
	return true


func _advance_incremental_begin_finalize() -> bool:
	# Every structural validator above already walks its bounded stripe table.
	# Accumulate actual PackedFloat32Array sizes in those same passes, then make
	# ABI/accounting metadata prove itself before any raw upload or reveal.
	var buffer_float_count_value: Variant = _native_begin_result.get(
		"buffer_float_count",
		null,
	)
	if not buffer_float_count_value is int \
			or int(buffer_float_count_value) != _native_begin_validated_float_count:
		push_error(
			"WorldObjectPacketLayer: native buffer_float_count does not match accepted buffers",
		)
		return _fail_incremental_presentation_begin()
	var actual_payload_bytes: int = _native_begin_validated_float_count * NATIVE_FLOAT_BYTE_SIZE
	var payload_bytes_value: Variant = _native_begin_result.get("payload_bytes", null)
	if not payload_bytes_value is int or int(payload_bytes_value) != actual_payload_bytes:
		push_error(
			"WorldObjectPacketLayer: native payload_bytes does not match accepted buffers",
		)
		return _fail_incremental_presentation_begin()
	_native_payload_bytes = actual_payload_bytes
	# A chunk is revealed only after every authored object family is staged.
	# Rocks do not block movement, but allowing them to finish after reveal makes
	# a technically fast pipeline visibly pop assets into the player's view.
	var has_pending_visual_retire: bool = _has_pending_visual_retire()
	_native_blocking_ready = _native_begin_presented_count <= 0 \
			and not _native_begin_has_previous_collision_owners \
			and not has_pending_visual_retire
	_native_presentation_complete = _native_blocking_ready
	if _native_presentation_complete:
		_native_apply_state = NativeApplyState.COMPLETE
		visible = false
	else:
		_native_apply_state = _first_native_apply_state()
		visible = false
	_native_begin_result = { }
	_native_begin_catalog = null
	_native_begin_state = NativeBeginState.COMPLETE
	return true


func _fail_incremental_presentation_begin() -> bool:
	# Earlier family phases may already retain COW buffer handles in their staged
	# apply state. Drop every local reference; never mutate shared worker arrays.
	cancel_pending_presentation_apply()
	_native_begin_state = NativeBeginState.FAILED
	visible = false
	return false


## One bounded main-thread slice. Returns true when it advanced work.
func apply_next_presentation_slice(
		visual_buffers_per_slice: int,
		colliders_per_slice: int,
		rock_stripes_per_slice: int,
) -> bool:
	_last_apply_created_visual_slot = false
	# Compatibility callers may still use this single entry point. Capacity
	# reservation remains allocation-only and always returns before a raw upload.
	if next_presentation_slice_requires_visual_slot_allocation():
		return apply_next_presentation_allocation_only()
	match _native_apply_state:
		NativeApplyState.RESET_PREVIOUS_COLLISIONS:
			_remove_previous_tree_collision_slice(maxi(1, colliders_per_slice))
			if _tree_collision_shape_owner_ids.is_empty():
				_native_apply_state = _first_native_apply_state()
			return true
		NativeApplyState.TREE_BUCKETS:
			if _layered_tree_batch_layer.has_pending_retire():
				_layered_tree_batch_layer.retire_next_batch(maxi(1, visual_buffers_per_slice))
				if _layered_tree_batch_layer.has_pending_retire():
					return true
			else:
				var tree_pending: bool = _layered_tree_batch_layer.apply_next_batch(
					maxi(1, visual_buffers_per_slice),
				)
				_last_apply_created_visual_slot = \
						_layered_tree_batch_layer.did_last_slice_create_slot()
				if tree_pending:
					return true
			if not _layered_tree_batch_layer.has_pending_retire():
				_native_apply_state = NativeApplyState.TREE_COLLISIONS \
						if not _native_collision_records.is_empty() \
						else _first_native_flora_or_rock_state()
			return true
		NativeApplyState.TREE_COLLISIONS:
			_apply_native_tree_collision_slice(maxi(1, colliders_per_slice))
			if _native_collision_record_index * TREE_COLLISION_RECORD_STRIDE \
					>= _native_collision_records.size():
				_native_apply_state = _first_native_flora_or_rock_state()
			return true
		NativeApplyState.LIVING_FLORA_BUFFERS:
			if _native_living_flora_batch_layer.has_pending_retire():
				_native_living_flora_batch_layer.retire_next_batch(
					maxi(1, visual_buffers_per_slice),
				)
				if _native_living_flora_batch_layer.has_pending_retire():
					return true
			else:
				var living_pending: bool = _native_living_flora_batch_layer.apply_next_batch(
					maxi(1, visual_buffers_per_slice),
				)
				_last_apply_created_visual_slot = \
						_native_living_flora_batch_layer.did_last_slice_create_slot()
				if living_pending:
					return true
			if not _native_living_flora_batch_layer.has_pending_retire():
				_native_apply_state = NativeApplyState.SPIKY_FLORA_BUFFERS \
						if _spiky_flora_count > 0 else _native_rock_or_commit_state()
			return true
		NativeApplyState.SPIKY_FLORA_BUFFERS:
			if _native_spiky_flora_batch_layer.has_pending_retire():
				_native_spiky_flora_batch_layer.retire_next_batch(
					maxi(1, visual_buffers_per_slice),
				)
				if _native_spiky_flora_batch_layer.has_pending_retire():
					return true
			else:
				var spiky_pending: bool = _native_spiky_flora_batch_layer.apply_next_batch(
					maxi(1, visual_buffers_per_slice),
				)
				_last_apply_created_visual_slot = \
						_native_spiky_flora_batch_layer.did_last_slice_create_slot()
				if spiky_pending:
					return true
			if not _native_spiky_flora_batch_layer.has_pending_retire():
				_native_apply_state = _native_rock_or_commit_state()
			return true
		NativeApplyState.ROCK_BUCKETS:
			if _layered_small_rock_batch_layer.has_pending_retire():
				_layered_small_rock_batch_layer.retire_next_batch(maxi(1, rock_stripes_per_slice))
				if _layered_small_rock_batch_layer.has_pending_retire():
					return true
			else:
				var rock_pending: bool = _layered_small_rock_batch_layer.apply_next_batch(
					maxi(1, rock_stripes_per_slice),
				)
				_last_apply_created_visual_slot = \
						_layered_small_rock_batch_layer.did_last_slice_create_slot()
				if rock_pending:
					return true
			if not _layered_small_rock_batch_layer.has_pending_retire():
				_native_apply_state = _native_bush_or_commit_state()
			return true
		NativeApplyState.BUSH_BUCKETS:
			if _layered_bush_batch_layer.has_pending_retire():
				_layered_bush_batch_layer.retire_next_batch(maxi(1, rock_stripes_per_slice))
				if _layered_bush_batch_layer.has_pending_retire():
					return true
			else:
				var bush_pending: bool = _layered_bush_batch_layer.apply_next_batch(
					maxi(1, rock_stripes_per_slice),
				)
				_last_apply_created_visual_slot = 						_layered_bush_batch_layer.did_last_slice_create_slot()
				if bush_pending:
					return true
			if not _layered_bush_batch_layer.has_pending_retire():
				_native_apply_state = NativeApplyState.RETIRE_UNUSED_VISUALS
			return true
		NativeApplyState.RETIRE_UNUSED_VISUALS:
			if not _retire_next_unused_visual_slice(1):
				_native_apply_state = NativeApplyState.COMMIT_BLOCKING
			return true
		NativeApplyState.COMMIT_BLOCKING:
			_commit_native_object_presentation()
			_native_apply_state = NativeApplyState.COMPLETE
			_native_presentation_complete = true
			return true
		_:
			return false


func get_next_presentation_apply_phase_hint() -> StringName:
	match _native_apply_state:
		NativeApplyState.TREE_BUCKETS:
			if _layered_tree_batch_layer.has_pending_retire():
				return PRESENTATION_PHASE_RETIRE
			return PRESENTATION_PHASE_TREE_SLOT_ALLOCATION \
					if _layered_tree_batch_layer.has_pending_required_slot_allocation() \
					else PRESENTATION_PHASE_TREE_APPLY
		NativeApplyState.TREE_COLLISIONS:
			return PRESENTATION_PHASE_TREE_COLLISIONS
		NativeApplyState.LIVING_FLORA_BUFFERS:
			if _native_living_flora_batch_layer.has_pending_retire():
				return PRESENTATION_PHASE_RETIRE
			return PRESENTATION_PHASE_LIVING_SLOT_ALLOCATION \
					if _native_living_flora_batch_layer.has_pending_required_slot_allocation() \
					else PRESENTATION_PHASE_LIVING_APPLY
		NativeApplyState.SPIKY_FLORA_BUFFERS:
			if _native_spiky_flora_batch_layer.has_pending_retire():
				return PRESENTATION_PHASE_RETIRE
			return PRESENTATION_PHASE_SPIKY_SLOT_ALLOCATION \
					if _native_spiky_flora_batch_layer.has_pending_required_slot_allocation() \
					else PRESENTATION_PHASE_SPIKY_APPLY
		NativeApplyState.ROCK_BUCKETS:
			if _layered_small_rock_batch_layer.has_pending_retire():
				return PRESENTATION_PHASE_RETIRE
			return PRESENTATION_PHASE_ROCK_SLOT_ALLOCATION \
					if _layered_small_rock_batch_layer.has_pending_required_slot_allocation() \
					else PRESENTATION_PHASE_ROCK_APPLY
		NativeApplyState.BUSH_BUCKETS:
			if _layered_bush_batch_layer.has_pending_retire():
				return PRESENTATION_PHASE_RETIRE
			return PRESENTATION_PHASE_BUSH_SLOT_ALLOCATION 					if _layered_bush_batch_layer.has_pending_required_slot_allocation() 					else PRESENTATION_PHASE_BUSH_APPLY
		NativeApplyState.RETIRE_UNUSED_VISUALS:
			return PRESENTATION_PHASE_RETIRE
		NativeApplyState.COMMIT_BLOCKING:
			return PRESENTATION_PHASE_COMMIT
		_:
			return PRESENTATION_PHASE_NONE


func apply_next_presentation_allocation_only() -> bool:
	_last_apply_created_visual_slot = false
	var allocated: bool = false
	match get_next_presentation_apply_phase_hint():
		PRESENTATION_PHASE_TREE_SLOT_ALLOCATION:
			allocated = _layered_tree_batch_layer.allocate_next_required_slot()
		PRESENTATION_PHASE_LIVING_SLOT_ALLOCATION:
			allocated = _native_living_flora_batch_layer.allocate_next_required_slot()
		PRESENTATION_PHASE_SPIKY_SLOT_ALLOCATION:
			allocated = _native_spiky_flora_batch_layer.allocate_next_required_slot()
		PRESENTATION_PHASE_ROCK_SLOT_ALLOCATION:
			allocated = _layered_small_rock_batch_layer.allocate_next_required_slot()
		PRESENTATION_PHASE_BUSH_SLOT_ALLOCATION:
			allocated = _layered_bush_batch_layer.allocate_next_required_slot()
	_last_apply_created_visual_slot = allocated
	return allocated


func next_presentation_slice_requires_visual_slot_allocation() -> bool:
	return get_next_presentation_apply_phase_hint() in [
		PRESENTATION_PHASE_TREE_SLOT_ALLOCATION,
		PRESENTATION_PHASE_LIVING_SLOT_ALLOCATION,
		PRESENTATION_PHASE_SPIKY_SLOT_ALLOCATION,
		PRESENTATION_PHASE_ROCK_SLOT_ALLOCATION,
		PRESENTATION_PHASE_BUSH_SLOT_ALLOCATION,
	]


func did_last_presentation_slice_create_visual_slot() -> bool:
	return _last_apply_created_visual_slot


func is_blocking_presentation_ready() -> bool:
	return _native_blocking_ready


func is_presentation_complete() -> bool:
	return _native_presentation_complete


## A completed native layer can remain GPU-resident outside the visible ring.
## Only committed transactions qualify: caching a half-filled pool would make a
## later zoom restore visually incomplete buffers as if they were authoritative.
func is_hot_cache_eligible() -> bool:
	return _native_apply_state == NativeApplyState.COMPLETE \
			and _native_presentation_complete \
			and _native_blocking_ready \
			and _living_flora_count + _spiky_flora_count + _tree_count + _small_rock_count + _bush_count > 0


## Exact committed residency after every slot/collider has been created.
func get_hot_cache_weight() -> Dictionary:
	return _build_hot_cache_weight(false)


## Conservative reservation used while a hidden source-ring transaction is
## still being sliced. It prevents several partial builds from exceeding node
## or physics budgets before their final exact weight becomes available.
func get_hot_cache_reservation_weight() -> Dictionary:
	return _build_hot_cache_weight(true)


## Conservative reservation for a shell whose fixed graph/begin transaction is
## still being prepared. It accounts the final graph and expected packed
## buffers before those resources exist, so incremental cold construction never
## escapes the same cache limits as a fully begun transaction.
func estimate_presentation_result_reservation_weight(result: Dictionary) -> Dictionary:
	var tree_count: int = maxi(0, int(result.get("tree_instance_count", 0)))
	var rock_count: int = maxi(0, int(result.get("rock_instance_count", 0)))
	var living_count: int = maxi(0, int(result.get("living_flora_count", 0)))
	var spiky_count: int = maxi(0, int(result.get("spiky_flora_count", 0)))
	var tree_state: Dictionary = _family_debug_state(_layered_tree_batch_layer)
	var rock_state: Dictionary = _family_debug_state(_layered_small_rock_batch_layer)
	var living_state: Dictionary = _family_debug_state(_native_living_flora_batch_layer)
	var spiky_state: Dictionary = _family_debug_state(_native_spiky_flora_batch_layer)
	var tree_slots: int = maxi(
		int(tree_state.get("pooled_slot_count", 0)),
		mini(tree_count, WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK),
	)
	var rock_slots: int = maxi(
		int(rock_state.get("pooled_slot_count", 0)),
		mini(rock_count, WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK),
	)
	var living_slots: int = maxi(
		int(living_state.get("pooled_slot_count", 0)),
		mini(living_count, WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK),
	)
	var spiky_slots: int = maxi(
		int(spiky_state.get("pooled_slot_count", 0)),
		mini(
			spiky_count,
			WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK \
					* WorldLayeredObjectAssetCatalog.SPIKY_ATLAS_BANK_COUNT,
		),
	)
	# Family owner + DepthLadder owner/three bands are fixed. Living flora also
	# owns one contact-shadow CanvasItem. Root + StaticBody are counted once.
	var canvas_item_count: int = 1 + 1
	canvas_item_count += maxi(int(tree_state.get("canvas_item_count", 0)), 5 + tree_slots * 4)
	canvas_item_count += maxi(int(rock_state.get("canvas_item_count", 0)), 5 + rock_slots * 3)
	if _living_flora_atlas != null:
		canvas_item_count += maxi(
			int(living_state.get("canvas_item_count", 0)),
			6 + living_slots,
		)
	if not _spiky_flora_atlases.is_empty():
		canvas_item_count += maxi(
			int(spiky_state.get("canvas_item_count", 0)),
			5 + spiky_slots,
		)
	if _collision_debug_layer != null and is_instance_valid(_collision_debug_layer):
		canvas_item_count += 1
	var tree_copies: int = maxi(
		int(tree_state.get("resident_instance_count", 0)) * 2,
		tree_count * 2,
	)
	var rock_copies: int = maxi(
		int(rock_state.get("resident_instance_count", 0)) * 2,
		rock_count * 2,
	)
	var living_copies: int = maxi(
		int(living_state.get("resident_instance_count", 0)),
		living_count,
	)
	var living_shadow_copies: int = maxi(
		int(living_state.get("resident_shadow_instance_count", 0)),
		living_count,
	)
	var spiky_copies: int = maxi(
		int(spiky_state.get("resident_instance_count", 0)),
		spiky_count,
	)
	return {
		"payload_bytes": maxi(0, int(result.get("payload_bytes", 0))),
		"gpu_buffer_bytes": (tree_copies + rock_copies + living_copies \
				+ living_shadow_copies + spiky_copies) \
				* NATIVE_MULTIMESH_BUFFER_STRIDE * 4,
		"canvas_item_count": canvas_item_count,
		"collider_count": maxi(_tree_collision_shape_owner_ids.size(), tree_count),
	}


func _family_debug_state(family: Node) -> Dictionary:
	if family == null or not is_instance_valid(family) or not family.has_method("get_debug_state"):
		return { }
	return family.call("get_debug_state") as Dictionary


func _build_hot_cache_weight(reserve_unallocated: bool) -> Dictionary:
	var tree_state: Dictionary = { }
	if _layered_tree_batch_layer != null and is_instance_valid(_layered_tree_batch_layer):
		tree_state = _layered_tree_batch_layer.get_debug_state()
	var rock_state: Dictionary = { }
	if _layered_small_rock_batch_layer != null \
			and is_instance_valid(_layered_small_rock_batch_layer):
		rock_state = _layered_small_rock_batch_layer.get_debug_state()
	var bush_state: Dictionary = { }
	if _layered_bush_batch_layer != null \
			and is_instance_valid(_layered_bush_batch_layer):
		bush_state = _layered_bush_batch_layer.get_debug_state()
	var living_state: Dictionary = { }
	if _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		living_state = _native_living_flora_batch_layer.get_debug_state()
	var spiky_state: Dictionary = { }
	if _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		spiky_state = _native_spiky_flora_batch_layer.get_debug_state()
	var tree_slots: int = int(tree_state.get("pooled_slot_count", 0))
	var rock_slots: int = int(rock_state.get("pooled_slot_count", 0))
	var bush_slots: int = int(bush_state.get("pooled_slot_count", 0))
	var living_slots: int = int(living_state.get("pooled_slot_count", 0))
	var spiky_slots: int = int(spiky_state.get("pooled_slot_count", 0))
	if reserve_unallocated:
		tree_slots = maxi(tree_slots, mini(_tree_count, WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK))
		rock_slots = maxi(rock_slots, mini(_small_rock_count, WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK))
		bush_slots = maxi(bush_slots, mini(_bush_count, WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK))
		living_slots = maxi(
			living_slots,
			mini(_living_flora_count, WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK),
		)
		spiky_slots = maxi(
			spiky_slots,
			mini(
				_spiky_flora_count,
				WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK \
						* WorldLayeredObjectAssetCatalog.SPIKY_ATLAS_BANK_COUNT,
			),
		)
	# Count the complete resident CanvasItem graph, not only draw leaves: this
	# includes the layer owner, family owners, DepthLadder root + three band roots,
	# optional living contact-shadow owner, collision body, and debug overlay.
	var canvas_item_count: int = 1
	for family_state: Dictionary in [tree_state, rock_state, bush_state, living_state, spiky_state]:
		canvas_item_count += int(family_state.get("canvas_item_count", 0))
	canvas_item_count += (tree_slots - int(tree_state.get("pooled_slot_count", 0))) * 4
	canvas_item_count += (rock_slots - int(rock_state.get("pooled_slot_count", 0))) * 3
	# A bush slot owns the same four channel layers a tree slot does.
	canvas_item_count += (bush_slots - int(bush_state.get("pooled_slot_count", 0))) * 4
	canvas_item_count += living_slots - int(living_state.get("pooled_slot_count", 0))
	canvas_item_count += spiky_slots - int(spiky_state.get("pooled_slot_count", 0))
	if _tree_collision_body != null and is_instance_valid(_tree_collision_body):
		canvas_item_count += 1
	if _collision_debug_layer != null and is_instance_valid(_collision_debug_layer):
		canvas_item_count += 1
	# Retirement can outlive logical counts. Resident counters follow the actual
	# MultiMesh buffers so an evicted dense layer keeps its weight until each
	# bounded reset slice really releases it.
	var resident_tree_copies: int = int(tree_state.get("resident_instance_count", 0)) * 2
	var resident_rock_copies: int = int(rock_state.get("resident_instance_count", 0)) * 2
	var resident_bush_copies: int = int(bush_state.get("resident_instance_count", 0)) * 2
	var resident_living_copies: int = int(living_state.get("resident_instance_count", 0))
	var resident_living_shadow_copies: int = int(
		living_state.get("resident_shadow_instance_count", 0),
	)
	var resident_spiky_copies: int = int(spiky_state.get("resident_instance_count", 0))
	var resident_spiky_shadow_copies: int = int(
		spiky_state.get("resident_shadow_instance_count", 0),
	)
	var accounted_instance_copies: int = resident_tree_copies + resident_rock_copies \
			+ resident_bush_copies \
			+ resident_living_copies + resident_living_shadow_copies \
			+ resident_spiky_copies + resident_spiky_shadow_copies
	if reserve_unallocated:
		# Production acquire only hands out fully-retired layers. Per-family max is
		# also stable for defensive direct reuse and avoids a phantom 2x dense weight.
		accounted_instance_copies = maxi(resident_tree_copies, _tree_count * 2) \
				+ maxi(resident_rock_copies, _small_rock_count * 2) \
				+ maxi(resident_bush_copies, _bush_count * 2) \
				+ maxi(resident_living_copies, _living_flora_count) \
				+ maxi(resident_living_shadow_copies, _living_flora_count) \
				+ maxi(resident_spiky_copies, _spiky_flora_count) \
				+ resident_spiky_shadow_copies
	var gpu_buffer_bytes: int = \
			accounted_instance_copies * NATIVE_MULTIMESH_BUFFER_STRIDE * 4
	return {
		"payload_bytes": _native_payload_bytes,
		"gpu_buffer_bytes": gpu_buffer_bytes,
		"canvas_item_count": canvas_item_count,
		"collider_count": maxi(_tree_collision_shape_owner_ids.size(), _tree_count) \
				if reserve_unallocated else _tree_collider_count,
	}


func set_hot_cache_resident(resident: bool) -> void:
	if resident:
		set_blocking_collision_active(false)
	visible = not resident \
			and _living_flora_count + _spiky_flora_count + _tree_count + _small_rock_count + _bush_count > 0


func set_streaming_world_parented(world_parented: bool) -> void:
	_streaming_world_parented = world_parented


func is_streaming_world_parented() -> bool:
	return _streaming_world_parented


## configure_packet() is the compatibility renderer and normally owns its own
## immediate lifecycle. Terminal worker recovery uses it under ChunkView's
## atomic reveal gate, so collisions must be declared prepared yet remain off
## until the parent view is actually published.
func mark_legacy_fallback_ready_for_reveal() -> void:
	_native_blocking_ready = true
	_native_presentation_complete = true
	if _tree_collision_body != null and is_instance_valid(_tree_collision_body):
		_tree_collision_body.collision_layer = 0


func get_raw_multimesh_upload_count_total() -> int:
	var total: int = 0
	for layer: Node in [
		_layered_tree_batch_layer,
		_layered_small_rock_batch_layer,
		_layered_bush_batch_layer,
		_native_living_flora_batch_layer,
		_native_spiky_flora_batch_layer,
	]:
		if layer == null or not is_instance_valid(layer) or not layer.has_method("get_debug_state"):
			continue
		var state: Dictionary = layer.call("get_debug_state") as Dictionary
		total += int(state.get("raw_multimesh_upload_count_total", 0))
	return total


## Physics activation belongs to the ChunkView reveal transaction. A prepared
## object layer may sit under an invisible chunk while mountain visuals finish;
## CanvasItem visibility does not disable StaticBody2D, so activating here
## would create an invisible obstacle.
func set_blocking_collision_active(active: bool) -> void:
	if _tree_collision_body == null or not is_instance_valid(_tree_collision_body):
		return
	_tree_collision_body.collision_layer = OBJECT_COLLISION_LAYER \
			if active and _native_blocking_ready else 0


func has_pending_presentation_apply() -> bool:
	return _native_apply_state != NativeApplyState.IDLE \
			and _native_apply_state != NativeApplyState.COMPLETE


func cancel_pending_presentation_apply() -> void:
	_native_begin_state = NativeBeginState.IDLE
	_native_begin_result = { }
	_native_begin_catalog = null
	_native_begin_validated_float_count = 0
	_native_apply_state = NativeApplyState.IDLE
	# Do not clear(): this may alias tree_collision_records in a warm worker result.
	_native_collision_records = PackedFloat32Array()
	_native_collision_record_index = 0
	_native_payload_bytes = 0
	_native_blocking_ready = false
	_native_presentation_complete = false
	if _layered_tree_batch_layer != null and is_instance_valid(_layered_tree_batch_layer):
		_layered_tree_batch_layer.cancel_pending_apply()
	if _layered_small_rock_batch_layer != null and is_instance_valid(_layered_small_rock_batch_layer):
		_layered_small_rock_batch_layer.cancel_pending_apply()
	if _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		_native_living_flora_batch_layer.cancel_pending_apply()
	if _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		_native_spiky_flora_batch_layer.cancel_pending_apply()
	if _tree_collision_body != null and is_instance_valid(_tree_collision_body):
		_tree_collision_body.collision_layer = 0


## Starts an O(1) recycle transaction. Buffer/collider destruction belongs to
## the streamer's separate retire dispatcher and this layer is not reusable
## until has_pending_pool_retire() becomes false.
func begin_pool_retire() -> void:
	cancel_pending_presentation_apply()
	_living_flora_count = 0
	_spiky_flora_count = 0
	_tree_count = 0
	_small_rock_count = 0
	_bush_count = 0
	_native_payload_bytes = 0
	visible = false


func has_pending_pool_retire() -> bool:
	return _has_pending_visual_retire() or not _tree_collision_shape_owner_ids.is_empty()


## Advances exactly one family-slot phase or one collider-owner slice.
func retire_next_pool_slice(max_visual_slots: int, max_colliders: int) -> bool:
	if _retire_next_unused_visual_slice(maxi(1, max_visual_slots)):
		return true
	if not _tree_collision_shape_owner_ids.is_empty():
		_remove_previous_tree_collision_slice(maxi(1, max_colliders))
		return true
	return false


func get_retained_residency_weight() -> Dictionary:
	return _build_hot_cache_weight(false)


## Once buffers/colliders are empty, overflow disposal removes one slot group
## per dispatcher callback before the remaining fixed graph is freed.
func shrink_pool_next_slot_group() -> bool:
	for family: Node in [
		_native_spiky_flora_batch_layer,
		_native_living_flora_batch_layer,
		_layered_small_rock_batch_layer,
		_layered_bush_batch_layer,
		_layered_tree_batch_layer,
	]:
		if family != null and is_instance_valid(family) \
				and bool(family.call("shrink_pool_next_slot")):
			return true
	return false


func _first_native_apply_state() -> NativeApplyState:
	if not _tree_collision_shape_owner_ids.is_empty():
		return NativeApplyState.RESET_PREVIOUS_COLLISIONS
	if _tree_count > 0:
		return NativeApplyState.TREE_BUCKETS
	return _first_native_flora_or_rock_state()


func _first_native_flora_or_rock_state() -> NativeApplyState:
	if _living_flora_count > 0:
		return NativeApplyState.LIVING_FLORA_BUFFERS
	if _spiky_flora_count > 0:
		return NativeApplyState.SPIKY_FLORA_BUFFERS
	return _native_rock_or_commit_state()


func _native_rock_or_commit_state() -> NativeApplyState:
	return NativeApplyState.ROCK_BUCKETS \
			if _small_rock_count > 0 else _native_bush_or_commit_state()


func _native_bush_or_commit_state() -> NativeApplyState:
	return NativeApplyState.BUSH_BUCKETS \
			if _bush_count > 0 else NativeApplyState.RETIRE_UNUSED_VISUALS


func _has_pending_visual_retire() -> bool:
	for family: Node in [
		_layered_tree_batch_layer,
		_native_living_flora_batch_layer,
		_native_spiky_flora_batch_layer,
		_layered_small_rock_batch_layer,
		_layered_bush_batch_layer,
	]:
		if family != null and is_instance_valid(family) \
				and bool(family.call("has_pending_retire")):
			return true
	return false


## One call touches at most one family and that family releases at most the
## requested number of slot groups. This is shared by sparse replacement and
## pool retirement.
func _retire_next_unused_visual_slice(max_slots: int) -> bool:
	for family: Node in [
		_layered_tree_batch_layer,
		_native_living_flora_batch_layer,
		_native_spiky_flora_batch_layer,
		_layered_small_rock_batch_layer,
		_layered_bush_batch_layer,
	]:
		if family == null or not is_instance_valid(family) \
				or not bool(family.call("has_pending_retire")):
			continue
		family.call("retire_next_batch", maxi(1, max_slots))
		return true
	return false


func _ensure_native_living_flora_batch_layer(
		catalog: WorldLayeredObjectAssetCatalog,
) -> NativeDecorBatchLayer:
	if _native_living_flora_batch_layer == null \
			or not is_instance_valid(_native_living_flora_batch_layer):
		_native_living_flora_batch_layer = NativeDecorBatchLayer.new()
		_native_living_flora_batch_layer.name = "NativeLivingFloraBatchLayer"
		add_child(_native_living_flora_batch_layer)
	var atlases: Array[Texture2D] = [_living_flora_atlas]
	if not _native_living_flora_batch_layer.configure(
		atlases,
		catalog.get_unit_quad_mesh(),
		catalog.get_living_flora_material(),
		catalog.get_classic_decor_shadow_material(),
	):
		return null
	_native_living_flora_batch_layer.set_world_origin_y(_world_origin_y)
	return _native_living_flora_batch_layer


func _ensure_native_spiky_flora_batch_layer(
		catalog: WorldLayeredObjectAssetCatalog,
) -> NativeDecorBatchLayer:
	if _native_spiky_flora_batch_layer == null \
			or not is_instance_valid(_native_spiky_flora_batch_layer):
		_native_spiky_flora_batch_layer = NativeDecorBatchLayer.new()
		_native_spiky_flora_batch_layer.name = "NativeSpikyFloraBatchLayer"
		add_child(_native_spiky_flora_batch_layer)
	if not _native_spiky_flora_batch_layer.configure(
		_spiky_flora_atlases,
		catalog.get_unit_quad_mesh(),
		catalog.get_spiky_flora_material(),
	):
		return null
	_native_spiky_flora_batch_layer.set_world_origin_y(_world_origin_y)
	return _native_spiky_flora_batch_layer


func _ensure_layered_tree_batch_layer(
		catalog: WorldLayeredObjectAssetCatalog,
) -> LayeredTreeBatchLayer:
	if _layered_tree_batch_layer == null or not is_instance_valid(_layered_tree_batch_layer):
		_layered_tree_batch_layer = LayeredTreeBatchLayer.new()
		_layered_tree_batch_layer.name = "LayeredTreeBatchLayer"
		add_child(_layered_tree_batch_layer)
	_layered_tree_batch_layer.configure_catalog(catalog)
	_layered_tree_batch_layer.set_world_origin_y(_world_origin_y)
	return _layered_tree_batch_layer


func _native_bucket_buffers_float_count(
		result: Dictionary,
		key: StringName,
		expected_instance_count: int,
) -> int:
	var value: Variant = result.get(key, null)
	if not value is Array:
		push_error("WorldObjectPacketLayer: native result is missing %s" % key)
		return -1
	var buffers: Array = value as Array
	var float_count: int = _native_bucket_array_float_count(buffers, str(key))
	if float_count < 0:
		return -1
	if float_count / NATIVE_MULTIMESH_BUFFER_STRIDE != expected_instance_count:
		push_error(
			"WorldObjectPacketLayer: %s instance total does not match native metadata" % key,
		)
		return -1
	return float_count


func _native_living_flora_buffers_float_count(
		result: Dictionary,
		expected_instance_count: int,
) -> int:
	var bucket_value: Variant = result.get("living_flora_bucket_buffers", null)
	var shadow_value: Variant = result.get("living_flora_shadow_buffer", null)
	if not bucket_value is Array or not shadow_value is PackedFloat32Array:
		push_error("WorldObjectPacketLayer: native living-flora buffers have invalid types")
		return -1
	var buckets: Array = bucket_value as Array
	var shadow_buffer: PackedFloat32Array = shadow_value as PackedFloat32Array
	if expected_instance_count <= 0:
		if not buckets.is_empty() or not shadow_buffer.is_empty():
			push_error("WorldObjectPacketLayer: zero living-flora count must use lazy empty payloads")
			return -1
		return 0
	if _living_flora_atlas == null:
		push_error("WorldObjectPacketLayer: living-flora packet requires a prepared atlas")
		return -1
	var bucket_float_count: int = _native_bucket_array_float_count(
		buckets,
		"living_flora_bucket_buffers",
	)
	if bucket_float_count < 0:
		return -1
	if bucket_float_count / NATIVE_MULTIMESH_BUFFER_STRIDE != expected_instance_count:
		push_error("WorldObjectPacketLayer: living-flora instance total does not match metadata")
		return -1
	if shadow_buffer.size() % NATIVE_MULTIMESH_BUFFER_STRIDE != 0 \
			or shadow_buffer.size() / NATIVE_MULTIMESH_BUFFER_STRIDE != expected_instance_count:
		push_error("WorldObjectPacketLayer: living-flora shadow count does not match metadata")
		return -1
	return bucket_float_count + shadow_buffer.size()


func _native_spiky_flora_buffers_float_count(
		result: Dictionary,
		expected_instance_count: int,
) -> int:
	var value: Variant = result.get("spiky_flora_atlas_bucket_buffers", null)
	if not value is Array:
		push_error("WorldObjectPacketLayer: native spiky-flora atlas buffers have an invalid type")
		return -1
	var atlas_buckets: Array = value as Array
	var bank_count: int = int(result.get("spiky_flora_atlas_bank_count", -1))
	if expected_instance_count <= 0:
		if not atlas_buckets.is_empty() or bank_count != 0:
			push_error("WorldObjectPacketLayer: zero spiky-flora count must use lazy empty payloads")
			return -1
		return 0
	if bank_count != WorldLayeredObjectAssetCatalog.SPIKY_ATLAS_BANK_COUNT \
			or atlas_buckets.size() != bank_count \
			or _spiky_flora_atlases.size() != bank_count:
		push_error("WorldObjectPacketLayer: spiky-flora atlas bank contract mismatch")
		return -1
	for atlas: Texture2D in _spiky_flora_atlases:
		if atlas == null:
			push_error("WorldObjectPacketLayer: spiky-flora atlas bank contains a null texture")
			return -1
	var float_count: int = 0
	for atlas_index: int in range(atlas_buckets.size()):
		if not atlas_buckets[atlas_index] is Array:
			push_error("WorldObjectPacketLayer: spiky-flora atlas %d has an invalid table" % atlas_index)
			return -1
		var buckets: Array = atlas_buckets[atlas_index] as Array
		var atlas_float_count: int = _native_bucket_array_float_count(
			buckets,
			"spiky_flora_atlas_%d" % atlas_index,
		)
		if atlas_float_count < 0:
			return -1
		float_count += atlas_float_count
	if float_count / NATIVE_MULTIMESH_BUFFER_STRIDE != expected_instance_count:
		push_error("WorldObjectPacketLayer: spiky-flora instance total does not match metadata")
		return -1
	return float_count


func _native_bucket_array_float_count(buffers: Array, label: String) -> int:
	if buffers.size() != WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK:
		push_error(
			"WorldObjectPacketLayer: %s must contain %d depth stripes" % [
				label,
				WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK,
			],
		)
		return -1
	var float_count: int = 0
	for stripe_index: int in range(buffers.size()):
		if not buffers[stripe_index] is PackedFloat32Array:
			push_error(
				"WorldObjectPacketLayer: %s stripe %d has an invalid type" \
						% [label, stripe_index],
			)
			return -1
		var buffer: PackedFloat32Array = buffers[stripe_index] as PackedFloat32Array
		if buffer.size() % NATIVE_MULTIMESH_BUFFER_STRIDE != 0:
			push_error(
				"WorldObjectPacketLayer: %s stripe %d violates raw buffer stride" \
						% [label, stripe_index],
			)
			return -1
		float_count += buffer.size()
	return float_count


func _ensure_layered_bush_batch_layer(
		catalog: WorldLayeredObjectAssetCatalog,
) -> LayeredBushBatchLayer:
	if _layered_bush_batch_layer == null 			or not is_instance_valid(_layered_bush_batch_layer):
		_layered_bush_batch_layer = LayeredBushBatchLayer.new()
		_layered_bush_batch_layer.name = "LayeredBushBatchLayer"
		add_child(_layered_bush_batch_layer)
	_layered_bush_batch_layer.configure_catalog(catalog)
	_layered_bush_batch_layer.set_world_origin_y(_world_origin_y)
	return _layered_bush_batch_layer


func _ensure_layered_small_rock_batch_layer(
		catalog: WorldLayeredObjectAssetCatalog,
) -> LayeredRockBatchLayer:
	if _layered_small_rock_batch_layer == null \
			or not is_instance_valid(_layered_small_rock_batch_layer):
		_layered_small_rock_batch_layer = LayeredRockBatchLayer.new()
		_layered_small_rock_batch_layer.name = "LayeredSmallRockBatchLayer"
		add_child(_layered_small_rock_batch_layer)
	_layered_small_rock_batch_layer.configure_catalog(catalog)
	_layered_small_rock_batch_layer.set_world_origin_y(_world_origin_y)
	return _layered_small_rock_batch_layer


func _apply_native_tree_collision_slice(max_colliders: int) -> void:
	var collision_started_usec: int = WorldPerfProbe.begin()
	var body: StaticBody2D = _ensure_tree_collision_body()
	body.collision_layer = 0
	var record_count: int = _native_collision_records.size() / TREE_COLLISION_RECORD_STRIDE
	var end_index: int = mini(_native_collision_record_index + max_colliders, record_count)
	while _native_collision_record_index < end_index:
		var offset: int = _native_collision_record_index * TREE_COLLISION_RECORD_STRIDE
		var position := Vector2(
			_native_collision_records[offset],
			_native_collision_records[offset + 1],
		)
		var size := Vector2(
			_native_collision_records[offset + 2],
			_native_collision_records[offset + 3],
		)
		var shape: RectangleShape2D = _native_asset_catalog.get_tree_collision_shape(size) \
				if _native_asset_catalog != null else null
		if shape == null:
			shape = RectangleShape2D.new()
			shape.size = size
		var owner_id: int = body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shape)
		body.shape_owner_set_transform(owner_id, Transform2D(0.0, position))
		_tree_collision_shape_owner_ids.append(owner_id)
		if _debug_collisions_visible:
			_tree_debug_rects.append(Rect2(position - size * 0.5, size))
		_native_collision_record_index += 1
	_tree_collider_count = _tree_collision_shape_owner_ids.size()
	WorldPerfProbe.end(
		"WorldObjectPacketLayer.collider_create_slice",
		collision_started_usec,
	)


func _remove_previous_tree_collision_slice(max_colliders: int) -> void:
	if _tree_collision_shape_owner_ids.is_empty():
		_tree_collider_count = 0
		return
	if _tree_collision_body == null or not is_instance_valid(_tree_collision_body):
		_tree_collision_shape_owner_ids.clear()
		_tree_collider_count = 0
		return
	var remove_count: int = mini(maxi(1, max_colliders), _tree_collision_shape_owner_ids.size())
	for remove_index: int in range(remove_count):
		var owner_id: int = _tree_collision_shape_owner_ids.pop_back()
		_tree_collision_body.remove_shape_owner(owner_id)
	_tree_collider_count = _tree_collision_shape_owner_ids.size()


func _commit_native_object_presentation() -> void:
	var commit_started_usec: int = WorldPerfProbe.begin()
	for family: Node in [
		_layered_tree_batch_layer,
		_native_living_flora_batch_layer,
		_native_spiky_flora_batch_layer,
		_layered_small_rock_batch_layer,
		_layered_bush_batch_layer,
	]:
		if family != null and is_instance_valid(family):
			family.call("commit_staged_slots")
	if _tree_collision_body != null and is_instance_valid(_tree_collision_body):
		_tree_collision_body.collision_layer = 0
	visible = _living_flora_count + _spiky_flora_count + _tree_count + _small_rock_count + _bush_count > 0
	_native_blocking_ready = true
	_sync_collision_debug_layer()
	WorldPerfProbe.end("WorldObjectPacketLayer.commit", commit_started_usec)


func configure_packet(packet: Dictionary) -> void:
	# Isolated compatibility tests still exercise the synchronous legacy path.
	# It must explicitly retire a previously staged native transaction so the two
	# presentation owners can never overlap.
	cancel_pending_presentation_apply()
	if _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		_native_living_flora_batch_layer.clear_batches()
	if _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		_native_spiky_flora_batch_layer.clear_batches()
	if _layered_tree_batch_layer != null and is_instance_valid(_layered_tree_batch_layer):
		_layered_tree_batch_layer.clear_batches()
	if _layered_small_rock_batch_layer != null \
			and is_instance_valid(_layered_small_rock_batch_layer):
		_layered_small_rock_batch_layer.clear_batches()
	_living_flora_count = 0
	_spiky_flora_count = 0
	_tree_count = 0
	_small_rock_count = 0
	_bush_count = 0
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
			or _small_rock_count > 0 \
			or _bush_count > 0


func get_debug_state() -> Dictionary:
	var tree_batch_state: Dictionary = { }
	if _layered_tree_batch_layer != null and is_instance_valid(_layered_tree_batch_layer):
		tree_batch_state = _layered_tree_batch_layer.get_debug_state()
	var rock_batch_state: Dictionary = { }
	if _layered_small_rock_batch_layer != null and is_instance_valid(_layered_small_rock_batch_layer):
		rock_batch_state = _layered_small_rock_batch_layer.get_debug_state()
	var living_batch_state: Dictionary = { }
	if _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		living_batch_state = _native_living_flora_batch_layer.get_debug_state()
	var spiky_batch_state: Dictionary = { }
	if _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		spiky_batch_state = _native_spiky_flora_batch_layer.get_debug_state()
	return {
		"living_flora_count": _living_flora_count,
		"spiky_flora_count": _spiky_flora_count,
		"tree_count": _tree_count,
		"small_rock_count": _small_rock_count,
		"bush_count": _bush_count,
		"bush_uses_collision": false,
		"tree_collider_count": _tree_collider_count,
		"previous_tree_collider_cleanup_remaining": _tree_collision_shape_owner_ids.size() \
				if _native_apply_state == NativeApplyState.RESET_PREVIOUS_COLLISIONS else 0,
		"tree_collision_layer": _tree_collision_body.collision_layer \
				if _tree_collision_body != null and is_instance_valid(_tree_collision_body) else 0,
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
		"uses_native_presentation_buffers": _native_apply_state != NativeApplyState.IDLE,
		"native_apply_state": NativeApplyState.keys()[_native_apply_state],
		"native_apply_phase_hint": get_next_presentation_apply_phase_hint(),
		"native_begin_state": NativeBeginState.keys()[_native_begin_state],
		"native_blocking_ready": _native_blocking_ready,
		"native_presentation_complete": _native_presentation_complete,
		"raw_multimesh_upload_count_total": get_raw_multimesh_upload_count_total(),
		"tree_batch": tree_batch_state,
		"rock_batch": rock_batch_state,
		"living_flora_batch": living_batch_state,
		"spiky_flora_batch": spiky_batch_state,
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
		Color(
			tint_factor,
			tint_factor,
			tint_factor,
			WorldLayeredObjectAssetCatalog.LIVING_FLORA_ALPHA,
		),
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
		Color(1.0, 1.0, 1.0, WorldLayeredObjectAssetCatalog.LIVING_FLORA_SHADOW_ALPHA),
		0.0,
		phase,
		maxf(
			size_px / WorldLayeredObjectAssetCatalog.LIVING_FLORA_SHADOW_SIZE_DIVISOR,
			WorldLayeredObjectAssetCatalog.LIVING_FLORA_SHADOW_MIN_SCALE,
		),
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
		Color(
			tint_factor,
			tint_factor,
			tint_factor,
			WorldLayeredObjectAssetCatalog.SPIKY_FLORA_ALPHA,
		),
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
			var footprint: Rect2 = _layered_tree_collision_footprint_for_variant(
				frame_index,
			)
			tree_collision_records.append(
				{
					"position": position + footprint.get_center(),
					"size": footprint.size,
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
		var collision_width: float = clampf(
			size_px * LEGACY_TREE_COLLISION_WIDTH_SCALE,
			LEGACY_TREE_COLLISION_MIN_WIDTH_PX,
			LEGACY_TREE_COLLISION_MAX_WIDTH_PX,
		)
		var collision_size := Vector2(collision_width, LEGACY_TREE_COLLISION_DEPTH_PX)
		tree_collision_records.append(
			{
				# Южный край прямоугольника совпадает с точкой комля: физическое
				# основание и depth-якорь дерева имеют один ground point.
				"position": position - Vector2(0.0, collision_size.y * 0.5),
				"size": collision_size,
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
	WorldHeightShadowProfile.mark_tall_caster_path(_tree_shadow_layer)
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
		body.collision_layer = OBJECT_COLLISION_LAYER
		for record: Dictionary in collision_records:
			var shape := RectangleShape2D.new()
			shape.size = record.get("size", Vector2(24.0, 16.0)) as Vector2
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
		var size: Vector2 = record.get("size", Vector2(20.0, 16.0)) as Vector2
		rects.append(Rect2(position - size * 0.5, size))
	return rects


## Dev-тумблер (F11, WorldStreamer.toggle_debug_object_collisions): рамки
## коллайдеров деревьев. Presentation only.
func set_debug_collisions_visible(enabled: bool) -> void:
	if enabled == _debug_collisions_visible:
		return
	_debug_collisions_visible = enabled
	if enabled and _tree_debug_rects.is_empty() and not _native_collision_records.is_empty():
		_tree_debug_rects = _debug_rects_from_packed_collision_records(_native_collision_records)
	if not enabled:
		if _collision_debug_layer != null and is_instance_valid(_collision_debug_layer):
			_collision_debug_layer.visible = false
		return
	if _collision_debug_layer != null and is_instance_valid(_collision_debug_layer):
		_collision_debug_layer.visible = true
	_sync_collision_debug_layer()


static func _debug_rects_from_packed_collision_records(records: PackedFloat32Array) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for offset: int in range(
		0,
		records.size() - TREE_COLLISION_RECORD_STRIDE + 1,
		TREE_COLLISION_RECORD_STRIDE,
	):
		var position := Vector2(records[offset], records[offset + 1])
		var size := Vector2(records[offset + 2], records[offset + 3])
		rects.append(Rect2(position - size * 0.5, size))
	return rects


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
	_bush_count = 0
	_clear_tree_collision_shapes()
	_tree_debug_rects = []
	_native_apply_state = NativeApplyState.IDLE
	# Drop the immutable worker-result alias without mutating cache truth.
	_native_collision_records = PackedFloat32Array()
	_native_collision_record_index = 0
	_native_blocking_ready = false
	_native_presentation_complete = false
	if _tree_collision_body != null and is_instance_valid(_tree_collision_body):
		_tree_collision_body.collision_layer = 0
	_sync_collision_debug_layer()
	visible = false
	if _living_flora_batch_layer != null and is_instance_valid(_living_flora_batch_layer):
		_living_flora_batch_layer.clear_batches()
	if _spiky_flora_batch_layer != null and is_instance_valid(_spiky_flora_batch_layer):
		_spiky_flora_batch_layer.clear_batches()
	if _native_living_flora_batch_layer != null \
			and is_instance_valid(_native_living_flora_batch_layer):
		_native_living_flora_batch_layer.clear_batches()
	if _native_spiky_flora_batch_layer != null \
			and is_instance_valid(_native_spiky_flora_batch_layer):
		_native_spiky_flora_batch_layer.clear_batches()
	if _tree_batch_layer != null and is_instance_valid(_tree_batch_layer):
		_tree_batch_layer.clear_batches()
	if _tree_shadow_layer != null and is_instance_valid(_tree_shadow_layer):
		_tree_shadow_layer.visible = false
		_tree_shadow_layer.multimesh = null
	_clear_layered_tree_layer()
	_clear_layered_small_rock_layer()
	if _layered_tree_batch_layer != null and is_instance_valid(_layered_tree_batch_layer):
		_layered_tree_batch_layer.clear_batches()
	if _layered_small_rock_batch_layer != null and is_instance_valid(_layered_small_rock_batch_layer):
		_layered_small_rock_batch_layer.clear_batches()


func _layered_tree_asset_dir_for_variant(frame_index: int) -> String:
	if _layered_tree_asset_dirs.is_empty():
		return ""
	return _layered_tree_asset_dirs[abs(frame_index) % _layered_tree_asset_dirs.size()]


func _layered_tree_collision_footprint_for_variant(frame_index: int) -> Rect2:
	var asset_dir: String = _layered_tree_asset_dir_for_variant(frame_index)
	var fallback_size := Vector2(
		LEGACY_TREE_COLLISION_MIN_WIDTH_PX,
		LEGACY_TREE_COLLISION_DEPTH_PX,
	)
	var fallback := Rect2(
		Vector2(-fallback_size.x * 0.5, -fallback_size.y),
		fallback_size,
	)
	if asset_dir.is_empty():
		return fallback
	if _layered_tree_collision_footprints_by_asset_dir.has(asset_dir):
		return _layered_tree_collision_footprints_by_asset_dir[asset_dir] as Rect2
	var metadata_path: String = "%s/meta.json" % asset_dir
	if not FileAccess.file_exists(metadata_path):
		push_error(
			"WorldObjectPacketLayer: missing layered tree collision metadata %s" \
					% metadata_path,
		)
		_layered_tree_collision_footprints_by_asset_dir[asset_dir] = fallback
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not parsed is Dictionary:
		push_error("WorldObjectPacketLayer: invalid layered tree metadata %s" % metadata_path)
		_layered_tree_collision_footprints_by_asset_dir[asset_dir] = fallback
		return fallback
	var metadata: Dictionary = parsed as Dictionary
	var footprint_value: Variant = metadata.get("collision_footprint", null)
	if not footprint_value is Dictionary:
		push_error(
			"WorldObjectPacketLayer: missing collision_footprint in %s" % metadata_path,
		)
		_layered_tree_collision_footprints_by_asset_dir[asset_dir] = fallback
		return fallback
	var authored: Dictionary = footprint_value as Dictionary
	var visual_scale: float = WorldLayeredObjectAssetCatalog.TREE_FIXED_FRAME_SCALE
	var authored_width_px: float = float(authored.get("width_px", 0.0))
	var authored_depth_px: float = float(authored.get("depth_px", 0.0))
	var collision_width: float = (
		authored_width_px
		* visual_scale
		* WorldLayeredObjectAssetCatalog.TREE_COLLISION_WIDTH_MULTIPLIER
	)
	var collision_depth: float = maxf(
		authored_depth_px
		* visual_scale
		* WorldLayeredObjectAssetCatalog.TREE_COLLISION_DEPTH_MULTIPLIER,
		WorldLayeredObjectAssetCatalog.TREE_COLLISION_MIN_DEPTH_PX,
	)
	var size := Vector2(collision_width, collision_depth)
	if size.x <= 0.0:
		push_error("WorldObjectPacketLayer: invalid collision_footprint in %s" % metadata_path)
		_layered_tree_collision_footprints_by_asset_dir[asset_dir] = fallback
		return fallback
	var center_x_offset: float = float(authored.get("offset_x_px", 0.0)) * visual_scale
	var footprint := Rect2(
		Vector2(center_x_offset - size.x * 0.5, -size.y),
		size,
	)
	_layered_tree_collision_footprints_by_asset_dir[asset_dir] = footprint
	return footprint


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
