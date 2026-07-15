extends SceneTree

## Exactness and CPU-side upload probe for the publish-time terrain presentation path.
##
## Usage:
##   Godot --headless --path . --script res://tools/tilemap_pattern_upload_probe.gd
##
## This intentionally benchmarks the public Godot API used by ChunkView. It does
## not depend on ChunkView itself, so it can remain useful while that pipeline is
## being refactored.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")

const CELL_SIDE: int = 16
const CELL_COUNT: int = CELL_SIDE * CELL_SIDE
const STAGED_BATCH_SIZE: int = 64
const WARMUP_ITERATIONS: int = 80
const MEASURE_ITERATIONS: int = 500

var _failed: bool = false
var _base_layer: TileMapLayer
var _overlay_layer: TileMapLayer
var _terrain_ids: PackedInt32Array = PackedInt32Array()
var _source_ids: PackedInt32Array = PackedInt32Array()
var _atlas_coords: Array[Vector2i] = []
var _overlay_flags: PackedByteArray = PackedByteArray()


func _init() -> void:
	WorldTileSetFactory.bootstrap()
	_base_layer = TileMapLayer.new()
	_base_layer.name = "PatternProbeBase"
	_base_layer.tile_set = WorldTileSetFactory.get_base_tile_set()
	root.add_child(_base_layer)
	_overlay_layer = TileMapLayer.new()
	_overlay_layer.name = "PatternProbeOverlay"
	_overlay_layer.tile_set = WorldTileSetFactory.get_overlay_tile_set()
	root.add_child(_overlay_layer)
	_build_fixture()
	_assert_exact_clear_and_pattern_commit()
	_assert_set_pattern_does_not_clear_omissions()
	if _failed:
		quit(1)
		return

	for iteration: int in range(WARMUP_ITERATIONS):
		_apply_direct()
		var warm_patterns: Array[TileMapPattern] = _build_patterns()
		_commit_patterns(warm_patterns)

	var prebuilt_patterns: Array[TileMapPattern] = _build_patterns()
	var direct_usec: int = _measure_direct()
	var staged_direct_usec: int = _measure_staged_direct()
	var build_usec: int = _measure_pattern_build()
	var commit_usec: int = _measure_pattern_commit(prebuilt_patterns)
	var end_to_end_usec: int = _measure_pattern_end_to_end()
	print(
		"tilemap_pattern_upload_probe: iterations=%d cells=%d " % [MEASURE_ITERATIONS, CELL_COUNT],
		"direct=%.3fms staged_direct_4x64=%.3fms pattern_build=%.3fms pattern_commit=%.3fms " % [
			_usec_per_iteration_to_msec(direct_usec),
			_usec_per_iteration_to_msec(staged_direct_usec),
			_usec_per_iteration_to_msec(build_usec),
			_usec_per_iteration_to_msec(commit_usec),
		],
		"pattern_total=%.3fms speedup_total=%.2fx speedup_commit=%.2fx" % [
			_usec_per_iteration_to_msec(end_to_end_usec),
			_ratio(direct_usec, end_to_end_usec),
			_ratio(direct_usec, commit_usec),
		],
	)
	print("tilemap_pattern_upload_probe: exact clear+set_pattern parity OK")
	quit(0)


func _build_fixture() -> void:
	var base_terrain_id: int = WorldRuntimeConstants.TERRAIN_PLAINS_GROUND
	var overlay_terrain_id: int = -1
	for candidate: int in [
		WorldRuntimeConstants.TERRAIN_LEGACY_BLOCKED,
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_WALL,
		WorldRuntimeConstants.TERRAIN_MOUNTAIN_FOOT,
		WorldRuntimeConstants.TERRAIN_LAKE_BED_SHALLOW,
		WorldRuntimeConstants.TERRAIN_LAKE_BED_DEEP,
	]:
		if WorldTileSetFactory.uses_overlay_layer(candidate):
			overlay_terrain_id = candidate
			break
	_expect(overlay_terrain_id >= 0, "fixture requires at least one overlay terrain")
	_terrain_ids.resize(CELL_COUNT)
	_source_ids.resize(CELL_COUNT)
	_atlas_coords.resize(CELL_COUNT)
	_overlay_flags.resize(CELL_COUNT)
	for index: int in range(CELL_COUNT):
		# An uneven split catches accidental same-cell writes and omitted cells in
		# both patterns. Every world cell belongs to exactly one presentation layer.
		var uses_overlay: bool = (index % 5 == 0) or (index % 13 == 0)
		var terrain_id: int = overlay_terrain_id if uses_overlay else base_terrain_id
		_terrain_ids[index] = terrain_id
		_source_ids[index] = WorldTileSetFactory.get_source_id(terrain_id)
		_atlas_coords[index] = WorldTileSetFactory.get_atlas_coords(terrain_id, 0)
		_overlay_flags[index] = 1 if uses_overlay else 0


