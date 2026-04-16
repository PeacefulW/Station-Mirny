class_name MassPlacementValidationScenario
extends "res://core/debug/scenarios/validation_scenario.gd"

const WAIT_SETTLE_FRAMES: int = 12
const WAIT_TIMEOUT_FRAMES: int = 180
const GRID_COLUMNS: int = 4
const GRID_ROWS: int = 3

var _stage: int = -1
var _wait_frames_remaining: int = 0
var _wait_timeout_frames_remaining: int = -1
var _placement_tiles: Array[Vector2i] = []

func _init() -> void:
	super._init(&"mass_placement")

func start(context) -> void:
	super.start(context)
	if context.building_system == null or context.player == null:
		context.log_status("mass placement skipped; building system unavailable")
		_finish_skip("building_system_unavailable")
		return
	context.collect_validation_scrap(256)
	var origin: Vector2i = context.building_system.world_to_grid(context.player.global_position) + Vector2i(12, 8)
	_placement_tiles.clear()
	for row: int in range(GRID_ROWS):
		for column: int in range(GRID_COLUMNS):
			_placement_tiles.append(origin + Vector2i(column, row))
	_stage = 0
	_set_result_state("running", {
		"origin": origin,
		"target_count": _placement_tiles.size(),
	})
	context.log_status("mass placement prepared at %s target_count=%d" % [origin, _placement_tiles.size()])

func update(context, _delta: float) -> void:
	if _process_wait_if_needed(context):
		return
	match _stage:
		0:
			for tile: Vector2i in _placement_tiles:
				if not context.place_validation_building("wall", tile):
					_finish_failed("failed to place validation wall during mass placement")
					return
			context.log_status("mass placement placed %d validation walls" % [_placement_tiles.size()])
			_begin_wait()
		1:
			for tile: Vector2i in _placement_tiles:
				if not context.building_system.has_building_at(tile):
					_finish_failed("mass placement verification did not find all placed walls")
					return
			for tile: Vector2i in _placement_tiles:
				if not context.remove_validation_building(tile):
					_finish_failed("failed to remove validation wall during mass placement cleanup")
					return
			context.log_status("mass placement removed %d validation walls" % [_placement_tiles.size()])
			_begin_wait()
		2:
			for tile: Vector2i in _placement_tiles:
				if context.building_system.has_building_at(tile):
					_finish_failed("mass placement cleanup left a validation wall behind")
					return
			_finish_pass({
				"placed_count": _placement_tiles.size(),
				"removed_count": _placement_tiles.size(),
			})
		_:
			_finish_failed("mass placement reached an invalid stage")

func _process_wait_if_needed(context) -> bool:
	if _wait_timeout_frames_remaining < 0:
		return false
	if context.building_system != null and context.building_system.has_pending_room_recompute():
		_wait_timeout_frames_remaining -= 1
		_wait_frames_remaining = WAIT_SETTLE_FRAMES
		if _wait_timeout_frames_remaining <= 0:
			_finish_failed("mass placement room recompute did not settle within timeout")
		return true
	if _wait_frames_remaining > 0:
		_wait_frames_remaining -= 1
		return true
	_wait_timeout_frames_remaining = -1
	_stage += 1
	return true

func _begin_wait() -> void:
	_wait_frames_remaining = WAIT_SETTLE_FRAMES
	_wait_timeout_frames_remaining = WAIT_TIMEOUT_FRAMES
