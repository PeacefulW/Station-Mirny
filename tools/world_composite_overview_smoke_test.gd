extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldChunkPacketBackend = preload("res://core/systems/world/world_chunk_packet_backend.gd")
const WorldFoundationPalette = preload("res://core/systems/world/world_foundation_palette.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const COMPOSITE_MODE: StringName = &"composite"
const COMPOSITE_LAYER_MASK: int = 1 << 6
const WORKER_TIMEOUT_MS: int = 5000

var _failed: bool = false

func _init() -> void:
	var modes: Array[StringName] = WorldFoundationPalette.all_modes()
	_assert(not modes.is_empty(), "overview palette should expose at least one mode")
	_assert(modes.has(COMPOSITE_MODE), "overview palette should expose the composite terrain-and-water mode")
	_assert(modes[0] == COMPOSITE_MODE, "composite terrain-and-water mode should be the default first overview mode")
	_assert(WorldFoundationPalette.coerce_mode(COMPOSITE_MODE) == COMPOSITE_MODE, "composite mode should be accepted by the palette")
	_assert(
		WorldFoundationPalette.get_label_key(COMPOSITE_MODE) == &"UI_WORLDGEN_OVERVIEW_MODE_COMPOSITE",
		"composite mode should have a localization key"
	)

	var palette := WorldFoundationPalette.new()
	_assert(palette.get_mode() == COMPOSITE_MODE, "new overview palettes should default to composite mode")
	_assert(palette.get_layer_mask() == COMPOSITE_LAYER_MASK, "composite mode should use the composite overview layer mask")

	var settings_packed: PackedFloat32Array = _build_settings_packed(WorldBoundsSettings.PRESET_SMALL)
	_assert(_native_composite_overview_is_available(settings_packed), "WorldCore should expose native composite overview images")
	var foundation_result: Dictionary = _request_backend_overview(settings_packed, 0)
	var composite_result: Dictionary = _request_backend_overview(settings_packed, COMPOSITE_LAYER_MASK)
	_assert(bool(foundation_result.get("success", false)), "foundation overview should still publish through the backend")
	_assert(bool(composite_result.get("success", false)), "composite overview should publish through the backend")
	var foundation_image: Image = foundation_result.get("image", null) as Image
	var composite_image: Image = composite_result.get("image", null) as Image
	_assert(foundation_image != null and not foundation_image.is_empty(), "foundation overview should return an image")
	_assert(composite_image != null and not composite_image.is_empty(), "composite overview should return an image")
	_assert(
		composite_image.get_width() == foundation_image.get_width() and composite_image.get_height() == foundation_image.get_height(),
		"composite overview should preserve the foundation overview dimensions"
	)
	_assert_composite_preserves_foundation_mountains(settings_packed)
	var pixel_counts: Dictionary = _count_composite_pixels(composite_image)
	_assert(int(pixel_counts.get("water", 0)) > 0, "composite overview should contain river/lake/ocean pixels")
	_assert(int(pixel_counts.get("relief", 0)) > 0, "composite overview should keep visible relief pixels")
	_assert(
		_gdscript_backend_uses_native_composite(),
		"overview composition should use the native composite overview API"
	)

	if _failed:
		quit(1)
		return
	print("world_composite_overview_smoke_test: OK")
	quit(0)

func _build_settings_packed(preset: StringName) -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(preset)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var river_settings := RiverGenSettings.hard_coded_defaults()
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _native_composite_overview_is_available(settings_packed: PackedFloat32Array) -> bool:
	var core := WorldCore.new()
	if not core.has_method("get_world_composite_overview"):
		return false
	var build_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed
	)
	if not bool(build_result.get("success", false)):
		return false
	var image: Image = core.call(
		"get_world_composite_overview",
		COMPOSITE_LAYER_MASK,
		WorldFoundationPalette.OVERVIEW_PIXELS_PER_CELL
	) as Image
	if image == null or image.is_empty():
		return false
	var counts: Dictionary = _count_composite_pixels(image)
	return int(counts.get("water", 0)) > 0 and int(counts.get("relief", 0)) > 0

func _request_backend_overview(settings_packed: PackedFloat32Array, layer_mask: int) -> Dictionary:
	var backend := WorldChunkPacketBackend.new()
	backend.start()
	backend.queue_overview_request(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		settings_packed,
		1,
		layer_mask,
		WorldFoundationPalette.OVERVIEW_PIXELS_PER_CELL
	)
	var deadline: int = Time.get_ticks_msec() + WORKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		var results: Array[Dictionary] = backend.drain_completed_overviews(1)
		if not results.is_empty():
			backend.stop()
			return results[0]
		OS.delay_msec(10)
	backend.stop()
	return {
		"success": false,
		"message": "Timed out waiting for overview worker result.",
	}