func _assert_exact_clear_and_pattern_commit() -> void:
	# Seed both layers, including a cell outside the incoming pattern. The exact
	# publish contract requires old cells and opposite-layer omissions to vanish.
	for index: int in range(CELL_COUNT):
		var coord: Vector2i = _coord(index)
		_base_layer.set_cell(coord, _source_ids[index], _atlas_coords[index])
		_overlay_layer.set_cell(coord, _source_ids[index], _atlas_coords[index])
	_base_layer.set_cell(Vector2i(CELL_SIDE + 2, CELL_SIDE + 3), _source_ids[1], _atlas_coords[1])
	_overlay_layer.set_cell(Vector2i(CELL_SIDE + 2, CELL_SIDE + 3), _source_ids[0], _atlas_coords[0])
	var exact_patterns: Array[TileMapPattern] = _build_patterns()
	_commit_patterns(exact_patterns)
	for index: int in range(CELL_COUNT):
		var coord: Vector2i = _coord(index)
		var expected_layer: TileMapLayer = _overlay_layer if _overlay_flags[index] != 0 else _base_layer
		var omitted_layer: TileMapLayer = _base_layer if _overlay_flags[index] != 0 else _overlay_layer
		_expect(
			expected_layer.get_cell_source_id(coord) == _source_ids[index],
			"source id mismatch at %s" % coord,
		)
		_expect(
			expected_layer.get_cell_atlas_coords(coord) == _atlas_coords[index],
			"atlas coords mismatch at %s" % coord,
		)
		_expect(
			omitted_layer.get_cell_source_id(coord) == -1,
			"opposite-layer omission was not cleared at %s" % coord,
		)
	_expect(
		_base_layer.get_cell_source_id(Vector2i(CELL_SIDE + 2, CELL_SIDE + 3)) == -1,
		"base stale cell outside pattern survived exact commit",
	)
	_expect(
		_overlay_layer.get_cell_source_id(Vector2i(CELL_SIDE + 2, CELL_SIDE + 3)) == -1,
		"overlay stale cell outside pattern survived exact commit",
	)


func _assert_set_pattern_does_not_clear_omissions() -> void:
	# This documents the API trap: set_pattern overlays cells; it is not a replace.
	# Chunk publication must clear the target layers before the exact commit.
	var omitted_index: int = 1
	if _overlay_flags[omitted_index] == 0:
		_overlay_layer.set_cell(_coord(omitted_index), _source_ids[0], _atlas_coords[0])
		_overlay_layer.set_pattern(Vector2i.ZERO, _build_patterns()[1])
		_expect(
			_overlay_layer.get_cell_source_id(_coord(omitted_index)) != -1,
			"probe assumption changed: set_pattern unexpectedly became replace semantics",
		)
	_overlay_layer.clear()


func _apply_direct() -> void:
	_base_layer.clear()
	_overlay_layer.clear()
	for index: int in range(CELL_COUNT):
		var layer: TileMapLayer = _overlay_layer if _overlay_flags[index] != 0 else _base_layer
		layer.set_cell(_coord(index), _source_ids[index], _atlas_coords[index])
	_flush_layer_updates()


func _build_patterns() -> Array[TileMapPattern]:
	var base_pattern := TileMapPattern.new()
	var overlay_pattern := TileMapPattern.new()
	for index: int in range(CELL_COUNT):
		var pattern: TileMapPattern = overlay_pattern if _overlay_flags[index] != 0 else base_pattern
		# TileMapPattern defaults alternative_tile to -1, unlike
		# TileMapLayer.set_cell() whose default is 0. Passing 0 explicitly is
		# required; otherwise set_pattern() discards these atlas cells.
		pattern.set_cell(_coord(index), _source_ids[index], _atlas_coords[index], 0)
	return [base_pattern, overlay_pattern]


func _commit_patterns(patterns: Array[TileMapPattern]) -> void:
	_base_layer.clear()
	_overlay_layer.clear()
	_base_layer.set_pattern(Vector2i.ZERO, patterns[0])
	_overlay_layer.set_pattern(Vector2i.ZERO, patterns[1])
	_flush_layer_updates()


func _measure_direct() -> int:
	var started_usec: int = Time.get_ticks_usec()
	for iteration: int in range(MEASURE_ITERATIONS):
		_apply_direct()
	return Time.get_ticks_usec() - started_usec


func _measure_staged_direct() -> int:
	var started_usec: int = Time.get_ticks_usec()
	for iteration: int in range(MEASURE_ITERATIONS):
		_base_layer.clear()
		_overlay_layer.clear()
		for batch_start: int in range(0, CELL_COUNT, STAGED_BATCH_SIZE):
			var batch_end: int = mini(batch_start + STAGED_BATCH_SIZE, CELL_COUNT)
			for index: int in range(batch_start, batch_end):
				var layer: TileMapLayer = (
					_overlay_layer if _overlay_flags[index] != 0 else _base_layer
				)
				layer.set_cell(_coord(index), _source_ids[index], _atlas_coords[index])
			_flush_layer_updates()
	return Time.get_ticks_usec() - started_usec


func _measure_pattern_build() -> int:
	var started_usec: int = Time.get_ticks_usec()
	for iteration: int in range(MEASURE_ITERATIONS):
		_build_patterns()
	return Time.get_ticks_usec() - started_usec


func _measure_pattern_commit(patterns: Array[TileMapPattern]) -> int:
	var started_usec: int = Time.get_ticks_usec()
	for iteration: int in range(MEASURE_ITERATIONS):
		_commit_patterns(patterns)
	return Time.get_ticks_usec() - started_usec


func _measure_pattern_end_to_end() -> int:
	var started_usec: int = Time.get_ticks_usec()
	for iteration: int in range(MEASURE_ITERATIONS):
		_commit_patterns(_build_patterns())
	return Time.get_ticks_usec() - started_usec


func _flush_layer_updates() -> void:
	# TileMapLayer batches its internal work until the end of frame by default.
	# Explicit flushing makes the probe include that CPU work instead of timing
	# only the public method calls.
	_base_layer.update_internals()
	_overlay_layer.update_internals()


func _coord(index: int) -> Vector2i:
	return Vector2i(index % CELL_SIDE, index / CELL_SIDE)


func _usec_per_iteration_to_msec(total_usec: int) -> float:
	return float(total_usec) / float(MEASURE_ITERATIONS) / 1000.0


func _ratio(numerator: int, denominator: int) -> float:
	if denominator <= 0:
		return 0.0
	return float(numerator) / float(denominator)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("tilemap_pattern_upload_probe: %s" % message)
