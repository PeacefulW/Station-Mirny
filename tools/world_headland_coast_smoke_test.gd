extends SceneTree

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failed: bool = false

func _init() -> void:
	var constants_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_runtime_constants.gd")
	var core_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	var prepass_source: String = FileAccess.get_file_as_string("res://gdextension/src/world_hydrology_prepass.cpp")

	_assert(
		WorldRuntimeConstants.WORLD_VERSION > WorldRuntimeConstants.WORLD_HYDROLOGY_SHAPE_FIX_VERSION,
		"current world version should advance beyond V1-R16 for multi-scale coastline headlands"
	)
	_assert(constants_source.contains("WORLD_HEADLAND_COAST_VERSION"), "runtime constants should expose WORLD_HEADLAND_COAST_VERSION")
	_assert(core_source.contains("WORLD_HEADLAND_COAST_VERSION"), "chunk coast rasterization should gate headland carving behind WORLD_HEADLAND_COAST_VERSION")
	_assert(prepass_source.contains("WORLD_HEADLAND_COAST_VERSION"), "overview coast rasterization should gate headland carving behind WORLD_HEADLAND_COAST_VERSION")
	_assert(_source_has_headland_octave(core_source), "world_core coast sampler should include a low-frequency headland octave")
	_assert(_source_has_headland_octave(prepass_source), "hydrology overview coast sampler should include a low-frequency headland octave")

	if _failed:
		quit(1)
		return
	print("world_headland_coast_smoke_test: OK")
	quit(0)

func _source_has_headland_octave(source: String) -> bool:
	return source.contains("headland_noise") \
			and source.contains("headland_offset") \
			and source.contains("cell_size * 8.0f") \
			and source.contains("cell_size * 5.0f") \
			and source.contains("cell_size * 1.50f")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
