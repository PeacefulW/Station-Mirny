class_name TravelStateResolver
extends RefCounted

const MODE_ON_FOOT: StringName = &"on_foot"
const MODE_VEHICLE: StringName = &"vehicle"
const MODE_TRAIN: StringName = &"train"
const SPEED_IDLE: StringName = &"idle"
const SPEED_WALK: StringName = &"walk"
const SPEED_SPRINT: StringName = &"sprint"

const WALK_HORIZON_MS: int = 450
const SPRINT_HORIZON_MS: int = 850
const VEHICLE_HORIZON_MS: int = 1200
const TRAIN_HORIZON_MS: int = 1800

var _owner: Node = null

func setup(owner: Node) -> void:
	_owner = owner

func resolve(player: Node2D, previous_chunk_motion: Vector2i, chunk_size_px: float) -> Dictionary:
	var velocity: Vector2 = _resolve_player_velocity(player)
	var speed_px_per_sec: float = velocity.length()
	var base_speed_px_per_sec: float = _resolve_base_foot_speed(player)
	var speed_class: StringName = _resolve_foot_speed_class(speed_px_per_sec, base_speed_px_per_sec)
	var planning_speed_class: StringName = SPEED_WALK if speed_class == SPEED_IDLE else speed_class
	var motion_step: Vector2i = _resolve_motion_step(velocity, previous_chunk_motion)
	var max_forward_chunks: int = _resolve_forward_chunks(planning_speed_class)
	var max_lateral_chunks: int = 1
	return {
		"travel_mode": MODE_ON_FOOT,
		"speed_class": speed_class,
		"planning_speed_class": planning_speed_class,
		"prediction_horizon_ms": _resolve_prediction_horizon(planning_speed_class),
		"max_forward_chunks": max_forward_chunks,
		"max_lateral_chunks": max_lateral_chunks,
		"braking_window_chunks": 1,
		"motion_step": motion_step,
		"speed_px_per_sec": speed_px_per_sec,
		"base_speed_px_per_sec": base_speed_px_per_sec,
		"chunk_size_px": chunk_size_px,
		"vehicle_scaffold_horizon_ms": VEHICLE_HORIZON_MS,
		"train_scaffold_horizon_ms": TRAIN_HORIZON_MS,
	}

func _resolve_player_velocity(player: Node2D) -> Vector2:
	if player == null:
		return Vector2.ZERO
	if player is CharacterBody2D:
		return (player as CharacterBody2D).velocity
	var velocity_value: Variant = player.get("velocity")
	if typeof(velocity_value) == TYPE_VECTOR2:
		return velocity_value as Vector2
	return Vector2.ZERO

func _resolve_base_foot_speed(player: Node2D) -> float:
	if player == null:
		return 0.0
	var balance_value: Variant = player.get("balance")
	if balance_value == null or not (balance_value is Resource):
		return 0.0
	var move_speed_value: Variant = (balance_value as Resource).get("move_speed")
	if typeof(move_speed_value) == TYPE_FLOAT or typeof(move_speed_value) == TYPE_INT:
		return float(move_speed_value)
	return 0.0

func _resolve_foot_speed_class(speed_px_per_sec: float, base_speed_px_per_sec: float) -> StringName:
	if speed_px_per_sec <= 1.0:
		return SPEED_IDLE
	if base_speed_px_per_sec > 0.0 and speed_px_per_sec >= base_speed_px_per_sec * 1.15:
		return SPEED_SPRINT
	return SPEED_WALK

func _resolve_forward_chunks(planning_speed_class: StringName) -> int:
	match planning_speed_class:
		SPEED_SPRINT:
			return 2
		_:
			return 1

func _resolve_prediction_horizon(planning_speed_class: StringName) -> int:
	match planning_speed_class:
		SPEED_SPRINT:
			return SPRINT_HORIZON_MS
		_:
			return WALK_HORIZON_MS

func _resolve_motion_step(velocity: Vector2, previous_chunk_motion: Vector2i) -> Vector2i:
	if velocity.length_squared() > 0.01:
		return Vector2i(_sign_to_int(velocity.x), _sign_to_int(velocity.y))
	if previous_chunk_motion != Vector2i.ZERO:
		return Vector2i(signi(previous_chunk_motion.x), signi(previous_chunk_motion.y))
	return Vector2i.ZERO

func _sign_to_int(value: float) -> int:
	if value > 0.01:
		return 1
	if value < -0.01:
		return -1
	return 0
