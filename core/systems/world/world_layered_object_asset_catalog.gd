class_name WorldLayeredObjectAssetCatalog
extends RefCounted
## Boot-prepared CPU metadata for object packing and collision.
##
## The historical class name is retained so packet-cache revisions remain easy
## to audit. It intentionally owns no Texture2D, Shader, Material, Mesh or GPU
## lookup table; WorldRenderClassRegistry is the sole visual asset registry.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload(
	"res://core/systems/world/world_visual_lighting_profile.gd"
)

const TREE_SOURCE_DIRS: Array[String] = [
	"res://assets/sprites/flora/layered_trees/rust_crown_01",
	"res://assets/sprites/flora/layered_trees/rust_crown_02",
	"res://assets/sprites/flora/layered_trees/rust_crown_03",
	"res://assets/sprites/flora/layered_trees/rust_crown_04",
	"res://assets/sprites/flora/layered_trees/rust_crown_05",
	"res://assets/sprites/flora/layered_trees/rust_crown_06",
	"res://assets/sprites/flora/layered_trees/rust_crown_07",
	"res://assets/sprites/flora/layered_trees/rust_crown_08",
]
const ROCK_SOURCE_DIRS: Array[String] = [
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_01",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_02",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_03",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_04",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_05",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_06",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_07",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_08",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_09",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_10",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_11",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_12",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_13",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_14",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_15",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_16",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_17",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_18",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_19",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_20",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_21",
	"res://assets/sprites/decor/plains/layered_small_rocks/small_rock_22",
]
const BUSH_SOURCE_DIRS: Array[String] = [
	"res://assets/sprites/flora/layered_bushes/alien_bush_01",
]

const TREE_COLUMNS: int = 8
const TREE_ROWS: int = 1
const ROCK_COLUMNS: int = 5
const ROCK_ROWS: int = 5
const BUSH_COLUMNS: int = 4
const BUSH_ROWS: int = 1
const CATALOG_GENERATION: int = 9
const TREE_METRIC_STRIDE: int = 8
const ROCK_METRIC_STRIDE: int = 5
const BUSH_METRIC_STRIDE: int = 5
const METRIC_FRAME_WIDTH: int = 0
const METRIC_FRAME_HEIGHT: int = 1
const METRIC_ANCHOR_X: int = 2
const METRIC_ANCHOR_Y: int = 3
const METRIC_VISIBLE_WIDTH: int = 4
const TREE_METRIC_COLLISION_CENTER_X_OFFSET: int = 5
const TREE_METRIC_COLLISION_WIDTH: int = 6
const TREE_METRIC_COLLISION_DEPTH: int = 7
const TREE_FIXED_FRAME_SCALE: float = 0.64
const OBJECT_POSITION_QUANTIZATION_PX: float = 4.0
const TREE_COLLISION_WIDTH_MULTIPLIER: float = 1.0
const TREE_COLLISION_DEPTH_MULTIPLIER: float = 1.0
const TREE_COLLISION_MIN_DEPTH_PX: float = 34.0
const DECOR_DEPTH_ANCHOR_Y_SCALE: float = 0.45
const SPIKY_ATLAS_BANK_COUNT: int = 2
const LIVING_FLORA_ALPHA: float = 0.96
const SPIKY_FLORA_ALPHA: float = 0.98
const LIVING_FLORA_SHADOW_WIDTH_SCALE: float = 0.42
const LIVING_FLORA_SHADOW_HEIGHT_SCALE: float = 0.13
const LIVING_FLORA_SHADOW_CENTER_Y_SCALE: float = 0.32
const LIVING_FLORA_SHADOW_MIN_WIDTH_PX: float = 10.0
const LIVING_FLORA_SHADOW_MIN_HEIGHT_PX: float = 4.0
const LIVING_FLORA_SHADOW_ALPHA: float = 0.58
const LIVING_FLORA_SHADOW_SIZE_DIVISOR: float = 96.0
const LIVING_FLORA_SHADOW_MIN_SCALE: float = 0.36
const SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION
const TREE_SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION
const BUSH_SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION

# Parse-only tombstones for retired batch-layer tools. They are deliberately
# null and therefore cannot keep dormant visual resources resident at boot.
const TREE_TRUNK_ATLAS: Texture2D = null
const TREE_FOLIAGE_ATLAS: Texture2D = null
const TREE_SHADOW_ATLAS: Texture2D = null
const TREE_SNOW_OVERLAY_ATLAS: Texture2D = null
const BUSH_TRUNK_ATLAS: Texture2D = null
const BUSH_FOLIAGE_ATLAS: Texture2D = null
const BUSH_SHADOW_ATLAS: Texture2D = null
const BUSH_SNOW_OVERLAY_ATLAS: Texture2D = null
const ROCK_ALBEDO_ATLAS: Texture2D = null
const ROCK_SHADOW_ATLAS: Texture2D = null
const ROCK_SNOW_OVERLAY_ATLAS: Texture2D = null

var _tree_native_metrics: PackedFloat32Array = PackedFloat32Array()
var _rock_native_metrics: PackedFloat32Array = PackedFloat32Array()
var _bush_native_metrics: PackedFloat32Array = PackedFloat32Array()
var _native_params_by_flora_policy: Array[PackedFloat32Array] = []
var _collision_shapes_by_size: Dictionary = { }
var _is_ready: bool = false
var _season_amount: float = 0.0
var _sun_shadow_length_px: float = WorldVisualLightingProfile.SHADOW_MIN_LENGTH_PX
var _sun_shadow_opacity: float = 0.0


func _init() -> void:
	_tree_native_metrics = _read_metrics(TREE_SOURCE_DIRS, TREE_FIXED_FRAME_SCALE, true)
	_rock_native_metrics = _read_metrics(ROCK_SOURCE_DIRS, -1.0, false)
	_bush_native_metrics = _read_metrics(BUSH_SOURCE_DIRS, -1.0, false)
	_prepare_native_param_policies()
	_is_ready = _tree_native_metrics.size() == TREE_SOURCE_DIRS.size() * TREE_METRIC_STRIDE \
			and _rock_native_metrics.size() == ROCK_SOURCE_DIRS.size() * ROCK_METRIC_STRIDE \
			and _bush_native_metrics.size() == BUSH_SOURCE_DIRS.size() * BUSH_METRIC_STRIDE
	if not _is_ready:
		push_error("WorldLayeredObjectAssetCatalog: invalid authored CPU metadata")


func is_ready() -> bool:
	return _is_ready


func get_catalog_generation() -> int:
	return CATALOG_GENERATION


func get_tree_native_metrics() -> PackedFloat32Array:
	return _tree_native_metrics


func get_rock_native_metrics() -> PackedFloat32Array:
	return _rock_native_metrics


func get_bush_native_metrics() -> PackedFloat32Array:
	return _bush_native_metrics


func get_native_params(
		living_flora_enabled: bool = false,
		spiky_flora_enabled: bool = false,
) -> PackedFloat32Array:
	var policy_index: int = (1 if living_flora_enabled else 0) \
			| (2 if spiky_flora_enabled else 0)
	return _native_params_by_flora_policy[policy_index]


func get_tree_collision_footprint_for_variant(variant: int) -> Rect2:
	if _tree_native_metrics.is_empty():
		return Rect2()
	var offset: int = posmod(variant, TREE_SOURCE_DIRS.size()) * TREE_METRIC_STRIDE
	var scale: float = _tree_native_metrics[offset + METRIC_VISIBLE_WIDTH]
	var size := Vector2(
		_tree_native_metrics[offset + TREE_METRIC_COLLISION_WIDTH] * scale,
		maxf(
			_tree_native_metrics[offset + TREE_METRIC_COLLISION_DEPTH] * scale,
			TREE_COLLISION_MIN_DEPTH_PX,
		),
	)
	var center_x: float = \
		_tree_native_metrics[offset + TREE_METRIC_COLLISION_CENTER_X_OFFSET] * scale
	return Rect2(Vector2(center_x - size.x * 0.5, -size.y), size)


func get_tree_collision_shape(size: Vector2) -> RectangleShape2D:
	var key := Vector2i(roundi(size.x * 1000.0), roundi(size.y * 1000.0))
	if _collision_shapes_by_size.has(key):
		return _collision_shapes_by_size.get(key) as RectangleShape2D
	var shape := RectangleShape2D.new()
	shape.size = size
	_collision_shapes_by_size[key] = shape
	return shape


func set_season_amount(amount: float) -> void:
	_season_amount = clampf(amount, 0.0, 1.0)


func get_season_amount() -> float:
	return _season_amount


func set_sun_lighting(shadow_length_px: float, shadow_opacity: float) -> void:
	_sun_shadow_length_px = shadow_length_px
	_sun_shadow_opacity = shadow_opacity


func get_sun_shadow_length_px() -> float:
	return _sun_shadow_length_px


