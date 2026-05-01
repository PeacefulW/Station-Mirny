extends SceneTree

const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const RiverGenSettings = preload("res://core/resources/river_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failed: bool = false

func _init() -> void:
	var preset_ids: Array[StringName] = RiverGenSettings.preset_ids()
	_assert(preset_ids[0] == RiverGenSettings.PRESET_FULL_HYDROLOGY, "Full Hydrology must remain the default water preset")
	_assert(preset_ids.has(RiverGenSettings.PRESET_LAKES_ONLY), "Lakes Only preset should be exposed")
	_assert(preset_ids.has(RiverGenSettings.PRESET_SPARSE_ARCTIC_RIVERS), "Sparse Arctic Rivers preset should be exposed")
	_assert(preset_ids.has(RiverGenSettings.PRESET_WET_RIVER_NETWORK), "Wet River Network preset should be exposed")
	_assert(preset_ids.has(RiverGenSettings.PRESET_DELTA_HEAVY), "Delta Heavy preset should be exposed")
	_assert(not preset_ids.has(RiverGenSettings.PRESET_CUSTOM), "Custom should be UI state, not a selectable generation preset")

	var defaults: RiverGenSettings = RiverGenSettings.hard_coded_defaults()
	var full: RiverGenSettings = RiverGenSettings.for_preset(RiverGenSettings.PRESET_FULL_HYDROLOGY)
	_assert(_settings_equal(defaults, full), "hard-coded defaults should match the Full Hydrology preset")
	_assert(full.enabled, "Full Hydrology should keep rivers enabled")
	_assert(full.density > 0.0, "Full Hydrology should keep non-zero river density")

	var fallback: RiverGenSettings = RiverGenSettings.for_preset(&"unknown_v4_preset")
	_assert(_settings_equal(fallback, full), "unknown water preset should safely fall back to Full Hydrology")
	_assert(fallback.preset_id == RiverGenSettings.PRESET_FULL_HYDROLOGY, "unknown preset fallback should report Full Hydrology")

	var lakes_only: RiverGenSettings = RiverGenSettings.for_preset(RiverGenSettings.PRESET_LAKES_ONLY)
	_assert(lakes_only.enabled, "Lakes Only must not disable hydrology, lakes, or ocean output")
	_assert(is_equal_approx(lakes_only.density, 0.0), "Lakes Only should disable trunk/tributary river selection through density 0")
	_assert(is_equal_approx(lakes_only.braid_chance, 0.0), "Lakes Only should disable braid/split chances")
	_assert(is_equal_approx(lakes_only.delta_scale, 0.0), "Lakes Only should disable delta fan tuning")
	_assert(lakes_only.lake_chance >= full.lake_chance, "Lakes Only should prefer lake generation over the default")
	_assert(lakes_only.preset_id == RiverGenSettings.PRESET_LAKES_ONLY, "Lakes Only should keep its transient preset id")

	var saved_lakes_only: Dictionary = lakes_only.to_save_dict()
	_assert(not saved_lakes_only.has("preset_id"), "river preset id must not become a save field")
	_assert(not saved_lakes_only.has("hydrology_mode"), "V4-7 should not add a new persisted hydrology mode")
	var restored_lakes_only: RiverGenSettings = RiverGenSettings.from_save_dict(saved_lakes_only)
	_assert(_settings_equal(restored_lakes_only, lakes_only), "existing river save fields should round-trip Lakes Only values")
	_assert(restored_lakes_only.preset_id == RiverGenSettings.PRESET_LAKES_ONLY, "loaded matching fields may recover transient Lakes Only UI state")

	var custom := RiverGenSettings.from_save_dict(lakes_only.to_save_dict())
	custom.lake_chance = 0.37
	custom = RiverGenSettings.from_save_dict(custom.to_save_dict())
	_assert(custom.preset_id == RiverGenSettings.PRESET_CUSTOM, "non-preset field combinations should report Custom")

	_assert(_locale_contains("UI_WORLDGEN_WATER_PRESET_LABEL"), "water preset label must be localized")
	_assert(_locale_contains("UI_WORLDGEN_WATER_PRESET_FULL_HYDROLOGY"), "Full Hydrology preset label must be localized")
	_assert(_locale_contains("UI_WORLDGEN_WATER_PRESET_LAKES_ONLY"), "Lakes Only preset label must be localized")
	_assert(_locale_contains("UI_WORLDGEN_WATER_PRESET_SPARSE_ARCTIC_RIVERS"), "Sparse Arctic Rivers preset label must be localized")
	_assert(_locale_contains("UI_WORLDGEN_WATER_PRESET_WET_RIVER_NETWORK"), "Wet River Network preset label must be localized")
	_assert(_locale_contains("UI_WORLDGEN_WATER_PRESET_DELTA_HEAVY"), "Delta Heavy preset label must be localized")
	_assert(_locale_contains("UI_WORLDGEN_WATER_PRESET_CUSTOM"), "Custom preset label must be localized")
	_assert(_new_game_panel_exposes_presets(), "new-game Water Sector should expose water preset selection")

	var core := WorldCore.new()
	var full_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed(full)
	)
	_assert(bool(full_result.get("success", false)), "Full Hydrology prepass should build")
	_assert(int(full_result.get("river_segment_count", 0)) > 0, "Full Hydrology should keep river segments")

	var legacy_lakes_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_LAKE_BASIN_CONTINUITY_V4_VERSION,
		_build_settings_packed(lakes_only)
	)
	_assert(bool(legacy_lakes_result.get("success", false)), "legacy density-zero hydrology prepass should still build")
	_assert(int(legacy_lakes_result.get("river_segment_count", 0)) > 0, "world_version 34 should preserve legacy density-zero river behavior")

	var lakes_result: Dictionary = core.build_world_hydrology_prepass(
		WorldRuntimeConstants.DEFAULT_WORLD_SEED,
		WorldRuntimeConstants.WORLD_VERSION,
		_build_settings_packed(lakes_only)
	)
	_assert(bool(lakes_result.get("success", false)), "Lakes Only prepass should build")
	_assert(int(lakes_result.get("river_segment_count", -1)) == 0, "Lakes Only should suppress trunk/tributary river segments on the V4-7 boundary")
	_assert(bool(lakes_result.get("river_density_zero_trunk_suppressed", false)), "Lakes Only should expose a RAM-only density-zero suppression counter")
	_assert(int(lakes_result.get("lake_spill_point_count", 0)) > 0, "Lakes Only should still generate natural lake spill diagnostics")
	_assert(int(lakes_result.get("basin_contour_lake_node_count", 0)) > 0, "Lakes Only should still generate lake basin output")
	_assert(int(lakes_result.get("ocean_coastline_node_count", 0)) > 0, "Lakes Only should keep ocean/coast output")

	if _failed:
		quit(1)
		return
	print("river_gen_settings_presets_v4_smoke_test: OK")
	quit(0)

