class_name WorldPrePass
extends RefCounted

class LakeRecord extends RefCounted:
	var id: int = 0
	var grid_cells: PackedInt32Array = PackedInt32Array()
	var spill_point: Vector2i = Vector2i.ZERO
	var surface_height: float = 0.0
	var max_depth: float = 0.0
	var area_grid_cells: int = 0
	var lake_type: StringName = &"tectonic"
	var inflow_accumulation: float = 0.0

class SpineSeed extends RefCounted:
	var position: Vector2i = Vector2i.ZERO
	var strength: float = 0.5
	var direction_bias: Vector2 = Vector2.ZERO

class RidgePath extends RefCounted:
	var points: Array[Vector2i] = []
	var spline_samples: Array[Vector2] = []
	var spline_half_widths: PackedFloat32Array = PackedFloat32Array()
	var source_seed_position: Vector2i = Vector2i.ZERO
	var strength: float = 0.5
	var is_branch: bool = false
	var branch_origin: Vector2i = Vector2i.ZERO

const HEIGHT_CHANNEL: StringName = &"height"
const DRAINAGE_CHANNEL: StringName = &"drainage"
const RIVER_WIDTH_CHANNEL: StringName = &"river_width"
const RIVER_DISTANCE_CHANNEL: StringName = &"river_distance"
const FLOODPLAIN_STRENGTH_CHANNEL: StringName = &"floodplain_strength"
const RIDGE_STRENGTH_CHANNEL: StringName = &"ridge_strength"
const MOUNTAIN_MASS_CHANNEL: StringName = &"mountain_mass"
const SLOPE_CHANNEL: StringName = &"slope"
const RAIN_SHADOW_CHANNEL: StringName = &"rain_shadow"
const CONTINENTALNESS_CHANNEL: StringName = &"continentalness"
const NATIVE_CHUNK_GENERATOR_SNAPSHOT_KIND: StringName = &"world_pre_pass_chunk_generator_v2"
const NATIVE_PREPASS_KERNELS_CLASS: StringName = &"WorldPrePassKernels"
const WorldNoiseUtilsScript = preload("res://core/systems/world/world_noise_utils.gd")
const FLOAT_EPSILON: float = 0.00001
const MAX_LAKE_MASK_ID: int = 255
const FLOW_DIRECTION_NONE: int = 255
const DIAGONAL_DIRECTION_DISTANCE: float = 1.41421356237
const LAKE_TYPE_MOUNTAIN: StringName = &"mountain"
const LAKE_TYPE_GLACIAL: StringName = &"glacial"
const LAKE_TYPE_FLOODPLAIN: StringName = &"floodplain"
const LAKE_TYPE_TECTONIC: StringName = &"tectonic"
const SPINE_STRENGTH_MIN: float = 0.5
const SPINE_STRENGTH_MAX: float = 1.0
const SPINE_SELECTION_JITTER_WEIGHT: float = 0.12
const RIDGE_HEIGHT_WEIGHT: float = 0.45
const RIDGE_RUGGEDNESS_WEIGHT: float = 0.30
const RIDGE_INERTIA_WEIGHT: float = 0.18
const RIDGE_NOISE_WEIGHT: float = 0.12
const RIDGE_MERGE_BONUS: float = 0.08
const RIDGE_SPLINE_CONTROL_STEP: int = 4
const RIDGE_SPLINE_SAMPLES_PER_SEGMENT: int = 4
const RIDGE_MAIN_PEAK_HALF_WIDTH_MIN: float = 2.0
const RIDGE_MAIN_PEAK_HALF_WIDTH_MAX: float = 4.0
const RIDGE_END_HALF_WIDTH_RATIO: float = 0.40
const RIDGE_BRANCH_HALF_WIDTH_SCALE: float = 0.72
const MOUNTAIN_MASS_HEIGHT_MIN: float = 0.25
const MOUNTAIN_MASS_HEIGHT_RANGE: float = 0.35
const MOUNTAIN_MASS_RUGGEDNESS_RANGE: float = 0.6
const THERMAL_SMOOTHING_RIDGE_THRESHOLD: float = 0.3
const GRID_NEIGHBOR_OFFSETS_8: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]
const GRID_NEIGHBOR_DISTANCES_8: Array[float] = [
	DIAGONAL_DIRECTION_DISTANCE,
	1.0,
	DIAGONAL_DIRECTION_DISTANCE,
	1.0,
	1.0,
	DIAGONAL_DIRECTION_DISTANCE,
	1.0,
	DIAGONAL_DIRECTION_DISTANCE,
]

var _balance: WorldGenBalance = null
var _planet_sampler: PlanetSampler = null
var _grid_step: int = 32
var _wrap_width_tiles: int = WorldNoiseUtilsScript.DEFAULT_WRAP_WIDTH_TILES
var _prepass_min_y: int = 0
var _prepass_max_y: int = 0
var _grid_width: int = 1
var _grid_height: int = 1
var _grid_span_x: float = 1.0
var _grid_span_y: float = 1.0
var _neighbor_index_cache: PackedInt32Array = PackedInt32Array()
var _neighbor_distance_cache: PackedFloat32Array = PackedFloat32Array()
var _grid_world_x_cache: PackedInt32Array = PackedInt32Array()
var _grid_world_y_cache: PackedInt32Array = PackedInt32Array()
var _grid_world_center_cache: PackedVector2Array = PackedVector2Array()
var _height_grid: PackedFloat32Array = PackedFloat32Array()
var _filled_height_grid: PackedFloat32Array = PackedFloat32Array()
var _flow_dir_grid: PackedByteArray = PackedByteArray()
var _accumulation_grid: PackedFloat32Array = PackedFloat32Array()
var _drainage_grid: PackedFloat32Array = PackedFloat32Array()
var _river_mask_grid: PackedByteArray = PackedByteArray()
var _river_width_grid: PackedFloat32Array = PackedFloat32Array()
var _river_distance_grid: PackedFloat32Array = PackedFloat32Array()
var _floodplain_strength_grid: PackedFloat32Array = PackedFloat32Array()
var _ridge_strength_grid: PackedFloat32Array = PackedFloat32Array()
var _mountain_mass_grid: PackedFloat32Array = PackedFloat32Array()
var _eroded_height_grid: PackedFloat32Array = PackedFloat32Array()
var _slope_grid: PackedFloat32Array = PackedFloat32Array()
var _rain_shadow_grid: PackedFloat32Array = PackedFloat32Array()
var _continentalness_grid: PackedFloat32Array = PackedFloat32Array()
var _lake_mask: PackedByteArray = PackedByteArray()
var _lake_records: Array[LakeRecord] = []
var _spine_seeds: Array[SpineSeed] = []
var _ridge_paths: Array[RidgePath] = []
var _native_prepass_kernels: RefCounted = null
var _numeric_heap_last_priority: float = 0.0

func configure(balance_resource: WorldGenBalance, planet_sampler: PlanetSampler) -> WorldPrePass:
	_balance = balance_resource
	_planet_sampler = planet_sampler
	_grid_step = _resolve_grid_step()
	_wrap_width_tiles = _resolve_wrap_width_tiles()
	_prepass_min_y = _resolve_prepass_min_y()
	_prepass_max_y = _resolve_prepass_max_y()
	var y_span_tiles: int = _resolve_y_span_tiles()
	_grid_width = maxi(1, int(ceili(float(_wrap_width_tiles) / float(_grid_step))))
	_grid_height = maxi(1, int(ceili(float(y_span_tiles) / float(_grid_step))))
	_grid_span_x = float(_wrap_width_tiles) / float(_grid_width)
	_grid_span_y = float(y_span_tiles) / float(_grid_height)
	_setup_native_prepass_kernels()
	_neighbor_distance_cache = PackedFloat32Array()
	_numeric_heap_last_priority = 0.0
	_rebuild_cell_caches()
	_height_grid = PackedFloat32Array()
	_filled_height_grid = PackedFloat32Array()
	_flow_dir_grid = PackedByteArray()
	_accumulation_grid = PackedFloat32Array()
	_drainage_grid = PackedFloat32Array()
	_river_mask_grid = PackedByteArray()
	_river_width_grid = PackedFloat32Array()
	_river_distance_grid = PackedFloat32Array()
	_floodplain_strength_grid = PackedFloat32Array()
	_ridge_strength_grid = PackedFloat32Array()
	_mountain_mass_grid = PackedFloat32Array()
	_eroded_height_grid = PackedFloat32Array()
	_slope_grid = PackedFloat32Array()
	_rain_shadow_grid = PackedFloat32Array()
	_continentalness_grid = PackedFloat32Array()
	_lake_mask = PackedByteArray()
	_lake_records.clear()
	_spine_seeds.clear()
	_ridge_paths.clear()
	return self

func _setup_native_prepass_kernels() -> void:
	_native_prepass_kernels = null
	if not ClassDB.class_exists(NATIVE_PREPASS_KERNELS_CLASS):
		return
	_native_prepass_kernels = ClassDB.instantiate(NATIVE_PREPASS_KERNELS_CLASS) as RefCounted

func _compute_native_wrapped_distance_field(
	source_indices: PackedInt32Array,
	max_distance: float
) -> PackedFloat32Array:
	if _native_prepass_kernels == null or not _native_prepass_kernels.has_method("compute_wrapped_distance_field"):
		return PackedFloat32Array()
	var result: PackedFloat32Array = _native_prepass_kernels.compute_wrapped_distance_field(
		_grid_width,
		_grid_height,
		source_indices,
		_build_neighbor_distance_cache(),
		max_distance
	)
	if result.size() != _grid_width * _grid_height:
		return PackedFloat32Array()
	return result

func _compute_native_priority_flood_fill() -> PackedFloat32Array:
	if _native_prepass_kernels == null or not _native_prepass_kernels.has_method("compute_priority_flood"):
		return PackedFloat32Array()
	var result: PackedFloat32Array = _native_prepass_kernels.compute_priority_flood(
		_grid_width,
		_grid_height,
		_height_grid
	)
	if result.size() != _grid_width * _grid_height:
		return PackedFloat32Array()
	return result

func _compute_native_ridge_strength_grid() -> PackedFloat32Array:
	if _native_prepass_kernels == null or not _native_prepass_kernels.has_method("compute_ridge_strength_grid"):
		return PackedFloat32Array()
	var path_offsets := PackedInt32Array()
	var path_counts := PackedInt32Array()
	var spline_samples := PackedVector2Array()
	var spline_half_widths := PackedFloat32Array()
	var sample_offset: int = 0
	for ridge_path: RidgePath in _ridge_paths:
		if ridge_path == null or ridge_path.spline_samples.is_empty():
			continue
		var sample_count: int = ridge_path.spline_samples.size()
		if ridge_path.spline_half_widths.size() != sample_count:
			continue
		path_offsets.append(sample_offset)
		path_counts.append(sample_count)
		for sample: Vector2 in ridge_path.spline_samples:
			spline_samples.append(sample)
		for half_width: float in ridge_path.spline_half_widths:
			spline_half_widths.append(half_width)
		sample_offset += sample_count
	if path_counts.is_empty():
		return PackedFloat32Array()
	var result: PackedFloat32Array = _native_prepass_kernels.compute_ridge_strength_grid(
		_grid_width,
		_grid_height,
		path_offsets,
		path_counts,
		spline_samples,
		spline_half_widths
	)
	if result.size() != _height_grid.size():
		return PackedFloat32Array()
	return result

func _compute_native_river_extraction(
	river_threshold: float,
	neighbor_distances: PackedFloat32Array,
	max_distance: float
) -> Dictionary:
	if _native_prepass_kernels == null or not _native_prepass_kernels.has_method("compute_river_extraction"):
		return {}
	var result: Dictionary = _native_prepass_kernels.compute_river_extraction(
		_grid_width,
		_grid_height,
		_accumulation_grid,
		_lake_mask,
		_flow_dir_grid,
		river_threshold,
		_resolve_river_base_width(),
		_resolve_river_width_scale(),
		neighbor_distances,
		max_distance
	)
	var expected_size: int = _accumulation_grid.size()
	var river_mask_grid: PackedByteArray = result.get("river_mask_grid", PackedByteArray())
	var river_width_grid: PackedFloat32Array = result.get("river_width_grid", PackedFloat32Array())
	var river_distance_grid: PackedFloat32Array = result.get("river_distance_grid", PackedFloat32Array())
	if (
		river_mask_grid.size() != expected_size
		or river_width_grid.size() != expected_size
		or river_distance_grid.size() != expected_size
	):
		return {}
	return {
		"river_mask_grid": river_mask_grid,
		"river_width_grid": river_width_grid,
		"river_distance_grid": river_distance_grid,
	}

func _rebuild_cell_caches() -> void:
	var cell_count: int = _grid_width * _grid_height
	_neighbor_index_cache = PackedInt32Array()
	_grid_world_x_cache = PackedInt32Array()
	_grid_world_y_cache = PackedInt32Array()
	_grid_world_center_cache = PackedVector2Array()
	if cell_count <= 0:
		return
	_neighbor_index_cache.resize(cell_count * GRID_NEIGHBOR_OFFSETS_8.size())
	_neighbor_index_cache.fill(-1)
	_grid_world_x_cache.resize(cell_count)
	_grid_world_y_cache.resize(cell_count)
	_grid_world_center_cache.resize(cell_count)
	for grid_y: int in range(_grid_height):
		var row_base: int = grid_y * _grid_width
		var north_row_base: int = (grid_y - 1) * _grid_width
		var south_row_base: int = (grid_y + 1) * _grid_width
		var world_y: int = _grid_to_world_y(grid_y)
		var world_center_y: float = float(world_y) + (_grid_span_y * 0.5)
		for grid_x: int in range(_grid_width):
			var cell_index: int = row_base + grid_x
			var west_x: int = grid_x - 1
			if west_x < 0:
				west_x += _grid_width
			var east_x: int = grid_x + 1
			if east_x >= _grid_width:
				east_x -= _grid_width
			var world_x: int = _grid_to_world_x(grid_x)
			_grid_world_x_cache[cell_index] = world_x
			_grid_world_y_cache[cell_index] = world_y
			_grid_world_center_cache[cell_index] = Vector2(
				float(world_x) + (_grid_span_x * 0.5),
				world_center_y
			)
			var cache_base: int = cell_index * GRID_NEIGHBOR_OFFSETS_8.size()
			if grid_y > 0:
				_neighbor_index_cache[cache_base + 0] = north_row_base + west_x
				_neighbor_index_cache[cache_base + 1] = north_row_base + grid_x
				_neighbor_index_cache[cache_base + 2] = north_row_base + east_x
			_neighbor_index_cache[cache_base + 3] = row_base + west_x
			_neighbor_index_cache[cache_base + 4] = row_base + east_x
			if grid_y + 1 < _grid_height:
				_neighbor_index_cache[cache_base + 5] = south_row_base + west_x
				_neighbor_index_cache[cache_base + 6] = south_row_base + grid_x
				_neighbor_index_cache[cache_base + 7] = south_row_base + east_x

