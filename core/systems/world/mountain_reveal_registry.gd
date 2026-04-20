class_name MountainRevealRegistry
extends Node

const RuntimeWorkTypes = preload("res://core/runtime/runtime_work_types.gd")

signal mountain_revealed(mountain_id: int)
signal mountain_concealed(mountain_id: int)
signal alpha_changed(mountain_id: int, alpha: float)

const FADE_SECONDS: float = 0.30
const EXIT_DEBOUNCE: float = 0.5
const _ALPHA_EPSILON: float = 0.001

var _alpha_by_mountain: Dictionary = {}
var _target_by_mountain: Dictionary = {}
var _conceal_delay_by_mountain: Dictionary = {}
var _job_id: StringName = &""
var _last_tick_usec: int = 0

func _ready() -> void:
	name = "MountainRevealRegistry"
	if not mountain_revealed.is_connected(_on_mountain_revealed):
		mountain_revealed.connect(_on_mountain_revealed)
	if not mountain_concealed.is_connected(_on_mountain_concealed):
		mountain_concealed.connect(_on_mountain_concealed)
	_job_id = FrameBudgetDispatcher.register_job(
		RuntimeWorkTypes.CATEGORY_VISUAL,
		0.2,
		_tick,
		&"mountain.reveal_tween",
		RuntimeWorkTypes.CadenceKind.PRESENTATION,
		RuntimeWorkTypes.ThreadingRole.MAIN_THREAD_ONLY,
		false,
		"Mountain reveal tween"
	)
	_last_tick_usec = Time.get_ticks_usec()

func _exit_tree() -> void:
	if _job_id and FrameBudgetDispatcher:
		FrameBudgetDispatcher.unregister_job(_job_id)

func request_reveal(mountain_id: int) -> void:
	if mountain_id <= 0:
		return
	var previous_target: float = _get_effective_target(mountain_id)
	_conceal_delay_by_mountain.erase(mountain_id)
	if not _alpha_by_mountain.has(mountain_id):
		_alpha_by_mountain[mountain_id] = 1.0
	_target_by_mountain[mountain_id] = 0.0
	if not is_equal_approx(previous_target, 0.0):
		mountain_revealed.emit(mountain_id)

func request_conceal(mountain_id: int) -> void:
	if mountain_id <= 0:
		return
	if is_equal_approx(_get_effective_target(mountain_id), 1.0) and not _alpha_by_mountain.has(mountain_id):
		return
	if not _alpha_by_mountain.has(mountain_id):
		_alpha_by_mountain[mountain_id] = _get_effective_target(mountain_id)
	_conceal_delay_by_mountain[mountain_id] = EXIT_DEBOUNCE

func get_alpha(mountain_id: int) -> float:
	if mountain_id <= 0:
		return 1.0
	return clampf(float(_alpha_by_mountain.get(mountain_id, 1.0)), 0.0, 1.0)

func get_debug_snapshot(mountain_id: int) -> Dictionary:
	return {
		"mountain_id": mountain_id,
		"alpha": get_alpha(mountain_id),
		"target_alpha": _get_effective_target(mountain_id),
		"debounce_seconds": float(_conceal_delay_by_mountain.get(mountain_id, 0.0)),
		"has_alpha": _alpha_by_mountain.has(mountain_id),
		"has_target": _target_by_mountain.has(mountain_id),
		"has_conceal_delay": _conceal_delay_by_mountain.has(mountain_id),
	}

func reset_state() -> void:
	_alpha_by_mountain = {}
	_target_by_mountain = {}
	_conceal_delay_by_mountain = {}
	_last_tick_usec = Time.get_ticks_usec()

func _tick() -> bool:
	var has_pending_targets: bool = not _target_by_mountain.is_empty()
	var has_pending_debounce: bool = not _conceal_delay_by_mountain.is_empty()
	if not has_pending_targets and not has_pending_debounce:
		_last_tick_usec = Time.get_ticks_usec()
		return false
	var now_usec: int = Time.get_ticks_usec()
	var delta: float = 0.0
	if _last_tick_usec > 0:
		delta = float(now_usec - _last_tick_usec) / 1000000.0
	_last_tick_usec = now_usec
	_advance_conceal_debounce(delta)
	var has_active_fade: bool = _advance_alpha(delta)
	return has_active_fade or not _conceal_delay_by_mountain.is_empty()

func _advance_conceal_debounce(delta: float) -> void:
	var mountain_ids: Array[int] = []
	for mountain_id_variant: Variant in _conceal_delay_by_mountain.keys():
		mountain_ids.append(int(mountain_id_variant))
	for mountain_id: int in mountain_ids:
		var remaining: float = maxf(float(_conceal_delay_by_mountain.get(mountain_id, 0.0)) - delta, 0.0)
		if remaining > 0.0:
			_conceal_delay_by_mountain[mountain_id] = remaining
			continue
		_conceal_delay_by_mountain.erase(mountain_id)
		if not is_equal_approx(_get_effective_target(mountain_id), 1.0):
			_target_by_mountain[mountain_id] = 1.0
			mountain_concealed.emit(mountain_id)

func _advance_alpha(delta: float) -> bool:
	var has_active_fade: bool = false
	var step: float = 1.0 if FADE_SECONDS <= 0.0 else delta / FADE_SECONDS
	var mountain_ids: Array[int] = []
	for mountain_id_variant: Variant in _target_by_mountain.keys():
		mountain_ids.append(int(mountain_id_variant))
	for mountain_id: int in mountain_ids:
		var current_alpha: float = get_alpha(mountain_id)
		var target_alpha: float = clampf(float(_target_by_mountain.get(mountain_id, current_alpha)), 0.0, 1.0)
		var resolved_alpha: float = move_toward(current_alpha, target_alpha, step)
		if absf(target_alpha - current_alpha) <= _ALPHA_EPSILON:
			resolved_alpha = target_alpha
		_alpha_by_mountain[mountain_id] = resolved_alpha
		var did_emit_alpha_change: bool = false
		if absf(resolved_alpha - current_alpha) > _ALPHA_EPSILON:
			alpha_changed.emit(mountain_id, resolved_alpha)
			did_emit_alpha_change = true
		var reached_target: bool = absf(float(_alpha_by_mountain.get(mountain_id, resolved_alpha)) - target_alpha) <= _ALPHA_EPSILON
		if reached_target:
			if not did_emit_alpha_change and not is_equal_approx(target_alpha, current_alpha):
				alpha_changed.emit(mountain_id, target_alpha)
			if is_equal_approx(target_alpha, 0.0):
				_alpha_by_mountain[mountain_id] = 0.0
			else:
				_alpha_by_mountain.erase(mountain_id)
			_target_by_mountain.erase(mountain_id)
			continue
		has_active_fade = true
	return has_active_fade

func _get_effective_target(mountain_id: int) -> float:
	if _conceal_delay_by_mountain.has(mountain_id):
		return 0.0
	if _target_by_mountain.has(mountain_id):
		return clampf(float(_target_by_mountain[mountain_id]), 0.0, 1.0)
	return get_alpha(mountain_id)

func _on_mountain_revealed(mountain_id: int) -> void:
	EventBus.mountain_revealed.emit(mountain_id)

func _on_mountain_concealed(mountain_id: int) -> void:
	EventBus.mountain_concealed.emit(mountain_id)
