class_name DaylightSystem
extends CanvasModulate

## Система освещения дня и ночи. Подписывается на TimeManager
## и плавно меняет цвет CanvasModulate.
## Днём — полная яркость, ночью — тёмно-синий мрак.

# --- Константы ---
## Цвета для каждой фазы дня (мягкие, атмосферные).
const COLOR_NIGHT := Color(1.0, 1.0, 1.0)
const COLOR_DAWN := Color(1.0, 1.0, 1.0)
const COLOR_DAY := Color(1.0, 1.0, 1.0)
const COLOR_DUSK := Color(1.0, 1.0, 1.0)
const COLOR_UNDERGROUND := Color(1.0, 1.0, 1.0)

# --- Приватные ---
var _target_color: Color = COLOR_DAY
## Скорость перехода между цветами (за секунду).
var _transition_speed: float = 0.4
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
	# Плавное подмешивание внутри фазы для естественных переходов.
	# Например: рассвет начинается тёмным и постепенно светлеет.
	if not TimeManager:
		return
	var balance: TimeBalance = TimeManager.balance
	if not balance:
		return
	var hour: int = floori(current_hour)

	# Внутри рассвета: плавно от ночного к рассветному
	if hour >= balance.dawn_hour and hour < balance.day_hour:
		var progress: float = (current_hour - float(balance.dawn_hour)) / float(balance.day_hour - balance.dawn_hour)
		_target_color = COLOR_NIGHT.lerp(COLOR_DAY, progress)
	# Внутри заката: плавно от дневного к закатному и к ночному
	elif hour >= balance.dusk_hour and hour < balance.night_hour:
		var progress: float = (current_hour - float(balance.dusk_hour)) / float(balance.night_hour - balance.dusk_hour)
		_target_color = COLOR_DAY.lerp(COLOR_NIGHT, progress)

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
		return COLOR_NIGHT.lerp(COLOR_DAY, dawn_progress)
	if current_hour >= float(balance.dusk_hour) and current_hour < float(balance.night_hour):
		var dusk_progress: float = (current_hour - float(balance.dusk_hour)) / float(balance.night_hour - balance.dusk_hour)
		return COLOR_DAY.lerp(COLOR_NIGHT, dusk_progress)
	if current_hour >= float(balance.night_hour) or current_hour < float(balance.dawn_hour):
		return COLOR_NIGHT
	return COLOR_DAY

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
