class_name DaylightSystem
extends CanvasModulate
## Система освещения дня и ночи. Подписывается на TimeManager
## и плавно меняет цвет CanvasModulate.
## Днём — полная яркость, ночью — тёмно-синий мрак.

# --- Константы ---
## Цвета фаз дня. Тонирование — presentation response (ADR-0007 layer 4):
## HUD живёт в CanvasLayer и не тонируется; подземный свет — геймплейная
## система (ADR-0005), поэтому underground остаётся нейтральным.
const COLOR_NIGHT := Color(0.32, 0.38, 0.56)
const COLOR_DAWN := Color(0.86, 0.74, 0.78)
const COLOR_DAY := Color(1.0, 1.0, 1.0)
const COLOR_DUSK := Color(1.0, 0.80, 0.58)
const COLOR_UNDERGROUND := Color(1.0, 1.0, 1.0)

# --- Приватные ---
var _target_color: Color = COLOR_DAY
## Скорость перехода между цветами (за секунду).
var _transition_speed: float = 1.0
var _current_z: int = 0


func _ready() -> void:
	EventBus.time_of_day_changed.connect(_on_time_of_day_changed)
	EventBus.time_tick.connect(_on_time_tick)
	EventBus.z_level_changed.connect(_on_z_level_changed)
	_current_z = _resolve_current_z()
	_sync_from_current_context(true)


func _process(delta: float) -> void:
	# Плавный переход к целевому цвету
	color = color.lerp(_target_color, _transition_speed * delta)

# --- Приватные методы ---


func _on_time_of_day_changed(new_phase: int, _old_phase: int) -> void:
	if not _is_surface_context():
		return
	match new_phase:
		TimeManagerSingleton.TimeOfDay.DAWN:
			_target_color = COLOR_DAWN
		TimeManagerSingleton.TimeOfDay.DAY:
			_target_color = COLOR_DAY
		TimeManagerSingleton.TimeOfDay.DUSK:
			_target_color = COLOR_DUSK
		TimeManagerSingleton.TimeOfDay.NIGHT:
			_target_color = COLOR_NIGHT


func _on_time_tick(current_hour: float, _day_progress: float) -> void:
	if not _is_surface_context():
		return
	if not TimeManager or not TimeManager.balance:
		return
	_target_color = _resolve_surface_color_for_hour(current_hour)


func _on_z_level_changed(new_z: int, _old_z: int) -> void:
	set_active_z_level(new_z)


func set_active_z_level(new_z: int) -> void:
	if new_z == _current_z:
		return
	_current_z = new_z
	_sync_from_current_context(true)


func _sync_from_current_context(force_immediate: bool) -> void:
	_target_color = _resolve_context_color()
	if force_immediate:
		color = _target_color


func _resolve_context_color() -> Color:
	if not _is_surface_context():
		return COLOR_UNDERGROUND
	if not TimeManager or not TimeManager.balance:
		return COLOR_DAY
	return _resolve_surface_color_for_hour(TimeManager.current_hour)


func _resolve_surface_color_for_hour(current_hour: float) -> Color:
	var balance: TimeBalance = TimeManager.balance
	if not balance:
		return COLOR_DAY
	if current_hour >= float(balance.dawn_hour) and current_hour < float(balance.day_hour):
		var dawn_progress: float = (current_hour - float(balance.dawn_hour)) / float(balance.day_hour - balance.dawn_hour)
		return _blend_phase_color(COLOR_NIGHT, COLOR_DAWN, COLOR_DAY, dawn_progress)
	if current_hour >= float(balance.dusk_hour) and current_hour < float(balance.night_hour):
		var dusk_progress: float = (current_hour - float(balance.dusk_hour)) / float(balance.night_hour - balance.dusk_hour)
		return _blend_phase_color(COLOR_DAY, COLOR_DUSK, COLOR_NIGHT, dusk_progress)
	if current_hour >= float(balance.night_hour) or current_hour < float(balance.dawn_hour):
		return COLOR_NIGHT
	return COLOR_DAY


## Переходная фаза проходит через свой пиковый цвет (янтарь заката, розовый
## рассвета), а не лерпит день<->ночь напрямую мимо него.
func _blend_phase_color(from_color: Color, peak_color: Color, to_color: Color, progress: float) -> Color:
	if progress < 0.5:
		return from_color.lerp(peak_color, progress * 2.0)
	return peak_color.lerp(to_color, (progress - 0.5) * 2.0)


func _is_surface_context() -> bool:
	return _current_z == 0


func _resolve_current_z() -> int:
	var z_managers: Array[Node] = get_tree().get_nodes_in_group("z_level_manager")
	if z_managers.is_empty():
		return 0
	var z_manager: Node = z_managers[0]
	if z_manager.has_method("get_current_z"):
		return int(z_manager.get_current_z())
	return 0