func _build_settings_packed(river_settings: RiverGenSettings) -> PackedFloat32Array:
	var bounds := WorldBoundsSettings.for_preset(WorldBoundsSettings.PRESET_SMALL)
	var mountain_settings := MountainGenSettings.hard_coded_defaults()
	var foundation_settings := FoundationGenSettings.for_bounds(bounds)
	var packed: PackedFloat32Array = mountain_settings.flatten_to_packed()
	packed = foundation_settings.write_to_settings_packed(packed, bounds)
	return river_settings.write_to_settings_packed(packed)

func _settings_equal(a: RiverGenSettings, b: RiverGenSettings) -> bool:
	return JSON.stringify(a.to_save_dict()) == JSON.stringify(b.to_save_dict())

func _locale_contains(key: String) -> bool:
	for path: String in ["res://locale/en/messages.po", "res://locale/ru/messages.po"]:
		var text: String = FileAccess.get_file_as_string(path)
		if not text.contains('msgid "%s"' % key):
			return false
	return true

func _new_game_panel_exposes_presets() -> bool:
	var source: String = FileAccess.get_file_as_string("res://scenes/ui/new_game_panel.gd")
	return source.contains("_water_preset_select") \
			and source.contains("RiverGenSettings.preset_select_ids()") \
			and source.contains("_on_water_preset_selected") \
			and source.contains("_sync_water_preset_select")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
