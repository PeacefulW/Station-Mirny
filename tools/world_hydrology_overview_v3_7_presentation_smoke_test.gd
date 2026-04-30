extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

const FLOODPLAIN_PRESENTATION_PATH: String = "res://data/balance/water_presentation_floodplain.tres"

var _failed: bool = false

func _init() -> void:
	_assert(WorldRuntimeConstants.WORLD_VERSION == 30, "V3-7 presentation polish must not bump WORLD_VERSION")
	_assert(ResourceLoader.exists(FLOODPLAIN_PRESENTATION_PATH), "V3-7 should provide a floodplain water presentation resource")
	var presentation: Resource = load(FLOODPLAIN_PRESENTATION_PATH) as Resource
	_assert(
		presentation != null \
				and presentation.has_method("is_valid_profile") \
				and bool(presentation.call("is_valid_profile")),
		"floodplain water presentation resource should validate"
	)

	var view := ChunkView.new()
	root.add_child(view)
	if not view.has_method("get_floodplain_overlay_debug"):
		_assert(false, "ChunkView should expose floodplain overlay debug for V3-7 smoke coverage")
		view.queue_free()
		_finish()
		return

	view.configure(Vector2i.ZERO)
	view.begin_apply(_build_packet())
	while view.apply_next_batch(128):
		pass

	var low_debug: Dictionary = view.get_floodplain_overlay_debug(Vector2i(3, 0))
	var far_debug: Dictionary = view.get_floodplain_overlay_debug(Vector2i(1, 0))
	var near_debug: Dictionary = view.get_floodplain_overlay_debug(Vector2i(2, 0))
	_assert(bool(far_debug.get("ready", false)), "floodplain overlay debug should be ready after chunk apply")
	_assert(int(far_debug.get("texture_width", 0)) == WorldRuntimeConstants.CHUNK_SIZE, "floodplain overlay should use one pixel per tile, not per-tile material instances")
	var low_color: Color = low_debug.get("color", Color.TRANSPARENT) as Color
	var far_color: Color = far_debug.get("color", Color.TRANSPARENT) as Color
	var near_color: Color = near_debug.get("color", Color.TRANSPARENT) as Color
	_assert(low_color.a == 0.0, "low non-floodplain strength should not draw floodplain overlay")
	_assert(far_color.a > 0.0, "far floodplain strength should draw a visible overlay")
	_assert(near_color.a > far_color.a, "near floodplain strength should draw stronger than far floodplain strength")

	view.queue_free()
	_finish()

func _build_packet() -> Dictionary:
	var terrain_ids := PackedInt32Array()
	var terrain_atlas_indices := PackedInt32Array()
	var hydrology_flags := PackedInt32Array()
	var floodplain_strength := PackedByteArray()
	terrain_ids.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	terrain_atlas_indices.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	hydrology_flags.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	floodplain_strength.resize(WorldRuntimeConstants.CHUNK_CELL_COUNT)
	for index: int in range(WorldRuntimeConstants.CHUNK_CELL_COUNT):
		terrain_ids[index] = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
		terrain_atlas_indices[index] = 0
		hydrology_flags[index] = 0
		floodplain_strength[index] = 0
	var far_index: int = WorldRuntimeConstants.local_to_index(Vector2i(1, 0))
	var near_index: int = WorldRuntimeConstants.local_to_index(Vector2i(2, 0))
	var low_index: int = WorldRuntimeConstants.local_to_index(Vector2i(3, 0))
	terrain_ids[far_index] = WorldRuntimeConstants.TERRAIN_FLOODPLAIN
	terrain_ids[near_index] = WorldRuntimeConstants.TERRAIN_FLOODPLAIN
	hydrology_flags[far_index] = WorldRuntimeConstants.HYDROLOGY_FLAG_FLOODPLAIN \
			| WorldRuntimeConstants.HYDROLOGY_FLAG_FLOODPLAIN_FAR
	hydrology_flags[near_index] = WorldRuntimeConstants.HYDROLOGY_FLAG_FLOODPLAIN \
			| WorldRuntimeConstants.HYDROLOGY_FLAG_FLOODPLAIN_NEAR
	floodplain_strength[low_index] = 64
	floodplain_strength[far_index] = 128
	floodplain_strength[near_index] = 224
	return {
		"terrain_ids": terrain_ids,
		"terrain_atlas_indices": terrain_atlas_indices,
		"hydrology_flags": hydrology_flags,
		"floodplain_strength": floodplain_strength,
	}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("world_hydrology_overview_v3_7_presentation_smoke_test: OK")
	quit(0)
