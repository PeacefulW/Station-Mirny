class_name MiningValidationScenario
extends "res://core/debug/scenarios/validation_scenario.gd"

const MINING_SETTLE_FRAMES: int = 20
const INVALID_TILE: Vector2i = Vector2i(999999, 999999)

var _require_deeper_tile: bool = false
var _validate_save_payload: bool = true
var _verify_exit_zone_reset: bool = true
var _mining_validation_stage: int = -1
var _mining_wait_frames_remaining: int = 0
var _mining_case: Dictionary = {}
var _mining_zone_tile_count_before_extension: int = 0
var _mining_save_snapshot: Dictionary = {}

func _init() -> void:
	super._init(&"mining")

func configure(
	scenario_name: StringName,
	require_deeper_tile: bool,
	validate_save_payload: bool,
	verify_exit_zone_reset: bool
) -> MiningValidationScenario:
	_scenario_name = scenario_name
	_result["name"] = String(_scenario_name)
	_require_deeper_tile = require_deeper_tile
	_validate_save_payload = validate_save_payload
	_verify_exit_zone_reset = verify_exit_zone_reset
	return self

func start(context) -> void:
	super.start(context)
	_mining_case = context.acquire_mining_validation_case(_require_deeper_tile)
	if _mining_case.is_empty():
		var reason: String = "no_deeper_case" if _require_deeper_tile else "no_suitable_case"
		context.log_status("%s skipped; no suitable mining case found in loaded chunks" % [String(_scenario_name)])
		_finish_skip(reason)
		return
	_mining_validation_stage = 0
	_set_result_state("running", {"entry_tile": _mining_case.get("entry_tile", INVALID_TILE)})
	context.log_status("%s prepared at %s" % [
		String(_scenario_name),
		_mining_case.get("entry_tile", INVALID_TILE),
	])

func update(context, _delta: float) -> void:
	if _mining_wait_frames_remaining > 0:
		_mining_wait_frames_remaining -= 1
		return
	match _mining_validation_stage:
		0:
			if not context.mine_tile(_mining_case.get("entry_tile", INVALID_TILE)):
				_finish_failed("failed to mine entry tile")
				return
			context.log_status("%s mined entry tile %s" % [String(_scenario_name), _mining_case["entry_tile"]])
			_mining_validation_stage = 1
			_mining_wait_frames_remaining = MINING_SETTLE_FRAMES
		1:
			if context.mountain_roof_system == null or not context.mountain_roof_system.has_active_local_zone():
				_finish_failed("local reveal zone did not activate after mining first entrance from exterior")
				return
			var first_entrance_zone_count: int = context.mountain_roof_system.get_active_local_zone_tile_count()
			if first_entrance_zone_count <= 0:
				_finish_failed("active local zone tile count is zero after mining first entrance from exterior")
				return
			context.log_status("%s first entrance reveal activated; zone_tiles=%d" % [
				String(_scenario_name),
				first_entrance_zone_count,
			])
			if not context.mine_tile(_mining_case.get("interior_tile", INVALID_TILE)):
				_finish_failed("failed to mine interior tile")
				return
			context.log_status("%s mined interior tile %s" % [String(_scenario_name), _mining_case["interior_tile"]])
			if context.player != null:
				context.player.global_position = context.tile_to_world_center(_mining_case["interior_tile"])
			_mining_validation_stage = 2
			_mining_wait_frames_remaining = MINING_SETTLE_FRAMES
		2:
			if context.mountain_roof_system == null or not context.mountain_roof_system.has_active_local_zone():
				_finish_failed("local reveal zone did not activate after entering mined pocket")
				return
			_mining_zone_tile_count_before_extension = context.mountain_roof_system.get_active_local_zone_tile_count()
			if _mining_zone_tile_count_before_extension <= 0:
				_finish_failed("active local zone tile count is zero after entering mined pocket")
				return
			context.log_status("%s entered mined pocket; zone_tiles=%d" % [
				String(_scenario_name),
				_mining_zone_tile_count_before_extension,
			])
			var deeper_tile: Vector2i = _mining_case.get("deeper_tile", INVALID_TILE)
			if deeper_tile == INVALID_TILE:
				if _require_deeper_tile:
					_finish_failed("deep mine scenario requires a deeper tile but none was found")
					return
				context.log_status("%s has no deeper tile; skipping extension step" % [String(_scenario_name)])
				_mining_validation_stage = 4 if (_validate_save_payload or _verify_exit_zone_reset) else 6
				return
			if not context.mine_tile(deeper_tile):
				_finish_failed("failed to mine deeper tile for local-zone extension")
				return
			context.log_status("%s mined deeper tile %s" % [String(_scenario_name), deeper_tile])
			_mining_validation_stage = 3
			_mining_wait_frames_remaining = MINING_SETTLE_FRAMES
		3:
			var extended_count: int = context.mountain_roof_system.get_active_local_zone_tile_count()
			if extended_count <= _mining_zone_tile_count_before_extension:
				_finish_failed("local reveal zone did not expand after deeper mining")
				return
			context.log_status("%s deep mining expanded zone to %d tiles" % [
				String(_scenario_name),
				extended_count,
			])
			_mining_validation_stage = 4 if (_validate_save_payload or _verify_exit_zone_reset) else 6
		4:
			if _validate_save_payload:
				_mining_save_snapshot = context.chunk_manager.get_save_data().duplicate(true)
				if not context.validate_chunk_save_payload(_mining_save_snapshot):
					_finish_failed("chunk save payload leaked local presentation state")
					return
			if _verify_exit_zone_reset and context.player != null:
				context.player.global_position = context.tile_to_world_center(_mining_case["exterior_tile"])
				context.log_status("%s moved player back to exterior tile %s" % [
					String(_scenario_name),
					_mining_case["exterior_tile"],
				])
				_mining_validation_stage = 5
				_mining_wait_frames_remaining = MINING_SETTLE_FRAMES
				return
			_mining_validation_stage = 6
		5:
			if context.mountain_roof_system.has_active_local_zone():
				_finish_failed("local reveal zone remained active after returning to exterior")
				return
			var post_exit_save: Dictionary = context.chunk_manager.get_save_data().duplicate(true)
			if _validate_save_payload and post_exit_save != _mining_save_snapshot:
				_finish_failed("chunk save payload changed on reveal-only movement without new mining")
				return
			var collected_chunk_save: Dictionary = SaveCollectors.collect_chunk_data(context.game_world.get_tree()).duplicate(true)
			if _validate_save_payload and collected_chunk_save != _mining_save_snapshot:
				_finish_failed("SaveCollectors chunk payload diverged from ChunkManager save snapshot")
				return
			context.log_status("%s mining + persistence validation complete" % [String(_scenario_name)])
			_mining_validation_stage = 6
		6:
			var extra: Dictionary = {}
			if _require_deeper_tile:
				extra["deep_mine"] = true
			_finish_pass(extra)
		_:
			_finish_failed("mining validation reached an invalid stage")
