extends SceneTree

const Autotile47 = preload("res://core/systems/tiles/autotile_47.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failed: bool = false

func _init() -> void:
	var source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		source.contains("func _is_loaded_mountain_geometry_surface(sample: Dictionary) -> bool:"),
		"world streamer must keep a dedicated runtime mountain surface helper"
	)
	_assert(
		source.contains("return _uses_mountain_surface_presentation("),
		"runtime mountain surface helper must resolve from current terrain_id"
	)
	_assert(
		not source.contains("func _is_loaded_mountain_geometry_surface(sample: Dictionary) -> bool:\n\tvar mountain_flags"),
		"runtime mountain surface helper must not treat stale mountain_flags as current surface"
	)

	var dug_surface_sample: Dictionary = {
		"terrain_id": WorldRuntimeConstants.TERRAIN_PLAINS_DUG,
		"mountain_id": 1,
		"mountain_flags": WorldRuntimeConstants.MOUNTAIN_FLAG_WALL,
	}
	_assert(
		not _is_runtime_mountain_surface(dug_surface_sample),
		"dug tile must not count as mountain surface for runtime autotile adjacency"
	)

	var wall_surface_sample: Dictionary = {
		"terrain_id": WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
		"mountain_id": 1,
		"mountain_flags": WorldRuntimeConstants.MOUNTAIN_FLAG_WALL,
	}
	_assert(
		_is_runtime_mountain_surface(wall_surface_sample),
		"wall tile must count as mountain surface for runtime autotile adjacency"
	)

	var north_wall_tile := Vector2i(2, 1)
	var world_seed: int = 240518
	var variant_index: int = Autotile47.pick_variant(north_wall_tile, world_seed)
	var solid_index: int = Autotile47.build_atlas_index(
		Autotile47.build_signature_code(true, true, true, true, true, true, true, true),
		variant_index
	)
	var open_south_index: int = Autotile47.build_atlas_index(
		Autotile47.build_signature_code(true, true, true, false, false, false, true, true),
		variant_index
	)
	_assert(open_south_index != solid_index, "open inner south edge must not collapse to solid atlas index")

	if _failed:
		quit(1)
		return
	print("world_streamer_visual_patch_smoke_test: OK")
	quit(0)

func _is_runtime_mountain_surface(sample: Dictionary) -> bool:
	var terrain_id: int = int(sample.get("terrain_id", WorldRuntimeConstants.TERRAIN_PLAINS_GROUND))
	return terrain_id == WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL \
		or terrain_id == WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