func compute() -> WorldPrePass:
	var stage_started_usec: int = WorldPerfProbe.begin()
	_height_grid.resize(_grid_width * _grid_height)
	_filled_height_grid.resize(_grid_width * _grid_height)
	_flow_dir_grid.resize(_grid_width * _grid_height)
	_flow_dir_grid.fill(FLOW_DIRECTION_NONE)
	_accumulation_grid.resize(_grid_width * _grid_height)
	_accumulation_grid.fill(0.0)
	_drainage_grid.resize(_grid_width * _grid_height)
	_drainage_grid.fill(0.0)
	_river_mask_grid.resize(_grid_width * _grid_height)
	_river_mask_grid.fill(0)
	_river_width_grid.resize(_grid_width * _grid_height)
	_river_width_grid.fill(0.0)
	_river_distance_grid.resize(_grid_width * _grid_height)
	_river_distance_grid.fill(_resolve_max_river_distance_tiles())
	_floodplain_strength_grid.resize(_grid_width * _grid_height)
	_floodplain_strength_grid.fill(0.0)
	_ridge_strength_grid.resize(_grid_width * _grid_height)
	_ridge_strength_grid.fill(0.0)
	_mountain_mass_grid.resize(_grid_width * _grid_height)
	_mountain_mass_grid.fill(0.0)
	_eroded_height_grid.resize(_grid_width * _grid_height)
	_eroded_height_grid.fill(0.0)
	_slope_grid.resize(_grid_width * _grid_height)
	_slope_grid.fill(0.0)
	_rain_shadow_grid.resize(_grid_width * _grid_height)
	_rain_shadow_grid.fill(0.0)
	_continentalness_grid.resize(_grid_width * _grid_height)
	_continentalness_grid.fill(0.0)
	_lake_mask.resize(_grid_width * _grid_height)
	_lake_mask.fill(0)
	_lake_records.clear()
	_spine_seeds.clear()
	_ridge_paths.clear()
	WorldPerfProbe.end("WorldPrePass.compute.allocate_grids", stage_started_usec)
	if _planet_sampler == null:
		_height_grid.fill(0.0)
		_filled_height_grid.fill(0.0)
		_eroded_height_grid.fill(0.0)
		_slope_grid.fill(0.0)
		_rain_shadow_grid.fill(0.0)
		_continentalness_grid.fill(0.0)
		return self
	stage_started_usec = WorldPerfProbe.begin()
	for grid_y: int in range(_grid_height):
		var world_y: int = _grid_to_world_y(grid_y)
		for grid_x: int in range(_grid_width):
			var world_pos := Vector2i(_grid_to_world_x(grid_x), world_y)
			_height_grid[_flatten_index(grid_x, grid_y)] = _planet_sampler.sample_height(world_pos)
	WorldPerfProbe.end("WorldPrePass.compute.sample_height_grid", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_spine_seeds()
	WorldPerfProbe.end("WorldPrePass.compute.spine_seeds", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_ridge_graph()
	WorldPerfProbe.end("WorldPrePass.compute.ridge_graph", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_smooth_ridge_paths()
	WorldPerfProbe.end("WorldPrePass.compute.smooth_ridge_paths", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_ridge_strength_grid()
	WorldPerfProbe.end("WorldPrePass.compute.ridge_strength_grid", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_mountain_mass_grid()
	WorldPerfProbe.end("WorldPrePass.compute.mountain_mass_grid", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_lake_aware_fill()
	WorldPerfProbe.end("WorldPrePass.compute.lake_aware_fill", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_flow_directions()
	WorldPerfProbe.end("WorldPrePass.compute.flow_directions", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_flow_accumulation()
	WorldPerfProbe.end("WorldPrePass.compute.flow_accumulation", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_drainage_grid()
	WorldPerfProbe.end("WorldPrePass.compute.drainage_grid", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_river_extraction()
	WorldPerfProbe.end("WorldPrePass.compute.river_extraction", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_floodplain_strength()
	WorldPerfProbe.end("WorldPrePass.compute.floodplain_strength", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_erosion_proxy()
	WorldPerfProbe.end("WorldPrePass.compute.erosion_proxy", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_slope_grid()
	WorldPerfProbe.end("WorldPrePass.compute.slope_grid", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_rain_shadow()
	WorldPerfProbe.end("WorldPrePass.compute.rain_shadow", stage_started_usec)
	stage_started_usec = WorldPerfProbe.begin()
	_compute_continentalness()
	WorldPerfProbe.end("WorldPrePass.compute.continentalness", stage_started_usec)
	return self

func sample(channel: StringName, world_pos: Vector2i) -> float:
	match channel:
		HEIGHT_CHANNEL:
			if _height_grid.is_empty():
				return 0.0
			return _sample_grid(_height_grid, world_pos)
		DRAINAGE_CHANNEL:
			if _drainage_grid.is_empty():
				return 0.0
			return _sample_grid(_drainage_grid, world_pos)
		RIVER_WIDTH_CHANNEL:
			if _river_width_grid.is_empty():
				return 0.0
			return _sample_grid(_river_width_grid, world_pos)
		RIVER_DISTANCE_CHANNEL:
			if _river_distance_grid.is_empty():
				return 0.0
			return _sample_grid(_river_distance_grid, world_pos)
		FLOODPLAIN_STRENGTH_CHANNEL:
			if _floodplain_strength_grid.is_empty():
				return 0.0
			return _sample_grid(_floodplain_strength_grid, world_pos)
		RIDGE_STRENGTH_CHANNEL:
			if _ridge_strength_grid.is_empty():
				return 0.0
			return _sample_grid(_ridge_strength_grid, world_pos)
		MOUNTAIN_MASS_CHANNEL:
			if _mountain_mass_grid.is_empty():
				return 0.0
			return _sample_grid(_mountain_mass_grid, world_pos)
		SLOPE_CHANNEL:
			if _slope_grid.is_empty():
				return 0.0
			return _sample_grid(_slope_grid, world_pos)
		RAIN_SHADOW_CHANNEL:
			if _rain_shadow_grid.is_empty():
				return 0.0
			return _sample_grid(_rain_shadow_grid, world_pos)
		CONTINENTALNESS_CHANNEL:
			if _continentalness_grid.is_empty():
				return 0.0
			return _sample_grid(_continentalness_grid, world_pos)
		_:
			return 0.0

func get_grid_value(channel: StringName, grid_x: int, grid_y: int) -> float:
	if grid_x < 0 or grid_x >= _grid_width or grid_y < 0 or grid_y >= _grid_height:
		return 0.0
	match channel:
		HEIGHT_CHANNEL:
			if _height_grid.is_empty():
				return 0.0
			return _height_grid[_flatten_index(grid_x, grid_y)]
		DRAINAGE_CHANNEL:
			if _drainage_grid.is_empty():
				return 0.0
			return _drainage_grid[_flatten_index(grid_x, grid_y)]
		RIVER_WIDTH_CHANNEL:
			if _river_width_grid.is_empty():
				return 0.0
			return _river_width_grid[_flatten_index(grid_x, grid_y)]
		RIVER_DISTANCE_CHANNEL:
			if _river_distance_grid.is_empty():
				return 0.0
			return _river_distance_grid[_flatten_index(grid_x, grid_y)]
		FLOODPLAIN_STRENGTH_CHANNEL:
			if _floodplain_strength_grid.is_empty():
				return 0.0
			return _floodplain_strength_grid[_flatten_index(grid_x, grid_y)]
		RIDGE_STRENGTH_CHANNEL:
			if _ridge_strength_grid.is_empty():
				return 0.0
			return _ridge_strength_grid[_flatten_index(grid_x, grid_y)]
		MOUNTAIN_MASS_CHANNEL:
			if _mountain_mass_grid.is_empty():
				return 0.0
			return _mountain_mass_grid[_flatten_index(grid_x, grid_y)]
		SLOPE_CHANNEL:
			if _slope_grid.is_empty():
				return 0.0
			return _slope_grid[_flatten_index(grid_x, grid_y)]
		RAIN_SHADOW_CHANNEL:
			if _rain_shadow_grid.is_empty():
				return 0.0
			return _rain_shadow_grid[_flatten_index(grid_x, grid_y)]
		CONTINENTALNESS_CHANNEL:
			if _continentalness_grid.is_empty():
				return 0.0
			return _continentalness_grid[_flatten_index(grid_x, grid_y)]
		_:
			return 0.0

func build_native_chunk_generator_snapshot() -> Dictionary:
	var expected_size: int = _grid_width * _grid_height
	var required_grids: Dictionary = {
		"prepass_drainage_grid": _drainage_grid,
		"prepass_slope_grid": _slope_grid,
		"prepass_rain_shadow_grid": _rain_shadow_grid,
		"prepass_continentalness_grid": _continentalness_grid,
		"prepass_ridge_strength_grid": _ridge_strength_grid,
		"prepass_river_width_grid": _river_width_grid,
		"prepass_river_distance_grid": _river_distance_grid,
		"prepass_floodplain_strength_grid": _floodplain_strength_grid,
		"prepass_mountain_mass_grid": _mountain_mass_grid,
	}
	if expected_size <= 0 or _grid_span_x <= 0.0 or _grid_span_y <= 0.0:
		push_error("WorldPrePass.build_native_chunk_generator_snapshot() requires a computed grid layout")
		assert(false, "WorldPrePass native chunk snapshot requires a computed grid layout")
		return {}
	for key: String in required_grids.keys():
		var grid: PackedFloat32Array = required_grids[key] as PackedFloat32Array
		if grid.size() != expected_size:
			push_error("WorldPrePass native chunk snapshot missing authoritative grid `%s` (%d != %d)" % [key, grid.size(), expected_size])
			assert(false, "WorldPrePass native chunk snapshot requires every authoritative structure grid")
			return {}
	return {
		"prepass_snapshot_kind": NATIVE_CHUNK_GENERATOR_SNAPSHOT_KIND,
		"prepass_grid_width": _grid_width,
		"prepass_grid_height": _grid_height,
		"prepass_min_y": _prepass_min_y,
		"prepass_max_y": _prepass_max_y,
		"prepass_grid_span_x": _grid_span_x,
		"prepass_grid_span_y": _grid_span_y,
		"prepass_drainage_grid": _drainage_grid.duplicate(),
		"prepass_slope_grid": _slope_grid.duplicate(),
		"prepass_rain_shadow_grid": _rain_shadow_grid.duplicate(),
		"prepass_continentalness_grid": _continentalness_grid.duplicate(),
		"prepass_ridge_strength_grid": _ridge_strength_grid.duplicate(),
		"prepass_river_width_grid": _river_width_grid.duplicate(),
		"prepass_river_distance_grid": _river_distance_grid.duplicate(),
		"prepass_floodplain_strength_grid": _floodplain_strength_grid.duplicate(),
		"prepass_mountain_mass_grid": _mountain_mass_grid.duplicate(),
	}

func _sample_grid(grid: PackedFloat32Array, world_pos: Vector2i) -> float:
	var wrapped_x: int = _wrap_x(world_pos.x)
	var x0: int = 0
	var x1: int = 0
	var tx: float = 0.0
	if _grid_width > 1:
		var x_coord: float = float(wrapped_x) / _grid_span_x
		var x_floor: int = floori(x_coord)
		x0 = int(posmod(x_floor, _grid_width))
		x1 = int(posmod(x0 + 1, _grid_width))
		tx = x_coord - float(x_floor)

	var y0: int = 0
	var y1: int = 0
	var ty: float = 0.0
	if _grid_height > 1:
		if world_pos.y <= _prepass_min_y:
			y0 = 0
			y1 = 0
		elif world_pos.y >= _prepass_max_y:
			y0 = _grid_height - 1
			y1 = y0
		else:
			var y_coord: float = float(world_pos.y - _prepass_min_y) / _grid_span_y
			var y_floor: int = floori(y_coord)
			y0 = clampi(y_floor, 0, _grid_height - 1)
			if y0 >= _grid_height - 1:
				y1 = y0
			else:
				y1 = y0 + 1
				ty = y_coord - float(y_floor)

	var v00: float = grid[_flatten_index(x0, y0)]
	if x0 == x1 and y0 == y1:
		return v00
	var v10: float = grid[_flatten_index(x1, y0)]
	var v01: float = grid[_flatten_index(x0, y1)]
	var v11: float = grid[_flatten_index(x1, y1)]
	var top: float = lerpf(v00, v10, tx)
	var bottom: float = lerpf(v01, v11, tx)
	return lerpf(top, bottom, ty)

func _flatten_index(grid_x: int, grid_y: int) -> int:
	return grid_y * _grid_width + grid_x

func _index_to_grid(index: int) -> Vector2i:
	if _grid_width <= 0:
		return Vector2i.ZERO
	return Vector2i(int(posmod(index, _grid_width)), int(index / _grid_width))

func _grid_to_world_x(grid_x: int) -> int:
	if _grid_width <= 0:
		return 0
	return _wrap_x(int(floor(float(grid_x) * float(_wrap_width_tiles) / float(_grid_width))))

func _grid_to_world_y(grid_y: int) -> int:
	if _grid_height <= 0:
		return _prepass_min_y
	var y_span_tiles: int = _resolve_y_span_tiles()
	return _prepass_min_y + int(floor(float(grid_y) * float(y_span_tiles) / float(_grid_height)))

func _resolve_grid_step() -> int:
	if _balance == null:
		return 32
	return maxi(1, _balance.prepass_grid_step)

func _resolve_wrap_width_tiles() -> int:
	if _planet_sampler:
		return maxi(1, _planet_sampler.get_wrap_width_tiles())
	return WorldNoiseUtilsScript.resolve_wrap_width_tiles(_balance)

func _resolve_prepass_min_y() -> int:
	var equator_y: int = 0
	if _balance:
		equator_y = _balance.equator_tile_y
	return equator_y - _resolve_latitude_half_span_tiles()

func _resolve_prepass_max_y() -> int:
	var equator_y: int = 0
	if _balance:
		equator_y = _balance.equator_tile_y
	return equator_y + _resolve_latitude_half_span_tiles()

func _resolve_latitude_half_span_tiles() -> int:
	if _balance == null:
		return 4096
	return maxi(256, _balance.latitude_half_span_tiles)

func _resolve_y_span_tiles() -> int:
	return maxi(1, _prepass_max_y - _prepass_min_y)

func _wrap_x(world_x: int) -> int:
	return WorldNoiseUtilsScript.wrap_x(world_x, _wrap_width_tiles)

func _compute_lake_aware_fill() -> void:
	if _height_grid.is_empty():
		return
	var native_filled_height := PackedFloat32Array()
	var phase_started_usec: int = WorldPerfProbe.begin()
	if _native_prepass_kernels != null:
		native_filled_height = _compute_native_priority_flood_fill()
	if not native_filled_height.is_empty():
		_filled_height_grid = native_filled_height
		WorldPerfProbe.end("WorldPrePass.compute.lake_aware_fill.priority_flood", phase_started_usec)
	else:
		WorldPerfProbe.end("WorldPrePass.compute.lake_aware_fill.priority_flood", phase_started_usec)
		phase_started_usec = WorldPerfProbe.begin()
		_filled_height_grid = _height_grid.duplicate()
		WorldPerfProbe.end("WorldPrePass.compute.lake_aware_fill.duplicate_height_grid", phase_started_usec)
	if not native_filled_height.is_empty():
		phase_started_usec = WorldPerfProbe.begin()
		_extract_lake_records()
		WorldPerfProbe.end("WorldPrePass.compute.lake_aware_fill.extract_lake_records", phase_started_usec)
		return
	var visited := PackedByteArray()
	visited.resize(_height_grid.size())
	visited.fill(0)
	var heap_indices: Array[int] = []
	var heap_priorities: Array[float] = []
	phase_started_usec = WorldPerfProbe.begin()
	_seed_priority_flood_boundaries(visited, heap_indices, heap_priorities)
	WorldPerfProbe.end("WorldPrePass.compute.lake_aware_fill.seed_boundaries", phase_started_usec)
	phase_started_usec = WorldPerfProbe.begin()
	while not heap_indices.is_empty():
		var current_index: int = _numeric_heap_pop(heap_indices, heap_priorities)
		var current_level: float = 0.0
		if current_index < 0:
			continue
		current_level = _filled_height_grid[current_index]
		for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
			var neighbor_index: int = _get_neighbor_index(current_index, direction_index)
			if neighbor_index < 0:
				continue
			if visited[neighbor_index] != 0:
				continue
			visited[neighbor_index] = 1
			var raw_height: float = _height_grid[neighbor_index]
			var filled_height: float = maxf(raw_height, current_level)
			_filled_height_grid[neighbor_index] = filled_height
			_numeric_heap_push(heap_indices, heap_priorities, neighbor_index, filled_height)
	WorldPerfProbe.end("WorldPrePass.compute.lake_aware_fill.priority_flood", phase_started_usec)
	phase_started_usec = WorldPerfProbe.begin()
	_extract_lake_records()
	WorldPerfProbe.end("WorldPrePass.compute.lake_aware_fill.extract_lake_records", phase_started_usec)

func _compute_flow_directions() -> void:
	if _filled_height_grid.is_empty():
		return
	_flow_dir_grid.resize(_filled_height_grid.size())
	_flow_dir_grid.fill(FLOW_DIRECTION_NONE)
	var unresolved_plateau_cells := PackedByteArray()
	unresolved_plateau_cells.resize(_filled_height_grid.size())
	unresolved_plateau_cells.fill(0)
	for cell_index: int in range(_filled_height_grid.size()):
		if _is_y_edge_cell(cell_index):
			continue
		var direct_direction: int = _find_direct_flow_direction(cell_index)
		if direct_direction >= 0:
			_flow_dir_grid[cell_index] = direct_direction
			continue
		unresolved_plateau_cells[cell_index] = 1
	for cell_index: int in range(_filled_height_grid.size()):
		if unresolved_plateau_cells[cell_index] != 1:
			continue
		_resolve_flat_plateau_flow(cell_index, unresolved_plateau_cells)

func _compute_flow_accumulation() -> void:
	if _flow_dir_grid.is_empty():
		return
	_accumulation_grid.resize(_flow_dir_grid.size())
	_accumulation_grid.fill(0.0)
	_reset_lake_inflow_accumulation()
	if _planet_sampler == null:
		return
	var temperature_grid: PackedFloat32Array = _build_temperature_grid()
	var indegree := PackedInt32Array()
	indegree.resize(_flow_dir_grid.size())
	indegree.fill(0)
	for cell_index: int in range(_flow_dir_grid.size()):
		_accumulation_grid[cell_index] = _resolve_base_accumulation(temperature_grid[cell_index])
		var target_index: int = _get_flow_target_index(cell_index)
		if target_index >= 0:
			indegree[target_index] += 1
	var queue: Array[int] = []
	for cell_index: int in range(indegree.size()):
		if indegree[cell_index] == 0:
			queue.append(cell_index)
	var queue_index: int = 0
	var processed_count: int = 0
	while queue_index < queue.size():
		var cell_index: int = queue[queue_index]
		queue_index += 1
		processed_count += 1
		var target_index: int = _get_flow_target_index(cell_index)
		if target_index >= 0:
			var transfer: float = _resolve_downstream_transfer(_accumulation_grid[cell_index], temperature_grid[cell_index])
			_accumulation_grid[target_index] += transfer
			_record_lake_inflow(cell_index, target_index, transfer)
			indegree[target_index] -= 1
			if indegree[target_index] == 0:
				queue.append(target_index)
	if processed_count != _flow_dir_grid.size():
		push_error(
			"WorldPrePass accumulation graph processed %d/%d cells; unresolved flow cycle detected"
			% [processed_count, _flow_dir_grid.size()]
		)

func _compute_drainage_grid() -> void:
	if _accumulation_grid.is_empty():
		return
	_drainage_grid.resize(_accumulation_grid.size())
	_drainage_grid.fill(0.0)
	var max_accumulation: float = 0.0
	for accumulation: float in _accumulation_grid:
		max_accumulation = maxf(max_accumulation, accumulation)
	if max_accumulation <= 1.0 + FLOAT_EPSILON:
		return
	var log2_divisor: float = log(2.0)
	var max_log_accumulation: float = log(max_accumulation) / log2_divisor
	if max_log_accumulation <= FLOAT_EPSILON:
		return
	for cell_index: int in range(_accumulation_grid.size()):
		var accumulation: float = maxf(1.0, _accumulation_grid[cell_index])
		var drainage: float = (log(accumulation) / log2_divisor) / max_log_accumulation
		_drainage_grid[cell_index] = clampf(drainage, 0.0, 1.0)

func _compute_river_extraction() -> void:
	if _accumulation_grid.is_empty():
		return
	var phase_started_usec: int = WorldPerfProbe.begin()
	_river_mask_grid.resize(_accumulation_grid.size())
	_river_mask_grid.fill(0)
	_river_width_grid.resize(_accumulation_grid.size())
	_river_width_grid.fill(0.0)
	_river_distance_grid.resize(_accumulation_grid.size())
	var max_distance: float = _resolve_max_river_distance_tiles()
	_river_distance_grid.fill(max_distance)
	var river_threshold: float = _resolve_river_accumulation_threshold()
	var neighbor_distances: PackedFloat32Array = _build_neighbor_distance_cache()
	var heap_indices: Array[int] = []
	var heap_priorities: Array[float] = []
	var source_indices := PackedInt32Array()
	WorldPerfProbe.end("WorldPrePass.compute.river_extraction.initialize_buffers", phase_started_usec)
	if _native_prepass_kernels != null and _native_prepass_kernels.has_method("compute_river_extraction"):
		phase_started_usec = WorldPerfProbe.begin()
		var native_river_data: Dictionary = _compute_native_river_extraction(
			river_threshold,
			neighbor_distances,
			max_distance
		)
		WorldPerfProbe.end("WorldPrePass.compute.river_extraction.native_total", phase_started_usec)
		if not native_river_data.is_empty():
			_river_mask_grid = native_river_data["river_mask_grid"]
			_river_width_grid = native_river_data["river_width_grid"]
			_river_distance_grid = native_river_data["river_distance_grid"]
			return
	phase_started_usec = WorldPerfProbe.begin()
	for cell_index: int in range(_accumulation_grid.size()):
		if not _is_river_cell(cell_index, river_threshold):
			continue
		_river_mask_grid[cell_index] = 1
		_river_width_grid[cell_index] = _resolve_river_width_tiles(_accumulation_grid[cell_index], river_threshold)
		_river_distance_grid[cell_index] = 0.0
		source_indices.append(cell_index)
		_numeric_heap_push(heap_indices, heap_priorities, cell_index, 0.0)
	WorldPerfProbe.end("WorldPrePass.compute.river_extraction.seed_river_sources", phase_started_usec)
	var native_river_distance := PackedFloat32Array()
	phase_started_usec = WorldPerfProbe.begin()
	if _native_prepass_kernels != null:
		native_river_distance = _compute_native_wrapped_distance_field(source_indices, max_distance)
	if not native_river_distance.is_empty():
		_river_distance_grid = native_river_distance
		WorldPerfProbe.end("WorldPrePass.compute.river_extraction.distance_propagation", phase_started_usec)
		return
	phase_started_usec = WorldPerfProbe.begin()
	while not heap_indices.is_empty():
		var cell_index: int = _numeric_heap_pop(heap_indices, heap_priorities)
		if cell_index < 0:
			continue
		var current_distance: float = _river_distance_grid[cell_index]
		if _numeric_heap_last_priority > current_distance + FLOAT_EPSILON:
			continue
		for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
			var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
			if neighbor_index < 0:
				continue
			var next_distance: float = current_distance + neighbor_distances[direction_index]
			if next_distance + FLOAT_EPSILON >= _river_distance_grid[neighbor_index]:
				continue
			_river_distance_grid[neighbor_index] = next_distance
			_numeric_heap_push(heap_indices, heap_priorities, neighbor_index, next_distance)
	WorldPerfProbe.end("WorldPrePass.compute.river_extraction.distance_propagation", phase_started_usec)

func _compute_floodplain_strength() -> void:
	_floodplain_strength_grid.resize(_river_mask_grid.size())
	_floodplain_strength_grid.fill(0.0)
	if _river_mask_grid.is_empty():
		return
	var heap: Array[Dictionary] = []
	for cell_index: int in range(_river_mask_grid.size()):
		if _river_mask_grid[cell_index] != 1:
			continue
		var floodplain_width: float = _resolve_floodplain_width_tiles(_river_width_grid[cell_index])
		if floodplain_width <= FLOAT_EPSILON:
			continue
		_floodplain_strength_grid[cell_index] = 1.0
		_heap_push(heap, cell_index, 0.0, {
			"source_width": floodplain_width,
		})
	while not heap.is_empty():
		var current: Dictionary = _heap_pop(heap)
		var cell_index: int = int(current.get("index", -1))
		var current_distance: float = float(current.get("priority", 0.0))
		var source_width: float = float(current.get("source_width", 0.0))
		if cell_index < 0 or source_width <= FLOAT_EPSILON:
			continue
		var current_strength: float = _resolve_floodplain_strength(current_distance, source_width)
		if current_strength + FLOAT_EPSILON < _floodplain_strength_grid[cell_index]:
			continue
		for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
			var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
			if neighbor_index < 0:
				continue
			if int(_lake_mask[neighbor_index]) > 0:
				continue
			var next_distance: float = current_distance + _resolve_neighbor_distance_tiles(direction_index)
			var next_strength: float = _resolve_floodplain_strength(next_distance, source_width)
			if next_strength <= FLOAT_EPSILON:
				continue
			if next_strength + FLOAT_EPSILON <= _floodplain_strength_grid[neighbor_index]:
				continue
			_floodplain_strength_grid[neighbor_index] = next_strength
			_heap_push(heap, neighbor_index, next_distance, {
				"source_width": source_width,
			})

func _compute_erosion_proxy() -> void:
	_eroded_height_grid.resize(_filled_height_grid.size())
	_eroded_height_grid.fill(0.0)
	if _filled_height_grid.is_empty():
		return
	_eroded_height_grid = _filled_height_grid.duplicate()
	_apply_valley_carving()
	_apply_thermal_smoothing()
	_apply_floodplain_deposition()

func _compute_slope_grid() -> void:
	_slope_grid.resize(_eroded_height_grid.size())
	_slope_grid.fill(0.0)
	if _eroded_height_grid.is_empty():
		return
	var max_possible_gradient: float = _resolve_max_possible_neighbor_gradient()
	if max_possible_gradient <= FLOAT_EPSILON:
		return
	for cell_index: int in range(_eroded_height_grid.size()):
		var raw_gradient: float = _compute_max_neighbor_gradient(_eroded_height_grid, cell_index)
		if raw_gradient <= FLOAT_EPSILON:
			continue
		_slope_grid[cell_index] = clampf(raw_gradient / max_possible_gradient, 0.0, 1.0)

func _compute_rain_shadow() -> void:
	_rain_shadow_grid.resize(_eroded_height_grid.size())
	_rain_shadow_grid.fill(0.0)
	if _eroded_height_grid.is_empty() or _planet_sampler == null:
		return
	var wind_direction: Vector2 = _resolve_prevailing_wind_direction()
	var moisture_grid: PackedFloat32Array = _build_moisture_grid()
	var column_entries: Array = _build_rain_shadow_columns(wind_direction)
	if column_entries.is_empty():
		return
	var max_possible_gradient: float = _resolve_max_possible_neighbor_gradient()
	var precipitation_rate: float = _resolve_precipitation_rate()
	var lift_factor: float = _resolve_orographic_lift_factor()
	var wrap_stabilization: bool = absf(wind_direction.y) <= FLOAT_EPSILON and _grid_width > 1
	for column_entry: Variant in column_entries:
		var column_cells: Array[int] = column_entry
		_apply_rain_shadow_column(
			column_cells,
			moisture_grid,
			wind_direction,
			wrap_stabilization,
			max_possible_gradient,
			precipitation_rate,
			lift_factor
		)

func _compute_continentalness() -> void:
	var phase_started_usec: int = WorldPerfProbe.begin()
	_continentalness_grid.resize(_eroded_height_grid.size())
	_continentalness_grid.fill(INF)
	if _eroded_height_grid.is_empty():
		return
	var sea_level_threshold: float = _resolve_sea_level_threshold()
	var neighbor_distances: PackedFloat32Array = _build_neighbor_distance_cache()
	var heap_indices: Array[int] = []
	var heap_priorities: Array[float] = []
	var source_indices := PackedInt32Array()
	WorldPerfProbe.end("WorldPrePass.compute.continentalness.initialize_buffers", phase_started_usec)
	phase_started_usec = WorldPerfProbe.begin()
	for cell_index: int in range(_eroded_height_grid.size()):
		if not _is_continentalness_water_source(cell_index, sea_level_threshold):
			continue
		_continentalness_grid[cell_index] = 0.0
		source_indices.append(cell_index)
		_numeric_heap_push(heap_indices, heap_priorities, cell_index, 0.0)
	WorldPerfProbe.end("WorldPrePass.compute.continentalness.seed_water_sources", phase_started_usec)
	if heap_indices.is_empty():
		_continentalness_grid.fill(0.0)
		return
	var native_continentalness := PackedFloat32Array()
	phase_started_usec = WorldPerfProbe.begin()
	if _native_prepass_kernels != null:
		native_continentalness = _compute_native_wrapped_distance_field(source_indices, INF)
	if not native_continentalness.is_empty():
		_continentalness_grid = native_continentalness
		WorldPerfProbe.end("WorldPrePass.compute.continentalness.distance_propagation", phase_started_usec)
	else:
		phase_started_usec = WorldPerfProbe.begin()
		while not heap_indices.is_empty():
			var cell_index: int = _numeric_heap_pop(heap_indices, heap_priorities)
			if cell_index < 0:
				continue
			var current_distance: float = _continentalness_grid[cell_index]
			if _numeric_heap_last_priority > current_distance + FLOAT_EPSILON:
				continue
			for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
				var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
				if neighbor_index < 0:
					continue
				var next_distance: float = current_distance + neighbor_distances[direction_index]
				if next_distance + FLOAT_EPSILON >= _continentalness_grid[neighbor_index]:
					continue
				_continentalness_grid[neighbor_index] = next_distance
				_numeric_heap_push(heap_indices, heap_priorities, neighbor_index, next_distance)
		WorldPerfProbe.end("WorldPrePass.compute.continentalness.distance_propagation", phase_started_usec)
	phase_started_usec = WorldPerfProbe.begin()
	var max_distance: float = 0.0
	for distance_to_water: float in _continentalness_grid:
		if is_inf(distance_to_water):
			continue
		max_distance = maxf(max_distance, distance_to_water)
	WorldPerfProbe.end("WorldPrePass.compute.continentalness.measure_max_distance", phase_started_usec)
	if max_distance <= FLOAT_EPSILON:
		_continentalness_grid.fill(0.0)
		return
	phase_started_usec = WorldPerfProbe.begin()
	for cell_index: int in range(_continentalness_grid.size()):
		var distance_to_water: float = _continentalness_grid[cell_index]
		if is_inf(distance_to_water):
			_continentalness_grid[cell_index] = 1.0
			continue
		_continentalness_grid[cell_index] = clampf(distance_to_water / max_distance, 0.0, 1.0)
	WorldPerfProbe.end("WorldPrePass.compute.continentalness.normalize_output", phase_started_usec)

func _apply_valley_carving() -> void:
	if _eroded_height_grid.is_empty() or _accumulation_grid.size() != _eroded_height_grid.size():
		return
	var valley_strength: float = _resolve_erosion_valley_strength()
	if valley_strength <= FLOAT_EPSILON:
		return
	for cell_index: int in range(_eroded_height_grid.size()):
		if int(_lake_mask[cell_index]) > 0:
			continue
		var local_slope: float = _compute_max_neighbor_gradient(_filled_height_grid, cell_index)
		if local_slope <= FLOAT_EPSILON:
			continue
		var valley_depth: float = valley_strength * sqrt(maxf(0.0, _accumulation_grid[cell_index])) * local_slope
		if valley_depth <= FLOAT_EPSILON:
			continue
		_eroded_height_grid[cell_index] = _clamp_prepass_height(_filled_height_grid[cell_index] - valley_depth)

func _apply_thermal_smoothing() -> void:
	if _eroded_height_grid.is_empty() or _ridge_strength_grid.size() != _eroded_height_grid.size():
		return
	var thermal_iterations: int = _resolve_thermal_iterations()
	var thermal_rate: float = _resolve_thermal_rate()
	if thermal_iterations <= 0 or thermal_rate <= FLOAT_EPSILON:
		return
	var current_grid: PackedFloat32Array = _eroded_height_grid
	for _iteration_index: int in range(thermal_iterations):
		var next_grid: PackedFloat32Array = current_grid.duplicate()
		for cell_index: int in range(current_grid.size()):
			var ridge_strength: float = _ridge_strength_grid[cell_index]
			if ridge_strength <= THERMAL_SMOOTHING_RIDGE_THRESHOLD:
				continue
			if int(_lake_mask[cell_index]) > 0:
				continue
			var average_neighbor_height_diff: float = _compute_average_neighbor_height_diff(current_grid, cell_index)
			if absf(average_neighbor_height_diff) <= FLOAT_EPSILON:
				continue
			var thermal_delta: float = average_neighbor_height_diff * thermal_rate * (1.0 - ridge_strength)
			next_grid[cell_index] = _clamp_prepass_height(current_grid[cell_index] + thermal_delta)
		current_grid = next_grid
	_eroded_height_grid = current_grid

func _apply_floodplain_deposition() -> void:
	if _eroded_height_grid.is_empty() or _river_mask_grid.size() != _eroded_height_grid.size():
		return
	var deposit_rate: float = _resolve_deposit_rate()
	if deposit_rate <= FLOAT_EPSILON:
		return
	var strongest_deposition := PackedFloat32Array()
	strongest_deposition.resize(_eroded_height_grid.size())
	strongest_deposition.fill(0.0)
	var river_height_targets := PackedFloat32Array()
	river_height_targets.resize(_eroded_height_grid.size())
	river_height_targets.fill(0.0)
	var heap: Array[Dictionary] = []
	for cell_index: int in range(_river_mask_grid.size()):
		if _river_mask_grid[cell_index] != 1:
			continue
		var floodplain_width: float = _resolve_floodplain_width_tiles(_river_width_grid[cell_index])
		if floodplain_width <= FLOAT_EPSILON:
			continue
		strongest_deposition[cell_index] = 1.0
		river_height_targets[cell_index] = _eroded_height_grid[cell_index]
		_heap_push(heap, cell_index, 0.0, {
			"source_width": floodplain_width,
			"source_height": _eroded_height_grid[cell_index],
		})
	while not heap.is_empty():
		var current: Dictionary = _heap_pop(heap)
		var cell_index: int = int(current.get("index", -1))
		var current_distance: float = float(current.get("priority", 0.0))
		var source_width: float = float(current.get("source_width", 0.0))
		var source_height: float = float(current.get("source_height", 0.0))
		if cell_index < 0 or source_width <= FLOAT_EPSILON:
			continue
		var current_strength: float = _resolve_floodplain_strength(current_distance, source_width)
		if current_strength + FLOAT_EPSILON < strongest_deposition[cell_index]:
			continue
		for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
			var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
			if neighbor_index < 0:
				continue
			if int(_lake_mask[neighbor_index]) > 0:
				continue
			var next_distance: float = current_distance + _resolve_neighbor_distance_tiles(direction_index)
			var next_strength: float = _resolve_floodplain_strength(next_distance, source_width)
			if next_strength <= FLOAT_EPSILON:
				continue
			if next_strength + FLOAT_EPSILON <= strongest_deposition[neighbor_index]:
				continue
			strongest_deposition[neighbor_index] = next_strength
			river_height_targets[neighbor_index] = source_height
			_heap_push(heap, neighbor_index, next_distance, {
				"source_width": source_width,
				"source_height": source_height,
			})
	for cell_index: int in range(_eroded_height_grid.size()):
		if int(_lake_mask[cell_index]) > 0:
			continue
		var deposition: float = clampf(deposit_rate * strongest_deposition[cell_index], 0.0, 1.0)
		if deposition <= FLOAT_EPSILON:
			continue
		_eroded_height_grid[cell_index] = _clamp_prepass_height(
			lerpf(_eroded_height_grid[cell_index], river_height_targets[cell_index], deposition)
		)

func _compute_ridge_strength_grid() -> void:
	_ridge_strength_grid.resize(_height_grid.size())
	_ridge_strength_grid.fill(0.0)
	if _ridge_paths.is_empty():
		return
	if _native_prepass_kernels != null and _native_prepass_kernels.has_method("compute_ridge_strength_grid"):
		var native_stage_started_usec: int = Time.get_ticks_usec()
		var native_ridge_strength_grid: PackedFloat32Array = _compute_native_ridge_strength_grid()
		var native_stage_elapsed_ms: float = float(Time.get_ticks_usec() - native_stage_started_usec) / 1000.0
		if native_stage_elapsed_ms < 2.0:
			print("[WorldPerf] WorldPrePass.compute.ridge_strength_grid.native_total: %.2f ms" % [native_stage_elapsed_ms])
		WorldPerfProbe.record("WorldPrePass.compute.ridge_strength_grid.native_total", native_stage_elapsed_ms)
		if not native_ridge_strength_grid.is_empty():
			_ridge_strength_grid = native_ridge_strength_grid
			return
	for ridge_path: RidgePath in _ridge_paths:
		_stamp_ridge_path_strength(ridge_path)

func _compute_mountain_mass_grid() -> void:
	_mountain_mass_grid.resize(_height_grid.size())
	_mountain_mass_grid.fill(0.0)
	if _height_grid.is_empty() or _ridge_strength_grid.is_empty():
		return
	for cell_index: int in range(_height_grid.size()):
		var ridge_strength: float = _ridge_strength_grid[cell_index]
		if ridge_strength <= FLOAT_EPSILON:
			continue
		var grid_pos: Vector2i = _index_to_grid(cell_index)
		var height_factor: float = clampf(
			(_height_grid[cell_index] - MOUNTAIN_MASS_HEIGHT_MIN) / MOUNTAIN_MASS_HEIGHT_RANGE,
			0.0,
			1.0
		)
		var ruggedness_factor: float = clampf(
			_sample_ruggedness_at_grid(grid_pos.x, grid_pos.y) / MOUNTAIN_MASS_RUGGEDNESS_RANGE,
			0.0,
			1.0
		)
		_mountain_mass_grid[cell_index] = clampf(ridge_strength * height_factor * ruggedness_factor, 0.0, 1.0)

func _sample_ridge_strength_at_grid(grid_pos: Vector2) -> float:
	var best_strength: float = 0.0
	for ridge_path: RidgePath in _ridge_paths:
		best_strength = maxf(best_strength, _sample_ridge_path_strength(ridge_path, grid_pos))
		if best_strength >= 1.0 - FLOAT_EPSILON:
			return 1.0
	return best_strength

func _stamp_ridge_path_strength(ridge_path: RidgePath) -> void:
	if ridge_path == null or ridge_path.spline_samples.is_empty():
		return
	if ridge_path.spline_half_widths.size() != ridge_path.spline_samples.size():
		return
	if ridge_path.spline_samples.size() == 1:
		_stamp_ridge_point_strength(
			ridge_path.spline_samples[0],
			ridge_path.spline_half_widths[0]
		)
		return
	for segment_index: int in range(ridge_path.spline_samples.size() - 1):
		_stamp_ridge_segment_strength(
			ridge_path.spline_samples[segment_index],
			ridge_path.spline_samples[segment_index + 1],
			ridge_path.spline_half_widths[segment_index],
			ridge_path.spline_half_widths[segment_index + 1]
		)

func _stamp_ridge_point_strength(point: Vector2, ridge_half_width: float) -> void:
	if ridge_half_width <= FLOAT_EPSILON or _grid_width <= 0 or _grid_height <= 0:
		return
	var point_x: float = point.x
	var point_y: float = point.y
	var half_width_sq: float = ridge_half_width * ridge_half_width
	var min_x: int = floori(point.x - ridge_half_width)
	var max_x: int = ceili(point.x + ridge_half_width)
	var min_y: int = maxi(0, floori(point.y - ridge_half_width))
	var max_y: int = mini(_grid_height - 1, ceili(point.y + ridge_half_width))
	for grid_y: int in range(min_y, max_y + 1):
		var row_base: int = grid_y * _grid_width
		var delta_y: float = float(grid_y) - point_y
		var delta_y_sq: float = delta_y * delta_y
		var wrapped_x: int = int(posmod(min_x, _grid_width))
		var query_x: float = float(min_x)
		for _x_offset: int in range(max_x - min_x + 1):
			var delta_x: float = query_x - point_x
			var distance_sq: float = delta_x * delta_x + delta_y_sq
			if distance_sq < half_width_sq:
				var strength: float = _resolve_ridge_strength(sqrt(distance_sq), ridge_half_width)
				var cell_index: int = row_base + wrapped_x
				if strength > _ridge_strength_grid[cell_index]:
					_ridge_strength_grid[cell_index] = strength
			query_x += 1.0
			wrapped_x += 1
			if wrapped_x >= _grid_width:
				wrapped_x = 0

func _stamp_ridge_segment_strength(
	segment_start: Vector2,
	segment_end: Vector2,
	start_half_width: float,
	end_half_width: float
) -> void:
	if _grid_width <= 0 or _grid_height <= 0:
		return
	var max_half_width: float = maxf(start_half_width, end_half_width)
	if max_half_width <= FLOAT_EPSILON:
		return
	var start_x: float = segment_start.x
	var start_y: float = segment_start.y
	var min_x: int = floori(minf(start_x, segment_end.x) - max_half_width)
	var max_x: int = ceili(maxf(start_x, segment_end.x) + max_half_width)
	var min_y: int = maxi(0, floori(minf(start_y, segment_end.y) - max_half_width))
	var max_y: int = mini(_grid_height - 1, ceili(maxf(start_y, segment_end.y) + max_half_width))
	var segment_delta: Vector2 = segment_end - segment_start
	var segment_delta_x: float = segment_delta.x
	var segment_delta_y: float = segment_delta.y
	var segment_length_sq: float = segment_delta_x * segment_delta_x + segment_delta_y * segment_delta_y
	var inverse_length_sq: float = 0.0
	if segment_length_sq > FLOAT_EPSILON:
		inverse_length_sq = 1.0 / segment_length_sq
	var width_delta: float = end_half_width - start_half_width
	for grid_y: int in range(min_y, max_y + 1):
		var row_base: int = grid_y * _grid_width
		var query_y: float = float(grid_y)
		var offset_y: float = query_y - start_y
		var wrapped_x: int = int(posmod(min_x, _grid_width))
		var query_x: float = float(min_x)
		for _x_offset: int in range(max_x - min_x + 1):
			var offset_x: float = query_x - start_x
			var t: float = 0.0
			if inverse_length_sq > 0.0:
				t = clampf((offset_x * segment_delta_x + offset_y * segment_delta_y) * inverse_length_sq, 0.0, 1.0)
			var ridge_half_width: float = start_half_width + width_delta * t
			if ridge_half_width > FLOAT_EPSILON:
				var nearest_x: float = start_x + segment_delta_x * t
				var nearest_y: float = start_y + segment_delta_y * t
				var delta_x: float = query_x - nearest_x
				var delta_y: float = query_y - nearest_y
				var distance_sq: float = delta_x * delta_x + delta_y * delta_y
				var half_width_sq: float = ridge_half_width * ridge_half_width
				if distance_sq < half_width_sq:
					var strength: float = _resolve_ridge_strength(sqrt(distance_sq), ridge_half_width)
					var cell_index: int = row_base + wrapped_x
					if strength > _ridge_strength_grid[cell_index]:
						_ridge_strength_grid[cell_index] = strength
			query_x += 1.0
			wrapped_x += 1
			if wrapped_x >= _grid_width:
				wrapped_x = 0

func _sample_ridge_path_strength(ridge_path: RidgePath, grid_pos: Vector2) -> float:
	if ridge_path == null or ridge_path.spline_samples.is_empty():
		return 0.0
	if ridge_path.spline_half_widths.size() != ridge_path.spline_samples.size():
		return 0.0
	if ridge_path.spline_samples.size() == 1:
		var single_point: Vector2 = ridge_path.spline_samples[0]
		var query_x: float = _unwrap_grid_x_near_reference(grid_pos.x, single_point.x)
		var single_query := Vector2(query_x, grid_pos.y)
		return _resolve_ridge_strength(
			single_query.distance_to(single_point),
			ridge_path.spline_half_widths[0]
		)
	var best_strength: float = 0.0
	for segment_index: int in range(ridge_path.spline_samples.size() - 1):
		var segment_start: Vector2 = ridge_path.spline_samples[segment_index]
		var segment_end: Vector2 = ridge_path.spline_samples[segment_index + 1]
		var segment_reference_x: float = 0.5 * (segment_start.x + segment_end.x)
		var query_x: float = _unwrap_grid_x_near_reference(grid_pos.x, segment_reference_x)
		var segment_query := Vector2(query_x, grid_pos.y)
		var segment_delta: Vector2 = segment_end - segment_start
		var segment_length_sq: float = segment_delta.length_squared()
		var t: float = 0.0
		if segment_length_sq > FLOAT_EPSILON:
			t = clampf((segment_query - segment_start).dot(segment_delta) / segment_length_sq, 0.0, 1.0)
		var nearest_point: Vector2 = segment_start.lerp(segment_end, t)
		var ridge_half_width: float = lerpf(
			ridge_path.spline_half_widths[segment_index],
			ridge_path.spline_half_widths[segment_index + 1],
			t
		)
		best_strength = maxf(
			best_strength,
			_resolve_ridge_strength(segment_query.distance_to(nearest_point), ridge_half_width)
		)
		if best_strength >= 1.0 - FLOAT_EPSILON:
			return 1.0
	return best_strength

func _compute_spine_seeds() -> void:
	_spine_seeds.clear()
	if _height_grid.is_empty() or _planet_sampler == null:
		return
	var target_seed_count: int = _resolve_target_spine_count()
	if target_seed_count <= 0:
		return
	var candidate_heap_indices: Array[int] = []
	var candidate_heap_priorities: Array[float] = []
	for cell_index: int in range(_height_grid.size()):
		var grid_pos: Vector2i = _index_to_grid(cell_index)
		var ruggedness: float = _sample_ruggedness_at_grid(grid_pos.x, grid_pos.y)
		var selection_score: float = _resolve_spine_selection_score(_height_grid[cell_index], ruggedness, grid_pos)
		_numeric_heap_push(candidate_heap_indices, candidate_heap_priorities, cell_index, -selection_score)
	var min_distance_grid: int = _resolve_min_spine_distance_grid()
	while not candidate_heap_indices.is_empty() and _spine_seeds.size() < target_seed_count:
		var cell_index: int = _numeric_heap_pop(candidate_heap_indices, candidate_heap_priorities)
		if cell_index < 0:
			continue
		var grid_pos: Vector2i = _index_to_grid(cell_index)
		if not _is_spine_seed_far_enough(grid_pos, min_distance_grid):
			continue
		var ruggedness: float = _sample_ruggedness_at_grid(grid_pos.x, grid_pos.y)
		var spine_seed := SpineSeed.new()
		spine_seed.position = grid_pos
		spine_seed.strength = _resolve_spine_strength(_height_grid[cell_index], ruggedness)
		spine_seed.direction_bias = _resolve_spine_direction_bias(grid_pos)
		_spine_seeds.append(spine_seed)

func _compute_ridge_graph() -> void:
	_ridge_paths.clear()
	if _spine_seeds.is_empty() or _height_grid.is_empty():
		return
	var occupied_cells: Dictionary = {}
	for seed_index: int in range(_spine_seeds.size()):
		var main_path: RidgePath = _build_main_ridge_path(seed_index, occupied_cells)
		if main_path == null or main_path.points.size() < 2:
			continue
		_ridge_paths.append(main_path)
		_register_ridge_path_cells(main_path, occupied_cells)
		_spawn_branch_ridges(main_path, occupied_cells)

func _build_main_ridge_path(seed_index: int, occupied_cells: Dictionary) -> RidgePath:
	if seed_index < 0 or seed_index >= _spine_seeds.size():
		return null
	var spine_seed: SpineSeed = _spine_seeds[seed_index]
	var seed_cell_index: int = _flatten_index(spine_seed.position.x, spine_seed.position.y)
	if occupied_cells.has(seed_cell_index):
		return null
	var local_cells: Dictionary = {
		seed_cell_index: true,
	}
	var forward_direction: int = _resolve_seed_ridge_direction(spine_seed, seed_index)
	var backward_direction: int = _rotate_direction_index(forward_direction, 4)
	var forward_points: Array[int] = []
	var backward_points: Array[int] = []
	var remaining_steps: int = _resolve_max_ridge_length_grid()
	var forward_state: Dictionary = {
		"active": true,
		"current_index": seed_cell_index,
		"previous_index": -1,
		"direction_index": forward_direction,
	}
	var backward_state: Dictionary = {
		"active": true,
		"current_index": seed_cell_index,
		"previous_index": -1,
		"direction_index": backward_direction,
	}
	while remaining_steps > 0 and (bool(forward_state.get("active", false)) or bool(backward_state.get("active", false))):
		if bool(forward_state.get("active", false)) and remaining_steps > 0:
			var forward_step: Dictionary = _advance_ridge_front(
				int(forward_state.get("current_index", -1)),
				int(forward_state.get("previous_index", -1)),
				int(forward_state.get("direction_index", forward_direction)),
				local_cells,
				occupied_cells,
				seed_index * 2 + 1
			)
			if forward_step.is_empty():
				forward_state["active"] = false
			else:
				var next_forward_index: int = int(forward_step.get("next_index", -1))
				forward_points.append(next_forward_index)
				local_cells[next_forward_index] = true
				forward_state["previous_index"] = int(forward_state.get("current_index", -1))
				forward_state["current_index"] = next_forward_index
				forward_state["direction_index"] = int(forward_step.get("direction_index", forward_direction))
				forward_state["active"] = not bool(forward_step.get("merged", false))
				remaining_steps -= 1
		if bool(backward_state.get("active", false)) and remaining_steps > 0:
			var backward_step: Dictionary = _advance_ridge_front(
				int(backward_state.get("current_index", -1)),
				int(backward_state.get("previous_index", -1)),
				int(backward_state.get("direction_index", backward_direction)),
				local_cells,
				occupied_cells,
				seed_index * 2 + 2
			)
			if backward_step.is_empty():
				backward_state["active"] = false
			else:
				var next_backward_index: int = int(backward_step.get("next_index", -1))
				backward_points.append(next_backward_index)
				local_cells[next_backward_index] = true
				backward_state["previous_index"] = int(backward_state.get("current_index", -1))
				backward_state["current_index"] = next_backward_index
				backward_state["direction_index"] = int(backward_step.get("direction_index", backward_direction))
				backward_state["active"] = not bool(backward_step.get("merged", false))
				remaining_steps -= 1
	var path_indices: Array[int] = []
	for reverse_index: int in range(backward_points.size() - 1, -1, -1):
		path_indices.append(backward_points[reverse_index])
	path_indices.append(seed_cell_index)
	for point_index: int in forward_points:
		path_indices.append(point_index)
	if path_indices.size() < 2:
		return null
	return _create_ridge_path(path_indices, spine_seed.position, spine_seed.strength, false, spine_seed.position)

func _spawn_branch_ridges(main_path: RidgePath, occupied_cells: Dictionary) -> void:
	if main_path == null or main_path.points.size() < 4:
		return
	var branch_probability: float = _resolve_branch_probability()
	if branch_probability <= FLOAT_EPSILON:
		return
	for point_index: int in range(1, main_path.points.size() - 1):
		var branch_origin: Vector2i = main_path.points[point_index]
		var branch_roll: float = _hash01_for_grid(branch_origin.x, branch_origin.y, 211 + point_index)
		if branch_roll > branch_probability:
			continue
		var branch_path: RidgePath = _build_branch_ridge_path(main_path, point_index, occupied_cells)
		if branch_path == null or branch_path.points.size() < 3:
			continue
		_ridge_paths.append(branch_path)
		_register_ridge_path_cells(branch_path, occupied_cells)

func _build_branch_ridge_path(main_path: RidgePath, branch_point_index: int, occupied_cells: Dictionary) -> RidgePath:
	if main_path == null or branch_point_index <= 0 or branch_point_index >= main_path.points.size() - 1:
		return null
	var branch_origin: Vector2i = main_path.points[branch_point_index]
	var origin_index: int = _flatten_index(branch_origin.x, branch_origin.y)
	var branch_direction: int = _resolve_branch_start_direction(main_path, branch_point_index)
	var branch_indices: Array[int] = [origin_index]
	var local_cells: Dictionary = {
		origin_index: true,
	}
	var current_index: int = origin_index
	var previous_index: int = -1
	var direction_index: int = branch_direction
	var remaining_steps: int = _resolve_max_branch_length_grid()
	while remaining_steps > 0:
		var branch_step: Dictionary = _advance_ridge_front(
			current_index,
			previous_index,
			direction_index,
			local_cells,
			occupied_cells,
			317 + branch_point_index
		)
		if branch_step.is_empty():
			break
		var next_index: int = int(branch_step.get("next_index", -1))
		branch_indices.append(next_index)
		local_cells[next_index] = true
		previous_index = current_index
		current_index = next_index
		direction_index = int(branch_step.get("direction_index", direction_index))
		remaining_steps -= 1
		if bool(branch_step.get("merged", false)):
			break
	if branch_indices.size() < 3:
		return null
	return _create_ridge_path(branch_indices, main_path.source_seed_position, main_path.strength, true, branch_origin)

func _advance_ridge_front(
	current_index: int,
	previous_index: int,
	direction_index: int,
	local_cells: Dictionary,
	occupied_cells: Dictionary,
	salt: int
) -> Dictionary:
	if current_index < 0 or direction_index < 0:
		return {}
	var best_step: Dictionary = {}
	var best_score: float = -INF
	for candidate_direction: int in _build_ridge_candidate_directions(direction_index):
		var neighbor_index: int = _get_neighbor_index(current_index, candidate_direction)
		if neighbor_index < 0 or neighbor_index == previous_index:
			continue
		if local_cells.has(neighbor_index):
			continue
		var occupied_by_existing_ridge: bool = occupied_cells.has(neighbor_index)
		var neighbor_height: float = _height_grid[neighbor_index]
		if neighbor_height + FLOAT_EPSILON < _resolve_ridge_min_height() and not occupied_by_existing_ridge:
			continue
		var candidate_score: float = _score_ridge_candidate(current_index, neighbor_index, direction_index, salt)
		if occupied_by_existing_ridge:
			candidate_score += RIDGE_MERGE_BONUS
		if candidate_score > best_score + FLOAT_EPSILON:
			best_score = candidate_score
			best_step = {
				"next_index": neighbor_index,
				"direction_index": candidate_direction,
				"merged": occupied_by_existing_ridge,
			}
			continue
		if absf(candidate_score - best_score) <= FLOAT_EPSILON and not best_step.is_empty():
			var best_index: int = int(best_step.get("next_index", neighbor_index))
			if _is_index_lexicographically_less(neighbor_index, best_index):
				best_step = {
					"next_index": neighbor_index,
					"direction_index": candidate_direction,
					"merged": occupied_by_existing_ridge,
				}
	return best_step

func _score_ridge_candidate(current_index: int, neighbor_index: int, previous_direction: int, salt: int) -> float:
	var neighbor_grid: Vector2i = _index_to_grid(neighbor_index)
	var height_score: float = clampf(_height_grid[neighbor_index], 0.0, 1.0)
	var ruggedness_score: float = _sample_ruggedness_at_grid(neighbor_grid.x, neighbor_grid.y)
	var continuation_score: float = 1.0
	var candidate_direction: int = _get_direction_between_indices(current_index, neighbor_index)
	if previous_direction >= 0 and candidate_direction >= 0:
		var previous_vector: Vector2 = _get_direction_vector(previous_direction)
		var candidate_vector: Vector2 = _get_direction_vector(candidate_direction)
		continuation_score = clampf((previous_vector.dot(candidate_vector) + 1.0) * 0.5, 0.0, 1.0)
	var noise_score: float = _hash01_for_grid(neighbor_grid.x, neighbor_grid.y, 101 + salt)
	return (
		height_score * RIDGE_HEIGHT_WEIGHT
		+ ruggedness_score * RIDGE_RUGGEDNESS_WEIGHT
		+ continuation_score * _resolve_ridge_continuation_inertia() * RIDGE_INERTIA_WEIGHT
		+ noise_score * RIDGE_NOISE_WEIGHT
	)

func _create_ridge_path(
	path_indices: Array[int],
	source_seed_position: Vector2i,
	strength: float,
	is_branch: bool,
	branch_origin: Vector2i
) -> RidgePath:
	var ridge_path := RidgePath.new()
	ridge_path.source_seed_position = source_seed_position
	ridge_path.strength = strength
	ridge_path.is_branch = is_branch
	ridge_path.branch_origin = branch_origin
	for cell_index: int in path_indices:
		ridge_path.points.append(_index_to_grid(cell_index))
	return ridge_path

func _register_ridge_path_cells(ridge_path: RidgePath, occupied_cells: Dictionary) -> void:
	if ridge_path == null:
		return
	for grid_pos: Vector2i in ridge_path.points:
		var cell_index: int = _flatten_index(grid_pos.x, grid_pos.y)
		if not occupied_cells.has(cell_index):
			occupied_cells[cell_index] = true

func _smooth_ridge_paths() -> void:
	for ridge_path: RidgePath in _ridge_paths:
		_smooth_ridge_path(ridge_path)

func _smooth_ridge_path(ridge_path: RidgePath) -> void:
	if ridge_path == null:
		return
	ridge_path.spline_samples.clear()
	ridge_path.spline_half_widths = PackedFloat32Array()
	var raw_points: Array[Vector2] = _unwrap_ridge_points(ridge_path.points)
	if raw_points.is_empty():
		return
	if raw_points.size() == 1:
		ridge_path.spline_samples.append(raw_points[0])
		ridge_path.spline_half_widths = PackedFloat32Array([_resolve_ridge_peak_half_width(ridge_path)])
		return
	var peak_index: int = _find_ridge_peak_point_index(ridge_path.points)
	var control_indices: Array[int] = _build_ridge_control_point_indices(raw_points.size(), peak_index)
	var control_points: Array[Vector2] = []
	for control_index: int in control_indices:
		control_points.append(raw_points[control_index])
	ridge_path.spline_samples = _sample_catmull_rom_points(control_points)
	if ridge_path.spline_samples.is_empty():
		for raw_point: Vector2 in raw_points:
			ridge_path.spline_samples.append(raw_point)
	ridge_path.spline_half_widths = _build_ridge_width_profile(
		ridge_path,
		raw_points,
		ridge_path.spline_samples,
		peak_index
	)

# Keep X in wrap-local continuous space so seam-crossing ridges smooth without jumps.
func _unwrap_ridge_points(grid_points: Array[Vector2i]) -> Array[Vector2]:
	var unwrapped_points: Array[Vector2] = []
	if grid_points.is_empty():
		return unwrapped_points
	var previous_point: Vector2i = grid_points[0]
	var current_x: float = float(previous_point.x)
	unwrapped_points.append(Vector2(current_x, float(previous_point.y)))
	for point_index: int in range(1, grid_points.size()):
		var grid_point: Vector2i = grid_points[point_index]
		current_x += float(_grid_wrap_delta_x(grid_point.x, previous_point.x))
		unwrapped_points.append(Vector2(current_x, float(grid_point.y)))
		previous_point = grid_point
	return unwrapped_points

func _build_ridge_control_point_indices(point_count: int, peak_index: int) -> Array[int]:
	var control_indices: Array[int] = [0]
	for point_index: int in range(RIDGE_SPLINE_CONTROL_STEP, point_count - 1, RIDGE_SPLINE_CONTROL_STEP):
		control_indices.append(point_index)
	if peak_index > 0 and peak_index < point_count - 1 and not control_indices.has(peak_index):
		control_indices.append(peak_index)
	var last_index: int = maxi(0, point_count - 1)
	if not control_indices.has(last_index):
		control_indices.append(last_index)
	control_indices.sort()
	return control_indices

func _sample_catmull_rom_points(control_points: Array[Vector2]) -> Array[Vector2]:
	var spline_points: Array[Vector2] = []
	if control_points.is_empty():
		return spline_points
	spline_points.append(control_points[0])
	if control_points.size() == 1:
		return spline_points
	for segment_index: int in range(control_points.size() - 1):
		var p0: Vector2 = control_points[maxi(0, segment_index - 1)]
		var p1: Vector2 = control_points[segment_index]
		var p2: Vector2 = control_points[segment_index + 1]
		var p3: Vector2 = control_points[mini(control_points.size() - 1, segment_index + 2)]
		for subdivision_index: int in range(1, RIDGE_SPLINE_SAMPLES_PER_SEGMENT + 1):
			var t: float = float(subdivision_index) / float(RIDGE_SPLINE_SAMPLES_PER_SEGMENT)
			var spline_point: Vector2 = _sample_catmull_rom_segment(p0, p1, p2, p3, t)
			spline_point.y = clampf(spline_point.y, 0.0, float(maxi(0, _grid_height - 1)))
			if spline_points.back().distance_squared_to(spline_point) <= FLOAT_EPSILON:
				continue
			spline_points.append(spline_point)
	return spline_points

func _sample_catmull_rom_segment(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _build_ridge_width_profile(
	ridge_path: RidgePath,
	raw_points: Array[Vector2],
	spline_points: Array[Vector2],
	peak_index: int
) -> PackedFloat32Array:
	var half_widths := PackedFloat32Array()
	half_widths.resize(spline_points.size())
	if spline_points.is_empty():
		return half_widths
	var raw_arc_lengths: PackedFloat32Array = _build_polyline_arc_lengths(raw_points)
	var spline_arc_lengths: PackedFloat32Array = _build_polyline_arc_lengths(spline_points)
	var peak_distance: float = 0.0
	if peak_index >= 0 and peak_index < raw_arc_lengths.size():
		peak_distance = raw_arc_lengths[peak_index]
	var peak_sample_index: int = _find_nearest_arc_length_index(spline_arc_lengths, peak_distance)
	var peak_sample_distance: float = 0.0
	if peak_sample_index >= 0 and peak_sample_index < spline_arc_lengths.size():
		peak_sample_distance = spline_arc_lengths[peak_sample_index]
	var total_length: float = 0.0
	if not spline_arc_lengths.is_empty():
		total_length = spline_arc_lengths[spline_arc_lengths.size() - 1]
	var peak_half_width: float = _resolve_ridge_peak_half_width(ridge_path)
	var end_half_width: float = maxf(0.55, peak_half_width * RIDGE_END_HALF_WIDTH_RATIO)
	for sample_index: int in range(spline_points.size()):
		var centrality: float = _resolve_ridge_profile_centrality(
			spline_arc_lengths[sample_index],
			peak_sample_distance,
			total_length
		)
		var eased_centrality: float = centrality * centrality * (3.0 - 2.0 * centrality)
		half_widths[sample_index] = lerpf(end_half_width, peak_half_width, eased_centrality)
	return half_widths

func _build_polyline_arc_lengths(points: Array[Vector2]) -> PackedFloat32Array:
	var arc_lengths := PackedFloat32Array()
	arc_lengths.resize(points.size())
	if points.is_empty():
		return arc_lengths
	arc_lengths[0] = 0.0
	var total_length: float = 0.0
	for point_index: int in range(1, points.size()):
		total_length += points[point_index - 1].distance_to(points[point_index])
		arc_lengths[point_index] = total_length
	return arc_lengths

func _find_nearest_arc_length_index(arc_lengths: PackedFloat32Array, target_distance: float) -> int:
	if arc_lengths.is_empty():
		return -1
	var best_index: int = 0
	var best_delta: float = absf(arc_lengths[0] - target_distance)
	for point_index: int in range(1, arc_lengths.size()):
		var candidate_delta: float = absf(arc_lengths[point_index] - target_distance)
		if candidate_delta < best_delta - FLOAT_EPSILON:
			best_delta = candidate_delta
			best_index = point_index
	return best_index

func _find_ridge_peak_point_index(grid_points: Array[Vector2i]) -> int:
	if grid_points.is_empty():
		return 0
	var best_index: int = 0
	var best_height: float = -INF
	var center_index: float = float(grid_points.size() - 1) * 0.5
	for point_index: int in range(grid_points.size()):
		var grid_point: Vector2i = grid_points[point_index]
		var point_height: float = _height_grid[_flatten_index(grid_point.x, grid_point.y)]
		if point_height > best_height + FLOAT_EPSILON:
			best_height = point_height
			best_index = point_index
			continue
		if absf(point_height - best_height) <= FLOAT_EPSILON:
			var current_distance_to_center: float = absf(float(point_index) - center_index)
			var best_distance_to_center: float = absf(float(best_index) - center_index)
			if current_distance_to_center < best_distance_to_center:
				best_index = point_index
	return best_index

func _resolve_ridge_peak_half_width(ridge_path: RidgePath) -> float:
	var peak_half_width: float = lerpf(
		RIDGE_MAIN_PEAK_HALF_WIDTH_MIN,
		RIDGE_MAIN_PEAK_HALF_WIDTH_MAX,
		clampf(ridge_path.strength, 0.0, 1.0)
	)
	if ridge_path != null and ridge_path.is_branch:
		peak_half_width *= RIDGE_BRANCH_HALF_WIDTH_SCALE
	return maxf(0.75, peak_half_width)

func _resolve_ridge_profile_centrality(distance_along_path: float, peak_distance: float, total_length: float) -> float:
	if total_length <= FLOAT_EPSILON:
		return 1.0
	var left_span: float = maxf(peak_distance, FLOAT_EPSILON)
	var right_span: float = maxf(total_length - peak_distance, FLOAT_EPSILON)
	if distance_along_path <= peak_distance:
		return clampf(1.0 - (peak_distance - distance_along_path) / left_span, 0.0, 1.0)
	return clampf(1.0 - (distance_along_path - peak_distance) / right_span, 0.0, 1.0)

func _resolve_seed_ridge_direction(spine_seed: SpineSeed, seed_index: int) -> int:
	if spine_seed != null and spine_seed.direction_bias.length_squared() > FLOAT_EPSILON:
		return _direction_index_from_vector(spine_seed.direction_bias, spine_seed.position, 401 + seed_index)
	return _fallback_direction_for_grid(spine_seed.position, 419 + seed_index)

func _resolve_branch_start_direction(main_path: RidgePath, branch_point_index: int) -> int:
	var branch_origin: Vector2i = main_path.points[branch_point_index]
	var previous_point: Vector2i = main_path.points[branch_point_index - 1]
	var next_point: Vector2i = main_path.points[branch_point_index + 1]
	var tangent := Vector2(
		float(_grid_wrap_delta_x(next_point.x, previous_point.x)),
		float(next_point.y - previous_point.y)
	)
	if tangent.length_squared() <= FLOAT_EPSILON:
		tangent = Vector2(
			float(_grid_wrap_delta_x(branch_origin.x, previous_point.x)),
			float(branch_origin.y - previous_point.y)
		)
	if tangent.length_squared() <= FLOAT_EPSILON:
		return _fallback_direction_for_grid(branch_origin, 443 + branch_point_index)
	var tangent_direction: int = _direction_index_from_vector(tangent.normalized(), branch_origin, 431 + branch_point_index)
	var branch_sign: int = -1 if _hash01_for_grid(branch_origin.x, branch_origin.y, 437 + branch_point_index) < 0.5 else 1
	return _rotate_direction_index(tangent_direction, 2 * branch_sign)

func _build_ridge_candidate_directions(direction_index: int) -> Array[int]:
	return [
		_rotate_direction_index(direction_index, 0),
		_rotate_direction_index(direction_index, -1),
		_rotate_direction_index(direction_index, 1),
	]

func _rotate_direction_index(direction_index: int, offset: int) -> int:
	return int(posmod(direction_index + offset, GRID_NEIGHBOR_OFFSETS_8.size()))

func _direction_index_from_vector(direction: Vector2, grid_pos: Vector2i, salt: int) -> int:
	if direction.length_squared() <= FLOAT_EPSILON:
		return _fallback_direction_for_grid(grid_pos, salt)
	var normalized_direction: Vector2 = direction.normalized()
	var best_direction: int = 0
	var best_dot: float = -INF
	for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
		var candidate_vector: Vector2 = _get_direction_vector(direction_index)
		var candidate_dot: float = normalized_direction.dot(candidate_vector)
		if candidate_dot > best_dot + FLOAT_EPSILON:
			best_dot = candidate_dot
			best_direction = direction_index
	return best_direction

func _fallback_direction_for_grid(grid_pos: Vector2i, salt: int) -> int:
	var direction_count: int = GRID_NEIGHBOR_OFFSETS_8.size()
	var hashed_index: int = floori(_hash01_for_grid(grid_pos.x, grid_pos.y, salt) * float(direction_count))
	return clampi(hashed_index, 0, direction_count - 1)

func _get_direction_vector(direction_index: int) -> Vector2:
	var offset: Vector2i = GRID_NEIGHBOR_OFFSETS_8[_rotate_direction_index(direction_index, 0)]
	return Vector2(float(offset.x), float(offset.y)).normalized()

func _resolve_spine_selection_score(height_value: float, ruggedness: float, grid_pos: Vector2i) -> float:
	var terrain_bias: float = clampf(height_value * 0.6 + ruggedness * 0.4, 0.0, 1.0)
	return terrain_bias + _hash01_for_grid(grid_pos.x, grid_pos.y, 11) * SPINE_SELECTION_JITTER_WEIGHT

func _resolve_spine_strength(height_value: float, ruggedness: float) -> float:
	var terrain_bias: float = clampf(height_value * 0.5 + ruggedness * 0.5, 0.0, 1.0)
	return lerpf(SPINE_STRENGTH_MIN, SPINE_STRENGTH_MAX, terrain_bias)

func _resolve_spine_direction_bias(grid_pos: Vector2i) -> Vector2:
	var left_ruggedness: float = _sample_ruggedness_at_grid(grid_pos.x - 1, grid_pos.y)
	var right_ruggedness: float = _sample_ruggedness_at_grid(grid_pos.x + 1, grid_pos.y)
	var up_ruggedness: float = _sample_ruggedness_at_grid(grid_pos.x, grid_pos.y - 1)
	var down_ruggedness: float = _sample_ruggedness_at_grid(grid_pos.x, grid_pos.y + 1)
	var delta_x: float = (right_ruggedness - left_ruggedness) / maxf(1.0, _grid_span_x * 2.0)
	var delta_y: float = (down_ruggedness - up_ruggedness) / maxf(1.0, _grid_span_y * 2.0)
	var gradient := Vector2(delta_x, delta_y)
	if gradient.length_squared() <= FLOAT_EPSILON:
		return Vector2.ZERO
	return gradient.normalized()

func _sample_ruggedness_at_grid(grid_x: int, grid_y: int) -> float:
	if _planet_sampler == null:
		return 0.0
	var wrapped_grid_x: int = int(posmod(grid_x, _grid_width))
	var clamped_grid_y: int = clampi(grid_y, 0, _grid_height - 1)
	var world_pos := Vector2i(_grid_to_world_x(wrapped_grid_x), _grid_to_world_y(clamped_grid_y))
	return clampf(_planet_sampler.sample_ruggedness(world_pos), 0.0, 1.0)

func _is_spine_seed_far_enough(candidate_grid: Vector2i, min_distance_grid: int) -> bool:
	if min_distance_grid <= 0:
		return true
	var min_distance_sq: int = min_distance_grid * min_distance_grid
	for spine_seed: SpineSeed in _spine_seeds:
		var distance_x: int = _grid_wrap_delta_x(candidate_grid.x, spine_seed.position.x)
		var distance_y: int = candidate_grid.y - spine_seed.position.y
		var distance_sq: int = distance_x * distance_x + distance_y * distance_y
		if distance_sq < min_distance_sq:
			return false
	return true

func _grid_wrap_delta_x(grid_x: int, reference_grid_x: int) -> int:
	if _grid_width <= 0:
		return grid_x - reference_grid_x
	var delta: int = int(posmod(grid_x, _grid_width)) - int(posmod(reference_grid_x, _grid_width))
	var half_width: int = _grid_width / 2
	if delta > half_width:
		delta -= _grid_width
	elif delta < -half_width:
		delta += _grid_width
	return delta

func _unwrap_grid_x_near_reference(grid_x: float, reference_x: float) -> float:
	if _grid_width <= 0:
		return grid_x
	var wrap_width: float = float(_grid_width)
	var wrapped_reference: float = fposmod(reference_x, wrap_width)
	var delta: float = grid_x - wrapped_reference
	var half_width: float = wrap_width * 0.5
	if delta > half_width:
		delta -= wrap_width
	elif delta < -half_width:
		delta += wrap_width
	return reference_x + delta

func _hash01_for_grid(grid_x: int, grid_y: int, salt: int = 0) -> float:
	var combined: int = _resolve_hash_seed()
	combined = int(combined ^ (grid_x * 73856093))
	combined = int(combined ^ (grid_y * 19349663))
	combined = int(combined ^ (salt * 83492791))
	var mixed: int = _mix_hash32(combined)
	return float(mixed) / 2147483647.0

func _resolve_hash_seed() -> int:
	if _planet_sampler == null:
		return 1
	return maxi(1, absi(_planet_sampler.get_world_seed()))

func _mix_hash32(value: int) -> int:
	var state: int = value & 0x7fffffff
	state = int(((state >> 16) ^ state) * 0x45D9F3B) & 0x7fffffff
	state = int(((state >> 16) ^ state) * 0x45D9F3B) & 0x7fffffff
	state = int((state >> 16) ^ state) & 0x7fffffff
	return state

func _is_river_cell(cell_index: int, river_threshold: float) -> bool:
	if int(_lake_mask[cell_index]) > 0:
		return false
	if _accumulation_grid[cell_index] + FLOAT_EPSILON < river_threshold:
		return false
	var target_index: int = _get_flow_target_index(cell_index)
	return target_index >= 0 or _is_y_edge_cell(cell_index)

func _resolve_river_width_tiles(accumulation: float, river_threshold: float) -> float:
	if accumulation + FLOAT_EPSILON < river_threshold:
		return 0.0
	var river_width: float = _resolve_river_base_width()
	var ratio: float = maxf(1.0, accumulation / maxf(1.0, river_threshold))
	if ratio > 1.0 + FLOAT_EPSILON:
		river_width += _resolve_river_width_scale() * (log(ratio) / log(2.0))
	return maxf(0.0, river_width)

func _resolve_floodplain_width_tiles(river_width_tiles: float) -> float:
	if river_width_tiles <= FLOAT_EPSILON:
		return 0.0
	return maxf(0.0, river_width_tiles * _resolve_floodplain_multiplier())

func _resolve_max_ridge_length_grid() -> int:
	if _balance == null:
		return 200
	return maxi(1, _balance.prepass_max_ridge_length_grid)

func _resolve_max_branch_length_grid() -> int:
	if _balance == null:
		return 60
	return maxi(1, _balance.prepass_max_branch_length_grid)

func _resolve_branch_probability() -> float:
	if _balance == null:
		return 0.15
	return clampf(_balance.prepass_branch_probability, 0.0, 1.0)

func _resolve_ridge_min_height() -> float:
	if _balance == null:
		return 0.35
	return clampf(_balance.prepass_ridge_min_height, 0.0, 1.0)

func _resolve_ridge_continuation_inertia() -> float:
	if _balance == null:
		return 0.65
	return clampf(_balance.prepass_ridge_continuation_inertia, 0.0, 1.0)

func _resolve_floodplain_strength(distance_tiles: float, floodplain_width_tiles: float) -> float:
	if floodplain_width_tiles <= FLOAT_EPSILON:
		return 0.0
	var t: float = clampf(1.0 - distance_tiles / floodplain_width_tiles, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _resolve_ridge_strength(distance_to_ridge: float, ridge_half_width: float) -> float:
	if ridge_half_width <= FLOAT_EPSILON:
		return 0.0
	var t: float = clampf(1.0 - distance_to_ridge / ridge_half_width, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _resolve_neighbor_distance_tiles(direction_index: int) -> float:
	var offset: Vector2i = GRID_NEIGHBOR_OFFSETS_8[direction_index]
	var distance_x: float = absf(float(offset.x)) * _grid_span_x
	var distance_y: float = absf(float(offset.y)) * _grid_span_y
	return sqrt(distance_x * distance_x + distance_y * distance_y)

func _build_neighbor_distance_cache() -> PackedFloat32Array:
	if _neighbor_distance_cache.size() == GRID_NEIGHBOR_OFFSETS_8.size():
		return _neighbor_distance_cache
	_neighbor_distance_cache = PackedFloat32Array()
	_neighbor_distance_cache.resize(GRID_NEIGHBOR_OFFSETS_8.size())
	for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
		_neighbor_distance_cache[direction_index] = _resolve_neighbor_distance_tiles(direction_index)
	return _neighbor_distance_cache

func _resolve_max_possible_neighbor_gradient() -> float:
	var min_neighbor_distance: float = 0.0
	for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
		var neighbor_distance: float = _resolve_neighbor_distance_tiles(direction_index)
		if neighbor_distance <= FLOAT_EPSILON:
			continue
		if min_neighbor_distance <= FLOAT_EPSILON or neighbor_distance < min_neighbor_distance:
			min_neighbor_distance = neighbor_distance
	if min_neighbor_distance <= FLOAT_EPSILON:
		return 0.0
	return 1.0 / min_neighbor_distance

func _compute_max_neighbor_gradient(height_grid: PackedFloat32Array, cell_index: int) -> float:
	if height_grid.is_empty():
		return 0.0
	var current_height: float = height_grid[cell_index]
	var max_gradient: float = 0.0
	for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
		var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
		if neighbor_index < 0:
			continue
		var neighbor_distance: float = maxf(FLOAT_EPSILON, _resolve_neighbor_distance_tiles(direction_index))
		var gradient: float = absf(current_height - height_grid[neighbor_index]) / neighbor_distance
		max_gradient = maxf(max_gradient, gradient)
	return max_gradient

func _compute_average_neighbor_height_diff(height_grid: PackedFloat32Array, cell_index: int) -> float:
	if height_grid.is_empty():
		return 0.0
	var current_height: float = height_grid[cell_index]
	var total_diff: float = 0.0
	var neighbor_count: int = 0
	for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
		var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
		if neighbor_index < 0:
			continue
		total_diff += height_grid[neighbor_index] - current_height
		neighbor_count += 1
	if neighbor_count <= 0:
		return 0.0
	return total_diff / float(neighbor_count)

func _clamp_prepass_height(height_value: float) -> float:
	return clampf(height_value, 0.0, 1.0)

func _build_temperature_grid() -> PackedFloat32Array:
	var temperature_grid := PackedFloat32Array()
	temperature_grid.resize(_flow_dir_grid.size())
	for cell_index: int in range(_flow_dir_grid.size()):
		var world_pos := Vector2i(_grid_world_x_cache[cell_index], _grid_world_y_cache[cell_index])
		var channels: WorldChannels = _planet_sampler.sample_world_channels(world_pos)
		temperature_grid[cell_index] = clampf(channels.temperature, 0.0, 1.0)
	return temperature_grid

func _build_moisture_grid() -> PackedFloat32Array:
	var moisture_grid := PackedFloat32Array()
	moisture_grid.resize(_eroded_height_grid.size())
	for cell_index: int in range(_eroded_height_grid.size()):
		var world_pos := Vector2i(_grid_world_x_cache[cell_index], _grid_world_y_cache[cell_index])
		var channels: WorldChannels = _planet_sampler.sample_world_channels(world_pos)
		moisture_grid[cell_index] = clampf(channels.moisture, 0.0, 1.0)
	return moisture_grid

func _build_rain_shadow_columns(wind_direction: Vector2) -> Array:
	var cross_direction := Vector2(-wind_direction.y, wind_direction.x)
	var column_scale: float = _resolve_rain_shadow_column_scale()
	var columns_by_key: Dictionary = {}
	for cell_index: int in range(_eroded_height_grid.size()):
		var cell_world_center: Vector2 = _get_grid_cell_world_center_by_index(cell_index)
		var cross_coord: float = cell_world_center.dot(cross_direction)
		var along_coord: float = cell_world_center.dot(wind_direction)
		var column_key: int = roundi(cross_coord / column_scale)
		if not columns_by_key.has(column_key):
			columns_by_key[column_key] = []
		var column_data: Array = columns_by_key[column_key]
		column_data.append({
			"index": cell_index,
			"along": along_coord,
		})
	var sorted_keys: Array = columns_by_key.keys()
	sorted_keys.sort()
	var ordered_columns: Array = []
	for column_key: Variant in sorted_keys:
		var column_data: Array = columns_by_key[column_key]
		column_data.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_along: float = float(left.get("along", 0.0))
			var right_along: float = float(right.get("along", 0.0))
			if absf(left_along - right_along) > FLOAT_EPSILON:
				return left_along < right_along
			return _is_index_lexicographically_less(
				int(left.get("index", -1)),
				int(right.get("index", -1))
			)
		)
		var column_cells: Array[int] = []
		for entry: Dictionary in column_data:
			column_cells.append(int(entry.get("index", -1)))
		if not column_cells.is_empty():
			ordered_columns.append(column_cells)
	return ordered_columns

func _apply_rain_shadow_column(
	column_cells: Array[int],
	moisture_grid: PackedFloat32Array,
	wind_direction: Vector2,
	wrap_stabilization: bool,
	max_possible_gradient: float,
	precipitation_rate: float,
	lift_factor: float
) -> void:
	if column_cells.is_empty():
		return
	var step_count: int = column_cells.size()
	var capture_start: int = 0
	var previous_cell_index: int = column_cells[0]
	if wrap_stabilization and column_cells.size() > 1:
		step_count *= 2
		capture_start = column_cells.size()
		previous_cell_index = column_cells[column_cells.size() - 1]
	var moisture_budget: float = clampf(moisture_grid[column_cells[0]], 0.0, 1.0)
	for step: int in range(step_count):
		var column_index: int = int(posmod(step, column_cells.size()))
		var cell_index: int = column_cells[column_index]
		var orographic_lift: float = _compute_orographic_lift(
			previous_cell_index,
			cell_index,
			wind_direction,
			max_possible_gradient
		)
		var precipitation: float = moisture_budget * precipitation_rate * (1.0 + orographic_lift * lift_factor)
		moisture_budget = maxf(0.0, moisture_budget - precipitation)
		moisture_budget = _recover_rain_shadow_moisture(moisture_budget, moisture_grid[cell_index])
		if step >= capture_start:
			_rain_shadow_grid[cell_index] = clampf(moisture_budget, 0.0, 1.0)
		previous_cell_index = cell_index

func _compute_orographic_lift(
	previous_cell_index: int,
	cell_index: int,
	wind_direction: Vector2,
	max_possible_gradient: float
) -> float:
	if previous_cell_index == cell_index:
		return 0.0
	var height_gain: float = _eroded_height_grid[cell_index] - _eroded_height_grid[previous_cell_index]
	if height_gain <= FLOAT_EPSILON or max_possible_gradient <= FLOAT_EPSILON:
		return 0.0
	var previous_world_center: Vector2 = _get_grid_cell_world_center_by_index(previous_cell_index)
	var current_world_center: Vector2 = _get_grid_cell_world_center_by_index(cell_index)
	var travel_vector: Vector2 = _get_wrapped_world_vector(previous_world_center, current_world_center)
	var along_distance: float = absf(travel_vector.dot(wind_direction))
	if along_distance <= FLOAT_EPSILON:
		along_distance = travel_vector.length()
	if along_distance <= FLOAT_EPSILON:
		return 0.0
	var raw_gradient: float = height_gain / along_distance
	return clampf(raw_gradient / max_possible_gradient, 0.0, 1.0)

func _recover_rain_shadow_moisture(moisture_budget: float, base_moisture: float) -> float:
	var evaporation_rate: float = _resolve_evaporation_rate()
	if evaporation_rate <= FLOAT_EPSILON:
		return clampf(moisture_budget, 0.0, 1.0)
	# Recover toward the sampler's baseline moisture instead of adding a flat constant.
	return clampf(
		lerpf(
			clampf(moisture_budget, 0.0, 1.0),
			clampf(base_moisture, 0.0, 1.0),
			evaporation_rate
		),
		0.0,
		1.0
	)

func _is_continentalness_water_source(cell_index: int, sea_level_threshold: float) -> bool:
	if _is_y_edge_cell(cell_index):
		return true
	return _eroded_height_grid[cell_index] < sea_level_threshold

func _resolve_base_accumulation(temperature: float) -> float:
	var glacial_melt_temperature: float = _resolve_glacial_melt_temperature()
	if temperature >= glacial_melt_temperature:
		return 1.0
	var glacial_proximity: float = clampf((glacial_melt_temperature - temperature) / 0.15, 0.0, 1.0)
	return 1.0 + _resolve_glacial_melt_bonus() * (1.0 - glacial_proximity)

func _resolve_downstream_transfer(accumulation: float, temperature: float) -> float:
	var evaporation_loss: float = accumulation * _resolve_latitude_evaporation_rate() * temperature * temperature
	return maxf(0.0, accumulation - evaporation_loss)

func _reset_lake_inflow_accumulation() -> void:
	for lake_record: LakeRecord in _lake_records:
		lake_record.inflow_accumulation = 0.0

func _record_lake_inflow(source_index: int, target_index: int, transfer: float) -> void:
	if transfer <= 0.0:
		return
	var target_lake_id: int = int(_lake_mask[target_index])
	if target_lake_id <= 0:
		return
	var source_lake_id: int = int(_lake_mask[source_index])
	if source_lake_id == target_lake_id:
		return
	var lake_record_index: int = target_lake_id - 1
	if lake_record_index < 0 or lake_record_index >= _lake_records.size():
		return
	var lake_record: LakeRecord = _lake_records[lake_record_index]
	lake_record.inflow_accumulation += transfer

func _get_flow_target_index(cell_index: int) -> int:
	var direction_index: int = int(_flow_dir_grid[cell_index])
	if direction_index == FLOW_DIRECTION_NONE:
		return -1
	return _get_neighbor_index(cell_index, direction_index)

func _find_direct_flow_direction(cell_index: int) -> int:
	var current_height: float = _filled_height_grid[cell_index]
	var best_direction: int = -1
	var best_gradient: float = 0.0
	var best_neighbor_index: int = -1
	for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
		var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
		if neighbor_index < 0:
			continue
		var height_drop: float = current_height - _filled_height_grid[neighbor_index]
		if height_drop <= FLOAT_EPSILON:
			continue
		var gradient: float = height_drop / GRID_NEIGHBOR_DISTANCES_8[direction_index]
		if gradient > best_gradient + FLOAT_EPSILON:
			best_direction = direction_index
			best_gradient = gradient
			best_neighbor_index = neighbor_index
			continue
		if absf(gradient - best_gradient) <= FLOAT_EPSILON and _is_index_lexicographically_less(neighbor_index, best_neighbor_index):
			best_direction = direction_index
			best_neighbor_index = neighbor_index
	return best_direction

func _resolve_flat_plateau_flow(start_index: int, unresolved_plateau_cells: PackedByteArray) -> void:
	var plateau_height: float = _filled_height_grid[start_index]
	var plateau_cells: Array[int] = []
	var queue: Array[int] = [start_index]
	var queue_index: int = 0
	unresolved_plateau_cells[start_index] = 2
	while queue_index < queue.size():
		var current_index: int = queue[queue_index]
		queue_index += 1
		plateau_cells.append(current_index)
		for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
			var neighbor_index: int = _get_neighbor_index(current_index, direction_index)
			if neighbor_index < 0:
				continue
			if unresolved_plateau_cells[neighbor_index] != 1:
				continue
			if not _heights_match(_filled_height_grid[neighbor_index], plateau_height):
				continue
			unresolved_plateau_cells[neighbor_index] = 2
			queue.append(neighbor_index)
	plateau_cells.sort()
	var seed_directions: Dictionary = {}
	var propagation_queue: Array[int] = []
	for cell_index: int in plateau_cells:
		var exit_direction: int = _find_flat_exit_direction(cell_index, plateau_height, unresolved_plateau_cells)
		if exit_direction < 0:
			continue
		seed_directions[cell_index] = exit_direction
	for cell_index: int in plateau_cells:
		if not seed_directions.has(cell_index):
			continue
		_flow_dir_grid[cell_index] = int(seed_directions[cell_index])
		unresolved_plateau_cells[cell_index] = 0
		propagation_queue.append(cell_index)
	var propagation_index: int = 0
	while propagation_index < propagation_queue.size():
		var resolved_index: int = propagation_queue[propagation_index]
		propagation_index += 1
		for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
			var neighbor_index: int = _get_neighbor_index(resolved_index, direction_index)
			if neighbor_index < 0:
				continue
			if unresolved_plateau_cells[neighbor_index] != 2:
				continue
			if not _heights_match(_filled_height_grid[neighbor_index], plateau_height):
				continue
			var toward_resolved_direction: int = _get_direction_between_indices(neighbor_index, resolved_index)
			if toward_resolved_direction < 0:
				continue
			_flow_dir_grid[neighbor_index] = toward_resolved_direction
			unresolved_plateau_cells[neighbor_index] = 0
			propagation_queue.append(neighbor_index)
	for cell_index: int in plateau_cells:
		if unresolved_plateau_cells[cell_index] != 0:
			unresolved_plateau_cells[cell_index] = 0

func _find_flat_exit_direction(
	cell_index: int,
	plateau_height: float,
	unresolved_plateau_cells: PackedByteArray
) -> int:
	var best_direction: int = -1
	var best_neighbor_index: int = -1
	for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
		var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
		if neighbor_index < 0:
			continue
		if not _heights_match(_filled_height_grid[neighbor_index], plateau_height):
			continue
		if unresolved_plateau_cells[neighbor_index] == 2:
			continue
		if not _is_y_edge_cell(neighbor_index) and _flow_dir_grid[neighbor_index] == FLOW_DIRECTION_NONE:
			continue
		if best_direction < 0 or _is_index_lexicographically_less(neighbor_index, best_neighbor_index):
			best_direction = direction_index
			best_neighbor_index = neighbor_index
	return best_direction

func _get_neighbor_index(cell_index: int, direction_index: int) -> int:
	if cell_index < 0 or direction_index < 0 or direction_index >= GRID_NEIGHBOR_OFFSETS_8.size():
		return -1
	if not _neighbor_index_cache.is_empty():
		var cache_index: int = cell_index * GRID_NEIGHBOR_OFFSETS_8.size() + direction_index
		if cache_index >= 0 and cache_index < _neighbor_index_cache.size():
			return _neighbor_index_cache[cache_index]
	var cell_grid: Vector2i = _index_to_grid(cell_index)
	var offset: Vector2i = GRID_NEIGHBOR_OFFSETS_8[direction_index]
	var neighbor_y: int = cell_grid.y + offset.y
	if neighbor_y < 0 or neighbor_y >= _grid_height:
		return -1
	var neighbor_x: int = int(posmod(cell_grid.x + offset.x, _grid_width))
	return _flatten_index(neighbor_x, neighbor_y)

func _get_direction_between_indices(from_index: int, to_index: int) -> int:
	var from_grid: Vector2i = _index_to_grid(from_index)
	var to_grid: Vector2i = _index_to_grid(to_index)
	var delta_x: int = to_grid.x - from_grid.x
	if delta_x > 1:
		delta_x -= _grid_width
	elif delta_x < -1:
		delta_x += _grid_width
	var delta_y: int = to_grid.y - from_grid.y
	var offset := Vector2i(delta_x, delta_y)
	for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
		if GRID_NEIGHBOR_OFFSETS_8[direction_index] == offset:
			return direction_index
	return -1

func _is_y_edge_cell(cell_index: int) -> bool:
	if _grid_width <= 0:
		return true
	var grid_y: int = int(cell_index / _grid_width)
	return grid_y <= 0 or grid_y >= _grid_height - 1

func _heights_match(left_height: float, right_height: float) -> bool:
	return absf(left_height - right_height) <= FLOAT_EPSILON

func _seed_priority_flood_boundaries(
	visited: PackedByteArray,
	heap_indices: Array[int],
	heap_priorities: Array[float]
) -> void:
	for grid_x: int in range(_grid_width):
		_seed_priority_flood_boundary_cell(grid_x, 0, visited, heap_indices, heap_priorities)
		if _grid_height > 1:
			_seed_priority_flood_boundary_cell(grid_x, _grid_height - 1, visited, heap_indices, heap_priorities)

func _seed_priority_flood_boundary_cell(
	grid_x: int,
	grid_y: int,
	visited: PackedByteArray,
	heap_indices: Array[int],
	heap_priorities: Array[float]
) -> void:
	var cell_index: int = _flatten_index(grid_x, grid_y)
	if visited[cell_index] != 0:
		return
	visited[cell_index] = 1
	_numeric_heap_push(heap_indices, heap_priorities, cell_index, _height_grid[cell_index])

func _extract_lake_records() -> void:
	_lake_mask.fill(0)
	_lake_records.clear()
	if _height_grid.is_empty():
		return
	var component_id_by_cell: Array[int] = []
	component_id_by_cell.resize(_height_grid.size())
	component_id_by_cell.fill(-1)
	var next_component_id: int = 0
	for cell_index: int in range(_height_grid.size()):
		if component_id_by_cell[cell_index] != -1:
			continue
		if _filled_height_grid[cell_index] <= _height_grid[cell_index] + FLOAT_EPSILON:
			continue
		var component_cells: Array[int] = _collect_basin_component(cell_index, next_component_id, component_id_by_cell)
		if component_cells.is_empty():
			continue
		component_cells.sort()
		var lake_record: LakeRecord = _build_lake_record(component_cells, next_component_id, component_id_by_cell)
		next_component_id += 1
		if lake_record == null:
			continue
		if lake_record.area_grid_cells < _resolve_lake_min_area():
			continue
		if lake_record.max_depth < _resolve_lake_min_depth():
			continue
		if _lake_records.size() >= MAX_LAKE_MASK_ID:
			push_error("WorldPrePass lake mask overflow: more than %d lakes detected" % MAX_LAKE_MASK_ID)
			break
		lake_record.id = _lake_records.size() + 1
		_lake_records.append(lake_record)
		for basin_index: int in component_cells:
			_lake_mask[basin_index] = lake_record.id

func _collect_basin_component(
	start_index: int,
	component_id: int,
	component_id_by_cell: Array[int]
) -> Array[int]:
	var surface_height: float = _filled_height_grid[start_index]
	var queue: Array[int] = [start_index]
	var queue_index: int = 0
	var component_cells: Array[int] = []
	component_id_by_cell[start_index] = component_id
	while queue_index < queue.size():
		var current_index: int = queue[queue_index]
		queue_index += 1
		component_cells.append(current_index)
		for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
			var neighbor_index: int = _get_neighbor_index(current_index, direction_index)
			if neighbor_index < 0:
				continue
			if component_id_by_cell[neighbor_index] != -1:
				continue
			if _filled_height_grid[neighbor_index] <= _height_grid[neighbor_index] + FLOAT_EPSILON:
				continue
			if absf(_filled_height_grid[neighbor_index] - surface_height) > FLOAT_EPSILON:
				continue
			component_id_by_cell[neighbor_index] = component_id
			queue.append(neighbor_index)
	return component_cells

func _build_lake_record(
	component_cells: Array[int],
	component_id: int,
	component_id_by_cell: Array[int]
) -> LakeRecord:
	if component_cells.is_empty():
		return null
	var record := LakeRecord.new()
	record.grid_cells = PackedInt32Array(component_cells)
	record.area_grid_cells = component_cells.size()
	record.surface_height = _filled_height_grid[component_cells[0]]
	record.max_depth = _measure_component_max_depth(component_cells)
	var spill_index: int = _find_component_spill_index(component_cells, component_id, component_id_by_cell)
	if spill_index >= 0:
		record.spill_point = _index_to_grid(spill_index)
	else:
		record.spill_point = _index_to_grid(component_cells[0])
	record.lake_type = _classify_lake_type(component_cells, record.max_depth)
	record.inflow_accumulation = 0.0
	return record

func _measure_component_max_depth(component_cells: Array[int]) -> float:
	var max_depth: float = 0.0
	for cell_index: int in component_cells:
		max_depth = maxf(max_depth, _filled_height_grid[cell_index] - _height_grid[cell_index])
	return max_depth

func _find_component_spill_index(
	component_cells: Array[int],
	component_id: int,
	component_id_by_cell: Array[int]
) -> int:
	var best_index: int = -1
	var best_filled_height: float = INF
	var best_raw_height: float = INF
	for cell_index: int in component_cells:
		for direction_index: int in range(GRID_NEIGHBOR_OFFSETS_8.size()):
			var neighbor_index: int = _get_neighbor_index(cell_index, direction_index)
			if neighbor_index < 0:
				continue
			if component_id_by_cell[neighbor_index] == component_id:
				continue
			var neighbor_filled_height: float = _filled_height_grid[neighbor_index]
			var neighbor_raw_height: float = _height_grid[neighbor_index]
			if neighbor_filled_height < best_filled_height - FLOAT_EPSILON:
				best_index = neighbor_index
				best_filled_height = neighbor_filled_height
				best_raw_height = neighbor_raw_height
				continue
			if absf(neighbor_filled_height - best_filled_height) <= FLOAT_EPSILON:
				if neighbor_raw_height < best_raw_height - FLOAT_EPSILON:
					best_index = neighbor_index
					best_raw_height = neighbor_raw_height
					continue
				if absf(neighbor_raw_height - best_raw_height) <= FLOAT_EPSILON and _is_index_lexicographically_less(neighbor_index, best_index):
					best_index = neighbor_index
	return best_index

func _classify_lake_type(component_cells: Array[int], max_depth: float) -> StringName:
	if _planet_sampler == null:
		if component_cells.size() >= 50 and max_depth > 0.15:
			return LAKE_TYPE_TECTONIC
		return LAKE_TYPE_FLOODPLAIN
	var total_temperature: float = 0.0
	var total_height: float = 0.0
	var total_ruggedness: float = 0.0
	for cell_index: int in component_cells:
		var cell_grid: Vector2i = _index_to_grid(cell_index)
		var world_pos := Vector2i(_grid_to_world_x(cell_grid.x), _grid_to_world_y(cell_grid.y))
		var channels: WorldChannels = _planet_sampler.sample_world_channels(world_pos)
		total_temperature += channels.temperature
		total_height += channels.height
		total_ruggedness += channels.ruggedness
	var sample_count: float = float(maxi(1, component_cells.size()))
	var average_temperature: float = total_temperature / sample_count
	if average_temperature <= _resolve_frozen_lake_temperature():
		return LAKE_TYPE_GLACIAL
	if component_cells.size() >= 50 and max_depth > 0.15:
		return LAKE_TYPE_TECTONIC
	var average_height: float = total_height / sample_count
	var average_ruggedness: float = total_ruggedness / sample_count
	if average_height >= 0.58 or average_ruggedness >= 0.45:
		return LAKE_TYPE_MOUNTAIN
	return LAKE_TYPE_FLOODPLAIN

func _resolve_lake_min_area() -> int:
	if _balance == null:
		return 8
	return maxi(3, _balance.prepass_lake_min_area)

func _resolve_lake_min_depth() -> float:
	if _balance == null:
		return 0.04
	return maxf(0.01, _balance.prepass_lake_min_depth)

func _resolve_frozen_lake_temperature() -> float:
	if _balance == null:
		return 0.15
	return clampf(_balance.prepass_frozen_lake_temperature, 0.0, 0.5)

func _resolve_glacial_melt_temperature() -> float:
	if _balance == null:
		return 0.22
	return clampf(_balance.prepass_glacial_melt_temperature, 0.0, 0.5)

func _resolve_glacial_melt_bonus() -> float:
	if _balance == null:
		return 2.5
	return maxf(0.0, _balance.prepass_glacial_melt_bonus)

func _resolve_latitude_evaporation_rate() -> float:
	if _balance == null:
		return 0.08
	return clampf(_balance.prepass_latitude_evaporation_rate, 0.0, 0.3)

func _resolve_prevailing_wind_direction() -> Vector2:
	if _balance == null:
		return Vector2.RIGHT
	var wind_direction: Vector2 = _balance.prepass_prevailing_wind_direction
	if wind_direction.length_squared() <= FLOAT_EPSILON:
		return Vector2.RIGHT
	return wind_direction.normalized()

func _resolve_precipitation_rate() -> float:
	if _balance == null:
		return 0.12
	return clampf(_balance.prepass_precipitation_rate, 0.0, 0.5)

func _resolve_orographic_lift_factor() -> float:
	if _balance == null:
		return 3.0
	return clampf(_balance.prepass_orographic_lift_factor, 0.5, 8.0)

func _resolve_evaporation_rate() -> float:
	if _balance == null:
		return 0.02
	return clampf(_balance.prepass_evaporation_rate, 0.0, 0.2)

func _resolve_sea_level_threshold() -> float:
	if _balance == null:
		return 0.15
	return clampf(_balance.prepass_sea_level_threshold, 0.0, 0.5)

func _resolve_river_accumulation_threshold() -> float:
	if _balance == null:
		return 200.0
	return maxf(1.0, float(_balance.prepass_river_accumulation_threshold))

func _resolve_river_base_width() -> float:
	if _balance == null:
		return 2.0
	return maxf(1.0, _balance.prepass_river_base_width)

func _resolve_river_width_scale() -> float:
	if _balance == null:
		return 6.0
	return maxf(0.0, _balance.prepass_river_width_scale)

func _resolve_floodplain_multiplier() -> float:
	if _balance == null:
		return 3.0
	return maxf(1.0, _balance.prepass_floodplain_multiplier)

func _resolve_erosion_valley_strength() -> float:
	if _balance == null:
		return 0.12
	return clampf(_balance.prepass_erosion_valley_strength, 0.0, 0.5)

func _resolve_thermal_iterations() -> int:
	if _balance == null:
		return 3
	return maxi(1, _balance.prepass_thermal_iterations)

func _resolve_thermal_rate() -> float:
	if _balance == null:
		return 0.08
	return clampf(_balance.prepass_thermal_rate, 0.0, 0.3)

func _resolve_deposit_rate() -> float:
	if _balance == null:
		return 0.15
	return clampf(_balance.prepass_deposit_rate, 0.0, 0.5)

func _resolve_target_spine_count() -> int:
	if _balance == null:
		return 4
	return maxi(1, _balance.prepass_target_spine_count)

func _resolve_min_spine_distance_grid() -> int:
	if _balance == null:
		return 80
	return maxi(1, _balance.prepass_min_spine_distance_grid)

func _resolve_max_river_distance_tiles() -> float:
	var wrap_span_tiles: float = maxf(1.0, float(_wrap_width_tiles))
	var y_span_tiles: float = maxf(1.0, float(_resolve_y_span_tiles()))
	return sqrt(wrap_span_tiles * wrap_span_tiles + y_span_tiles * y_span_tiles)

func _resolve_rain_shadow_column_scale() -> float:
	return maxf(1.0, minf(_grid_span_x, _grid_span_y))

func _get_grid_cell_world_center(grid: Vector2i) -> Vector2:
	return Vector2(
		float(_grid_to_world_x(grid.x)) + (_grid_span_x * 0.5),
		float(_grid_to_world_y(grid.y)) + (_grid_span_y * 0.5)
	)

func _get_grid_cell_world_center_by_index(cell_index: int) -> Vector2:
	if cell_index >= 0 and cell_index < _grid_world_center_cache.size():
		return _grid_world_center_cache[cell_index]
	return _get_grid_cell_world_center(_index_to_grid(cell_index))

func _get_wrapped_world_vector(from_world: Vector2, to_world: Vector2) -> Vector2:
	var delta_x: float = to_world.x - from_world.x
	var wrap_width: float = maxf(1.0, float(_wrap_width_tiles))
	var half_wrap: float = wrap_width * 0.5
	if delta_x > half_wrap:
		delta_x -= wrap_width
	elif delta_x < -half_wrap:
		delta_x += wrap_width
	return Vector2(delta_x, to_world.y - from_world.y)

func _heap_push(
	heap: Array[Dictionary],
	cell_index: int,
	priority: float,
	extra_fields: Dictionary = {}
) -> void:
	var entry: Dictionary = {
		"index": cell_index,
		"priority": priority,
	}
	for field_name: Variant in extra_fields.keys():
		entry[field_name] = extra_fields[field_name]
	heap.append(entry)
	var child_index: int = heap.size() - 1
	while child_index > 0:
		var parent_index: int = int((child_index - 1) / 2)
		if not _is_heap_entry_less(heap[child_index], heap[parent_index]):
			break
		var temp: Dictionary = heap[parent_index]
		heap[parent_index] = heap[child_index]
		heap[child_index] = temp
		child_index = parent_index

func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	if heap.is_empty():
		return {}
	var result: Dictionary = heap[0]
	var last_index: int = heap.size() - 1
	if last_index == 0:
		heap.pop_back()
		return result
	heap[0] = heap[last_index]
	heap.pop_back()
	var parent_index: int = 0
	while true:
		var left_index: int = parent_index * 2 + 1
		if left_index >= heap.size():
			break
		var smallest_index: int = left_index
		var right_index: int = left_index + 1
		if right_index < heap.size() and _is_heap_entry_less(heap[right_index], heap[left_index]):
			smallest_index = right_index
		if not _is_heap_entry_less(heap[smallest_index], heap[parent_index]):
			break
		var temp: Dictionary = heap[parent_index]
		heap[parent_index] = heap[smallest_index]
		heap[smallest_index] = temp
		parent_index = smallest_index
	return result

func _numeric_heap_push(heap_indices: Array[int], heap_priorities: Array[float], cell_index: int, priority: float) -> void:
	heap_indices.append(cell_index)
	heap_priorities.append(priority)
	var child_index: int = heap_indices.size() - 1
	while child_index > 0:
		var parent_index: int = int((child_index - 1) / 2)
		if not _is_numeric_heap_entry_less(
			heap_priorities[child_index],
			heap_indices[child_index],
			heap_priorities[parent_index],
			heap_indices[parent_index]
		):
			break
		var temp_index: int = heap_indices[parent_index]
		var temp_priority: float = heap_priorities[parent_index]
		heap_indices[parent_index] = heap_indices[child_index]
		heap_priorities[parent_index] = heap_priorities[child_index]
		heap_indices[child_index] = temp_index
		heap_priorities[child_index] = temp_priority
		child_index = parent_index

func _numeric_heap_pop(heap_indices: Array[int], heap_priorities: Array[float]) -> int:
	if heap_indices.is_empty():
		_numeric_heap_last_priority = INF
		return -1
	var result_index: int = heap_indices[0]
	_numeric_heap_last_priority = heap_priorities[0]
	var last_index: int = heap_indices.size() - 1
	if last_index == 0:
		heap_indices.pop_back()
		heap_priorities.pop_back()
		return result_index
	heap_indices[0] = heap_indices[last_index]
	heap_priorities[0] = heap_priorities[last_index]
	heap_indices.pop_back()
	heap_priorities.pop_back()
	var parent_index: int = 0
	while true:
		var left_index: int = parent_index * 2 + 1
		if left_index >= heap_indices.size():
			break
		var smallest_index: int = left_index
		var right_index: int = left_index + 1
		if right_index < heap_indices.size() and _is_numeric_heap_entry_less(
			heap_priorities[right_index],
			heap_indices[right_index],
			heap_priorities[left_index],
			heap_indices[left_index]
		):
			smallest_index = right_index
		if not _is_numeric_heap_entry_less(
			heap_priorities[smallest_index],
			heap_indices[smallest_index],
			heap_priorities[parent_index],
			heap_indices[parent_index]
		):
			break
		var temp_index: int = heap_indices[parent_index]
		var temp_priority: float = heap_priorities[parent_index]
		heap_indices[parent_index] = heap_indices[smallest_index]
		heap_priorities[parent_index] = heap_priorities[smallest_index]
		heap_indices[smallest_index] = temp_index
		heap_priorities[smallest_index] = temp_priority
		parent_index = smallest_index
	return result_index

func _is_heap_entry_less(left_entry: Dictionary, right_entry: Dictionary) -> bool:
	var left_priority: float = float(left_entry.get("priority", 0.0))
	var right_priority: float = float(right_entry.get("priority", 0.0))
	if left_priority < right_priority - FLOAT_EPSILON:
		return true
	if left_priority > right_priority + FLOAT_EPSILON:
		return false
	return int(left_entry.get("index", 0)) < int(right_entry.get("index", 0))

func _is_numeric_heap_entry_less(
	left_priority: float,
	left_index: int,
	right_priority: float,
	right_index: int
) -> bool:
	if left_priority < right_priority - FLOAT_EPSILON:
		return true
	if left_priority > right_priority + FLOAT_EPSILON:
		return false
	return left_index < right_index

func _is_index_lexicographically_less(left_index: int, right_index: int) -> bool:
	if right_index < 0:
		return true
	var left_grid: Vector2i = _index_to_grid(left_index)
	var right_grid: Vector2i = _index_to_grid(right_index)
	if left_grid.y != right_grid.y:
		return left_grid.y < right_grid.y
	return left_grid.x < right_grid.x