func get_sun_shadow_opacity() -> float:
	return _sun_shadow_opacity


func _prepare_native_param_policies() -> void:
	var base := PackedFloat32Array([
		OBJECT_POSITION_QUANTIZATION_PX,
		float(WorldRuntimeConstants.DEPTH_STRIPE_PX),
		float(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK),
		TREE_COLLISION_WIDTH_MULTIPLIER,
		TREE_COLLISION_DEPTH_MULTIPLIER,
		TREE_COLLISION_MIN_DEPTH_PX,
		DECOR_DEPTH_ANCHOR_Y_SCALE,
		float(SPIKY_ATLAS_BANK_COUNT),
		LIVING_FLORA_ALPHA,
		SPIKY_FLORA_ALPHA,
		LIVING_FLORA_SHADOW_WIDTH_SCALE,
		LIVING_FLORA_SHADOW_HEIGHT_SCALE,
		LIVING_FLORA_SHADOW_CENTER_Y_SCALE,
		LIVING_FLORA_SHADOW_MIN_WIDTH_PX,
		LIVING_FLORA_SHADOW_MIN_HEIGHT_PX,
		LIVING_FLORA_SHADOW_ALPHA,
		LIVING_FLORA_SHADOW_SIZE_DIVISOR,
		LIVING_FLORA_SHADOW_MIN_SCALE,
		0.0,
		0.0,
	])
	_native_params_by_flora_policy.resize(4)
	for policy_index: int in range(4):
		var params: PackedFloat32Array = base.duplicate()
		params[18] = 1.0 if (policy_index & 1) != 0 else 0.0
		params[19] = 1.0 if (policy_index & 2) != 0 else 0.0
		_native_params_by_flora_policy[policy_index] = params


static func _read_metrics(
		source_dirs: Array[String],
		fixed_scale: float,
		include_collision_footprint: bool,
) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for source_dir: String in source_dirs:
		var path: String = "%s/meta.json" % source_dir
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			return PackedFloat32Array()
		var metadata: Dictionary = parsed as Dictionary
		var anchor: Array = metadata.get("anchor", []) as Array
		var alpha_bbox: Array = metadata.get("alpha_bbox", []) as Array
		if anchor.size() < 2 or alpha_bbox.size() < 4:
			return PackedFloat32Array()
		result.append(float(metadata.get("frame_width", 0.0)))
		result.append(float(metadata.get("frame_height", 0.0)))
		result.append(float(anchor[0]))
		result.append(float(anchor[1]))
		result.append(fixed_scale if fixed_scale > 0.0 else float(alpha_bbox[2]))
		if include_collision_footprint:
			var footprint: Dictionary = metadata.get("collision_footprint", { }) as Dictionary
			if float(footprint.get("width_px", 0.0)) <= 0.0 \
					or float(footprint.get("depth_px", 0.0)) <= 0.0:
				return PackedFloat32Array()
			result.append(float(footprint.get("offset_x_px", 0.0)))
			result.append(float(footprint.get("width_px", 0.0)))
			result.append(float(footprint.get("depth_px", 0.0)))
	return result


# Retired visual batch classes may still be opened by editor tools. These
# parse-safe tombstones never allocate or return a production GPU resource.
func get_world_render_sources() -> Dictionary: return { }
func get_unit_quad_mesh() -> QuadMesh: return null
func get_shadow_mesh() -> ArrayMesh: return null
func get_tree_shadow_mesh() -> ArrayMesh: return null
func get_bush_shadow_mesh() -> ArrayMesh: return null
func get_tree_trunk_material() -> ShaderMaterial: return null
func get_tree_foliage_material() -> ShaderMaterial: return null
func get_tree_snow_material() -> ShaderMaterial: return null
func get_tree_shadow_material() -> ShaderMaterial: return null
func get_bush_trunk_material() -> ShaderMaterial: return null
func get_bush_foliage_material() -> ShaderMaterial: return null
func get_bush_snow_material() -> ShaderMaterial: return null
func get_bush_shadow_material() -> ShaderMaterial: return null
func get_rock_albedo_material() -> ShaderMaterial: return null
func get_rock_snow_material() -> ShaderMaterial: return null
func get_rock_shadow_material() -> ShaderMaterial: return null
func get_living_flora_material() -> ShaderMaterial: return null
func get_spiky_flora_material() -> ShaderMaterial: return null
func get_classic_decor_shadow_material() -> ShaderMaterial: return null
