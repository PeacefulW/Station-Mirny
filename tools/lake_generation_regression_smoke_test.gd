extends SceneTree

const ChunkView = preload("res://core/systems/world/chunk_view.gd")

var _failed: bool = false

func _init() -> void:
	_assert_lake_classification_uses_foundation_height()
	_assert_overview_uses_lake_settings()
	_assert_basin_bfs_uses_dynamic_rim()
	_assert_water_seam_refresh_contract()
	if _failed:
		quit(1)
		return
	print("lake_generation_regression_smoke_test: OK")
	quit(0)

func _assert_lake_classification_uses_foundation_height() -> void:
	var source: String = FileAccess.get_file_as_string("res://gdextension/src/world_core.cpp")
	_assert(
		source.contains("sample_foundation_height_bilinear"),
		"WorldCore lake classification must sample foundation_height in the same units as lake_water_level_q16."
	)
	_assert(
		not source.contains("mountain_elevations[static_cast<size_t>(sample_index)] + shore_warp"),
		"WorldCore lake classification must not compare raw mountain elevation against foundation_height water level."
	)

func _assert_overview_uses_lake_settings() -> void:
	var source: String = FileAccess.get_file_as_string("res://gdextension/src/world_prepass.cpp")
	_assert(
		source.contains("const LakeSettings &p_lake_settings"),
		"Overview lake classification must receive the active LakeSettings."
	)
	_assert(
		source.contains("lake_settings_(p_lake_settings)"),
		"OverviewTerrainSampler must store the active LakeSettings."
	)
	_assert(
		not source.contains("const LakeSettings lake_settings;"),
		"Overview lake classification must not instantiate default LakeSettings."
	)

func _assert_basin_bfs_uses_dynamic_rim() -> void:
	var source: String = FileAccess.get_file_as_string("res://gdextension/src/lake_field.cpp")
	_assert(
		source.contains("rim_height_so_far"),
		"Lake basin BFS must track a dynamic observed rim height."
	)
	_assert(
		not source.contains("height_ceiling"),
		"Lake basin BFS must not use fixed center_height + fill_depth as the water boundary."
	)
	_assert(
		not source.contains("fill_depth"),
		"Lake basin shape must not carry a fixed fill_depth cutoff."
	)

func _assert_water_seam_refresh_contract() -> void:
	var chunk_view_source: String = FileAccess.get_file_as_string("res://core/systems/world/chunk_view.gd")
	var streamer_source: String = FileAccess.get_file_as_string("res://core/systems/world/world_streamer.gd")
	_assert(
		chunk_view_source.contains("func set_water_neighbour_resolver"),
		"ChunkView must accept a bounded neighbour-water resolver for cross-chunk water autotile checks."
	)
	_assert(
		chunk_view_source.contains("func refresh_water_edge_towards"),
		"ChunkView must expose edge-only water seam refresh."
	)
	_assert(
		chunk_view_source.contains("_water_neighbour_resolver.call"),
		"ChunkView out-of-chunk water neighbour checks must use the resolver."
	)
	_assert(
		streamer_source.contains("func _handle_water_chunk_published"),
		"WorldStreamer must refresh water seams after chunk publish."
	)
	_assert(
		streamer_source.contains("refresh_water_edge_towards"),
		"WorldStreamer water seam refresh must re-evaluate edge tiles only."
	)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
