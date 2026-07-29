class_name WorldLayeredObjectAssetCatalog
extends RefCounted

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload("res://core/systems/world/world_visual_lighting_profile.gd")

const TREE_TRUNK_SHADER: Shader = preload("res://assets/shaders/layered_tree_trunk_batch.gdshader")
const TREE_FOLIAGE_SHADER: Shader = preload("res://assets/shaders/layered_tree_foliage_batch.gdshader")
const ALBEDO_SHADER: Shader = preload("res://assets/shaders/layered_object_albedo_batch.gdshader")
const SNOW_SHADER: Shader = preload("res://assets/shaders/layered_object_snow_batch.gdshader")
const SHADOW_SHADER: Shader = preload("res://assets/shaders/layered_object_shadow_batch.gdshader")
const CLASSIC_DECOR_SHADER: Shader = preload("res://assets/shaders/world_decor_atlas_batch.gdshader")
const CLASSIC_DECOR_SHADOW_SHADER: Shader = preload("res://assets/shaders/world_decor_shadow_batch.gdshader")

const TREE_TRUNK_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_trees/trunk.png")
const TREE_FOLIAGE_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_trees/foliage.png")
const TREE_SHADOW_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_trees/shadow.png")
const TREE_SNOW_OVERLAY_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_trees/snow_overlay.png")
const TREE_WIND_MASK_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_trees/wind_mask.png")
const TREE_SNOW_MASK_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_trees/snow_mask.png")
const TREE_SEASON_MASK_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_trees/season_mask.png")

## Bushes ride the tree channel set (they are baked on the tree contract), but
## keep their own atlas so the two families size and scatter independently.
const BUSH_TRUNK_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_bushes/trunk.png")
const BUSH_FOLIAGE_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_bushes/foliage.png")
const BUSH_SHADOW_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_bushes/shadow.png")
const BUSH_SNOW_OVERLAY_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_bushes/snow_overlay.png")
const BUSH_WIND_MASK_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_bushes/wind_mask.png")
const BUSH_SNOW_MASK_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_bushes/snow_mask.png")
const BUSH_SEASON_MASK_ATLAS: Texture2D = preload("res://assets/sprites/flora/atlases/layered_bushes/season_mask.png")

const ROCK_ALBEDO_ATLAS: Texture2D = preload("res://assets/sprites/decor/atlases/layered_small_rocks/albedo.png")
const ROCK_SHADOW_ATLAS: Texture2D = preload("res://assets/sprites/decor/atlases/layered_small_rocks/shadow.png")
const ROCK_SNOW_OVERLAY_ATLAS: Texture2D = preload("res://assets/sprites/decor/atlases/layered_small_rocks/snow_overlay.png")
const ROCK_SNOW_MASK_ATLAS: Texture2D = preload("res://assets/sprites/decor/atlases/layered_small_rocks/snow_mask.png")

