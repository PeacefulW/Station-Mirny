extends SceneTree
## Fixed-sun and global painter-pass contract after removal of family batch and
## tall-caster renderers.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldVisualLightingProfile = preload(
	"res://core/systems/world/world_visual_lighting_profile.gd"
)
const AssetCatalog = preload("res://core/systems/world/world_layered_object_asset_catalog.gd")

const EPSILON: float = 0.00001
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_fixed_sun_contract()
	_verify_global_shadow_shader()
	_verify_fixed_pass_depth_contract()
	await process_frame
	if _failures.is_empty():
		print("shadow_direction_and_depth_contract_test: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _verify_fixed_sun_contract() -> void:
	var expected_light_angle: float = WorldVisualLightingProfile.FIXED_LIGHT_ANGLE_DEG
	var expected_shadow_direction: Vector2 = WorldVisualLightingProfile.FIXED_SHADOW_DIRECTION
	for hour: float in [0.0, 6.0, 12.0, 18.0, 23.5]:
		_expect(
			is_equal_approx(WorldVisualLightingProfile.light_angle_deg_for_hour(hour), expected_light_angle),
			"visual sun azimuth stays fixed at hour %.1f" % hour,
		)
	var runtime_direction := Vector2.RIGHT.rotated(
		deg_to_rad(expected_light_angle + 180.0),
	).normalized()
	_expect(runtime_direction.distance_to(expected_shadow_direction) <= EPSILON,
		"runtime projection matches authored atlas direction")
	for family_direction: Vector2 in [
		AssetCatalog.TREE_SHADOW_DIRECTION,
		AssetCatalog.SHADOW_DIRECTION,
		AssetCatalog.BUSH_SHADOW_DIRECTION,
	]:
		_expect(family_direction.distance_to(expected_shadow_direction) <= EPSILON,
			"CPU source metadata shares the fixed shadow direction")
	var dawn: float = WorldVisualLightingProfile.low_sun_for_progress(
		WorldVisualLightingProfile.sun_progress_for_hour(6.0),
	)
	var noon: float = WorldVisualLightingProfile.low_sun_for_progress(
		WorldVisualLightingProfile.sun_progress_for_hour(12.0),
	)
	_expect(
		WorldVisualLightingProfile.shadow_length_px_for_low_sun(dawn)
				> WorldVisualLightingProfile.shadow_length_px_for_low_sun(noon),
		"dawn/dusk stretches the fixed-direction shadow farther than noon",
	)


func _verify_global_shadow_shader() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://assets/shaders/world_render_shadow.gdshader",
	)
	_expect(source.contains("output_crop.xy + sprite_uv(UV) * output_crop.zw"),
		"global shadow maps QuadMesh V through the shared sprite convention")
	_expect(not source.contains("output_crop.xy + UV * output_crop.zw"),
		"global shadow does not vertically mirror authored frames")
	_expect(source.contains("world_shadow_atlas") and source.contains("actor_shadow_atlas"),
		"one fixed shader serves static and actor shadow atlases")
	_expect(source.contains("render_descriptor_lut"),
		"shadow selection is descriptor-driven")
	for retired_family_token: String in ["tree_shadow_atlas", "rock_shadow_atlas", "bush_shadow_atlas"]:
		_expect(not source.contains(retired_family_token),
			"shadow shader has no family sampler %s" % retired_family_token)
	_expect(not source.contains("softness_lod_bias"),
		"global object shadows use natural mip selection")


func _verify_fixed_pass_depth_contract() -> void:
	_expect(WorldRuntimeConstants.Z_WORLD_SHADOW < WorldRuntimeConstants.Z_MOUNTAIN_PAGE,
		"world shadow pass stays below mountain bodies")
	_expect(WorldRuntimeConstants.Z_ACTOR_SHADOW < WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE,
		"actor shadow stays below painter-sorted body pages")
	_expect(WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE < WorldRuntimeConstants.Z_RENDER_EMISSIVE_PAGE_BASE,
		"emissive is a fixed overlay pass above body pages")
	_expect(WorldRuntimeConstants.Z_RENDER_EMISSIVE_PAGE_BASE < WorldRuntimeConstants.Z_RENDER_OVERHEAD_PAGE_BASE,
		"overhead is the highest authored world-object pass")
	var collision_owner_source: String = FileAccess.get_file_as_string(
		"res://core/systems/world/world_object_collision_owner.gd",
	)
	_expect(not collision_owner_source.contains("ShaderMaterial")
			and not collision_owner_source.contains("MultiMesh"),
		"chunk collision owner has no shadow or body renderer")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
