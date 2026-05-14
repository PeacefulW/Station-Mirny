extends SceneTree

const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")
const MountainContourStyleRegistry = preload("res://core/systems/world/mountain_contour_style_registry.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const STYLE_PATH: String = "res://assets/textures/terrain/mountains/mountain/mountain_contour_style.v1.json"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert_style_fixture_exists()
	_assert_registry_loads_known_style()
	_assert_invalid_style_shapes_fail()

	if _failed:
		quit(1)
		return
	print("mountain_contour_style_registry_smoke_test: OK")
	quit(0)

func _assert_style_fixture_exists() -> void:
	_assert(FileAccess.file_exists(STYLE_PATH), "Canonical mountain contour style fixture must exist.")

func _assert_registry_loads_known_style() -> void:
	var registry := MountainContourStyleRegistry.new()
	_assert(registry.load_styles([STYLE_PATH]), "Registry must load the canonical mountain contour style.")
	_assert(registry.has_style(StringName("mountain")), "Registry must index style by asset name.")

	var style: MountainContourStyle = registry.get_style(StringName("mountain"))
	_assert(style != null, "Registry lookup must return MountainContourStyle.")
	if style == null:
		return
	_assert(style.asset_name == StringName("mountain"), "Loaded style must keep the authored asset name.")
	_assert(style.logical_tile_size_px == WorldRuntimeConstants.TILE_SIZE_PX, "Style logical tile size must match world runtime tile size.")
	_assert(style.top_albedo is Texture2D, "top_albedo must load as Texture2D.")
	_assert(style.face_albedo is Texture2D, "face_albedo must load as Texture2D.")
	_assert(style.base_albedo is Texture2D, "base_albedo must load as Texture2D.")
	_assert(style.top_modulation is Texture2D, "top_modulation must load as Texture2D.")
	_assert(style.face_modulation is Texture2D, "face_modulation must load as Texture2D.")
	_assert(style.top_normal is Texture2D, "top_normal must load as Texture2D.")
	_assert(style.face_normal is Texture2D, "face_normal must load as Texture2D.")
	_assert(style.edge_profile_lut is Texture2D, "edge_profile_lut must load as Texture2D.")
	_assert(style.height_profile_lut is Texture2D, "height_profile_lut must load as Texture2D.")

	var snapshot: Dictionary = style.debug_snapshot()
	_assert(snapshot.get("asset_name", "") == "mountain", "Debug snapshot must expose asset_name.")
	_assert(int(snapshot.get("logical_tile_size_px", 0)) == WorldRuntimeConstants.TILE_SIZE_PX, "Debug snapshot must expose logical tile size.")
	_assert(int(snapshot.get("texture_count", 0)) == 9, "Debug snapshot must count required style textures.")

func _assert_invalid_style_shapes_fail() -> void:
	var data: Dictionary = _load_style_dict(STYLE_PATH)
	_assert(not data.is_empty(), "Canonical style JSON must parse for invalid-case checks.")
	if data.is_empty():
		return
	var base_dir: String = STYLE_PATH.get_base_dir()

	var missing_face_normal: Dictionary = data.duplicate(true)
	var missing_paths: Dictionary = missing_face_normal.get("texture_paths", {}) as Dictionary
	missing_paths["face_normal"] = "missing_face_normal.png"
	missing_face_normal["texture_paths"] = missing_paths
	var missing_result: MountainContourStyle = MountainContourStyle.load_from_dict(missing_face_normal, base_dir)
	_assert(missing_result == null, "Missing face_normal texture must fail validation.")

	var wrong_tile_size: Dictionary = data.duplicate(true)
	wrong_tile_size["logical_tile_size_px"] = WorldRuntimeConstants.TILE_SIZE_PX / 2
	var wrong_tile_result: MountainContourStyle = MountainContourStyle.load_from_dict(wrong_tile_size, base_dir)
	_assert(wrong_tile_result == null, "Wrong logical_tile_size_px must fail validation.")

	var legacy_recipe := {
		"schema": "station_peaceful.runtime_sdf_contour_recipe.v1",
		"asset_name": "unnamed_recipe",
	}
	var legacy_result: MountainContourStyle = MountainContourStyle.load_from_dict(legacy_recipe, base_dir)
	_assert(legacy_result == null, "Legacy runtime SDF recipe shape must not be accepted as a contour style.")

func _load_style_dict(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