const TREE_SOURCE_DIRS: Array[String] = [
	"res://assets/sprites/flora/layered_trees/tree_01",
	"res://assets/sprites/flora/layered_trees/tree_02",
	"res://assets/sprites/flora/layered_trees/tree_03",
	"res://assets/sprites/flora/layered_trees/tree_04",
	"res://assets/sprites/flora/layered_trees/tree_05",
	"res://assets/sprites/flora/layered_trees/tree_06",
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

const TREE_COLUMNS: int = 6
const TREE_ROWS: int = 1
const ROCK_COLUMNS: int = 5
const ROCK_ROWS: int = 5
const BUSH_COLUMNS: int = 4
const BUSH_ROWS: int = 1
## Bumped whenever the atlas layout or asset set changes: stale prepared buffers
## must be rejected rather than sampled against a grid that no longer matches.
const CATALOG_GENERATION: int = 5
const TREE_METRIC_STRIDE: int = 5
const ROCK_METRIC_STRIDE: int = 5
const BUSH_METRIC_STRIDE: int = 5
const METRIC_FRAME_WIDTH: int = 0
const METRIC_FRAME_HEIGHT: int = 1
const METRIC_ANCHOR_X: int = 2
const METRIC_ANCHOR_Y: int = 3
const METRIC_VISIBLE_WIDTH: int = 4
const TREE_FIXED_FRAME_SCALE: float = 0.64
const TREE_WIND_STRENGTH_PX: float = 3.0
const OBJECT_POSITION_QUANTIZATION_PX: float = 4.0
const TREE_COLLISION_RADIUS_SCALE: float = 0.065
const TREE_COLLISION_RADIUS_MIN_PX: float = 9.0
const TREE_COLLISION_RADIUS_MAX_PX: float = 20.0
# Classic atlas-decor presentation constants live here because the worker must
# reproduce that visual contract without hard-coded native tuning. The legacy
# synchronous compatibility path aliases these same values.
const DECOR_DEPTH_ANCHOR_Y_SCALE: float = 0.45
const SPIKY_ATLAS_BANK_COUNT: int = 2
const LIVING_FLORA_ATLAS_COLUMNS: int = 16
const LIVING_FLORA_ATLAS_ROWS: int = 4
const LIVING_FLORA_FRAME_COUNT: int = 64
const LIVING_FLORA_FRAMES_PER_VIEW: int = 16
const LIVING_FLORA_ANIMATION_FPS: float = 7.0
const SPIKY_FLORA_ATLAS_COLUMNS: int = 4
const SPIKY_FLORA_ATLAS_ROWS: int = 1
const SPIKY_FLORA_FRAME_COUNT: int = 4
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
const CLASSIC_CONTACT_SHADOW_BASE_OPACITY: float = 0.30
const CLASSIC_CONTACT_SHADOW_SUN_OPACITY_SCALE: float = 0.08
const CLASSIC_CONTACT_SHADOW_MAX_OPACITY: float = 0.40
## Shadow framing is per object family because families migrate to the current
## sun one at a time. The output window must open toward the baked shadow, and
## the stretch direction must match it, or a lengthening shadow walks off its own
## sprite.
## Small rocks migrated to sun azimuth 225 with the whole family re-baked, so
## this framing now matches the tree one; it stays a separate constant because
## the next family to migrate will need its own.
const SHADOW_OUTPUT_UV_MIN: Vector2 = Vector2(-0.10, -0.10)
const SHADOW_OUTPUT_UV_MAX: Vector2 = Vector2(1.70, 1.50)
const SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION
## Trees are baked with sun azimuth 225, so their shadow runs screen south-east.
const TREE_SHADOW_OUTPUT_UV_MIN: Vector2 = Vector2(-0.10, -0.10)
const TREE_SHADOW_OUTPUT_UV_MAX: Vector2 = Vector2(1.70, 1.50)
const TREE_SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION
## Bushes were baked on the same revision-4 sun, so their framing opens
## south-east too. It stays a separate constant per family, as the contract in
## docs/art/layered_asset_bake_contract.md requires.
const BUSH_SHADOW_OUTPUT_UV_MIN: Vector2 = Vector2(-0.10, -0.10)
const BUSH_SHADOW_OUTPUT_UV_MAX: Vector2 = Vector2(1.70, 1.50)
const BUSH_SHADOW_DIRECTION: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION
## A bush is a fraction of a tree in world pixels, so the same authored sway in
## pixels would read as a storm. Wind is scaled to the family's size.
const BUSH_WIND_STRENGTH_PX: float = 1.2

var _tree_native_metrics := PackedFloat32Array()
var _rock_native_metrics := PackedFloat32Array()
var _bush_native_metrics := PackedFloat32Array()
var _native_params := PackedFloat32Array([
	OBJECT_POSITION_QUANTIZATION_PX,
	float(WorldRuntimeConstants.DEPTH_STRIPE_PX),
	float(WorldRuntimeConstants.DEPTH_STRIPES_PER_CHUNK),
	TREE_COLLISION_RADIUS_SCALE,
	TREE_COLLISION_RADIUS_MIN_PX,
	TREE_COLLISION_RADIUS_MAX_PX,
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
	0.0, # living presentation enabled; selected through get_native_params()
	0.0, # spiky presentation enabled; selected through get_native_params()
])
var _native_params_by_flora_policy: Array[PackedFloat32Array] = []
var _tree_anchor_lut: Texture2D = null
var _rock_anchor_lut: Texture2D = null
var _bush_anchor_lut: Texture2D = null
var _unit_quad_mesh: QuadMesh = null
var _shadow_mesh: ArrayMesh = null
var _tree_shadow_mesh: ArrayMesh = null
var _bush_shadow_mesh: ArrayMesh = null
var _tree_trunk_material: ShaderMaterial = null
var _tree_foliage_material: ShaderMaterial = null
var _tree_snow_material: ShaderMaterial = null
var _tree_shadow_material: ShaderMaterial = null
var _bush_trunk_material: ShaderMaterial = null
var _bush_foliage_material: ShaderMaterial = null
var _bush_snow_material: ShaderMaterial = null
var _bush_shadow_material: ShaderMaterial = null
var _rock_albedo_material: ShaderMaterial = null
var _rock_snow_material: ShaderMaterial = null
var _rock_shadow_material: ShaderMaterial = null
var _living_flora_material: ShaderMaterial = null
var _spiky_flora_material: ShaderMaterial = null
var _classic_decor_shadow_material: ShaderMaterial = null
var _tree_collision_shapes_by_radius: Dictionary = { }
var _is_ready: bool = false
var _season_amount: float = 0.0
var _season_materials_initialized: bool = false
var _sun_materials_initialized: bool = false
var _sun_shadow_length_px: float = 0.0
var _sun_shadow_opacity: float = 0.0


func _init() -> void:
	_prepare()


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


func get_unit_quad_mesh() -> QuadMesh:
	return _unit_quad_mesh


func get_shadow_mesh() -> ArrayMesh:
	return _shadow_mesh


func get_tree_shadow_mesh() -> ArrayMesh:
	return _tree_shadow_mesh


func get_bush_shadow_mesh() -> ArrayMesh:
	return _bush_shadow_mesh


func get_tree_trunk_material() -> ShaderMaterial:
	return _tree_trunk_material


func get_tree_foliage_material() -> ShaderMaterial:
	return _tree_foliage_material


func get_tree_snow_material() -> ShaderMaterial:
	return _tree_snow_material


func get_tree_shadow_material() -> ShaderMaterial:
	return _tree_shadow_material


func get_bush_trunk_material() -> ShaderMaterial:
	return _bush_trunk_material


func get_bush_foliage_material() -> ShaderMaterial:
	return _bush_foliage_material


func get_bush_snow_material() -> ShaderMaterial:
	return _bush_snow_material


func get_bush_shadow_material() -> ShaderMaterial:
	return _bush_shadow_material


func get_rock_albedo_material() -> ShaderMaterial:
	return _rock_albedo_material


func get_rock_snow_material() -> ShaderMaterial:
	return _rock_snow_material


func get_rock_shadow_material() -> ShaderMaterial:
	return _rock_shadow_material


func get_living_flora_material() -> ShaderMaterial:
	return _living_flora_material


func get_spiky_flora_material() -> ShaderMaterial:
	return _spiky_flora_material


func get_classic_decor_shadow_material() -> ShaderMaterial:
	return _classic_decor_shadow_material


func get_season_amount() -> float:
	return _season_amount


func get_sun_shadow_length_px() -> float:
	return _sun_shadow_length_px


func get_sun_shadow_opacity() -> float:
	return _sun_shadow_opacity


## Immutable shared shape resources; each chunk keeps independent shape-owner
## transforms, but identical authored radii do not allocate duplicate physics
## resources while streaming.
func get_tree_collision_shape(radius: float) -> CircleShape2D:
	var radius_key: int = roundi(radius * 100000.0)
	if _tree_collision_shapes_by_radius.has(radius_key):
		return _tree_collision_shapes_by_radius.get(radius_key) as CircleShape2D
	var shape := CircleShape2D.new()
	shape.radius = radius
	_tree_collision_shapes_by_radius[radius_key] = shape
	return shape


func set_season_amount(season_amount: float) -> void:
	var safe_amount: float = clampf(season_amount, 0.0, 1.0)
	if _season_materials_initialized and is_equal_approx(safe_amount, _season_amount):
		return
	_season_amount = safe_amount
	_season_materials_initialized = true
	_tree_trunk_material.set_shader_parameter("season_amount", _season_amount)
	_tree_foliage_material.set_shader_parameter("season_amount", _season_amount)
	_tree_snow_material.set_shader_parameter("season_amount", _season_amount)
	_bush_trunk_material.set_shader_parameter("season_amount", _season_amount)
	_bush_foliage_material.set_shader_parameter("season_amount", _season_amount)
	_bush_snow_material.set_shader_parameter("season_amount", _season_amount)
	_rock_snow_material.set_shader_parameter("season_amount", _season_amount)


func set_sun_lighting(shadow_length_px: float, shadow_opacity: float) -> void:
	if _sun_materials_initialized \
			and is_equal_approx(shadow_length_px, _sun_shadow_length_px) \
			and is_equal_approx(shadow_opacity, _sun_shadow_opacity):
		return
	_sun_shadow_length_px = shadow_length_px
	_sun_shadow_opacity = shadow_opacity
	_sun_materials_initialized = true
	var low_sun: float = clampf(
		(shadow_length_px - WorldVisualLightingProfile.SHADOW_MIN_LENGTH_PX)
				/ maxf(
					WorldVisualLightingProfile.SHADOW_MAX_LENGTH_PX
							- WorldVisualLightingProfile.SHADOW_MIN_LENGTH_PX,
					0.001,
				),
		0.0,
		1.0,
	)
	var length_scale: float = lerpf(1.0, 1.85, low_sun)
	var opacity: float = clampf(shadow_opacity * 0.60, 0.0, 0.60)
	_tree_shadow_material.set_shader_parameter("shadow_length_scale", length_scale)
	_tree_shadow_material.set_shader_parameter("shadow_opacity", opacity)
	_rock_shadow_material.set_shader_parameter("shadow_length_scale", length_scale)
	_rock_shadow_material.set_shader_parameter("shadow_opacity", opacity)
	_bush_shadow_material.set_shader_parameter("shadow_length_scale", length_scale)
	_bush_shadow_material.set_shader_parameter("shadow_opacity", opacity)
	# Living-flora contact shadows use one catalog-shared material too. Their
	# authored displacement length is zero, so sun angle is visually irrelevant;
	# softness is the same deterministic low-sun function used by WorldStreamer.
	if _classic_decor_shadow_material != null:
		_classic_decor_shadow_material.set_shader_parameter("shadow_angle_rad", 0.0)
		_classic_decor_shadow_material.set_shader_parameter("shadow_length_px", 0.0)
		_classic_decor_shadow_material.set_shader_parameter(
			"shadow_opacity",
			clampf(
				CLASSIC_CONTACT_SHADOW_BASE_OPACITY \
						+ shadow_opacity * CLASSIC_CONTACT_SHADOW_SUN_OPACITY_SCALE,
				0.0,
				CLASSIC_CONTACT_SHADOW_MAX_OPACITY,
			),
		)
		_classic_decor_shadow_material.set_shader_parameter(
			"shadow_softness_px",
			maxf(1.0, WorldVisualLightingProfile.shadow_softness_px_for_low_sun(low_sun)),
		)


func _prepare() -> void:
	_prepare_native_param_policies()
	_tree_native_metrics = _read_metrics(TREE_SOURCE_DIRS, TREE_FIXED_FRAME_SCALE)
	_rock_native_metrics = _read_metrics(ROCK_SOURCE_DIRS, -1.0)
	# Bushes are sized from the packet byte like rocks, so their metric carries
	# the alpha-bbox visible width rather than an authored fixed frame scale.
	_bush_native_metrics = _read_metrics(BUSH_SOURCE_DIRS, -1.0)
	if _tree_native_metrics.size() != TREE_SOURCE_DIRS.size() * TREE_METRIC_STRIDE:
		push_error("WorldLayeredObjectAssetCatalog: invalid tree metadata")
		return
	if _rock_native_metrics.size() != ROCK_SOURCE_DIRS.size() * ROCK_METRIC_STRIDE:
		push_error("WorldLayeredObjectAssetCatalog: invalid rock metadata")
		return
	if _bush_native_metrics.size() != BUSH_SOURCE_DIRS.size() * BUSH_METRIC_STRIDE:
		push_error("WorldLayeredObjectAssetCatalog: invalid bush metadata")
		return
	_tree_anchor_lut = _make_anchor_lut(_tree_native_metrics, TREE_METRIC_STRIDE)
	_rock_anchor_lut = _make_anchor_lut(_rock_native_metrics, ROCK_METRIC_STRIDE)
	_bush_anchor_lut = _make_anchor_lut(_bush_native_metrics, BUSH_METRIC_STRIDE)
	_unit_quad_mesh = QuadMesh.new()
	_unit_quad_mesh.size = Vector2.ONE
	_shadow_mesh = _make_shadow_mesh(SHADOW_OUTPUT_UV_MIN, SHADOW_OUTPUT_UV_MAX)
	_tree_shadow_mesh = _make_shadow_mesh(TREE_SHADOW_OUTPUT_UV_MIN, TREE_SHADOW_OUTPUT_UV_MAX)
	_bush_shadow_mesh = _make_shadow_mesh(BUSH_SHADOW_OUTPUT_UV_MIN, BUSH_SHADOW_OUTPUT_UV_MAX)
	_prepare_materials()
	_is_ready = true


func _prepare_native_param_policies() -> void:
	_native_params_by_flora_policy.resize(4)
	for policy_index: int in range(4):
		var params: PackedFloat32Array = _native_params.duplicate()
		params[18] = 1.0 if (policy_index & 1) != 0 else 0.0
		params[19] = 1.0 if (policy_index & 2) != 0 else 0.0
		_native_params_by_flora_policy[policy_index] = params


func _prepare_materials() -> void:
	_tree_trunk_material = ShaderMaterial.new()
	_tree_trunk_material.shader = TREE_TRUNK_SHADER
	_set_atlas_layout(
		_tree_trunk_material,
		TREE_COLUMNS,
		TREE_ROWS,
		TREE_SOURCE_DIRS.size(),
		TREE_TRUNK_ATLAS,
	)
	_tree_trunk_material.set_shader_parameter("snow_mask_texture", TREE_SNOW_MASK_ATLAS)
	_tree_trunk_material.set_shader_parameter("wind_mask_texture", TREE_WIND_MASK_ATLAS)
	_tree_trunk_material.set_shader_parameter("wind_strength_px", TREE_WIND_STRENGTH_PX)

	_tree_foliage_material = ShaderMaterial.new()
	_tree_foliage_material.shader = TREE_FOLIAGE_SHADER
	_set_atlas_layout(
		_tree_foliage_material,
		TREE_COLUMNS,
		TREE_ROWS,
		TREE_SOURCE_DIRS.size(),
		TREE_FOLIAGE_ATLAS,
	)
	_tree_foliage_material.set_shader_parameter("wind_mask_texture", TREE_WIND_MASK_ATLAS)
	_tree_foliage_material.set_shader_parameter("season_mask_texture", TREE_SEASON_MASK_ATLAS)
	_tree_foliage_material.set_shader_parameter("wind_strength_px", TREE_WIND_STRENGTH_PX)

	_tree_snow_material = ShaderMaterial.new()
	_tree_snow_material.shader = SNOW_SHADER
	_set_atlas_layout(
		_tree_snow_material,
		TREE_COLUMNS,
		TREE_ROWS,
		TREE_SOURCE_DIRS.size(),
		TREE_SNOW_OVERLAY_ATLAS,
	)
	_tree_snow_material.set_shader_parameter("snow_mask_texture", TREE_SNOW_MASK_ATLAS)

	_tree_shadow_material = _make_shadow_material(
		TREE_COLUMNS,
		TREE_ROWS,
		TREE_SOURCE_DIRS.size(),
		_tree_anchor_lut,
		TREE_SHADOW_ATLAS,
		TREE_SHADOW_OUTPUT_UV_MIN,
		TREE_SHADOW_OUTPUT_UV_MAX,
		TREE_SHADOW_DIRECTION,
	)

	_bush_trunk_material = ShaderMaterial.new()
	_bush_trunk_material.shader = TREE_TRUNK_SHADER
	_set_atlas_layout(
		_bush_trunk_material,
		BUSH_COLUMNS,
		BUSH_ROWS,
		BUSH_SOURCE_DIRS.size(),
		BUSH_TRUNK_ATLAS,
	)
	_bush_trunk_material.set_shader_parameter("snow_mask_texture", BUSH_SNOW_MASK_ATLAS)
	_bush_trunk_material.set_shader_parameter("wind_mask_texture", BUSH_WIND_MASK_ATLAS)
	_bush_trunk_material.set_shader_parameter("wind_strength_px", BUSH_WIND_STRENGTH_PX)

	_bush_foliage_material = ShaderMaterial.new()
	_bush_foliage_material.shader = TREE_FOLIAGE_SHADER
	_set_atlas_layout(
		_bush_foliage_material,
		BUSH_COLUMNS,
		BUSH_ROWS,
		BUSH_SOURCE_DIRS.size(),
		BUSH_FOLIAGE_ATLAS,
	)
	_bush_foliage_material.set_shader_parameter("wind_mask_texture", BUSH_WIND_MASK_ATLAS)
	_bush_foliage_material.set_shader_parameter("season_mask_texture", BUSH_SEASON_MASK_ATLAS)
	_bush_foliage_material.set_shader_parameter("wind_strength_px", BUSH_WIND_STRENGTH_PX)

	_bush_snow_material = ShaderMaterial.new()
	_bush_snow_material.shader = SNOW_SHADER
	_set_atlas_layout(
		_bush_snow_material,
		BUSH_COLUMNS,
		BUSH_ROWS,
		BUSH_SOURCE_DIRS.size(),
		BUSH_SNOW_OVERLAY_ATLAS,
	)
	_bush_snow_material.set_shader_parameter("snow_mask_texture", BUSH_SNOW_MASK_ATLAS)

	_bush_shadow_material = _make_shadow_material(
		BUSH_COLUMNS,
		BUSH_ROWS,
		BUSH_SOURCE_DIRS.size(),
		_bush_anchor_lut,
		BUSH_SHADOW_ATLAS,
		BUSH_SHADOW_OUTPUT_UV_MIN,
		BUSH_SHADOW_OUTPUT_UV_MAX,
		BUSH_SHADOW_DIRECTION,
	)

	_rock_albedo_material = ShaderMaterial.new()
	_rock_albedo_material.shader = ALBEDO_SHADER
	_set_atlas_layout(
		_rock_albedo_material,
		ROCK_COLUMNS,
		ROCK_ROWS,
		ROCK_SOURCE_DIRS.size(),
		ROCK_ALBEDO_ATLAS,
	)

	_rock_snow_material = ShaderMaterial.new()
	_rock_snow_material.shader = SNOW_SHADER
	_set_atlas_layout(
		_rock_snow_material,
		ROCK_COLUMNS,
		ROCK_ROWS,
		ROCK_SOURCE_DIRS.size(),
		ROCK_SNOW_OVERLAY_ATLAS,
	)
	_rock_snow_material.set_shader_parameter("snow_mask_texture", ROCK_SNOW_MASK_ATLAS)

	_rock_shadow_material = _make_shadow_material(
		ROCK_COLUMNS,
		ROCK_ROWS,
		ROCK_SOURCE_DIRS.size(),
		_rock_anchor_lut,
		ROCK_SHADOW_ATLAS,
		SHADOW_OUTPUT_UV_MIN,
		SHADOW_OUTPUT_UV_MAX,
		SHADOW_DIRECTION,
	)
	_living_flora_material = _make_classic_decor_material(
		LIVING_FLORA_ATLAS_COLUMNS,
		LIVING_FLORA_ATLAS_ROWS,
		LIVING_FLORA_FRAME_COUNT,
		LIVING_FLORA_FRAMES_PER_VIEW,
		LIVING_FLORA_ANIMATION_FPS,
	)
	_spiky_flora_material = _make_classic_decor_material(
		SPIKY_FLORA_ATLAS_COLUMNS,
		SPIKY_FLORA_ATLAS_ROWS,
		SPIKY_FLORA_FRAME_COUNT,
		1,
		0.0,
	)
	_classic_decor_shadow_material = ShaderMaterial.new()
	_classic_decor_shadow_material.shader = CLASSIC_DECOR_SHADOW_SHADER
	set_season_amount(_season_amount)
	set_sun_lighting(WorldVisualLightingProfile.SHADOW_MIN_LENGTH_PX, 0.0)


func _make_shadow_material(
		columns: int,
		rows: int,
		frame_count: int,
		anchor_lut: Texture2D,
		atlas: Texture2D,
		output_uv_min: Vector2,
		output_uv_max: Vector2,
		shadow_direction: Vector2,
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADOW_SHADER
	_set_atlas_layout(material, columns, rows, frame_count, atlas)
	material.set_shader_parameter("anchor_lut", anchor_lut)
	material.set_shader_parameter("output_uv_min", output_uv_min)
	material.set_shader_parameter("output_uv_max", output_uv_max)
	material.set_shader_parameter("shadow_direction", shadow_direction)
	return material


func _make_classic_decor_material(
		columns: int,
		rows: int,
		frame_count: int,
		animation_frames_per_group: int,
		animation_fps: float,
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLASSIC_DECOR_SHADER
	material.set_shader_parameter("atlas_columns", float(columns))
	material.set_shader_parameter("atlas_rows", float(rows))
	material.set_shader_parameter("atlas_frame_count", float(frame_count))
	material.set_shader_parameter(
		"animation_frames_per_group",
		float(animation_frames_per_group),
	)
	material.set_shader_parameter("animation_fps", animation_fps)
	material.set_shader_parameter("wind_direction", Vector2.RIGHT)
	return material


func _set_atlas_layout(
		material: ShaderMaterial,
		columns: int,
		rows: int,
		frame_count: int,
		atlas: Texture2D,
) -> void:
	material.set_shader_parameter("atlas_columns", float(columns))
	material.set_shader_parameter("atlas_rows", float(rows))
	material.set_shader_parameter("atlas_frame_count", float(frame_count))
	material.set_shader_parameter(
		"frame_texel_size",
		Vector2(float(columns) / float(atlas.get_width()), float(rows) / float(atlas.get_height())),
	)


func _read_metrics(source_dirs: Array[String], fixed_scale: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for source_dir: String in source_dirs:
		var path: String = "%s/meta.json" % source_dir
		if not FileAccess.file_exists(path):
			push_error("WorldLayeredObjectAssetCatalog: missing %s" % path)
			return PackedFloat32Array()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			push_error("WorldLayeredObjectAssetCatalog: invalid %s" % path)
			return PackedFloat32Array()
		var metadata: Dictionary = parsed as Dictionary
		var anchor: Array = metadata.get("anchor", []) as Array
		var alpha_bbox: Array = metadata.get("alpha_bbox", []) as Array
		if anchor.size() < 2 or alpha_bbox.size() < 4:
			push_error("WorldLayeredObjectAssetCatalog: incomplete %s" % path)
			return PackedFloat32Array()
		result.append(float(metadata.get("frame_width", 0.0)))
		result.append(float(metadata.get("frame_height", 0.0)))
		result.append(float(anchor[0]))
		result.append(float(anchor[1]))
		result.append(fixed_scale if fixed_scale > 0.0 else float(alpha_bbox[2]))
	return result


func _make_anchor_lut(metrics: PackedFloat32Array, stride: int) -> Texture2D:
	var count: int = metrics.size() / stride
	var image := Image.create_empty(count, 1, false, Image.FORMAT_RGF)
	for index: int in range(count):
		var offset: int = index * stride
		var width: float = maxf(metrics[offset + METRIC_FRAME_WIDTH], 1.0)
		var height: float = maxf(metrics[offset + METRIC_FRAME_HEIGHT], 1.0)
		image.set_pixel(
			index,
			0,
			Color(
				metrics[offset + METRIC_ANCHOR_X] / width,
				metrics[offset + METRIC_ANCHOR_Y] / height,
				0.0,
				1.0,
			),
		)
	return ImageTexture.create_from_image(image)


func _make_shadow_mesh(output_uv_min: Vector2, output_uv_max: Vector2) -> ArrayMesh:
	var min_vertex: Vector2 = output_uv_min - Vector2(0.5, 0.5)
	var max_vertex: Vector2 = output_uv_max - Vector2(0.5, 0.5)
	var vertices := PackedVector3Array([
		Vector3(min_vertex.x, min_vertex.y, 0.0),
		Vector3(max_vertex.x, min_vertex.y, 0.0),
		Vector3(max_vertex.x, max_vertex.y, 0.0),
		Vector3(min_vertex.x, min_vertex.y, 0.0),
		Vector3(max_vertex.x, max_vertex.y, 0.0),
		Vector3(min_vertex.x, max_vertex.y, 0.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