func _count_composite_pixels(image: Image) -> Dictionary:
	var counts: Dictionary = {
		"water": 0,
		"relief": 0,
	}
	if image == null or image.is_empty():
		return counts
	var data: PackedByteArray = image.get_data()
	for offset: int in range(0, data.size(), 4):
		var r: int = int(data[offset])
		var g: int = int(data[offset + 1])
		var b: int = int(data[offset + 2])
		var a: int = int(data[offset + 3])
		if a == 0:
			continue
		if _is_water_pixel(r, g, b):
			counts["water"] = int(counts["water"]) + 1
		elif r > 28 or g > 34 or b > 32:
			counts["relief"] = int(counts["relief"]) + 1
	return counts

func _is_water_pixel(r: int, g: int, b: int) -> bool:
	return b >= 110 and b > r + 35 and b >= g + 8

func _assert_composite_preserves_foundation_mountains(settings_packed: PackedFloat32Array) -> void:
	var checked_mountain_pixels: int = 0
	var seeds: Array[int] = [
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		1,
		7,
		23,
		42,
		1337,
		26031,
	]
	for seed: int in seeds:
		var core := WorldCore.new()
		var build_result: Dictionary = core.build_world_hydrology_prepass(
			seed,
			WorldRuntimeConstants.WORLD_VERSION,
			settings_packed
		)
		_assert(
			bool(build_result.get("success", false)),
			"hydrology prepass should build for composite mountain priority check"
		)
		var foundation_image: Image = core.call(
			"get_world_foundation_overview",
			0,
			WorldFoundationPalette.OVERVIEW_PIXELS_PER_CELL
		) as Image
		var composite_image: Image = core.call(
			"get_world_composite_overview",
			COMPOSITE_LAYER_MASK,
			WorldFoundationPalette.OVERVIEW_PIXELS_PER_CELL
		) as Image
		_assert(
			foundation_image != null and composite_image != null,
			"overview images should exist for composite mountain priority check"
		)
		if foundation_image == null or composite_image == null:
			continue
		_assert(
			foundation_image.get_width() == composite_image.get_width() and foundation_image.get_height() == composite_image.get_height(),
			"foundation and composite overview dimensions should match for mountain priority check"
		)
		var foundation_data: PackedByteArray = foundation_image.get_data()
		var composite_data: PackedByteArray = composite_image.get_data()
		var max_offset: int = min(foundation_data.size(), composite_data.size())
		for offset: int in range(0, max_offset, 4):
			var r: int = int(foundation_data[offset])
			var g: int = int(foundation_data[offset + 1])
			var b: int = int(foundation_data[offset + 2])
			var a: int = int(foundation_data[offset + 3])
			if not _is_foundation_mountain_pixel(r, g, b, a):
				continue
			checked_mountain_pixels += 1
			if (
				composite_data[offset] != foundation_data[offset] or
				composite_data[offset + 1] != foundation_data[offset + 1] or
				composite_data[offset + 2] != foundation_data[offset + 2] or
				composite_data[offset + 3] != foundation_data[offset + 3]
			):
				_assert(false, "composite overview should not overwrite foundation mountain pixels with hydrology overlay")
				return
	_assert(checked_mountain_pixels > 0, "composite mountain priority check should inspect foundation mountain pixels")

func _is_foundation_mountain_pixel(r: int, g: int, b: int, a: int) -> bool:
	if a != 255:
		return false
	var is_wall: bool = r >= 164 and r <= 238 and g == r - 4 and b == r - 18
	var is_foot: bool = (
		r >= 107 and r <= 178 and
		g >= 98 and g <= 143 and
		b >= 74 and b <= 102 and
		r > g and g > b
	)
	return is_wall or is_foot

func _gdscript_backend_uses_native_composite() -> bool:
	var backend_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_chunk_packet_backend.gd")
	if not backend_source.contains("get_world_composite_overview"):
		return false
	if backend_source.contains("get_world_hydrology_snapshot"):
		return false
	if backend_source.contains("blend_rect") or backend_source.contains("get_pixel(") or backend_source.contains("set_pixel("):
		return false
	return true

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
