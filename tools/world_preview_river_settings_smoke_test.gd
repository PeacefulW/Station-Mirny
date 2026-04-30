extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldPreviewController = preload("res://core/systems/world/world_preview_controller.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failed: bool = false

func _init() -> void:
	var controller := WorldPreviewController.new()
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)

	var dry_settings := RiverGenSettings.hard_coded_defaults()
	dry_settings.density = 0.05
	dry_settings.width_scale = 0.5
	dry_settings.lake_chance = 0.0
	dry_settings.meander_strength = 0.1
	dry_settings.braid_chance = 0.0

	var wet_settings := RiverGenSettings.hard_coded_defaults()
	wet_settings.density = 1.0
	wet_settings.width_scale = 3.0
	wet_settings.lake_chance = 1.0
	wet_settings.meander_strength = 1.0
	wet_settings.braid_chance = 1.0

	controller.queue_preview_rebuild(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		mountain_settings,
		bounds,
		foundation_settings,
		dry_settings
	)
	var dry_signature: String = str(controller._pending_settings_signature)

	controller.queue_preview_rebuild(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		mountain_settings,
		bounds,
		foundation_settings,
		wet_settings
	)
	var wet_signature: String = str(controller._pending_settings_signature)

	_assert(dry_signature != wet_signature, "preview signature should include river settings")

	var packed: PackedFloat32Array = controller._build_settings_packed(
		mountain_settings,
		bounds,
		foundation_settings,
		wet_settings
	)
	_assert(
		is_equal_approx(packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_WIDTH_SCALE], wet_settings.width_scale),
		"preview settings_packed should use supplied river width scale"
	)
	_assert(
		is_equal_approx(packed[WorldRuntimeConstants.SETTINGS_PACKED_LAYOUT_RIVER_LAKE_CHANCE], wet_settings.lake_chance),
		"preview settings_packed should use supplied lake chance"
	)
	_assert(_native_preview_patch_image_is_available(packed), "WorldCore should expose native preview patch images")
	_assert(_preview_palette_uses_native_patch_images(), "world preview patch coloring should run through native patch images")

	if _failed:
		quit(1)
		return
	print("world_preview_river_settings_smoke_test: OK")
	quit(0)

func _native_preview_patch_image_is_available(settings_packed: PackedFloat32Array) -> bool:
	var core := WorldCore.new()
	if not core.has_method("make_world_preview_patch_image"):
		return false
	var coords := PackedVector2Array()
	coords.append(Vector2.ZERO)
	var packets: Array = core.generate_chunk_packets_batch(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		coords,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	if packets.size() != 1:
		return false
	var image: Image = core.call("make_world_preview_patch_image", packets[0] as Dictionary, &"terrain") as Image
	return image != null \
			and not image.is_empty() \
			and image.get_width() == WorldRuntimeConstants.CHUNK_SIZE \
			and image.get_height() == WorldRuntimeConstants.CHUNK_SIZE

func _preview_palette_uses_native_patch_images() -> bool:
	var palette_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_preview_palette.gd")
	if not palette_source.contains("make_world_preview_patch_image"):
		return false
	for forbidden: String in ["set_pixel(", "get_pixel(", "Image.create(", "Image.create_from_data("]:
		if palette_source.contains(forbidden):
			return false
	return true

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
